begin;

-- ============================================================================
-- Compras y almacén: nombres funcionales, actores legibles, seguimiento de
-- recepción por documento/línea y formatos de detalle consultables.
-- ============================================================================

select set_config('appgt.erp_receipt_context','1',true);

alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  add column if not exists aprobado_por_nombre text,
  add column if not exists anulado_por_nombre text,
  add column if not exists fecha_aprobacion_oc date,
  add column if not exists orden_compra text,
  add column if not exists estado_de_recibido text not null default 'PENDIENTE';

alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  drop constraint if exists erp_solicitud_estado_recibido_ck;
alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  add constraint erp_solicitud_estado_recibido_ck check (
    estado_de_recibido in ('PENDIENTE','RECIBIDO PARCIAL','RECIBIDO')
  );

alter table public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"
  add column if not exists precio_unitario numeric(20,6) not null default 0,
  add column if not exists total numeric(20,6)
    generated always as (round(cantidad_solicitada*precio_unitario,6)) stored,
  add column if not exists estado_de_recibido text not null default 'PENDIENTE';

alter table public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"
  drop constraint if exists erp_solicitud_det_precio_ck,
  drop constraint if exists erp_solicitud_det_estado_recibido_ck;
alter table public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"
  add constraint erp_solicitud_det_precio_ck check (precio_unitario>=0),
  add constraint erp_solicitud_det_estado_recibido_ck check (
    estado_de_recibido in ('PENDIENTE','RECIBIDO PARCIAL','RECIBIDO')
  );

update public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" d
set precio_unitario=coalesce(a.costo_estandar,0)
from public."ERP_ARTICULOS_APPGT" a
where a.empresa_id=d.empresa_id and a.codigo=d.articulo_codigo
  and d.precio_unitario=0;

alter table public."ERP_ORDENES_COMPRA_APPGT"
  add column if not exists aprobado_por_nombre text,
  add column if not exists anulado_por_nombre text,
  add column if not exists fecha_solicitada_usuario timestamptz,
  add column if not exists fecha_recibida date,
  add column if not exists estado_de_recibido text not null default 'PENDIENTE',
  add column if not exists otros_descuentos numeric(20,6) not null default 0;

alter table public."ERP_ORDENES_COMPRA_APPGT"
  drop constraint if exists erp_oc_estado_recibido_ck,
  drop constraint if exists erp_oc_otros_descuentos_ck;
alter table public."ERP_ORDENES_COMPRA_APPGT"
  add constraint erp_oc_estado_recibido_ck check (
    estado_de_recibido in ('PENDIENTE','RECIBIDO PARCIAL','RECIBIDO')
  ),
  add constraint erp_oc_otros_descuentos_ck check (otros_descuentos>=0);

update public."ERP_ORDENES_COMPRA_APPGT"
set otros_descuentos=greatest(coalesce(descuento,0),0)
where otros_descuentos=0 and coalesce(descuento,0)>0;

alter table public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  add column if not exists estado_de_recibido text not null default 'PENDIENTE';
alter table public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  drop constraint if exists erp_oc_det_estado_recibido_ck;
alter table public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  add constraint erp_oc_det_estado_recibido_ck check (
    estado_de_recibido in ('PENDIENTE','RECIBIDO PARCIAL','RECIBIDO')
  );

alter table public."ERP_INGRESOS_ALMACEN_APPGT"
  add column if not exists usuario text;

-- --------------------------------------------------------------------------
-- Identidad del usuario y nombres legibles de aprobación/anulación.
-- --------------------------------------------------------------------------

create or replace function public.appgt_erp_identidad_ingreso_v1()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_identidad jsonb;
begin
  if tg_op='UPDATE' then
    new.usuario:=old.usuario;
    return new;
  end if;
  if auth.uid() is null then return new; end if;
  v_identidad:=public.erp_identidad_usuario_actual_v1();
  if v_identidad='{}'::jsonb then
    raise exception 'El usuario activo no tiene un perfil válido en la empresa.'
      using errcode='42501';
  end if;
  new.usuario:=v_identidad->>'solicitante';
  return new;
end
$$;

