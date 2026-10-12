begin;

-- El registro con OC actualiza líneas ya aprobadas. Se mantiene la función 081
-- como implementación y se la envuelve en el contexto interno que reconoce el
-- guard de documentos, sin exponer dicho contexto al cliente.
alter function public.erp_registrar_ingreso_compra_v2(
  text,date,text,text,text,jsonb,text
) rename to erp_registrar_ingreso_compra_v2_impl_081;

create function public.erp_registrar_ingreso_compra_v2(
  p_orden_numero text,
  p_fecha date,
  p_tipo_documento text,
  p_numero_documento text,
  p_almacen_codigo text,
  p_detalles jsonb,
  p_observacion text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  perform set_config('appgt.erp_receipt_context','1',true);
  return public.erp_registrar_ingreso_compra_v2_impl_081(
    p_orden_numero,p_fecha,p_tipo_documento,p_numero_documento,
    p_almacen_codigo,p_detalles,p_observacion
  );
end
$$;

revoke all on function public.erp_registrar_ingreso_compra_v2_impl_081(
  text,date,text,text,text,jsonb,text
) from public,anon,authenticated;
revoke all on function public.erp_registrar_ingreso_compra_v2(
  text,date,text,text,text,jsonb,text
) from public,anon;
grant execute on function public.erp_registrar_ingreso_compra_v2(
  text,date,text,text,text,jsonb,text
) to authenticated,service_role;

notify pgrst, 'reload schema';
commit;
