begin;

create or replace function public.appgt_obtener_plantilla_formato_completa(
  p_plantilla_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_format public."PLANTILLAS_CONFIGURACION_APPGT";
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'configuration manager permission required'
      using errcode = '42501';
  end if;

  select * into v_format
  from public."PLANTILLAS_CONFIGURACION_APPGT"
  where id = p_plantilla_id and empresa_id = v_empresa_id
    and entidad_tipo = 'FORMATO' and activo and deleted_at is null;
  if v_format.id is null then
    raise exception 'format template not found';
  end if;

  return jsonb_build_object(
    'formato', to_jsonb(v_format),
    'tablas', coalesce((
      select jsonb_agg(to_jsonb(t) order by
        coalesce((t.definicion ->> 'orden')::integer, 0), t.nombre)
      from public."PLANTILLAS_CONFIGURACION_APPGT" t
      where t.empresa_id = v_empresa_id and t.entidad_tipo = 'TABLA'
        and t.padre_origen_id = v_format.entidad_origen_id
        and t.activo and t.es_actual and t.deleted_at is null
    ), '[]'::jsonb),
    'campos', coalesce((
      select jsonb_agg(to_jsonb(c) order by
        coalesce((c.definicion ->> 'orden')::integer, 0), c.nombre)
      from public."PLANTILLAS_CONFIGURACION_APPGT" c
      where c.empresa_id = v_empresa_id and c.entidad_tipo = 'CAMPO'
        and c.activo and c.es_actual and c.deleted_at is null
        and (
          c.padre_origen_id in (
            select t.entidad_origen_id
            from public."PLANTILLAS_CONFIGURACION_APPGT" t
            where t.empresa_id = v_empresa_id and t.entidad_tipo = 'TABLA'
              and t.padre_origen_id = v_format.entidad_origen_id
              and t.activo and t.es_actual and t.deleted_at is null
          )
          or c.definicion ->> 'tabla_destino' in (
            select t.definicion ->> 'tabla_destino'
            from public."PLANTILLAS_CONFIGURACION_APPGT" t
            where t.empresa_id = v_empresa_id and t.entidad_tipo = 'TABLA'
              and t.padre_origen_id = v_format.entidad_origen_id
              and t.activo and t.es_actual and t.deleted_at is null
          )
        )
    ), '[]'::jsonb),
    'matrices', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.nombre)
      from public."PLANTILLAS_CONFIGURACION_APPGT" m
      where m.empresa_id = v_empresa_id and m.entidad_tipo = 'MATRIZ'
        and m.activo and m.es_actual and m.deleted_at is null
        and m.padre_origen_id in (
          select c.entidad_origen_id
          from public."PLANTILLAS_CONFIGURACION_APPGT" c
          where c.empresa_id = v_empresa_id and c.entidad_tipo = 'CAMPO'
            and c.activo and c.es_actual and c.deleted_at is null
            and (
              c.padre_origen_id in (
                select t.entidad_origen_id
                from public."PLANTILLAS_CONFIGURACION_APPGT" t
                where t.empresa_id = v_empresa_id and t.entidad_tipo = 'TABLA'
                  and t.padre_origen_id = v_format.entidad_origen_id
                  and t.activo and t.es_actual and t.deleted_at is null
              )
              or c.definicion ->> 'tabla_destino' in (
                select t.definicion ->> 'tabla_destino'
                from public."PLANTILLAS_CONFIGURACION_APPGT" t
                where t.empresa_id = v_empresa_id and t.entidad_tipo = 'TABLA'
                  and t.padre_origen_id = v_format.entidad_origen_id
                  and t.activo and t.es_actual and t.deleted_at is null
              )
            )
        )
    ), '[]'::jsonb)
  );
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
  v_base jsonb;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_tables jsonb;
  v_table jsonb;
  v_field jsonb;
  v_matrix jsonb;
  v_table_index integer := 0;
  v_field_index integer;
  v_matrix_index integer;
  v_table_codes text[] := '{}';
  v_table_names text[] := '{}';
  v_field_codes text[];
  v_field_names text[];
  v_code text;
  v_name text;
  v_ui text;
  v_class text;
  v_valid boolean;
  v_result jsonb;
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'configuration manager permission required'
      using errcode = '42501';
  end if;

  select * into v_draft
  from public."BORRADORES_CONFIGURACION_APPGT"
  where id = p_borrador_id and empresa_id = v_empresa_id
    and deleted_at is null
  for update;
  if v_draft.id is null or v_draft.entidad_tipo <> 'FORMATO' then
    raise exception 'format draft not found';
  end if;

  v_base := public.appgt_validar_borrador_configuracion(p_borrador_id);
  v_errors := coalesce(v_base -> 'errores', '[]'::jsonb);
  v_warnings := coalesce(v_base -> 'advertencias', '[]'::jsonb);
  v_tables := v_draft.definicion -> 'tablas';

  if jsonb_typeof(v_tables) <> 'array' or jsonb_array_length(v_tables) = 0 then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'campo', 'tablas',
      'mensaje', 'El formato debe contener al menos una tabla.'
    ));
  else
    for v_table in select value from jsonb_array_elements(v_tables)
    loop
      v_table_index := v_table_index + 1;
      v_code := btrim(coalesce(v_table ->> 'codigo', ''));
      v_name := btrim(coalesce(v_table ->> 'tabla_destino', ''));
      if v_code !~ '^[A-Za-z0-9][A-Za-z0-9_-]{1,62}$' then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', format('tablas[%s].codigo', v_table_index - 1),
          'mensaje', 'Cada tabla necesita un código técnico válido.'
        ));
      elsif v_code = any(v_table_codes) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', format('tablas[%s].codigo', v_table_index - 1),
          'mensaje', 'Los códigos de tabla no pueden repetirse.'
        ));
      else
        v_table_codes := array_append(v_table_codes, v_code);
      end if;
      if v_name !~ '^[A-Za-z0-9][A-Za-z0-9_-]{1,62}$' then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', format('tablas[%s].tabla_destino', v_table_index - 1),
          'mensaje', 'Cada tabla necesita un nombre físico válido.'
        ));
      elsif v_name = any(v_table_names) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', format('tablas[%s].tabla_destino', v_table_index - 1),
          'mensaje', 'Las tablas físicas no pueden repetirse.'
        ));
      else
        v_table_names := array_append(v_table_names, v_name);
      end if;
      if nullif(btrim(coalesce(v_table ->> 'nombre', '')), '') is null then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', format('tablas[%s].nombre', v_table_index - 1),
          'mensaje', 'Cada tabla necesita un nombre visible.'
        ));
      end if;
      if public.appgt_jsonb_bool(v_table, 'es_detalle', false)
         and (
           nullif(v_table ->> 'tabla_padre', '') is null
           or nullif(v_table ->> 'campo_fk_hijo', '') is null
         ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', format('tablas[%s].relacion', v_table_index - 1),
          'mensaje', 'Una tabla detalle necesita tabla padre y campo FK.'
        ));
      end if;

      if jsonb_typeof(v_table -> 'campos') <> 'array'
         or jsonb_array_length(v_table -> 'campos') = 0 then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'campo', format('tablas[%s].campos', v_table_index - 1),
          'mensaje', 'Cada tabla debe contener al menos un campo.'
        ));
        continue;
      end if;

      v_field_index := 0;
      v_field_codes := '{}';
      v_field_names := '{}';
      for v_field in select value from jsonb_array_elements(v_table -> 'campos')
      loop
        v_field_index := v_field_index + 1;
        v_code := btrim(coalesce(v_field ->> 'codigo', ''));
        v_name := btrim(coalesce(v_field ->> 'campo', ''));
        v_ui := lower(btrim(coalesce(v_field ->> 'tipo_ui', v_field ->> 'tipo', '')));
        if v_code !~ '^[A-Za-z0-9][A-Za-z0-9_-]{1,62}$' then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'campo', format('tablas[%s].campos[%s].codigo', v_table_index - 1, v_field_index - 1),
            'mensaje', 'Cada campo necesita un código técnico válido.'
          ));
        elsif v_code = any(v_field_codes) then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'campo', format('tablas[%s].campos[%s].codigo', v_table_index - 1, v_field_index - 1),
            'mensaje', 'Los códigos de campo no pueden repetirse en una tabla.'
          ));
        else
          v_field_codes := array_append(v_field_codes, v_code);
        end if;
        if v_name = '' or length(v_name) > 63 or v_name ~ '[[:cntrl:]]' then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'campo', format('tablas[%s].campos[%s].campo', v_table_index - 1, v_field_index - 1),
            'mensaje', 'Cada campo necesita un nombre físico válido.'
          ));
        elsif lower(v_name) = any(v_field_names) then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'campo', format('tablas[%s].campos[%s].campo', v_table_index - 1, v_field_index - 1),
            'mensaje', 'Los nombres físicos no pueden repetirse en una tabla.'
          ));
        else
          v_field_names := array_append(v_field_names, lower(v_name));
        end if;
        if nullif(btrim(coalesce(v_field ->> 'etiqueta', '')), '') is null then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'campo', format('tablas[%s].campos[%s].etiqueta', v_table_index - 1, v_field_index - 1),
            'mensaje', 'Cada campo necesita una etiqueta visible.'
          ));
        end if;
        if v_ui = '' then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'campo', format('tablas[%s].campos[%s].tipo_ui', v_table_index - 1, v_field_index - 1),
            'mensaje', 'Seleccione el tipo de control de cada campo.'
          ));
        end if;
        if v_ui in ('formula', 'lookup')
           and nullif(btrim(coalesce(v_field ->> 'formula_funcion', '')), '') is null then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'campo', format('tablas[%s].campos[%s].formula_funcion', v_table_index - 1, v_field_index - 1),
            'mensaje', 'El campo calculado necesita una fórmula.'
          ));
        end if;
        if v_ui in ('dropdown', 'multiselect')
           and nullif(btrim(coalesce(v_field ->> 'id_campo_dropdown', '')), '') is null
           and jsonb_array_length(coalesce(v_field -> 'matrices', '[]'::jsonb)) = 0 then
          v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
            'campo', format('tablas[%s].campos[%s].id_campo_dropdown', v_table_index - 1, v_field_index - 1),
            'mensaje', 'El selector no tiene una fuente o matriz dropdown.'
          ));
        end if;

        if jsonb_typeof(v_field -> 'matrices') = 'array' then
          v_matrix_index := 0;
          for v_matrix in select value from jsonb_array_elements(v_field -> 'matrices')
          loop
            v_matrix_index := v_matrix_index + 1;
            v_class := upper(btrim(coalesce(v_matrix ->> 'clase_matriz', '')));
            if v_class not in ('DROPDOWN', 'VALIDACION', 'CONDICION', 'FORMULA') then
              v_errors := v_errors || jsonb_build_array(jsonb_build_object(
                'campo', format('tablas[%s].campos[%s].matrices[%s].clase_matriz', v_table_index - 1, v_field_index - 1, v_matrix_index - 1),
                'mensaje', 'La clase de matriz no es válida.'
              ));
            end if;
            if v_class = 'FORMULA'
               and nullif(btrim(coalesce(v_matrix ->> 'expresion', '')), '') is null then
              v_errors := v_errors || jsonb_build_array(jsonb_build_object(
                'campo', format('tablas[%s].campos[%s].matrices[%s].expresion', v_table_index - 1, v_field_index - 1, v_matrix_index - 1),
                'mensaje', 'La matriz de fórmula necesita una expresión.'
              ));
            end if;
          end loop;
        end if;
      end loop;
    end loop;
  end if;

  v_valid := jsonb_array_length(v_errors) = 0;
  v_result := jsonb_build_object(
    'valido', v_valid,
    'errores', v_errors,
    'advertencias', v_warnings,
    'estructura', jsonb_build_object(
      'tablas', case when jsonb_typeof(v_tables) = 'array'
        then jsonb_array_length(v_tables) else 0 end
    ),
    'validado_en', now()
  );

  update public."BORRADORES_CONFIGURACION_APPGT" set
    estado = case when v_valid then 'VALIDADO' else 'BORRADOR' end,
    validacion = v_result,
    validated_at = now(), updated_by = auth.uid(), updated_at = now(),
    lock_version = lock_version + 1
  where id = v_draft.id;

  insert into public."AUDITORIA_CONFIGURACION_APPGT" (
    empresa_id, borrador_id, entidad_tipo, entidad_id, accion,
    estado_anterior, estado_nuevo, datos_despues, user_id
  ) values (
    v_empresa_id, v_draft.id, 'FORMATO', v_draft.codigo,
    'VALIDAR_ESTRUCTURA', v_draft.estado,
    case when v_valid then 'VALIDADO' else 'BORRADOR' end,
    v_result, auth.uid()
  );

  return v_result;
