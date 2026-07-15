begin;

-- Matrices declarativas que la arquitectura maestra requiere y que antes
-- estaban mezcladas dentro de MATRIZ_CAMPOS_FORMATO_APPGT.
create table if not exists public."RUBROS_APPGT" (
  id text primary key default gen_random_uuid()::text,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  codigo text not null,
  nombre text not null,
  descripcion text,
  icono text,
  color text,
  orden integer not null default 0,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (empresa_id, codigo)
);

create table if not exists public."MATRIZ_DROPDOWNS_APPGT" (
  id text primary key default gen_random_uuid()::text,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  codigo text not null,
  campo_id text,
  campo_origen_id text,
  tabla_origen text,
  campo_valor text,
  campo_etiqueta text,
  filtro_json jsonb not null default '{}'::jsonb,
  permite_multiple boolean not null default false,
  orden integer not null default 0,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (empresa_id, codigo)
);

create table if not exists public."MATRIZ_VALIDACIONES_APPGT" (
  id text primary key default gen_random_uuid()::text,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  codigo text not null,
  formato_id text,
  campo_id text,
  tipo_validacion text not null,
  expresion text,
  mensaje_error text,
  bloquea_guardado boolean not null default true,
  orden integer not null default 0,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (empresa_id, codigo)
);

create table if not exists public."MATRIZ_CONDICIONES_APPGT" (
  id text primary key default gen_random_uuid()::text,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  codigo text not null,
  formato_id text,
  campo_id text,
  campo_dependencia_id text,
  operador text not null default 'EXPRESION',
  valor_comparacion jsonb,
  expresion text,
  accion text not null default 'MOSTRAR',
  orden integer not null default 0,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (empresa_id, codigo)
);

create table if not exists public."MATRIZ_FORMULAS_APPGT" (
  id text primary key default gen_random_uuid()::text,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  codigo text not null,
  formato_id text,
  campo_id text,
  expresion text not null,
  lenguaje text not null default 'ZUMAC_EXPR',
  recalcular_al_cambiar boolean not null default true,
  orden integer not null default 0,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (empresa_id, codigo)
);

create index if not exists idx_rubros_appgt_empresa on public."RUBROS_APPGT" (empresa_id, activo, orden);
create index if not exists idx_dropdowns_appgt_campo on public."MATRIZ_DROPDOWNS_APPGT" (empresa_id, campo_id, activo);
create index if not exists idx_validaciones_appgt_campo on public."MATRIZ_VALIDACIONES_APPGT" (empresa_id, campo_id, activo, orden);
create index if not exists idx_condiciones_appgt_campo on public."MATRIZ_CONDICIONES_APPGT" (empresa_id, campo_id, activo, orden);
create index if not exists idx_formulas_appgt_campo on public."MATRIZ_FORMULAS_APPGT" (empresa_id, campo_id, activo, orden);

-- Clasificacion declarativa de navegacion. Los ids antiguos quedan solo como
-- migracion de datos; Flutter leera tipo_contenido a partir de ahora.
alter table public."MATRIZ_SECCIONES_APPGT"
  add column if not exists rubro_id text references public."RUBROS_APPGT"(id),
  add column if not exists tipo_contenido text,
  add column if not exists ruta_flutter text;

insert into public."RUBROS_APPGT" (id, empresa_id, codigo, nombre, descripcion, orden)
values (
  'rubro_general_zumac',
  '00000000-0000-0000-0000-000000000001'::uuid,
  'GENERAL',
  'General',
  'Rubro inicial para conservar la configuracion productiva existente.',
  0
)
on conflict (id) do update set
  nombre = excluded.nombre,
  updated_at = now(),
  deleted_at = null,
  activo = true;

update public."MATRIZ_SECCIONES_APPGT"
set rubro_id = 'rubro_general_zumac'
where rubro_id is null;

