begin;

-- Keep the audited implementations and place version-aware guards around them.
do $$
begin
  if to_regprocedure('public.appgt_guardar_borrador_configuracion_base(text,jsonb,uuid,uuid,integer)') is null then
    alter function public.appgt_guardar_borrador_configuracion(text, jsonb, uuid, uuid, integer)
      rename to appgt_guardar_borrador_configuracion_base;
  end if;
  if to_regprocedure('public.appgt_validar_borrador_configuracion_base(uuid)') is null then
    alter function public.appgt_validar_borrador_configuracion(uuid)
      rename to appgt_validar_borrador_configuracion_base;
  end if;
  if to_regprocedure('public.appgt_publicar_borrador_configuracion_base(uuid,text)') is null then
    alter function public.appgt_publicar_borrador_configuracion(uuid, text)
      rename to appgt_publicar_borrador_configuracion_base;
  end if;
  if to_regprocedure('public.appgt_publicar_estructura_formato_base(uuid,text)') is null then
    alter function public.appgt_publicar_estructura_formato(uuid, text)
      rename to appgt_publicar_estructura_formato_base;
  end if;
end
$$;

create or replace function public.appgt_guardar_borrador_configuracion(
  p_entidad_tipo text,
  p_payload jsonb,
  p_borrador_id uuid default null,
  p_plantilla_origen_id uuid default null,
  p_lock_version integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payload jsonb := p_payload;
  v_edit boolean := upper(coalesce(p_payload ->> '_modo_edicion', '')) = 'NUEVA_VERSION'
    or current_setting('appgt.versioned_edit', true) = 'on';
begin
  if v_edit then
    v_payload := v_payload || jsonb_build_object(
      '_modo_edicion', 'NUEVA_VERSION',
      '_entidad_objetivo_id', coalesce(
        nullif(p_payload ->> '_entidad_objetivo_id', ''),
        p_payload ->> 'codigo'
      )
    );
  end if;
  return public.appgt_guardar_borrador_configuracion_base(
    p_entidad_tipo, v_payload, p_borrador_id,
    p_plantilla_origen_id, p_lock_version
  );
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
  v_draft public."BORRADORES_CONFIGURACION_APPGT";
  v_result jsonb;
  v_errors jsonb;
  v_valid boolean;
  v_target text;
begin
  v_result := public.appgt_validar_borrador_configuracion_base(p_borrador_id);
  select * into v_draft
  from public."BORRADORES_CONFIGURACION_APPGT"
  where id = p_borrador_id and deleted_at is null;

  if v_draft.id is null
     or upper(coalesce(v_draft.definicion ->> '_modo_edicion', '')) <> 'NUEVA_VERSION' then
    return v_result;
  end if;

  v_target := v_draft.definicion ->> '_entidad_objetivo_id';
  v_errors := coalesce((
    select jsonb_agg(item)
    from jsonb_array_elements(coalesce(v_result -> 'errores', '[]'::jsonb)) item
    where not (
      coalesce(item ->> 'mensaje', '') like 'Ya existe %'
      or coalesce(item ->> 'mensaje', '') = 'Ese campo ya está configurado para la tabla.'
    )
  ), '[]'::jsonb);

  if nullif(v_target, '') is null or v_target <> v_draft.codigo then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'campo', 'codigo',
      'mensaje', 'El código técnico de una configuración publicada no puede cambiar.'
    ));
  end if;

  v_valid := jsonb_array_length(v_errors) = 0;
  v_result := v_result || jsonb_build_object(
    'valido', v_valid,
    'errores', v_errors,
    'modo_edicion', 'NUEVA_VERSION'
  );
  update public."BORRADORES_CONFIGURACION_APPGT" set
    estado = case when v_valid then 'VALIDADO' else 'BORRADOR' end,
    validacion = v_result,
    validated_at = now(), updated_by = auth.uid(), updated_at = now(),
    lock_version = lock_version + 1
  where id = p_borrador_id;
  return v_result;
end
$$;

