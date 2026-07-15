begin;

do $$
begin
  if exists (
    select 1 from pg_event_trigger
    where evtname = 'trg_appgt_auto_insertar_campos'
  ) then
    execute 'alter event trigger trg_appgt_auto_insertar_campos disable';
  end if;
end
$$;

create table if not exists public."BORRADORES_CONFIGURACION_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  rubro_id text,
  entidad_tipo text not null
    check (entidad_tipo in (
      'RUBRO', 'SECCION', 'MODULO', 'FORMATO', 'TABLA',
      'CAMPO', 'MATRIZ', 'PAQUETE'
    )),
  codigo text not null,
  nombre text not null,
  plantilla_origen_id uuid
    references public."PLANTILLAS_CONFIGURACION_APPGT"(id),
  definicion jsonb not null default '{}'::jsonb,
  estado text not null default 'BORRADOR'
    check (estado in (
      'BORRADOR', 'VALIDANDO', 'VALIDADO', 'PUBLICADO',
      'ARCHIVADO', 'ERROR_PUBLICACION'
    )),
  validacion jsonb not null default jsonb_build_object(
    'valido', false, 'errores', '[]'::jsonb, 'advertencias', '[]'::jsonb
  ),
  resultado_publicacion jsonb,
  version_borrador integer not null default 1 check (version_borrador > 0),
  lock_version integer not null default 1 check (lock_version > 0),
  version_configuracion_id uuid
    references public."VERSIONES_CONFIGURACION_APPGT"(id),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  validated_at timestamptz,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public."MIGRACIONES_CONFIGURACION_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  borrador_id uuid not null
    references public."BORRADORES_CONFIGURACION_APPGT"(id),
  entidad_tipo text not null,
  operacion text not null,
  objeto text not null,
  estado text not null default 'PENDIENTE'
    check (estado in ('PENDIENTE', 'APLICANDO', 'APLICADA', 'ERROR', 'REVERTIDA')),
  instrucciones jsonb not null default '{}'::jsonb,
  sql_preview text,
  checksum text,
  error_mensaje text,
  applied_by uuid references auth.users(id),
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public."AUDITORIA_CONFIGURACION_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  borrador_id uuid references public."BORRADORES_CONFIGURACION_APPGT"(id),
  entidad_tipo text,
  entidad_id text,
  accion text not null,
  estado_anterior text,
  estado_nuevo text,
  datos_antes jsonb,
  datos_despues jsonb,
  metadata jsonb not null default '{}'::jsonb,
  user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_borradores_configuracion_estado
  on public."BORRADORES_CONFIGURACION_APPGT"
  (empresa_id, estado, entidad_tipo, updated_at desc)
  where deleted_at is null;
create index if not exists idx_borradores_configuracion_codigo
  on public."BORRADORES_CONFIGURACION_APPGT"
  (empresa_id, entidad_tipo, codigo)
  where deleted_at is null;
create index if not exists idx_migraciones_configuracion_borrador
  on public."MIGRACIONES_CONFIGURACION_APPGT"
  (empresa_id, borrador_id, estado, created_at desc);
create index if not exists idx_auditoria_configuracion_entidad
  on public."AUDITORIA_CONFIGURACION_APPGT"
  (empresa_id, entidad_tipo, entidad_id, created_at desc);

-- El trigger automático continúa funcionando para DDL ajeno al constructor.
-- Las publicaciones controladas pueden suspenderlo con una variable local de
-- transacción para evitar duplicar los campos que insertan explícitamente.
create or replace function public.appgt_auto_insertar_campos_nueva_tabla()
returns event_trigger
language plpgsql
as $$
begin
  if current_setting('appgt.skip_auto_fields', true) = 'on' then
    return;
  end if;
  perform public.appgt_insertar_campos_faltantes_matriz();
end
$$;

create or replace function public.appgt_empresa_actual_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select ue.empresa_id
  from public."USUARIOS_EMPRESAS_APPGT" ue
  join public."EMPRESAS_APPGT" e on e.id = ue.empresa_id and e.activo
  where ue.user_id = auth.uid() and ue.activo
  order by ue.es_predeterminada desc, ue.created_at
  limit 1;
$$;

create or replace function public.appgt_puede_gestionar_configuracion(
  p_empresa_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public."USUARIOS_EMPRESAS_APPGT" ue
    where ue.user_id = auth.uid()
      and ue.empresa_id = p_empresa_id
      and ue.activo
      and ue.rol in ('ADMIN', 'GESTOR')
  );
$$;

create or replace function public.appgt_jsonb_bool(
  p_payload jsonb,
  p_key text,
  p_default boolean
)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select case
    when not (p_payload ? p_key) then p_default
    when lower(btrim(coalesce(p_payload ->> p_key, ''))) in
      ('true', 't', '1', 'si', 'sí', 'yes', 'x') then true
    when lower(btrim(coalesce(p_payload ->> p_key, ''))) in
      ('false', 'f', '0', 'no', '') then false
    else p_default
  end;
$$;

create or replace function public.appgt_contexto_constructor_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_rol text;
begin
  if v_empresa_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select ue.rol into v_rol
  from public."USUARIOS_EMPRESAS_APPGT" ue
  where ue.user_id = auth.uid() and ue.empresa_id = v_empresa_id and ue.activo;

  return jsonb_build_object(
    'empresa_id', v_empresa_id,
    'rol', v_rol,
    'puede_gestionar', v_rol in ('ADMIN', 'GESTOR'),
    'puede_publicar', v_rol = 'ADMIN',
    'rubros', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.orden, r.nombre)
      from public."RUBROS_APPGT" r
      where r.empresa_id = v_empresa_id
        and coalesce(r.activo, true)
        and r.deleted_at is null
    ), '[]'::jsonb),
    'resumen_plantillas', coalesce((
      select jsonb_object_agg(entidad_tipo, total)
      from (
        select entidad_tipo, count(*) total
        from public."PLANTILLAS_CONFIGURACION_APPGT"
        where empresa_id = v_empresa_id and activo and deleted_at is null
        group by entidad_tipo
      ) q
    ), '{}'::jsonb),
    'resumen_borradores', coalesce((
      select jsonb_object_agg(estado, total)
      from (
        select estado, count(*) total
        from public."BORRADORES_CONFIGURACION_APPGT"
        where empresa_id = v_empresa_id and deleted_at is null
        group by estado
      ) q
    ), '{}'::jsonb)
  );
