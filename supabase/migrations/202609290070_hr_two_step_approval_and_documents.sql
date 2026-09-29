begin;

-- El sustento solo es obligatorio para los cuatro tipos que generan un
-- documento externo al trabajador. La regla queda también en servidor para
-- que una versión antigua de la aplicación no pueda omitirla.
update public."MATRIZ_TIPOS_AUSENCIA_APPGT"
set documento_requerido = public.appgt_normalizar_clave(nombre) in (
      'DESCANSOMEDICO',
      'LICENCIADEMATERNIDAD',
      'LICENCIADEPATERNIDAD',
      'LICENCIAPORFALLECIMIENTO'
    ),
    updated_at = now()
where not coalesce(eliminado, false);

create or replace function public.appgt_gh_permisos_preparar_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tipo record;
  v_requiere_documento boolean;
begin
  select t.con_goce_haber
    into v_tipo
  from public."MATRIZ_TIPOS_AUSENCIA_APPGT" t
  where t.empresa_id = new.empresa_id
    and public.appgt_normalizar_clave(t.nombre) =
        public.appgt_normalizar_clave(new.tipo_permiso)
    and coalesce(t.activo, true)
    and not coalesce(t.eliminado, false)
  limit 1;

  if not found then
    raise exception 'El tipo de permiso o licencia seleccionado ya no esta disponible.';
  end if;

  v_requiere_documento := public.appgt_normalizar_clave(new.tipo_permiso) in (
    'DESCANSOMEDICO',
    'LICENCIADEMATERNIDAD',
    'LICENCIADEPATERNIDAD',
    'LICENCIAPORFALLECIMIENTO'
  );
  if v_requiere_documento
      and nullif(btrim(coalesce(new.documento_sustento, '')), '') is null then
    raise exception 'Debe adjuntar el documento de sustento en formato PDF.';
  end if;
  if not v_requiere_documento then
    new.documento_sustento := null;
  end if;

  new.con_goce_haber := coalesce(v_tipo.con_goce_haber, true);
  new.dias_solicitados := greatest(1, new.fecha_fin - new.fecha_inicio + 1);
  new.updated_at := now();
  new.updated_by := auth.uid();
  if tg_op = 'UPDATE' then new.version := old.version + 1; end if;
  return new;
end
$$;

-- La aprobación completa datos de la constancia, pero el PDF real solo se
-- registra en documento_generado después de que la web lo crea y almacena.
create or replace function public.appgt_permiso_aprobacion_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa public."EMPRESAS_APPGT"%rowtype;
begin
  if old."ESTADO_APROBACION" is distinct from new."ESTADO_APROBACION"
     and new."ESTADO_APROBACION" in ('APROBADO','RECHAZADO','ANULADO')
     and not public.appgt_puede_accion_tabla_v1(
       'GH_PERMISOS_LICENCIAS_APPGT','APROBAR'
     ) then
    raise exception 'No tiene permiso para resolver permisos o licencias.'
      using errcode='42501';
  end if;
  if new."ESTADO_APROBACION" = 'APROBADO'
     and old."ESTADO_APROBACION" is distinct from 'APROBADO' then
    select * into v_empresa
    from public."EMPRESAS_APPGT"
    where id = new.empresa_id;
    new.estado := 'APROBADO';
    new.aprobado_por := auth.uid();
    new.fecha_aprobacion := now();
    new.fecha_reincorporacion := new.fecha_fin + 1;
    new.empresa_nombre := coalesce(new.empresa_nombre, v_empresa.nombre);
    new.empresa_ruc := coalesce(new.empresa_ruc, v_empresa.ruc);
    new.representante_nombre := coalesce(
      new.representante_nombre, v_empresa.representante_legal
    );
    new.representante_cargo := coalesce(
      new.representante_cargo, v_empresa.representante_cargo
    );
    new.lugar_emision := coalesce(new.lugar_emision, v_empresa.ciudad_emision);
  elsif new."ESTADO_APROBACION" = 'RECHAZADO' then
    new.estado := 'RECHAZADO';
  elsif new."ESTADO_APROBACION" = 'ANULADO' then
    new.estado := 'ANULADO';
  end if;
  return new;
