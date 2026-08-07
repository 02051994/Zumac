begin;

-- El proyecto tiene un event trigger heredado que inspecciona todo DDL y
-- completa MATRIZ_CAMPOS_FORMATO_APPGT. Estas tablas son infraestructura, no
-- formatos capturables. Suspenderlo durante esta transacción evita que el
-- propio trigger vuelva a reaccionar a sus operaciones y agote la pila.
select set_config('appgt.skip_auto_fields', 'on', true);

-- Corrige una condición heredada del seguimiento incremental: si la tabla de
-- cambios llegó a recibir su propio trigger, cada escritura intentaba registrar
-- otra escritura de forma infinita. La protección en la función evita que el
-- problema reaparezca incluso si alguien instala manualmente ese trigger.
create or replace function public.appgt_registrar_tabla_modificada()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_table_name = 'APPGT_TABLAS_CAMBIADAS' then
    return coalesce(new, old);
  end if;

  insert into public."APPGT_TABLAS_CAMBIADAS" (
    tabla_nombre,
    ultimo_cambio,
    ultima_operacion,
    cantidad_cambios,
    origen,
    updated_at
  ) values (
    tg_table_name,
    now(),
    tg_op,
    1,
    'trigger',
    now()
  )
  on conflict (tabla_nombre)
  do update set
    ultimo_cambio = excluded.ultimo_cambio,
    ultima_operacion = excluded.ultima_operacion,
    cantidad_cambios = public."APPGT_TABLAS_CAMBIADAS".cantidad_cambios + 1,
    updated_at = now();

  return coalesce(new, old);
end
$$;

-- Elimina cualquier trigger autorreferente ya creado por una instalación
-- anterior. Se identifica por la función, no por un nombre supuesto.
do $$
declare v_trigger text;
begin
  for v_trigger in
    select t.tgname
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace n on n.oid = p.pronamespace
    where t.tgrelid = 'public."APPGT_TABLAS_CAMBIADAS"'::regclass
      and not t.tgisinternal
      and n.nspname = 'public'
      and p.proname = 'appgt_registrar_tabla_modificada'
  loop
    execute format(
      'drop trigger if exists %I on public."APPGT_TABLAS_CAMBIADAS"',
      v_trigger
    );
  end loop;
end
$$;

-- =============================================================================
-- Zumac Alerts + Actions
-- =============================================================================
-- Las reglas se almacenan como datos por empresa. El motor nunca contiene
-- nombres de formatos o campos de negocio codificados; los descubre desde las
-- matrices de configuración y valida que la tabla física siga existiendo.

alter table public."EMPRESAS_APPGT"
  add column if not exists habilitar_zumac_alerts boolean not null default false,
  add column if not exists habilitar_zumac_actions boolean not null default false;

-- Conserva el comportamiento de las empresas existentes. Las empresas nuevas
-- se habilitan explícitamente desde administración comercial.
update public."EMPRESAS_APPGT"
set habilitar_zumac_alerts = true,
    habilitar_zumac_actions = true,
    updated_at = now()
where activo;

create table if not exists public."ZUMAC_ALERTAS_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  nombre text not null,
  descripcion text,
  tipo_disparador text not null default 'PROGRAMADA'
    check (tipo_disparador in ('EVENTO', 'PROGRAMADA', 'AUSENCIA', 'MANUAL')),
  tabla_origen text not null,
  expresion_regla jsonb not null default '{"logic":"AND","conditions":[]}'::jsonb,
  plantilla_titulo text not null default 'Alerta de Zumac',
  plantilla_mensaje text not null default 'Se detectó una condición que requiere revisión.',
  severidad text not null default 'MEDIA'
    check (severidad in ('INFORMATIVA', 'BAJA', 'MEDIA', 'ALTA', 'CRITICA')),
  frecuencia_minutos integer not null default 15 check (frecuencia_minutos between 1 and 10080),
  ventana_ausencia_minutos integer check (ventana_ausencia_minutos is null or ventana_ausencia_minutos > 0),
  cooldown_minutos integer not null default 60 check (cooldown_minutos >= 0),
  zona_horaria text not null default 'America/Lima',
  campos_agrupacion jsonb not null default '[]'::jsonb,
  accion_automatica jsonb not null default '{}'::jsonb,
  cerrar_automaticamente boolean not null default false,
  activa boolean not null default true,
  proxima_ejecucion timestamptz not null default now(),
  ultima_ejecucion timestamptz,
  creada_por uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public."ZUMAC_ALERTA_DESTINATARIOS_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  alerta_id uuid not null references public."ZUMAC_ALERTAS_APPGT"(id) on delete cascade,
  tipo_destinatario text not null
    check (tipo_destinatario in ('USUARIO', 'ROL', 'CREADOR', 'TODOS')),
  user_id uuid references auth.users(id) on delete cascade,
  rol text check (rol is null or rol in ('ADMIN', 'GESTOR', 'COLABORADOR', 'VISUALIZADOR')),
  canal text not null default 'APP' check (canal in ('APP', 'PUSH', 'EMAIL')),
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  check (
    (tipo_destinatario = 'USUARIO' and user_id is not null and rol is null)
    or (tipo_destinatario = 'ROL' and rol is not null and user_id is null)
    or (tipo_destinatario in ('CREADOR', 'TODOS') and user_id is null and rol is null)
  )
);

create table if not exists public."ZUMAC_ALERTA_EVENTOS_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  alerta_id uuid not null references public."ZUMAC_ALERTAS_APPGT"(id) on delete cascade,
  tabla_origen text not null,
  registro_origen_id text,
  clave_dedupe text not null,
  titulo text not null,
  mensaje text not null,
  severidad text not null
    check (severidad in ('INFORMATIVA', 'BAJA', 'MEDIA', 'ALTA', 'CRITICA')),
  estado text not null default 'DETECTADA'
    check (estado in ('DETECTADA', 'NOTIFICADA', 'LEIDA', 'ASIGNADA', 'ATENDIDA', 'CERRADA', 'DESCARTADA')),
  datos_origen jsonb not null default '{}'::jsonb,
  contexto jsonb not null default '{}'::jsonb,
  ocurrencias integer not null default 1,
  responsable_id uuid references auth.users(id) on delete set null,
  detectada_at timestamptz not null default now(),
  ultima_ocurrencia_at timestamptz not null default now(),
  notificada_at timestamptz,
  leida_at timestamptz,
  atendida_at timestamptz,
  cerrada_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists uq_zumac_alerta_evento_abierto
  on public."ZUMAC_ALERTA_EVENTOS_APPGT" (alerta_id, clave_dedupe)
  where estado not in ('CERRADA', 'DESCARTADA');

