begin;

create extension if not exists pgcrypto;

-- Motor legal de planillas Peru v2.
-- Fuentes primarias verificadas al 14/08/2026:
-- Ley 31110, Ley 31969, DS 005-2021-MIDAGRI, DS 007-2002-TR, Ley 30334,
-- DS 012-2016-TR,
-- TUO CTS (DS 001-97-TR), SUNAT quinta categoria y SBS tasas AFP.
-- Los valores variables se guardan con vigencia y nunca se fijan en Flutter.

-- ---------------------------------------------------------------------------
-- Parametros legales con vigencia y configuracion propia de cada empleador.
-- ---------------------------------------------------------------------------

create table if not exists public."PLANILLA_PARAMETROS_LEGALES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  regimen_codigo text not null check (regimen_codigo in ('AGRARIO_31110','GENERAL_728')),
  vigente_desde date not null,
  vigente_hasta date,
  rmv numeric(14,4) not null check (rmv > 0),
  uit numeric(14,4) not null check (uit > 0),
  asignacion_familiar_tasa numeric(10,6) not null default 0.10,
  cts_provision_tasa numeric(10,6) not null default 0.097222,
  gratificacion_provision_tasa numeric(10,6) not null default 0.166667,
  vacaciones_provision_tasa numeric(10,6) not null default 0.083333,
  beta_tasa numeric(10,6) not null default 0,
  nocturnidad_tasa numeric(10,6) not null default 0.35,
  onp_tasa numeric(10,6) not null default 0.13,
  afp_aporte_tasa numeric(10,6) not null default 0.10,
  afp_seguro_tasa numeric(10,6) not null default 0.0137,
  essalud_general_tasa numeric(10,6) not null default 0.09,
  essalud_agrario_pequeno_tasa numeric(10,6),
  essalud_agrario_grande_tasa numeric(10,6),
  fuente_legal text not null,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (regimen_codigo, vigente_desde),
  check (vigente_hasta is null or vigente_hasta >= vigente_desde),
  check (asignacion_familiar_tasa between 0 and 1),
  check (cts_provision_tasa between 0 and 1),
  check (gratificacion_provision_tasa between 0 and 1),
  check (vacaciones_provision_tasa between 0 and 1),
  check (beta_tasa between 0 and 1),
  check (nocturnidad_tasa between 0 and 1),
  check (onp_tasa between 0 and 1),
  check (afp_aporte_tasa between 0 and 1),
  check (afp_seguro_tasa between 0 and 1),
  check (essalud_general_tasa between 0 and 1),
  check (essalud_agrario_pequeno_tasa is null or essalud_agrario_pequeno_tasa between 0 and 1),
  check (essalud_agrario_grande_tasa is null or essalud_agrario_grande_tasa between 0 and 1)
);

insert into public."PLANILLA_PARAMETROS_LEGALES_APPGT" (
  regimen_codigo, vigente_desde, vigente_hasta, rmv, uit,
  beta_tasa, essalud_agrario_pequeno_tasa,
  essalud_agrario_grande_tasa, fuente_legal
) values
  ('AGRARIO_31110', date '2025-01-01', date '2025-12-31', 1130, 5350,
    0.30, 0.06, 0.06, 'Ley 31110; Ley 31969 art. 9; DS 005-2021-MIDAGRI; DS 006-2024-TR; DS 260-2024-EF'),
  ('AGRARIO_31110', date '2026-01-01', date '2026-12-31', 1130, 5500,
    0.30, 0.06, 0.06, 'Ley 31110; Ley 31969 art. 9; DS 005-2021-MIDAGRI; DS 006-2024-TR; DS 301-2025-EF'),
  ('GENERAL_728', date '2025-01-01', date '2025-12-31', 1130, 5350,
    0, null, null, 'DL 728; DS 007-2002-TR; DS 006-2024-TR; DS 260-2024-EF'),
  ('GENERAL_728', date '2026-01-01', date '2026-12-31', 1130, 5500,
    0, null, null, 'DL 728; DS 007-2002-TR; DS 006-2024-TR; DS 301-2025-EF')
on conflict (regimen_codigo, vigente_desde) do update set
  vigente_hasta=excluded.vigente_hasta, rmv=excluded.rmv, uit=excluded.uit,
  beta_tasa=excluded.beta_tasa,
  essalud_agrario_pequeno_tasa=excluded.essalud_agrario_pequeno_tasa,
  essalud_agrario_grande_tasa=excluded.essalud_agrario_grande_tasa,
  fuente_legal=excluded.fuente_legal, activo=true, updated_at=now();

update public."PLANILLA_PARAMETROS_LEGALES_APPGT" set
  cts_provision_tasa=0.0972,gratificacion_provision_tasa=0.1666,updated_at=now()
where regimen_codigo='AGRARIO_31110';
update public."PLANILLA_PARAMETROS_LEGALES_APPGT" set
  cts_provision_tasa=0.097222,gratificacion_provision_tasa=0.166667,updated_at=now()
where regimen_codigo='GENERAL_728';

create table if not exists public."PLANILLA_TASAS_AFP_APPGT" (
  id uuid primary key default gen_random_uuid(),
  afp_codigo text not null check (afp_codigo in ('HABITAT','INTEGRA','PRIMA','PROFUTURO')),
  vigente_desde date not null,
  vigente_hasta date,
  aporte_obligatorio_tasa numeric(10,6) not null default 0.10,
  prima_seguro_tasa numeric(10,6) not null,
  comision_flujo_tasa numeric(10,6) not null,
  comision_saldo_anual_tasa numeric(10,6) not null,
  fuente text not null default 'SBS',
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (afp_codigo, vigente_desde),
  check (vigente_hasta is null or vigente_hasta >= vigente_desde),
  check (aporte_obligatorio_tasa between 0 and 1),
  check (prima_seguro_tasa between 0 and 1),
  check (comision_flujo_tasa between 0 and 1),
  check (comision_saldo_anual_tasa between 0 and 1)
);

insert into public."PLANILLA_TASAS_AFP_APPGT" (
  afp_codigo, vigente_desde, vigente_hasta, prima_seguro_tasa,
  comision_flujo_tasa, comision_saldo_anual_tasa
) values
  ('HABITAT', date '2026-07-01', date '2026-12-31', 0.0137, 0.0147, 0.0125),
  ('INTEGRA', date '2026-07-01', date '2026-12-31', 0.0137, 0.0155, 0.0078),
  ('PRIMA', date '2026-07-01', date '2026-12-31', 0.0137, 0.0160, 0.0125),
  ('PROFUTURO', date '2026-07-01', date '2026-12-31', 0.0137, 0.0169, 0.0068)
on conflict (afp_codigo, vigente_desde) do update set
  vigente_hasta=excluded.vigente_hasta,
  prima_seguro_tasa=excluded.prima_seguro_tasa,
  comision_flujo_tasa=excluded.comision_flujo_tasa,
  comision_saldo_anual_tasa=excluded.comision_saldo_anual_tasa,
  activo=true, updated_at=now();

create table if not exists public."PLANILLA_CONFIG_EMPRESA_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null unique references public."EMPRESAS_APPGT"(id) on delete cascade,
  aplica_ley_31110 boolean not null default false,
  sustento_aplicacion_ley_31110 text,
  clasificacion_essalud_agrario text check (
    clasificacion_essalud_agrario in ('PEQUENO','GRANDE')
  ),
  trabajadores_agrarios_declarados_anterior integer check (
    trabajadores_agrarios_declarados_anterior is null or trabajadores_agrarios_declarados_anterior >= 0
  ),
  ventas_anuales_uit_anterior numeric(18,4) check (
    ventas_anuales_uit_anterior is null or ventas_anuales_uit_anterior >= 0
  ),
  tiene_eps boolean not null default false,
  bono_gratificacion_eps_tasa numeric(10,6) not null default 0.0675
    check (bono_gratificacion_eps_tasa=0.0675),
  sctr_salud_tasa numeric(10,6) check (sctr_salud_tasa is null or sctr_salud_tasa between 0 and 1),
  sctr_pension_tasa numeric(10,6) check (sctr_pension_tasa is null or sctr_pension_tasa between 0 and 1),
  responsable_legal text,
  validado_por uuid references auth.users(id),
  validado_at timestamptz,
  observaciones text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public."PLANILLA_CONFIG_EMPRESA_APPGT" (empresa_id)
select e.id from public."EMPRESAS_APPGT" e
on conflict (empresa_id) do nothing;

create or replace function public.appgt_validar_config_empresa_planilla_v2()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  new.bono_gratificacion_eps_tasa:=0.0675;
  if new.aplica_ley_31110 and
     nullif(btrim(new.sustento_aplicacion_ley_31110),'') is null then
    raise exception 'Para aplicar la Ley 31110 registre el sustento de la actividad agraria/agroindustrial comprendida.';
  end if;
  if new.clasificacion_essalud_agrario='GRANDE' and not (
    coalesce(new.trabajadores_agrarios_declarados_anterior,0)>=100 or
    coalesce(new.ventas_anuales_uit_anterior,0)>=1700
  ) then
    raise exception 'La clasificacion GRANDE requiere 100 o mas trabajadores agrarios o ventas de 1700 UIT o mas.';
  end if;
  if new.clasificacion_essalud_agrario='PEQUENO' and (
    new.trabajadores_agrarios_declarados_anterior is null or
    new.ventas_anuales_uit_anterior is null or
    new.trabajadores_agrarios_declarados_anterior>=100 or
    new.ventas_anuales_uit_anterior>=1700
  ) then
    raise exception 'La clasificacion PEQUENO requiere informar ambos valores y que sean menores a 100 trabajadores y 1700 UIT.';
  end if;
  if new.aplica_ley_31110 and
     nullif(btrim(new.sustento_aplicacion_ley_31110),'') is not null then
    new.validado_por:=auth.uid();
    new.validado_at:=now();
  else
    new.validado_por:=null;
    new.validado_at:=null;
  end if;
  new.updated_at:=now();
  return new;
end;
$$;

drop trigger if exists appgt_validar_config_empresa_planilla_v2_trigger
  on public."PLANILLA_CONFIG_EMPRESA_APPGT";
create trigger appgt_validar_config_empresa_planilla_v2_trigger
before insert or update on public."PLANILLA_CONFIG_EMPRESA_APPGT"
for each row execute function public.appgt_validar_config_empresa_planilla_v2();

-- ---------------------------------------------------------------------------
-- Datos laborales canonicos. Frecuencia de pago no cambia el devengo legal.
-- ---------------------------------------------------------------------------

alter table public."GH-REGISTRO_PERSONAL_PLANILLA"
  add column if not exists empresa_id uuid,
  add column if not exists "REGIMEN_LABORAL_CODIGO" text,
  add column if not exists "TIPO_REMUNERACION" text,
  add column if not exists "FRECUENCIA_PAGO" text,
  add column if not exists "MODALIDAD_CTS_GRATIFICACION" text,
  add column if not exists "FECHA_ELECCION_CTS_GRATIFICACION" date,
  add column if not exists "DOCUMENTO_ELECCION_CTS_GRATIFICACION" text,
  add column if not exists "MODALIDAD_BETA" text,
  add column if not exists "FECHA_ACUERDO_BETA" date,
  add column if not exists "DOCUMENTO_ACUERDO_BETA" text,
  add column if not exists "SISTEMA_PENSION_CODIGO" text,
  add column if not exists "AFP_NOMBRE" text,
  add column if not exists "AFP_TIPO_COMISION" text,
  add column if not exists "HORAS_DIARIAS_PROMEDIO" numeric(6,3),
  add column if not exists "ES_ADMINISTRATIVO_SOPORTE" boolean not null default false,
  add column if not exists "INGRESOS_OTRO_EMPLEADOR_5TA_MENSUAL" numeric(18,6) not null default 0,
  add column if not exists "RENTA_5TA_ACUMULADA_INICIAL" numeric(18,6) not null default 0,
  add column if not exists "RETENCION_5TA_ACUMULADA_INICIAL" numeric(18,6) not null default 0,
  add column if not exists "REQUIERE_SCTR" boolean not null default false;

-- Esta matriz historica nacio antes del aislamiento por empresa. Se incorpora
-- la clave de tenant antes de crear historiales y calculos que dependen de ella.
-- Los registros existentes pertenecen a la empresa ZUMAC creada por la
-- migracion base; los nuevos registros reciben la empresa activa desde el
-- cliente o, por compatibilidad, el tenant inicial.
update public."GH-REGISTRO_PERSONAL_PLANILLA"
set empresa_id = '00000000-0000-0000-0000-000000000001'::uuid
where empresa_id is null;

alter table public."GH-REGISTRO_PERSONAL_PLANILLA"
  alter column empresa_id set default '00000000-0000-0000-0000-000000000001'::uuid,
  alter column empresa_id set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='gh_personal_planilla_empresa_fk'
      and conrelid='public."GH-REGISTRO_PERSONAL_PLANILLA"'::regclass
  ) then
    alter table public."GH-REGISTRO_PERSONAL_PLANILLA"
      add constraint gh_personal_planilla_empresa_fk
      foreign key (empresa_id) references public."EMPRESAS_APPGT"(id);
  end if;
end;
$$;

create index if not exists gh_personal_planilla_empresa_idx
  on public."GH-REGISTRO_PERSONAL_PLANILLA" (empresa_id);

update public."GH-REGISTRO_PERSONAL_PLANILLA" p set
  "REGIMEN_LABORAL_CODIGO" = coalesce("REGIMEN_LABORAL_CODIGO", case
    when public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p), array['Regimen laboral','REGIMEN_LABORAL','Regimen'])
    ) like '%GENERAL%' then 'GENERAL_728'
    else 'AGRARIO_31110' end),
  "FRECUENCIA_PAGO" = coalesce("FRECUENCIA_PAGO", case
    when public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p), array['Periodo de pago','PERIODO_PAGO'])
    ) like '%QUINC%' then 'QUINCENAL'
    when public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p), array['Periodo de pago','PERIODO_PAGO'])
    ) like '%MENS%' then 'MENSUAL'
    else null end),
  "TIPO_REMUNERACION" = coalesce("TIPO_REMUNERACION", case
    when public.appgt_normalizar_clave(coalesce("GRUPO_COSTO", '')) in
      ('EMPLEADO','ADMINISTRATIVO') then 'MENSUAL'
    when public.appgt_normalizar_clave(coalesce("GRUPO_COSTO", '')) = 'OBRERO'
      then 'JORNAL'
    else null end),
  "SISTEMA_PENSION_CODIGO" = coalesce("SISTEMA_PENSION_CODIGO", case
    when public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p), array['Sistema pensionario','SISTEMA_PENSION','AFP/ONP'])
    ) like '%ONP%' then 'ONP'
    when public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p), array['Sistema pensionario','SISTEMA_PENSION','AFP/ONP'])
    ) like '%AFP%' then 'AFP'
    else null end);

update public."GH-REGISTRO_PERSONAL_PLANILLA" set
  "MODALIDAD_CTS_GRATIFICACION" = coalesce(
    "MODALIDAD_CTS_GRATIFICACION",
    case when "REGIMEN_LABORAL_CODIGO"='AGRARIO_31110'
      then 'PRORRATEADA' else 'SEMESTRAL' end
  ),
  "MODALIDAD_BETA" = case when "REGIMEN_LABORAL_CODIGO"='AGRARIO_31110'
    then coalesce("MODALIDAD_BETA", 'MENSUAL') else 'NO_APLICA' end;

alter table public."GH-REGISTRO_PERSONAL_PLANILLA"
  drop constraint if exists gh_personal_regimen_legal_check,
  drop constraint if exists gh_personal_tipo_remuneracion_check,
  drop constraint if exists gh_personal_frecuencia_pago_check,
  drop constraint if exists gh_personal_modalidad_cts_grat_check,
  drop constraint if exists gh_personal_modalidad_beta_check,
  drop constraint if exists gh_personal_pension_codigo_check,
  drop constraint if exists gh_personal_afp_nombre_check,
  drop constraint if exists gh_personal_afp_comision_check,
  drop constraint if exists gh_personal_horas_diarias_check,
  drop constraint if exists gh_personal_quinta_inputs_check;

alter table public."GH-REGISTRO_PERSONAL_PLANILLA"
  add constraint gh_personal_regimen_legal_check check (
    "REGIMEN_LABORAL_CODIGO" is null or
    "REGIMEN_LABORAL_CODIGO" in ('AGRARIO_31110','GENERAL_728')
  ),
  add constraint gh_personal_tipo_remuneracion_check check (
    "TIPO_REMUNERACION" is null or "TIPO_REMUNERACION" in ('MENSUAL','JORNAL')
  ),
  add constraint gh_personal_frecuencia_pago_check check (
    "FRECUENCIA_PAGO" is null or "FRECUENCIA_PAGO" in ('QUINCENAL','MENSUAL')
  ),
  add constraint gh_personal_modalidad_cts_grat_check check (
    "MODALIDAD_CTS_GRATIFICACION" is null or
    "MODALIDAD_CTS_GRATIFICACION" in ('PRORRATEADA','SEMESTRAL')
  ),
  add constraint gh_personal_modalidad_beta_check check (
    "MODALIDAD_BETA" is null or
    "MODALIDAD_BETA" in ('MENSUAL','PRORRATEADA','NO_APLICA')
  ),
  add constraint gh_personal_pension_codigo_check check (
    "SISTEMA_PENSION_CODIGO" is null or "SISTEMA_PENSION_CODIGO" in ('ONP','AFP')
  ),
  add constraint gh_personal_afp_nombre_check check (
    "AFP_NOMBRE" is null or "AFP_NOMBRE" in ('HABITAT','INTEGRA','PRIMA','PROFUTURO')
  ),
  add constraint gh_personal_afp_comision_check check (
    "AFP_TIPO_COMISION" is null or "AFP_TIPO_COMISION" in ('FLUJO','SALDO')
  ),
  add constraint gh_personal_horas_diarias_check check (
    "HORAS_DIARIAS_PROMEDIO" is null or
    "HORAS_DIARIAS_PROMEDIO">0 and "HORAS_DIARIAS_PROMEDIO"<=8
  ),
  add constraint gh_personal_quinta_inputs_check check (
    "INGRESOS_OTRO_EMPLEADOR_5TA_MENSUAL">=0 and
    "RENTA_5TA_ACUMULADA_INICIAL">=0 and
    "RETENCION_5TA_ACUMULADA_INICIAL">=0
  );

create table if not exists public."PLANILLA_ELECCIONES_BENEFICIOS_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null default public.appgt_empresa_actual_id()
    references public."EMPRESAS_APPGT"(id) on delete cascade,
  dni text not null,
  concepto text not null check (concepto in ('CTS_GRATIFICACION','BETA')),
  modalidad_anterior text,
  modalidad_nueva text not null,
  vigente_desde date not null,
  documento_sustento text,
  observaciones text,
  registrado_por uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (empresa_id, dni, concepto, vigente_desde)
);

create or replace function public.appgt_validar_eleccion_beneficios_v2()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cambio_cts boolean := false;
  v_cambio_beta boolean := false;
