begin;

-- La aprobación y la recepción son seguimientos distintos. Una solicitud
-- conserva su estado de aprobación y usa estado_de_recibido para la entrega.
select set_config('appgt.erp_receipt_context','1',true);

update public."ERP_SOLICITUDES_COMPRA_APPGT"
set estado='APROBADO',updated_at=now()
where estado='DESPACHADO';

alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  drop constraint if exists erp_solicitud_estado_ck;
alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  add constraint erp_solicitud_estado_ck check (
    estado in ('PENDIENTE','REVISADO','APROBADO','ANULADO')
  );

create or replace function public.appgt_erp_refrescar_solicitudes_orden_v1(
  p_empresa uuid,p_orden_numero text
)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_request record;
begin
  perform set_config('appgt.erp_receipt_context','1',true);
  for v_request in
    select solicitud_numero
    from public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT"
    where empresa_id=p_empresa and orden_numero=p_orden_numero
      and not eliminado and deleted_at is null
    union
    select solicitud_numero
    from public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
    where empresa_id=p_empresa and orden_numero=p_orden_numero
      and solicitud_numero is not null and not eliminado and deleted_at is null
  loop
    perform public.appgt_erp_refrescar_cabeceras_v2(
      p_empresa,p_orden_numero,v_request.solicitud_numero
    );
  end loop;
end
$$;

-- El disparador genérico de capacidades intenta recrear el campo técnico
-- ESTADO_APROBACION que esta instalación ya tiene. La actualización solo
-- cambia el catálogo de estados, por lo que se suspende únicamente aquí.
alter table public."MATRIZ_FORMATOS_APPGT"
  disable trigger appgt_aplicar_capacidades_formato_trigger;
update public."MATRIZ_FORMATOS_APPGT"
set flujo_estados='["PENDIENTE","REVISADO","APROBADO","ANULADO"]'::jsonb,
    updated_at=now()
where tabla_destino='ERP_SOLICITUDES_COMPRA_APPGT';
alter table public."MATRIZ_FORMATOS_APPGT"
  enable trigger appgt_aplicar_capacidades_formato_trigger;

with companies as (
  select distinct empresa_id from public."MATRIZ_FORMATOS_APPGT"
), fields(tabla,campo,etiqueta,tipo,tipo_ui,requerido,visible,visible_tabla,editable,orden) as (values
  ('ERP_ORDENES_COMPRA_APPGT','aprobado_at','Fecha y hora de aprobación','timestamptz','datetime',false,false,true,false,18),
  ('ERP_ORDENES_COMPRA_APPGT','anulado_at','Fecha y hora de anulación','timestamptz','datetime',false,false,true,false,19)
)
insert into public."MATRIZ_CAMPOS_FORMATO_APPGT"(
  id,empresa_id,tabla_destino,campo,etiqueta,tipo,tipo_ui,requerido,visible,
  visible_tabla,editable,orden,activo,created_at,updated_at,estado_sync,eliminado
)
select 'erp_approval_'||substr(md5(c.empresa_id::text||'|'||f.tabla||'|'||f.campo),1,24),
  c.empresa_id,f.tabla,f.campo,f.etiqueta,f.tipo,f.tipo_ui,f.requerido,
  f.visible,f.visible_tabla,f.editable,f.orden,true,now(),now(),'sincronizado',false
from companies c cross join fields f
on conflict (tabla_destino,campo) do update set
  etiqueta=excluded.etiqueta,tipo=excluded.tipo,tipo_ui=excluded.tipo_ui,
  requerido=excluded.requerido,visible=excluded.visible,
  visible_tabla=excluded.visible_tabla,editable=excluded.editable,
  orden=excluded.orden,activo=true,eliminado=false,updated_at=now();

select set_config('appgt.erp_receipt_context','0',true);
notify pgrst, 'reload schema';
commit;
