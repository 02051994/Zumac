begin;

-- Los formatos históricos de una sola tabla guardaban el destino directamente
-- en MATRIZ_FORMATOS_APPGT. El constructor, en cambio, solo recorría la tabla
-- intermedia. Se materializa el vínculo faltante sin duplicar estructuras que
-- ya fueron publicadas con varias tablas.
insert into public."MATRIZ_FORMATO_TABLAS_APPGT" (
  id,
  empresa_id,
  formato_id,
  nombre,
  tabla_destino,
  orden,
  activo,
  eliminado,
  deleted_at,
  estado_sync,
  es_cabecera,
  es_detalle,
  rubro_id
)
select
  md5('LEGACY_TABLE|' || f.empresa_id::text || '|' || f.id || '|' || f.tabla_destino),
  f.empresa_id,
  f.id,
  f.nombre,
  btrim(f.tabla_destino),
  0,
  true,
  false,
  null,
  'sincronizado',
  false,
  false,
  f.rubro_id
from public."MATRIZ_FORMATOS_APPGT" f
where coalesce(f.activo, true)
  and not coalesce(f.eliminado, false)
  and f.deleted_at is null
  and nullif(btrim(f.tabla_destino), '') is not null
  and not exists (
    select 1
    from public."MATRIZ_FORMATO_TABLAS_APPGT" t
    where t.empresa_id = f.empresa_id
      and t.formato_id = f.id
      and coalesce(t.activo, true)
      and not coalesce(t.eliminado, false)
      and t.deleted_at is null
  )
on conflict do nothing;

-- Publica una plantilla TABLA por cada vínculo vivo. Los campos ya contienen
-- tabla_destino en su definición, por lo que el lector de formato completo los
-- asocia incluso cuando dos formatos reutilizan una misma tabla física.
insert into public."PLANTILLAS_CONFIGURACION_APPGT" (
  id,
  empresa_id,
  paquete_id,
  rubro_id,
  entidad_tipo,
  entidad_origen_id,
  padre_tipo,
  padre_origen_id,
  codigo,
  nombre,
  origen,
  tipo_plantilla,
  definicion,
  editable,
  version,
  estado,
  es_actual,
  activo,
  published_at,
  deleted_at
)
select
  md5('TABLA|' || t.empresa_id::text || '|' || t.id)::uuid,
  t.empresa_id,
  pf.paquete_id,
  coalesce(t.rubro_id, pf.rubro_id),
  'TABLA',
  t.id,
  'FORMATO',
  t.formato_id,
  t.id,
  t.nombre,
  pf.origen,
  pf.tipo_plantilla,
  to_jsonb(t),
  pf.editable,
  1,
  'PUBLICADO',
  true,
  true,
  coalesce(pf.published_at, now()),
  null
from public."MATRIZ_FORMATO_TABLAS_APPGT" t
join lateral (
  select p.*
  from public."PLANTILLAS_CONFIGURACION_APPGT" p
  where p.empresa_id = t.empresa_id
    and p.entidad_tipo = 'FORMATO'
    and p.entidad_origen_id = t.formato_id
    and p.es_actual
    and p.activo
    and p.deleted_at is null
  order by p.version desc
  limit 1
) pf on true
where coalesce(t.activo, true)
  and not coalesce(t.eliminado, false)
  and t.deleted_at is null
on conflict (empresa_id, entidad_tipo, entidad_origen_id, version) do update set
  paquete_id = excluded.paquete_id,
  rubro_id = excluded.rubro_id,
  padre_tipo = excluded.padre_tipo,
  padre_origen_id = excluded.padre_origen_id,
  codigo = excluded.codigo,
  nombre = excluded.nombre,
  definicion = excluded.definicion,
  estado = 'PUBLICADO',
  es_actual = true,
  activo = true,
  deleted_at = null,
  updated_at = now();

