begin;

-- La migración recalcula líneas históricas aprobadas dentro de una única
-- transacción de mantenimiento. El guard de documentos reconoce este contexto.
select set_config('appgt.erp_receipt_context','1',true);

-- ============================================================================
-- Correlativos legibles y uniformes por empresa.
-- ============================================================================

create or replace function public.appgt_erp_codigo_automatico_v1()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_prefix text;
  v_field text;
  v_next bigint;
begin
  v_prefix:=case tg_table_name
    when 'ERP_PROVEEDORES_APPGT' then 'PRV-'
    when 'ERP_SOLICITUDES_COMPRA_APPGT' then 'SP-'
    when 'ERP_ORDENES_COMPRA_APPGT' then 'OC-'
    when 'ERP_VALES_DESPACHO_APPGT' then 'VD-'
    when 'ERP_INGRESOS_ALMACEN_APPGT' then 'I-'
    when 'ERP_CLIENTES_APPGT' then 'CL-'
    when 'ERP_PEDIDOS_VENTA_APPGT' then 'PV-'
    when 'ERP_EXPORTACIONES_APPGT' then 'EX-'
  end;
  if v_prefix is null then return new; end if;

  v_field:=case when tg_table_name in ('ERP_PROVEEDORES_APPGT','ERP_CLIENTES_APPGT')
    then 'codigo' else 'numero' end;
  perform pg_advisory_xact_lock(hashtext(tg_table_name),hashtext(new.empresa_id::text));
  execute format(
    'select greatest(100001,coalesce(max(case when %1$I~%2$L then substring(%1$I from %3$s)::bigint end),100000)+1) from public.%4$I where empresa_id=$1',
    v_field,'^'||v_prefix||'[0-9]+$',(length(v_prefix)+1)::text,tg_table_name
  ) into v_next using new.empresa_id;

  if v_field='codigo' then new.codigo:=v_prefix||v_next::text;
  else new.numero:=v_prefix||v_next::text;
  end if;
  return new;
end
$$;

do $$
declare v_table text; v_trigger text;
begin
  for v_table,v_trigger in select * from (values
    ('ERP_PROVEEDORES_APPGT','erp_codigo_proveedor_automatico'),
    ('ERP_SOLICITUDES_COMPRA_APPGT','erp_codigo_solicitud_automatico'),
    ('ERP_ORDENES_COMPRA_APPGT','erp_codigo_oc_automatico'),
    ('ERP_VALES_DESPACHO_APPGT','erp_codigo_vale_automatico'),
    ('ERP_INGRESOS_ALMACEN_APPGT','erp_codigo_ingreso_automatico'),
    ('ERP_CLIENTES_APPGT','erp_codigo_cliente_automatico'),
    ('ERP_PEDIDOS_VENTA_APPGT','erp_codigo_pedido_venta_automatico'),
    ('ERP_EXPORTACIONES_APPGT','erp_codigo_exportacion_automatico')
  ) as x(tabla,disparador)
  loop
    execute format('drop trigger if exists %I on public.%I',v_trigger,v_table);
    execute format(
      'create trigger %I before insert on public.%I for each row execute function public.appgt_erp_codigo_automatico_v1()',
      v_trigger,v_table
    );
  end loop;
end
$$;

-- ============================================================================
-- Orden de compra: porcentaje configurable y fórmulas explícitas.
-- ============================================================================

alter table public."ERP_ORDENES_COMPRA_APPGT"
  add column if not exists igv_porcentaje numeric(9,6) not null default 18;
alter table public."ERP_ORDENES_COMPRA_APPGT"
  drop constraint if exists erp_oc_igv_porcentaje_ck;
alter table public."ERP_ORDENES_COMPRA_APPGT"
  add constraint erp_oc_igv_porcentaje_ck check (igv_porcentaje between 0 and 100);
alter table public."ERP_ORDENES_COMPRA_APPGT"
  alter column impuesto drop not null;

alter table public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  alter column subtotal drop expression if exists,
  alter column impuesto drop expression if exists,
  alter column total drop expression if exists;
alter table public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  add column if not exists con_igv boolean not null default false,
  add column if not exists importe numeric(20,6) not null default 0,
  add column if not exists descuento numeric(20,6) not null default 0,
  add column if not exists estado text not null default 'PENDIENTE';
alter table public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  alter column impuesto drop not null;

create or replace function public.appgt_erp_calcular_linea_oc_v2()
returns trigger
language plpgsql
set search_path=public,pg_temp
as $$
begin
  new.descuento_porcentaje:=least(greatest(coalesce(new.descuento_porcentaje,0),0),100);
  new.impuesto_porcentaje:=least(greatest(coalesce(new.impuesto_porcentaje,18),0),100);
  new.importe:=round(coalesce(new.cantidad,0)*coalesce(new.precio_unitario,0),6);
  new.descuento:=round(new.importe*new.descuento_porcentaje/100,6);
  new.subtotal:=round(new.importe-new.descuento,6);
  new.impuesto:=case when coalesce(new.con_igv,false) then null
    else round(new.subtotal*new.impuesto_porcentaje/100,6) end;
  new.total:=round(new.subtotal+coalesce(new.impuesto,0),6);
  return new;
end
$$;

drop trigger if exists erp_calcular_linea_oc_v2 on public."ERP_ORDENES_COMPRA_DETALLE_APPGT";
create trigger erp_calcular_linea_oc_v2
before insert or update of cantidad,precio_unitario,descuento_porcentaje,
  impuesto_porcentaje,con_igv
on public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
for each row execute function public.appgt_erp_calcular_linea_oc_v2();

update public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d set
  con_igv=o.con_igv,
  impuesto_porcentaje=o.igv_porcentaje,
  cantidad=d.cantidad
from public."ERP_ORDENES_COMPRA_APPGT" o
where o.empresa_id=d.empresa_id and o.numero=d.orden_numero;

drop trigger if exists erp_otros_descuentos on public."ERP_ORDENES_COMPRA_APPGT";

drop function if exists public.erp_guardar_orden_compra_v1(
  text,text,date,date,text,numeric,text,text,text,boolean,numeric,jsonb,jsonb
);