drop trigger if exists erp_identidad_ingreso on public."ERP_INGRESOS_ALMACEN_APPGT";
create trigger erp_identidad_ingreso
before insert or update on public."ERP_INGRESOS_ALMACEN_APPGT"
for each row execute function public.appgt_erp_identidad_ingreso_v1();

update public."ERP_INGRESOS_ALMACEN_APPGT" i
set usuario=concat_ws('-',
  nullif(btrim(coalesce(p."DNI",'')),''),
  nullif(btrim(coalesce(nullif(p.first_nombres,''),p.nombres,'')),''),
  nullif(btrim(coalesce(p.apellido_paterno,'')),'')
)
from public."PERFILES_DE_USUARIOS_APPGT" p
where p.id=i.confirmado_por and p.empresa_id=i.empresa_id
  and nullif(btrim(coalesce(i.usuario,'')),'') is null;

create or replace function public.appgt_erp_actor_nombre_v1()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_identidad jsonb; v_nombre text;
begin
  if new.estado is not distinct from old.estado then return new; end if;
  v_identidad:=public.erp_identidad_usuario_actual_v1();
  v_nombre:=concat_ws('-',
    nullif(v_identidad->>'dni',''),nullif(v_identidad->>'first_nombres','')
  );
  if new.estado='APROBADO' then new.aprobado_por_nombre:=nullif(v_nombre,''); end if;
  if new.estado='ANULADO' then new.anulado_por_nombre:=nullif(v_nombre,''); end if;
  return new;
end
$$;

drop trigger if exists zzz_erp_actor_nombre on public."ERP_SOLICITUDES_COMPRA_APPGT";
create trigger zzz_erp_actor_nombre
before update of estado on public."ERP_SOLICITUDES_COMPRA_APPGT"
for each row execute function public.appgt_erp_actor_nombre_v1();

drop trigger if exists zzz_erp_actor_nombre on public."ERP_ORDENES_COMPRA_APPGT";
create trigger zzz_erp_actor_nombre
before update of estado on public."ERP_ORDENES_COMPRA_APPGT"
for each row execute function public.appgt_erp_actor_nombre_v1();

update public."ERP_SOLICITUDES_COMPRA_APPGT" s
set aprobado_por_nombre=concat_ws('-',nullif(p."DNI",''),
      nullif(coalesce(nullif(p.first_nombres,''),p.nombres),''))
from public."PERFILES_DE_USUARIOS_APPGT" p
where p.id=s.aprobado_por and p.empresa_id=s.empresa_id
  and nullif(s.aprobado_por_nombre,'') is null;
update public."ERP_SOLICITUDES_COMPRA_APPGT" s
set anulado_por_nombre=concat_ws('-',nullif(p."DNI",''),
      nullif(coalesce(nullif(p.first_nombres,''),p.nombres),''))
from public."PERFILES_DE_USUARIOS_APPGT" p
where p.id=s.anulado_por and p.empresa_id=s.empresa_id
  and nullif(s.anulado_por_nombre,'') is null;
update public."ERP_ORDENES_COMPRA_APPGT" o
set aprobado_por_nombre=concat_ws('-',nullif(p."DNI",''),
      nullif(coalesce(nullif(p.first_nombres,''),p.nombres),''))
from public."PERFILES_DE_USUARIOS_APPGT" p
where p.id=o.aprobado_por and p.empresa_id=o.empresa_id
  and nullif(o.aprobado_por_nombre,'') is null;
update public."ERP_ORDENES_COMPRA_APPGT" o
set anulado_por_nombre=concat_ws('-',nullif(p."DNI",''),
      nullif(coalesce(nullif(p.first_nombres,''),p.nombres),''))
from public."PERFILES_DE_USUARIOS_APPGT" p
where p.id=o.anulado_por and p.empresa_id=o.empresa_id
  and nullif(o.anulado_por_nombre,'') is null;

-- Conserva por separado el valor ingresado en "Otros Dctos.".
create or replace function public.appgt_erp_otros_descuentos_v1()
returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
  if tg_op='INSERT' then
    new.otros_descuentos:=greatest(coalesce(new.otros_descuentos,new.descuento,0),0);
  elsif new.descuento is distinct from old.descuento
    and new.otros_descuentos is not distinct from old.otros_descuentos then
    new.otros_descuentos:=greatest(coalesce(new.descuento,0),0);
  end if;
  return new;