begin
  new.empresa_id := coalesce(
    new.empresa_id,
    public.appgt_empresa_actual_id(),
    '00000000-0000-0000-0000-000000000001'::uuid
  );
  if new."SISTEMA_PENSION_CODIGO"='ONP' then
    new."AFP_NOMBRE":=null;
    new."AFP_TIPO_COMISION":=null;
  end if;
  if new."REGIMEN_LABORAL_CODIGO" = 'GENERAL_728' then
    new."MODALIDAD_CTS_GRATIFICACION" := 'SEMESTRAL';
    new."FECHA_ELECCION_CTS_GRATIFICACION" := null;
    new."DOCUMENTO_ELECCION_CTS_GRATIFICACION" := null;
    new."MODALIDAD_BETA" := 'NO_APLICA';
    new."FECHA_ACUERDO_BETA" := null;
    new."DOCUMENTO_ACUERDO_BETA" := null;
  elsif new."REGIMEN_LABORAL_CODIGO" = 'AGRARIO_31110' then
    if tg_op = 'INSERT' then
      new."MODALIDAD_CTS_GRATIFICACION" := coalesce(
        new."MODALIDAD_CTS_GRATIFICACION", 'PRORRATEADA'
      );
      new."MODALIDAD_BETA" := coalesce(new."MODALIDAD_BETA", 'MENSUAL');
    elsif old."REGIMEN_LABORAL_CODIGO" is distinct from new."REGIMEN_LABORAL_CODIGO" then
      -- Al ingresar al regimen agrario no se arrastra el pago semestral del
      -- regimen general: sin eleccion escrita, la regla legal es prorratear.
      if new."MODALIDAD_CTS_GRATIFICACION" = 'SEMESTRAL' and
         new."FECHA_ELECCION_CTS_GRATIFICACION" is not null and
         nullif(btrim(new."DOCUMENTO_ELECCION_CTS_GRATIFICACION"), '') is not null then
        v_cambio_cts := true;
      else
        new."MODALIDAD_CTS_GRATIFICACION" := 'PRORRATEADA';
        new."FECHA_ELECCION_CTS_GRATIFICACION" := null;
        new."DOCUMENTO_ELECCION_CTS_GRATIFICACION" := null;
      end if;

      if new."MODALIDAD_BETA" = 'PRORRATEADA' and
         new."FECHA_ACUERDO_BETA" is not null and
         nullif(btrim(new."DOCUMENTO_ACUERDO_BETA"), '') is not null then
        v_cambio_beta := true;
      else
        new."MODALIDAD_BETA" := 'MENSUAL';
        new."FECHA_ACUERDO_BETA" := null;
        new."DOCUMENTO_ACUERDO_BETA" := null;
      end if;
    else
      new."MODALIDAD_CTS_GRATIFICACION" := coalesce(
        new."MODALIDAD_CTS_GRATIFICACION", 'PRORRATEADA'
      );
      new."MODALIDAD_BETA" := coalesce(new."MODALIDAD_BETA", 'MENSUAL');
      v_cambio_cts := new."MODALIDAD_CTS_GRATIFICACION" is distinct from
        old."MODALIDAD_CTS_GRATIFICACION";
      v_cambio_beta := new."MODALIDAD_BETA" is distinct from old."MODALIDAD_BETA";
    end if;
  end if;

  if new."REGIMEN_LABORAL_CODIGO" = 'AGRARIO_31110' and
     new."MODALIDAD_CTS_GRATIFICACION" = 'SEMESTRAL' and (
       new."FECHA_ELECCION_CTS_GRATIFICACION" is null or
       nullif(btrim(new."DOCUMENTO_ELECCION_CTS_GRATIFICACION"), '') is null
     ) then
    raise exception 'El pago semestral de CTS/gratificacion agraria requiere eleccion escrita, fecha y documento del trabajador.';
  end if;

  if v_cambio_cts then
    if new."FECHA_ELECCION_CTS_GRATIFICACION" is null or
       nullif(btrim(new."DOCUMENTO_ELECCION_CTS_GRATIFICACION"), '') is null then
      raise exception 'El cambio de CTS/gratificacion requiere fecha y documento escrito del trabajador.';
    end if;
    if tg_op = 'UPDATE' and
       old."REGIMEN_LABORAL_CODIGO" = 'AGRARIO_31110' and
       new."FECHA_ELECCION_CTS_GRATIFICACION" is not distinct from old."FECHA_ELECCION_CTS_GRATIFICACION" and
       new."DOCUMENTO_ELECCION_CTS_GRATIFICACION" is not distinct from old."DOCUMENTO_ELECCION_CTS_GRATIFICACION" then
      raise exception 'Cada cambio de CTS/gratificacion requiere registrar una nueva fecha o un nuevo documento escrito.';
    end if;
  end if;

  if new."MODALIDAD_BETA" = 'PRORRATEADA' and (
       new."FECHA_ACUERDO_BETA" is null or
       nullif(btrim(new."DOCUMENTO_ACUERDO_BETA"), '') is null
  ) then
    raise exception 'El prorrateo del BETA requiere acuerdo escrito, fecha y documento.';
  end if;
  if v_cambio_beta then
    if new."FECHA_ACUERDO_BETA" is null or
       nullif(btrim(new."DOCUMENTO_ACUERDO_BETA"), '') is null then
      raise exception 'El cambio de pago del BETA requiere acuerdo escrito, fecha y documento.';
    end if;
    if tg_op = 'UPDATE' and
       old."REGIMEN_LABORAL_CODIGO" = 'AGRARIO_31110' and
       new."FECHA_ACUERDO_BETA" is not distinct from old."FECHA_ACUERDO_BETA" and
       new."DOCUMENTO_ACUERDO_BETA" is not distinct from old."DOCUMENTO_ACUERDO_BETA" then
      raise exception 'Cada cambio de pago del BETA requiere registrar una nueva fecha o un nuevo documento escrito.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists appgt_validar_eleccion_beneficios_v2_trigger
  on public."GH-REGISTRO_PERSONAL_PLANILLA";
create trigger appgt_validar_eleccion_beneficios_v2_trigger
before insert or update of "REGIMEN_LABORAL_CODIGO",
  "MODALIDAD_CTS_GRATIFICACION", "MODALIDAD_BETA",
  "FECHA_ELECCION_CTS_GRATIFICACION", "DOCUMENTO_ELECCION_CTS_GRATIFICACION",
  "FECHA_ACUERDO_BETA", "DOCUMENTO_ACUERDO_BETA",
  "SISTEMA_PENSION_CODIGO", "AFP_NOMBRE", "AFP_TIPO_COMISION"
on public."GH-REGISTRO_PERSONAL_PLANILLA"
for each row execute function public.appgt_validar_eleccion_beneficios_v2();

create or replace function public.appgt_historial_eleccion_beneficios_v2()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_dni text := public.appgt_jsonb_text(to_jsonb(new), array['DNI','DOCUMENTO']);
  v_empresa uuid := coalesce(new.empresa_id, public.appgt_empresa_actual_id());
begin
  if tg_op = 'INSERT' or
     new."MODALIDAD_CTS_GRATIFICACION" is distinct from old."MODALIDAD_CTS_GRATIFICACION" then
    insert into public."PLANILLA_ELECCIONES_BENEFICIOS_APPGT" (
      empresa_id, dni, concepto, modalidad_anterior, modalidad_nueva,
      vigente_desde, documento_sustento
    ) values (
      v_empresa, v_dni, 'CTS_GRATIFICACION',
      case when tg_op='UPDATE' then old."MODALIDAD_CTS_GRATIFICACION" else null end,
      new."MODALIDAD_CTS_GRATIFICACION",
      coalesce(new."FECHA_ELECCION_CTS_GRATIFICACION",
        public.appgt_jsonb_date(to_jsonb(new),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),
        current_date),
      new."DOCUMENTO_ELECCION_CTS_GRATIFICACION"
    ) on conflict (empresa_id, dni, concepto, vigente_desde) do update set
      modalidad_anterior=excluded.modalidad_anterior,
      modalidad_nueva=excluded.modalidad_nueva,
      documento_sustento=excluded.documento_sustento;
  end if;
  if (tg_op = 'INSERT' and new."REGIMEN_LABORAL_CODIGO"='AGRARIO_31110') or
     (tg_op='UPDATE' and new."MODALIDAD_BETA" is distinct from old."MODALIDAD_BETA") then
    insert into public."PLANILLA_ELECCIONES_BENEFICIOS_APPGT" (
      empresa_id, dni, concepto, modalidad_anterior, modalidad_nueva,
      vigente_desde, documento_sustento
    ) values (
      v_empresa, v_dni, 'BETA',
      case when tg_op='UPDATE' then old."MODALIDAD_BETA" else null end,
      new."MODALIDAD_BETA", coalesce(new."FECHA_ACUERDO_BETA",
        public.appgt_jsonb_date(to_jsonb(new),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),
        current_date),
      new."DOCUMENTO_ACUERDO_BETA"
    ) on conflict (empresa_id, dni, concepto, vigente_desde) do update set
      modalidad_anterior=excluded.modalidad_anterior,
      modalidad_nueva=excluded.modalidad_nueva,
      documento_sustento=excluded.documento_sustento;
  end if;
  return new;
end;
$$;

drop trigger if exists appgt_historial_eleccion_beneficios_v2_trigger
  on public."GH-REGISTRO_PERSONAL_PLANILLA";
create trigger appgt_historial_eleccion_beneficios_v2_trigger
after insert or update of "REGIMEN_LABORAL_CODIGO",
  "MODALIDAD_CTS_GRATIFICACION", "MODALIDAD_BETA"
on public."GH-REGISTRO_PERSONAL_PLANILLA"
for each row execute function public.appgt_historial_eleccion_beneficios_v2();

insert into public."PLANILLA_ELECCIONES_BENEFICIOS_APPGT" (
  empresa_id,dni,concepto,modalidad_anterior,modalidad_nueva,
  vigente_desde,documento_sustento,observaciones
)
select p.empresa_id,
  public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']),
  'CTS_GRATIFICACION',null,p."MODALIDAD_CTS_GRATIFICACION",
  coalesce(p."FECHA_ELECCION_CTS_GRATIFICACION",
    public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),
    current_date),
  p."DOCUMENTO_ELECCION_CTS_GRATIFICACION",'Estado inicial migrado a LEGAL_V2'
from public."GH-REGISTRO_PERSONAL_PLANILLA" p
where p.empresa_id is not null
  and public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']) is not null
  and p."MODALIDAD_CTS_GRATIFICACION" is not null
on conflict (empresa_id,dni,concepto,vigente_desde) do nothing;

insert into public."PLANILLA_ELECCIONES_BENEFICIOS_APPGT" (
  empresa_id,dni,concepto,modalidad_anterior,modalidad_nueva,
  vigente_desde,documento_sustento,observaciones
)
select p.empresa_id,
  public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']),
  'BETA',null,p."MODALIDAD_BETA",
  coalesce(p."FECHA_ACUERDO_BETA",
    public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),
    current_date),
  p."DOCUMENTO_ACUERDO_BETA",'Estado inicial migrado a LEGAL_V2'
from public."GH-REGISTRO_PERSONAL_PLANILLA" p
where p.empresa_id is not null
  and p."REGIMEN_LABORAL_CODIGO"='AGRARIO_31110'
  and public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']) is not null
  and p."MODALIDAD_BETA" is not null
on conflict (empresa_id,dni,concepto,vigente_desde) do nothing;

-- ---------------------------------------------------------------------------
-- La liquidacion por periodo es la fuente de pago. La tabla diaria queda como
-- costeo y distribucion por labor/centro de costo, no como boleta.
-- ---------------------------------------------------------------------------

create table if not exists public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  periodo_id uuid not null references public."PLANILLA_PERIODOS_APPGT"(id) on delete cascade,
  dni text not null,
  trabajador text not null,
  regimen_codigo text not null,
  tipo_remuneracion text not null,
  frecuencia_pago text not null,
  modalidad_cts_gratificacion text not null,
  modalidad_beta text not null,
  sistema_pension text not null,
  afp_nombre text,
  afp_tipo_comision text,
  sueldo_mensual numeric(18,6) not null default 0,
  rmv numeric(18,6) not null default 0,
  uit numeric(18,6) not null default 0,
  dias_base_30 numeric(10,4) not null default 0,
  dias_sin_goce numeric(10,4) not null default 0,
  horas_ordinarias numeric(12,4) not null default 0,
  horas_extra_25 numeric(12,4) not null default 0,
  horas_extra_35 numeric(12,4) not null default 0,
  horas_nocturnas numeric(12,4) not null default 0,
  remuneracion_basica numeric(18,6) not null default 0,
  asignacion_familiar numeric(18,6) not null default 0,
  descanso_semanal numeric(18,6) not null default 0,
  horas_extra_25_importe numeric(18,6) not null default 0,
  horas_extra_35_importe numeric(18,6) not null default 0,
  nocturnidad_importe numeric(18,6) not null default 0,
  licencias_pagadas numeric(18,6) not null default 0,
  beta_pagado numeric(18,6) not null default 0,
  cts_pagada numeric(18,6) not null default 0,
  gratificacion_pagada numeric(18,6) not null default 0,
  bono_extraordinario_gratificacion numeric(18,6) not null default 0,
  otros_ingresos_afectos numeric(18,6) not null default 0,
  otros_ingresos_inafectos numeric(18,6) not null default 0,
  remuneracion_bruta numeric(18,6) not null default 0,
  base_pension numeric(18,6) not null default 0,
  base_essalud numeric(18,6) not null default 0,
  renta_quinta_categoria numeric(18,6) not null default 0,
  onp numeric(18,6) not null default 0,
  afp_aporte numeric(18,6) not null default 0,
  afp_seguro numeric(18,6) not null default 0,
  afp_comision numeric(18,6) not null default 0,
  retencion_quinta numeric(18,6) not null default 0,
  otros_descuentos numeric(18,6) not null default 0,
  total_descuentos numeric(18,6) not null default 0,
  neto_pagar numeric(18,6) not null default 0,
  deposito_cts numeric(18,6) not null default 0,
  total_desembolso_trabajador numeric(18,6) not null default 0,
  essalud_empleador numeric(18,6) not null default 0,
  sctr_salud numeric(18,6) not null default 0,
  sctr_pension numeric(18,6) not null default 0,
  provision_cts numeric(18,6) not null default 0,
  provision_gratificacion numeric(18,6) not null default 0,
  provision_vacaciones numeric(18,6) not null default 0,
  total_provisiones numeric(18,6) not null default 0,
  costo_total_empresa numeric(18,6) not null default 0,
  estado_calculo text not null default 'CALCULADO',
  detalle_calculo jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (periodo_id, dni)
);

create index if not exists planilla_liquidacion_empresa_periodo_idx
  on public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT" (empresa_id, periodo_id, dni);

create table if not exists public."PLANILLA_FERIADOS_APPGT" (
  id uuid primary key default gen_random_uuid(),
  fecha date not null,
  nombre text not null,
  ambito text not null default 'NACIONAL' check (ambito in ('NACIONAL','REGIONAL','LOCAL')),
  empresa_id uuid references public."EMPRESAS_APPGT"(id) on delete cascade,
  remunerado boolean not null default true,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  unique nulls not distinct (fecha, nombre, empresa_id)
);

insert into public."PLANILLA_FERIADOS_APPGT" (fecha,nombre) values
  (date '2026-01-01','Ano Nuevo'),
  (date '2026-04-02','Jueves Santo'),
  (date '2026-04-03','Viernes Santo'),
  (date '2026-05-01','Dia del Trabajo'),
  (date '2026-06-07','Batalla de Arica y Dia de la Bandera'),
  (date '2026-06-29','San Pedro y San Pablo'),
  (date '2026-07-23','Dia de la Fuerza Aerea del Peru'),
  (date '2026-07-28','Fiestas Patrias'),
  (date '2026-07-29','Fiestas Patrias'),
  (date '2026-08-06','Batalla de Junin'),
  (date '2026-08-30','Santa Rosa de Lima'),
  (date '2026-10-08','Combate de Angamos'),
  (date '2026-11-01','Todos los Santos'),
  (date '2026-12-08','Inmaculada Concepcion'),
  (date '2026-12-09','Batalla de Ayacucho'),
  (date '2026-12-25','Navidad')
on conflict (fecha,nombre,empresa_id) do update set activo=true, remunerado=true;

create table if not exists public."PLANILLA_VALIDACIONES_APPGT" (
  id bigint generated always as identity primary key,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  periodo_id uuid not null references public."PLANILLA_PERIODOS_APPGT"(id) on delete cascade,
  nivel text not null check (nivel in ('ERROR','ADVERTENCIA')),
  codigo text not null,
  dni text,
  mensaje text not null,
  resuelto boolean not null default false,
  generado_at timestamptz not null default now()
);

create index if not exists planilla_validaciones_periodo_idx
  on public."PLANILLA_VALIDACIONES_APPGT" (periodo_id, nivel, resuelto);

alter table public."PLANILLA_TRABAJADORES_ZUMAC"
  add column if not exists regimen_codigo text,
  add column if not exists tipo_remuneracion text,
  add column if not exists frecuencia_pago text,
  add column if not exists modalidad_cts_gratificacion text,
  add column if not exists modalidad_beta text,
  add column if not exists uit numeric(18,6) not null default 0,
  add column if not exists provision_cts_legal numeric(18,6) not null default 0,
  add column if not exists provision_gratificacion_legal numeric(18,6) not null default 0,
  add column if not exists provision_vacaciones_legal numeric(18,6) not null default 0;

create or replace function public.appgt_impuesto_anual_quinta_v2(
  p_renta_neta numeric,
  p_uit numeric
)
returns numeric
language sql
immutable
parallel safe
as $$
  select round(
    least(greatest(coalesce(p_renta_neta,0),0), 5*coalesce(p_uit,0)) * 0.08
    + least(greatest(coalesce(p_renta_neta,0)-5*coalesce(p_uit,0),0), 15*coalesce(p_uit,0)) * 0.14
    + least(greatest(coalesce(p_renta_neta,0)-20*coalesce(p_uit,0),0), 15*coalesce(p_uit,0)) * 0.17
    + least(greatest(coalesce(p_renta_neta,0)-35*coalesce(p_uit,0),0), 10*coalesce(p_uit,0)) * 0.20
    + greatest(coalesce(p_renta_neta,0)-45*coalesce(p_uit,0),0) * 0.30,
    6
  )
$$;

create or replace function public.appgt_dias_base_30_v2(
  p_desde date,
  p_hasta date
)
returns numeric
language plpgsql
immutable
parallel safe
as $$
declare
  v_mes date;
  v_inicio date;
  v_fin date;
  v_total numeric := 0;
