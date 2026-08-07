begin;

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Utilidades defensivas para convivir con columnas historicas cuyos nombres
-- usan espacios, guiones, mayusculas o tildes.
-- ---------------------------------------------------------------------------

create or replace function public.appgt_normalizar_clave(p_value text)
returns text
language sql
immutable
parallel safe
as $$
  select regexp_replace(
    translate(
      upper(coalesce(p_value, '')),
      'ÁÉÍÓÚÜÑáéíóúüñ',
      'AEIOUUNAEIOUUN'
    ),
    '[^A-Z0-9]+',
    '',
    'g'
  )
$$;

create or replace function public.appgt_jsonb_text(
  p_document jsonb,
  p_candidates text[]
)
returns text
language sql
immutable
parallel safe
as $$
  select nullif(btrim(e.value #>> '{}'), '')
  from unnest(coalesce(p_candidates, array[]::text[])) with ordinality c(name, priority)
  join lateral jsonb_each(coalesce(p_document, '{}'::jsonb)) e
    on public.appgt_normalizar_clave(e.key) = public.appgt_normalizar_clave(c.name)
  where e.value is not null
    and jsonb_typeof(e.value) <> 'null'
  order by c.priority
  limit 1
$$;

create or replace function public.appgt_jsonb_numeric(
  p_document jsonb,
  p_candidates text[],
  p_default numeric default 0
)
returns numeric
language plpgsql
immutable
parallel safe
as $$
declare
  v_value text;
begin
  v_value := public.appgt_jsonb_text(p_document, p_candidates);
  if v_value is null then
    return p_default;
  end if;
  v_value := replace(regexp_replace(v_value, '[^0-9,.-]+', '', 'g'), ',', '.');
  return coalesce(nullif(v_value, '')::numeric, p_default);
exception when others then
  return p_default;
end
$$;

create or replace function public.appgt_jsonb_date(
  p_document jsonb,
  p_candidates text[]
)
returns date
language plpgsql
immutable
parallel safe
as $$
declare
  v_value text;
begin
  v_value := public.appgt_jsonb_text(p_document, p_candidates);
  if v_value is null then
    return null;
  end if;
  if v_value ~ '^\d{4}-\d{2}-\d{2}' then
    return substring(v_value from 1 for 10)::date;
  end if;
  if v_value ~ '^\d{2}/\d{2}/\d{4}$' then
    return to_date(v_value, 'DD/MM/YYYY');
  end if;
  return v_value::date;
exception when others then
  return null;
end
$$;

create or replace function public.appgt_jsonb_time(
  p_document jsonb,
  p_candidates text[]
)
returns time
language plpgsql
immutable
parallel safe
as $$
declare
  v_value text;
begin
  v_value := public.appgt_jsonb_text(p_document, p_candidates);
  if v_value is null then
    return null;
  end if;
  return v_value::time;
exception when others then
  return null;
end
$$;

create or replace function public.appgt_jsonb_bool(
  p_document jsonb,
  p_candidates text[],
  p_default boolean default false
)
returns boolean
language plpgsql
immutable
parallel safe
as $$
declare
  v_value text;
  v_numeric numeric;
begin
  v_value := public.appgt_jsonb_text(p_document, p_candidates);
  if v_value is null then
    return p_default;
  end if;
  if public.appgt_normalizar_clave(v_value) in
      ('SI', 'S', 'YES', 'TRUE', 'ACTIVO', 'APLICA', 'CONASIGNACION') then
    return true;
  end if;
  if public.appgt_normalizar_clave(v_value) in
      ('NO', 'N', 'FALSE', 'INACTIVO', 'NOAPLICA', 'SINASIGNACION') then
    return false;
  end if;
  v_numeric := replace(v_value, ',', '.')::numeric;
  return v_numeric > 0;
exception when others then
  return p_default;
end
$$;

create or replace function public.appgt_horas_nocturnas(
  p_hora_inicio time,
  p_hora_fin time
)
returns numeric
language plpgsql
immutable
parallel safe
as $$
declare
  v_inicio numeric;
  v_fin numeric;
  v_minutos numeric := 0;
begin
  if p_hora_inicio is null or p_hora_fin is null or p_hora_inicio = p_hora_fin then
    return 0;
  end if;

  v_inicio := extract(hour from p_hora_inicio) * 60
    + extract(minute from p_hora_inicio)
    + extract(second from p_hora_inicio) / 60;
  v_fin := extract(hour from p_hora_fin) * 60
    + extract(minute from p_hora_fin)
    + extract(second from p_hora_fin) / 60;

  if v_fin < v_inicio then
    v_fin := v_fin + 1440;
  end if;

  -- Ventanas nocturnas: 00:00-06:00 y 22:00-06:00 del dia siguiente.
  v_minutos := greatest(least(v_fin, 360) - greatest(v_inicio, 0), 0)
    + greatest(least(v_fin, 1800) - greatest(v_inicio, 1320), 0);
  return round(v_minutos / 60.0, 4);
end
$$;

-- ---------------------------------------------------------------------------
-- Matriz canonica solicitada. La matriz APPGT anterior queda reemplazada.
-- ---------------------------------------------------------------------------

delete from public."MATRIZ_CAMPOS_FORMATO_APPGT"
where "tabla_destino" in ('MATRIZ_BENEFICIOS_SOCIALES_APPGT', 'MATRIZ_BENEFICIOS_SOCIALES');

delete from public."MATRIZ_FORMATO_TABLAS_APPGT"
where "tabla_destino" in ('MATRIZ_BENEFICIOS_SOCIALES_APPGT', 'MATRIZ_BENEFICIOS_SOCIALES');

delete from public."PERMISOS_DE_USUARIOS_APPGT"
where "tabla_destino" in ('MATRIZ_BENEFICIOS_SOCIALES_APPGT', 'MATRIZ_BENEFICIOS_SOCIALES');

delete from public."MATRIZ_FORMATOS_APPGT"
where "tabla_destino" in ('MATRIZ_BENEFICIOS_SOCIALES_APPGT', 'MATRIZ_BENEFICIOS_SOCIALES');

drop table if exists public."MATRIZ_BENEFICIOS_SOCIALES_APPGT" cascade;
drop table if exists public."MATRIZ_BENEFICIOS_SOCIALES" cascade;

create table public."MATRIZ_BENEFICIOS_SOCIALES" (
  id_local uuid primary key default gen_random_uuid(),
  "régimen" text not null unique,
  "RMV" numeric(14,4) not null check ("RMV" > 0),
  "Asignación familiar" numeric(10,6) not null check ("Asignación familiar" between 0 and 1),
  "CTS" numeric(10,6) not null check ("CTS" between 0 and 1),
  "gratificación" numeric(10,6) not null check ("gratificación" between 0 and 1),
  "bono extraordinario de gratificación" numeric(10,6) not null
    check ("bono extraordinario de gratificación" between 0 and 1),
  "bono beta" numeric(10,6) not null check ("bono beta" between 0 and 1),
  essalud numeric(10,6) not null check (essalud between 0 and 1),
  onp numeric(10,6) not null check (onp between 0 and 1),
  afp numeric(10,6) not null check (afp between 0 and 1),
  afp_seguro numeric(10,6) not null check (afp_seguro between 0 and 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  estado_sync text not null default 'sincronizado',
  activo boolean not null default true,
  eliminado boolean not null default false
);

insert into public."MATRIZ_BENEFICIOS_SOCIALES" (
  "régimen", "RMV", "Asignación familiar", "CTS", "gratificación",
  "bono extraordinario de gratificación", "bono beta", essalud, onp, afp, afp_seguro
) values (
  'Agrario 31110', 1130, 0.1, 0.0972, 0.1666, 0.06, 0.3, 0.06, 0.13, 0.1, 0.0137
);

comment on table public."MATRIZ_BENEFICIOS_SOCIALES" is
  'Fuente unica versionable para porcentajes y RMV del calculo de planilla Zumac.';

-- ---------------------------------------------------------------------------
-- Campos adicionales de personal y datos de tareo requeridos por el calculo.
-- ---------------------------------------------------------------------------

alter table public."GH-REGISTRO_PERSONAL_PLANILLA"
  add column if not exists "Apellido_paterno" text,
  add column if not exists "Apellido_materno" text,
  add column if not exists "Nombres" text,
  add column if not exists "Periodo de pago" text,
  add column if not exists "%comisión" numeric(10,6);

alter table public."GT-TAREO_PERSONAL"
  add column if not exists "VARIEDAD" text,
  add column if not exists "HORA_INICIO" time,
  add column if not exists "HORA_FIN" time;

-- ---------------------------------------------------------------------------
-- Tabla diaria y distribuida por labor/centro de costo.
-- Los conceptos de licencias y bonos pendientes quedan editables; los costos
-- y totales son derivados por trigger y nunca dependen del cliente Flutter.
-- ---------------------------------------------------------------------------

create table if not exists public."PLANILLA_TRABAJADORES_ZUMAC" (
  id_local uuid primary key default gen_random_uuid(),
  trabajador_id_local text,
  tareo_id_local text,
  origen_clave text not null,
  regimen_laboral text not null,
  fecha date not null,
  dni text not null,
  apellido_paterno text,
  apellido_materno text,
  nombres text,
  puesto text,
  periodo_pago text,
  labor text,
  centro_costo text,
  variedad text,
  sistema_pension text,
  sueldo_mensual numeric(18,6) not null default 0,
  rmv numeric(18,6) not null default 0,
  tiene_asignacion_familiar boolean not null default false,
  tasa_asignacion_familiar numeric(10,6) not null default 0,
  tasa_cts numeric(10,6) not null default 0,
  tasa_gratificacion numeric(10,6) not null default 0,
  tasa_bono_gratificacion numeric(10,6) not null default 0,
  tasa_bono_beta numeric(10,6) not null default 0,
  tasa_essalud numeric(10,6) not null default 0,
  tasa_onp numeric(10,6) not null default 0,
  tasa_afp numeric(10,6) not null default 0,
  tasa_afp_seguro numeric(10,6) not null default 0,
  tasa_afp_comision numeric(10,6) not null default 0,
  horas_trabajadas numeric(12,4) not null default 0,
  descanso_semanal numeric(12,4) not null default 0,
  horas_extras_25 numeric(12,4) not null default 0,
  horas_extras_35 numeric(12,4) not null default 0,
  horas_nocturnas numeric(12,4) not null default 0,
  descanso_medico numeric(12,4) not null default 0,
  teletrabajo numeric(12,4) not null default 0,
  licencia_maternidad numeric(12,4) not null default 0,
  licencia_paternidad numeric(12,4) not null default 0,
  licencia_fallecimiento numeric(12,4) not null default 0,
  comision numeric(12,4) not null default 0,
  costo_hora_sueldo numeric(18,6) not null default 0,
  costo_hora_rmv numeric(18,6) not null default 0,
  basico_costo numeric(18,6) not null default 0,
  asignacion_familiar_costo numeric(18,6) not null default 0,
  gratificacion_costo numeric(18,6) not null default 0,
  bono_gratificacion_costo numeric(18,6) not null default 0,
  cts_costo numeric(18,6) not null default 0,
  bono_beta_costo numeric(18,6) not null default 0,
  descanso_semanal_costo numeric(18,6) not null default 0,
  horas_extras_25_costo numeric(18,6) not null default 0,
  horas_extras_35_costo numeric(18,6) not null default 0,
  horas_nocturnas_costo numeric(18,6) not null default 0,
  descanso_medico_costo numeric(18,6) not null default 0,
  teletrabajo_costo numeric(18,6) not null default 0,
  licencia_maternidad_costo numeric(18,6) not null default 0,
  licencia_paternidad_costo numeric(18,6) not null default 0,
  licencia_fallecimiento_costo numeric(18,6) not null default 0,
  comision_costo numeric(18,6) not null default 0,
  bono_cargo_costo numeric(18,6),
  bono_labor_costo numeric(18,6),
  bono_movilidad_costo numeric(18,6),
  ingreso_bruto numeric(18,6) not null default 0,
  afecto numeric(18,6) not null default 0,
  inafecto numeric(18,6) not null default 0,
  essalud_costo numeric(18,6) not null default 0,
  costo_empresa numeric(18,6) not null default 0,
  onp_costo numeric(18,6) not null default 0,
  afp_costo numeric(18,6) not null default 0,
  afp_seguro_costo numeric(18,6) not null default 0,
  afp_comision_costo numeric(18,6) not null default 0,
  descuento numeric(18,6) not null default 0,
  total_neto numeric(18,6) not null default 0,
  auto_generado boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  estado_sync text not null default 'sincronizado',
  estado_registro text not null default 'COMPLETO',
  activo boolean not null default true,
  eliminado boolean not null default false,
  constraint planilla_zumac_dni_fecha_origen_uq unique (dni, fecha, origen_clave),
  constraint planilla_zumac_horas_no_negativas check (
    horas_trabajadas >= 0 and descanso_semanal >= 0
    and horas_extras_25 >= 0 and horas_extras_35 >= 0
    and horas_nocturnas >= 0 and descanso_medico >= 0
    and teletrabajo >= 0 and licencia_maternidad >= 0
    and licencia_paternidad >= 0 and licencia_fallecimiento >= 0
    and comision >= 0
  )
);

create index if not exists idx_planilla_zumac_fecha_dni
  on public."PLANILLA_TRABAJADORES_ZUMAC" (fecha, dni);
create index if not exists idx_planilla_zumac_centro_labor
  on public."PLANILLA_TRABAJADORES_ZUMAC" (centro_costo, labor, fecha);

comment on table public."PLANILLA_TRABAJADORES_ZUMAC" is
  'Planilla diaria por trabajador y distribucion de tareo. Importes en soles y horas en decimal.';
comment on column public."PLANILLA_TRABAJADORES_ZUMAC".horas_extras_25_costo is
  'Incluye el recargo legal de 25%: horas x costo_hora_sueldo x 1.25.';
comment on column public."PLANILLA_TRABAJADORES_ZUMAC".horas_extras_35_costo is
  'Incluye el recargo legal de 35%: horas x costo_hora_sueldo x 1.35.';
comment on column public."PLANILLA_TRABAJADORES_ZUMAC".bono_beta_costo is
  'Se calcula sobre RMV por la regla especial indicada para el regimen agrario.';

create or replace function public.appgt_calcular_costos_planilla_zumac()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_pension text;
begin
  new.costo_hora_sueldo := round(coalesce(new.sueldo_mensual, 0) / 30.0 / 8.0, 6);
  new.costo_hora_rmv := round(coalesce(new.rmv, 0) / 30.0 / 8.0, 6);

  new.basico_costo := round(coalesce(new.horas_trabajadas, 0) * new.costo_hora_sueldo, 6);
  new.asignacion_familiar_costo := case when coalesce(new.tiene_asignacion_familiar, false)
    then round(coalesce(new.horas_trabajadas, 0) * new.costo_hora_rmv
      * coalesce(new.tasa_asignacion_familiar, 0), 6)
    else 0 end;
  new.gratificacion_costo := round(new.basico_costo * coalesce(new.tasa_gratificacion, 0), 6);
  new.bono_gratificacion_costo := round(new.gratificacion_costo
    * coalesce(new.tasa_bono_gratificacion, 0), 6);
  new.cts_costo := round(new.basico_costo * coalesce(new.tasa_cts, 0), 6);
  new.bono_beta_costo := round(coalesce(new.horas_trabajadas, 0) * new.costo_hora_rmv
    * coalesce(new.tasa_bono_beta, 0), 6);
  new.descanso_semanal_costo := round(coalesce(new.descanso_semanal, 0)
    * new.costo_hora_sueldo, 6);
  new.horas_extras_25_costo := round(coalesce(new.horas_extras_25, 0)
    * new.costo_hora_sueldo * 1.25, 6);
  new.horas_extras_35_costo := round(coalesce(new.horas_extras_35, 0)
    * new.costo_hora_sueldo * 1.35, 6);
  new.horas_nocturnas_costo := round(coalesce(new.horas_nocturnas, 0)
    * new.costo_hora_rmv, 6);
  new.descanso_medico_costo := round(coalesce(new.descanso_medico, 0)
    * new.costo_hora_sueldo, 6);
  new.teletrabajo_costo := round(coalesce(new.teletrabajo, 0)
    * new.costo_hora_sueldo, 6);
  new.licencia_maternidad_costo := round(coalesce(new.licencia_maternidad, 0)
    * new.costo_hora_sueldo, 6);
  new.licencia_paternidad_costo := round(coalesce(new.licencia_paternidad, 0)
    * new.costo_hora_sueldo, 6);
  new.licencia_fallecimiento_costo := round(coalesce(new.licencia_fallecimiento, 0)
    * new.costo_hora_sueldo, 6);
  new.comision_costo := round(coalesce(new.comision, 0) * new.costo_hora_sueldo, 6);

  new.ingreso_bruto := round(
    new.basico_costo + new.asignacion_familiar_costo
    + new.gratificacion_costo + new.bono_gratificacion_costo
    + new.cts_costo + new.bono_beta_costo + new.descanso_semanal_costo
    + new.horas_extras_25_costo + new.horas_extras_35_costo
    + new.horas_nocturnas_costo + new.descanso_medico_costo
    + new.teletrabajo_costo + new.licencia_maternidad_costo
    + new.licencia_paternidad_costo + new.licencia_fallecimiento_costo
    + new.comision_costo + coalesce(new.bono_cargo_costo, 0)
    + coalesce(new.bono_labor_costo, 0) + coalesce(new.bono_movilidad_costo, 0),
    6
  );
  new.afecto := round(new.basico_costo + new.asignacion_familiar_costo
    + new.horas_nocturnas_costo, 6);
  new.inafecto := round(new.ingreso_bruto - new.afecto, 6);
  new.essalud_costo := round(new.afecto * coalesce(new.tasa_essalud, 0), 6);
  new.costo_empresa := round(new.ingreso_bruto + new.essalud_costo, 6);

  v_pension := public.appgt_normalizar_clave(new.sistema_pension);
  if v_pension like '%ONP%' then
    new.onp_costo := round(new.afecto * coalesce(new.tasa_onp, 0), 6);
    new.afp_costo := 0;
    new.afp_seguro_costo := 0;
    new.afp_comision_costo := 0;
  elsif v_pension like '%AFP%' then
    new.onp_costo := 0;
    new.afp_costo := round(new.afecto * coalesce(new.tasa_afp, 0), 6);
    new.afp_seguro_costo := round(new.afecto * coalesce(new.tasa_afp_seguro, 0), 6);
    new.afp_comision_costo := round(new.afecto * coalesce(new.tasa_afp_comision, 0), 6);
  else
    -- Compatibilidad con la formula entregada mientras no exista selector ONP/AFP.
    new.onp_costo := round(new.afecto * coalesce(new.tasa_onp, 0), 6);
    new.afp_costo := round(new.afecto * coalesce(new.tasa_afp, 0), 6);
    new.afp_seguro_costo := round(new.afecto * coalesce(new.tasa_afp_seguro, 0), 6);
    new.afp_comision_costo := round(new.afecto * coalesce(new.tasa_afp_comision, 0), 6);
  end if;

  new.descuento := round(new.onp_costo + new.afp_costo
    + new.afp_seguro_costo + new.afp_comision_costo, 6);
  new.total_neto := round(new.ingreso_bruto - new.descuento, 6);
  new.updated_at := now();
  return new;
end
$$;

drop trigger if exists appgt_calcular_costos_planilla_zumac_trigger
  on public."PLANILLA_TRABAJADORES_ZUMAC";
create trigger appgt_calcular_costos_planilla_zumac_trigger
before insert or update on public."PLANILLA_TRABAJADORES_ZUMAC"
for each row execute function public.appgt_calcular_costos_planilla_zumac();

-- Pruebas de humo transaccionales: no dejan filas y abortan la migracion si
-- las reglas esenciales cambian accidentalmente.
do $$
declare
  v_test public."PLANILLA_TRABAJADORES_ZUMAC"%rowtype;
begin
  if abs(public.appgt_horas_nocturnas('22:00'::time, '04:00'::time) - 6) > 0.0001 then
    raise exception 'Prueba nocturna invalida: 22:00 a 04:00 debe producir 6 horas.';
  end if;

  insert into public."PLANILLA_TRABAJADORES_ZUMAC" (
    origen_clave, regimen_laboral, fecha, dni, sueldo_mensual, rmv,
    tiene_asignacion_familiar, tasa_asignacion_familiar, tasa_cts,
    tasa_gratificacion, tasa_bono_gratificacion, tasa_bono_beta,
    tasa_essalud, tasa_onp, tasa_afp, tasa_afp_seguro,
    horas_trabajadas, horas_extras_25, horas_extras_35, horas_nocturnas
  ) values (
    'PRUEBA_MIGRACION', 'Agrario 31110', date '1900-01-01',
    '__ZUMAC_TEST__', 2400, 1200, true, 0.1, 0.0972, 0.1666, 0.06,
    0.3, 0.06, 0.13, 0.1, 0.0137, 8, 2, 1, 6
  ) returning * into v_test;

  if abs(v_test.costo_hora_sueldo - 10) > 0.0001
      or abs(v_test.costo_hora_rmv - 5) > 0.0001
      or abs(v_test.basico_costo - 80) > 0.0001
      or abs(v_test.asignacion_familiar_costo - 4) > 0.0001
      or abs(v_test.bono_beta_costo - 12) > 0.0001
      or abs(v_test.horas_extras_25_costo - 25) > 0.0001
      or abs(v_test.horas_extras_35_costo - 13.5) > 0.0001
      or abs(v_test.horas_nocturnas_costo - 30) > 0.0001 then
    raise exception 'Prueba de costos de planilla no superada.';
  end if;

  delete from public."PLANILLA_TRABAJADORES_ZUMAC"
  where dni = '__ZUMAC_TEST__' and origen_clave = 'PRUEBA_MIGRACION';
end
$$;

-- Recalcula un DNI/rango. Cada fila de tareo conserva su labor y centro de
-- costo. La jornada ordinaria se limita a 8 h; las 2 siguientes van a 25% y
-- el exceso restante a 35%.
create or replace function public.appgt_recalcular_planilla_zumac(
  p_dni text,
  p_desde date,
  p_hasta date
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rows integer := 0;
begin
  if nullif(btrim(p_dni), '') is null or p_desde is null or p_hasta is null
      or p_hasta < p_desde then
    return 0;
  end if;

  with worker as (
    select s.data,
      public.appgt_jsonb_text(s.data, array['id_local', 'id']) as trabajador_id,
      public.appgt_jsonb_text(s.data, array['DNI', 'DOCUMENTO']) as dni,
      public.appgt_jsonb_date(s.data, array['Fecha inicio de Contrato', 'FECHA_INICIO_CONTRATO']) as contrato_inicio,
      public.appgt_jsonb_date(s.data, array['Fecha fin de Contrato', 'FECHA_FIN_CONTRATO']) as contrato_fin,
      coalesce(public.appgt_jsonb_text(s.data, array['Régimen laboral', 'REGIMEN_LABORAL', 'Régimen']), 'Agrario 31110') as regimen,
      public.appgt_jsonb_numeric(s.data, array['Sueldo', 'SUELDO_MENSUAL', 'REMUNERACION'], 0) as sueldo,
      public.appgt_jsonb_bool(s.data, array['Asignación familiar', 'ASIGNACION_FAMILIAR'], false) as tiene_asignacion,
      public.appgt_jsonb_numeric(s.data, array['%comisión', 'PORCENTAJE_COMISION', 'AFP_COMISION'], 0) as afp_comision,
      public.appgt_jsonb_text(s.data, array['Sistema pensionario', 'SISTEMA_PENSION', 'REGIMEN_PENSIONARIO', 'AFP/ONP']) as sistema_pension,
      public.appgt_jsonb_text(s.data, array['Apellido_paterno', 'APELLIDO_PATERNO']) as apellido_paterno,
      public.appgt_jsonb_text(s.data, array['Apellido_materno', 'APELLIDO_MATERNO']) as apellido_materno,
      public.appgt_jsonb_text(s.data, array['Nombres', 'NOMBRES']) as nombres,
      public.appgt_jsonb_text(s.data, array['Puesto', 'PUESTO', 'CARGO']) as puesto,
      public.appgt_jsonb_text(s.data, array['Periodo de pago', 'PERIODO_PAGO']) as periodo_pago
    from (
      select to_jsonb(p) as data
      from public."GH-REGISTRO_PERSONAL_PLANILLA" p
    ) s
    where public.appgt_normalizar_clave(
      public.appgt_jsonb_text(s.data, array['DNI', 'DOCUMENTO'])
    ) = public.appgt_normalizar_clave(p_dni)
      and public.appgt_normalizar_clave(
        public.appgt_jsonb_text(s.data, array['Status', 'ESTADO', 'ESTADO_PERSONAL'])
      ) = 'ACTIVO'
    limit 1
  ), bounded_worker as (
    select w.*,
      greatest(p_desde, w.contrato_inicio) as desde,
      least(p_hasta, w.contrato_fin, current_date) as hasta
    from worker w
    where w.contrato_inicio is not null
      and w.contrato_fin is not null
      and w.contrato_inicio <= p_hasta
      and w.contrato_fin >= p_desde
  ), dates as (
    select w.*, gs::date as fecha
    from bounded_worker w
    cross join lateral generate_series(w.desde, w.hasta, interval '1 day') gs
    where w.desde <= w.hasta
  ), source_rows as (
    select d.*,
      t.data as tareo,
      coalesce(
        public.appgt_jsonb_text(t.data, array['id_local', 'id']),
        t.row_locator,
        'SIN_TAREO'
      ) as source_id,
      greatest(public.appgt_jsonb_numeric(t.data, array['HORAS_TRABAJADAS'], 0), 0) as raw_hours,
      public.appgt_jsonb_time(t.data, array['HORA_INICIO', 'HORA INCIO']) as hora_inicio,
      public.appgt_jsonb_time(t.data, array['HORA_FIN']) as hora_fin,
      public.appgt_jsonb_text(t.data, array['LABOR']) as labor,
      public.appgt_jsonb_text(t.data, array['CENTRO_COSTO', 'CENTRO COSTO']) as centro_costo,
      public.appgt_jsonb_text(t.data, array['VARIEDAD']) as variedad
    from dates d
    left join lateral (
      select to_jsonb(gt) as data, gt.ctid::text as row_locator
      from public."GT-TAREO_PERSONAL" gt
      where public.appgt_normalizar_clave(
          public.appgt_jsonb_text(to_jsonb(gt), array['DNI', 'DOCUMENTO'])
        ) = public.appgt_normalizar_clave(d.dni)
        and public.appgt_jsonb_date(to_jsonb(gt), array['FECHA']) = d.fecha
        and not public.appgt_jsonb_bool(to_jsonb(gt), array['eliminado'], false)
        and public.appgt_jsonb_text(to_jsonb(gt), array['deleted_at']) is null
    ) t on true
  ), distributed as (
    select s.*,
      row_number() over (partition by s.fecha order by s.source_id) as source_order,
      coalesce(sum(s.raw_hours) over (
        partition by s.fecha order by s.source_id
        rows between unbounded preceding and 1 preceding
      ), 0) as prior_hours
    from source_rows s
  ), calculated as (
    select d.*,
      greatest(least(d.prior_hours + d.raw_hours, 8) - least(d.prior_hours, 8), 0) as regular_hours,
      greatest(least(d.prior_hours + d.raw_hours, 10) - greatest(d.prior_hours, 8), 0) as extra_25,
      greatest(d.prior_hours + d.raw_hours - greatest(d.prior_hours, 10), 0) as extra_35,
      least(public.appgt_horas_nocturnas(d.hora_inicio, d.hora_fin), d.raw_hours) as night_hours,
      case when extract(dow from d.fecha) = 0 and d.source_order = 1 then
        (
          select count(distinct public.appgt_jsonb_date(to_jsonb(a), array['FECHA']))::numeric
          from public."GT-TAREO_PERSONAL" a
          where public.appgt_normalizar_clave(
              public.appgt_jsonb_text(to_jsonb(a), array['DNI', 'DOCUMENTO'])
            ) = public.appgt_normalizar_clave(d.dni)
            and public.appgt_jsonb_date(to_jsonb(a), array['FECHA'])
              between d.fecha - 6 and d.fecha - 1
            and public.appgt_jsonb_numeric(to_jsonb(a), array['HORAS_TRABAJADAS'], 0) > 0
            and not public.appgt_jsonb_bool(to_jsonb(a), array['eliminado'], false)
            and public.appgt_jsonb_text(to_jsonb(a), array['deleted_at']) is null
        ) * 8.0 / 6.0
      else 0 end as weekly_rest
    from distributed d
  ), ready as (
    select c.*,
      b."RMV" as benefit_rmv,
      b."Asignación familiar" as benefit_asignacion,
      b."CTS" as benefit_cts,
      b."gratificación" as benefit_gratificacion,
      b."bono extraordinario de gratificación" as benefit_bono_gratificacion,
      b."bono beta" as benefit_bono_beta,
      b.essalud as benefit_essalud,
      b.onp as benefit_onp,
      b.afp as benefit_afp,
      b.afp_seguro as benefit_afp_seguro
    from calculated c
    join lateral (
      select mb.*
      from public."MATRIZ_BENEFICIOS_SOCIALES" mb
      where mb.activo and not mb.eliminado
      order by case when public.appgt_normalizar_clave(mb."régimen")
        = public.appgt_normalizar_clave(c.regimen) then 0 else 1 end,
        mb.created_at
      limit 1
    ) b on true
  )
  insert into public."PLANILLA_TRABAJADORES_ZUMAC" (
    trabajador_id_local, tareo_id_local, origen_clave, regimen_laboral,
    fecha, dni, apellido_paterno, apellido_materno, nombres, puesto,
    periodo_pago, labor, centro_costo, variedad, sistema_pension,
    sueldo_mensual, rmv, tiene_asignacion_familiar,
    tasa_asignacion_familiar, tasa_cts, tasa_gratificacion,
    tasa_bono_gratificacion, tasa_bono_beta, tasa_essalud, tasa_onp,
    tasa_afp, tasa_afp_seguro, tasa_afp_comision,
    horas_trabajadas, descanso_semanal, horas_extras_25,
    horas_extras_35, horas_nocturnas
  )
  select
    r.trabajador_id,
    case when r.source_id = 'SIN_TAREO' then null else r.source_id end,
    case when r.source_id = 'SIN_TAREO' then 'SIN_TAREO' else 'TAREO:' || r.source_id end,
    r.regimen, r.fecha, r.dni, r.apellido_paterno, r.apellido_materno,
    r.nombres, r.puesto, r.periodo_pago, r.labor, r.centro_costo, r.variedad,
    r.sistema_pension, r.sueldo, r.benefit_rmv, r.tiene_asignacion,
    r.benefit_asignacion, r.benefit_cts, r.benefit_gratificacion,
    r.benefit_bono_gratificacion, r.benefit_bono_beta, r.benefit_essalud,
    r.benefit_onp, r.benefit_afp, r.benefit_afp_seguro,
    case when r.afp_comision > 1 then r.afp_comision / 100.0 else r.afp_comision end,
    round(r.regular_hours, 4), round(r.weekly_rest, 4), round(r.extra_25, 4),
    round(r.extra_35, 4), round(r.night_hours, 4)
  from ready r
  on conflict (dni, fecha, origen_clave) do update set
    trabajador_id_local = excluded.trabajador_id_local,
    tareo_id_local = excluded.tareo_id_local,
    regimen_laboral = excluded.regimen_laboral,
    apellido_paterno = excluded.apellido_paterno,
    apellido_materno = excluded.apellido_materno,
    nombres = excluded.nombres,
    puesto = excluded.puesto,
    periodo_pago = excluded.periodo_pago,
    labor = excluded.labor,
    centro_costo = excluded.centro_costo,
    variedad = excluded.variedad,
    sistema_pension = excluded.sistema_pension,
    sueldo_mensual = excluded.sueldo_mensual,
    rmv = excluded.rmv,
    tiene_asignacion_familiar = excluded.tiene_asignacion_familiar,
    tasa_asignacion_familiar = excluded.tasa_asignacion_familiar,
    tasa_cts = excluded.tasa_cts,
    tasa_gratificacion = excluded.tasa_gratificacion,
    tasa_bono_gratificacion = excluded.tasa_bono_gratificacion,
    tasa_bono_beta = excluded.tasa_bono_beta,
    tasa_essalud = excluded.tasa_essalud,
    tasa_onp = excluded.tasa_onp,
    tasa_afp = excluded.tasa_afp,
    tasa_afp_seguro = excluded.tasa_afp_seguro,
    tasa_afp_comision = excluded.tasa_afp_comision,
    horas_trabajadas = excluded.horas_trabajadas,
    descanso_semanal = excluded.descanso_semanal,
    horas_extras_25 = excluded.horas_extras_25,
    horas_extras_35 = excluded.horas_extras_35,
    horas_nocturnas = excluded.horas_nocturnas,
    activo = true,
    eliminado = false,
    deleted_at = null,
    estado_sync = 'sincronizado';

  get diagnostics v_rows = row_count;

  -- Retira distribuciones que ya no tienen tareo y el marcador SIN_TAREO
  -- cuando el dia ya cuenta con al menos una distribucion real.
  delete from public."PLANILLA_TRABAJADORES_ZUMAC" p
  where public.appgt_normalizar_clave(p.dni) = public.appgt_normalizar_clave(p_dni)
    and p.fecha between p_desde and p_hasta
    and p.auto_generado
    and p.origen_clave like 'TAREO:%'
    and not exists (
      select 1
      from public."GT-TAREO_PERSONAL" gt
      where public.appgt_normalizar_clave(
          public.appgt_jsonb_text(to_jsonb(gt), array['DNI', 'DOCUMENTO'])
        ) = public.appgt_normalizar_clave(p.dni)
        and public.appgt_jsonb_date(to_jsonb(gt), array['FECHA']) = p.fecha
        and 'TAREO:' || coalesce(
          public.appgt_jsonb_text(to_jsonb(gt), array['id_local', 'id']),
          gt.ctid::text
        ) = p.origen_clave
        and not public.appgt_jsonb_bool(to_jsonb(gt), array['eliminado'], false)
        and public.appgt_jsonb_text(to_jsonb(gt), array['deleted_at']) is null
    );

  delete from public."PLANILLA_TRABAJADORES_ZUMAC" p
  where public.appgt_normalizar_clave(p.dni) = public.appgt_normalizar_clave(p_dni)
    and p.fecha between p_desde and p_hasta
    and p.auto_generado
    and p.origen_clave = 'SIN_TAREO'
    and exists (
      select 1
      from public."GT-TAREO_PERSONAL" gt
      where public.appgt_normalizar_clave(
          public.appgt_jsonb_text(to_jsonb(gt), array['DNI', 'DOCUMENTO'])
        ) = public.appgt_normalizar_clave(p.dni)
        and public.appgt_jsonb_date(to_jsonb(gt), array['FECHA']) = p.fecha
        and not public.appgt_jsonb_bool(to_jsonb(gt), array['eliminado'], false)
        and public.appgt_jsonb_text(to_jsonb(gt), array['deleted_at']) is null
    );

  return v_rows;
end
$$;

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
      public.appgt_jsonb_text(s.data, array['DNI', 'DOCUMENTO']) as dni,
      public.appgt_jsonb_date(s.data, array['Fecha inicio de Contrato', 'FECHA_INICIO_CONTRATO']) as inicio,
      public.appgt_jsonb_date(s.data, array['Fecha fin de Contrato', 'FECHA_FIN_CONTRATO']) as fin
    from (
      select to_jsonb(p) as data
      from public."GH-REGISTRO_PERSONAL_PLANILLA" p
    ) s
    where public.appgt_normalizar_clave(
        public.appgt_jsonb_text(s.data, array['Status', 'ESTADO', 'ESTADO_PERSONAL'])
      ) = 'ACTIVO'
      and public.appgt_jsonb_text(s.data, array['DNI', 'DOCUMENTO']) is not null
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

-- ---------------------------------------------------------------------------
-- Ciclo contractual: validacion de reactivacion, backfill de renovaciones y
-- marcado explicito de contratos vencidos al abrir la tabla desde Flutter.
-- ---------------------------------------------------------------------------

create or replace function public.appgt_validar_reactivacion_personal_zumac()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old_status text;
  v_new_status text;
  v_inicio date;
  v_fin date;
begin
  v_old_status := public.appgt_normalizar_clave(
    public.appgt_jsonb_text(to_jsonb(old), array['Status', 'ESTADO', 'ESTADO_PERSONAL'])
  );
  v_new_status := public.appgt_normalizar_clave(
    public.appgt_jsonb_text(to_jsonb(new), array['Status', 'ESTADO', 'ESTADO_PERSONAL'])
  );

  if v_new_status = 'ACTIVO' and v_old_status in ('CESE', 'PENDIENTERENOVACION') then
    v_inicio := public.appgt_jsonb_date(to_jsonb(new), array['Fecha inicio de Contrato', 'FECHA_INICIO_CONTRATO']);
    v_fin := public.appgt_jsonb_date(to_jsonb(new), array['Fecha fin de Contrato', 'FECHA_FIN_CONTRATO']);
    if v_inicio is null or v_fin is null then
      raise exception 'Para activar al trabajador complete Fecha inicio de Contrato y Fecha fin de Contrato.';
    end if;
    if v_fin < v_inicio then
      raise exception 'Fecha fin de Contrato no puede ser anterior a Fecha inicio de Contrato.';
    end if;
  end if;

  if v_new_status = 'ACTIVO' and v_old_status = 'CESE' then
    if public.appgt_jsonb_date(to_jsonb(new), array['Fecha de Ingreso', 'FECHA_INGRESO']) is null
      or public.appgt_jsonb_numeric(to_jsonb(new), array['Sueldo', 'SUELDO_MENSUAL', 'REMUNERACION'], 0) <= 0
      or public.appgt_jsonb_text(to_jsonb(new), array['Asignación familiar', 'ASIGNACION_FAMILIAR']) is null then
      raise exception 'Para reactivar un trabajador cesado complete Fecha de Ingreso, sueldo y asignacion familiar.';
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists appgt_validar_reactivacion_personal_zumac_trigger
  on public."GH-REGISTRO_PERSONAL_PLANILLA";
create trigger appgt_validar_reactivacion_personal_zumac_trigger
before update on public."GH-REGISTRO_PERSONAL_PLANILLA"
for each row execute function public.appgt_validar_reactivacion_personal_zumac();

create or replace function public.appgt_personal_refrescar_planilla_zumac()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_new jsonb := to_jsonb(new);
  v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  v_dni text;
  v_status text;
  v_inicio date;
  v_fin date;
  v_old_inicio date;
  v_old_fin date;
  v_old_status text;
  v_desde date;
begin
  v_dni := public.appgt_jsonb_text(v_new, array['DNI', 'DOCUMENTO']);
  v_status := public.appgt_normalizar_clave(
    public.appgt_jsonb_text(v_new, array['Status', 'ESTADO', 'ESTADO_PERSONAL'])
  );
  v_inicio := public.appgt_jsonb_date(v_new, array['Fecha inicio de Contrato', 'FECHA_INICIO_CONTRATO']);
  v_fin := public.appgt_jsonb_date(v_new, array['Fecha fin de Contrato', 'FECHA_FIN_CONTRATO']);

  if v_status <> 'ACTIVO' or v_dni is null or v_inicio is null or v_fin is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    v_desde := v_inicio;
  else
    v_old_inicio := public.appgt_jsonb_date(v_old, array['Fecha inicio de Contrato', 'FECHA_INICIO_CONTRATO']);
    v_old_fin := public.appgt_jsonb_date(v_old, array['Fecha fin de Contrato', 'FECHA_FIN_CONTRATO']);
    v_old_status := public.appgt_normalizar_clave(
      public.appgt_jsonb_text(v_old, array['Status', 'ESTADO', 'ESTADO_PERSONAL'])
    );
    if v_old_status <> 'ACTIVO' or v_inicio is distinct from v_old_inicio
        or v_fin is distinct from v_old_fin then
      v_desde := v_inicio;
    else
      v_desde := current_date;
    end if;
  end if;

  if v_desde <= least(v_fin, current_date) then
    perform public.appgt_recalcular_planilla_zumac(
      v_dni, v_desde, least(v_fin, current_date)
    );
  end if;
  return new;
end
$$;

drop trigger if exists appgt_personal_refrescar_planilla_zumac_trigger
  on public."GH-REGISTRO_PERSONAL_PLANILLA";
create trigger appgt_personal_refrescar_planilla_zumac_trigger
after insert or update on public."GH-REGISTRO_PERSONAL_PLANILLA"
for each row execute function public.appgt_personal_refrescar_planilla_zumac();

create or replace function public.appgt_tareo_refrescar_planilla_zumac()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_data jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_old_data jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else null end;
  v_dni text;
  v_fecha date;
  v_domingo date;
begin
  v_dni := public.appgt_jsonb_text(v_data, array['DNI', 'DOCUMENTO']);
  v_fecha := public.appgt_jsonb_date(v_data, array['FECHA']);
  if v_dni is not null and v_fecha is not null then
    v_domingo := v_fecha + ((7 - extract(dow from v_fecha)::integer) % 7);
    perform public.appgt_recalcular_planilla_zumac(
      v_dni, v_fecha, least(v_domingo, current_date)
    );
  end if;

  if tg_op = 'UPDATE' and (
    public.appgt_jsonb_text(v_old_data, array['DNI', 'DOCUMENTO']) is distinct from v_dni
    or public.appgt_jsonb_date(v_old_data, array['FECHA']) is distinct from v_fecha
  ) then
    perform public.appgt_recalcular_planilla_zumac(
      public.appgt_jsonb_text(v_old_data, array['DNI', 'DOCUMENTO']),
      public.appgt_jsonb_date(v_old_data, array['FECHA']),
      least(
        public.appgt_jsonb_date(v_old_data, array['FECHA'])
          + ((7 - extract(dow from public.appgt_jsonb_date(v_old_data, array['FECHA']))::integer) % 7),
        current_date
      )
    );
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end
$$;

drop trigger if exists appgt_tareo_refrescar_planilla_zumac_trigger
  on public."GT-TAREO_PERSONAL";
create trigger appgt_tareo_refrescar_planilla_zumac_trigger
after insert or update or delete on public."GT-TAREO_PERSONAL"
for each row execute function public.appgt_tareo_refrescar_planilla_zumac();

create or replace function public.appgt_marcar_contratos_vencidos_zumac()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_status_column text;
  v_count integer := 0;
begin
  select c.column_name into v_status_column
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'GH-REGISTRO_PERSONAL_PLANILLA'
    and public.appgt_normalizar_clave(c.column_name) in ('STATUS', 'ESTADO', 'ESTADOPERSONAL')
  order by case public.appgt_normalizar_clave(c.column_name)
    when 'STATUS' then 0 when 'ESTADO' then 1 else 2 end
  limit 1;

  if v_status_column is null then
    raise exception 'GH-REGISTRO_PERSONAL_PLANILLA no tiene una columna Status compatible.';
  end if;

  execute format(
    'update public.%I p set %I = $1
     where public.appgt_normalizar_clave(
       public.appgt_jsonb_text(to_jsonb(p), array[''Status'', ''ESTADO'', ''ESTADO_PERSONAL''])
     ) = ''ACTIVO''
       and public.appgt_jsonb_date(
         to_jsonb(p), array[''Fecha fin de Contrato'', ''FECHA_FIN_CONTRATO'']
       ) < current_date',
    'GH-REGISTRO_PERSONAL_PLANILLA', v_status_column
  ) using 'pendiente renovación';

  select count(*)::integer into v_count
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  where public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p), array['Status', 'ESTADO', 'ESTADO_PERSONAL'])
    ) = 'PENDIENTERENOVACION'
    and not public.appgt_jsonb_bool(to_jsonb(p), array['eliminado'], false);

  return v_count;
end
$$;

-- Automatizacion diaria en Supabase. El bloque es tolerante a proyectos donde
-- pg_cron no este habilitado: los triggers y los RPC de Flutter siguen siendo
-- suficientes para mantener la tabla al dia.
do $$
begin
  begin
    if not exists (select 1 from pg_extension where extname = 'pg_cron') then
      execute 'create extension if not exists pg_cron';
    end if;
    if to_regnamespace('cron') is not null then
      execute 'select cron.unschedule(jobid) from cron.job where jobname = $1'
        using 'zumac_planilla_diaria';
      execute 'select cron.unschedule(jobid) from cron.job where jobname = $1'
        using 'zumac_contratos_vencidos';
      -- Supabase opera en UTC; 05:05/05:10 UTC equivalen a 00:05/00:10 en Peru.
      execute 'select cron.schedule($1, $2, $3)'
        using 'zumac_planilla_diaria', '5 5 * * *',
          'select public.appgt_refrescar_planilla_zumac(current_date, current_date)';
      execute 'select cron.schedule($1, $2, $3)'
        using 'zumac_contratos_vencidos', '10 5 * * *',
          'select public.appgt_marcar_contratos_vencidos_zumac()';
    end if;
  exception when others then
    raise notice 'pg_cron no disponible; se usaran triggers y RPC Flutter: %', sqlerrm;
  end;
end
$$;

-- Generacion inicial del dia actual; las renovaciones disparan su propio backfill.
select public.appgt_refrescar_planilla_zumac(current_date, current_date);

-- ---------------------------------------------------------------------------
-- Registro dinamico en Zumac y permisos coherentes con Gestion Humana.
-- ---------------------------------------------------------------------------

insert into public."MATRIZ_FORMATOS_APPGT" (
  "id", "modulo_id", "nombre", "tabla_destino", "ruta_flutter", "orden",
  "activo", "updated_at", "created_at", "deleted_at", "estado_sync", "eliminado"
) values
  ('matriz_beneficios_sociales', 'gestion_humana', 'Matriz de Beneficios Sociales',
   'MATRIZ_BENEFICIOS_SOCIALES', null, 80, true, now(), now(), null, 'sincronizado', false),
  ('planilla_trabajadores_zumac', 'gestion_humana', 'Planilla de Trabajadores Zumac',
   'PLANILLA_TRABAJADORES_ZUMAC', null, 81, true, now(), now(), null, 'sincronizado', false)
on conflict ("id") do update set
  "modulo_id" = excluded."modulo_id",
  "nombre" = excluded."nombre",
  "tabla_destino" = excluded."tabla_destino",
  "activo" = true,
  "updated_at" = now(),
  "deleted_at" = null,
  "eliminado" = false;

insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  "id", "tabla_destino", "campo", "etiqueta", "tipo", "tipo_ui",
  "requerido", "visible", "visible_tabla", "editable", "orden", "activo",
  "created_at", "updated_at", "estado_sync", "eliminado"
) values
  ('gh_planilla_apellido_paterno', 'GH-REGISTRO_PERSONAL_PLANILLA', 'Apellido_paterno', 'Apellido paterno', 'text', 'text', false, true, true, true, 901, true, now(), now(), 'sincronizado', false),
  ('gh_planilla_apellido_materno', 'GH-REGISTRO_PERSONAL_PLANILLA', 'Apellido_materno', 'Apellido materno', 'text', 'text', false, true, true, true, 902, true, now(), now(), 'sincronizado', false),
  ('gh_planilla_nombres', 'GH-REGISTRO_PERSONAL_PLANILLA', 'Nombres', 'Nombres', 'text', 'text', false, true, true, true, 903, true, now(), now(), 'sincronizado', false),
  ('gh_planilla_periodo_pago', 'GH-REGISTRO_PERSONAL_PLANILLA', 'Periodo de pago', 'Periodo de pago', 'text', 'text', false, true, true, true, 904, true, now(), now(), 'sincronizado', false),
  ('gh_planilla_afp_comision', 'GH-REGISTRO_PERSONAL_PLANILLA', '%comisión', '% comisión AFP', 'numeric', 'number', false, true, true, true, 905, true, now(), now(), 'sincronizado', false),
  ('benef_regimen', 'MATRIZ_BENEFICIOS_SOCIALES', 'régimen', 'Régimen', 'text', 'text', true, true, true, true, 1, true, now(), now(), 'sincronizado', false),
  ('benef_rmv', 'MATRIZ_BENEFICIOS_SOCIALES', 'RMV', 'RMV', 'numeric', 'number', true, true, true, true, 2, true, now(), now(), 'sincronizado', false),
  ('benef_asignacion', 'MATRIZ_BENEFICIOS_SOCIALES', 'Asignación familiar', 'Asignación familiar', 'numeric', 'number', true, true, true, true, 3, true, now(), now(), 'sincronizado', false),
  ('benef_cts', 'MATRIZ_BENEFICIOS_SOCIALES', 'CTS', 'CTS', 'numeric', 'number', true, true, true, true, 4, true, now(), now(), 'sincronizado', false),
  ('benef_gratificacion', 'MATRIZ_BENEFICIOS_SOCIALES', 'gratificación', 'Gratificación', 'numeric', 'number', true, true, true, true, 5, true, now(), now(), 'sincronizado', false),
  ('benef_bono_gratificacion', 'MATRIZ_BENEFICIOS_SOCIALES', 'bono extraordinario de gratificación', 'Bono extraordinario de gratificación', 'numeric', 'number', true, true, true, true, 6, true, now(), now(), 'sincronizado', false),
  ('benef_bono_beta', 'MATRIZ_BENEFICIOS_SOCIALES', 'bono beta', 'Bono Beta', 'numeric', 'number', true, true, true, true, 7, true, now(), now(), 'sincronizado', false),
  ('benef_essalud', 'MATRIZ_BENEFICIOS_SOCIALES', 'essalud', 'EsSalud', 'numeric', 'number', true, true, true, true, 8, true, now(), now(), 'sincronizado', false),
  ('benef_onp', 'MATRIZ_BENEFICIOS_SOCIALES', 'onp', 'ONP', 'numeric', 'number', true, true, true, true, 9, true, now(), now(), 'sincronizado', false),
  ('benef_afp', 'MATRIZ_BENEFICIOS_SOCIALES', 'afp', 'AFP', 'numeric', 'number', true, true, true, true, 10, true, now(), now(), 'sincronizado', false),
  ('benef_afp_seguro', 'MATRIZ_BENEFICIOS_SOCIALES', 'afp_seguro', 'AFP seguro', 'numeric', 'number', true, true, true, true, 11, true, now(), now(), 'sincronizado', false)
