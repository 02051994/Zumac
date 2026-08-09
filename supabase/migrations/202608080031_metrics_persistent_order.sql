begin;

-- Devuelve el orden confirmado por PostgreSQL. El cliente ya no necesita una
-- recarga susceptible de mostrar el orden anterior mientras se propaga el RPC.
create or replace function public.appgt_reordenar_dashboards_metrics_v2(
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
  v_found integer;
  v_result jsonb;
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'Sin permiso' using errcode = '42501';
  end if;
  if v_received = 0
     or (select count(distinct value) from unnest(p_ids) value) <> v_received then
    raise exception 'La lista de dashboards es invalida o contiene duplicados.';
  end if;

  -- Serializa dos reordenamientos simultaneos de la misma empresa.
  perform pg_advisory_xact_lock(hashtextextended(v_empresa_id::text, 831));

  perform 1
  from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  where d.empresa_id = v_empresa_id
    and d.activo
    and d.deleted_at is null
    and d.id = any(p_ids)
  for update;

  select count(*) into v_found
  from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  where d.empresa_id = v_empresa_id
    and d.activo
    and d.deleted_at is null
    and d.id = any(p_ids);

  if v_found <> v_received then
    raise exception 'Uno o mas dashboards ya no estan disponibles.';
  end if;

  update public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  set orden = 100000 + ordered.position::integer,
      updated_at = clock_timestamp()
  from unnest(p_ids) with ordinality ordered(id, position)
  where d.empresa_id = v_empresa_id and d.id = ordered.id;

  update public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  set orden = ordered.position::integer - 1,
      updated_at = clock_timestamp()
  from unnest(p_ids) with ordinality ordered(id, position)
  where d.empresa_id = v_empresa_id and d.id = ordered.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id,
    'orden', d.orden,
    'updated_at', d.updated_at
  ) order by d.orden), '[]'::jsonb)
  into v_result
  from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  where d.empresa_id = v_empresa_id and d.id = any(p_ids);

  return jsonb_build_object(
    'guardado', true,
    'total', v_received,
    'dashboards', v_result
  );
end
$$;

revoke all on function public.appgt_reordenar_dashboards_metrics_v2(uuid[])
  from public, anon;
grant execute on function public.appgt_reordenar_dashboards_metrics_v2(uuid[])
  to authenticated, service_role;

commit;