end
$$;

create or replace function public.appgt_publicar_estructura_formato(
  p_borrador_id uuid,
  p_notas text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_root public."BORRADORES_CONFIGURACION_APPGT";
  v_validation jsonb;
  v_root_result jsonb;
  v_table_result jsonb;
  v_field_result jsonb;
  v_matrix_result jsonb;
  v_table jsonb;
  v_field jsonb;
  v_matrix jsonb;
  v_draft jsonb;
  v_tables_count integer := 0;
  v_fields_count integer := 0;
  v_matrices_count integer := 0;
  v_error text;
  v_result jsonb;
begin
  if v_empresa_id is null or not public.appgt_es_admin_empresa(v_empresa_id) then
    raise exception 'administrator permission required' using errcode = '42501';
  end if;

  select * into v_root
  from public."BORRADORES_CONFIGURACION_APPGT"
  where id = p_borrador_id and empresa_id = v_empresa_id
    and entidad_tipo = 'FORMATO' and deleted_at is null
  for update;
  if v_root.id is null then
    raise exception 'format draft not found';
  end if;
  if v_root.estado = 'PUBLICADO' then
    return coalesce(v_root.resultado_publicacion, to_jsonb(v_root));
  end if;

  v_validation := public.appgt_validar_estructura_formato(v_root.id);
  if not coalesce((v_validation ->> 'valido')::boolean, false) then
    return jsonb_build_object(
      'publicado', false, 'borrador_id', v_root.id,
      'validacion', v_validation
    );
  end if;

  begin
    v_root_result := public.appgt_publicar_borrador_configuracion(
      v_root.id,
      coalesce(p_notas, 'Publicación atómica de estructura de formato.')
    );
    if not coalesce((v_root_result ->> 'publicado')::boolean, false) then
      raise exception 'No se pudo publicar el formato: %',
        coalesce(v_root_result ->> 'error', 'error desconocido');
    end if;

    for v_table in
      select value from jsonb_array_elements(v_root.definicion -> 'tablas')
    loop
      v_tables_count := v_tables_count + 1;
      v_draft := public.appgt_guardar_borrador_configuracion(
        'TABLA',
        (v_table - 'campos') || jsonb_build_object(
          'formato_id', v_root.codigo,
          'rubro_id', v_root.rubro_id
        )
      );
      v_table_result := public.appgt_publicar_borrador_configuracion(
        (v_draft ->> 'id')::uuid,
        'Tabla de la estructura ' || v_root.codigo
      );
      if not coalesce((v_table_result ->> 'publicado')::boolean, false) then
        raise exception 'No se pudo publicar la tabla %: %',
          v_table ->> 'codigo',
          coalesce(v_table_result ->> 'error', 'validación rechazada');
      end if;

      for v_field in
        select value from jsonb_array_elements(v_table -> 'campos')
      loop
        v_fields_count := v_fields_count + 1;
        v_draft := public.appgt_guardar_borrador_configuracion(
          'CAMPO',
          (v_field - 'matrices') || jsonb_build_object(
            'tabla_destino', v_table ->> 'tabla_destino',
            'rubro_id', v_root.rubro_id
          )
        );
        v_field_result := public.appgt_publicar_borrador_configuracion(
          (v_draft ->> 'id')::uuid,
          'Campo de la estructura ' || v_root.codigo
        );
        if not coalesce((v_field_result ->> 'publicado')::boolean, false) then
          raise exception 'No se pudo publicar el campo %: %',
            v_field ->> 'codigo',
            coalesce(v_field_result ->> 'error', 'validación rechazada');
        end if;

        if jsonb_typeof(v_field -> 'matrices') = 'array' then
          for v_matrix in
            select value from jsonb_array_elements(v_field -> 'matrices')
          loop
            v_matrices_count := v_matrices_count + 1;
            v_draft := public.appgt_guardar_borrador_configuracion(
              'MATRIZ',
              v_matrix || jsonb_build_object(
                'campo_id', v_field ->> 'codigo',
                'formato_id', v_root.codigo,
                'rubro_id', v_root.rubro_id
              )
            );
            v_matrix_result := public.appgt_publicar_borrador_configuracion(
              (v_draft ->> 'id')::uuid,
              'Matriz de la estructura ' || v_root.codigo
            );
            if not coalesce((v_matrix_result ->> 'publicado')::boolean, false) then
              raise exception 'No se pudo publicar la matriz %: %',
                v_matrix ->> 'codigo',
                coalesce(v_matrix_result ->> 'error', 'validación rechazada');
            end if;
          end loop;
        end if;
      end loop;
    end loop;

    v_result := v_root_result || jsonb_build_object(
      'estructura_atomica', true,
      'tablas_publicadas', v_tables_count,
      'campos_publicados', v_fields_count,
      'matrices_publicadas', v_matrices_count
    );
    update public."BORRADORES_CONFIGURACION_APPGT"
    set resultado_publicacion = v_result, updated_at = now()
    where id = v_root.id;
  exception when others then
    get stacked diagnostics v_error = message_text;
    perform set_config('appgt.skip_auto_fields', 'off', true);
    update public."BORRADORES_CONFIGURACION_APPGT" set
      estado = 'ERROR_PUBLICACION',
      resultado_publicacion = jsonb_build_object(
        'publicado', false, 'estructura_atomica', true, 'error', v_error
      ),
      updated_by = auth.uid(), updated_at = now(),
      lock_version = lock_version + 1
    where id = v_root.id;
    insert into public."AUDITORIA_CONFIGURACION_APPGT" (
      empresa_id, borrador_id, entidad_tipo, entidad_id, accion,
      estado_anterior, estado_nuevo, metadata, user_id
    ) values (
      v_empresa_id, v_root.id, 'FORMATO', v_root.codigo,
      'ERROR_PUBLICACION_ESTRUCTURA', v_root.estado, 'ERROR_PUBLICACION',
      jsonb_build_object('error', v_error), auth.uid()
    );
    return jsonb_build_object(
      'publicado', false, 'borrador_id', v_root.id,
      'estructura_atomica', true, 'error', v_error
    );
  end;

  return v_result;
end
$$;

revoke all on function public.appgt_obtener_plantilla_formato_completa(uuid)
  from public, anon;
revoke all on function public.appgt_validar_estructura_formato(uuid)
  from public, anon;
revoke all on function public.appgt_publicar_estructura_formato(uuid, text)
  from public, anon;

grant execute on function public.appgt_obtener_plantilla_formato_completa(uuid)
  to authenticated;
grant execute on function public.appgt_validar_estructura_formato(uuid)
  to authenticated;
grant execute on function public.appgt_publicar_estructura_formato(uuid, text)
  to authenticated;

commit;
