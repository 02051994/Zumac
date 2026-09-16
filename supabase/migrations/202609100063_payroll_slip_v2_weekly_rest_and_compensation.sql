-- Boleta V2, descanso semanal configurable y compensacion de dias trabajados.
--
-- Esta migracion es monotona: no modifica el historico de asistencia ni borra
-- objetos de Storage. Las URL de PDF se invalidan para que se regenere el
-- documento con el contrato V2.
begin;

-- ---------------------------------------------------------------------------
-- Maestro de trabajadores: FRECUENCIA_PAGO es el dato operativo. El antiguo
-- "Periodo de pago" queda solo como texto informativo del sueldo mensual.
-- ---------------------------------------------------------------------------
-- No se vuelve a inferir la frecuencia desde el texto informativo. Los valores
-- heredados incompletos se dejan explícitamente en MENSUAL (valor por defecto)
-- para que RR.HH. cambie a QUINCENAL solo cuando corresponda al acuerdo vigente.
update public."GH-REGISTRO_PERSONAL_PLANILLA"
set "FRECUENCIA_PAGO" = case
  when upper(btrim(coalesce("FRECUENCIA_PAGO", ''))) in ('QUINCENAL','QUINCENA')
    then 'QUINCENAL'
  else 'MENSUAL'
end
where "FRECUENCIA_PAGO" is null
   or upper(btrim("FRECUENCIA_PAGO")) not in ('QUINCENAL','MENSUAL');

alter table public."GH-REGISTRO_PERSONAL_PLANILLA"
  alter column "FRECUENCIA_PAGO" set default 'MENSUAL',
  alter column "FRECUENCIA_PAGO" set not null,
  drop constraint if exists gh_personal_frecuencia_pago_check,
  add constraint gh_personal_frecuencia_pago_check
    check ("FRECUENCIA_PAGO" in ('QUINCENAL','MENSUAL'));

alter table public."GH-REGISTRO_PERSONAL_PLANILLA"
  add column if not exists "DIA_DESCANSO_SEMANAL" smallint;

update public."GH-REGISTRO_PERSONAL_PLANILLA"
set "DIA_DESCANSO_SEMANAL" = 7
where "DIA_DESCANSO_SEMANAL" is null;

alter table public."GH-REGISTRO_PERSONAL_PLANILLA"
  alter column "DIA_DESCANSO_SEMANAL" set default 7,
  alter column "DIA_DESCANSO_SEMANAL" set not null,
  drop constraint if exists gh_personal_dia_descanso_semanal_check,
  add constraint gh_personal_dia_descanso_semanal_check
    check ("DIA_DESCANSO_SEMANAL" between 1 and 7);

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set etiqueta = 'Periodo de pago (solo informativo)',
    updated_at = now()
where tabla_destino = 'GH-REGISTRO_PERSONAL_PLANILLA'
  and campo = 'Periodo de pago';

insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id, tabla_destino, campo, etiqueta, tipo, tipo_ui, id_campo_dropdown,
  requerido, visible, visible_tabla, editable, orden, activo,
  created_at, updated_at, estado_sync, eliminado
) values (
  'gh_planilla_frecuencia_pago_v2', 'GH-REGISTRO_PERSONAL_PLANILLA',
  'FRECUENCIA_PAGO', 'Frecuencia de pago (operativa)', 'text', 'dropdown',
  '[QUINCENAL;MENSUAL]', true, true, true, true, 904, true, now(), now(),
  'sincronizado', false
)
on conflict (tabla_destino, campo) do update set
  etiqueta = excluded.etiqueta,
  tipo = excluded.tipo,
  tipo_ui = excluded.tipo_ui,
  id_campo_dropdown = excluded.id_campo_dropdown,
  requerido = true,
  visible = true,
  visible_tabla = true,
  editable = true,
  orden = excluded.orden,
  activo = true,
  eliminado = false,
  updated_at = now();

insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id, tabla_destino, campo, etiqueta, tipo, tipo_ui, id_campo_dropdown,
  requerido, visible, visible_tabla, editable, orden, activo,
  created_at, updated_at, estado_sync, eliminado
) values (
  'gh_planilla_dia_descanso_semanal', 'GH-REGISTRO_PERSONAL_PLANILLA',
  'DIA_DESCANSO_SEMANAL', 'Dia de descanso semanal', 'numeric', 'number',
  null, true, true, true, true, 905, true, now(), now(), 'sincronizado', false
)
on conflict (tabla_destino, campo) do update set
  etiqueta = excluded.etiqueta,
  tipo = excluded.tipo,
  tipo_ui = excluded.tipo_ui,
  requerido = excluded.requerido,
  visible = excluded.visible,
  visible_tabla = excluded.visible_tabla,
  editable = excluded.editable,
  orden = excluded.orden,
  activo = true,
  eliminado = false,
  updated_at = now();

comment on column public."GH-REGISTRO_PERSONAL_PLANILLA"."DIA_DESCANSO_SEMANAL" is
  'ISO 1=lunes a 7=domingo. Se configura por trabajador; nunca se infiere por puesto.';
comment on column public."GH-REGISTRO_PERSONAL_PLANILLA"."FRECUENCIA_PAGO" is
  'Dato canónico operativo para liquidación: QUINCENAL o MENSUAL. No se deriva de "Periodo de pago".';

-- La BETA se conserva mensual por defecto. Solo se migra a prorrateada si el
-- trabajador agrario ya tiene fecha y documento de acuerdo verificables.
with convertidos as (
  update public."GH-REGISTRO_PERSONAL_PLANILLA" p
  set "MODALIDAD_BETA" = 'PRORRATEADA'
  where p."REGIMEN_LABORAL_CODIGO" = 'AGRARIO_31110'
    and p."MODALIDAD_BETA" = 'MENSUAL'
    and p."FECHA_ACUERDO_BETA" is not null
    and nullif(btrim(p."DOCUMENTO_ACUERDO_BETA"), '') is not null
  returning p.empresa_id,
    public.appgt_jsonb_text(to_jsonb(p), array['DNI', 'DOCUMENTO']) as dni,
    p."FECHA_ACUERDO_BETA" as vigente_desde,
    p."DOCUMENTO_ACUERDO_BETA" as documento_sustento
)
insert into public."PLANILLA_ELECCIONES_BENEFICIOS_APPGT" (
  empresa_id, dni, concepto, modalidad_anterior, modalidad_nueva,
  vigente_desde, documento_sustento, observaciones
)
select empresa_id, dni, 'BETA', 'MENSUAL', 'PRORRATEADA', vigente_desde,
  documento_sustento,
  'Migracion BOLETA_V2: conversion limitada a acuerdo BETA existente y documentado.'
from convertidos
where empresa_id is not null and dni is not null
on conflict (empresa_id, dni, concepto, vigente_desde) do update set
  modalidad_anterior = excluded.modalidad_anterior,
  modalidad_nueva = excluded.modalidad_nueva,
  documento_sustento = excluded.documento_sustento,
  observaciones = excluded.observaciones;

create or replace function public.appgt_validar_modalidad_beta_v2()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new."REGIMEN_LABORAL_CODIGO" = 'AGRARIO_31110'
     and new."MODALIDAD_BETA" = 'PRORRATEADA'
     and (
       new."FECHA_ACUERDO_BETA" is null
       or nullif(btrim(new."DOCUMENTO_ACUERDO_BETA"), '') is null
     ) then
    raise exception 'BETA PRORRATEADA exige fecha y documento de acuerdo escrito.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

-- La liquidación conserva cada concepto visible por separado, pero mantiene
-- las mismas bases legales del motor 045/051. Los bonos fijos del maestro se
-- prorratean como montos mensuales y no se copian a cada fila diaria.
do $$
declare
  v_sql text;
  v_old text;
  v_new text;