create or replace function public.appgt_publicar_borrador_configuracion(
  p_borrador_id uuid,
  p_notas text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_draft public."BORRADORES_CONFIGURACION_APPGT";
  v_previous text := coalesce(current_setting('appgt.versioned_edit', true), 'off');
  v_edit boolean;
  v_result jsonb;
begin
  select * into v_draft
  from public."BORRADORES_CONFIGURACION_APPGT"
  where id = p_borrador_id and deleted_at is null;
  v_edit := v_previous = 'on'
    or upper(coalesce(v_draft.definicion ->> '_modo_edicion', '')) = 'NUEVA_VERSION';
  if v_edit then
    perform set_config('appgt.versioned_edit', 'on', true);
  end if;
  v_result := public.appgt_publicar_borrador_configuracion_base(
    p_borrador_id, p_notas
  );
  perform set_config('appgt.versioned_edit', v_previous, true);
  return v_result;
exception when others then
  perform set_config('appgt.versioned_edit', v_previous, true);
  raise;
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
  v_draft public."BORRADORES_CONFIGURACION_APPGT";
  v_previous text := coalesce(current_setting('appgt.versioned_edit', true), 'off');
  v_edit boolean;
  v_result jsonb;
begin
  select * into v_draft
  from public."BORRADORES_CONFIGURACION_APPGT"
  where id = p_borrador_id and entidad_tipo = 'FORMATO' and deleted_at is null;
  v_edit := upper(coalesce(v_draft.definicion ->> '_modo_edicion', '')) = 'NUEVA_VERSION';
  if v_edit then
    perform set_config('appgt.versioned_edit', 'on', true);
  end if;
  v_result := public.appgt_publicar_estructura_formato_base(
    p_borrador_id, p_notas
  );
  perform set_config('appgt.versioned_edit', v_previous, true);
  return v_result;
exception when others then
  perform set_config('appgt.versioned_edit', v_previous, true);
  raise;
end
$$;

-- During a versioned publication, convert an INSERT of an existing live entity
-- into an UPDATE. New entities continue through the normal INSERT path.
create or replace function public.appgt_versioned_live_upsert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_assignments text;
  v_predicate text;
  v_count integer;
begin
  if current_setting('appgt.versioned_edit', true) <> 'on' then
    return new;
  end if;

  select string_agg(format('%1$I = n.%1$I', a.attname), ', ' order by a.attnum)
  into v_assignments
  from pg_attribute a
  where a.attrelid = tg_relid and a.attnum > 0 and not a.attisdropped
    and a.attname not in ('id', 'empresa_id', 'codigo', 'created_at');

  if tg_table_name in (
    'MATRIZ_DROPDOWNS_APPGT', 'MATRIZ_VALIDACIONES_APPGT',
    'MATRIZ_CONDICIONES_APPGT', 'MATRIZ_FORMULAS_APPGT'
  ) then
    v_predicate := 't.empresa_id = n.empresa_id and t.codigo = n.codigo';
  else
    v_predicate := 't.id = n.id';
  end if;

  execute format(
    'update public.%1$I t set %2$s
       from jsonb_populate_record(null::public.%1$I, $1) n
      where %3$s',
    tg_table_name, v_assignments, v_predicate
  ) using to_jsonb(new);
  get diagnostics v_count = row_count;
  if v_count > 0 then
    return null;
  end if;
  return new;
end
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'RUBROS_APPGT', 'MATRIZ_SECCIONES_APPGT', 'MATRIZ_MODULOS_APPGT',
    'MATRIZ_FORMATOS_APPGT', 'MATRIZ_FORMATO_TABLAS_APPGT',
    'MATRIZ_CAMPOS_FORMATO_APPGT', 'MATRIZ_DROPDOWNS_APPGT',
    'MATRIZ_VALIDACIONES_APPGT', 'MATRIZ_CONDICIONES_APPGT',
    'MATRIZ_FORMULAS_APPGT'
  ] loop
    execute format('drop trigger if exists appgt_versioned_live_upsert_trigger on public.%I', t);
    execute format(
      'create trigger appgt_versioned_live_upsert_trigger
       before insert on public.%I for each row
       execute function public.appgt_versioned_live_upsert()', t
    );
  end loop;