end
$$;

create or replace function public.appgt_listar_plantillas_configuracion(
  p_entidad_tipo text default null,
  p_rubro_id text default null,
  p_padre_origen_id text default null,
  p_busqueda text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'configuration manager permission required'
      using errcode = '42501';
  end if;

  return jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.entidad_tipo, p.nombre, p.version desc)
      from (
        select *
        from public."PLANTILLAS_CONFIGURACION_APPGT" p0
        where p0.empresa_id = v_empresa_id
          and p0.activo and p0.deleted_at is null and p0.es_actual
          and (p_entidad_tipo is null or p0.entidad_tipo = upper(btrim(p_entidad_tipo)))
          and (p_rubro_id is null or p0.rubro_id = p_rubro_id)
          and (p_padre_origen_id is null or p0.padre_origen_id = p_padre_origen_id)
          and (
            nullif(btrim(coalesce(p_busqueda, '')), '') is null
            or p0.nombre ilike '%' || btrim(p_busqueda) || '%'
            or p0.codigo ilike '%' || btrim(p_busqueda) || '%'
          )
        order by p0.entidad_tipo, p0.nombre, p0.version desc
        limit v_limit offset v_offset
      ) p
    ), '[]'::jsonb),
    'total', (
      select count(*)
      from public."PLANTILLAS_CONFIGURACION_APPGT" p0
      where p0.empresa_id = v_empresa_id
        and p0.activo and p0.deleted_at is null and p0.es_actual
        and (p_entidad_tipo is null or p0.entidad_tipo = upper(btrim(p_entidad_tipo)))
        and (p_rubro_id is null or p0.rubro_id = p_rubro_id)
        and (p_padre_origen_id is null or p0.padre_origen_id = p_padre_origen_id)
        and (
          nullif(btrim(coalesce(p_busqueda, '')), '') is null
          or p0.nombre ilike '%' || btrim(p_busqueda) || '%'
          or p0.codigo ilike '%' || btrim(p_busqueda) || '%'
        )
    ),
    'limit', v_limit,
    'offset', v_offset
  );
end
$$;

create or replace function public.appgt_listar_borradores_configuracion(
  p_estado text default null,
  p_entidad_tipo text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'configuration manager permission required'
      using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(b) order by b.updated_at desc)
    from public."BORRADORES_CONFIGURACION_APPGT" b
    where b.empresa_id = v_empresa_id and b.deleted_at is null
      and (p_estado is null or b.estado = upper(btrim(p_estado)))
      and (p_entidad_tipo is null or b.entidad_tipo = upper(btrim(p_entidad_tipo)))
  ), '[]'::jsonb);
end
$$;

