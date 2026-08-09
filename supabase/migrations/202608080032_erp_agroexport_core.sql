begin;

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Maestros de terceros, almacenes y articulos.
-- Todos los documentos conservan id_local para la sincronizacion offline.
-- ---------------------------------------------------------------------------

create table if not exists public."ERP_PROVEEDORES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  codigo text not null,
  tipo_documento text not null default 'RUC',
  numero_documento text,
  razon_social text not null,
  nombre_comercial text,
  pais text not null default 'PERU',
  direccion text,
  telefono text,
  email text,
  contacto text,
  moneda_preferida text not null default 'PEN' check (moneda_preferida in ('PEN','USD','EUR')),
  dias_credito integer not null default 0 check (dias_credito >= 0),
  homologado boolean not null default false,
  fecha_homologacion date,
  calificacion numeric(5,2) check (calificacion between 0 and 100),
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO','SUSPENDIDO','INACTIVO')),
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  unique (empresa_id, codigo),
  unique (empresa_id, tipo_documento, numero_documento)
);

create table if not exists public."ERP_ALMACENES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  codigo text not null,
  nombre text not null,
  tipo text not null default 'GENERAL' check (tipo in ('GENERAL','AGROQUIMICOS','MATERIA_PRIMA','PACKING','PRODUCTO_TERMINADO','TRANSITO')),
  ubicacion text,
  responsable text,
  permite_stock_negativo boolean not null default false,
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO','INACTIVO')),
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  unique (empresa_id, codigo)
);

create table if not exists public."ERP_ARTICULOS_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  codigo text not null,
  nombre text not null,
  tipo text not null default 'INSUMO' check (tipo in ('INSUMO','AGROQUIMICO','ENVASE','EMBALAJE','MATERIA_PRIMA','PRODUCTO_TERMINADO','SERVICIO','ACTIVO')),
  categoria text,
  unidad_medida text not null,
  costo_estandar numeric(20,6) not null default 0 check (costo_estandar >= 0),
  stock_minimo numeric(20,6) not null default 0 check (stock_minimo >= 0),
  stock_maximo numeric(20,6) check (stock_maximo is null or stock_maximo >= stock_minimo),
  controla_lote boolean not null default false,
  controla_vencimiento boolean not null default false,
  afecto_igv boolean not null default true,
  tabla_legacy text,
  referencia_legacy text,
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO','INACTIVO')),
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  unique (empresa_id, codigo)
);

create table if not exists public."ERP_STOCK_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  almacen_codigo text not null,
  articulo_codigo text not null,
  lote text,
  fecha_vencimiento date,
  cantidad numeric(20,6) not null default 0,
  cantidad_reservada numeric(20,6) not null default 0 check (cantidad_reservada >= 0),
  costo_promedio numeric(20,6) not null default 0 check (costo_promedio >= 0),
  updated_at timestamptz not null default now(),
  constraint erp_stock_reserva_ck check (cantidad_reservada <= greatest(cantidad, 0)),
  constraint erp_stock_almacen_fk foreign key (empresa_id, almacen_codigo)
    references public."ERP_ALMACENES_APPGT"(empresa_id, codigo),
  constraint erp_stock_articulo_fk foreign key (empresa_id, articulo_codigo)
    references public."ERP_ARTICULOS_APPGT"(empresa_id, codigo),
  unique nulls not distinct (empresa_id, almacen_codigo, articulo_codigo, lote)
);

create table if not exists public."ERP_MOVIMIENTOS_INVENTARIO_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  numero text not null,
  fecha timestamptz not null default now(),
  almacen_codigo text not null,
  articulo_codigo text not null,
  lote text,
  fecha_vencimiento date,
  tipo_movimiento text not null,
  direccion smallint not null check (direccion in (-1, 1)),
  cantidad numeric(20,6) not null check (cantidad > 0),
  costo_unitario numeric(20,6) not null default 0 check (costo_unitario >= 0),
  costo_total numeric(20,6) not null default 0,
  documento_origen_tipo text,
  documento_origen_codigo text,
  centro_costo text,
  lote_agricola text,
  observacion text,
  estado text not null default 'BORRADOR' check (estado in ('BORRADOR','CONFIRMADO','ANULADO')),
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_mov_almacen_fk foreign key (empresa_id, almacen_codigo)
    references public."ERP_ALMACENES_APPGT"(empresa_id, codigo),
  constraint erp_mov_articulo_fk foreign key (empresa_id, articulo_codigo)
    references public."ERP_ARTICULOS_APPGT"(empresa_id, codigo),
  unique (empresa_id, numero)
);

-- ---------------------------------------------------------------------------
-- Compras y abastecimiento.
-- ---------------------------------------------------------------------------

