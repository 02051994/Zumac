begin;

-- Conserva todos los parámetros de MATRIZ_CAMPOS_FORMATO_APPGT al publicar
-- desde el constructor. La publicación base crea la fila con los campos
-- esenciales; este trigger completa automáticamente cualquier columna real
-- cuyo nombre también exista en la definición JSON del borrador.
create or replace function public.appgt_expandir_campo_desde_borrador()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payload jsonb;
  v_numeric_key text;
begin
  select b.definicion
  into v_payload
  from public."BORRADORES_CONFIGURACION_APPGT" b
  where b.empresa_id = new.empresa_id
    and b.entidad_tipo = 'CAMPO'
    and b.codigo = new.id
    and b.deleted_at is null
    and b.definicion ->> 'tabla_destino' = new.tabla_destino
    and b.definicion ->> 'campo' = new.campo
  order by b.updated_at desc
  limit 1;

  if v_payload is null then
    return new;
  end if;

  -- Los controles vacíos significan NULL. Evita convertir '' a numeric/int.
  foreach v_numeric_key in array array[
    'orden', 'numero_decimales', 'grid_fila', 'grid_columna',
    'grid_fila_pendientes', 'grid_columna_pendientes', 'num_caracteres',
    'numero_fotos', 'orden_lista_photo', 'fila_sub_titulo'
  ] loop
    if jsonb_typeof(v_payload -> v_numeric_key) = 'string'
       and btrim(coalesce(v_payload ->> v_numeric_key, '')) = '' then
      v_payload := v_payload - v_numeric_key;
    end if;
  end loop;

  v_payload := v_payload - array[
    'id', 'empresa_id', 'tabla_destino', 'campo', 'created_at',
    'updated_at', 'deleted_at', 'created_by', 'updated_by',
    'estado_sync', 'eliminado'
  ];
  new := jsonb_populate_record(new, jsonb_strip_nulls(v_payload));
  return new;
end
$$;

drop trigger if exists appgt_00_expandir_campo_desde_borrador_trigger
  on public."MATRIZ_CAMPOS_FORMATO_APPGT";
create trigger appgt_00_expandir_campo_desde_borrador_trigger
before insert on public."MATRIZ_CAMPOS_FORMATO_APPGT"
for each row execute function public.appgt_expandir_campo_desde_borrador();