on conflict ("tabla_destino", "campo") do update set
  "etiqueta" = excluded."etiqueta", "tipo" = excluded."tipo",
  "tipo_ui" = excluded."tipo_ui", "requerido" = excluded."requerido",
  "visible" = excluded."visible", "visible_tabla" = excluded."visible_tabla",
  "editable" = excluded."editable", "orden" = excluded."orden",
  "activo" = true, "updated_at" = now(), "eliminado" = false;

-- Campos de planilla: entradas manuales editables y resultados de solo lectura.
with fields(campo, etiqueta, tipo, tipo_ui, editable, orden) as (
  values
    ('regimen_laboral', 'Régimen laboral', 'text', 'text', false, 1),
    ('fecha', 'Fecha', 'date', 'date', false, 2),
    ('dni', 'DNI', 'text', 'text', false, 3),
    ('apellido_paterno', 'Apellido paterno', 'text', 'text', false, 4),
    ('apellido_materno', 'Apellido materno', 'text', 'text', false, 5),
    ('nombres', 'Nombres', 'text', 'text', false, 6),
    ('puesto', 'Puesto', 'text', 'text', false, 7),
    ('periodo_pago', 'Periodo de pago', 'text', 'text', false, 8),
    ('labor', 'Labor', 'text', 'text', false, 9),
    ('centro_costo', 'Centro de costo', 'text', 'text', false, 10),
    ('variedad', 'Variedad', 'text', 'text', false, 11),
    ('horas_trabajadas', 'Horas trabajadas', 'numeric', 'number', false, 12),
    ('descanso_semanal', 'Descanso semanal', 'numeric', 'number', false, 13),
    ('horas_extras_25', 'Horas extras (25%)', 'numeric', 'number', false, 14),
    ('horas_extras_35', 'Horas extras (35%)', 'numeric', 'number', false, 15),
    ('horas_nocturnas', 'Horas nocturnas', 'numeric', 'number', false, 16),
    ('descanso_medico', 'Descanso médico', 'numeric', 'number', true, 17),
    ('teletrabajo', 'Teletrabajo', 'numeric', 'number', true, 18),
    ('licencia_maternidad', 'Licencia de maternidad', 'numeric', 'number', true, 19),
    ('licencia_paternidad', 'Licencia de paternidad', 'numeric', 'number', true, 20),
    ('licencia_fallecimiento', 'Licencia de fallecimiento', 'numeric', 'number', true, 21),
    ('comision', 'Comisión', 'numeric', 'number', true, 22),
    ('costo_hora_sueldo', 'Costo hora sueldo', 'numeric', 'number', false, 30),
    ('costo_hora_rmv', 'Costo hora RMV', 'numeric', 'number', false, 31),
    ('basico_costo', 'Básico costo', 'numeric', 'number', false, 32),
    ('asignacion_familiar_costo', 'Asignación familiar costo', 'numeric', 'number', false, 33),
    ('gratificacion_costo', 'Gratificación costo', 'numeric', 'number', false, 34),
    ('bono_gratificacion_costo', 'Bono gratificación costo', 'numeric', 'number', false, 35),
    ('cts_costo', 'CTS costo', 'numeric', 'number', false, 36),
    ('bono_beta_costo', 'Bono Beta costo', 'numeric', 'number', false, 37),
    ('descanso_semanal_costo', 'Descanso semanal costo', 'numeric', 'number', false, 38),
    ('horas_extras_25_costo', 'Horas extras (25%) costo', 'numeric', 'number', false, 39),
    ('horas_extras_35_costo', 'Horas extras (35%) costo', 'numeric', 'number', false, 40),
    ('horas_nocturnas_costo', 'Horas nocturnas costo', 'numeric', 'number', false, 41),
    ('descanso_medico_costo', 'Descanso médico costo', 'numeric', 'number', false, 42),
    ('teletrabajo_costo', 'Teletrabajo costo', 'numeric', 'number', false, 43),
    ('licencia_maternidad_costo', 'Licencia maternidad costo', 'numeric', 'number', false, 44),
    ('licencia_paternidad_costo', 'Licencia paternidad costo', 'numeric', 'number', false, 45),
    ('licencia_fallecimiento_costo', 'Licencia fallecimiento costo', 'numeric', 'number', false, 46),
    ('comision_costo', 'Comisión costo', 'numeric', 'number', false, 47),
    ('bono_cargo_costo', 'Bono cargo costo', 'numeric', 'number', true, 48),
    ('bono_labor_costo', 'Bono labor costo', 'numeric', 'number', true, 49),
    ('bono_movilidad_costo', 'Bono movilidad costo', 'numeric', 'number', true, 50),
    ('ingreso_bruto', 'Ingreso bruto', 'numeric', 'number', false, 60),
    ('afecto', 'Afecto', 'numeric', 'number', false, 61),
    ('inafecto', 'Inafecto', 'numeric', 'number', false, 62),
    ('essalud_costo', 'EsSalud', 'numeric', 'number', false, 63),
    ('costo_empresa', 'Costo empresa', 'numeric', 'number', false, 64),
    ('onp_costo', 'ONP costo', 'numeric', 'number', false, 65),
    ('afp_costo', 'AFP costo', 'numeric', 'number', false, 66),
    ('afp_seguro_costo', 'AFP seguro costo', 'numeric', 'number', false, 67),
    ('afp_comision_costo', 'AFP comisión costo', 'numeric', 'number', false, 68),
    ('descuento', 'Descuento', 'numeric', 'number', false, 69),
    ('total_neto', 'Total neto', 'numeric', 'number', false, 70)
)
insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  "id", "tabla_destino", "campo", "etiqueta", "tipo", "tipo_ui",
  "requerido", "visible", "visible_tabla", "editable", "orden", "activo",
  "created_at", "updated_at", "estado_sync", "eliminado"
)
select 'planilla_zumac_' || campo, 'PLANILLA_TRABAJADORES_ZUMAC', campo,
  etiqueta, tipo, tipo_ui, false, true, true, editable, orden, true,
  now(), now(), 'sincronizado', false
