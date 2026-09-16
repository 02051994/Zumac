-- El cambio masivo de período tiene una auditoría agregada al final de la
-- transición. Evitar 300 snapshots idénticos previene el timeout y conserva
-- la trazabilidad de la acción del período.
create or replace function public.appgt_auditar_operacion_planilla_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old jsonb := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;
  v_new jsonb := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end;
  v_data jsonb := coalesce(v_new, v_old);
  v_empresa uuid;
  v_periodo uuid;
begin
  if current_setting('appgt.planilla_transition', true) = '1' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  v_empresa := coalesce(
    nullif(public.appgt_jsonb_text(v_data, array['empresa_id']), '')::uuid,
    public.appgt_empresa_actual_id()
  );
  v_periodo := nullif(public.appgt_jsonb_text(v_data, array['periodo_id']), '')::uuid;
  insert into public."PLANILLA_AUDITORIA_APPGT" (
    empresa_id, tabla_origen, entidad_id, periodo_id, dni, accion,
    estado_anterior, estado_nuevo, datos_anteriores, datos_nuevos
  ) values (
    v_empresa, tg_table_name,
    public.appgt_jsonb_text(v_data, array['id_local','id']), v_periodo,
    public.appgt_jsonb_text(v_data, array['DNI','dni','DOCUMENTO']), tg_op,
    public.appgt_jsonb_text(v_old, array['ESTADO_APROBACION','estado']),
    public.appgt_jsonb_text(v_new, array['ESTADO_APROBACION','estado']),
    v_old, v_new
  );
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;
