begin;

-- ---------------------------------------------------------------------------
-- Navegacion por areas de negocio. Los ids incluyen la empresa para respetar
-- la llave primaria historica de texto y permitir mas de un tenant.
-- ---------------------------------------------------------------------------

create temporary table erp_areas (
  area text primary key,
  nombre text not null,
  icono text not null,
  color text not null,
  orden integer not null
) on commit drop;

insert into erp_areas values
  ('operaciones', 'Operaciones', 'precision_manufacturing_outlined', '#176B87', 10),
  ('finanzas', 'Finanzas', 'account_balance_outlined', '#3957A5', 20),
  ('almacen', 'Almacenes e Inventarios', 'warehouse_outlined', '#A0621A', 30),
  ('compras', 'Compras y Proveedores', 'shopping_cart_outlined', '#7A4F9A', 40),
  ('ventas', 'Ventas y Exportaciones', 'public_outlined', '#147A5B', 50),
  ('gestion_humana', 'Gestion Humana', 'groups_outlined', '#A33E5C', 60);

insert into public."MATRIZ_SECCIONES_APPGT" (
  id, empresa_id, nombre, icono, color, orden, activo, rubro_id,
  tipo_contenido, ruta_flutter
)
select
  'erp_' || a.area || '_' || substr(md5(r.empresa_id::text), 1, 10),
  r.empresa_id, a.nombre, a.icono, a.color, a.orden, true, r.id,
  'FORMATOS', null
from public."RUBROS_APPGT" r
cross join erp_areas a
where r.activo and r.deleted_at is null
on conflict (id) do update set
  nombre = excluded.nombre,
  icono = excluded.icono,
  color = excluded.color,
  orden = excluded.orden,
  activo = true,
  rubro_id = excluded.rubro_id,
  tipo_contenido = 'FORMATOS',
  deleted_at = null,
  eliminado = false,
  updated_at = now();

create temporary table erp_modules (
  module_key text primary key,
  area text not null references erp_areas(area),
  nombre text not null,
  icono text not null,
  color text not null,
  orden integer not null
) on commit drop;

insert into erp_modules values
  ('produccion_planificacion', 'operaciones', 'Produccion y Planificacion', 'calendar_month_outlined', '#176B87', 10),
  ('costos_agroexportadores', 'operaciones', 'Costos Agroexportadores', 'agriculture_outlined', '#237A68', 20),
  ('contabilidad_finanzas', 'finanzas', 'Contabilidad y Finanzas', 'account_balance_wallet_outlined', '#3957A5', 10),
  ('inventarios_almacenes', 'almacen', 'Inventarios y Almacenes', 'inventory_2_outlined', '#A0621A', 10),
  ('compras_proveedores', 'compras', 'Compras y Proveedores', 'local_shipping_outlined', '#7A4F9A', 10),
  ('ventas_exportaciones', 'ventas', 'Ventas y Exportaciones', 'sailing_outlined', '#147A5B', 10),
  ('gestion_humana_planilla', 'gestion_humana', 'Gestion Humana y Planilla Completa', 'badge_outlined', '#A33E5C', 10);

insert into public."MATRIZ_MODULOS_APPGT" (
  id, empresa_id, nombre, seccion, orden, activo, rubro_id, icono, color
)
select
  'erp_' || m.module_key || '_' || substr(md5(r.empresa_id::text), 1, 10),
  r.empresa_id, m.nombre,
  'erp_' || m.area || '_' || substr(md5(r.empresa_id::text), 1, 10),
  m.orden, true, r.id, m.icono, m.color
from public."RUBROS_APPGT" r
cross join erp_modules m
where r.activo and r.deleted_at is null
on conflict (id) do update set
  nombre = excluded.nombre,
  seccion = excluded.seccion,
  orden = excluded.orden,
  activo = true,
  rubro_id = excluded.rubro_id,
  icono = excluded.icono,
  color = excluded.color,
  deleted_at = null,
  eliminado = false,
  updated_at = now();

-- Reubica solo modulos de negocio reconocibles; las vistas tecnicas, matrices
-- y registros locales conservan su seccion especial y sus datos intactos.
do $$
declare
  v_rubro record;
  v_suffix text;