from fields
on conflict ("tabla_destino", "campo") do update set
  "etiqueta" = excluded."etiqueta", "tipo" = excluded."tipo",
  "tipo_ui" = excluded."tipo_ui", "visible" = true, "visible_tabla" = true,
  "editable" = excluded."editable", "orden" = excluded."orden",
  "activo" = true, "updated_at" = now(), "eliminado" = false;

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set "id_campo_dropdown" = '[Activo;pendiente renovación;Cese]',
    "updated_at" = now()
where "tabla_destino" = 'GH-REGISTRO_PERSONAL_PLANILLA'
  and public.appgt_normalizar_clave("campo") in ('STATUS', 'ESTADO', 'ESTADOPERSONAL');

with source_permissions as (
  select distinct on (p.user_id)
    p.empresa_id, p.user_id, p.seccion,
    p.can_view, p.can_insert, p.can_update, p.can_delete,
    p.can_export, p.can_import
  from public."PERMISOS_DE_USUARIOS_APPGT" p
  where p.tabla_destino = 'GH-REGISTRO_PERSONAL_PLANILLA'
    and p.user_id is not null
    and p.activo
    and not p.eliminado
  order by p.user_id, p.updated_at desc nulls last
), targets(formato, tabla_destino) as (values
  ('matriz_beneficios_sociales', 'MATRIZ_BENEFICIOS_SOCIALES'),
  ('planilla_trabajadores_zumac', 'PLANILLA_TRABAJADORES_ZUMAC')
)
insert into public."PERMISOS_DE_USUARIOS_APPGT" (
  empresa_id, user_id, seccion, modulo, formato, tabla_destino,
  can_view, can_insert, can_update, can_delete, can_export, can_import,
  activo, created_at, updated_at, estado_sync, eliminado
)
select p.empresa_id, p.user_id, p.seccion, 'gestion_humana', target.formato,
  target.tabla_destino, p.can_view, p.can_insert, p.can_update, p.can_delete,
  p.can_export, p.can_import, true, now(), now(), 'sincronizado', false
