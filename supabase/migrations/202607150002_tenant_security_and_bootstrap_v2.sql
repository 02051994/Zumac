begin;

create table if not exists public."EMPRESAS_APPGT" (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public."USUARIOS_EMPRESAS_APPGT" (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  rol text not null check (rol in ('ADMIN', 'GESTOR', 'COLABORADOR', 'VISUALIZADOR')),
  es_predeterminada boolean not null default false,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, empresa_id)
);

insert into public."EMPRESAS_APPGT" (id, codigo, nombre, activo)
values ('00000000-0000-0000-0000-000000000001', 'ZUMAC', 'ZUMAC', true)
on conflict (id) do update
set codigo = excluded.codigo,
    nombre = excluded.nombre,
    activo = true,
    updated_at = now();

insert into public."USUARIOS_EMPRESAS_APPGT" (
  user_id,
  empresa_id,
  rol,
  es_predeterminada,
  activo
)
select
  u.id,
  '00000000-0000-0000-0000-000000000001'::uuid,
  'ADMIN',
  true,
  true
from auth.users u
on conflict (user_id, empresa_id) do update
set activo = true,
    es_predeterminada = true,
    updated_at = now();

create or replace function public.appgt_puede_acceder_empresa(p_empresa_id uuid)
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
      and ue.activo is true
  );
$$;

create or replace function public.appgt_es_admin_empresa(p_empresa_id uuid)
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
      and ue.activo is true
      and ue.rol = 'ADMIN'
  );
$$;

revoke all on function public.appgt_puede_acceder_empresa(uuid) from public, anon;
revoke all on function public.appgt_es_admin_empresa(uuid) from public, anon;
grant execute on function public.appgt_puede_acceder_empresa(uuid) to authenticated;
grant execute on function public.appgt_es_admin_empresa(uuid) to authenticated;

alter table public."EMPRESAS_APPGT" enable row level security;
alter table public."USUARIOS_EMPRESAS_APPGT" enable row level security;

drop policy if exists empresas_miembro_select on public."EMPRESAS_APPGT";
create policy empresas_miembro_select
on public."EMPRESAS_APPGT"
for select
to authenticated
using (public.appgt_puede_acceder_empresa(id));

drop policy if exists empresas_admin_update on public."EMPRESAS_APPGT";
create policy empresas_admin_update
on public."EMPRESAS_APPGT"
for update
to authenticated
using (public.appgt_es_admin_empresa(id))
with check (public.appgt_es_admin_empresa(id));

drop policy if exists usuarios_empresas_select on public."USUARIOS_EMPRESAS_APPGT";
create policy usuarios_empresas_select
on public."USUARIOS_EMPRESAS_APPGT"
for select
to authenticated
using (user_id = auth.uid() or public.appgt_es_admin_empresa(empresa_id));

drop policy if exists usuarios_empresas_admin_all on public."USUARIOS_EMPRESAS_APPGT";
create policy usuarios_empresas_admin_all
on public."USUARIOS_EMPRESAS_APPGT"
for all
to authenticated
using (public.appgt_es_admin_empresa(empresa_id))
with check (public.appgt_es_admin_empresa(empresa_id));

do $$
declare
  table_name text;
  constraint_name text;