update public."MATRIZ_SECCIONES_APPGT" s
set tipo_contenido = case
  when lower(btrim(s.id)) = 'reportes' then 'REPORTES'
  when lower(btrim(s.id)) = 'registros_pendientes' then 'VISTAS_DINAMICAS'
  when lower(btrim(s.id)) = 'registros_locales' then 'REGISTROS_LOCALES'
  when lower(btrim(s.id)) = 'inicio_gt' then 'INICIO'
  when exists (
    select 1 from public."MATRIZ_MODULOS_APPGT" m
    where lower(btrim(m.seccion)) = lower(btrim(s.id))
      and coalesce(m.activo, true)
  ) then 'FORMATOS'
  else 'GENERICO'
end
where nullif(btrim(s.tipo_contenido), '') is null;

alter table public."MATRIZ_SECCIONES_APPGT"
  alter column rubro_id set default 'rubro_general_zumac',
  alter column tipo_contenido set default 'GENERICO',
  alter column tipo_contenido set not null;

-- Compatibilidad: convertir reglas ya productivas en las nuevas matrices sin
-- borrar ni cambiar las columnas antiguas que consumen versiones previas.
insert into public."MATRIZ_DROPDOWNS_APPGT" (
  id, empresa_id, codigo, campo_id, campo_origen_id, orden, activo
)
select
  'legacy_dropdown_' || f.id,
  f.empresa_id,
  'LEGACY_DROPDOWN_' || f.id,
  f.id,
  nullif(btrim(f.id_campo_dropdown), ''),
  coalesce(f.orden, 0),
  coalesce(f.activo, true)
from public."MATRIZ_CAMPOS_FORMATO_APPGT" f
where nullif(btrim(f.id_campo_dropdown), '') is not null
on conflict (id) do update set
  campo_origen_id = excluded.campo_origen_id,
  orden = excluded.orden,
  activo = excluded.activo,
  updated_at = now();

insert into public."MATRIZ_FORMULAS_APPGT" (
  id, empresa_id, codigo, campo_id, expresion, orden, activo
)
select
  'legacy_formula_' || f.id,
  f.empresa_id,
  'LEGACY_FORMULA_' || f.id,
  f.id,
  btrim(f.formula_funcion),
  coalesce(f.orden, 0),
  coalesce(f.activo, true)
from public."MATRIZ_CAMPOS_FORMATO_APPGT" f
where nullif(btrim(f.formula_funcion), '') is not null
on conflict (id) do update set
  expresion = excluded.expresion,
  orden = excluded.orden,
  activo = excluded.activo,
  updated_at = now();

insert into public."MATRIZ_VALIDACIONES_APPGT" (
  id, empresa_id, codigo, campo_id, tipo_validacion, expresion,
  mensaje_error, orden, activo
)
select
  'legacy_required_' || f.id,
  f.empresa_id,
  'LEGACY_REQUIRED_' || f.id,
  f.id,
  'REQUERIDO',
  'true',
  'Campo obligatorio',
  coalesce(f.orden, 0),
  coalesce(f.activo, true)
from public."MATRIZ_CAMPOS_FORMATO_APPGT" f
where lower(btrim(coalesce(f.requerido, ''))) in
  ('true', 't', '1', 'si', 'si.', 'yes', 'x')
on conflict (id) do update set
  activo = excluded.activo,
  updated_at = now();

insert into public."MATRIZ_VALIDACIONES_APPGT" (
  id, empresa_id, codigo, campo_id, tipo_validacion, expresion,
  mensaje_error, orden, activo
)
select
  'legacy_range_' || f.id,
  f.empresa_id,
  'LEGACY_RANGE_' || f.id,
  f.id,
  'RANGO',
  btrim(f.rango_valor),
  'Valor fuera del rango permitido',
  coalesce(f.orden, 0) + 1,
  coalesce(f.activo, true)
from public."MATRIZ_CAMPOS_FORMATO_APPGT" f
where nullif(btrim(f.rango_valor), '') is not null
on conflict (id) do update set
  expresion = excluded.expresion,
  activo = excluded.activo,
  updated_at = now();