create table if not exists public."ZUMAC_ACCIONES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  alerta_evento_id uuid references public."ZUMAC_ALERTA_EVENTOS_APPGT"(id) on delete set null,
  alerta_id uuid references public."ZUMAC_ALERTAS_APPGT"(id) on delete set null,
  tipo text not null default 'TAREA'
    check (tipo in ('TAREA', 'SOLICITUD_APROBACION', 'NOTIFICACION', 'CAMBIO_ESTADO')),
  titulo text not null,
  descripcion text,
  prioridad text not null default 'MEDIA'
    check (prioridad in ('BAJA', 'MEDIA', 'ALTA', 'CRITICA')),
  estado text not null default 'PENDIENTE'
    check (estado in ('PENDIENTE', 'EN_PROGRESO', 'APROBADA', 'RECHAZADA', 'COMPLETADA', 'CANCELADA')),
  asignado_a uuid references auth.users(id) on delete set null,
  aprobador_id uuid references auth.users(id) on delete set null,
  fecha_limite timestamptz,
  evidencia jsonb not null default '[]'::jsonb,
  resultado jsonb not null default '{}'::jsonb,
  creada_por uuid not null references auth.users(id),
  iniciada_at timestamptz,
  completada_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public."ZUMAC_ACCION_COMENTARIOS_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  accion_id uuid not null references public."ZUMAC_ACCIONES_APPGT"(id) on delete cascade,
  comentario text not null check (btrim(comentario) <> ''),
  evidencia jsonb not null default '[]'::jsonb,
  creado_por uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public."ZUMAC_ALERTA_EJECUCIONES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  alerta_id uuid references public."ZUMAC_ALERTAS_APPGT"(id) on delete cascade,
  estado text not null check (estado in ('INICIADA', 'COMPLETADA', 'ERROR')),
  filas_revisadas integer not null default 0,
  coincidencias integer not null default 0,
  eventos_creados integer not null default 0,
  detalle text,
  iniciada_at timestamptz not null default now(),
  finalizada_at timestamptz
);

-- Registro preparado para FCM. No almacena credenciales de Firebase: solo el
-- token público del dispositivo y siempre asociado al usuario autenticado.
create table if not exists public."ZUMAC_DISPOSITIVOS_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  plataforma text not null check (plataforma in ('ANDROID', 'IOS', 'WEB', 'WINDOWS')),
  activo boolean not null default true,
  ultima_actividad_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_zumac_alertas_due
  on public."ZUMAC_ALERTAS_APPGT" (activa, proxima_ejecucion);
create index if not exists idx_zumac_eventos_empresa_estado
  on public."ZUMAC_ALERTA_EVENTOS_APPGT" (empresa_id, estado, ultima_ocurrencia_at desc);
create index if not exists idx_zumac_acciones_empresa_estado
  on public."ZUMAC_ACCIONES_APPGT" (empresa_id, estado, fecha_limite);
create index if not exists idx_zumac_comentarios_accion
  on public."ZUMAC_ACCION_COMENTARIOS_APPGT" (accion_id, created_at);

-- Mantiene updated_at sin depender de que cada cliente recuerde enviarlo.
create or replace function public.appgt_zumac_touch_updated_at()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  new.updated_at := now();
  return new;
end
$$;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'ZUMAC_ALERTAS_APPGT', 'ZUMAC_ALERTA_EVENTOS_APPGT',
    'ZUMAC_ACCIONES_APPGT', 'ZUMAC_DISPOSITIVOS_APPGT'
  ] loop
    execute format('drop trigger if exists zumac_touch_updated_at on public.%I', v_table);
    execute format(
      'create trigger zumac_touch_updated_at before update on public.%I for each row execute function public.appgt_zumac_touch_updated_at()',
      v_table
    );
  end loop;
end
$$;

-- Conversores tolerantes: una regla inválida nunca detiene el lote completo.
create or replace function public.appgt_alerta_numero_v1(p_value text)
returns numeric language plpgsql immutable set search_path = public, pg_temp as $$
begin
  return replace(nullif(btrim(p_value), ''), ',', '.')::numeric;
exception when others then return null;
end
$$;

create or replace function public.appgt_alerta_fecha_v1(p_value text)
returns timestamptz language plpgsql immutable set search_path = public, pg_temp as $$
begin
  return nullif(btrim(p_value), '')::timestamptz;
exception when others then return null;
end
$$;