begin
  v_sql := replace(
    pg_get_functiondef('public.appgt_calcular_liquidacion_periodo_v2(uuid)'::regprocedure),
    E'\r\n', E'\n'
  );

  v_old := $old$  v_licencias numeric;
  v_he25_importe numeric;$old$;
  v_new := $new$  v_licencias numeric;
  v_compensacion numeric;
  v_sobretasa_dso numeric;
  v_bono_cargo_maestro numeric;
  v_bono_movilidad_maestro numeric;
  v_factor_bono numeric;
  v_clasificacion_movilidad text;
  v_he25_importe numeric;$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro la declaracion de importes de liquidacion V2.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$      coalesce(sum(descanso_medico_costo+teletrabajo_costo+licencia_maternidad_costo+
        licencia_paternidad_costo+licencia_fallecimiento_costo+comision_costo+vacaciones_costo),0),
      coalesce(sum(horas_extras_25_costo),0),$old$;
  v_new := $new$      coalesce(sum(descanso_medico_costo+teletrabajo_costo+licencia_maternidad_costo+
        licencia_paternidad_costo+licencia_fallecimiento_costo+comision_costo+vacaciones_costo),0),
      coalesce(sum(compensacion_costo),0),
      coalesce(sum(sobretasa_descanso_semanal_100_costo),0),
      coalesce(sum(horas_extras_25_costo),0),$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro el agregado de licencias de liquidacion V2.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$      v_descanso,v_licencias,v_he25_importe,v_he35_importe,v_noct_importe,$old$;
  v_new := $new$      v_descanso,v_licencias,v_compensacion,v_sobretasa_dso,
      v_he25_importe,v_he35_importe,v_noct_importe,$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro el INTO de importes de liquidacion V2.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  if position('d.licencia_fallecimiento+d.comision+d.vacaciones)>0' in v_sql)=0 then
    raise exception 'No se encontro la regla de dias elegibles BETA.';
  end if;
  v_sql := replace(
    v_sql,
    'd.licencia_fallecimiento+d.comision+d.vacaciones)>0',
    'd.licencia_fallecimiento+d.comision+d.vacaciones+d.horas_compensacion)>0'
  );

  v_old := $old$    v_basico := case when w."TIPO_REMUNERACION"='MENSUAL'
      then round(w.sueldo*v_dias/30.0,6)
      else round(v_basico_diario+v_descanso+v_licencias,6) end;$old$;
  v_new := $new$    v_basico := case when w."TIPO_REMUNERACION"='MENSUAL'
      then round(w.sueldo*v_dias/30.0,6)
      else round(v_basico_diario,6) end;$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro la remuneracion basica JORNAL para separarla.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$      v_basico:=0; v_asignacion:=0; v_descanso:=0; v_licencias:=0;
      v_he25_importe:=0; v_he35_importe:=0; v_noct_importe:=0;$old$;
  v_new := $new$      v_basico:=0; v_asignacion:=0; v_descanso:=0; v_licencias:=0;
      v_compensacion:=0; v_sobretasa_dso:=0;
      v_he25_importe:=0; v_he35_importe:=0; v_noct_importe:=0;$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro el bloque de liquidacion sin pago.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$    if w."TIPO_REMUNERACION"='MENSUAL' then
      v_descanso:=0; v_licencias:=0;
    end if;
    v_base_beneficios := v_basico+v_asignacion+v_otros_afectos;$old$;
  v_new := $new$    if w."TIPO_REMUNERACION"='MENSUAL' then
      v_descanso:=0; v_licencias:=0; v_compensacion:=0;
    end if;

    v_bono_cargo_maestro:=0;
    v_bono_movilidad_maestro:=0;
    v_factor_bono:=0;
    v_clasificacion_movilidad:=coalesce(
      nullif(btrim(w."CLASIFICACION_BONO_MOVILIDAD"),''),
      'REMUNERATIVA_AFECTA'
    );
    if v_paga_remuneracion then
      v_factor_bono:=least(greatest(case
        when w."TIPO_REMUNERACION"='JORNAL' then v_dias_elegibles/30.0
        else v_dias/30.0 end,0),1);
      v_bono_cargo_maestro:=round(greatest(coalesce(
        public.appgt_jsonb_numeric(to_jsonb(w),array['Bono al cargo'],0),0
      ),0)*v_factor_bono,6);
      v_bono_movilidad_maestro:=round(greatest(coalesce(
        public.appgt_jsonb_numeric(to_jsonb(w),array['Bono movilidad'],0),0
      ),0)*v_factor_bono,6);
      v_otros_afectos:=v_otros_afectos+v_bono_cargo_maestro;
      if v_clasificacion_movilidad='CONDICION_TRABAJO_INAFECTA'
         and nullif(btrim(w."DOCUMENTO_SUSTENTO_BONO_MOVILIDAD"),'') is not null then
        v_otros_inafectos:=v_otros_inafectos+v_bono_movilidad_maestro;
      else
        v_otros_afectos:=v_otros_afectos+v_bono_movilidad_maestro;
      end if;
    end if;

    v_base_beneficios := v_basico+v_descanso+v_licencias+v_compensacion+
      v_asignacion+v_otros_afectos;$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro el bloque de base de beneficios para bonos maestros.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$    v_base_afecta:=round(v_basico+v_asignacion+v_he25_importe+v_he35_importe+
      v_noct_importe+v_otros_afectos,6);$old$;
  v_new := $new$    v_base_afecta:=round(v_basico+v_descanso+v_licencias+v_compensacion+
      v_sobretasa_dso+v_asignacion+v_he25_importe+v_he35_importe+
      v_noct_importe+v_otros_afectos,6);$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro la base afecta de liquidacion para conceptos separados.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$      remuneracion_basica,asignacion_familiar,descanso_semanal,
      horas_extra_25_importe,horas_extra_35_importe,nocturnidad_importe,
      licencias_pagadas,beta_pagado,cts_pagada,gratificacion_pagada,$old$;
  v_new := $new$      remuneracion_basica,remuneracion_basica_jornales,
      asignacion_familiar,descanso_semanal,
      horas_extra_25_importe,horas_extra_35_importe,nocturnidad_importe,
      licencias_pagadas,compensacion_pagada,sobretasa_descanso_semanal_100,
      beta_pagado,cts_pagada,gratificacion_pagada,$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro la lista de columnas de liquidacion para conceptos V2.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$      bono_extraordinario_gratificacion,otros_ingresos_afectos,
      otros_ingresos_inafectos,remuneracion_bruta,$old$;
  v_new := $new$      bono_extraordinario_gratificacion,otros_ingresos_afectos,
      otros_ingresos_inafectos,bono_cargo_maestro,bono_movilidad_maestro,
      remuneracion_bruta,$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro la lista de otros ingresos de liquidacion V2.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$      v_dias,v_dias_sin_goce,v_horas,v_he25,v_he35,v_noct,v_basico,v_asignacion,
      v_descanso,v_he25_importe,v_he35_importe,v_noct_importe,v_licencias,v_beta,$old$;
  v_new := $new$      v_dias,v_dias_sin_goce,v_horas,v_he25,v_he35,v_noct,v_basico,
      case when w."TIPO_REMUNERACION"='JORNAL' then v_basico_diario else v_basico end,
      v_asignacion,v_descanso,v_he25_importe,v_he35_importe,v_noct_importe,
      v_licencias,v_compensacion,v_sobretasa_dso,v_beta,$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro la lista de valores base de liquidacion V2.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$       v_cts,v_grat,v_bono_grat,v_otros_afectos,v_otros_inafectos,v_bruto,$old$;
  v_new := $new$       v_cts,v_grat,v_bono_grat,v_otros_afectos,v_otros_inafectos,
       v_bono_cargo_maestro,v_bono_movilidad_maestro,v_bruto,$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro la lista de valores de otros ingresos V2.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$        'quinta_impuesto_anual',v_impuesto_anual,'fuente_parametro',v_param.fuente_legal)$old$;
  v_new := $new$        'quinta_impuesto_anual',v_impuesto_anual,'fuente_parametro',v_param.fuente_legal,
        'bono_factor_periodo',v_factor_bono,
        'clasificacion_bono_movilidad',v_clasificacion_movilidad)$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro el detalle JSON de liquidacion V2.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  execute v_sql;
end;
$$;

drop trigger if exists zzzz_appgt_validar_modalidad_beta_v2_trigger
  on public."GH-REGISTRO_PERSONAL_PLANILLA";
create trigger zzzz_appgt_validar_modalidad_beta_v2_trigger
before insert or update of "REGIMEN_LABORAL_CODIGO", "MODALIDAD_BETA",
  "FECHA_ACUERDO_BETA", "DOCUMENTO_ACUERDO_BETA"
on public."GH-REGISTRO_PERSONAL_PLANILLA"
for each row execute function public.appgt_validar_modalidad_beta_v2();

-- Los campos existentes "Bono al cargo" y "Bono movilidad" son montos
-- mensuales del maestro. No se crean columnas diarias paralelas: la liquidación
-- los prorratea una sola vez según días pagados del periodo. El bono por cargo
-- es remunerativo/afecto. La movilidad solo es inafecta si existe evidencia
-- explícita de condición de trabajo; sin ella se trata conservadoramente como
-- remunerativa/afecta. El costo operativo de transporte de la empresa permanece
-- en costo_movilidad_empresa y nunca forma parte de la boleta del trabajador.
alter table public."GH-REGISTRO_PERSONAL_PLANILLA"
  add column if not exists "CLASIFICACION_BONO_MOVILIDAD" text not null default 'REMUNERATIVA_AFECTA',
  add column if not exists "DOCUMENTO_SUSTENTO_BONO_MOVILIDAD" text;