begin
  if p_desde is null or p_hasta is null or p_hasta < p_desde then return 0; end if;
  v_mes := date_trunc('month', p_desde)::date;
  while v_mes <= p_hasta loop
    v_inicio := greatest(p_desde, v_mes);
    v_fin := least(p_hasta, (v_mes + interval '1 month - 1 day')::date);
    if v_inicio = v_mes and v_fin = (v_mes + interval '1 month - 1 day')::date then
      v_total := v_total + 30;
    else
      v_total := v_total + greatest(
        least(extract(day from v_fin)::numeric,30)
        - least(extract(day from v_inicio)::numeric-1,30), 0
      );
    end if;
    v_mes := (v_mes + interval '1 month')::date;
  end loop;
  return v_total;
end;
$$;

-- Reemplaza el calculo heredado. Las deducciones pensionarias son excluyentes,
-- la nocturnidad usa 35% y los beneficios no pagados quedan como provision.
create or replace function public.appgt_calcular_costos_planilla_zumac()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_worker jsonb;
  v_param record;
  v_config public."PLANILLA_CONFIG_EMPRESA_APPGT"%rowtype;
  v_afp record;
  v_regimen text;
  v_modalidad text;
  v_beta_modalidad text;
  v_pension text;
  v_afp_nombre text;
  v_afp_tipo text;
  v_asig_mensual numeric := 0;
  v_jornada numeric := 8;
  v_hora_ordinaria numeric := 0;
  v_base_beneficios numeric := 0;
  v_base_afecta numeric := 0;
  v_essalud_tasa numeric := 0;
  v_bono_grat_tasa numeric := 0;
  v_afp_comision numeric := 0;
begin
  new.empresa_id:=coalesce(new.empresa_id,public.appgt_empresa_actual_id());
  select to_jsonb(p) into v_worker
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  where p.empresa_id=new.empresa_id
    and public.appgt_normalizar_clave(
    public.appgt_jsonb_text(to_jsonb(p), array['DNI','DOCUMENTO'])
  ) = public.appgt_normalizar_clave(new.dni)
  limit 1;

  v_regimen := coalesce(
    public.appgt_jsonb_text(v_worker, array['REGIMEN_LABORAL_CODIGO']),
    new.regimen_codigo
  );
  v_modalidad := coalesce(
    public.appgt_jsonb_text(v_worker, array['MODALIDAD_CTS_GRATIFICACION']),
    case when v_regimen='AGRARIO_31110' then 'PRORRATEADA' else 'SEMESTRAL' end
  );
  v_beta_modalidad := coalesce(
    public.appgt_jsonb_text(v_worker, array['MODALIDAD_BETA']),
    case when v_regimen='AGRARIO_31110' then 'MENSUAL' else 'NO_APLICA' end
  );
  v_pension := public.appgt_jsonb_text(v_worker, array['SISTEMA_PENSION_CODIGO']);
  v_afp_nombre := public.appgt_jsonb_text(v_worker, array['AFP_NOMBRE']);
  v_afp_tipo := public.appgt_jsonb_text(v_worker, array['AFP_TIPO_COMISION']);
  v_jornada := greatest(public.appgt_jsonb_numeric(
    v_worker,array['HORAS_DIARIAS_PROMEDIO'],8
  ),0.001);
  new.area:=coalesce(new.area,
    public.appgt_jsonb_text(v_worker,array['AREA','Area','AREA_TRABAJO']));
  new.grupo_costo:=coalesce(new.grupo_costo,
    public.appgt_jsonb_text(v_worker,array['GRUPO_COSTO','Grupo de costo','TIPO_TRABAJADOR']));
  new.campana:=coalesce(new.campana,
    public.appgt_jsonb_text(v_worker,array['CAMPANA','CAMPANA_TRABAJO']));

  select * into v_param
  from public."PLANILLA_PARAMETROS_LEGALES_APPGT" q
  where q.regimen_codigo=v_regimen and q.activo
    and new.fecha >= q.vigente_desde
    and (q.vigente_hasta is null or new.fecha <= q.vigente_hasta)
  order by q.vigente_desde desc limit 1;

  select * into v_config from public."PLANILLA_CONFIG_EMPRESA_APPGT" c
  where c.empresa_id=coalesce(new.empresa_id, public.appgt_empresa_actual_id()) and c.activo;

  if v_regimen='GENERAL_728' then
    v_essalud_tasa := coalesce(v_param.essalud_general_tasa,0);
  elsif v_regimen='AGRARIO_31110' then
    -- Ley 31969: del 01/01/2024 al 31/12/2028 la tasa es 6 % para todos
    -- los trabajadores agrarios comprendidos, sin usar la clasificacion
    -- historica del articulo 9 original de la Ley 31110.
    v_essalud_tasa := coalesce(
      v_param.essalud_agrario_pequeno_tasa,
      v_param.essalud_agrario_grande_tasa,
      0
    );
  end if;
  v_bono_grat_tasa := case when coalesce(v_config.tiene_eps,false)
    then coalesce(v_config.bono_gratificacion_eps_tasa,0.0675)
    else coalesce(v_param.essalud_general_tasa,0.09) end;

  if v_pension='AFP' then
    select * into v_afp from public."PLANILLA_TASAS_AFP_APPGT" a
    where a.afp_codigo=v_afp_nombre and a.activo
      and new.fecha >= a.vigente_desde
      and (a.vigente_hasta is null or new.fecha <= a.vigente_hasta)
    order by a.vigente_desde desc limit 1;
    v_afp_comision := case when v_afp_tipo='FLUJO'
      then coalesce(v_afp.comision_flujo_tasa,0) else 0 end;
  end if;

  new.regimen_codigo := v_regimen;
  new.regimen_laboral := case when v_regimen='GENERAL_728'
    then 'General 728' else 'Agrario 31110' end;
  new.tipo_remuneracion := public.appgt_jsonb_text(v_worker, array['TIPO_REMUNERACION']);
  new.frecuencia_pago := public.appgt_jsonb_text(v_worker, array['FRECUENCIA_PAGO']);
  new.modalidad_cts_gratificacion := v_modalidad;
  new.modalidad_beta := v_beta_modalidad;
  new.sistema_pension := v_pension;
  new.rmv := coalesce(v_param.rmv,0);
  new.uit := coalesce(v_param.uit,0);
  new.tasa_asignacion_familiar := coalesce(v_param.asignacion_familiar_tasa,0);
  new.tasa_cts := coalesce(v_param.cts_provision_tasa,0);
  new.tasa_gratificacion := coalesce(v_param.gratificacion_provision_tasa,0);
  new.tasa_bono_gratificacion := v_bono_grat_tasa;
  new.tasa_bono_beta := coalesce(v_param.beta_tasa,0);
  new.tasa_essalud := v_essalud_tasa;
  new.tasa_onp := coalesce(v_param.onp_tasa,0);
  new.tasa_afp := coalesce(v_afp.aporte_obligatorio_tasa, v_param.afp_aporte_tasa,0);
  new.tasa_afp_seguro := coalesce(v_afp.prima_seguro_tasa, v_param.afp_seguro_tasa,0);
  new.tasa_afp_comision := v_afp_comision;

  new.costo_hora_sueldo := round(coalesce(new.sueldo_mensual,0)/240.0,6);
  new.costo_hora_rmv := round(coalesce(new.rmv,0)/240.0,6);
  v_asig_mensual := case when coalesce(new.tiene_asignacion_familiar,false)
    then new.rmv*new.tasa_asignacion_familiar else 0 end;
  v_hora_ordinaria := (coalesce(new.sueldo_mensual,0)+v_asig_mensual)/240.0;

  new.basico_costo := round(coalesce(new.horas_trabajadas,0)*new.costo_hora_sueldo,6);
  new.asignacion_familiar_costo := round(
    coalesce(new.horas_trabajadas,0)*v_asig_mensual/240.0,6
  );
  new.descanso_semanal_costo := round(
    coalesce(new.descanso_semanal,0)*(v_jornada/8.0)*v_hora_ordinaria,6
  );
  new.horas_extras_25_costo := round(coalesce(new.horas_extras_25,0)*v_hora_ordinaria*1.25,6);
  new.horas_extras_35_costo := round(coalesce(new.horas_extras_35,0)*v_hora_ordinaria*1.35,6);
  new.horas_nocturnas_costo := round(coalesce(new.horas_nocturnas,0) * case
    when v_regimen='AGRARIO_31110' then new.rmv/240.0*coalesce(v_param.nocturnidad_tasa,0.35)
    else greatest(new.rmv*1.35-coalesce(new.sueldo_mensual,0),0)/240.0
  end,6);
  new.descanso_medico_costo := round(coalesce(new.descanso_medico,0)*v_hora_ordinaria,6);
  new.teletrabajo_costo := round(coalesce(new.teletrabajo,0)*v_hora_ordinaria,6);
  new.licencia_maternidad_costo := round(coalesce(new.licencia_maternidad,0)*v_hora_ordinaria,6);
  new.licencia_paternidad_costo := round(coalesce(new.licencia_paternidad,0)*v_hora_ordinaria,6);
  new.licencia_fallecimiento_costo := round(coalesce(new.licencia_fallecimiento,0)*v_hora_ordinaria,6);
  new.comision_costo := round(coalesce(new.comision,0)*v_hora_ordinaria,6);
  new.vacaciones_costo := round(coalesce(new.vacaciones,0)*v_hora_ordinaria,6);

  v_base_beneficios := new.basico_costo + new.asignacion_familiar_costo
    + new.descanso_semanal_costo + new.descanso_medico_costo
    + new.teletrabajo_costo + new.licencia_maternidad_costo
    + new.licencia_paternidad_costo + new.licencia_fallecimiento_costo
    + new.comision_costo + new.vacaciones_costo;
  new.provision_cts_legal := round(v_base_beneficios*new.tasa_cts,6);
  new.provision_gratificacion_legal := round(v_base_beneficios*new.tasa_gratificacion,6);
  new.provision_vacaciones_legal := round(v_base_beneficios*coalesce(v_param.vacaciones_provision_tasa,0),6);
  new.cts_costo := case when v_modalidad='PRORRATEADA'
    then new.provision_cts_legal else 0 end;
  new.gratificacion_costo := case when v_modalidad='PRORRATEADA'
    then new.provision_gratificacion_legal else 0 end;
  new.bono_gratificacion_costo := round(new.gratificacion_costo*v_bono_grat_tasa,6);
  new.bono_beta_costo := case when v_regimen='AGRARIO_31110' and v_beta_modalidad='PRORRATEADA'
    then round((coalesce(new.horas_trabajadas,0)+
      coalesce(new.descanso_semanal,0)*(v_jornada/8.0)
      +coalesce(new.descanso_medico,0)+coalesce(new.teletrabajo,0)
      +coalesce(new.licencia_maternidad,0)+coalesce(new.licencia_paternidad,0)
      +coalesce(new.licencia_fallecimiento,0)+coalesce(new.comision,0)
      +coalesce(new.vacaciones,0))
      *new.costo_hora_rmv*new.tasa_bono_beta*
      case when v_jornada<4 then 1 else 8.0/v_jornada end,6)
    else 0 end;

  v_base_afecta := v_base_beneficios + new.horas_extras_25_costo
    + new.horas_extras_35_costo + new.horas_nocturnas_costo
    + coalesce(new.bono_cargo_costo,0)+coalesce(new.bono_labor_costo,0);
  new.ingreso_bruto := round(v_base_afecta + new.cts_costo + new.gratificacion_costo
    +new.bono_gratificacion_costo+new.bono_beta_costo
    +coalesce(new.bono_movilidad_costo,0),6);
  new.afecto := round(v_base_afecta,6);
  new.inafecto := round(new.ingreso_bruto-new.afecto,6);
  new.essalud_costo := round(new.afecto*v_essalud_tasa,6);

  new.onp_costo := case when v_pension='ONP'
    then round(new.afecto*new.tasa_onp,6) else 0 end;
  new.afp_costo := case when v_pension='AFP'
    then round(new.afecto*new.tasa_afp,6) else 0 end;
  new.afp_seguro_costo := case when v_pension='AFP'
    then round(new.afecto*new.tasa_afp_seguro,6) else 0 end;
  new.afp_comision_costo := case when v_pension='AFP'
    then round(new.afecto*new.tasa_afp_comision,6) else 0 end;
  new.descuento := round(new.onp_costo+new.afp_costo+new.afp_seguro_costo+new.afp_comision_costo,6);
  new.total_neto := round(new.ingreso_bruto-new.descuento,6);
  new.remuneracion_bruta := new.ingreso_bruto;
  new.deducciones_trabajador := new.descuento;
  new.neto_pagar := new.total_neto;
  new.aportes_empleador := new.essalud_costo;
  new.beneficios_provisionados := case when v_modalidad='SEMESTRAL'
    then new.provision_cts_legal+new.provision_gratificacion_legal
    else 0 end + new.provision_vacaciones_legal;
  new.costo_total_empresa := round(new.ingreso_bruto+new.aportes_empleador
    +new.beneficios_provisionados+coalesce(new.otros_costos_empresa,0),6);
  new.costo_empresa := new.costo_total_empresa;
  new.costo_total_usd := case when coalesce(new.tipo_cambio,0)>0
    then round(new.costo_total_empresa/new.tipo_cambio,6) else 0 end;
  new.updated_at := now();
  return new;
end;
$$;

-- El trigger separador heredado duplicaba algunos importes despues del calculo.
drop trigger if exists zzz_appgt_planilla_separar_costos_trigger
  on public."PLANILLA_TRABAJADORES_ZUMAC";
drop trigger if exists zz_appgt_planilla_costo_vacaciones_trigger
  on public."PLANILLA_TRABAJADORES_ZUMAC";

