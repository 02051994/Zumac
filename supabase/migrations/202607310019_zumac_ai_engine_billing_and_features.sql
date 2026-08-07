-- Zumac AI Engine: habilitación multiempresa, planes avanzados y consumo
-- individual de OpenAI. El motor gratuito propio no consume estos créditos.

begin;

alter table public."EMPRESAS_APPGT"
  add column if not exists habilitar_zumac_consultor boolean not null default false,
  add column if not exists habilitar_zumac_creator boolean not null default false,
  add column if not exists habilitar_ia_avanzada boolean not null default false;

-- Conserva las herramientas visibles para las empresas que ya existían. Las
-- empresas creadas después de esta migración requieren autorización explícita.
update public."EMPRESAS_APPGT"
set habilitar_zumac_consultor = true,
    habilitar_zumac_creator = true,
    habilitar_ia_avanzada = true,
    updated_at = now();

create table if not exists public."PLANES_IA_APPGT" (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  descripcion text not null default '',
  periodo text not null check (periodo in ('MENSUAL', 'ANUAL')),
  duracion_dias integer not null check (duracion_dias > 0),
  presupuesto_proveedor_usd numeric(14,6) not null
    check (presupuesto_proveedor_usd > 0),
  multiplicador_precio numeric(8,3) not null default 3
    check (multiplicador_precio >= 1),
  precio_usd numeric(14,2) not null check (precio_usd > 0),
  creditos_ia bigint not null check (creditos_ia > 0),
  activo boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint planes_ia_precio_margen_check check (
    precio_usd = round(presupuesto_proveedor_usd * multiplicador_precio, 2)
  )
);

comment on column public."PLANES_IA_APPGT".creditos_ia is
  'Créditos comerciales. 1 crédito equivale a USD 0.001 de costo real del proveedor.';

insert into public."PLANES_IA_APPGT" (
  codigo, nombre, descripcion, periodo, duracion_dias,
  presupuesto_proveedor_usd, multiplicador_precio, precio_usd, creditos_ia
) values
  (
    'AVANZADO_MENSUAL', 'IA avanzada mensual',
    'OpenAI opcional para documentos que requieren mayor capacidad.',
    'MENSUAL', 31, 10, 3, 30, 10000
  ),
  (
    'AVANZADO_ANUAL', 'IA avanzada anual',
    'Doce meses de acceso a OpenAI opcional con crédito anual.',
    'ANUAL', 366, 120, 3, 360, 120000
  )
on conflict (codigo) do update
set nombre = excluded.nombre,
    descripcion = excluded.descripcion,
    periodo = excluded.periodo,
    duracion_dias = excluded.duracion_dias,
    presupuesto_proveedor_usd = excluded.presupuesto_proveedor_usd,
    multiplicador_precio = excluded.multiplicador_precio,
    precio_usd = excluded.precio_usd,
    creditos_ia = excluded.creditos_ia,
    updated_at = now();

create table if not exists public."TARIFAS_MODELOS_IA_APPGT" (
  id uuid primary key default gen_random_uuid(),
  proveedor text not null,
  modelo text not null,
  entrada_usd_millon numeric(14,6) not null check (entrada_usd_millon >= 0),
  entrada_cache_usd_millon numeric(14,6) not null
    check (entrada_cache_usd_millon >= 0),
  salida_usd_millon numeric(14,6) not null check (salida_usd_millon >= 0),
  activo boolean not null default true,
  vigente_desde timestamptz not null default now(),
  vigente_hasta timestamptz,
  created_at timestamptz not null default now(),
  unique (proveedor, modelo, vigente_desde)
);

insert into public."TARIFAS_MODELOS_IA_APPGT" (
  proveedor, modelo, entrada_usd_millon,
  entrada_cache_usd_millon, salida_usd_millon, vigente_desde
) values ('OPENAI', 'gpt-5.6-sol', 5, 0.5, 30, '2026-07-01T00:00:00Z')
on conflict (proveedor, modelo, vigente_desde) do update
set entrada_usd_millon = excluded.entrada_usd_millon,
    entrada_cache_usd_millon = excluded.entrada_cache_usd_millon,
    salida_usd_millon = excluded.salida_usd_millon,
    activo = true;

