-- Incluye en planilla a contratos vigentes cuya renovación está pendiente y
-- convierte el permiso de teletrabajo en una jornada pagada de teletrabajo.
begin;

update public."APPGT_REGLAS_DUPLICADO_APPGT"
set campos_clave = array['dni', 'fecha_inicio', 'fecha_fin', 'tipo_permiso']::text[],
    descripcion = 'Una solicitud por trabajador, rango y tipo de permiso.',
    updated_at = now()
where upper(tabla_destino) = 'GH_PERMISOS_LICENCIAS_APPGT';

create or replace function public.appgt_refrescar_planilla_zumac(
  p_desde date default current_date,
  p_hasta date default current_date
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_worker record;
  v_total integer := 0;
begin
  if p_desde is null or p_hasta is null or p_hasta < p_desde then
    raise exception 'Rango de fechas invalido para refrescar planilla.';
  end if;

  for v_worker in
    select
      public.appgt_jsonb_text(to_jsonb(p), array['DNI', 'DOCUMENTO']) as dni,
      public.appgt_jsonb_date(to_jsonb(p), array['Fecha inicio de Contrato', 'FECHA_INICIO_CONTRATO']) as inicio,
      public.appgt_jsonb_date(to_jsonb(p), array['Fecha fin de Contrato', 'FECHA_FIN_CONTRATO']) as fin
    from public."GH-REGISTRO_PERSONAL_PLANILLA" p
    where coalesce(p.activo, true)
      and not coalesce(p.eliminado, false)
      and p.deleted_at is null
      and public.appgt_normalizar_clave(
        public.appgt_jsonb_text(to_jsonb(p), array['Status', 'ESTADO', 'ESTADO_PERSONAL'])
      ) in ('ACTIVO', 'PENDIENTERENOVACION')
      and public.appgt_jsonb_text(to_jsonb(p), array['DNI', 'DOCUMENTO']) is not null
  loop
    if v_worker.inicio is not null and v_worker.fin is not null
        and v_worker.inicio <= p_hasta and v_worker.fin >= p_desde then
      v_total := v_total + public.appgt_recalcular_planilla_zumac(
        v_worker.dni,
        greatest(p_desde, v_worker.inicio),
        least(p_hasta, v_worker.fin, current_date)
      );
    end if;
  end loop;
  return v_total;
end
$$;

do $$
declare
  v_sql text;
  v_old text;
  v_new text;
begin
  -- El detalle diario y la liquidación usan la misma definición de trabajador vigente.
  v_sql := pg_get_functiondef('public.appgt_recalcular_planilla_zumac(text,date,date)'::regprocedure);
  v_old := $old$
      and public.appgt_normalizar_clave(
        public.appgt_jsonb_text(s.data, array['Status','ESTADO','ESTADO_PERSONAL'])
      ) = 'ACTIVO'$old$;
  v_new := $new$
      and not public.appgt_jsonb_bool(s.data, array['eliminado'], false)
      and public.appgt_jsonb_text(s.data, array['deleted_at']) is null
      and public.appgt_jsonb_bool(s.data, array['activo'], true)
      and public.appgt_normalizar_clave(
        public.appgt_jsonb_text(s.data, array['Status','ESTADO','ESTADO_PERSONAL'])
      ) in ('ACTIVO','PENDIENTERENOVACION')$new$;
  v_old := replace(v_old, E'\r\n', E'\n');
  if position(v_old in v_sql) = 0 then
    raise exception 'No se encontró el selector de trabajador diario para actualizarlo.';
  end if;
  execute replace(v_sql, v_old, v_new);

  v_sql := pg_get_functiondef('public.appgt_calcular_liquidacion_periodo_v2(uuid)'::regprocedure);
  v_old := $old$      and (
        public.appgt_normalizar_clave(
          public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
        )='ACTIVO'$old$;
  v_new := $new$      and coalesce(p.activo, true)
      and not coalesce(p.eliminado, false)
      and p.deleted_at is null
      and (
        public.appgt_normalizar_clave(
          public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
        ) in ('ACTIVO','PENDIENTERENOVACION')$new$;
  v_old := replace(v_old, E'\r\n', E'\n');
  if position(v_old in v_sql) = 0 then
    raise exception 'No se encontró el selector de liquidación para actualizarlo.';
  end if;
  execute replace(v_sql, v_old, v_new);

  if false then -- La versión previa tiene una estructura distinta; se reemplaza explícitamente abajo.
  v_sql := pg_get_functiondef('public.appgt_reconstruir_permisos_periodo_v2(uuid)'::regprocedure);
  v_old := $old$        'PERMISO SIN GOCE','COMISION DE SERVICIO','LICENCIA DE PATERNIDAD',
        'LICENCIA POR FALLECIMIENTO','VACACIONES') and r.horas >= 8 then 0$old$;
  v_new := $new$        'PERMISO SIN GOCE','COMISION DE SERVICIO','LICENCIA DE PATERNIDAD',
        'LICENCIA POR FALLECIMIENTO','VACACIONES','TELETRABAJO') and r.horas >= 8 then 0$new$;
  v_old := replace(v_old, E'\r\n', E'\n');
  if position(v_old in v_sql) = 0 then
    raise exception 'No se encontró la regla de jornada completa de permisos.';
  end if;
  v_sql := replace(v_sql, v_old, v_new);
  v_old := $old$    descanso_medico=case when r.rn=1 and r.tipo_permiso='DESCANSO MEDICO'
      then r.horas else 0 end,
    licencia_maternidad=$old$;
  v_new := $new$    descanso_medico=case when r.rn=1 and r.tipo_permiso='DESCANSO MEDICO'
      then r.horas else 0 end,
    teletrabajo=case when r.rn=1 and r.tipo_permiso='TELETRABAJO'
      then r.horas else 0 end,
    licencia_maternidad=$new$;
  v_old := replace(v_old, E'\r\n', E'\n');
  if position(v_old in v_sql) = 0 then
    raise exception 'No se encontró el mapeo de permisos para teletrabajo.';
  end if;
  execute replace(v_sql, v_old, v_new);

  v_sql := pg_get_functiondef('public.appgt_aplicar_permisos_planilla_rango_v1(text,date,date)'::regprocedure);
  v_old := $old$        'PERMISO SIN GOCE','COMISION DE SERVICIO','LICENCIA DE PATERNIDAD',
        'LICENCIA POR FALLECIMIENTO','VACACIONES') and r.horas_permiso >= 8 then 0$old$;
  v_new := $new$        'PERMISO SIN GOCE','COMISION DE SERVICIO','LICENCIA DE PATERNIDAD',
        'LICENCIA POR FALLECIMIENTO','VACACIONES','TELETRABAJO') and r.horas_permiso >= 8 then 0$new$;
  v_old := replace(v_old, E'\r\n', E'\n');
  if position(v_old in v_sql) = 0 then
    raise exception 'No se encontró la regla auxiliar de permisos.';
  end if;
  v_sql := replace(v_sql, v_old, v_new);
  v_old := $old$    descanso_medico = case when r.row_number = 1 and r.tipo_permiso = 'DESCANSO MEDICO'
      then r.horas_permiso else 0 end,
    licencia_maternidad =$old$;
  v_new := $new$    descanso_medico = case when r.row_number = 1 and r.tipo_permiso = 'DESCANSO MEDICO'
      then r.horas_permiso else 0 end,
    teletrabajo = case when r.row_number = 1 and r.tipo_permiso = 'TELETRABAJO'
      then r.horas_permiso else 0 end,
    licencia_maternidad =$new$;
  v_old := replace(v_old, E'\r\n', E'\n');
  if position(v_old in v_sql) = 0 then
    raise exception 'No se encontró el mapeo auxiliar para teletrabajo.';
  end if;
  execute replace(v_sql, v_old, v_new);
  end if;
