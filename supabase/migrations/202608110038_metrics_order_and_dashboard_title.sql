begin;

-- Normaliza una sola vez los órdenes heredados antes de volverlos únicos.
with ranked as (
  select d.id,
         row_number() over (
           partition by d.empresa_id
           order by d.orden, d.created_at, d.id
         ) - 1 as new_order
  from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  where d.activo and d.deleted_at is null
)
update public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
set orden = ranked.new_order, updated_at = now()
from ranked
where d.id = ranked.id and d.orden is distinct from ranked.new_order;

create unique index if not exists ux_metrics_dashboard_company_order
  on public."ZUMAC_METRICS_DASHBOARDS_APPGT" (empresa_id, orden)
  where activo and deleted_at is null;

create or replace function public.appgt_reordenar_dashboards_metrics_v3(
  p_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_received integer := coalesce(array_length(p_ids, 1), 0);
  v_active integer;
  v_result jsonb;
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'Sin permiso' using errcode = '42501';
  end if;
  if v_received = 0
     or (select count(distinct value) from unnest(p_ids) value) <> v_received then
    raise exception 'La lista de dashboards es inválida o contiene duplicados.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_empresa_id::text, 831));

  select count(*) into v_active
  from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  where d.empresa_id = v_empresa_id and d.activo and d.deleted_at is null;

  if v_active <> v_received or exists (
    select 1 from unnest(p_ids) requested(id)
    where not exists (
      select 1 from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
      where d.empresa_id = v_empresa_id and d.id = requested.id
        and d.activo and d.deleted_at is null
    )
  ) then
    raise exception 'La lista debe contener todos los dashboards activos.';
  end if;

  perform 1
  from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  where d.empresa_id = v_empresa_id and d.activo and d.deleted_at is null
  for update;

  update public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  set orden = 1000000 + ordered.position::integer,
      updated_at = clock_timestamp()
  from unnest(p_ids) with ordinality ordered(id, position)
  where d.empresa_id = v_empresa_id and d.id = ordered.id;

  update public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  set orden = ordered.position::integer - 1,
      updated_at = clock_timestamp()
  from unnest(p_ids) with ordinality ordered(id, position)
  where d.empresa_id = v_empresa_id and d.id = ordered.id;

  select jsonb_agg(jsonb_build_object(
           'id', d.id, 'orden', d.orden, 'updated_at', d.updated_at
         ) order by d.orden)
    into v_result
  from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  where d.empresa_id = v_empresa_id and d.activo and d.deleted_at is null;

  return jsonb_build_object(
    'guardado', true,
    'total', v_active,
    'dashboards', coalesce(v_result, '[]'::jsonb)
  );
end
$$;

create or replace function public.appgt_guardar_dashboard_metrics_v1(
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_id uuid := nullif(p_payload->>'id','')::uuid;
  v_config jsonb := coalesce(p_payload->'configuracion','{}'::jsonb);
  v_next_order integer;
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'Sin permiso' using errcode = '42501';
  end if;
  if nullif(btrim(p_payload->>'nombre'),'') is null then
    raise exception 'El nombre es obligatorio';
  end if;
  if coalesce(v_config->>'visibility','ALL') not in
      ('ADMINS','ALL','SPECIFIC','ALL_EXCEPT') then
    raise exception 'Visibilidad de dashboard inválida';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_empresa_id::text, 831));
  if v_id is null then
    select coalesce(max(d.orden), -1) + 1 into v_next_order
    from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
    where d.empresa_id = v_empresa_id and d.activo and d.deleted_at is null;

    insert into public."ZUMAC_METRICS_DASHBOARDS_APPGT"(
      empresa_id,nombre,descripcion,color,filtros_globales,configuracion,
      orden,creado_por
    ) values(
      v_empresa_id, btrim(p_payload->>'nombre'),
      nullif(btrim(p_payload->>'descripcion'),''),
      coalesce(nullif(p_payload->>'color',''),'#176B87'),
      coalesce(p_payload->'filtros_globales','[]'::jsonb),
      v_config, v_next_order, auth.uid()
    ) returning id into v_id;
  else
    update public."ZUMAC_METRICS_DASHBOARDS_APPGT" set
      nombre = btrim(p_payload->>'nombre'),
      descripcion = nullif(btrim(p_payload->>'descripcion'),''),
      color = coalesce(nullif(p_payload->>'color',''), color),
      filtros_globales = coalesce(p_payload->'filtros_globales', filtros_globales),
      configuracion = coalesce(p_payload->'configuracion', configuracion),
      -- Editar el título, color o visibilidad nunca debe restaurar un orden
      -- antiguo enviado por una pantalla que quedó abierta.
      orden = orden,
      deleted_at = null, activo = true, updated_at = now()
    where id = v_id and empresa_id = v_empresa_id;
    if not found then raise exception 'Dashboard no encontrado'; end if;
  end if;
  return jsonb_build_object('id', v_id, 'guardado', true);
end
$$;

revoke all on function public.appgt_reordenar_dashboards_metrics_v3(uuid[])
  from public, anon;
grant execute on function public.appgt_reordenar_dashboards_metrics_v3(uuid[])
  to authenticated, service_role;
revoke all on function public.appgt_guardar_dashboard_metrics_v1(jsonb)
  from public, anon;
grant execute on function public.appgt_guardar_dashboard_metrics_v1(jsonb)
  to authenticated, service_role;

notify pgrst, 'reload schema';
commit;
