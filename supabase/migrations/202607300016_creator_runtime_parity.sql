begin;

-- MATRIZ_CAMPOS_FORMATO_APPGT sigue siendo la fuente de verdad. Estas
-- columnas conservan la configuración avanzada completa del constructor.
alter table public."MATRIZ_CAMPOS_FORMATO_APPGT"
  add column if not exists formula_tipo text,
  add column if not exists formula_tabla_origen text,
  add column if not exists formula_campo_valor text,
  add column if not exists formula_campo_condicion text,
  add column if not exists formula_valor_condicion text,
  add column if not exists condicion_color_texto text,
  add column if not exists condicion_color_fondo text,
  add column if not exists condicion_color_borde text,
  add column if not exists tamanio_letra numeric,
  add column if not exists subtitulo_alineacion text,
  add column if not exists subtitulo_tamanio_letra numeric,
  add column if not exists subtitulo_color text,
  add column if not exists subtitulo_padding text,
  add column if not exists titulo1_alineacion text,
  add column if not exists titulo1_tamanio_letra numeric,
  add column if not exists titulo1_color text,
  add column if not exists titulo1_padding text,
  add column if not exists titulo2_alineacion text,
  add column if not exists titulo2_tamanio_letra numeric,
  add column if not exists titulo2_color text,
  add column if not exists titulo2_padding text;

alter table public."MATRIZ_FORMATOS_APPGT"
  add column if not exists capacidades jsonb not null default '{}'::jsonb,
  add column if not exists flujo_estados jsonb not null default '[]'::jsonb,
  add column if not exists workflow_enabled boolean not null default false,
  add column if not exists geolocation_enabled boolean not null default false,
  add column if not exists approvals_enabled boolean not null default false;

alter table public."PERMISOS_DE_USUARIOS_APPGT"
  add column if not exists can_review boolean not null default false,
  add column if not exists can_approve boolean not null default false;

-- LOTES_VARIEDADES_GT conserva las coordenadas para que el catálogo descargado
-- pueda usarse aun cuando el dispositivo esté fuera de cobertura.
do $$
begin
  if to_regclass('public."LOTES_VARIEDADES_GT"') is not null then
    alter table public."LOTES_VARIEDADES_GT"
      add column if not exists "LATITUD" numeric,
      add column if not exists "LONGITUD" numeric,
      add column if not exists "PRECISION_GPS" numeric,
      add column if not exists "FECHA_GPS" timestamptz;
  end if;
end
$$;

-- Completa la fila de formato con el JSON del borrador antes de que el trigger
-- de edición versionada convierta el INSERT en UPDATE.
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

  if v_payload is null then
    return new;
  end if;

  v_capabilities := coalesce(v_payload -> 'capacidades', '{}'::jsonb);
  new.capacidades := v_capabilities;
  new.flujo_estados := coalesce(v_payload -> 'flujo_estados', '[]'::jsonb);
  new.workflow_enabled :=
    lower(coalesce(v_capabilities ->> 'workflow', 'false')) in ('true','1','yes','si','sí');
  new.geolocation_enabled :=
    lower(coalesce(v_capabilities ->> 'geolocalizacion', 'false')) in ('true','1','yes','si','sí');
  new.approvals_enabled :=
    lower(coalesce(v_capabilities ->> 'aprobaciones', 'false')) in ('true','1','yes','si','sí');
  return new;
end
$$;

drop trigger if exists appgt_00_expandir_formato_desde_borrador_trigger
  on public."MATRIZ_FORMATOS_APPGT";
create trigger appgt_00_expandir_formato_desde_borrador_trigger
before insert on public."MATRIZ_FORMATOS_APPGT"
for each row execute function public.appgt_expandir_formato_desde_borrador();