create table if not exists public."ERP_SOLICITUDES_COMPRA_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  numero text not null,
  fecha date not null default current_date,
  fecha_necesidad date,
  solicitante text not null,
  area text,
  centro_costo text,
  justificacion text,
  monto_estimado numeric(20,6) not null default 0 check (monto_estimado >= 0),
  moneda text not null default 'PEN' check (moneda in ('PEN','USD','EUR')),
  estado text not null default 'BORRADOR' check (estado in ('BORRADOR','ENVIADA','APROBADA','RECHAZADA','ATENDIDA','ANULADA')),
  aprobado_por uuid references auth.users(id),
  aprobado_at timestamptz,
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  unique (empresa_id, numero)
);

create table if not exists public."ERP_ORDENES_COMPRA_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  numero text not null,
  solicitud_numero text,
  proveedor_codigo text not null,
  fecha_emision date not null default current_date,
  fecha_entrega date,
  moneda text not null default 'PEN' check (moneda in ('PEN','USD','EUR')),
  tipo_cambio numeric(18,6) not null default 1 check (tipo_cambio > 0),
  condicion_pago text,
  almacen_codigo text,
  subtotal numeric(20,6) not null default 0,
  descuento numeric(20,6) not null default 0,
  impuesto numeric(20,6) not null default 0,
  total numeric(20,6) not null default 0,
  estado text not null default 'BORRADOR' check (estado in ('BORRADOR','EMITIDA','APROBADA','PARCIAL','RECIBIDA','CERRADA','ANULADA')),
  observacion text,
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_oc_proveedor_fk foreign key (empresa_id, proveedor_codigo)
    references public."ERP_PROVEEDORES_APPGT"(empresa_id, codigo),
  constraint erp_oc_solicitud_fk foreign key (empresa_id, solicitud_numero)
    references public."ERP_SOLICITUDES_COMPRA_APPGT"(empresa_id, numero),
  constraint erp_oc_almacen_fk foreign key (empresa_id, almacen_codigo)
    references public."ERP_ALMACENES_APPGT"(empresa_id, codigo),
  unique (empresa_id, numero)
);

create table if not exists public."ERP_ORDENES_COMPRA_DETALLE_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  orden_numero text not null,
  linea integer not null check (linea > 0),
  articulo_codigo text not null,
  descripcion text,
  cantidad numeric(20,6) not null check (cantidad > 0),
  unidad_medida text not null,
  precio_unitario numeric(20,6) not null check (precio_unitario >= 0),
  descuento_porcentaje numeric(9,6) not null default 0 check (descuento_porcentaje between 0 and 100),
  impuesto_porcentaje numeric(9,6) not null default 18 check (impuesto_porcentaje between 0 and 100),
  subtotal numeric(20,6) generated always as (round(cantidad * precio_unitario * (1 - descuento_porcentaje / 100), 6)) stored,
  impuesto numeric(20,6) generated always as (round(cantidad * precio_unitario * (1 - descuento_porcentaje / 100) * impuesto_porcentaje / 100, 6)) stored,
  total numeric(20,6) generated always as (round(cantidad * precio_unitario * (1 - descuento_porcentaje / 100) * (1 + impuesto_porcentaje / 100), 6)) stored,
  cantidad_recibida numeric(20,6) not null default 0 check (cantidad_recibida >= 0 and cantidad_recibida <= cantidad),
  centro_costo text,
  lote_agricola text,
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_ocd_orden_fk foreign key (empresa_id, orden_numero)
    references public."ERP_ORDENES_COMPRA_APPGT"(empresa_id, numero) on delete cascade,
  constraint erp_ocd_articulo_fk foreign key (empresa_id, articulo_codigo)
    references public."ERP_ARTICULOS_APPGT"(empresa_id, codigo),
  unique (empresa_id, orden_numero, linea)
);

-- ---------------------------------------------------------------------------
-- Produccion, planificacion y costos agroexportadores.
-- ---------------------------------------------------------------------------

create table if not exists public."ERP_PLANES_PRODUCCION_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  codigo text not null,
  campana text not null,
  cultivo text not null,
  variedad text,
  fecha_inicio date not null,
  fecha_fin date not null,
  cantidad_planificada numeric(20,6) not null default 0 check (cantidad_planificada >= 0),
  unidad_medida text not null,
  responsable text,
  estado text not null default 'BORRADOR' check (estado in ('BORRADOR','APROBADO','EN_EJECUCION','CERRADO','ANULADO')),
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  check (fecha_fin >= fecha_inicio),
  unique (empresa_id, codigo)
);

create table if not exists public."ERP_ORDENES_PRODUCCION_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  codigo text not null,
  plan_codigo text,
  lote text not null,
  cultivo text,
  variedad text,
  labor text,
  centro_costo text,
  fecha_inicio date not null,
  fecha_fin_plan date,
  cantidad_objetivo numeric(20,6) not null default 0 check (cantidad_objetivo >= 0),
  unidad_medida text not null,
  responsable text,
  estado text not null default 'PLANIFICADA' check (estado in ('PLANIFICADA','LIBERADA','EN_PROCESO','PAUSADA','COMPLETADA','CERRADA','ANULADA')),
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_op_plan_fk foreign key (empresa_id, plan_codigo)
    references public."ERP_PLANES_PRODUCCION_APPGT"(empresa_id, codigo),
  unique (empresa_id, codigo)
);

