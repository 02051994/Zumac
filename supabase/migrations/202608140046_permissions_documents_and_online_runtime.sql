begin;

create extension if not exists pgcrypto;

-- Catalogo administrable de ausencias. Si la tabla ya existe en produccion,
-- solo se agregan las columnas que este flujo necesita.
create table if not exists public."MATRIZ_TIPOS_AUSENCIA_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  codigo text not null,
  nombre text not null,
  descripcion text,
  con_goce_haber boolean not null default true,
  documento_requerido boolean not null default false,
  activo boolean not null default true,
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1
);

alter table public."MATRIZ_TIPOS_AUSENCIA_APPGT"
  add column if not exists id_local uuid default gen_random_uuid(),
  add column if not exists empresa_id uuid references public."EMPRESAS_APPGT"(id),
  add column if not exists codigo text,
  add column if not exists nombre text,
  add column if not exists descripcion text,
  add column if not exists con_goce_haber boolean not null default true,
  add column if not exists documento_requerido boolean not null default false,
  add column if not exists activo boolean not null default true,
  add column if not exists created_by uuid references auth.users(id) default auth.uid(),
  add column if not exists updated_by uuid references auth.users(id),
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz,
  add column if not exists eliminado boolean not null default false,
  add column if not exists estado_sync text not null default 'sincronizado',
  add column if not exists version integer not null default 1;

create unique index if not exists uq_matriz_tipos_ausencia_empresa_nombre
  on public."MATRIZ_TIPOS_AUSENCIA_APPGT" (empresa_id, upper(btrim(nombre)))
  where not coalesce(eliminado, false);
create unique index if not exists uq_matriz_tipos_ausencia_id_local
  on public."MATRIZ_TIPOS_AUSENCIA_APPGT" (id_local)
  where id_local is not null;
create index if not exists idx_matriz_tipos_ausencia_activos
  on public."MATRIZ_TIPOS_AUSENCIA_APPGT" (empresa_id, activo, nombre);

insert into public."MATRIZ_TIPOS_AUSENCIA_APPGT" (
  empresa_id, codigo, nombre, descripcion, con_goce_haber, documento_requerido
)
select e.id,
       seed.codigo || '_' || upper(substr(md5(e.id::text), 1, 8)),
       seed.nombre, seed.descripcion, seed.con_goce, seed.documento
from public."EMPRESAS_APPGT" e
cross join (values
  ('DESCANSO_MEDICO','DESCANSO MEDICO','Descanso sustentado por certificado medico',true,true),
  ('LICENCIA_MATERNIDAD','LICENCIA DE MATERNIDAD','Licencia legal por maternidad',true,true),
  ('PERMISO_SIN_GOCE','PERMISO SIN GOCE','Permiso autorizado sin pago de remuneracion',false,true),
  ('COMISION_SERVICIO','COMISION DE SERVICIO','Desplazamiento autorizado por trabajo',true,true),
  ('LICENCIA_PATERNIDAD','LICENCIA DE PATERNIDAD','Licencia legal por paternidad',true,true),
  ('LICENCIA_FALLECIMIENTO','LICENCIA POR FALLECIMIENTO','Licencia por fallecimiento de familiar',true,true),
  ('VACACIONES','VACACIONES','Descanso vacacional autorizado',true,false),
  ('OTRO','OTRO','Otro permiso o licencia configurado por Gestion Humana',true,false)
) as seed(codigo, nombre, descripcion, con_goce, documento)
where coalesce(e.activo, true)
  and not exists (
    select 1 from public."MATRIZ_TIPOS_AUSENCIA_APPGT" t
    where t.empresa_id = e.id
      and upper(btrim(t.nombre)) = seed.nombre
      and not coalesce(t.eliminado, false)
  );

alter table public."MATRIZ_TIPOS_AUSENCIA_APPGT" enable row level security;
drop policy if exists matriz_tipos_ausencia_tenant on public."MATRIZ_TIPOS_AUSENCIA_APPGT";
create policy matriz_tipos_ausencia_tenant
  on public."MATRIZ_TIPOS_AUSENCIA_APPGT" for all to authenticated
  using (public.appgt_puede_acceder_empresa(empresa_id))
  with check (public.appgt_puede_acceder_empresa(empresa_id));
grant select, insert, update, delete on public."MATRIZ_TIPOS_AUSENCIA_APPGT" to authenticated;
grant all on public."MATRIZ_TIPOS_AUSENCIA_APPGT" to service_role;

-- El tipo ya no se limita por una lista SQL fija: la matriz es la fuente unica.
do $$
declare v_constraint record;
begin
  for v_constraint in
    select conname
    from pg_constraint
    where conrelid = 'public."GH_PERMISOS_LICENCIAS_APPGT"'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%tipo_permiso%'
  loop
    execute format(
      'alter table public."GH_PERMISOS_LICENCIAS_APPGT" drop constraint %I',
      v_constraint.conname
    );
  end loop;
end
$$;

