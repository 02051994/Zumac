begin;

-- Las acciones de revisión/aprobación usan la misma autorización granular
-- "update" que se configura en la pantalla de permisos por estado. Cuando no
-- hay permisos granulares, se conservan los indicadores can_review/can_approve.
create or replace function public.appgt_puede_accion_estado_formato_v1(
  p_tabla text,
  p_estado text,
  p_accion text
)
returns boolean
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select case
    when auth.role() = 'service_role' then true
    when auth.uid() is null or public.appgt_empresa_actual_id() is null then false
    when public.appgt_es_admin_empresa(public.appgt_empresa_actual_id()) then true
    else exists (
      select 1
      from public."PERMISOS_DE_USUARIOS_APPGT" p
      where p.empresa_id=public.appgt_empresa_actual_id()
        and p.user_id=auth.uid()
        and coalesce(p.activo,true) and not coalesce(p.eliminado,false)
        and p.deleted_at is null
        and public.appgt_normalizar_clave(coalesce(p.tabla_destino,''))
            = public.appgt_normalizar_clave(p_tabla)
        and case
          when p.permisos_estado <> '{}'::jsonb then
            case lower(btrim(coalesce(p_accion,'')))
              when 'review' then coalesce(
                (p.permisos_estado
                  -> upper(btrim(coalesce(p_estado,'')))
                  ->> 'review')::boolean,
                (p.permisos_estado
                  -> upper(btrim(coalesce(p_estado,'')))
                  ->> 'update')::boolean,
                false
              )
              when 'approve' then coalesce(
                (p.permisos_estado
                  -> upper(btrim(coalesce(p_estado,'')))
                  ->> 'approve')::boolean,
                (p.permisos_estado
                  -> upper(btrim(coalesce(p_estado,'')))
                  ->> 'update')::boolean,
                false
              )
              else coalesce(
                (p.permisos_estado
                  -> upper(btrim(coalesce(p_estado,'')))
                  ->> lower(btrim(coalesce(p_accion,''))))::boolean,
                false
              )
            end
          when lower(btrim(coalesce(p_accion,''))) = 'view'
            then coalesce(p.can_view,false)
          when lower(btrim(coalesce(p_accion,''))) in ('create','insert')
            then coalesce(p.can_insert,false)
          when lower(btrim(coalesce(p_accion,''))) in ('update','edit')
            then coalesce(p.can_update,false)
              or (upper(btrim(coalesce(p_estado,'')))='PENDIENTE' and coalesce(p.can_review,false))
              or (upper(btrim(coalesce(p_estado,'')))='REVISADO' and coalesce(p.can_approve,false))
              or (
                public.appgt_normalizar_clave(p_tabla)
                  = public.appgt_normalizar_clave('ERP_INGRESOS_ALMACEN_APPGT')
                and upper(btrim(coalesce(p_estado,'')))='PENDIENTE'
                and coalesce(p.can_approve,false)
              )
              or (
                public.appgt_normalizar_clave(p_tabla)
                  = public.appgt_normalizar_clave('ERP_VALES_DESPACHO_APPGT')
                and upper(btrim(coalesce(p_estado,'')))='APROBADO'
                and coalesce(p.can_approve,false)
              )
          when lower(btrim(coalesce(p_accion,''))) = 'review'
            then coalesce(p.can_review,false)
          when lower(btrim(coalesce(p_accion,''))) = 'approve'
            then coalesce(p.can_approve,false)
          when lower(btrim(coalesce(p_accion,''))) = 'delete'
            then coalesce(p.can_delete,false)
          else false
        end
    )
  end
$$;