create table if not exists public."ERP_PARTES_PRODUCCION_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  numero text not null,
  orden_codigo text not null,
  fecha date not null default current_date,
  turno text,
  lote text,
  labor text,
  centro_costo text,
  cantidad_producida numeric(20,6) not null default 0 check (cantidad_producida >= 0),
  cantidad_rechazada numeric(20,6) not null default 0 check (cantidad_rechazada >= 0),
  horas_maquina numeric(14,4) not null default 0 check (horas_maquina >= 0),
  horas_hombre numeric(14,4) not null default 0 check (horas_hombre >= 0),
  trabajadores integer not null default 0 check (trabajadores >= 0),
  observacion text,
  estado text not null default 'REGISTRADO' check (estado in ('REGISTRADO','VALIDADO','ANULADO')),
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_parte_orden_fk foreign key (empresa_id, orden_codigo)
    references public."ERP_ORDENES_PRODUCCION_APPGT"(empresa_id, codigo),
  unique (empresa_id, numero)
);

create table if not exists public."ERP_COSTOS_AGROEXPORTADORES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  numero text not null,
  fecha date not null default current_date,
  periodo text not null,
  centro_costo text not null,
  lote text,
  cultivo text,
  variedad text,
  labor text,
  proceso text,
  tipo_costo text not null check (tipo_costo in ('MANO_OBRA','INSUMO','MAQUINARIA','SERVICIO','INDIRECTO','LOGISTICO','PACKING','EXPORTACION')),
  documento_origen_tipo text,
  documento_origen_codigo text,
  cantidad numeric(20,6) not null default 1 check (cantidad >= 0),
  unidad_medida text,
  costo_unitario numeric(20,6) not null default 0 check (costo_unitario >= 0),
  costo_total numeric(20,6) generated always as (round(cantidad * costo_unitario, 6)) stored,
  moneda text not null default 'PEN' check (moneda in ('PEN','USD','EUR')),
  tipo_cambio numeric(18,6) not null default 1 check (tipo_cambio > 0),
  costo_total_pen numeric(20,6) generated always as (round(cantidad * costo_unitario * tipo_cambio, 6)) stored,
  estado text not null default 'REGISTRADO' check (estado in ('REGISTRADO','CONTABILIZADO','ANULADO')),
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  unique (empresa_id, numero)
);

-- ---------------------------------------------------------------------------
-- Ventas y exportaciones.
-- ---------------------------------------------------------------------------

create table if not exists public."ERP_CLIENTES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  codigo text not null,
  tipo_documento text,
  numero_documento text,
  razon_social text not null,
  nombre_comercial text,
  pais text,
  direccion text,
  contacto text,
  email text,
  telefono text,
  moneda_preferida text not null default 'USD' check (moneda_preferida in ('PEN','USD','EUR')),
  dias_credito integer not null default 0 check (dias_credito >= 0),
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO','BLOQUEADO','INACTIVO')),
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  unique (empresa_id, codigo),
  unique (empresa_id, tipo_documento, numero_documento)
);

create table if not exists public."ERP_PEDIDOS_VENTA_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  numero text not null,
  cliente_codigo text not null,
  fecha_emision date not null default current_date,
  fecha_entrega date,
  moneda text not null default 'USD' check (moneda in ('PEN','USD','EUR')),
  tipo_cambio numeric(18,6) not null default 1 check (tipo_cambio > 0),
  incoterm text,
  destino text,
  subtotal numeric(20,6) not null default 0,
  descuento numeric(20,6) not null default 0,
  impuesto numeric(20,6) not null default 0,
  total numeric(20,6) not null default 0,
  estado text not null default 'BORRADOR' check (estado in ('BORRADOR','CONFIRMADO','EN_PREPARACION','DESPACHADO','FACTURADO','CERRADO','ANULADO')),
  observacion text,
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_pv_cliente_fk foreign key (empresa_id, cliente_codigo)
    references public."ERP_CLIENTES_APPGT"(empresa_id, codigo),
  unique (empresa_id, numero)
);

