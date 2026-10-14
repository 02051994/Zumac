begin;

-- Cuando cambia el estado de una cabecera, la propagación a sus líneas es una
-- consecuencia interna del mismo flujo. El control de detalles debe seguir
-- bloqueando ediciones directas después de aprobar, pero no puede rechazar
-- esta actualización derivada del trigger de la cabecera.
create or replace function public.appgt_erp_propagar_estado_detalle_v1()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_previous_context text:=coalesce(
    current_setting('appgt.erp_approval_transition_context',true),
    '0'
  );
begin
  if new.estado is not distinct from old.estado then return new; end if;

  perform set_config('appgt.erp_approval_transition_context','1',true);

  if tg_table_name='ERP_SOLICITUDES_COMPRA_APPGT' then
    update public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"
    set estado=new.estado
    where empresa_id=new.empresa_id and solicitud_numero=new.numero
      and not eliminado and deleted_at is null
      and coalesce(cantidad_recibida,0)=0;
  elsif tg_table_name='ERP_ORDENES_COMPRA_APPGT' then
    update public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
    set estado=new.estado
    where empresa_id=new.empresa_id and orden_numero=new.numero
      and not eliminado and deleted_at is null
      and coalesce(cantidad_recibida,0)=0;
  elsif tg_table_name='ERP_VALES_DESPACHO_APPGT' then
    update public."ERP_VALES_DESPACHO_DETALLE_APPGT"
    set estado=new.estado
    where empresa_id=new.empresa_id and vale_numero=new.numero
      and not eliminado and deleted_at is null;
  end if;

  perform set_config(
    'appgt.erp_approval_transition_context',
    v_previous_context,
    true
  );
  return new;
exception
  when others then
    perform set_config(
      'appgt.erp_approval_transition_context',
      v_previous_context,
      true
    );
    raise;
end
$$;

create or replace function public.appgt_erp_controlar_detalle_flujo_v2()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa uuid:=coalesce(new.empresa_id,old.empresa_id);
  v_documento text;
  v_estado text;
  v_header text;
  v_approval_transition boolean:=
    coalesce(
      current_setting('appgt.erp_approval_transition_context',true),
      '0'
    )='1'
    and pg_trigger_depth()>1;
begin
  if tg_table_name='ERP_SOLICITUDES_COMPRA_DETALLE_APPGT' then
    v_documento:=coalesce(new.solicitud_numero,old.solicitud_numero);
    v_header:='ERP_SOLICITUDES_COMPRA_APPGT';
    select estado into v_estado
    from public."ERP_SOLICITUDES_COMPRA_APPGT"
    where empresa_id=v_empresa and numero=v_documento;
  elsif tg_table_name='ERP_ORDENES_COMPRA_DETALLE_APPGT' then
    v_documento:=coalesce(new.orden_numero,old.orden_numero);
    v_header:='ERP_ORDENES_COMPRA_APPGT';
    select estado into v_estado
    from public."ERP_ORDENES_COMPRA_APPGT"
    where empresa_id=v_empresa and numero=v_documento;
  else
    v_documento:=coalesce(new.vale_numero,old.vale_numero);
    v_header:='ERP_VALES_DESPACHO_APPGT';
    select estado into v_estado
    from public."ERP_VALES_DESPACHO_APPGT"
    where empresa_id=v_empresa and numero=v_documento;
  end if;

  if not (
    coalesce(current_setting('appgt.erp_dispatch_context',true),'0')='1'
    or coalesce(current_setting('appgt.erp_receipt_context',true),'0')='1'
    or v_approval_transition
  ) and v_estado not in ('PENDIENTE','REVISADO') then
    raise exception 'No se pueden modificar detalles cuando el documento está %.',v_estado;
  end if;

  if tg_op='DELETE' then return old; end if;
  return new;
end
$$;

-- Prueba transaccional contra datos reales, si existe al menos un documento
-- elegible. El SAVEPOINT permite recorrer REVISADO -> APROBADO y comprobar la
-- propagación completa sin conservar ningún cambio de negocio ni auditoría.
savepoint appgt_approval_transition_test;

do $$
declare
  v_id uuid;
  v_empresa uuid;
  v_numero text;
  v_estado text;
