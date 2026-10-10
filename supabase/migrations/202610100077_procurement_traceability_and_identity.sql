begin;

-- ============================================================================
-- Compras y almacenes: RUC canónico, correlativos legibles, identidad del
-- usuario autenticado y trazabilidad por línea SP -> OC -> ingreso -> despacho.
-- ============================================================================

-- La base productiva puede haber renombrado numero_documento manualmente. La
-- migración funciona tanto en ese escenario como al reconstruir desde cero.
alter table public."ERP_PROVEEDORES_APPGT"
  add column if not exists ruc text;

-- El campo fue creado manualmente como numérico en algunas empresas. RUC es
-- un identificador, no una cantidad, por lo que se normaliza a texto.
alter table public."ERP_PROVEEDORES_APPGT"
  alter column ruc type text using ruc::text;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='ERP_PROVEEDORES_APPGT'
      and column_name='numero_documento'
  ) then
    update public."ERP_PROVEEDORES_APPGT"
    set ruc=coalesce(nullif(btrim(ruc),''),nullif(btrim(numero_documento),''));
  end if;
end
$$;

alter table public."ERP_PROVEEDORES_APPGT"
  drop constraint if exists erp_proveedor_ruc_no_vacio_ck;
alter table public."ERP_PROVEEDORES_APPGT"
  add constraint erp_proveedor_ruc_no_vacio_ck
  check (ruc is null or btrim(ruc)<>'');
create unique index if not exists erp_proveedor_ruc_unico_idx
  on public."ERP_PROVEEDORES_APPGT"(empresa_id,ruc)
  where ruc is not null and btrim(ruc)<>'' and not eliminado and deleted_at is null;

alter table public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"
  add column if not exists cantidad_recibida numeric(20,6) not null default 0,
  add column if not exists fecha_oc_aprobada date,
  add column if not exists fecha_recibida date;

alter table public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"
  drop constraint if exists erp_scd_cantidad_recibida_ck;
alter table public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"
  add constraint erp_scd_cantidad_recibida_ck
  check (cantidad_recibida>=0 and cantidad_recibida<=cantidad_solicitada);

alter table public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  add column if not exists almacen_destino_codigo text,
  add column if not exists fecha_solicitada date,
  add column if not exists fecha_oc_aprobada date,
  add column if not exists fecha_recibida date;

select set_config('appgt.erp_receipt_context','1',true);

update public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d
set almacen_destino_codigo=coalesce(d.almacen_destino_codigo,(
      select sd.almacen_destino_codigo
      from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" sd
      where sd.empresa_id=d.empresa_id and sd.solicitud_numero=d.solicitud_numero
        and sd.linea=d.solicitud_linea
    ),(
      select o.almacen_codigo from public."ERP_ORDENES_COMPRA_APPGT" o
      where o.empresa_id=d.empresa_id and o.numero=d.orden_numero
    )),
    fecha_solicitada=coalesce(d.fecha_solicitada,(
      select s.fecha from public."ERP_SOLICITUDES_COMPRA_APPGT" s
      where s.empresa_id=d.empresa_id and s.numero=d.solicitud_numero
    )),
    fecha_oc_aprobada=coalesce(d.fecha_oc_aprobada,(
      select o.aprobado_at::date from public."ERP_ORDENES_COMPRA_APPGT" o
      where o.empresa_id=d.empresa_id and o.numero=d.orden_numero
    )),
    fecha_recibida=coalesce(d.fecha_recibida,(
      select o.fecha_despachada from public."ERP_ORDENES_COMPRA_APPGT" o
      where o.empresa_id=d.empresa_id and o.numero=d.orden_numero
    ));

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname='erp_ocd_almacen_destino_fk'
      and conrelid='public."ERP_ORDENES_COMPRA_DETALLE_APPGT"'::regclass
  ) then
    alter table public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
      add constraint erp_ocd_almacen_destino_fk
      foreign key (empresa_id,almacen_destino_codigo)
      references public."ERP_ALMACENES_APPGT"(empresa_id,codigo);
  end if;
end $$;

alter table public."ERP_VALES_DESPACHO_DETALLE_APPGT"
  add column if not exists centro_costo text;
update public."ERP_VALES_DESPACHO_DETALLE_APPGT" d
set centro_costo=v.centro_costo
from public."ERP_VALES_DESPACHO_APPGT" v
where v.empresa_id=d.empresa_id and v.numero=d.vale_numero
  and nullif(btrim(coalesce(d.centro_costo,'')),'') is null;

-- --------------------------------------------------------------------------
-- Correlativos automáticos por empresa. El bloqueo transaccional evita que
-- dos usuarios reciban el mismo número.
-- --------------------------------------------------------------------------

create or replace function public.appgt_erp_codigo_automatico_v1()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_next bigint;
begin
  perform pg_advisory_xact_lock(hashtext(tg_table_name),hashtext(new.empresa_id::text));
  if tg_table_name='ERP_PROVEEDORES_APPGT' then
    if btrim(coalesce(new.ruc,''))='' then
      raise exception 'El RUC del proveedor es obligatorio.';
    end if;
    select greatest(10001,coalesce(max(
      case when codigo~'^[0-9]+-' then (regexp_match(codigo,'^([0-9]+)-'))[1]::bigint end
    ),10000)+1)
    into v_next from public."ERP_PROVEEDORES_APPGT"
    where empresa_id=new.empresa_id;
    new.codigo:=v_next::text||'-'||btrim(new.ruc);
  elsif tg_table_name='ERP_SOLICITUDES_COMPRA_APPGT' then
    if tg_op='INSERT' then
      select greatest(10001,coalesce(max(
        case when numero~'^SP-[0-9]+$' then substring(numero from 4)::bigint end
      ),10000)+1)
      into v_next from public."ERP_SOLICITUDES_COMPRA_APPGT"
      where empresa_id=new.empresa_id;
      new.numero:='SP-'||v_next::text;
    end if;
  elsif tg_table_name='ERP_ORDENES_COMPRA_APPGT' then
    if tg_op='INSERT' then
      select greatest(10001,coalesce(max(
        case when numero~'^OC-[0-9]+$' then substring(numero from 4)::bigint end
      ),10000)+1)
      into v_next from public."ERP_ORDENES_COMPRA_APPGT"
      where empresa_id=new.empresa_id;
      new.numero:='OC-'||v_next::text;
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists erp_codigo_proveedor_automatico on public."ERP_PROVEEDORES_APPGT";
create trigger erp_codigo_proveedor_automatico
before insert on public."ERP_PROVEEDORES_APPGT"
for each row execute function public.appgt_erp_codigo_automatico_v1();