create or replace function public.appgt_guardar_borrador_configuracion(
  p_entidad_tipo text,
  p_payload jsonb,
  p_borrador_id uuid default null,
  p_plantilla_origen_id uuid default null,
  p_lock_version integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_tipo text := upper(btrim(coalesce(p_entidad_tipo, '')));
  v_codigo text := btrim(coalesce(p_payload ->> 'codigo', ''));
  v_nombre text := btrim(coalesce(p_payload ->> 'nombre', ''));
  v_rubro_id text;
  v_template public."PLANTILLAS_CONFIGURACION_APPGT";
  v_before public."BORRADORES_CONFIGURACION_APPGT";
  v_draft public."BORRADORES_CONFIGURACION_APPGT";
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'configuration manager permission required'
      using errcode = '42501';
  end if;
  if v_tipo not in (
    'RUBRO', 'SECCION', 'MODULO', 'FORMATO', 'TABLA',
    'CAMPO', 'MATRIZ', 'PAQUETE'
  ) then
    raise exception 'invalid entity type';
  end if;
  if jsonb_typeof(p_payload) <> 'object' then
    raise exception 'payload must be a JSON object';
  end if;

  if p_plantilla_origen_id is not null then
    select * into v_template
    from public."PLANTILLAS_CONFIGURACION_APPGT"
    where id = p_plantilla_origen_id
      and empresa_id = v_empresa_id and activo and deleted_at is null;
    if v_template.id is null or v_template.entidad_tipo <> v_tipo then
      raise exception 'template not found or incompatible';
    end if;
  end if;

  v_rubro_id := coalesce(
    nullif(btrim(p_payload ->> 'rubro_id'), ''),
    v_template.rubro_id,
    case when v_tipo = 'RUBRO' then v_codigo else null end,
    (
      select r.id from public."RUBROS_APPGT" r
      where r.empresa_id = v_empresa_id
        and coalesce(r.activo, true) and r.deleted_at is null
      order by r.orden, r.id limit 1
    )
  );

  if p_borrador_id is null then
    insert into public."BORRADORES_CONFIGURACION_APPGT" (
      empresa_id, rubro_id, entidad_tipo, codigo, nombre,
      plantilla_origen_id, definicion, created_by, updated_by
    ) values (
      v_empresa_id, v_rubro_id, v_tipo, v_codigo, v_nombre,
      p_plantilla_origen_id, p_payload, auth.uid(), auth.uid()
    ) returning * into v_draft;
  else
    select * into v_before
    from public."BORRADORES_CONFIGURACION_APPGT"
    where id = p_borrador_id and empresa_id = v_empresa_id
      and deleted_at is null
    for update;
    if v_before.id is null then
      raise exception 'draft not found';
    end if;
    if v_before.estado in ('PUBLICADO', 'ARCHIVADO') then
      raise exception 'published or archived drafts are immutable';
    end if;
    if p_lock_version is not null and v_before.lock_version <> p_lock_version then
      raise exception 'draft was modified by another session' using errcode = '40001';
    end if;

    update public."BORRADORES_CONFIGURACION_APPGT" set
      rubro_id = v_rubro_id,
      codigo = v_codigo,
      nombre = v_nombre,
      plantilla_origen_id = coalesce(p_plantilla_origen_id, plantilla_origen_id),
      definicion = p_payload,
      estado = 'BORRADOR',
      validacion = jsonb_build_object(
        'valido', false, 'errores', '[]'::jsonb,
        'advertencias', '[]'::jsonb
      ),
      resultado_publicacion = null,
      version_borrador = version_borrador + 1,
      lock_version = lock_version + 1,
      updated_by = auth.uid(),
      validated_at = null,
      updated_at = now()
    where id = p_borrador_id
    returning * into v_draft;
  end if;

  insert into public."AUDITORIA_CONFIGURACION_APPGT" (
    empresa_id, borrador_id, entidad_tipo, entidad_id, accion,
    estado_anterior, estado_nuevo, datos_antes, datos_despues, user_id
  ) values (
    v_empresa_id, v_draft.id, v_tipo, v_codigo,
    case when p_borrador_id is null then 'CREAR_BORRADOR' else 'EDITAR_BORRADOR' end,
    v_before.estado, v_draft.estado,
    case when v_before.id is null then null else to_jsonb(v_before) end,
    to_jsonb(v_draft), auth.uid()
  );

  return to_jsonb(v_draft);
end
$$;

create or replace function public.appgt_clonar_plantilla_configuracion(
  p_plantilla_id uuid,
  p_sobrescritura jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_template public."PLANTILLAS_CONFIGURACION_APPGT";
  v_payload jsonb;
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'configuration manager permission required'
      using errcode = '42501';
  end if;

  select * into v_template
  from public."PLANTILLAS_CONFIGURACION_APPGT"
  where id = p_plantilla_id and empresa_id = v_empresa_id
    and activo and deleted_at is null;
  if v_template.id is null then
    raise exception 'template not found';
  end if;

  v_payload := v_template.definicion || coalesce(p_sobrescritura, '{}'::jsonb);
  return public.appgt_guardar_borrador_configuracion(
    v_template.entidad_tipo,
    v_payload,
    null,
    v_template.id,
    null
  );
end
$$;

create or replace function public.appgt_validar_borrador_configuracion(
  p_borrador_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_draft public."BORRADORES_CONFIGURACION_APPGT";
  v_payload jsonb;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_parent text;
  v_table text;
  v_field text;
  v_tipo_formato text;
  v_clase_matriz text;
  v_is_valid boolean;
  v_validation jsonb;
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'configuration manager permission required'
      using errcode = '42501';
  end if;

  select * into v_draft
  from public."BORRADORES_CONFIGURACION_APPGT"
  where id = p_borrador_id and empresa_id = v_empresa_id
    and deleted_at is null
  for update;
  if v_draft.id is null then
    raise exception 'draft not found';
  end if;
  if v_draft.estado in ('PUBLICADO', 'ARCHIVADO') then
    return v_draft.validacion;
  end if;

  v_payload := v_draft.definicion;
  update public."BORRADORES_CONFIGURACION_APPGT"
  set estado = 'VALIDANDO', updated_at = now()
  where id = v_draft.id;

  if v_draft.codigo = '' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'campo', 'codigo', 'mensaje', 'El código técnico es obligatorio.'
    ));
  elsif v_draft.codigo !~ '^[A-Za-z0-9][A-Za-z0-9_-]{1,62}$' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'campo', 'codigo',
      'mensaje', 'Use de 2 a 63 caracteres: letras, números, guion o guion bajo.'
    ));
  end if;
  if v_draft.nombre = '' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'campo', 'nombre', 'mensaje', 'El nombre visible es obligatorio.'
    ));
  end if;
  if nullif(btrim(v_payload ->> 'orden'), '') is not null
     and (v_payload ->> 'orden') !~ '^-?[0-9]+$' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'campo', 'orden', 'mensaje', 'El orden debe ser un número entero.'
    ));
  end if;

  case v_draft.entidad_tipo
    when 'RUBRO' then
      if exists (
        select 1 from public."RUBROS_APPGT" x
        where x.empresa_id = v_empresa_id and x.id = v_draft.codigo
      ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'codigo', 'mensaje', 'Ya existe un rubro publicado con ese código.'
        ));
      end if;
    when 'SECCION' then
      v_parent := coalesce(nullif(v_payload ->> 'rubro_id', ''), v_draft.rubro_id);
      if v_parent is null or not exists (
        select 1 from public."RUBROS_APPGT" x
        where x.empresa_id = v_empresa_id and x.id = v_parent
          and coalesce(x.activo, true) and x.deleted_at is null
      ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'rubro_id', 'mensaje', 'Seleccione un rubro publicado.'
        ));
      end if;
      if upper(coalesce(v_payload ->> 'tipo_contenido', '')) not in
        ('FORMATOS', 'REPORTES', 'VISTAS_DINAMICAS', 'REGISTROS_LOCALES', 'INICIO', 'GENERICO') then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'tipo_contenido', 'mensaje', 'Seleccione el tipo de contenido.'
        ));
      end if;
      if exists (
        select 1 from public."MATRIZ_SECCIONES_APPGT" x
        where x.empresa_id = v_empresa_id and x.id = v_draft.codigo
      ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'codigo', 'mensaje', 'Ya existe una sección publicada con ese código.'
        ));
      end if;
    when 'MODULO' then
      v_parent := coalesce(v_payload ->> 'seccion_id', v_payload ->> 'seccion');
      if nullif(v_parent, '') is null or not exists (
        select 1 from public."MATRIZ_SECCIONES_APPGT" x
        where x.empresa_id = v_empresa_id and x.id = v_parent
          and coalesce(x.activo, true) and x.deleted_at is null
      ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'seccion_id', 'mensaje', 'Seleccione una sección publicada.'
        ));
      end if;
      if exists (
        select 1 from public."MATRIZ_MODULOS_APPGT" x
        where x.empresa_id = v_empresa_id and x.id = v_draft.codigo
      ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'codigo', 'mensaje', 'Ya existe un módulo publicado con ese código.'
        ));
      end if;
    when 'FORMATO' then
      v_parent := v_payload ->> 'modulo_id';
      v_tipo_formato := upper(coalesce(v_payload ->> 'tipo_formato', 'SIMPLE'));
      v_table := btrim(coalesce(v_payload ->> 'tabla_destino', ''));
      if nullif(v_parent, '') is null or not exists (
        select 1 from public."MATRIZ_MODULOS_APPGT" x
        where x.empresa_id = v_empresa_id and x.id = v_parent
          and coalesce(x.activo, true) and x.deleted_at is null
      ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'modulo_id', 'mensaje', 'Seleccione un módulo publicado.'
        ));
      end if;
      if v_tipo_formato not in (
        'SIMPLE', 'CABECERA_DETALLE', 'MATRIZ', 'FLUJO', 'INSPECCION',
        'ENCUESTA', 'REGISTRO_MASIVO', 'CONSULTA', 'REPORTE', 'ESPECIAL'
      ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'tipo_formato', 'mensaje', 'El tipo de formato no es válido.'
        ));
      end if;
      if v_table = '' then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'tabla_destino', 'mensaje', 'Defina la tabla principal del formato.'
        ));
      end if;
      if exists (
        select 1 from public."MATRIZ_FORMATOS_APPGT" x
        where x.empresa_id = v_empresa_id and x.id = v_draft.codigo
      ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'codigo', 'mensaje', 'Ya existe un formato publicado con ese código.'
        ));
      end if;
    when 'TABLA' then
      v_parent := v_payload ->> 'formato_id';
      v_table := btrim(coalesce(v_payload ->> 'tabla_destino', ''));
      if nullif(v_parent, '') is null or not exists (
        select 1 from public."MATRIZ_FORMATOS_APPGT" x
        where x.empresa_id = v_empresa_id and x.id = v_parent
          and coalesce(x.activo, true) and x.deleted_at is null
      ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'formato_id', 'mensaje', 'Seleccione un formato publicado.'
        ));
      end if;
      if v_table !~ '^[A-Za-z0-9][A-Za-z0-9_-]{1,62}$' then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'tabla_destino', 'mensaje', 'El nombre técnico de tabla no es válido.'
        ));
      end if;
      if exists (
        select 1 from public."MATRIZ_FORMATO_TABLAS_APPGT" x
        where x.empresa_id = v_empresa_id and x.id = v_draft.codigo
      ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'codigo', 'mensaje', 'Ya existe una tabla de formato con ese código.'
        ));
      end if;
    when 'CAMPO' then
      v_table := btrim(coalesce(v_payload ->> 'tabla_destino', ''));
      v_field := btrim(coalesce(v_payload ->> 'campo', ''));
      if to_regclass(format('public.%I', v_table)) is null then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'tabla_destino', 'mensaje', 'La tabla física todavía no existe.'
        ));
      end if;
      if v_field = '' or length(v_field) > 63 or v_field ~ '[[:cntrl:]]' then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'campo', 'mensaje', 'El nombre técnico del campo no es válido.'
        ));
      end if;
      if lower(v_field) in (
        'id', 'id_local', 'empresa_id', 'created_at', 'updated_at',
        'deleted_at', 'eliminado', 'estado_sync'
      ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'campo', 'mensaje', 'Ese nombre está reservado por el sistema.'
        ));
      end if;
      if nullif(btrim(coalesce(v_payload ->> 'tipo_ui', v_payload ->> 'tipo')), '') is null then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'tipo_ui', 'mensaje', 'Seleccione el tipo de control.'
        ));
      end if;
      if exists (
        select 1 from public."MATRIZ_CAMPOS_FORMATO_APPGT" x
        where x.empresa_id = v_empresa_id
          and x.tabla_destino = v_table and x.campo = v_field
          and coalesce(x.activo, true) and x.deleted_at is null
      ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'campo', 'mensaje', 'Ese campo ya está configurado para la tabla.'
        ));
      end if;
      if lower(coalesce(v_payload ->> 'tipo_ui', '')) in ('dropdown', 'multiselect')
         and nullif(btrim(coalesce(v_payload ->> 'id_campo_dropdown', '')), '') is null then
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'campo', 'id_campo_dropdown',
          'mensaje', 'El selector aún no tiene una fuente configurada.'
        ));
      end if;
    when 'MATRIZ' then
      v_clase_matriz := upper(btrim(coalesce(v_payload ->> 'clase_matriz', '')));
      if v_clase_matriz not in ('DROPDOWN', 'VALIDACION', 'CONDICION', 'FORMULA') then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'clase_matriz', 'mensaje', 'Seleccione la clase de matriz.'
        ));
      end if;
      if v_clase_matriz = 'FORMULA'
         and nullif(btrim(coalesce(v_payload ->> 'expresion', '')), '') is null then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'expresion', 'mensaje', 'La fórmula necesita una expresión.'
        ));
      end if;
    when 'PAQUETE' then
      if jsonb_typeof(v_payload -> 'entidades') <> 'array' then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', 'entidades', 'mensaje', 'El paquete debe incluir una lista de entidades.'
        ));
      end if;
  end case;

  v_is_valid := jsonb_array_length(v_errors) = 0;
  v_validation := jsonb_build_object(
    'valido', v_is_valid,
    'errores', v_errors,
    'advertencias', v_warnings,
    'validado_en', now()
  );

  update public."BORRADORES_CONFIGURACION_APPGT" set
    estado = case when v_is_valid then 'VALIDADO' else 'BORRADOR' end,
    validacion = v_validation,
    validated_at = now(),
    updated_by = auth.uid(),
    updated_at = now(),
    lock_version = lock_version + 1
  where id = v_draft.id;

  insert into public."AUDITORIA_CONFIGURACION_APPGT" (
    empresa_id, borrador_id, entidad_tipo, entidad_id, accion,
    estado_anterior, estado_nuevo, datos_despues, user_id
  ) values (
    v_empresa_id, v_draft.id, v_draft.entidad_tipo, v_draft.codigo,
    'VALIDAR', v_draft.estado,
    case when v_is_valid then 'VALIDADO' else 'BORRADOR' end,
    v_validation, auth.uid()
  );

  return v_validation;