begin
  for v_rubro in
    select * from public."RUBROS_APPGT" where activo and deleted_at is null
  loop
    v_suffix := substr(md5(v_rubro.empresa_id::text), 1, 10);
    update public."MATRIZ_MODULOS_APPGT" m set
      seccion = case
        when public.appgt_normalizar_clave(m.nombre) ~ 'GESTIONHUMANA|PLANILLA|PERSONAL'
          then 'erp_gestion_humana_' || v_suffix
        when public.appgt_normalizar_clave(m.nombre) ~ 'ALMACEN|INVENTARIO'
          then 'erp_almacen_' || v_suffix
        when public.appgt_normalizar_clave(m.nombre) ~ 'COMPRA|PROVEED'
          then 'erp_compras_' || v_suffix
        when public.appgt_normalizar_clave(m.nombre) ~ 'EXPORT|VENTA|COMERCIAL'
          then 'erp_ventas_' || v_suffix
        when public.appgt_normalizar_clave(m.nombre) ~ 'FINAN|CONTAB|PRESUPUEST|COSTO'
          then 'erp_finanzas_' || v_suffix
        when public.appgt_normalizar_clave(m.nombre) ~ 'RIEGO|SANIDAD|CALIDAD|COSECHA|PACKING|PRODUC|MAQUINARIA|OPERACION|SEGURIDAD'
          then 'erp_operaciones_' || v_suffix
        else m.seccion
      end,
      updated_at = now()
    where m.empresa_id = v_rubro.empresa_id
      and m.rubro_id is not distinct from v_rubro.id
      and coalesce(m.activo, true)
      and not coalesce(m.eliminado, false)
      and public.appgt_normalizar_clave(m.seccion) not like '%MATRIZ%';
  end loop;
end
$$;

create temporary table erp_formats (
  format_key text primary key,
  module_key text not null references erp_modules(module_key),
  tabla text not null,
  nombre text not null,
  orden integer not null,
  access_domain text not null
) on commit drop;

insert into erp_formats values
  ('proveedores','compras_proveedores','ERP_PROVEEDORES_APPGT','Proveedores',10,'ALMACEN'),
  ('solicitudes_compra','compras_proveedores','ERP_SOLICITUDES_COMPRA_APPGT','Solicitudes de Compra',20,'ALMACEN'),
  ('ordenes_compra','compras_proveedores','ERP_ORDENES_COMPRA_APPGT','Ordenes de Compra',30,'ALMACEN'),
  ('ordenes_compra_detalle','compras_proveedores','ERP_ORDENES_COMPRA_DETALLE_APPGT','Detalle de Ordenes de Compra',40,'ALMACEN'),
  ('almacenes','inventarios_almacenes','ERP_ALMACENES_APPGT','Almacenes',10,'ALMACEN'),
  ('articulos','inventarios_almacenes','ERP_ARTICULOS_APPGT','Articulos e Insumos',20,'ALMACEN'),
  ('stock','inventarios_almacenes','ERP_STOCK_APPGT','Stock por Almacen y Lote',30,'ALMACEN'),
  ('movimientos_inventario','inventarios_almacenes','ERP_MOVIMIENTOS_INVENTARIO_APPGT','Movimientos de Inventario',40,'ALMACEN'),
  ('planes_produccion','produccion_planificacion','ERP_PLANES_PRODUCCION_APPGT','Planes de Produccion',10,'PRODUCCION'),
  ('ordenes_produccion','produccion_planificacion','ERP_ORDENES_PRODUCCION_APPGT','Ordenes de Produccion',20,'PRODUCCION'),
  ('partes_produccion','produccion_planificacion','ERP_PARTES_PRODUCCION_APPGT','Partes de Produccion',30,'PRODUCCION'),
  ('costos_agroexportadores','costos_agroexportadores','ERP_COSTOS_AGROEXPORTADORES_APPGT','Costos Agroexportadores',10,'COSTOS'),
  ('clientes','ventas_exportaciones','ERP_CLIENTES_APPGT','Clientes',10,'VENTAS'),
  ('pedidos_venta','ventas_exportaciones','ERP_PEDIDOS_VENTA_APPGT','Pedidos de Venta',20,'VENTAS'),
  ('pedidos_venta_detalle','ventas_exportaciones','ERP_PEDIDOS_VENTA_DETALLE_APPGT','Detalle de Pedidos de Venta',30,'VENTAS'),
  ('exportaciones','ventas_exportaciones','ERP_EXPORTACIONES_APPGT','Exportaciones',40,'VENTAS'),
  ('periodos_contables','contabilidad_finanzas','ERP_PERIODOS_CONTABLES_APPGT','Periodos Contables',10,'FINANZAS'),
  ('cuentas_contables','contabilidad_finanzas','ERP_CUENTAS_CONTABLES_APPGT','Plan de Cuentas',20,'FINANZAS'),
  ('asientos_contables','contabilidad_finanzas','ERP_ASIENTOS_CONTABLES_APPGT','Asientos Contables',30,'FINANZAS'),
  ('asientos_detalle','contabilidad_finanzas','ERP_ASIENTOS_DETALLE_APPGT','Detalle de Asientos',40,'FINANZAS'),
  ('tesoreria','contabilidad_finanzas','ERP_TESORERIA_MOVIMIENTOS_APPGT','Tesoreria y Conciliacion',50,'FINANZAS');