end
$$;

create or replace function public.appgt_version_template_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if current_setting('appgt.versioned_edit', true) = 'on' then
    select coalesce(max(p.version), 0) + 1 into new.version
    from public."PLANTILLAS_CONFIGURACION_APPGT" p
    where p.empresa_id = new.empresa_id
      and p.entidad_tipo = new.entidad_tipo
      and p.entidad_origen_id = new.entidad_origen_id;
    update public."PLANTILLAS_CONFIGURACION_APPGT" p set
      es_actual = false, updated_at = now()
    where p.empresa_id = new.empresa_id
      and p.entidad_tipo = new.entidad_tipo
      and p.entidad_origen_id = new.entidad_origen_id
      and p.es_actual;
    new.es_actual := true;
  end if;
  return new;
end
$$;

drop trigger if exists appgt_version_template_before_insert_trigger
  on public."PLANTILLAS_CONFIGURACION_APPGT";
create trigger appgt_version_template_before_insert_trigger
before insert on public."PLANTILLAS_CONFIGURACION_APPGT"
for each row execute function public.appgt_version_template_before_insert();

create or replace function public.appgt_crear_borrador_desde_publicado(
  p_plantilla_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_template public."PLANTILLAS_CONFIGURACION_APPGT";
  v_full jsonb;
  v_payload jsonb;
  v_table_row jsonb;
  v_field_row jsonb;
  v_matrix_row jsonb;
  v_table_def jsonb;
  v_field_def jsonb;
  v_tables jsonb := '[]'::jsonb;
  v_fields jsonb;
  v_matrices jsonb;
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'configuration manager permission required' using errcode = '42501';
  end if;
  select * into v_template
  from public."PLANTILLAS_CONFIGURACION_APPGT"
  where id = p_plantilla_id and empresa_id = v_empresa_id
    and activo and es_actual and deleted_at is null;
  if v_template.id is null or v_template.entidad_tipo not in
     ('RUBRO', 'SECCION', 'MODULO', 'FORMATO') then
    raise exception 'published editable template not found';
  end if;

  v_payload := v_template.definicion || jsonb_build_object(
    'codigo', v_template.entidad_origen_id,
    'nombre', v_template.nombre,
    'rubro_id', v_template.rubro_id,
    '_modo_edicion', 'NUEVA_VERSION',
    '_entidad_objetivo_id', v_template.entidad_origen_id
  );

  if v_template.entidad_tipo = 'FORMATO' then
    v_full := public.appgt_obtener_plantilla_formato_completa(v_template.id);
    for v_table_row in
      select value from jsonb_array_elements(v_full -> 'tablas')
    loop
      v_table_def := v_table_row -> 'definicion';
      v_fields := '[]'::jsonb;
      for v_field_row in
        select value from jsonb_array_elements(v_full -> 'campos')
        where value ->> 'padre_origen_id' = v_table_row ->> 'entidad_origen_id'
           or value -> 'definicion' ->> 'tabla_destino' =
              v_table_def ->> 'tabla_destino'
      loop
        v_field_def := v_field_row -> 'definicion';
        if lower(coalesce(v_field_def ->> 'campo', '')) = any(array[
          'id','id_local','empresa_id','created_by','created_at','updated_at',
          'deleted_at','eliminado','estado_sync'
        ]) then
          continue;
        end if;
        v_matrices := '[]'::jsonb;
        for v_matrix_row in
          select value from jsonb_array_elements(v_full -> 'matrices')
          where value ->> 'padre_origen_id' = v_field_row ->> 'entidad_origen_id'
        loop
          v_matrices := v_matrices || jsonb_build_array(
            (v_matrix_row -> 'definicion') || jsonb_build_object(
              'codigo', v_matrix_row ->> 'codigo',
              'nombre', v_matrix_row ->> 'nombre',
              'clase_matriz', case upper(coalesce(
                v_matrix_row -> 'definicion' ->> 'clase_matriz', ''
              ))
                when 'DROPDOWNS' then 'DROPDOWN'
                when 'VALIDACIONES' then 'VALIDACION'
                when 'CONDICIONES' then 'CONDICION'
                when 'FORMULAS' then 'FORMULA'
                else upper(v_matrix_row -> 'definicion' ->> 'clase_matriz')
              end,
              '_modo_edicion', 'NUEVA_VERSION',
              '_entidad_objetivo_id', v_matrix_row ->> 'codigo'
            )
          );
        end loop;
        v_fields := v_fields || jsonb_build_array(
          v_field_def || jsonb_build_object(
            'codigo', v_field_row ->> 'codigo',
            'nombre', v_field_row ->> 'nombre',
            'matrices', v_matrices,
            '_modo_edicion', 'NUEVA_VERSION',
            '_entidad_objetivo_id', v_field_row ->> 'entidad_origen_id'
          )
        );
      end loop;
      v_tables := v_tables || jsonb_build_array(
        v_table_def || jsonb_build_object(
          'codigo', v_table_row ->> 'codigo',
          'nombre', v_table_row ->> 'nombre',
          'crear_tabla_fisica', false,
          'campos', v_fields,
          '_modo_edicion', 'NUEVA_VERSION',
          '_entidad_objetivo_id', v_table_row ->> 'entidad_origen_id'
        )
      );
    end loop;
    v_payload := v_payload || jsonb_build_object('tablas', v_tables);
  end if;

  return public.appgt_guardar_borrador_configuracion(
    v_template.entidad_tipo, v_payload, null, v_template.id, null
  );
end
$$;

create or replace function public.appgt_previsualizar_configuracion(
  p_entidad_tipo text,
  p_entidad_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_tipo text := upper(btrim(coalesce(p_entidad_tipo, '')));
  v_root public."PLANTILLAS_CONFIGURACION_APPGT";
  v_rubro text;
  v_section text;
  v_module text;
  v_detail jsonb;
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'configuration manager permission required' using errcode = '42501';
  end if;
  select * into v_root
  from public."PLANTILLAS_CONFIGURACION_APPGT"
  where empresa_id = v_empresa_id and entidad_tipo = v_tipo
    and entidad_origen_id = p_entidad_id
    and activo and es_actual and deleted_at is null;
  if v_root.id is null then raise exception 'published configuration not found'; end if;

  v_rubro := v_root.rubro_id;
  if v_tipo = 'SECCION' then v_section := v_root.entidad_origen_id; end if;
  if v_tipo = 'MODULO' then
    v_module := v_root.entidad_origen_id;
    v_section := v_root.padre_origen_id;
  end if;
  if v_tipo = 'FORMATO' then
    v_module := v_root.padre_origen_id;
    select m.padre_origen_id into v_section
    from public."PLANTILLAS_CONFIGURACION_APPGT" m
    where m.empresa_id = v_empresa_id and m.entidad_tipo = 'MODULO'
      and m.entidad_origen_id = v_module and m.es_actual and m.activo;
    v_detail := public.appgt_obtener_plantilla_formato_completa(v_root.id);
  end if;

  return jsonb_build_object(
    'raiz', to_jsonb(v_root),
    'navegacion', coalesce((
      select jsonb_agg(
        to_jsonb(s) || jsonb_build_object(
          'modulos', coalesce((
            select jsonb_agg(
              to_jsonb(m) || jsonb_build_object(
                'formatos', coalesce((
                  select jsonb_agg(to_jsonb(f) order by
                    coalesce((f.definicion ->> 'orden')::integer, 0), f.nombre)
                  from public."PLANTILLAS_CONFIGURACION_APPGT" f
                  where f.empresa_id = v_empresa_id and f.entidad_tipo = 'FORMATO'
                    and f.padre_origen_id = m.entidad_origen_id
                    and f.es_actual and f.activo and f.deleted_at is null
                    and (v_module is null or f.padre_origen_id = v_module)
                ), '[]'::jsonb)
              ) order by coalesce((m.definicion ->> 'orden')::integer, 0), m.nombre
            )
            from public."PLANTILLAS_CONFIGURACION_APPGT" m
            where m.empresa_id = v_empresa_id and m.entidad_tipo = 'MODULO'
              and m.padre_origen_id = s.entidad_origen_id
              and m.es_actual and m.activo and m.deleted_at is null
              and (v_module is null or m.entidad_origen_id = v_module)
          ), '[]'::jsonb)
        ) order by coalesce((s.definicion ->> 'orden')::integer, 0), s.nombre
      )
      from public."PLANTILLAS_CONFIGURACION_APPGT" s
      where s.empresa_id = v_empresa_id and s.entidad_tipo = 'SECCION'
        and s.rubro_id = v_rubro and s.es_actual and s.activo and s.deleted_at is null
        and (v_section is null or s.entidad_origen_id = v_section)
    ), '[]'::jsonb),
    'detalle_formato', v_detail
  );
end
$$;

create or replace function public.appgt_historial_configuracion(
  p_entidad_tipo text,
  p_entidad_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_tipo text := upper(btrim(coalesce(p_entidad_tipo, '')));
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'configuration manager permission required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'versiones', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.version desc)
      from public."PLANTILLAS_CONFIGURACION_APPGT" p
      where p.empresa_id = v_empresa_id and p.entidad_tipo = v_tipo
        and p.entidad_origen_id = p_entidad_id and p.deleted_at is null
    ), '[]'::jsonb),
    'auditoria', coalesce((
      select jsonb_agg(to_jsonb(a) order by a.created_at desc)
      from (
        select * from public."AUDITORIA_CONFIGURACION_APPGT" a0
        where a0.empresa_id = v_empresa_id and a0.entidad_tipo = v_tipo
          and a0.entidad_id = p_entidad_id
        order by a0.created_at desc limit 100
      ) a
    ), '[]'::jsonb)
  );
