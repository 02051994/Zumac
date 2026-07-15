-- =========================================================
-- IMPORTACION GENERICA SIN DUPLICADOS EXACTOS DE NEGOCIO
-- =========================================================
-- Uso desde Flutter:
-- supabase.rpc('fn_importar_registros_sin_duplicados', params: {
--   'p_tabla': 'NOMBRE_DE_TABLA',
--   'p_registros': rows
-- });
--
-- Esta version es SET-BASED: evita hacer una consulta por cada fila,
-- por eso no debe caer en timeout con importaciones medianas.
--
-- Detecta duplicados comparando todos los campos de negocio recibidos,
-- ignorando IDs tecnicos/generados. Tambien omite duplicados dentro
-- del mismo archivo importado.

create or replace function public.fn_importar_registros_sin_duplicados(
    p_tabla text,
    p_registros jsonb,
    p_ignorar_campos text[] default array[
        'id',
        'ID',
        'id_local',
        'ID_LOCAL',
        'ID_REGISTRO',
        'id_registro',
        'hash_fila_sin_ids',
        'HASH_FILA_SIN_IDS',
        'ID_FILA_SERIAL',
        'id_fila_serial',
        'created_at',
        'updated_at',
        'creado_en',
        'actualizado_en'
    ]
)
returns table (
    filas_recibidas integer,
    filas_insertadas integer,
    filas_omitidas integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_total integer := 0;
    v_insertadas integer := 0;
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

    select count(*)
    into v_total
    from jsonb_array_elements(p_registros);

    v_sql := format($fmt$
        with input_rows as (
            select
                value as registro,
                ordinality as ord
            from jsonb_array_elements($1) with ordinality
        ),
        normalized_input as (
            select
                i.registro,
                i.ord,
                coalesce((
                    select jsonb_object_agg(e.key, to_jsonb(e.value #>> '{}'))
                    from jsonb_each(i.registro) e
                    where not exists (
                          select 1
                          from unnest($2) ignored(campo)
                          where lower(ignored.campo) = lower(e.key)
                      )
                      and e.value is not null
                      and e.value <> 'null'::jsonb
                      and btrim(e.value #>> '{}') <> ''
                ), '{}'::jsonb) as negocio
            from input_rows i
        ),
        input_without_empty_business as (
            select *
            from normalized_input
            where negocio <> '{}'::jsonb
        ),
        dedup_input as (
            select distinct on (negocio)
                registro,
                negocio,
                ord
            from input_without_empty_business
            order by negocio, ord
        ),
        existing_rows as (
            select
                coalesce((
                    select jsonb_object_agg(e.key, to_jsonb(e.value #>> '{}'))
                    from jsonb_each(to_jsonb(t)) e
                    where not exists (
                          select 1
                          from unnest($2) ignored(campo)
                          where lower(ignored.campo) = lower(e.key)
                      )
                      and e.value is not null
                      and e.value <> 'null'::jsonb
                      and btrim(e.value #>> '{}') <> ''
                ), '{}'::jsonb) as negocio
            from public.%I t
        ),
        to_insert as (
            select d.registro
            from dedup_input d
            where not exists (
                select 1
                from existing_rows e
                where e.negocio = d.negocio
            )
        ),
        inserted as (
            insert into public.%I
            select *
            from jsonb_populate_recordset(
                null::public.%I,
                coalesce((select jsonb_agg(registro) from to_insert), '[]'::jsonb)
            )
            returning 1
        )
        select count(*)::integer from inserted
    $fmt$, p_tabla, p_tabla, p_tabla);

    execute v_sql
    using p_registros, p_ignorar_campos
    into v_insertadas;

    return query
    select
        v_total,
        v_insertadas,
        greatest(v_total - v_insertadas, 0);
end;
$$;

grant execute on function public.fn_importar_registros_sin_duplicados(text, jsonb, text[]) to authenticated;
grant execute on function public.fn_importar_registros_sin_duplicados(text, jsonb, text[]) to anon;
