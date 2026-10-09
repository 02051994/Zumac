begin;

-- ============================================================================
-- Cierre funcional de compras y almacén.
-- Los nombres visibles se configuran en matrices; las relaciones y reglas usan
-- exclusivamente códigos, UUID y nombres físicos de columnas/tablas.
-- ============================================================================

alter table public."EMPRESAS_APPGT"
  add column if not exists email text;

alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  add column if not exists pdf_url text,
  add column if not exists pdf_generado_at timestamptz,
  add column if not exists pdf_estado text,
  add column if not exists despachado_por uuid references auth.users(id),
  add column if not exists despachado_at timestamptz,
  add column if not exists anulado_por uuid references auth.users(id),
  add column if not exists anulado_at timestamptz;

alter table public."ERP_ORDENES_COMPRA_APPGT"
  add column if not exists con_igv boolean not null default false,
  add column if not exists importe_bruto numeric(20,6) not null default 0,
  add column if not exists fecha_despachada date,
  add column if not exists pdf_url text,
  add column if not exists pdf_generado_at timestamptz,
  add column if not exists pdf_estado text,
  add column if not exists despachado_por uuid references auth.users(id),
  add column if not exists despachado_at timestamptz,
  add column if not exists anulado_por uuid references auth.users(id),
  add column if not exists anulado_at timestamptz;

alter table public."ERP_INGRESOS_ALMACEN_APPGT"
  add column if not exists pdf_url text,
  add column if not exists pdf_generado_at timestamptz,
  add column if not exists pdf_estado text;

alter table public."ERP_VALES_DESPACHO_APPGT"
  add column if not exists pdf_url text,
  add column if not exists pdf_generado_at timestamptz,
  add column if not exists pdf_estado text;

alter table public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  add column if not exists solicitud_numero text;

select set_config('appgt.erp_receipt_context','1',true);

update public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d
set solicitud_numero=o.solicitud_numero
from public."ERP_ORDENES_COMPRA_APPGT" o
where o.empresa_id=d.empresa_id and o.numero=d.orden_numero
  and d.solicitud_numero is null;

alter table public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"
  add column if not exists orden_numero text,
  add column if not exists solicitud_numero text;

update public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT" d
set orden_numero=i.orden_numero,
    solicitud_numero=od.solicitud_numero
from public."ERP_INGRESOS_ALMACEN_APPGT" i
left join public."ERP_ORDENES_COMPRA_DETALLE_APPGT" od
  on od.empresa_id=i.empresa_id and od.orden_numero=i.orden_numero
where i.empresa_id=d.empresa_id and i.numero=d.ingreso_numero
  and od.linea=d.orden_linea
  and (d.orden_numero is null or d.solicitud_numero is null);

select set_config('appgt.erp_receipt_context','0',true);

create table if not exists public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  orden_numero text not null,
  solicitud_numero text not null,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) default auth.uid(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  constraint erp_ocs_orden_fk foreign key (empresa_id,orden_numero)
    references public."ERP_ORDENES_COMPRA_APPGT"(empresa_id,numero) on delete cascade,
  constraint erp_ocs_solicitud_fk foreign key (empresa_id,solicitud_numero)
    references public."ERP_SOLICITUDES_COMPRA_APPGT"(empresa_id,numero),
  unique (empresa_id,orden_numero,solicitud_numero)
);

insert into public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT"(
  empresa_id,orden_numero,solicitud_numero
)
select distinct o.empresa_id,o.numero,o.solicitud_numero
from public."ERP_ORDENES_COMPRA_APPGT" o
where o.solicitud_numero is not null and btrim(o.solicitud_numero)<>''
on conflict (empresa_id,orden_numero,solicitud_numero) do nothing;

alter table public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT" enable row level security;
drop policy if exists erp_ocs_select on public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT";
create policy erp_ocs_select on public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT"
for select to authenticated using (
  empresa_id=public.appgt_empresa_actual_id()
  and public.appgt_can_view_table('ERP_ORDENES_COMPRA_APPGT')
);
grant select on public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT" to authenticated;
grant all on public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT" to service_role;

-- Códigos automáticos por empresa. El bloqueo transaccional evita duplicados
-- aun cuando dos usuarios guardan simultáneamente.
create or replace function public.appgt_erp_codigo_automatico_v1()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_next bigint;
begin
  if tg_table_name='ERP_PROVEEDORES_APPGT' then
    if nullif(btrim(coalesce(new.codigo,'')),'') is null then
      perform pg_advisory_xact_lock(hashtext(tg_table_name),hashtext(new.empresa_id::text));
      select coalesce(max((regexp_match(codigo,'^Prov-([0-9]+)$'))[1]::bigint),0)+1
      into v_next
      from public."ERP_PROVEEDORES_APPGT"
      where empresa_id=new.empresa_id and codigo~'^Prov-[0-9]+$';
      new.codigo:='Prov-'||v_next::text;
    end if;
  elsif tg_table_name='ERP_ORDENES_COMPRA_APPGT' then
    if nullif(btrim(coalesce(new.numero,'')),'') is null then
      perform pg_advisory_xact_lock(hashtext(tg_table_name),hashtext(new.empresa_id::text));
      select coalesce(max((regexp_match(numero,'^Comp-([0-9]+)$'))[1]::bigint),0)+1
      into v_next
      from public."ERP_ORDENES_COMPRA_APPGT"
      where empresa_id=new.empresa_id and numero~'^Comp-[0-9]+$';
      new.numero:='Comp-'||v_next::text;
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists erp_codigo_proveedor_automatico on public."ERP_PROVEEDORES_APPGT";
create trigger erp_codigo_proveedor_automatico
before insert on public."ERP_PROVEEDORES_APPGT"
for each row execute function public.appgt_erp_codigo_automatico_v1();