insert into public."MATRIZ_CONDICIONES_APPGT" (
  id, empresa_id, codigo, campo_id, expresion, accion, orden, activo
)
select
  'legacy_condition_' || f.id,
  f.empresa_id,
  'LEGACY_CONDITION_' || f.id,
  f.id,
  btrim(f.formato_condicional_campo),
  'FORMATO_CONDICIONAL',
  coalesce(f.orden, 0),
  coalesce(f.activo, true)
from public."MATRIZ_CAMPOS_FORMATO_APPGT" f
where nullif(btrim(f.formato_condicional_campo), '') is not null
on conflict (id) do update set
  expresion = excluded.expresion,
  activo = excluded.activo,
  updated_at = now();

create or replace function public.appgt_set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'RUBROS_APPGT',
    'MATRIZ_DROPDOWNS_APPGT',
    'MATRIZ_VALIDACIONES_APPGT',
    'MATRIZ_CONDICIONES_APPGT',
    'MATRIZ_FORMULAS_APPGT'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists tenant_scope on public.%I', t);
    execute format(
      'create policy tenant_scope on public.%I for all to authenticated using (public.appgt_puede_acceder_empresa(empresa_id)) with check (public.appgt_puede_acceder_empresa(empresa_id))',
      t
    );
    execute format('drop trigger if exists appgt_set_updated_at_trigger on public.%I', t);
    execute format(
      'create trigger appgt_set_updated_at_trigger before update on public.%I for each row execute function public.appgt_set_updated_at()',
      t
    );
  end loop;
end
$$;

-- Conservar la funcion v2 original como nucleo y enriquecer su respuesta sin
-- duplicar la logica estable de modulos, formatos, campos y permisos.
do $$
begin
  if to_regprocedure('public.appgt_bootstrap_offline_data_v2_core(timestamp with time zone)') is null then
    alter function public.appgt_bootstrap_offline_data_v2(timestamptz)
      rename to appgt_bootstrap_offline_data_v2_core;
  end if;
end
$$;

create or replace function public.appgt_configuration_matrices_v1(
  p_since timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_empresa_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select ue.empresa_id into v_empresa_id
  from public."USUARIOS_EMPRESAS_APPGT" ue
  where ue.user_id = v_user_id and ue.activo
  order by ue.es_predeterminada desc, ue.created_at
  limit 1;

  if v_empresa_id is null then
    raise exception 'user has no active company' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'rubros', coalesce((select jsonb_agg(to_jsonb(x)) from public."RUBROS_APPGT" x where x.empresa_id = v_empresa_id and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)), '[]'::jsonb),
    'dropdowns', coalesce((select jsonb_agg(to_jsonb(x)) from public."MATRIZ_DROPDOWNS_APPGT" x where x.empresa_id = v_empresa_id and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)), '[]'::jsonb),
    'validations', coalesce((select jsonb_agg(to_jsonb(x)) from public."MATRIZ_VALIDACIONES_APPGT" x where x.empresa_id = v_empresa_id and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)), '[]'::jsonb),
    'conditions', coalesce((select jsonb_agg(to_jsonb(x)) from public."MATRIZ_CONDICIONES_APPGT" x where x.empresa_id = v_empresa_id and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)), '[]'::jsonb),
    'formulas', coalesce((select jsonb_agg(to_jsonb(x)) from public."MATRIZ_FORMULAS_APPGT" x where x.empresa_id = v_empresa_id and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)), '[]'::jsonb)
  );
end
$$;

create or replace function public.appgt_bootstrap_offline_data_v2(
  p_since timestamptz default null
)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.appgt_bootstrap_offline_data_v2_core(p_since)
      || public.appgt_configuration_matrices_v1(p_since);
$$;

revoke all on function public.appgt_bootstrap_offline_data_v2_core(timestamptz) from public, anon, authenticated;
revoke all on function public.appgt_configuration_matrices_v1(timestamptz) from public, anon, authenticated;
revoke all on function public.appgt_bootstrap_offline_data_v2(timestamptz) from public, anon;
grant execute on function public.appgt_bootstrap_offline_data_v2(timestamptz) to authenticated;

commit;