create table if not exists public."SOLICITUDES_PLAN_IA_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public."PLANES_IA_APPGT"(id),
  estado text not null default 'PENDIENTE_PAGO'
    check (estado in ('PENDIENTE_PAGO', 'PAGADA', 'CANCELADA', 'VENCIDA')),
  monto_usd numeric(14,2) not null check (monto_usd > 0),
  moneda text not null default 'USD' check (moneda = 'USD'),
  proveedor_pago text,
  referencia_pago text,
  url_pago text,
  metadata jsonb not null default '{}'::jsonb,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists uq_solicitud_plan_ia_pendiente_usuario
  on public."SOLICITUDES_PLAN_IA_APPGT" (empresa_id, user_id)
  where estado = 'PENDIENTE_PAGO';

create table if not exists public."SUSCRIPCIONES_IA_USUARIO_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public."PLANES_IA_APPGT"(id),
  solicitud_id uuid references public."SOLICITUDES_PLAN_IA_APPGT"(id),
  estado text not null default 'ACTIVA'
    check (estado in ('ACTIVA', 'AGOTADA', 'EXPIRADA', 'CANCELADA')),
  vigente_desde timestamptz not null default now(),
  vigente_hasta timestamptz not null,
  saldo_inicial_microusd bigint not null check (saldo_inicial_microusd > 0),
  consumo_microusd bigint not null default 0 check (consumo_microusd >= 0),
  input_tokens_consumidos bigint not null default 0,
  cached_input_tokens_consumidos bigint not null default 0,
  output_tokens_consumidos bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists uq_suscripcion_ia_activa_usuario
  on public."SUSCRIPCIONES_IA_USUARIO_APPGT" (empresa_id, user_id)
  where estado = 'ACTIVA';

create index if not exists idx_suscripcion_ia_usuario
  on public."SUSCRIPCIONES_IA_USUARIO_APPGT"
  (empresa_id, user_id, vigente_hasta desc);

create table if not exists public."CONSUMOS_IA_USUARIO_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  suscripcion_id uuid not null
    references public."SUSCRIPCIONES_IA_USUARIO_APPGT"(id),
  importacion_id uuid references public."IMPORTACIONES_FORMATO_IA_APPGT"(id),
  proveedor text not null,
  modelo text not null,
  request_id text not null,
  input_tokens bigint not null default 0,
  cached_input_tokens bigint not null default 0,
  output_tokens bigint not null default 0,
  costo_proveedor_microusd bigint not null check (costo_proveedor_microusd >= 0),
  valor_cliente_microusd bigint not null check (valor_cliente_microusd >= 0),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (proveedor, request_id)
);

create index if not exists idx_consumos_ia_usuario
  on public."CONSUMOS_IA_USUARIO_APPGT"
  (empresa_id, user_id, created_at desc);

alter table public."PLANES_IA_APPGT" enable row level security;
alter table public."TARIFAS_MODELOS_IA_APPGT" enable row level security;
alter table public."SOLICITUDES_PLAN_IA_APPGT" enable row level security;
alter table public."SUSCRIPCIONES_IA_USUARIO_APPGT" enable row level security;
alter table public."CONSUMOS_IA_USUARIO_APPGT" enable row level security;

drop policy if exists planes_ia_lectura on public."PLANES_IA_APPGT";
create policy planes_ia_lectura on public."PLANES_IA_APPGT"
for select to authenticated using (activo);

drop policy if exists solicitudes_ia_lectura on public."SOLICITUDES_PLAN_IA_APPGT";
create policy solicitudes_ia_lectura on public."SOLICITUDES_PLAN_IA_APPGT"
for select to authenticated
using (user_id = auth.uid() or public.appgt_es_admin_empresa(empresa_id));