alter table public."GH-REGISTRO_PERSONAL_PLANILLA"
  drop constraint if exists gh_personal_bonos_maestros_check,
  add constraint gh_personal_bonos_maestros_check check (
    coalesce("Bono al cargo", 0) >= 0
    and coalesce("Bono movilidad", 0) >= 0
    and "CLASIFICACION_BONO_MOVILIDAD" in (
      'REMUNERATIVA_AFECTA','CONDICION_TRABAJO_INAFECTA'
    )
  );

create or replace function public.appgt_validar_bonos_maestros_v2()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce(new."Bono movilidad", 0) > 0
     and new."CLASIFICACION_BONO_MOVILIDAD" = 'CONDICION_TRABAJO_INAFECTA'
     and nullif(btrim(new."DOCUMENTO_SUSTENTO_BONO_MOVILIDAD"), '') is null then
    raise exception 'La movilidad inafecta exige documento de sustento como condición de trabajo; clasifíquela como afecto si no cuenta con él.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists zzzz_appgt_validar_bonos_maestros_v2_trigger
  on public."GH-REGISTRO_PERSONAL_PLANILLA";
create trigger zzzz_appgt_validar_bonos_maestros_v2_trigger
before insert or update of "Bono al cargo", "Bono movilidad",
  "CLASIFICACION_BONO_MOVILIDAD", "DOCUMENTO_SUSTENTO_BONO_MOVILIDAD"
on public."GH-REGISTRO_PERSONAL_PLANILLA"
for each row execute function public.appgt_validar_bonos_maestros_v2();

comment on column public."GH-REGISTRO_PERSONAL_PLANILLA"."Bono al cargo" is
  'Bono maestro mensual por cargo; es remunerativo, afecto y se prorratea en la liquidación.';
comment on column public."GH-REGISTRO_PERSONAL_PLANILLA"."Bono movilidad" is
  'Bono maestro mensual de movilidad pagado al trabajador; distinto del costo operativo de transporte.';
comment on column public."GH-REGISTRO_PERSONAL_PLANILLA"."CLASIFICACION_BONO_MOVILIDAD" is
  'REMUNERATIVA_AFECTA por defecto; CONDICION_TRABAJO_INAFECTA requiere documento de sustento.';

-- ---------------------------------------------------------------------------
-- Compensacion: una ausencia pagada se vincula con el DSO configurado o un
-- feriado trabajado. No se permite reutilizar un origen aprobado.
-- ---------------------------------------------------------------------------
alter table public."GH_PERMISOS_LICENCIAS_APPGT"
  add column if not exists fecha_origen_compensacion date;

create index if not exists gh_permisos_compensacion_origen_lookup_idx
  on public."GH_PERMISOS_LICENCIAS_APPGT" (
    empresa_id, public.appgt_normalizar_clave(dni), fecha_origen_compensacion
  )
  where upper(btrim(tipo_permiso)) = 'COMPENSACION'
    and not coalesce(eliminado, false)
    and deleted_at is null;

create unique index if not exists gh_permisos_compensacion_origen_aprobada_uq
  on public."GH_PERMISOS_LICENCIAS_APPGT" (
    empresa_id, public.appgt_normalizar_clave(dni), fecha_origen_compensacion
  )
  where upper(btrim(tipo_permiso)) = 'COMPENSACION'
    and estado = 'APROBADO'
    and "ESTADO_APROBACION" = 'APROBADO'
    and not coalesce(eliminado, false)
    and deleted_at is null;

insert into public."MATRIZ_TIPOS_AUSENCIA_APPGT" (
  empresa_id, codigo, nombre, descripcion, con_goce_haber, documento_requerido,
  activo, eliminado, estado_sync, created_at, updated_at
)
select e.id, 'COMPENSACION_' || upper(substr(md5(e.id::text), 1, 8)),
  'COMPENSACION',
  'Dia pagado que compensa un domingo o feriado efectivamente trabajado y aprobado.',
  true, false, true, false, 'sincronizado', now(), now()
from public."EMPRESAS_APPGT" e
where coalesce(e.activo, true)
  and not exists (
    select 1
    from public."MATRIZ_TIPOS_AUSENCIA_APPGT" t
    where t.empresa_id = e.id
      and upper(btrim(t.nombre)) = 'COMPENSACION'
      and not coalesce(t.eliminado, false)
  );

create or replace function public.appgt_validar_compensacion_v2()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_es_compensacion boolean := upper(btrim(coalesce(new.tipo_permiso, ''))) = 'COMPENSACION';
  v_aprobada boolean := coalesce(new.estado, '') = 'APROBADO'
    and coalesce(new."ESTADO_APROBACION", '') = 'APROBADO';
  v_origen_habilitado boolean := false;
  v_origen_feriado boolean := false;
  v_dia_descanso integer := 7;
begin
  if not v_es_compensacion then
    return new;
  end if;

  if new.fecha_origen_compensacion is null then
    raise exception 'COMPENSACION requiere fecha_origen_compensacion.' using errcode = '23514';
  end if;
  if new.fecha_inicio is distinct from new.fecha_fin then
    raise exception 'COMPENSACION solo puede cubrir un dia.' using errcode = '23514';
  end if;
  if new.fecha_origen_compensacion = new.fecha_inicio then
    raise exception 'El origen y el dia compensado deben ser distintos.'
      using errcode = '23514';
  end if;

  select coalesce(p."DIA_DESCANSO_SEMANAL", 7) into v_dia_descanso
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  where p.empresa_id = new.empresa_id
    and public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(p), array['DNI','DOCUMENTO']))
      = public.appgt_normalizar_clave(new.dni)
    and coalesce(p.activo, true) and not coalesce(p.eliminado, false) and p.deleted_at is null
  limit 1;
  v_dia_descanso := least(greatest(coalesce(v_dia_descanso, 7), 1), 7);

  v_origen_feriado := exists (
    select 1 from public."PLANILLA_FERIADOS_APPGT" f
    where f.fecha = new.fecha_origen_compensacion
      and f.activo and f.remunerado
      and (f.empresa_id is null or f.empresa_id = new.empresa_id)
  );
  v_origen_habilitado := extract(isodow from new.fecha_origen_compensacion) = v_dia_descanso
    or v_origen_feriado;
  if not v_origen_habilitado then
    raise exception 'El origen de COMPENSACION debe ser el descanso semanal configurado o un feriado remunerado.'
      using errcode = '23514';
  end if;
  if not v_origen_feriado
     and date_trunc('week', new.fecha_origen_compensacion) <> date_trunc('week', new.fecha_inicio) then
    raise exception 'La compensacion del descanso semanal debe quedar en la misma semana ISO.'
      using errcode = '23514';
  end if;
  if not v_origen_feriado
     and extract(isodow from new.fecha_inicio)::integer = v_dia_descanso then
    raise exception 'El descanso sustitutorio no puede recaer nuevamente en el DSO configurado.'
      using errcode = '23514';
  end if;

  new.con_goce_haber := true;
  if not v_aprobada then
    return new;
  end if;

  if not exists (
    select 1
    from public."GT-TAREO_PERSONAL" t
    join public."GT-ASISTENCIA_PERSONAL" a
      on a.empresa_id = new.empresa_id
      and public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(a), array['DNI', 'DOCUMENTO']))
        = public.appgt_normalizar_clave(new.dni)
      and public.appgt_jsonb_date(to_jsonb(a), array['FECHA', 'FECHA_INGRESO'])
        = new.fecha_origen_compensacion
      and not public.appgt_jsonb_bool(to_jsonb(a), array['eliminado'], false)
      and public.appgt_jsonb_text(to_jsonb(a), array['deleted_at']) is null
    where t.empresa_id = new.empresa_id
      and public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(t), array['DNI', 'DOCUMENTO']))
        = public.appgt_normalizar_clave(new.dni)
      and public.appgt_jsonb_date(to_jsonb(t), array['FECHA']) = new.fecha_origen_compensacion
      and t."ESTADO_APROBACION" = 'APROBADO'
      and public.appgt_jsonb_numeric(to_jsonb(t), array['HORAS_TRABAJADAS'], 0) > 0
      and not public.appgt_jsonb_bool(to_jsonb(t), array['eliminado'], false)
      and public.appgt_jsonb_text(to_jsonb(t), array['deleted_at']) is null
  ) then
    raise exception 'La compensacion requiere asistencia y tareo aprobado en su fecha de origen.'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public."GH_PERMISOS_LICENCIAS_APPGT" q
    where q.empresa_id = new.empresa_id
      and public.appgt_normalizar_clave(q.dni) = public.appgt_normalizar_clave(new.dni)
      and q.fecha_origen_compensacion = new.fecha_origen_compensacion
      and upper(btrim(q.tipo_permiso)) = 'COMPENSACION'
      and q.estado = 'APROBADO'
      and q."ESTADO_APROBACION" = 'APROBADO'
      and not q.eliminado and q.deleted_at is null
      and q.id is distinct from new.id
  ) then
    raise exception 'La fecha de origen ya tiene una COMPENSACION aprobada.' using errcode = '23505';
  end if;
  return new;