end
$$;

create or replace function public.appgt_publicar_borrador_configuracion(
  p_borrador_id uuid,
  p_notas text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_draft public."BORRADORES_CONFIGURACION_APPGT";
  v_payload jsonb;
  v_validation jsonb;
  v_code text;
  v_table text;
  v_field text;
  v_ui_type text;
  v_sql_type text;
  v_class text;
  v_migration_id uuid;
  v_version_number integer;
  v_version public."VERSIONES_CONFIGURACION_APPGT";
  v_rubro_id text;
  v_parent_type text;
  v_parent_id text;
  v_result jsonb;
begin
  if v_empresa_id is null or not public.appgt_es_admin_empresa(v_empresa_id) then
    raise exception 'administrator permission required' using errcode = '42501';
  end if;

  select * into v_draft
  from public."BORRADORES_CONFIGURACION_APPGT"
  where id = p_borrador_id and empresa_id = v_empresa_id
    and deleted_at is null
  for update;
  if v_draft.id is null then
    raise exception 'draft not found';
  end if;
  if v_draft.estado = 'PUBLICADO' then
    return coalesce(v_draft.resultado_publicacion, to_jsonb(v_draft));
  end if;

  v_validation := public.appgt_validar_borrador_configuracion(v_draft.id);
  if not coalesce((v_validation ->> 'valido')::boolean, false) then
    return jsonb_build_object(
      'publicado', false, 'borrador_id', v_draft.id,
      'validacion', v_validation
    );
  end if;

  select * into v_draft
  from public."BORRADORES_CONFIGURACION_APPGT"
  where id = p_borrador_id for update;
  v_payload := v_draft.definicion;
  v_code := v_draft.codigo;

  begin
    case v_draft.entidad_tipo
      when 'RUBRO' then
        insert into public."RUBROS_APPGT" (
          id, empresa_id, codigo, nombre, descripcion, icono, color,
          orden, activo
        ) values (
          v_code, v_empresa_id, v_code, v_draft.nombre,
          v_payload ->> 'descripcion', v_payload ->> 'icono',
          v_payload ->> 'color',
          coalesce(nullif(v_payload ->> 'orden', '')::integer, 0),
          public.appgt_jsonb_bool(v_payload, 'activo', true)
        );
        v_rubro_id := v_code;
        v_parent_type := null;
        v_parent_id := null;
      when 'SECCION' then
        v_rubro_id := coalesce(v_payload ->> 'rubro_id', v_draft.rubro_id);
        insert into public."MATRIZ_SECCIONES_APPGT" (
          id, empresa_id, nombre, icono, orden, activo, rubro_id,
          tipo_contenido, ruta_flutter
        ) values (
          v_code, v_empresa_id, v_draft.nombre, v_payload ->> 'icono',
          coalesce(nullif(v_payload ->> 'orden', '')::integer, 0),
          public.appgt_jsonb_bool(v_payload, 'activo', true),
          v_rubro_id, upper(v_payload ->> 'tipo_contenido'),
          nullif(v_payload ->> 'ruta_flutter', '')
        );
        v_parent_type := 'RUBRO';
        v_parent_id := v_rubro_id;
      when 'MODULO' then
        insert into public."MATRIZ_MODULOS_APPGT" (
          id, empresa_id, nombre, seccion, orden, activo
        ) values (
          v_code, v_empresa_id, v_draft.nombre,
          coalesce(v_payload ->> 'seccion_id', v_payload ->> 'seccion'),
          coalesce(nullif(v_payload ->> 'orden', '')::integer, 0),
          public.appgt_jsonb_bool(v_payload, 'activo', true)
        );
        v_rubro_id := v_draft.rubro_id;
        v_parent_type := 'SECCION';
        v_parent_id := coalesce(v_payload ->> 'seccion_id', v_payload ->> 'seccion');
      when 'FORMATO' then
        insert into public."MATRIZ_FORMATOS_APPGT" (
          id, empresa_id, modulo_id, nombre, tabla_destino,
          ruta_flutter, tabla_visible_app, orden, activo
        ) values (
          v_code, v_empresa_id, v_payload ->> 'modulo_id', v_draft.nombre,
          v_payload ->> 'tabla_destino', nullif(v_payload ->> 'ruta_flutter', ''),
          public.appgt_jsonb_bool(v_payload, 'tabla_visible_app', true),
          coalesce(nullif(v_payload ->> 'orden', '')::integer, 0),
          public.appgt_jsonb_bool(v_payload, 'activo', true)
        );
        v_rubro_id := v_draft.rubro_id;
        v_parent_type := 'MODULO';
        v_parent_id := v_payload ->> 'modulo_id';
      when 'TABLA' then
        v_table := v_payload ->> 'tabla_destino';
        if public.appgt_jsonb_bool(v_payload, 'crear_tabla_fisica', false)
           and to_regclass(format('public.%I', v_table)) is null then
          insert into public."MIGRACIONES_CONFIGURACION_APPGT" (
            empresa_id, borrador_id, entidad_tipo, operacion, objeto,
            estado, instrucciones, sql_preview, checksum
          ) values (
            v_empresa_id, v_draft.id, 'TABLA', 'CREATE_TABLE', v_table,
            'APLICANDO', jsonb_build_object('tabla', v_table),
            format('create table public.%I (...)', v_table),
            md5(v_table || '|CREATE_TABLE|' || v_payload::text)
          ) returning id into v_migration_id;

          perform set_config('appgt.skip_auto_fields', 'on', true);
          execute format(
            'create table public.%I (
               id uuid primary key default gen_random_uuid(),
               id_local uuid not null unique,
               empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
               created_by uuid references auth.users(id) default auth.uid(),
               created_at timestamptz not null default now(),
               updated_at timestamptz not null default now(),
               deleted_at timestamptz,
               eliminado boolean not null default false,
               estado_sync text not null default ''sincronizado''
             )',
            v_table
          );
          execute format('alter table public.%I enable row level security', v_table);
          execute format(
            'create policy tenant_scope on public.%I for all to authenticated
             using (public.appgt_puede_acceder_empresa(empresa_id))
             with check (public.appgt_puede_acceder_empresa(empresa_id))',
            v_table
          );
          execute format(
            'create trigger appgt_set_updated_at_trigger before update on public.%I
             for each row execute function public.appgt_set_updated_at()',
            v_table
          );
          execute format(
            'grant select, insert, update, delete on table public.%I to authenticated',
            v_table
          );
          perform set_config('appgt.skip_auto_fields', 'off', true);

          update public."MIGRACIONES_CONFIGURACION_APPGT" set
            estado = 'APLICADA', applied_by = auth.uid(), applied_at = now()
          where id = v_migration_id;
        end if;

        insert into public."MATRIZ_FORMATO_TABLAS_APPGT" (
          id, empresa_id, formato_id, nombre, tabla_destino, orden, activo,
          tipo_relacion, tabla_padre, campo_pk_padre, campo_fk_hijo,
          es_cabecera, es_detalle, campo_iterador, iterador_desde,
          iterador_hasta, copiar_campos_desde_padre, modo_captura
        ) values (
          v_code, v_empresa_id, v_payload ->> 'formato_id', v_draft.nombre,
          v_table, coalesce(nullif(v_payload ->> 'orden', '')::integer, 0),
          public.appgt_jsonb_bool(v_payload, 'activo', true),
          nullif(v_payload ->> 'tipo_relacion', ''),
          nullif(v_payload ->> 'tabla_padre', ''),
          nullif(v_payload ->> 'campo_pk_padre', ''),
          nullif(v_payload ->> 'campo_fk_hijo', ''),
          public.appgt_jsonb_bool(v_payload, 'es_cabecera', false),
          public.appgt_jsonb_bool(v_payload, 'es_detalle', false),
          nullif(v_payload ->> 'campo_iterador', ''),
          nullif(v_payload ->> 'iterador_desde', '')::integer,
          nullif(v_payload ->> 'iterador_hasta', '')::integer,
          nullif(v_payload ->> 'copiar_campos_desde_padre', ''),
          nullif(v_payload ->> 'modo_captura', '')
        );
        v_rubro_id := v_draft.rubro_id;
        v_parent_type := 'FORMATO';
        v_parent_id := v_payload ->> 'formato_id';
      when 'CAMPO' then
        v_table := v_payload ->> 'tabla_destino';
        v_field := v_payload ->> 'campo';
        v_ui_type := lower(coalesce(v_payload ->> 'tipo_ui', v_payload ->> 'tipo', 'text'));
        v_sql_type := case
          when v_ui_type in ('number', 'numeric', 'decimal', 'formula', 'lookup') then 'numeric'
          when v_ui_type in ('integer', 'int') then 'bigint'
          when v_ui_type = 'date' then 'date'
          when v_ui_type = 'time' then 'time'
          when v_ui_type in ('datetime', 'timestamp') then 'timestamptz'
          when v_ui_type in ('boolean', 'bool', 'switch', 'checkbox') then 'boolean'
          when v_ui_type in ('json', 'jsonb') then 'jsonb'
          else 'text'
        end;

        if not exists (
          select 1 from information_schema.columns
          where table_schema = 'public' and table_name = v_table
            and column_name = v_field
        ) then
          insert into public."MIGRACIONES_CONFIGURACION_APPGT" (
            empresa_id, borrador_id, entidad_tipo, operacion, objeto,
            estado, instrucciones, sql_preview, checksum
          ) values (
            v_empresa_id, v_draft.id, 'CAMPO', 'ADD_COLUMN', v_table || '.' || v_field,
            'APLICANDO', jsonb_build_object(
              'tabla', v_table, 'campo', v_field, 'tipo_sql', v_sql_type
            ),
            format('alter table public.%I add column %I %s', v_table, v_field, v_sql_type),
            md5(v_table || '|' || v_field || '|' || v_sql_type)
          ) returning id into v_migration_id;

          perform set_config('appgt.skip_auto_fields', 'on', true);
          execute format(
            'alter table public.%I add column if not exists %I %s',
            v_table, v_field, v_sql_type
          );
          perform set_config('appgt.skip_auto_fields', 'off', true);

          update public."MIGRACIONES_CONFIGURACION_APPGT" set
            estado = 'APLICADA', applied_by = auth.uid(), applied_at = now()
          where id = v_migration_id;
        end if;

        insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
          id, empresa_id, tabla_destino, campo, etiqueta, tipo, tipo_ui,
          requerido, orden, activo, id_campo_dropdown, formula_funcion,
          valor_default, editable, visible, visible_tabla, numero_decimales,
          grid_fila, grid_columna, rango_valor, num_caracteres, numero_fotos,
          sub_titulo, fila_sub_titulo, grupo_captura
        ) values (
          v_code, v_empresa_id, v_table, v_field,
          coalesce(nullif(v_payload ->> 'etiqueta', ''), v_field),
          coalesce(nullif(v_payload ->> 'tipo', ''), v_ui_type), v_ui_type,
          case when public.appgt_jsonb_bool(v_payload, 'requerido', false)
            then 'true' else 'false' end,
          coalesce(nullif(v_payload ->> 'orden', '')::integer, 0),
          public.appgt_jsonb_bool(v_payload, 'activo', true),
          nullif(v_payload ->> 'id_campo_dropdown', ''),
          nullif(v_payload ->> 'formula_funcion', ''),
          nullif(v_payload ->> 'valor_default', ''),
          public.appgt_jsonb_bool(v_payload, 'editable', true),
          public.appgt_jsonb_bool(v_payload, 'visible', true),
          public.appgt_jsonb_bool(v_payload, 'visible_tabla', true),
          nullif(v_payload ->> 'numero_decimales', '')::numeric,
          nullif(v_payload ->> 'grid_fila', '')::numeric,
          nullif(v_payload ->> 'grid_columna', '')::numeric,
          nullif(v_payload ->> 'rango_valor', ''),
          nullif(v_payload ->> 'num_caracteres', '')::numeric,
          nullif(v_payload ->> 'numero_fotos', '')::numeric,
          nullif(v_payload ->> 'sub_titulo', ''),
          nullif(v_payload ->> 'fila_sub_titulo', '')::integer,
          nullif(v_payload ->> 'grupo_captura', '')
        );
        v_rubro_id := v_draft.rubro_id;
        v_parent_type := 'TABLA';
        v_parent_id := v_table;
      when 'MATRIZ' then
        v_class := upper(v_payload ->> 'clase_matriz');
        if v_class = 'DROPDOWN' then
          insert into public."MATRIZ_DROPDOWNS_APPGT" (
            empresa_id, codigo, campo_id, campo_origen_id, tabla_origen,
            campo_valor, campo_etiqueta, filtro_json, permite_multiple,
            orden, activo
          ) values (
            v_empresa_id, v_code, nullif(v_payload ->> 'campo_id', ''),
            nullif(v_payload ->> 'campo_origen_id', ''),
            nullif(v_payload ->> 'tabla_origen', ''),
            nullif(v_payload ->> 'campo_valor', ''),
            nullif(v_payload ->> 'campo_etiqueta', ''),
            coalesce(v_payload -> 'filtro_json', '{}'::jsonb),
            public.appgt_jsonb_bool(v_payload, 'permite_multiple', false),
            coalesce(nullif(v_payload ->> 'orden', '')::integer, 0), true
          );
        elsif v_class = 'VALIDACION' then
          insert into public."MATRIZ_VALIDACIONES_APPGT" (
            empresa_id, codigo, formato_id, campo_id, tipo_validacion,
            expresion, mensaje_error, bloquea_guardado, orden, activo
          ) values (
            v_empresa_id, v_code, nullif(v_payload ->> 'formato_id', ''),
            nullif(v_payload ->> 'campo_id', ''),
            upper(coalesce(nullif(v_payload ->> 'tipo_validacion', ''), 'EXPRESION')),
            nullif(v_payload ->> 'expresion', ''),
            nullif(v_payload ->> 'mensaje_error', ''),
            public.appgt_jsonb_bool(v_payload, 'bloquea_guardado', true),
            coalesce(nullif(v_payload ->> 'orden', '')::integer, 0), true
          );
        elsif v_class = 'CONDICION' then
          insert into public."MATRIZ_CONDICIONES_APPGT" (
            empresa_id, codigo, formato_id, campo_id, campo_dependencia_id,
            operador, valor_comparacion, expresion, accion, orden, activo
          ) values (
            v_empresa_id, v_code, nullif(v_payload ->> 'formato_id', ''),
            nullif(v_payload ->> 'campo_id', ''),
            nullif(v_payload ->> 'campo_dependencia_id', ''),
            upper(coalesce(nullif(v_payload ->> 'operador', ''), 'EXPRESION')),
            v_payload -> 'valor_comparacion', nullif(v_payload ->> 'expresion', ''),
            upper(coalesce(nullif(v_payload ->> 'accion', ''), 'MOSTRAR')),
            coalesce(nullif(v_payload ->> 'orden', '')::integer, 0), true
          );
        elsif v_class = 'FORMULA' then
          insert into public."MATRIZ_FORMULAS_APPGT" (
            empresa_id, codigo, formato_id, campo_id, expresion, lenguaje,
            recalcular_al_cambiar, orden, activo
          ) values (
            v_empresa_id, v_code, nullif(v_payload ->> 'formato_id', ''),
            nullif(v_payload ->> 'campo_id', ''), v_payload ->> 'expresion',
            coalesce(nullif(v_payload ->> 'lenguaje', ''), 'ZUMAC_EXPR'),
            public.appgt_jsonb_bool(v_payload, 'recalcular_al_cambiar', true),
            coalesce(nullif(v_payload ->> 'orden', '')::integer, 0), true
          );
        end if;
        v_rubro_id := v_draft.rubro_id;
        v_parent_type := case when nullif(v_payload ->> 'campo_id', '') is null
          then null else 'CAMPO' end;
        v_parent_id := nullif(v_payload ->> 'campo_id', '');
      else
        raise exception 'package publication requires its entities to be published individually';
    end case;

    lock table public."VERSIONES_CONFIGURACION_APPGT" in exclusive mode;
    select coalesce(max(numero_version), 0) + 1 into v_version_number
    from public."VERSIONES_CONFIGURACION_APPGT"
    where empresa_id = v_empresa_id;

    insert into public."VERSIONES_CONFIGURACION_APPGT" (
      empresa_id, numero_version, version, estado, descripcion,
      hash_configuracion, created_by
    ) values (
      v_empresa_id, v_version_number, '1.0.' || v_version_number,
      'BORRADOR',
      'Publicación de ' || v_draft.entidad_tipo || ' ' || v_code,
      md5(v_draft.entidad_tipo || '|' || v_code || '|' || v_payload::text),
      auth.uid()
    ) returning * into v_version;

    perform public.appgt_publicar_configuracion(
      v_version.id, 'PRODUCCION',
      coalesce(p_notas, 'Publicación desde el constructor visual ZUMAC.')
    );

    insert into public."PLANTILLAS_CONFIGURACION_APPGT" (
      empresa_id, rubro_id, entidad_tipo, entidad_origen_id,
      padre_tipo, padre_origen_id, codigo, nombre, descripcion,
      origen, tipo_plantilla, plantilla_origen_id, definicion,
      editable, version, estado, published_at
    ) values (
      v_empresa_id, v_rubro_id, v_draft.entidad_tipo, v_code,
      v_parent_type, v_parent_id, v_code, v_draft.nombre,
      v_payload ->> 'descripcion', 'EMPRESA', 'PERSONALIZADA',
      v_draft.plantilla_origen_id,
      v_payload || jsonb_build_object(
        'publicado_desde_borrador', v_draft.id,
        'version_configuracion_id', v_version.id
      ),
      true, 1, 'PUBLICADO', now()
    )
    on conflict (empresa_id, entidad_tipo, entidad_origen_id, version)
    do update set
      definicion = excluded.definicion,
      nombre = excluded.nombre,
      estado = 'PUBLICADO',
      es_actual = true,
      activo = true,
      deleted_at = null,
      updated_at = now();

    v_result := jsonb_build_object(
      'publicado', true,
      'borrador_id', v_draft.id,
      'entidad_tipo', v_draft.entidad_tipo,
      'entidad_id', v_code,
      'version_configuracion_id', v_version.id,
      'version', v_version.version,
      'published_at', now()
    );
  exception when others then
    perform set_config('appgt.skip_auto_fields', 'off', true);
    update public."BORRADORES_CONFIGURACION_APPGT" set
      estado = 'ERROR_PUBLICACION',
      resultado_publicacion = jsonb_build_object(
        'publicado', false, 'error', sqlerrm, 'sqlstate', sqlstate
      ),
      updated_by = auth.uid(), updated_at = now(),
      lock_version = lock_version + 1
    where id = v_draft.id;
    insert into public."AUDITORIA_CONFIGURACION_APPGT" (
      empresa_id, borrador_id, entidad_tipo, entidad_id, accion,
      estado_anterior, estado_nuevo, metadata, user_id
    ) values (
      v_empresa_id, v_draft.id, v_draft.entidad_tipo, v_code,
      'ERROR_PUBLICACION', v_draft.estado, 'ERROR_PUBLICACION',
      jsonb_build_object('error', sqlerrm, 'sqlstate', sqlstate), auth.uid()
    );
    return jsonb_build_object(
      'publicado', false, 'borrador_id', v_draft.id,
      'error', sqlerrm, 'sqlstate', sqlstate
    );
  end;

  update public."BORRADORES_CONFIGURACION_APPGT" set
    estado = 'PUBLICADO', resultado_publicacion = v_result,
    version_configuracion_id = v_version.id,
    published_at = now(), updated_by = auth.uid(), updated_at = now(),
    lock_version = lock_version + 1
  where id = v_draft.id;

  insert into public."AUDITORIA_CONFIGURACION_APPGT" (
    empresa_id, borrador_id, entidad_tipo, entidad_id, accion,
    estado_anterior, estado_nuevo, datos_despues, metadata, user_id
  ) values (
    v_empresa_id, v_draft.id, v_draft.entidad_tipo, v_code,
    'PUBLICAR', v_draft.estado, 'PUBLICADO', v_payload,
    v_result, auth.uid()
  );

  return v_result;