end $$;

drop trigger if exists erp_otros_descuentos on public."ERP_ORDENES_COMPRA_APPGT";
create trigger erp_otros_descuentos
before insert or update on public."ERP_ORDENES_COMPRA_APPGT"
for each row execute function public.appgt_erp_otros_descuentos_v1();

-- --------------------------------------------------------------------------
-- Solicitud: sin centro de costo operativo, con precio/total por artículo.
-- Se conserva el parámetro antiguo para compatibilidad con clientes previos.
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
  v_item jsonb; v_article public."ERP_ARTICULOS_APPGT"%rowtype;
  v_line integer:=0; v_qty numeric(20,6); v_price numeric(20,6);
  v_amount numeric(20,6):=0; v_need date:=coalesce(p_fecha_necesidad,current_date);
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
      coalesce(nullif(btrim(coalesce(p_area,'')),''),v_identidad->>'area'),null,
      nullif(btrim(coalesce(p_justificacion,'')),''),0,'PEN','PENDIENTE'
    ) returning numero into v_numero;
  else
    if v_existing.estado not in ('PENDIENTE','REVISADO') then
      raise exception 'Una solicitud % no se puede editar.',v_existing.estado;
    end if;
    update public."ERP_SOLICITUDES_COMPRA_APPGT" set
      fecha=coalesce(p_fecha,current_date),fecha_necesidad=v_need,
      area=coalesce(nullif(btrim(coalesce(p_area,'')),''),area),centro_costo=null,
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
    v_price:=greatest(coalesce(nullif(v_item->>'precio_unitario','')::numeric,
      v_article.costo_estandar,0),0);
    v_line:=v_line+1; v_amount:=v_amount+round(v_qty*v_price,6);
    insert into public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"(
      empresa_id,solicitud_numero,linea,articulo_codigo,descripcion,
      cantidad_solicitada,unidad_medida,precio_unitario,fecha_necesidad,
      proveedor_recomendado_codigo,almacen_destino_codigo,observacion
    ) values (
      v_empresa,v_numero,v_line,v_article.codigo,v_article.nombre,v_qty,
      v_article.unidad_medida,v_price,
      coalesce((v_item->>'fecha_necesidad')::date,v_need),
      nullif(btrim(coalesce(v_item->>'proveedor_recomendado_codigo','')),''),
      btrim(v_item->>'almacen_destino_codigo'),
      nullif(btrim(coalesce(v_item->>'observacion','')),'')
    );
  end loop;
  update public."ERP_SOLICITUDES_COMPRA_APPGT" set monto_estimado=v_amount
  where empresa_id=v_empresa and numero=v_numero;
  return jsonb_build_object('numero',v_numero,'codigo',v_numero,'estado','PENDIENTE',
    'lineas',v_line,'monto_estimado',v_amount);
end
$$;

-- La fecha solicitada del usuario es la aprobación de la(s) SP asociada(s).
create or replace function public.appgt_erp_fecha_solicitada_oc_v1()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_empresa uuid;
  v_orden text;
begin
  if tg_op='DELETE' then
    v_empresa:=old.empresa_id;
    v_orden:=old.orden_numero;
  else
    v_empresa:=new.empresa_id;
    v_orden:=new.orden_numero;
  end if;
  perform set_config('appgt.erp_receipt_context','1',true);
  update public."ERP_ORDENES_COMPRA_APPGT" o
  set fecha_solicitada_usuario=(
    select min(s.aprobado_at)
    from public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT" os
    join public."ERP_SOLICITUDES_COMPRA_APPGT" s
      on s.empresa_id=os.empresa_id and s.numero=os.solicitud_numero
    where os.empresa_id=v_empresa and os.orden_numero=v_orden
      and not os.eliminado and os.deleted_at is null
  ) where o.empresa_id=v_empresa and o.numero=v_orden;
  if tg_op='DELETE' then
    return old;
  end if;
  return new;