end;
$$;

drop trigger if exists zzzz_appgt_validar_compensacion_v2_trigger
  on public."GH_PERMISOS_LICENCIAS_APPGT";
create trigger zzzz_appgt_validar_compensacion_v2_trigger
before insert or update of tipo_permiso, fecha_inicio, fecha_fin,
  fecha_origen_compensacion, estado, "ESTADO_APROBACION", dni, empresa_id
on public."GH_PERMISOS_LICENCIAS_APPGT"
for each row execute function public.appgt_validar_compensacion_v2();

alter table public."PLANILLA_TRABAJADORES_ZUMAC"
  add column if not exists horas_compensacion numeric(12,4) not null default 0,
  add column if not exists compensacion_costo numeric(18,6) not null default 0,
  add column if not exists horas_sobretasa_descanso_semanal_100 numeric(12,4) not null default 0,
  add column if not exists sobretasa_descanso_semanal_100_costo numeric(18,6) not null default 0,
  add column if not exists horas_trabajadas_origen numeric(12,4) not null default 0,
  add column if not exists horas_extras_25_origen numeric(12,4) not null default 0,
  add column if not exists horas_extras_35_origen numeric(12,4) not null default 0,
  add column if not exists horas_origen_v2_capturadas boolean not null default false;

-- La primera captura conserva el estado visible heredado. En cada recálculo el
-- origen vuelve a tomar el tareo aprobado, de modo que una segunda reconstrucción
-- nunca descuente nuevamente horas ya reclasificadas por un permiso.
update public."PLANILLA_TRABAJADORES_ZUMAC" diario
set horas_trabajadas_origen = coalesce(horas_trabajadas, 0),
    horas_extras_25_origen = coalesce(horas_extras_25, 0),
    horas_extras_35_origen = coalesce(horas_extras_35, 0),
    horas_origen_v2_capturadas = true
where not diario.horas_origen_v2_capturadas
  and not exists (
    select 1
    from public."PLANILLA_PERIODOS_APPGT" periodo
    where periodo.id = diario.periodo_id
      and periodo.estado = 'CERRADA'
  );

alter table public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT"
  add column if not exists remuneracion_basica_jornales numeric(18,6) not null default 0,
  add column if not exists compensacion_pagada numeric(18,6) not null default 0,
  add column if not exists sobretasa_descanso_semanal_100 numeric(18,6) not null default 0,
  add column if not exists bono_cargo_maestro numeric(18,6) not null default 0,
  add column if not exists bono_movilidad_maestro numeric(18,6) not null default 0;

comment on column public."PLANILLA_TRABAJADORES_ZUMAC".horas_compensacion is
  'Horas de ausencia pagada por COMPENSACION; se muestran con etiqueta C en boleta.';
comment on column public."PLANILLA_TRABAJADORES_ZUMAC".horas_sobretasa_descanso_semanal_100 is
  'Horas equivalentes de sobretasa 100 % por descanso semanal trabajado sin sustituto valido.';
comment on column public."PLANILLA_TRABAJADORES_ZUMAC".horas_trabajadas_origen is
  'Horas ordinarias provenientes del tareo antes de reclasificar permisos; base idempotente de la reconstrucción.';

-- Permisos aprobados se reconstruyen a partir de las horas de origen:
-- COMPENSACION es una ausencia pagada, no una asistencia ni una hora extra.
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
  if not found then raise exception 'Periodo de planilla no encontrado.'; end if;

  v_desde := case when v_periodo.fecha_fin =
    (date_trunc('month', v_periodo.fecha_fin) + interval '1 month - 1 day')::date
    then date_trunc('month', v_periodo.fecha_fin)::date else v_periodo.fecha_inicio end;

  update public."PLANILLA_TRABAJADORES_ZUMAC"
  set descanso_medico=0, licencia_maternidad=0, licencia_paternidad=0,
      licencia_fallecimiento=0, comision=0, permiso_sin_goce=0, vacaciones=0,
      teletrabajo=0, horas_compensacion=0, updated_at=now()
  where empresa_id=v_periodo.empresa_id
    and fecha between v_desde and v_periodo.fecha_fin
    and activo and not eliminado and deleted_at is null;

  with ranked as (
    select p.id_local,p.dni,p.fecha,
      row_number() over (partition by p.dni,p.fecha order by
        case when p.origen_clave='SIN_TAREO' then 0 else 1 end,p.origen_clave,p.id_local) as rn,
      coalesce(p.horas_trabajadas_origen,0)+coalesce(p.horas_extras_25_origen,0)
        +coalesce(p.horas_extras_35_origen,0) as horas_origen,
      coalesce(sum(coalesce(p.horas_trabajadas_origen,0)+coalesce(p.horas_extras_25_origen,0)
        +coalesce(p.horas_extras_35_origen,0)) over (
          partition by p.dni,p.fecha order by
            case when p.origen_clave='SIN_TAREO' then 0 else 1 end,p.origen_clave,p.id_local
          rows between unbounded preceding and 1 preceding
        ),0) as horas_previas,
      coalesce(w."HORAS_DIARIAS_PROMEDIO",8) as jornada
    from public."PLANILLA_TRABAJADORES_ZUMAC" p
    left join lateral (
      select x."HORAS_DIARIAS_PROMEDIO"
      from public."GH-REGISTRO_PERSONAL_PLANILLA" x
      where x.empresa_id=v_periodo.empresa_id
        and public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(x),array['DNI','DOCUMENTO']))
          = public.appgt_normalizar_clave(p.dni)
        and coalesce(x.activo,true) and not coalesce(x.eliminado,false) and x.deleted_at is null
      limit 1
    ) w on true
    where p.empresa_id=v_periodo.empresa_id
      and p.fecha between v_desde and v_periodo.fecha_fin
      and p.activo and not p.eliminado and p.deleted_at is null
  ), resolved as (
    select r.*,
      q.tipo_permiso,q.con_goce_haber,
      case when q.id is null then 0
        when q.fecha_inicio=q.fecha_fin and q.hora_inicio is not null and q.hora_fin is not null
          then least(r.jornada,greatest(extract(epoch from (q.hora_fin-q.hora_inicio))/3600,0))
        else r.jornada end as horas_permiso
    from ranked r
    left join lateral (
      select q.* from public."GH_PERMISOS_LICENCIAS_APPGT" q
      where q.empresa_id=v_periodo.empresa_id
        and public.appgt_normalizar_clave(q.dni)=public.appgt_normalizar_clave(r.dni)
        and r.fecha between q.fecha_inicio and q.fecha_fin
        and q.estado='APROBADO' and q."ESTADO_APROBACION"='APROBADO'
        and not q.eliminado and q.deleted_at is null
      order by q.fecha_aprobacion desc nulls last,q.updated_at desc,q.id limit 1
    ) q on true
  ), reclassified as (
    select r.*,
      greatest(least(coalesce(r.horas_permiso,0)+r.horas_previas+r.horas_origen,r.jornada)
        -least(coalesce(r.horas_permiso,0)+r.horas_previas,r.jornada),0) as horas_regulares_nuevas,
      greatest(least(coalesce(r.horas_permiso,0)+r.horas_previas+r.horas_origen,r.jornada+2)
        -greatest(coalesce(r.horas_permiso,0)+r.horas_previas,r.jornada),0) as horas_25_nuevas,
      greatest(coalesce(r.horas_permiso,0)+r.horas_previas+r.horas_origen
        -greatest(coalesce(r.horas_permiso,0)+r.horas_previas,r.jornada+2),0) as horas_35_nuevas
    from resolved r
  )
  update public."PLANILLA_TRABAJADORES_ZUMAC" p
  set horas_trabajadas=r.horas_regulares_nuevas,
      horas_extras_25=r.horas_25_nuevas,
      horas_extras_35=r.horas_35_nuevas,
      descanso_medico=case when r.rn=1 and r.tipo_permiso='DESCANSO MEDICO' then r.horas_permiso else 0 end,
      teletrabajo=case when r.rn=1 and r.tipo_permiso='TELETRABAJO' then r.horas_permiso else 0 end,
      licencia_maternidad=case when r.rn=1 and r.tipo_permiso='LICENCIA DE MATERNIDAD' then r.horas_permiso else 0 end,
      licencia_paternidad=case when r.rn=1 and r.tipo_permiso='LICENCIA DE PATERNIDAD' then r.horas_permiso else 0 end,
      licencia_fallecimiento=case when r.rn=1 and r.tipo_permiso='LICENCIA POR FALLECIMIENTO' then r.horas_permiso else 0 end,
      comision=case when r.rn=1 and r.tipo_permiso='COMISION DE SERVICIO' then r.horas_permiso else 0 end,
      permiso_sin_goce=case when r.rn=1 and (r.tipo_permiso='PERMISO SIN GOCE' or not coalesce(r.con_goce_haber,true)) then r.horas_permiso else 0 end,
      vacaciones=case when r.rn=1 and r.tipo_permiso='VACACIONES' then r.horas_permiso else 0 end,
      horas_compensacion=case when r.rn=1 and r.tipo_permiso='COMPENSACION' then r.horas_permiso else 0 end,
      updated_at=now()
  from reclassified r where p.id_local=r.id_local;
