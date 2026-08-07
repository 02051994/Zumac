begin;

alter table public."ZUMAC_METRICS_DASHBOARDS_APPGT"
  add column if not exists configuracion jsonb not null default '{}'::jsonb;

alter table public."ZUMAC_METRICS_WIDGETS_APPGT"
  drop constraint if exists "ZUMAC_METRICS_WIDGETS_APPGT_tipo_grafico_check";
alter table public."ZUMAC_METRICS_WIDGETS_APPGT"
  add constraint "ZUMAC_METRICS_WIDGETS_APPGT_tipo_grafico_check"
  check(tipo_grafico in(
    'KPI','BAR','STACKED_BAR','LINE','MULTI_LINE','AREA','PIE','DONUT',
    'TABLE','SCATTER','FUNNEL','COMBO'
  ));

drop policy if exists zumac_metrics_select
  on public."ZUMAC_METRICS_DASHBOARDS_APPGT";
create policy zumac_metrics_select
on public."ZUMAC_METRICS_DASHBOARDS_APPGT"
for select
using (
  public.appgt_puede_acceder_empresa(empresa_id)
  and (
    public.appgt_es_admin_empresa(empresa_id)
    or coalesce(configuracion ->> 'visibility', 'ALL') = 'ALL'
    or (
      configuracion ->> 'visibility' = 'SPECIFIC'
      and coalesce(configuracion -> 'users', '[]'::jsonb) ? auth.uid()::text
    )
    or (
      configuracion ->> 'visibility' = 'ALL_EXCEPT'
      and not (coalesce(configuracion -> 'users', '[]'::jsonb) ? auth.uid()::text)
    )
  )
);

drop policy if exists zumac_metrics_select
  on public."ZUMAC_METRICS_WIDGETS_APPGT";
create policy zumac_metrics_select
on public."ZUMAC_METRICS_WIDGETS_APPGT"
for select
using (
  public.appgt_puede_acceder_empresa(empresa_id)
  and exists (
    select 1
    from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
    where d.id="ZUMAC_METRICS_WIDGETS_APPGT".dashboard_id
      and d.empresa_id="ZUMAC_METRICS_WIDGETS_APPGT".empresa_id
      and d.activo
      and d.deleted_at is null
  )
);

drop policy if exists zumac_metrics_select
  on public."ZUMAC_METRICS_RELACIONES_APPGT";
create policy zumac_metrics_select
on public."ZUMAC_METRICS_RELACIONES_APPGT"
for select
using (
  public.appgt_puede_acceder_empresa(empresa_id)
  and exists (
    select 1
    from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
    where d.id="ZUMAC_METRICS_RELACIONES_APPGT".dashboard_id
      and d.empresa_id="ZUMAC_METRICS_RELACIONES_APPGT".empresa_id
      and d.activo
      and d.deleted_at is null
  )
);

create or replace function public.appgt_metrics_contexto_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa_id uuid:=public.appgt_empresa_actual_id();
  v_enabled boolean;
  v_manage boolean;
begin
  if v_empresa_id is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select habilitar_zumac_metrics into v_enabled
  from public."EMPRESAS_APPGT" where id=v_empresa_id and activo;
  v_manage:=public.appgt_puede_gestionar_configuracion(v_empresa_id);
  return jsonb_build_object(
    'empresa_id',v_empresa_id,
    'metrics_habilitado',coalesce(v_enabled,false),
    'puede_gestionar',v_manage,
    'usuarios',case when v_manage then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,
        'nombres',p.nombres,
        'apellidos',concat_ws(' ',p.apellido_paterno,p.apellido_materno),
        'email',''
      ) order by p.nombres,p.apellido_paterno,p.apellido_materno)
      from public."PERFILES_DE_USUARIOS_APPGT" p
      where p.empresa_id=v_empresa_id and coalesce(p.activo,true)
    ),'[]'::jsonb) else '[]'::jsonb end,
    'fuentes',coalesce((
      select jsonb_agg(source order by source->>'nombre') from (
        select jsonb_build_object(
          'tabla',ft.tabla_destino,
          'nombre',coalesce(nullif(f.nombre,''),nullif(ft.nombre,''),ft.tabla_destino),
          'formato_id',ft.formato_id,
          'modulo_id',f.modulo_id,
          'campos',coalesce((
            select jsonb_agg(jsonb_build_object(
              'campo',c.campo,
              'etiqueta',coalesce(nullif(c.etiqueta,''),c.campo),
              'tipo',coalesce(nullif(c.tipo,''),'text')
            ) order by c.orden,c.campo)
            from public."MATRIZ_CAMPOS_FORMATO_APPGT" c
            join information_schema.columns pc
              on pc.table_schema='public'
              and pc.table_name=ft.tabla_destino
              and pc.column_name=c.campo
            where c.empresa_id=v_empresa_id
              and c.tabla_destino=ft.tabla_destino
              and coalesce(c.activo,true)
              and not coalesce(c.eliminado,false)
          ),'[]'::jsonb)
        ) source
        from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
        left join public."MATRIZ_FORMATOS_APPGT" f
          on f.empresa_id=ft.empresa_id and f.id=ft.formato_id
        where ft.empresa_id=v_empresa_id
          and coalesce(ft.activo,true)
          and ft.deleted_at is null
          and public.appgt_tabla_alertable_v1(v_empresa_id,ft.tabla_destino)
        group by ft.tabla_destino,ft.nombre,f.nombre,ft.formato_id,f.modulo_id
      ) sources
    ),'[]'::jsonb)
  );