-- Crea una columna técnica y su definición en la matriz, salvo que el usuario
-- ya la haya definido dentro del mismo borrador.
create or replace function public.appgt_asegurar_campo_capacidad(
  p_empresa_id uuid,
  p_tabla text,
  p_campo text,
  p_etiqueta text,
  p_sql_type text,
  p_tipo text,
  p_tipo_ui text,
  p_default text,
  p_visible_tabla boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_existing_column text;
  v_id text;
  v_definition text;
begin
  if p_tabla is null
     or to_regclass(format('public.%I', p_tabla)) is null then
    return;
  end if;

  select c.column_name into v_existing_column
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = p_tabla
    and regexp_replace(upper(c.column_name), '[^A-Z0-9]', '', 'g')
      = regexp_replace(upper(p_campo), '[^A-Z0-9]', '', 'g')
  order by case when c.column_name = p_campo then 0 else 1 end
  limit 1;

  if not exists (
    select 1
    from public."MATRIZ_CAMPOS_FORMATO_APPGT" f
    where f.empresa_id = p_empresa_id
      and f.tabla_destino = p_tabla
      and regexp_replace(upper(f.campo), '[^A-Z0-9]', '', 'g')
        = regexp_replace(upper(p_campo), '[^A-Z0-9]', '', 'g')
      and coalesce(f.activo, true)
  ) and exists (
    select 1
    from public."BORRADORES_CONFIGURACION_APPGT" b
    where b.empresa_id = p_empresa_id
      and b.entidad_tipo = 'CAMPO'
      and b.deleted_at is null
      and b.definicion ->> 'tabla_destino' = p_tabla
      and regexp_replace(
            upper(coalesce(b.definicion ->> 'campo', '')),
            '[^A-Z0-9]', '', 'g'
          ) = regexp_replace(upper(p_campo), '[^A-Z0-9]', '', 'g')
  ) then
    return;
  end if;

  if v_existing_column is null then
    v_definition := p_sql_type;
    if p_default is not null then
      v_definition := v_definition || ' default ' || quote_literal(p_default);
    end if;
    execute format(
      'alter table public.%I add column if not exists %I %s',
      p_tabla, p_campo, v_definition
    );
    v_existing_column := p_campo;
  end if;

  if not exists (
    select 1
    from public."MATRIZ_CAMPOS_FORMATO_APPGT" f
    where f.empresa_id = p_empresa_id
      and f.tabla_destino = p_tabla
      and regexp_replace(upper(f.campo), '[^A-Z0-9]', '', 'g')
        = regexp_replace(upper(v_existing_column), '[^A-Z0-9]', '', 'g')
      and coalesce(f.activo, true)
  ) then
    v_id := 'auto_' || substr(
      md5(p_empresa_id::text || '|' || p_tabla || '|' || v_existing_column),
      1, 32
    );
    insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
      id, empresa_id, tabla_destino, campo, etiqueta, tipo, tipo_ui,
      requerido, orden, activo, valor_default, editable, visible,
      visible_tabla
    ) values (
      v_id, p_empresa_id, p_tabla, v_existing_column, p_etiqueta,
      p_tipo, p_tipo_ui, 'false', 9990, true, p_default, false, false,
      p_visible_tabla
    )
    on conflict (id) do update set
      campo = excluded.campo,
      etiqueta = excluded.etiqueta,
      tipo = excluded.tipo,
      tipo_ui = excluded.tipo_ui,
      valor_default = excluded.valor_default,
      editable = false,
      visible = false,
      visible_tabla = excluded.visible_tabla,
      activo = true;
  end if;
end
$$;