create function public.erp_guardar_orden_compra_v1(
  p_codigo text,p_proveedor_codigo text,p_fecha_emision date,p_fecha_entrega date,
  p_moneda text,p_tipo_cambio numeric,p_condicion_pago text,p_almacen_codigo text,
  p_observacion text,p_con_igv boolean,p_igv_porcentaje numeric,p_descuento numeric,
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
  v_line integer:=0; v_count integer:=0;
  v_qty numeric(20,6); v_price numeric(20,6); v_line_discount numeric(9,6);
  v_igv numeric(9,6):=least(greatest(coalesce(p_igv_porcentaje,18),0),100);
  v_other_discount numeric(20,6):=greatest(coalesce(p_descuento,0),0);
  v_items numeric(20,6):=0; v_line_discounts numeric(20,6):=0;
  v_discount_total numeric(20,6); v_subtotal numeric(20,6);
  v_tax numeric(20,6); v_total numeric(20,6);
  v_first_request text;
  v_request_line public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"%rowtype;
  v_request_date date; v_line_warehouse text;
begin
  if v_empresa is null then raise exception 'No se pudo resolver la empresa activa' using errcode='42501'; end if;
  if btrim(coalesce(p_proveedor_codigo,''))='' then raise exception 'Seleccione un proveedor.'; end if;
  if btrim(coalesce(p_almacen_codigo,''))='' then raise exception 'Seleccione un almacén.'; end if;
  if jsonb_typeof(p_solicitudes)<>'array' or jsonb_array_length(p_solicitudes)=0 then
    raise exception 'Agregue al menos una solicitud de pedido aprobada.';
  end if;
  if jsonb_typeof(p_detalles)<>'array' or jsonb_array_length(p_detalles)=0 then
    raise exception 'La orden de compra debe tener al menos un ítem.';
  end if;
  select nullif(btrim(coalesce(value->>'numero',value#>>'{}')),'') into v_first_request
  from jsonb_array_elements(p_solicitudes) limit 1;

  if v_codigo is not null then
    select * into v_existing from public."ERP_ORDENES_COMPRA_APPGT"
    where empresa_id=v_empresa and numero=v_codigo for update;
  end if;
  if v_existing.id is null then
    insert into public."ERP_ORDENES_COMPRA_APPGT"(
      empresa_id,numero,solicitud_numero,proveedor_codigo,fecha_emision,fecha_entrega,
      moneda,tipo_cambio,condicion_pago,almacen_codigo,con_igv,igv_porcentaje,
      importe_bruto,subtotal,descuento,otros_descuentos,impuesto,total,estado,observacion
    ) values (
      v_empresa,null,v_first_request,btrim(p_proveedor_codigo),coalesce(p_fecha_emision,current_date),
      p_fecha_entrega,upper(coalesce(nullif(btrim(p_moneda),''),'PEN')),coalesce(p_tipo_cambio,1),
      nullif(btrim(coalesce(p_condicion_pago,'')),''),btrim(p_almacen_codigo),
      coalesce(p_con_igv,false),v_igv,0,0,0,v_other_discount,null,0,'PENDIENTE',
      nullif(btrim(coalesce(p_observacion,'')),'')
    ) returning numero into v_codigo;
  else
    if v_existing.estado not in ('PENDIENTE','REVISADO') then
      raise exception 'La orden % no se puede editar en estado %.',v_codigo,v_existing.estado;
    end if;
    update public."ERP_ORDENES_COMPRA_APPGT" set
      solicitud_numero=v_first_request,proveedor_codigo=btrim(p_proveedor_codigo),
      fecha_emision=coalesce(p_fecha_emision,current_date),fecha_entrega=p_fecha_entrega,
      moneda=upper(coalesce(nullif(btrim(p_moneda),''),'PEN')),tipo_cambio=coalesce(p_tipo_cambio,1),
      condicion_pago=nullif(btrim(coalesce(p_condicion_pago,'')),''),
      almacen_codigo=btrim(p_almacen_codigo),con_igv=coalesce(p_con_igv,false),
      igv_porcentaje=v_igv,otros_descuentos=v_other_discount,
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
    if not exists(select 1 from public."ERP_SOLICITUDES_COMPRA_APPGT" s
      where s.empresa_id=v_empresa
        and s.numero=nullif(btrim(coalesce(v_item->>'numero',v_item#>>'{}')),'')
        and s.estado='APROBADO' and not s.eliminado and s.deleted_at is null) then
      raise exception 'La solicitud % no está aprobada o disponible.',coalesce(v_item->>'numero',v_item#>>'{}');
    end if;
    insert into public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT"(
      empresa_id,orden_numero,solicitud_numero
    ) values (
      v_empresa,v_codigo,nullif(btrim(coalesce(v_item->>'numero',v_item#>>'{}')),'')
    ) on conflict (empresa_id,orden_numero,solicitud_numero) do update set
      eliminado=false,deleted_at=null,created_by=auth.uid();
  end loop;

  for v_item in select value from jsonb_array_elements(p_detalles) loop
    v_qty:=coalesce((v_item->>'cantidad')::numeric,0);
    v_price:=greatest(coalesce((v_item->>'precio_unitario')::numeric,0),0);
    v_line_discount:=least(greatest(coalesce((v_item->>'descuento_porcentaje')::numeric,0),0),100);
    if v_qty<=0 then raise exception 'Todas las cantidades deben ser mayores que cero.'; end if;
    if not exists(select 1 from public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT" os
      where os.empresa_id=v_empresa and os.orden_numero=v_codigo
        and os.solicitud_numero=nullif(btrim(coalesce(v_item->>'solicitud_numero','')),'')
        and not os.eliminado and os.deleted_at is null) then
      raise exception 'Cada ítem debe pertenecer a una solicitud agregada a la orden.';
    end if;
    select * into v_article from public."ERP_ARTICULOS_APPGT"
    where empresa_id=v_empresa and codigo=v_item->>'articulo_codigo'
      and not eliminado and deleted_at is null;
    if v_article.id is null then raise exception 'Artículo no encontrado: %',v_item->>'articulo_codigo'; end if;
    select * into v_request_line from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" d
    where d.empresa_id=v_empresa and d.solicitud_numero=v_item->>'solicitud_numero'
      and d.linea=nullif(v_item->>'solicitud_linea','')::integer;
    select s.fecha into v_request_date from public."ERP_SOLICITUDES_COMPRA_APPGT" s
    where s.empresa_id=v_empresa and s.numero=v_item->>'solicitud_numero';
    v_line_warehouse:=coalesce(nullif(btrim(v_item->>'almacen_destino_codigo'),''),
      v_request_line.almacen_destino_codigo,nullif(btrim(p_almacen_codigo),''));
    if v_line_warehouse is null then raise exception 'Seleccione el almacén para el artículo %.',v_article.codigo; end if;

    v_line:=v_line+1; v_count:=v_count+1;
    insert into public."ERP_ORDENES_COMPRA_DETALLE_APPGT"(
      empresa_id,orden_numero,linea,solicitud_numero,solicitud_linea,articulo_codigo,
      descripcion,cantidad,cantidad_solicitada,unidad_medida,precio_unitario,
      descuento_porcentaje,impuesto_porcentaje,con_igv,centro_costo,lote_agricola,
      almacen_destino_codigo,fecha_solicitada,estado
    ) values (
      v_empresa,v_codigo,v_line,nullif(btrim(v_item->>'solicitud_numero'),''),
      nullif(v_item->>'solicitud_linea','')::integer,v_article.codigo,
      coalesce(nullif(btrim(v_item->>'descripcion'),''),v_article.nombre),v_qty,
      coalesce(nullif(v_item->>'cantidad_solicitada','')::numeric,v_qty),
      coalesce(nullif(btrim(v_item->>'unidad_medida'),''),v_article.unidad_medida),
      v_price,v_line_discount,v_igv,coalesce(p_con_igv,false),
      nullif(btrim(v_item->>'centro_costo'),''),nullif(btrim(v_item->>'lote_agricola'),''),
      v_line_warehouse,v_request_date,'PENDIENTE'
    );
    v_items:=v_items+round(v_qty*v_price,6);
    v_line_discounts:=v_line_discounts+round(v_qty*v_price*v_line_discount/100,6);
  end loop;

  v_discount_total:=round(v_line_discounts+v_other_discount,6);
  if v_discount_total>v_items then
    raise exception 'El descuento total no puede superar el importe de los ítems.';
  end if;
  v_subtotal:=round(v_items-v_discount_total,6);
  v_tax:=case when coalesce(p_con_igv,false) then null else round(v_subtotal*v_igv/100,6) end;
  v_total:=round(v_subtotal+coalesce(v_tax,0),6);
  update public."ERP_ORDENES_COMPRA_APPGT" set
    importe_bruto=v_items,descuento=v_discount_total,otros_descuentos=v_other_discount,
    subtotal=v_subtotal,impuesto=v_tax,total=v_total
  where empresa_id=v_empresa and numero=v_codigo;
  return jsonb_build_object('guardado',true,'codigo',v_codigo,'estado','PENDIENTE',
    'lineas',v_count,'importe_bruto',v_items,'descuento',v_discount_total,
    'subtotal',v_subtotal,'impuesto',v_tax,'total',v_total,'igv_porcentaje',v_igv);
end
$$;

revoke all on function public.erp_guardar_orden_compra_v1(
  text,text,date,date,text,numeric,text,text,text,boolean,numeric,numeric,jsonb,jsonb
) from public,anon;
grant execute on function public.erp_guardar_orden_compra_v1(
  text,text,date,date,text,numeric,text,text,text,boolean,numeric,numeric,jsonb,jsonb
) to authenticated,service_role;

-- ============================================================================
-- Un solo campo estado para aprobación y recepción.
-- ============================================================================

select set_config('appgt.erp_receipt_context','1',true);

alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  drop constraint if exists erp_solicitud_estado_ck;
alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  add constraint erp_solicitud_estado_ck check (
    estado in ('PENDIENTE','REVISADO','APROBADO','RECIBIDO PARCIAL','RECIBIDO','ANULADO')
  );
alter table public."ERP_ORDENES_COMPRA_APPGT"
  drop constraint if exists erp_oc_estado_ck,
  drop constraint if exists "ERP_ORDENES_COMPRA_APPGT_estado_check";
alter table public."ERP_ORDENES_COMPRA_APPGT" disable trigger erp_validar_flujo_v3;
update public."ERP_ORDENES_COMPRA_APPGT" set estado=case estado
  when 'DESPACHADO PARCIALMENTE' then 'RECIBIDO PARCIAL'
  when 'DESPACHADO' then 'RECIBIDO' else estado end;
alter table public."ERP_ORDENES_COMPRA_APPGT"
  add constraint erp_oc_estado_ck check (
    estado in ('PENDIENTE','REVISADO','APROBADO','RECIBIDO PARCIAL','RECIBIDO','ANULADO')
  );

alter table public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"
  add column if not exists estado text not null default 'PENDIENTE';
alter table public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  add column if not exists estado text not null default 'PENDIENTE';
alter table public."ERP_VALES_DESPACHO_DETALLE_APPGT"
  add column if not exists estado text not null default 'PENDIENTE';

update public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" d
set estado=case when coalesce(d.cantidad_recibida,0)<=0 then s.estado
  when d.cantidad_recibida>=d.cantidad_solicitada then 'RECIBIDO'
  else 'RECIBIDO PARCIAL' end
from public."ERP_SOLICITUDES_COMPRA_APPGT" s
where s.empresa_id=d.empresa_id and s.numero=d.solicitud_numero;
update public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d
set estado=case when coalesce(d.cantidad_recibida,0)<=0 then o.estado
  when d.cantidad_recibida>=d.cantidad then 'RECIBIDO'
  else 'RECIBIDO PARCIAL' end
from public."ERP_ORDENES_COMPRA_APPGT" o
where o.empresa_id=d.empresa_id and o.numero=d.orden_numero;
update public."ERP_VALES_DESPACHO_DETALLE_APPGT" d set estado=v.estado
from public."ERP_VALES_DESPACHO_APPGT" v
where v.empresa_id=d.empresa_id and v.numero=d.vale_numero;

alter table public."ERP_SOLICITUDES_COMPRA_APPGT" drop column if exists estado_de_recibido;
alter table public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" drop column if exists estado_de_recibido;
alter table public."ERP_ORDENES_COMPRA_APPGT" drop column if exists estado_de_recibido;
alter table public."ERP_ORDENES_COMPRA_DETALLE_APPGT" drop column if exists estado_de_recibido;

create or replace function public.appgt_erp_validar_flujo_documento_v3()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_allowed boolean;
  v_details integer;
  v_receipt_context boolean:=coalesce(current_setting('appgt.erp_receipt_context',true),'0')='1';
  v_pdf_context boolean:=coalesce(current_setting('appgt.erp_pdf_context',true),'0')='1';
begin
  if tg_op='DELETE' then
    if auth.role()<>'service_role' then
      v_allowed:=public.appgt_puede_accion_estado_formato_v1(tg_table_name,old.estado,'delete');
      if not v_allowed then raise exception 'Sin permiso para eliminar registros % en estado %.',tg_table_name,old.estado using errcode='42501'; end if;
    end if;
    return old;
  end if;
  new.estado:=upper(btrim(coalesce(new.estado,'PENDIENTE')));
  if tg_op='INSERT' then
    if auth.role()<>'service_role' and not public.appgt_puede_accion_estado_formato_v1(
      tg_table_name,new.estado,'create') then
      raise exception 'Sin permiso para crear registros % en estado %.',tg_table_name,new.estado using errcode='42501';
    end if;
    if new.estado<>'PENDIENTE' and auth.role()<>'service_role' then
      raise exception 'Todo documento nuevo debe iniciar en PENDIENTE.';
    end if;
    return new;
  end if;
  if auth.role()<>'service_role' and not v_pdf_context
     and not (v_receipt_context and tg_table_name in ('ERP_SOLICITUDES_COMPRA_APPGT','ERP_ORDENES_COMPRA_APPGT'))
     and not (
       new.estado is distinct from old.estado and new.estado='ANULADO'
       and (public.appgt_can_update_table(tg_table_name) or public.appgt_can_delete_table(tg_table_name))
     )
     and not public.appgt_puede_accion_estado_formato_v1(tg_table_name,old.estado,'update') then
    raise exception 'Sin permiso para editar registros % en estado %.',tg_table_name,old.estado using errcode='42501';
  end if;
  if new.estado is distinct from old.estado then
    if tg_table_name in ('ERP_SOLICITUDES_COMPRA_APPGT','ERP_ORDENES_COMPRA_APPGT') then
      if not (
        (old.estado='PENDIENTE' and new.estado='REVISADO') or
        (old.estado='REVISADO' and new.estado='APROBADO') or
        (old.estado in ('PENDIENTE','REVISADO','APROBADO') and new.estado='ANULADO') or
        (v_receipt_context and old.estado in ('APROBADO','RECIBIDO PARCIAL','RECIBIDO')
          and new.estado in ('APROBADO','RECIBIDO PARCIAL','RECIBIDO'))
      ) then raise exception 'Transición no permitida: % -> %.',old.estado,new.estado; end if;
    elsif tg_table_name='ERP_VALES_DESPACHO_APPGT' then
      if not (
        (old.estado='PENDIENTE' and new.estado='REVISADO') or
        (old.estado='REVISADO' and new.estado='APROBADO') or
        (old.estado='APROBADO' and new.estado='DESPACHADO') or
        (old.estado in ('PENDIENTE','REVISADO','APROBADO','DESPACHADO') and new.estado='ANULADO')
      ) then raise exception 'Transición no permitida: % -> %.',old.estado,new.estado; end if;
    end if;
    if new.estado='REVISADO' then
      new.revisado_por:=auth.uid();new.revisado_at:=clock_timestamp();
    elsif new.estado='APROBADO' and not v_receipt_context then
      new.aprobado_por:=auth.uid();new.aprobado_at:=clock_timestamp();
      if tg_table_name='ERP_SOLICITUDES_COMPRA_APPGT' then
        select count(*) into v_details from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"
        where empresa_id=new.empresa_id and solicitud_numero=new.numero and not eliminado and deleted_at is null;
      elsif tg_table_name='ERP_ORDENES_COMPRA_APPGT' then
        select count(*) into v_details from public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
        where empresa_id=new.empresa_id and orden_numero=new.numero and not eliminado and deleted_at is null;
      elsif tg_table_name='ERP_VALES_DESPACHO_APPGT' then
        select count(*) into v_details from public."ERP_VALES_DESPACHO_DETALLE_APPGT"
        where empresa_id=new.empresa_id and vale_numero=new.numero and not eliminado and deleted_at is null;
      end if;
      if coalesce(v_details,0)=0 then raise exception 'No se puede aprobar un documento sin artículos o insumos.'; end if;
    elsif new.estado='DESPACHADO' and tg_table_name='ERP_VALES_DESPACHO_APPGT' then
      new.despachado_por:=auth.uid();new.despachado_at:=clock_timestamp();
    elsif new.estado='ANULADO' then
      new.anulado_por:=auth.uid();new.anulado_at:=clock_timestamp();
    end if;
  end if;
  return new;
end
$$;

alter table public."ERP_ORDENES_COMPRA_APPGT" enable trigger erp_validar_flujo_v3;

create or replace function public.appgt_erp_propagar_estado_detalle_v1()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if new.estado is not distinct from old.estado then return new; end if;
  if tg_table_name='ERP_SOLICITUDES_COMPRA_APPGT' then
    update public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"
    set estado=new.estado where empresa_id=new.empresa_id and solicitud_numero=new.numero
      and not eliminado and deleted_at is null and coalesce(cantidad_recibida,0)=0;
  elsif tg_table_name='ERP_ORDENES_COMPRA_APPGT' then
    update public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
    set estado=new.estado where empresa_id=new.empresa_id and orden_numero=new.numero
      and not eliminado and deleted_at is null and coalesce(cantidad_recibida,0)=0;
  elsif tg_table_name='ERP_VALES_DESPACHO_APPGT' then
    update public."ERP_VALES_DESPACHO_DETALLE_APPGT"
    set estado=new.estado where empresa_id=new.empresa_id and vale_numero=new.numero
      and not eliminado and deleted_at is null;
  end if;
  return new;
end $$;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'ERP_SOLICITUDES_COMPRA_APPGT','ERP_ORDENES_COMPRA_APPGT','ERP_VALES_DESPACHO_APPGT'
  ] loop
    execute format('drop trigger if exists erp_propagar_estado_detalle on public.%I',v_table);
    execute format('create trigger erp_propagar_estado_detalle after update of estado on public.%I for each row execute function public.appgt_erp_propagar_estado_detalle_v1()',v_table);
  end loop;
end $$;

create or replace function public.appgt_erp_refrescar_cabeceras_v2(
  p_empresa uuid,p_orden text,p_solicitud text
)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  perform set_config('appgt.erp_receipt_context','1',true);
  if p_orden is not null then
    update public."ERP_ORDENES_COMPRA_APPGT" o set
      fecha_recibida=(select max(i.fecha_ingreso) from public."ERP_INGRESOS_ALMACEN_APPGT" i
        where i.empresa_id=o.empresa_id and i.orden_numero=o.numero
          and i.estado='CONFIRMADO' and not i.eliminado and i.deleted_at is null),
      estado=case
        when coalesce((select sum(d.cantidad_recibida) from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d
          where d.empresa_id=o.empresa_id and d.orden_numero=o.numero and not d.eliminado and d.deleted_at is null),0)=0 then 'APROBADO'
        when (select bool_and(d.cantidad_recibida>=d.cantidad) from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d
          where d.empresa_id=o.empresa_id and d.orden_numero=o.numero and not d.eliminado and d.deleted_at is null) then 'RECIBIDO'
        else 'RECIBIDO PARCIAL' end
    where o.empresa_id=p_empresa and o.numero=p_orden
      and o.estado in ('APROBADO','RECIBIDO PARCIAL','RECIBIDO');
  end if;
  if p_solicitud is not null then
    update public."ERP_SOLICITUDES_COMPRA_APPGT" s set
      fecha_aprobacion_oc=(select min(o.aprobado_at::date)
        from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
        join public."ERP_ORDENES_COMPRA_APPGT" o on o.empresa_id=od.empresa_id and o.numero=od.orden_numero
        where od.empresa_id=s.empresa_id and od.solicitud_numero=s.numero
          and o.estado in ('APROBADO','RECIBIDO PARCIAL','RECIBIDO')
          and not od.eliminado and od.deleted_at is null),
      orden_compra=(select string_agg(distinct o.numero,', ' order by o.numero)
        from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
        join public."ERP_ORDENES_COMPRA_APPGT" o on o.empresa_id=od.empresa_id and o.numero=od.orden_numero
        where od.empresa_id=s.empresa_id and od.solicitud_numero=s.numero
          and o.estado in ('APROBADO','RECIBIDO PARCIAL','RECIBIDO')
          and not od.eliminado and od.deleted_at is null),
      estado=case
        when coalesce((select sum(sd.cantidad_recibida) from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" sd
          where sd.empresa_id=s.empresa_id and sd.solicitud_numero=s.numero and not sd.eliminado and sd.deleted_at is null),0)=0 then 'APROBADO'
        when (select bool_and(sd.cantidad_recibida>=sd.cantidad_solicitada)
          from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" sd
          where sd.empresa_id=s.empresa_id and sd.solicitud_numero=s.numero and not sd.eliminado and sd.deleted_at is null) then 'RECIBIDO'
        else 'RECIBIDO PARCIAL' end
    where s.empresa_id=p_empresa and s.numero=p_solicitud
      and s.estado in ('APROBADO','RECIBIDO PARCIAL','RECIBIDO');
  end if;
end $$;

create or replace function public.appgt_erp_refrescar_trazabilidad_linea_v1(
  p_empresa uuid,p_orden text,p_linea integer
)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_line public."ERP_ORDENES_COMPRA_DETALLE_APPGT"%rowtype; v_fecha date;
begin
  perform set_config('appgt.erp_receipt_context','1',true);
  select * into v_line from public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  where empresa_id=p_empresa and orden_numero=p_orden and linea=p_linea;
  if v_line.id is null then return; end if;
  select max(i.fecha_ingreso) into v_fecha
  from public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT" d
  join public."ERP_INGRESOS_ALMACEN_APPGT" i on i.empresa_id=d.empresa_id and i.numero=d.ingreso_numero
  where d.empresa_id=p_empresa and d.orden_numero=p_orden and d.orden_linea=p_linea
    and i.estado='CONFIRMADO' and not i.eliminado and i.deleted_at is null
    and not d.eliminado and d.deleted_at is null;
  update public."ERP_ORDENES_COMPRA_DETALLE_APPGT" set
    fecha_recibida=v_fecha,
    estado=case when cantidad_recibida<=0 then 'APROBADO'
      when cantidad_recibida>=cantidad then 'RECIBIDO' else 'RECIBIDO PARCIAL' end
  where id=v_line.id;
  if v_line.solicitud_numero is not null and v_line.solicitud_linea is not null then
    update public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" sd set
      cantidad_recibida=least(sd.cantidad_solicitada,coalesce((select sum(od.cantidad_recibida)
        from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
        join public."ERP_ORDENES_COMPRA_APPGT" o on o.empresa_id=od.empresa_id and o.numero=od.orden_numero
        where od.empresa_id=sd.empresa_id and od.solicitud_numero=sd.solicitud_numero
          and od.solicitud_linea=sd.linea and o.estado<>'ANULADO'
          and not od.eliminado and od.deleted_at is null),0)),
      fecha_recibida=v_fecha,
      estado=case
        when least(sd.cantidad_solicitada,coalesce((select sum(od.cantidad_recibida)
          from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
          join public."ERP_ORDENES_COMPRA_APPGT" o on o.empresa_id=od.empresa_id and o.numero=od.orden_numero
          where od.empresa_id=sd.empresa_id and od.solicitud_numero=sd.solicitud_numero
            and od.solicitud_linea=sd.linea and o.estado<>'ANULADO'
            and not od.eliminado and od.deleted_at is null),0))<=0 then 'APROBADO'
        when least(sd.cantidad_solicitada,coalesce((select sum(od.cantidad_recibida)
          from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
          join public."ERP_ORDENES_COMPRA_APPGT" o on o.empresa_id=od.empresa_id and o.numero=od.orden_numero
          where od.empresa_id=sd.empresa_id and od.solicitud_numero=sd.solicitud_numero
            and od.solicitud_linea=sd.linea and o.estado<>'ANULADO'
            and not od.eliminado and od.deleted_at is null),0))>=sd.cantidad_solicitada then 'RECIBIDO'
        else 'RECIBIDO PARCIAL' end
    where sd.empresa_id=v_line.empresa_id and sd.solicitud_numero=v_line.solicitud_numero
      and sd.linea=v_line.solicitud_linea;
  end if;
  perform public.appgt_erp_refrescar_cabeceras_v2(
    v_line.empresa_id,v_line.orden_numero,v_line.solicitud_numero
  );
end $$;

create or replace function public.erp_ordenes_pendientes_ingreso_v1()
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
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
      'cantidad_pendiente',greatest(d.cantidad-d.cantidad_recibida,0),
      'costo_unitario',d.precio_unitario,'almacen_destino_codigo',d.almacen_destino_codigo,
      'controla_lote',a.controla_lote,'controla_vencimiento',a.controla_vencimiento
    ) order by d.linea)
    from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d
    join public."ERP_ARTICULOS_APPGT" a on a.empresa_id=d.empresa_id and a.codigo=d.articulo_codigo
    where d.empresa_id=o.empresa_id and d.orden_numero=o.numero
      and d.cantidad_recibida<d.cantidad and not d.eliminado and d.deleted_at is null),'[]'::jsonb)
  ) order by o.fecha_emision,o.numero),'[]'::jsonb)
  from public."ERP_ORDENES_COMPRA_APPGT" o
  join public."ERP_PROVEEDORES_APPGT" p on p.empresa_id=o.empresa_id and p.codigo=o.proveedor_codigo
  where o.empresa_id=public.appgt_empresa_actual_id()
    and o.estado in ('APROBADO','RECIBIDO PARCIAL')
    and not o.eliminado and o.deleted_at is null
    and (auth.role()='service_role' or public.appgt_can_view_table('ERP_ORDENES_COMPRA_APPGT'))
$$;

-- ============================================================================
-- Ingresos SIN OC: pendientes hasta CONFIRMAR y sin efecto en stock previo.
-- ============================================================================

alter table public."ERP_INGRESOS_ALMACEN_APPGT"
  drop constraint if exists erp_ingreso_oc_fk,
  drop constraint if exists ERP_INGRESOS_ALMACEN_APPGT_orden_numero_fkey;
alter table public."ERP_INGRESOS_ALMACEN_APPGT"
  alter column proveedor_codigo drop not null,
  alter column confirmado_at drop not null;
alter table public."ERP_INGRESOS_ALMACEN_APPGT"
  drop constraint if exists "ERP_INGRESOS_ALMACEN_APPGT_estado_check",
  drop constraint if exists erp_ingreso_estado_ck;
alter table public."ERP_INGRESOS_ALMACEN_APPGT"
  alter column estado set default 'PENDIENTE';
alter table public."ERP_INGRESOS_ALMACEN_APPGT"
  add constraint erp_ingreso_estado_ck check (estado in ('PENDIENTE','CONFIRMADO','ANULADO'));

drop function if exists public.erp_registrar_ingreso_compra_v2(text,date,text,text,text,jsonb,text);
create function public.erp_registrar_ingreso_compra_v2(
  p_orden_numero text,p_fecha date,p_tipo_documento text,p_numero_documento text,
  p_almacen_codigo text,p_detalles jsonb,p_observacion text default null
)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_empresa uuid:=public.appgt_empresa_actual_id();
  v_order public."ERP_ORDENES_COMPRA_APPGT"%rowtype;
  v_detail jsonb; v_line public."ERP_ORDENES_COMPRA_DETALLE_APPGT"%rowtype;
  v_article public."ERP_ARTICULOS_APPGT"%rowtype;
  v_qty numeric(20,6); v_cost numeric(20,6); v_ingreso text;
  v_ingreso_line integer:=0; v_state text; v_new_state text;
  v_type text:=upper(btrim(coalesce(p_tipo_documento,'')));
  v_document text:=nullif(btrim(coalesce(p_numero_documento,'')),'');
  v_warehouse text:=nullif(btrim(coalesce(p_almacen_codigo,'')),'');
  v_without_order boolean:=upper(btrim(coalesce(p_orden_numero,'')))='SIN OC';
begin
  if v_empresa is null then raise exception 'No se pudo resolver la empresa activa' using errcode='42501'; end if;
  if auth.role()<>'service_role' and not public.appgt_can_insert_table('ERP_INGRESOS_ALMACEN_APPGT') then
    raise exception 'Sin permiso para registrar ingresos de almacén' using errcode='42501';
  end if;
  if v_type not in ('GUIA DE REMISION','FACTURA') then raise exception 'Seleccione un tipo de documento válido.'; end if;
  if v_document is null then raise exception 'Debe ingresar el número de documento.'; end if;
  if v_warehouse is null or not exists(select 1 from public."ERP_ALMACENES_APPGT" a
    where a.empresa_id=v_empresa and a.codigo=v_warehouse and a.estado='ACTIVO'
      and not a.eliminado and a.deleted_at is null) then raise exception 'Seleccione un almacén válido.'; end if;
  if jsonb_typeof(p_detalles)<>'array' or jsonb_array_length(p_detalles)=0 then
    raise exception 'Debe confirmar al menos un artículo o insumo recibido.';
  end if;

  if not v_without_order then
    select * into v_order from public."ERP_ORDENES_COMPRA_APPGT"
    where empresa_id=v_empresa and numero=p_orden_numero and not eliminado and deleted_at is null for update;
    if v_order.id is null then raise exception 'Orden de compra no encontrada.'; end if;
    if v_order.estado not in ('APROBADO','RECIBIDO PARCIAL') then
      raise exception 'Solo se reciben órdenes APROBADAS o RECIBIDAS PARCIALMENTE.';
    end if;
  end if;

  v_state:=case when v_without_order then 'PENDIENTE' else 'CONFIRMADO' end;
  insert into public."ERP_INGRESOS_ALMACEN_APPGT"(
    empresa_id,numero,fecha_ingreso,orden_numero,proveedor_codigo,proveedor_ruc,
    almacen_codigo,tipo_documento,guia_remision,estado,observacion,
    confirmado_por,confirmado_at
  ) values (
    v_empresa,null,coalesce(p_fecha,current_date),case when v_without_order then 'SIN OC' else v_order.numero end,
    case when v_without_order then null else v_order.proveedor_codigo end,
    case when v_without_order then null else v_order.proveedor_ruc end,
    v_warehouse,v_type,v_document,v_state,nullif(btrim(coalesce(p_observacion,'')),''),
    case when v_without_order then null else auth.uid() end,
    case when v_without_order then null else clock_timestamp() end
  ) returning numero into v_ingreso;

  for v_detail in select value from jsonb_array_elements(p_detalles) loop
    v_qty:=coalesce((v_detail->>'cantidad_recibida')::numeric,0);
    if v_qty<=0 then continue; end if;
    if v_without_order then
      select * into v_article from public."ERP_ARTICULOS_APPGT"
      where empresa_id=v_empresa and codigo=v_detail->>'articulo_codigo'
        and estado='ACTIVO' and not eliminado and deleted_at is null;
      if v_article.id is null then raise exception 'Artículo no encontrado: %.',v_detail->>'articulo_codigo'; end if;
      v_cost:=greatest(coalesce(nullif(v_detail->>'costo_unitario','')::numeric,v_article.costo_estandar,0),0);
      v_ingreso_line:=v_ingreso_line+1;
      insert into public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"(
        empresa_id,ingreso_numero,linea,orden_numero,orden_linea,articulo_codigo,
        descripcion,unidad_medida,cantidad_ordenada,cantidad_pendiente_antes,
        cantidad_recibida,costo_unitario,lote,fecha_vencimiento,almacen_codigo
      ) values (
        v_empresa,v_ingreso,v_ingreso_line,'SIN OC',v_ingreso_line,v_article.codigo,
        coalesce(nullif(btrim(v_detail->>'descripcion'),''),v_article.nombre),
        coalesce(nullif(btrim(v_detail->>'unidad_medida'),''),v_article.unidad_medida),
        v_qty,v_qty,v_qty,v_cost,nullif(btrim(coalesce(v_detail->>'lote','')),''),
        nullif(v_detail->>'fecha_vencimiento','')::date,v_warehouse
      );
    else
      select * into v_line from public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
      where empresa_id=v_empresa and orden_numero=v_order.numero
        and linea=(v_detail->>'linea')::integer and not eliminado and deleted_at is null for update;
      if v_line.id is null then raise exception 'La línea % no pertenece a la orden %.',v_detail->>'linea',v_order.numero; end if;
      if v_qty>v_line.cantidad-v_line.cantidad_recibida then
        raise exception 'La cantidad de % supera el saldo pendiente de %.',v_line.articulo_codigo,v_line.cantidad-v_line.cantidad_recibida;
      end if;
      v_ingreso_line:=v_ingreso_line+1;
      insert into public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"(
        empresa_id,ingreso_numero,linea,orden_numero,solicitud_numero,orden_linea,
        articulo_codigo,descripcion,unidad_medida,cantidad_ordenada,
        cantidad_pendiente_antes,cantidad_recibida,costo_unitario,lote,
        fecha_vencimiento,almacen_codigo
      ) values (
        v_empresa,v_ingreso,v_ingreso_line,v_order.numero,v_line.solicitud_numero,
        v_line.linea,v_line.articulo_codigo,v_line.descripcion,v_line.unidad_medida,
        v_line.cantidad,v_line.cantidad-v_line.cantidad_recibida,v_qty,
        v_line.precio_unitario,nullif(btrim(coalesce(v_detail->>'lote','')),''),
        nullif(v_detail->>'fecha_vencimiento','')::date,v_warehouse
      );
      insert into public."ERP_MOVIMIENTOS_INVENTARIO_APPGT"(
        empresa_id,numero,fecha,almacen_codigo,articulo_codigo,lote,
        fecha_vencimiento,tipo_movimiento,direccion,cantidad,costo_unitario,
        documento_origen_tipo,documento_origen_codigo,observacion,estado
      ) values (
        v_empresa,'ENT-'||v_ingreso||'-'||lpad(v_ingreso_line::text,3,'0'),
        clock_timestamp(),v_warehouse,v_line.articulo_codigo,
        nullif(btrim(coalesce(v_detail->>'lote','')),''),
        nullif(v_detail->>'fecha_vencimiento','')::date,'INGRESO_COMPRA',1,v_qty,
        v_line.precio_unitario,'INGRESO_COMPRA',v_ingreso,
        'OC '||v_order.numero||' / '||v_type||' '||v_document,'CONFIRMADO'
      );
      update public."ERP_ORDENES_COMPRA_DETALLE_APPGT" set
        cantidad_despachada=cantidad_despachada+v_qty,cantidad_recibida=cantidad_recibida+v_qty
      where id=v_line.id;
      perform public.appgt_erp_refrescar_trazabilidad_linea_v1(v_empresa,v_order.numero,v_line.linea);
    end if;
  end loop;
  if v_ingreso_line=0 then raise exception 'Todas las cantidades recibidas son cero.'; end if;
  if not v_without_order then
    perform public.appgt_erp_refrescar_solicitudes_orden_v1(v_empresa,v_order.numero);
    select estado into v_new_state from public."ERP_ORDENES_COMPRA_APPGT" where id=v_order.id;
    insert into public."ERP_EVENTOS_INTEGRACION_APPGT"(
      empresa_id,modulo_origen,documento_tipo,documento_numero,evento,modulos_destino,payload
    ) values (
      v_empresa,'ALMACEN','INGRESO_COMPRA',v_ingreso,'STOCK_ACTUALIZADO',array['COMPRAS','FINANZAS'],
      jsonb_build_object('orden_numero',v_order.numero,'tipo_documento',v_type,
        'numero_documento',v_document,'almacen_codigo',v_warehouse,'estado_orden',v_new_state)
    ) on conflict do nothing;
  end if;
  return jsonb_build_object('guardado',true,'ingreso_numero',v_ingreso,
    'orden_numero',case when v_without_order then 'SIN OC' else v_order.numero end,
    'estado_ingreso',v_state,'estado_orden',v_new_state,'lineas_recibidas',v_ingreso_line);