end $$;

drop trigger if exists erp_fecha_solicitada_oc on public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT";
create trigger erp_fecha_solicitada_oc
after insert or update or delete on public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT"
for each row execute function public.appgt_erp_fecha_solicitada_oc_v1();

-- --------------------------------------------------------------------------
-- Trazabilidad de recepción por línea y por cabecera.
-- --------------------------------------------------------------------------

create or replace function public.appgt_erp_refrescar_cabeceras_v2(
  p_empresa uuid,p_orden text,p_solicitud text
)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  perform set_config('appgt.erp_receipt_context','1',true);
  if p_orden is not null then
    update public."ERP_ORDENES_COMPRA_APPGT" o set
      fecha_recibida=(select max(i.fecha_ingreso)
        from public."ERP_INGRESOS_ALMACEN_APPGT" i
        where i.empresa_id=o.empresa_id and i.orden_numero=o.numero
          and i.estado='CONFIRMADO' and not i.eliminado and i.deleted_at is null),
      estado_de_recibido=coalesce((select case
        when coalesce(sum(d.cantidad_recibida),0)=0 then 'PENDIENTE'
        when bool_and(d.cantidad_recibida>=d.cantidad) then 'RECIBIDO'
        else 'RECIBIDO PARCIAL' end
        from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d
        where d.empresa_id=o.empresa_id and d.orden_numero=o.numero
          and not d.eliminado and d.deleted_at is null),'PENDIENTE')
    where o.empresa_id=p_empresa and o.numero=p_orden;
  end if;
  if p_solicitud is not null then
    update public."ERP_SOLICITUDES_COMPRA_APPGT" s set
      fecha_aprobacion_oc=(select min(o.aprobado_at::date)
        from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
        join public."ERP_ORDENES_COMPRA_APPGT" o
          on o.empresa_id=od.empresa_id and o.numero=od.orden_numero
        where od.empresa_id=s.empresa_id and od.solicitud_numero=s.numero
          and o.estado in ('APROBADO','DESPACHADO PARCIALMENTE','DESPACHADO')
          and not od.eliminado and od.deleted_at is null),
      orden_compra=(select string_agg(distinct o.numero,', ' order by o.numero)
        from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
        join public."ERP_ORDENES_COMPRA_APPGT" o
          on o.empresa_id=od.empresa_id and o.numero=od.orden_numero
        where od.empresa_id=s.empresa_id and od.solicitud_numero=s.numero
          and o.estado in ('APROBADO','DESPACHADO PARCIALMENTE','DESPACHADO')
          and not od.eliminado and od.deleted_at is null),
      estado_de_recibido=coalesce((select case
        when coalesce(sum(sd.cantidad_recibida),0)=0 then 'PENDIENTE'
        when bool_and(sd.estado_de_recibido='RECIBIDO') then 'RECIBIDO'
        else 'RECIBIDO PARCIAL' end
        from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" sd
        where sd.empresa_id=s.empresa_id and sd.solicitud_numero=s.numero
          and not sd.eliminado and sd.deleted_at is null),'PENDIENTE')
    where s.empresa_id=p_empresa and s.numero=p_solicitud;
  end if;