create or replace function public.appgt_aplicar_capacidades_formato(
  p_empresa_id uuid,
  p_formato_id text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_format public."MATRIZ_FORMATOS_APPGT";
  v_table record;
  v_first_state text;
begin
  select * into v_format
  from public."MATRIZ_FORMATOS_APPGT" f
  where f.empresa_id = p_empresa_id and f.id = p_formato_id
  limit 1;
  if v_format.id is null then return; end if;

  select value #>> '{}'
  into v_first_state
  from jsonb_array_elements(coalesce(v_format.flujo_estados, '[]'::jsonb))
  limit 1;
  v_first_state := coalesce(nullif(v_first_state, ''), 'BORRADOR');

  for v_table in
    select distinct ft.tabla_destino
    from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
    where ft.empresa_id = p_empresa_id
      and ft.formato_id = p_formato_id
      and coalesce(ft.activo, true)
      and ft.deleted_at is null
  loop
    if v_format.geolocation_enabled then
      perform public.appgt_asegurar_campo_capacidad(
        p_empresa_id, v_table.tabla_destino, 'LATITUD', 'Latitud GPS',
        'numeric', 'decimal', 'hidden', null, false
      );
      perform public.appgt_asegurar_campo_capacidad(
        p_empresa_id, v_table.tabla_destino, 'LONGITUD', 'Longitud GPS',
        'numeric', 'decimal', 'hidden', null, false
      );
      perform public.appgt_asegurar_campo_capacidad(
        p_empresa_id, v_table.tabla_destino, 'PRECISION_GPS', 'Precisión GPS',
        'numeric', 'decimal', 'hidden', null, false
      );
      perform public.appgt_asegurar_campo_capacidad(
        p_empresa_id, v_table.tabla_destino, 'FECHA_GPS', 'Fecha GPS',
        'timestamptz', 'datetime', 'hidden', null, false
      );
    end if;

    if v_format.approvals_enabled then
      perform public.appgt_asegurar_campo_capacidad(
        p_empresa_id, v_table.tabla_destino,
        'ESTADO_APROBACION', 'Estado de aprobación',
        'text', 'text', 'hidden', 'PENDIENTE', true
      );
    end if;

    if v_format.workflow_enabled then
      perform public.appgt_asegurar_campo_capacidad(
        p_empresa_id, v_table.tabla_destino,
        'estado_registro', 'Estado del registro',
        'text', 'text', 'hidden', v_first_state, true
      );
    end if;
  end loop;
end
$$;

create or replace function public.appgt_aplicar_capacidades_desde_formato()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.appgt_aplicar_capacidades_formato(new.empresa_id, new.id);
  return new;
end
$$;

drop trigger if exists appgt_aplicar_capacidades_formato_trigger
  on public."MATRIZ_FORMATOS_APPGT";
create trigger appgt_aplicar_capacidades_formato_trigger
after insert or update of capacidades, flujo_estados, workflow_enabled,
  geolocation_enabled, approvals_enabled
on public."MATRIZ_FORMATOS_APPGT"
for each row execute function public.appgt_aplicar_capacidades_desde_formato();

create or replace function public.appgt_aplicar_capacidades_desde_tabla()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.appgt_aplicar_capacidades_formato(
    new.empresa_id, new.formato_id
  );
  return new;
end
$$;

drop trigger if exists appgt_aplicar_capacidades_tabla_trigger
  on public."MATRIZ_FORMATO_TABLAS_APPGT";
create trigger appgt_aplicar_capacidades_tabla_trigger
after insert or update of tabla_destino, formato_id, activo
on public."MATRIZ_FORMATO_TABLAS_APPGT"
for each row execute function public.appgt_aplicar_capacidades_desde_tabla();

-- numero_fotos=N garantiza FOTO1..FOTON. Se respetan las variantes históricas
-- "FOTO 1", "foto1" o "FOTO_1" y los campos ya previstos en el borrador.
create or replace function public.appgt_asegurar_columnas_foto()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_total integer := greatest(coalesce(new.numero_fotos, 0)::integer, 0);
  v_index integer;
  v_column text;
  v_id text;
begin
  if v_total <= 0
     or to_regclass(format('public.%I', new.tabla_destino)) is null then
    return new;
  end if;

  for v_index in 1..v_total loop
    if exists (
      select 1
      from public."BORRADORES_CONFIGURACION_APPGT" b
      where b.empresa_id = new.empresa_id
        and b.entidad_tipo = 'CAMPO'
        and b.deleted_at is null
        and b.definicion ->> 'tabla_destino' = new.tabla_destino
        and regexp_replace(
              upper(coalesce(b.definicion ->> 'campo', '')),
              '[^A-Z0-9]', '', 'g'
            ) = 'FOTO' || v_index
    ) and not exists (
      select 1
      from public."MATRIZ_CAMPOS_FORMATO_APPGT" f
      where f.empresa_id = new.empresa_id
        and f.tabla_destino = new.tabla_destino
        and regexp_replace(upper(f.campo), '[^A-Z0-9]', '', 'g')
          = 'FOTO' || v_index
        and coalesce(f.activo, true)
    ) then
      continue;
    end if;

    select c.column_name into v_column
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = new.tabla_destino
      and regexp_replace(upper(c.column_name), '[^A-Z0-9]', '', 'g')
        = 'FOTO' || v_index
    order by case when c.column_name = 'FOTO' || v_index then 0 else 1 end
    limit 1;

    if v_column is null then
      v_column := 'FOTO' || v_index;
      execute format(
        'alter table public.%I add column if not exists %I text',
        new.tabla_destino, v_column
      );
    end if;

    if not exists (
      select 1
      from public."MATRIZ_CAMPOS_FORMATO_APPGT" f
      where f.empresa_id = new.empresa_id
        and f.tabla_destino = new.tabla_destino
        and regexp_replace(upper(f.campo), '[^A-Z0-9]', '', 'g')
          = 'FOTO' || v_index
        and coalesce(f.activo, true)
    ) then
      v_id := 'auto_photo_' || substr(
        md5(new.empresa_id::text || '|' || new.tabla_destino || '|' || v_index),
        1, 30
      );
      insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
        id, empresa_id, tabla_destino, campo, etiqueta, tipo, tipo_ui,
        requerido, orden, activo, editable, visible, visible_tabla,
        numero_fotos, grupo_captura, lista_destino_photo, orden_lista_photo
      ) values (
        v_id, new.empresa_id, new.tabla_destino, v_column,
        'Foto ' || v_index, 'photo', 'photo', 'false',
        coalesce(new.orden, 0) + v_index, true, true, true, true,
        null, new.grupo_captura, new.lista_destino_photo,
        coalesce(new.orden_lista_photo, new.orden, 0) + v_index
      )
      on conflict (id) do update set
        campo = excluded.campo,
        etiqueta = excluded.etiqueta,
        tipo = 'photo',
        tipo_ui = 'photo',
        activo = true;
    end if;
  end loop;
  return new;