end
$$;


create or replace function public.appgt_reconstruir_permisos_periodo_v2(p_periodo uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_periodo public."PLANILLA_PERIODOS_APPGT"%rowtype;
  v_desde date;
begin
  select * into v_periodo
  from public."PLANILLA_PERIODOS_APPGT"
  where id = p_periodo
    and empresa_id = public.appgt_empresa_actual_id()
    and not eliminado and deleted_at is null;
  if not found then
    raise exception 'Periodo de planilla no encontrado.';
  end if;

  v_desde := case
    when v_periodo.fecha_fin = (date_trunc('month', v_periodo.fecha_fin) + interval '1 month - 1 day')::date
      then date_trunc('month', v_periodo.fecha_fin)::date
    else v_periodo.fecha_inicio
  end;

  update public."PLANILLA_TRABAJADORES_ZUMAC"
  set descanso_medico = 0, licencia_maternidad = 0, licencia_paternidad = 0,
      licencia_fallecimiento = 0, comision = 0, permiso_sin_goce = 0,
      vacaciones = 0, teletrabajo = 0, updated_at = now()
  where empresa_id = v_periodo.empresa_id
    and fecha between v_desde and v_periodo.fecha_fin
    and activo and not eliminado and deleted_at is null;

  with ranked as (
    select p.id_local, p.dni, p.fecha,
      row_number() over (partition by p.dni, p.fecha order by
        case when p.origen_clave = 'SIN_TAREO' then 0 else 1 end,
        p.origen_clave, p.id_local) as rn,
      coalesce(w."HORAS_DIARIAS_PROMEDIO", 8) as jornada,
      q.tipo_permiso, q.con_goce_haber,
      case
        when q.id is null then 0
        when q.fecha_inicio = q.fecha_fin and q.hora_inicio is not null and q.hora_fin is not null
          then least(coalesce(w."HORAS_DIARIAS_PROMEDIO", 8), greatest(extract(epoch from (q.hora_fin-q.hora_inicio))/3600, 0))
        else coalesce(w."HORAS_DIARIAS_PROMEDIO", 8)
      end as horas_permiso
    from public."PLANILLA_TRABAJADORES_ZUMAC" p
    left join lateral (
      select x."HORAS_DIARIAS_PROMEDIO"
      from public."GH-REGISTRO_PERSONAL_PLANILLA" x
      where x.empresa_id = v_periodo.empresa_id
        and public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(x),array['DNI','DOCUMENTO']))
          = public.appgt_normalizar_clave(p.dni)
        and coalesce(x.activo, true) and not coalesce(x.eliminado, false) and x.deleted_at is null
      limit 1
    ) w on true
    left join lateral (
      select q.*
      from public."GH_PERMISOS_LICENCIAS_APPGT" q
      where q.empresa_id = v_periodo.empresa_id
        and public.appgt_normalizar_clave(q.dni) = public.appgt_normalizar_clave(p.dni)
        and p.fecha between q.fecha_inicio and q.fecha_fin
        and q.estado = 'APROBADO' and q."ESTADO_APROBACION" = 'APROBADO'
        and not q.eliminado and q.deleted_at is null
      order by q.fecha_aprobacion desc nulls last, q.updated_at desc, q.id
      limit 1
    ) q on true
    where p.empresa_id = v_periodo.empresa_id
      and p.fecha between v_desde and v_periodo.fecha_fin
      and p.activo and not p.eliminado and p.deleted_at is null
  )
  update public."PLANILLA_TRABAJADORES_ZUMAC" p
  set horas_trabajadas = case
        when r.rn = 1 and r.horas_permiso >= r.jornada then 0
        when r.rn = 1 and r.horas_permiso > 0 then greatest(p.horas_trabajadas-r.horas_permiso,0)
        else p.horas_trabajadas end,
      horas_extras_25 = case when r.rn = 1 and r.horas_permiso >= r.jornada then 0 else p.horas_extras_25 end,
      horas_extras_35 = case when r.rn = 1 and r.horas_permiso >= r.jornada then 0 else p.horas_extras_35 end,
      descanso_medico = case when r.rn = 1 and r.tipo_permiso = 'DESCANSO MEDICO' then r.horas_permiso else 0 end,
      teletrabajo = case when r.rn = 1 and r.tipo_permiso = 'TELETRABAJO' then r.horas_permiso else 0 end,
      licencia_maternidad = case when r.rn = 1 and r.tipo_permiso = 'LICENCIA DE MATERNIDAD' then r.horas_permiso else 0 end,
      licencia_paternidad = case when r.rn = 1 and r.tipo_permiso = 'LICENCIA DE PATERNIDAD' then r.horas_permiso else 0 end,
      licencia_fallecimiento = case when r.rn = 1 and r.tipo_permiso = 'LICENCIA POR FALLECIMIENTO' then r.horas_permiso else 0 end,
      comision = case when r.rn = 1 and r.tipo_permiso = 'COMISION DE SERVICIO' then r.horas_permiso else 0 end,
      permiso_sin_goce = case when r.rn = 1 and (r.tipo_permiso = 'PERMISO SIN GOCE' or not coalesce(r.con_goce_haber,true)) then r.horas_permiso else 0 end,
      vacaciones = case when r.rn = 1 and r.tipo_permiso = 'VACACIONES' then r.horas_permiso else 0 end,
      updated_at = now()
  from ranked r
  where p.id_local = r.id_local;
