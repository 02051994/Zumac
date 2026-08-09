begin;

-- Guarda exclusivamente la geometria del objeto. No reenvia una configuracion
-- completa potencialmente obsoleta y devuelve la fila realmente persistida.
create or replace function public.appgt_guardar_geometria_widget_metrics_v2(
  p_widget_id uuid,
  p_dashboard_id uuid,
  p_geometria jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_configuracion jsonb;
  v_updated_at timestamptz;
  v_key text;
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'Sin permiso' using errcode = '42501';
  end if;
  if p_geometria is null or jsonb_typeof(p_geometria) <> 'object' then
    raise exception 'La geometria debe ser un objeto JSON.';
  end if;

  for v_key in select jsonb_object_keys(p_geometria)
  loop
    if v_key not in ('pixel_x','pixel_y','pixel_width','pixel_height') then
      raise exception 'Campo de geometria no permitido: %', v_key;
    end if;
    if jsonb_typeof(p_geometria -> v_key) <> 'number' then
      raise exception 'La geometria % debe ser numerica.', v_key;
    end if;
  end loop;

  if p_geometria ? 'pixel_x'
     and (p_geometria ->> 'pixel_x')::numeric not between 0 and 10000 then
    raise exception 'pixel_x fuera de rango.';
  end if;
  if p_geometria ? 'pixel_y'
     and (p_geometria ->> 'pixel_y')::numeric not between 0 and 10000 then
    raise exception 'pixel_y fuera de rango.';
  end if;
  if p_geometria ? 'pixel_width'
     and (p_geometria ->> 'pixel_width')::numeric not between 190 and 5000 then
    raise exception 'pixel_width fuera de rango.';
  end if;
  if p_geometria ? 'pixel_height'
     and (p_geometria ->> 'pixel_height')::numeric not between 150 and 3000 then
    raise exception 'pixel_height fuera de rango.';
  end if;

  perform 1
  from public."ZUMAC_METRICS_WIDGETS_APPGT" w
  where w.id = p_widget_id
    and w.dashboard_id = p_dashboard_id
    and w.empresa_id = v_empresa_id
    and w.activo
    and w.deleted_at is null
  for update;

  update public."ZUMAC_METRICS_WIDGETS_APPGT" w
  set configuracion = coalesce(w.configuracion, '{}'::jsonb) || p_geometria
  where w.id = p_widget_id
    and w.dashboard_id = p_dashboard_id
    and w.empresa_id = v_empresa_id
    and w.activo
    and w.deleted_at is null
  returning w.configuracion, w.updated_at
  into v_configuracion, v_updated_at;

  if not found then
    raise exception 'Grafico no encontrado.';
  end if;

  return jsonb_build_object(
    'id', p_widget_id,
    'dashboard_id', p_dashboard_id,
    'configuracion', v_configuracion,
    'updated_at', v_updated_at,
    'guardado', true
  );
end
$$;

revoke all on function public.appgt_guardar_geometria_widget_metrics_v2(
  uuid, uuid, jsonb
) from public, anon;
grant execute on function public.appgt_guardar_geometria_widget_metrics_v2(
  uuid, uuid, jsonb
) to authenticated, service_role;

-- Completa la clasificacion de modulos heredados a partir de sus tablas. La
-- migracion anterior solo uso el nombre del modulo y dejo, por ejemplo, SST y
-- Osmosis dentro del contenedor generico Formatos.
with module_domains as (
  select
    m.empresa_id,
    m.id,
    substr(md5(m.empresa_id::text), 1, 10) suffix,
    bool_or(
      upper(coalesce(f.tabla_destino, '')) ~ '^(GH-|GT-|PLANILLA_)'
      or public.appgt_normalizar_clave(coalesce(m.nombre, '')) ~
        'GESTIONHUMANA|PLANILLA|PERSONAL'
    ) is_human,
    bool_or(
      upper(coalesce(f.tabla_destino, '')) like 'ALM-%'
      or public.appgt_normalizar_clave(coalesce(m.nombre, '')) ~
        'ALMACEN|INVENTARIO'
    ) is_warehouse,
    bool_or(
      public.appgt_normalizar_clave(
        coalesce(m.nombre, '') || ' ' || coalesce(f.nombre, '')
      ) ~ 'FINAN|CONTAB|PRESUPUEST|COSTO'
    ) is_finance,
    bool_or(
      public.appgt_normalizar_clave(
        coalesce(m.nombre, '') || ' ' || coalesce(f.nombre, '')
      ) ~ 'COMPRA|PROVEED'
    ) is_purchase,
    bool_or(
      public.appgt_normalizar_clave(
        coalesce(m.nombre, '') || ' ' || coalesce(f.nombre, '')
      ) ~ 'EXPORT|VENTA|COMERCIAL'
    ) is_sales,
    bool_or(
      upper(coalesce(f.tabla_destino, '')) ~
        '^(SST-|OS-|RF-|SN-|SIG-|SIGP-|CO-|PROD-|MQ-)'
      or public.appgt_normalizar_clave(coalesce(m.nombre, '')) ~
        'SST|OSMOSIS|RIEGO|SANIDAD|CALIDAD|COSECHA|PACKING|PRODUC|MAQUINARIA|OPERACION|SEGURIDAD'
    ) is_operations
  from public."MATRIZ_MODULOS_APPGT" m
  left join public."MATRIZ_FORMATOS_APPGT" f
    on f.empresa_id = m.empresa_id
    and f.modulo_id = m.id
    and coalesce(f.activo, true)
    and not coalesce(f.eliminado, false)
  where coalesce(m.activo, true)
    and not coalesce(m.eliminado, false)
    and m.id not like 'erp\_%' escape '\'
    and public.appgt_normalizar_clave(coalesce(m.seccion, '')) not like '%MATRIZ%'
  group by m.empresa_id, m.id
), classified as (
  select empresa_id, id,
    case
      when is_human then 'erp_gestion_humana_' || suffix
      when is_warehouse then 'erp_almacen_' || suffix
      when is_finance then 'erp_finanzas_' || suffix
      when is_purchase then 'erp_compras_' || suffix
      when is_sales then 'erp_ventas_' || suffix
      when is_operations then 'erp_operaciones_' || suffix
    end seccion
  from module_domains
)
update public."MATRIZ_MODULOS_APPGT" m
set seccion = c.seccion,
    updated_at = now()
from classified c
where c.empresa_id = m.empresa_id
  and c.id = m.id
  and c.seccion is not null
  and m.seccion is distinct from c.seccion;

-- Los permisos por formato existentes deben apuntar a la seccion actual del
-- modulo. Esto conserva todos los formatos que el usuario ya podia utilizar.
update public."PERMISOS_DE_USUARIOS_APPGT" p
set seccion = m.seccion,
    updated_at = now()
from public."MATRIZ_MODULOS_APPGT" m
where m.empresa_id = p.empresa_id
  and m.id = p.modulo
  and p.activo
  and not p.eliminado
  and p.seccion is distinct from m.seccion;

-- ADMIN y GESTOR reciben los formatos del nucleo ERP. Los demas perfiles
-- conservan la herencia por dominio instalada en la migracion anterior.
with erp_access as (
  select
    ue.empresa_id,
    ue.user_id,
    m.seccion,
    m.id modulo_id,
    f.id formato_id,
    f.tabla_destino
  from public."USUARIOS_EMPRESAS_APPGT" ue
  join public."MATRIZ_FORMATOS_APPGT" f
    on f.empresa_id = ue.empresa_id
    and f.tabla_destino like 'ERP\_%' escape '\'
    and f.activo
    and not f.eliminado
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id = f.empresa_id and m.id = f.modulo_id
  where ue.activo
    and ue.rol in ('ADMIN', 'GESTOR')
)
insert into public."PERMISOS_DE_USUARIOS_APPGT" (
  empresa_id, user_id, seccion, modulo, formato, tabla_destino,
  can_view, can_insert, can_update, can_delete, can_export, can_import,
  can_review, can_approve,
  activo, created_at, updated_at, estado_sync, eliminado
)
select
  empresa_id, user_id, seccion, modulo_id, formato_id, tabla_destino,
  true,
  tabla_destino <> 'ERP_STOCK_APPGT',
  tabla_destino <> 'ERP_STOCK_APPGT',
  tabla_destino <> 'ERP_STOCK_APPGT',
  true, true, true, true,
  true, now(), now(), 'sincronizado', false
from erp_access
on conflict (user_id, modulo, formato) do update set
  empresa_id = excluded.empresa_id,
  seccion = excluded.seccion,
  tabla_destino = excluded.tabla_destino,
  can_view = true,
  can_insert = excluded.can_insert,
  can_update = excluded.can_update,
  can_delete = excluded.can_delete,
  can_export = true,
  can_import = true,
  can_review = true,
  can_approve = true,
  activo = true,
  eliminado = false,
  updated_at = now();

-- Reactiva o crea el permiso de cada seccion que contiene al menos un modulo
-- visible para el usuario. Esta era la pieza ausente que oculto formatos y ERP.
with needed_sections as (
  select distinct p.empresa_id, p.user_id, m.seccion seccion_id
  from public."PERMISOS_DE_USUARIOS_APPGT" p
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id = p.empresa_id and m.id = p.modulo
  join public."MATRIZ_SECCIONES_APPGT" s
    on s.empresa_id = m.empresa_id and s.id = m.seccion
  where p.activo and not p.eliminado and p.can_view
    and m.activo and not m.eliminado
    and s.activo and not s.eliminado
  union
  select distinct ue.empresa_id, ue.user_id, s.id
  from public."USUARIOS_EMPRESAS_APPGT" ue
  join public."MATRIZ_SECCIONES_APPGT" s
    on s.empresa_id = ue.empresa_id
    and s.id like 'erp\_%' escape '\'
  where ue.activo and ue.rol in ('ADMIN', 'GESTOR')
)
update public."PERMISOS_SECCIONES_APPGT" p
set seccion = n.seccion_id,
    seccion_id = n.seccion_id,
    can_view = true,
    activo = true,
    eliminado = false,
    updated_at = now()
from needed_sections n
where p.empresa_id = n.empresa_id
  and p.user_id = n.user_id
  and coalesce(nullif(btrim(p.seccion), ''), btrim(p.seccion_id)) = n.seccion_id;

with needed_sections as (
  select distinct p.empresa_id, p.user_id, m.seccion seccion_id
  from public."PERMISOS_DE_USUARIOS_APPGT" p
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id = p.empresa_id and m.id = p.modulo
  join public."MATRIZ_SECCIONES_APPGT" s
    on s.empresa_id = m.empresa_id and s.id = m.seccion
  where p.activo and not p.eliminado and p.can_view
    and m.activo and not m.eliminado
    and s.activo and not s.eliminado
  union
  select distinct ue.empresa_id, ue.user_id, s.id
  from public."USUARIOS_EMPRESAS_APPGT" ue
  join public."MATRIZ_SECCIONES_APPGT" s
    on s.empresa_id = ue.empresa_id
    and s.id like 'erp\_%' escape '\'
  where ue.activo and ue.rol in ('ADMIN', 'GESTOR')
)
insert into public."PERMISOS_SECCIONES_APPGT" (
  empresa_id, user_id, seccion, seccion_id,
  can_view, can_insert, can_update, can_delete,
  activo, eliminado, created_at, updated_at
)
select
  n.empresa_id, n.user_id, n.seccion_id, n.seccion_id,
  true, false, false, false,
  true, false, now(), now()
from needed_sections n
where not exists (
  select 1
  from public."PERMISOS_SECCIONES_APPGT" p
  where p.empresa_id = n.empresa_id
    and p.user_id = n.user_id
    and coalesce(nullif(btrim(p.seccion), ''), btrim(p.seccion_id)) = n.seccion_id
);

select public.appgt_instalar_seguimiento_tablas_v1();

commit;