end
$$;

alter table public."GH_SANCIONES_PERSONAL_APPGT"
  add column if not exists "ESTADO_APROBACION" text not null default 'PENDIENTE',
  add column if not exists aprobado_por uuid references auth.users(id),
  add column if not exists fecha_aprobacion timestamptz,
  add column if not exists documento_generado text;

alter table public."GH_SANCIONES_PERSONAL_APPGT"
  alter column estado set default 'BORRADOR';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public."GH_SANCIONES_PERSONAL_APPGT"'::regclass
      and conname = 'gh_sanciones_estado_aprobacion_check'
  ) then
    alter table public."GH_SANCIONES_PERSONAL_APPGT"
      add constraint gh_sanciones_estado_aprobacion_check
      check ("ESTADO_APROBACION" in (
        'PENDIENTE','REVISADO','APROBADO','RECHAZADO','ANULADO'
      ));
  end if;
end
$$;

-- Las sanciones ya vigentes antes de esta migración se consideran aprobadas;
-- así no se pierde ningún bloqueo histórico válido.
update public."GH_SANCIONES_PERSONAL_APPGT"
set "ESTADO_APROBACION" = case
      when estado in ('VIGENTE','CUMPLIDA') then 'APROBADO'
      when estado = 'ANULADA' then 'ANULADO'
      else 'PENDIENTE'
    end,
    fecha_aprobacion = case
      when estado in ('VIGENTE','CUMPLIDA')
        then coalesce(fecha_aprobacion, updated_at, created_at)
      else fecha_aprobacion
    end
where "ESTADO_APROBACION" = 'PENDIENTE';

create or replace function public.appgt_sancion_aprobacion_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if (tg_op = 'INSERT' or
      old."ESTADO_APROBACION" is distinct from new."ESTADO_APROBACION")
     and new."ESTADO_APROBACION" in ('APROBADO','RECHAZADO','ANULADO')
     and not public.appgt_puede_accion_tabla_v1(
       'GH_SANCIONES_PERSONAL_APPGT','APROBAR'
     ) then
    raise exception 'No tiene permiso para resolver sanciones.'
      using errcode='42501';
  end if;
  if new."ESTADO_APROBACION" = 'APROBADO' then
    new.estado := case
      when tg_op = 'UPDATE' and old.estado = 'CUMPLIDA' then 'CUMPLIDA'
      else 'VIGENTE'
    end;
    if tg_op = 'INSERT'
       or old."ESTADO_APROBACION" is distinct from 'APROBADO' then
      new.aprobado_por := auth.uid();
      new.fecha_aprobacion := now();
    end if;
  elsif new."ESTADO_APROBACION" = 'ANULADO' then
    new.estado := 'ANULADA';
  elsif new."ESTADO_APROBACION" in ('PENDIENTE','REVISADO','RECHAZADO') then
    new.estado := 'BORRADOR';
    new.aprobado_por := null;
    new.fecha_aprobacion := null;
  end if;
  return new;
end
$$;

drop trigger if exists zz_appgt_sancion_aprobacion_trigger
  on public."GH_SANCIONES_PERSONAL_APPGT";
create trigger zz_appgt_sancion_aprobacion_trigger
before insert or update of "ESTADO_APROBACION"
on public."GH_SANCIONES_PERSONAL_APPGT"
for each row execute function public.appgt_sancion_aprobacion_v1();

-- El campo se conserva físicamente para no destruir datos históricos, pero
-- deja de existir en el formulario y en la tabla de sanciones.
update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set requerido=false, visible=false, visible_tabla=false, editable=false,
    activo=false, eliminado=true, updated_at=now()
where upper(tabla_destino)='GH_SANCIONES_PERSONAL_APPGT'
  and upper(campo)='DOCUMENTO_SUSTENTO';

insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id, tabla_destino, campo, etiqueta, tipo, tipo_ui, id_campo_dropdown,
  requerido, visible, visible_tabla, editable, orden, activo,
  created_at, updated_at, estado_sync, eliminado
) values
  ('gh_san_aprobacion','GH_SANCIONES_PERSONAL_APPGT','ESTADO_APROBACION',
   'Estado de aprobación','text','readonly',null,false,false,true,false,10,
   true,now(),now(),'sincronizado',false),
  ('gh_san_documento_generado','GH_SANCIONES_PERSONAL_APPGT','documento_generado',
   'Documento generado','document','pdf',null,false,false,true,false,11,
   true,now(),now(),'sincronizado',false),
  ('gh_perm_documento','GH_PERMISOS_LICENCIAS_APPGT','documento_generado',
   'Documento generado','document','pdf',null,false,false,true,false,18,
   true,now(),now(),'sincronizado',false)
on conflict (tabla_destino, campo) do update set
  etiqueta=excluded.etiqueta, tipo=excluded.tipo, tipo_ui=excluded.tipo_ui,
  requerido=excluded.requerido, visible=excluded.visible,
  visible_tabla=excluded.visible_tabla, editable=excluded.editable,
  orden=excluded.orden, activo=true, eliminado=false, updated_at=now();

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set tipo='document', tipo_ui='pdf', requerido=false,
    visible=true, visible_tabla=true, editable=true,
    activo=true, eliminado=false, updated_at=now()
where upper(tabla_destino)='GH_PERMISOS_LICENCIAS_APPGT'
  and upper(campo)='DOCUMENTO_SUSTENTO';

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set visible=false, visible_tabla=true, editable=false, updated_at=now()
where upper(tabla_destino) in (
    'GH_PERMISOS_LICENCIAS_APPGT','GH_SANCIONES_PERSONAL_APPGT'
  )
  and upper(campo) in ('ESTADO','ESTADO_APROBACION','DOCUMENTO_GENERADO');

update public."MATRIZ_FORMATOS_APPGT"
set capacidades = coalesce(capacidades, '{}'::jsonb) ||
      '{"aprobaciones":true,"documento_laboral":true}'::jsonb,
    auditable=true, updated_at=now()
where upper(coalesce(tabla_destino,'')) in (
  'GH_PERMISOS_LICENCIAS_APPGT','GH_SANCIONES_PERSONAL_APPGT'
);

create or replace function public.appgt_documento_laboral_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_folder text := case
    when tg_table_name = 'GH_PERMISOS_LICENCIAS_APPGT' then 'permisos'
    else 'sanciones'
  end;
  v_prefix text;
begin
  if new.documento_generado is not distinct from old.documento_generado then
    return new;
  end if;
  if nullif(btrim(coalesce(new.documento_generado, '')), '') is null then
    return new;
  end if;
  if new."ESTADO_APROBACION" <> 'APROBADO' then
    raise exception 'El documento solo puede registrarse después de aprobar.';
  end if;
  if not public.appgt_puede_accion_tabla_v1(tg_table_name, 'APROBAR') then
    raise exception 'No tiene permiso para generar el documento laboral.';
  end if;
  v_prefix := 'storage://documentos-laborales/' || new.empresa_id::text ||
    '/' || v_folder || '/';
  if new.documento_generado not like v_prefix || '%' then
    raise exception 'La ruta del documento laboral no pertenece a la empresa.';
  end if;
  return new;
end
$$;

drop trigger if exists zz_appgt_permiso_documento_laboral_guard
  on public."GH_PERMISOS_LICENCIAS_APPGT";
create trigger zz_appgt_permiso_documento_laboral_guard
before update of documento_generado
on public."GH_PERMISOS_LICENCIAS_APPGT"
for each row execute function public.appgt_documento_laboral_guard_v1();

drop trigger if exists zz_appgt_sancion_documento_laboral_guard
  on public."GH_SANCIONES_PERSONAL_APPGT";
create trigger zz_appgt_sancion_documento_laboral_guard
before update of documento_generado
on public."GH_SANCIONES_PERSONAL_APPGT"
for each row execute function public.appgt_documento_laboral_guard_v1();