end
$$;

alter table public."BORRADORES_CONFIGURACION_APPGT" enable row level security;
alter table public."MIGRACIONES_CONFIGURACION_APPGT" enable row level security;
alter table public."AUDITORIA_CONFIGURACION_APPGT" enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array[
    'BORRADORES_CONFIGURACION_APPGT',
    'MIGRACIONES_CONFIGURACION_APPGT',
    'AUDITORIA_CONFIGURACION_APPGT'
  ] loop
    execute format('drop policy if exists constructor_select on public.%I', t);
    execute format(
      'create policy constructor_select on public.%I for select to authenticated
       using (public.appgt_puede_gestionar_configuracion(empresa_id))',
      t
    );
    execute format('drop policy if exists constructor_admin on public.%I', t);
    execute format(
      'create policy constructor_admin on public.%I for all to authenticated
       using (public.appgt_es_admin_empresa(empresa_id))
       with check (public.appgt_es_admin_empresa(empresa_id))',
      t
    );
  end loop;
end
$$;

drop trigger if exists appgt_set_updated_at_trigger
  on public."BORRADORES_CONFIGURACION_APPGT";
create trigger appgt_set_updated_at_trigger
before update on public."BORRADORES_CONFIGURACION_APPGT"
for each row execute function public.appgt_set_updated_at();
drop trigger if exists appgt_set_updated_at_trigger
  on public."MIGRACIONES_CONFIGURACION_APPGT";