drop trigger if exists erp_codigo_oc_automatico on public."ERP_ORDENES_COMPRA_APPGT";
create trigger erp_codigo_oc_automatico
before insert on public."ERP_ORDENES_COMPRA_APPGT"
for each row execute function public.appgt_erp_codigo_automatico_v1();

-- La solicitud también queda despachada cuando todos sus ítems considerados en
-- órdenes de compra fueron recibidos. No se expone una acción manual para ello.
alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  drop constraint if exists erp_solicitud_estado_ck;
alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  add constraint erp_solicitud_estado_ck check (
    estado in ('PENDIENTE','REVISADO','APROBADO','DESPACHADO','ANULADO')
  );

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
      if not v_allowed then
        raise exception 'Sin permiso para eliminar registros % en estado %.',tg_table_name,old.estado
          using errcode='42501';
      end if;
    end if;
    return old;
  end if;

  new.estado:=upper(btrim(coalesce(new.estado,'PENDIENTE')));
  if tg_op='INSERT' then
    if auth.role()<>'service_role' and not public.appgt_puede_accion_estado_formato_v1(
      tg_table_name,new.estado,'create'
    ) then
      raise exception 'Sin permiso para crear registros % en estado %.',tg_table_name,new.estado
        using errcode='42501';
    end if;
    if new.estado<>'PENDIENTE' and auth.role()<>'service_role' then
      raise exception 'Todo documento nuevo debe iniciar en PENDIENTE.';
    end if;
    return new;
  end if;

  if auth.role()<>'service_role' and not v_pdf_context
     and not (v_receipt_context and tg_table_name in (
       'ERP_SOLICITUDES_COMPRA_APPGT','ERP_ORDENES_COMPRA_APPGT'
     ))
     and not (
       new.estado is distinct from old.estado and new.estado='ANULADO'
       and (
         public.appgt_can_update_table(tg_table_name)
         or public.appgt_can_delete_table(tg_table_name)
       )
     )
     and not public.appgt_puede_accion_estado_formato_v1(
       tg_table_name,old.estado,'update'
     ) then
    raise exception 'Sin permiso para editar registros % en estado %.',tg_table_name,old.estado
      using errcode='42501';
  end if;

  if new.estado is distinct from old.estado then
    if tg_table_name='ERP_SOLICITUDES_COMPRA_APPGT' then
      if not (
        (old.estado='PENDIENTE' and new.estado='REVISADO') or
        (old.estado='REVISADO' and new.estado='APROBADO') or
        (old.estado in ('PENDIENTE','REVISADO','APROBADO') and new.estado='ANULADO') or
        (v_receipt_context and old.estado in ('APROBADO','DESPACHADO')
          and new.estado in ('APROBADO','DESPACHADO'))
      ) then
        raise exception 'Transición no permitida: % -> %.',old.estado,new.estado;
      end if;
    elsif tg_table_name='ERP_ORDENES_COMPRA_APPGT' then
      if not (
        (old.estado='PENDIENTE' and new.estado='REVISADO') or
        (old.estado='REVISADO' and new.estado='APROBADO') or
        (old.estado in ('PENDIENTE','REVISADO','APROBADO') and new.estado='ANULADO') or
        (v_receipt_context and old.estado in ('APROBADO','DESPACHADO PARCIALMENTE','DESPACHADO')
          and new.estado in ('APROBADO','DESPACHADO PARCIALMENTE','DESPACHADO'))
      ) then
        raise exception 'Transición no permitida: % -> %.',old.estado,new.estado;
      end if;
    elsif tg_table_name='ERP_VALES_DESPACHO_APPGT' then
      if not (
        (old.estado='PENDIENTE' and new.estado='REVISADO') or
        (old.estado='REVISADO' and new.estado='APROBADO') or
        (old.estado='APROBADO' and new.estado='DESPACHADO') or
        (old.estado in ('PENDIENTE','REVISADO','APROBADO','DESPACHADO') and new.estado='ANULADO')
      ) then
        raise exception 'Transición no permitida: % -> %.',old.estado,new.estado;
      end if;
    end if;

    if new.estado='REVISADO' then
      new.revisado_por:=auth.uid();new.revisado_at:=clock_timestamp();
    elsif new.estado='APROBADO' and not v_receipt_context then
      new.aprobado_por:=auth.uid();new.aprobado_at:=clock_timestamp();
      if tg_table_name='ERP_SOLICITUDES_COMPRA_APPGT' then
        select count(*) into v_details from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" d
        where d.empresa_id=new.empresa_id and d.solicitud_numero=new.numero
          and not d.eliminado and d.deleted_at is null;
      elsif tg_table_name='ERP_ORDENES_COMPRA_APPGT' then
        select count(*) into v_details from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d
        where d.empresa_id=new.empresa_id and d.orden_numero=new.numero
          and not d.eliminado and d.deleted_at is null;
      elsif tg_table_name='ERP_VALES_DESPACHO_APPGT' then
        select count(*) into v_details from public."ERP_VALES_DESPACHO_DETALLE_APPGT" d
        where d.empresa_id=new.empresa_id and d.vale_numero=new.numero
          and not d.eliminado and d.deleted_at is null;
      end if;
      if coalesce(v_details,0)=0 then
        raise exception 'No se puede aprobar un documento sin artículos o insumos.';
      end if;
    elsif new.estado='DESPACHADO' and tg_table_name='ERP_VALES_DESPACHO_APPGT' then
      new.despachado_por:=auth.uid();new.despachado_at:=clock_timestamp();
    elsif new.estado='ANULADO' then
      new.anulado_por:=auth.uid();new.anulado_at:=clock_timestamp();
    end if;
  end if;
  return new;
