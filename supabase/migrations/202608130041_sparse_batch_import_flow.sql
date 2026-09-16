begin;

-- Huellas de negocio de las filas importadas. Evita volver a recorrer y
-- normalizar toda la tabla destino en cada importación.
create table if not exists public."APPGT_IMPORT_ROW_HASHES" (
  empresa_id uuid not null,
  tabla_destino text not null,
  hash_negocio text not null,
  datos_negocio jsonb not null,
  created_by uuid,
  created_at timestamptz not null default now(),
  primary key (empresa_id, tabla_destino, hash_negocio)
);

create index if not exists appgt_import_row_hashes_table_idx
  on public."APPGT_IMPORT_ROW_HASHES" (tabla_destino, empresa_id);

alter table public."APPGT_IMPORT_ROW_HASHES" enable row level security;
revoke all on table public."APPGT_IMPORT_ROW_HASHES" from public, anon, authenticated;

create or replace function public.fn_importar_registros_sin_duplicados(
  p_tabla text,
  p_registros jsonb,
  p_ignorar_campos text[] default array[
    'id','ID','id_local','ID_LOCAL','ID_REGISTRO','id_registro',
    'hash_fila_sin_ids','HASH_FILA_SIN_IDS','ID_FILA_SERIAL','id_fila_serial',
    'PK_ID','pk_id','ID_PK','id_pk','empresa_id','EMPRESA_ID',
    'created_at','updated_at','creado_en','actualizado_en','created_by',
    'updated_by','user_id','estado_sync','eliminado','activo'
  ]
)
returns table (
  filas_recibidas integer,
  filas_insertadas integer,
  filas_omitidas integer
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_invocation uuid := gen_random_uuid();
  v_total integer := 0;
  v_insertadas integer := 0;
  v_insertadas_grupo integer := 0;
  v_can_import boolean;
  v_table_columns text[];
  v_hash_ignored text[];
  v_automatic_config_columns text[];
  v_input_technical text[] := array[
    'id','id_local','id_registro','id_fila_serial','pk_id','id_pk',
    'hash_fila_sin_ids','hash_fila_sin_id','empresa_id','created_by',
    'updated_by','user_id'
  ];
  v_missing_auto_id_columns text[];
  v_empresa_column text;
  v_created_by_column text;
  v_group record;
  v_column_list text;
  v_sql text;
begin
  if p_tabla is null or btrim(p_tabla) = '' then
    raise exception 'Debe indicar p_tabla';
  end if;
  if p_registros is null or jsonb_typeof(p_registros) <> 'array' then
    raise exception 'p_registros debe ser un arreglo JSON';
  end if;
  if to_regclass(format('public.%I', p_tabla)) is null then
    raise exception 'No existe la tabla public.%', p_tabla;
  end if;
  if v_empresa_id is null then
    raise exception 'No se pudo resolver la empresa activa' using errcode = '42501';
  end if;

  select public.appgt_puede_gestionar_configuracion(v_empresa_id)
      or exists (
        select 1
        from public."PERMISOS_DE_USUARIOS_APPGT" p
        join public."MATRIZ_FORMATOS_APPGT" f
          on f.empresa_id = p.empresa_id and f.id = p.formato
        where p.user_id = auth.uid()
          and p.empresa_id = v_empresa_id
          and coalesce(p.can_import, false)
          and (
            f.tabla_destino = p_tabla
            or exists (
              select 1 from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
              where ft.empresa_id = f.empresa_id
                and ft.formato_id = f.id
                and ft.tabla_destino = p_tabla
            )
          )
      )
    into v_can_import;
  if not coalesce(v_can_import, false) then
    raise exception 'Usuario sin permiso de importación para %', p_tabla
      using errcode = '42501';
  end if;

  select array_agg(c.column_name order by c.ordinal_position),
         max(c.column_name) filter (where lower(c.column_name) = 'empresa_id'),
         max(c.column_name) filter (where lower(c.column_name) = 'created_by')
    into v_table_columns, v_empresa_column, v_created_by_column
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = p_tabla;

  select coalesce(array_agg(distinct lower(f.campo)), array[]::text[])
    into v_automatic_config_columns
  from public."MATRIZ_CAMPOS_FORMATO_APPGT" f
  where f.tabla_destino = p_tabla
    and nullif(btrim(f.campo), '') is not null
    and coalesce(f.activo, true)
    and (
      lower(coalesce(f.tipo, '')) in ('hidden', 'hidden_id')
      or lower(coalesce(f.tipo_ui, '')) in ('hidden', 'hidden_id')
      or nullif(btrim(coalesce(f.id_generador, '')), '') is not null
    );

  select array_agg(distinct lower(x))
    into v_hash_ignored
  from unnest(
    coalesce(p_ignorar_campos, array[]::text[])
      || coalesce(v_automatic_config_columns, array[]::text[])
  ) x;

  -- Si una llave técnica UUID/texto no tiene DEFAULT físico, también se crea
  -- dentro del RPC. Las llaves seriales/identity conservan su DEFAULT nativo.
  select coalesce(array_agg(c.column_name order by c.ordinal_position),
                  array[]::text[])
    into v_missing_auto_id_columns
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = p_tabla
    and lower(c.column_name) = any(v_input_technical)
    and c.column_default is null
    and c.is_identity = 'NO'
    and c.is_generated = 'NEVER'
    and c.data_type in ('uuid', 'text', 'character varying', 'character');

  select count(*)::integer into v_total from jsonb_array_elements(p_registros);

  create temporary table if not exists appgt_import_buffer (
    invocation_id uuid not null,
    ord bigint not null,
    registro jsonb not null,
    negocio jsonb not null,
    hash_negocio text not null,
    importar boolean not null default false
  ) on commit drop;

  with input_rows as (
    select value, ordinality as ord
    from jsonb_array_elements(p_registros) with ordinality
  ), cleaned as (
    select i.ord,
      coalesce((
        select jsonb_object_agg(e.key, e.value)
        from jsonb_each(i.value) e
        where e.key = any(v_table_columns)
          and not (lower(e.key) = any(v_input_technical))
          and e.value is not null and e.value <> 'null'::jsonb
          and btrim(e.value #>> '{}') <> ''
      ), '{}'::jsonb) as registro,
      coalesce((
        select jsonb_object_agg(e.key, to_jsonb(btrim(e.value #>> '{}')))
        from jsonb_each(i.value) e
        where e.key = any(v_table_columns)
          and not (lower(e.key) = any(coalesce(v_hash_ignored, array[]::text[])))
          and e.value is not null and e.value <> 'null'::jsonb
          and btrim(e.value #>> '{}') <> ''
      ), '{}'::jsonb) as negocio
    from input_rows i
  ), enriched as (
    select c.ord, c.negocio,
      c.registro
      || auto_ids.payload
      || case when v_empresa_column is null then '{}'::jsonb
              else jsonb_build_object(v_empresa_column, v_empresa_id) end
      || case when v_created_by_column is null then '{}'::jsonb
              else jsonb_build_object(v_created_by_column, auth.uid()) end
        as registro
    from cleaned c
    cross join lateral (
      select coalesce(jsonb_object_agg(col, to_jsonb(gen_random_uuid())),
                      '{}'::jsonb) as payload
      from unnest(v_missing_auto_id_columns) col
      where c.ord is not null
    ) auto_ids
    where c.negocio <> '{}'::jsonb
  )
  insert into appgt_import_buffer(
    invocation_id, ord, registro, negocio, hash_negocio
  )
  select v_invocation, e.ord, e.registro, e.negocio, md5(e.negocio::text)
  from enriched e;

  -- Una huella se reserva antes de insertar. El registro y la huella quedan en
  -- la misma transacción, de modo que cualquier error revierte ambos.
  with candidates as (
    select distinct on (b.hash_negocio)
      b.ord, b.hash_negocio, b.negocio
    from appgt_import_buffer b
    where b.invocation_id = v_invocation
    order by b.hash_negocio, b.ord
  ), reserved as (
    insert into public."APPGT_IMPORT_ROW_HASHES"(
      empresa_id, tabla_destino, hash_negocio, datos_negocio, created_by
    )
    select v_empresa_id, p_tabla, c.hash_negocio, c.negocio, auth.uid()
    from candidates c
    on conflict (empresa_id, tabla_destino, hash_negocio) do nothing
    returning hash_negocio
  )
  update appgt_import_buffer b
  set importar = true
  from candidates c
  join reserved r on r.hash_negocio = c.hash_negocio
  where b.invocation_id = v_invocation and b.ord = c.ord;

  -- Los triggers de planilla/tareo reconocen esta marca y evitan recalcular un
  -- rango histórico por cada fila. El cálculo normal sigue disponible por
  -- periodo, al abrir la planilla y en la automatización diaria.
  perform set_config('appgt.bulk_import', 'on', true);

  for v_group in
    select grouped.columnas,
           jsonb_agg(grouped.registro order by grouped.ord) as registros
    from (
      select b.ord, b.registro,
             array(
               select key
               from jsonb_object_keys(b.registro) key
               order by key
             ) as columnas
      from appgt_import_buffer b
      where b.invocation_id = v_invocation and b.importar
    ) grouped
    group by grouped.columnas
  loop
    select string_agg(format('%I', col), ', ' order by col)
      into v_column_list
    from unnest(v_group.columnas) col;

    if nullif(v_column_list, '') is null then
      continue;
    end if;

    v_sql := format($fmt$
      with inserted as (
        insert into public.%I (%s)
        select %s
        from jsonb_populate_recordset(null::public.%I, $1) as source_rows
        on conflict do nothing
        returning 1
      )
      select count(*)::integer from inserted
    $fmt$, p_tabla, v_column_list, v_column_list, p_tabla);

    execute v_sql using v_group.registros into v_insertadas_grupo;
    v_insertadas := v_insertadas + coalesce(v_insertadas_grupo, 0);
  end loop;

  delete from appgt_import_buffer where invocation_id = v_invocation;

  return query select v_total, v_insertadas,
    greatest(v_total - v_insertadas, 0);
end
$$;

revoke all on function public.fn_importar_registros_sin_duplicados(
  text, jsonb, text[]
) from public, anon;
grant execute on function public.fn_importar_registros_sin_duplicados(
  text, jsonb, text[]
) to authenticated, service_role;

-- Evita el recálculo histórico por trabajador durante una importación masiva.
create or replace function public.appgt_personal_refrescar_planilla_zumac()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_new jsonb := to_jsonb(new);
  v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  v_dni text;
  v_status text;
  v_inicio date;
  v_fin date;
  v_old_inicio date;
  v_old_fin date;
  v_old_status text;
  v_desde date;
begin
  if current_setting('appgt.bulk_import', true) = 'on' then
    return new;
  end if;

  v_dni := public.appgt_jsonb_text(v_new, array['DNI', 'DOCUMENTO']);
  v_status := public.appgt_normalizar_clave(
    public.appgt_jsonb_text(v_new, array['Status', 'ESTADO', 'ESTADO_PERSONAL'])
  );
  v_inicio := public.appgt_jsonb_date(
    v_new, array['Fecha inicio de Contrato', 'FECHA_INICIO_CONTRATO']
  );
  v_fin := public.appgt_jsonb_date(
    v_new, array['Fecha fin de Contrato', 'FECHA_FIN_CONTRATO']
  );
  if v_status <> 'ACTIVO' or v_dni is null or v_inicio is null or v_fin is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    v_desde := v_inicio;
  else
    v_old_inicio := public.appgt_jsonb_date(
      v_old, array['Fecha inicio de Contrato', 'FECHA_INICIO_CONTRATO']
    );
    v_old_fin := public.appgt_jsonb_date(
      v_old, array['Fecha fin de Contrato', 'FECHA_FIN_CONTRATO']
    );
    v_old_status := public.appgt_normalizar_clave(
      public.appgt_jsonb_text(v_old, array['Status', 'ESTADO', 'ESTADO_PERSONAL'])
    );
    if v_old_status <> 'ACTIVO' or v_inicio is distinct from v_old_inicio
        or v_fin is distinct from v_old_fin then
      v_desde := v_inicio;
    else
      v_desde := current_date;
    end if;
  end if;

  if v_desde <= least(v_fin, current_date) then
    perform public.appgt_recalcular_planilla_zumac(
      v_dni, v_desde, least(v_fin, current_date)
    );
  end if;
  return new;
end
$$;

create or replace function public.appgt_tareo_refrescar_planilla_zumac()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_data jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_old_data jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else null end;
  v_dni text;
  v_fecha date;
  v_domingo date;
begin
  if current_setting('appgt.bulk_import', true) = 'on' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  v_dni := public.appgt_jsonb_text(v_data, array['DNI', 'DOCUMENTO']);
  v_fecha := public.appgt_jsonb_date(v_data, array['FECHA']);
  if v_dni is not null and v_fecha is not null then
    v_domingo := v_fecha + ((7 - extract(dow from v_fecha)::integer) % 7);
    perform public.appgt_recalcular_planilla_zumac(
      v_dni, v_fecha, least(v_domingo, current_date)
    );
  end if;

  if tg_op = 'UPDATE' and (
    public.appgt_jsonb_text(v_old_data, array['DNI', 'DOCUMENTO']) is distinct from v_dni
    or public.appgt_jsonb_date(v_old_data, array['FECHA']) is distinct from v_fecha
  ) then
    perform public.appgt_recalcular_planilla_zumac(
      public.appgt_jsonb_text(v_old_data, array['DNI', 'DOCUMENTO']),
      public.appgt_jsonb_date(v_old_data, array['FECHA']),
      least(
        public.appgt_jsonb_date(v_old_data, array['FECHA'])
          + ((7 - extract(dow from public.appgt_jsonb_date(v_old_data, array['FECHA']))::integer) % 7),
        current_date
      )
    );
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;

notify pgrst, 'reload schema';
commit;