create table if not exists public."ERP_PEDIDOS_VENTA_DETALLE_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  pedido_numero text not null,
  linea integer not null check (linea > 0),
  articulo_codigo text not null,
  descripcion text,
  lote text,
  variedad text,
  cantidad numeric(20,6) not null check (cantidad > 0),
  unidad_medida text not null,
  precio_unitario numeric(20,6) not null check (precio_unitario >= 0),
  descuento_porcentaje numeric(9,6) not null default 0 check (descuento_porcentaje between 0 and 100),
  impuesto_porcentaje numeric(9,6) not null default 0 check (impuesto_porcentaje between 0 and 100),
  subtotal numeric(20,6) generated always as (round(cantidad * precio_unitario * (1 - descuento_porcentaje / 100), 6)) stored,
  impuesto numeric(20,6) generated always as (round(cantidad * precio_unitario * (1 - descuento_porcentaje / 100) * impuesto_porcentaje / 100, 6)) stored,
  total numeric(20,6) generated always as (round(cantidad * precio_unitario * (1 - descuento_porcentaje / 100) * (1 + impuesto_porcentaje / 100), 6)) stored,
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_pvd_pedido_fk foreign key (empresa_id, pedido_numero)
    references public."ERP_PEDIDOS_VENTA_APPGT"(empresa_id, numero) on delete cascade,
  constraint erp_pvd_articulo_fk foreign key (empresa_id, articulo_codigo)
    references public."ERP_ARTICULOS_APPGT"(empresa_id, codigo),
  unique (empresa_id, pedido_numero, linea)
);

create table if not exists public."ERP_EXPORTACIONES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  numero text not null,
  pedido_numero text,
  cliente_codigo text not null,
  campana text,
  booking text,
  contenedor text,
  naviera text,
  incoterm text,
  pais_destino text not null,
  puerto_origen text,
  puerto_destino text,
  etd date,
  eta date,
  producto text,
  variedad text,
  cantidad_cajas numeric(20,4) not null default 0 check (cantidad_cajas >= 0),
  peso_neto numeric(20,6) not null default 0 check (peso_neto >= 0),
  peso_bruto numeric(20,6) not null default 0 check (peso_bruto >= 0),
  certificado_fitosanitario text,
  dua text,
  estado_documentario text not null default 'PENDIENTE' check (estado_documentario in ('PENDIENTE','EN_TRAMITE','COMPLETO','OBSERVADO')),
  estado text not null default 'PLANIFICADA' check (estado in ('PLANIFICADA','RESERVADA','EMBARCADA','EN_TRANSITO','ARRIBADA','CERRADA','ANULADA')),
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_exp_pedido_fk foreign key (empresa_id, pedido_numero)
    references public."ERP_PEDIDOS_VENTA_APPGT"(empresa_id, numero),
  constraint erp_exp_cliente_fk foreign key (empresa_id, cliente_codigo)
    references public."ERP_CLIENTES_APPGT"(empresa_id, codigo),
  check (eta is null or etd is null or eta >= etd),
  unique (empresa_id, numero)
);

-- ---------------------------------------------------------------------------
-- Contabilidad y finanzas.
-- ---------------------------------------------------------------------------

create table if not exists public."ERP_PERIODOS_CONTABLES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  codigo text not null,
  ejercicio integer not null check (ejercicio between 2000 and 2200),
  mes integer not null check (mes between 1 and 13),
  fecha_inicio date not null,
  fecha_fin date not null,
  estado text not null default 'ABIERTO' check (estado in ('ABIERTO','CERRADO','BLOQUEADO')),
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  check (fecha_fin >= fecha_inicio),
  unique (empresa_id, codigo),
  unique (empresa_id, ejercicio, mes)
);

create table if not exists public."ERP_CUENTAS_CONTABLES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  codigo text not null,
  nombre text not null,
  tipo text not null check (tipo in ('ACTIVO','PASIVO','PATRIMONIO','INGRESO','GASTO','ORDEN')),
  naturaleza text not null check (naturaleza in ('DEUDORA','ACREEDORA')),
  cuenta_padre_codigo text,
  nivel integer not null default 1 check (nivel between 1 and 12),
  acepta_movimiento boolean not null default true,
  requiere_centro_costo boolean not null default false,
  requiere_tercero boolean not null default false,
  moneda text check (moneda is null or moneda in ('PEN','USD','EUR')),
  estado text not null default 'ACTIVO' check (estado in ('ACTIVO','INACTIVO')),
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_cuenta_padre_fk foreign key (empresa_id, cuenta_padre_codigo)
    references public."ERP_CUENTAS_CONTABLES_APPGT"(empresa_id, codigo),
  unique (empresa_id, codigo)
);

create table if not exists public."ERP_ASIENTOS_CONTABLES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  numero text not null,
  fecha date not null default current_date,
  periodo_codigo text not null,
  libro text not null,
  tipo_asiento text not null default 'DIARIO',
  glosa text not null,
  documento_origen_tipo text,
  documento_origen_codigo text,
  moneda text not null default 'PEN' check (moneda in ('PEN','USD','EUR')),
  tipo_cambio numeric(18,6) not null default 1 check (tipo_cambio > 0),
  total_debe numeric(20,6) not null default 0,
  total_haber numeric(20,6) not null default 0,
  estado text not null default 'BORRADOR' check (estado in ('BORRADOR','POSTEADO','ANULADO')),
  posteado_por uuid references auth.users(id),
  posteado_at timestamptz,
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_asiento_periodo_fk foreign key (empresa_id, periodo_codigo)
    references public."ERP_PERIODOS_CONTABLES_APPGT"(empresa_id, codigo),
  check (total_debe >= 0 and total_haber >= 0),
  unique (empresa_id, numero)
);