end;
$$;

create or replace function public.appgt_aplicar_permisos_planilla_rango_v1(
  p_dni text, p_desde date, p_hasta date
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_periodo uuid;
begin
  if nullif(btrim(p_dni),'') is null or p_desde is null or p_hasta is null or p_hasta<p_desde then
    return;
  end if;
  perform public.appgt_recalcular_planilla_zumac(p_dni,p_desde,p_hasta);
  select periodo_id into v_periodo
  from public."PLANILLA_TRABAJADORES_ZUMAC"
  where public.appgt_normalizar_clave(dni)=public.appgt_normalizar_clave(p_dni)
    and fecha between p_desde and p_hasta and periodo_id is not null
  order by updated_at desc nulls last limit 1;
  if v_periodo is not null then
    perform public.appgt_reconstruir_permisos_periodo_v2(v_periodo);
  end if;
end;
$$;

-- Los parches 053 (ONP), 054 (tipo AFP) y 057 (metadatos de periodo) deben
-- estar presentes antes de ampliar el trigger diario.
do $$
declare
  v_sql text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef('public.appgt_calcular_costos_planilla_zumac()'::regprocedure)
    into v_sql;
  if position('v_afp public."PLANILLA_TASAS_AFP_APPGT"%rowtype;' in v_sql)=0
     or position('case when v_pension = ''AFP'' then' in v_sql)=0
     or position('to_jsonb(new) - array[''periodo_id''' in v_sql)=0 then
    raise exception 'No se preservaron los fixes 053/054/057 del trigger diario.';
  end if;

  v_old := $old$
  new.vacaciones_costo := round(coalesce(new.vacaciones,0)*v_hora_ordinaria,6);

  v_base_beneficios := new.basico_costo + new.asignacion_familiar_costo
    + new.descanso_semanal_costo + new.descanso_medico_costo
    + new.teletrabajo_costo + new.licencia_maternidad_costo
    + new.licencia_paternidad_costo + new.licencia_fallecimiento_costo
    + new.comision_costo + new.vacaciones_costo;$old$;
  v_new := $new$
  new.vacaciones_costo := round(coalesce(new.vacaciones,0)*v_hora_ordinaria,6);
  new.compensacion_costo := round(coalesce(new.horas_compensacion,0)*v_hora_ordinaria,6);
  new.sobretasa_descanso_semanal_100_costo := round(
    coalesce(new.horas_sobretasa_descanso_semanal_100,0)*v_hora_ordinaria,6
  );

  v_base_beneficios := new.basico_costo + new.asignacion_familiar_costo
    + new.descanso_semanal_costo + new.descanso_medico_costo
    + new.teletrabajo_costo + new.licencia_maternidad_costo
    + new.licencia_paternidad_costo + new.licencia_fallecimiento_costo
    + new.comision_costo + new.vacaciones_costo + new.compensacion_costo;$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro el bloque diario de licencias para COMPENSACION.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$
      +coalesce(new.licencia_fallecimiento,0)+coalesce(new.comision,0)
      +coalesce(new.vacaciones,0))$old$;
  v_new := $new$
      +coalesce(new.licencia_fallecimiento,0)+coalesce(new.comision,0)
      +coalesce(new.vacaciones,0)+coalesce(new.horas_compensacion,0))$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro el elegible BETA diario para COMPENSACION.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$
  v_base_afecta := v_base_beneficios + new.horas_extras_25_costo
    + new.horas_extras_35_costo + new.horas_nocturnas_costo
    + coalesce(new.bono_cargo_costo,0)+coalesce(new.bono_labor_costo,0);$old$;
  v_new := $new$
  v_base_afecta := v_base_beneficios + new.sobretasa_descanso_semanal_100_costo
    + new.horas_extras_25_costo + new.horas_extras_35_costo + new.horas_nocturnas_costo
    + coalesce(new.bono_cargo_costo,0)+coalesce(new.bono_labor_costo,0);$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro la base afecta diaria para sobretasa DSO.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  if position('new.compensacion_costo := round' in v_sql)=0
     or position('new.sobretasa_descanso_semanal_100_costo := round' in v_sql)=0 then
    raise exception 'El trigger diario V2 no quedo completamente instalado.';
  end if;
  execute v_sql;
end;
$$;

-- DL 713 y su Reglamento (DS 012-92-TR): el DSO se remunera en proporción
-- a los días efectivamente trabajados. Se computa trabajo con asistencia+tareo
-- aprobado, ausencia aprobada y pagada por el empleador, o feriado remunerado;
-- nunca se inventa una falta porque no exista una fila de control.
create or replace function public.appgt_dias_efectivos_descanso_semanal_v2(
  p_empresa uuid,
  p_dni text,
  p_desde date,
  p_hasta date
)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select count(*)::numeric
  from generate_series(p_desde, p_hasta, interval '1 day') g(fecha)
  where exists (
    select 1
    from public."GT-TAREO_PERSONAL" t
    where t.empresa_id = p_empresa
      and public.appgt_normalizar_clave(
        public.appgt_jsonb_text(to_jsonb(t), array['DNI','DOCUMENTO'])
      ) = public.appgt_normalizar_clave(p_dni)
      and public.appgt_jsonb_date(to_jsonb(t), array['FECHA']) = g.fecha::date
      and t."ESTADO_APROBACION" = 'APROBADO'
      and public.appgt_jsonb_numeric(to_jsonb(t), array['HORAS_TRABAJADAS'], 0) > 0
      and not public.appgt_jsonb_bool(to_jsonb(t), array['eliminado'], false)
      and public.appgt_jsonb_text(to_jsonb(t), array['deleted_at']) is null
      and exists (
        select 1 from public."GT-ASISTENCIA_PERSONAL" a
        where a.empresa_id = p_empresa
          and public.appgt_normalizar_clave(
            public.appgt_jsonb_text(to_jsonb(a), array['DNI','DOCUMENTO'])
          ) = public.appgt_normalizar_clave(p_dni)
          and public.appgt_jsonb_date(to_jsonb(a), array['FECHA','FECHA_INGRESO']) = g.fecha::date
          and not public.appgt_jsonb_bool(to_jsonb(a), array['eliminado'], false)
          and public.appgt_jsonb_text(to_jsonb(a), array['deleted_at']) is null
      )
  ) or exists (
    select 1 from public."GH_PERMISOS_LICENCIAS_APPGT" q
    where q.empresa_id = p_empresa
      and public.appgt_normalizar_clave(q.dni) = public.appgt_normalizar_clave(p_dni)
      and g.fecha::date between q.fecha_inicio and q.fecha_fin
      and q.estado = 'APROBADO' and q."ESTADO_APROBACION" = 'APROBADO'
      and coalesce(q.con_goce_haber, false)
      and not q.eliminado and q.deleted_at is null
  ) or exists (
    select 1 from public."PLANILLA_FERIADOS_APPGT" f
    where f.fecha = g.fecha::date and f.activo and f.remunerado
      and (f.empresa_id is null or f.empresa_id = p_empresa)
  );