from source_permissions p
cross join targets target
on conflict (user_id, modulo, formato) do update set
  empresa_id = excluded.empresa_id,
  seccion = excluded.seccion,
  tabla_destino = excluded.tabla_destino,
  can_view = excluded.can_view,
  can_insert = excluded.can_insert,
  can_update = excluded.can_update,
  can_delete = excluded.can_delete,
  can_export = excluded.can_export,
  can_import = excluded.can_import,
  activo = true,
  updated_at = now(),
  eliminado = false;

alter table public."MATRIZ_BENEFICIOS_SOCIALES" enable row level security;
alter table public."PLANILLA_TRABAJADORES_ZUMAC" enable row level security;

drop policy if exists appgt_select_matriz_beneficios_sociales
  on public."MATRIZ_BENEFICIOS_SOCIALES";
create policy appgt_select_matriz_beneficios_sociales
  on public."MATRIZ_BENEFICIOS_SOCIALES" for select to authenticated
  using (public.appgt_can_view_table('MATRIZ_BENEFICIOS_SOCIALES'));
drop policy if exists appgt_write_matriz_beneficios_sociales
  on public."MATRIZ_BENEFICIOS_SOCIALES";
drop policy if exists appgt_insert_matriz_beneficios_sociales
  on public."MATRIZ_BENEFICIOS_SOCIALES";