create or replace function public.appgt_gh_permisos_preparar_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tipo record;
begin
  select t.con_goce_haber, t.documento_requerido
    into v_tipo
  from public."MATRIZ_TIPOS_AUSENCIA_APPGT" t
  where t.empresa_id = new.empresa_id
    and upper(btrim(t.nombre)) = upper(btrim(new.tipo_permiso))
    and coalesce(t.activo, true)
    and not coalesce(t.eliminado, false)
  limit 1;

  if not found then
    raise exception 'El tipo de permiso o licencia seleccionado ya no esta disponible.';
  end if;
  if coalesce(v_tipo.documento_requerido, false)
      and nullif(btrim(coalesce(new.documento_sustento, '')), '') is null then
    raise exception 'Debe adjuntar el documento de sustento en formato PDF.';
  end if;

  new.con_goce_haber := coalesce(v_tipo.con_goce_haber, true);
  new.dias_solicitados := greatest(1, new.fecha_fin - new.fecha_inicio + 1);
  new.updated_at := now();
  new.updated_by := auth.uid();
  if tg_op = 'UPDATE' then new.version := old.version + 1; end if;
  return new;
end
$$;

-- Bucket privado. La primera carpeta siempre es empresa_id, validada por RLS.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'permisos-licencias', 'permisos-licencias', false, 15728640,
  array['application/pdf']::text[]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists permisos_documentos_select on storage.objects;
create policy permisos_documentos_select on storage.objects
for select to authenticated
using (
  bucket_id = 'permisos-licencias'
  and case
    when coalesce((storage.foldername(name))[1], '') ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then public.appgt_puede_acceder_empresa(((storage.foldername(name))[1])::uuid)
    else false
  end
);
drop policy if exists permisos_documentos_insert on storage.objects;
create policy permisos_documentos_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'permisos-licencias'
  and case
    when coalesce((storage.foldername(name))[1], '') ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then public.appgt_puede_acceder_empresa(((storage.foldername(name))[1])::uuid)
    else false
  end
);
drop policy if exists permisos_documentos_update on storage.objects;
create policy permisos_documentos_update on storage.objects
for update to authenticated
using (
  bucket_id = 'permisos-licencias'
  and case
    when coalesce((storage.foldername(name))[1], '') ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then public.appgt_puede_acceder_empresa(((storage.foldername(name))[1])::uuid)
    else false
  end
)
with check (
  bucket_id = 'permisos-licencias'
  and case
    when coalesce((storage.foldername(name))[1], '') ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then public.appgt_puede_acceder_empresa(((storage.foldername(name))[1])::uuid)
    else false
  end
);
drop policy if exists permisos_documentos_delete on storage.objects;
create policy permisos_documentos_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'permisos-licencias'
  and case
    when coalesce((storage.foldername(name))[1], '') ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then public.appgt_puede_acceder_empresa(((storage.foldername(name))[1])::uuid)
    else false
  end
);

-- Matriz visible en MATRICES > Gestion Humana y consumida por el dropdown.
do $$
declare
  v_empresa record;
  v_module_id text;
  v_rubro_id text;
  v_format_id text;
begin
  for v_empresa in select id from public."EMPRESAS_APPGT" where coalesce(activo, true)
  loop
    select m.id, m.rubro_id into v_module_id, v_rubro_id
    from public."MATRIZ_MODULOS_APPGT" m
    join public."MATRIZ_SECCIONES_APPGT" s
      on s.empresa_id = m.empresa_id and s.id = m.seccion
    where m.empresa_id = v_empresa.id
      and public.appgt_normalizar_clave(m.nombre) = 'GESTION HUMANA'
      and public.appgt_normalizar_clave(s.nombre) = 'MATRICES'
      and coalesce(m.activo, true) and coalesce(s.activo, true)
    order by m.orden, m.id limit 1;
    if v_module_id is null then continue; end if;

    v_format_id := 'matrix_absence_' || substr(md5(v_empresa.id::text), 1, 20);
    insert into public."MATRIZ_FORMATOS_APPGT" (
      id, empresa_id, modulo_id, nombre, tabla_destino, tabla_visible_app,
      orden, activo, rubro_id, auditable, icono, capacidades,
      created_at, updated_at, estado_sync, eliminado
    ) values (
      v_format_id, v_empresa.id, v_module_id, 'Tipos de ausencia',
      'MATRIZ_TIPOS_AUSENCIA_APPGT', true, 20, true, v_rubro_id, true,
      'event_busy', '{"importar":true,"exportar":true}'::jsonb,
      now(), now(), 'sincronizado', false
    ) on conflict (id) do update set
      modulo_id=excluded.modulo_id, nombre=excluded.nombre,
      tabla_destino=excluded.tabla_destino, tabla_visible_app=true,
      activo=true, eliminado=false, deleted_at=null, updated_at=now();

    insert into public."MATRIZ_FORMATO_TABLAS_APPGT" (
      id, empresa_id, formato_id, nombre, tabla_destino, orden, activo,
      rubro_id, auditable, icono, created_at, updated_at
    ) values (
      'matrix_absence_table_' || substr(md5(v_empresa.id::text),1,16),
      v_empresa.id, v_format_id, 'Tipos de ausencia',
      'MATRIZ_TIPOS_AUSENCIA_APPGT', 0, true, v_rubro_id, true,
      'event_busy', now(), now()
    ) on conflict (id) do update set
      formato_id=excluded.formato_id, tabla_destino=excluded.tabla_destino,
      activo=true, deleted_at=null, updated_at=now();
  end loop;