create or replace function public.appgt_generar_validaciones_planilla_v2(p_periodo uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_periodo public."PLANILLA_PERIODOS_APPGT"%rowtype;
  v_count integer;
begin
  select * into v_periodo from public."PLANILLA_PERIODOS_APPGT"
  where id=p_periodo and empresa_id=public.appgt_empresa_actual_id()
    and not eliminado and deleted_at is null;
  if not found then raise exception 'Periodo de planilla no encontrado.'; end if;
  delete from public."PLANILLA_VALIDACIONES_APPGT" where periodo_id=p_periodo;

  if date_trunc('month',v_periodo.fecha_inicio) <> date_trunc('month',v_periodo.fecha_fin)
     or not (
       (extract(day from v_periodo.fecha_inicio)=1 and extract(day from v_periodo.fecha_fin)=15)
       or (extract(day from v_periodo.fecha_inicio)=16 and
           v_periodo.fecha_fin=(date_trunc('month',v_periodo.fecha_fin)+interval '1 month - 1 day')::date)
       or (extract(day from v_periodo.fecha_inicio)=1 and
           v_periodo.fecha_fin=(date_trunc('month',v_periodo.fecha_fin)+interval '1 month - 1 day')::date)
     ) then
    insert into public."PLANILLA_VALIDACIONES_APPGT"
      (empresa_id,periodo_id,nivel,codigo,mensaje)
    values (v_periodo.empresa_id,p_periodo,'ERROR','PERIODO_INVALIDO',
       'El periodo debe ser mensual (1 al ultimo dia) o quincenal (1 al 15 / 16 al ultimo dia), dentro de un solo mes.');
  end if;

  if exists (select 1 from public."PLANILLA_PERIODOS_APPGT" x
    where x.empresa_id=v_periodo.empresa_id and x.id<>v_periodo.id
      and not x.eliminado and x.deleted_at is null
      and daterange(x.fecha_inicio,x.fecha_fin,'[]') &&
          daterange(v_periodo.fecha_inicio,v_periodo.fecha_fin,'[]')) then
    insert into public."PLANILLA_VALIDACIONES_APPGT"
      (empresa_id,periodo_id,nivel,codigo,mensaje)
    values (v_periodo.empresa_id,p_periodo,'ERROR','PERIODO_SUPERPUESTO',
      'El periodo se superpone con otro periodo de planilla.');
  end if;

  with workers as (
    select to_jsonb(p) data,
      public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']) dni
    from public."GH-REGISTRO_PERSONAL_PLANILLA" p
    where p.empresa_id=v_periodo.empresa_id
      and public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
    )='ACTIVO'
      and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),'-infinity'::date) <= v_periodo.fecha_fin
      and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']),'infinity'::date) >= v_periodo.fecha_inicio
  ), issues as (
    select dni, unnest(array_remove(array[
      case when dni is null then 'DNI' end,
      case when public.appgt_jsonb_date(data,array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']) is null then 'fecha de inicio de contrato' end,
      case when public.appgt_jsonb_text(data,array['REGIMEN_LABORAL_CODIGO']) is null then 'regimen laboral' end,
      case when public.appgt_jsonb_text(data,array['TIPO_REMUNERACION']) is null then 'tipo de remuneracion' end,
      case when public.appgt_jsonb_text(data,array['FRECUENCIA_PAGO']) is null then 'frecuencia de pago' end,
      case when public.appgt_jsonb_text(data,array['MODALIDAD_CTS_GRATIFICACION']) is null then 'modalidad de CTS/gratificacion' end,
      case when public.appgt_jsonb_text(data,array['MODALIDAD_BETA']) is null then 'modalidad de BETA' end,
      case when public.appgt_jsonb_numeric(data,array['Sueldo','SUELDO_MENSUAL','REMUNERACION'],0)<=0 then 'sueldo' end,
      case when public.appgt_jsonb_text(data,array['SISTEMA_PENSION_CODIGO']) is null then 'sistema pensionario' end,
      case when public.appgt_jsonb_numeric(data,array['HORAS_DIARIAS_PROMEDIO'],-1)<=0 then 'horas diarias promedio' end
    ],null)) issue from workers
  )
  insert into public."PLANILLA_VALIDACIONES_APPGT"
    (empresa_id,periodo_id,nivel,codigo,dni,mensaje)
  select v_periodo.empresa_id,p_periodo,'ERROR','DATO_LABORAL_FALTANTE',dni,
    'Falta configurar '||issue||' para el trabajador '||coalesce(dni,'sin DNI')||'.'
  from issues;

  insert into public."PLANILLA_VALIDACIONES_APPGT"
    (empresa_id,periodo_id,nivel,codigo,dni,mensaje)
  select v_periodo.empresa_id,p_periodo,'ERROR','REMUNERACION_MENOR_RMV',
    public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']),
    'La remuneracion es menor a la RMV aplicable a la jornada declarada.'
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  join lateral (select q.* from public."PLANILLA_PARAMETROS_LEGALES_APPGT" q
    where q.regimen_codigo=p."REGIMEN_LABORAL_CODIGO" and q.activo
      and v_periodo.fecha_fin>=q.vigente_desde
      and (q.vigente_hasta is null or v_periodo.fecha_inicio<=q.vigente_hasta)
    order by q.vigente_desde desc limit 1) q on true
  where p.empresa_id=v_periodo.empresa_id
    and public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
    )='ACTIVO'
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),'-infinity'::date)<=v_periodo.fecha_fin
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']),'infinity'::date)>=v_periodo.fecha_inicio
    and public.appgt_jsonb_numeric(to_jsonb(p),array['Sueldo','SUELDO_MENSUAL','REMUNERACION'],0)
      < q.rmv*case when coalesce(p."HORAS_DIARIAS_PROMEDIO",8)<4
        then p."HORAS_DIARIAS_PROMEDIO"/8.0 else 1 end;

  insert into public."PLANILLA_VALIDACIONES_APPGT"
    (empresa_id,periodo_id,nivel,codigo,dni,mensaje)
  select v_periodo.empresa_id,p_periodo,'ERROR','REGIMEN_GENERAL_NO_PRORRATEA',
    public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']),
    'El regimen general paga CTS y gratificacion en sus oportunidades legales; no admite prorrateo.'
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  where p.empresa_id=v_periodo.empresa_id
    and p."REGIMEN_LABORAL_CODIGO"='GENERAL_728'
    and p."MODALIDAD_CTS_GRATIFICACION"<>'SEMESTRAL'
    and public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
    )='ACTIVO'
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),'-infinity'::date)<=v_periodo.fecha_fin
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']),'infinity'::date)>=v_periodo.fecha_inicio;

  insert into public."PLANILLA_VALIDACIONES_APPGT"
    (empresa_id,periodo_id,nivel,codigo,dni,mensaje)
  select v_periodo.empresa_id,p_periodo,'ERROR','ADMINISTRATIVO_NO_AGRARIO',
    public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']),
    'El personal administrativo o de soporte tecnico esta excluido del regimen agrario por el articulo 2 de la Ley 31110.'
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  where p.empresa_id=v_periodo.empresa_id
    and p."REGIMEN_LABORAL_CODIGO"='AGRARIO_31110' and (
      p."ES_ADMINISTRATIVO_SOPORTE" or
      public.appgt_normalizar_clave(coalesce(p."GRUPO_COSTO",''))='ADMINISTRATIVO'
    ) and public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
    )='ACTIVO'
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),'-infinity'::date)<=v_periodo.fecha_fin
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']),'infinity'::date)>=v_periodo.fecha_inicio;

  insert into public."PLANILLA_VALIDACIONES_APPGT"
    (empresa_id,periodo_id,nivel,codigo,dni,mensaje)
  select v_periodo.empresa_id,p_periodo,'ERROR','AFP_INCOMPLETA',
    public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']),
    'Complete AFP y tipo de comision; no se aplicara ONP y AFP simultaneamente.'
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  where p.empresa_id=v_periodo.empresa_id
    and p."SISTEMA_PENSION_CODIGO"='AFP'
    and public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
    )='ACTIVO'
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),'-infinity'::date)<=v_periodo.fecha_fin
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']),'infinity'::date)>=v_periodo.fecha_inicio
    and (p."AFP_NOMBRE" is null or p."AFP_TIPO_COMISION" is null or not exists (
      select 1 from public."PLANILLA_TASAS_AFP_APPGT" a
      where a.afp_codigo=p."AFP_NOMBRE" and a.activo
        and v_periodo.fecha_inicio>=a.vigente_desde
        and (a.vigente_hasta is null or v_periodo.fecha_fin<=a.vigente_hasta)
    ));

  if exists (select 1 from public."GH-REGISTRO_PERSONAL_PLANILLA" p
      where p.empresa_id=v_periodo.empresa_id
        and p."REGIMEN_LABORAL_CODIGO"='AGRARIO_31110'
        and public.appgt_normalizar_clave(
          public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
        )='ACTIVO'
        and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),'-infinity'::date)<=v_periodo.fecha_fin
        and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']),'infinity'::date)>=v_periodo.fecha_inicio) and not exists (
      select 1 from public."PLANILLA_CONFIG_EMPRESA_APPGT" c
      where c.empresa_id=v_periodo.empresa_id and c.activo and c.aplica_ley_31110
        and nullif(btrim(c.sustento_aplicacion_ley_31110),'') is not null
    ) then
    insert into public."PLANILLA_VALIDACIONES_APPGT"
      (empresa_id,periodo_id,nivel,codigo,mensaje)
    values (v_periodo.empresa_id,p_periodo,'ERROR','LEY_31110_SIN_SUSTENTO',
      'La empresa no ha validado el sustento de su actividad comprendida en la Ley 31110.');
  end if;

  insert into public."PLANILLA_VALIDACIONES_APPGT"
    (empresa_id,periodo_id,nivel,codigo,dni,mensaje)
  select v_periodo.empresa_id,p_periodo,'ERROR','PARAMETRO_LEGAL_SIN_VIGENCIA',
    public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']),
    'No existe parametro legal vigente para '||p."REGIMEN_LABORAL_CODIGO"||
      ' en las fechas del periodo. Actualice la matriz legal con la norma publicada.'
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  where p.empresa_id=v_periodo.empresa_id
    and p."REGIMEN_LABORAL_CODIGO" is not null
    and public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
    )='ACTIVO'
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),'-infinity'::date)<=v_periodo.fecha_fin
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']),'infinity'::date)>=v_periodo.fecha_inicio
    and not exists (select 1 from public."PLANILLA_PARAMETROS_LEGALES_APPGT" q
      where q.regimen_codigo=p."REGIMEN_LABORAL_CODIGO" and q.activo
        and v_periodo.fecha_inicio>=q.vigente_desde
        and (q.vigente_hasta is null or v_periodo.fecha_fin<=q.vigente_hasta));

  insert into public."PLANILLA_VALIDACIONES_APPGT"
    (empresa_id,periodo_id,nivel,codigo,dni,mensaje)
  select v_periodo.empresa_id,p_periodo,'ERROR','SCTR_SIN_TASA',
    public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']),
    'El trabajador requiere SCTR y faltan las tasas contratadas de salud y/o pension.'
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  left join public."PLANILLA_CONFIG_EMPRESA_APPGT" c on c.empresa_id=v_periodo.empresa_id
  where p.empresa_id=v_periodo.empresa_id and p."REQUIERE_SCTR"
    and public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
    )='ACTIVO'
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),'-infinity'::date)<=v_periodo.fecha_fin
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']),'infinity'::date)>=v_periodo.fecha_inicio
    and (c.sctr_salud_tasa is null or c.sctr_pension_tasa is null);

  insert into public."PLANILLA_VALIDACIONES_APPGT"
    (empresa_id,periodo_id,nivel,codigo,dni,mensaje)
  select v_periodo.empresa_id,p_periodo,'ERROR','ELECCION_BENEFICIO_SIN_SUSTENTO',
    public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']),
    case when p."MODALIDAD_CTS_GRATIFICACION"='SEMESTRAL'
      then 'El pago semestral agrario de CTS/gratificacion no tiene eleccion escrita vigente.'
      else 'El prorrateo diario del BETA no tiene acuerdo escrito vigente.' end
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  where p.empresa_id=v_periodo.empresa_id
    and p."REGIMEN_LABORAL_CODIGO"='AGRARIO_31110'
    and public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
    )='ACTIVO'
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),'-infinity'::date)<=v_periodo.fecha_fin
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']),'infinity'::date)>=v_periodo.fecha_inicio
    and (
      (p."MODALIDAD_CTS_GRATIFICACION"='SEMESTRAL' and (
        p."FECHA_ELECCION_CTS_GRATIFICACION" is null or
        nullif(btrim(p."DOCUMENTO_ELECCION_CTS_GRATIFICACION"),'') is null
      )) or
      (p."MODALIDAD_BETA"='PRORRATEADA' and (
        p."FECHA_ACUERDO_BETA" is null or
        nullif(btrim(p."DOCUMENTO_ACUERDO_BETA"),'') is null
      ))
    );

  insert into public."PLANILLA_VALIDACIONES_APPGT"
    (empresa_id,periodo_id,nivel,codigo,dni,mensaje)
  select v_periodo.empresa_id,p_periodo,'ERROR','MODALIDAD_BENEFICIO_INCOMPATIBLE',
    public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']),
    'La modalidad de beneficios no corresponde al regimen laboral declarado.'
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  where p.empresa_id=v_periodo.empresa_id
    and public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
    )='ACTIVO'
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),'-infinity'::date)<=v_periodo.fecha_fin
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']),'infinity'::date)>=v_periodo.fecha_inicio
    and (
      (p."REGIMEN_LABORAL_CODIGO"='GENERAL_728' and p."MODALIDAD_BETA"<>'NO_APLICA') or
      (p."REGIMEN_LABORAL_CODIGO"='AGRARIO_31110' and
        p."MODALIDAD_BETA" not in ('MENSUAL','PRORRATEADA'))
    );

  insert into public."PLANILLA_VALIDACIONES_APPGT"
    (empresa_id,periodo_id,nivel,codigo,dni,mensaje)
  select distinct v_periodo.empresa_id,p_periodo,'ERROR','TAREO_NO_APROBADO',
    public.appgt_jsonb_text(to_jsonb(t),array['DNI','DOCUMENTO']),
    'Existe tareo sin aprobar dentro del periodo.'
  from public."GT-TAREO_PERSONAL" t
  where t.empresa_id=v_periodo.empresa_id
    and public.appgt_jsonb_date(to_jsonb(t),array['FECHA']) between v_periodo.fecha_inicio and v_periodo.fecha_fin
    and t."ESTADO_APROBACION" not in ('APROBADO','RECHAZADO','ANULADO')
    and not public.appgt_jsonb_bool(to_jsonb(t),array['eliminado'],false)
    and public.appgt_jsonb_text(to_jsonb(t),array['deleted_at']) is null;

  insert into public."PLANILLA_VALIDACIONES_APPGT"
    (empresa_id,periodo_id,nivel,codigo,dni,mensaje)
  select distinct v_periodo.empresa_id,p_periodo,'ERROR','ASISTENCIA_SIN_TAREO',
    public.appgt_jsonb_text(to_jsonb(a),array['DNI','DOCUMENTO']),
    'Hay asistencia sin tareo aprobado el '||to_char(
      public.appgt_jsonb_date(to_jsonb(a),array['FECHA','FECHA_INGRESO']),'DD/MM/YYYY')||'.'
  from public."GT-ASISTENCIA_PERSONAL" a
  where a.empresa_id=v_periodo.empresa_id
    and public.appgt_jsonb_date(to_jsonb(a),array['FECHA','FECHA_INGRESO'])
      between v_periodo.fecha_inicio and v_periodo.fecha_fin
    and not public.appgt_jsonb_bool(to_jsonb(a),array['eliminado'],false)
    and public.appgt_jsonb_text(to_jsonb(a),array['deleted_at']) is null
    and not exists (select 1 from public."GT-TAREO_PERSONAL" t
      where t.empresa_id=v_periodo.empresa_id
        and public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(t),array['DNI','DOCUMENTO']))
        =public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(a),array['DNI','DOCUMENTO']))
        and public.appgt_jsonb_date(to_jsonb(t),array['FECHA'])
          =public.appgt_jsonb_date(to_jsonb(a),array['FECHA','FECHA_INGRESO'])
        and t."ESTADO_APROBACION"='APROBADO'
        and not public.appgt_jsonb_bool(to_jsonb(t),array['eliminado'],false)
        and public.appgt_jsonb_text(to_jsonb(t),array['deleted_at']) is null);

  insert into public."PLANILLA_VALIDACIONES_APPGT"
    (empresa_id,periodo_id,nivel,codigo,dni,mensaje)
  select distinct v_periodo.empresa_id,p_periodo,'ERROR','TAREO_SIN_ASISTENCIA',
    public.appgt_jsonb_text(to_jsonb(t),array['DNI','DOCUMENTO']),
    'Hay tareo aprobado sin asistencia el '||to_char(
      public.appgt_jsonb_date(to_jsonb(t),array['FECHA']),'DD/MM/YYYY')||'.'
  from public."GT-TAREO_PERSONAL" t
  where t.empresa_id=v_periodo.empresa_id
    and public.appgt_jsonb_date(to_jsonb(t),array['FECHA'])
      between v_periodo.fecha_inicio and v_periodo.fecha_fin
    and t."ESTADO_APROBACION"='APROBADO'
    and not public.appgt_jsonb_bool(to_jsonb(t),array['eliminado'],false)
    and public.appgt_jsonb_text(to_jsonb(t),array['deleted_at']) is null
    and not exists (select 1 from public."GT-ASISTENCIA_PERSONAL" a
      where a.empresa_id=v_periodo.empresa_id
        and public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(a),array['DNI','DOCUMENTO']))
        =public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(t),array['DNI','DOCUMENTO']))
        and public.appgt_jsonb_date(to_jsonb(a),array['FECHA','FECHA_INGRESO'])
          =public.appgt_jsonb_date(to_jsonb(t),array['FECHA'])
        and not public.appgt_jsonb_bool(to_jsonb(a),array['eliminado'],false)
        and public.appgt_jsonb_text(to_jsonb(a),array['deleted_at']) is null);

  insert into public."PLANILLA_VALIDACIONES_APPGT"
    (empresa_id,periodo_id,nivel,codigo,dni,mensaje)
  select v_periodo.empresa_id,p_periodo,'ERROR','PERMISOS_SUPERPUESTOS',q1.dni,
    'Existen permisos/licencias aprobados superpuestos en el periodo.'
  from public."GH_PERMISOS_LICENCIAS_APPGT" q1
  join public."GH_PERMISOS_LICENCIAS_APPGT" q2 on q2.id>q1.id
    and q2.empresa_id=q1.empresa_id
    and public.appgt_normalizar_clave(q2.dni)=public.appgt_normalizar_clave(q1.dni)
    and daterange(q2.fecha_inicio,q2.fecha_fin,'[]') && daterange(q1.fecha_inicio,q1.fecha_fin,'[]')
  where q1.empresa_id=v_periodo.empresa_id
    and q1.estado='APROBADO' and q1."ESTADO_APROBACION"='APROBADO'
    and q2.estado='APROBADO' and q2."ESTADO_APROBACION"='APROBADO'
    and daterange(q1.fecha_inicio,q1.fecha_fin,'[]') &&
      daterange(v_periodo.fecha_inicio,v_periodo.fecha_fin,'[]');

  insert into public."PLANILLA_VALIDACIONES_APPGT"
    (empresa_id,periodo_id,nivel,codigo,dni,mensaje)
  select v_periodo.empresa_id,p_periodo,'ERROR','TRABAJADOR_SIN_CONTROL_DIARIO',
    public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']),
    'El trabajador activo no tiene asistencia, tareo ni permiso aprobado en todo el periodo.'
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  where p.empresa_id=v_periodo.empresa_id
    and public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
    )='ACTIVO'
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),'-infinity'::date)<=v_periodo.fecha_fin
    and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']),'infinity'::date)>=v_periodo.fecha_inicio
    and not exists (select 1 from public."GT-ASISTENCIA_PERSONAL" a
      where a.empresa_id=v_periodo.empresa_id
        and public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(a),array['DNI','DOCUMENTO']))
        =public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']))
        and public.appgt_jsonb_date(to_jsonb(a),array['FECHA','FECHA_INGRESO'])
          between v_periodo.fecha_inicio and v_periodo.fecha_fin
        and not public.appgt_jsonb_bool(to_jsonb(a),array['eliminado'],false))
    and not exists (select 1 from public."GT-TAREO_PERSONAL" t
      where t.empresa_id=v_periodo.empresa_id
        and public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(t),array['DNI','DOCUMENTO']))
        =public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']))
        and public.appgt_jsonb_date(to_jsonb(t),array['FECHA'])
          between v_periodo.fecha_inicio and v_periodo.fecha_fin
        and t."ESTADO_APROBACION"='APROBADO'
        and not public.appgt_jsonb_bool(to_jsonb(t),array['eliminado'],false))
    and not exists (select 1 from public."GH_PERMISOS_LICENCIAS_APPGT" q
      where q.empresa_id=v_periodo.empresa_id
        and public.appgt_normalizar_clave(q.dni)=public.appgt_normalizar_clave(
        public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']))
        and q.estado='APROBADO' and q."ESTADO_APROBACION"='APROBADO'
        and daterange(q.fecha_inicio,q.fecha_fin,'[]') &&
          daterange(v_periodo.fecha_inicio,v_periodo.fecha_fin,'[]'));

  select count(*) into v_count from public."PLANILLA_VALIDACIONES_APPGT"
  where periodo_id=p_periodo and nivel='ERROR' and not resuelto;
  return v_count;
end;
$$;

create or replace function public.appgt_exigir_planilla_valida_v2(p_periodo uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer;
  v_detail text;
begin
  v_count := public.appgt_generar_validaciones_planilla_v2(p_periodo);
  if v_count>0 then
    select string_agg(x.mensaje, E'\n- ') into v_detail
    from (select mensaje from public."PLANILLA_VALIDACIONES_APPGT"
      where periodo_id=p_periodo and nivel='ERROR' and not resuelto
      order by id limit 8) x;
    raise exception 'Planilla bloqueada: % validacion(es) pendiente(s).\n- %',v_count,v_detail;
  end if;
end;
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
  select * into v_periodo from public."PLANILLA_PERIODOS_APPGT"
  where id=p_periodo and empresa_id=public.appgt_empresa_actual_id();
  if not found then raise exception 'Periodo de planilla no encontrado.'; end if;
  v_desde:=case when v_periodo.fecha_fin=
    (date_trunc('month',v_periodo.fecha_fin)+interval '1 month - 1 day')::date
    then date_trunc('month',v_periodo.fecha_fin)::date else v_periodo.fecha_inicio end;

  update public."PLANILLA_TRABAJADORES_ZUMAC" set
    descanso_medico=0, licencia_maternidad=0, licencia_paternidad=0,
    licencia_fallecimiento=0, comision=0, permiso_sin_goce=0, vacaciones=0,
    teletrabajo=0, updated_at=now()
  where empresa_id=v_periodo.empresa_id
    and fecha between v_desde and v_periodo.fecha_fin
    and activo and not eliminado and deleted_at is null;

  with ranked as (
    select p.id_local,p.dni,p.fecha,
      row_number() over (partition by p.dni,p.fecha order by
        case when p.origen_clave='SIN_TAREO' then 0 else 1 end,
        p.origen_clave,p.id_local) rn,
      p.horas_trabajadas+p.horas_extras_25+p.horas_extras_35 horas_origen,
      coalesce(sum(p.horas_trabajadas+p.horas_extras_25+p.horas_extras_35) over (
        partition by p.dni,p.fecha order by
          case when p.origen_clave='SIN_TAREO' then 0 else 1 end,
          p.origen_clave,p.id_local
        rows between unbounded preceding and 1 preceding
      ),0) horas_previas,
      coalesce(w."HORAS_DIARIAS_PROMEDIO",8) jornada
    from public."PLANILLA_TRABAJADORES_ZUMAC" p
    left join lateral (
      select x."HORAS_DIARIAS_PROMEDIO"
      from public."GH-REGISTRO_PERSONAL_PLANILLA" x
      where x.empresa_id=v_periodo.empresa_id
        and public.appgt_normalizar_clave(
          public.appgt_jsonb_text(to_jsonb(x),array['DNI','DOCUMENTO'])
        )=public.appgt_normalizar_clave(p.dni)
      limit 1
    ) w on true
    where p.empresa_id=v_periodo.empresa_id
      and p.fecha between v_desde and v_periodo.fecha_fin
      and p.activo and not p.eliminado and p.deleted_at is null
  ), resolved as (
    select r.id_local,r.rn,r.horas_origen,r.horas_previas,r.jornada,
      q.tipo_permiso,q.con_goce_haber,
      case when q.id is null then 0
        when q.fecha_inicio=q.fecha_fin and q.hora_inicio is not null
          and q.hora_fin is not null then least(r.jornada,greatest(
            extract(epoch from (q.hora_fin-q.hora_inicio))/3600,0
          )) else r.jornada end horas
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
      greatest(
        least(coalesce(r.horas,0)+r.horas_previas+r.horas_origen,r.jornada)
          -least(coalesce(r.horas,0)+r.horas_previas,r.jornada),0
      ) horas_regulares_nuevas,
      greatest(
        least(coalesce(r.horas,0)+r.horas_previas+r.horas_origen,r.jornada+2)
          -greatest(coalesce(r.horas,0)+r.horas_previas,r.jornada),0
      ) horas_25_nuevas,
      greatest(
        coalesce(r.horas,0)+r.horas_previas+r.horas_origen
          -greatest(coalesce(r.horas,0)+r.horas_previas,r.jornada+2),0
      ) horas_35_nuevas
    from resolved r
  )
  update public."PLANILLA_TRABAJADORES_ZUMAC" p set
    horas_trabajadas=r.horas_regulares_nuevas,
    horas_extras_25=r.horas_25_nuevas,
    horas_extras_35=r.horas_35_nuevas,
    descanso_medico=case when r.rn=1 and r.tipo_permiso='DESCANSO MEDICO'
      then r.horas else 0 end,
    licencia_maternidad=case when r.rn=1 and r.tipo_permiso='LICENCIA DE MATERNIDAD'
      then r.horas else 0 end,
    licencia_paternidad=case when r.rn=1 and r.tipo_permiso='LICENCIA DE PATERNIDAD'
      then r.horas else 0 end,
    licencia_fallecimiento=case when r.rn=1 and r.tipo_permiso='LICENCIA POR FALLECIMIENTO'
      then r.horas else 0 end,
    comision=case when r.rn=1 and r.tipo_permiso='COMISION DE SERVICIO'
      then r.horas else 0 end,
    permiso_sin_goce=case when r.rn=1 and (r.tipo_permiso='PERMISO SIN GOCE'
      or not coalesce(r.con_goce_haber,true)) then r.horas else 0 end,
    vacaciones=case when r.rn=1 and r.tipo_permiso='VACACIONES'
      then r.horas else 0 end,
    updated_at=now()
  from reclassified r where p.id_local=r.id_local;
end;
$$;

create or replace function public.appgt_calcular_liquidacion_periodo_v2(p_periodo uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_periodo public."PLANILLA_PERIODOS_APPGT"%rowtype;
  v_config public."PLANILLA_CONFIG_EMPRESA_APPGT"%rowtype;
  w record;
  v_param record;
  v_afp record;
  v_desde date;
  v_contrato_inicio date;
  v_contrato_fin date;
  v_mes_inicio date;
  v_mes_fin date;
  v_dias numeric;
  v_dias_sin_goce numeric;
  v_dias_sin_goce_cts numeric;
  v_dias_elegibles numeric;
  v_dias_beta numeric;
  v_horas numeric;
  v_he25 numeric;
  v_he35 numeric;
  v_noct numeric;
  v_basico_diario numeric;
  v_descanso numeric;
  v_licencias numeric;
  v_he25_importe numeric;
  v_he35_importe numeric;
  v_noct_importe numeric;
  v_otros_afectos numeric;
  v_otros_inafectos numeric;
  v_basico numeric;
  v_asignacion numeric;
  v_base_beneficios numeric;
  v_cts numeric;
  v_grat numeric;
  v_bono_grat numeric;
  v_beta numeric;
  v_beta_factor numeric;
  v_base_afecta numeric;
  v_base_essalud numeric;
  v_base_essalud_previa numeric;
  v_bruto numeric;
  v_renta_quinta numeric;
  v_onp numeric;
  v_afp_aporte numeric;
  v_afp_seguro numeric;
  v_afp_comision numeric;
  v_quinta numeric;
  v_descuentos numeric;
  v_neto numeric;
  v_essalud_tasa numeric;
  v_bono_grat_tasa numeric;
  v_essalud numeric;
  v_sctr_salud numeric;
  v_sctr_pension numeric;
  v_prov_cts numeric;
  v_prov_grat numeric;
  v_prov_vac numeric;
  v_total_prov numeric;
  v_costo numeric;
  v_ytd_renta numeric;
  v_ytd_retencion numeric;
  v_retencion_deducible numeric;
  v_mes_renta numeric;
  v_proyeccion numeric;
  v_mensual_proyectable numeric;
  v_impuesto_anual numeric;
  v_divisor numeric;
  v_meses_grat integer;
  v_variable_promedio numeric;
  v_ultima_grat numeric;
  v_semestre_inicio date;
  v_semestre_fin date;
  v_rows integer := 0;
  v_es_fin_mes boolean;
  v_paga_remuneracion boolean;
begin
  select * into v_periodo from public."PLANILLA_PERIODOS_APPGT"
  where id=p_periodo and empresa_id=public.appgt_empresa_actual_id()
    and not eliminado and deleted_at is null;
  if not found then raise exception 'Periodo de planilla no encontrado.'; end if;
  select * into v_config from public."PLANILLA_CONFIG_EMPRESA_APPGT"
  where empresa_id=v_periodo.empresa_id and activo;
  v_mes_inicio := date_trunc('month',v_periodo.fecha_fin)::date;
  v_mes_fin := (v_mes_inicio+interval '1 month - 1 day')::date;
  v_es_fin_mes := v_periodo.fecha_fin=v_mes_fin;

  delete from public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT"
  where periodo_id=p_periodo;

  for w in
    select p.*,
      public.appgt_jsonb_text(to_jsonb(p),array['DNI','DOCUMENTO']) dni_canonico,
      public.appgt_jsonb_numeric(to_jsonb(p),array['Sueldo','SUELDO_MENSUAL','REMUNERACION'],0) sueldo,
      public.appgt_jsonb_bool(to_jsonb(p),array['Asignacion familiar','ASIGNACION_FAMILIAR'],false) asignacion,
      public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']) contrato_inicio,
      public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']) contrato_fin,
      concat_ws(' ',public.appgt_jsonb_text(to_jsonb(p),array['Nombres','NOMBRES']),
        public.appgt_jsonb_text(to_jsonb(p),array['Apellido_paterno','APELLIDO_PATERNO']),
        public.appgt_jsonb_text(to_jsonb(p),array['Apellido_materno','APELLIDO_MATERNO'])) trabajador_nombre
    from public."GH-REGISTRO_PERSONAL_PLANILLA" p
    where p.empresa_id=v_periodo.empresa_id
      and public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
    )='ACTIVO'
      and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),'-infinity'::date)<=v_periodo.fecha_fin
      and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']),'infinity'::date)>=v_periodo.fecha_inicio
      and (p."FRECUENCIA_PAGO"='QUINCENAL' or v_es_fin_mes or
        coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']),'infinity'::date)
          between v_periodo.fecha_inicio and v_periodo.fecha_fin or (
        extract(month from v_periodo.fecha_fin) in (5,7,11,12)
        and v_periodo.fecha_inicio<=make_date(extract(year from v_periodo.fecha_fin)::int,
          extract(month from v_periodo.fecha_fin)::int,15)
        and v_periodo.fecha_fin>=make_date(extract(year from v_periodo.fecha_fin)::int,
          extract(month from v_periodo.fecha_fin)::int,15)
      ))
  loop
    select * into v_param from public."PLANILLA_PARAMETROS_LEGALES_APPGT" q
    where q.regimen_codigo=w."REGIMEN_LABORAL_CODIGO" and q.activo
      and v_periodo.fecha_fin>=q.vigente_desde
      and (q.vigente_hasta is null or v_periodo.fecha_inicio<=q.vigente_hasta)
    order by q.vigente_desde desc limit 1;
    v_desde := case when w."FRECUENCIA_PAGO"='MENSUAL' then v_mes_inicio
      else v_periodo.fecha_inicio end;
    v_paga_remuneracion:=w."FRECUENCIA_PAGO"='QUINCENAL' or v_es_fin_mes
      or coalesce(w.contrato_fin,'infinity'::date)<=v_periodo.fecha_fin;
    v_contrato_inicio := greatest(v_desde,w.contrato_inicio);
    v_contrato_fin := least(v_periodo.fecha_fin,coalesce(w.contrato_fin,v_periodo.fecha_fin));
    v_dias := public.appgt_dias_base_30_v2(v_contrato_inicio,v_contrato_fin);

    select coalesce(sum(permiso_sin_goce),0)/8.0,
      coalesce(sum(horas_trabajadas),0),coalesce(sum(horas_extras_25),0),
      coalesce(sum(horas_extras_35),0),coalesce(sum(horas_nocturnas),0),
      coalesce(sum(basico_costo),0),coalesce(sum(descanso_semanal_costo),0),
      coalesce(sum(descanso_medico_costo+teletrabajo_costo+licencia_maternidad_costo+
        licencia_paternidad_costo+licencia_fallecimiento_costo+comision_costo+vacaciones_costo),0),
      coalesce(sum(horas_extras_25_costo),0),coalesce(sum(horas_extras_35_costo),0),
      coalesce(sum(horas_nocturnas_costo),0),
      coalesce(sum(coalesce(bono_cargo_costo,0)+coalesce(bono_labor_costo,0)),0),
      coalesce(sum(coalesce(bono_movilidad_costo,0)),0)
    into v_dias_sin_goce,v_horas,v_he25,v_he35,v_noct,v_basico_diario,
      v_descanso,v_licencias,v_he25_importe,v_he35_importe,v_noct_importe,
      v_otros_afectos,v_otros_inafectos
    from public."PLANILLA_TRABAJADORES_ZUMAC" d
    where d.empresa_id=v_periodo.empresa_id
      and public.appgt_normalizar_clave(d.dni)=public.appgt_normalizar_clave(w.dni_canonico)
      and d.fecha between v_desde and v_periodo.fecha_fin
      and d.activo and not d.eliminado and d.deleted_at is null;

    select count(*) into v_dias_elegibles from (
      select d.fecha from public."PLANILLA_TRABAJADORES_ZUMAC" d
      where d.empresa_id=v_periodo.empresa_id
        and public.appgt_normalizar_clave(d.dni)=public.appgt_normalizar_clave(w.dni_canonico)
        and d.fecha between v_desde and v_periodo.fecha_fin
        and d.activo and not d.eliminado and d.deleted_at is null
      group by d.fecha having sum(d.horas_trabajadas+d.descanso_semanal+d.descanso_medico+
        d.teletrabajo+d.licencia_maternidad+d.licencia_paternidad+
        d.licencia_fallecimiento+d.comision+d.vacaciones)>0
      union
      select f.fecha from public."PLANILLA_FERIADOS_APPGT" f
      where f.fecha between v_contrato_inicio and v_contrato_fin and f.activo and f.remunerado
        and (f.empresa_id is null or f.empresa_id=v_periodo.empresa_id)
    ) eligible;
    v_dias_beta:=v_dias_elegibles;
    if w."MODALIDAD_BETA"='MENSUAL' and v_es_fin_mes then
      select count(*) into v_dias_beta from (
        select d.fecha from public."PLANILLA_TRABAJADORES_ZUMAC" d
        where d.empresa_id=v_periodo.empresa_id
          and public.appgt_normalizar_clave(d.dni)=public.appgt_normalizar_clave(w.dni_canonico)
          and d.fecha between v_mes_inicio and v_periodo.fecha_fin
          and d.activo and not d.eliminado and d.deleted_at is null
        group by d.fecha having sum(d.horas_trabajadas+d.descanso_semanal+d.descanso_medico+
          d.teletrabajo+d.licencia_maternidad+d.licencia_paternidad+
          d.licencia_fallecimiento+d.comision+d.vacaciones)>0
        union
        select f.fecha from public."PLANILLA_FERIADOS_APPGT" f
        where f.fecha between greatest(v_mes_inicio,w.contrato_inicio)
          and least(v_mes_fin,coalesce(w.contrato_fin,v_mes_fin)) and f.activo and f.remunerado
          and (f.empresa_id is null or f.empresa_id=v_periodo.empresa_id)
      ) beta_days;
    end if;

    v_dias := greatest(v_dias-v_dias_sin_goce,0);
    v_asignacion := case when w.asignacion then round(v_param.rmv*
      v_param.asignacion_familiar_tasa * case
        when w."REGIMEN_LABORAL_CODIGO"='AGRARIO_31110' and w."TIPO_REMUNERACION"='JORNAL'
          then least(v_dias_elegibles,30)/30.0
        else v_dias/30.0 end,6) else 0 end;
    v_basico := case when w."TIPO_REMUNERACION"='MENSUAL'
      then round(w.sueldo*v_dias/30.0,6)
      else round(v_basico_diario+v_descanso+v_licencias,6) end;
    if not v_paga_remuneracion then
      v_dias:=0; v_dias_sin_goce:=0; v_horas:=0; v_he25:=0; v_he35:=0; v_noct:=0;
      v_basico:=0; v_asignacion:=0; v_descanso:=0; v_licencias:=0;
      v_he25_importe:=0; v_he35_importe:=0; v_noct_importe:=0;
      v_otros_afectos:=0; v_otros_inafectos:=0;
    end if;
    if w."TIPO_REMUNERACION"='MENSUAL' then
      v_descanso:=0; v_licencias:=0;
    end if;
    v_base_beneficios := v_basico+v_asignacion+v_otros_afectos;

    v_cts:=0; v_grat:=0; v_bono_grat:=0;
    if w."MODALIDAD_CTS_GRATIFICACION"='PRORRATEADA' then
      v_cts:=round(v_base_beneficios*v_param.cts_provision_tasa,6);
      v_grat:=round(v_base_beneficios*v_param.gratificacion_provision_tasa,6);
    else
      if extract(month from v_periodo.fecha_fin) in (7,12) and
         v_periodo.fecha_inicio<=make_date(extract(year from v_periodo.fecha_fin)::int,
           extract(month from v_periodo.fecha_fin)::int,15) and
         v_periodo.fecha_fin>=make_date(extract(year from v_periodo.fecha_fin)::int,
           extract(month from v_periodo.fecha_fin)::int,15) then
        v_semestre_inicio:=case when extract(month from v_periodo.fecha_fin)=7
          then make_date(extract(year from v_periodo.fecha_fin)::int,1,1)
          else make_date(extract(year from v_periodo.fecha_fin)::int,7,1) end;
        v_semestre_fin:=case when extract(month from v_periodo.fecha_fin)=7
          then make_date(extract(year from v_periodo.fecha_fin)::int,6,30)
          else make_date(extract(year from v_periodo.fecha_fin)::int,12,31) end;
        select count(*) into v_meses_grat from generate_series(
          v_semestre_inicio,v_semestre_fin,interval '1 month'
        ) m where w.contrato_inicio<=m::date
          and coalesce(w.contrato_fin,'infinity'::date)>=(m+interval '1 month - 1 day')::date;
        select case when count(*) filter (where x.importe>0)>=3
          then coalesce(sum(x.importe),0)/6.0 else 0 end
        into v_variable_promedio from (
          select date_trunc('month',d.fecha) mes,
            sum(d.horas_extras_25_costo+d.horas_extras_35_costo+
              d.horas_nocturnas_costo+coalesce(d.bono_cargo_costo,0)+
              coalesce(d.bono_labor_costo,0)) importe
          from public."PLANILLA_TRABAJADORES_ZUMAC" d
          where d.empresa_id=v_periodo.empresa_id
            and public.appgt_normalizar_clave(d.dni)=public.appgt_normalizar_clave(w.dni_canonico)
            and d.fecha between v_semestre_inicio and v_semestre_fin
            and d.activo and not d.eliminado and d.deleted_at is null
          group by date_trunc('month',d.fecha)
        ) x;
        v_grat:=round((w.sueldo+case when w.asignacion then
          v_param.rmv*v_param.asignacion_familiar_tasa else 0 end+
          coalesce(v_variable_promedio,0))*v_meses_grat/6.0,6);
      end if;

      if extract(month from v_periodo.fecha_fin) in (5,11) and
         v_periodo.fecha_inicio<=make_date(extract(year from v_periodo.fecha_fin)::int,
           extract(month from v_periodo.fecha_fin)::int,15) and
         v_periodo.fecha_fin>=make_date(extract(year from v_periodo.fecha_fin)::int,
           extract(month from v_periodo.fecha_fin)::int,15) then
        v_semestre_inicio:=case when extract(month from v_periodo.fecha_fin)=5
          then make_date(extract(year from v_periodo.fecha_fin)::int-1,11,1)
          else make_date(extract(year from v_periodo.fecha_fin)::int,5,1) end;
        v_semestre_fin:=case when extract(month from v_periodo.fecha_fin)=5
          then make_date(extract(year from v_periodo.fecha_fin)::int,4,30)
          else make_date(extract(year from v_periodo.fecha_fin)::int,10,31) end;
        select coalesce(sum(l.gratificacion_pagada),0) into v_ultima_grat
        from public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT" l
        join public."PLANILLA_PERIODOS_APPGT" pp on pp.id=l.periodo_id
        where l.empresa_id=v_periodo.empresa_id
          and public.appgt_normalizar_clave(l.dni)=public.appgt_normalizar_clave(w.dni_canonico)
          and pp.fecha_fin between v_semestre_inicio and v_semestre_fin;
        select case when count(*) filter (where x.importe>0)>=3
          then coalesce(sum(x.importe),0)/6.0 else 0 end
        into v_variable_promedio from (
          select date_trunc('month',d.fecha) mes,
            sum(d.horas_extras_25_costo+d.horas_extras_35_costo+
              d.horas_nocturnas_costo+coalesce(d.bono_cargo_costo,0)+
              coalesce(d.bono_labor_costo,0)) importe
          from public."PLANILLA_TRABAJADORES_ZUMAC" d
          where d.empresa_id=v_periodo.empresa_id
            and public.appgt_normalizar_clave(d.dni)=public.appgt_normalizar_clave(w.dni_canonico)
            and d.fecha between v_semestre_inicio and v_semestre_fin
            and d.activo and not d.eliminado and d.deleted_at is null
          group by date_trunc('month',d.fecha)
        ) x;
        select coalesce(sum(d.permiso_sin_goce),0)/
          greatest(coalesce(w."HORAS_DIARIAS_PROMEDIO",8),0.001)
        into v_dias_sin_goce_cts
        from public."PLANILLA_TRABAJADORES_ZUMAC" d
        where d.empresa_id=v_periodo.empresa_id
          and public.appgt_normalizar_clave(d.dni)=public.appgt_normalizar_clave(w.dni_canonico)
          and d.fecha between v_semestre_inicio and v_semestre_fin
          and d.activo and not d.eliminado and d.deleted_at is null;
        v_cts:=round((w.sueldo+case when w.asignacion then
          v_param.rmv*v_param.asignacion_familiar_tasa else 0 end+
          coalesce(v_variable_promedio,0)+coalesce(v_ultima_grat,0)/6.0)*
          greatest(public.appgt_dias_base_30_v2(
            greatest(w.contrato_inicio,v_semestre_inicio),
            least(coalesce(w.contrato_fin,v_semestre_fin),v_semestre_fin)
          )-coalesce(v_dias_sin_goce_cts,0),0)/360.0,6);
      end if;
    end if;

    v_essalud_tasa:=case when w."REGIMEN_LABORAL_CODIGO"='GENERAL_728'
      then v_param.essalud_general_tasa
      else coalesce(v_param.essalud_agrario_pequeno_tasa,
        v_param.essalud_agrario_grande_tasa,0) end;
    v_bono_grat_tasa:=case when v_config.tiene_eps
      then v_config.bono_gratificacion_eps_tasa
      else coalesce(v_param.essalud_general_tasa,0.09) end;
    v_bono_grat:=round(v_grat*v_bono_grat_tasa,6);

    v_beta_factor:=case when coalesce(w."HORAS_DIARIAS_PROMEDIO",8)<4
      then coalesce(w."HORAS_DIARIAS_PROMEDIO",8)/8.0 else 1 end;
    v_beta:=case when not v_paga_remuneracion then 0
      when w."REGIMEN_LABORAL_CODIGO"<>'AGRARIO_31110' then 0
      when w."MODALIDAD_BETA"='PRORRATEADA' then
        round(v_param.rmv*v_param.beta_tasa*least(v_dias_elegibles,30)/30.0*
          v_beta_factor,6)
      when w."MODALIDAD_BETA"='MENSUAL' and v_es_fin_mes then
        round(v_param.rmv*v_param.beta_tasa*least(v_dias_beta,30)/30.0*
          v_beta_factor,6)
      else 0 end;
    v_base_afecta:=round(v_basico+v_asignacion+v_he25_importe+v_he35_importe+
      v_noct_importe+v_otros_afectos,6);
    v_bruto:=round(v_base_afecta+v_beta+v_grat+v_bono_grat+
      v_otros_inafectos+
      case when w."MODALIDAD_CTS_GRATIFICACION"='PRORRATEADA' then v_cts else 0 end,6);
    v_renta_quinta:=round(v_base_afecta+v_beta+v_grat+v_bono_grat,6);

    v_onp:=0; v_afp_aporte:=0; v_afp_seguro:=0; v_afp_comision:=0;
    if w."SISTEMA_PENSION_CODIGO"='ONP' then
      v_onp:=round(v_base_afecta*v_param.onp_tasa,6);
    elsif w."SISTEMA_PENSION_CODIGO"='AFP' then
      select * into v_afp from public."PLANILLA_TASAS_AFP_APPGT" a
      where a.afp_codigo=w."AFP_NOMBRE" and a.activo
        and v_periodo.fecha_fin>=a.vigente_desde
        and (a.vigente_hasta is null or v_periodo.fecha_inicio<=a.vigente_hasta)
      order by a.vigente_desde desc limit 1;
      v_afp_aporte:=round(v_base_afecta*v_afp.aporte_obligatorio_tasa,6);
      v_afp_seguro:=round(v_base_afecta*v_afp.prima_seguro_tasa,6);
      v_afp_comision:=case when w."AFP_TIPO_COMISION"='FLUJO'
        then round(v_base_afecta*v_afp.comision_flujo_tasa,6) else 0 end;
    end if;

    v_quinta:=0;
    if v_es_fin_mes then
      select coalesce(sum(l.renta_quinta_categoria),0),coalesce(sum(l.retencion_quinta),0)
      into v_ytd_renta,v_ytd_retencion
      from public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT" l
      join public."PLANILLA_PERIODOS_APPGT" pp on pp.id=l.periodo_id
      where l.empresa_id=v_periodo.empresa_id
        and public.appgt_normalizar_clave(l.dni)=public.appgt_normalizar_clave(w.dni_canonico)
        and extract(year from pp.fecha_fin)=extract(year from v_periodo.fecha_fin)
        and pp.fecha_fin<v_periodo.fecha_inicio;
      v_ytd_renta:=v_ytd_renta+coalesce(w."RENTA_5TA_ACUMULADA_INICIAL",0);
      v_ytd_retencion:=v_ytd_retencion+coalesce(w."RETENCION_5TA_ACUMULADA_INICIAL",0);
      select coalesce(sum(l.renta_quinta_categoria),0) into v_mes_renta
      from public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT" l
      join public."PLANILLA_PERIODOS_APPGT" pp on pp.id=l.periodo_id
      where l.empresa_id=v_periodo.empresa_id
        and public.appgt_normalizar_clave(l.dni)=public.appgt_normalizar_clave(w.dni_canonico)
        and date_trunc('month',pp.fecha_fin)=date_trunc('month',v_periodo.fecha_fin)
        and pp.id<>p_periodo;
      v_mes_renta:=v_mes_renta+v_renta_quinta;
      v_mensual_proyectable:=greatest(v_mes_renta-v_grat-v_bono_grat,0);
      v_proyeccion:=v_ytd_renta+v_renta_quinta+
        v_mensual_proyectable*(12-extract(month from v_periodo.fecha_fin))+
        coalesce(w."INGRESOS_OTRO_EMPLEADOR_5TA_MENSUAL",0)
          *(13-extract(month from v_periodo.fecha_fin));
      if w."MODALIDAD_CTS_GRATIFICACION"='SEMESTRAL' then
        v_proyeccion:=v_proyeccion+(w.sueldo+case when w.asignacion then
          v_param.rmv*v_param.asignacion_familiar_tasa else 0 end)*
          (1+v_bono_grat_tasa)*case
          when extract(month from v_periodo.fecha_fin)<7 then 2
          when extract(month from v_periodo.fecha_fin)<12 then 1 else 0 end;
      end if;
      v_impuesto_anual:=public.appgt_impuesto_anual_quinta_v2(
        greatest(v_proyeccion-7*v_param.uit,0),v_param.uit
      );
      select coalesce(sum(l.retencion_quinta),0) into v_retencion_deducible
      from public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT" l
      join public."PLANILLA_PERIODOS_APPGT" pp on pp.id=l.periodo_id
      where l.empresa_id=v_periodo.empresa_id
        and public.appgt_normalizar_clave(l.dni)=public.appgt_normalizar_clave(w.dni_canonico)
        and extract(year from pp.fecha_fin)=extract(year from v_periodo.fecha_fin)
        and extract(month from pp.fecha_fin)<=case
          when extract(month from v_periodo.fecha_fin)=4 then 3
          when extract(month from v_periodo.fecha_fin) between 5 and 7 then 4
          when extract(month from v_periodo.fecha_fin)=8 then 7
          when extract(month from v_periodo.fecha_fin) between 9 and 11 then 8
          when extract(month from v_periodo.fecha_fin)=12 then 11
          else 0 end;
      v_retencion_deducible:=v_retencion_deducible+
        case when extract(month from v_periodo.fecha_fin)>3
          then coalesce(w."RETENCION_5TA_ACUMULADA_INICIAL",0) else 0 end;
      v_divisor:=case
        when extract(month from v_periodo.fecha_fin) between 1 and 3 then 12
        when extract(month from v_periodo.fecha_fin)=4 then 9
        when extract(month from v_periodo.fecha_fin) between 5 and 7 then 8
        when extract(month from v_periodo.fecha_fin)=8 then 5
        when extract(month from v_periodo.fecha_fin) between 9 and 11 then 4
        else 1 end;
      v_quinta:=round(greatest(v_impuesto_anual-v_retencion_deducible,0)/v_divisor,6);
    end if;

    v_descuentos:=round(v_onp+v_afp_aporte+v_afp_seguro+v_afp_comision+v_quinta,6);
    v_neto:=round(v_bruto-v_descuentos,6);
    select coalesce(sum(l.base_essalud),0) into v_base_essalud_previa
    from public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT" l
    join public."PLANILLA_PERIODOS_APPGT" pp on pp.id=l.periodo_id
    where l.empresa_id=v_periodo.empresa_id
      and public.appgt_normalizar_clave(l.dni)=public.appgt_normalizar_clave(w.dni_canonico)
      and date_trunc('month',pp.fecha_fin)=date_trunc('month',v_periodo.fecha_fin)
      and pp.id<>p_periodo;
    v_base_essalud:=case when v_base_afecta<=0 then 0
      when v_es_fin_mes or coalesce(w.contrato_fin,'infinity'::date)<=v_periodo.fecha_fin
      then greatest(v_base_afecta,v_param.rmv-v_base_essalud_previa)
      else v_base_afecta end;
    v_essalud:=round(v_base_essalud*v_essalud_tasa,6);
    v_sctr_salud:=case when w."REQUIERE_SCTR" then round(v_base_afecta*v_config.sctr_salud_tasa,6) else 0 end;
    v_sctr_pension:=case when w."REQUIERE_SCTR" then round(v_base_afecta*v_config.sctr_pension_tasa,6) else 0 end;
    v_prov_cts:=case when w."MODALIDAD_CTS_GRATIFICACION"='SEMESTRAL'
      and v_paga_remuneracion
      then round(v_base_beneficios*v_param.cts_provision_tasa,6) else 0 end;
    v_prov_grat:=case when w."MODALIDAD_CTS_GRATIFICACION"='SEMESTRAL'
      and v_paga_remuneracion
      then round(v_base_beneficios*v_param.gratificacion_provision_tasa*(1+v_bono_grat_tasa),6) else 0 end;
    v_prov_vac:=case when v_paga_remuneracion
      then round(v_base_beneficios*v_param.vacaciones_provision_tasa,6) else 0 end;
    v_total_prov:=v_prov_cts+v_prov_grat+v_prov_vac;
    v_costo:=round(v_bruto-
      case when w."MODALIDAD_CTS_GRATIFICACION"='SEMESTRAL' then v_grat+v_bono_grat else 0 end+
      v_essalud+v_sctr_salud+v_sctr_pension+v_total_prov,6);

    insert into public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT" (
      empresa_id,periodo_id,dni,trabajador,regimen_codigo,tipo_remuneracion,
      frecuencia_pago,modalidad_cts_gratificacion,modalidad_beta,sistema_pension,
      afp_nombre,afp_tipo_comision,sueldo_mensual,rmv,uit,dias_base_30,dias_sin_goce,
      horas_ordinarias,horas_extra_25,horas_extra_35,horas_nocturnas,
      remuneracion_basica,asignacion_familiar,descanso_semanal,
      horas_extra_25_importe,horas_extra_35_importe,nocturnidad_importe,
      licencias_pagadas,beta_pagado,cts_pagada,gratificacion_pagada,
      bono_extraordinario_gratificacion,otros_ingresos_afectos,
      otros_ingresos_inafectos,remuneracion_bruta,
      base_pension,base_essalud,renta_quinta_categoria,onp,afp_aporte,afp_seguro,
      afp_comision,retencion_quinta,total_descuentos,neto_pagar,deposito_cts,
      total_desembolso_trabajador,essalud_empleador,sctr_salud,sctr_pension,
      provision_cts,provision_gratificacion,provision_vacaciones,total_provisiones,
      costo_total_empresa,detalle_calculo
    ) values (
      v_periodo.empresa_id,p_periodo,w.dni_canonico,
      coalesce(nullif(btrim(w.trabajador_nombre),''),w.dni_canonico),
      w."REGIMEN_LABORAL_CODIGO",w."TIPO_REMUNERACION",w."FRECUENCIA_PAGO",
      w."MODALIDAD_CTS_GRATIFICACION",w."MODALIDAD_BETA",w."SISTEMA_PENSION_CODIGO",
      w."AFP_NOMBRE",w."AFP_TIPO_COMISION",w.sueldo,v_param.rmv,v_param.uit,
      v_dias,v_dias_sin_goce,v_horas,v_he25,v_he35,v_noct,v_basico,v_asignacion,
      v_descanso,v_he25_importe,v_he35_importe,v_noct_importe,v_licencias,v_beta,
       v_cts,v_grat,v_bono_grat,v_otros_afectos,v_otros_inafectos,v_bruto,
      v_base_afecta,v_base_essalud,v_renta_quinta,v_onp,v_afp_aporte,v_afp_seguro,
      v_afp_comision,v_quinta,v_descuentos,v_neto,
      case when w."MODALIDAD_CTS_GRATIFICACION"='SEMESTRAL' then v_cts else 0 end,
      v_neto+case when w."MODALIDAD_CTS_GRATIFICACION"='SEMESTRAL' then v_cts else 0 end,
      v_essalud,v_sctr_salud,v_sctr_pension,v_prov_cts,v_prov_grat,v_prov_vac,
      v_total_prov,v_costo,
      jsonb_build_object('version','LEGAL_V2','essalud_tasa',v_essalud_tasa,
        'bono_gratificacion_tasa',v_bono_grat_tasa,'quinta_proyeccion',v_proyeccion,
        'quinta_impuesto_anual',v_impuesto_anual,'fuente_parametro',v_param.fuente_legal)
    );
    v_rows:=v_rows+1;
  end loop;
  return v_rows;