begin
  foreach table_name in array array[
    'MATRIZ_SECCIONES_APPGT',
    'MATRIZ_MODULOS_APPGT',
    'MATRIZ_FORMATOS_APPGT',
    'MATRIZ_FORMATO_TABLAS_APPGT',
    'MATRIZ_CAMPOS_FORMATO_APPGT',
    'MATRIZ_FORMATOS_ESPECIALES_APPGT',
    'MATRIZ_VISTAS_DINAMICAS_APPGT',
    'MATRIZ_ESTADOS_FLUJO_APPGT',
    'MATRIZ_MODULOS_GRAFICOS_DINAMICOS',
    'MATRIZ_VISTAS_REPORTES',
    'MATRIZ_FILTROS_DINAMICOS',
    'MATRIZ_GRAFICOS_DINAMICOS',
    'PERFILES_DE_USUARIOS_APPGT',
    'PERMISOS_DE_USUARIOS_APPGT',
    'PERMISOS_SECCIONES_APPGT',
    'PERMISOS_REPORTES_USUARIOS_APPGT'
  ] loop
    if to_regclass(format('public.%I', table_name)) is null then
      continue;
    end if;

    execute format(
      'alter table public.%I add column if not exists empresa_id uuid',
      table_name
    );
    execute format(
      'update public.%I set empresa_id = $1 where empresa_id is null',
      table_name
    ) using '00000000-0000-0000-0000-000000000001'::uuid;
    execute format(
      'alter table public.%I alter column empresa_id set default %L::uuid',
      table_name,
      '00000000-0000-0000-0000-000000000001'
    );
    execute format(
      'alter table public.%I alter column empresa_id set not null',
      table_name
    );

    constraint_name := 'fk_empresa_' || substr(md5(table_name), 1, 12);
    if not exists (
      select 1
      from pg_constraint
      where conname = constraint_name
        and conrelid = format('public.%I', table_name)::regclass
    ) then
      execute format(
        'alter table public.%I add constraint %I foreign key (empresa_id) references public."EMPRESAS_APPGT"(id)',
        table_name,
        constraint_name
      );
    end if;

    execute format(
      'create index if not exists %I on public.%I (empresa_id)',
      'idx_' || substr(md5(table_name), 1, 16) || '_empresa',
      table_name
    );
    execute format('alter table public.%I enable row level security', table_name);
    execute format('drop policy if exists tenant_scope on public.%I', table_name);
    execute format(
      'create policy tenant_scope on public.%I as restrictive for all to authenticated using (public.appgt_puede_acceder_empresa(empresa_id)) with check (public.appgt_puede_acceder_empresa(empresa_id))',
      table_name
    );
  end loop;
end
$$;