-- El borrador se archiva lógicamente. Nunca se elimina la configuración viva
-- ni los registros capturados con ella.
create or replace function public.appgt_descartar_borrador_configuracion(
  p_borrador_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_draft public."BORRADORES_CONFIGURACION_APPGT";
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'configuration manager permission required'
      using errcode = '42501';
  end if;

  select * into v_draft
  from public."BORRADORES_CONFIGURACION_APPGT"
  where id = p_borrador_id
    and empresa_id = v_empresa_id
    and deleted_at is null
  for update;

  if v_draft.id is null then
    raise exception 'draft not found';
  end if;
  if v_draft.estado = 'PUBLICADO' then
    raise exception 'a published configuration cannot be discarded';
  end if;

  update public."BORRADORES_CONFIGURACION_APPGT" set
    estado = 'ARCHIVADO',
    deleted_at = now(),
    updated_by = auth.uid(),
    updated_at = now(),
    lock_version = lock_version + 1
  where id = v_draft.id;

  insert into public."AUDITORIA_CONFIGURACION_APPGT" (
    empresa_id, borrador_id, entidad_tipo, entidad_id, accion,
    estado_anterior, estado_nuevo, datos_antes, user_id
  ) values (
    v_empresa_id, v_draft.id, v_draft.entidad_tipo, v_draft.codigo,
    'DESCARTAR_BORRADOR', v_draft.estado, 'ARCHIVADO',
    to_jsonb(v_draft), auth.uid()
  );

  return jsonb_build_object(
    'descartado', true,
    'borrador_id', v_draft.id,
    'estado', 'ARCHIVADO'
  );
end
$$;

create or replace function public.appgt_validar_usuario_permisos_empresa(
  p_empresa_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public."USUARIOS_EMPRESAS_APPGT" ue
    where ue.empresa_id = p_empresa_id
      and ue.user_id = p_user_id
      and ue.activo
  ) or exists (
    select 1
    from public."PERFILES_DE_USUARIOS_APPGT" p
    where p.empresa_id = p_empresa_id
      and p.id = p_user_id
      and coalesce(p.activo, true)
  );
$$;

-- Permiso de sección: aquí termina la jerarquía cuando el administrador elige
-- solamente una sección.
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
  v_id uuid;
begin
  if v_empresa_id is null or not public.appgt_es_admin_empresa(v_empresa_id) then
    raise exception 'administrator permission required' using errcode = '42501';
  end if;
  if not public.appgt_validar_usuario_permisos_empresa(v_empresa_id, p_user_id) then
    raise exception 'target user does not belong to the active company';
  end if;
  if not exists (
    select 1 from public."MATRIZ_SECCIONES_APPGT" s
    where s.empresa_id = v_empresa_id and s.id = p_seccion_id
      and coalesce(s.activo, true)
  ) then
    raise exception 'active section not found';
  end if;

  select p.id into v_id
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
end
$$;

create or replace function public.appgt_admin_delete_section_permission(
  p_user_id uuid,
  p_seccion_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_count integer;
begin
  if v_empresa_id is null or not public.appgt_es_admin_empresa(v_empresa_id) then
    raise exception 'administrator permission required' using errcode = '42501';
  end if;
  update public."PERMISOS_SECCIONES_APPGT" set
    activo = false,
    eliminado = true,
    updated_at = now()
  where empresa_id = v_empresa_id
    and user_id = p_user_id
    and coalesce(nullif(btrim(seccion), ''), btrim(seccion_id)) = p_seccion_id;
  get diagnostics v_count = row_count;
  return jsonb_build_object('eliminados', v_count);
end
$$;

-- Permiso de formato con las seis acciones que consume Flutter. Se derivan la
-- sección y tabla destino para mantener compatibles las políticas existentes.
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
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_id uuid;
  v_seccion_id text;
  v_tabla_destino text;
begin
  if v_empresa_id is null or not public.appgt_es_admin_empresa(v_empresa_id) then
    raise exception 'administrator permission required' using errcode = '42501';
  end if;
  if not public.appgt_validar_usuario_permisos_empresa(v_empresa_id, p_user_id) then
    raise exception 'target user does not belong to the active company';
  end if;

  select m.seccion, f.tabla_destino
  into v_seccion_id, v_tabla_destino
  from public."MATRIZ_FORMATOS_APPGT" f
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id = f.empresa_id and m.id = f.modulo_id
  where f.empresa_id = v_empresa_id
    and f.id = p_formato
    and f.modulo_id = p_modulo
    and coalesce(f.activo, true)
    and coalesce(m.activo, true)
  limit 1;

  if v_seccion_id is null then
    raise exception 'active format/module hierarchy not found';
  end if;

  select p.id into v_id
  from public."PERMISOS_DE_USUARIOS_APPGT" p
  where p.empresa_id = v_empresa_id
    and p.user_id = p_user_id
    and p.modulo = p_modulo
    and p.formato = p_formato
  order by p.updated_at desc nulls last
  limit 1;

  if v_id is null then
    insert into public."PERMISOS_DE_USUARIOS_APPGT" (
      empresa_id, user_id, seccion, modulo, formato, tabla_destino,
      can_view, can_insert, can_update, can_delete, can_export, can_import,
      activo, eliminado
    ) values (
      v_empresa_id, p_user_id, v_seccion_id, p_modulo, p_formato,
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

  return jsonb_build_object('id', v_id, 'guardado', true);
end
$$;

-- La validación final también compara los nombres visibles. El administrador no
-- necesita conocer códigos ni nombres físicos para entender un conflicto.
do $$
begin
  if to_regprocedure(
    'public.appgt_validar_borrador_configuracion_pre_nombres(uuid)'
  ) is null then
    alter function public.appgt_validar_borrador_configuracion(uuid)
      rename to appgt_validar_borrador_configuracion_pre_nombres;
  end if;
  if to_regprocedure(
    'public.appgt_validar_estructura_formato_pre_nombres(uuid)'
  ) is null then
    alter function public.appgt_validar_estructura_formato(uuid)
      rename to appgt_validar_estructura_formato_pre_nombres;
  end if;
end
$$;

create or replace function public.appgt_validar_borrador_configuracion(
  p_borrador_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_draft public."BORRADORES_CONFIGURACION_APPGT";
  v_result jsonb;
  v_errors jsonb;
  v_target text;
  v_conflict boolean := false;
  v_entity_label text;
  v_valid boolean;
begin
  v_result := public.appgt_validar_borrador_configuracion_pre_nombres(
    p_borrador_id
  );
  select * into v_draft
  from public."BORRADORES_CONFIGURACION_APPGT"
  where id = p_borrador_id
    and empresa_id = v_empresa_id
    and deleted_at is null;
  if v_draft.id is null then return v_result; end if;

  v_target := nullif(v_draft.definicion ->> '_entidad_objetivo_id', '');
  case v_draft.entidad_tipo
    when 'RUBRO' then
      v_entity_label := 'El rubro';
      select exists (
        select 1 from public."RUBROS_APPGT" x
        where x.empresa_id = v_empresa_id
          and lower(btrim(x.nombre)) = lower(btrim(v_draft.nombre))
          and (v_target is null or x.id <> v_target)
          and coalesce(x.activo, true) and x.deleted_at is null
      ) into v_conflict;
    when 'SECCION' then
      v_entity_label := 'La sección';
      select exists (
        select 1 from public."MATRIZ_SECCIONES_APPGT" x
        where x.empresa_id = v_empresa_id
          and lower(btrim(x.nombre)) = lower(btrim(v_draft.nombre))
          and (v_target is null or x.id <> v_target)
          and coalesce(x.activo, true) and x.deleted_at is null
      ) into v_conflict;
    when 'MODULO' then
      v_entity_label := 'El módulo';
      select exists (
        select 1 from public."MATRIZ_MODULOS_APPGT" x
        where x.empresa_id = v_empresa_id
          and lower(btrim(x.nombre)) = lower(btrim(v_draft.nombre))
          and (v_target is null or x.id <> v_target)
          and coalesce(x.activo, true) and x.deleted_at is null
      ) into v_conflict;
    when 'FORMATO' then
      v_entity_label := 'El formato';
      select exists (
        select 1 from public."MATRIZ_FORMATOS_APPGT" x
        where x.empresa_id = v_empresa_id
          and lower(btrim(x.nombre)) = lower(btrim(v_draft.nombre))
          and (v_target is null or x.id <> v_target)
          and coalesce(x.activo, true) and x.deleted_at is null
      ) into v_conflict;
    else
      v_conflict := false;
  end case;

  v_errors := coalesce(v_result -> 'errores', '[]'::jsonb);
  if v_conflict then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'campo', 'nombre',
      'mensaje', format(
        '%s "%s" ya existe, por favor elija otro nombre.',
        v_entity_label,
        v_draft.nombre
      ),
      'sugerencias', jsonb_build_array(
        v_draft.nombre || ' 2',
        v_draft.nombre || ' nuevo',
        v_draft.nombre || ' ' || extract(year from current_date)::integer
      )
    ));
  end if;

  v_valid := jsonb_array_length(v_errors) = 0;
  v_result := v_result || jsonb_build_object(
    'valido', v_valid,
    'errores', v_errors
  );
  update public."BORRADORES_CONFIGURACION_APPGT" set
    estado = case when v_valid then 'VALIDADO' else 'BORRADOR' end,
    validacion = v_result,
    validated_at = now(),
    updated_by = auth.uid(),
    updated_at = now(),
    lock_version = lock_version + 1
  where id = p_borrador_id;
  return v_result;
end
$$;

create or replace function public.appgt_validar_estructura_formato(
  p_borrador_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_draft public."BORRADORES_CONFIGURACION_APPGT";
  v_result jsonb;
  v_errors jsonb;
  v_table jsonb;
  v_table_index integer := 0;
  v_name text;
  v_destination text;
  v_table_target text;
  v_seen_names text[] := '{}';
  v_conflict boolean;
  v_valid boolean;
begin
  v_result := public.appgt_validar_estructura_formato_pre_nombres(
    p_borrador_id
  );
  select * into v_draft
  from public."BORRADORES_CONFIGURACION_APPGT"
  where id = p_borrador_id
    and empresa_id = v_empresa_id
    and entidad_tipo = 'FORMATO'
    and deleted_at is null;
  if v_draft.id is null then return v_result; end if;

  v_errors := coalesce(v_result -> 'errores', '[]'::jsonb);
  if jsonb_typeof(v_draft.definicion -> 'tablas') = 'array' then
    for v_table in
      select value from jsonb_array_elements(v_draft.definicion -> 'tablas')
    loop
      v_name := btrim(coalesce(v_table ->> 'nombre', ''));
      v_destination := btrim(coalesce(v_table ->> 'tabla_destino', ''));
      v_table_target := nullif(v_table ->> '_entidad_objetivo_id', '');
      if lower(v_name) = any(v_seen_names) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', format('tablas[%s].nombre', v_table_index),
          'mensaje', format(
            'La tabla "%s" ya existe en este formato, por favor elija otro nombre.',
            v_name
          ),
          'sugerencias', jsonb_build_array(
            v_name || ' 2', v_name || ' detalle', v_name || ' nuevo'
          )
        ));
      else
        v_seen_names := array_append(v_seen_names, lower(v_name));
      end if;

      if v_name <> '' and v_destination <> '' then
        select exists (
          select 1 from public."MATRIZ_FORMATO_TABLAS_APPGT" x
          where x.empresa_id = v_empresa_id
            and (
              lower(btrim(x.nombre)) = lower(v_name)
              or lower(btrim(x.tabla_destino)) = lower(v_destination)
            )
            and (v_table_target is null or x.id <> v_table_target)
            and coalesce(x.activo, true)
            and x.deleted_at is null
        ) or (
          v_table_target is null
          and to_regclass(format('public.%I', v_destination)) is not null
        )
        into v_conflict;
        if v_conflict then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'campo', format('tablas[%s].nombre', v_table_index),
            'mensaje', format(
              'La tabla "%s" ya existe, por favor elija otro nombre.',
              v_name
            ),
            'sugerencias', jsonb_build_array(
              v_name || ' 2', v_name || ' nuevo',
              v_name || ' ' || extract(year from current_date)::integer
            )
          ));
        end if;
      end if;
      v_table_index := v_table_index + 1;
    end loop;
  end if;

  v_valid := jsonb_array_length(v_errors) = 0;
  v_result := v_result || jsonb_build_object(
    'valido', v_valid,
    'errores', v_errors
  );
  update public."BORRADORES_CONFIGURACION_APPGT" set
    estado = case when v_valid then 'VALIDADO' else 'BORRADOR' end,
    validacion = v_result,
    validated_at = now(),
    updated_by = auth.uid(),
    updated_at = now(),
    lock_version = lock_version + 1
  where id = p_borrador_id;
  return v_result;
