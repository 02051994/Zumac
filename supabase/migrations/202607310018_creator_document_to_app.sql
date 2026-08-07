-- Zumac Creator: sesiones auditables para convertir fotos, imágenes y PDF
-- en borradores de formatos. Los binarios no se conservan en la base; sólo
-- se almacena su hash, metadatos, análisis y las correcciones del usuario.

create table if not exists public."IMPORTACIONES_FORMATO_IA_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  created_by uuid not null references auth.users(id),
  archivo_nombre text not null,
  mime_type text not null,
  tamano_bytes bigint not null check (tamano_bytes > 0 and tamano_bytes <= 18874368),
  hash_archivo text not null,
  tipo_origen text not null check (tipo_origen in ('CAMARA', 'GALERIA', 'PDF')),
  estado text not null default 'CARGADO' check (estado in (
    'CARGADO', 'CALIDAD_RECHAZADA', 'ANALIZANDO', 'REQUIERE_REVISION',
    'GENERADA_IA', 'CONVERTIDO_BORRADOR', 'APROBADA', 'ERROR'
  )),
  calidad_local jsonb not null default '{}'::jsonb,
  calidad_servidor jsonb not null default '{}'::jsonb,
  analisis_ia jsonb not null default '{}'::jsonb,
  definicion_revisada jsonb not null default '{}'::jsonb,
  fila_encabezados integer check (fila_encabezados is null or fila_encabezados > 0),
  layout_formulario text check (layout_formulario is null or layout_formulario in (
    'VERTICAL', 'DOS_COLUMNAS', 'SECCIONES', 'COMPACTO'
  )),
  layout_registros text check (layout_registros is null or layout_registros in (
    'TABLA', 'TARJETAS', 'LISTA'
  )),
  modelo_ia text,
  borrador_id uuid references public."BORRADORES_CONFIGURACION_APPGT"(id),
  error_mensaje text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_importaciones_formato_ia_empresa
  on public."IMPORTACIONES_FORMATO_IA_APPGT"
  (empresa_id, updated_at desc);
create index if not exists idx_importaciones_formato_ia_hash
  on public."IMPORTACIONES_FORMATO_IA_APPGT"
  (empresa_id, hash_archivo, created_at desc);

alter table public."IMPORTACIONES_FORMATO_IA_APPGT" enable row level security;

drop policy if exists importaciones_formato_ia_select on public."IMPORTACIONES_FORMATO_IA_APPGT";
create policy importaciones_formato_ia_select
  on public."IMPORTACIONES_FORMATO_IA_APPGT"
  for select to authenticated
  using (
    empresa_id = public.appgt_empresa_actual_id()
    and public.appgt_puede_gestionar_configuracion(empresa_id)
  );

create or replace function public.appgt_crear_importacion_formato_ia_v1(
  p_archivo_nombre text,
  p_mime_type text,
  p_tamano_bytes bigint,
  p_hash_archivo text,
  p_tipo_origen text,
  p_calidad_local jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_row public."IMPORTACIONES_FORMATO_IA_APPGT";
  v_mime text := lower(btrim(coalesce(p_mime_type, '')));
  v_origen text := upper(btrim(coalesce(p_tipo_origen, '')));
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'configuration manager permission required'
      using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_archivo_nombre, '')), '') is null then
    raise exception 'file name required';
  end if;
  if v_mime not in ('image/jpeg', 'image/png', 'image/webp', 'application/pdf') then
    raise exception 'unsupported document type';
  end if;
  if p_tamano_bytes is null or p_tamano_bytes <= 0 or p_tamano_bytes > 18874368 then
    raise exception 'file size must be between 1 byte and 18 MB';
  end if;
  if coalesce(p_hash_archivo, '') !~ '^[a-f0-9]{64}$' then
    raise exception 'invalid SHA-256 file hash';
  end if;
  if v_origen not in ('CAMARA', 'GALERIA', 'PDF') then
    raise exception 'invalid import source';
  end if;

  insert into public."IMPORTACIONES_FORMATO_IA_APPGT" (
    empresa_id, created_by, archivo_nombre, mime_type, tamano_bytes,
    hash_archivo, tipo_origen, estado, calidad_local
  ) values (
    v_empresa_id, auth.uid(), btrim(p_archivo_nombre), v_mime, p_tamano_bytes,
    lower(p_hash_archivo), v_origen,
    case when coalesce((p_calidad_local ->> 'aceptable')::boolean, true)
      then 'CARGADO' else 'CALIDAD_RECHAZADA' end,
    coalesce(p_calidad_local, '{}'::jsonb)
  ) returning * into v_row;

  insert into public."AUDITORIA_CONFIGURACION_APPGT" (
    empresa_id, entidad_tipo, entidad_id, accion, estado_nuevo,
    datos_despues, metadata, user_id
  ) values (
    v_empresa_id, 'FORMATO', v_row.id::text, 'CREAR_IMPORTACION_IA',
    v_row.estado, to_jsonb(v_row),
    jsonb_build_object('hash_archivo', v_row.hash_archivo), auth.uid()
  );

  return to_jsonb(v_row);