begin
  select h.id,h.empresa_id,h.numero,h.estado
  into v_id,v_empresa,v_numero,v_estado
  from public."ERP_SOLICITUDES_COMPRA_APPGT" h
  where h.estado in ('PENDIENTE','REVISADO')
    and not h.eliminado and h.deleted_at is null
    and exists (
      select 1
      from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" d
      where d.empresa_id=h.empresa_id and d.solicitud_numero=h.numero
        and not d.eliminado and d.deleted_at is null
        and coalesce(d.cantidad_recibida,0)=0
    )
  order by case when h.estado='REVISADO' then 0 else 1 end,h.created_at desc
  limit 1
  for update;

  if v_id is not null then
    if v_estado='PENDIENTE' then
      update public."ERP_SOLICITUDES_COMPRA_APPGT"
      set estado='REVISADO' where id=v_id;
    end if;
    update public."ERP_SOLICITUDES_COMPRA_APPGT"
    set estado='APROBADO' where id=v_id;

    if exists (
      select 1
      from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" d
      where d.empresa_id=v_empresa and d.solicitud_numero=v_numero
        and not d.eliminado and d.deleted_at is null
        and coalesce(d.cantidad_recibida,0)=0 and d.estado<>'APROBADO'
    ) then
      raise exception 'La aprobación de solicitud no propagó el estado a sus líneas.';
    end if;
  end if;

  v_id:=null;v_empresa:=null;v_numero:=null;v_estado:=null;
  select h.id,h.empresa_id,h.numero,h.estado
  into v_id,v_empresa,v_numero,v_estado
  from public."ERP_ORDENES_COMPRA_APPGT" h
  where h.estado in ('PENDIENTE','REVISADO')
    and not h.eliminado and h.deleted_at is null
    and exists (
      select 1
      from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d
      where d.empresa_id=h.empresa_id and d.orden_numero=h.numero
        and not d.eliminado and d.deleted_at is null
        and coalesce(d.cantidad_recibida,0)=0
    )
  order by case when h.estado='REVISADO' then 0 else 1 end,h.created_at desc
  limit 1
  for update;

  if v_id is not null then
    if v_estado='PENDIENTE' then
      update public."ERP_ORDENES_COMPRA_APPGT"
      set estado='REVISADO' where id=v_id;
    end if;
    update public."ERP_ORDENES_COMPRA_APPGT"
    set estado='APROBADO' where id=v_id;

    if exists (
      select 1
      from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d
      where d.empresa_id=v_empresa and d.orden_numero=v_numero
        and not d.eliminado and d.deleted_at is null
        and coalesce(d.cantidad_recibida,0)=0 and d.estado<>'APROBADO'
    ) then
      raise exception 'La aprobación de orden no propagó el estado a sus líneas.';
    end if;
  end if;

  v_id:=null;v_empresa:=null;v_numero:=null;v_estado:=null;
  select h.id,h.empresa_id,h.numero,h.estado
  into v_id,v_empresa,v_numero,v_estado
  from public."ERP_VALES_DESPACHO_APPGT" h
  where h.estado in ('PENDIENTE','REVISADO')
    and not h.eliminado and h.deleted_at is null
    and exists (
      select 1
      from public."ERP_VALES_DESPACHO_DETALLE_APPGT" d
      where d.empresa_id=h.empresa_id and d.vale_numero=h.numero
        and not d.eliminado and d.deleted_at is null
    )
  order by case when h.estado='REVISADO' then 0 else 1 end,h.created_at desc
  limit 1
  for update;

  if v_id is not null then
    if v_estado='PENDIENTE' then
      update public."ERP_VALES_DESPACHO_APPGT"
      set estado='REVISADO' where id=v_id;
    end if;
    update public."ERP_VALES_DESPACHO_APPGT"
    set estado='APROBADO' where id=v_id;

    if exists (
      select 1
      from public."ERP_VALES_DESPACHO_DETALLE_APPGT" d
      where d.empresa_id=v_empresa and d.vale_numero=v_numero
        and not d.eliminado and d.deleted_at is null
        and d.estado<>'APROBADO'
    ) then
      raise exception 'La aprobación de vale no propagó el estado a sus líneas.';
    end if;
  end if;
end
$$;

rollback to savepoint appgt_approval_transition_test;
release savepoint appgt_approval_transition_test;

notify pgrst, 'reload schema';
commit;
