begin;

select set_config('appgt.skip_auto_fields', 'on', true);

-- Separa el evaluador validado de su preparación periódica. Esto permite
-- retirar estados vivos vencidos aun cuando no exista ninguna regla pendiente
-- de evaluación en ese minuto.
alter function public.appgt_evaluar_alertas_v1(integer)
  rename to appgt_evaluar_alertas_core_v1;

create or replace function public.appgt_limpiar_alertas_vencidas_v1()
returns integer
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_removed integer:=0;
begin
  update public."ZUMAC_ACCIONES_APPGT" action set
    estado='CANCELADA',completada_at=coalesce(action.completada_at,now())
  from public."ZUMAC_ALERTAS_APPGT" alert
  where action.alerta_id=alert.id and action.generada_automaticamente
    and action.estado in ('PENDIENTE','EN_PROGRESO')
    and alert.vigente_hasta is not null and alert.vigente_hasta<now();

  delete from public."ZUMAC_ALERTA_EVENTOS_APPGT" event
  using public."ZUMAC_ALERTAS_APPGT" alert
  where event.alerta_id=alert.id
    and alert.vigente_hasta is not null and alert.vigente_hasta<now();
  get diagnostics v_removed=row_count;
  return v_removed;
end
$$;

create or replace function public.appgt_evaluar_alertas_v1(p_limit integer default 100)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_result jsonb;
begin
  perform public.appgt_limpiar_alertas_vencidas_v1();
  v_result:=public.appgt_evaluar_alertas_core_v1(p_limit);
  return v_result;
end
$$;

revoke all on function public.appgt_evaluar_alertas_core_v1(integer) from public,anon,authenticated;
revoke all on function public.appgt_limpiar_alertas_vencidas_v1() from public,anon;
revoke all on function public.appgt_evaluar_alertas_v1(integer) from public,anon;

grant execute on function public.appgt_evaluar_alertas_core_v1(integer) to service_role;
grant execute on function public.appgt_limpiar_alertas_vencidas_v1() to authenticated,service_role;
grant execute on function public.appgt_evaluar_alertas_v1(integer) to authenticated,service_role;

commit;
