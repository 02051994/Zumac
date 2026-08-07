begin;

-- En la base productiva los identificadores de ambas matrices de permisos son
-- TEXT. Las versiones anteriores declaraban la variable local como UUID y la
-- asignación fallaba antes de insertar o actualizar.
create or replace function public.appgt_admin_upsert_section_permission(
  p_user_id uuid,
  p_seccion_id text,
  p_can_view boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_id text;
begin
  if v_empresa_id is null or not public.appgt_es_admin_empresa(v_empresa_id) then
    raise exception 'administrator permission required' using errcode = '42501';
  end if;
  if not public.appgt_validar_usuario_permisos_empresa(v_empresa_id, p_user_id) then
    raise exception 'target user does not belong to the active company';
  end if;
  if not exists (
    select 1
    from public."MATRIZ_SECCIONES_APPGT" s
    where s.empresa_id = v_empresa_id
      and s.id = p_seccion_id
      and coalesce(s.activo, true)
  ) then
    raise exception 'active section not found';
  end if;

  select p.id
  into v_id
  from public."PERMISOS_SECCIONES_APPGT" p
  where p.empresa_id = v_empresa_id
    and p.user_id = p_user_id
    and coalesce(nullif(btrim(p.seccion), ''), btrim(p.seccion_id)) = p_seccion_id
  order by p.updated_at desc nulls last
  limit 1;

  if v_id is null then
    insert into public."PERMISOS_SECCIONES_APPGT" (
      empresa_id, user_id, seccion, seccion_id,
      can_view, can_insert, can_update, can_delete, activo, eliminado
    ) values (
      v_empresa_id, p_user_id, p_seccion_id, p_seccion_id,
      p_can_view, false, false, false, true, false
    ) returning id into v_id;
  else
    update public."PERMISOS_SECCIONES_APPGT" set
      seccion = p_seccion_id,
      seccion_id = p_seccion_id,
      can_view = p_can_view,
      activo = true,
      eliminado = false,
      updated_at = now()
    where id = v_id;
  end if;

  return jsonb_build_object('id', v_id, 'guardado', true);
end;
$$;

create or replace function public.appgt_admin_upsert_user_permission_v3(
  p_user_id uuid,
  p_modulo text,
  p_formato text,
  p_can_view boolean,
  p_can_insert boolean,
  p_can_update boolean,
  p_can_delete boolean,
  p_can_export boolean default false,
  p_can_import boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_id text;
  v_seccion_id text;
  v_modulo_id text;
  v_formato_id text;
  v_tabla_destino text;
begin
  if v_empresa_id is null or not public.appgt_es_admin_empresa(v_empresa_id) then
    raise exception 'administrator permission required' using errcode = '42501';
  end if;
  if not public.appgt_validar_usuario_permisos_empresa(v_empresa_id, p_user_id) then
    raise exception 'target user does not belong to the active company';
  end if;

  select
    m.seccion,
    m.id,
    f.id,
    coalesce(t.tabla_destino, f.tabla_destino)
  into v_seccion_id, v_modulo_id, v_formato_id, v_tabla_destino
  from public."MATRIZ_FORMATOS_APPGT" f
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id = f.empresa_id
   and m.id = f.modulo_id
  left join lateral (
    select ft.tabla_destino
    from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
    where ft.empresa_id = f.empresa_id
      and ft.formato_id = f.id
      and coalesce(ft.activo, true)
      and ft.deleted_at is null
    order by ft.orden, ft.id
    limit 1
  ) t on true
  where f.empresa_id = v_empresa_id
    and (f.id = p_formato or f.tabla_destino = p_formato)
    and f.modulo_id = p_modulo
    and coalesce(f.activo, true)
    and f.deleted_at is null
    and coalesce(m.activo, true)
    and m.deleted_at is null
  limit 1;

  if v_seccion_id is null or v_tabla_destino is null then
    raise exception 'active format/module/table hierarchy not found';
  end if;

  select p.id
  into v_id
  from public."PERMISOS_DE_USUARIOS_APPGT" p
  where p.empresa_id = v_empresa_id
    and p.user_id = p_user_id
    and p.modulo = v_modulo_id
    and p.formato = v_formato_id
  order by p.updated_at desc nulls last
  limit 1;

  if v_id is null then
    insert into public."PERMISOS_DE_USUARIOS_APPGT" (
      empresa_id, user_id, seccion, modulo, formato, tabla_destino,
      can_view, can_insert, can_update, can_delete, can_export, can_import,
      activo, eliminado
    ) values (
      v_empresa_id, p_user_id, v_seccion_id, v_modulo_id, v_formato_id,
      v_tabla_destino, p_can_view, p_can_insert, p_can_update, p_can_delete,
      p_can_export, p_can_import, true, false
    ) returning id into v_id;
  else
    update public."PERMISOS_DE_USUARIOS_APPGT" set
      seccion = v_seccion_id,
      tabla_destino = v_tabla_destino,
      can_view = p_can_view,
      can_insert = p_can_insert,
      can_update = p_can_update,
      can_delete = p_can_delete,
      can_export = p_can_export,
      can_import = p_can_import,
      activo = true,
      eliminado = false,
      updated_at = now()
    where id = v_id;
  end if;

  return jsonb_build_object(
    'id', v_id,
    'guardado', true,
    'seccion', v_seccion_id,
    'modulo', v_modulo_id,
    'formato', v_formato_id,
    'tabla_destino', v_tabla_destino
  );
end;
$$;

-- Conserva compatibilidad con clientes anteriores sin duplicar la lógica.
create or replace function public.appgt_admin_upsert_user_permission_v2(
  p_user_id uuid,
  p_modulo text,
  p_formato text,
  p_can_view boolean,
  p_can_insert boolean,
  p_can_update boolean,
  p_can_delete boolean,
  p_can_export boolean default false,
  p_can_import boolean default false
)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.appgt_admin_upsert_user_permission_v3(
    p_user_id,
    p_modulo,
    p_formato,
    p_can_view,
    p_can_insert,
    p_can_update,
    p_can_delete,
    p_can_export,
    p_can_import
  );
$$;

-- `translate` y otras expresiones usadas por estas funciones son STABLE en
-- PostgreSQL; declarar la misma volatilidad elimina planes incorrectos.
alter function public.appgt_perfil_tecnico_agro_v1(text) stable;
alter function public.appgt_documentacion_formato_v1(text,text,text,text,jsonb) stable;

revoke all on function public.appgt_admin_upsert_section_permission(
  uuid,text,boolean
) from public, anon;
grant execute on function public.appgt_admin_upsert_section_permission(
  uuid,text,boolean
) to authenticated;

revoke all on function public.appgt_admin_upsert_user_permission_v2(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean
) from public, anon;
grant execute on function public.appgt_admin_upsert_user_permission_v2(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean
) to authenticated;

revoke all on function public.appgt_admin_upsert_user_permission_v3(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean
) from public, anon;
grant execute on function public.appgt_admin_upsert_user_permission_v3(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean
) to authenticated;

notify pgrst, 'reload schema';

commit;