create trigger appgt_set_updated_at_trigger
before update on public."MIGRACIONES_CONFIGURACION_APPGT"
for each row execute function public.appgt_set_updated_at();

revoke all on function public.appgt_empresa_actual_id() from public, anon;
revoke all on function public.appgt_puede_gestionar_configuracion(uuid) from public, anon;
revoke all on function public.appgt_jsonb_bool(jsonb, text, boolean) from public, anon;
revoke all on function public.appgt_contexto_constructor_v1() from public, anon;
revoke all on function public.appgt_listar_plantillas_configuracion(text, text, text, text, integer, integer) from public, anon;
revoke all on function public.appgt_listar_borradores_configuracion(text, text) from public, anon;
revoke all on function public.appgt_guardar_borrador_configuracion(text, jsonb, uuid, uuid, integer) from public, anon;
revoke all on function public.appgt_clonar_plantilla_configuracion(uuid, jsonb) from public, anon;
revoke all on function public.appgt_validar_borrador_configuracion(uuid) from public, anon;
revoke all on function public.appgt_publicar_borrador_configuracion(uuid, text) from public, anon;

grant execute on function public.appgt_empresa_actual_id() to authenticated;
grant execute on function public.appgt_puede_gestionar_configuracion(uuid) to authenticated;
grant execute on function public.appgt_contexto_constructor_v1() to authenticated;
grant execute on function public.appgt_listar_plantillas_configuracion(text, text, text, text, integer, integer) to authenticated;
grant execute on function public.appgt_listar_borradores_configuracion(text, text) to authenticated;
grant execute on function public.appgt_guardar_borrador_configuracion(text, jsonb, uuid, uuid, integer) to authenticated;
grant execute on function public.appgt_clonar_plantilla_configuracion(uuid, jsonb) to authenticated;
grant execute on function public.appgt_validar_borrador_configuracion(uuid) to authenticated;
grant execute on function public.appgt_publicar_borrador_configuracion(uuid, text) to authenticated;