insert into public."MATRIZ_FORMATOS_APPGT" (
  id, empresa_id, modulo_id, nombre, tabla_destino, ruta_flutter,
  tabla_visible_app, orden, activo, rubro_id, auditable,
  created_at, updated_at, deleted_at, estado_sync, eliminado
)
select
  'erp_' || f.format_key || '_' || substr(md5(r.empresa_id::text), 1, 10),
  r.empresa_id,
  'erp_' || f.module_key || '_' || substr(md5(r.empresa_id::text), 1, 10),
  f.nombre, f.tabla, null, true, f.orden, true, r.id, true,
  now(), now(), null, 'sincronizado', false
from public."RUBROS_APPGT" r
cross join erp_formats f
where r.activo and r.deleted_at is null
on conflict (id) do update set
  modulo_id = excluded.modulo_id,
  nombre = excluded.nombre,
  tabla_destino = excluded.tabla_destino,
  tabla_visible_app = true,
  orden = excluded.orden,
  activo = true,
  rubro_id = excluded.rubro_id,
  auditable = true,
  deleted_at = null,
  eliminado = false,
  updated_at = now();

insert into public."MATRIZ_FORMATO_TABLAS_APPGT" (
  id, empresa_id, formato_id, nombre, tabla_destino, orden, activo,
  rubro_id, auditable, created_at, updated_at, deleted_at
)
select
  'erp_' || f.format_key || '_table_' || substr(md5(r.empresa_id::text), 1, 10),
  r.empresa_id,
  'erp_' || f.format_key || '_' || substr(md5(r.empresa_id::text), 1, 10),
  f.nombre, f.tabla, 0, true, r.id, true, now(), now(), null
from public."RUBROS_APPGT" r
cross join erp_formats f
where r.activo and r.deleted_at is null
on conflict (id) do update set
  formato_id = excluded.formato_id,
  nombre = excluded.nombre,
  tabla_destino = excluded.tabla_destino,
  activo = true,
  rubro_id = excluded.rubro_id,
  auditable = true,
  deleted_at = null,
  updated_at = now();

-- ---------------------------------------------------------------------------
-- Campos generados desde el esquema fisico: no se duplica la definicion SQL y
-- los resultados calculados se muestran en tabla sin enviarlos al guardar.
-- ---------------------------------------------------------------------------