create table if not exists public."ERP_ASIENTOS_DETALLE_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  asiento_numero text not null,
  linea integer not null check (linea > 0),
  cuenta_codigo text not null,
  centro_costo text,
  lote text,
  tercero_codigo text,
  documento_referencia text,
  glosa text,
  debe numeric(20,6) not null default 0 check (debe >= 0),
  haber numeric(20,6) not null default 0 check (haber >= 0),
  moneda text not null default 'PEN' check (moneda in ('PEN','USD','EUR')),
  tipo_cambio numeric(18,6) not null default 1 check (tipo_cambio > 0),
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_asiento_detalle_fk foreign key (empresa_id, asiento_numero)
    references public."ERP_ASIENTOS_CONTABLES_APPGT"(empresa_id, numero) on delete cascade,
  constraint erp_asiento_cuenta_fk foreign key (empresa_id, cuenta_codigo)
    references public."ERP_CUENTAS_CONTABLES_APPGT"(empresa_id, codigo),
  constraint erp_asiento_linea_ck check ((debe > 0 and haber = 0) or (haber > 0 and debe = 0)),
  unique (empresa_id, asiento_numero, linea)
);

create table if not exists public."ERP_TESORERIA_MOVIMIENTOS_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  numero text not null,
  fecha date not null default current_date,
  tipo text not null check (tipo in ('INGRESO','EGRESO','TRANSFERENCIA')),
  cuenta_financiera text not null,
  beneficiario text,
  documento_referencia text,
  concepto text not null,
  moneda text not null default 'PEN' check (moneda in ('PEN','USD','EUR')),
  importe numeric(20,6) not null check (importe > 0),
  tipo_cambio numeric(18,6) not null default 1 check (tipo_cambio > 0),
  importe_pen numeric(20,6) generated always as (round(importe * tipo_cambio, 6)) stored,
  asiento_numero text,
  estado text not null default 'REGISTRADO' check (estado in ('REGISTRADO','CONCILIADO','CONTABILIZADO','ANULADO')),
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_tes_asiento_fk foreign key (empresa_id, asiento_numero)
    references public."ERP_ASIENTOS_CONTABLES_APPGT"(empresa_id, numero),
  unique (empresa_id, numero)
);

-- ---------------------------------------------------------------------------
-- Integridad transaccional y auditoria.
-- ---------------------------------------------------------------------------

create or replace function public.appgt_erp_touch_row()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  new.updated_at := clock_timestamp();
  new.updated_by := auth.uid();
  new.version := coalesce(old.version, 0) + 1;
  return new;
end
$$;

create or replace function public.appgt_erp_preparar_movimiento_stock()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'UPDATE' and old.estado = 'CONFIRMADO' then
    if new.estado not in ('CONFIRMADO','ANULADO') then
      raise exception 'Un movimiento confirmado solo puede anularse.';
    end if;
    if new.almacen_codigo is distinct from old.almacen_codigo
       or new.articulo_codigo is distinct from old.articulo_codigo
       or new.lote is distinct from old.lote
       or new.cantidad is distinct from old.cantidad
       or new.direccion is distinct from old.direccion
       or new.costo_unitario is distinct from old.costo_unitario then
      raise exception 'No se puede modificar el contenido de un movimiento confirmado.';
    end if;
  end if;
  new.costo_total := round(new.cantidad * new.costo_unitario, 6);
  return new;
end
$$;

create or replace function public.appgt_erp_aplicar_stock()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_factor integer := 0;
  v_delta numeric(20,6);
  v_permite_negativo boolean;
  v_actual numeric(20,6);
