begin;

-- ============================================================================
-- ERP integrado: compras -> ingresos -> stock -> despacho -> costos.
-- Incluye permisos por estado y metadatos para que el runtime siga siendo
-- declarativo y multiempresa.
-- ============================================================================

alter table public."PERMISOS_DE_USUARIOS_APPGT"
  add column if not exists permisos_estado jsonb not null default '{}'::jsonb;

alter table public."PERMISOS_DE_USUARIOS_APPGT"
  drop constraint if exists appgt_permisos_estado_object_ck;
alter table public."PERMISOS_DE_USUARIOS_APPGT"
  add constraint appgt_permisos_estado_object_ck
  check (jsonb_typeof(permisos_estado) = 'object');

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
          when p.permisos_estado <> '{}'::jsonb then coalesce(
            (p.permisos_estado
              -> upper(btrim(coalesce(p_estado,'')))
              ->> lower(btrim(coalesce(p_accion,''))))::boolean,
            false
          )
          when lower(btrim(coalesce(p_accion,''))) = 'view'
            then coalesce(p.can_view,false)
          when lower(btrim(coalesce(p_accion,''))) in ('create','insert')
            then coalesce(p.can_insert,false)
          when lower(btrim(coalesce(p_accion,''))) in ('update','edit')
            then coalesce(p.can_update,false)
              or (upper(btrim(coalesce(p_estado,'')))='PENDIENTE' and coalesce(p.can_review,false))
              or (upper(btrim(coalesce(p_estado,'')))='REVISADO' and coalesce(p.can_approve,false))
          when lower(btrim(coalesce(p_accion,''))) = 'delete'
            then coalesce(p.can_delete,false)
          else false
        end
    )
  end
$$;

create or replace function public.appgt_guardar_permisos_estado_formatos_v1(
  p_user_id uuid,
  p_permisos jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa_id uuid:=public.appgt_empresa_actual_id();
  v_actor_role text:=public.appgt_rol_empresa_actual();
  v_item jsonb;
  v_format_id text;
  v_states jsonb;
  v_normalized jsonb;
  v_state record;
  v_permission_id text;
  v_own_states jsonb;
  v_count integer:=0;
begin
  if v_empresa_id is null or v_actor_role not in ('ADMIN','GESTOR') then
    raise exception 'permission manager role required' using errcode='42501';
  end if;
  if not public.appgt_actor_puede_gestionar_usuario(v_empresa_id,p_user_id) then
    raise exception 'target user is outside delegated authority' using errcode='42501';
  end if;
  if jsonb_typeof(p_permisos) <> 'array' then
    raise exception 'p_permisos must be a JSON array';
  end if;

  for v_item in select value from jsonb_array_elements(p_permisos)
  loop
    v_format_id:=coalesce(v_item->>'formato_id',v_item->>'formato');
    v_states:=coalesce(v_item->'permisos_estado','{}'::jsonb);
    if jsonb_typeof(v_states) <> 'object' then
      raise exception 'permisos_estado must be a JSON object';
    end if;

    select p.id into v_permission_id
    from public."PERMISOS_DE_USUARIOS_APPGT" p
    where p.empresa_id=v_empresa_id and p.user_id=p_user_id
      and p.formato=v_format_id and coalesce(p.activo,true)
      and not coalesce(p.eliminado,false) and p.deleted_at is null
    order by p.updated_at desc nulls last limit 1;
    if v_permission_id is null then
      raise exception 'format permission must be saved before state permissions: %',v_format_id;
    end if;

    select coalesce(jsonb_object_agg(
      upper(btrim(v_state.key)),
      jsonb_build_object(
        'view',coalesce((v_state.value->>'view')::boolean,false),
        'create',coalesce((v_state.value->>'create')::boolean,false),
        'update',coalesce((v_state.value->>'update')::boolean,false),
        'delete',coalesce((v_state.value->>'delete')::boolean,false)
      )
    ),'{}'::jsonb) into v_normalized
    from jsonb_each(v_states) v_state
    where btrim(v_state.key)<>'' and jsonb_typeof(v_state.value)='object';

    if v_actor_role='GESTOR' then
      select coalesce(p.permisos_estado,'{}'::jsonb) into v_own_states
      from public."PERMISOS_DE_USUARIOS_APPGT" p
      where p.empresa_id=v_empresa_id and p.user_id=auth.uid()
        and p.formato=v_format_id and coalesce(p.activo,true)
        and not coalesce(p.eliminado,false) and p.deleted_at is null
      order by p.updated_at desc nulls last limit 1;
      if v_own_states is null or exists (
        select 1
        from jsonb_each(v_normalized) requested_state
        cross join lateral jsonb_each(requested_state.value) requested_action
        where coalesce((requested_action.value)::boolean,false)
          and not coalesce((v_own_states
            -> requested_state.key
            ->> requested_action.key)::boolean,false)
      ) then
        raise exception 'GESTOR cannot delegate state permissions outside own scope'
          using errcode='42501';
      end if;
    end if;

    update public."PERMISOS_DE_USUARIOS_APPGT"
    set permisos_estado=v_normalized,
        otorgado_por=auth.uid(),otorgado_at=now(),
        version_permiso=coalesce(version_permiso,0)+1,updated_at=now()
    where id=v_permission_id;
    v_count:=v_count+1;
  end loop;
  perform public.appgt_incrementar_revision_permisos(v_empresa_id);
  return jsonb_build_object('guardado',true,'formatos_actualizados',v_count);
end
$$;

revoke all on function public.appgt_guardar_permisos_estado_formatos_v1(uuid,jsonb)
  from public,anon;
grant execute on function public.appgt_guardar_permisos_estado_formatos_v1(uuid,jsonb)
  to authenticated,service_role;
grant execute on function public.appgt_puede_accion_estado_formato_v1(text,text,text)
  to authenticated,service_role;

-- --------------------------------------------------------------------------
-- Extensión de maestros y documentos de compras.
-- --------------------------------------------------------------------------

alter table public."ERP_ARTICULOS_APPGT"
  add column if not exists almacen_predeterminado_codigo text;

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname='erp_articulo_almacen_pred_fk'
      and conrelid='public."ERP_ARTICULOS_APPGT"'::regclass
  ) then
    alter table public."ERP_ARTICULOS_APPGT"
      add constraint erp_articulo_almacen_pred_fk
      foreign key (empresa_id,almacen_predeterminado_codigo)
      references public."ERP_ALMACENES_APPGT"(empresa_id,codigo);
  end if;
end $$;

alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  add column if not exists revisado_por uuid references auth.users(id),
  add column if not exists revisado_at timestamptz;

update public."ERP_SOLICITUDES_COMPRA_APPGT" set estado=case estado
  when 'BORRADOR' then 'PENDIENTE'
  when 'ENVIADA' then 'PENDIENTE'
  when 'APROBADA' then 'APROBADO'
  when 'ATENDIDA' then 'APROBADO'
  when 'RECHAZADA' then 'ANULADO'
  when 'ANULADA' then 'ANULADO'
  else estado end;
alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  alter column estado set default 'PENDIENTE';
alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  drop constraint if exists "ERP_SOLICITUDES_COMPRA_APPGT_estado_check";
alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  drop constraint if exists erp_solicitud_estado_ck;
alter table public."ERP_SOLICITUDES_COMPRA_APPGT"
  add constraint erp_solicitud_estado_ck
  check (estado in ('PENDIENTE','REVISADO','APROBADO','ANULADO'));

create table if not exists public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  solicitud_numero text not null,
  linea integer not null check (linea>0),
  articulo_codigo text not null,
  descripcion text,
  cantidad_solicitada numeric(20,6) not null check (cantidad_solicitada>0),
  unidad_medida text not null,
  fecha_necesidad date not null,
  proveedor_recomendado_codigo text,
  almacen_destino_codigo text not null,
  observacion text,
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_scd_solicitud_fk foreign key (empresa_id,solicitud_numero)
    references public."ERP_SOLICITUDES_COMPRA_APPGT"(empresa_id,numero) on delete cascade,
  constraint erp_scd_articulo_fk foreign key (empresa_id,articulo_codigo)
    references public."ERP_ARTICULOS_APPGT"(empresa_id,codigo),
  constraint erp_scd_proveedor_fk foreign key (empresa_id,proveedor_recomendado_codigo)
    references public."ERP_PROVEEDORES_APPGT"(empresa_id,codigo),
  constraint erp_scd_almacen_fk foreign key (empresa_id,almacen_destino_codigo)
    references public."ERP_ALMACENES_APPGT"(empresa_id,codigo),
  unique (empresa_id,solicitud_numero,linea)
);

alter table public."ERP_ORDENES_COMPRA_APPGT"
  add column if not exists proveedor_ruc text,
  add column if not exists revisado_por uuid references auth.users(id),
  add column if not exists revisado_at timestamptz,
  add column if not exists aprobado_por uuid references auth.users(id),
  add column if not exists aprobado_at timestamptz;

update public."ERP_ORDENES_COMPRA_APPGT" set estado=case estado
  when 'BORRADOR' then 'PENDIENTE'
  when 'EMITIDA' then 'PENDIENTE'
  when 'APROBADA' then 'APROBADO'
  when 'PARCIAL' then 'DESPACHADO PARCIALMENTE'
  when 'RECIBIDA' then 'DESPACHADO'
  when 'CERRADA' then 'DESPACHADO'
  when 'ANULADA' then 'ANULADO'
  else estado end;
alter table public."ERP_ORDENES_COMPRA_APPGT"
  alter column estado set default 'PENDIENTE';
alter table public."ERP_ORDENES_COMPRA_APPGT"
  drop constraint if exists "ERP_ORDENES_COMPRA_APPGT_estado_check";
alter table public."ERP_ORDENES_COMPRA_APPGT"
  drop constraint if exists erp_oc_estado_ck;
alter table public."ERP_ORDENES_COMPRA_APPGT"
  add constraint erp_oc_estado_ck check (estado in (
    'PENDIENTE','REVISADO','APROBADO','DESPACHADO PARCIALMENTE','DESPACHADO','ANULADO'
  ));

alter table public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  add column if not exists solicitud_linea integer,
  add column if not exists cantidad_solicitada numeric(20,6),
  add column if not exists cantidad_despachada numeric(20,6) not null default 0;
update public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
set cantidad_solicitada=coalesce(cantidad_solicitada,cantidad),
    cantidad_despachada=greatest(coalesce(cantidad_despachada,0),coalesce(cantidad_recibida,0));
alter table public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  alter column cantidad_solicitada set not null;
alter table public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  drop constraint if exists erp_ocd_despachada_ck;
alter table public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  add constraint erp_ocd_despachada_ck check (
    cantidad_despachada>=0 and cantidad_despachada<=cantidad
  );

-- --------------------------------------------------------------------------
-- Ingresos por orden de compra y vales de despacho.
-- --------------------------------------------------------------------------

create table if not exists public."ERP_INGRESOS_ALMACEN_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  numero text not null,
  fecha_ingreso date not null default current_date,
  orden_numero text not null,
  proveedor_codigo text not null,
  proveedor_ruc text,
  almacen_codigo text not null,
  guia_remision text not null check (btrim(guia_remision)<>''),
  estado text not null default 'CONFIRMADO'
    check (estado in ('CONFIRMADO','ANULADO')),
  observacion text,
  confirmado_por uuid references auth.users(id) default auth.uid(),
  confirmado_at timestamptz not null default now(),
  anulado_por uuid references auth.users(id),
  anulado_at timestamptz,
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_ingreso_oc_fk foreign key (empresa_id,orden_numero)
    references public."ERP_ORDENES_COMPRA_APPGT"(empresa_id,numero),
  constraint erp_ingreso_proveedor_fk foreign key (empresa_id,proveedor_codigo)
    references public."ERP_PROVEEDORES_APPGT"(empresa_id,codigo),
  constraint erp_ingreso_almacen_fk foreign key (empresa_id,almacen_codigo)
    references public."ERP_ALMACENES_APPGT"(empresa_id,codigo),
  unique (empresa_id,numero)
);