end
$$;

drop trigger if exists appgt_asegurar_columnas_foto_trigger
  on public."MATRIZ_CAMPOS_FORMATO_APPGT";
create trigger appgt_asegurar_columnas_foto_trigger
after insert or update of numero_fotos
on public."MATRIZ_CAMPOS_FORMATO_APPGT"
for each row
when (new.numero_fotos is not null and new.numero_fotos > 0)
execute function public.appgt_asegurar_columnas_foto();

-- Formula y lista siempre se almacenan como texto. Este trigger corrige la
-- columna física creada por publicadores antiguos.
create or replace function public.appgt_ajustar_tipo_fisico_campo()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if lower(coalesce(new.tipo_ui, '')) in ('formula', 'lookup')
     and to_regclass(format('public.%I', new.tabla_destino)) is not null then
    execute format(
      'alter table public.%I alter column %I type text using %I::text',
      new.tabla_destino, new.campo, new.campo
    );
  end if;
  return new;
end
$$;

drop trigger if exists appgt_ajustar_tipo_fisico_campo_trigger
  on public."MATRIZ_CAMPOS_FORMATO_APPGT";
create trigger appgt_ajustar_tipo_fisico_campo_trigger
after insert or update of tipo, tipo_ui
on public."MATRIZ_CAMPOS_FORMATO_APPGT"
for each row execute function public.appgt_ajustar_tipo_fisico_campo();

-- Los identificadores configurados con prefijo son secuenciales y se asignan
-- bajo un advisory lock, evitando duplicados entre dispositivos.
create or replace function public.appgt_asignar_ids_incrementales()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_field record;
  v_next bigint;