with target as (
  select r.empresa_id, f.tabla
  from public."RUBROS_APPGT" r cross join erp_formats f
  where r.activo and r.deleted_at is null
), columns as (
  select t.empresa_id, t.tabla, c.column_name, c.data_type,
    c.is_nullable, c.column_default, c.is_generated, c.ordinal_position
  from target t
  join information_schema.columns c
    on c.table_schema = 'public' and c.table_name = t.tabla
  where c.column_name not in (
    'id','id_local','empresa_id','created_by','updated_by','created_at',
    'updated_at','deleted_at','eliminado','estado_sync','version'
  )
)
insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id, empresa_id, tabla_destino, campo, etiqueta, tipo, tipo_ui,
  requerido, visible, visible_tabla, editable, orden, activo,
  created_at, updated_at, estado_sync, eliminado
)
select
  'erp_field_' || substr(md5(empresa_id::text || '|' || tabla || '|' || column_name), 1, 24),
  empresa_id, tabla, column_name,
  initcap(replace(column_name, '_', ' ')),
  case
    when data_type in ('smallint','integer','bigint','numeric','decimal','real','double precision') then 'numeric'
    when data_type = 'boolean' then 'boolean'
    when data_type = 'date' then 'date'
    when data_type like 'timestamp%' then 'timestamptz'
    else 'text'
  end,
  case
    when data_type in ('smallint','integer','bigint','numeric','decimal','real','double precision') then 'number'
    when data_type = 'boolean' then 'switch'
    when data_type = 'date' then 'date'
    when data_type like 'timestamp%' then 'datetime'
    else 'text'
  end,
  (is_nullable = 'NO' and column_default is null and is_generated <> 'ALWAYS'),
  (is_generated <> 'ALWAYS'),
  true,
  (is_generated <> 'ALWAYS'),
  ordinal_position,
  true, now(), now(), 'sincronizado', false
from columns
on conflict (tabla_destino, campo) do update set
  empresa_id = excluded.empresa_id,
  etiqueta = excluded.etiqueta,
  tipo = excluded.tipo,
  tipo_ui = excluded.tipo_ui,
  requerido = excluded.requerido,
  visible = excluded.visible,
  visible_tabla = true,
  editable = excluded.editable,
  orden = excluded.orden,
  activo = true,
  eliminado = false,
  updated_at = now();

-- Totales y saldos son responsabilidad del servidor.
update public."MATRIZ_CAMPOS_FORMATO_APPGT" set
  visible = false, visible_tabla = true, editable = false, updated_at = now()
where tabla_destino like 'ERP\_%' escape '\'
  and campo in (
    'subtotal','descuento','impuesto','total','costo_total','costo_total_pen',
    'importe_pen','total_debe','total_haber','cantidad_reservada','costo_promedio'
  );

-- Dropdowns de claves legibles. Se almacenan codigos de negocio en lugar de
-- UUID opacos, manteniendo FKs multiempresa en PostgreSQL.
update public."MATRIZ_CAMPOS_FORMATO_APPGT" set
  tipo_ui = 'dropdown',
  id_campo_dropdown = case campo
    when 'proveedor_codigo' then 'ERP_PROVEEDORES_APPGT.codigo'
    when 'almacen_codigo' then 'ERP_ALMACENES_APPGT.codigo'
    when 'articulo_codigo' then 'ERP_ARTICULOS_APPGT.codigo'
    when 'solicitud_numero' then 'ERP_SOLICITUDES_COMPRA_APPGT.numero'
    when 'orden_numero' then 'ERP_ORDENES_COMPRA_APPGT.numero'
    when 'plan_codigo' then 'ERP_PLANES_PRODUCCION_APPGT.codigo'
    when 'orden_codigo' then 'ERP_ORDENES_PRODUCCION_APPGT.codigo'
    when 'cliente_codigo' then 'ERP_CLIENTES_APPGT.codigo'
    when 'pedido_numero' then 'ERP_PEDIDOS_VENTA_APPGT.numero'
    when 'periodo_codigo' then 'ERP_PERIODOS_CONTABLES_APPGT.codigo'
    when 'cuenta_codigo' then 'ERP_CUENTAS_CONTABLES_APPGT.codigo'
    when 'cuenta_padre_codigo' then 'ERP_CUENTAS_CONTABLES_APPGT.codigo'
    when 'asiento_numero' then 'ERP_ASIENTOS_CONTABLES_APPGT.numero'
  end,
  updated_at = now()