drop trigger if exists erp_codigo_solicitud_automatico on public."ERP_SOLICITUDES_COMPRA_APPGT";
create trigger erp_codigo_solicitud_automatico
before insert on public."ERP_SOLICITUDES_COMPRA_APPGT"
for each row execute function public.appgt_erp_codigo_automatico_v1();

drop trigger if exists erp_codigo_oc_automatico on public."ERP_ORDENES_COMPRA_APPGT";
create trigger erp_codigo_oc_automatico
before insert on public."ERP_ORDENES_COMPRA_APPGT"
for each row execute function public.appgt_erp_codigo_automatico_v1();

-- --------------------------------------------------------------------------
-- Identidad obligatoria obtenida de PERFILES_DE_USUARIOS_APPGT.
-- --------------------------------------------------------------------------

create or replace function public.erp_identidad_usuario_actual_v1()
returns jsonb
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select coalesce((
    select jsonb_build_object(
      'dni',btrim(coalesce(p."DNI",'')),
      'first_nombres',btrim(coalesce(nullif(p.first_nombres,''),p.nombres,'')),
      'apellido_paterno',btrim(coalesce(p.apellido_paterno,'')),
      'usuario_nombre',concat_ws('-',
        nullif(btrim(coalesce(nullif(p.first_nombres,''),p.nombres,'')),''),
        nullif(btrim(coalesce(p.apellido_paterno,'')),'')
      ),
      'solicitante',concat_ws('-',
        nullif(btrim(coalesce(p."DNI",'')),''),
        nullif(btrim(coalesce(nullif(p.first_nombres,''),p.nombres,'')),''),
        nullif(btrim(coalesce(p.apellido_paterno,'')),'')
      ),
      'area',nullif(btrim(coalesce(p.area,'')),'')
    )
    from public."PERFILES_DE_USUARIOS_APPGT" p
    where p.id=auth.uid() and p.empresa_id=public.appgt_empresa_actual_id()
      and coalesce(p.activo,true) and not coalesce(p.eliminado,false)
      and p.deleted_at is null
    limit 1
  ),'{}'::jsonb)
$$;

create or replace function public.appgt_erp_identidad_documento_v1()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_identidad jsonb;
begin
  if tg_op='UPDATE' then
    if tg_table_name='ERP_SOLICITUDES_COMPRA_APPGT' then
      new.solicitante:=old.solicitante;
    elsif tg_table_name='ERP_VALES_DESPACHO_APPGT' then
      new.usuario_dni:=old.usuario_dni;
      new.usuario_nombre:=old.usuario_nombre;
    end if;
    return new;
  end if;
  if auth.uid() is null then return new; end if;
  v_identidad:=public.erp_identidad_usuario_actual_v1();
  if v_identidad='{}'::jsonb then
    raise exception 'El usuario activo no tiene un perfil válido en la empresa.' using errcode='42501';
  end if;
  if tg_table_name='ERP_SOLICITUDES_COMPRA_APPGT' then
    new.solicitante:=v_identidad->>'solicitante';
    new.area:=coalesce(new.area,v_identidad->>'area');
  elsif tg_table_name='ERP_VALES_DESPACHO_APPGT' then
    new.usuario_dni:=v_identidad->>'dni';
    new.usuario_nombre:=v_identidad->>'usuario_nombre';
  end if;
  return new;
end
$$;

drop trigger if exists erp_identidad_solicitud on public."ERP_SOLICITUDES_COMPRA_APPGT";
create trigger erp_identidad_solicitud
before insert or update on public."ERP_SOLICITUDES_COMPRA_APPGT"
for each row execute function public.appgt_erp_identidad_documento_v1();

drop trigger if exists erp_identidad_vale on public."ERP_VALES_DESPACHO_APPGT";
create trigger erp_identidad_vale
before insert or update on public."ERP_VALES_DESPACHO_APPGT"
for each row execute function public.appgt_erp_identidad_documento_v1();

create or replace function public.appgt_erp_preparar_orden_compra_v2()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  select p.ruc into new.proveedor_ruc
  from public."ERP_PROVEEDORES_APPGT" p
  where p.empresa_id=new.empresa_id and p.codigo=new.proveedor_codigo;
  return new;
end
$$;

-- --------------------------------------------------------------------------
-- Solicitudes: código SP correlativo e identidad no editable.
-- --------------------------------------------------------------------------

create or replace function public.erp_guardar_solicitud_pedido_v1(
  p_numero text,p_fecha date,p_fecha_necesidad date,p_solicitante text,
  p_area text,p_centro_costo text,p_justificacion text,p_detalles jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa uuid:=public.appgt_empresa_actual_id();
  v_numero text:=nullif(btrim(coalesce(p_numero,'')),'');
  v_existing public."ERP_SOLICITUDES_COMPRA_APPGT"%rowtype;
  v_identidad jsonb:=public.erp_identidad_usuario_actual_v1();
  v_item jsonb;
  v_article public."ERP_ARTICULOS_APPGT"%rowtype;
  v_line integer:=0;
  v_qty numeric(20,6);
  v_need date:=coalesce(p_fecha_necesidad,current_date);
begin
  if v_empresa is null then raise exception 'No se pudo resolver la empresa activa' using errcode='42501'; end if;
  if v_identidad='{}'::jsonb then raise exception 'El usuario activo no tiene perfil válido.' using errcode='42501'; end if;
  if jsonb_typeof(p_detalles)<>'array' or jsonb_array_length(p_detalles)=0 then
    raise exception 'Agregue al menos un artículo o insumo.';
  end if;
  if v_numero is not null then
    select * into v_existing from public."ERP_SOLICITUDES_COMPRA_APPGT"
    where empresa_id=v_empresa and numero=v_numero for update;
  end if;
  if v_existing.id is null then
    insert into public."ERP_SOLICITUDES_COMPRA_APPGT"(
      empresa_id,numero,fecha,fecha_necesidad,solicitante,area,centro_costo,
      justificacion,monto_estimado,moneda,estado
    ) values (
      v_empresa,null,coalesce(p_fecha,current_date),v_need,v_identidad->>'solicitante',
      coalesce(nullif(btrim(coalesce(p_area,'')),''),v_identidad->>'area'),
      nullif(btrim(coalesce(p_centro_costo,'')),''),
      nullif(btrim(coalesce(p_justificacion,'')),''),0,'PEN','PENDIENTE'
    ) returning numero into v_numero;
  else
    if v_existing.estado not in ('PENDIENTE','REVISADO') then
      raise exception 'Una solicitud % no se puede editar.',v_existing.estado;
    end if;
    update public."ERP_SOLICITUDES_COMPRA_APPGT" set
      fecha=coalesce(p_fecha,current_date),fecha_necesidad=v_need,
      area=coalesce(nullif(btrim(coalesce(p_area,'')),''),area),
      centro_costo=nullif(btrim(coalesce(p_centro_costo,'')),''),
      justificacion=nullif(btrim(coalesce(p_justificacion,'')),''),updated_by=auth.uid()
    where id=v_existing.id;
    delete from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"
    where empresa_id=v_empresa and solicitud_numero=v_numero;
  end if;
  for v_item in select value from jsonb_array_elements(p_detalles) loop
    v_qty:=coalesce((v_item->>'cantidad_solicitada')::numeric,0);
    if v_qty<=0 then raise exception 'Todas las cantidades deben ser mayores que cero.'; end if;
    select * into v_article from public."ERP_ARTICULOS_APPGT"
    where empresa_id=v_empresa and codigo=v_item->>'articulo_codigo'
      and estado='ACTIVO' and not eliminado and deleted_at is null;
    if v_article.id is null then raise exception 'Artículo o insumo no encontrado: %',v_item->>'articulo_codigo'; end if;
    if btrim(coalesce(v_item->>'almacen_destino_codigo',''))='' then
      raise exception 'Indique el almacén de destino para %.',v_article.nombre;
    end if;
    v_line:=v_line+1;
    insert into public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"(
      empresa_id,solicitud_numero,linea,articulo_codigo,descripcion,
      cantidad_solicitada,unidad_medida,fecha_necesidad,
      proveedor_recomendado_codigo,almacen_destino_codigo,observacion
    ) values (
      v_empresa,v_numero,v_line,v_article.codigo,v_article.nombre,v_qty,
      v_article.unidad_medida,coalesce((v_item->>'fecha_necesidad')::date,v_need),
      nullif(btrim(coalesce(v_item->>'proveedor_recomendado_codigo','')),''),
      btrim(v_item->>'almacen_destino_codigo'),
      nullif(btrim(coalesce(v_item->>'observacion','')),'')
    );
  end loop;
  return jsonb_build_object('numero',v_numero,'codigo',v_numero,'estado','PENDIENTE','lineas',v_line);
