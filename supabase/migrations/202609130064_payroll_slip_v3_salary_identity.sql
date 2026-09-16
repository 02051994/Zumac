-- Boleta V3:
-- 1) expone el sueldo mensual informativo del maestro de trabajadores;
-- 2) mantiene intacto el contrato de cálculo V2 y sus importes auditables.

do $$
declare
  v_sql text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
    'public.appgt_obtener_contexto_boleta_v2(uuid)'::regprocedure
  ) into v_sql;

  if position('''sueldo''' in v_sql) = 0 then
    v_old := $old$
      'tipo_remuneracion',v_liquidacion.tipo_remuneracion
$old$;
    v_new := $new$
      'tipo_remuneracion',v_liquidacion.tipo_remuneracion,
      'sueldo',public.appgt_jsonb_numeric(
        v_trabajador,
        array['Sueldo','SUELDO','sueldo','SUELDO_MENSUAL','sueldo_mensual'],
        0
      )
$new$;
    if position(v_old in v_sql) = 0 then
      raise exception
        'No se encontro el cierre del bloque trabajador en appgt_obtener_contexto_boleta_v2.';
    end if;
    execute replace(v_sql, v_old, v_new);
  end if;

  select pg_get_functiondef(
    'public.appgt_obtener_contexto_boleta_v2(uuid)'::regprocedure
  ) into v_sql;
  if position('''sueldo''' in v_sql) = 0 then
    raise exception 'El contexto de boleta V3 no expone sueldo.';
  end if;
end;
$$;

notify pgrst, 'reload schema';