end
$$;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'ERP_SOLICITUDES_COMPRA_APPGT','ERP_ORDENES_COMPRA_APPGT','ERP_VALES_DESPACHO_APPGT'
  ] loop
    execute format('drop trigger if exists erp_validar_flujo_v2 on public.%I',v_table);
    execute format('drop trigger if exists erp_validar_flujo_v3 on public.%I',v_table);
    execute format(
      'create trigger erp_validar_flujo_v3 before insert or update or delete on public.%I for each row execute function public.appgt_erp_validar_flujo_documento_v3()',
      v_table
    );
  end loop;
end
$$;

create or replace function public.erp_solicitudes_aprobadas_oc_v1()
returns jsonb
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select coalesce(jsonb_agg(
    to_jsonb(s)||jsonb_build_object(
      'detalles',coalesce((
        select jsonb_agg(jsonb_build_object(
          'linea',d.linea,'articulo_codigo',d.articulo_codigo,
          'descripcion',coalesce(d.descripcion,a.nombre),
          'cantidad_solicitada',d.cantidad_solicitada,
          'unidad_medida',d.unidad_medida,
          'proveedor_recomendado_codigo',d.proveedor_recomendado_codigo,
          'almacen_destino_codigo',d.almacen_destino_codigo,
          'precio_referencial',coalesce(a.costo_estandar,0),
          'observacion',d.observacion
        ) order by d.linea)
        from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" d
        join public."ERP_ARTICULOS_APPGT" a
          on a.empresa_id=d.empresa_id and a.codigo=d.articulo_codigo
        where d.empresa_id=s.empresa_id and d.solicitud_numero=s.numero
          and not d.eliminado and d.deleted_at is null
      ),'[]'::jsonb)
    ) order by s.fecha,s.numero
  ),'[]'::jsonb)
  from public."ERP_SOLICITUDES_COMPRA_APPGT" s
  where s.empresa_id=public.appgt_empresa_actual_id()
    and s.estado='APROBADO' and not s.eliminado and s.deleted_at is null
    and (auth.role()='service_role' or public.appgt_can_view_table('ERP_SOLICITUDES_COMPRA_APPGT'))
$$;