create table if not exists public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  ingreso_numero text not null,
  linea integer not null check (linea>0),
  orden_linea integer not null check (orden_linea>0),
  articulo_codigo text not null,
  descripcion text,
  unidad_medida text not null,
  cantidad_ordenada numeric(20,6) not null check (cantidad_ordenada>0),
  cantidad_pendiente_antes numeric(20,6) not null check (cantidad_pendiente_antes>0),
  cantidad_recibida numeric(20,6) not null check (
    cantidad_recibida>0 and cantidad_recibida<=cantidad_pendiente_antes
  ),
  costo_unitario numeric(20,6) not null default 0 check (costo_unitario>=0),
  lote text,
  fecha_vencimiento date,
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_ingreso_det_header_fk foreign key (empresa_id,ingreso_numero)
    references public."ERP_INGRESOS_ALMACEN_APPGT"(empresa_id,numero) on delete cascade,
  constraint erp_ingreso_det_articulo_fk foreign key (empresa_id,articulo_codigo)
    references public."ERP_ARTICULOS_APPGT"(empresa_id,codigo),
  unique (empresa_id,ingreso_numero,linea),
  unique (empresa_id,ingreso_numero,orden_linea)
);

create table if not exists public."ERP_VALES_DESPACHO_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  numero text not null,
  fecha date not null default current_date,
  usuario_dni text not null,
  usuario_nombre text,
  tipo_destino text not null check (tipo_destino in ('DIRECTO','INDIRECTO')),
  centro_costo text not null,
  almacen_codigo text not null,
  estado text not null default 'PENDIENTE' check (
    estado in ('PENDIENTE','REVISADO','APROBADO','DESPACHADO','ANULADO')
  ),
  observacion text,
  revisado_por uuid references auth.users(id),
  revisado_at timestamptz,
  aprobado_por uuid references auth.users(id),
  aprobado_at timestamptz,
  despachado_por uuid references auth.users(id),
  despachado_at timestamptz,
  anulado_por uuid references auth.users(id),
  anulado_at timestamptz,
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_vale_almacen_fk foreign key (empresa_id,almacen_codigo)
    references public."ERP_ALMACENES_APPGT"(empresa_id,codigo),
  unique (empresa_id,numero)
);

create table if not exists public."ERP_VALES_DESPACHO_DETALLE_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  vale_numero text not null,
  linea integer not null check (linea>0),
  articulo_codigo text not null,
  descripcion text,
  unidad_medida text not null,
  cantidad_solicitada numeric(20,6) not null check (cantidad_solicitada>0),
  cantidad_despachada numeric(20,6) not null default 0 check (cantidad_despachada>=0),
  costo_unitario numeric(20,6) not null default 0 check (costo_unitario>=0),
  lote text,
  observacion text,
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  constraint erp_vale_det_header_fk foreign key (empresa_id,vale_numero)
    references public."ERP_VALES_DESPACHO_APPGT"(empresa_id,numero) on delete cascade,
  constraint erp_vale_det_articulo_fk foreign key (empresa_id,articulo_codigo)
    references public."ERP_ARTICULOS_APPGT"(empresa_id,codigo),
  unique (empresa_id,vale_numero,linea)
);

create table if not exists public."ERP_EVENTOS_INTEGRACION_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  modulo_origen text not null,
  documento_tipo text not null,
  documento_numero text not null,
  evento text not null,
  modulos_destino text[] not null default '{}',
  payload jsonb not null default '{}'::jsonb,
  estado text not null default 'PENDIENTE'
    check (estado in ('PENDIENTE','PROCESADO','ERROR','ANULADO')),
  mensaje text,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (empresa_id,documento_tipo,documento_numero,evento)
);

-- --------------------------------------------------------------------------
-- Reglas de negocio y transiciones protegidas.
-- --------------------------------------------------------------------------

create or replace function public.appgt_erp_preparar_orden_compra_v2()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  select p.numero_documento into new.proveedor_ruc
  from public."ERP_PROVEEDORES_APPGT" p
  where p.empresa_id=new.empresa_id and p.codigo=new.proveedor_codigo;
  return new;
end
$$;

drop trigger if exists erp_preparar_orden_compra_v2
  on public."ERP_ORDENES_COMPRA_APPGT";
create trigger erp_preparar_orden_compra_v2
before insert or update of proveedor_codigo
on public."ERP_ORDENES_COMPRA_APPGT" for each row
execute function public.appgt_erp_preparar_orden_compra_v2();

create or replace function public.appgt_erp_validar_flujo_documento_v2()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_allowed boolean;
  v_details integer;
  v_receipt_context boolean:=coalesce(current_setting('appgt.erp_receipt_context',true),'0')='1';
begin
  if tg_op='DELETE' then
    if auth.role()<>'service_role' then
      v_allowed:=public.appgt_puede_accion_estado_formato_v1(
        tg_table_name,old.estado,'delete'
      );
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

  if auth.role()<>'service_role'
     and not (v_receipt_context and tg_table_name='ERP_ORDENES_COMPRA_APPGT')
     and not public.appgt_puede_accion_estado_formato_v1(
       tg_table_name,old.estado,'update'
     ) then
    raise exception 'Sin permiso para editar registros % en estado %.',tg_table_name,old.estado
      using errcode='42501';
  end if;

  if new.estado is distinct from old.estado then
    if tg_table_name='ERP_VALES_DESPACHO_APPGT' and new.estado='DESPACHADO'
       and old.estado<>'APROBADO' then
      raise exception 'Vale no tiene aprobacion';
    end if;

    if tg_table_name in ('ERP_SOLICITUDES_COMPRA_APPGT','ERP_ORDENES_COMPRA_APPGT') then
      if not (
        (old.estado='PENDIENTE' and new.estado='REVISADO') or
        (old.estado='REVISADO' and new.estado='APROBADO') or
        (old.estado in ('PENDIENTE','REVISADO','APROBADO') and new.estado='ANULADO') or
        (tg_table_name='ERP_ORDENES_COMPRA_APPGT' and v_receipt_context and
          old.estado in ('APROBADO','DESPACHADO PARCIALMENTE') and
          new.estado in ('DESPACHADO PARCIALMENTE','DESPACHADO'))
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
    elsif new.estado='APROBADO' then
      new.aprobado_por:=auth.uid();new.aprobado_at:=clock_timestamp();
      if tg_table_name='ERP_SOLICITUDES_COMPRA_APPGT' then
        select count(*) into v_details
        from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" d
        where d.empresa_id=new.empresa_id and d.solicitud_numero=new.numero
          and not d.eliminado and d.deleted_at is null;
      elsif tg_table_name='ERP_ORDENES_COMPRA_APPGT' then
        select count(*) into v_details
        from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d
        where d.empresa_id=new.empresa_id and d.orden_numero=new.numero
          and not d.eliminado and d.deleted_at is null;
      elsif tg_table_name='ERP_VALES_DESPACHO_APPGT' then
        select count(*) into v_details
        from public."ERP_VALES_DESPACHO_DETALLE_APPGT" d
        where d.empresa_id=new.empresa_id and d.vale_numero=new.numero
          and not d.eliminado and d.deleted_at is null;
      end if;
      if coalesce(v_details,0)=0 then
        raise exception 'No se puede aprobar un documento sin artículos o insumos.';
      end if;
    elsif new.estado='DESPACHADO' and tg_table_name='ERP_VALES_DESPACHO_APPGT' then
      new.despachado_por:=auth.uid();new.despachado_at:=clock_timestamp();
    elsif new.estado='ANULADO' and tg_table_name='ERP_VALES_DESPACHO_APPGT' then
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
    'ERP_SOLICITUDES_COMPRA_APPGT',
    'ERP_ORDENES_COMPRA_APPGT',
    'ERP_VALES_DESPACHO_APPGT'
  ] loop
    execute format('drop trigger if exists erp_validar_flujo_v2 on public.%I',v_table);
    execute format(
      'create trigger erp_validar_flujo_v2 before insert or update or delete on public.%I for each row execute function public.appgt_erp_validar_flujo_documento_v2()',
      v_table
    );
  end loop;
end
$$;

-- --------------------------------------------------------------------------
-- Catálogo inicial solicitado: 80 generales, 30 agroquímicos y 10 packing.
-- Se vincula al almacén activo correspondiente de cada empresa.
-- --------------------------------------------------------------------------

with companies as (
  select distinct empresa_id from public."RUBROS_APPGT"
  where activo and deleted_at is null
), warehouses as (
  select c.empresa_id,
    (select a.codigo from public."ERP_ALMACENES_APPGT" a
      where a.empresa_id=c.empresa_id and a.estado='ACTIVO'
        and (a.tipo='GENERAL' or public.appgt_normalizar_clave(a.nombre) like '%GENERAL%')
      order by (a.tipo='GENERAL') desc,a.created_at limit 1) general_codigo,
    (select a.codigo from public."ERP_ALMACENES_APPGT" a
      where a.empresa_id=c.empresa_id and a.estado='ACTIVO'
        and (a.tipo='AGROQUIMICOS' or public.appgt_normalizar_clave(a.nombre) like '%AGROQUIM%')
      order by (a.tipo='AGROQUIMICOS') desc,a.created_at limit 1) agro_codigo,
    (select a.codigo from public."ERP_ALMACENES_APPGT" a
      where a.empresa_id=c.empresa_id and a.estado='ACTIVO'
        and (a.tipo='PACKING' or public.appgt_normalizar_clave(a.nombre) like '%PACKING%')
      order by (a.tipo='PACKING') desc,a.created_at limit 1) packing_codigo
  from companies c
), seed as (
  select empresa_id,'CAT-GEN-'||lpad(n::text,3,'0') codigo,
    'Insumo general '||lpad(n::text,3,'0') nombre,'INSUMO' tipo,
    'SUMINISTROS GENERALES' categoria,'UND' unidad_medida,
    general_codigo almacen, n from warehouses cross join generate_series(1,80) n
  where general_codigo is not null
  union all
  select empresa_id,'CAT-AGR-'||lpad(n::text,3,'0'),
    'Agroquímico '||lpad(n::text,3,'0'),'AGROQUIMICO',
    'SANIDAD VEGETAL','L',agro_codigo,n
  from warehouses cross join generate_series(1,30) n where agro_codigo is not null
  union all
  select empresa_id,'CAT-PAC-'||lpad(n::text,3,'0'),
    'Material de packing '||lpad(n::text,3,'0'),'EMBALAJE',
    'PACKING','UND',packing_codigo,n
  from warehouses cross join generate_series(1,10) n where packing_codigo is not null
)
insert into public."ERP_ARTICULOS_APPGT"(
  empresa_id,codigo,nombre,tipo,categoria,unidad_medida,costo_estandar,
  stock_minimo,stock_maximo,controla_lote,controla_vencimiento,
  afecto_igv,almacen_predeterminado_codigo,estado
)
select empresa_id,codigo,nombre,tipo,categoria,unidad_medida,
  case when tipo='AGROQUIMICO' then 45+n else 5+n end,
  case when tipo='AGROQUIMICO' then 10 else 20 end,
  case when tipo='AGROQUIMICO' then 200 else 500 end,
  tipo='AGROQUIMICO',tipo='AGROQUIMICO',true,almacen,'ACTIVO'
