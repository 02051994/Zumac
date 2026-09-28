begin;

-- El estado contractual es derivado de la vigencia, salvo CESE, que siempre
-- representa una decisión manual de Gestión Humana.
create or replace function public.appgt_normalizar_estado_contractual_zumac()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_status text;
  v_inicio date;
  v_fin date;
begin
  v_status := public.appgt_normalizar_clave(new."Status");
  v_inicio := new."Fecha inicio de Contrato";
  v_fin := new."Fecha fin de contrato";

  if v_inicio is not null and v_fin is not null and v_fin < v_inicio then
    raise exception 'Fecha fin de contrato no puede ser anterior a Fecha inicio de Contrato.';
  end if;

  if v_status = 'CESE' then
    return new;
  end if;

  if v_fin is null then
    return new;
  end if;

  new."Status" := case
    when v_fin < current_date then 'pendiente renovación'
    else 'Activo'
  end;
  return new;
end
$$;

drop trigger if exists appgt_05_normalizar_estado_contractual_zumac_trigger
  on public."GH-REGISTRO_PERSONAL_PLANILLA";
create trigger appgt_05_normalizar_estado_contractual_zumac_trigger
before insert or update on public."GH-REGISTRO_PERSONAL_PLANILLA"
for each row execute function public.appgt_normalizar_estado_contractual_zumac();

-- Antes esta función reconstruía toda la historia desde el inicio del contrato
-- dentro del UPDATE del trabajador. Eso excedía statement_timeout. El detalle
-- histórico continúa actualizándose mediante el refresco explícito de planilla;
-- aquí sólo se mantiene el día actual.
create or replace function public.appgt_personal_refrescar_planilla_zumac()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_data jsonb := to_jsonb(new);
  v_dni text;
  v_status text;
  v_inicio date;
  v_fin date;
begin
  if current_setting('appgt.bulk_import', true) = 'on' then
    return new;
  end if;

  v_dni := public.appgt_jsonb_text(v_data, array['DNI', 'DOCUMENTO']);
  v_status := public.appgt_normalizar_clave(
    public.appgt_jsonb_text(v_data, array['Status', 'ESTADO', 'ESTADO_PERSONAL'])
  );
  v_inicio := public.appgt_jsonb_date(
    v_data, array['Fecha inicio de Contrato', 'FECHA_INICIO_CONTRATO']
  );
  v_fin := public.appgt_jsonb_date(
    v_data, array['Fecha fin de Contrato', 'FECHA_FIN_CONTRATO']
  );

  if v_status = 'ACTIVO'
      and v_dni is not null
      and v_inicio is not null
      and v_fin is not null
      and current_date between v_inicio and v_fin then
    perform public.appgt_recalcular_planilla_zumac(
      v_dni, current_date, current_date
    );
  end if;
  return new;
end
$$;

-- El mismo RPC que la aplicación ejecuta al abrir Trabajadores corrige ahora
-- ambos sentidos: vence contratos y reactiva renovaciones. CESE no se toca.
create or replace function public.appgt_marcar_contratos_vencidos_zumac()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer := 0;
begin
  perform set_config('appgt.bulk_import', 'on', true);

  update public."GH-REGISTRO_PERSONAL_PLANILLA" p
  set "Status" = case
    when p."Fecha fin de contrato" < current_date
      then 'pendiente renovación'
    else 'Activo'
  end
  where public.appgt_normalizar_clave(coalesce(p."Status", '')) <> 'CESE'
    and p."Fecha fin de contrato" is not null
    and public.appgt_normalizar_clave(coalesce(p."Status", '')) is distinct from
      case
        when p."Fecha fin de contrato" < current_date
          then 'PENDIENTERENOVACION'
        else 'ACTIVO'
      end;

  select count(*)::integer into v_count
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  where public.appgt_normalizar_clave(coalesce(p."Status", '')) =
        'PENDIENTERENOVACION'
    and not coalesce(p.eliminado, false);

  return v_count;
end
$$;

-- Acelera la búsqueda de la ficha contractual usada por asistencia.
create index if not exists gh_personal_empresa_dni_activo_idx
  on public."GH-REGISTRO_PERSONAL_PLANILLA" (empresa_id, "Dni")
  where not coalesce(eliminado, false);

-- Corrige inmediatamente los estados existentes sin disparar recálculos
-- históricos por cada trabajador.
select public.appgt_marcar_contratos_vencidos_zumac();

-- Validaciones de despliegue: ningún contrato con fecha fin debe conservar un
-- estado incoherente y el control de sanciones debe seguir en el servidor.
do $$
declare
  v_attendance_definition text;
begin
  if exists (
    select 1
    from public."GH-REGISTRO_PERSONAL_PLANILLA" p
    where public.appgt_normalizar_clave(coalesce(p."Status", '')) <> 'CESE'
      and p."Fecha fin de contrato" is not null
      and public.appgt_normalizar_clave(coalesce(p."Status", '')) is distinct from
        case
          when p."Fecha fin de contrato" < current_date
            then 'PENDIENTERENOVACION'
          else 'ACTIVO'
        end
  ) then
    raise exception 'La normalización del estado contractual dejó filas incoherentes.';
  end if;

  select pg_get_functiondef(
    'public.appgt_validar_asistencia_laboral_v1()'::regprocedure
  ) into v_attendance_definition;
  if position('GH_SANCIONES_PERSONAL_APPGT' in v_attendance_definition) = 0
      or position('bloquea_asistencia' in v_attendance_definition) = 0 then
    raise exception 'La validación de asistencia perdió el bloqueo por sanciones.';
  end if;
end
$$;

commit;