create or replace function public.appgt_alerta_compara_v1(
  p_actual jsonb,
  p_operador text,
  p_esperado jsonb,
  p_tipo text default 'text'
)
returns boolean
language plpgsql immutable set search_path = public, pg_temp
as $$
declare
  v_actual text := coalesce(p_actual #>> '{}', '');
  v_esperado text := coalesce(p_esperado #>> '{}', '');
  v_a_num numeric;
  v_e_num numeric;
  v_a_fecha timestamptz;
  v_e_fecha timestamptz;
  v_segundo text;
begin
  case lower(coalesce(p_operador, 'eq'))
    when 'is_null' then return p_actual is null or p_actual = 'null'::jsonb or btrim(v_actual) = '';
    when 'is_not_null' then return not (p_actual is null or p_actual = 'null'::jsonb or btrim(v_actual) = '');
    when 'contains' then return lower(v_actual) like '%' || lower(v_esperado) || '%';
    when 'not_contains' then return lower(v_actual) not like '%' || lower(v_esperado) || '%';
    when 'in' then
      return exists (
        select 1 from jsonb_array_elements_text(coalesce(p_esperado, '[]'::jsonb)) x
        where lower(x) = lower(v_actual)
      );
    else null;
  end case;

  if lower(p_tipo) in ('number', 'numeric', 'integer', 'decimal') then
    v_a_num := public.appgt_alerta_numero_v1(v_actual);
    v_e_num := public.appgt_alerta_numero_v1(v_esperado);
    if v_a_num is null or v_e_num is null then return false; end if;
    case lower(p_operador)
      when 'eq' then return v_a_num = v_e_num;
      when 'neq' then return v_a_num <> v_e_num;
      when 'gt' then return v_a_num > v_e_num;
      when 'gte' then return v_a_num >= v_e_num;
      when 'lt' then return v_a_num < v_e_num;
      when 'lte' then return v_a_num <= v_e_num;
      when 'between' then
        v_segundo := p_esperado ->> 1;
        return v_a_num between public.appgt_alerta_numero_v1(p_esperado ->> 0)
          and public.appgt_alerta_numero_v1(v_segundo);
      else return false;
    end case;
  elsif lower(p_tipo) in ('date', 'datetime', 'timestamp') then
    v_a_fecha := public.appgt_alerta_fecha_v1(v_actual);
    v_e_fecha := public.appgt_alerta_fecha_v1(v_esperado);
    if lower(p_operador) = 'between' then
      return v_a_fecha between public.appgt_alerta_fecha_v1(p_esperado ->> 0)
        and public.appgt_alerta_fecha_v1(p_esperado ->> 1);
    end if;
    if v_a_fecha is null or v_e_fecha is null then return false; end if;
    case lower(p_operador)
      when 'eq' then return v_a_fecha = v_e_fecha;
      when 'neq' then return v_a_fecha <> v_e_fecha;
      when 'gt' then return v_a_fecha > v_e_fecha;
      when 'gte' then return v_a_fecha >= v_e_fecha;
      when 'lt' then return v_a_fecha < v_e_fecha;
      when 'lte' then return v_a_fecha <= v_e_fecha;
      else return false;
    end case;
  end if;

  case lower(p_operador)
    when 'eq' then return lower(v_actual) = lower(v_esperado);
    when 'neq' then return lower(v_actual) <> lower(v_esperado);
    when 'gt' then return lower(v_actual) > lower(v_esperado);
    when 'gte' then return lower(v_actual) >= lower(v_esperado);
    when 'lt' then return lower(v_actual) < lower(v_esperado);
    when 'lte' then return lower(v_actual) <= lower(v_esperado);
    else return false;
  end case;
end
$$;

create or replace function public.appgt_alerta_cumple_v1(
  p_fila jsonb,
  p_expresion jsonb
)
returns boolean
language plpgsql immutable set search_path = public, pg_temp
as $$
declare
  v_logica text := upper(coalesce(p_expresion ->> 'logic', 'AND'));
  v_item jsonb;
  v_result boolean;
  v_has_items boolean := false;
begin
  -- Un nodo hoja también es válido, lo que simplifica el editor móvil.
  if p_expresion ? 'field' then
    return public.appgt_alerta_compara_v1(
      p_fila -> (p_expresion ->> 'field'),
      p_expresion ->> 'operator',
      p_expresion -> 'value',
      coalesce(p_expresion ->> 'value_type', 'text')
    );
  end if;

  v_result := (v_logica = 'AND');
  for v_item in
    select value from jsonb_array_elements(coalesce(p_expresion -> 'conditions', '[]'::jsonb))
  loop
    v_has_items := true;
    if v_logica = 'OR' then
      v_result := v_result or public.appgt_alerta_cumple_v1(p_fila, v_item);
      if v_result then return true; end if;
    else
      v_result := v_result and public.appgt_alerta_cumple_v1(p_fila, v_item);
      if not v_result then return false; end if;
    end if;
  end loop;
  return v_has_items and v_result;
end
$$;

create or replace function public.appgt_alerta_campos_expresion_v1(p_expresion jsonb)
returns table(campo text)
language sql immutable set search_path = public, pg_temp
as $$
  with recursive nodes(node) as (
    select p_expresion
    union all
    select child.value
    from nodes n
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(n.node -> 'conditions') = 'array'
        then n.node -> 'conditions' else '[]'::jsonb end
    ) child
  )
  select distinct node ->> 'field'
  from nodes
  where nullif(node ->> 'field', '') is not null;
$$;

create or replace function public.appgt_tabla_alertable_v1(
  p_empresa_id uuid,
  p_tabla text
)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select
    to_regclass(format('public.%I', p_tabla)) is not null
    and exists (
      select 1 from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
      where ft.empresa_id = p_empresa_id
        and ft.tabla_destino = p_tabla
        and coalesce(ft.activo, true)
        and ft.deleted_at is null
    )
    and (
      exists (
        select 1 from information_schema.columns c
        where c.table_schema = 'public' and c.table_name = p_tabla
          and c.column_name = 'empresa_id'
      )
      or not exists (
        select 1 from public."MATRIZ_FORMATO_TABLAS_APPGT" other
        where other.tabla_destino = p_tabla
          and other.empresa_id <> p_empresa_id
          and coalesce(other.activo, true)
          and other.deleted_at is null
      )
    );
$$;

create or replace function public.appgt_validar_alerta_v1(
  p_empresa_id uuid,
  p_tabla text,
  p_expresion jsonb
)
returns void
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_campo text;
begin
  if not public.appgt_tabla_alertable_v1(p_empresa_id, p_tabla) then
    raise exception 'La tabla no está disponible para alertas de esta empresa';
  end if;
  if jsonb_array_length(coalesce(p_expresion -> 'conditions', '[]'::jsonb)) = 0
     and not (p_expresion ? 'field') then
    raise exception 'La regla necesita al menos una condición';
  end if;
  for v_campo in
    select x.campo from public.appgt_alerta_campos_expresion_v1(p_expresion) x
  loop
    if not exists (
      select 1
      from public."MATRIZ_CAMPOS_FORMATO_APPGT" c
      join information_schema.columns pc
        on pc.table_schema = 'public'
       and pc.table_name = p_tabla
       and pc.column_name = c.campo
      where c.empresa_id = p_empresa_id
        and c.tabla_destino = p_tabla
        and c.campo = v_campo
        and coalesce(c.activo, true)
        and not coalesce(c.eliminado, false)
    ) then
      raise exception 'El campo % no está disponible en %', v_campo, p_tabla;
    end if;
  end loop;
end
$$;

create or replace function public.appgt_alertas_contexto_v1()
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_empresa public."EMPRESAS_APPGT"%rowtype;
  v_rol text;
begin
  if v_empresa_id is null then raise exception 'authentication required' using errcode = '42501'; end if;
  select * into v_empresa from public."EMPRESAS_APPGT" where id = v_empresa_id and activo;
  select rol into v_rol from public."USUARIOS_EMPRESAS_APPGT"
    where empresa_id = v_empresa_id and user_id = auth.uid() and activo limit 1;

  return jsonb_build_object(
    'empresa_id', v_empresa_id,
    'alerts_habilitado', v_empresa.habilitar_zumac_alerts,
    'actions_habilitado', v_empresa.habilitar_zumac_actions,
    'puede_gestionar', v_rol in ('ADMIN', 'GESTOR'),
    'rol', v_rol,
    'resumen', jsonb_build_object(
      'reglas_activas', (select count(*) from public."ZUMAC_ALERTAS_APPGT" a where a.empresa_id = v_empresa_id and a.activa),
      'eventos_abiertos', (select count(*) from public."ZUMAC_ALERTA_EVENTOS_APPGT" e where e.empresa_id = v_empresa_id and e.estado not in ('CERRADA', 'DESCARTADA')),
      'acciones_pendientes', (select count(*) from public."ZUMAC_ACCIONES_APPGT" x where x.empresa_id = v_empresa_id and x.estado in ('PENDIENTE', 'EN_PROGRESO'))
    ),
    'fuentes', coalesce((
      select jsonb_agg(source order by source ->> 'nombre')
      from (
        select jsonb_build_object(
          'tabla', ft.tabla_destino,
          'nombre', coalesce(nullif(ft.nombre, ''), nullif(f.nombre, ''), ft.tabla_destino),
          'formato_id', ft.formato_id,
          'campos', coalesce((
            select jsonb_agg(jsonb_build_object(
              'campo', c.campo,
              'etiqueta', coalesce(nullif(c.etiqueta, ''), c.campo),
              'tipo', coalesce(nullif(c.tipo, ''), 'text')
            ) order by c.orden, c.campo)
            from public."MATRIZ_CAMPOS_FORMATO_APPGT" c
            join information_schema.columns pc
              on pc.table_schema = 'public'
             and pc.table_name = ft.tabla_destino
             and pc.column_name = c.campo
            where c.empresa_id = v_empresa_id
              and c.tabla_destino = ft.tabla_destino
              and coalesce(c.activo, true)
              and not coalesce(c.eliminado, false)
          ), '[]'::jsonb)
        ) source
        from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
        left join public."MATRIZ_FORMATOS_APPGT" f
          on f.empresa_id = ft.empresa_id and f.id = ft.formato_id
        where ft.empresa_id = v_empresa_id
          and coalesce(ft.activo, true) and ft.deleted_at is null
          and public.appgt_tabla_alertable_v1(v_empresa_id, ft.tabla_destino)
        group by ft.tabla_destino, ft.nombre, f.nombre, ft.formato_id
      ) sources
    ), '[]'::jsonb),
    'usuarios', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', ue.user_id,
        'rol', ue.rol,
        'email', u.email,
        'nombre', coalesce(
          nullif(u.raw_user_meta_data ->> 'full_name', ''),
          nullif(u.raw_user_meta_data ->> 'name', ''),
          split_part(coalesce(u.email, ue.user_id::text), '@', 1)
        )
      ) order by ue.rol, u.email)
      from public."USUARIOS_EMPRESAS_APPGT" ue
      join auth.users u on u.id = ue.user_id
      where ue.empresa_id = v_empresa_id and ue.activo
    ), '[]'::jsonb)
  );