begin
  if tg_op = 'INSERT' and new.estado = 'CONFIRMADO' then
    v_factor := 1;
  elsif tg_op = 'UPDATE' and old.estado <> 'CONFIRMADO' and new.estado = 'CONFIRMADO' then
    v_factor := 1;
  elsif tg_op = 'UPDATE' and old.estado = 'CONFIRMADO' and new.estado = 'ANULADO' then
    v_factor := -1;
  end if;
  if v_factor = 0 then return new; end if;

  v_delta := new.direccion * new.cantidad * v_factor;
  select permite_stock_negativo into v_permite_negativo
  from public."ERP_ALMACENES_APPGT"
  where empresa_id = new.empresa_id and codigo = new.almacen_codigo;

  insert into public."ERP_STOCK_APPGT" (
    empresa_id, almacen_codigo, articulo_codigo, lote, fecha_vencimiento,
    cantidad, costo_promedio
  ) values (
    new.empresa_id, new.almacen_codigo, new.articulo_codigo, new.lote,
    new.fecha_vencimiento, v_delta,
    case when new.direccion = 1 then new.costo_unitario else 0 end
  )
  on conflict (empresa_id, almacen_codigo, articulo_codigo, lote)
  do update set
    cantidad = public."ERP_STOCK_APPGT".cantidad + excluded.cantidad,
    fecha_vencimiento = coalesce(excluded.fecha_vencimiento, public."ERP_STOCK_APPGT".fecha_vencimiento),
    costo_promedio = case
      when excluded.cantidad > 0 and public."ERP_STOCK_APPGT".cantidad + excluded.cantidad > 0
      then round((public."ERP_STOCK_APPGT".cantidad * public."ERP_STOCK_APPGT".costo_promedio
        + excluded.cantidad * excluded.costo_promedio)
        / (public."ERP_STOCK_APPGT".cantidad + excluded.cantidad), 6)
      else public."ERP_STOCK_APPGT".costo_promedio
    end,
    updated_at = clock_timestamp()
  returning cantidad into v_actual;

  if not coalesce(v_permite_negativo, false) and v_actual < 0 then
    raise exception 'Stock insuficiente para % en el almacen %.',
      new.articulo_codigo, new.almacen_codigo;
  end if;
  return new;
end
$$;

create or replace function public.appgt_erp_recalcular_total_documento()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa uuid := coalesce(new.empresa_id, old.empresa_id);
  v_numero text;
begin
  if tg_table_name = 'ERP_ORDENES_COMPRA_DETALLE_APPGT' then
    v_numero := coalesce(new.orden_numero, old.orden_numero);
    update public."ERP_ORDENES_COMPRA_APPGT" h set
      subtotal = coalesce(x.subtotal, 0),
      descuento = coalesce(x.descuento, 0),
      impuesto = coalesce(x.impuesto, 0),
      total = coalesce(x.total, 0)
    from (
      select sum(d.cantidad * d.precio_unitario) - sum(d.subtotal) descuento,
        sum(d.subtotal) subtotal, sum(d.impuesto) impuesto, sum(d.total) total
      from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d
      where d.empresa_id = v_empresa and d.orden_numero = v_numero
        and not d.eliminado and d.deleted_at is null
    ) x
    where h.empresa_id = v_empresa and h.numero = v_numero;
  else
    v_numero := coalesce(new.pedido_numero, old.pedido_numero);
    update public."ERP_PEDIDOS_VENTA_APPGT" h set
      subtotal = coalesce(x.subtotal, 0),
      descuento = coalesce(x.descuento, 0),
      impuesto = coalesce(x.impuesto, 0),
      total = coalesce(x.total, 0)
    from (
      select sum(d.cantidad * d.precio_unitario) - sum(d.subtotal) descuento,
        sum(d.subtotal) subtotal, sum(d.impuesto) impuesto, sum(d.total) total
      from public."ERP_PEDIDOS_VENTA_DETALLE_APPGT" d
      where d.empresa_id = v_empresa and d.pedido_numero = v_numero
        and not d.eliminado and d.deleted_at is null
    ) x
    where h.empresa_id = v_empresa and h.numero = v_numero;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;

create or replace function public.appgt_erp_validar_asiento()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_debe numeric(20,6);
  v_haber numeric(20,6);
  v_periodo_estado text;
begin
  if new.estado = 'POSTEADO'
     and (tg_op = 'INSERT' or old.estado is distinct from 'POSTEADO') then
    select coalesce(sum(debe),0), coalesce(sum(haber),0)
      into v_debe, v_haber
    from public."ERP_ASIENTOS_DETALLE_APPGT"
    where empresa_id = new.empresa_id and asiento_numero = new.numero
      and not eliminado and deleted_at is null;
    select estado into v_periodo_estado
    from public."ERP_PERIODOS_CONTABLES_APPGT"
    where empresa_id = new.empresa_id and codigo = new.periodo_codigo;
    if v_periodo_estado <> 'ABIERTO' then
      raise exception 'El periodo contable no esta abierto.';
    end if;
    if v_debe <= 0 or abs(v_debe - v_haber) > 0.000001 then
      raise exception 'El asiento no esta balanceado. Debe %, Haber %.', v_debe, v_haber;
    end if;
    new.total_debe := v_debe;
    new.total_haber := v_haber;
    new.posteado_por := auth.uid();
    new.posteado_at := clock_timestamp();
  elsif tg_op = 'UPDATE' and old.estado = 'POSTEADO'
        and new.estado <> 'ANULADO' then
    raise exception 'Un asiento posteado solo puede anularse.';
  end if;
  return new;
end
$$;

create or replace function public.appgt_erp_controlar_linea_asiento()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa uuid := coalesce(new.empresa_id, old.empresa_id);
  v_numero text := coalesce(new.asiento_numero, old.asiento_numero);
  v_estado text;