-- PDFs laborales privados. La ruta obligatoria es:
-- empresa_id/{permisos|sanciones}/registro/archivo.pdf.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'documentos-laborales', 'documentos-laborales', false, 15728640,
  array['application/pdf']::text[]
)
on conflict (id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists documentos_laborales_select on storage.objects;
create policy documentos_laborales_select on storage.objects
for select to authenticated
using (
  bucket_id='documentos-laborales'
  and coalesce((storage.foldername(name))[1], '') ~
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and public.appgt_puede_acceder_empresa(
    ((storage.foldername(name))[1])::uuid
  )
  and ((storage.foldername(name))[1])::uuid = public.appgt_empresa_actual_id()
  and case lower(coalesce((storage.foldername(name))[2], ''))
    when 'permisos' then public.appgt_puede_accion_tabla_v1(
      'GH_PERMISOS_LICENCIAS_APPGT','VER'
    )
    when 'sanciones' then public.appgt_puede_accion_tabla_v1(
      'GH_SANCIONES_PERSONAL_APPGT','VER'
    )
    else false
  end
);

drop policy if exists documentos_laborales_insert on storage.objects;
create policy documentos_laborales_insert on storage.objects
for insert to authenticated
with check (
  bucket_id='documentos-laborales'
  and coalesce((storage.foldername(name))[1], '') ~
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and public.appgt_puede_acceder_empresa(
    ((storage.foldername(name))[1])::uuid
  )
  and ((storage.foldername(name))[1])::uuid = public.appgt_empresa_actual_id()
  and case lower(coalesce((storage.foldername(name))[2], ''))
    when 'permisos' then public.appgt_puede_accion_tabla_v1(
      'GH_PERMISOS_LICENCIAS_APPGT','APROBAR'
    )
    when 'sanciones' then public.appgt_puede_accion_tabla_v1(
      'GH_SANCIONES_PERSONAL_APPGT','APROBAR'
    )
    else false
  end
);

drop policy if exists documentos_laborales_update on storage.objects;
create policy documentos_laborales_update on storage.objects
for update to authenticated
using (
  bucket_id='documentos-laborales'
  and coalesce((storage.foldername(name))[1], '') ~
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and ((storage.foldername(name))[1])::uuid = public.appgt_empresa_actual_id()
  and case lower(coalesce((storage.foldername(name))[2], ''))
    when 'permisos' then public.appgt_puede_accion_tabla_v1(
      'GH_PERMISOS_LICENCIAS_APPGT','APROBAR'
    )
    when 'sanciones' then public.appgt_puede_accion_tabla_v1(
      'GH_SANCIONES_PERSONAL_APPGT','APROBAR'
    )
    else false
  end
)
with check (
  bucket_id='documentos-laborales'
  and coalesce((storage.foldername(name))[1], '') ~
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and ((storage.foldername(name))[1])::uuid = public.appgt_empresa_actual_id()
  and case lower(coalesce((storage.foldername(name))[2], ''))
    when 'permisos' then public.appgt_puede_accion_tabla_v1(
      'GH_PERMISOS_LICENCIAS_APPGT','APROBAR'
    )
    when 'sanciones' then public.appgt_puede_accion_tabla_v1(
      'GH_SANCIONES_PERSONAL_APPGT','APROBAR'
    )
    else false
  end
);

drop policy if exists documentos_laborales_delete on storage.objects;
create policy documentos_laborales_delete on storage.objects
for delete to authenticated
using (
  bucket_id='documentos-laborales'
  and coalesce((storage.foldername(name))[1], '') ~
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and ((storage.foldername(name))[1])::uuid = public.appgt_empresa_actual_id()
  and case lower(coalesce((storage.foldername(name))[2], ''))
    when 'permisos' then public.appgt_puede_accion_tabla_v1(
      'GH_PERMISOS_LICENCIAS_APPGT','APROBAR'
    )
    when 'sanciones' then public.appgt_puede_accion_tabla_v1(
      'GH_SANCIONES_PERSONAL_APPGT','APROBAR'
    )
    else false
  end
);

notify pgrst, 'reload schema';
commit;