end
$$;

-- --------------------------------------------------------------------------
-- Órdenes: varias solicitudes por OC, líneas editables y almacén por línea.
-- --------------------------------------------------------------------------

create or replace function public.erp_solicitudes_aprobadas_oc_v1()
returns jsonb
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object(
    'detalles',coalesce((select jsonb_agg(jsonb_build_object(
      'linea',d.linea,'articulo_codigo',d.articulo_codigo,
      'descripcion',coalesce(d.descripcion,a.nombre),
      'cantidad_solicitada',d.cantidad_solicitada,
      'cantidad_recibida',d.cantidad_recibida,
      'unidad_medida',d.unidad_medida,
      'proveedor_recomendado_codigo',d.proveedor_recomendado_codigo,
      'almacen_destino_codigo',d.almacen_destino_codigo,
      'fecha_solicitada',s.fecha,'fecha_oc_aprobada',d.fecha_oc_aprobada,
      'fecha_recibida',d.fecha_recibida,
      'precio_referencial',coalesce(a.costo_estandar,0),'observacion',d.observacion
    ) order by d.linea)
    from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" d
    join public."ERP_ARTICULOS_APPGT" a
      on a.empresa_id=d.empresa_id and a.codigo=d.articulo_codigo
    where d.empresa_id=s.empresa_id and d.solicitud_numero=s.numero
      and not d.eliminado and d.deleted_at is null),'[]'::jsonb)
  ) order by s.fecha,s.numero),'[]'::jsonb)
  from public."ERP_SOLICITUDES_COMPRA_APPGT" s
  where s.empresa_id=public.appgt_empresa_actual_id() and s.estado='APROBADO'
    and not s.eliminado and s.deleted_at is null
    and (auth.role()='service_role' or public.appgt_can_view_table('ERP_SOLICITUDES_COMPRA_APPGT'))
$$;

