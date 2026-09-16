-- Las validaciones heredadas incluían filas históricas eliminadas/inactivas y
-- omitían contratos vigentes en estado PENDIENTE RENOVACION. Sólo deben
-- bloquear los contratos activos que se cruzan con el período evaluado.
do $$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'public.appgt_generar_validaciones_planilla_legacy_048(uuid)'::regprocedure
  ) into v_definition;

  v_definition := replace(
    v_definition,
    'where p.empresa_id=v_periodo.empresa_id',
    'where p.empresa_id=v_periodo.empresa_id' || E'\n'
      || '    and coalesce(p.activo,false)' || E'\n'
      || '    and not coalesce(p.eliminado,false)' || E'\n'
      || '    and p.deleted_at is null'
  );
  v_definition := replace(
    v_definition,
    '=''ACTIVO''',
    ' in (''ACTIVO'',''PENDIENTERENOVACION'')'
  );
  v_definition := replace(
    v_definition,
    '''ERROR'',''TRABAJADOR_SIN_CONTROL_DIARIO''',
    '''ADVERTENCIA'',''TRABAJADOR_SIN_CONTROL_DIARIO'''
  );

  if position('coalesce(p.activo,false)' in v_definition) = 0
     or position('PENDIENTERENOVACION' in v_definition) = 0 then
    raise exception 'No se encontró el alcance esperado de las validaciones de planilla';
  end if;

  execute v_definition;
end
$$;

comment on function public.appgt_generar_validaciones_planilla_legacy_048(uuid) is
  'Validaciones de planilla limitadas a contratos activos y vigentes; ausencia total queda como advertencia visible.';
