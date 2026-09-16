-- Asociar una jornada ya calculada a un período no altera su costo. Evita que
-- el trigger recorra parámetros laborales de nuevo cuando sólo cambian los
-- metadatos de cierre (periodo, campaña, moneda o tipo de cambio).
do $$
declare
  v_definition text;
  v_marker text := 'begin' || E'\n' ||
    '  new.empresa_id:=coalesce(new.empresa_id,public.appgt_empresa_actual_id());';
  v_replacement text := 'begin' || E'\n' ||
    '  if tg_op = ''UPDATE''' || E'\n' ||
    '     and (to_jsonb(new) - array[''periodo_id'',''campana'',''moneda'',''tipo_cambio'',''updated_at''])' || E'\n' ||
    '       = (to_jsonb(old) - array[''periodo_id'',''campana'',''moneda'',''tipo_cambio'',''updated_at'']) then' || E'\n' ||
    '    return new;' || E'\n' ||
    '  end if;' || E'\n' ||
    '  new.empresa_id:=coalesce(new.empresa_id,public.appgt_empresa_actual_id());';
begin
  select pg_get_functiondef('public.appgt_calcular_costos_planilla_zumac()'::regprocedure)
    into v_definition;

  if position('to_jsonb(new) - array[''periodo_id''' in v_definition) = 0 then
    v_definition := replace(v_definition, v_marker, v_replacement);
  end if;

  if position('to_jsonb(new) - array[''periodo_id''' in v_definition) = 0 then
    raise exception 'No se pudo insertar la guarda de metadatos de período';
  end if;

  execute v_definition;
end
$$;