end
$$;

revoke all on function public.appgt_guardar_borrador_configuracion_base(text,jsonb,uuid,uuid,integer)
  from public, anon, authenticated;
revoke all on function public.appgt_validar_borrador_configuracion_base(uuid)
  from public, anon, authenticated;
revoke all on function public.appgt_publicar_borrador_configuracion_base(uuid,text)
  from public, anon, authenticated;
revoke all on function public.appgt_publicar_estructura_formato_base(uuid,text)
  from public, anon, authenticated;

revoke all on function public.appgt_guardar_borrador_configuracion(text,jsonb,uuid,uuid,integer)
  from public, anon;
revoke all on function public.appgt_validar_borrador_configuracion(uuid)
  from public, anon;
revoke all on function public.appgt_publicar_borrador_configuracion(uuid,text)
  from public, anon;
revoke all on function public.appgt_publicar_estructura_formato(uuid,text)
  from public, anon;
revoke all on function public.appgt_crear_borrador_desde_publicado(uuid)
  from public, anon;
revoke all on function public.appgt_previsualizar_configuracion(text,text)
  from public, anon;
revoke all on function public.appgt_historial_configuracion(text,text)
  from public, anon;

grant execute on function public.appgt_guardar_borrador_configuracion(text,jsonb,uuid,uuid,integer)
  to authenticated;
grant execute on function public.appgt_validar_borrador_configuracion(uuid)
  to authenticated;
grant execute on function public.appgt_publicar_borrador_configuracion(uuid,text)
  to authenticated;
grant execute on function public.appgt_publicar_estructura_formato(uuid,text)
  to authenticated;
grant execute on function public.appgt_crear_borrador_desde_publicado(uuid)
  to authenticated;
grant execute on function public.appgt_previsualizar_configuracion(text,text)
  to authenticated;
grant execute on function public.appgt_historial_configuracion(text,text)
  to authenticated;

commit;
