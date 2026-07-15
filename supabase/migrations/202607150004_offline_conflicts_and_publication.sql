begin;

create table if not exists public."VERSIONES_CONFIGURACION_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  numero_version integer not null,
  version text not null,
  estado text not null default 'BORRADOR'
    check (estado in ('BORRADOR', 'PUBLICADA', 'ARCHIVADA')),
  descripcion text,
  hash_configuracion text,
  created_by uuid references auth.users(id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (empresa_id, numero_version),
  unique (empresa_id, version)
);

create table if not exists public."PUBLICACIONES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  version_id uuid not null references public."VERSIONES_CONFIGURACION_APPGT"(id),
  canal text not null default 'PRODUCCION',
  estado text not null default 'PUBLICADA'
    check (estado in ('PUBLICADA', 'RETIRADA')),
  notas text,
  metadata jsonb not null default '{}'::jsonb,
  published_by uuid references auth.users(id),
  published_at timestamptz not null default now(),
  retired_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (empresa_id, canal, version_id)
);

create table if not exists public."SINCRONIZACIONES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  user_id uuid not null references auth.users(id),
  dispositivo_id text,
  estado text not null default 'EJECUTANDO'
    check (estado in ('EJECUTANDO', 'COMPLETADA', 'PARCIAL', 'ERROR')),
  pendientes_iniciales integer not null default 0,
  sincronizados integer not null default 0,
  conflictos integer not null default 0,
  errores integer not null default 0,
  detalle jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public."CONFLICTOS_SYNC_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  user_id uuid not null references auth.users(id),
  sincronizacion_id uuid references public."SINCRONIZACIONES_APPGT"(id),
  tabla_destino text not null,
  registro_id_local text not null,
  payload_local jsonb not null default '{}'::jsonb,
  payload_remoto jsonb not null default '{}'::jsonb,
  base_updated_at timestamptz,
  remote_updated_at timestamptz,
  estado text not null default 'PENDIENTE'
    check (estado in ('PENDIENTE', 'RESUELTO_LOCAL', 'RESUELTO_REMOTO', 'RESUELTO_MANUAL', 'DESCARTADO')),
  resolucion text,
  payload_resuelto jsonb,
  resolved_by uuid references auth.users(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public."ARCHIVOS_EVIDENCIA_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  user_id uuid not null references auth.users(id),
  tabla_destino text not null,
  registro_id_local text not null,
  campo text not null,
  bucket text not null,
  object_path text not null,
  mime_type text,
  tamano_bytes bigint,
  estado text not null default 'PENDIENTE_VINCULAR'
    check (estado in ('PENDIENTE_VINCULAR', 'VINCULADO', 'HUERFANO', 'ELIMINADO')),
  linked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (empresa_id, bucket, object_path)
);

create index if not exists idx_versiones_config_empresa
  on public."VERSIONES_CONFIGURACION_APPGT" (empresa_id, estado, numero_version desc);
create index if not exists idx_publicaciones_empresa
  on public."PUBLICACIONES_APPGT" (empresa_id, canal, estado, published_at desc);
create index if not exists idx_sincronizaciones_usuario
  on public."SINCRONIZACIONES_APPGT" (empresa_id, user_id, started_at desc);
create index if not exists idx_conflictos_sync_pendientes
  on public."CONFLICTOS_SYNC_APPGT" (empresa_id, user_id, estado, created_at desc);
create index if not exists idx_evidencias_registro
  on public."ARCHIVOS_EVIDENCIA_APPGT" (empresa_id, tabla_destino, registro_id_local, estado);

insert into public."VERSIONES_CONFIGURACION_APPGT" (
  id, empresa_id, numero_version, version, estado, descripcion, published_at
) values (
  '00000000-0000-0000-0000-000000000101',
  '00000000-0000-0000-0000-000000000001',
  1,
  '1.0.0',
  'PUBLICADA',
  'Version inicial de la arquitectura declarativa ZUMAC.',
  now()
) on conflict (empresa_id, numero_version) do update set
  version = excluded.version,
  estado = 'PUBLICADA',
  published_at = coalesce(public."VERSIONES_CONFIGURACION_APPGT".published_at, excluded.published_at),
  updated_at = now();

insert into public."PUBLICACIONES_APPGT" (
  id, empresa_id, version_id, canal, estado, notas, published_at
)
select
  gen_random_uuid(),
  v.empresa_id,
  v.id,
  'PRODUCCION',
  'PUBLICADA',
  'Publicacion inicial compatible con la configuracion productiva existente.',
  now()