$$;

create or replace function public.appgt_horas_dso_trabajadas_v2(
  p_empresa uuid,
  p_dni text,
  p_fecha date
)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum(greatest(
    public.appgt_jsonb_numeric(to_jsonb(t), array['HORAS_TRABAJADAS'], 0), 0
  )), 0)
  from public."GT-TAREO_PERSONAL" t
  where t.empresa_id = p_empresa
    and public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(t), array['DNI','DOCUMENTO'])
    ) = public.appgt_normalizar_clave(p_dni)
    and public.appgt_jsonb_date(to_jsonb(t), array['FECHA']) = p_fecha
    and t."ESTADO_APROBACION" = 'APROBADO'
    and not public.appgt_jsonb_bool(to_jsonb(t), array['eliminado'], false)
    and public.appgt_jsonb_text(to_jsonb(t), array['deleted_at']) is null
    and exists (
      select 1 from public."GT-ASISTENCIA_PERSONAL" a
      where a.empresa_id = p_empresa
        and public.appgt_normalizar_clave(
          public.appgt_jsonb_text(to_jsonb(a), array['DNI','DOCUMENTO'])
        ) = public.appgt_normalizar_clave(p_dni)
        and public.appgt_jsonb_date(to_jsonb(a), array['FECHA','FECHA_INGRESO']) = p_fecha
        and not public.appgt_jsonb_bool(to_jsonb(a), array['eliminado'], false)
        and public.appgt_jsonb_text(to_jsonb(a), array['deleted_at']) is null
    );
$$;

create or replace function public.appgt_tiene_sustituto_dso_v2(
  p_empresa uuid,
  p_dni text,
  p_origen date,
  p_dia_descanso integer
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public."GH_PERMISOS_LICENCIAS_APPGT" q
    where q.empresa_id = p_empresa
      and public.appgt_normalizar_clave(q.dni) = public.appgt_normalizar_clave(p_dni)
      and q.fecha_origen_compensacion = p_origen
      and q.fecha_inicio <> p_origen
      and date_trunc('week', q.fecha_inicio) = date_trunc('week', p_origen)
      and extract(isodow from q.fecha_inicio)::integer <> p_dia_descanso
      and upper(btrim(q.tipo_permiso)) = 'COMPENSACION'
      and q.estado = 'APROBADO' and q."ESTADO_APROBACION" = 'APROBADO'
      and not q.eliminado and q.deleted_at is null
  );
$$;

-- El recálculo diario conserva el selector de contratos pendientes de la 051,
-- pero sustituye el domingo fijo por DIA_DESCANSO_SEMANAL del trabajador.
-- Las aserciones evitan aplicar el parche sobre una definición inesperada.
do $$
declare
  v_sql text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef('public.appgt_recalcular_planilla_zumac(text,date,date)'::regprocedure)
    into v_sql;

  v_old := $old$
      public.appgt_jsonb_text(s.data, array['Puesto','PUESTO','CARGO']) puesto,
      public.appgt_jsonb_text(s.data, array['Periodo de pago','PERIODO_PAGO']) periodo_pago$old$;
  v_new := $new$
      public.appgt_jsonb_text(s.data, array['Puesto','PUESTO','CARGO']) puesto,
       public.appgt_jsonb_text(s.data, array['Periodo de pago','PERIODO_PAGO']) periodo_pago,
       least(greatest(coalesce(public.appgt_jsonb_numeric(
         s.data, array['DIA_DESCANSO_SEMANAL'], 7
       ), 7), 1), 7)::integer as dia_descanso_semanal,
       greatest(public.appgt_jsonb_numeric(s.data, array['HORAS_DIARIAS_PROMEDIO'], 8), 0.001) as jornada$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro el selector de trabajador para DIA_DESCANSO_SEMANAL.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$
      least(public.appgt_horas_nocturnas(d.hora_inicio, d.hora_fin), d.raw_hours) night_hours,
      case when extract(dow from d.fecha) = 0 and d.source_order = 1 then (
        select count(distinct public.appgt_jsonb_date(to_jsonb(a), array['FECHA']))::numeric
        from public."GT-TAREO_PERSONAL" a
        where public.appgt_normalizar_clave(
          public.appgt_jsonb_text(to_jsonb(a), array['DNI','DOCUMENTO'])
        ) = public.appgt_normalizar_clave(d.dni)
          and public.appgt_jsonb_date(to_jsonb(a), array['FECHA'])
              between d.fecha - 6 and d.fecha - 1
          and a."ESTADO_APROBACION" = 'APROBADO'
          and public.appgt_jsonb_numeric(to_jsonb(a), array['HORAS_TRABAJADAS'], 0) > 0
          and not public.appgt_jsonb_bool(to_jsonb(a), array['eliminado'], false)
          and public.appgt_jsonb_text(to_jsonb(a), array['deleted_at']) is null
      ) * 8.0 / 6.0 else 0 end weekly_rest$old$;
  v_new := $new$
      least(public.appgt_horas_nocturnas(d.hora_inicio, d.hora_fin), d.raw_hours) night_hours,
      case when extract(isodow from d.fecha)::integer = d.dia_descanso_semanal
          and d.source_order = 1 then
        case when public.appgt_horas_dso_trabajadas_v2(
          public.appgt_empresa_actual_id(), d.dni, d.fecha
        ) > 0 and public.appgt_tiene_sustituto_dso_v2(
          public.appgt_empresa_actual_id(), d.dni, d.fecha, d.dia_descanso_semanal
        ) then 0
        else public.appgt_dias_efectivos_descanso_semanal_v2(
          public.appgt_empresa_actual_id(), d.dni, d.fecha - 6, d.fecha - 1
        ) * 8.0 / 6.0 end
      else 0 end weekly_rest,
      case when extract(isodow from d.fecha)::integer = d.dia_descanso_semanal
          and d.source_order = 1
          and public.appgt_horas_dso_trabajadas_v2(
            public.appgt_empresa_actual_id(), d.dni, d.fecha
          ) > 0
          and not public.appgt_tiene_sustituto_dso_v2(
            public.appgt_empresa_actual_id(), d.dni, d.fecha, d.dia_descanso_semanal
          ) then public.appgt_horas_dso_trabajadas_v2(
            public.appgt_empresa_actual_id(), d.dni, d.fecha
          )
      else 0 end weekly_rest_surcharge$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro la regla heredada de domingo para descanso semanal.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$
    horas_trabajadas, descanso_semanal, horas_extras_25,
    horas_extras_35, horas_nocturnas$old$;
  v_new := $new$
    horas_trabajadas, descanso_semanal, horas_sobretasa_descanso_semanal_100,
    horas_extras_25, horas_extras_35, horas_nocturnas$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro el INSERT diario para sobretasa DSO.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$
    round(r.regular_hours, 4), round(r.weekly_rest, 4), round(r.extra_25, 4),
    round(r.extra_35, 4), round(r.night_hours, 4)$old$;
  v_new := $new$
    round(r.regular_hours, 4), round(r.weekly_rest, 4),
    round(r.weekly_rest_surcharge, 4), round(r.extra_25, 4),
    round(r.extra_35, 4), round(r.night_hours, 4)$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro el SELECT diario para sobretasa DSO.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$
    horas_trabajadas = excluded.horas_trabajadas,
    descanso_semanal = excluded.descanso_semanal,
    horas_extras_25 = excluded.horas_extras_25,$old$;
  v_new := $new$
    horas_trabajadas = excluded.horas_trabajadas,
    descanso_semanal = excluded.descanso_semanal,
    horas_sobretasa_descanso_semanal_100 = excluded.horas_sobretasa_descanso_semanal_100,
    horas_extras_25 = excluded.horas_extras_25,$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro el UPSERT diario para sobretasa DSO.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$
    horas_extras_25, horas_extras_35, horas_nocturnas$old$;
  v_new := $new$
    horas_extras_25, horas_extras_35, horas_nocturnas,
    horas_trabajadas_origen, horas_extras_25_origen,
    horas_extras_35_origen, horas_origen_v2_capturadas$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro el cierre de columnas diarias para guardar horas de origen.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$
    round(r.extra_35, 4), round(r.night_hours, 4)$old$;
  v_new := $new$
    round(r.extra_35, 4), round(r.night_hours, 4),
    round(r.regular_hours, 4), round(r.extra_25, 4),
    round(r.extra_35, 4), true$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro el cierre de valores diarios para guardar horas de origen.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $old$
    horas_extras_25 = excluded.horas_extras_25,$old$;
  v_new := $new$
    horas_trabajadas_origen = excluded.horas_trabajadas_origen,
    horas_extras_25_origen = excluded.horas_extras_25_origen,
    horas_extras_35_origen = excluded.horas_extras_35_origen,
    horas_origen_v2_capturadas = true,
    horas_extras_25 = excluded.horas_extras_25,$new$;
  if position(v_old in v_sql)=0 then
    raise exception 'No se encontro el UPSERT diario para refrescar horas de origen.';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  if position('extract(isodow from d.fecha)::integer = d.dia_descanso_semanal' in v_sql)=0
     or position('weekly_rest_surcharge' in v_sql)=0 then
    raise exception 'La regla configurable de descanso semanal no quedo instalada.';
  end if;
  execute v_sql;
