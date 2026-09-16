-- En PL/pgSQL un record sin SELECT no tiene estructura. El disparador diario
-- consultaba v_afp aun cuando el trabajador era ONP, bloqueando cualquier
-- recalculo disparado por permisos, asistencia o tareo.
do $$
declare
  v_definition text;
begin
  select pg_get_functiondef('public.appgt_calcular_costos_planilla_zumac()'::regprocedure)
    into v_definition;

  v_definition := replace(
    v_definition,
    '  new.tasa_afp := coalesce(v_afp.aporte_obligatorio_tasa, v_param.afp_aporte_tasa,0);' || E'\n' ||
    '  new.tasa_afp_seguro := coalesce(v_afp.prima_seguro_tasa, v_param.afp_seguro_tasa,0);',
    '  new.tasa_afp := case when v_pension = ''AFP'' then' || E'\n' ||
    '    coalesce(v_afp.aporte_obligatorio_tasa, v_param.afp_aporte_tasa, 0) else 0 end;' || E'\n' ||
    '  new.tasa_afp_seguro := case when v_pension = ''AFP'' then' || E'\n' ||
    '    coalesce(v_afp.prima_seguro_tasa, v_param.afp_seguro_tasa, 0) else 0 end;'
  );

  if position('case when v_pension = ''AFP'' then' in v_definition) = 0 then
    raise exception 'No se encontró el cálculo AFP esperado para corregir';
  end if;

  execute v_definition;
end
$$;

comment on function public.appgt_calcular_costos_planilla_zumac() is
  'Calcula costos diarios de planilla. AFP sólo se consulta para afiliados AFP; ONP no depende de tasas AFP.';