end $$;

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
  perform set_config('appgt.erp_receipt_context','1',true);
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
  update public."ERP_ORDENES_COMPRA_DETALLE_APPGT" set
    fecha_recibida=v_fecha,
    estado_de_recibido=case when cantidad_recibida<=0 then 'PENDIENTE'
      when cantidad_recibida>=cantidad then 'RECIBIDO' else 'RECIBIDO PARCIAL' end
  where id=v_line.id;
  if v_line.solicitud_numero is not null and v_line.solicitud_linea is not null then
    update public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" sd set
      cantidad_recibida=least(sd.cantidad_solicitada,coalesce((
        select sum(od.cantidad_recibida)
        from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
        join public."ERP_ORDENES_COMPRA_APPGT" o
          on o.empresa_id=od.empresa_id and o.numero=od.orden_numero
        where od.empresa_id=sd.empresa_id and od.solicitud_numero=sd.solicitud_numero
          and od.solicitud_linea=sd.linea and o.estado<>'ANULADO'
          and not od.eliminado and od.deleted_at is null),0)),
      fecha_oc_aprobada=(select min(o.aprobado_at::date)
        from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
        join public."ERP_ORDENES_COMPRA_APPGT" o
          on o.empresa_id=od.empresa_id and o.numero=od.orden_numero
        where od.empresa_id=sd.empresa_id and od.solicitud_numero=sd.solicitud_numero
          and od.solicitud_linea=sd.linea
          and o.estado in ('APROBADO','DESPACHADO PARCIALMENTE','DESPACHADO')
          and not od.eliminado and od.deleted_at is null),
      fecha_recibida=(select max(i.fecha_ingreso)
        from public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT" rd
        join public."ERP_INGRESOS_ALMACEN_APPGT" i
          on i.empresa_id=rd.empresa_id and i.numero=rd.ingreso_numero
        join public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
          on od.empresa_id=rd.empresa_id and od.orden_numero=rd.orden_numero
         and od.linea=rd.orden_linea
        where rd.empresa_id=sd.empresa_id and rd.solicitud_numero=sd.solicitud_numero
          and od.solicitud_linea=sd.linea and i.estado='CONFIRMADO'
          and not i.eliminado and i.deleted_at is null
          and not rd.eliminado and rd.deleted_at is null),
      estado_de_recibido=case
        when least(sd.cantidad_solicitada,coalesce((select sum(od.cantidad_recibida)
          from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
          join public."ERP_ORDENES_COMPRA_APPGT" o
            on o.empresa_id=od.empresa_id and o.numero=od.orden_numero
          where od.empresa_id=sd.empresa_id and od.solicitud_numero=sd.solicitud_numero
            and od.solicitud_linea=sd.linea and o.estado<>'ANULADO'
            and not od.eliminado and od.deleted_at is null),0))<=0 then 'PENDIENTE'
        when least(sd.cantidad_solicitada,coalesce((select sum(od.cantidad_recibida)
          from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
          join public."ERP_ORDENES_COMPRA_APPGT" o
            on o.empresa_id=od.empresa_id and o.numero=od.orden_numero
          where od.empresa_id=sd.empresa_id and od.solicitud_numero=sd.solicitud_numero
            and od.solicitud_linea=sd.linea and o.estado<>'ANULADO'
            and not od.eliminado and od.deleted_at is null),0))>=sd.cantidad_solicitada
          then 'RECIBIDO' else 'RECIBIDO PARCIAL' end
    where sd.empresa_id=v_line.empresa_id and sd.solicitud_numero=v_line.solicitud_numero
      and sd.linea=v_line.solicitud_linea;
  end if;
  perform public.appgt_erp_refrescar_cabeceras_v2(
    v_line.empresa_id,v_line.orden_numero,v_line.solicitud_numero
  );
end
$$;

create or replace function public.appgt_erp_trazabilidad_aprobacion_oc_v1()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_item record;
begin
  if new.estado is distinct from old.estado then
    perform set_config('appgt.erp_receipt_context','1',true);
    if new.estado='APROBADO' then
      update public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
      set fecha_oc_aprobada=coalesce(new.aprobado_at::date,current_date)
      where empresa_id=new.empresa_id and orden_numero=new.numero
        and not eliminado and deleted_at is null;
    end if;
    for v_item in select linea from public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
      where empresa_id=new.empresa_id and orden_numero=new.numero
        and not eliminado and deleted_at is null
    loop
      perform public.appgt_erp_refrescar_trazabilidad_linea_v1(
        new.empresa_id,new.numero,v_item.linea
      );
    end loop;
  end if;
  return new;
end $$;

-- Backfill seguro de todas las líneas existentes.
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

update public."ERP_ORDENES_COMPRA_APPGT" o
set fecha_solicitada_usuario=(select min(s.aprobado_at)
  from public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT" os
  join public."ERP_SOLICITUDES_COMPRA_APPGT" s
    on s.empresa_id=os.empresa_id and s.numero=os.solicitud_numero
  where os.empresa_id=o.empresa_id and os.orden_numero=o.numero
    and not os.eliminado and os.deleted_at is null);