end;
$$;

-- Metadatos editables de los nuevos datos maestros y del vínculo de
-- compensación. Los importes de bonos existentes conservan sus nombres.
insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id,tabla_destino,campo,etiqueta,tipo,tipo_ui,id_campo_dropdown,
  requerido,visible,visible_tabla,editable,orden,activo,
  created_at,updated_at,estado_sync,eliminado
) values
  ('gh_planilla_clasif_mov_v2','GH-REGISTRO_PERSONAL_PLANILLA',
   'CLASIFICACION_BONO_MOVILIDAD','Clasificación bono movilidad','text','dropdown',
   '[REMUNERATIVA_AFECTA;CONDICION_TRABAJO_INAFECTA]',true,true,true,true,906,true,
   now(),now(),'sincronizado',false),
  ('gh_planilla_sustento_mov_v2','GH-REGISTRO_PERSONAL_PLANILLA',
   'DOCUMENTO_SUSTENTO_BONO_MOVILIDAD','Sustento bono movilidad','text','text',
   null,false,true,false,true,907,true,now(),now(),'sincronizado',false),
  ('gh_permiso_origen_comp_v2','GH_PERMISOS_LICENCIAS_APPGT',
   'fecha_origen_compensacion','Fecha trabajada a compensar','date','date',
   null,false,true,true,true,908,true,now(),now(),'sincronizado',false)
on conflict (tabla_destino,campo) do update set
  etiqueta=excluded.etiqueta,tipo=excluded.tipo,tipo_ui=excluded.tipo_ui,
  id_campo_dropdown=excluded.id_campo_dropdown,requerido=excluded.requerido,
  visible=excluded.visible,visible_tabla=excluded.visible_tabla,
  editable=excluded.editable,orden=excluded.orden,activo=true,eliminado=false,
  updated_at=now();

-- Versionado de documentos: un snapshot nuevo invalida el PDF almacenado.
alter table public."PLANILLA_BOLETAS_APPGT"
  add column if not exists pdf_version integer not null default 0,
  drop constraint if exists planilla_boletas_pdf_version_check,
  add constraint planilla_boletas_pdf_version_check check (pdf_version >= 0);

create or replace function public.appgt_invalidar_pdf_boleta_v2()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if old.liquidacion_id is distinct from new.liquidacion_id
     or old.liquidacion_snapshot is distinct from new.liquidacion_snapshot then
    new.pdf_url:=null;
    new.pdf_generado_at:=null;
    new.pdf_version:=0;
    if new.estado<>'ANULADA' then new.estado:='PENDIENTE'; end if;
  end if;
  return new;
end;
$$;

drop trigger if exists appgt_invalidar_pdf_boleta_v2_trigger
  on public."PLANILLA_BOLETAS_APPGT";
create trigger appgt_invalidar_pdf_boleta_v2_trigger
before update of liquidacion_id,liquidacion_snapshot
on public."PLANILLA_BOLETAS_APPGT"
for each row execute function public.appgt_invalidar_pdf_boleta_v2();

update public."PLANILLA_BOLETAS_APPGT"
set pdf_url=null,pdf_generado_at=null,pdf_version=0,
    estado=case when estado='ANULADA' then estado else 'PENDIENTE' end,
    updated_at=now()
where pdf_version<2 or pdf_url is not null;