end
$$;

create or replace function public.appgt_guardar_alerta_v1(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_id uuid;
  v_dest jsonb;
begin
  if v_empresa_id is null or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'No tienes permiso para administrar alertas' using errcode = '42501';
  end if;
  if not coalesce((select habilitar_zumac_alerts from public."EMPRESAS_APPGT" where id = v_empresa_id), false) then
    raise exception 'Alerts no está habilitado para esta empresa';
  end if;
  if nullif(btrim(p_payload ->> 'nombre'), '') is null then raise exception 'El nombre es obligatorio'; end if;
  perform public.appgt_validar_alerta_v1(v_empresa_id, p_payload ->> 'tabla_origen', p_payload -> 'expresion_regla');

  v_id := nullif(p_payload ->> 'id', '')::uuid;
  if v_id is null then
    insert into public."ZUMAC_ALERTAS_APPGT" (
      empresa_id, nombre, descripcion, tipo_disparador, tabla_origen,
      expresion_regla, plantilla_titulo, plantilla_mensaje, severidad,
      frecuencia_minutos, ventana_ausencia_minutos, cooldown_minutos,
      campos_agrupacion, accion_automatica, cerrar_automaticamente,
      activa, creada_por
    ) values (
      v_empresa_id, btrim(p_payload ->> 'nombre'), nullif(btrim(p_payload ->> 'descripcion'), ''),
      coalesce(nullif(p_payload ->> 'tipo_disparador', ''), 'PROGRAMADA'), p_payload ->> 'tabla_origen',
      p_payload -> 'expresion_regla', coalesce(nullif(p_payload ->> 'plantilla_titulo', ''), p_payload ->> 'nombre'),
      coalesce(nullif(p_payload ->> 'plantilla_mensaje', ''), 'Se detectó una condición que requiere revisión.'),
      coalesce(nullif(p_payload ->> 'severidad', ''), 'MEDIA'),
      greatest(coalesce((p_payload ->> 'frecuencia_minutos')::integer, 15), 1),
      nullif(p_payload ->> 'ventana_ausencia_minutos', '')::integer,
      greatest(coalesce((p_payload ->> 'cooldown_minutos')::integer, 60), 0),
      coalesce(p_payload -> 'campos_agrupacion', '[]'::jsonb),
      coalesce(p_payload -> 'accion_automatica', '{}'::jsonb),
      coalesce((p_payload ->> 'cerrar_automaticamente')::boolean, false),
      coalesce((p_payload ->> 'activa')::boolean, true), auth.uid()
    ) returning id into v_id;
  else
    update public."ZUMAC_ALERTAS_APPGT" set
      nombre = btrim(p_payload ->> 'nombre'),
      descripcion = nullif(btrim(p_payload ->> 'descripcion'), ''),
      tipo_disparador = coalesce(nullif(p_payload ->> 'tipo_disparador', ''), tipo_disparador),
      tabla_origen = p_payload ->> 'tabla_origen', expresion_regla = p_payload -> 'expresion_regla',
      plantilla_titulo = coalesce(nullif(p_payload ->> 'plantilla_titulo', ''), p_payload ->> 'nombre'),
      plantilla_mensaje = coalesce(nullif(p_payload ->> 'plantilla_mensaje', ''), plantilla_mensaje),
      severidad = coalesce(nullif(p_payload ->> 'severidad', ''), severidad),
      frecuencia_minutos = greatest(coalesce((p_payload ->> 'frecuencia_minutos')::integer, frecuencia_minutos), 1),
      ventana_ausencia_minutos = nullif(p_payload ->> 'ventana_ausencia_minutos', '')::integer,
      cooldown_minutos = greatest(coalesce((p_payload ->> 'cooldown_minutos')::integer, cooldown_minutos), 0),
      campos_agrupacion = coalesce(p_payload -> 'campos_agrupacion', campos_agrupacion),
      accion_automatica = coalesce(p_payload -> 'accion_automatica', accion_automatica),
      cerrar_automaticamente = coalesce((p_payload ->> 'cerrar_automaticamente')::boolean, cerrar_automaticamente),
      activa = coalesce((p_payload ->> 'activa')::boolean, activa), proxima_ejecucion = now()
    where id = v_id and empresa_id = v_empresa_id;
    if not found then raise exception 'Alerta no encontrada'; end if;
  end if;

  if p_payload ? 'destinatarios' then
    delete from public."ZUMAC_ALERTA_DESTINATARIOS_APPGT" where alerta_id = v_id and empresa_id = v_empresa_id;
    for v_dest in select value from jsonb_array_elements(coalesce(p_payload -> 'destinatarios', '[]'::jsonb))
    loop
      if v_dest ->> 'tipo_destinatario' = 'USUARIO'
         and not exists (
           select 1 from public."USUARIOS_EMPRESAS_APPGT" ue
           where ue.empresa_id = v_empresa_id
             and ue.user_id = nullif(v_dest ->> 'user_id', '')::uuid
             and ue.activo
         ) then
        raise exception 'El destinatario no pertenece a la empresa';
      end if;
      insert into public."ZUMAC_ALERTA_DESTINATARIOS_APPGT" (
        empresa_id, alerta_id, tipo_destinatario, user_id, rol, canal
      ) values (
        v_empresa_id, v_id, coalesce(v_dest ->> 'tipo_destinatario', 'TODOS'),
        nullif(v_dest ->> 'user_id', '')::uuid, nullif(v_dest ->> 'rol', ''),
        coalesce(nullif(v_dest ->> 'canal', ''), 'APP')
      );
    end loop;
  end if;
  if not exists (select 1 from public."ZUMAC_ALERTA_DESTINATARIOS_APPGT" where alerta_id = v_id) then
    insert into public."ZUMAC_ALERTA_DESTINATARIOS_APPGT" (empresa_id, alerta_id, tipo_destinatario)
    values (v_empresa_id, v_id, 'TODOS');
  end if;
  return jsonb_build_object('id', v_id, 'guardada', true);
end
$$;

create or replace function public.appgt_alerta_filas_v1(
  p_empresa_id uuid,
  p_tabla text,
  p_limit integer default 500
)
returns setof jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_has_company boolean;
begin
  if not public.appgt_tabla_alertable_v1(p_empresa_id, p_tabla) then
    raise exception 'Tabla no disponible para esta empresa';
  end if;
  select exists(select 1 from information_schema.columns where table_schema='public' and table_name=p_tabla and column_name='empresa_id') into v_has_company;
  if v_has_company then
    return query execute format('select to_jsonb(t) from public.%I t where t.empresa_id = $1 limit $2', p_tabla)
      using p_empresa_id, least(greatest(p_limit, 1), 1000);
  else
    return query execute format('select to_jsonb(t) from public.%I t limit $1', p_tabla)
      using least(greatest(p_limit, 1), 1000);
  end if;
end
$$;

create or replace function public.appgt_probar_alerta_v1(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_row jsonb;
  v_matches integer := 0;
  v_reviewed integer := 0;
  v_samples jsonb := '[]'::jsonb;
begin
  if v_empresa_id is null or not public.appgt_puede_acceder_empresa(v_empresa_id) then raise exception 'Sin acceso' using errcode='42501'; end if;
  perform public.appgt_validar_alerta_v1(v_empresa_id, p_payload ->> 'tabla_origen', p_payload -> 'expresion_regla');
  for v_row in select * from public.appgt_alerta_filas_v1(v_empresa_id, p_payload ->> 'tabla_origen', 500)
  loop
    v_reviewed := v_reviewed + 1;
    if public.appgt_alerta_cumple_v1(v_row, p_payload -> 'expresion_regla') then
      v_matches := v_matches + 1;
      if jsonb_array_length(v_samples) < 5 then v_samples := v_samples || jsonb_build_array(v_row); end if;
    end if;
  end loop;
  return jsonb_build_object('filas_revisadas', v_reviewed, 'coincidencias', v_matches, 'muestras', v_samples);
end
$$;

create or replace function public.appgt_alerta_interpolar_v1(p_template text, p_row jsonb)
returns text language plpgsql immutable set search_path = public, pg_temp as $$
declare v_result text := p_template; v_pair record;
begin
  for v_pair in select key, value #>> '{}' as value from jsonb_each(p_row)
  loop v_result := replace(v_result, '{{' || v_pair.key || '}}', coalesce(v_pair.value, '')); end loop;
  return v_result;
end
$$;

create or replace function public.appgt_evaluar_alertas_v1(p_limit integer default 100)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_caller uuid := auth.uid();
  v_current_company uuid := public.appgt_empresa_actual_id();
  v_rule public."ZUMAC_ALERTAS_APPGT"%rowtype;
  v_row jsonb;
  v_exec_id uuid;
  v_event_id uuid;
  v_key text;
  v_group text;
  v_groups jsonb;
  v_reviewed integer;
  v_matches integer;
  v_created integer;
  v_total_rules integer := 0;
  v_total_events integer := 0;
  v_any_match boolean;
  v_inserted boolean;
begin
  -- auth.uid() nulo identifica al planificador/service_role. Un usuario normal
  -- solo puede evaluar la empresa activa y debe ser ADMIN o GESTOR.
  if v_caller is not null and (v_current_company is null or not public.appgt_puede_gestionar_configuracion(v_current_company)) then
    raise exception 'No tienes permiso para evaluar alertas' using errcode='42501';
  end if;

  for v_rule in
    select a.* from public."ZUMAC_ALERTAS_APPGT" a
    join public."EMPRESAS_APPGT" e on e.id = a.empresa_id and e.activo and e.habilitar_zumac_alerts
    where a.activa and a.proxima_ejecucion <= now()
      and (v_caller is null or a.empresa_id = v_current_company)
    order by a.proxima_ejecucion
    limit least(greatest(p_limit, 1), 500)
    for update of a skip locked
  loop
    v_total_rules := v_total_rules + 1; v_reviewed := 0; v_matches := 0; v_created := 0; v_any_match := false;
    insert into public."ZUMAC_ALERTA_EJECUCIONES_APPGT" (empresa_id, alerta_id, estado)
      values (v_rule.empresa_id, v_rule.id, 'INICIADA') returning id into v_exec_id;
    begin
      for v_row in select * from public.appgt_alerta_filas_v1(v_rule.empresa_id, v_rule.tabla_origen, 500)
      loop
        v_reviewed := v_reviewed + 1;
        if public.appgt_alerta_cumple_v1(v_row, v_rule.expresion_regla) then
          v_any_match := true; v_matches := v_matches + 1;
          -- AUSENCIA crea un único evento solo cuando no hay coincidencias.
          if v_rule.tipo_disparador = 'AUSENCIA' then continue; end if;
          v_groups := coalesce(v_rule.campos_agrupacion, '[]'::jsonb); v_group := '';
          if jsonb_array_length(v_groups) > 0 then
            select string_agg(coalesce(v_row ->> value, ''), '|') into v_group from jsonb_array_elements_text(v_groups);
          end if;
          v_key := md5(coalesce(nullif(v_group, ''), coalesce(v_row ->> 'id', v_row ->> 'ID'), v_row::text));
          v_event_id := null; v_inserted := false;
          insert into public."ZUMAC_ALERTA_EVENTOS_APPGT" (
            empresa_id, alerta_id, tabla_origen, registro_origen_id, clave_dedupe,
            titulo, mensaje, severidad, datos_origen
          ) values (
            v_rule.empresa_id, v_rule.id, v_rule.tabla_origen,
            coalesce(v_row ->> 'id', v_row ->> 'ID'), v_key,
            public.appgt_alerta_interpolar_v1(v_rule.plantilla_titulo, v_row),
            public.appgt_alerta_interpolar_v1(v_rule.plantilla_mensaje, v_row),
            v_rule.severidad, v_row
          )
          on conflict (alerta_id, clave_dedupe) where estado not in ('CERRADA', 'DESCARTADA')
          do update set ocurrencias = public."ZUMAC_ALERTA_EVENTOS_APPGT".ocurrencias + 1,
            ultima_ocurrencia_at = now(), datos_origen = excluded.datos_origen,
            titulo = excluded.titulo, mensaje = excluded.mensaje
          where public."ZUMAC_ALERTA_EVENTOS_APPGT".ultima_ocurrencia_at
            <= now() - make_interval(mins => v_rule.cooldown_minutos)
          returning id, (xmax = 0) into v_event_id, v_inserted;
          if v_inserted then
            v_created := v_created + 1; v_total_events := v_total_events + 1;
            if coalesce((v_rule.accion_automatica ->> 'crear_tarea')::boolean, false)
               and not exists (select 1 from public."ZUMAC_ACCIONES_APPGT" where alerta_evento_id = v_event_id and estado not in ('COMPLETADA','CANCELADA')) then
              insert into public."ZUMAC_ACCIONES_APPGT" (
                empresa_id, alerta_evento_id, alerta_id, tipo, titulo, descripcion,
                prioridad, asignado_a, fecha_limite, creada_por
              ) values (
                v_rule.empresa_id, v_event_id, v_rule.id, 'TAREA',
                coalesce(nullif(v_rule.accion_automatica ->> 'titulo', ''), 'Atender: ' || v_rule.nombre),
                public.appgt_alerta_interpolar_v1(v_rule.plantilla_mensaje, v_row),
                case when v_rule.severidad in ('ALTA','CRITICA') then v_rule.severidad else 'MEDIA' end,
                nullif(v_rule.accion_automatica ->> 'asignado_a', '')::uuid,
                case when (v_rule.accion_automatica ->> 'plazo_horas') ~ '^[0-9]+$'
                  then now() + make_interval(hours => (v_rule.accion_automatica ->> 'plazo_horas')::integer) else null end,
                v_rule.creada_por
              );
            end if;
          end if;
        end if;
      end loop;

      if v_rule.tipo_disparador = 'AUSENCIA' and not v_any_match then
        v_key := md5('AUSENCIA|' || v_rule.tabla_origen);
        v_event_id := null; v_inserted := false;
        insert into public."ZUMAC_ALERTA_EVENTOS_APPGT" (
          empresa_id, alerta_id, tabla_origen, clave_dedupe, titulo, mensaje, severidad, contexto
        ) values (v_rule.empresa_id, v_rule.id, v_rule.tabla_origen, v_key,
          v_rule.plantilla_titulo, v_rule.plantilla_mensaje, v_rule.severidad,
          jsonb_build_object('tipo', 'AUSENCIA', 'evaluada_at', now()))
        on conflict (alerta_id, clave_dedupe) where estado not in ('CERRADA', 'DESCARTADA')
        do update set ocurrencias = public."ZUMAC_ALERTA_EVENTOS_APPGT".ocurrencias + 1, ultima_ocurrencia_at = now()
        where public."ZUMAC_ALERTA_EVENTOS_APPGT".ultima_ocurrencia_at
          <= now() - make_interval(mins => v_rule.cooldown_minutos)
        returning id, (xmax = 0) into v_event_id, v_inserted;
        if v_inserted then
          v_created := v_created + 1;
          v_total_events := v_total_events + 1;
          if coalesce((v_rule.accion_automatica ->> 'crear_tarea')::boolean, false) then
            insert into public."ZUMAC_ACCIONES_APPGT" (
              empresa_id, alerta_evento_id, alerta_id, tipo, titulo,
              descripcion, prioridad, asignado_a, fecha_limite, creada_por
            ) values (
              v_rule.empresa_id, v_event_id, v_rule.id, 'TAREA',
              coalesce(nullif(v_rule.accion_automatica ->> 'titulo', ''), 'Atender: ' || v_rule.nombre),
              v_rule.plantilla_mensaje,
              case when v_rule.severidad in ('ALTA','CRITICA') then v_rule.severidad else 'MEDIA' end,
              nullif(v_rule.accion_automatica ->> 'asignado_a', '')::uuid,
              case when (v_rule.accion_automatica ->> 'plazo_horas') ~ '^[0-9]+$'
                then now() + make_interval(hours => (v_rule.accion_automatica ->> 'plazo_horas')::integer) else null end,
              v_rule.creada_por
            );
          end if;
        end if;
      elsif v_rule.cerrar_automaticamente and not v_any_match then
        update public."ZUMAC_ALERTA_EVENTOS_APPGT" set estado='CERRADA', cerrada_at=now()
        where alerta_id=v_rule.id and estado not in ('CERRADA','DESCARTADA');
      end if;

      update public."ZUMAC_ALERTAS_APPGT" set ultima_ejecucion=now(),
        proxima_ejecucion=now()+make_interval(mins=>v_rule.frecuencia_minutos) where id=v_rule.id;
      update public."ZUMAC_ALERTA_EJECUCIONES_APPGT" set estado='COMPLETADA', filas_revisadas=v_reviewed,
        coincidencias=v_matches, eventos_creados=v_created, finalizada_at=now() where id=v_exec_id;
    exception when others then
      update public."ZUMAC_ALERTA_EJECUCIONES_APPGT" set estado='ERROR', detalle=sqlerrm, finalizada_at=now() where id=v_exec_id;
      update public."ZUMAC_ALERTAS_APPGT" set ultima_ejecucion=now(), proxima_ejecucion=now()+interval '15 minutes' where id=v_rule.id;
    end;
  end loop;
  return jsonb_build_object('reglas_evaluadas', v_total_rules, 'eventos_creados', v_total_events);
end
$$;

create or replace function public.appgt_actualizar_evento_alerta_v1(
  p_evento_id uuid,
  p_estado text default null,
  p_responsable_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_empresa_id uuid := public.appgt_empresa_actual_id(); v_row public."ZUMAC_ALERTA_EVENTOS_APPGT"%rowtype;
begin
  if v_empresa_id is null then raise exception 'Sin acceso' using errcode='42501'; end if;
  if p_estado is not null and p_estado not in ('DETECTADA','NOTIFICADA','LEIDA','ASIGNADA','ATENDIDA','CERRADA','DESCARTADA') then raise exception 'Estado inválido'; end if;
  if p_responsable_id is not null and not exists (
    select 1 from public."USUARIOS_EMPRESAS_APPGT" ue
    where ue.empresa_id=v_empresa_id and ue.user_id=p_responsable_id and ue.activo
  ) then raise exception 'El responsable no pertenece a la empresa'; end if;
  update public."ZUMAC_ALERTA_EVENTOS_APPGT" set
    estado = coalesce(p_estado, case when p_responsable_id is not null then 'ASIGNADA' else estado end),
    responsable_id = coalesce(p_responsable_id, responsable_id),
    leida_at = case when p_estado='LEIDA' then now() else leida_at end,
    atendida_at = case when p_estado='ATENDIDA' then now() else atendida_at end,
    cerrada_at = case when p_estado in ('CERRADA','DESCARTADA') then now() else cerrada_at end
  where id=p_evento_id and empresa_id=v_empresa_id returning * into v_row;
  if v_row.id is null then raise exception 'Evento no encontrado'; end if;
  return to_jsonb(v_row);
end
$$;

create or replace function public.appgt_guardar_accion_v1(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_empresa_id uuid := public.appgt_empresa_actual_id(); v_id uuid;
begin
  if v_empresa_id is null then raise exception 'Sin acceso' using errcode='42501'; end if;
  if not coalesce((select habilitar_zumac_actions from public."EMPRESAS_APPGT" where id=v_empresa_id),false) then raise exception 'Actions no está habilitado'; end if;
  if nullif(btrim(p_payload->>'titulo'),'') is null then raise exception 'El título es obligatorio'; end if;
  if nullif(p_payload->>'asignado_a','') is not null and not exists (
    select 1 from public."USUARIOS_EMPRESAS_APPGT" ue
    where ue.empresa_id=v_empresa_id
      and ue.user_id=nullif(p_payload->>'asignado_a','')::uuid and ue.activo
  ) then raise exception 'El responsable no pertenece a la empresa'; end if;
  v_id := nullif(p_payload->>'id','')::uuid;
  if v_id is null then
    insert into public."ZUMAC_ACCIONES_APPGT" (
      empresa_id, alerta_evento_id, alerta_id, tipo, titulo, descripcion, prioridad,
      asignado_a, aprobador_id, fecha_limite, creada_por
    ) values (
      v_empresa_id, nullif(p_payload->>'alerta_evento_id','')::uuid, nullif(p_payload->>'alerta_id','')::uuid,
      coalesce(nullif(p_payload->>'tipo',''),'TAREA'), btrim(p_payload->>'titulo'), p_payload->>'descripcion',
      coalesce(nullif(p_payload->>'prioridad',''),'MEDIA'), nullif(p_payload->>'asignado_a','')::uuid,
      nullif(p_payload->>'aprobador_id','')::uuid, public.appgt_alerta_fecha_v1(p_payload->>'fecha_limite'), auth.uid()
    ) returning id into v_id;
  else
    update public."ZUMAC_ACCIONES_APPGT" set titulo=btrim(p_payload->>'titulo'), descripcion=p_payload->>'descripcion',
      tipo=coalesce(nullif(p_payload->>'tipo',''),tipo), prioridad=coalesce(nullif(p_payload->>'prioridad',''),prioridad),
      asignado_a=nullif(p_payload->>'asignado_a','')::uuid, aprobador_id=nullif(p_payload->>'aprobador_id','')::uuid,
      fecha_limite=public.appgt_alerta_fecha_v1(p_payload->>'fecha_limite')
    where id=v_id and empresa_id=v_empresa_id and (public.appgt_puede_gestionar_configuracion(v_empresa_id) or creada_por=auth.uid());
    if not found then raise exception 'Acción no encontrada o sin permiso'; end if;
  end if;
  return jsonb_build_object('id',v_id,'guardada',true);
end
$$;

create or replace function public.appgt_actualizar_accion_v1(
  p_accion_id uuid, p_estado text, p_resultado jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_empresa_id uuid:=public.appgt_empresa_actual_id(); v_row public."ZUMAC_ACCIONES_APPGT"%rowtype;
begin
  if p_estado not in ('PENDIENTE','EN_PROGRESO','APROBADA','RECHAZADA','COMPLETADA','CANCELADA') then raise exception 'Estado inválido'; end if;
  update public."ZUMAC_ACCIONES_APPGT" set estado=p_estado, resultado=coalesce(p_resultado,'{}'::jsonb),
    iniciada_at=case when p_estado='EN_PROGRESO' then coalesce(iniciada_at,now()) else iniciada_at end,
    completada_at=case when p_estado in ('APROBADA','RECHAZADA','COMPLETADA','CANCELADA') then now() else completada_at end
  where id=p_accion_id and empresa_id=v_empresa_id
    and (public.appgt_puede_gestionar_configuracion(v_empresa_id) or asignado_a=auth.uid() or aprobador_id=auth.uid() or creada_por=auth.uid())
  returning * into v_row;
  if v_row.id is null then raise exception 'Acción no encontrada o sin permiso'; end if;
  if v_row.alerta_evento_id is not null and p_estado in ('APROBADA','COMPLETADA') then
    update public."ZUMAC_ALERTA_EVENTOS_APPGT" set estado='ATENDIDA', atendida_at=now() where id=v_row.alerta_evento_id and estado not in ('CERRADA','DESCARTADA');
  end if;
  return to_jsonb(v_row);
end
$$;

create or replace function public.appgt_comentar_accion_v1(
  p_accion_id uuid, p_comentario text, p_evidencia jsonb default '[]'::jsonb
)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_empresa_id uuid:=public.appgt_empresa_actual_id(); v_id uuid;
begin
  if nullif(btrim(p_comentario),'') is null then raise exception 'El comentario es obligatorio'; end if;
  if not exists(select 1 from public."ZUMAC_ACCIONES_APPGT" where id=p_accion_id and empresa_id=v_empresa_id) then raise exception 'Acción no encontrada'; end if;
  insert into public."ZUMAC_ACCION_COMENTARIOS_APPGT"(empresa_id,accion_id,comentario,evidencia,creado_por)
    values(v_empresa_id,p_accion_id,btrim(p_comentario),coalesce(p_evidencia,'[]'::jsonb),auth.uid()) returning id into v_id;
  return jsonb_build_object('id',v_id,'guardado',true);
end
$$;

create or replace function public.appgt_registrar_dispositivo_v1(p_token text,p_plataforma text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_empresa_id uuid:=public.appgt_empresa_actual_id(); v_id uuid;
begin
  if v_empresa_id is null or nullif(btrim(p_token),'') is null then raise exception 'Datos incompletos'; end if;
  insert into public."ZUMAC_DISPOSITIVOS_APPGT"(empresa_id,user_id,token,plataforma)
  values(v_empresa_id,auth.uid(),btrim(p_token),upper(p_plataforma))
  on conflict(token) do update set empresa_id=excluded.empresa_id,user_id=excluded.user_id,
    plataforma=excluded.plataforma,activo=true,ultima_actividad_at=now()
  returning id into v_id;
  return jsonb_build_object('id',v_id,'registrado',true);
end
$$;

-- RLS: lectura para miembros de la empresa; cambios de negocio pasan por RPC
-- para validar transiciones, responsables y permisos.
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'ZUMAC_ALERTAS_APPGT','ZUMAC_ALERTA_DESTINATARIOS_APPGT','ZUMAC_ALERTA_EVENTOS_APPGT',
    'ZUMAC_ACCIONES_APPGT','ZUMAC_ACCION_COMENTARIOS_APPGT','ZUMAC_ALERTA_EJECUCIONES_APPGT','ZUMAC_DISPOSITIVOS_APPGT'
  ] loop
    execute format('alter table public.%I enable row level security',v_table);
    execute format('drop policy if exists zumac_empresa_select on public.%I',v_table);
    execute format('create policy zumac_empresa_select on public.%I for select to authenticated using (public.appgt_puede_acceder_empresa(empresa_id))',v_table);
  end loop;
end
$$;

drop policy if exists zumac_alertas_manager_all on public."ZUMAC_ALERTAS_APPGT";
create policy zumac_alertas_manager_all on public."ZUMAC_ALERTAS_APPGT" for all to authenticated
  using(public.appgt_puede_gestionar_configuracion(empresa_id)) with check(public.appgt_puede_gestionar_configuracion(empresa_id));
drop policy if exists zumac_destinatarios_manager_all on public."ZUMAC_ALERTA_DESTINATARIOS_APPGT";
create policy zumac_destinatarios_manager_all on public."ZUMAC_ALERTA_DESTINATARIOS_APPGT" for all to authenticated
  using(public.appgt_puede_gestionar_configuracion(empresa_id)) with check(public.appgt_puede_gestionar_configuracion(empresa_id));
drop policy if exists zumac_dispositivos_own_all on public."ZUMAC_DISPOSITIVOS_APPGT";
create policy zumac_dispositivos_own_all on public."ZUMAC_DISPOSITIVOS_APPGT" for all to authenticated
  using(user_id=auth.uid() and public.appgt_puede_acceder_empresa(empresa_id))
  with check(user_id=auth.uid() and public.appgt_puede_acceder_empresa(empresa_id));

-- Los eventos y acciones se publican por Realtime para actualizar la bandeja
-- abierta sin volver a descargar las tablas operativas del negocio.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='ZUMAC_ALERTA_EVENTOS_APPGT') then
      alter publication supabase_realtime add table public."ZUMAC_ALERTA_EVENTOS_APPGT";
    end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='ZUMAC_ACCIONES_APPGT') then
      alter publication supabase_realtime add table public."ZUMAC_ACCIONES_APPGT";
    end if;
  end if;
exception when insufficient_privilege then
  raise notice 'Realtime deberá habilitarse desde el panel de Supabase.';
end
$$;

-- Extiende el contexto ya consumido por Inicio sin romper clientes antiguos.
create or replace function public.appgt_empresa_funcionalidad_habilitada(p_empresa_id uuid,p_codigo text)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select case upper(btrim(coalesce(p_codigo, '')))
    when 'ZUMAC_CONSULTOR' then e.habilitar_zumac_consultor
    when 'ZUMAC_CREATOR' then e.habilitar_zumac_creator
    when 'ZUMAC_ALERTS' then e.habilitar_zumac_alerts
    when 'ZUMAC_ACTIONS' then e.habilitar_zumac_actions
    when 'IA_AVANZADA' then e.habilitar_ia_avanzada
    else false end
  from public."EMPRESAS_APPGT" e where e.id=p_empresa_id and e.activo;
$$;

-- Supabase Cron (pg_cron) ejecuta el evaluador aun cuando ningún usuario tenga
-- la aplicación abierta. El nombre estable hace idempotente el despliegue.
create extension if not exists pg_cron with schema pg_catalog;
do $$
declare v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job where jobname = 'zumac-alerts-every-minute'
  loop
    perform cron.unschedule(v_job_id);
  end loop;
  perform cron.schedule(
    'zumac-alerts-every-minute',
    '* * * * *',
    'select public.appgt_evaluar_alertas_v1();'
  );
end
$$;

revoke all on function public.appgt_alertas_contexto_v1() from public,anon;
revoke all on function public.appgt_guardar_alerta_v1(jsonb) from public,anon;
revoke all on function public.appgt_probar_alerta_v1(jsonb) from public,anon;
revoke all on function public.appgt_evaluar_alertas_v1(integer) from public,anon;
revoke all on function public.appgt_actualizar_evento_alerta_v1(uuid,text,uuid) from public,anon;
revoke all on function public.appgt_guardar_accion_v1(jsonb) from public,anon;
revoke all on function public.appgt_actualizar_accion_v1(uuid,text,jsonb) from public,anon;
revoke all on function public.appgt_comentar_accion_v1(uuid,text,jsonb) from public,anon;
revoke all on function public.appgt_registrar_dispositivo_v1(text,text) from public,anon;

-- Los auxiliares SECURITY DEFINER solo son piezas internas. Revocar su acceso
-- evita que un cliente intente consultar una empresa distinta pasando un UUID.
revoke all on function public.appgt_alerta_numero_v1(text) from public,anon,authenticated;
revoke all on function public.appgt_alerta_fecha_v1(text) from public,anon,authenticated;
revoke all on function public.appgt_alerta_compara_v1(jsonb,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.appgt_alerta_cumple_v1(jsonb,jsonb) from public,anon,authenticated;
revoke all on function public.appgt_alerta_campos_expresion_v1(jsonb) from public,anon,authenticated;
revoke all on function public.appgt_tabla_alertable_v1(uuid,text) from public,anon,authenticated;
revoke all on function public.appgt_validar_alerta_v1(uuid,text,jsonb) from public,anon,authenticated;
revoke all on function public.appgt_alerta_filas_v1(uuid,text,integer) from public,anon,authenticated;
revoke all on function public.appgt_alerta_interpolar_v1(text,jsonb) from public,anon,authenticated;

grant execute on function public.appgt_alertas_contexto_v1() to authenticated;
grant execute on function public.appgt_guardar_alerta_v1(jsonb) to authenticated;
grant execute on function public.appgt_probar_alerta_v1(jsonb) to authenticated;
grant execute on function public.appgt_evaluar_alertas_v1(integer) to authenticated,service_role;
grant execute on function public.appgt_actualizar_evento_alerta_v1(uuid,text,uuid) to authenticated;
grant execute on function public.appgt_guardar_accion_v1(jsonb) to authenticated;
grant execute on function public.appgt_actualizar_accion_v1(uuid,text,jsonb) to authenticated;
grant execute on function public.appgt_comentar_accion_v1(uuid,text,jsonb) to authenticated;
grant execute on function public.appgt_registrar_dispositivo_v1(text,text) to authenticated;

grant select on public."ZUMAC_ALERTAS_APPGT", public."ZUMAC_ALERTA_DESTINATARIOS_APPGT",
  public."ZUMAC_ALERTA_EVENTOS_APPGT", public."ZUMAC_ACCIONES_APPGT",
  public."ZUMAC_ACCION_COMENTARIOS_APPGT" to authenticated;
grant select,insert,update,delete on public."ZUMAC_DISPOSITIVOS_APPGT" to authenticated;

select set_config('appgt.skip_auto_fields', 'off', true);

commit;