-- --------------------------------------------------------------------------
-- Nombres y campos visibles de los formatos.
-- --------------------------------------------------------------------------

update public."MATRIZ_FORMATOS_APPGT" set
  nombre='Ingresos en Almacén',updated_at=now()
where tabla_destino='ERP_INGRESOS_ALMACEN_APPGT';
update public."MATRIZ_FORMATO_TABLAS_APPGT" set
  nombre='Ingresos en Almacén',updated_at=now()
where tabla_destino='ERP_INGRESOS_ALMACEN_APPGT' and not coalesce(es_detalle,false);
update public."MATRIZ_FORMATO_TABLAS_APPGT" set
  nombre='Detalle de Ingresos en Almacén',updated_at=now()
where tabla_destino='ERP_INGRESOS_ALMACEN_DETALLE_APPGT';
update public."MATRIZ_FORMATO_TABLAS_APPGT" set
  nombre='Detalle de Vales de Despacho',updated_at=now()
where tabla_destino='ERP_VALES_DESPACHO_DETALLE_APPGT';

with parents as (
  select empresa_id,modulo_id,rubro_id
  from public."MATRIZ_FORMATOS_APPGT"
  where tabla_destino='ERP_INGRESOS_ALMACEN_APPGT'
    and activo and not eliminado and deleted_at is null
)
insert into public."MATRIZ_FORMATOS_APPGT"(
  id,empresa_id,modulo_id,nombre,tabla_destino,tabla_visible_app,orden,activo,
  rubro_id,auditable,workflow_enabled,approvals_enabled,flujo_estados,
  capacidades,icono,created_at,updated_at,estado_sync,eliminado
)
select 'erp_ingresos_almacen_detalle_'||substr(md5(empresa_id::text),1,10),
  empresa_id,modulo_id,'Detalle de Ingresos en Almacén',
  'ERP_INGRESOS_ALMACEN_DETALLE_APPGT',true,46,true,rubro_id,true,false,false,
  '[]'::jsonb,'{}'::jsonb,'list_alt_outlined',now(),now(),'sincronizado',false
from parents
on conflict (id) do update set nombre=excluded.nombre,tabla_visible_app=true,
  activo=true,eliminado=false,deleted_at=null,updated_at=now();

with parents as (
  select empresa_id,modulo_id,rubro_id
  from public."MATRIZ_FORMATOS_APPGT"
  where tabla_destino='ERP_VALES_DESPACHO_APPGT'
    and activo and not eliminado and deleted_at is null
)
insert into public."MATRIZ_FORMATOS_APPGT"(
  id,empresa_id,modulo_id,nombre,tabla_destino,tabla_visible_app,orden,activo,
  rubro_id,auditable,workflow_enabled,approvals_enabled,flujo_estados,
  capacidades,icono,created_at,updated_at,estado_sync,eliminado
)
select 'erp_vales_despacho_detalle_'||substr(md5(empresa_id::text),1,10),
  empresa_id,modulo_id,'Detalle de Vales de Despacho',
  'ERP_VALES_DESPACHO_DETALLE_APPGT',true,51,true,rubro_id,true,false,false,
  '[]'::jsonb,'{}'::jsonb,'list_alt_outlined',now(),now(),'sincronizado',false
from parents
on conflict (id) do update set nombre=excluded.nombre,tabla_visible_app=true,
  activo=true,eliminado=false,deleted_at=null,updated_at=now();

insert into public."MATRIZ_FORMATO_TABLAS_APPGT"(
  id,empresa_id,formato_id,nombre,tabla_destino,orden,activo,rubro_id,
  auditable,created_at,updated_at,estado_sync,eliminado
)
select 'erp_ingresos_almacen_detalle_main_'||substr(md5(f.empresa_id::text),1,10),
  f.empresa_id,f.id,f.nombre,f.tabla_destino,0,true,f.rubro_id,true,
  now(),now(),'sincronizado',false
from public."MATRIZ_FORMATOS_APPGT" f
where f.tabla_destino='ERP_INGRESOS_ALMACEN_DETALLE_APPGT'
on conflict (id) do update set nombre=excluded.nombre,activo=true,
  eliminado=false,deleted_at=null,updated_at=now();