create or replace function public.appgt_registrar_pdf_boleta_v2(
  p_boleta_id uuid,
  p_pdf_url text,
  p_pdf_version integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_boleta public."PLANILLA_BOLETAS_APPGT"%rowtype;
begin
  select * into v_boleta
  from public."PLANILLA_BOLETAS_APPGT"
  where id=p_boleta_id and empresa_id=public.appgt_empresa_actual_id()
  for update;
  if not found then raise exception 'Boleta no encontrada.'; end if;
  if not public.appgt_can_view_table('PLANILLA_BOLETAS_APPGT') then
    raise exception 'No tiene permiso para generar esta boleta.' using errcode='42501';
  end if;
  if p_pdf_version<>2 then
    raise exception 'Versión de boleta no soportada: %.',p_pdf_version;
  end if;
  if p_pdf_url !~ ('^storage://planilla-boletas/' || v_boleta.empresa_id::text || '/') then
    raise exception 'La ruta del PDF de boleta no es válida.';
  end if;
  update public."PLANILLA_BOLETAS_APPGT"
  set pdf_url=p_pdf_url,pdf_generado_at=clock_timestamp(),pdf_version=p_pdf_version,
      estado='GENERADA',updated_at=now()
  where id=v_boleta.id;
  select * into v_boleta from public."PLANILLA_BOLETAS_APPGT" where id=v_boleta.id;
  return to_jsonb(v_boleta);
end;
$$;

-- Contrato único para el renderer: identidad, importes separados, resumen y
-- días del periodo. F solo proviene de una falta explícita; nunca se infiere
-- por ausencia de una fila. El costo operativo de movilidad no se retorna.
create or replace function public.appgt_obtener_contexto_boleta_v2(p_boleta_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_boleta public."PLANILLA_BOLETAS_APPGT"%rowtype;
  v_periodo public."PLANILLA_PERIODOS_APPGT"%rowtype;
  v_liquidacion public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT"%rowtype;
  v_trabajador jsonb := '{}'::jsonb;
  v_liq jsonb := '{}'::jsonb;
  v_dias jsonb := '[]'::jsonb;
  v_resumen jsonb := '{}'::jsonb;
  v_cargo numeric := 0;
  v_movilidad numeric := 0;
  v_otros_afectos numeric := 0;
  v_otros_inafectos numeric := 0;
  v_clasificacion text := 'REMUNERATIVA_AFECTA';
begin
  select * into v_boleta
  from public."PLANILLA_BOLETAS_APPGT"
  where id=p_boleta_id and empresa_id=public.appgt_empresa_actual_id();
  if not found then raise exception 'Boleta no encontrada.'; end if;
  if not public.appgt_can_view_table('PLANILLA_BOLETAS_APPGT') then
    raise exception 'No tiene permiso para consultar esta boleta.' using errcode='42501';
  end if;

  select * into v_periodo
  from public."PLANILLA_PERIODOS_APPGT"
  where id=v_boleta.periodo_id and empresa_id=v_boleta.empresa_id;
  if not found then raise exception 'Periodo de la boleta no encontrado.'; end if;

  select * into v_liquidacion
  from public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT"
  where id=v_boleta.liquidacion_id and empresa_id=v_boleta.empresa_id;
  if not found then raise exception 'Liquidación de la boleta no encontrada.'; end if;

  select to_jsonb(p) into v_trabajador
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  where p.empresa_id=v_boleta.empresa_id
    and public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO'])
    )=public.appgt_normalizar_clave(v_boleta.dni)
    and coalesce(p.activo,true) and not coalesce(p.eliminado,false)
    and p.deleted_at is null
  order by p.updated_at desc nulls last
  limit 1;
  v_trabajador:=coalesce(v_trabajador,'{}'::jsonb);

  -- El snapshot cerrado tiene prioridad; las claves V2 explícitas provienen de
  -- la liquidación asociada para regenerar documentos anteriores al cambio.
  v_liq:=to_jsonb(v_liquidacion) || coalesce(
    nullif(v_boleta.liquidacion_snapshot,'{}'::jsonb),'{}'::jsonb
  );
  v_cargo:=public.appgt_jsonb_numeric(v_liq,array['bono_cargo_maestro'],0);
  v_movilidad:=public.appgt_jsonb_numeric(v_liq,array['bono_movilidad_maestro'],0);
  v_otros_afectos:=public.appgt_jsonb_numeric(v_liq,array['otros_ingresos_afectos'],0);
  v_otros_inafectos:=public.appgt_jsonb_numeric(v_liq,array['otros_ingresos_inafectos'],0);
  v_clasificacion:=coalesce(nullif(public.appgt_jsonb_text(
    v_trabajador,array['CLASIFICACION_BONO_MOVILIDAD']
  ),''),'REMUNERATIVA_AFECTA');
  v_liq:=v_liq || jsonb_build_object(
    'remuneracion_basica_jornales',v_liquidacion.remuneracion_basica_jornales,
    'licencias_pagadas_sin_compensacion',v_liquidacion.licencias_pagadas,
    'compensacion_pagada',v_liquidacion.compensacion_pagada,
    'sobretasa_descanso_semanal_100',v_liquidacion.sobretasa_descanso_semanal_100,
    'bono_cargo_maestro',v_liquidacion.bono_cargo_maestro,
    'bono_movilidad_maestro',v_liquidacion.bono_movilidad_maestro,
    'otros_ingresos_afectos_no_bonos',greatest(
      v_otros_afectos-v_cargo-case when v_clasificacion='REMUNERATIVA_AFECTA'
        then v_movilidad else 0 end,0
    ),
    'otros_ingresos_inafectos_no_movilidad',greatest(
      v_otros_inafectos-case when v_clasificacion='CONDICION_TRABAJO_INAFECTA'
        then v_movilidad else 0 end,0
    )
  );

  with dias as (
    select g.fecha::date as fecha,
      coalesce(d.horas_totales,0) as horas_totales,
      array_remove(array[
        case when coalesce(d.descanso_semanal,0)>0 then 'DS' end,
        case when exists (
          select 1 from public."GH_PERMISOS_LICENCIAS_APPGT" q
          where q.empresa_id=v_boleta.empresa_id
            and public.appgt_normalizar_clave(q.dni)=public.appgt_normalizar_clave(v_boleta.dni)
            and g.fecha::date between q.fecha_inicio and q.fecha_fin
            and upper(btrim(q.tipo_permiso))='COMPENSACION'
            and q.estado='APROBADO' and q."ESTADO_APROBACION"='APROBADO'
            and not q.eliminado and q.deleted_at is null
        ) then 'C' end,
        case when exists (
          select 1 from public."GH_PERMISOS_LICENCIAS_APPGT" q
          where q.empresa_id=v_boleta.empresa_id
            and public.appgt_normalizar_clave(q.dni)=public.appgt_normalizar_clave(v_boleta.dni)
            and g.fecha::date between q.fecha_inicio and q.fecha_fin
            and upper(btrim(q.tipo_permiso))<>'COMPENSACION'
            and q.estado='APROBADO' and q."ESTADO_APROBACION"='APROBADO'
            and not q.eliminado and q.deleted_at is null
        ) then 'P' end,
        case when exists (
          select 1 from public."GT-ASISTENCIA_PERSONAL" a
          where a.empresa_id=v_boleta.empresa_id
            and public.appgt_normalizar_clave(
              public.appgt_jsonb_text(to_jsonb(a),array['DNI','DOCUMENTO'])
            )=public.appgt_normalizar_clave(v_boleta.dni)
            and public.appgt_jsonb_date(to_jsonb(a),array['FECHA','FECHA_INGRESO'])=g.fecha::date
            and public.appgt_normalizar_clave(
              public.appgt_jsonb_text(to_jsonb(a),array['ESTADO_ASISTENCIA','ESTADO'])
            ) in ('FALTA','AUSENTE','INASISTENCIA')
            and not public.appgt_jsonb_bool(to_jsonb(a),array['eliminado'],false)
            and public.appgt_jsonb_text(to_jsonb(a),array['deleted_at']) is null
        ) then 'F' end,
        case when exists (
          select 1 from public."PLANILLA_FERIADOS_APPGT" f
          where f.fecha=g.fecha::date and f.activo and f.remunerado
            and (f.empresa_id is null or f.empresa_id=v_boleta.empresa_id)
        ) then 'FE' end
      ],null)::text[] as codigos
    from generate_series(v_periodo.fecha_inicio,v_periodo.fecha_fin,interval '1 day') g(fecha)
    left join lateral (
      select
        sum(coalesce(x.horas_trabajadas,0)+coalesce(x.horas_extras_25,0)+
          coalesce(x.horas_extras_35,0)) as horas_totales,
        sum(coalesce(x.descanso_semanal,0)) as descanso_semanal
      from public."PLANILLA_TRABAJADORES_ZUMAC" x
      where x.empresa_id=v_boleta.empresa_id
        and public.appgt_normalizar_clave(x.dni)=public.appgt_normalizar_clave(v_boleta.dni)
        and x.fecha=g.fecha::date and x.activo and not x.eliminado and x.deleted_at is null
    ) d on true
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'fecha',to_char(fecha,'YYYY-MM-DD'),
    'horas_totales',round(horas_totales,4),
    'codigos',to_jsonb(codigos)
  ) order by fecha),'[]'::jsonb)
  into v_dias
  from dias;

  select jsonb_build_object(
    'dias_trabajados',count(*) filter (
      where public.appgt_jsonb_numeric(e,array['horas_totales'],0)>0
    ),
    'descansos_semanales',count(*) filter (where coalesce(e->'codigos','[]'::jsonb) ? 'DS'),
    'dias_permisos',count(*) filter (
      where coalesce(e->'codigos','[]'::jsonb) ? 'P'
         or coalesce(e->'codigos','[]'::jsonb) ? 'C'
    ),
    'faltas',count(*) filter (where coalesce(e->'codigos','[]'::jsonb) ? 'F')
  ) into v_resumen
  from jsonb_array_elements(v_dias) e;

  return jsonb_build_object(
    'version',2,
    'periodo',jsonb_build_object(
      'fecha_inicio',v_periodo.fecha_inicio,
      'fecha_fin',v_periodo.fecha_fin,
      'es_prueba',upper(v_periodo.codigo) like 'PRUEBA%',
      'etiqueta',case when upper(v_periodo.codigo) like 'PRUEBA%'
        then 'Escenario de prueba' else '' end
    ),
    'trabajador',jsonb_build_object(
      'dni',v_boleta.dni,
      'nombre',v_boleta.nombres,
      'puesto',public.appgt_jsonb_text(v_trabajador,array['Puesto','PUESTO','CARGO']),
      'sistema_pension',v_liquidacion.sistema_pension,
      'tiene_asignacion_familiar',public.appgt_jsonb_bool(
        v_trabajador,array['Asignacion familiar','Asignación familiar','ASIGNACION_FAMILIAR'],false
      ),
      'fecha_ingreso',public.appgt_jsonb_date(
        v_trabajador,array['Fecha de Ingreso','FECHA_INGRESO','fecha_ingreso']
      ),
      'tipo_remuneracion',v_liquidacion.tipo_remuneracion
    ),
    'resumen',v_resumen,
    'liquidacion',v_liq,
    'dias',v_dias
  );
end;
$$;

revoke all on function public.appgt_obtener_contexto_boleta_v2(uuid) from public;
revoke all on function public.appgt_registrar_pdf_boleta_v2(uuid,text,integer) from public;
grant execute on function public.appgt_obtener_contexto_boleta_v2(uuid)
  to authenticated,service_role;
grant execute on function public.appgt_registrar_pdf_boleta_v2(uuid,text,integer)
  to authenticated,service_role;
grant execute on function public.appgt_dias_efectivos_descanso_semanal_v2(uuid,text,date,date),
  public.appgt_horas_dso_trabajadas_v2(uuid,text,date),
  public.appgt_tiene_sustituto_dso_v2(uuid,text,date,integer)
  to authenticated,service_role;

do $$
declare
  v_recalculo text:=pg_get_functiondef(
    'public.appgt_recalcular_planilla_zumac(text,date,date)'::regprocedure
  );
  v_liquidacion text:=pg_get_functiondef(
    'public.appgt_calcular_liquidacion_periodo_v2(uuid)'::regprocedure
  );
begin
  if position('DIA_DESCANSO_SEMANAL' in v_recalculo)=0
     or position('horas_sobretasa_descanso_semanal_100' in v_recalculo)=0
     or position('horas_origen_v2_capturadas' in v_recalculo)=0 then
    raise exception 'El recálculo V2 no contiene descanso configurable, sobretasa y horas de origen.';
  end if;
  if position('remuneracion_basica_jornales' in v_liquidacion)=0
     or position('Bono al cargo' in v_liquidacion)=0
     or position('compensacion_pagada' in v_liquidacion)=0 then
    raise exception 'La liquidación V2 no contiene todos los conceptos separados.';
  end if;
end;
$$;

notify pgrst,'reload schema';
commit;