create or replace function public.erp_guardar_orden_compra_v1(
  p_codigo text,p_proveedor_codigo text,p_fecha_emision date,p_fecha_entrega date,
  p_moneda text,p_tipo_cambio numeric,p_condicion_pago text,p_almacen_codigo text,
  p_observacion text,p_con_igv boolean,p_descuento numeric,
  p_solicitudes jsonb,p_detalles jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa uuid:=public.appgt_empresa_actual_id();
  v_codigo text:=nullif(btrim(coalesce(p_codigo,'')),'');
  v_existing public."ERP_ORDENES_COMPRA_APPGT"%rowtype;
  v_item jsonb; v_article public."ERP_ARTICULOS_APPGT"%rowtype;
  v_line integer:=0; v_count integer:=0; v_qty numeric(20,6); v_price numeric(20,6);
  v_line_discount numeric(9,6); v_sum numeric(20,6):=0; v_gross numeric(20,6);
  v_discount numeric(20,6):=greatest(coalesce(p_descuento,0),0);
  v_subtotal numeric(20,6); v_tax numeric(20,6); v_total numeric(20,6);
  v_first_request text; v_request_line public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"%rowtype;
  v_request_date date; v_line_warehouse text;
begin
  if v_empresa is null then raise exception 'No se pudo resolver la empresa activa' using errcode='42501'; end if;
  if btrim(coalesce(p_proveedor_codigo,''))='' then raise exception 'Seleccione un proveedor.'; end if;
  if btrim(coalesce(p_almacen_codigo,''))='' then raise exception 'Seleccione un almacén.'; end if;
  if jsonb_typeof(p_solicitudes)<>'array' or jsonb_array_length(p_solicitudes)=0 then raise exception 'Agregue al menos una solicitud de pedido aprobada.'; end if;
  if jsonb_typeof(p_detalles)<>'array' or jsonb_array_length(p_detalles)=0 then raise exception 'La orden de compra debe tener al menos un ítem.'; end if;
  select nullif(btrim(coalesce(value->>'numero',value#>>'{}')),'') into v_first_request
  from jsonb_array_elements(p_solicitudes) limit 1;
  if v_codigo is not null then
    select * into v_existing from public."ERP_ORDENES_COMPRA_APPGT"
    where empresa_id=v_empresa and numero=v_codigo for update;
  end if;
  if v_existing.id is null then
    insert into public."ERP_ORDENES_COMPRA_APPGT"(
      empresa_id,numero,solicitud_numero,proveedor_codigo,fecha_emision,fecha_entrega,
      moneda,tipo_cambio,condicion_pago,almacen_codigo,con_igv,importe_bruto,
      subtotal,descuento,impuesto,total,estado,observacion
    ) values (
      v_empresa,null,v_first_request,btrim(p_proveedor_codigo),coalesce(p_fecha_emision,current_date),
      p_fecha_entrega,upper(coalesce(nullif(btrim(p_moneda),''),'PEN')),coalesce(p_tipo_cambio,1),
      nullif(btrim(coalesce(p_condicion_pago,'')),''),btrim(p_almacen_codigo),
      coalesce(p_con_igv,false),0,0,v_discount,0,0,'PENDIENTE',
      nullif(btrim(coalesce(p_observacion,'')),'')
    ) returning numero into v_codigo;
  else
    if v_existing.estado not in ('PENDIENTE','REVISADO') then raise exception 'La orden % no se puede editar en estado %.',v_codigo,v_existing.estado; end if;
    update public."ERP_ORDENES_COMPRA_APPGT" set
      solicitud_numero=v_first_request,proveedor_codigo=btrim(p_proveedor_codigo),
      fecha_emision=coalesce(p_fecha_emision,current_date),fecha_entrega=p_fecha_entrega,
      moneda=upper(coalesce(nullif(btrim(p_moneda),''),'PEN')),tipo_cambio=coalesce(p_tipo_cambio,1),
      condicion_pago=nullif(btrim(coalesce(p_condicion_pago,'')),''),almacen_codigo=btrim(p_almacen_codigo),
      con_igv=coalesce(p_con_igv,false),descuento=v_discount,
      observacion=nullif(btrim(coalesce(p_observacion,'')),''),updated_by=auth.uid()
    where id=v_existing.id;
    update public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
    set eliminado=true,deleted_at=clock_timestamp(),updated_by=auth.uid()
    where empresa_id=v_empresa and orden_numero=v_codigo and not eliminado and deleted_at is null;
    update public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT"
    set eliminado=true,deleted_at=clock_timestamp()
    where empresa_id=v_empresa and orden_numero=v_codigo and not eliminado and deleted_at is null;
  end if;
  select coalesce(max(linea),0) into v_line from public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  where empresa_id=v_empresa and orden_numero=v_codigo;
  for v_item in select value from jsonb_array_elements(p_solicitudes) loop
    if not exists (select 1 from public."ERP_SOLICITUDES_COMPRA_APPGT" s
      where s.empresa_id=v_empresa and s.numero=nullif(btrim(coalesce(v_item->>'numero',v_item#>>'{}')),'')
        and s.estado='APROBADO' and not s.eliminado and s.deleted_at is null) then
      raise exception 'La solicitud % no está aprobada o disponible.',coalesce(v_item->>'numero',v_item#>>'{}');
    end if;
    insert into public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT"(empresa_id,orden_numero,solicitud_numero)
    values (v_empresa,v_codigo,nullif(btrim(coalesce(v_item->>'numero',v_item#>>'{}')),''))
    on conflict (empresa_id,orden_numero,solicitud_numero) do update set
      eliminado=false,deleted_at=null,created_by=auth.uid();
  end loop;
  for v_item in select value from jsonb_array_elements(p_detalles) loop
    v_qty:=coalesce((v_item->>'cantidad')::numeric,0);
    v_price:=greatest(coalesce((v_item->>'precio_unitario')::numeric,0),0);
    v_line_discount:=least(greatest(coalesce((v_item->>'descuento_porcentaje')::numeric,0),0),100);
    if v_qty<=0 then raise exception 'Todas las cantidades deben ser mayores que cero.'; end if;
    if not exists (select 1 from public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT" os
      where os.empresa_id=v_empresa and os.orden_numero=v_codigo
        and os.solicitud_numero=nullif(btrim(coalesce(v_item->>'solicitud_numero','')),'')
        and not os.eliminado and os.deleted_at is null) then
      raise exception 'Cada ítem debe pertenecer a una solicitud agregada a la orden.';
    end if;
    select * into v_article from public."ERP_ARTICULOS_APPGT"
    where empresa_id=v_empresa and codigo=v_item->>'articulo_codigo' and not eliminado and deleted_at is null;
    if v_article.id is null then raise exception 'Artículo no encontrado: %',v_item->>'articulo_codigo'; end if;
    select d.* into v_request_line
    from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" d
    where d.empresa_id=v_empresa and d.solicitud_numero=v_item->>'solicitud_numero'
      and d.linea=nullif(v_item->>'solicitud_linea','')::integer;
    select s.fecha into v_request_date
    from public."ERP_SOLICITUDES_COMPRA_APPGT" s
    where s.empresa_id=v_empresa and s.numero=v_item->>'solicitud_numero';
    v_line_warehouse:=coalesce(nullif(btrim(v_item->>'almacen_destino_codigo'),''),
      v_request_line.almacen_destino_codigo,nullif(btrim(p_almacen_codigo),''));
    if v_line_warehouse is null then raise exception 'Seleccione el almacén para el artículo %.',v_article.codigo; end if;
    v_line:=v_line+1; v_count:=v_count+1;
    insert into public."ERP_ORDENES_COMPRA_DETALLE_APPGT"(
      empresa_id,orden_numero,linea,solicitud_numero,solicitud_linea,articulo_codigo,
      descripcion,cantidad,cantidad_solicitada,unidad_medida,precio_unitario,
      descuento_porcentaje,impuesto_porcentaje,centro_costo,lote_agricola,
      almacen_destino_codigo,fecha_solicitada
    ) values (
      v_empresa,v_codigo,v_line,nullif(btrim(v_item->>'solicitud_numero'),''),
      nullif(v_item->>'solicitud_linea','')::integer,v_article.codigo,
      coalesce(nullif(btrim(v_item->>'descripcion'),''),v_article.nombre),v_qty,
      coalesce(nullif(v_item->>'cantidad_solicitada','')::numeric,v_qty),
      coalesce(nullif(btrim(v_item->>'unidad_medida'),''),v_article.unidad_medida),
      v_price,v_line_discount,case when coalesce(p_con_igv,false) then 0 else 18 end,
      nullif(btrim(v_item->>'centro_costo'),''),nullif(btrim(v_item->>'lote_agricola'),''),
      v_line_warehouse,v_request_date
    );
    v_sum:=v_sum+round(v_qty*v_price*(1-v_line_discount/100),6);
  end loop;
  if v_discount>v_sum then raise exception 'El descuento no puede superar el importe de los ítems.'; end if;
  if coalesce(p_con_igv,false) then
    v_total:=round(v_sum-v_discount,6);v_subtotal:=round(v_total/1.18,6);
    v_tax:=round(v_total-v_subtotal,6);v_gross:=round(v_subtotal+v_discount,6);
  else
    v_gross:=round(v_sum,6);v_subtotal:=round(v_gross-v_discount,6);
    v_tax:=round(v_subtotal*0.18,6);v_total:=round(v_subtotal+v_tax,6);
  end if;
  update public."ERP_ORDENES_COMPRA_APPGT" set importe_bruto=v_gross,descuento=v_discount,
    subtotal=v_subtotal,impuesto=v_tax,total=v_total
  where empresa_id=v_empresa and numero=v_codigo;
  return jsonb_build_object('guardado',true,'codigo',v_codigo,'estado','PENDIENTE',
    'lineas',v_count,'importe_bruto',v_gross,'descuento',v_discount,
    'subtotal',v_subtotal,'impuesto',v_tax,'total',v_total);
end
$$;

-- --------------------------------------------------------------------------
-- Fechas y cantidades recibidas calculadas desde las operaciones reales.
-- --------------------------------------------------------------------------

create or replace function public.appgt_erp_refrescar_trazabilidad_linea_v1(
  p_empresa uuid,p_orden text,p_linea integer
)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_line public."ERP_ORDENES_COMPRA_DETALLE_APPGT"%rowtype; v_fecha date;
begin
  select * into v_line from public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  where empresa_id=p_empresa and orden_numero=p_orden and linea=p_linea;
  if v_line.id is null then return; end if;
  select max(i.fecha_ingreso) into v_fecha
  from public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT" d
  join public."ERP_INGRESOS_ALMACEN_APPGT" i
    on i.empresa_id=d.empresa_id and i.numero=d.ingreso_numero
  where d.empresa_id=p_empresa and d.orden_numero=p_orden and d.orden_linea=p_linea
    and i.estado='CONFIRMADO' and not i.eliminado and i.deleted_at is null
    and not d.eliminado and d.deleted_at is null;
  update public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  set fecha_recibida=v_fecha where id=v_line.id and fecha_recibida is distinct from v_fecha;
  if v_line.solicitud_numero is not null and v_line.solicitud_linea is not null then
    update public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" sd set
      cantidad_recibida=least(sd.cantidad_solicitada,coalesce((
        select sum(od.cantidad_recibida)
        from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
        join public."ERP_ORDENES_COMPRA_APPGT" o
          on o.empresa_id=od.empresa_id and o.numero=od.orden_numero
        where od.empresa_id=sd.empresa_id and od.solicitud_numero=sd.solicitud_numero
          and od.solicitud_linea=sd.linea and o.estado<>'ANULADO'
          and not od.eliminado and od.deleted_at is null
      ),0)),
      fecha_oc_aprobada=coalesce(sd.fecha_oc_aprobada,(select min(o.aprobado_at::date)
        from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
        join public."ERP_ORDENES_COMPRA_APPGT" o
          on o.empresa_id=od.empresa_id and o.numero=od.orden_numero
        where od.empresa_id=sd.empresa_id and od.solicitud_numero=sd.solicitud_numero
          and od.solicitud_linea=sd.linea and o.estado in (
            'APROBADO','DESPACHADO PARCIALMENTE','DESPACHADO'
          ) and not od.eliminado and od.deleted_at is null)),
      fecha_recibida=(select max(i.fecha_ingreso)
        from public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT" rd
        join public."ERP_INGRESOS_ALMACEN_APPGT" i
          on i.empresa_id=rd.empresa_id and i.numero=rd.ingreso_numero
        join public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
          on od.empresa_id=rd.empresa_id and od.orden_numero=rd.orden_numero
         and od.linea=rd.orden_linea
        where rd.empresa_id=sd.empresa_id and rd.solicitud_numero=sd.solicitud_numero
          and od.solicitud_linea=sd.linea
          and i.estado='CONFIRMADO' and not i.eliminado and i.deleted_at is null
          and not rd.eliminado and rd.deleted_at is null)
    where sd.empresa_id=v_line.empresa_id and sd.solicitud_numero=v_line.solicitud_numero
      and sd.linea=v_line.solicitud_linea;
  end if;
end
$$;

create or replace function public.appgt_erp_trazabilidad_oc_detalle_v1()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if tg_op='INSERT' or new.cantidad_recibida is distinct from old.cantidad_recibida then
    perform public.appgt_erp_refrescar_trazabilidad_linea_v1(new.empresa_id,new.orden_numero,new.linea);
  end if;
  return new;
end $$;

drop trigger if exists erp_trazabilidad_oc_detalle on public."ERP_ORDENES_COMPRA_DETALLE_APPGT";
create trigger erp_trazabilidad_oc_detalle
after insert or update on public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
for each row execute function public.appgt_erp_trazabilidad_oc_detalle_v1();

create or replace function public.appgt_erp_trazabilidad_ingreso_v1()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_item record;
begin
  if new.estado is distinct from old.estado then
    for v_item in select orden_numero,orden_linea
      from public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"
      where empresa_id=new.empresa_id and ingreso_numero=new.numero
    loop
      perform public.appgt_erp_refrescar_trazabilidad_linea_v1(
        new.empresa_id,v_item.orden_numero,v_item.orden_linea
      );
    end loop;
  end if;
  return new;
end $$;

drop trigger if exists erp_trazabilidad_ingreso on public."ERP_INGRESOS_ALMACEN_APPGT";
create trigger erp_trazabilidad_ingreso
after update of estado on public."ERP_INGRESOS_ALMACEN_APPGT"
for each row execute function public.appgt_erp_trazabilidad_ingreso_v1();

create or replace function public.appgt_erp_trazabilidad_aprobacion_oc_v1()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if new.estado='APROBADO' and old.estado is distinct from new.estado then
    update public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
    set fecha_oc_aprobada=coalesce(new.aprobado_at::date,current_date)
    where empresa_id=new.empresa_id and orden_numero=new.numero
      and not eliminado and deleted_at is null;
    update public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" sd
    set fecha_oc_aprobada=coalesce(sd.fecha_oc_aprobada,coalesce(new.aprobado_at::date,current_date))
    where exists (select 1 from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
      where od.empresa_id=sd.empresa_id and od.orden_numero=new.numero
        and od.solicitud_numero=sd.solicitud_numero and od.solicitud_linea=sd.linea
        and not od.eliminado and od.deleted_at is null);
  end if;
  return new;
end $$;

drop trigger if exists erp_trazabilidad_aprobacion_oc on public."ERP_ORDENES_COMPRA_APPGT";
create trigger erp_trazabilidad_aprobacion_oc
after update of estado on public."ERP_ORDENES_COMPRA_APPGT"
for each row execute function public.appgt_erp_trazabilidad_aprobacion_oc_v1();

do $$
declare v_item record;
begin
  for v_item in select empresa_id,orden_numero,linea
    from public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
    where not eliminado and deleted_at is null
  loop
    perform public.appgt_erp_refrescar_trazabilidad_linea_v1(
      v_item.empresa_id,v_item.orden_numero,v_item.linea
    );
  end loop;
end $$;

select set_config('appgt.erp_receipt_context','0',true);

create or replace function public.erp_ordenes_pendientes_ingreso_v1()
returns jsonb
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'numero',o.numero,'referencia',o.numero||' - '||coalesce(o.proveedor_ruc,p.ruc,''),
    'proveedor_codigo',o.proveedor_codigo,'proveedor_ruc',coalesce(o.proveedor_ruc,p.ruc),
    'proveedor',p.razon_social,'almacen_codigo',o.almacen_codigo,'estado',o.estado,
    'detalles',coalesce((select jsonb_agg(jsonb_build_object(
      'linea',d.linea,'solicitud_numero',d.solicitud_numero,
      'articulo_codigo',d.articulo_codigo,'descripcion',coalesce(d.descripcion,a.nombre),
      'unidad_medida',d.unidad_medida,'cantidad_solicitada',d.cantidad_solicitada,
      'cantidad_oc',d.cantidad,'cantidad_recibida',d.cantidad_recibida,
      'cantidad_despachada',d.cantidad_despachada,
      'cantidad_pendiente',greatest(d.cantidad-d.cantidad_despachada,0),
      'costo_unitario',d.precio_unitario,'almacen_destino_codigo',d.almacen_destino_codigo,
      'controla_lote',a.controla_lote,'controla_vencimiento',a.controla_vencimiento
    ) order by d.linea)
    from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d
    join public."ERP_ARTICULOS_APPGT" a on a.empresa_id=d.empresa_id and a.codigo=d.articulo_codigo
    where d.empresa_id=o.empresa_id and d.orden_numero=o.numero
      and d.cantidad_despachada<d.cantidad and not d.eliminado and d.deleted_at is null),'[]'::jsonb)
  ) order by o.fecha_emision,o.numero),'[]'::jsonb)
  from public."ERP_ORDENES_COMPRA_APPGT" o
  join public."ERP_PROVEEDORES_APPGT" p on p.empresa_id=o.empresa_id and p.codigo=o.proveedor_codigo
  where o.empresa_id=public.appgt_empresa_actual_id()
    and o.estado in ('APROBADO','DESPACHADO PARCIALMENTE')
    and not o.eliminado and o.deleted_at is null
    and (auth.role()='service_role' or public.appgt_can_view_table('ERP_ORDENES_COMPRA_APPGT'))
$$;

-- --------------------------------------------------------------------------
-- Vale: identidad automática y centro de costo definido por cada artículo.
-- --------------------------------------------------------------------------

create or replace function public.erp_guardar_vale_despacho_v1(
  p_numero text,p_fecha date,p_usuario_dni text,p_usuario_nombre text,
  p_tipo_destino text,p_centro_costo text,p_almacen_codigo text,
  p_detalles jsonb,p_observacion text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa uuid:=public.appgt_empresa_actual_id();
  v_numero text:=nullif(btrim(coalesce(p_numero,'')),'');
  v_existing public."ERP_VALES_DESPACHO_APPGT"%rowtype;
  v_identidad jsonb:=public.erp_identidad_usuario_actual_v1();
  v_item jsonb; v_article public."ERP_ARTICULOS_APPGT"%rowtype;
  v_line integer:=0; v_qty numeric(20,6); v_tipo text:=upper(btrim(coalesce(p_tipo_destino,'')));
  v_center text; v_header_center text;
begin
  if v_empresa is null then raise exception 'No se pudo resolver la empresa activa'; end if;
  if v_identidad='{}'::jsonb then raise exception 'El usuario activo no tiene perfil válido.' using errcode='42501'; end if;
  if v_tipo not in ('DIRECTO','INDIRECTO') then raise exception 'El destino debe ser DIRECTO o INDIRECTO.'; end if;
  if btrim(coalesce(p_almacen_codigo,''))='' then raise exception 'Seleccione el almacén.'; end if;
  if jsonb_typeof(p_detalles)<>'array' or jsonb_array_length(p_detalles)=0 then raise exception 'Agregue al menos un artículo o insumo.'; end if;
  select nullif(btrim(value->>'centro_costo'),'') into v_header_center
  from jsonb_array_elements(p_detalles) limit 1;
  if v_header_center is null then raise exception 'Defina el centro de costo de cada artículo.'; end if;
  if v_numero is null then
    v_numero:='VD-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,5));
  end if;
  select * into v_existing from public."ERP_VALES_DESPACHO_APPGT"
  where empresa_id=v_empresa and numero=v_numero for update;
  if v_existing.id is null then
    insert into public."ERP_VALES_DESPACHO_APPGT"(
      empresa_id,numero,fecha,usuario_dni,usuario_nombre,tipo_destino,
      centro_costo,almacen_codigo,estado,observacion
    ) values (
      v_empresa,v_numero,coalesce(p_fecha,current_date),v_identidad->>'dni',
      v_identidad->>'usuario_nombre',v_tipo,v_header_center,btrim(p_almacen_codigo),
      'PENDIENTE',nullif(btrim(coalesce(p_observacion,'')),'')
    );
  else
    if v_existing.estado not in ('PENDIENTE','REVISADO') then raise exception 'Solo se puede editar un vale PENDIENTE o REVISADO.'; end if;
    update public."ERP_VALES_DESPACHO_APPGT" set fecha=coalesce(p_fecha,current_date),
      tipo_destino=v_tipo,centro_costo=v_header_center,almacen_codigo=btrim(p_almacen_codigo),
      observacion=nullif(btrim(coalesce(p_observacion,'')),'') where id=v_existing.id;
    delete from public."ERP_VALES_DESPACHO_DETALLE_APPGT"
    where empresa_id=v_empresa and vale_numero=v_numero;
  end if;
  for v_item in select value from jsonb_array_elements(p_detalles) loop
    v_qty:=coalesce((v_item->>'cantidad_solicitada')::numeric,0);
    v_center:=nullif(btrim(coalesce(v_item->>'centro_costo','')),'');
    if v_qty<=0 then raise exception 'Las cantidades solicitadas deben ser mayores a cero.'; end if;
    if v_center is null then raise exception 'Defina el centro de costo de cada artículo.'; end if;
    if v_tipo='INDIRECTO' and upper(v_center)<>'INVERSION' and not exists (
      select 1 from public."PERFILES_DE_USUARIOS_APPGT" p
      where p.empresa_id=v_empresa and upper(btrim(coalesce(p.area,'')))=upper(v_center)
    ) then raise exception 'Para destino indirecto use INVERSION o un área registrada.'; end if;
    select * into v_article from public."ERP_ARTICULOS_APPGT"
    where empresa_id=v_empresa and codigo=v_item->>'articulo_codigo'
      and estado='ACTIVO' and not eliminado and deleted_at is null;
    if v_article.id is null then raise exception 'Artículo no encontrado: %.',v_item->>'articulo_codigo'; end if;
    v_line:=v_line+1;
    insert into public."ERP_VALES_DESPACHO_DETALLE_APPGT"(
      empresa_id,vale_numero,linea,articulo_codigo,descripcion,unidad_medida,
      cantidad_solicitada,centro_costo,lote,observacion
    ) values (
      v_empresa,v_numero,v_line,v_article.codigo,v_article.nombre,v_article.unidad_medida,
      v_qty,v_center,nullif(btrim(coalesce(v_item->>'lote','')),''),
      nullif(btrim(coalesce(v_item->>'observacion','')),'')
    );
  end loop;
  return jsonb_build_object('guardado',true,'vale_numero',v_numero,'estado','PENDIENTE');
end
$$;

create or replace function public.appgt_erp_aplicar_despacho_vale_v1()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_detail record; v_stock record; v_remaining numeric(20,6); v_take numeric(20,6);
  v_seq integer; v_total_cost numeric(20,6); v_cost_unit numeric(20,6); v_center text;
begin
  if old.estado<>'DESPACHADO' and new.estado='DESPACHADO' then
    perform set_config('appgt.erp_dispatch_context','1',true);
    for v_detail in select * from public."ERP_VALES_DESPACHO_DETALLE_APPGT"
      where empresa_id=new.empresa_id and vale_numero=new.numero
        and not eliminado and deleted_at is null order by linea
    loop
      v_center:=coalesce(nullif(btrim(v_detail.centro_costo),''),new.centro_costo);
      v_remaining:=v_detail.cantidad_solicitada;v_seq:=0;v_total_cost:=0;
      for v_stock in select * from public."ERP_STOCK_APPGT" s
        where s.empresa_id=new.empresa_id and s.almacen_codigo=new.almacen_codigo
          and s.articulo_codigo=v_detail.articulo_codigo
          and (v_detail.lote is null or s.lote is not distinct from v_detail.lote)
          and s.cantidad-s.cantidad_reservada>0
        order by s.fecha_vencimiento nulls last,s.lote nulls last,s.id for update
      loop
        exit when v_remaining<=0;
        v_take:=least(v_remaining,v_stock.cantidad-v_stock.cantidad_reservada);
        if v_take<=0 then continue; end if;
        v_seq:=v_seq+1;
        insert into public."ERP_MOVIMIENTOS_INVENTARIO_APPGT"(
          empresa_id,numero,fecha,almacen_codigo,articulo_codigo,lote,fecha_vencimiento,
          tipo_movimiento,direccion,cantidad,costo_unitario,documento_origen_tipo,
          documento_origen_codigo,centro_costo,lote_agricola,observacion,estado
        ) values (
          new.empresa_id,'SAL-'||new.numero||'-'||lpad(v_detail.linea::text,3,'0')||'-'||lpad(v_seq::text,2,'0'),
          clock_timestamp(),new.almacen_codigo,v_detail.articulo_codigo,v_stock.lote,
          v_stock.fecha_vencimiento,'SALIDA_VALE',-1,v_take,v_stock.costo_promedio,
          'VALE_DESPACHO',new.numero,v_center,
          case when new.tipo_destino='DIRECTO' then v_center else null end,
          coalesce(v_detail.observacion,'Vale de despacho'),'CONFIRMADO'
        );
        v_total_cost:=v_total_cost+v_take*v_stock.costo_promedio;v_remaining:=v_remaining-v_take;
      end loop;
      if v_remaining>0 then raise exception 'Stock insuficiente para % en el almacén %. Faltan % %.',
        v_detail.articulo_codigo,new.almacen_codigo,v_remaining,v_detail.unidad_medida; end if;
      v_cost_unit:=case when v_detail.cantidad_solicitada>0 then round(v_total_cost/v_detail.cantidad_solicitada,6) else 0 end;
      update public."ERP_VALES_DESPACHO_DETALLE_APPGT"
      set cantidad_despachada=cantidad_solicitada,costo_unitario=v_cost_unit where id=v_detail.id;
      insert into public."ERP_COSTOS_AGROEXPORTADORES_APPGT"(
        empresa_id,numero,fecha,periodo,centro_costo,lote,tipo_costo,
        documento_origen_tipo,documento_origen_codigo,cantidad,unidad_medida,
        costo_unitario,moneda,tipo_cambio,estado
      ) values (
        new.empresa_id,'CST-'||new.numero||'-'||lpad(v_detail.linea::text,3,'0'),
        new.fecha,to_char(new.fecha,'YYYY-MM'),v_center,
        case when new.tipo_destino='DIRECTO' then v_center else null end,
        'INSUMO','VALE_DESPACHO',new.numero,v_detail.cantidad_solicitada,
        v_detail.unidad_medida,v_cost_unit,'PEN',1,'REGISTRADO'
      ) on conflict (empresa_id,numero) do nothing;
    end loop;
    insert into public."ERP_EVENTOS_INTEGRACION_APPGT"(
      empresa_id,modulo_origen,documento_tipo,documento_numero,evento,modulos_destino,payload
    ) values (
      new.empresa_id,'ALMACEN','VALE_DESPACHO',new.numero,'DESPACHADO',
      array['INVENTARIO','COSTOS','FINANZAS'],jsonb_build_object(
        'centros_costo',(select jsonb_agg(distinct centro_costo)
          from public."ERP_VALES_DESPACHO_DETALLE_APPGT"
          where empresa_id=new.empresa_id and vale_numero=new.numero),
        'tipo_destino',new.tipo_destino,'almacen_codigo',new.almacen_codigo)
    ) on conflict do nothing;
  elsif old.estado='DESPACHADO' and new.estado='ANULADO' then
    perform set_config('appgt.erp_dispatch_context','1',true);
    update public."ERP_MOVIMIENTOS_INVENTARIO_APPGT" set estado='ANULADO'
    where empresa_id=new.empresa_id and documento_origen_tipo='VALE_DESPACHO'
      and documento_origen_codigo=new.numero and estado='CONFIRMADO';
    update public."ERP_COSTOS_AGROEXPORTADORES_APPGT" set estado='ANULADO'
    where empresa_id=new.empresa_id and documento_origen_tipo='VALE_DESPACHO'
      and documento_origen_codigo=new.numero and estado<>'ANULADO';
    update public."ERP_VALES_DESPACHO_DETALLE_APPGT" set cantidad_despachada=0
    where empresa_id=new.empresa_id and vale_numero=new.numero;
    update public."ERP_EVENTOS_INTEGRACION_APPGT" set estado='ANULADO'
    where empresa_id=new.empresa_id and documento_tipo='VALE_DESPACHO'
      and documento_numero=new.numero;
  end if;
  return new;
end
$$;

-- --------------------------------------------------------------------------
-- Metadatos visibles de los formatos.
-- --------------------------------------------------------------------------

with companies as (
  select distinct empresa_id from public."MATRIZ_FORMATOS_APPGT"
), fields(tabla,campo,etiqueta,tipo,tipo_ui,requerido,visible,visible_tabla,editable,orden) as (values
  ('ERP_PROVEEDORES_APPGT','ruc','RUC','text','text',true,true,true,true,2),
  ('ERP_SOLICITUDES_COMPRA_APPGT','numero','Código','text','readonly',false,true,true,false,1),
  ('ERP_SOLICITUDES_COMPRA_DETALLE_APPGT','almacen_destino_codigo','Almacén','text','dropdown',true,true,true,true,7),
  ('ERP_SOLICITUDES_COMPRA_DETALLE_APPGT','cantidad_recibida','Cantidad recibida','numeric','readonly',false,true,true,false,8),
  ('ERP_SOLICITUDES_COMPRA_DETALLE_APPGT','fecha_oc_aprobada','Fecha OC aprobada','date','readonly',false,true,true,false,9),
  ('ERP_SOLICITUDES_COMPRA_DETALLE_APPGT','fecha_recibida','Fecha recibida','date','readonly',false,true,true,false,10),
  ('ERP_ORDENES_COMPRA_APPGT','numero','Código OC','text','readonly',false,true,true,false,1),
  ('ERP_ORDENES_COMPRA_APPGT','tipo_cambio','Tipo de cambio a PEN','numeric','number',true,true,true,true,8),
  ('ERP_ORDENES_COMPRA_DETALLE_APPGT','almacen_destino_codigo','Almacén','text','dropdown',true,true,true,true,8),
  ('ERP_ORDENES_COMPRA_DETALLE_APPGT','cantidad_solicitada','Cantidad solicitada','numeric','readonly',false,true,true,false,9),
  ('ERP_ORDENES_COMPRA_DETALLE_APPGT','cantidad_recibida','Cantidad recibida','numeric','readonly',false,true,true,false,10),
  ('ERP_ORDENES_COMPRA_DETALLE_APPGT','fecha_solicitada','Fecha solicitada','date','readonly',false,true,true,false,11),
  ('ERP_ORDENES_COMPRA_DETALLE_APPGT','fecha_oc_aprobada','Fecha OC aprobada','date','readonly',false,true,true,false,12),
  ('ERP_ORDENES_COMPRA_DETALLE_APPGT','fecha_recibida','Fecha recibida','date','readonly',false,true,true,false,13),
  ('ERP_VALES_DESPACHO_APPGT','usuario_dni','Usuario (DNI)','text','readonly',false,true,true,false,3),
  ('ERP_VALES_DESPACHO_APPGT','usuario_nombre','Nombre de usuario','text','readonly',false,true,true,false,4),
  ('ERP_VALES_DESPACHO_DETALLE_APPGT','centro_costo','Centro de costo','text','dropdown',true,true,true,true,7)
)
insert into public."MATRIZ_CAMPOS_FORMATO_APPGT"(
  id,empresa_id,tabla_destino,campo,etiqueta,tipo,tipo_ui,requerido,visible,
  visible_tabla,editable,orden,activo,created_at,updated_at,estado_sync,eliminado
)
select 'erp_trace_'||substr(md5(c.empresa_id::text||'|'||f.tabla||'|'||f.campo),1,24),
  c.empresa_id,f.tabla,f.campo,f.etiqueta,f.tipo,f.tipo_ui,f.requerido,
  f.visible,f.visible_tabla,f.editable,f.orden,true,now(),now(),'sincronizado',false
from companies c cross join fields f
on conflict (tabla_destino,campo) do update set
  etiqueta=excluded.etiqueta,tipo=excluded.tipo,tipo_ui=excluded.tipo_ui,
  requerido=excluded.requerido,visible=excluded.visible,visible_tabla=excluded.visible_tabla,
  editable=excluded.editable,orden=excluded.orden,activo=true,eliminado=false,updated_at=now();

update public."MATRIZ_CAMPOS_FORMATO_APPGT" set
  visible=false,visible_tabla=false,editable=false,activo=false,updated_at=now()
where tabla_destino='ERP_PROVEEDORES_APPGT'
  and campo in ('tipo_documento','numero_documento');

update public."MATRIZ_CAMPOS_FORMATO_APPGT" set
  etiqueta='Domicilio fiscal',updated_at=now()
where tabla_destino='ERP_PROVEEDORES_APPGT' and campo='direccion';

update public."MATRIZ_CAMPOS_FORMATO_APPGT" set
  tipo_ui='readonly',editable=false,updated_at=now()
where (tabla_destino='ERP_SOLICITUDES_COMPRA_APPGT' and campo in ('numero','solicitante'))
   or (tabla_destino='ERP_ORDENES_COMPRA_APPGT' and campo='numero')
   or (tabla_destino='ERP_VALES_DESPACHO_APPGT' and campo in ('usuario_dni','usuario_nombre'));

revoke all on function public.erp_identidad_usuario_actual_v1() from public,anon;
grant execute on function public.erp_identidad_usuario_actual_v1() to authenticated,service_role;
grant execute on function public.erp_guardar_solicitud_pedido_v1(text,date,date,text,text,text,text,jsonb) to authenticated,service_role;
grant execute on function public.erp_guardar_orden_compra_v1(text,text,date,date,text,numeric,text,text,text,boolean,numeric,jsonb,jsonb) to authenticated,service_role;
grant execute on function public.erp_guardar_vale_despacho_v1(text,date,text,text,text,text,text,jsonb,text) to authenticated,service_role;
grant execute on function public.erp_solicitudes_aprobadas_oc_v1() to authenticated,service_role;
grant execute on function public.erp_ordenes_pendientes_ingreso_v1() to authenticated,service_role;

notify pgrst, 'reload schema';
commit;