insert into public."MATRIZ_FORMATO_TABLAS_APPGT"(
  id,empresa_id,formato_id,nombre,tabla_destino,orden,activo,rubro_id,
  auditable,created_at,updated_at,estado_sync,eliminado
)
select 'erp_vales_despacho_detalle_main_'||substr(md5(f.empresa_id::text),1,10),
  f.empresa_id,f.id,f.nombre,f.tabla_destino,0,true,f.rubro_id,true,
  now(),now(),'sincronizado',false
from public."MATRIZ_FORMATOS_APPGT" f
where f.tabla_destino='ERP_VALES_DESPACHO_DETALLE_APPGT'
on conflict (id) do update set nombre=excluded.nombre,activo=true,
  eliminado=false,deleted_at=null,updated_at=now();

with mappings(parent_table,detail_table) as (values
  ('ERP_INGRESOS_ALMACEN_APPGT','ERP_INGRESOS_ALMACEN_DETALLE_APPGT'),
  ('ERP_VALES_DESPACHO_APPGT','ERP_VALES_DESPACHO_DETALLE_APPGT')
), resolved as (
  select p.*,df.id detail_format,df.modulo_id detail_module,
    m.seccion detail_section,df.tabla_destino detail_table
  from mappings x
  join public."MATRIZ_FORMATOS_APPGT" pf on pf.tabla_destino=x.parent_table
  join public."MATRIZ_FORMATOS_APPGT" df
    on df.empresa_id=pf.empresa_id and df.tabla_destino=x.detail_table
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id=df.empresa_id and m.id=df.modulo_id
  join public."PERMISOS_DE_USUARIOS_APPGT" p
    on p.empresa_id=pf.empresa_id and p.formato=pf.id
  where coalesce(p.activo,true) and not coalesce(p.eliminado,false)
    and p.deleted_at is null
)
insert into public."PERMISOS_DE_USUARIOS_APPGT"(
  empresa_id,user_id,seccion,modulo,formato,tabla_destino,
  can_view,can_insert,can_update,can_delete,can_export,can_import,
  can_review,can_approve,activo,created_at,updated_at,estado_sync,eliminado
)
select empresa_id,user_id,detail_section,detail_module,detail_format,detail_table,
  can_view,false,false,false,can_export,false,false,false,true,now(),now(),
  'sincronizado',false
from resolved
on conflict (user_id,modulo,formato) do update set
  tabla_destino=excluded.tabla_destino,can_view=excluded.can_view,
  can_insert=false,can_update=false,can_delete=false,can_export=excluded.can_export,
  activo=true,eliminado=false,deleted_at=null,updated_at=now();