end
$$;

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
  if not public.appgt_tabla_alertable_v1(
      v_empresa_id,p_payload->>'tabla_origen') then
    raise exception 'Fuente no disponible';
  end if;

  if v_id is null then
    insert into public."ZUMAC_METRICS_WIDGETS_APPGT"(
      empresa_id,dashboard_id,titulo,descripcion,tabla_origen,
      campo_dimension,campo_valor,campo_serie,agregacion,tipo_grafico,
      filtros,configuracion,ancho,alto,orden,creado_por
    ) values(
      v_empresa_id,v_dashboard,btrim(p_payload->>'titulo'),
      nullif(btrim(p_payload->>'descripcion'),''),p_payload->>'tabla_origen',
      nullif(p_payload->>'campo_dimension',''),
      nullif(p_payload->>'campo_valor',''),
      nullif(p_payload->>'campo_serie',''),
      coalesce(nullif(p_payload->>'agregacion',''),'COUNT'),
      coalesce(nullif(p_payload->>'tipo_grafico',''),'BAR'),
      coalesce(p_payload->'filtros','[]'::jsonb),
      coalesce(p_payload->'configuracion','{}'::jsonb),
      greatest(1,least(coalesce((p_payload->>'ancho')::integer,6),12)),
      greatest(2,least(coalesce((p_payload->>'alto')::integer,4),12)),
      coalesce((p_payload->>'orden')::integer,0),auth.uid()
    ) returning id into v_id;
  else
    update public."ZUMAC_METRICS_WIDGETS_APPGT" set
      titulo=btrim(p_payload->>'titulo'),
      descripcion=nullif(btrim(p_payload->>'descripcion'),''),
      tabla_origen=p_payload->>'tabla_origen',
      campo_dimension=nullif(p_payload->>'campo_dimension',''),
      campo_valor=nullif(p_payload->>'campo_valor',''),
      campo_serie=nullif(p_payload->>'campo_serie',''),
      agregacion=coalesce(nullif(p_payload->>'agregacion',''),agregacion),
      tipo_grafico=coalesce(nullif(p_payload->>'tipo_grafico',''),tipo_grafico),
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

create or replace function public.appgt_guardar_dashboard_metrics_v1(
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
  v_config jsonb:=coalesce(p_payload->'configuracion','{}'::jsonb);
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'Sin permiso' using errcode='42501';
  end if;
  if nullif(btrim(p_payload->>'nombre'),'') is null then
    raise exception 'El nombre es obligatorio';
  end if;
  if coalesce(v_config->>'visibility','ALL') not in
      ('ADMINS','ALL','SPECIFIC','ALL_EXCEPT') then
    raise exception 'Visibilidad de dashboard inválida';
  end if;

  if v_id is null then
    insert into public."ZUMAC_METRICS_DASHBOARDS_APPGT"(
      empresa_id,nombre,descripcion,color,filtros_globales,configuracion,
      orden,creado_por
    ) values(
      v_empresa_id,
      btrim(p_payload->>'nombre'),
      nullif(btrim(p_payload->>'descripcion'),''),
      coalesce(nullif(p_payload->>'color',''),'#176B87'),
      coalesce(p_payload->'filtros_globales','[]'::jsonb),
      v_config,
      coalesce((p_payload->>'orden')::integer,0),
      auth.uid()
    ) returning id into v_id;
  else
    update public."ZUMAC_METRICS_DASHBOARDS_APPGT" set
      nombre=btrim(p_payload->>'nombre'),
      descripcion=nullif(btrim(p_payload->>'descripcion'),''),
      color=coalesce(nullif(p_payload->>'color',''),color),
      filtros_globales=coalesce(p_payload->'filtros_globales',filtros_globales),
      configuracion=coalesce(p_payload->'configuracion',configuracion),
      orden=coalesce((p_payload->>'orden')::integer,orden),
      deleted_at=null,
      activo=true
    where id=v_id and empresa_id=v_empresa_id;
    if not found then raise exception 'Dashboard no encontrado'; end if;
  end if;
  return jsonb_build_object('id',v_id,'guardado',true);
end
$$;

revoke all on function public.appgt_metrics_contexto_v1() from public,anon;
revoke all on function public.appgt_guardar_dashboard_metrics_v1(jsonb)
  from public,anon;
revoke all on function public.appgt_guardar_widget_metrics_v1(jsonb)
  from public,anon;
grant execute on function public.appgt_metrics_contexto_v1() to authenticated;
grant execute on function public.appgt_guardar_dashboard_metrics_v1(jsonb)
  to authenticated;
grant execute on function public.appgt_guardar_widget_metrics_v1(jsonb)
  to authenticated;

commit;