end
$$;

revoke all on function public.appgt_expandir_campo_desde_borrador()
  from public, anon, authenticated;
revoke all on function public.appgt_validar_usuario_permisos_empresa(uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.appgt_descartar_borrador_configuracion(uuid)
  from public, anon;
revoke all on function public.appgt_admin_upsert_section_permission(uuid,text,boolean)
  from public, anon;
revoke all on function public.appgt_admin_delete_section_permission(uuid,text)
  from public, anon;
revoke all on function public.appgt_admin_upsert_user_permission_v2(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean
) from public, anon;
revoke all on function public.appgt_validar_borrador_configuracion(uuid)
  from public, anon;
revoke all on function public.appgt_validar_estructura_formato(uuid)
  from public, anon;

grant execute on function public.appgt_descartar_borrador_configuracion(uuid)
  to authenticated;
grant execute on function public.appgt_admin_upsert_section_permission(uuid,text,boolean)
  to authenticated;
grant execute on function public.appgt_admin_delete_section_permission(uuid,text)
  to authenticated;
grant execute on function public.appgt_admin_upsert_user_permission_v2(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean
) to authenticated;
grant execute on function public.appgt_validar_borrador_configuracion(uuid)
  to authenticated;
grant execute on function public.appgt_validar_estructura_formato(uuid)
  to authenticated;

commit;