begin
  for v_field in
    select f.campo, btrim(f.id_generador) as prefix
    from public."MATRIZ_CAMPOS_FORMATO_APPGT" f
    where f.empresa_id = new.empresa_id
      and f.tabla_destino = tg_table_name
      and nullif(btrim(f.id_generador), '') is not null
      and coalesce(f.activo, true)
  loop
    perform pg_advisory_xact_lock(
      hashtextextended(
        new.empresa_id::text || '|' || tg_table_name || '|' ||
        v_field.campo || '|' || v_field.prefix,
        0
      )
    );
    execute format(
      'select coalesce(max(substring(%1$I::text from %2$s)::bigint), 0)
         from public.%3$I
        where left(%1$I::text, %4$s) = %5$L
          and substring(%1$I::text from %2$s) ~ ''^[0-9]+$''',
      v_field.campo,
      length(v_field.prefix) + 1,
      tg_table_name,
      length(v_field.prefix),
      v_field.prefix
    ) into v_next;
    new := jsonb_populate_record(
      new,
      jsonb_build_object(v_field.campo, v_field.prefix || (v_next + 1))
    );
  end loop;
  return new;
end
$$;

create or replace function public.appgt_adjuntar_trigger_id_incremental()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if nullif(btrim(new.id_generador), '') is null
     or to_regclass(format('public.%I', new.tabla_destino)) is null then
    return new;
  end if;
  execute format(
    'drop trigger if exists appgt_asignar_ids_incrementales_trigger on public.%I',
    new.tabla_destino
  );
  execute format(
    'create trigger appgt_asignar_ids_incrementales_trigger
       before insert on public.%I
       for each row execute function public.appgt_asignar_ids_incrementales()',
    new.tabla_destino
  );
  return new;
end
$$;

drop trigger if exists appgt_adjuntar_trigger_id_incremental_trigger
  on public."MATRIZ_CAMPOS_FORMATO_APPGT";
create trigger appgt_adjuntar_trigger_id_incremental_trigger
after insert or update of id_generador
on public."MATRIZ_CAMPOS_FORMATO_APPGT"
for each row execute function public.appgt_adjuntar_trigger_id_incremental();

do $$
declare
  v_table text;
begin
  for v_table in
    select distinct f.tabla_destino
    from public."MATRIZ_CAMPOS_FORMATO_APPGT" f
    where nullif(btrim(f.id_generador), '') is not null
      and coalesce(f.activo, true)
      and to_regclass(format('public.%I', f.tabla_destino)) is not null
  loop
    execute format(
      'drop trigger if exists appgt_asignar_ids_incrementales_trigger on public.%I',
      v_table
    );
    execute format(
      'create trigger appgt_asignar_ids_incrementales_trigger
         before insert on public.%I
         for each row execute function public.appgt_asignar_ids_incrementales()',
      v_table
    );
  end loop;
end
$$;

-- Catálogo buscable y limitado por permisos para dropdown, multiselect y LISTA.
create or replace function public.appgt_catalogo_campos_constructor_v1(
  p_busqueda text default null,
  p_limit integer default 250
)
returns table (
  modulo_id text,
  modulo_nombre text,
  formato_id text,
  formato_nombre text,
  tabla_destino text,
  tabla_nombre text,
  campo text,
  campo_etiqueta text,
  ruta text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    m.id,
    m.nombre,
    f.id,
    f.nombre,
    ft.tabla_destino,
    ft.nombre,
    c.campo,
    coalesce(nullif(c.etiqueta, ''), c.campo),
    concat_ws(' › ', m.nombre, ft.nombre, c.campo)
  from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
  join public."MATRIZ_FORMATOS_APPGT" f
    on f.empresa_id = ft.empresa_id and f.id = ft.formato_id
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id = f.empresa_id and m.id = f.modulo_id
  join public."MATRIZ_CAMPOS_FORMATO_APPGT" c
    on c.empresa_id = ft.empresa_id
   and c.tabla_destino = ft.tabla_destino
  where ft.empresa_id = public.appgt_empresa_actual_id()
    and coalesce(ft.activo, true)
    and ft.deleted_at is null
    and coalesce(f.activo, true)
    and f.deleted_at is null
    and coalesce(m.activo, true)
    and m.deleted_at is null
    and coalesce(c.activo, true)
    and (
      public.appgt_puede_gestionar_configuracion(ft.empresa_id)
      or exists (
        select 1
        from public."PERMISOS_DE_USUARIOS_APPGT" p
        where p.empresa_id = ft.empresa_id
          and p.user_id = auth.uid()
          and coalesce(p.activo, true)
          and not coalesce(p.eliminado, false)
          and coalesce(p.can_view, false)
          and (
            p.formato = f.id
            or p.tabla_destino = ft.tabla_destino
          )
      )
    )
    and (
      nullif(btrim(p_busqueda), '') is null
      or concat_ws(
        ' ', m.nombre, f.nombre, ft.nombre, ft.tabla_destino,
        c.etiqueta, c.campo
      ) ilike '%' || btrim(p_busqueda) || '%'
    )
  order by m.nombre, ft.nombre, coalesce(c.orden, 0), c.campo
  limit greatest(1, least(coalesce(p_limit, 250), 500))
$$;

revoke all on function public.appgt_catalogo_campos_constructor_v1(text,integer)
  from public, anon;
grant execute on function public.appgt_catalogo_campos_constructor_v1(text,integer)
  to authenticated;

-- Aprobaciones agrega dos acciones específicas al permiso de formato.
create or replace function public.appgt_admin_upsert_user_permission_v4(
  p_user_id uuid,
  p_modulo text,
  p_formato text,
  p_can_view boolean,
  p_can_insert boolean,
  p_can_update boolean,
  p_can_delete boolean,
  p_can_export boolean default false,
  p_can_import boolean default false,
  p_can_review boolean default false,
  p_can_approve boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_result jsonb;
begin
  v_result := public.appgt_admin_upsert_user_permission_v3(
    p_user_id, p_modulo, p_formato, p_can_view, p_can_insert,
    p_can_update, p_can_delete, p_can_export, p_can_import
  );
  update public."PERMISOS_DE_USUARIOS_APPGT" p
  set can_review = p_can_review,
      can_approve = p_can_approve,
      updated_at = now()
  where p.empresa_id = v_empresa_id
    and p.user_id = p_user_id
    and p.modulo = v_result ->> 'modulo'
    and p.formato = v_result ->> 'formato';
  return v_result || jsonb_build_object(
    'can_review', p_can_review,
    'can_approve', p_can_approve
  );
end
$$;

revoke all on function public.appgt_admin_upsert_user_permission_v4(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean
) from public, anon;
grant execute on function public.appgt_admin_upsert_user_permission_v4(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean
) to authenticated;

-- Activa las columnas FOTO faltantes de configuraciones ya publicadas.
update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set numero_fotos = numero_fotos
where coalesce(numero_fotos, 0) > 0;

notify pgrst, 'reload schema';

commit;