from public."VERSIONES_CONFIGURACION_APPGT" v
where v.empresa_id = '00000000-0000-0000-0000-000000000001'
  and v.numero_version = 1
on conflict (empresa_id, canal, version_id) do update set
  estado = 'PUBLICADA',
  retired_at = null,
  updated_at = now();

do $$
declare
  t text;
begin
  foreach t in array array[
    'VERSIONES_CONFIGURACION_APPGT',
    'PUBLICACIONES_APPGT',
    'SINCRONIZACIONES_APPGT',
    'CONFLICTOS_SYNC_APPGT',
    'ARCHIVOS_EVIDENCIA_APPGT'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop trigger if exists appgt_set_updated_at_trigger on public.%I', t);
    execute format(
      'create trigger appgt_set_updated_at_trigger before update on public.%I for each row execute function public.appgt_set_updated_at()',
      t
    );
  end loop;
end
$$;

drop policy if exists versiones_select on public."VERSIONES_CONFIGURACION_APPGT";
create policy versiones_select on public."VERSIONES_CONFIGURACION_APPGT"
for select to authenticated
using (public.appgt_puede_acceder_empresa(empresa_id));
drop policy if exists versiones_admin on public."VERSIONES_CONFIGURACION_APPGT";
create policy versiones_admin on public."VERSIONES_CONFIGURACION_APPGT"
for all to authenticated
using (public.appgt_es_admin_empresa(empresa_id))
with check (public.appgt_es_admin_empresa(empresa_id));

drop policy if exists publicaciones_select on public."PUBLICACIONES_APPGT";
create policy publicaciones_select on public."PUBLICACIONES_APPGT"
for select to authenticated
using (public.appgt_puede_acceder_empresa(empresa_id));
drop policy if exists publicaciones_admin on public."PUBLICACIONES_APPGT";
create policy publicaciones_admin on public."PUBLICACIONES_APPGT"
for all to authenticated
using (public.appgt_es_admin_empresa(empresa_id))
with check (public.appgt_es_admin_empresa(empresa_id));

drop policy if exists sincronizaciones_propias on public."SINCRONIZACIONES_APPGT";
create policy sincronizaciones_propias on public."SINCRONIZACIONES_APPGT"
for all to authenticated
using (user_id = auth.uid() and public.appgt_puede_acceder_empresa(empresa_id))
with check (user_id = auth.uid() and public.appgt_puede_acceder_empresa(empresa_id));

drop policy if exists conflictos_propios on public."CONFLICTOS_SYNC_APPGT";
create policy conflictos_propios on public."CONFLICTOS_SYNC_APPGT"
for all to authenticated
using (user_id = auth.uid() and public.appgt_puede_acceder_empresa(empresa_id))
with check (user_id = auth.uid() and public.appgt_puede_acceder_empresa(empresa_id));

drop policy if exists evidencias_propias on public."ARCHIVOS_EVIDENCIA_APPGT";
create policy evidencias_propias on public."ARCHIVOS_EVIDENCIA_APPGT"
for all to authenticated
using (user_id = auth.uid() and public.appgt_puede_acceder_empresa(empresa_id))
with check (user_id = auth.uid() and public.appgt_puede_acceder_empresa(empresa_id));

create or replace function public.appgt_publicar_configuracion(
  p_version_id uuid,
  p_canal text default 'PRODUCCION',
  p_notas text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid;
  v_publicacion public."PUBLICACIONES_APPGT";
begin
  select empresa_id into v_empresa_id
  from public."VERSIONES_CONFIGURACION_APPGT"
  where id = p_version_id;

  if v_empresa_id is null or not public.appgt_es_admin_empresa(v_empresa_id) then
    raise exception 'administrator permission required' using errcode = '42501';
  end if;

  update public."PUBLICACIONES_APPGT"
  set estado = 'RETIRADA', retired_at = now()
  where empresa_id = v_empresa_id
    and canal = upper(btrim(p_canal))
    and estado = 'PUBLICADA';

  insert into public."PUBLICACIONES_APPGT" (
    empresa_id, version_id, canal, estado, notas, published_by
  ) values (
    v_empresa_id, p_version_id, upper(btrim(p_canal)), 'PUBLICADA', p_notas, auth.uid()
  )
  on conflict (empresa_id, canal, version_id) do update set
    estado = 'PUBLICADA',
    notas = excluded.notas,
    published_by = excluded.published_by,
    published_at = now(),
    retired_at = null
  returning * into v_publicacion;

  update public."VERSIONES_CONFIGURACION_APPGT"
  set estado = 'ARCHIVADA', updated_at = now()
  where empresa_id = v_empresa_id
    and id <> p_version_id
    and estado = 'PUBLICADA';

  update public."VERSIONES_CONFIGURACION_APPGT"
  set estado = 'PUBLICADA', published_at = coalesce(published_at, now())
  where id = p_version_id;

  return to_jsonb(v_publicacion);
end
$$;

create or replace function public.appgt_resolver_conflicto_sync(
  p_conflicto_id uuid,
  p_resolucion text,
  p_payload_resuelto jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_conflicto public."CONFLICTOS_SYNC_APPGT";
  v_estado text := upper(btrim(p_resolucion));
begin
  select * into v_conflicto
  from public."CONFLICTOS_SYNC_APPGT"
  where id = p_conflicto_id;

  if v_conflicto.id is null
     or (v_conflicto.user_id <> auth.uid()
         and not public.appgt_es_admin_empresa(v_conflicto.empresa_id)) then
    raise exception 'conflict not found or access denied' using errcode = '42501';
  end if;

  if v_estado not in ('RESUELTO_LOCAL', 'RESUELTO_REMOTO', 'RESUELTO_MANUAL', 'DESCARTADO') then
    raise exception 'invalid resolution';
  end if;

  update public."CONFLICTOS_SYNC_APPGT"
  set estado = v_estado,
      resolucion = v_estado,
      payload_resuelto = p_payload_resuelto,
      resolved_by = auth.uid(),
      resolved_at = now()
  where id = p_conflicto_id
  returning * into v_conflicto;

  return to_jsonb(v_conflicto);
end
$$;

create or replace function public.appgt_offline_control_v1()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid;
begin
  select ue.empresa_id into v_empresa_id
  from public."USUARIOS_EMPRESAS_APPGT" ue
  where ue.user_id = auth.uid() and ue.activo
  order by ue.es_predeterminada desc, ue.created_at
  limit 1;

  if v_empresa_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'configuration_version', coalesce((
      select to_jsonb(v)
      from public."VERSIONES_CONFIGURACION_APPGT" v
      where v.empresa_id = v_empresa_id and v.estado = 'PUBLICADA'
      order by v.numero_version desc
      limit 1
    ), '{}'::jsonb),
    'publications', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.published_at desc)
      from public."PUBLICACIONES_APPGT" p
      where p.empresa_id = v_empresa_id and p.estado = 'PUBLICADA'
    ), '[]'::jsonb),
    'offline_policy', jsonb_build_object(
      'states', jsonb_build_array(
        'borrador', 'pendiente', 'sincronizando', 'sincronizado',
        'error', 'conflicto', 'eliminado_pendiente', 'bloqueado'
      ),
      'conflict_strategy', 'OPTIMISTIC_UPDATED_AT',
      'evidence_manifest', true
    )
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
      || public.appgt_configuration_matrices_v1(p_since)
      || public.appgt_offline_control_v1();
$$;

revoke all on function public.appgt_publicar_configuracion(uuid, text, text) from public, anon;
revoke all on function public.appgt_resolver_conflicto_sync(uuid, text, jsonb) from public, anon;
revoke all on function public.appgt_offline_control_v1() from public, anon, authenticated;
revoke all on function public.appgt_bootstrap_offline_data_v2(timestamptz) from public, anon;
grant select on table public."VERSIONES_CONFIGURACION_APPGT" to authenticated;
grant select on table public."PUBLICACIONES_APPGT" to authenticated;
grant select, insert, update on table public."SINCRONIZACIONES_APPGT" to authenticated;
grant select, insert, update on table public."CONFLICTOS_SYNC_APPGT" to authenticated;
grant select, insert, update on table public."ARCHIVOS_EVIDENCIA_APPGT" to authenticated;
grant execute on function public.appgt_publicar_configuracion(uuid, text, text) to authenticated;
grant execute on function public.appgt_resolver_conflicto_sync(uuid, text, jsonb) to authenticated;
grant execute on function public.appgt_bootstrap_offline_data_v2(timestamptz) to authenticated;

commit;