-- Supabase puede aplicar privilegios predeterminados a tablas nuevas. Se
-- revocan explícitamente: Flutter solo lee estas tablas y toda escritura debe
-- cruzar las funciones security definer auditadas.
revoke all on table public."BORRADORES_CONFIGURACION_APPGT"
  from anon, authenticated;
revoke all on table public."MIGRACIONES_CONFIGURACION_APPGT"
  from anon, authenticated;
revoke all on table public."AUDITORIA_CONFIGURACION_APPGT"
  from anon, authenticated;
revoke all on table public."PAQUETES_PLANTILLA_APPGT"
  from anon, authenticated;
revoke all on table public."PLANTILLAS_CONFIGURACION_APPGT"
  from anon, authenticated;

grant select on table public."BORRADORES_CONFIGURACION_APPGT" to authenticated;
grant select on table public."MIGRACIONES_CONFIGURACION_APPGT" to authenticated;
grant select on table public."AUDITORIA_CONFIGURACION_APPGT" to authenticated;
grant select on table public."PAQUETES_PLANTILLA_APPGT" to authenticated;
grant select on table public."PLANTILLAS_CONFIGURACION_APPGT" to authenticated;

do $$
begin
  if exists (
    select 1 from pg_event_trigger
    where evtname = 'trg_appgt_auto_insertar_campos'
  ) then
    execute 'alter event trigger trg_appgt_auto_insertar_campos enable';
  end if;
end
$$;

commit;