from seed
on conflict (empresa_id,codigo) do update set
  nombre=excluded.nombre,tipo=excluded.tipo,categoria=excluded.categoria,
  unidad_medida=excluded.unidad_medida,
  almacen_predeterminado_codigo=excluded.almacen_predeterminado_codigo,
  estado='ACTIVO',eliminado=false,deleted_at=null,updated_at=now();

-- Dos proveedores y dos solicitudes/órdenes aprobadas de ejemplo.
with companies as (
  select distinct empresa_id from public."RUBROS_APPGT"
  where activo and deleted_at is null
)
insert into public."ERP_PROVEEDORES_APPGT"(
  empresa_id,codigo,tipo_documento,numero_documento,razon_social,
  nombre_comercial,pais,direccion,telefono,email,contacto,
  moneda_preferida,dias_credito,homologado,fecha_homologacion,calificacion,estado
)
select empresa_id,'PRV-SANIDAD','RUC','20990000001','Agroinsumos Sanidad Demo SAC',
  'Agroinsumos Sanidad','PERU','Lima','999000001','sanidad.proveedor@example.com',
  'Ejecutivo Sanidad','PEN',30,true,current_date,90,'ACTIVO' from companies
union all
select empresa_id,'PRV-PRODUCCION','RUC','20990000002','Suministros Producción Demo SAC',
  'Suministros Producción','PERU','Lima','999000002','produccion.proveedor@example.com',
  'Ejecutivo Producción','PEN',15,true,current_date,88,'ACTIVO' from companies
on conflict (empresa_id,codigo) do update set
  numero_documento=excluded.numero_documento,razon_social=excluded.razon_social,
  estado='ACTIVO',eliminado=false,deleted_at=null,updated_at=now();

with warehouses as (
  select distinct a.empresa_id,
    (select x.codigo from public."ERP_ALMACENES_APPGT" x where x.empresa_id=a.empresa_id
      and x.estado='ACTIVO' and x.tipo='AGROQUIMICOS' order by x.created_at limit 1) agro,
    (select x.codigo from public."ERP_ALMACENES_APPGT" x where x.empresa_id=a.empresa_id
      and x.estado='ACTIVO' and x.tipo='GENERAL' order by x.created_at limit 1) general
  from public."ERP_ALMACENES_APPGT" a
)
insert into public."ERP_SOLICITUDES_COMPRA_APPGT"(
  empresa_id,numero,fecha,fecha_necesidad,solicitante,area,centro_costo,
  justificacion,monto_estimado,moneda,estado
)
select empresa_id,'SP-DEMO-SANIDAD-001',current_date,current_date+7,
  'Usuario de Sanidad','SANIDAD','SANIDAD','Reposición preventiva de agroquímicos',
  1500,'PEN','PENDIENTE' from warehouses where agro is not null
union all
select empresa_id,'SP-DEMO-PRODUCCION-001',current_date,current_date+5,
  'Usuario de Producción','PRODUCCION','PRODUCCION','Materiales para labores de campo',
  900,'PEN','PENDIENTE' from warehouses where general is not null
on conflict (empresa_id,numero) do nothing;

with base as (
  select s.empresa_id,s.numero,s.fecha_necesidad,
    case when s.area='SANIDAD' then 'PRV-SANIDAD' else 'PRV-PRODUCCION' end proveedor,
    case when s.area='SANIDAD' then
      (select a.codigo from public."ERP_ARTICULOS_APPGT" a where a.empresa_id=s.empresa_id
        and a.codigo like 'CAT-AGR-%' order by a.codigo limit 1)
      else (select a.codigo from public."ERP_ARTICULOS_APPGT" a where a.empresa_id=s.empresa_id
        and a.codigo like 'CAT-GEN-%' order by a.codigo limit 1) end articulo,
    case when s.area='SANIDAD' then
      (select a.codigo from public."ERP_ALMACENES_APPGT" a where a.empresa_id=s.empresa_id
        and a.tipo='AGROQUIMICOS' and a.estado='ACTIVO' order by a.created_at limit 1)
      else (select a.codigo from public."ERP_ALMACENES_APPGT" a where a.empresa_id=s.empresa_id
        and a.tipo='GENERAL' and a.estado='ACTIVO' order by a.created_at limit 1) end almacen,
    case when s.area='SANIDAD' then 10::numeric else 25::numeric end cantidad
  from public."ERP_SOLICITUDES_COMPRA_APPGT" s
  where s.numero in ('SP-DEMO-SANIDAD-001','SP-DEMO-PRODUCCION-001')
)
insert into public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"(
  empresa_id,solicitud_numero,linea,articulo_codigo,descripcion,
  cantidad_solicitada,unidad_medida,fecha_necesidad,
  proveedor_recomendado_codigo,almacen_destino_codigo
)
select b.empresa_id,b.numero,1,b.articulo,a.nombre,b.cantidad,a.unidad_medida,
  b.fecha_necesidad,b.proveedor,b.almacen
from base b join public."ERP_ARTICULOS_APPGT" a
  on a.empresa_id=b.empresa_id and a.codigo=b.articulo
where b.articulo is not null and b.almacen is not null
on conflict (empresa_id,solicitud_numero,linea) do nothing;

update public."ERP_SOLICITUDES_COMPRA_APPGT" set estado='REVISADO'
where numero in ('SP-DEMO-SANIDAD-001','SP-DEMO-PRODUCCION-001') and estado='PENDIENTE';
update public."ERP_SOLICITUDES_COMPRA_APPGT" set estado='APROBADO'
where numero in ('SP-DEMO-SANIDAD-001','SP-DEMO-PRODUCCION-001') and estado='REVISADO';

insert into public."ERP_ORDENES_COMPRA_APPGT"(
  empresa_id,numero,solicitud_numero,proveedor_codigo,fecha_emision,
  fecha_entrega,moneda,tipo_cambio,condicion_pago,almacen_codigo,estado,observacion
)
select s.empresa_id,
  case when s.area='SANIDAD' then 'OC-DEMO-SANIDAD-001' else 'OC-DEMO-PRODUCCION-001' end,
  s.numero,case when s.area='SANIDAD' then 'PRV-SANIDAD' else 'PRV-PRODUCCION' end,
  current_date,s.fecha_necesidad,'PEN',1,'CRÉDITO',d.almacen_destino_codigo,
  'PENDIENTE','Orden de compra de ejemplo generada desde solicitud aprobada'
from public."ERP_SOLICITUDES_COMPRA_APPGT" s
join public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" d
  on d.empresa_id=s.empresa_id and d.solicitud_numero=s.numero and d.linea=1
where s.numero in ('SP-DEMO-SANIDAD-001','SP-DEMO-PRODUCCION-001')
on conflict (empresa_id,numero) do nothing;

insert into public."ERP_ORDENES_COMPRA_DETALLE_APPGT"(
  empresa_id,orden_numero,linea,solicitud_linea,articulo_codigo,descripcion,
  cantidad_solicitada,cantidad,unidad_medida,precio_unitario,
  descuento_porcentaje,impuesto_porcentaje,cantidad_recibida,cantidad_despachada,
  centro_costo
)
select o.empresa_id,o.numero,1,d.linea,d.articulo_codigo,d.descripcion,
  d.cantidad_solicitada,d.cantidad_solicitada,d.unidad_medida,a.costo_estandar,
  0,18,0,0,s.centro_costo
from public."ERP_ORDENES_COMPRA_APPGT" o
join public."ERP_SOLICITUDES_COMPRA_APPGT" s
  on s.empresa_id=o.empresa_id and s.numero=o.solicitud_numero
join public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT" d
  on d.empresa_id=s.empresa_id and d.solicitud_numero=s.numero and d.linea=1
join public."ERP_ARTICULOS_APPGT" a
  on a.empresa_id=d.empresa_id and a.codigo=d.articulo_codigo
where o.numero in ('OC-DEMO-SANIDAD-001','OC-DEMO-PRODUCCION-001')
on conflict (empresa_id,orden_numero,linea) do nothing;

update public."ERP_ORDENES_COMPRA_APPGT" set estado='REVISADO'
where numero in ('OC-DEMO-SANIDAD-001','OC-DEMO-PRODUCCION-001') and estado='PENDIENTE';
update public."ERP_ORDENES_COMPRA_APPGT" set estado='APROBADO'
where numero in ('OC-DEMO-SANIDAD-001','OC-DEMO-PRODUCCION-001') and estado='REVISADO';

-- Hereda acceso de los formatos equivalentes; luego el administrador puede
-- afinarlo desde la nueva matriz por estado.
with mappings(source_table,target_table) as (values
  ('ERP_SOLICITUDES_COMPRA_APPGT','ERP_SOLICITUDES_COMPRA_DETALLE_APPGT'),
  ('ERP_MOVIMIENTOS_INVENTARIO_APPGT','ERP_INGRESOS_ALMACEN_APPGT'),
  ('ERP_MOVIMIENTOS_INVENTARIO_APPGT','ERP_VALES_DESPACHO_APPGT'),
  ('ERP_TESORERIA_MOVIMIENTOS_APPGT','ERP_EVENTOS_INTEGRACION_APPGT')
), resolved as (
  select p.*,tf.id target_format,tf.modulo_id target_module,
    tm.seccion target_section,tf.tabla_destino target_table
  from mappings x
  join public."MATRIZ_FORMATOS_APPGT" sf on sf.tabla_destino=x.source_table
  join public."MATRIZ_FORMATOS_APPGT" tf
    on tf.empresa_id=sf.empresa_id and tf.tabla_destino=x.target_table
  join public."MATRIZ_MODULOS_APPGT" tm
    on tm.empresa_id=tf.empresa_id and tm.id=tf.modulo_id
  join public."PERMISOS_DE_USUARIOS_APPGT" p
    on p.empresa_id=sf.empresa_id and p.formato=sf.id
  where coalesce(p.activo,true) and not coalesce(p.eliminado,false)
    and p.deleted_at is null
)
insert into public."PERMISOS_DE_USUARIOS_APPGT"(
  empresa_id,user_id,seccion,modulo,formato,tabla_destino,
  can_view,can_insert,can_update,can_delete,can_export,can_import,
  can_review,can_approve,activo,created_at,updated_at,estado_sync,eliminado
)
select empresa_id,user_id,target_section,target_module,target_format,target_table,
  can_view,case when target_table='ERP_EVENTOS_INTEGRACION_APPGT' then false else can_insert end,
  case when target_table='ERP_EVENTOS_INTEGRACION_APPGT' then false else can_update end,
  case when target_table='ERP_EVENTOS_INTEGRACION_APPGT' then false else can_delete end,
  can_export,false,can_review,can_approve,true,now(),now(),'sincronizado',false
from resolved
on conflict (user_id,modulo,formato) do update set
  tabla_destino=excluded.tabla_destino,
  can_view=public."PERMISOS_DE_USUARIOS_APPGT".can_view or excluded.can_view,
  can_insert=public."PERMISOS_DE_USUARIOS_APPGT".can_insert or excluded.can_insert,
  can_update=public."PERMISOS_DE_USUARIOS_APPGT".can_update or excluded.can_update,
  can_delete=public."PERMISOS_DE_USUARIOS_APPGT".can_delete or excluded.can_delete,
  can_export=public."PERMISOS_DE_USUARIOS_APPGT".can_export or excluded.can_export,
  can_review=public."PERMISOS_DE_USUARIOS_APPGT".can_review or excluded.can_review,
  can_approve=public."PERMISOS_DE_USUARIOS_APPGT".can_approve or excluded.can_approve,
  activo=true,eliminado=false,deleted_at=null,updated_at=now();