create or replace function public.appgt_bootstrap_offline_data_v2(
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
  v_empresa jsonb;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select ue.empresa_id
  into v_empresa_id
  from public."USUARIOS_EMPRESAS_APPGT" ue
  where ue.user_id = v_user_id
    and ue.activo is true
  order by ue.es_predeterminada desc, ue.created_at
  limit 1;

  if v_empresa_id is null then
    raise exception 'user has no active company' using errcode = '42501';
  end if;

  select to_jsonb(e)
  into v_empresa
  from public."EMPRESAS_APPGT" e
  where e.id = v_empresa_id
    and e.activo is true;

  return jsonb_build_object(
    'empresa', coalesce(v_empresa, '{}'::jsonb),
    'modules', coalesce((
      select jsonb_agg(to_jsonb(x)) from public."MATRIZ_MODULOS_APPGT" x
      where x.empresa_id = v_empresa_id
        and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)
    ), '[]'::jsonb),
    'formats', coalesce((
      select jsonb_agg(to_jsonb(x)) from public."MATRIZ_FORMATOS_APPGT" x
      where x.empresa_id = v_empresa_id
        and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)
    ), '[]'::jsonb),
    'format_tables', coalesce((
      select jsonb_agg(to_jsonb(x)) from public."MATRIZ_FORMATO_TABLAS_APPGT" x
      where x.empresa_id = v_empresa_id
        and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)
    ), '[]'::jsonb),
    'fields', coalesce((
      select jsonb_agg(to_jsonb(x)) from public."MATRIZ_CAMPOS_FORMATO_APPGT" x
      where x.empresa_id = v_empresa_id
        and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)
    ), '[]'::jsonb),
    'sections', coalesce((
      select jsonb_agg(to_jsonb(x)) from public."MATRIZ_SECCIONES_APPGT" x
      where x.empresa_id = v_empresa_id
        and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)
    ), '[]'::jsonb),
    'special_formats', coalesce((
      select jsonb_agg(to_jsonb(x)) from public."MATRIZ_FORMATOS_ESPECIALES_APPGT" x
      where x.empresa_id = v_empresa_id
        and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)
    ), '[]'::jsonb),
    'dynamic_views', coalesce((
      select jsonb_agg(to_jsonb(x)) from public."MATRIZ_VISTAS_DINAMICAS_APPGT" x
      where x.empresa_id = v_empresa_id
        and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)
    ), '[]'::jsonb),
    'profiles', coalesce((
      select jsonb_agg(to_jsonb(x)) from public."PERFILES_DE_USUARIOS_APPGT" x
      where x.id = v_user_id
        and x.empresa_id = v_empresa_id
        and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)
    ), '[]'::jsonb),
    'permissions', coalesce((
      select jsonb_agg(to_jsonb(x)) from public."PERMISOS_DE_USUARIOS_APPGT" x
      where x.user_id = v_user_id
        and x.empresa_id = v_empresa_id
        and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)
    ), '[]'::jsonb),
    'section_permissions', coalesce((
      select jsonb_agg(to_jsonb(x)) from public."PERMISOS_SECCIONES_APPGT" x
      where x.user_id = v_user_id
        and x.empresa_id = v_empresa_id
        and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)
    ), '[]'::jsonb),
    'flow_rules', coalesce((
      select jsonb_agg(to_jsonb(x)) from public."MATRIZ_ESTADOS_FLUJO_APPGT" x
      where x.empresa_id = v_empresa_id
        and (p_since is null or x.updated_at > p_since or x.deleted_at > p_since)
    ), '[]'::jsonb),
    'lotes_variedades', coalesce((
      select jsonb_agg(to_jsonb(x)) from public."LOTES_VARIEDADES_GT" x
    ), '[]'::jsonb),
    'plagas_conceptos', coalesce((
      select jsonb_agg(to_jsonb(x)) from public."SN-MATRIZ_CONCEPTOS_ESTADIOS_PLAGAS" x
    ), '[]'::jsonb),
    'etapas_fenologicas', coalesce((
      select jsonb_agg(to_jsonb(x)) from public."SN-MATRIZ_ETAPAS_FENOLOGICAS" x
    ), '[]'::jsonb),
    'conteo_estadios', coalesce((
      select jsonb_agg(to_jsonb(x)) from public."SN-MATRIZ_ESTADIOS_CONTEO_FRUTA" x
    ), '[]'::jsonb)
  );
end
$$;

revoke all on function public.appgt_bootstrap_offline_data_v2(timestamptz) from public, anon;
grant execute on function public.appgt_bootstrap_offline_data_v2(timestamptz) to authenticated;

create or replace function public.appgt_bootstrap_offline_data()
returns jsonb
language sql
security invoker
set search_path = public, pg_temp
as $$
  select public.appgt_bootstrap_offline_data_v2(null);
$$;

create or replace function public.appgt_bootstrap_offline_data(p_since timestamptz)
returns jsonb
language sql
security invoker
set search_path = public, pg_temp
as $$
  select public.appgt_bootstrap_offline_data_v2(p_since);
$$;

revoke all on function public.appgt_bootstrap_offline_data() from public, anon;
revoke all on function public.appgt_bootstrap_offline_data(timestamptz) from public, anon;
grant execute on function public.appgt_bootstrap_offline_data() to authenticated;
grant execute on function public.appgt_bootstrap_offline_data(timestamptz) to authenticated;

revoke all on function public.appgt_tablas_cambiadas_desde(timestamptz) from public, anon;
grant execute on function public.appgt_tablas_cambiadas_desde(timestamptz) to authenticated;
alter function public.appgt_tablas_cambiadas_desde(timestamptz)
  set search_path = public, pg_temp;
alter function public.appgt_registrar_tabla_modificada()
  set search_path = public, pg_temp;
revoke all on function public.appgt_registrar_tabla_modificada() from public, anon, authenticated;

do $$
begin
  if to_regclass('public.appgt_auditoria_peru') is not null then
    execute 'alter view public.appgt_auditoria_peru set (security_invoker = true)';
  end if;
end
$$;

commit;
