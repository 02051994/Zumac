begin;

-- La recuperación de estados puede activar propagaciones internas hacia las
-- líneas. Se habilita el mismo contexto controlado usado por las migraciones
-- de trazabilidad para que esas actualizaciones derivadas no sean rechazadas.
select set_config('appgt.erp_receipt_context','1',true);

-- Los cuatro documentos ERP ya poseen un estado operativo propio. El campo
-- técnico ESTADO_APROBACION fue agregado por la capacidad genérica y provocó
-- una doble fuente de verdad: la acción actualizaba ese campo, mientras la
-- grilla, los triggers y el stock trabajaban con estado.
create temporary table appgt_erp_estado_reconcile (
  tabla text not null,
  id uuid not null,
  estado_objetivo text not null,
  primary key (tabla,id)
) on commit drop;

do $$
declare
  v_table text;
  v_detail_table text;
  v_detail_fk text;
begin
  foreach v_table in array array[
    'ERP_SOLICITUDES_COMPRA_APPGT',
    'ERP_ORDENES_COMPRA_APPGT'
  ] loop
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=v_table
        and column_name='ESTADO_APROBACION'
    ) then
      if v_table='ERP_SOLICITUDES_COMPRA_APPGT' then
        v_detail_table:='ERP_SOLICITUDES_COMPRA_DETALLE_APPGT';
        v_detail_fk:='solicitud_numero';
      else
        v_detail_table:='ERP_ORDENES_COMPRA_DETALLE_APPGT';
        v_detail_fk:='orden_numero';
      end if;

      execute format($sql$
        insert into appgt_erp_estado_reconcile(tabla,id,estado_objetivo)
        select %L,h.id,upper(btrim(h."ESTADO_APROBACION"))
        from public.%I h
        where upper(btrim(coalesce(h.estado,''))) in ('PENDIENTE','REVISADO')
          and upper(btrim(coalesce(h."ESTADO_APROBACION",'')))
              in ('REVISADO','APROBADO','ANULADO')
          and exists (
            select 1 from public.%I d
            where d.empresa_id=h.empresa_id and d.%I=h.numero
              and not coalesce(d.eliminado,false) and d.deleted_at is null
          )
        on conflict do nothing
      $sql$,v_table,v_table,v_detail_table,v_detail_fk);
    end if;
  end loop;
end
$$;

create or replace function public.appgt_erp_sincronizar_estado_aprobacion_v1()
returns trigger
language plpgsql
set search_path=public,pg_temp
as $$
begin
  -- jsonb_populate_record permite reutilizar el trigger sin acoplarlo al tipo
  -- concreto de cada cabecera ERP.
  new:=jsonb_populate_record(
    new,
    jsonb_build_object(
      'ESTADO_APROBACION',
      upper(btrim(coalesce(to_jsonb(new)->>'estado','PENDIENTE')))
    )
  );
  return new;
end
$$;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'ERP_SOLICITUDES_COMPRA_APPGT',
    'ERP_ORDENES_COMPRA_APPGT',
    'ERP_INGRESOS_ALMACEN_APPGT',
    'ERP_VALES_DESPACHO_APPGT'
  ] loop
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=v_table and column_name='estado'
    ) and exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=v_table
        and column_name='ESTADO_APROBACION'
    ) then
      execute format(
        'drop trigger if exists appgt_erp_estado_unico_v1 on public.%I',
        v_table
      );
      execute format(
        'create trigger appgt_erp_estado_unico_v1 '
        'before insert or update of estado,"ESTADO_APROBACION" on public.%I '
        'for each row execute function public.appgt_erp_sincronizar_estado_aprobacion_v1()',
        v_table
      );
    end if;
  end loop;
end
$$;

-- Recupera las acciones que el cliente anterior informó como exitosas pero
-- dejó únicamente en el campo técnico. Se recorren los estados válidos para
-- que las reglas de transición y los controles de detalle sigan ejecutándose.
update public."ERP_SOLICITUDES_COMPRA_APPGT" h
set estado='REVISADO'
from appgt_erp_estado_reconcile r
where r.tabla='ERP_SOLICITUDES_COMPRA_APPGT' and r.id=h.id
  and h.estado='PENDIENTE'
  and r.estado_objetivo in ('REVISADO','APROBADO');