-- Catálogo administrativo canónico. La función evita que las políticas RLS de
-- navegación reduzcan el catálogo a los formatos permitidos al propio admin.
create or replace function public.appgt_admin_permission_catalog_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
begin
  if v_empresa_id is null or not public.appgt_es_admin_empresa(v_empresa_id) then
    raise exception 'administrator permission required' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'secciones', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.orden, s.nombre, s.id)
      from public."MATRIZ_SECCIONES_APPGT" s
      where s.empresa_id = v_empresa_id
        and coalesce(s.activo, true)
        and not coalesce(s.eliminado, false)
        and s.deleted_at is null
    ), '[]'::jsonb),
    'modulos', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.orden, m.nombre, m.id)
      from public."MATRIZ_MODULOS_APPGT" m
      where m.empresa_id = v_empresa_id
        and coalesce(m.activo, true)
        and not coalesce(m.eliminado, false)
        and m.deleted_at is null
    ), '[]'::jsonb),
    'formatos', coalesce((
      select jsonb_agg(to_jsonb(f) order by f.orden, f.nombre, f.id)
      from public."MATRIZ_FORMATOS_APPGT" f
      where f.empresa_id = v_empresa_id
        and coalesce(f.activo, true)
        and not coalesce(f.eliminado, false)
        and f.deleted_at is null
    ), '[]'::jsonb)
  );
end
$$;

-- Devuelve las filas completas para que Flutter pueda resolver identificadores
-- históricos, tabla_destino, estado y herencia sin mezclar lecturas parciales.
create or replace function public.appgt_admin_user_access_v1(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
begin
  if v_empresa_id is null or not public.appgt_es_admin_empresa(v_empresa_id) then
    raise exception 'administrator permission required' using errcode = '42501';
  end if;
  if not public.appgt_validar_usuario_permisos_empresa(v_empresa_id, p_user_id) then
    raise exception 'target user does not belong to the active company';
  end if;

  return jsonb_build_object(
    'permisos_formatos', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.modulo, p.formato, p.created_at)
      from public."PERMISOS_DE_USUARIOS_APPGT" p
      where p.empresa_id = v_empresa_id and p.user_id = p_user_id
    ), '[]'::jsonb),
    'permisos_secciones', coalesce((
      select jsonb_agg(to_jsonb(p) order by coalesce(p.seccion_id, p.seccion), p.created_at)
      from public."PERMISOS_SECCIONES_APPGT" p
      where p.empresa_id = v_empresa_id and p.user_id = p_user_id
    ), '[]'::jsonb)
  );
end
$$;

revoke all on function public.appgt_admin_permission_catalog_v1()
  from public, anon;
revoke all on function public.appgt_admin_user_access_v1(uuid)
  from public, anon;
grant execute on function public.appgt_admin_permission_catalog_v1()
  to authenticated;
grant execute on function public.appgt_admin_user_access_v1(uuid)
  to authenticated;

do $$
begin
  if exists (
    select 1
    from public."MATRIZ_FORMATOS_APPGT" f
    where coalesce(f.activo, true)
      and not coalesce(f.eliminado, false)
      and f.deleted_at is null
      and nullif(btrim(f.tabla_destino), '') is not null
      and not exists (
        select 1
        from public."MATRIZ_FORMATO_TABLAS_APPGT" t
        where t.empresa_id = f.empresa_id
          and t.formato_id = f.id
          and coalesce(t.activo, true)
          and not coalesce(t.eliminado, false)
          and t.deleted_at is null
      )
  ) then
    raise exception 'format hierarchy backfill incomplete';
  end if;

  if exists (
    select 1
    from public."MATRIZ_FORMATO_TABLAS_APPGT" t
    where coalesce(t.activo, true)
      and not coalesce(t.eliminado, false)
      and t.deleted_at is null
      and not exists (
        select 1
        from public."PLANTILLAS_CONFIGURACION_APPGT" p
        where p.empresa_id = t.empresa_id
          and p.entidad_tipo = 'TABLA'
          and p.entidad_origen_id = t.id
          and p.padre_origen_id = t.formato_id
          and p.es_actual
          and p.activo
          and p.deleted_at is null
      )
  ) then
    raise exception 'table template backfill incomplete';
  end if;
end
$$;

notify pgrst, 'reload schema';

commit;