with companies as (
  select distinct empresa_id from public."MATRIZ_FORMATOS_APPGT"
), fields(tabla,campo,etiqueta,tipo,tipo_ui,requerido,visible,visible_tabla,editable,orden) as (values
  ('ERP_SOLICITUDES_COMPRA_APPGT','estado','Estado aprobación','text','readonly',false,true,true,false,10),
  ('ERP_SOLICITUDES_COMPRA_APPGT','aprobado_por_nombre','Aprobado por','text','readonly',false,false,true,false,11),
  ('ERP_SOLICITUDES_COMPRA_APPGT','aprobado_at','Fecha y hora de aprobación','timestamptz','datetime',false,false,true,false,12),
  ('ERP_SOLICITUDES_COMPRA_APPGT','anulado_por_nombre','Anulado por','text','readonly',false,false,true,false,13),
  ('ERP_SOLICITUDES_COMPRA_APPGT','anulado_at','Fecha y hora de anulación','timestamptz','datetime',false,false,true,false,14),
  ('ERP_SOLICITUDES_COMPRA_APPGT','fecha_aprobacion_oc','Fecha aprobación OC','date','readonly',false,false,true,false,15),
  ('ERP_SOLICITUDES_COMPRA_APPGT','orden_compra','Orden de compra','text','readonly',false,false,true,false,16),
  ('ERP_SOLICITUDES_COMPRA_APPGT','estado_de_recibido','Estado de recibido','text','readonly',false,false,true,false,17),
  ('ERP_SOLICITUDES_COMPRA_DETALLE_APPGT','precio_unitario','Precio unitario','numeric','number',false,true,true,true,8),
  ('ERP_SOLICITUDES_COMPRA_DETALLE_APPGT','total','Total','numeric','readonly',false,true,true,false,9),
  ('ERP_SOLICITUDES_COMPRA_DETALLE_APPGT','estado_de_recibido','Estado de recibido','text','readonly',false,false,true,false,14),
  ('ERP_ORDENES_COMPRA_APPGT','fecha_emision','Fecha emisión OC','date','date',true,true,true,true,4),
  ('ERP_ORDENES_COMPRA_APPGT','fecha_solicitada_usuario','Fecha aprobación solicitud','timestamptz','datetime',false,false,true,false,5),
  ('ERP_ORDENES_COMPRA_APPGT','fecha_entrega','Fecha entrega programada','date','date',false,true,true,true,6),
  ('ERP_ORDENES_COMPRA_APPGT','fecha_recibida','Fecha recibida','date','readonly',false,false,true,false,14),
  ('ERP_ORDENES_COMPRA_APPGT','estado_de_recibido','Estado de recibido','text','readonly',false,false,true,false,15),
  ('ERP_ORDENES_COMPRA_APPGT','aprobado_por_nombre','Aprobado por','text','readonly',false,false,true,false,16),
  ('ERP_ORDENES_COMPRA_APPGT','anulado_por_nombre','Anulado por','text','readonly',false,false,true,false,17),
  ('ERP_ORDENES_COMPRA_APPGT','otros_descuentos','Otros Dctos.','numeric','number',false,true,true,true,18),
  ('ERP_ORDENES_COMPRA_DETALLE_APPGT','estado_de_recibido','Estado de recibido','text','readonly',false,false,true,false,14),
  ('ERP_INGRESOS_ALMACEN_APPGT','usuario','Usuario','text','readonly',false,true,true,false,2)
)
insert into public."MATRIZ_CAMPOS_FORMATO_APPGT"(
  id,empresa_id,tabla_destino,campo,etiqueta,tipo,tipo_ui,requerido,visible,
  visible_tabla,editable,orden,activo,created_at,updated_at,estado_sync,eliminado
)
select 'erp_receipt_'||substr(md5(c.empresa_id::text||'|'||f.tabla||'|'||f.campo),1,24),
  c.empresa_id,f.tabla,f.campo,f.etiqueta,f.tipo,f.tipo_ui,f.requerido,
  f.visible,f.visible_tabla,f.editable,f.orden,true,now(),now(),'sincronizado',false
from companies c cross join fields f
on conflict (tabla_destino,campo) do update set
  etiqueta=excluded.etiqueta,tipo=excluded.tipo,tipo_ui=excluded.tipo_ui,
  requerido=excluded.requerido,visible=excluded.visible,
  visible_tabla=excluded.visible_tabla,editable=excluded.editable,
  orden=excluded.orden,activo=true,eliminado=false,updated_at=now();

update public."MATRIZ_CAMPOS_FORMATO_APPGT" set
  visible=false,visible_tabla=false,editable=false,activo=false,updated_at=now()
where tabla_destino in ('ERP_SOLICITUDES_COMPRA_APPGT','ERP_ORDENES_COMPRA_APPGT')
  and lower(campo) in (
    'centro_costo','revisado_por','revisado_at','estado_aprobacion',
    'despachado_por','despachado_pro','despachado_at','fecha_despachada',
    'aprobado_por','anulado_por'
  );

revoke all on function public.appgt_erp_refrescar_cabeceras_v2(uuid,text,text) from public,anon;
revoke all on function public.appgt_erp_refrescar_trazabilidad_linea_v1(uuid,text,integer) from public,anon;
grant execute on function public.erp_guardar_solicitud_pedido_v1(text,date,date,text,text,text,text,jsonb) to authenticated,service_role;

select set_config('appgt.erp_receipt_context','0',true);
notify pgrst, 'reload schema';
commit;