drop policy if exists suscripciones_ia_lectura on public."SUSCRIPCIONES_IA_USUARIO_APPGT";
create policy suscripciones_ia_lectura on public."SUSCRIPCIONES_IA_USUARIO_APPGT"
for select to authenticated
using (user_id = auth.uid() or public.appgt_es_admin_empresa(empresa_id));

drop policy if exists consumos_ia_lectura on public."CONSUMOS_IA_USUARIO_APPGT";
create policy consumos_ia_lectura on public."CONSUMOS_IA_USUARIO_APPGT"
for select to authenticated
using (user_id = auth.uid() or public.appgt_es_admin_empresa(empresa_id));

create or replace function public.appgt_empresa_funcionalidad_habilitada(
  p_empresa_id uuid,
  p_codigo text
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case upper(btrim(coalesce(p_codigo, '')))
    when 'ZUMAC_CONSULTOR' then e.habilitar_zumac_consultor
    when 'ZUMAC_CREATOR' then e.habilitar_zumac_creator
    when 'IA_AVANZADA' then e.habilitar_ia_avanzada
    else false
  end
  from public."EMPRESAS_APPGT" e
  where e.id = p_empresa_id and e.activo;
$$;

revoke all on function public.appgt_empresa_funcionalidad_habilitada(uuid, text)
  from public, anon;
grant execute on function public.appgt_empresa_funcionalidad_habilitada(uuid, text)
  to authenticated, service_role;

create or replace function public.appgt_contexto_producto_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_empresa public."EMPRESAS_APPGT"%rowtype;
  v_suscripcion jsonb;
begin
  if v_user_id is null or v_empresa_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_empresa
  from public."EMPRESAS_APPGT"
  where id = v_empresa_id and activo;

  select jsonb_build_object(
    'id', s.id,
    'plan_codigo', p.codigo,
    'plan_nombre', p.nombre,
    'periodo', p.periodo,
    'estado', case
      when s.vigente_hasta <= now() then 'EXPIRADA'
      when s.consumo_microusd >= s.saldo_inicial_microusd then 'AGOTADA'
      else s.estado
    end,
    'vigente_desde', s.vigente_desde,
    'vigente_hasta', s.vigente_hasta,
    'creditos_iniciales', floor(s.saldo_inicial_microusd / 1000.0),
    'creditos_consumidos', ceil(s.consumo_microusd / 1000.0),
    'creditos_restantes', greatest(
      0, floor((s.saldo_inicial_microusd - s.consumo_microusd) / 1000.0)
    ),
    'input_tokens_consumidos', s.input_tokens_consumidos,
    'cached_input_tokens_consumidos', s.cached_input_tokens_consumidos,
    'output_tokens_consumidos', s.output_tokens_consumidos
  ) into v_suscripcion
  from public."SUSCRIPCIONES_IA_USUARIO_APPGT" s
  join public."PLANES_IA_APPGT" p on p.id = s.plan_id
  where s.empresa_id = v_empresa_id
    and s.user_id = v_user_id
    and s.estado in ('ACTIVA', 'AGOTADA')
  order by s.vigente_hasta desc
  limit 1;

  return jsonb_build_object(
    'empresa_id', v_empresa_id,
    'empresa_nombre', v_empresa.nombre,
    'zumac_consultor_habilitado', v_empresa.habilitar_zumac_consultor,
    'zumac_creator_habilitado', v_empresa.habilitar_zumac_creator,
    'ia_avanzada_habilitada', v_empresa.habilitar_ia_avanzada,
    'planes_ia', coalesce((
      select jsonb_agg(jsonb_build_object(
        'codigo', p.codigo,
        'nombre', p.nombre,
        'descripcion', p.descripcion,
        'periodo', p.periodo,
        'precio_usd', p.precio_usd,
        'creditos_incluidos', p.creditos_ia
      ) order by p.duracion_dias)
      from public."PLANES_IA_APPGT" p where p.activo
    ), '[]'::jsonb),
    'suscripcion_ia', coalesce(v_suscripcion, '{}'::jsonb),
    'solicitud_pendiente', coalesce((
      select jsonb_build_object(
        'id', q.id,
        'plan_codigo', p.codigo,
        'plan_nombre', p.nombre,
        'estado', q.estado,
        'monto_usd', q.monto_usd,
        'moneda', q.moneda,
        'url_pago', q.url_pago,
        'created_at', q.created_at
      )
      from public."SOLICITUDES_PLAN_IA_APPGT" q
      join public."PLANES_IA_APPGT" p on p.id = q.plan_id
      where q.empresa_id = v_empresa_id
        and q.user_id = v_user_id
        and q.estado = 'PENDIENTE_PAGO'
      order by q.created_at desc limit 1
    ), '{}'::jsonb)
  );
end
$$;

create or replace function public.appgt_solicitar_plan_ia_v1(p_plan_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_plan public."PLANES_IA_APPGT"%rowtype;
  v_row public."SOLICITUDES_PLAN_IA_APPGT"%rowtype;
begin
  if v_user_id is null or v_empresa_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if not public.appgt_empresa_funcionalidad_habilitada(v_empresa_id, 'IA_AVANZADA') then
    raise exception 'La IA avanzada no está habilitada para esta empresa.'
      using errcode = '42501';
  end if;

  select * into v_plan from public."PLANES_IA_APPGT"
  where codigo = upper(btrim(p_plan_codigo)) and activo;
  if v_plan.id is null then
    raise exception 'Plan de IA no disponible.' using errcode = '22023';
  end if;

  select * into v_row from public."SOLICITUDES_PLAN_IA_APPGT"
  where empresa_id = v_empresa_id and user_id = v_user_id
    and estado = 'PENDIENTE_PAGO'
  for update;

  if v_row.id is null then
    insert into public."SOLICITUDES_PLAN_IA_APPGT" (
      empresa_id, user_id, plan_id, monto_usd, moneda
    ) values (v_empresa_id, v_user_id, v_plan.id, v_plan.precio_usd, 'USD')
    returning * into v_row;
  elsif v_row.plan_id <> v_plan.id then
    update public."SOLICITUDES_PLAN_IA_APPGT"
    set plan_id = v_plan.id,
        monto_usd = v_plan.precio_usd,
        updated_at = now()
    where id = v_row.id returning * into v_row;
  end if;

  return jsonb_build_object(
    'id', v_row.id,
    'estado', v_row.estado,
    'plan_codigo', v_plan.codigo,
    'plan_nombre', v_plan.nombre,
    'monto_usd', v_row.monto_usd,
    'moneda', v_row.moneda,
    'url_pago', v_row.url_pago,
    'mensaje', 'Solicitud creada. El acceso se activará al confirmar el pago.'
  );
end
$$;

create or replace function public.appgt_preautorizar_consumo_ia_v1(
  p_importacion_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_s public."SUSCRIPCIONES_IA_USUARIO_APPGT"%rowtype;
begin
  if v_user_id is null or v_empresa_id is null then
    return jsonb_build_object('autorizado', false, 'codigo', 'AUTH_REQUIRED');
  end if;
  if not public.appgt_empresa_funcionalidad_habilitada(v_empresa_id, 'ZUMAC_CREATOR')
     or not public.appgt_empresa_funcionalidad_habilitada(v_empresa_id, 'IA_AVANZADA') then
    return jsonb_build_object(
      'autorizado', false, 'codigo', 'AI_ADVANCED_DISABLED',
      'mensaje', 'La IA avanzada no está habilitada para esta empresa.'
    );
  end if;
  if p_importacion_id is not null and not exists (
    select 1 from public."IMPORTACIONES_FORMATO_IA_APPGT" i
    where i.id = p_importacion_id and i.empresa_id = v_empresa_id
      and i.created_by = v_user_id
  ) then
    return jsonb_build_object(
      'autorizado', false, 'codigo', 'IMPORT_NOT_ALLOWED',
      'mensaje', 'La importación no pertenece al usuario.'
    );
  end if;

  update public."SUSCRIPCIONES_IA_USUARIO_APPGT"
  set estado = 'EXPIRADA', updated_at = now()
  where empresa_id = v_empresa_id and user_id = v_user_id
    and estado = 'ACTIVA' and vigente_hasta <= now();

  select * into v_s
  from public."SUSCRIPCIONES_IA_USUARIO_APPGT"
  where empresa_id = v_empresa_id and user_id = v_user_id
    and estado = 'ACTIVA' and vigente_hasta > now()
  order by vigente_hasta desc limit 1;

  if v_s.id is null then
    return jsonb_build_object(
      'autorizado', false, 'codigo', 'AI_PLAN_REQUIRED',
      'mensaje', 'Necesitas un plan avanzado mensual o anual.'
    );
  end if;
  if v_s.consumo_microusd >= v_s.saldo_inicial_microusd then
    update public."SUSCRIPCIONES_IA_USUARIO_APPGT"
    set estado = 'AGOTADA', updated_at = now() where id = v_s.id;
    return jsonb_build_object(
      'autorizado', false, 'codigo', 'AI_CREDITS_EXHAUSTED',
      'mensaje', '¿Ya consumiste todos los tokens, deseas más?'
    );
  end if;

  return jsonb_build_object(
    'autorizado', true,
    'suscripcion_id', v_s.id,
    'creditos_restantes', floor(
      (v_s.saldo_inicial_microusd - v_s.consumo_microusd) / 1000.0
    )
  );
end
$$;

create or replace function public.appgt_registrar_consumo_ia_v1(
  p_empresa_id uuid,
  p_user_id uuid,
  p_importacion_id uuid,
  p_proveedor text,
  p_modelo text,
  p_request_id text,
  p_input_tokens bigint,
  p_cached_input_tokens bigint,
  p_output_tokens bigint,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_s public."SUSCRIPCIONES_IA_USUARIO_APPGT"%rowtype;
  v_t public."TARIFAS_MODELOS_IA_APPGT"%rowtype;
  v_uncached bigint;
  v_cost bigint;
  v_existing public."CONSUMOS_IA_USUARIO_APPGT"%rowtype;
begin
  if not exists (
    select 1 from public."USUARIOS_EMPRESAS_APPGT" ue
    where ue.user_id = p_user_id and ue.empresa_id = p_empresa_id and ue.activo
  ) then
    raise exception 'El usuario no pertenece a la empresa.' using errcode = '42501';
  end if;

  select * into v_existing from public."CONSUMOS_IA_USUARIO_APPGT"
  where proveedor = upper(btrim(p_proveedor)) and request_id = p_request_id;
  if v_existing.id is not null then
    return jsonb_build_object(
      'registrado', true,
      'repetido', true,
      'costo_microusd', v_existing.costo_proveedor_microusd
    );
  end if;

  select * into v_s from public."SUSCRIPCIONES_IA_USUARIO_APPGT"
  where empresa_id = p_empresa_id and user_id = p_user_id
    and estado = 'ACTIVA' and vigente_hasta > now()
  order by vigente_hasta desc limit 1 for update;
  if v_s.id is null then
    raise exception 'No existe una suscripción activa.' using errcode = '42501';
  end if;

  select * into v_t from public."TARIFAS_MODELOS_IA_APPGT"
  where proveedor = upper(btrim(p_proveedor)) and modelo = p_modelo and activo
    and vigente_desde <= now()
    and (vigente_hasta is null or vigente_hasta > now())
  order by vigente_desde desc limit 1;
  if v_t.id is null then
    raise exception 'No existe tarifa vigente para el modelo %.', p_modelo
      using errcode = '22023';
  end if;

  v_uncached := greatest(coalesce(p_input_tokens, 0) -
    greatest(coalesce(p_cached_input_tokens, 0), 0), 0);
  -- Al estar la tarifa expresada en USD por millón, tokens * tarifa produce
  -- directamente microdólares.
  v_cost := round(
    v_uncached * v_t.entrada_usd_millon +
    greatest(coalesce(p_cached_input_tokens, 0), 0) * v_t.entrada_cache_usd_millon +
    greatest(coalesce(p_output_tokens, 0), 0) * v_t.salida_usd_millon
  );

  insert into public."CONSUMOS_IA_USUARIO_APPGT" (
    empresa_id, user_id, suscripcion_id, importacion_id,
    proveedor, modelo, request_id, input_tokens, cached_input_tokens,
    output_tokens, costo_proveedor_microusd, valor_cliente_microusd, metadata
  ) values (
    p_empresa_id, p_user_id, v_s.id, p_importacion_id,
    upper(btrim(p_proveedor)), p_modelo, p_request_id,
    greatest(coalesce(p_input_tokens, 0), 0),
    greatest(coalesce(p_cached_input_tokens, 0), 0),
    greatest(coalesce(p_output_tokens, 0), 0),
    v_cost, v_cost * 3, coalesce(p_metadata, '{}'::jsonb)
  );

  update public."SUSCRIPCIONES_IA_USUARIO_APPGT"
  set consumo_microusd = consumo_microusd + v_cost,
      input_tokens_consumidos = input_tokens_consumidos +
        greatest(coalesce(p_input_tokens, 0), 0),
      cached_input_tokens_consumidos = cached_input_tokens_consumidos +
        greatest(coalesce(p_cached_input_tokens, 0), 0),
      output_tokens_consumidos = output_tokens_consumidos +
        greatest(coalesce(p_output_tokens, 0), 0),
      estado = case
        when consumo_microusd + v_cost >= saldo_inicial_microusd
          then 'AGOTADA' else estado end,
      updated_at = now()
  where id = v_s.id
  returning * into v_s;

  return jsonb_build_object(
    'registrado', true,
    'costo_microusd', v_cost,
    'creditos_consumidos', ceil(v_cost / 1000.0),
    'creditos_restantes', greatest(
      0, floor((v_s.saldo_inicial_microusd - v_s.consumo_microusd) / 1000.0)
    ),
    'agotado', v_s.estado = 'AGOTADA'
  );
end
$$;

create or replace function public.appgt_confirmar_pago_plan_ia_v1(
  p_solicitud_id uuid,
  p_referencia_pago text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_q public."SOLICITUDES_PLAN_IA_APPGT"%rowtype;
  v_p public."PLANES_IA_APPGT"%rowtype;
  v_s public."SUSCRIPCIONES_IA_USUARIO_APPGT"%rowtype;
  v_credit_microusd bigint;
begin
  select * into v_q from public."SOLICITUDES_PLAN_IA_APPGT"
  where id = p_solicitud_id for update;
  if v_q.id is null or v_q.estado <> 'PENDIENTE_PAGO' then
    raise exception 'Solicitud de pago no disponible.' using errcode = '22023';
  end if;
  select * into v_p from public."PLANES_IA_APPGT" where id = v_q.plan_id and activo;
  if v_p.id is null then
    raise exception 'El plan asociado ya no está disponible.' using errcode = '22023';
  end if;
  v_credit_microusd := round(v_p.presupuesto_proveedor_usd * 1000000);

  update public."SUSCRIPCIONES_IA_USUARIO_APPGT"
  set estado = 'EXPIRADA', updated_at = now()
  where empresa_id = v_q.empresa_id and user_id = v_q.user_id
    and estado = 'ACTIVA' and vigente_hasta <= now();

  select * into v_s from public."SUSCRIPCIONES_IA_USUARIO_APPGT"
  where empresa_id = v_q.empresa_id and user_id = v_q.user_id
    and estado = 'ACTIVA' and vigente_hasta > now()
  for update;

  if v_s.id is null then
    insert into public."SUSCRIPCIONES_IA_USUARIO_APPGT" (
      empresa_id, user_id, plan_id, solicitud_id, estado,
      vigente_desde, vigente_hasta, saldo_inicial_microusd
    ) values (
      v_q.empresa_id, v_q.user_id, v_p.id, v_q.id, 'ACTIVA', now(),
      now() + make_interval(days => v_p.duracion_dias), v_credit_microusd
    ) returning * into v_s;
  else
    update public."SUSCRIPCIONES_IA_USUARIO_APPGT"
    set plan_id = v_p.id,
        solicitud_id = v_q.id,
        saldo_inicial_microusd = saldo_inicial_microusd + v_credit_microusd,
        vigente_hasta = vigente_hasta + make_interval(days => v_p.duracion_dias),
        updated_at = now()
    where id = v_s.id returning * into v_s;
  end if;

  update public."SOLICITUDES_PLAN_IA_APPGT"
  set estado = 'PAGADA',
      referencia_pago = nullif(btrim(p_referencia_pago), ''),
      paid_at = now(), updated_at = now()
  where id = v_q.id;

  return jsonb_build_object(
    'suscripcion_id', v_s.id,
    'estado', v_s.estado,
    'vigente_hasta', v_s.vigente_hasta,
    'creditos_restantes', floor(
      (v_s.saldo_inicial_microusd - v_s.consumo_microusd) / 1000.0
    )
  );
end
$$;

revoke all on function public.appgt_contexto_producto_v1() from public, anon;
revoke all on function public.appgt_solicitar_plan_ia_v1(text) from public, anon;
revoke all on function public.appgt_preautorizar_consumo_ia_v1(uuid) from public, anon;
revoke all on function public.appgt_registrar_consumo_ia_v1(
  uuid, uuid, uuid, text, text, text, bigint, bigint, bigint, jsonb
) from public, anon, authenticated;
revoke all on function public.appgt_confirmar_pago_plan_ia_v1(uuid, text)
  from public, anon, authenticated;

grant execute on function public.appgt_contexto_producto_v1() to authenticated;
grant execute on function public.appgt_solicitar_plan_ia_v1(text) to authenticated;
grant execute on function public.appgt_preautorizar_consumo_ia_v1(uuid) to authenticated;
grant execute on function public.appgt_registrar_consumo_ia_v1(
  uuid, uuid, uuid, text, text, text, bigint, bigint, bigint, jsonb
) to service_role;
grant execute on function public.appgt_confirmar_pago_plan_ia_v1(uuid, text)
  to service_role;

-- Las tablas de conocimiento solo son visibles si la empresa tiene Consultor.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'FUENTES_CONOCIMIENTO_APPGT',
    'BASE_CONOCIMIENTO_APPGT',
    'RELACIONES_CONOCIMIENTO_APPGT',
    'CONVERSACIONES_CONSULTOR_APPGT',
    'MENSAJES_CONSULTOR_APPGT'
  ] loop
    if to_regclass(format('public.%I', v_table)) is null then continue; end if;
    execute format('drop policy if exists consultant_feature_scope on public.%I', v_table);
    execute format(
      'create policy consultant_feature_scope on public.%I as restrictive for select to authenticated using (public.appgt_empresa_funcionalidad_habilitada(empresa_id, %L))',
      v_table, 'ZUMAC_CONSULTOR'
    );
  end loop;
end
$$;

drop policy if exists creator_feature_scope
  on public."IMPORTACIONES_FORMATO_IA_APPGT";
create policy creator_feature_scope
on public."IMPORTACIONES_FORMATO_IA_APPGT"
as restrictive for all to authenticated
using (public.appgt_empresa_funcionalidad_habilitada(empresa_id, 'ZUMAC_CREATOR'))
with check (public.appgt_empresa_funcionalidad_habilitada(empresa_id, 'ZUMAC_CREATOR'));

commit;