update public."PERMISOS_DE_USUARIOS_APPGT" p set permisos_estado=
  case p.tabla_destino
    when 'ERP_SOLICITUDES_COMPRA_APPGT' then jsonb_build_object(
      'PENDIENTE',jsonb_build_object('view',p.can_view,'create',p.can_insert,'update',p.can_update or p.can_review,'delete',p.can_delete),
      'REVISADO',jsonb_build_object('view',p.can_view,'create',false,'update',p.can_update or p.can_approve,'delete',p.can_delete),
      'APROBADO',jsonb_build_object('view',p.can_view,'create',false,'update',false,'delete',false),
      'ANULADO',jsonb_build_object('view',p.can_view,'create',false,'update',false,'delete',false))
    when 'ERP_ORDENES_COMPRA_APPGT' then jsonb_build_object(
      'PENDIENTE',jsonb_build_object('view',p.can_view,'create',p.can_insert,'update',p.can_update or p.can_review,'delete',p.can_delete),
      'REVISADO',jsonb_build_object('view',p.can_view,'create',false,'update',p.can_update or p.can_approve,'delete',p.can_delete),
      'APROBADO',jsonb_build_object('view',p.can_view,'create',false,'update',false,'delete',false),
      'DESPACHADO PARCIALMENTE',jsonb_build_object('view',p.can_view,'create',false,'update',false,'delete',false),
      'DESPACHADO',jsonb_build_object('view',p.can_view,'create',false,'update',false,'delete',false),
      'ANULADO',jsonb_build_object('view',p.can_view,'create',false,'update',false,'delete',false))
    when 'ERP_VALES_DESPACHO_APPGT' then jsonb_build_object(
      'PENDIENTE',jsonb_build_object('view',p.can_view,'create',p.can_insert,'update',p.can_update or p.can_review,'delete',p.can_delete),
      'REVISADO',jsonb_build_object('view',p.can_view,'create',false,'update',p.can_update or p.can_approve,'delete',p.can_delete),
      'APROBADO',jsonb_build_object('view',p.can_view,'create',false,'update',p.can_update or p.can_approve,'delete',false),
      'DESPACHADO',jsonb_build_object('view',p.can_view,'create',false,'update',p.can_delete or p.can_approve,'delete',false),
      'ANULADO',jsonb_build_object('view',p.can_view,'create',false,'update',false,'delete',false))
    else p.permisos_estado end,
  updated_at=now()
where p.tabla_destino in (
  'ERP_SOLICITUDES_COMPRA_APPGT','ERP_ORDENES_COMPRA_APPGT','ERP_VALES_DESPACHO_APPGT'
);

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
begin
  if tg_table_name='ERP_SOLICITUDES_COMPRA_DETALLE_APPGT' then
    v_documento:=coalesce(new.solicitud_numero,old.solicitud_numero);
    v_header:='ERP_SOLICITUDES_COMPRA_APPGT';
    select estado into v_estado from public."ERP_SOLICITUDES_COMPRA_APPGT"
    where empresa_id=v_empresa and numero=v_documento;
  elsif tg_table_name='ERP_ORDENES_COMPRA_DETALLE_APPGT' then
    v_documento:=coalesce(new.orden_numero,old.orden_numero);
    v_header:='ERP_ORDENES_COMPRA_APPGT';
    select estado into v_estado from public."ERP_ORDENES_COMPRA_APPGT"
    where empresa_id=v_empresa and numero=v_documento;
  else
    v_documento:=coalesce(new.vale_numero,old.vale_numero);
    v_header:='ERP_VALES_DESPACHO_APPGT';
    select estado into v_estado from public."ERP_VALES_DESPACHO_APPGT"
    where empresa_id=v_empresa and numero=v_documento;
  end if;

  if not (
    coalesce(current_setting('appgt.erp_dispatch_context',true),'0')='1'
    or coalesce(current_setting('appgt.erp_receipt_context',true),'0')='1'
  ) and v_estado not in ('PENDIENTE','REVISADO') then
    raise exception 'No se pueden modificar detalles cuando el documento está %.',v_estado;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end
$$;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'ERP_SOLICITUDES_COMPRA_DETALLE_APPGT',
    'ERP_ORDENES_COMPRA_DETALLE_APPGT',
    'ERP_VALES_DESPACHO_DETALLE_APPGT'
  ] loop
    execute format('drop trigger if exists erp_controlar_detalle_flujo_v2 on public.%I',v_table);
    execute format(
      'create trigger erp_controlar_detalle_flujo_v2 before insert or update or delete on public.%I for each row execute function public.appgt_erp_controlar_detalle_flujo_v2()',
      v_table
    );
  end loop;
end
$$;

create or replace function public.appgt_erp_preparar_movimiento_stock()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  new.tipo_movimiento:=upper(btrim(new.tipo_movimiento));
  if new.tipo_movimiento in ('INGRESO_COMPRA','AJUSTE_ENTRADA','TRANSFERENCIA_ENTRADA','DEVOLUCION') then
    new.direccion:=1;
  elsif new.tipo_movimiento in ('SALIDA_VALE','AJUSTE_SALIDA','TRANSFERENCIA_SALIDA','DESPACHO_VENTA') then
    new.direccion:=-1;
  elsif new.direccion not in (-1,1) then
    raise exception 'Tipo de movimiento no reconocido. Use ingreso, salida, ajuste, transferencia o devolución.';
  end if;
  if tg_op='UPDATE' and old.estado='CONFIRMADO' then
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
  new.costo_total:=round(new.cantidad*new.costo_unitario,6);
  return new;
end
$$;

create or replace function public.appgt_erp_bloquear_ingreso_directo_v1()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  if auth.role()<>'service_role'
     and coalesce(current_setting('appgt.erp_receipt_context',true),'0')<>'1' then
    raise exception 'Registre o anule el ingreso desde la operación guiada de Orden de Compra.';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end
$$;

drop trigger if exists erp_bloquear_ingreso_directo
  on public."ERP_INGRESOS_ALMACEN_APPGT";
create trigger erp_bloquear_ingreso_directo
before insert or update or delete on public."ERP_INGRESOS_ALMACEN_APPGT"
for each row execute function public.appgt_erp_bloquear_ingreso_directo_v1();

drop trigger if exists erp_bloquear_ingreso_detalle_directo
  on public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT";
create trigger erp_bloquear_ingreso_detalle_directo
before insert or update or delete on public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"
for each row execute function public.appgt_erp_bloquear_ingreso_directo_v1();

create or replace function public.erp_ordenes_pendientes_ingreso_v1()
returns jsonb
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'numero',o.numero,
      'referencia',o.numero||' - '||coalesce(o.proveedor_ruc,p.numero_documento,''),
      'proveedor_codigo',o.proveedor_codigo,
      'proveedor_ruc',coalesce(o.proveedor_ruc,p.numero_documento),
      'proveedor',p.razon_social,
      'almacen_codigo',o.almacen_codigo,
      'estado',o.estado,
      'detalles',coalesce((
        select jsonb_agg(jsonb_build_object(
          'linea',d.linea,
          'articulo_codigo',d.articulo_codigo,
          'descripcion',coalesce(d.descripcion,a.nombre),
          'unidad_medida',d.unidad_medida,
          'cantidad_solicitada',d.cantidad_solicitada,
          'cantidad_oc',d.cantidad,
          'cantidad_despachada',d.cantidad_despachada,
          'cantidad_pendiente',greatest(d.cantidad-d.cantidad_despachada,0),
          'costo_unitario',d.precio_unitario,
          'controla_lote',a.controla_lote,
          'controla_vencimiento',a.controla_vencimiento
        ) order by d.linea)
        from public."ERP_ORDENES_COMPRA_DETALLE_APPGT" d
        join public."ERP_ARTICULOS_APPGT" a
          on a.empresa_id=d.empresa_id and a.codigo=d.articulo_codigo
        where d.empresa_id=o.empresa_id and d.orden_numero=o.numero
          and d.cantidad_despachada<d.cantidad
          and not d.eliminado and d.deleted_at is null
      ),'[]'::jsonb)
    ) order by o.fecha_emision,o.numero),'[]'::jsonb)
  from public."ERP_ORDENES_COMPRA_APPGT" o
  join public."ERP_PROVEEDORES_APPGT" p
    on p.empresa_id=o.empresa_id and p.codigo=o.proveedor_codigo
  where o.empresa_id=public.appgt_empresa_actual_id()
    and o.estado in ('APROBADO','DESPACHADO PARCIALMENTE')
    and not o.eliminado and o.deleted_at is null
    and (auth.role()='service_role' or public.appgt_can_view_table('ERP_ORDENES_COMPRA_APPGT'))
$$;

create or replace function public.erp_registrar_ingreso_compra_v1(
  p_orden_numero text,
  p_fecha date,
  p_guia_remision text,
  p_detalles jsonb,
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
  v_detail jsonb;
  v_line public."ERP_ORDENES_COMPRA_DETALLE_APPGT"%rowtype;
  v_qty numeric(20,6);
  v_ingreso text;
  v_ingreso_line integer:=0;
  v_new_state text;
begin
  if v_empresa is null then
    raise exception 'No se pudo resolver la empresa activa' using errcode='42501';
  end if;
  if auth.role()<>'service_role'
     and not public.appgt_can_insert_table('ERP_INGRESOS_ALMACEN_APPGT') then
    raise exception 'Sin permiso para registrar ingresos de almacén' using errcode='42501';
  end if;
  if btrim(coalesce(p_guia_remision,''))='' then
    raise exception 'Debe ingresar el número de guía de remisión.';
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
    proveedor_ruc,almacen_codigo,guia_remision,estado,observacion
  ) values (
    v_empresa,v_ingreso,coalesce(p_fecha,current_date),v_order.numero,
    v_order.proveedor_codigo,v_order.proveedor_ruc,v_order.almacen_codigo,
    btrim(p_guia_remision),'CONFIRMADO',nullif(btrim(coalesce(p_observacion,'')),'')
  );

  for v_detail in select value from jsonb_array_elements(p_detalles)
  loop
    v_qty:=coalesce((v_detail->>'cantidad_recibida')::numeric,0);
    if v_qty<=0 then continue; end if;
    select * into v_line from public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
    where empresa_id=v_empresa and orden_numero=v_order.numero
      and linea=(v_detail->>'linea')::integer
      and not eliminado and deleted_at is null for update;
    if v_line.id is null then
      raise exception 'La línea % no pertenece a la orden %.',v_detail->>'linea',v_order.numero;
    end if;
    if v_qty>v_line.cantidad-v_line.cantidad_despachada then
      raise exception 'La cantidad de % supera el saldo pendiente de %.',
        v_line.articulo_codigo,v_line.cantidad-v_line.cantidad_despachada;
    end if;
    v_ingreso_line:=v_ingreso_line+1;
    insert into public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"(
      empresa_id,ingreso_numero,linea,orden_linea,articulo_codigo,descripcion,
      unidad_medida,cantidad_ordenada,cantidad_pendiente_antes,
      cantidad_recibida,costo_unitario,lote,fecha_vencimiento
    ) values (
      v_empresa,v_ingreso,v_ingreso_line,v_line.linea,v_line.articulo_codigo,
      v_line.descripcion,v_line.unidad_medida,v_line.cantidad,
      v_line.cantidad-v_line.cantidad_despachada,v_qty,v_line.precio_unitario,
      nullif(btrim(coalesce(v_detail->>'lote','')),''),
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
      nullif(v_detail->>'fecha_vencimiento','')::date,
      'INGRESO_COMPRA',1,v_qty,v_line.precio_unitario,
      'INGRESO_COMPRA',v_ingreso,'OC '||v_order.numero||' / Guía '||p_guia_remision,
      'CONFIRMADO'
    );
    update public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
    set cantidad_despachada=cantidad_despachada+v_qty,
        cantidad_recibida=cantidad_recibida+v_qty
    where id=v_line.id;
  end loop;
  if v_ingreso_line=0 then
    raise exception 'Todas las cantidades recibidas son cero.';
  end if;

  select case when bool_and(cantidad_despachada>=cantidad)
    then 'DESPACHADO' else 'DESPACHADO PARCIALMENTE' end
  into v_new_state
  from public."ERP_ORDENES_COMPRA_DETALLE_APPGT"
  where empresa_id=v_empresa and orden_numero=v_order.numero
    and not eliminado and deleted_at is null;
  update public."ERP_ORDENES_COMPRA_APPGT" set estado=v_new_state
  where id=v_order.id;

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
  v_row record;
  v_state text;
