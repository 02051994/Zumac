begin;

-- Algunos esquemas heredados instalaron funciones de auditoría que leen
-- NEW.empresa_id aun en tablas operativas que nunca tuvieron esa columna.
-- Esos triggers hacen fallar cualquier INSERT (incluida la importación XLSX).
-- Solo se retiran los triggers incompatibles de tablas declaradas en Creator;
-- el seguimiento incremental genérico se reinstala al final de la migración.
do $$
declare
  v_trigger record;
begin
  for v_trigger in
    select n.nspname as schema_name, c.relname as table_name,
           t.tgname as trigger_name
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_proc p on p.oid = t.tgfoid
    where not t.tgisinternal
      and n.nspname = 'public'
      and lower(p.prosrc) ~ '(new|old)[[:space:]]*\.[[:space:]]*empresa_id'
      and not exists (
        select 1 from information_schema.columns col
        where col.table_schema = n.nspname
          and col.table_name = c.relname
          and lower(col.column_name) = 'empresa_id'
      )
      and (
        exists (
          select 1 from public."MATRIZ_FORMATOS_APPGT" f
          where f.tabla_destino = c.relname
        )
        or exists (
          select 1 from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
          where ft.tabla_destino = c.relname
        )
      )
  loop
    execute format(
      'drop trigger if exists %I on %I.%I',
      v_trigger.trigger_name, v_trigger.schema_name, v_trigger.table_name
    );
  end loop;
end
$$;