where tabla_destino like 'ERP\_%' escape '\'
  and campo in (
    'proveedor_codigo','almacen_codigo','articulo_codigo','solicitud_numero',
    'orden_numero','plan_codigo','orden_codigo','cliente_codigo','pedido_numero',
    'periodo_codigo','cuenta_codigo','cuenta_padre_codigo','asiento_numero'
  );

update public."MATRIZ_CAMPOS_FORMATO_APPGT" set
  tipo_ui = 'dropdown',
  id_campo_dropdown = case campo
    when 'moneda' then '[PEN;USD;EUR]'
    when 'moneda_preferida' then '[PEN;USD;EUR]'
    when 'direccion' then '[1;-1]'
    when 'lote' then 'LOTES_VARIEDADES_GT.TURNO'
    when 'lote_agricola' then 'LOTES_VARIEDADES_GT.TURNO'
    when 'variedad' then 'LOTES_VARIEDADES_GT.VARIEDAD'
    when 'referencia_legacy' then 'SN-PRODUCTOS_FITOSANITARIOS.NOMBRE'
  end,
  updated_at = now()
where tabla_destino like 'ERP\_%' escape '\'
  and campo in ('moneda','moneda_preferida','direccion','lote','lote_agricola','variedad','referencia_legacy');

-- Estados y clasificaciones cerradas evitan variantes ortograficas que luego
-- rompen reportes o automatizaciones.
update public."MATRIZ_CAMPOS_FORMATO_APPGT" c set
  tipo_ui = 'dropdown',
  id_campo_dropdown = case c.tabla_destino
    when 'ERP_PROVEEDORES_APPGT' then '[ACTIVO;SUSPENDIDO;INACTIVO]'
    when 'ERP_ALMACENES_APPGT' then '[ACTIVO;INACTIVO]'
    when 'ERP_ARTICULOS_APPGT' then '[ACTIVO;INACTIVO]'
    when 'ERP_MOVIMIENTOS_INVENTARIO_APPGT' then '[BORRADOR;CONFIRMADO;ANULADO]'
    when 'ERP_SOLICITUDES_COMPRA_APPGT' then '[BORRADOR;ENVIADA;APROBADA;RECHAZADA;ATENDIDA;ANULADA]'
    when 'ERP_ORDENES_COMPRA_APPGT' then '[BORRADOR;EMITIDA;APROBADA;PARCIAL;RECIBIDA;CERRADA;ANULADA]'
    when 'ERP_PLANES_PRODUCCION_APPGT' then '[BORRADOR;APROBADO;EN_EJECUCION;CERRADO;ANULADO]'
    when 'ERP_ORDENES_PRODUCCION_APPGT' then '[PLANIFICADA;LIBERADA;EN_PROCESO;PAUSADA;COMPLETADA;CERRADA;ANULADA]'
    when 'ERP_PARTES_PRODUCCION_APPGT' then '[REGISTRADO;VALIDADO;ANULADO]'
    when 'ERP_COSTOS_AGROEXPORTADORES_APPGT' then '[REGISTRADO;CONTABILIZADO;ANULADO]'
    when 'ERP_CLIENTES_APPGT' then '[ACTIVO;BLOQUEADO;INACTIVO]'
    when 'ERP_PEDIDOS_VENTA_APPGT' then '[BORRADOR;CONFIRMADO;EN_PREPARACION;DESPACHADO;FACTURADO;CERRADO;ANULADO]'
    when 'ERP_EXPORTACIONES_APPGT' then '[PLANIFICADA;RESERVADA;EMBARCADA;EN_TRANSITO;ARRIBADA;CERRADA;ANULADA]'
    when 'ERP_PERIODOS_CONTABLES_APPGT' then '[ABIERTO;CERRADO;BLOQUEADO]'
    when 'ERP_CUENTAS_CONTABLES_APPGT' then '[ACTIVO;INACTIVO]'
    when 'ERP_ASIENTOS_CONTABLES_APPGT' then '[BORRADOR;POSTEADO;ANULADO]'
    when 'ERP_TESORERIA_MOVIMIENTOS_APPGT' then '[REGISTRADO;CONCILIADO;CONTABILIZADO;ANULADO]'
    else c.id_campo_dropdown
  end,
  updated_at = now()
