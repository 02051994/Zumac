begin;

-- ============================================================================
-- Solicitudes: proveedor/almacén de cabecera y foto opcional por artículo.
-- ============================================================================

alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  add column if not exists proveedor_codigo text,
  add column if not exists almacen_codigo text;

update public."ERP_SOLICITUDES_COMPRA_APPGT" s
set proveedor_codigo=coalesce(s.proveedor_codigo,(
      select d.proveedor_recomendado_codigo
      from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" d
      where d.empresa_id=s.empresa_id and d.solicitud_numero=s.numero
        and not d.eliminado and d.deleted_at is null
      order by d.linea limit 1)),
    almacen_codigo=coalesce(s.almacen_codigo,(
      select d.almacen_destino_codigo
      from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" d
      where d.empresa_id=s.empresa_id and d.solicitud_numero=s.numero
        and not d.eliminado and d.deleted_at is null
      order by d.linea limit 1))
where s.proveedor_codigo is null or s.almacen_codigo is null;

alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  drop constraint if exists erp_solicitud_proveedor_fk,
  drop constraint if exists erp_solicitud_almacen_fk;
alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  add constraint erp_solicitud_proveedor_fk foreign key (empresa_id,proveedor_codigo)
    references public."ERP_PROVEEDORES_APPGT"(empresa_id,codigo),
  add constraint erp_solicitud_almacen_fk foreign key (empresa_id,almacen_codigo)
    references public."ERP_ALMACENES_APPGT"(empresa_id,codigo);

alter table public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"
  add column if not exists foto_url text;

