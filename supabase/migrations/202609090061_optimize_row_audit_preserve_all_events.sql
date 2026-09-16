-- Conserva todos los eventos de auditoría. Sólo sustituye conversiones
-- repetidas por accesos directos a JSON durante cambios masivos de jornadas.
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
  v_empresa := coalesce(
    nullif(v_data->>'empresa_id', '')::uuid,
    public.appgt_empresa_actual_id()
  );
  v_periodo := nullif(v_data->>'periodo_id', '')::uuid;
  insert into public."PLANILLA_AUDITORIA_APPGT" (
    empresa_id, tabla_origen, entidad_id, periodo_id, dni, accion,
    estado_anterior, estado_nuevo, datos_anteriores, datos_nuevos
  ) values (
    v_empresa, tg_table_name,
    coalesce(v_data->>'id_local', v_data->>'id'), v_periodo,
    coalesce(v_data->>'DNI', v_data->>'dni', v_data->>'DOCUMENTO'), tg_op,
    coalesce(v_old->>'ESTADO_APROBACION', v_old->>'estado'),
    coalesce(v_new->>'ESTADO_APROBACION', v_new->>'estado'),
    v_old, v_new
  );
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;