end
$$;

create or replace function public.appgt_aplicar_permisos_planilla_rango_v1(
  p_dni text,
  p_desde date,
  p_hasta date
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if nullif(btrim(p_dni), '') is null or p_desde is null or p_hasta is null or p_hasta < p_desde then
    return;
  end if;
  perform public.appgt_recalcular_planilla_zumac(p_dni, p_desde, p_hasta);

  update public."PLANILLA_TRABAJADORES_ZUMAC" p
  set descanso_medico = 0, licencia_maternidad = 0, licencia_paternidad = 0,
      licencia_fallecimiento = 0, comision = 0, permiso_sin_goce = 0,
      vacaciones = 0, teletrabajo = 0, updated_at = now()
  where public.appgt_normalizar_clave(p.dni) = public.appgt_normalizar_clave(p_dni)
    and p.fecha between p_desde and p_hasta
    and p.activo and not p.eliminado and p.deleted_at is null;

  with ranked as (
    select p.id_local, p.dni, p.fecha,
      row_number() over (partition by p.dni,p.fecha order by
        case when p.origen_clave = 'SIN_TAREO' then 0 else 1 end, p.origen_clave,p.id_local) as rn,
      coalesce(w."HORAS_DIARIAS_PROMEDIO",8) as jornada,
      q.tipo_permiso, q.con_goce_haber,
      case when q.id is null then 0
        when q.fecha_inicio=q.fecha_fin and q.hora_inicio is not null and q.hora_fin is not null
          then least(coalesce(w."HORAS_DIARIAS_PROMEDIO",8), greatest(extract(epoch from(q.hora_fin-q.hora_inicio))/3600,0))
        else coalesce(w."HORAS_DIARIAS_PROMEDIO",8) end as horas_permiso
    from public."PLANILLA_TRABAJADORES_ZUMAC" p
    left join lateral (
      select x."HORAS_DIARIAS_PROMEDIO" from public."GH-REGISTRO_PERSONAL_PLANILLA" x
      where public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(x),array['DNI','DOCUMENTO']))=public.appgt_normalizar_clave(p.dni)
        and coalesce(x.activo,true) and not coalesce(x.eliminado,false) and x.deleted_at is null
      limit 1
    ) w on true
    left join lateral (
      select q.* from public."GH_PERMISOS_LICENCIAS_APPGT" q
      where q.empresa_id=public.appgt_empresa_actual_id()
        and public.appgt_normalizar_clave(q.dni)=public.appgt_normalizar_clave(p_dni)
        and p.fecha between q.fecha_inicio and q.fecha_fin
        and q.estado='APROBADO' and q."ESTADO_APROBACION"='APROBADO'
        and not q.eliminado and q.deleted_at is null
      order by q.fecha_aprobacion desc nulls last,q.updated_at desc,q.id limit 1
    ) q on true
    where public.appgt_normalizar_clave(p.dni)=public.appgt_normalizar_clave(p_dni)
      and p.fecha between p_desde and p_hasta and p.activo and not p.eliminado and p.deleted_at is null
  )
  update public."PLANILLA_TRABAJADORES_ZUMAC" p
  set horas_trabajadas=case when r.rn=1 and r.horas_permiso>=r.jornada then 0
        when r.rn=1 and r.horas_permiso>0 then greatest(p.horas_trabajadas-r.horas_permiso,0) else p.horas_trabajadas end,
      horas_extras_25=case when r.rn=1 and r.horas_permiso>=r.jornada then 0 else p.horas_extras_25 end,
      horas_extras_35=case when r.rn=1 and r.horas_permiso>=r.jornada then 0 else p.horas_extras_35 end,
      descanso_medico=case when r.rn=1 and r.tipo_permiso='DESCANSO MEDICO' then r.horas_permiso else 0 end,
      teletrabajo=case when r.rn=1 and r.tipo_permiso='TELETRABAJO' then r.horas_permiso else 0 end,
      licencia_maternidad=case when r.rn=1 and r.tipo_permiso='LICENCIA DE MATERNIDAD' then r.horas_permiso else 0 end,
      licencia_paternidad=case when r.rn=1 and r.tipo_permiso='LICENCIA DE PATERNIDAD' then r.horas_permiso else 0 end,
      licencia_fallecimiento=case when r.rn=1 and r.tipo_permiso='LICENCIA POR FALLECIMIENTO' then r.horas_permiso else 0 end,
      comision=case when r.rn=1 and r.tipo_permiso='COMISION DE SERVICIO' then r.horas_permiso else 0 end,
      permiso_sin_goce=case when r.rn=1 and (r.tipo_permiso='PERMISO SIN GOCE' or not coalesce(r.con_goce_haber,true)) then r.horas_permiso else 0 end,
      vacaciones=case when r.rn=1 and r.tipo_permiso='VACACIONES' then r.horas_permiso else 0 end,
      updated_at=now()
  from ranked r where p.id_local=r.id_local;
end
$$;
notify pgrst, 'reload schema';
commit;