create or replace function public.erp_identidad_usuario_actual_v1()
returns jsonb
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select coalesce((
    select jsonb_build_object(
      'empresa_id',p.empresa_id,
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

create or replace function public.erp_guardar_solicitud_pedido_v2(
  p_numero text,p_fecha date,p_fecha_necesidad date,p_solicitante text,
  p_area text,p_centro_costo text,p_justificacion text,
  p_proveedor_codigo text,p_almacen_codigo text,p_detalles jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa uuid:=public.appgt_empresa_actual_id();
  v_numero text:=nullif(btrim(coalesce(p_numero,'')),'');
  v_provider text:=nullif(btrim(coalesce(p_proveedor_codigo,'')),'');
  v_warehouse text:=nullif(btrim(coalesce(p_almacen_codigo,'')),'');
  v_existing public."ERP_SOLICITUDES_COMPRA_APPGT"%rowtype;
  v_identidad jsonb:=public.erp_identidad_usuario_actual_v1();
  v_item jsonb; v_article public."ERP_ARTICULOS_APPGT"%rowtype;
  v_line integer:=0; v_qty numeric(20,6); v_price numeric(20,6);
  v_amount numeric(20,6):=0; v_need date:=coalesce(p_fecha_necesidad,current_date);
  v_photo text;
begin
  if v_empresa is null then raise exception 'No se pudo resolver la empresa activa' using errcode='42501'; end if;
  if v_identidad='{}'::jsonb then raise exception 'El usuario activo no tiene perfil válido.' using errcode='42501'; end if;
  if v_provider is null then raise exception 'Seleccione un proveedor.'; end if;
  if v_warehouse is null then raise exception 'Seleccione un almacén.'; end if;
  if not exists(select 1 from public."ERP_PROVEEDORES_APPGT" p
    where p.empresa_id=v_empresa and p.codigo=v_provider and p.estado='ACTIVO'
      and not p.eliminado and p.deleted_at is null) then
    raise exception 'El proveedor seleccionado no está disponible.';
  end if;
  if not exists(select 1 from public."ERP_ALMACENES_APPGT" a
    where a.empresa_id=v_empresa and a.codigo=v_warehouse and a.estado='ACTIVO'
      and not a.eliminado and a.deleted_at is null) then
    raise exception 'El almacén seleccionado no está disponible.';
  end if;
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
      justificacion,monto_estimado,moneda,estado,proveedor_codigo,almacen_codigo
    ) values (
      v_empresa,null,coalesce(p_fecha,current_date),v_need,v_identidad->>'solicitante',
      coalesce(nullif(btrim(coalesce(p_area,'')),''),v_identidad->>'area'),null,
      nullif(btrim(coalesce(p_justificacion,'')),''),0,'PEN','PENDIENTE',
      v_provider,v_warehouse
    ) returning numero into v_numero;
  else
    if v_existing.estado not in ('PENDIENTE','REVISADO') then
      raise exception 'Una solicitud % no se puede editar.',v_existing.estado;
    end if;
    update public."ERP_SOLICITUDES_COMPRA_APPGT" set
      fecha=coalesce(p_fecha,current_date),fecha_necesidad=v_need,
      area=coalesce(nullif(btrim(coalesce(p_area,'')),''),area),centro_costo=null,
      justificacion=nullif(btrim(coalesce(p_justificacion,'')),''),
      proveedor_codigo=v_provider,almacen_codigo=v_warehouse,updated_by=auth.uid()
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
    v_price:=greatest(coalesce(nullif(v_item->>'precio_unitario','')::numeric,
      v_article.costo_estandar,0),0);
    v_photo:=nullif(btrim(coalesce(v_item->>'foto_url','')),'');
    if v_photo is not null and v_photo !~ ('^storage://erp-articulos/'||v_empresa::text||'/') then
      raise exception 'La foto del artículo tiene una ruta inválida.';
    end if;
    v_line:=v_line+1; v_amount:=v_amount+round(v_qty*v_price,6);
    insert into public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"(
      empresa_id,solicitud_numero,linea,articulo_codigo,descripcion,
      cantidad_solicitada,unidad_medida,precio_unitario,fecha_necesidad,
      proveedor_recomendado_codigo,almacen_destino_codigo,observacion,foto_url
    ) values (
      v_empresa,v_numero,v_line,v_article.codigo,v_article.nombre,v_qty,
      v_article.unidad_medida,v_price,
      coalesce(nullif(v_item->>'fecha_necesidad','')::date,v_need),
      v_provider,v_warehouse,
      nullif(btrim(coalesce(v_item->>'observacion','')),''),v_photo
    );
  end loop;
  update public."ERP_SOLICITUDES_COMPRA_APPGT" set monto_estimado=v_amount
  where empresa_id=v_empresa and numero=v_numero;
  return jsonb_build_object('numero',v_numero,'codigo',v_numero,'estado','PENDIENTE',
    'lineas',v_line,'monto_estimado',v_amount);
end
$$;

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
      'proveedor_recomendado_codigo',coalesce(d.proveedor_recomendado_codigo,s.proveedor_codigo),
      'almacen_destino_codigo',coalesce(d.almacen_destino_codigo,s.almacen_codigo),
      'fecha_solicitada',s.fecha,'fecha_oc_aprobada',d.fecha_oc_aprobada,
      'fecha_recibida',d.fecha_recibida,'foto_url',d.foto_url,
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

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('erp-articulos','erp-articulos',false,10485760,
  array['image/jpeg','image/png','image/webp']::text[])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists erp_articulos_select on storage.objects;
create policy erp_articulos_select on storage.objects for select to authenticated using (
  bucket_id='erp-articulos'
  and split_part(name,'/',1)=public.appgt_empresa_actual_id()::text
);
drop policy if exists erp_articulos_insert on storage.objects;
create policy erp_articulos_insert on storage.objects for insert to authenticated with check (
  bucket_id='erp-articulos'
  and split_part(name,'/',1)=public.appgt_empresa_actual_id()::text
);

-- ============================================================================
-- Ingresos en Almacén: documento, almacén elegido y saldos por ingreso.
-- ============================================================================

alter table public."ERP_INGRESOS_ALMACEN_APPGT"
  add column if not exists tipo_documento text not null default 'GUIA DE REMISION';
alter table public."ERP_INGRESOS_ALMACEN_APPGT"
  drop constraint if exists erp_ingreso_tipo_documento_ck;
alter table public."ERP_INGRESOS_ALMACEN_APPGT"
  add constraint erp_ingreso_tipo_documento_ck check (
    tipo_documento in ('GUIA DE REMISION','FACTURA')
  );

alter table public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"
  add column if not exists almacen_codigo text,
  add column if not exists cantidad_pendiente numeric(20,6)
    generated always as (greatest(cantidad_pendiente_antes-cantidad_recibida,0)) stored;

update public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT" d
set almacen_codigo=i.almacen_codigo
from public."ERP_INGRESOS_ALMACEN_APPGT" i
where i.empresa_id=d.empresa_id and i.numero=d.ingreso_numero
  and d.almacen_codigo is null;

alter table public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"
  drop constraint if exists erp_ingreso_det_almacen_fk;
alter table public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"
  add constraint erp_ingreso_det_almacen_fk foreign key (empresa_id,almacen_codigo)
    references public."ERP_ALMACENES_APPGT"(empresa_id,codigo);

create or replace function public.erp_registrar_ingreso_compra_v2(
  p_orden_numero text,p_fecha date,p_tipo_documento text,p_numero_documento text,
  p_almacen_codigo text,p_detalles jsonb,p_observacion text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa uuid:=public.appgt_empresa_actual_id();
  v_order public."ERP_ORDENES_COMPRA_APPGT"%rowtype;
  v_detail jsonb; v_line public."ERP_ORDENES_COMPRA_DETALLE_APPGT"%rowtype;
  v_qty numeric(20,6); v_ingreso text; v_ingreso_line integer:=0; v_new_state text;
  v_type text:=upper(btrim(coalesce(p_tipo_documento,'')));
  v_document text:=nullif(btrim(coalesce(p_numero_documento,'')),'');
  v_warehouse text:=nullif(btrim(coalesce(p_almacen_codigo,'')),'');
begin
  if v_empresa is null then raise exception 'No se pudo resolver la empresa activa' using errcode='42501'; end if;
  if auth.role()<>'service_role' and not public.appgt_can_insert_table('ERP_INGRESOS_ALMACEN_APPGT') then
    raise exception 'Sin permiso para registrar ingresos de almacén' using errcode='42501';
  end if;
  if v_type not in ('GUIA DE REMISION','FACTURA') then raise exception 'Seleccione un tipo de documento válido.'; end if;
  if v_document is null then raise exception 'Debe ingresar el número de documento.'; end if;
  if v_warehouse is null or not exists(select 1 from public."ERP_ALMACENES_APPGT" a
    where a.empresa_id=v_empresa and a.codigo=v_warehouse and a.estado='ACTIVO'
      and not a.eliminado and a.deleted_at is null) then
    raise exception 'Seleccione un almacén válido.';
  end if;
  if jsonb_typeof(p_detalles)<>'array' or jsonb_array_length(p_detalles)=0 then
    raise exception 'Debe confirmar al menos un artículo o insumo recibido.';
  end if;
  select * into v_order from public."ERP_ORDENES_COMPRA_APPGT"
  where empresa_id=v_empresa and numero=p_orden_numero
    and not eliminado and deleted_at is null for update;
  if v_order.id is null then raise exception 'Orden de compra no encontrada.'; end if;
  if v_order.estado not in ('APROBADO','DESPACHADO PARCIALMENTE') then
    raise exception 'Solo se reciben órdenes APROBADAS o DESPACHADAS PARCIALMENTE.';
  end if;
  v_ingreso:='ING-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS')||'-'||
    upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  perform set_config('appgt.erp_receipt_context','1',true);
  insert into public."ERP_INGRESOS_ALMACEN_APPGT"(
    empresa_id,numero,fecha_ingreso,orden_numero,proveedor_codigo,
    proveedor_ruc,almacen_codigo,tipo_documento,guia_remision,estado,observacion
  ) values (
    v_empresa,v_ingreso,coalesce(p_fecha,current_date),v_order.numero,
    v_order.proveedor_codigo,v_order.proveedor_ruc,v_warehouse,v_type,
    v_document,'CONFIRMADO',nullif(btrim(coalesce(p_observacion,'')),'')
  );
  for v_detail in select value from jsonb_array_elements(p_detalles) loop
    v_qty:=coalesce((v_detail->>'cantidad_recibida')::numeric,0);
    if v_qty<=0 then continue; end if;
    select * into v_line from public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
    where empresa_id=v_empresa and orden_numero=v_order.numero
      and linea=(v_detail->>'linea')::integer
      and not eliminado and deleted_at is null for update;
    if v_line.id is null then raise exception 'La línea % no pertenece a la orden %.',v_detail->>'linea',v_order.numero; end if;
    if v_qty>v_line.cantidad-v_line.cantidad_despachada then
      raise exception 'La cantidad de % supera el saldo pendiente de %.',
        v_line.articulo_codigo,v_line.cantidad-v_line.cantidad_despachada;
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
      v_line.cantidad,v_line.cantidad-v_line.cantidad_despachada,v_qty,
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
      'OC '||v_order.numero||' / Solicitud '||coalesce(v_line.solicitud_numero,'-')||
        ' / '||v_type||' '||v_document,'CONFIRMADO'
    );
    update public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
    set cantidad_despachada=cantidad_despachada+v_qty,
        cantidad_recibida=cantidad_recibida+v_qty
    where id=v_line.id;
  end loop;
  if v_ingreso_line=0 then raise exception 'Todas las cantidades recibidas son cero.'; end if;
  select case when bool_and(cantidad_despachada>=cantidad)
    then 'DESPACHADO' else 'DESPACHADO PARCIALMENTE' end
  into v_new_state from public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  where empresa_id=v_empresa and orden_numero=v_order.numero
    and not eliminado and deleted_at is null;
  update public."ERP_ORDENES_COMPRA_APPGT" set
    estado=v_new_state,fecha_despachada=coalesce(p_fecha,current_date),
    despachado_por=auth.uid(),despachado_at=clock_timestamp()
  where id=v_order.id;
  perform public.appgt_erp_refrescar_solicitudes_orden_v1(v_empresa,v_order.numero);
  insert into public."ERP_EVENTOS_INTEGRACION_APPGT"(
    empresa_id,modulo_origen,documento_tipo,documento_numero,evento,
    modulos_destino,payload
  ) values (
    v_empresa,'ALMACEN','INGRESO_COMPRA',v_ingreso,'STOCK_ACTUALIZADO',
    array['COMPRAS','FINANZAS'],jsonb_build_object(
      'orden_numero',v_order.numero,'tipo_documento',v_type,
      'numero_documento',v_document,'almacen_codigo',v_warehouse,
      'estado_orden',v_new_state
    )
  ) on conflict do nothing;
  return jsonb_build_object(
    'guardado',true,'ingreso_numero',v_ingreso,'orden_numero',v_order.numero,
    'estado_orden',v_new_state,'lineas_recibidas',v_ingreso_line
  );
end
$$;

-- ============================================================================
-- Vales: actores legibles. Los UUID y cantidad_despachada se conservan como
-- auditoría técnica/inventario, pero dejan de exponerse como campos funcionales.
-- ============================================================================

alter table public."ERP_VALES_DESPACHO_APPGT"
  add column if not exists aprobado_por_nombre text,
  add column if not exists despachado_por_nombre text,
  add column if not exists anulado_por_nombre text;

update public."ERP_VALES_DESPACHO_APPGT" v
set aprobado_por_nombre=concat_ws('-',nullif(p."DNI",''),
      nullif(coalesce(nullif(p.first_nombres,''),p.nombres),''))
from public."PERFILES_DE_USUARIOS_APPGT" p
where p.id=v.aprobado_por and p.empresa_id=v.empresa_id
  and nullif(v.aprobado_por_nombre,'') is null;
update public."ERP_VALES_DESPACHO_APPGT" v
set despachado_por_nombre=concat_ws('-',nullif(p."DNI",''),
      nullif(coalesce(nullif(p.first_nombres,''),p.nombres),''))
from public."PERFILES_DE_USUARIOS_APPGT" p
where p.id=v.despachado_por and p.empresa_id=v.empresa_id
  and nullif(v.despachado_por_nombre,'') is null;
update public."ERP_VALES_DESPACHO_APPGT" v
set anulado_por_nombre=concat_ws('-',nullif(p."DNI",''),
      nullif(coalesce(nullif(p.first_nombres,''),p.nombres),''))
from public."PERFILES_DE_USUARIOS_APPGT" p
where p.id=v.anulado_por and p.empresa_id=v.empresa_id
  and nullif(v.anulado_por_nombre,'') is null;

create or replace function public.appgt_erp_actor_nombre_vale_v1()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_identidad jsonb; v_nombre text;
begin
  if new.estado is not distinct from old.estado then return new; end if;
  v_identidad:=public.erp_identidad_usuario_actual_v1();
  v_nombre:=concat_ws('-',nullif(v_identidad->>'dni',''),
    nullif(v_identidad->>'first_nombres',''));
  if new.estado='APROBADO' then new.aprobado_por_nombre:=nullif(v_nombre,''); end if;
  if new.estado='DESPACHADO' then new.despachado_por_nombre:=nullif(v_nombre,''); end if;
  if new.estado='ANULADO' then new.anulado_por_nombre:=nullif(v_nombre,''); end if;
  return new;
end
$$;

drop trigger if exists zzz_erp_actor_nombre_vale on public."ERP_VALES_DESPACHO_APPGT";
create trigger zzz_erp_actor_nombre_vale
before update of estado on public."ERP_VALES_DESPACHO_APPGT"
for each row execute function public.appgt_erp_actor_nombre_vale_v1();

-- ============================================================================
-- Metadatos de formatos.
-- ============================================================================

with companies as (
  select distinct empresa_id from public."MATRIZ_FORMATOS_APPGT"
), fields(tabla,campo,etiqueta,tipo,tipo_ui,requerido,visible,visible_tabla,editable,orden) as (values
  ('ERP_SOLICITUDES_COMPRA_APPGT','proveedor_codigo','Proveedor','text','dropdown',true,true,true,true,7),
  ('ERP_SOLICITUDES_COMPRA_APPGT','almacen_codigo','Almacén','text','dropdown',true,true,true,true,8),
  ('ERP_SOLICITUDES_COMPRA_DETALLE_APPGT','foto_url','Foto','text','image',false,true,true,true,10),
  ('ERP_INGRESOS_ALMACEN_APPGT','tipo_documento','Tipo de documento','text','dropdown',true,true,true,true,7),
  ('ERP_INGRESOS_ALMACEN_APPGT','guia_remision','Número de documento','text','text',true,true,true,true,8),
  ('ERP_INGRESOS_ALMACEN_APPGT','almacen_codigo','Almacén','text','dropdown',true,true,true,true,6),
  ('ERP_INGRESOS_ALMACEN_DETALLE_APPGT','almacen_codigo','Almacén','text','readonly',false,true,true,false,7),
  ('ERP_INGRESOS_ALMACEN_DETALLE_APPGT','cantidad_ordenada','Cantidad ordenada','numeric','readonly',false,true,true,false,8),
  ('ERP_INGRESOS_ALMACEN_DETALLE_APPGT','cantidad_pendiente','Cantidad pendiente','numeric','readonly',false,true,true,false,9),
  ('ERP_INGRESOS_ALMACEN_DETALLE_APPGT','cantidad_recibida','Cantidad recibida','numeric','readonly',false,true,true,false,10),
  ('ERP_VALES_DESPACHO_APPGT','estado','Estado','text','readonly',false,true,true,false,9),
  ('ERP_VALES_DESPACHO_APPGT','aprobado_por_nombre','Aprobado por','text','readonly',false,false,true,false,10),
  ('ERP_VALES_DESPACHO_APPGT','aprobado_at','Fecha y hora de aprobación','timestamptz','datetime',false,false,true,false,11),
  ('ERP_VALES_DESPACHO_APPGT','despachado_por_nombre','Despachado por','text','readonly',false,false,true,false,12),
  ('ERP_VALES_DESPACHO_APPGT','despachado_at','Fecha y hora de despacho','timestamptz','datetime',false,false,true,false,13),
  ('ERP_VALES_DESPACHO_APPGT','anulado_por_nombre','Anulado por','text','readonly',false,false,true,false,14),
  ('ERP_VALES_DESPACHO_APPGT','anulado_at','Fecha y hora de anulación','timestamptz','datetime',false,false,true,false,15),
  ('ERP_VALES_DESPACHO_DETALLE_APPGT','cantidad_solicitada','Cantidad','numeric','number',true,true,true,true,5)
)
insert into public."MATRIZ_CAMPOS_FORMATO_APPGT"(
  id,empresa_id,tabla_destino,campo,etiqueta,tipo,tipo_ui,requerido,visible,
  visible_tabla,editable,orden,activo,created_at,updated_at,estado_sync,eliminado
)
select 'erp_procurement_'||substr(md5(c.empresa_id::text||'|'||f.tabla||'|'||f.campo),1,20),
  c.empresa_id,f.tabla,f.campo,f.etiqueta,f.tipo,f.tipo_ui,f.requerido,
  f.visible,f.visible_tabla,f.editable,f.orden,true,now(),now(),'sincronizado',false
from companies c cross join fields f
on conflict (tabla_destino,campo) do update set
  etiqueta=excluded.etiqueta,tipo=excluded.tipo,tipo_ui=excluded.tipo_ui,
  requerido=excluded.requerido,visible=excluded.visible,
  visible_tabla=excluded.visible_tabla,editable=excluded.editable,
  orden=excluded.orden,activo=true,eliminado=false,updated_at=now();

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set id_campo_dropdown='[GUIA DE REMISION;FACTURA]',updated_at=now()
where tabla_destino='ERP_INGRESOS_ALMACEN_APPGT' and campo='tipo_documento';

update public."MATRIZ_CAMPOS_FORMATO_APPGT" set
  visible=false,visible_tabla=false,editable=false,activo=false,updated_at=now()
where (tabla_destino='ERP_INGRESOS_ALMACEN_DETALLE_APPGT'
       and lower(campo)='cantidad_pendiente_antes')
   or (tabla_destino='ERP_VALES_DESPACHO_DETALLE_APPGT'
       and lower(campo)='cantidad_despachada')
   or (tabla_destino='ERP_VALES_DESPACHO_APPGT' and lower(campo) in (
       'revisado_por','revisado_at','estado_aprobacion','estado_aprobado',
       'aprobado_por','despachado_por','anulado_por'));

alter table public."MATRIZ_FORMATOS_APPGT"
  disable trigger appgt_aplicar_capacidades_formato_trigger;
update public."MATRIZ_FORMATOS_APPGT"
set flujo_estados='["PENDIENTE","REVISADO","APROBADO","DESPACHADO","ANULADO"]'::jsonb,
    workflow_enabled=true,approvals_enabled=true,updated_at=now()
where tabla_destino='ERP_VALES_DESPACHO_APPGT';
alter table public."MATRIZ_FORMATOS_APPGT"
  enable trigger appgt_aplicar_capacidades_formato_trigger;

revoke all on function public.erp_guardar_solicitud_pedido_v2(
  text,date,date,text,text,text,text,text,text,jsonb
) from public,anon;
grant execute on function public.erp_guardar_solicitud_pedido_v2(
  text,date,date,text,text,text,text,text,text,jsonb
) to authenticated,service_role;
revoke all on function public.erp_registrar_ingreso_compra_v2(
  text,date,text,text,text,jsonb,text
) from public,anon;
grant execute on function public.erp_registrar_ingreso_compra_v2(
  text,date,text,text,text,jsonb,text
) to authenticated,service_role;
grant execute on function public.erp_identidad_usuario_actual_v1()
  to authenticated,service_role;
grant execute on function public.erp_solicitudes_aprobadas_oc_v1()
  to authenticated,service_role;

notify pgrst, 'reload schema';
commit;