create or replace function public.fn_importar_registros_sin_duplicados(
  p_tabla text,
  p_registros jsonb,
  p_ignorar_campos text[] default array[
    'id','ID','id_local','ID_LOCAL','ID_REGISTRO','id_registro',
    'hash_fila_sin_ids','HASH_FILA_SIN_IDS','ID_FILA_SERIAL','id_fila_serial',
    'created_at','updated_at','creado_en','actualizado_en','created_by',
    'updated_by','estado_sync','eliminado','activo'
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
  v_total integer := 0;
  v_insertadas integer := 0;
  v_sql text;
  v_has_empresa boolean;
  v_has_created_by boolean;
  v_can_import boolean;
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

  select exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = p_tabla
        and lower(column_name) = 'empresa_id'
    ), exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = p_tabla
        and lower(column_name) = 'created_by'
    )
    into v_has_empresa, v_has_created_by;

  select count(*) into v_total from jsonb_array_elements(p_registros);

  v_sql := format($fmt$
    with input_rows as (
      select
        case when $3 then jsonb_set(value, '{empresa_id}', to_jsonb($5::uuid), true)
             else value end as with_company,
        ordinality as ord
      from jsonb_array_elements($1) with ordinality
    ),
    enriched_input as (
      select
        case when $4 then jsonb_set(with_company, '{created_by}', to_jsonb($6::uuid), true)
             else with_company end as registro,
        ord
      from input_rows
    ),
    normalized_input as (
      select i.registro, i.ord,
        coalesce((
          select jsonb_object_agg(e.key, to_jsonb(e.value #>> '{}'))
          from jsonb_each(i.registro) e
          where not exists (
            select 1 from unnest($2) ignored(campo)
            where lower(ignored.campo) = lower(e.key)
          )
            and e.value is not null and e.value <> 'null'::jsonb
            and btrim(e.value #>> '{}') <> ''
        ), '{}'::jsonb) as negocio
      from enriched_input i
    ),
    dedup_input as (
      select distinct on (negocio) registro, negocio, ord
      from normalized_input
      where negocio <> '{}'::jsonb
      order by negocio, ord
    ),
    existing_rows as (
      select coalesce((
        select jsonb_object_agg(e.key, to_jsonb(e.value #>> '{}'))
        from jsonb_each(to_jsonb(t)) e
        where not exists (
          select 1 from unnest($2) ignored(campo)
          where lower(ignored.campo) = lower(e.key)
        )
          and e.value is not null and e.value <> 'null'::jsonb
          and btrim(e.value #>> '{}') <> ''
      ), '{}'::jsonb) as negocio
      from public.%I t
      where not $3 or to_jsonb(t)->>'empresa_id' = $5::text
    ),
    to_insert as (
      select d.registro, d.ord
      from dedup_input d
      where not exists (
        select 1 from existing_rows e where e.negocio = d.negocio
      )
    ),
    inserted as (
      insert into public.%I
      select * from jsonb_populate_recordset(
        null::public.%I,
        coalesce((select jsonb_agg(registro order by ord) from to_insert), '[]'::jsonb)
      )
      returning 1
    )
    select count(*)::integer from inserted
  $fmt$, p_tabla, p_tabla, p_tabla);

  execute v_sql
    using p_registros, p_ignorar_campos, v_has_empresa, v_has_created_by,
          v_empresa_id, auth.uid()
    into v_insertadas;

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

create or replace function public.appgt_select_format_records(
  p_format_id text,
  p_table_name text,
  p_limit integer default null,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_can_view boolean;
  v_rows jsonb;
  v_columns jsonb;
  v_total bigint;
  v_order_expression text;
  v_has_empresa boolean;
  v_company_filter text := '';
begin
  if v_empresa_id is null then
    raise exception 'No se pudo resolver la empresa activa' using errcode = '42501';
  end if;
  if to_regclass(format('public.%I', p_table_name)) is null then
    raise exception 'No existe la tabla public.%', p_table_name;
  end if;
  if not exists (
    select 1
    from public."MATRIZ_FORMATOS_APPGT" f
    where f.empresa_id = v_empresa_id and f.id = p_format_id
      and (
        f.tabla_destino = p_table_name
        or exists (
          select 1 from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
          where ft.empresa_id = f.empresa_id and ft.formato_id = f.id
            and ft.tabla_destino = p_table_name
        )
      )
  ) then
    raise exception 'Tabla destino no coincide con el formato: formato %, tabla %',
      p_format_id, p_table_name;
  end if;

  select public.appgt_puede_gestionar_configuracion(v_empresa_id)
      or exists (
        select 1 from public."PERMISOS_DE_USUARIOS_APPGT" p
        where p.user_id = auth.uid() and p.empresa_id = v_empresa_id
          and p.formato = p_format_id and coalesce(p.can_view, false)
      )
    into v_can_view;
  if not coalesce(v_can_view, false) then
    raise exception 'Usuario sin permiso de visualización para el formato %',
      p_format_id using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(c.column_name order by c.ordinal_position), '[]'::jsonb)
    into v_columns
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = p_table_name;

  select exists (
    select 1 from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = p_table_name
      and lower(c.column_name) = 'empresa_id'
  ) into v_has_empresa;
  if v_has_empresa then
    v_company_filter := format('where t.empresa_id = %L::uuid', v_empresa_id);
  end if;

  select string_agg(format('t.%I', a.attname), ', ' order by k.ordinality)
    into v_order_expression
  from pg_index i
  join pg_class c on c.oid = i.indrelid
  join pg_namespace n on n.oid = c.relnamespace
  join unnest(i.indkey) with ordinality k(attnum, ordinality) on true
  join pg_attribute a on a.attrelid = c.oid and a.attnum = k.attnum
  where i.indisprimary and n.nspname = 'public' and c.relname = p_table_name;

  if v_order_expression is null then
    select format('t.%I', c.column_name) into v_order_expression
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = p_table_name
      and lower(c.column_name) in ('id_local','id','created_at','updated_at')
    order by case lower(c.column_name)
      when 'id_local' then 1 when 'id' then 2
      when 'created_at' then 3 else 4 end
    limit 1;
  end if;
  v_order_expression := coalesce(v_order_expression || ', ', '') ||
    'to_jsonb(t)::text';

  execute format(
    'select count(*) from public.%I t %s', p_table_name, v_company_filter
  ) into v_total;
  execute format(
    'select coalesce(jsonb_agg(row_value), ''[]''::jsonb) from (
       select to_jsonb(t) as row_value
       from public.%I t
       %s
       order by %s
       limit %s offset %s
     ) ordered_rows',
    p_table_name,
    v_company_filter,
    v_order_expression,
    case when p_limit is null or p_limit <= 0 then 'all'
         else greatest(1, p_limit)::text end,
    greatest(0, coalesce(p_offset, 0))
  ) into v_rows;

  return jsonb_build_object(
    'columns', coalesce(v_columns, '[]'::jsonb),
    'rows', coalesce(v_rows, '[]'::jsonb),
    'total_rows', v_total,
    'order_expression', v_order_expression
  );
end
$$;

revoke all on function public.appgt_select_format_records(
  text, text, integer, integer
) from public, anon;
grant execute on function public.appgt_select_format_records(
  text, text, integer, integer
) to authenticated, service_role;

do $$
begin
  if to_regprocedure('public.appgt_instalar_seguimiento_tablas_v1()') is not null then
    perform public.appgt_instalar_seguimiento_tablas_v1();
  end if;
end
$$;

notify pgrst, 'reload schema';
commit;
