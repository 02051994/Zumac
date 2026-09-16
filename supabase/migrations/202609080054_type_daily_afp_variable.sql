-- Un record genérico no puede siquiera ser referenciado en una expresión CASE
-- cuando no se ejecutó el SELECT de AFP (caso ONP). Se tipa con la tabla de
-- tasas para que sus atributos nulos sean seguros.
do $$
declare
  v_definition text;
begin
  select pg_get_functiondef('public.appgt_calcular_costos_planilla_zumac()'::regprocedure)
    into v_definition;

  v_definition := replace(
    v_definition,
    '  v_afp record;',
    '  v_afp public."PLANILLA_TASAS_AFP_APPGT"%rowtype;'
  );

  if position('v_afp public."PLANILLA_TASAS_AFP_APPGT"%rowtype;' in v_definition) = 0 then
    raise exception 'No se encontró la variable AFP esperada para tiparla';
  end if;

  execute v_definition;
end
$$;