end;
$$;

alter table public."PLANILLA_PERIODOS_APPGT"
  add column if not exists total_depositos_cts numeric(20,6) not null default 0,
  add column if not exists total_desembolso_trabajador numeric(20,6) not null default 0,
  add column if not exists cantidad_trabajadores integer not null default 0,
  add column if not exists motor_calculo text;

create or replace function public.appgt_planilla_periodo_totales_v2(p_periodo uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public."PLANILLA_PERIODOS_APPGT" p set
    total_bruto=x.bruto,
    total_descuentos_trabajador=x.descuentos,
    total_neto_pagar=x.neto,
    total_depositos_cts=x.cts,
    total_desembolso_trabajador=x.desembolso,
    total_aportes_empleador=x.aportes,
    total_beneficios_provisionados=x.provisiones,
    total_costo_empresa=x.costo,
    cantidad_trabajadores=x.trabajadores,
    motor_calculo='PERU_LEGAL_V2',updated_at=now()
  from (
    select coalesce(sum(remuneracion_bruta),0) bruto,
      coalesce(sum(total_descuentos),0) descuentos,
      coalesce(sum(neto_pagar),0) neto,
      coalesce(sum(deposito_cts),0) cts,
      coalesce(sum(total_desembolso_trabajador),0) desembolso,
      coalesce(sum(essalud_empleador+sctr_salud+sctr_pension),0) aportes,
      coalesce(sum(total_provisiones),0) provisiones,
      coalesce(sum(costo_total_empresa),0) costo,
      count(*)::integer trabajadores
    from public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT"
    where periodo_id=p_periodo
  ) x where p.id=p_periodo;
end;
$$;

-- Conserva el ciclo de permisos/auditoria anterior, pero antepone validaciones
-- legales y sustituye sus totales diarios por la liquidacion autoritativa.
do $$
begin
  if to_regprocedure('public.appgt_cambiar_estado_planilla_periodo_legacy_045(uuid,text,text)') is null
     and to_regprocedure('public.appgt_cambiar_estado_planilla_periodo_v1(uuid,text,text)') is not null then
    execute 'alter function public.appgt_cambiar_estado_planilla_periodo_v1(uuid,text,text) rename to appgt_cambiar_estado_planilla_periodo_legacy_045';
  end if;
end;
$$;

create or replace function public.appgt_cambiar_estado_planilla_periodo_v1(
  p_periodo_id uuid,
  p_accion text,
  p_motivo text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_periodo public."PLANILLA_PERIODOS_APPGT"%rowtype;
  v_accion text:=upper(btrim(p_accion));
  v_result jsonb;
  v_mes_inicio date;
  v_fuente_desde date;
begin
  select * into v_periodo from public."PLANILLA_PERIODOS_APPGT"
  where id=p_periodo_id and empresa_id=public.appgt_empresa_actual_id()
    and not eliminado and deleted_at is null;
  if not found then raise exception 'Periodo de planilla no encontrado.'; end if;

  if v_accion='CALCULAR' then
    perform public.appgt_exigir_planilla_valida_v2(p_periodo_id);
    v_mes_inicio:=date_trunc('month',v_periodo.fecha_fin)::date;
    if v_periodo.fecha_fin=(v_mes_inicio+interval '1 month - 1 day')::date then
      -- Garantiza el mes completo para trabajadores de pago mensual y BETA mensual.
      perform public.appgt_refrescar_planilla_zumac(v_mes_inicio,v_periodo.fecha_fin);
    end if;
    v_result:=public.appgt_cambiar_estado_planilla_periodo_legacy_045(
      p_periodo_id,p_accion,p_motivo
    );
    perform public.appgt_reconstruir_permisos_periodo_v2(p_periodo_id);
    perform public.appgt_calcular_liquidacion_periodo_v2(p_periodo_id);
    perform public.appgt_planilla_periodo_totales_v2(p_periodo_id);
    perform set_config('appgt.planilla_transition','1',true);
    update public."PLANILLA_PERIODOS_APPGT" set
      calculada_por=auth.uid(),calculada_at=clock_timestamp(),updated_at=now()
    where id=p_periodo_id;
  elsif v_accion in ('REVISAR','APROBAR','CERRAR') then
    if v_periodo.calculada_at is null then
      raise exception 'La planilla fue reabierta o no tiene un calculo vigente. Ejecute Calcular nuevamente.';
    end if;
    v_mes_inicio:=date_trunc('month',v_periodo.fecha_fin)::date;
    v_fuente_desde:=case when v_periodo.fecha_fin=
      (v_mes_inicio+interval '1 month - 1 day')::date
      then v_mes_inicio else v_periodo.fecha_inicio end;
    if exists (
      select 1 from public."GH-REGISTRO_PERSONAL_PLANILLA" p
      where p.empresa_id=v_periodo.empresa_id and p.updated_at>v_periodo.calculada_at
        and public.appgt_normalizar_clave(
          public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
        )='ACTIVO'
        and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']),'-infinity'::date)<=v_periodo.fecha_fin
        and coalesce(public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']),'infinity'::date)>=v_fuente_desde
    ) or exists (
      select 1 from public."GT-ASISTENCIA_PERSONAL" a
      where a.empresa_id=v_periodo.empresa_id and a.updated_at>v_periodo.calculada_at
        and public.appgt_jsonb_date(to_jsonb(a),array['FECHA','FECHA_INGRESO'])
          between v_fuente_desde and v_periodo.fecha_fin
    ) or exists (
      select 1 from public."GT-TAREO_PERSONAL" t
      where t.empresa_id=v_periodo.empresa_id and t.updated_at>v_periodo.calculada_at
        and public.appgt_jsonb_date(to_jsonb(t),array['FECHA'])
          between v_fuente_desde and v_periodo.fecha_fin
    ) or exists (
      select 1 from public."GH_PERMISOS_LICENCIAS_APPGT" q
      where q.empresa_id=v_periodo.empresa_id and q.updated_at>v_periodo.calculada_at
        and daterange(q.fecha_inicio,q.fecha_fin,'[]') &&
          daterange(v_fuente_desde,v_periodo.fecha_fin,'[]')
    ) or exists (
      select 1 from public."PLANILLA_TRABAJADORES_ZUMAC" d
      where d.empresa_id=v_periodo.empresa_id and d.updated_at>v_periodo.calculada_at
        and d.fecha between v_fuente_desde and v_periodo.fecha_fin
    ) then
      raise exception 'Asistencia, tareo, permisos o datos laborales cambiaron despues del ultimo calculo. Ejecute Calcular nuevamente.';
    end if;
    perform public.appgt_exigir_planilla_valida_v2(p_periodo_id);
    if not exists (select 1 from public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT"
      where periodo_id=p_periodo_id) then
      raise exception 'No existe liquidacion calculada para el periodo.';
    end if;
    perform public.appgt_planilla_periodo_totales_v2(p_periodo_id);
    v_result:=public.appgt_cambiar_estado_planilla_periodo_legacy_045(
      p_periodo_id,p_accion,p_motivo
    );
    perform public.appgt_planilla_periodo_totales_v2(p_periodo_id);
  elsif v_accion='REABRIR' then
    v_result:=public.appgt_cambiar_estado_planilla_periodo_legacy_045(
      p_periodo_id,p_accion,p_motivo
    );
    perform set_config('appgt.planilla_transition','1',true);
    update public."PLANILLA_PERIODOS_APPGT" set
      calculada_at=null,calculada_por=null,motor_calculo='REQUIERE_RECALCULO',updated_at=now()
    where id=p_periodo_id;
  else
    v_result:=public.appgt_cambiar_estado_planilla_periodo_legacy_045(
      p_periodo_id,p_accion,p_motivo
    );
  end if;
  select to_jsonb(p) into v_result from public."PLANILLA_PERIODOS_APPGT" p
  where p.id=p_periodo_id;
  return v_result;
end;
$$;

revoke all on function public.appgt_cambiar_estado_planilla_periodo_v1(uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.appgt_cambiar_estado_planilla_periodo_v1(uuid,text,text)
  to authenticated,service_role;
revoke all on function public.appgt_cambiar_estado_planilla_periodo_legacy_045(uuid,text,text)
  from public,anon,authenticated;
revoke all on function public.appgt_generar_validaciones_planilla_v2(uuid)
  from public,anon,authenticated;
revoke all on function public.appgt_exigir_planilla_valida_v2(uuid),
  public.appgt_reconstruir_permisos_periodo_v2(uuid),
  public.appgt_calcular_liquidacion_periodo_v2(uuid),
  public.appgt_planilla_periodo_totales_v2(uuid)
  from public,anon,authenticated;
grant execute on function public.appgt_generar_validaciones_planilla_v2(uuid)
  to authenticated,service_role;
grant execute on function public.appgt_exigir_planilla_valida_v2(uuid),
  public.appgt_reconstruir_permisos_periodo_v2(uuid),
  public.appgt_calcular_liquidacion_periodo_v2(uuid),
  public.appgt_planilla_periodo_totales_v2(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Catalogo visible en la aplicacion. Se retira la matriz heredada sin borrarla.
-- ---------------------------------------------------------------------------

update public."MATRIZ_FORMATOS_APPGT" set
  nombre='Costeo diario de planilla',
  capacidades=coalesce(capacidades,'{}'::jsonb)||'{"solo_lectura":true,"no_es_boleta":true}'::jsonb,
  updated_at=now()
where upper(coalesce(tabla_destino,''))='PLANILLA_TRABAJADORES_ZUMAC';

update public."MATRIZ_FORMATOS_APPGT" set
  nombre='Parametros heredados (no usar)',tabla_visible_app=false,activo=false,updated_at=now()
where upper(coalesce(tabla_destino,''))='MATRIZ_BENEFICIOS_SOCIALES';

do $$
declare
  f record;
  x record;
  v_suffix text;
begin
  for f in select distinct empresa_id,modulo_id,rubro_id
    from public."MATRIZ_FORMATOS_APPGT"
    where upper(coalesce(tabla_destino,''))='PLANILLA_PERIODOS_APPGT'
      and empresa_id is not null
  loop
    v_suffix:=substr(md5(f.empresa_id::text),1,10);
    for x in select * from (values
      ('gh_plan_config_'||v_suffix,'Configuracion legal de planilla','PLANILLA_CONFIG_EMPRESA_APPGT',1,'settings',false),
      ('gh_plan_liquidacion_'||v_suffix,'Liquidacion de planilla','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT',10,'payments',true),
      ('gh_plan_validaciones_'||v_suffix,'Validaciones de planilla','PLANILLA_VALIDACIONES_APPGT',11,'fact_check',true),
      ('gh_plan_parametros_'||v_suffix,'Parametros legales por vigencia','PLANILLA_PARAMETROS_LEGALES_APPGT',90,'gavel',true),
      ('gh_plan_afp_'||v_suffix,'Tasas AFP por vigencia','PLANILLA_TASAS_AFP_APPGT',91,'account_balance',true),
      ('gh_plan_feriados_'||v_suffix,'Feriados de planilla','PLANILLA_FERIADOS_APPGT',92,'event',false),
      ('gh_plan_elecciones_'||v_suffix,'Historial de elecciones de beneficios','PLANILLA_ELECCIONES_BENEFICIOS_APPGT',93,'history',true)
    ) y(id,nombre,tabla,orden,icono,solo_lectura)
    loop
      insert into public."MATRIZ_FORMATOS_APPGT" (
        id,empresa_id,modulo_id,nombre,tabla_destino,ruta_flutter,
        tabla_visible_app,orden,activo,rubro_id,auditable,icono,capacidades,
        created_at,updated_at,deleted_at,estado_sync,eliminado
      ) values (
        x.id,f.empresa_id,f.modulo_id,x.nombre,x.tabla,null,true,x.orden,true,
        f.rubro_id,true,x.icono,jsonb_build_object('solo_lectura',x.solo_lectura),
        now(),now(),null,'sincronizado',false
      ) on conflict (id) do update set nombre=excluded.nombre,
        tabla_destino=excluded.tabla_destino,tabla_visible_app=true,activo=true,
        orden=excluded.orden,icono=excluded.icono,capacidades=excluded.capacidades,
        deleted_at=null,eliminado=false,updated_at=now();

      insert into public."MATRIZ_FORMATO_TABLAS_APPGT" (
        id,empresa_id,formato_id,nombre,tabla_destino,orden,activo,
        rubro_id,auditable,icono,created_at,updated_at,deleted_at
      ) values (
        x.id||'_table',f.empresa_id,x.id,x.nombre,x.tabla,0,true,
        f.rubro_id,true,x.icono,now(),now(),null
      ) on conflict (id) do update set nombre=excluded.nombre,
        tabla_destino=excluded.tabla_destino,activo=true,deleted_at=null,updated_at=now();
    end loop;
  end loop;
end;
$$;

insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id,tabla_destino,campo,etiqueta,tipo,tipo_ui,id_campo_dropdown,
  requerido,visible,visible_tabla,editable,orden,activo,
  created_at,updated_at,estado_sync,eliminado
) values
  ('pl_w_regimen','GH-REGISTRO_PERSONAL_PLANILLA','REGIMEN_LABORAL_CODIGO','Regimen laboral','text','dropdown','[AGRARIO_31110;GENERAL_728]',true,true,true,true,40,true,now(),now(),'sincronizado',false),
  ('pl_w_tipo_rem','GH-REGISTRO_PERSONAL_PLANILLA','TIPO_REMUNERACION','Tipo de remuneracion','text','dropdown','[MENSUAL;JORNAL]',true,true,true,true,41,true,now(),now(),'sincronizado',false),
  ('pl_w_frecuencia','GH-REGISTRO_PERSONAL_PLANILLA','FRECUENCIA_PAGO','Frecuencia de pago','text','dropdown','[QUINCENAL;MENSUAL]',true,true,true,true,42,true,now(),now(),'sincronizado',false),
  ('pl_w_modalidad','GH-REGISTRO_PERSONAL_PLANILLA','MODALIDAD_CTS_GRATIFICACION','Pago CTS y gratificacion','text','dropdown','[PRORRATEADA;SEMESTRAL]',true,true,true,true,43,true,now(),now(),'sincronizado',false),
  ('pl_w_fecha_eleccion','GH-REGISTRO_PERSONAL_PLANILLA','FECHA_ELECCION_CTS_GRATIFICACION','Fecha de eleccion CTS/gratificacion','date','date',null,false,true,false,true,44,true,now(),now(),'sincronizado',false),
  ('pl_w_doc_eleccion','GH-REGISTRO_PERSONAL_PLANILLA','DOCUMENTO_ELECCION_CTS_GRATIFICACION','Documento de eleccion CTS/gratificacion','text','photo',null,false,true,false,true,45,true,now(),now(),'sincronizado',false),
  ('pl_w_beta','GH-REGISTRO_PERSONAL_PLANILLA','MODALIDAD_BETA','Pago BETA','text','dropdown','[MENSUAL;PRORRATEADA;NO_APLICA]',true,true,true,true,46,true,now(),now(),'sincronizado',false),
  ('pl_w_fecha_beta','GH-REGISTRO_PERSONAL_PLANILLA','FECHA_ACUERDO_BETA','Fecha de acuerdo BETA','date','date',null,false,true,false,true,47,true,now(),now(),'sincronizado',false),
  ('pl_w_doc_beta','GH-REGISTRO_PERSONAL_PLANILLA','DOCUMENTO_ACUERDO_BETA','Documento de acuerdo BETA','text','photo',null,false,true,false,true,48,true,now(),now(),'sincronizado',false),
  ('pl_w_pension','GH-REGISTRO_PERSONAL_PLANILLA','SISTEMA_PENSION_CODIGO','Sistema pensionario','text','dropdown','[ONP;AFP]',true,true,true,true,49,true,now(),now(),'sincronizado',false),
  ('pl_w_afp','GH-REGISTRO_PERSONAL_PLANILLA','AFP_NOMBRE','AFP','text','dropdown','[HABITAT;INTEGRA;PRIMA;PROFUTURO]',false,true,true,true,50,true,now(),now(),'sincronizado',false),
  ('pl_w_afp_tipo','GH-REGISTRO_PERSONAL_PLANILLA','AFP_TIPO_COMISION','Tipo de comision AFP','text','dropdown','[FLUJO;SALDO]',false,true,true,true,51,true,now(),now(),'sincronizado',false),
  ('pl_w_horas','GH-REGISTRO_PERSONAL_PLANILLA','HORAS_DIARIAS_PROMEDIO','Horas diarias promedio','numeric','number',null,true,true,true,true,52,true,now(),now(),'sincronizado',false),
  ('pl_w_admin','GH-REGISTRO_PERSONAL_PLANILLA','ES_ADMINISTRATIVO_SOPORTE','Es administrativo o soporte tecnico','boolean','switch',null,true,true,true,true,53,true,now(),now(),'sincronizado',false),
  ('pl_w_otro_emp','GH-REGISTRO_PERSONAL_PLANILLA','INGRESOS_OTRO_EMPLEADOR_5TA_MENSUAL','Ingreso mensual de otro empleador (5ta)','numeric','number',null,false,true,false,true,54,true,now(),now(),'sincronizado',false),
  ('pl_w_renta_ini','GH-REGISTRO_PERSONAL_PLANILLA','RENTA_5TA_ACUMULADA_INICIAL','Renta 5ta acumulada antes de Zumac','numeric','number',null,false,true,false,true,55,true,now(),now(),'sincronizado',false),
  ('pl_w_ret_ini','GH-REGISTRO_PERSONAL_PLANILLA','RETENCION_5TA_ACUMULADA_INICIAL','Retencion 5ta acumulada antes de Zumac','numeric','number',null,false,true,false,true,56,true,now(),now(),'sincronizado',false),
  ('pl_w_sctr','GH-REGISTRO_PERSONAL_PLANILLA','REQUIERE_SCTR','Requiere SCTR','boolean','switch',null,true,true,true,true,57,true,now(),now(),'sincronizado',false),

  ('pl_cfg_aplica','PLANILLA_CONFIG_EMPRESA_APPGT','aplica_ley_31110','Empresa comprendida en Ley 31110','boolean','switch',null,true,true,true,true,1,true,now(),now(),'sincronizado',false),
  ('pl_cfg_sustento','PLANILLA_CONFIG_EMPRESA_APPGT','sustento_aplicacion_ley_31110','Sustento de aplicacion Ley 31110','text','multiline',null,false,true,true,true,2,true,now(),now(),'sincronizado',false),
  ('pl_cfg_clase','PLANILLA_CONFIG_EMPRESA_APPGT','clasificacion_essalud_agrario','Clasificacion EsSalud agrario','text','dropdown','[PEQUENO;GRANDE]',false,true,true,true,3,true,now(),now(),'sincronizado',false),
  ('pl_cfg_trab','PLANILLA_CONFIG_EMPRESA_APPGT','trabajadores_agrarios_declarados_anterior','Trabajadores agrarios declarados en el ejercicio anterior','integer','number',null,false,true,true,true,4,true,now(),now(),'sincronizado',false),
  ('pl_cfg_ventas','PLANILLA_CONFIG_EMPRESA_APPGT','ventas_anuales_uit_anterior','Ventas del ejercicio anterior en UIT','numeric','number',null,false,true,true,true,5,true,now(),now(),'sincronizado',false),
  ('pl_cfg_eps','PLANILLA_CONFIG_EMPRESA_APPGT','tiene_eps','Tiene EPS','boolean','switch',null,true,true,true,true,6,true,now(),now(),'sincronizado',false),
  ('pl_cfg_eps_tasa','PLANILLA_CONFIG_EMPRESA_APPGT','bono_gratificacion_eps_tasa','Tasa legal fija bono gratificacion con EPS','numeric','number',null,true,true,true,false,7,true,now(),now(),'sincronizado',false),
  ('pl_cfg_sctr_s','PLANILLA_CONFIG_EMPRESA_APPGT','sctr_salud_tasa','Tasa SCTR salud contratada','numeric','number',null,false,true,true,true,8,true,now(),now(),'sincronizado',false),
  ('pl_cfg_sctr_p','PLANILLA_CONFIG_EMPRESA_APPGT','sctr_pension_tasa','Tasa SCTR pension contratada','numeric','number',null,false,true,true,true,9,true,now(),now(),'sincronizado',false),
  ('pl_cfg_resp','PLANILLA_CONFIG_EMPRESA_APPGT','responsable_legal','Responsable de validacion','text','text',null,false,true,true,true,10,true,now(),now(),'sincronizado',false),
  ('pl_cfg_valid','PLANILLA_CONFIG_EMPRESA_APPGT','validado_at','Validado el','datetime','readonly',null,false,true,true,false,11,true,now(),now(),'sincronizado',false),
  ('pl_cfg_obs','PLANILLA_CONFIG_EMPRESA_APPGT','observaciones','Observaciones','text','multiline',null,false,true,true,true,12,true,now(),now(),'sincronizado',false),

  ('pl_l_dni','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','dni','DNI','text','readonly',null,false,true,true,false,1,true,now(),now(),'sincronizado',false),
  ('pl_l_trab','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','trabajador','Trabajador','text','readonly',null,false,true,true,false,2,true,now(),now(),'sincronizado',false),
  ('pl_l_reg','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','regimen_codigo','Regimen','text','readonly',null,false,true,true,false,3,true,now(),now(),'sincronizado',false),
  ('pl_l_dias','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','dias_base_30','Dias base 30','numeric','number',null,false,true,true,false,4,true,now(),now(),'sincronizado',false),
  ('pl_l_basico','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','remuneracion_basica','Remuneracion basica','numeric','number',null,false,true,true,false,5,true,now(),now(),'sincronizado',false),
  ('pl_l_af','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','asignacion_familiar','Asignacion familiar','numeric','number',null,false,true,true,false,6,true,now(),now(),'sincronizado',false),
  ('pl_l_beta','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','beta_pagado','BETA','numeric','number',null,false,true,true,false,7,true,now(),now(),'sincronizado',false),
  ('pl_l_grat','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','gratificacion_pagada','Gratificacion pagada','numeric','number',null,false,true,true,false,8,true,now(),now(),'sincronizado',false),
  ('pl_l_cts','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','deposito_cts','Deposito CTS','numeric','number',null,false,true,true,false,9,true,now(),now(),'sincronizado',false),
  ('pl_l_bruto','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','remuneracion_bruta','Total ingresos del periodo','numeric','number',null,false,true,true,false,10,true,now(),now(),'sincronizado',false),
  ('pl_l_pension','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','base_pension','Base pensionaria','numeric','number',null,false,true,true,false,11,true,now(),now(),'sincronizado',false),
  ('pl_l_onp','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','onp','ONP','numeric','number',null,false,true,true,false,12,true,now(),now(),'sincronizado',false),
  ('pl_l_afp','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','afp_aporte','AFP aporte','numeric','number',null,false,true,true,false,13,true,now(),now(),'sincronizado',false),
  ('pl_l_quinta','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','retencion_quinta','Retencion quinta categoria','numeric','number',null,false,true,true,false,14,true,now(),now(),'sincronizado',false),
  ('pl_l_desc','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','total_descuentos','Total descuentos','numeric','number',null,false,true,true,false,15,true,now(),now(),'sincronizado',false),
  ('pl_l_neto','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','neto_pagar','Neto de remuneracion','numeric','number',null,false,true,true,false,16,true,now(),now(),'sincronizado',false),
  ('pl_l_desembolso','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','total_desembolso_trabajador','Desembolso total al trabajador','numeric','number',null,false,true,true,false,17,true,now(),now(),'sincronizado',false),
  ('pl_l_essalud','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','essalud_empleador','EsSalud empleador','numeric','number',null,false,true,true,false,18,true,now(),now(),'sincronizado',false),
  ('pl_l_prov','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','total_provisiones','Provisiones del periodo','numeric','number',null,false,true,true,false,19,true,now(),now(),'sincronizado',false),
  ('pl_l_costo','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','costo_total_empresa','Costo total empresa','numeric','number',null,false,true,true,false,20,true,now(),now(),'sincronizado',false),

  ('pl_v_nivel','PLANILLA_VALIDACIONES_APPGT','nivel','Nivel','text','readonly',null,false,true,true,false,1,true,now(),now(),'sincronizado',false),
  ('pl_v_codigo','PLANILLA_VALIDACIONES_APPGT','codigo','Codigo','text','readonly',null,false,true,true,false,2,true,now(),now(),'sincronizado',false),
  ('pl_v_dni','PLANILLA_VALIDACIONES_APPGT','dni','DNI','text','readonly',null,false,true,true,false,3,true,now(),now(),'sincronizado',false),
  ('pl_v_msg','PLANILLA_VALIDACIONES_APPGT','mensaje','Validacion','text','readonly',null,false,true,true,false,4,true,now(),now(),'sincronizado',false),
  ('pl_v_fecha','PLANILLA_VALIDACIONES_APPGT','generado_at','Generada el','datetime','readonly',null,false,true,true,false,5,true,now(),now(),'sincronizado',false),

  ('pl_p_cts','PLANILLA_PERIODOS_APPGT','total_depositos_cts','Total depositos CTS','numeric','number',null,false,false,true,false,17,true,now(),now(),'sincronizado',false),
  ('pl_p_desemb','PLANILLA_PERIODOS_APPGT','total_desembolso_trabajador','Desembolso total trabajadores','numeric','number',null,false,false,true,false,18,true,now(),now(),'sincronizado',false),
  ('pl_p_cant','PLANILLA_PERIODOS_APPGT','cantidad_trabajadores','Trabajadores liquidados','integer','number',null,false,false,true,false,19,true,now(),now(),'sincronizado',false),
  ('pl_p_motor','PLANILLA_PERIODOS_APPGT','motor_calculo','Motor de calculo','text','readonly',null,false,false,true,false,20,true,now(),now(),'sincronizado',false)
on conflict (tabla_destino,campo) do update set
  etiqueta=excluded.etiqueta,tipo=excluded.tipo,tipo_ui=excluded.tipo_ui,
  id_campo_dropdown=excluded.id_campo_dropdown,requerido=excluded.requerido,
  visible=excluded.visible,visible_tabla=excluded.visible_tabla,
  editable=excluded.editable,orden=excluded.orden,activo=true,
  eliminado=false,updated_at=now();

insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id,tabla_destino,campo,etiqueta,tipo,tipo_ui,id_campo_dropdown,
  requerido,visible,visible_tabla,editable,orden,activo,
  created_at,updated_at,estado_sync,eliminado
) values
  ('pl_par_reg','PLANILLA_PARAMETROS_LEGALES_APPGT','regimen_codigo','Regimen','text','dropdown','[AGRARIO_31110;GENERAL_728]',true,true,true,true,1,true,now(),now(),'sincronizado',false),
  ('pl_par_desde','PLANILLA_PARAMETROS_LEGALES_APPGT','vigente_desde','Vigente desde','date','date',null,true,true,true,true,2,true,now(),now(),'sincronizado',false),
  ('pl_par_hasta','PLANILLA_PARAMETROS_LEGALES_APPGT','vigente_hasta','Vigente hasta','date','date',null,false,true,true,true,3,true,now(),now(),'sincronizado',false),
  ('pl_par_rmv','PLANILLA_PARAMETROS_LEGALES_APPGT','rmv','RMV','numeric','number',null,true,true,true,true,4,true,now(),now(),'sincronizado',false),
  ('pl_par_uit','PLANILLA_PARAMETROS_LEGALES_APPGT','uit','UIT','numeric','number',null,true,true,true,true,5,true,now(),now(),'sincronizado',false),
  ('pl_par_af','PLANILLA_PARAMETROS_LEGALES_APPGT','asignacion_familiar_tasa','Tasa asignacion familiar','numeric','number',null,true,true,true,true,6,true,now(),now(),'sincronizado',false),
  ('pl_par_cts','PLANILLA_PARAMETROS_LEGALES_APPGT','cts_provision_tasa','Tasa provision CTS','numeric','number',null,true,true,true,true,7,true,now(),now(),'sincronizado',false),
  ('pl_par_grat','PLANILLA_PARAMETROS_LEGALES_APPGT','gratificacion_provision_tasa','Tasa provision gratificacion','numeric','number',null,true,true,true,true,8,true,now(),now(),'sincronizado',false),
  ('pl_par_vac','PLANILLA_PARAMETROS_LEGALES_APPGT','vacaciones_provision_tasa','Tasa provision vacaciones','numeric','number',null,true,true,true,true,9,true,now(),now(),'sincronizado',false),
  ('pl_par_beta','PLANILLA_PARAMETROS_LEGALES_APPGT','beta_tasa','Tasa BETA','numeric','number',null,true,true,true,true,10,true,now(),now(),'sincronizado',false),
  ('pl_par_noc','PLANILLA_PARAMETROS_LEGALES_APPGT','nocturnidad_tasa','Tasa nocturnidad','numeric','number',null,true,true,true,true,11,true,now(),now(),'sincronizado',false),
  ('pl_par_onp','PLANILLA_PARAMETROS_LEGALES_APPGT','onp_tasa','Tasa ONP','numeric','number',null,true,true,true,true,12,true,now(),now(),'sincronizado',false),
  ('pl_par_fuente','PLANILLA_PARAMETROS_LEGALES_APPGT','fuente_legal','Fuente legal','text','multiline',null,true,true,true,true,13,true,now(),now(),'sincronizado',false),

  ('pl_afp_nombre','PLANILLA_TASAS_AFP_APPGT','afp_codigo','AFP','text','dropdown','[HABITAT;INTEGRA;PRIMA;PROFUTURO]',true,true,true,true,1,true,now(),now(),'sincronizado',false),
  ('pl_afp_desde','PLANILLA_TASAS_AFP_APPGT','vigente_desde','Vigente desde','date','date',null,true,true,true,true,2,true,now(),now(),'sincronizado',false),
  ('pl_afp_hasta','PLANILLA_TASAS_AFP_APPGT','vigente_hasta','Vigente hasta','date','date',null,false,true,true,true,3,true,now(),now(),'sincronizado',false),
  ('pl_afp_aporte','PLANILLA_TASAS_AFP_APPGT','aporte_obligatorio_tasa','Aporte obligatorio','numeric','number',null,true,true,true,true,4,true,now(),now(),'sincronizado',false),
  ('pl_afp_seguro','PLANILLA_TASAS_AFP_APPGT','prima_seguro_tasa','Prima de seguro','numeric','number',null,true,true,true,true,5,true,now(),now(),'sincronizado',false),
  ('pl_afp_flujo','PLANILLA_TASAS_AFP_APPGT','comision_flujo_tasa','Comision sobre flujo','numeric','number',null,true,true,true,true,6,true,now(),now(),'sincronizado',false),
  ('pl_afp_saldo','PLANILLA_TASAS_AFP_APPGT','comision_saldo_anual_tasa','Comision anual sobre saldo','numeric','number',null,true,true,true,true,7,true,now(),now(),'sincronizado',false),

  ('pl_fer_fecha','PLANILLA_FERIADOS_APPGT','fecha','Fecha','date','date',null,true,true,true,true,1,true,now(),now(),'sincronizado',false),
  ('pl_fer_nombre','PLANILLA_FERIADOS_APPGT','nombre','Feriado','text','text',null,true,true,true,true,2,true,now(),now(),'sincronizado',false),
  ('pl_fer_ambito','PLANILLA_FERIADOS_APPGT','ambito','Ambito','text','dropdown','[NACIONAL;REGIONAL;LOCAL]',true,true,true,true,3,true,now(),now(),'sincronizado',false),
  ('pl_fer_rem','PLANILLA_FERIADOS_APPGT','remunerado','Remunerado','boolean','switch',null,true,true,true,true,4,true,now(),now(),'sincronizado',false),
  ('pl_fer_act','PLANILLA_FERIADOS_APPGT','activo','Activo','boolean','switch',null,true,true,true,true,5,true,now(),now(),'sincronizado',false),

  ('pl_e_dni','PLANILLA_ELECCIONES_BENEFICIOS_APPGT','dni','DNI','text','readonly',null,false,true,true,false,1,true,now(),now(),'sincronizado',false),
  ('pl_e_con','PLANILLA_ELECCIONES_BENEFICIOS_APPGT','concepto','Concepto','text','readonly',null,false,true,true,false,2,true,now(),now(),'sincronizado',false),
  ('pl_e_ant','PLANILLA_ELECCIONES_BENEFICIOS_APPGT','modalidad_anterior','Modalidad anterior','text','readonly',null,false,true,true,false,3,true,now(),now(),'sincronizado',false),
  ('pl_e_nueva','PLANILLA_ELECCIONES_BENEFICIOS_APPGT','modalidad_nueva','Modalidad nueva','text','readonly',null,false,true,true,false,4,true,now(),now(),'sincronizado',false),
  ('pl_e_desde','PLANILLA_ELECCIONES_BENEFICIOS_APPGT','vigente_desde','Vigente desde','date','readonly',null,false,true,true,false,5,true,now(),now(),'sincronizado',false),
  ('pl_e_doc','PLANILLA_ELECCIONES_BENEFICIOS_APPGT','documento_sustento','Documento','text','readonly',null,false,true,true,false,6,true,now(),now(),'sincronizado',false)
on conflict (tabla_destino,campo) do update set
  etiqueta=excluded.etiqueta,tipo=excluded.tipo,tipo_ui=excluded.tipo_ui,
  id_campo_dropdown=excluded.id_campo_dropdown,requerido=excluded.requerido,
  visible=excluded.visible,visible_tabla=excluded.visible_tabla,
  editable=excluded.editable,orden=excluded.orden,activo=true,
  eliminado=false,updated_at=now();

update public."MATRIZ_CAMPOS_FORMATO_APPGT" set editable=false,updated_at=now()
where tabla_destino in (
  'PLANILLA_PARAMETROS_LEGALES_APPGT','PLANILLA_TASAS_AFP_APPGT'
);

-- Permisos de lectura heredados del ciclo de planilla. La escritura de la
-- configuracion legal queda ademas protegida por RLS para ADMIN/GESTOR.
with access_source as (
  select p.* from public."PERMISOS_DE_USUARIOS_APPGT" p
  where upper(coalesce(p.tabla_destino,''))='PLANILLA_PERIODOS_APPGT'
    and p.user_id is not null and p.activo and not p.eliminado
), targets as (
  select f.empresa_id,f.id formato_id,f.tabla_destino,f.modulo_id,m.seccion
  from public."MATRIZ_FORMATOS_APPGT" f
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id=f.empresa_id and m.id=f.modulo_id
  where f.tabla_destino in (
    'PLANILLA_CONFIG_EMPRESA_APPGT','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT',
    'PLANILLA_VALIDACIONES_APPGT','PLANILLA_PARAMETROS_LEGALES_APPGT',
    'PLANILLA_TASAS_AFP_APPGT','PLANILLA_FERIADOS_APPGT',
    'PLANILLA_ELECCIONES_BENEFICIOS_APPGT'
  ) and f.activo and not f.eliminado
)
insert into public."PERMISOS_DE_USUARIOS_APPGT" (
  empresa_id,user_id,seccion,modulo,formato,tabla_destino,
  can_view,can_insert,can_update,can_delete,can_export,can_import,
  can_review,can_approve,activo,created_at,updated_at,estado_sync,eliminado
)
select s.empresa_id,s.user_id,t.seccion,t.modulo_id,t.formato_id,t.tabla_destino,
  s.can_view,
  case when t.tabla_destino in ('PLANILLA_LIQUIDACION_TRABAJADOR_APPGT',
    'PLANILLA_VALIDACIONES_APPGT','PLANILLA_ELECCIONES_BENEFICIOS_APPGT',
    'PLANILLA_PARAMETROS_LEGALES_APPGT','PLANILLA_TASAS_AFP_APPGT') then false else s.can_insert end,
  case when t.tabla_destino in ('PLANILLA_LIQUIDACION_TRABAJADOR_APPGT',
    'PLANILLA_VALIDACIONES_APPGT','PLANILLA_ELECCIONES_BENEFICIOS_APPGT',
    'PLANILLA_PARAMETROS_LEGALES_APPGT','PLANILLA_TASAS_AFP_APPGT') then false else s.can_update end,
  false,s.can_export,false,s.can_review,s.can_approve,true,now(),now(),'sincronizado',false
from access_source s join targets t on t.empresa_id=s.empresa_id
on conflict (user_id,modulo,formato) do update set
  tabla_destino=excluded.tabla_destino,can_view=excluded.can_view,
  can_insert=excluded.can_insert,can_update=excluded.can_update,
  can_delete=false,can_export=excluded.can_export,can_import=false,
  can_review=excluded.can_review,can_approve=excluded.can_approve,
  activo=true,eliminado=false,updated_at=now();

alter table public."PLANILLA_CONFIG_EMPRESA_APPGT" enable row level security;
alter table public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT" enable row level security;
alter table public."PLANILLA_VALIDACIONES_APPGT" enable row level security;
alter table public."PLANILLA_PARAMETROS_LEGALES_APPGT" enable row level security;
alter table public."PLANILLA_TASAS_AFP_APPGT" enable row level security;
alter table public."PLANILLA_FERIADOS_APPGT" enable row level security;
alter table public."PLANILLA_ELECCIONES_BENEFICIOS_APPGT" enable row level security;

drop policy if exists planilla_config_select_v2 on public."PLANILLA_CONFIG_EMPRESA_APPGT";
create policy planilla_config_select_v2 on public."PLANILLA_CONFIG_EMPRESA_APPGT"
for select to authenticated using (
  empresa_id=public.appgt_empresa_actual_id()
  and public.appgt_can_view_table('PLANILLA_CONFIG_EMPRESA_APPGT')
);
drop policy if exists planilla_config_write_v2 on public."PLANILLA_CONFIG_EMPRESA_APPGT";
create policy planilla_config_write_v2 on public."PLANILLA_CONFIG_EMPRESA_APPGT"
for all to authenticated using (public.appgt_puede_gestionar_configuracion(empresa_id))
with check (public.appgt_puede_gestionar_configuracion(empresa_id));

drop policy if exists planilla_liquidacion_select_v2 on public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT";
create policy planilla_liquidacion_select_v2 on public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT"
for select to authenticated using (
  empresa_id=public.appgt_empresa_actual_id()
  and public.appgt_can_view_table('PLANILLA_LIQUIDACION_TRABAJADOR_APPGT')
);
drop policy if exists planilla_validaciones_select_v2 on public."PLANILLA_VALIDACIONES_APPGT";
create policy planilla_validaciones_select_v2 on public."PLANILLA_VALIDACIONES_APPGT"
for select to authenticated using (
  empresa_id=public.appgt_empresa_actual_id()
  and public.appgt_can_view_table('PLANILLA_VALIDACIONES_APPGT')
);
drop policy if exists planilla_elecciones_select_v2 on public."PLANILLA_ELECCIONES_BENEFICIOS_APPGT";
create policy planilla_elecciones_select_v2 on public."PLANILLA_ELECCIONES_BENEFICIOS_APPGT"
for select to authenticated using (
  empresa_id=public.appgt_empresa_actual_id()
  and public.appgt_can_view_table('PLANILLA_ELECCIONES_BENEFICIOS_APPGT')
);

drop policy if exists planilla_parametros_select_v2 on public."PLANILLA_PARAMETROS_LEGALES_APPGT";
create policy planilla_parametros_select_v2 on public."PLANILLA_PARAMETROS_LEGALES_APPGT"
for select to authenticated using (
  public.appgt_can_view_table('PLANILLA_PARAMETROS_LEGALES_APPGT')
);
drop policy if exists planilla_parametros_write_v2 on public."PLANILLA_PARAMETROS_LEGALES_APPGT";

drop policy if exists planilla_afp_select_v2 on public."PLANILLA_TASAS_AFP_APPGT";
create policy planilla_afp_select_v2 on public."PLANILLA_TASAS_AFP_APPGT"
for select to authenticated using (
  public.appgt_can_view_table('PLANILLA_TASAS_AFP_APPGT')
);
drop policy if exists planilla_afp_write_v2 on public."PLANILLA_TASAS_AFP_APPGT";

drop policy if exists planilla_feriados_select_v2 on public."PLANILLA_FERIADOS_APPGT";
create policy planilla_feriados_select_v2 on public."PLANILLA_FERIADOS_APPGT"
for select to authenticated using (
  (empresa_id is null or empresa_id=public.appgt_empresa_actual_id())
  and public.appgt_can_view_table('PLANILLA_FERIADOS_APPGT')
);
drop policy if exists planilla_feriados_write_v2 on public."PLANILLA_FERIADOS_APPGT";
create policy planilla_feriados_write_v2 on public."PLANILLA_FERIADOS_APPGT"
for all to authenticated using (
  empresa_id=public.appgt_empresa_actual_id()
  and public.appgt_puede_gestionar_configuracion(empresa_id)
) with check (
  empresa_id=public.appgt_empresa_actual_id()
  and public.appgt_puede_gestionar_configuracion(empresa_id)
);

grant select,insert,update on public."PLANILLA_CONFIG_EMPRESA_APPGT" to authenticated;
grant select on public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT",
  public."PLANILLA_VALIDACIONES_APPGT",
  public."PLANILLA_ELECCIONES_BENEFICIOS_APPGT" to authenticated;
revoke insert,update,delete on public."PLANILLA_PARAMETROS_LEGALES_APPGT",
  public."PLANILLA_TASAS_AFP_APPGT" from authenticated;
grant select on public."PLANILLA_PARAMETROS_LEGALES_APPGT",
  public."PLANILLA_TASAS_AFP_APPGT" to authenticated;
grant select,insert,update,delete on public."PLANILLA_FERIADOS_APPGT" to authenticated;
grant all on public."PLANILLA_CONFIG_EMPRESA_APPGT",
  public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT",
  public."PLANILLA_VALIDACIONES_APPGT",
  public."PLANILLA_PARAMETROS_LEGALES_APPGT",
  public."PLANILLA_TASAS_AFP_APPGT",public."PLANILLA_FERIADOS_APPGT",
  public."PLANILLA_ELECCIONES_BENEFICIOS_APPGT" to service_role;
grant usage,select on sequence public."PLANILLA_VALIDACIONES_APPGT_id_seq"
  to authenticated,service_role;

-- Pruebas de humo deterministas; una regresion aborta toda la migracion.
do $$
begin
  if public.appgt_dias_base_30_v2(date '2026-02-01',date '2026-02-28')<>30 then
    raise exception 'Prueba base 30: febrero completo debe equivaler a 30 dias.';
  end if;
  if public.appgt_dias_base_30_v2(date '2026-07-16',date '2026-07-31')<>15 then
    raise exception 'Prueba base 30: segunda quincena debe equivaler a 15 dias.';
  end if;
  if abs(public.appgt_impuesto_anual_quinta_v2(27500,5500)-2200)>0.001 then
    raise exception 'Prueba quinta categoria: primer tramo de 5 UIT incorrecto.';
  end if;
  if exists (
    select 1 from public."PLANILLA_PARAMETROS_LEGALES_APPGT" a
    join public."PLANILLA_PARAMETROS_LEGALES_APPGT" b
      on b.id>a.id and b.regimen_codigo=a.regimen_codigo and a.activo and b.activo
      and daterange(a.vigente_desde,coalesce(a.vigente_hasta,'infinity'::date),'[]') &&
          daterange(b.vigente_desde,coalesce(b.vigente_hasta,'infinity'::date),'[]')
  ) then
    raise exception 'Existen vigencias legales superpuestas para un mismo regimen.';
  end if;
end;
$$;

commit;