end
$$;

create or replace function public.appgt_actualizar_importacion_formato_ia_v1(
  p_importacion_id uuid,
  p_estado text,
  p_calidad_servidor jsonb default null,
  p_analisis_ia jsonb default null,
  p_definicion_revisada jsonb default null,
  p_fila_encabezados integer default null,
  p_layout_formulario text default null,
  p_layout_registros text default null,
  p_borrador_id uuid default null,
  p_modelo_ia text default null,
  p_error_mensaje text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_estado text := upper(btrim(coalesce(p_estado, '')));
  v_before public."IMPORTACIONES_FORMATO_IA_APPGT";
  v_row public."IMPORTACIONES_FORMATO_IA_APPGT";
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'configuration manager permission required'
      using errcode = '42501';
  end if;
  if v_estado not in (
    'CARGADO', 'CALIDAD_RECHAZADA', 'ANALIZANDO', 'REQUIERE_REVISION',
    'GENERADA_IA', 'CONVERTIDO_BORRADOR', 'APROBADA', 'ERROR'
  ) then
    raise exception 'invalid import status';
  end if;
  if p_fila_encabezados is not null and p_fila_encabezados <= 0 then
    raise exception 'header row must be positive';
  end if;
  if p_layout_formulario is not null and upper(p_layout_formulario) not in (
    'VERTICAL', 'DOS_COLUMNAS', 'SECCIONES', 'COMPACTO'
  ) then
    raise exception 'invalid form layout';
  end if;
  if p_layout_registros is not null and upper(p_layout_registros) not in (
    'TABLA', 'TARJETAS', 'LISTA'
  ) then
    raise exception 'invalid records layout';
  end if;
  if p_borrador_id is not null and not exists (
    select 1 from public."BORRADORES_CONFIGURACION_APPGT" b
    where b.id = p_borrador_id and b.empresa_id = v_empresa_id
      and b.entidad_tipo = 'FORMATO' and b.deleted_at is null
  ) then
    raise exception 'format draft not found';
  end if;

  select * into v_before
  from public."IMPORTACIONES_FORMATO_IA_APPGT"
  where id = p_importacion_id and empresa_id = v_empresa_id
  for update;
  if v_before.id is null then
    raise exception 'AI import not found';
  end if;

  update public."IMPORTACIONES_FORMATO_IA_APPGT" set
    estado = v_estado,
    calidad_servidor = coalesce(p_calidad_servidor, calidad_servidor),
    analisis_ia = coalesce(p_analisis_ia, analisis_ia),
    definicion_revisada = coalesce(p_definicion_revisada, definicion_revisada),
    fila_encabezados = coalesce(p_fila_encabezados, fila_encabezados),
    layout_formulario = coalesce(upper(p_layout_formulario), layout_formulario),
    layout_registros = coalesce(upper(p_layout_registros), layout_registros),
    borrador_id = coalesce(p_borrador_id, borrador_id),
    modelo_ia = coalesce(nullif(btrim(p_modelo_ia), ''), modelo_ia),
    error_mensaje = case when v_estado = 'ERROR'
      then p_error_mensaje else null end,
    updated_at = now()
  where id = p_importacion_id
  returning * into v_row;

  insert into public."AUDITORIA_CONFIGURACION_APPGT" (
    empresa_id, borrador_id, entidad_tipo, entidad_id, accion,
    estado_anterior, estado_nuevo, datos_antes, datos_despues, user_id
  ) values (
    v_empresa_id, v_row.borrador_id, 'FORMATO', v_row.id::text,
    'ACTUALIZAR_IMPORTACION_IA', v_before.estado, v_row.estado,
    to_jsonb(v_before), to_jsonb(v_row), auth.uid()
  );

  return to_jsonb(v_row);
end
$$;

revoke all on table public."IMPORTACIONES_FORMATO_IA_APPGT" from public, anon, authenticated;
grant select on table public."IMPORTACIONES_FORMATO_IA_APPGT" to authenticated;

revoke all on function public.appgt_crear_importacion_formato_ia_v1(
  text, text, bigint, text, text, jsonb
) from public, anon;
revoke all on function public.appgt_actualizar_importacion_formato_ia_v1(
  uuid, text, jsonb, jsonb, jsonb, integer, text, text, uuid, text, text
) from public, anon;
grant execute on function public.appgt_crear_importacion_formato_ia_v1(
  text, text, bigint, text, text, jsonb
) to authenticated;
grant execute on function public.appgt_actualizar_importacion_formato_ia_v1(
  uuid, text, jsonb, jsonb, jsonb, integer, text, text, uuid, text, text
) to authenticated;

-- Lleva las decisiones de diseño al runtime publicado. Los campos generados
-- también guardan grid_fila/grid_columna, por lo que el formulario funciona
-- offline incluso en clientes que aún no muestran estos metadatos raíz.
alter table public."MATRIZ_FORMATOS_APPGT"
  add column if not exists layout_formulario text not null default 'VERTICAL'
    check (layout_formulario in ('VERTICAL', 'DOS_COLUMNAS', 'SECCIONES', 'COMPACTO')),
  add column if not exists layout_registros text not null default 'TABLA'
    check (layout_registros in ('TABLA', 'TARJETAS', 'LISTA')),
  add column if not exists origen_creador jsonb not null default '{}'::jsonb,
  add column if not exists estado_revision_ia text not null default 'APROBADA'
    check (estado_revision_ia in ('GENERADA_IA', 'APROBADA'));

create or replace function public.appgt_expandir_formato_desde_borrador()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payload jsonb;
  v_capabilities jsonb;
begin
  select b.definicion
  into v_payload
  from public."BORRADORES_CONFIGURACION_APPGT" b
  where b.empresa_id = new.empresa_id
    and b.entidad_tipo = 'FORMATO'
    and b.codigo = new.id
    and b.deleted_at is null
  order by b.updated_at desc
  limit 1;

  if v_payload is null then return new; end if;

  v_capabilities := coalesce(v_payload -> 'capacidades', '{}'::jsonb);
  new.capacidades := v_capabilities;
  new.flujo_estados := coalesce(v_payload -> 'flujo_estados', '[]'::jsonb);
  new.workflow_enabled :=
    lower(coalesce(v_capabilities ->> 'workflow', 'false')) in ('true','1','yes','si','sí');
  new.geolocation_enabled :=
    lower(coalesce(v_capabilities ->> 'geolocalizacion', 'false')) in ('true','1','yes','si','sí');
  new.approvals_enabled :=
    lower(coalesce(v_capabilities ->> 'aprobaciones', 'false')) in ('true','1','yes','si','sí');
  new.layout_formulario := case upper(coalesce(v_payload ->> 'layout_formulario', 'VERTICAL'))
    when 'DOS_COLUMNAS' then 'DOS_COLUMNAS'
    when 'SECCIONES' then 'SECCIONES'
    when 'COMPACTO' then 'COMPACTO'
    else 'VERTICAL'
  end;
  new.layout_registros := case upper(coalesce(v_payload ->> 'layout_registros', 'TABLA'))
    when 'TARJETAS' then 'TARJETAS'
    when 'LISTA' then 'LISTA'
    else 'TABLA'
  end;
  new.origen_creador := coalesce(v_payload -> 'origen_creador', '{}'::jsonb);
  -- Llegar a esta inserción significa que un administrador ejecutó la
  -- publicación normal del Creator; hasta entonces el borrador fue GENERADA_IA.
  new.estado_revision_ia := 'APROBADA';
  return new;
end
$$;

create or replace function public.appgt_marcar_importacion_ia_aprobada()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_import_id text := new.origen_creador ->> 'importacion_id';
begin
  if v_import_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    update public."IMPORTACIONES_FORMATO_IA_APPGT"
    set estado = 'APROBADA', updated_at = now(), error_mensaje = null
    where id = v_import_id::uuid and empresa_id = new.empresa_id;
  end if;
  return new;
end
$$;

drop trigger if exists appgt_marcar_importacion_ia_aprobada_trigger
  on public."MATRIZ_FORMATOS_APPGT";
create trigger appgt_marcar_importacion_ia_aprobada_trigger
after insert on public."MATRIZ_FORMATOS_APPGT"
for each row execute function public.appgt_marcar_importacion_ia_aprobada();

comment on table public."IMPORTACIONES_FORMATO_IA_APPGT" is
  'Sesiones auditables de Documento a App. GENERADA_IA exige revisión humana y nunca equivale a publicación.';