update public."ERP_SOLICITUDES_COMPRA_APPGT" h
set estado='APROBADO'
from appgt_erp_estado_reconcile r
where r.tabla='ERP_SOLICITUDES_COMPRA_APPGT' and r.id=h.id
  and h.estado='REVISADO' and r.estado_objetivo='APROBADO';

update public."ERP_SOLICITUDES_COMPRA_APPGT" h
set estado='ANULADO'
from appgt_erp_estado_reconcile r
where r.tabla='ERP_SOLICITUDES_COMPRA_APPGT' and r.id=h.id
  and h.estado in ('PENDIENTE','REVISADO','APROBADO')
  and r.estado_objetivo='ANULADO';

update public."ERP_ORDENES_COMPRA_APPGT" h
set estado='REVISADO'
from appgt_erp_estado_reconcile r
where r.tabla='ERP_ORDENES_COMPRA_APPGT' and r.id=h.id
  and h.estado='PENDIENTE'
  and r.estado_objetivo in ('REVISADO','APROBADO');

update public."ERP_ORDENES_COMPRA_APPGT" h
set estado='APROBADO'
from appgt_erp_estado_reconcile r
where r.tabla='ERP_ORDENES_COMPRA_APPGT' and r.id=h.id
  and h.estado='REVISADO' and r.estado_objetivo='APROBADO';

update public."ERP_ORDENES_COMPRA_APPGT" h
set estado='ANULADO'
from appgt_erp_estado_reconcile r
where r.tabla='ERP_ORDENES_COMPRA_APPGT' and r.id=h.id
  and h.estado in ('PENDIENTE','REVISADO','APROBADO')
  and r.estado_objetivo='ANULADO';

-- Cualquier discrepancia restante se resuelve a favor de estado, que es el
-- campo consumido por negocio, inventario, trazabilidad y las grillas.
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'ERP_SOLICITUDES_COMPRA_APPGT',
    'ERP_ORDENES_COMPRA_APPGT',
    'ERP_INGRESOS_ALMACEN_APPGT',
    'ERP_VALES_DESPACHO_APPGT'
  ] loop
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=v_table
        and column_name='ESTADO_APROBACION'
    ) then
      execute format(
        'update public.%I set "ESTADO_APROBACION"=estado '
        'where "ESTADO_APROBACION" is distinct from estado',
        v_table
      );
    end if;
  end loop;
end
$$;

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set visible=false,visible_tabla=false,editable=false,updated_at=now()
where public.appgt_normalizar_clave(tabla_destino) in (
    public.appgt_normalizar_clave('ERP_SOLICITUDES_COMPRA_APPGT'),
    public.appgt_normalizar_clave('ERP_ORDENES_COMPRA_APPGT'),
    public.appgt_normalizar_clave('ERP_INGRESOS_ALMACEN_APPGT'),
    public.appgt_normalizar_clave('ERP_VALES_DESPACHO_APPGT')
  )
  and public.appgt_normalizar_clave(campo)
      =public.appgt_normalizar_clave('ESTADO_APROBACION');

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set visible_tabla=true,editable=false,updated_at=now()
where public.appgt_normalizar_clave(tabla_destino) in (
    public.appgt_normalizar_clave('ERP_SOLICITUDES_COMPRA_APPGT'),
    public.appgt_normalizar_clave('ERP_ORDENES_COMPRA_APPGT'),
    public.appgt_normalizar_clave('ERP_INGRESOS_ALMACEN_APPGT'),
    public.appgt_normalizar_clave('ERP_VALES_DESPACHO_APPGT')
  )
  and public.appgt_normalizar_clave(campo)
      =public.appgt_normalizar_clave('estado');

notify pgrst, 'reload schema';
select set_config('appgt.erp_receipt_context','0',true);
commit;
