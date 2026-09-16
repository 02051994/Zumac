-- Un período sólo puede asociar jornadas de su propia empresa. El fallback de
-- empresa_id nulo arrastraba jornadas históricas ajenas y disparaba cálculos
-- masivos al validar una sola empresa.
do $$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'public.appgt_cambiar_estado_planilla_periodo_v1(uuid,text,text)'::regprocedure
  ) into v_definition;

  v_definition := replace(
    v_definition,
    'and (d.empresa_id is null or d.empresa_id=v_periodo.empresa_id)',
    'and d.empresa_id=v_periodo.empresa_id'
  );

  if position('and d.empresa_id=v_periodo.empresa_id' in v_definition) = 0 then
    raise exception 'No se pudo limitar la asociación de jornadas a la empresa del período';
  end if;

  execute v_definition;
end
$$;