begin
  select * into v_header from public."ERP_INGRESOS_ALMACEN_APPGT"
  where empresa_id=v_empresa and numero=p_ingreso_numero for update;
  if v_header.id is null then raise exception 'Ingreso no encontrado.'; end if;
  if v_header.estado<>'CONFIRMADO' then raise exception 'El ingreso ya fue anulado.'; end if;
  if auth.role()<>'service_role'
     and not public.appgt_puede_accion_estado_formato_v1(
       'ERP_INGRESOS_ALMACEN_APPGT','CONFIRMADO','delete'
     ) then
    raise exception 'Sin permiso para anular ingresos.' using errcode='42501';
  end if;
  perform set_config('appgt.erp_receipt_context','1',true);
  update public."ERP_MOVIMIENTOS_INVENTARIO_APPGT"
  set estado='ANULADO'
  where empresa_id=v_empresa and documento_origen_tipo='INGRESO_COMPRA'
    and documento_origen_codigo=v_header.numero and estado='CONFIRMADO';
  for v_row in
    select * from public."ERP_INGRESOS_ALMACEN_DETALLE_APPGT"
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
  update public."ERP_ORDENES_COMPRA_APPGT" set estado=v_state
  where empresa_id=v_empresa and numero=v_header.orden_numero;
  update public."ERP_EVENTOS_INTEGRACION_APPGT" set estado='ANULADO'
  where empresa_id=v_empresa and documento_tipo='INGRESO_COMPRA'
    and documento_numero=v_header.numero;
  return jsonb_build_object('anulado',true,'estado_orden',v_state);
end
$$;

create or replace function public.erp_catalogos_vale_despacho_v1()
returns jsonb
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select jsonb_build_object(
    'almacenes',coalesce((
      select jsonb_agg(jsonb_build_object('codigo',a.codigo,'nombre',a.nombre)
        order by a.nombre)
      from public."ERP_ALMACENES_APPGT" a
      where a.empresa_id=public.appgt_empresa_actual_id()
        and a.estado='ACTIVO' and not a.eliminado and a.deleted_at is null
    ),'[]'::jsonb),
    'articulos',coalesce((
      select jsonb_agg(jsonb_build_object(
        'codigo',a.codigo,'nombre',a.nombre,'unidad_medida',a.unidad_medida,
        'almacen_predeterminado_codigo',a.almacen_predeterminado_codigo
      ) order by a.nombre)
      from public."ERP_ARTICULOS_APPGT" a
      where a.empresa_id=public.appgt_empresa_actual_id()
        and a.estado='ACTIVO' and not a.eliminado and a.deleted_at is null
    ),'[]'::jsonb),
    'lotes',coalesce((
      select jsonb_agg(distinct x."TURNO")
      from public."LOTES_VARIEDADES_GT" x
      where btrim(coalesce(x."TURNO",''))<>''
    ),'[]'::jsonb),
    'areas',coalesce((
      select jsonb_agg(distinct p.area)
      from public."PERFILES_DE_USUARIOS_APPGT" p
      where p.empresa_id=public.appgt_empresa_actual_id()
        and btrim(coalesce(p.area,''))<>''
        and coalesce(p.activo,true) and not coalesce(p.eliminado,false)
    ),'[]'::jsonb)
  )
$$;

create or replace function public.erp_guardar_vale_despacho_v1(
  p_numero text,
  p_fecha date,
  p_usuario_dni text,
  p_usuario_nombre text,
  p_tipo_destino text,
  p_centro_costo text,
  p_almacen_codigo text,
  p_detalles jsonb,
  p_observacion text default null
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
  v_item jsonb;
  v_article public."ERP_ARTICULOS_APPGT"%rowtype;
  v_line integer:=0;
  v_qty numeric(20,6);
  v_tipo text:=upper(btrim(coalesce(p_tipo_destino,'')));
begin
  if v_empresa is null then raise exception 'No se pudo resolver la empresa activa'; end if;
  if v_tipo not in ('DIRECTO','INDIRECTO') then
    raise exception 'El destino debe ser DIRECTO o INDIRECTO.';
  end if;
  if v_tipo='INDIRECTO' and upper(btrim(p_centro_costo))<>'INVERSION'
     and not exists (
       select 1 from public."PERFILES_DE_USUARIOS_APPGT" p
       where p.empresa_id=v_empresa and upper(btrim(coalesce(p.area,'')))=upper(btrim(p_centro_costo))
     ) then
    raise exception 'Para destino indirecto use INVERSION o un área registrada.';
  end if;
  if jsonb_typeof(p_detalles)<>'array' or jsonb_array_length(p_detalles)=0 then
    raise exception 'Agregue al menos un artículo o insumo.';
  end if;
  if v_numero is null then
    v_numero:='VD-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS')||'-'||
      upper(substr(replace(gen_random_uuid()::text,'-',''),1,5));
  end if;

  select * into v_existing from public."ERP_VALES_DESPACHO_APPGT"
  where empresa_id=v_empresa and numero=v_numero for update;
  if v_existing.id is null then
    insert into public."ERP_VALES_DESPACHO_APPGT"(
      empresa_id,numero,fecha,usuario_dni,usuario_nombre,tipo_destino,
      centro_costo,almacen_codigo,estado,observacion
    ) values (
      v_empresa,v_numero,coalesce(p_fecha,current_date),btrim(p_usuario_dni),
      nullif(btrim(coalesce(p_usuario_nombre,'')),''),v_tipo,btrim(p_centro_costo),
      btrim(p_almacen_codigo),'PENDIENTE',nullif(btrim(coalesce(p_observacion,'')),'')
    );
  else
    if v_existing.estado not in ('PENDIENTE','REVISADO') then
      raise exception 'Solo se puede editar un vale PENDIENTE o REVISADO.';
    end if;
    update public."ERP_VALES_DESPACHO_APPGT" set
      fecha=coalesce(p_fecha,current_date),usuario_dni=btrim(p_usuario_dni),
      usuario_nombre=nullif(btrim(coalesce(p_usuario_nombre,'')),''),
      tipo_destino=v_tipo,centro_costo=btrim(p_centro_costo),
      almacen_codigo=btrim(p_almacen_codigo),
      observacion=nullif(btrim(coalesce(p_observacion,'')),'')
    where id=v_existing.id;
    delete from public."ERP_VALES_DESPACHO_DETALLE_APPGT"
    where empresa_id=v_empresa and vale_numero=v_numero;
  end if;

  for v_item in select value from jsonb_array_elements(p_detalles)
  loop
    v_qty:=coalesce((v_item->>'cantidad_solicitada')::numeric,0);
    if v_qty<=0 then raise exception 'Las cantidades solicitadas deben ser mayores a cero.'; end if;
    select * into v_article from public."ERP_ARTICULOS_APPGT"
    where empresa_id=v_empresa and codigo=v_item->>'articulo_codigo'
      and estado='ACTIVO' and not eliminado and deleted_at is null;
    if v_article.id is null then
      raise exception 'Artículo no encontrado: %.',v_item->>'articulo_codigo';
    end if;
    v_line:=v_line+1;
    insert into public."ERP_VALES_DESPACHO_DETALLE_APPGT"(
      empresa_id,vale_numero,linea,articulo_codigo,descripcion,unidad_medida,
      cantidad_solicitada,lote,observacion
    ) values (
      v_empresa,v_numero,v_line,v_article.codigo,v_article.nombre,
      v_article.unidad_medida,v_qty,
      nullif(btrim(coalesce(v_item->>'lote','')),''),
      nullif(btrim(coalesce(v_item->>'observacion','')),'')
    );
  end loop;
  return jsonb_build_object('guardado',true,'vale_numero',v_numero,'estado','PENDIENTE');
end
$$;

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
begin
  select * into v_row from public."ERP_VALES_DESPACHO_APPGT"
  where empresa_id=v_empresa and numero=p_vale_numero for update;
  if v_row.id is null then raise exception 'Vale de despacho no encontrado.'; end if;
  update public."ERP_VALES_DESPACHO_APPGT" set estado=v_next where id=v_row.id;
  return jsonb_build_object('actualizado',true,'vale_numero',v_row.numero,'estado',v_next);
end
$$;

create or replace function public.appgt_erp_aplicar_despacho_vale_v1()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_detail record;
  v_stock record;
  v_remaining numeric(20,6);
  v_take numeric(20,6);
  v_seq integer;
  v_total_cost numeric(20,6);
  v_cost_unit numeric(20,6);
