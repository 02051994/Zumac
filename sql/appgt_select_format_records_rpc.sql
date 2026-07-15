-- Ejecutar / reemplazar en Supabase SQL Editor.
-- Objetivo: permitir que la vista Windows lea registros del formato usando permisos de la app,
-- devolviendo también el orden real de columnas de la tabla.
-- Incluye paginación real: p_limit + p_offset.

create or replace function public.appgt_select_format_records(
  p_format_id text,
  p_table_name text,
  p_limit integer default null,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expected_table text;
  v_can_view boolean;
  v_rows jsonb;
  v_columns jsonb;
begin
  select f.tabla_destino
    into v_expected_table
  from public."MATRIZ_FORMATOS_APPGT" f
  where f.id = p_format_id
    and coalesce(f.tabla_destino, '') <> ''
  limit 1;

  if v_expected_table is null then
    select ft.tabla_destino
      into v_expected_table
    from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
    where ft.formato_id = p_format_id
      and coalesce(ft.tabla_destino, '') <> ''
    order by ft.orden nulls last
    limit 1;
  end if;

  if v_expected_table is null or v_expected_table <> p_table_name then
    raise exception 'Tabla destino no coincide con el formato: formato %, tabla %', p_format_id, p_table_name;
  end if;

  select exists(
    select 1
    from public."PERMISOS_DE_USUARIOS_APPGT" p
    where p.user_id = auth.uid()
      and p.formato = p_format_id
      and coalesce(p.can_view, false) = true
  ) into v_can_view;

  if not v_can_view then
    raise exception 'Usuario sin permiso de visualización para el formato %', p_format_id;
  end if;

  select coalesce(jsonb_agg(c.column_name order by c.ordinal_position), '[]'::jsonb)
    into v_columns
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = p_table_name;

  if p_limit is null or p_limit <= 0 then
    execute format(
      'select coalesce(jsonb_agg(row_to_json(t)::jsonb), ''[]''::jsonb)
       from (select * from public.%I offset %s) t',
      p_table_name,
      greatest(0, coalesce(p_offset, 0))
    ) into v_rows;
  else
    execute format(
      'select coalesce(jsonb_agg(row_to_json(t)::jsonb), ''[]''::jsonb)
       from (select * from public.%I limit %s offset %s) t',
      p_table_name,
      greatest(1, p_limit),
      greatest(0, coalesce(p_offset, 0))
    ) into v_rows;
  end if;

  return jsonb_build_object(
    'columns', coalesce(v_columns, '[]'::jsonb),
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
end;
$$;

grant execute on function public.appgt_select_format_records(text, text, integer, integer) to authenticated;

-- Compatibilidad para llamadas antiguas de 3 argumentos.
grant execute on function public.appgt_select_format_records(text, text, integer) to authenticated;