create policy appgt_insert_matriz_beneficios_sociales
  on public."MATRIZ_BENEFICIOS_SOCIALES" for insert to authenticated
  with check (public.appgt_can_insert_table('MATRIZ_BENEFICIOS_SOCIALES'));
drop policy if exists appgt_update_matriz_beneficios_sociales
  on public."MATRIZ_BENEFICIOS_SOCIALES";
create policy appgt_update_matriz_beneficios_sociales
  on public."MATRIZ_BENEFICIOS_SOCIALES" for update to authenticated
  using (public.appgt_can_update_table('MATRIZ_BENEFICIOS_SOCIALES'))
  with check (public.appgt_can_update_table('MATRIZ_BENEFICIOS_SOCIALES'));
drop policy if exists appgt_delete_matriz_beneficios_sociales
  on public."MATRIZ_BENEFICIOS_SOCIALES";
create policy appgt_delete_matriz_beneficios_sociales
  on public."MATRIZ_BENEFICIOS_SOCIALES" for delete to authenticated
  using (public.appgt_can_delete_table('MATRIZ_BENEFICIOS_SOCIALES'));

drop policy if exists appgt_select_planilla_trabajadores_zumac
  on public."PLANILLA_TRABAJADORES_ZUMAC";
create policy appgt_select_planilla_trabajadores_zumac
  on public."PLANILLA_TRABAJADORES_ZUMAC" for select to authenticated
  using (public.appgt_can_view_table('PLANILLA_TRABAJADORES_ZUMAC'));