begin
  if old.estado<>'DESPACHADO' and new.estado='DESPACHADO' then
    perform set_config('appgt.erp_dispatch_context','1',true);
    for v_detail in
      select * from public."ERP_VALES_DESPACHO_DETALLE_APPGT"
      where empresa_id=new.empresa_id and vale_numero=new.numero
        and not eliminado and deleted_at is null order by linea
    loop
      v_remaining:=v_detail.cantidad_solicitada;
      v_seq:=0;v_total_cost:=0;
      for v_stock in
        select * from public."ERP_STOCK_APPGT" s
        where s.empresa_id=new.empresa_id and s.almacen_codigo=new.almacen_codigo
          and s.articulo_codigo=v_detail.articulo_codigo
          and (v_detail.lote is null or s.lote is not distinct from v_detail.lote)
          and s.cantidad-s.cantidad_reservada>0
        order by s.fecha_vencimiento nulls last,s.lote nulls last,s.id
        for update
      loop
        exit when v_remaining<=0;
        v_take:=least(v_remaining,v_stock.cantidad-v_stock.cantidad_reservada);
        if v_take<=0 then continue; end if;
        v_seq:=v_seq+1;
        insert into public."ERP_MOVIMIENTOS_INVENTARIO_APPGT"(
          empresa_id,numero,fecha,almacen_codigo,articulo_codigo,lote,
          fecha_vencimiento,tipo_movimiento,direccion,cantidad,costo_unitario,
          documento_origen_tipo,documento_origen_codigo,centro_costo,lote_agricola,
          observacion,estado
        ) values (
          new.empresa_id,'SAL-'||new.numero||'-'||lpad(v_detail.linea::text,3,'0')||'-'||lpad(v_seq::text,2,'0'),
          clock_timestamp(),new.almacen_codigo,v_detail.articulo_codigo,v_stock.lote,
          v_stock.fecha_vencimiento,'SALIDA_VALE',-1,v_take,v_stock.costo_promedio,
          'VALE_DESPACHO',new.numero,new.centro_costo,
          case when new.tipo_destino='DIRECTO' then new.centro_costo else null end,
          coalesce(v_detail.observacion,'Vale de despacho'), 'CONFIRMADO'
        );
        v_total_cost:=v_total_cost+v_take*v_stock.costo_promedio;
        v_remaining:=v_remaining-v_take;
      end loop;
      if v_remaining>0 then
        raise exception 'Stock insuficiente para % en el almacén %. Faltan % %.',
          v_detail.articulo_codigo,new.almacen_codigo,v_remaining,v_detail.unidad_medida;
      end if;
      v_cost_unit:=case when v_detail.cantidad_solicitada>0
        then round(v_total_cost/v_detail.cantidad_solicitada,6) else 0 end;
      update public."ERP_VALES_DESPACHO_DETALLE_APPGT"
      set cantidad_despachada=cantidad_solicitada,costo_unitario=v_cost_unit
      where id=v_detail.id;
      insert into public."ERP_COSTOS_AGROEXPORTADORES_APPGT"(
        empresa_id,numero,fecha,periodo,centro_costo,lote,tipo_costo,
        documento_origen_tipo,documento_origen_codigo,cantidad,unidad_medida,
        costo_unitario,moneda,tipo_cambio,estado
      ) values (
        new.empresa_id,'CST-'||new.numero||'-'||lpad(v_detail.linea::text,3,'0'),
        new.fecha,to_char(new.fecha,'YYYY-MM'),new.centro_costo,
        case when new.tipo_destino='DIRECTO' then new.centro_costo else null end,
        'INSUMO','VALE_DESPACHO',new.numero,v_detail.cantidad_solicitada,
        v_detail.unidad_medida,v_cost_unit,'PEN',1,'REGISTRADO'
      ) on conflict (empresa_id,numero) do nothing;
    end loop;
    insert into public."ERP_EVENTOS_INTEGRACION_APPGT"(
      empresa_id,modulo_origen,documento_tipo,documento_numero,evento,
      modulos_destino,payload
    ) values (
      new.empresa_id,'ALMACEN','VALE_DESPACHO',new.numero,'DESPACHADO',
      array['INVENTARIO','COSTOS','FINANZAS'],jsonb_build_object(
        'centro_costo',new.centro_costo,'tipo_destino',new.tipo_destino,
        'almacen_codigo',new.almacen_codigo
      )
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

drop trigger if exists erp_aplicar_despacho_vale
  on public."ERP_VALES_DESPACHO_APPGT";
create trigger erp_aplicar_despacho_vale
after update of estado on public."ERP_VALES_DESPACHO_APPGT"
for each row execute function public.appgt_erp_aplicar_despacho_vale_v1();

revoke all on function public.erp_ordenes_pendientes_ingreso_v1() from public,anon;
revoke all on function public.erp_registrar_ingreso_compra_v1(text,date,text,jsonb,text) from public,anon;
revoke all on function public.erp_anular_ingreso_compra_v1(text) from public,anon;
revoke all on function public.erp_catalogos_vale_despacho_v1() from public,anon;
revoke all on function public.erp_guardar_vale_despacho_v1(text,date,text,text,text,text,text,jsonb,text) from public,anon;
revoke all on function public.erp_cambiar_estado_vale_despacho_v1(text,text) from public,anon;
grant execute on function public.erp_ordenes_pendientes_ingreso_v1() to authenticated,service_role;
grant execute on function public.erp_registrar_ingreso_compra_v1(text,date,text,jsonb,text) to authenticated,service_role;
grant execute on function public.erp_anular_ingreso_compra_v1(text) to authenticated,service_role;
grant execute on function public.erp_catalogos_vale_despacho_v1() to authenticated,service_role;
grant execute on function public.erp_guardar_vale_despacho_v1(text,date,text,text,text,text,text,jsonb,text) to authenticated,service_role;
grant execute on function public.erp_cambiar_estado_vale_despacho_v1(text,text) to authenticated,service_role;

create or replace function public.erp_guardar_solicitud_pedido_v1(
  p_numero text,
  p_fecha date,
  p_fecha_necesidad date,
  p_solicitante text,
  p_area text,
  p_centro_costo text,
  p_justificacion text,
  p_detalles jsonb
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
  v_item jsonb;
  v_article public."ERP_ARTICULOS_APPGT"%rowtype;
  v_line integer:=0;
  v_qty numeric(20,6);
  v_need date:=coalesce(p_fecha_necesidad,current_date);
begin
  if v_empresa is null then
    raise exception 'No se pudo resolver la empresa activa' using errcode='42501';
  end if;
  if btrim(coalesce(p_solicitante,''))='' then
    raise exception 'Debe indicar el solicitante.';
  end if;
  if jsonb_typeof(p_detalles)<>'array' or jsonb_array_length(p_detalles)=0 then
    raise exception 'Agregue al menos un artículo o insumo.';
  end if;
  if v_numero is null then
    v_numero:='SP-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS')||'-'||
      upper(substr(replace(gen_random_uuid()::text,'-',''),1,5));
  end if;

  select * into v_existing
  from public."ERP_SOLICITUDES_COMPRA_APPGT"
  where empresa_id=v_empresa and numero=v_numero for update;

  if v_existing.id is null then
    insert into public."ERP_SOLICITUDES_COMPRA_APPGT"(
      empresa_id,numero,fecha,fecha_necesidad,solicitante,area,centro_costo,
      justificacion,monto_estimado,moneda,estado
    ) values (
      v_empresa,v_numero,coalesce(p_fecha,current_date),v_need,
      btrim(p_solicitante),nullif(btrim(coalesce(p_area,'')),''),
      nullif(btrim(coalesce(p_centro_costo,'')),''),
      nullif(btrim(coalesce(p_justificacion,'')),''),0,'PEN','PENDIENTE'
    );
  else
    if v_existing.estado not in ('PENDIENTE','REVISADO') then
      raise exception 'Una solicitud % no se puede editar.',v_existing.estado;
    end if;
    update public."ERP_SOLICITUDES_COMPRA_APPGT" set
      fecha=coalesce(p_fecha,current_date),fecha_necesidad=v_need,
      solicitante=btrim(p_solicitante),area=nullif(btrim(coalesce(p_area,'')),''),
      centro_costo=nullif(btrim(coalesce(p_centro_costo,'')),''),
      justificacion=nullif(btrim(coalesce(p_justificacion,'')),''),
      updated_by=auth.uid()
    where empresa_id=v_empresa and numero=v_numero;
    delete from public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"
    where empresa_id=v_empresa and solicitud_numero=v_numero;
  end if;

  for v_item in select value from jsonb_array_elements(p_detalles)
  loop
    v_qty:=coalesce((v_item->>'cantidad_solicitada')::numeric,0);
    if v_qty<=0 then raise exception 'Todas las cantidades deben ser mayores que cero.'; end if;
    select * into v_article from public."ERP_ARTICULOS_APPGT"
    where empresa_id=v_empresa and codigo=v_item->>'articulo_codigo'
      and estado='ACTIVO' and not eliminado and deleted_at is null;
    if v_article.id is null then
      raise exception 'Artículo o insumo no encontrado: %',v_item->>'articulo_codigo';
    end if;
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
      v_article.unidad_medida,
      coalesce((v_item->>'fecha_necesidad')::date,v_need),
      nullif(btrim(coalesce(v_item->>'proveedor_recomendado_codigo','')),''),
      btrim(v_item->>'almacen_destino_codigo'),
      nullif(btrim(coalesce(v_item->>'observacion','')),'')
    );
  end loop;
  return jsonb_build_object('numero',v_numero,'estado','PENDIENTE','lineas',v_line);
end
$$;

revoke all on function public.erp_guardar_solicitud_pedido_v1(text,date,date,text,text,text,text,jsonb)
  from public,anon;
grant execute on function public.erp_guardar_solicitud_pedido_v1(text,date,date,text,text,text,text,jsonb)
  to authenticated,service_role;