create or replace function public.erp_confirmar_ingreso_almacen_v1(
  p_ingreso_numero text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa uuid:=public.appgt_empresa_actual_id();
  v_header public."ERP_INGRESOS_ALMACEN_APPGT"%rowtype;
  v_detail record;
  v_detail_count integer;
begin
  select * into v_header
  from public."ERP_INGRESOS_ALMACEN_APPGT"
  where empresa_id=v_empresa and numero=p_ingreso_numero
  for update;

  if v_header.id is null then
    raise exception 'Ingreso no encontrado.';
  end if;
  if v_header.orden_numero<>'SIN OC' then
    raise exception 'Los ingresos con OC se confirman al guardarse.';
  end if;
  if v_header.estado<>'PENDIENTE' then
    raise exception 'Solo se confirman ingresos PENDIENTES.';
  end if;
  if auth.role()<>'service_role'
     and not (
       public.appgt_puede_accion_estado_formato_v1(
         'ERP_INGRESOS_ALMACEN_APPGT','PENDIENTE','approve'
       )
       or public.appgt_puede_accion_estado_formato_v1(
         'ERP_INGRESOS_ALMACEN_APPGT','PENDIENTE','update'
       )
     ) then
    raise exception 'Sin permiso para confirmar ingresos.' using errcode='42501';
  end if;

  select count(*) into v_detail_count
  from public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"
  where empresa_id=v_empresa and ingreso_numero=v_header.numero
    and not eliminado and deleted_at is null;
  if v_detail_count=0 then
    raise exception 'No se puede confirmar un ingreso sin artículos o insumos.';
  end if;

  for v_detail in
    select *
    from public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"
    where empresa_id=v_empresa and ingreso_numero=v_header.numero
      and not eliminado and deleted_at is null
    order by linea
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

  update public."ERP_INGRESOS_ALMACEN_APPGT"
  set estado='CONFIRMADO',
      confirmado_por=auth.uid(),
      confirmado_at=clock_timestamp()
  where id=v_header.id;

  if not found then
    raise exception 'No se pudo confirmar el ingreso %.',v_header.numero;
  end if;

  insert into public."ERP_EVENTOS_INTEGRACION_APPGT"(
    empresa_id,modulo_origen,documento_tipo,documento_numero,evento,
    modulos_destino,payload
  ) values (
    v_empresa,'ALMACEN','INGRESO_SIN_OC',v_header.numero,'STOCK_ACTUALIZADO',
    array['INVENTARIO','FINANZAS'],
    jsonb_build_object('orden_numero','SIN OC','almacen_codigo',v_header.almacen_codigo)
  ) on conflict do nothing;

  return jsonb_build_object(
    'confirmado',true,
    'ingreso_numero',v_header.numero,
    'estado','CONFIRMADO',
    'movimientos_creados',v_detail_count
  );
end
$$;

create or replace function public.erp_anular_ingreso_compra_v1(
  p_ingreso_numero text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa uuid:=public.appgt_empresa_actual_id();
  v_header public."ERP_INGRESOS_ALMACEN_APPGT"%rowtype;
  v_row record;
  v_movements_reversed integer:=0;
begin
  select * into v_header
  from public."ERP_INGRESOS_ALMACEN_APPGT"
  where empresa_id=v_empresa and numero=p_ingreso_numero
  for update;

  if v_header.id is null then
    raise exception 'Ingreso no encontrado.';
  end if;
  if v_header.estado='ANULADO' then
    raise exception 'El ingreso ya fue anulado.';
  end if;
  if auth.role()<>'service_role'
     and not (
       public.appgt_puede_accion_estado_formato_v1(
         'ERP_INGRESOS_ALMACEN_APPGT',v_header.estado,'delete'
       )
       or public.appgt_puede_accion_estado_formato_v1(
         'ERP_INGRESOS_ALMACEN_APPGT',v_header.estado,'update'
       )
     ) then
    raise exception 'Sin permiso para anular ingresos.' using errcode='42501';
  end if;

  perform set_config('appgt.erp_receipt_context','1',true);
  if v_header.estado='CONFIRMADO' then
    update public."ERP_MOVIMIENTOS_INVENTARIO_APPGT"
    set estado='ANULADO'
    where empresa_id=v_empresa
      and documento_origen_tipo='INGRESO_COMPRA'
      and documento_origen_codigo=v_header.numero
      and estado='CONFIRMADO';
    get diagnostics v_movements_reversed = row_count;

    if v_movements_reversed=0 then
      raise exception 'El ingreso confirmado % no tiene movimientos de stock activos para revertir.',v_header.numero;
    end if;

    if v_header.orden_numero<>'SIN OC' then
      for v_row in
        select *
        from public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"
        where empresa_id=v_empresa and ingreso_numero=v_header.numero
          and not eliminado and deleted_at is null
      loop
        update public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
        set cantidad_despachada=greatest(cantidad_despachada-v_row.cantidad_recibida,0),
            cantidad_recibida=greatest(cantidad_recibida-v_row.cantidad_recibida,0)
        where empresa_id=v_empresa
          and orden_numero=v_header.orden_numero
          and linea=v_row.orden_linea;
        perform public.appgt_erp_refrescar_trazabilidad_linea_v1(
          v_empresa,v_header.orden_numero,v_row.orden_linea
        );
      end loop;
      perform public.appgt_erp_refrescar_solicitudes_orden_v1(
        v_empresa,v_header.orden_numero
      );
    end if;
  end if;

  update public."ERP_INGRESOS_ALMACEN_APPGT"
  set estado='ANULADO',
      anulado_por=auth.uid(),
      anulado_at=clock_timestamp()
  where id=v_header.id;

  if not found then
    raise exception 'No se pudo anular el ingreso %.',v_header.numero;
  end if;

  update public."ERP_EVENTOS_INTEGRACION_APPGT"
  set estado='ANULADO'
  where empresa_id=v_empresa
    and documento_tipo in ('INGRESO_COMPRA','INGRESO_SIN_OC')
    and documento_numero=v_header.numero;

  return jsonb_build_object(
    'anulado',true,
    'ingreso_numero',v_header.numero,
    'estado','ANULADO',
    'movimientos_revertidos',v_movements_reversed
  );
end
$$;

-- Los vales descuentan o restituyen stock mediante el trigger de cambio de
-- estado. El RPC valida en el servidor tanto el permiso como la transición,
-- para impedir saltos de estado y asegurar que el trigger realmente se ejecute.
create or replace function public.erp_cambiar_estado_vale_despacho_v1(
  p_vale_numero text,
  p_estado text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa uuid:=public.appgt_empresa_actual_id();
  v_next text:=upper(btrim(coalesce(p_estado,'')));
  v_row public."ERP_VALES_DESPACHO_APPGT"%rowtype;
  v_action text;
  v_movement_count integer:=0;
begin
  select * into v_row
  from public."ERP_VALES_DESPACHO_APPGT"
  where empresa_id=v_empresa and numero=p_vale_numero
  for update;

  if v_row.id is null then
    raise exception 'Vale de despacho no encontrado.';
  end if;
  if not (
    (v_row.estado='PENDIENTE' and v_next in ('REVISADO','ANULADO'))
    or (v_row.estado='REVISADO' and v_next in ('APROBADO','ANULADO'))
    or (v_row.estado='APROBADO' and v_next in ('DESPACHADO','ANULADO'))
    or (v_row.estado='DESPACHADO' and v_next='ANULADO')
  ) then
    raise exception 'Transición de vale no permitida: % -> %.',v_row.estado,v_next;
  end if;

  v_action:=case
    when v_next='REVISADO' then 'review'
    when v_next in ('APROBADO','DESPACHADO') then 'approve'
    else 'delete'
  end;
  if auth.role()<>'service_role'
     and not (
       public.appgt_puede_accion_estado_formato_v1(
         'ERP_VALES_DESPACHO_APPGT',v_row.estado,v_action
       )
       or public.appgt_puede_accion_estado_formato_v1(
         'ERP_VALES_DESPACHO_APPGT',v_row.estado,'update'
       )
     ) then
    raise exception 'Sin permiso para cambiar el estado del vale.' using errcode='42501';
  end if;

  if v_row.estado='DESPACHADO' and v_next='ANULADO' then
    select count(*) into v_movement_count
    from public."ERP_MOVIMIENTOS_INVENTARIO_APPGT"
    where empresa_id=v_empresa
      and documento_origen_tipo='VALE_DESPACHO'
      and documento_origen_codigo=v_row.numero
      and estado='CONFIRMADO';
    if v_movement_count=0 then
      raise exception 'El vale despachado % no tiene movimientos de stock activos para revertir.',v_row.numero;
    end if;
  end if;

  update public."ERP_VALES_DESPACHO_APPGT"
  set estado=v_next
  where id=v_row.id;

  if not found then
    raise exception 'No se pudo actualizar el vale %.',v_row.numero;
  end if;

  if v_next='DESPACHADO' then
    select count(*) into v_movement_count
    from public."ERP_MOVIMIENTOS_INVENTARIO_APPGT"
    where empresa_id=v_empresa
      and documento_origen_tipo='VALE_DESPACHO'
      and documento_origen_codigo=v_row.numero
      and estado='CONFIRMADO';
    if v_movement_count=0 then
      raise exception 'El despacho % no generó movimientos de stock.',v_row.numero;
    end if;
  elsif v_row.estado='DESPACHADO' and v_next='ANULADO' then
    select count(*) into v_movement_count
    from public."ERP_MOVIMIENTOS_INVENTARIO_APPGT"
    where empresa_id=v_empresa
      and documento_origen_tipo='VALE_DESPACHO'
      and documento_origen_codigo=v_row.numero
      and estado='CONFIRMADO';
    if v_movement_count<>0 then
      raise exception 'La anulación del vale % no revirtió todos los movimientos de stock.',v_row.numero;
    end if;
  end if;

  return jsonb_build_object(
    'actualizado',true,
    'vale_numero',v_row.numero,
    'estado',v_next,
    'movimientos_stock',v_movement_count
  );
end
$$;

revoke all on function public.appgt_puede_accion_estado_formato_v1(text,text,text)
  from public,anon;
revoke all on function public.erp_confirmar_ingreso_almacen_v1(text)
  from public,anon;
revoke all on function public.erp_anular_ingreso_compra_v1(text)
  from public,anon;
revoke all on function public.erp_cambiar_estado_vale_despacho_v1(text,text)
  from public,anon;

grant execute on function public.appgt_puede_accion_estado_formato_v1(text,text,text)
  to authenticated,service_role;
grant execute on function public.erp_confirmar_ingreso_almacen_v1(text)
  to authenticated,service_role;
grant execute on function public.erp_anular_ingreso_compra_v1(text)
  to authenticated,service_role;
grant execute on function public.erp_cambiar_estado_vale_despacho_v1(text,text)
  to authenticated,service_role;

commit;