begin
  select estado into v_estado from public."ERP_ASIENTOS_CONTABLES_APPGT"
  where empresa_id = v_empresa and numero = v_numero;
  if v_estado in ('POSTEADO','ANULADO') then
    raise exception 'No se pueden cambiar lineas de un asiento %.', lower(v_estado);
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;

create or replace function public.appgt_erp_totalizar_asiento()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa uuid := coalesce(new.empresa_id, old.empresa_id);
  v_numero text := coalesce(new.asiento_numero, old.asiento_numero);
begin
  update public."ERP_ASIENTOS_CONTABLES_APPGT" h set
    total_debe = coalesce(x.debe, 0), total_haber = coalesce(x.haber, 0)
  from (
    select sum(debe) debe, sum(haber) haber
    from public."ERP_ASIENTOS_DETALLE_APPGT"
    where empresa_id = v_empresa and asiento_numero = v_numero
      and not eliminado and deleted_at is null
  ) x
  where h.empresa_id = v_empresa and h.numero = v_numero;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;

drop trigger if exists erp_preparar_movimiento_stock on public."ERP_MOVIMIENTOS_INVENTARIO_APPGT";
create trigger erp_preparar_movimiento_stock before insert or update
on public."ERP_MOVIMIENTOS_INVENTARIO_APPGT" for each row
execute function public.appgt_erp_preparar_movimiento_stock();
drop trigger if exists erp_aplicar_stock on public."ERP_MOVIMIENTOS_INVENTARIO_APPGT";
create trigger erp_aplicar_stock after insert or update
on public."ERP_MOVIMIENTOS_INVENTARIO_APPGT" for each row
execute function public.appgt_erp_aplicar_stock();

drop trigger if exists erp_total_oc on public."ERP_ORDENES_COMPRA_DETALLE_APPGT";
create trigger erp_total_oc after insert or update or delete
on public."ERP_ORDENES_COMPRA_DETALLE_APPGT" for each row
execute function public.appgt_erp_recalcular_total_documento();
drop trigger if exists erp_total_pv on public."ERP_PEDIDOS_VENTA_DETALLE_APPGT";
create trigger erp_total_pv after insert or update or delete
on public."ERP_PEDIDOS_VENTA_DETALLE_APPGT" for each row
execute function public.appgt_erp_recalcular_total_documento();

drop trigger if exists erp_validar_asiento on public."ERP_ASIENTOS_CONTABLES_APPGT";
create trigger erp_validar_asiento before insert or update
on public."ERP_ASIENTOS_CONTABLES_APPGT" for each row
execute function public.appgt_erp_validar_asiento();
drop trigger if exists erp_controlar_linea_asiento on public."ERP_ASIENTOS_DETALLE_APPGT";
create trigger erp_controlar_linea_asiento before insert or update or delete
on public."ERP_ASIENTOS_DETALLE_APPGT" for each row
execute function public.appgt_erp_controlar_linea_asiento();
drop trigger if exists erp_totalizar_asiento on public."ERP_ASIENTOS_DETALLE_APPGT";
create trigger erp_totalizar_asiento after insert or update or delete
on public."ERP_ASIENTOS_DETALLE_APPGT" for each row
execute function public.appgt_erp_totalizar_asiento();

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'ERP_PROVEEDORES_APPGT','ERP_ALMACENES_APPGT','ERP_ARTICULOS_APPGT',
    'ERP_MOVIMIENTOS_INVENTARIO_APPGT','ERP_SOLICITUDES_COMPRA_APPGT',
    'ERP_ORDENES_COMPRA_APPGT','ERP_ORDENES_COMPRA_DETALLE_APPGT',
    'ERP_PLANES_PRODUCCION_APPGT','ERP_ORDENES_PRODUCCION_APPGT',
    'ERP_PARTES_PRODUCCION_APPGT','ERP_COSTOS_AGROEXPORTADORES_APPGT',
    'ERP_CLIENTES_APPGT','ERP_PEDIDOS_VENTA_APPGT',
    'ERP_PEDIDOS_VENTA_DETALLE_APPGT','ERP_EXPORTACIONES_APPGT',
    'ERP_PERIODOS_CONTABLES_APPGT','ERP_CUENTAS_CONTABLES_APPGT',
    'ERP_ASIENTOS_CONTABLES_APPGT','ERP_ASIENTOS_DETALLE_APPGT',
    'ERP_TESORERIA_MOVIMIENTOS_APPGT'
  ] loop
    execute format('drop trigger if exists erp_touch_row on public.%I', v_table);
    execute format('create trigger erp_touch_row before update on public.%I for each row execute function public.appgt_erp_touch_row()', v_table);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- Indices, permisos SQL y RLS por empresa + permiso efectivo del formato.
-- ---------------------------------------------------------------------------