end
$$;

insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id, tabla_destino, campo, etiqueta, tipo, tipo_ui, id_campo_dropdown,
  requerido, visible, visible_tabla, editable, orden, activo,
  created_at, updated_at, estado_sync, eliminado
) values
  ('ausencia_id','MATRIZ_TIPOS_AUSENCIA_APPGT','id','ID','hidden','hidden',null,false,false,false,false,1,true,now(),now(),'sincronizado',false),
  ('ausencia_id_local','MATRIZ_TIPOS_AUSENCIA_APPGT','id_local','ID local','hidden','hidden',null,false,false,false,false,2,true,now(),now(),'sincronizado',false),
  ('ausencia_empresa','MATRIZ_TIPOS_AUSENCIA_APPGT','empresa_id','Empresa','hidden','hidden',null,false,false,false,false,3,true,now(),now(),'sincronizado',false),
  ('ausencia_codigo','MATRIZ_TIPOS_AUSENCIA_APPGT','codigo','Codigo','text','text',null,true,true,true,true,4,true,now(),now(),'sincronizado',false),
  ('ausencia_nombre','MATRIZ_TIPOS_AUSENCIA_APPGT','nombre','Nombre','text','text',null,true,true,true,true,5,true,now(),now(),'sincronizado',false),
  ('ausencia_descripcion','MATRIZ_TIPOS_AUSENCIA_APPGT','descripcion','Descripcion','text','multiline',null,false,true,true,true,6,true,now(),now(),'sincronizado',false),
  ('ausencia_goce','MATRIZ_TIPOS_AUSENCIA_APPGT','con_goce_haber','Con goce de haber','boolean','switch',null,true,true,true,true,7,true,now(),now(),'sincronizado',false),
  ('ausencia_documento','MATRIZ_TIPOS_AUSENCIA_APPGT','documento_requerido','Documento requerido','boolean','switch',null,true,true,true,true,8,true,now(),now(),'sincronizado',false),
  ('ausencia_activo','MATRIZ_TIPOS_AUSENCIA_APPGT','activo','Activo','hidden','hidden',null,false,false,false,false,9,true,now(),now(),'sincronizado',false)
on conflict (tabla_destino, campo) do update set
  etiqueta=excluded.etiqueta, tipo=excluded.tipo, tipo_ui=excluded.tipo_ui,
  requerido=excluded.requerido, visible=excluded.visible,
  visible_tabla=excluded.visible_tabla, editable=excluded.editable,
  orden=excluded.orden, activo=true, eliminado=false, updated_at=now();

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set tipo='text', tipo_ui='dropdown',
    id_campo_dropdown='MATRIZ_TIPOS_AUSENCIA_APPGT.nombre',
    requerido=true, visible=true, visible_tabla=true, editable=true,
    updated_at=now()
where upper(tabla_destino)='GH_PERMISOS_LICENCIAS_APPGT'
  and upper(campo)='TIPO_PERMISO';

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set tipo='document', tipo_ui='pdf', requerido=false,
    visible=true, visible_tabla=true, editable=true, updated_at=now()
where upper(tabla_destino)='GH_PERMISOS_LICENCIAS_APPGT'
  and upper(campo)='DOCUMENTO_SUSTENTO';

-- Los campos tecnicos nunca se muestran ni en formularios ni en tablas.
update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set visible=false, visible_tabla=false, editable=false, updated_at=now()
where
  lower(coalesce(tipo,'')) in ('hidden','hidden_id')
  or lower(coalesce(tipo_ui,'')) in ('hidden','hidden_id')
  or upper(regexp_replace(coalesce(campo,''),'[^A-Za-z0-9]+','_','g')) in (
    'ID','ID_LOCAL','ID_REGISTRO','ID_FILA_SERIAL','EMPRESA_ID','USER_ID',
    'CREATED_BY','UPDATED_BY','CREATED_AT','UPDATED_AT','DELETED_AT',
    'ESTADO_SYNC','VERSION','ACTIVO','ELIMINADO','HASH_FILA_SIN_IDS',
    'HASH_FILA_SIN_ID'
  )
  or upper(regexp_replace(coalesce(campo,''),'[^A-Za-z0-9]+','_','g')) like 'ID\_%' escape '\'
  or upper(regexp_replace(coalesce(campo,''),'[^A-Za-z0-9]+','_','g')) like '%\_ID' escape '\';

notify pgrst, 'reload schema';
commit;