where c.tabla_destino like 'ERP\_%' escape '\' and c.campo = 'estado';

-- Otras enumeraciones centrales.
update public."MATRIZ_CAMPOS_FORMATO_APPGT" set tipo_ui = 'dropdown',
  id_campo_dropdown = case
    when tabla_destino = 'ERP_ALMACENES_APPGT' and campo = 'tipo'
      then '[GENERAL;AGROQUIMICOS;MATERIA_PRIMA;PACKING;PRODUCTO_TERMINADO;TRANSITO]'
    when tabla_destino = 'ERP_ARTICULOS_APPGT' and campo = 'tipo'
      then '[INSUMO;AGROQUIMICO;ENVASE;EMBALAJE;MATERIA_PRIMA;PRODUCTO_TERMINADO;SERVICIO;ACTIVO]'
    when tabla_destino = 'ERP_COSTOS_AGROEXPORTADORES_APPGT' and campo = 'tipo_costo'
      then '[MANO_OBRA;INSUMO;MAQUINARIA;SERVICIO;INDIRECTO;LOGISTICO;PACKING;EXPORTACION]'
    when tabla_destino = 'ERP_CUENTAS_CONTABLES_APPGT' and campo = 'tipo'
      then '[ACTIVO;PASIVO;PATRIMONIO;INGRESO;GASTO;ORDEN]'
    when tabla_destino = 'ERP_CUENTAS_CONTABLES_APPGT' and campo = 'naturaleza'
      then '[DEUDORA;ACREEDORA]'
    when tabla_destino = 'ERP_TESORERIA_MOVIMIENTOS_APPGT' and campo = 'tipo'
      then '[INGRESO;EGRESO;TRANSFERENCIA]'
    else id_campo_dropdown
  end,
  updated_at = now()
where (tabla_destino, campo) in (
  ('ERP_ALMACENES_APPGT','tipo'),('ERP_ARTICULOS_APPGT','tipo'),
  ('ERP_COSTOS_AGROEXPORTADORES_APPGT','tipo_costo'),
  ('ERP_CUENTAS_CONTABLES_APPGT','tipo'),
  ('ERP_CUENTAS_CONTABLES_APPGT','naturaleza'),
  ('ERP_TESORERIA_MOVIMIENTOS_APPGT','tipo')
);

-- La planilla existente ya contiene calculos productivos; solo se integra a la
-- nueva agrupacion y se renombra de forma clara.
update public."MATRIZ_FORMATOS_APPGT" f set
  modulo_id = 'erp_gestion_humana_planilla_' || substr(md5(f.empresa_id::text), 1, 10),
  nombre = case
    when f.tabla_destino = 'PLANILLA_TRABAJADORES_ZUMAC'
      then 'Planilla Completa Agroexportadora'
    else f.nombre
  end,
  updated_at = now()
where f.tabla_destino in (
  'PLANILLA_TRABAJADORES_ZUMAC','MATRIZ_BENEFICIOS_SOCIALES',
  'GH-REGISTRO_PERSONAL_PLANILLA','GT-ASISTENCIA_PERSONAL','GT-TAREO_PERSONAL'
)
and f.activo and not f.eliminado;

-- ---------------------------------------------------------------------------
-- Permisos: se heredan por dominio desde procesos que ya operaban en la misma
-- empresa. No se conceden secciones completas ni acceso transversal nuevo.
-- ---------------------------------------------------------------------------