create index if not exists erp_proveedores_nombre_idx on public."ERP_PROVEEDORES_APPGT" (empresa_id, razon_social) where deleted_at is null;
create index if not exists erp_articulos_nombre_idx on public."ERP_ARTICULOS_APPGT" (empresa_id, nombre) where deleted_at is null;
create unique index if not exists erp_articulos_legacy_uq
  on public."ERP_ARTICULOS_APPGT" (empresa_id, tabla_legacy, referencia_legacy)
  where tabla_legacy is not null and referencia_legacy is not null;
create index if not exists erp_stock_consulta_idx on public."ERP_STOCK_APPGT" (empresa_id, almacen_codigo, articulo_codigo);
create index if not exists erp_movimientos_fecha_idx on public."ERP_MOVIMIENTOS_INVENTARIO_APPGT" (empresa_id, fecha desc, articulo_codigo);
create index if not exists erp_oc_fecha_idx on public."ERP_ORDENES_COMPRA_APPGT" (empresa_id, fecha_emision desc, proveedor_codigo);
create index if not exists erp_ocd_articulo_idx on public."ERP_ORDENES_COMPRA_DETALLE_APPGT" (empresa_id, articulo_codigo);
create index if not exists erp_op_fecha_idx on public."ERP_ORDENES_PRODUCCION_APPGT" (empresa_id, fecha_inicio desc, lote);
create index if not exists erp_partes_fecha_idx on public."ERP_PARTES_PRODUCCION_APPGT" (empresa_id, fecha desc, orden_codigo);
create index if not exists erp_costos_analitica_idx on public."ERP_COSTOS_AGROEXPORTADORES_APPGT" (empresa_id, periodo, centro_costo, lote, labor);
create index if not exists erp_pv_fecha_idx on public."ERP_PEDIDOS_VENTA_APPGT" (empresa_id, fecha_emision desc, cliente_codigo);
create index if not exists erp_exportaciones_etd_idx on public."ERP_EXPORTACIONES_APPGT" (empresa_id, etd desc, estado);
create index if not exists erp_asientos_fecha_idx on public."ERP_ASIENTOS_CONTABLES_APPGT" (empresa_id, fecha desc, libro);
create index if not exists erp_asientos_detalle_cuenta_idx on public."ERP_ASIENTOS_DETALLE_APPGT" (empresa_id, cuenta_codigo, asiento_numero);
create index if not exists erp_tesoreria_fecha_idx on public."ERP_TESORERIA_MOVIMIENTOS_APPGT" (empresa_id, fecha desc, cuenta_financiera);

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'ERP_PROVEEDORES_APPGT','ERP_ALMACENES_APPGT','ERP_ARTICULOS_APPGT',
    'ERP_STOCK_APPGT','ERP_MOVIMIENTOS_INVENTARIO_APPGT',
    'ERP_SOLICITUDES_COMPRA_APPGT','ERP_ORDENES_COMPRA_APPGT',
    'ERP_ORDENES_COMPRA_DETALLE_APPGT','ERP_PLANES_PRODUCCION_APPGT',
    'ERP_ORDENES_PRODUCCION_APPGT','ERP_PARTES_PRODUCCION_APPGT',
    'ERP_COSTOS_AGROEXPORTADORES_APPGT','ERP_CLIENTES_APPGT',
    'ERP_PEDIDOS_VENTA_APPGT','ERP_PEDIDOS_VENTA_DETALLE_APPGT',
    'ERP_EXPORTACIONES_APPGT','ERP_PERIODOS_CONTABLES_APPGT',
    'ERP_CUENTAS_CONTABLES_APPGT','ERP_ASIENTOS_CONTABLES_APPGT',
    'ERP_ASIENTOS_DETALLE_APPGT','ERP_TESORERIA_MOVIMIENTOS_APPGT'
  ] loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format('drop policy if exists erp_select on public.%I', v_table);
    execute format('drop policy if exists erp_insert on public.%I', v_table);
    execute format('drop policy if exists erp_update on public.%I', v_table);
    execute format('drop policy if exists erp_delete on public.%I', v_table);
    execute format('create policy erp_select on public.%I for select to authenticated using (empresa_id = public.appgt_empresa_actual_id() and public.appgt_can_view_table(%L))', v_table, v_table);
    execute format('create policy erp_insert on public.%I for insert to authenticated with check (empresa_id = public.appgt_empresa_actual_id() and public.appgt_can_insert_table(%L))', v_table, v_table);
    execute format('create policy erp_update on public.%I for update to authenticated using (empresa_id = public.appgt_empresa_actual_id() and public.appgt_can_update_table(%L)) with check (empresa_id = public.appgt_empresa_actual_id() and public.appgt_can_update_table(%L))', v_table, v_table, v_table);
    execute format('create policy erp_delete on public.%I for delete to authenticated using (empresa_id = public.appgt_empresa_actual_id() and public.appgt_can_delete_table(%L))', v_table, v_table);
    execute format('grant select, insert, update, delete on public.%I to authenticated', v_table);
    execute format('grant all on public.%I to service_role', v_table);
  end loop;
end
$$;

commit;