-- La consulta central también aplica el permiso de lectura por estado. Para
-- permisos históricos sin matriz se conserva exactamente el comportamiento.
create or replace function public.appgt_select_format_records(
  p_format_id text,
  p_table_name text,
  p_limit integer default null,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa uuid:=public.appgt_empresa_actual_id();
  v_states jsonb:='{}'::jsonb;
  v_raw jsonb;
  v_rows jsonb;
  v_total integer;
begin
  if auth.role()<>'service_role' and not public.appgt_es_admin_empresa(v_empresa) then
    select coalesce(p.permisos_estado,'{}'::jsonb) into v_states
    from public."PERMISOS_DE_USUARIOS_APPGT" p
    where p.empresa_id=v_empresa and p.user_id=auth.uid() and p.formato=p_format_id
      and coalesce(p.activo,true) and not coalesce(p.eliminado,false)
      and p.deleted_at is null
    order by p.updated_at desc nulls last limit 1;
  end if;
  if coalesce(v_states,'{}'::jsonb)='{}'::jsonb then
    return public.appgt_select_format_records_internal_v1(
      p_format_id,p_table_name,p_limit,p_offset
    );
  end if;
  v_raw:=public.appgt_select_format_records_internal_v1(
    p_format_id,p_table_name,null,0
  );
  with permitted as (
    select e.value,e.ordinality
    from jsonb_array_elements(coalesce(v_raw->'rows','[]'::jsonb))
      with ordinality e(value,ordinality)
    where coalesce((v_states
      -> upper(coalesce(e.value->>'ESTADO_APROBACION',e.value->>'estado_aprobacion',
                         e.value->>'ESTADO',e.value->>'estado',''))
      ->> 'view')::boolean,false)
  ), paged as (
    select value,ordinality from permitted
    where ordinality>greatest(coalesce(p_offset,0),0)
      and (p_limit is null or p_limit<=0
        or ordinality<=greatest(coalesce(p_offset,0),0)+p_limit)
    order by ordinality
  )
  select coalesce(jsonb_agg(value order by ordinality),'[]'::jsonb)
    into v_rows from paged;
  select count(*) into v_total
  from jsonb_array_elements(coalesce(v_raw->'rows','[]'::jsonb)) e(value)
  where coalesce((v_states
    -> upper(coalesce(e.value->>'ESTADO_APROBACION',e.value->>'estado_aprobacion',
                       e.value->>'ESTADO',e.value->>'estado',''))
    ->> 'view')::boolean,false);
  return jsonb_set(jsonb_set(v_raw,'{rows}',v_rows,true),'{total_rows}',to_jsonb(v_total),true);
end
$$;

revoke all on function public.appgt_select_format_records(text,text,integer,integer)
  from public,anon;
grant execute on function public.appgt_select_format_records(text,text,integer,integer)
  to authenticated,service_role;

-- --------------------------------------------------------------------------
-- Navegación, formatos, campos y pantallas especiales.
-- --------------------------------------------------------------------------

update public."MATRIZ_FORMATOS_APPGT" f set
  nombre='Solicitud de Pedido',
  tabla_visible_app=true,
  workflow_enabled=true,
  approvals_enabled=true,
  capacidades=coalesce(f.capacidades,'{}'::jsonb)||
    '{"workflow":true,"approvals":true}'::jsonb,
  flujo_estados='["PENDIENTE","REVISADO","APROBADO","ANULADO"]'::jsonb,
  updated_at=now()
where f.tabla_destino='ERP_SOLICITUDES_COMPRA_APPGT';

insert into public."MATRIZ_FORMATOS_ESPECIALES_APPGT"(
  id,empresa_id,modulo_id,formato_id,tipo_pantalla,descripcion,activo,orden,
  created_at,updated_at,deleted_at,estado_sync,eliminado
)
select 'erp_special_solicitud_pedido_'||substr(md5(f.empresa_id::text),1,10),
  f.empresa_id,f.modulo_id,f.id,'erp_solicitud_pedido','Solicitud de Pedido',
  true,0,now(),now(),null,'sincronizado',false
from public."MATRIZ_FORMATOS_APPGT" f
where f.tabla_destino='ERP_SOLICITUDES_COMPRA_APPGT'
on conflict (formato_id) do update set
  modulo_id=excluded.modulo_id,tipo_pantalla=excluded.tipo_pantalla,
  descripcion=excluded.descripcion,activo=true,deleted_at=null,eliminado=false,
  updated_at=now();

update public."MATRIZ_FORMATOS_APPGT" f set
  workflow_enabled=true,
  approvals_enabled=true,
  capacidades=coalesce(f.capacidades,'{}'::jsonb)||
    '{"workflow":true,"approvals":true}'::jsonb,
  flujo_estados='["PENDIENTE","REVISADO","APROBADO","DESPACHADO PARCIALMENTE","DESPACHADO","ANULADO"]'::jsonb,
  updated_at=now()
where f.tabla_destino='ERP_ORDENES_COMPRA_APPGT';

create temporary table erp_new_formats_075(
  format_key text primary key,
  module_key text not null,
  tabla text not null,
  nombre text not null,
  orden integer not null,
  workflow jsonb not null default '[]'::jsonb,
  special_type text
) on commit drop;

insert into erp_new_formats_075 values
  ('solicitudes_compra_detalle','compras_proveedores','ERP_SOLICITUDES_COMPRA_DETALLE_APPGT','Detalle de Solicitudes de Pedido',25,'[]',null),
  ('ingresos_almacen','inventarios_almacenes','ERP_INGRESOS_ALMACEN_APPGT','Ingresos según Orden de Compra',45,'["CONFIRMADO","ANULADO"]','erp_ingreso_compra'),
  ('vales_despacho','inventarios_almacenes','ERP_VALES_DESPACHO_APPGT','Vale de Despacho',50,'["PENDIENTE","REVISADO","APROBADO","DESPACHADO","ANULADO"]','erp_vale_despacho'),
  ('eventos_integracion','contabilidad_finanzas','ERP_EVENTOS_INTEGRACION_APPGT','Integraciones ERP',60,'["PENDIENTE","PROCESADO","ERROR","ANULADO"]',null);

insert into public."MATRIZ_FORMATOS_APPGT"(
  id,empresa_id,modulo_id,nombre,tabla_destino,tabla_visible_app,orden,activo,
  rubro_id,auditable,workflow_enabled,approvals_enabled,flujo_estados,
  capacidades,icono,created_at,updated_at,deleted_at,estado_sync,eliminado
)
select
  'erp_'||x.format_key||'_'||substr(md5(r.empresa_id::text),1,10),r.empresa_id,
  'erp_'||x.module_key||'_'||substr(md5(r.empresa_id::text),1,10),
  x.nombre,x.tabla,true,x.orden,true,r.id,true,
  jsonb_array_length(x.workflow)>0,
  coalesce(x.special_type='erp_vale_despacho',false),x.workflow,
  case when jsonb_array_length(x.workflow)>0
    then '{"workflow":true,"approvals":true}'::jsonb else '{}'::jsonb end,
  case x.format_key
    when 'ingresos_almacen' then 'move_to_inbox_outlined'
    when 'vales_despacho' then 'outbox_outlined'
    else 'sync_alt_outlined' end,
  now(),now(),null,'sincronizado',false
from public."RUBROS_APPGT" r cross join erp_new_formats_075 x
where r.activo and r.deleted_at is null
on conflict (id) do update set
  modulo_id=excluded.modulo_id,nombre=excluded.nombre,
  tabla_destino=excluded.tabla_destino,tabla_visible_app=true,orden=excluded.orden,
  activo=true,rubro_id=excluded.rubro_id,auditable=true,
  workflow_enabled=excluded.workflow_enabled,
  approvals_enabled=excluded.approvals_enabled,flujo_estados=excluded.flujo_estados,
  capacidades=excluded.capacidades,icono=excluded.icono,
  deleted_at=null,eliminado=false,updated_at=now();

insert into public."MATRIZ_FORMATO_TABLAS_APPGT"(
  id,empresa_id,formato_id,nombre,tabla_destino,orden,activo,rubro_id,
  auditable,created_at,updated_at,deleted_at,estado_sync,eliminado
)
select
  'erp_'||x.format_key||'_table_'||substr(md5(r.empresa_id::text),1,10),
  r.empresa_id,'erp_'||x.format_key||'_'||substr(md5(r.empresa_id::text),1,10),
  x.nombre,x.tabla,0,true,r.id,true,now(),now(),null,'sincronizado',false
from public."RUBROS_APPGT" r cross join erp_new_formats_075 x
where r.activo and r.deleted_at is null
on conflict (id) do update set
  formato_id=excluded.formato_id,nombre=excluded.nombre,
  tabla_destino=excluded.tabla_destino,activo=true,rubro_id=excluded.rubro_id,
  deleted_at=null,eliminado=false,updated_at=now();

-- Las tablas de detalle se muestran dentro de su documento, pero también
-- quedan consultables para auditoría y exportación.
insert into public."MATRIZ_FORMATO_TABLAS_APPGT"(
  id,empresa_id,formato_id,nombre,tabla_destino,orden,activo,rubro_id,
  tipo_relacion,tabla_padre,campo_pk_padre,campo_fk_hijo,es_detalle,
  auditable,created_at,updated_at,deleted_at,estado_sync,eliminado
)
select 'erp_ingresos_detalle_table_'||substr(md5(r.empresa_id::text),1,10),
  r.empresa_id,'erp_ingresos_almacen_'||substr(md5(r.empresa_id::text),1,10),
  'Detalle recibido','ERP_INGRESOS_ALMACEN_DETALLE_APPGT',10,true,r.id,
  'detalle','ERP_INGRESOS_ALMACEN_APPGT','numero','ingreso_numero',true,
  true,now(),now(),null,'sincronizado',false
from public."RUBROS_APPGT" r where r.activo and r.deleted_at is null
on conflict (id) do update set activo=true,deleted_at=null,eliminado=false,updated_at=now();

insert into public."MATRIZ_FORMATO_TABLAS_APPGT"(
  id,empresa_id,formato_id,nombre,tabla_destino,orden,activo,rubro_id,
  tipo_relacion,tabla_padre,campo_pk_padre,campo_fk_hijo,es_detalle,
  auditable,created_at,updated_at,deleted_at,estado_sync,eliminado
)
select 'erp_vales_detalle_table_'||substr(md5(r.empresa_id::text),1,10),
  r.empresa_id,'erp_vales_despacho_'||substr(md5(r.empresa_id::text),1,10),
  'Artículos solicitados','ERP_VALES_DESPACHO_DETALLE_APPGT',10,true,r.id,
  'detalle','ERP_VALES_DESPACHO_APPGT','numero','vale_numero',true,
  true,now(),now(),null,'sincronizado',false
from public."RUBROS_APPGT" r where r.activo and r.deleted_at is null
on conflict (id) do update set activo=true,deleted_at=null,eliminado=false,updated_at=now();

insert into public."MATRIZ_FORMATOS_ESPECIALES_APPGT"(
  id,empresa_id,modulo_id,formato_id,tipo_pantalla,descripcion,activo,orden,
  created_at,updated_at,deleted_at,estado_sync,eliminado
)
select
  'erp_special_'||x.format_key||'_'||substr(md5(r.empresa_id::text),1,10),
  r.empresa_id,'erp_'||x.module_key||'_'||substr(md5(r.empresa_id::text),1,10),
  'erp_'||x.format_key||'_'||substr(md5(r.empresa_id::text),1,10),
  x.special_type,x.nombre,true,0,now(),now(),null,'sincronizado',false
from public."RUBROS_APPGT" r cross join erp_new_formats_075 x
where r.activo and r.deleted_at is null and x.special_type is not null
on conflict (formato_id) do update set
  modulo_id=excluded.modulo_id,tipo_pantalla=excluded.tipo_pantalla,
  descripcion=excluded.descripcion,activo=true,deleted_at=null,eliminado=false,
  updated_at=now();

with target_tables(tabla) as (values
  ('ERP_ARTICULOS_APPGT'),
  ('ERP_SOLICITUDES_COMPRA_APPGT'),
  ('ERP_SOLICITUDES_COMPRA_DETALLE_APPGT'),
  ('ERP_ORDENES_COMPRA_APPGT'),
  ('ERP_ORDENES_COMPRA_DETALLE_APPGT'),
  ('ERP_INGRESOS_ALMACEN_APPGT'),
  ('ERP_INGRESOS_ALMACEN_DETALLE_APPGT'),
  ('ERP_VALES_DESPACHO_APPGT'),
  ('ERP_VALES_DESPACHO_DETALLE_APPGT'),
  ('ERP_EVENTOS_INTEGRACION_APPGT')
), companies as (
  select distinct empresa_id from public."RUBROS_APPGT"
  where activo and deleted_at is null
), columns as (
  select e.empresa_id,t.tabla,c.column_name,c.data_type,c.is_nullable,
    c.column_default,c.is_generated,c.ordinal_position
  from companies e cross join target_tables t
  join information_schema.columns c
    on c.table_schema='public' and c.table_name=t.tabla
  where c.column_name not in (
    'id','id_local','empresa_id','created_by','updated_by','created_at',
    'updated_at','deleted_at','eliminado','estado_sync','version'
  )
)
insert into public."MATRIZ_CAMPOS_FORMATO_APPGT"(
  id,empresa_id,tabla_destino,campo,etiqueta,tipo,tipo_ui,requerido,
  visible,visible_tabla,editable,orden,activo,created_at,updated_at,
  estado_sync,eliminado
)
select
  'erp_field_'||substr(md5(empresa_id::text||'|'||tabla||'|'||column_name),1,24),
  empresa_id,tabla,column_name,initcap(replace(column_name,'_',' ')),
  case
    when data_type in ('smallint','integer','bigint','numeric','decimal','real','double precision') then 'numeric'
    when data_type='boolean' then 'boolean'
    when data_type='date' then 'date'
    when data_type like 'timestamp%' then 'timestamptz'
    else 'text' end,
  case
    when data_type in ('smallint','integer','bigint','numeric','decimal','real','double precision') then 'number'
    when data_type='boolean' then 'switch'
    when data_type='date' then 'date'
    when data_type like 'timestamp%' then 'datetime'
    else 'text' end,
  (is_nullable='NO' and column_default is null and is_generated<>'ALWAYS'),
  is_generated<>'ALWAYS',true,is_generated<>'ALWAYS',ordinal_position,true,
  now(),now(),'sincronizado',false
from columns
on conflict (tabla_destino,campo) do update set
  empresa_id=excluded.empresa_id,etiqueta=excluded.etiqueta,tipo=excluded.tipo,
  tipo_ui=excluded.tipo_ui,requerido=excluded.requerido,visible=excluded.visible,
  visible_tabla=true,editable=excluded.editable,orden=excluded.orden,
  activo=true,eliminado=false,updated_at=now();

update public."MATRIZ_CAMPOS_FORMATO_APPGT" set
  etiqueta=case campo
    when 'numero' then case when tabla_destino='ERP_MOVIMIENTOS_INVENTARIO_APPGT'
      then 'Número de movimiento' else 'Número' end
    when 'orden_numero' then 'Número de orden de compra'
    when 'proveedor_ruc' then 'RUC del proveedor'
    when 'cantidad' then 'Cantidad generada en OC'
    when 'cantidad_solicitada' then 'Cantidad solicitada'
    when 'cantidad_despachada' then 'Cantidad despachada'
    when 'cantidad_recibida' then 'Cantidad recibida en este ingreso'
    when 'almacen_predeterminado_codigo' then 'Almacén asignado'
    when 'almacen_destino_codigo' then 'Almacén de destino'
    when 'guia_remision' then 'Guía de remisión'
    when 'tipo_movimiento' then 'Tipo de movimiento'
    when 'tipo_destino' then 'Directo / Indirecto'
    when 'usuario_dni' then 'Usuario (DNI)'
    else etiqueta end,
  updated_at=now()
where tabla_destino in (
  'ERP_ARTICULOS_APPGT','ERP_SOLICITUDES_COMPRA_APPGT',
  'ERP_SOLICITUDES_COMPRA_DETALLE_APPGT','ERP_ORDENES_COMPRA_APPGT',
  'ERP_ORDENES_COMPRA_DETALLE_APPGT','ERP_INGRESOS_ALMACEN_APPGT',
  'ERP_INGRESOS_ALMACEN_DETALLE_APPGT','ERP_VALES_DESPACHO_APPGT',
  'ERP_VALES_DESPACHO_DETALLE_APPGT','ERP_MOVIMIENTOS_INVENTARIO_APPGT'
);

update public."MATRIZ_CAMPOS_FORMATO_APPGT" set
  tipo_ui='dropdown',
  id_campo_dropdown=case
    when campo in ('almacen_codigo','almacen_destino_codigo','almacen_predeterminado_codigo')
      then 'ERP_ALMACENES_APPGT.codigo'
    when campo='articulo_codigo' then 'ERP_ARTICULOS_APPGT.codigo'
    when campo in ('proveedor_codigo','proveedor_recomendado_codigo')
      then 'ERP_PROVEEDORES_APPGT.codigo'
    when campo='solicitud_numero' then 'ERP_SOLICITUDES_COMPRA_APPGT.numero'
    when campo='orden_numero' then 'ERP_ORDENES_COMPRA_APPGT.numero'
    when campo='tipo_movimiento' then '[INGRESO_COMPRA;SALIDA_VALE;AJUSTE_ENTRADA;AJUSTE_SALIDA;TRANSFERENCIA_ENTRADA;TRANSFERENCIA_SALIDA;DEVOLUCION;DESPACHO_VENTA]'
    when campo='tipo_destino' then '[DIRECTO;INDIRECTO]'
    else id_campo_dropdown end,
  updated_at=now()
where tabla_destino like 'ERP\_%' escape '\'
  and campo in (
    'almacen_codigo','almacen_destino_codigo','almacen_predeterminado_codigo',
    'articulo_codigo','proveedor_codigo','proveedor_recomendado_codigo',
    'solicitud_numero','orden_numero','tipo_movimiento','tipo_destino'
  );

update public."MATRIZ_CAMPOS_FORMATO_APPGT" set
  tipo_ui='dropdown',id_campo_dropdown=case tabla_destino
    when 'ERP_SOLICITUDES_COMPRA_APPGT' then '[PENDIENTE;REVISADO;APROBADO;ANULADO]'
    when 'ERP_ORDENES_COMPRA_APPGT' then '[PENDIENTE;REVISADO;APROBADO;DESPACHADO PARCIALMENTE;DESPACHADO;ANULADO]'
    when 'ERP_INGRESOS_ALMACEN_APPGT' then '[CONFIRMADO;ANULADO]'
    when 'ERP_VALES_DESPACHO_APPGT' then '[PENDIENTE;REVISADO;APROBADO;DESPACHADO;ANULADO]'
    when 'ERP_EVENTOS_INTEGRACION_APPGT' then '[PENDIENTE;PROCESADO;ERROR;ANULADO]'
    else id_campo_dropdown end,
  editable=false,updated_at=now()
where campo='estado' and tabla_destino in (
  'ERP_SOLICITUDES_COMPRA_APPGT','ERP_ORDENES_COMPRA_APPGT',
  'ERP_INGRESOS_ALMACEN_APPGT','ERP_VALES_DESPACHO_APPGT',
  'ERP_EVENTOS_INTEGRACION_APPGT'
);

update public."MATRIZ_CAMPOS_FORMATO_APPGT" set
  visible=false,visible_tabla=true,editable=false,updated_at=now()
where campo in (
  'proveedor_ruc','revisado_por','revisado_at','aprobado_por','aprobado_at',
  'confirmado_por','confirmado_at','anulado_por','anulado_at',
  'despachado_por','despachado_at','cantidad_despachada','costo_total',
  'modulos_destino','payload','processed_at'
) and tabla_destino like 'ERP\_%' escape '\';

create index if not exists erp_solicitud_det_articulo_idx
  on public."ERP_SOLICITUDES_COMPRA_DETALLE_APPGT"(empresa_id,articulo_codigo);
create index if not exists erp_ingreso_oc_idx
  on public."ERP_INGRESOS_ALMACEN_APPGT"(empresa_id,orden_numero,fecha_ingreso desc);
create index if not exists erp_vale_fecha_idx
  on public."ERP_VALES_DESPACHO_APPGT"(empresa_id,fecha desc,estado);
create index if not exists erp_eventos_pendientes_idx
  on public."ERP_EVENTOS_INTEGRACION_APPGT"(empresa_id,estado,created_at);

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'ERP_SOLICITUDES_COMPRA_DETALLE_APPGT','ERP_INGRESOS_ALMACEN_APPGT',
    'ERP_INGRESOS_ALMACEN_DETALLE_APPGT','ERP_VALES_DESPACHO_APPGT',
    'ERP_VALES_DESPACHO_DETALLE_APPGT'
  ] loop
    execute format('drop trigger if exists erp_touch_row on public.%I',v_table);
    execute format('create trigger erp_touch_row before update on public.%I for each row execute function public.appgt_erp_touch_row()',v_table);
  end loop;