end $$;

create or replace function public.erp_confirmar_ingreso_almacen_v1(p_ingreso_numero text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_empresa uuid:=public.appgt_empresa_actual_id();
  v_header public."ERP_INGRESOS_ALMACEN_APPGT"%rowtype;
  v_detail record;
begin
  select * into v_header from public."ERP_INGRESOS_ALMACEN_APPGT"
  where empresa_id=v_empresa and numero=p_ingreso_numero for update;
  if v_header.id is null then raise exception 'Ingreso no encontrado.'; end if;
  if v_header.orden_numero<>'SIN OC' then raise exception 'Los ingresos con OC se confirman al guardarse.'; end if;
  if v_header.estado<>'PENDIENTE' then raise exception 'Solo se confirman ingresos PENDIENTES.'; end if;
  if auth.role()<>'service_role' and not public.appgt_puede_accion_estado_formato_v1(
    'ERP_INGRESOS_ALMACEN_APPGT','PENDIENTE','approve') then
    raise exception 'Sin permiso para confirmar ingresos.' using errcode='42501';
  end if;
  for v_detail in select * from public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"
    where empresa_id=v_empresa and ingreso_numero=v_header.numero
      and not eliminado and deleted_at is null order by linea
  loop
    insert into public."ERP_MOVIMIENTOS_INVENTARIO_APPGT"(
      empresa_id,numero,fecha,almacen_codigo,articulo_codigo,lote,
      fecha_vencimiento,tipo_movimiento,direccion,cantidad,costo_unitario,
      documento_origen_tipo,documento_origen_codigo,observacion,estado
    ) values (
      v_empresa,'ENT-'||v_header.numero||'-'||lpad(v_detail.linea::text,3,'0'),
      clock_timestamp(),v_header.almacen_codigo,v_detail.articulo_codigo,v_detail.lote,
      v_detail.fecha_vencimiento,'INGRESO_SIN_OC',1,v_detail.cantidad_recibida,
      v_detail.costo_unitario,'INGRESO_COMPRA',v_header.numero,
      'SIN OC / '||v_header.tipo_documento||' '||v_header.guia_remision,'CONFIRMADO'
    );
  end loop;
  update public."ERP_INGRESOS_ALMACEN_APPGT" set
    estado='CONFIRMADO',confirmado_por=auth.uid(),confirmado_at=clock_timestamp()
  where id=v_header.id;
  insert into public."ERP_EVENTOS_INTEGRACION_APPGT"(
    empresa_id,modulo_origen,documento_tipo,documento_numero,evento,modulos_destino,payload
  ) values (
    v_empresa,'ALMACEN','INGRESO_SIN_OC',v_header.numero,'STOCK_ACTUALIZADO',
    array['INVENTARIO','FINANZAS'],jsonb_build_object('orden_numero','SIN OC','almacen_codigo',v_header.almacen_codigo)
  ) on conflict do nothing;
  return jsonb_build_object('confirmado',true,'ingreso_numero',v_header.numero,'estado','CONFIRMADO');
end $$;

create or replace function public.erp_anular_ingreso_compra_v1(p_ingreso_numero text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_empresa uuid:=public.appgt_empresa_actual_id();
  v_header public."ERP_INGRESOS_ALMACEN_APPGT"%rowtype;
  v_row record;
begin
  select * into v_header from public."ERP_INGRESOS_ALMACEN_APPGT"
  where empresa_id=v_empresa and numero=p_ingreso_numero for update;
  if v_header.id is null then raise exception 'Ingreso no encontrado.'; end if;
  if v_header.estado='ANULADO' then raise exception 'El ingreso ya fue anulado.'; end if;
  if auth.role()<>'service_role' and not public.appgt_puede_accion_estado_formato_v1(
    'ERP_INGRESOS_ALMACEN_APPGT',v_header.estado,'delete') then
    raise exception 'Sin permiso para anular ingresos.' using errcode='42501';
  end if;
  perform set_config('appgt.erp_receipt_context','1',true);
  if v_header.estado='CONFIRMADO' then
    update public."ERP_MOVIMIENTOS_INVENTARIO_APPGT" set estado='ANULADO'
    where empresa_id=v_empresa and documento_origen_tipo='INGRESO_COMPRA'
      and documento_origen_codigo=v_header.numero and estado='CONFIRMADO';
    if v_header.orden_numero<>'SIN OC' then
      for v_row in select * from public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"
        where empresa_id=v_empresa and ingreso_numero=v_header.numero
          and not eliminado and deleted_at is null
      loop
        update public."ERP_ORDENES_COMPRA_DETALLE_APPGT" set
          cantidad_despachada=greatest(cantidad_despachada-v_row.cantidad_recibida,0),
          cantidad_recibida=greatest(cantidad_recibida-v_row.cantidad_recibida,0)
        where empresa_id=v_empresa and orden_numero=v_header.orden_numero and linea=v_row.orden_linea;
        perform public.appgt_erp_refrescar_trazabilidad_linea_v1(
          v_empresa,v_header.orden_numero,v_row.orden_linea
        );
      end loop;
      perform public.appgt_erp_refrescar_solicitudes_orden_v1(v_empresa,v_header.orden_numero);
    end if;
  end if;
  update public."ERP_INGRESOS_ALMACEN_APPGT" set
    estado='ANULADO',anulado_por=auth.uid(),anulado_at=clock_timestamp()
  where id=v_header.id;
  update public."ERP_EVENTOS_INTEGRACION_APPGT" set estado='ANULADO'
  where empresa_id=v_empresa and documento_tipo in ('INGRESO_COMPRA','INGRESO_SIN_OC')
    and documento_numero=v_header.numero;
  return jsonb_build_object('anulado',true,'ingreso_numero',v_header.numero);
end $$;

revoke all on function public.erp_registrar_ingreso_compra_v2(text,date,text,text,text,jsonb,text) from public,anon;
revoke all on function public.erp_confirmar_ingreso_almacen_v1(text) from public,anon;
revoke all on function public.erp_anular_ingreso_compra_v1(text) from public,anon;
grant execute on function public.erp_registrar_ingreso_compra_v2(text,date,text,text,text,jsonb,text) to authenticated,service_role;
grant execute on function public.erp_confirmar_ingreso_almacen_v1(text) to authenticated,service_role;
grant execute on function public.erp_anular_ingreso_compra_v1(text) to authenticated,service_role;

-- ============================================================================
-- Metadatos visibles de formatos y tablas.
-- ============================================================================

delete from public."MATRIZ_CAMPOS_FORMATO_APPGT"
where campo='estado_de_recibido' and tabla_destino in (
  'ERP_SOLICITUDES_COMPRA_APPGT','ERP_SOLICITUDES_COMPRA_DETALLE_APPGT',
  'ERP_ORDENES_COMPRA_APPGT','ERP_ORDENES_COMPRA_DETALLE_APPGT'
);

update public."MATRIZ_CAMPOS_FORMATO_APPGT" set
  etiqueta='Observación',updated_at=now()
where tabla_destino='ERP_SOLICITUDES_COMPRA_APPGT' and campo='justificacion';
update public."MATRIZ_CAMPOS_FORMATO_APPGT" set
  etiqueta='%IGV',visible=true,visible_tabla=true,updated_at=now()
where tabla_destino='ERP_ORDENES_COMPRA_DETALLE_APPGT' and campo='impuesto_porcentaje';
update public."MATRIZ_CAMPOS_FORMATO_APPGT" set orden=9,updated_at=now()
where tabla_destino='ERP_INGRESOS_ALMACEN_DETALLE_APPGT' and campo='cantidad_recibida';
update public."MATRIZ_CAMPOS_FORMATO_APPGT" set orden=10,updated_at=now()
where tabla_destino='ERP_INGRESOS_ALMACEN_DETALLE_APPGT' and campo='cantidad_pendiente';

with companies as (
  select distinct empresa_id from public."MATRIZ_FORMATOS_APPGT"
), fields(tabla,campo,etiqueta,tipo,tipo_ui,requerido,visible,visible_tabla,editable,orden) as (values
  ('ERP_ORDENES_COMPRA_APPGT','igv_porcentaje','%IGV','numeric','number',true,true,true,true,13),
  ('ERP_ORDENES_COMPRA_DETALLE_APPGT','importe','Importe','numeric','readonly',false,true,true,false,10),
  ('ERP_ORDENES_COMPRA_DETALLE_APPGT','descuento','Descuento','numeric','readonly',false,true,true,false,11),
  ('ERP_SOLICITUDES_COMPRA_DETALLE_APPGT','estado','Estado','text','readonly',false,true,true,false,15),
  ('ERP_ORDENES_COMPRA_DETALLE_APPGT','estado','Estado','text','readonly',false,true,true,false,16),
  ('ERP_VALES_DESPACHO_DETALLE_APPGT','estado','Estado','text','readonly',false,true,true,false,12)
)
insert into public."MATRIZ_CAMPOS_FORMATO_APPGT"(
  id,empresa_id,tabla_destino,campo,etiqueta,tipo,tipo_ui,requerido,visible,
  visible_tabla,editable,orden,activo,created_at,updated_at,estado_sync,eliminado
)
select 'erp_081_'||substr(md5(c.empresa_id::text||'|'||f.tabla||'|'||f.campo),1,24),
  c.empresa_id,f.tabla,f.campo,f.etiqueta,f.tipo,f.tipo_ui,f.requerido,
  f.visible,f.visible_tabla,f.editable,f.orden,true,now(),now(),'sincronizado',false
from companies c cross join fields f
on conflict (tabla_destino,campo) do update set
  etiqueta=excluded.etiqueta,tipo=excluded.tipo,tipo_ui=excluded.tipo_ui,
  requerido=excluded.requerido,visible=excluded.visible,visible_tabla=excluded.visible_tabla,
  editable=excluded.editable,orden=excluded.orden,activo=true,eliminado=false,updated_at=now();

alter table public."MATRIZ_FORMATOS_APPGT" disable trigger appgt_aplicar_capacidades_formato_trigger;
update public."MATRIZ_FORMATOS_APPGT" set
  flujo_estados='["PENDIENTE","REVISADO","APROBADO","RECIBIDO PARCIAL","RECIBIDO","ANULADO"]'::jsonb,
  updated_at=now()
where tabla_destino in ('ERP_SOLICITUDES_COMPRA_APPGT','ERP_ORDENES_COMPRA_APPGT');
update public."MATRIZ_FORMATOS_APPGT" set
  flujo_estados='["PENDIENTE","CONFIRMADO","ANULADO"]'::jsonb,
  workflow_enabled=true,approvals_enabled=true,
  capacidades=coalesce(capacidades,'{}'::jsonb)||
    '{"workflow":true,"approvals":true}'::jsonb,
  updated_at=now()
where tabla_destino='ERP_INGRESOS_ALMACEN_APPGT';
alter table public."MATRIZ_FORMATOS_APPGT" enable trigger appgt_aplicar_capacidades_formato_trigger;

-- Confirmar/anular debe respetar los mismos permisos que muestra la UI.
update public."PERMISOS_DE_USUARIOS_APPGT" p set
  permisos_estado=jsonb_build_object(
    'PENDIENTE',jsonb_build_object(
      'view',coalesce(p.can_view,false),
      'create',coalesce(p.can_insert,false),
      'update',coalesce(p.can_update,false) or coalesce(p.can_approve,false),
      'approve',coalesce(p.can_approve,false) or coalesce(p.can_update,false),
      'delete',coalesce(p.can_delete,false) or coalesce(p.can_update,false)
    ),
    'CONFIRMADO',jsonb_build_object(
      'view',coalesce(p.can_view,false),'create',false,'update',false,
      'approve',false,
      'delete',coalesce(p.can_delete,false) or coalesce(p.can_update,false)
    ),
    'ANULADO',jsonb_build_object(
      'view',coalesce(p.can_view,false),'create',false,'update',false,
      'approve',false,'delete',false
    )
  ),updated_at=now()
where p.tabla_destino='ERP_INGRESOS_ALMACEN_APPGT';

select set_config('appgt.erp_receipt_context','0',true);
notify pgrst, 'reload schema';
commit;