drop policy if exists appgt_write_planilla_trabajadores_zumac
  on public."PLANILLA_TRABAJADORES_ZUMAC";
drop policy if exists appgt_insert_planilla_trabajadores_zumac
  on public."PLANILLA_TRABAJADORES_ZUMAC";
create policy appgt_insert_planilla_trabajadores_zumac
  on public."PLANILLA_TRABAJADORES_ZUMAC" for insert to authenticated
  with check (public.appgt_can_insert_table('PLANILLA_TRABAJADORES_ZUMAC'));
drop policy if exists appgt_update_planilla_trabajadores_zumac
  on public."PLANILLA_TRABAJADORES_ZUMAC";
create policy appgt_update_planilla_trabajadores_zumac
  on public."PLANILLA_TRABAJADORES_ZUMAC" for update to authenticated
  using (public.appgt_can_update_table('PLANILLA_TRABAJADORES_ZUMAC'))
  with check (public.appgt_can_update_table('PLANILLA_TRABAJADORES_ZUMAC'));
drop policy if exists appgt_delete_planilla_trabajadores_zumac
  on public."PLANILLA_TRABAJADORES_ZUMAC";
create policy appgt_delete_planilla_trabajadores_zumac
  on public."PLANILLA_TRABAJADORES_ZUMAC" for delete to authenticated
  using (public.appgt_can_delete_table('PLANILLA_TRABAJADORES_ZUMAC'));

grant select, insert, update, delete on public."MATRIZ_BENEFICIOS_SOCIALES" to authenticated, service_role;
grant select, insert, update, delete on public."PLANILLA_TRABAJADORES_ZUMAC" to authenticated, service_role;
revoke all on function public.appgt_marcar_contratos_vencidos_zumac() from public, anon;
revoke all on function public.appgt_refrescar_planilla_zumac(date, date) from public, anon;
revoke all on function public.appgt_recalcular_planilla_zumac(text, date, date) from public, anon;
revoke all on function public.appgt_calcular_costos_planilla_zumac() from public, anon;
revoke all on function public.appgt_validar_reactivacion_personal_zumac() from public, anon;
revoke all on function public.appgt_personal_refrescar_planilla_zumac() from public, anon;
revoke all on function public.appgt_tareo_refrescar_planilla_zumac() from public, anon;
grant execute on function public.appgt_marcar_contratos_vencidos_zumac() to authenticated, service_role;
grant execute on function public.appgt_refrescar_planilla_zumac(date, date) to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