end
$$;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'ERP_SOLICITUDES_COMPRA_DETALLE_APPGT','ERP_INGRESOS_ALMACEN_APPGT',
    'ERP_INGRESOS_ALMACEN_DETALLE_APPGT','ERP_VALES_DESPACHO_APPGT',
    'ERP_VALES_DESPACHO_DETALLE_APPGT','ERP_EVENTOS_INTEGRACION_APPGT'
  ] loop
    execute format('alter table public.%I enable row level security',v_table);
    execute format('drop policy if exists erp_select on public.%I',v_table);
    execute format('drop policy if exists erp_insert on public.%I',v_table);
    execute format('drop policy if exists erp_update on public.%I',v_table);
    execute format('drop policy if exists erp_delete on public.%I',v_table);
    execute format('create policy erp_select on public.%I for select to authenticated using (empresa_id=public.appgt_empresa_actual_id() and public.appgt_can_view_table(%L))',v_table,v_table);
    execute format('create policy erp_insert on public.%I for insert to authenticated with check (empresa_id=public.appgt_empresa_actual_id() and public.appgt_can_insert_table(%L))',v_table,v_table);
    execute format('create policy erp_update on public.%I for update to authenticated using (empresa_id=public.appgt_empresa_actual_id() and public.appgt_can_update_table(%L)) with check (empresa_id=public.appgt_empresa_actual_id() and public.appgt_can_update_table(%L))',v_table,v_table,v_table);
    execute format('create policy erp_delete on public.%I for delete to authenticated using (empresa_id=public.appgt_empresa_actual_id() and public.appgt_can_delete_table(%L))',v_table,v_table);
    execute format('grant select,insert,update,delete on public.%I to authenticated',v_table);
    execute format('grant all on public.%I to service_role',v_table);
  end loop;
end
$$;

-- Los formatos nuevos ya existen en este punto: se heredan permisos de sus
-- formatos equivalentes y se inicializa el alcance detallado por estado.
with mappings(source_table,target_table) as (values
  ('ERP_SOLICITUDES_COMPRA_APPGT','ERP_SOLICITUDES_COMPRA_DETALLE_APPGT'),
  ('ERP_MOVIMIENTOS_INVENTARIO_APPGT','ERP_INGRESOS_ALMACEN_APPGT'),
  ('ERP_MOVIMIENTOS_INVENTARIO_APPGT','ERP_VALES_DESPACHO_APPGT'),
  ('ERP_TESORERIA_MOVIMIENTOS_APPGT','ERP_EVENTOS_INTEGRACION_APPGT')
), resolved as (
  select p.*,tf.id target_format,tf.modulo_id target_module,
    tm.seccion target_section,tf.tabla_destino target_table
  from mappings x
  join public."MATRIZ_FORMATOS_APPGT" sf on sf.tabla_destino=x.source_table
  join public."MATRIZ_FORMATOS_APPGT" tf
    on tf.empresa_id=sf.empresa_id and tf.tabla_destino=x.target_table
  join public."MATRIZ_MODULOS_APPGT" tm
    on tm.empresa_id=tf.empresa_id and tm.id=tf.modulo_id
  join public."PERMISOS_DE_USUARIOS_APPGT" p
    on p.empresa_id=sf.empresa_id and p.formato=sf.id
  where coalesce(p.activo,true) and not coalesce(p.eliminado,false)
    and p.deleted_at is null
)
insert into public."PERMISOS_DE_USUARIOS_APPGT"(
  empresa_id,user_id,seccion,modulo,formato,tabla_destino,
  can_view,can_insert,can_update,can_delete,can_export,can_import,
  can_review,can_approve,activo,created_at,updated_at,estado_sync,eliminado
)
select empresa_id,user_id,target_section,target_module,target_format,target_table,
  can_view,case when target_table='ERP_EVENTOS_INTEGRACION_APPGT' then false else can_insert end,
  case when target_table='ERP_EVENTOS_INTEGRACION_APPGT' then false else can_update end,
  case when target_table='ERP_EVENTOS_INTEGRACION_APPGT' then false else can_delete end,
  can_export,false,can_review,can_approve,true,now(),now(),'sincronizado',false
from resolved
on conflict (user_id,modulo,formato) do update set
  tabla_destino=excluded.tabla_destino,
  can_view=public."PERMISOS_DE_USUARIOS_APPGT".can_view or excluded.can_view,
  can_insert=public."PERMISOS_DE_USUARIOS_APPGT".can_insert or excluded.can_insert,
  can_update=public."PERMISOS_DE_USUARIOS_APPGT".can_update or excluded.can_update,
  can_delete=public."PERMISOS_DE_USUARIOS_APPGT".can_delete or excluded.can_delete,
  can_export=public."PERMISOS_DE_USUARIOS_APPGT".can_export or excluded.can_export,
  can_review=public."PERMISOS_DE_USUARIOS_APPGT".can_review or excluded.can_review,
  can_approve=public."PERMISOS_DE_USUARIOS_APPGT".can_approve or excluded.can_approve,
  activo=true,eliminado=false,deleted_at=null,updated_at=now();

update public."PERMISOS_DE_USUARIOS_APPGT" p set permisos_estado=
  case p.tabla_destino
    when 'ERP_INGRESOS_ALMACEN_APPGT' then jsonb_build_object(
      'CONFIRMADO',jsonb_build_object('view',p.can_view,'create',p.can_insert,'update',false,'delete',p.can_delete),
      'ANULADO',jsonb_build_object('view',p.can_view,'create',false,'update',false,'delete',false))
    when 'ERP_VALES_DESPACHO_APPGT' then jsonb_build_object(
      'PENDIENTE',jsonb_build_object('view',p.can_view,'create',p.can_insert,'update',p.can_update or p.can_review,'delete',p.can_delete),
      'REVISADO',jsonb_build_object('view',p.can_view,'create',false,'update',p.can_update or p.can_approve,'delete',p.can_delete),
      'APROBADO',jsonb_build_object('view',p.can_view,'create',false,'update',p.can_update or p.can_approve,'delete',false),
      'DESPACHADO',jsonb_build_object('view',p.can_view,'create',false,'update',p.can_delete or p.can_approve,'delete',false),
      'ANULADO',jsonb_build_object('view',p.can_view,'create',false,'update',false,'delete',false))
    else p.permisos_estado end,
  updated_at=now()
where p.tabla_destino in ('ERP_INGRESOS_ALMACEN_APPGT','ERP_VALES_DESPACHO_APPGT');

select public.appgt_instalar_seguimiento_tablas_v1();
notify pgrst,'reload schema';
commit;
