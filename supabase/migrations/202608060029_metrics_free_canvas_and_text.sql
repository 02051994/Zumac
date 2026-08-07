begin;

-- Los objetos de texto y figuras pertenecen al dashboard, no a una tabla de
-- negocio. Por eso su fuente puede ser nula, mientras los gráficos de datos
-- conservan la validación estricta de fuentes autorizadas por empresa.
alter table public."ZUMAC_METRICS_WIDGETS_APPGT"
  alter column tabla_origen drop not null;

alter table public."ZUMAC_METRICS_WIDGETS_APPGT"
  drop constraint if exists "ZUMAC_METRICS_WIDGETS_APPGT_tipo_grafico_check";
alter table public."ZUMAC_METRICS_WIDGETS_APPGT"
  add constraint "ZUMAC_METRICS_WIDGETS_APPGT_tipo_grafico_check"
  check(tipo_grafico in(
    'KPI','BAR','STACKED_BAR','LINE','MULTI_LINE','AREA','PIE','DONUT',
    'TABLE','SCATTER','FUNNEL','COMBO','TEXT'
  ));

create or replace function public.appgt_guardar_widget_metrics_v1(
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa_id uuid:=public.appgt_empresa_actual_id();
  v_id uuid:=nullif(p_payload->>'id','')::uuid;
  v_dashboard uuid:=nullif(p_payload->>'dashboard_id','')::uuid;
  v_type text:=coalesce(nullif(upper(p_payload->>'tipo_grafico'),''),'BAR');
  v_source text:=nullif(btrim(p_payload->>'tabla_origen'),'');
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'Sin permiso' using errcode='42501';
  end if;
  if not exists(
    select 1 from public."ZUMAC_METRICS_DASHBOARDS_APPGT"
    where id=v_dashboard and empresa_id=v_empresa_id and deleted_at is null
  ) then
    raise exception 'Dashboard no disponible';
  end if;
  if v_type <> 'TEXT'
     and not public.appgt_tabla_alertable_v1(v_empresa_id,v_source) then
    raise exception 'Fuente no disponible';
  end if;

  if v_id is null then
    insert into public."ZUMAC_METRICS_WIDGETS_APPGT"(
      empresa_id,dashboard_id,titulo,descripcion,tabla_origen,
      campo_dimension,campo_valor,campo_serie,agregacion,tipo_grafico,
      filtros,configuracion,ancho,alto,orden,creado_por
    ) values(
      v_empresa_id,v_dashboard,coalesce(btrim(p_payload->>'titulo'),''),
      nullif(btrim(p_payload->>'descripcion'),''),v_source,
      nullif(p_payload->>'campo_dimension',''),
      nullif(p_payload->>'campo_valor',''),
      nullif(p_payload->>'campo_serie',''),
      coalesce(nullif(p_payload->>'agregacion',''),'COUNT'),v_type,
      coalesce(p_payload->'filtros','[]'::jsonb),
      coalesce(p_payload->'configuracion','{}'::jsonb),
      greatest(1,least(coalesce((p_payload->>'ancho')::integer,6),12)),
      greatest(2,least(coalesce((p_payload->>'alto')::integer,4),12)),
      coalesce((p_payload->>'orden')::integer,0),auth.uid()
    ) returning id into v_id;
  else
    update public."ZUMAC_METRICS_WIDGETS_APPGT" set
      titulo=coalesce(btrim(p_payload->>'titulo'),''),
      descripcion=nullif(btrim(p_payload->>'descripcion'),''),
      tabla_origen=v_source,
      campo_dimension=nullif(p_payload->>'campo_dimension',''),
      campo_valor=nullif(p_payload->>'campo_valor',''),
      campo_serie=nullif(p_payload->>'campo_serie',''),
      agregacion=coalesce(nullif(p_payload->>'agregacion',''),agregacion),
      tipo_grafico=v_type,
      filtros=coalesce(p_payload->'filtros',filtros),
      configuracion=coalesce(p_payload->'configuracion',configuracion),
      ancho=greatest(1,least(coalesce((p_payload->>'ancho')::integer,ancho),12)),
      alto=greatest(2,least(coalesce((p_payload->>'alto')::integer,alto),12)),
      orden=coalesce((p_payload->>'orden')::integer,orden),
      activo=true,
      deleted_at=null
    where id=v_id and empresa_id=v_empresa_id and dashboard_id=v_dashboard;
    if not found then raise exception 'Gráfico no encontrado'; end if;
  end if;
  return jsonb_build_object('id',v_id,'guardado',true);
end
$$;

revoke all on function public.appgt_guardar_widget_metrics_v1(jsonb)
  from public,anon;
grant execute on function public.appgt_guardar_widget_metrics_v1(jsonb)
  to authenticated;

commit;
