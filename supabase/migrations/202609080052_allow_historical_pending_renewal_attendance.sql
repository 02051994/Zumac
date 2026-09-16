-- Un contrato marcado como pendiente de renovación puede tener asistencia
-- histórica mientras la fecha registrada esté cubierta por su contrato.
begin;

do $$
declare
  v_sql text;
  v_old text := 'if v_status <> ''ACTIVO'' or v_fin is null or v_fin < v_fecha then';
  v_new text := 'if v_status not in (''ACTIVO'', ''PENDIENTERENOVACION'') or v_fin is null or v_fin < v_fecha then';
begin
  v_sql := pg_get_functiondef('public.appgt_validar_asistencia_laboral_v1()'::regprocedure);
  if position(v_old in v_sql) = 0 then
    raise exception 'No se encontró la validación laboral de asistencia para actualizarla.';
  end if;
  execute replace(v_sql, v_old, v_new);
end
$$;

notify pgrst, 'reload schema';
commit;