with targets as (
  select r.empresa_id, f.*,
    'erp_' || f.format_key || '_' || substr(md5(r.empresa_id::text), 1, 10) formato_id,
    'erp_' || f.module_key || '_' || substr(md5(r.empresa_id::text), 1, 10) modulo_id,
    'erp_' || m.area || '_' || substr(md5(r.empresa_id::text), 1, 10) seccion_id
  from public."RUBROS_APPGT" r
  cross join erp_formats f
  join erp_modules m on m.module_key = f.module_key
  where r.activo and r.deleted_at is null
), source_permissions as (
  select distinct on (t.empresa_id, t.format_key, p.user_id)
    t.*, p.user_id,
    p.can_view, p.can_insert, p.can_update, p.can_delete,
    p.can_export, p.can_import
  from targets t
  join public."PERMISOS_DE_USUARIOS_APPGT" p
    on p.empresa_id = t.empresa_id and p.user_id is not null
    and p.activo and not p.eliminado
  left join public."MATRIZ_FORMATOS_APPGT" source_format
    on source_format.empresa_id = p.empresa_id
    and (
      source_format.id = p.formato
      or source_format.tabla_destino = p.formato
      or source_format.tabla_destino = p.tabla_destino
    )
  left join public."MATRIZ_MODULOS_APPGT" source_module
    on source_module.empresa_id = source_format.empresa_id
    and source_module.id = source_format.modulo_id
  where case t.access_domain
    when 'ALMACEN' then public.appgt_normalizar_clave(
      coalesce(source_module.nombre,'') || ' ' || coalesce(source_format.nombre,'') || ' ' || coalesce(source_format.tabla_destino,'')
    ) ~ 'ALMACEN|INVENTARIO|AGROQUIM|RECEPCION|SALIDA'
    when 'PRODUCCION' then public.appgt_normalizar_clave(
      coalesce(source_module.nombre,'') || ' ' || coalesce(source_format.nombre,'') || ' ' || coalesce(source_format.tabla_destino,'')
    ) ~ 'PRODUC|COSECHA|PACKING|PESAJE|TAREO'
    when 'COSTOS' then public.appgt_normalizar_clave(
      coalesce(source_module.nombre,'') || ' ' || coalesce(source_format.nombre,'') || ' ' || coalesce(source_format.tabla_destino,'')
    ) ~ 'COSTO|PRESUPUEST|TAREO|PLANILLA'
    when 'VENTAS' then public.appgt_normalizar_clave(
      coalesce(source_module.nombre,'') || ' ' || coalesce(source_format.nombre,'') || ' ' || coalesce(source_format.tabla_destino,'')
    ) ~ 'EXPORT|VENTA|DESPACHO|PACKING'
    when 'FINANZAS' then public.appgt_normalizar_clave(
      coalesce(source_module.nombre,'') || ' ' || coalesce(source_format.nombre,'') || ' ' || coalesce(source_format.tabla_destino,'')
    ) ~ 'COSTO|PRESUPUEST|PLANILLA|FINAN|CONTAB'
    else false
  end
  order by t.empresa_id, t.format_key, p.user_id, p.updated_at desc nulls last
)
insert into public."PERMISOS_DE_USUARIOS_APPGT" (
  empresa_id, user_id, seccion, modulo, formato, tabla_destino,
  can_view, can_insert, can_update, can_delete, can_export, can_import,
  activo, created_at, updated_at, estado_sync, eliminado
)
select empresa_id, user_id, seccion_id, modulo_id, formato_id, tabla,
  can_view,
  case when tabla = 'ERP_STOCK_APPGT' then false else can_insert end,
  case when tabla = 'ERP_STOCK_APPGT' then false else can_update end,
  case when tabla = 'ERP_STOCK_APPGT' then false else can_delete end,
  can_export, can_import, true, now(), now(), 'sincronizado', false
from source_permissions
on conflict (user_id, modulo, formato) do update set
  empresa_id = excluded.empresa_id,
  seccion = excluded.seccion,
  tabla_destino = excluded.tabla_destino,
  can_view = excluded.can_view,
  can_insert = excluded.can_insert,
  can_update = excluded.can_update,
  can_delete = excluded.can_delete,
  can_export = excluded.can_export,
  can_import = excluded.can_import,
  activo = true,
  eliminado = false,
  updated_at = now();

-- Las tablas nuevas participan de la descarga incremental sin enumerarlas a
-- mano: MATRIZ_FORMATO_TABLAS_APPGT e id_campo_dropdown las hacen descubribles.
select public.appgt_instalar_seguimiento_tablas_v1();

commit;