create or replace function public.erp_guardar_orden_compra_v1(
  p_codigo text,
  p_proveedor_codigo text,
  p_fecha_emision date,
  p_fecha_entrega date,
  p_moneda text,
  p_tipo_cambio numeric,
  p_condicion_pago text,
  p_almacen_codigo text,
  p_observacion text,
  p_con_igv boolean,
  p_descuento numeric,
  p_solicitudes jsonb,
  p_detalles jsonb
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
  v_item jsonb;
  v_article public."ERP_ARTICULOS_APPGT"%rowtype;
  v_line integer:=0;
  v_count integer:=0;
  v_qty numeric(20,6);
  v_price numeric(20,6);
  v_line_discount numeric(9,6);
  v_sum numeric(20,6):=0;
  v_gross numeric(20,6);
  v_discount numeric(20,6):=greatest(coalesce(p_descuento,0),0);
  v_subtotal numeric(20,6);
  v_tax numeric(20,6);
  v_total numeric(20,6);
  v_first_request text;
begin
  if v_empresa is null then raise exception 'No se pudo resolver la empresa activa' using errcode='42501'; end if;
  if btrim(coalesce(p_proveedor_codigo,''))='' then raise exception 'Seleccione un proveedor.'; end if;
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
      empresa_id,numero,solicitud_numero,proveedor_codigo,fecha_emision,
      fecha_entrega,moneda,tipo_cambio,condicion_pago,almacen_codigo,
      con_igv,importe_bruto,subtotal,descuento,impuesto,total,estado,observacion
    ) values (
      v_empresa,v_codigo,v_first_request,btrim(p_proveedor_codigo),
      coalesce(p_fecha_emision,current_date),p_fecha_entrega,
      upper(coalesce(nullif(btrim(p_moneda),''),'PEN')),coalesce(p_tipo_cambio,1),
      nullif(btrim(coalesce(p_condicion_pago,'')),''),nullif(btrim(coalesce(p_almacen_codigo,'')),''),
      coalesce(p_con_igv,false),0,0,v_discount,0,0,'PENDIENTE',
      nullif(btrim(coalesce(p_observacion,'')),'')
    ) returning numero into v_codigo;
  else
    if v_existing.estado not in ('PENDIENTE','REVISADO') then
      raise exception 'La orden % no se puede editar en estado %.',v_codigo,v_existing.estado;
    end if;
    update public."ERP_ORDENES_COMPRA_APPGT" set
      solicitud_numero=v_first_request,proveedor_codigo=btrim(p_proveedor_codigo),
      fecha_emision=coalesce(p_fecha_emision,current_date),fecha_entrega=p_fecha_entrega,
      moneda=upper(coalesce(nullif(btrim(p_moneda),''),'PEN')),
      tipo_cambio=coalesce(p_tipo_cambio,1),
      condicion_pago=nullif(btrim(coalesce(p_condicion_pago,'')),''),
      almacen_codigo=nullif(btrim(coalesce(p_almacen_codigo,'')),''),
      con_igv=coalesce(p_con_igv,false),descuento=v_discount,
      observacion=nullif(btrim(coalesce(p_observacion,'')),''),updated_by=auth.uid()
    where id=v_existing.id;
    update public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
    set eliminado=true,deleted_at=clock_timestamp(),updated_by=auth.uid()
    where empresa_id=v_empresa and orden_numero=v_codigo
      and not eliminado and deleted_at is null;
    update public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT"
    set eliminado=true,deleted_at=clock_timestamp()
    where empresa_id=v_empresa and orden_numero=v_codigo
      and not eliminado and deleted_at is null;
  end if;

  select coalesce(max(linea),0) into v_line
  from public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  where empresa_id=v_empresa and orden_numero=v_codigo;

  for v_item in select value from jsonb_array_elements(p_solicitudes) loop
    if not exists (
      select 1 from public."ERP_SOLICITUDES_COMPRA_APPGT" s
      where s.empresa_id=v_empresa
        and s.numero=nullif(btrim(coalesce(v_item->>'numero',v_item#>>'{}')),'')
        and s.estado='APROBADO' and not s.eliminado and s.deleted_at is null
    ) then
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
    if not exists (
      select 1 from public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT" os
      where os.empresa_id=v_empresa and os.orden_numero=v_codigo
        and os.solicitud_numero=nullif(btrim(coalesce(v_item->>'solicitud_numero','')),'')
        and not os.eliminado and os.deleted_at is null
    ) then
      raise exception 'Cada ítem debe pertenecer a una solicitud agregada a la orden.';
    end if;
    select * into v_article from public."ERP_ARTICULOS_APPGT"
    where empresa_id=v_empresa and codigo=v_item->>'articulo_codigo'
      and not eliminado and deleted_at is null;
    if v_article.id is null then raise exception 'Artículo no encontrado: %',v_item->>'articulo_codigo'; end if;
    v_line:=v_line+1;
    v_count:=v_count+1;
    insert into public."ERP_ORDENES_COMPRA_DETALLE_APPGT"(
      empresa_id,orden_numero,linea,solicitud_numero,solicitud_linea,
      articulo_codigo,descripcion,cantidad,cantidad_solicitada,unidad_medida,
      precio_unitario,descuento_porcentaje,impuesto_porcentaje,centro_costo,lote_agricola
    ) values (
      v_empresa,v_codigo,v_line,nullif(btrim(coalesce(v_item->>'solicitud_numero','')),''),
      nullif(v_item->>'solicitud_linea','')::integer,v_article.codigo,
      coalesce(nullif(btrim(coalesce(v_item->>'descripcion','')),''),v_article.nombre),
      v_qty,coalesce(nullif(v_item->>'cantidad_solicitada','')::numeric,v_qty),
      coalesce(nullif(btrim(coalesce(v_item->>'unidad_medida','')),''),v_article.unidad_medida),
      v_price,v_line_discount,case when coalesce(p_con_igv,false) then 0 else 18 end,
      nullif(btrim(coalesce(v_item->>'centro_costo','')),''),
      nullif(btrim(coalesce(v_item->>'lote_agricola','')),'')
    );
    v_sum:=v_sum+round(v_qty*v_price*(1-v_line_discount/100),6);
  end loop;

  if v_discount>v_sum then raise exception 'El descuento no puede superar el importe de los ítems.'; end if;
  if coalesce(p_con_igv,false) then
    v_total:=round(v_sum-v_discount,6);
    v_subtotal:=round(v_total/1.18,6);
    v_tax:=round(v_total-v_subtotal,6);
    v_gross:=round(v_subtotal+v_discount,6);
  else
    v_gross:=round(v_sum,6);
    v_subtotal:=round(v_gross-v_discount,6);
    v_tax:=round(v_subtotal*0.18,6);
    v_total:=round(v_subtotal+v_tax,6);
  end if;
  update public."ERP_ORDENES_COMPRA_APPGT" set
    importe_bruto=v_gross,descuento=v_discount,subtotal=v_subtotal,
    impuesto=v_tax,total=v_total
  where empresa_id=v_empresa and numero=v_codigo;

  return jsonb_build_object(
    'guardado',true,'codigo',v_codigo,'estado','PENDIENTE','lineas',v_count,
    'importe_bruto',v_gross,'descuento',v_discount,'subtotal',v_subtotal,
    'impuesto',v_tax,'total',v_total
  );
end
$$;

create or replace function public.appgt_erp_refrescar_solicitudes_orden_v1(
  p_empresa uuid,p_orden_numero text
)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_request record; v_completed boolean;
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
    select coalesce(bool_and(d.cantidad_despachada>=d.cantidad),false)
    into v_completed
    from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d
    join public."ERP_ORDENES_COMPRA_APPGT" o
      on o.empresa_id=d.empresa_id and o.numero=d.orden_numero
    where d.empresa_id=p_empresa and d.solicitud_numero=v_request.solicitud_numero
      and o.estado<>'ANULADO' and not o.eliminado and o.deleted_at is null
      and not d.eliminado and d.deleted_at is null;
    update public."ERP_SOLICITUDES_COMPRA_APPGT"
    set estado=case when v_completed then 'DESPACHADO' else 'APROBADO' end,
        despachado_por=case when v_completed then auth.uid() else null end,
        despachado_at=case when v_completed then clock_timestamp() else null end
    where empresa_id=p_empresa and numero=v_request.solicitud_numero
      and estado in ('APROBADO','DESPACHADO');
  end loop;
end
$$;

-- Reemplaza la operación de ingreso para conservar códigos de OC/solicitud en
-- cada línea, fecha del último ingreso y estados automáticos de ambos documentos.
create or replace function public.erp_registrar_ingreso_compra_v1(
  p_orden_numero text,p_fecha date,p_guia_remision text,p_detalles jsonb,
  p_observacion text default null
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
begin
  if v_empresa is null then raise exception 'No se pudo resolver la empresa activa' using errcode='42501'; end if;
  if auth.role()<>'service_role' and not public.appgt_can_insert_table('ERP_INGRESOS_ALMACEN_APPGT') then
    raise exception 'Sin permiso para registrar ingresos de almacén' using errcode='42501';
  end if;
  if btrim(coalesce(p_guia_remision,''))='' then raise exception 'Debe ingresar el número de guía de remisión.'; end if;
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
    proveedor_ruc,almacen_codigo,guia_remision,estado,observacion
  ) values (
    v_empresa,v_ingreso,coalesce(p_fecha,current_date),v_order.numero,
    v_order.proveedor_codigo,v_order.proveedor_ruc,v_order.almacen_codigo,
    btrim(p_guia_remision),'CONFIRMADO',nullif(btrim(coalesce(p_observacion,'')),'')
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
      cantidad_pendiente_antes,cantidad_recibida,costo_unitario,lote,fecha_vencimiento
    ) values (
      v_empresa,v_ingreso,v_ingreso_line,v_order.numero,v_line.solicitud_numero,
      v_line.linea,v_line.articulo_codigo,v_line.descripcion,v_line.unidad_medida,
      v_line.cantidad,v_line.cantidad-v_line.cantidad_despachada,v_qty,
      v_line.precio_unitario,nullif(btrim(coalesce(v_detail->>'lote','')),''),
      nullif(v_detail->>'fecha_vencimiento','')::date
    );
    insert into public."ERP_MOVIMIENTOS_INVENTARIO_APPGT"(
      empresa_id,numero,fecha,almacen_codigo,articulo_codigo,lote,
      fecha_vencimiento,tipo_movimiento,direccion,cantidad,costo_unitario,
      documento_origen_tipo,documento_origen_codigo,observacion,estado
    ) values (
      v_empresa,'ENT-'||v_ingreso||'-'||lpad(v_ingreso_line::text,3,'0'),
      clock_timestamp(),v_order.almacen_codigo,v_line.articulo_codigo,
      nullif(btrim(coalesce(v_detail->>'lote','')),''),
      nullif(v_detail->>'fecha_vencimiento','')::date,'INGRESO_COMPRA',1,v_qty,
      v_line.precio_unitario,'INGRESO_COMPRA',v_ingreso,
      'OC '||v_order.numero||' / Solicitud '||coalesce(v_line.solicitud_numero,'-')||
        ' / Guía '||p_guia_remision,'CONFIRMADO'
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
      'orden_numero',v_order.numero,'guia_remision',p_guia_remision,
      'estado_orden',v_new_state
    )
  ) on conflict do nothing;
  return jsonb_build_object(
    'guardado',true,'ingreso_numero',v_ingreso,'orden_numero',v_order.numero,
    'estado_orden',v_new_state,'lineas_recibidas',v_ingreso_line
  );
end
$$;

create or replace function public.erp_anular_ingreso_compra_v1(p_ingreso_numero text)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa uuid:=public.appgt_empresa_actual_id();
  v_header public."ERP_INGRESOS_ALMACEN_APPGT"%rowtype;
  v_row record; v_state text; v_last_date date;
  v_last_actor uuid; v_last_at timestamptz;
begin
  select * into v_header from public."ERP_INGRESOS_ALMACEN_APPGT"
  where empresa_id=v_empresa and numero=p_ingreso_numero for update;
  if v_header.id is null then raise exception 'Ingreso no encontrado.'; end if;
  if v_header.estado<>'CONFIRMADO' then raise exception 'El ingreso ya fue anulado.'; end if;
  if auth.role()<>'service_role' and not public.appgt_puede_accion_estado_formato_v1(
    'ERP_INGRESOS_ALMACEN_APPGT','CONFIRMADO','delete'
  ) then raise exception 'Sin permiso para anular ingresos.' using errcode='42501'; end if;
  perform set_config('appgt.erp_receipt_context','1',true);
  update public."ERP_MOVIMIENTOS_INVENTARIO_APPGT" set estado='ANULADO'
  where empresa_id=v_empresa and documento_origen_tipo='INGRESO_COMPRA'
    and documento_origen_codigo=v_header.numero and estado='CONFIRMADO';
  for v_row in select * from public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"
    where empresa_id=v_empresa and ingreso_numero=v_header.numero
      and not eliminado and deleted_at is null
  loop
    update public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
    set cantidad_despachada=greatest(cantidad_despachada-v_row.cantidad_recibida,0),
        cantidad_recibida=greatest(cantidad_recibida-v_row.cantidad_recibida,0)
    where empresa_id=v_empresa and orden_numero=v_header.orden_numero
      and linea=v_row.orden_linea;
  end loop;
  update public."ERP_INGRESOS_ALMACEN_APPGT"
  set estado='ANULADO',anulado_por=auth.uid(),anulado_at=clock_timestamp()
  where id=v_header.id;
  select case
    when coalesce(sum(cantidad_despachada),0)=0 then 'APROBADO'
    when bool_and(cantidad_despachada>=cantidad) then 'DESPACHADO'
    else 'DESPACHADO PARCIALMENTE' end
  into v_state from public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  where empresa_id=v_empresa and orden_numero=v_header.orden_numero
    and not eliminado and deleted_at is null;
  select max(fecha_ingreso) into v_last_date
  from public."ERP_INGRESOS_ALMACEN_APPGT"
  where empresa_id=v_empresa and orden_numero=v_header.orden_numero
    and estado='CONFIRMADO' and not eliminado and deleted_at is null;
  select confirmado_por,confirmado_at into v_last_actor,v_last_at
  from public."ERP_INGRESOS_ALMACEN_APPGT"
  where empresa_id=v_empresa and orden_numero=v_header.orden_numero
    and estado='CONFIRMADO' and not eliminado and deleted_at is null
  order by confirmado_at desc limit 1;
  update public."ERP_ORDENES_COMPRA_APPGT"
  set estado=v_state,fecha_despachada=v_last_date,
      despachado_por=v_last_actor,despachado_at=v_last_at
  where empresa_id=v_empresa and numero=v_header.orden_numero;
  perform public.appgt_erp_refrescar_solicitudes_orden_v1(v_empresa,v_header.orden_numero);
  update public."ERP_EVENTOS_INTEGRACION_APPGT" set estado='ANULADO'
  where empresa_id=v_empresa and documento_tipo='INGRESO_COMPRA'
    and documento_numero=v_header.numero;
  return jsonb_build_object('anulado',true,'estado_orden',v_state);
end
$$;

-- Registro seguro de PDFs: desde APROBADO para documentos con flujo; el ingreso
-- puede imprimirse confirmado o anulado.
create or replace function public.erp_registrar_pdf_documento_v1(
  p_tabla text,p_numero text,p_pdf_url text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa uuid:=public.appgt_empresa_actual_id();
  v_state text;
  v_existing_pdf text;
  v_table text:=upper(btrim(p_tabla));
begin
  if v_table not in (
    'ERP_SOLICITUDES_COMPRA_APPGT','ERP_ORDENES_COMPRA_APPGT',
    'ERP_INGRESOS_ALMACEN_APPGT','ERP_VALES_DESPACHO_APPGT'
  ) then raise exception 'Documento ERP no permitido.'; end if;
  execute format('select estado,pdf_url from public.%I where empresa_id=$1 and numero=$2 and not eliminado and deleted_at is null',v_table)
    into v_state,v_existing_pdf using v_empresa,p_numero;
  if v_state is null then raise exception 'Documento no encontrado.'; end if;
  if v_table<>'ERP_INGRESOS_ALMACEN_APPGT'
     and v_state not in ('APROBADO','DESPACHADO PARCIALMENTE','DESPACHADO')
     and not (v_state='ANULADO' and nullif(btrim(coalesce(v_existing_pdf,'')),'') is not null) then
    raise exception 'El PDF se genera desde el estado APROBADO.';
  end if;
  if p_pdf_url !~ ('^storage://documentos-erp/'||v_empresa::text||'/') then
    raise exception 'Ruta de PDF ERP inválida.';
  end if;
  perform set_config('appgt.erp_pdf_context','1',true);
  perform set_config('appgt.erp_receipt_context','1',true);
  execute format('update public.%I set pdf_url=$1,pdf_generado_at=clock_timestamp(),pdf_estado=$2 where empresa_id=$3 and numero=$4',v_table)
    using p_pdf_url,v_state,v_empresa,p_numero;
  return jsonb_build_object('guardado',true,'tabla',v_table,'numero',p_numero,'estado',v_state,'pdf_url',p_pdf_url);
end
$$;

revoke all on function public.erp_solicitudes_aprobadas_oc_v1() from public,anon;
revoke all on function public.erp_guardar_orden_compra_v1(text,text,date,date,text,numeric,text,text,text,boolean,numeric,jsonb,jsonb) from public,anon;
revoke all on function public.erp_registrar_pdf_documento_v1(text,text,text) from public,anon;
grant execute on function public.erp_solicitudes_aprobadas_oc_v1() to authenticated,service_role;
grant execute on function public.erp_guardar_orden_compra_v1(text,text,date,date,text,numeric,text,text,text,boolean,numeric,jsonb,jsonb) to authenticated,service_role;
grant execute on function public.erp_registrar_pdf_documento_v1(text,text,text) to authenticated,service_role;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('documentos-erp','documentos-erp',false,15728640,array['application/pdf']::text[])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists documentos_erp_select on storage.objects;
create policy documentos_erp_select on storage.objects for select to authenticated using (
  bucket_id='documentos-erp'
  and split_part(name,'/',1)=public.appgt_empresa_actual_id()::text
);
drop policy if exists documentos_erp_insert on storage.objects;
create policy documentos_erp_insert on storage.objects for insert to authenticated with check (
  bucket_id='documentos-erp'
  and split_part(name,'/',1)=public.appgt_empresa_actual_id()::text
);
drop policy if exists documentos_erp_update on storage.objects;
create policy documentos_erp_update on storage.objects for update to authenticated using (
  bucket_id='documentos-erp'
  and split_part(name,'/',1)=public.appgt_empresa_actual_id()::text
) with check (
  bucket_id='documentos-erp'
  and split_part(name,'/',1)=public.appgt_empresa_actual_id()::text
);

-- Matrices: detalles embebidos, orden de compra especial y campos visibles.
update public."MATRIZ_FORMATOS_APPGT"
set tabla_visible_app=false,updated_at=now()
where tabla_destino in (
  'ERP_SOLICITUDES_COMPRA_DETALLE_APPGT','ERP_ORDENES_COMPRA_DETALLE_APPGT',
  'ERP_INGRESOS_ALMACEN_DETALLE_APPGT','ERP_VALES_DESPACHO_DETALLE_APPGT'
);

update public."MATRIZ_FORMATOS_APPGT"
set flujo_estados='["PENDIENTE","REVISADO","APROBADO","DESPACHADO","ANULADO"]'::jsonb,
    workflow_enabled=true,approvals_enabled=true,updated_at=now()
where tabla_destino='ERP_SOLICITUDES_COMPRA_APPGT';

insert into public."MATRIZ_FORMATOS_ESPECIALES_APPGT"(
  id,empresa_id,modulo_id,formato_id,tipo_pantalla,descripcion,activo,orden,
  created_at,updated_at,deleted_at,estado_sync,eliminado
)
select 'erp_special_orden_compra_'||substr(md5(f.empresa_id::text),1,10),
  f.empresa_id,f.modulo_id,f.id,'erp_orden_compra','Orden de Compra',true,0,
  now(),now(),null,'sincronizado',false
from public."MATRIZ_FORMATOS_APPGT" f
where f.tabla_destino='ERP_ORDENES_COMPRA_APPGT'
on conflict (formato_id) do update set
  modulo_id=excluded.modulo_id,tipo_pantalla=excluded.tipo_pantalla,
  descripcion=excluded.descripcion,activo=true,deleted_at=null,eliminado=false,
  updated_at=now();

with companies as (
  select distinct empresa_id from public."MATRIZ_FORMATOS_APPGT"
), fields(tabla,campo,etiqueta,tipo,tipo_ui,requerido,visible,visible_tabla,editable,orden) as (values
  ('ERP_SOLICITUDES_COMPRA_APPGT','pdf_url','PDF generado','text','pdf',false,false,true,false,90),
  ('ERP_SOLICITUDES_COMPRA_APPGT','pdf_generado_at','Fecha de PDF','timestamptz','datetime',false,false,true,false,91),
  ('ERP_SOLICITUDES_COMPRA_APPGT','pdf_estado','Estado del PDF','text','readonly',false,false,false,false,92),
  ('ERP_ORDENES_COMPRA_APPGT','con_igv','Con IGV','boolean','checkbox',false,true,true,true,12),
  ('ERP_ORDENES_COMPRA_APPGT','importe_bruto','Importe bruto','numeric','number',false,true,true,false,13),
  ('ERP_ORDENES_COMPRA_APPGT','fecha_despachada','Fecha despachada','date','date',false,false,true,false,14),
  ('ERP_ORDENES_COMPRA_APPGT','pdf_url','PDF generado','text','pdf',false,false,true,false,90),
  ('ERP_ORDENES_COMPRA_APPGT','pdf_generado_at','Fecha de PDF','timestamptz','datetime',false,false,true,false,91),
  ('ERP_ORDENES_COMPRA_APPGT','pdf_estado','Estado del PDF','text','readonly',false,false,false,false,92),
  ('ERP_INGRESOS_ALMACEN_APPGT','pdf_url','PDF generado','text','pdf',false,false,true,false,90),
  ('ERP_INGRESOS_ALMACEN_APPGT','pdf_generado_at','Fecha de PDF','timestamptz','datetime',false,false,true,false,91),
  ('ERP_INGRESOS_ALMACEN_APPGT','pdf_estado','Estado del PDF','text','readonly',false,false,false,false,92),
  ('ERP_VALES_DESPACHO_APPGT','pdf_url','PDF generado','text','pdf',false,false,true,false,90),
  ('ERP_VALES_DESPACHO_APPGT','pdf_generado_at','Fecha de PDF','timestamptz','datetime',false,false,true,false,91),
  ('ERP_VALES_DESPACHO_APPGT','pdf_estado','Estado del PDF','text','readonly',false,false,false,false,92),
  ('ERP_ORDENES_COMPRA_DETALLE_APPGT','solicitud_numero','Código de solicitud','text','readonly',false,false,true,false,4),
  ('ERP_INGRESOS_ALMACEN_DETALLE_APPGT','orden_numero','Código de orden de compra','text','readonly',false,false,true,false,3),
  ('ERP_INGRESOS_ALMACEN_DETALLE_APPGT','solicitud_numero','Código de solicitud de pedido','text','readonly',false,false,true,false,4)
)
insert into public."MATRIZ_CAMPOS_FORMATO_APPGT"(
  id,empresa_id,tabla_destino,campo,etiqueta,tipo,tipo_ui,requerido,visible,
  visible_tabla,editable,orden,activo,created_at,updated_at,estado_sync,eliminado
)
select 'erp_field_'||substr(md5(c.empresa_id::text||'|'||f.tabla||'|'||f.campo),1,24),
  c.empresa_id,f.tabla,f.campo,f.etiqueta,f.tipo,f.tipo_ui,f.requerido,
  f.visible,f.visible_tabla,f.editable,f.orden,true,now(),now(),'sincronizado',false
from companies c cross join fields f
on conflict (tabla_destino,campo) do update set
  etiqueta=excluded.etiqueta,tipo=excluded.tipo,tipo_ui=excluded.tipo_ui,
  requerido=excluded.requerido,visible=excluded.visible,
  visible_tabla=excluded.visible_tabla,editable=excluded.editable,
  orden=excluded.orden,activo=true,eliminado=false,updated_at=now();

update public."MATRIZ_CAMPOS_FORMATO_APPGT" set
  etiqueta=case
    when tabla_destino='ERP_PROVEEDORES_APPGT' and campo='codigo' then 'Código'
    when tabla_destino='ERP_ORDENES_COMPRA_APPGT' and campo='numero' then 'Código'
    else etiqueta end,
  tipo_ui='readonly',requerido=false,editable=false,updated_at=now()
where (tabla_destino='ERP_PROVEEDORES_APPGT' and campo='codigo')
   or (tabla_destino='ERP_ORDENES_COMPRA_APPGT' and campo='numero');

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set id_campo_dropdown='[PENDIENTE;REVISADO;APROBADO;DESPACHADO;ANULADO]',
    editable=false,updated_at=now()
where tabla_destino='ERP_SOLICITUDES_COMPRA_APPGT' and campo='estado';

update public."PERMISOS_DE_USUARIOS_APPGT" p
set permisos_estado=jsonb_set(
  coalesce(p.permisos_estado,'{}'::jsonb),'{DESPACHADO}',
  jsonb_build_object('view',p.can_view,'create',false,'update',false,'delete',false),true
),updated_at=now()
where p.tabla_destino='ERP_SOLICITUDES_COMPRA_APPGT';

create index if not exists erp_oc_solicitud_idx
  on public."ERP_ORDENES_COMPRA_DETALLE_APPGT"(empresa_id,solicitud_numero);
create index if not exists erp_ingreso_solicitud_idx
  on public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"(empresa_id,solicitud_numero);
create index if not exists erp_ocs_request_idx
  on public."ERP_ORDENES_COMPRA_SOLICITUDES_APPGT"(empresa_id,solicitud_numero);

notify pgrst, 'reload schema';
commit;
