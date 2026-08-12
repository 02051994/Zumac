begin;

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Datos empresariales usados como instantanea en documentos laborales.
-- ---------------------------------------------------------------------------

alter table public."EMPRESAS_APPGT"
  add column if not exists ruc text,
  add column if not exists representante_legal text,
  add column if not exists representante_cargo text,
  add column if not exists ciudad_emision text not null default 'CHICLAYO',
  add column if not exists moneda_base text not null default 'PEN';

-- ---------------------------------------------------------------------------
-- Catalogos y operaciones nuevas de Gestion Humana.
-- ---------------------------------------------------------------------------

create table if not exists public."GH_CAMPANAS_LABORALES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  codigo text not null,
  nombre text not null,
  fecha_inicio date not null,
  fecha_fin date not null,
  activa boolean not null default true,
  es_predeterminada boolean not null default false,
  created_by uuid default auth.uid() references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  unique (empresa_id, codigo),
  check (fecha_fin >= fecha_inicio)
);

create unique index if not exists gh_campanas_predeterminada_uq
  on public."GH_CAMPANAS_LABORALES_APPGT" (empresa_id)
  where es_predeterminada and activa and not eliminado and deleted_at is null;

create table if not exists public."FIN_TIPOS_CAMBIO_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  fecha date not null,
  moneda_origen text not null default 'USD',
  moneda_destino text not null default 'PEN',
  tipo_cambio numeric(18,6) not null check (tipo_cambio > 0),
  fuente text,
  created_by uuid default auth.uid() references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  unique (empresa_id, fecha, moneda_origen, moneda_destino)
);

create table if not exists public."GT_INGRESO_MOVILIDADES_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null default public.appgt_empresa_actual_id()
    references public."EMPRESAS_APPGT"(id) on delete cascade,
  fecha date not null default current_date,
  hora_ingreso time not null default localtime,
  hora_salida time,
  placa text not null,
  movilidad_codigo text,
  proveedor text,
  conductor_dni text not null,
  conductor_nombre text not null,
  licencia_conducir text,
  licencia_vigencia date,
  documento_conductor text,
  documento_vehiculo text,
  soat_vigencia date,
  revision_tecnica_vigencia date,
  capacidad integer check (capacidad is null or capacidad > 0),
  cantidad_personas integer not null default 0 check (cantidad_personas >= 0),
  estado text not null default 'ADMITIDA' check (estado in (
    'BORRADOR','ADMITIDA','RECHAZADA','CERRADA','ANULADA'
  )),
  observaciones text,
  registrado_por uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  unique (empresa_id, fecha, placa, hora_ingreso)
);

create index if not exists gt_ingreso_movilidad_fecha_placa_idx
  on public."GT_INGRESO_MOVILIDADES_APPGT" (empresa_id, fecha desc, placa)
  where not eliminado and deleted_at is null;

create table if not exists public."GH_SANCIONES_PERSONAL_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null default public.appgt_empresa_actual_id()
    references public."EMPRESAS_APPGT"(id) on delete cascade,
  numero_sancion text not null,
  dni text not null,
  trabajador text not null,
  tipo_sancion text not null check (tipo_sancion in (
    'AMONESTACION VERBAL','AMONESTACION ESCRITA','SUSPENSION DE LABORES','OTRA'
  )),
  fecha_inicio date not null,
  fecha_fin date not null,
  bloquea_asistencia boolean not null default false,
  motivo text not null,
  documento_sustento text,
  estado text not null default 'VIGENTE' check (estado in (
    'BORRADOR','VIGENTE','CUMPLIDA','ANULADA'
  )),
  created_by uuid default auth.uid() references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  unique (empresa_id, numero_sancion),
  check (fecha_fin >= fecha_inicio),
  check (tipo_sancion <> 'SUSPENSION DE LABORES' or bloquea_asistencia)
);

create index if not exists gh_sanciones_dni_vigencia_idx
  on public."GH_SANCIONES_PERSONAL_APPGT"
  (empresa_id, dni, fecha_inicio, fecha_fin)
  where estado = 'VIGENTE' and not eliminado and deleted_at is null;

-- ---------------------------------------------------------------------------
-- Campos organizacionales y controles de origen.
-- ---------------------------------------------------------------------------

alter table public."GH-REGISTRO_PERSONAL_PLANILLA"
  add column if not exists "AREA" text,
  add column if not exists "GRUPO_COSTO" text,
  add column if not exists "CAMPANA" text;

alter table public."GT-ASISTENCIA_PERSONAL"
  add column if not exists empresa_id uuid
    references public."EMPRESAS_APPGT"(id),
  add column if not exists "INGRESO_MOVILIDAD_ID" uuid
    references public."GT_INGRESO_MOVILIDADES_APPGT"(id),
  add column if not exists "VALIDACION_LABORAL" text,
  add column if not exists "BLOQUEO_MOTIVO" text;

alter table public."GT-TAREO_PERSONAL"
  add column if not exists empresa_id uuid
    references public."EMPRESAS_APPGT"(id),
  add column if not exists "ESTADO_APROBACION" text,
  add column if not exists "CERRADO_POR" uuid references auth.users(id),
  add column if not exists "CERRADO_AT" timestamptz,
  add column if not exists "REQUIERE_HORAS_EXTRA" boolean not null default false,
  add column if not exists "HORAS_EXTRA_SOLICITADAS" numeric(12,4) not null default 0,
  add column if not exists "MOTIVO_HORAS_EXTRA" text,
  add column if not exists "ESTADO_HORAS_EXTRA" text not null default 'NO_REQUIERE',
  add column if not exists "HORAS_EXTRA_AUTORIZADAS_POR" uuid references auth.users(id),
  add column if not exists "HORAS_EXTRA_AUTORIZADAS_AT" timestamptz;

update public."GT-TAREO_PERSONAL"
set "ESTADO_APROBACION" = 'APROBADO'
where nullif(btrim("ESTADO_APROBACION"), '') is null;

alter table public."GT-TAREO_PERSONAL"
  alter column "ESTADO_APROBACION" set default 'BORRADOR',
  alter column "ESTADO_APROBACION" set not null;

alter table public."GT-TAREO_PERSONAL"
  drop constraint if exists gt_tareo_estado_aprobacion_check,
  drop constraint if exists gt_tareo_estado_horas_extra_check;
alter table public."GT-TAREO_PERSONAL"
  add constraint gt_tareo_estado_aprobacion_check check (
    "ESTADO_APROBACION" in ('BORRADOR','CERRADO','REVISADO','APROBADO','RECHAZADO','ANULADO')
  ),
  add constraint gt_tareo_estado_horas_extra_check check (
    "ESTADO_HORAS_EXTRA" in ('NO_REQUIERE','SOLICITADO','AUTORIZADO','RECHAZADO')
  );

alter table public."GH_PERMISOS_LICENCIAS_APPGT"
  add column if not exists "ESTADO_APROBACION" text not null default 'PENDIENTE',
  add column if not exists empresa_nombre text,
  add column if not exists empresa_ruc text,
  add column if not exists representante_nombre text,
  add column if not exists representante_cargo text,
  add column if not exists lugar_emision text,
  add column if not exists aprobado_por uuid references auth.users(id),
  add column if not exists fecha_aprobacion timestamptz,
  add column if not exists fecha_reincorporacion date;

alter table public."GH_PERMISOS_LICENCIAS_APPGT"
  drop constraint if exists gh_permisos_estado_aprobacion_check;
alter table public."GH_PERMISOS_LICENCIAS_APPGT"
  add constraint gh_permisos_estado_aprobacion_check check (
    "ESTADO_APROBACION" in ('PENDIENTE','REVISADO','APROBADO','RECHAZADO','ANULADO')
  );

-- ---------------------------------------------------------------------------
-- Ciclo de planilla y auditoria inmutable.
-- ---------------------------------------------------------------------------

create table if not exists public."PLANILLA_PERIODOS_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null default public.appgt_empresa_actual_id()
    references public."EMPRESAS_APPGT"(id) on delete cascade,
  codigo text not null,
  descripcion text,
  fecha_inicio date not null,
  fecha_fin date not null,
  campana_id uuid references public."GH_CAMPANAS_LABORALES_APPGT"(id),
  campana text,
  moneda text not null default 'PEN',
  tipo_cambio numeric(18,6) not null default 1 check (tipo_cambio > 0),
  estado text not null default 'BORRADOR' check (estado in (
    'BORRADOR','CALCULADA','REVISADA','APROBADA','CERRADA'
  )),
  total_bruto numeric(20,6) not null default 0,
  total_descuentos_trabajador numeric(20,6) not null default 0,
  total_neto_pagar numeric(20,6) not null default 0,
  total_aportes_empleador numeric(20,6) not null default 0,
  total_beneficios_provisionados numeric(20,6) not null default 0,
  total_costo_empresa numeric(20,6) not null default 0,
  calculada_por uuid references auth.users(id),
  calculada_at timestamptz,
  revisada_por uuid references auth.users(id),
  revisada_at timestamptz,
  aprobada_por uuid references auth.users(id),
  aprobada_at timestamptz,
  cerrada_por uuid references auth.users(id),
  cerrada_at timestamptz,
  ultima_reapertura_por uuid references auth.users(id),
  ultima_reapertura_at timestamptz,
  motivo_ultima_reapertura text,
  cantidad_reaperturas integer not null default 0,
  created_by uuid default auth.uid() references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  unique (empresa_id, codigo),
  check (fecha_fin >= fecha_inicio)
);

create index if not exists planilla_periodos_fechas_idx
  on public."PLANILLA_PERIODOS_APPGT" (empresa_id, fecha_inicio, fecha_fin, estado)
  where not eliminado and deleted_at is null;

create table if not exists public."PLANILLA_AUDITORIA_APPGT" (
  id bigint generated always as identity primary key,
  empresa_id uuid references public."EMPRESAS_APPGT"(id),
  tabla_origen text not null,
  entidad_id text,
  periodo_id uuid references public."PLANILLA_PERIODOS_APPGT"(id),
  dni text,
  accion text not null,
  estado_anterior text,
  estado_nuevo text,
  motivo text,
  datos_anteriores jsonb,
  datos_nuevos jsonb,
  ejecutado_por uuid default auth.uid() references auth.users(id),
  ejecutado_at timestamptz not null default now(),
  ip_cliente inet
);

create index if not exists planilla_auditoria_periodo_idx
  on public."PLANILLA_AUDITORIA_APPGT" (empresa_id, periodo_id, ejecutado_at desc);

alter table public."PLANILLA_TRABAJADORES_ZUMAC"
  add column if not exists empresa_id uuid references public."EMPRESAS_APPGT"(id),
  add column if not exists periodo_id uuid references public."PLANILLA_PERIODOS_APPGT"(id),
  add column if not exists area text,
  add column if not exists grupo_costo text,
  add column if not exists campana text,
  add column if not exists moneda text not null default 'PEN',
  add column if not exists tipo_cambio numeric(18,6) not null default 1,
  add column if not exists remuneracion_bruta numeric(18,6) not null default 0,
  add column if not exists deducciones_trabajador numeric(18,6) not null default 0,
  add column if not exists neto_pagar numeric(18,6) not null default 0,
  add column if not exists aportes_empleador numeric(18,6) not null default 0,
  add column if not exists beneficios_provisionados numeric(18,6) not null default 0,
  add column if not exists otros_costos_empresa numeric(18,6) not null default 0,
  add column if not exists costo_total_empresa numeric(18,6) not null default 0,
  add column if not exists costo_total_usd numeric(18,6) not null default 0;

comment on column public."PLANILLA_TRABAJADORES_ZUMAC".deducciones_trabajador is
  'AFP/ONP y otros descuentos retenidos al trabajador; no se suman nuevamente al costo empresa.';
comment on column public."PLANILLA_TRABAJADORES_ZUMAC".aportes_empleador is
  'Aportes a cargo del empleador, separados del neto pagado al trabajador.';
comment on column public."PLANILLA_TRABAJADORES_ZUMAC".beneficios_provisionados is
  'Beneficios no incluidos ya en remuneracion_bruta. Evita doble contabilizacion.';

-- ---------------------------------------------------------------------------
-- Preparacion y validaciones de movilidad, sanciones y permisos.
-- ---------------------------------------------------------------------------

create or replace function public.appgt_operacion_preparar_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  if tg_op = 'UPDATE' then
    new.version := coalesce(old.version, 0) + 1;
  end if;
  return new;
end
$$;

drop trigger if exists appgt_movilidad_preparar_trigger
  on public."GT_INGRESO_MOVILIDADES_APPGT";
create trigger appgt_movilidad_preparar_trigger
before insert or update on public."GT_INGRESO_MOVILIDADES_APPGT"
for each row execute function public.appgt_operacion_preparar_v1();

drop trigger if exists appgt_sancion_preparar_trigger
  on public."GH_SANCIONES_PERSONAL_APPGT";
create trigger appgt_sancion_preparar_trigger
before insert or update on public."GH_SANCIONES_PERSONAL_APPGT"
for each row execute function public.appgt_operacion_preparar_v1();

create or replace function public.appgt_validar_asistencia_laboral_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_data jsonb := to_jsonb(new);
  v_empresa uuid := coalesce(new.empresa_id, public.appgt_empresa_actual_id());
  v_dni text := public.appgt_jsonb_text(v_data, array['DNI','DOCUMENTO']);
  v_fecha date := coalesce(
    public.appgt_jsonb_date(v_data, array['FECHA','FECHA_INGRESO']), current_date
  );
  v_placa text := public.appgt_jsonb_text(v_data, array['PLACA','MOVILIDAD']);
  v_worker jsonb;
  v_status text;
  v_fin date;
  v_sancion record;
begin
  new.empresa_id := v_empresa;
  if nullif(btrim(v_dni), '') is null then
    raise exception 'No se puede marcar asistencia sin DNI.';
  end if;

  select to_jsonb(p) into v_worker
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  where public.appgt_normalizar_clave(
    public.appgt_jsonb_text(to_jsonb(p), array['DNI','DOCUMENTO'])
  ) = public.appgt_normalizar_clave(v_dni)
  limit 1;

  if v_worker is null then
    raise exception 'El DNI % no existe en Registro de Personal.', v_dni;
  end if;
  v_status := public.appgt_normalizar_clave(
    public.appgt_jsonb_text(v_worker, array['Status','ESTADO','ESTADO_PERSONAL'])
  );
  v_fin := public.appgt_jsonb_date(
    v_worker, array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']
  );
  if v_status <> 'ACTIVO' or v_fin is null or v_fin < v_fecha then
    new."VALIDACION_LABORAL" := 'BLOQUEADO';
    new."BLOQUEO_MOTIVO" := case
      when v_fin is null then 'El trabajador no tiene fecha fin de contrato.'
      when v_fin < v_fecha then 'Contrato vencido el ' || to_char(v_fin, 'DD/MM/YYYY') || '.'
      else 'Estado laboral no activo: ' || coalesce(v_status, 'SIN ESTADO') || '.'
    end;
    raise exception '%', new."BLOQUEO_MOTIVO";
  end if;

  select s.numero_sancion, s.tipo_sancion, s.fecha_fin
  into v_sancion
  from public."GH_SANCIONES_PERSONAL_APPGT" s
  where s.empresa_id = v_empresa
    and public.appgt_normalizar_clave(s.dni) = public.appgt_normalizar_clave(v_dni)
    and s.estado = 'VIGENTE' and s.bloquea_asistencia
    and v_fecha between s.fecha_inicio and s.fecha_fin
    and not s.eliminado and s.deleted_at is null
  order by s.fecha_inicio desc, s.created_at desc
  limit 1;
  if found then
    new."VALIDACION_LABORAL" := 'BLOQUEADO';
    new."BLOQUEO_MOTIVO" := 'El trabajador cuenta con ' ||
      lower(v_sancion.tipo_sancion) || ' vigente hasta ' ||
      to_char(v_sancion.fecha_fin, 'DD/MM/YYYY') || '.';
    raise exception '%', new."BLOQUEO_MOTIVO";
  end if;

  if nullif(btrim(v_placa), '') is not null then
    select m.id into new."INGRESO_MOVILIDAD_ID"
    from public."GT_INGRESO_MOVILIDADES_APPGT" m
    where m.empresa_id = v_empresa and m.fecha = v_fecha
      and public.appgt_normalizar_clave(m.placa) = public.appgt_normalizar_clave(v_placa)
      and m.estado in ('ADMITIDA','CERRADA')
      and not m.eliminado and m.deleted_at is null
      and (m.licencia_vigencia is null or m.licencia_vigencia >= v_fecha)
      and (m.soat_vigencia is null or m.soat_vigencia >= v_fecha)
      and (m.revision_tecnica_vigencia is null or m.revision_tecnica_vigencia >= v_fecha)
    order by m.hora_ingreso desc limit 1;
    if new."INGRESO_MOVILIDAD_ID" is null then
      raise exception 'La movilidad % no tiene un ingreso formal vigente para %.',
        v_placa, to_char(v_fecha, 'DD/MM/YYYY');
    end if;
  end if;

  new."VALIDACION_LABORAL" := 'VALIDADO';
  new."BLOQUEO_MOTIVO" := null;
  return new;
end
$$;

drop trigger if exists appgt_validar_asistencia_laboral_trigger
  on public."GT-ASISTENCIA_PERSONAL";
create trigger appgt_validar_asistencia_laboral_trigger
before insert or update of "DNI", "FECHA", "FECHA_INGRESO", "PLACA"
on public."GT-ASISTENCIA_PERSONAL"
for each row execute function public.appgt_validar_asistencia_laboral_v1();

create or replace function public.appgt_permiso_aprobacion_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa public."EMPRESAS_APPGT"%rowtype;
begin
  if new."ESTADO_APROBACION" = 'APROBADO'
     and old."ESTADO_APROBACION" is distinct from 'APROBADO' then
    select * into v_empresa from public."EMPRESAS_APPGT"
    where id = new.empresa_id;
    new.estado := 'APROBADO';
    new.aprobado_por := auth.uid();
    new.fecha_aprobacion := now();
    new.fecha_reincorporacion := new.fecha_fin + 1;
    new.empresa_nombre := coalesce(new.empresa_nombre, v_empresa.nombre);
    new.empresa_ruc := coalesce(new.empresa_ruc, v_empresa.ruc);
    new.representante_nombre := coalesce(
      new.representante_nombre, v_empresa.representante_legal
    );
    new.representante_cargo := coalesce(
      new.representante_cargo, v_empresa.representante_cargo
    );
    new.lugar_emision := coalesce(new.lugar_emision, v_empresa.ciudad_emision);
    new.documento_generado := coalesce(
      nullif(new.documento_generado, ''),
      'constancia_' || lower(replace(new.tipo_permiso, ' ', '_')) || '_' ||
      regexp_replace(new.dni, '[^0-9A-Za-z_-]', '_', 'g') || '.pdf'
    );
  elsif new."ESTADO_APROBACION" = 'RECHAZADO' then
    new.estado := 'RECHAZADO';
  elsif new."ESTADO_APROBACION" = 'ANULADO' then
    new.estado := 'ANULADO';
  end if;
  return new;
end
$$;

drop trigger if exists zz_appgt_permiso_aprobacion_trigger
  on public."GH_PERMISOS_LICENCIAS_APPGT";
create trigger zz_appgt_permiso_aprobacion_trigger
before update of "ESTADO_APROBACION"
on public."GH_PERMISOS_LICENCIAS_APPGT"
for each row execute function public.appgt_permiso_aprobacion_v1();

-- ---------------------------------------------------------------------------
-- Tareo cerrado, autorizacion de horas extra y aprobacion obligatoria.
-- ---------------------------------------------------------------------------

create or replace function public.appgt_tareo_control_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_data jsonb := to_jsonb(new);
  v_dni text := public.appgt_jsonb_text(v_data, array['DNI','DOCUMENTO']);
  v_fecha date := public.appgt_jsonb_date(v_data, array['FECHA']);
  v_horas numeric := greatest(
    public.appgt_jsonb_numeric(v_data, array['HORAS_TRABAJADAS'], 0), 0
  );
  v_previas numeric := 0;
  v_id text := public.appgt_jsonb_text(v_data, array['id_local','id']);
  v_cierre_nuevo boolean := false;
begin
  new.empresa_id := coalesce(new.empresa_id, public.appgt_empresa_actual_id());
  if v_dni is not null and v_fecha is not null then
    select coalesce(sum(greatest(
      public.appgt_jsonb_numeric(to_jsonb(t), array['HORAS_TRABAJADAS'], 0), 0
    )), 0)
    into v_previas
    from public."GT-TAREO_PERSONAL" t
    where public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(t), array['DNI','DOCUMENTO'])
    ) = public.appgt_normalizar_clave(v_dni)
      and public.appgt_jsonb_date(to_jsonb(t), array['FECHA']) = v_fecha
      and public.appgt_jsonb_text(to_jsonb(t), array['id_local','id'])
          is distinct from v_id
      and not public.appgt_jsonb_bool(to_jsonb(t), array['eliminado'], false)
      and public.appgt_jsonb_text(to_jsonb(t), array['deleted_at']) is null;
  end if;

  new."HORAS_EXTRA_SOLICITADAS" := greatest(v_previas + v_horas - 8, 0);
  new."REQUIERE_HORAS_EXTRA" := new."HORAS_EXTRA_SOLICITADAS" > 0;
  if not new."REQUIERE_HORAS_EXTRA" then
    new."ESTADO_HORAS_EXTRA" := 'NO_REQUIERE';
    new."MOTIVO_HORAS_EXTRA" := null;
  elsif new."ESTADO_HORAS_EXTRA" = 'NO_REQUIERE' then
    new."ESTADO_HORAS_EXTRA" := 'SOLICITADO';
  end if;

  if new."ESTADO_APROBACION" = 'CERRADO' then
    if tg_op = 'INSERT' then
      v_cierre_nuevo := true;
    else
      v_cierre_nuevo := old."ESTADO_APROBACION" is distinct from 'CERRADO';
    end if;
  end if;
  if v_cierre_nuevo then
    new."CERRADO_POR" := auth.uid();
    new."CERRADO_AT" := now();
    if new."REQUIERE_HORAS_EXTRA"
       and nullif(btrim(new."MOTIVO_HORAS_EXTRA"), '') is null then
      raise exception 'Indique el motivo de las horas extra antes de cerrar el tareo.';
    end if;
  end if;

  if new."ESTADO_APROBACION" = 'APROBADO'
     and new."REQUIERE_HORAS_EXTRA"
     and new."ESTADO_HORAS_EXTRA" <> 'AUTORIZADO' then
    raise exception 'Las horas extra deben estar autorizadas antes de aprobar el tareo.';
  end if;
  return new;
end
$$;

drop trigger if exists appgt_tareo_control_trigger
  on public."GT-TAREO_PERSONAL";
create trigger appgt_tareo_control_trigger
before insert or update on public."GT-TAREO_PERSONAL"
for each row execute function public.appgt_tareo_control_v1();

create or replace function public.appgt_puede_accion_tabla_v1(
  p_tabla text,
  p_accion text
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.appgt_puede_gestionar_configuracion(public.appgt_empresa_actual_id())
    or exists (
      select 1
      from public."PERMISOS_DE_USUARIOS_APPGT" p
      where p.empresa_id = public.appgt_empresa_actual_id()
        and p.user_id = auth.uid() and p.activo and not p.eliminado
        and public.appgt_normalizar_clave(coalesce(p.tabla_destino, ''))
            = public.appgt_normalizar_clave(p_tabla)
        and case upper(btrim(p_accion))
          when 'VER' then p.can_view
          when 'INSERTAR' then p.can_insert
          when 'ACTUALIZAR' then p.can_update
          when 'REVISAR' then p.can_review
          when 'APROBAR' then p.can_approve
          else false
        end
    )
$$;

create or replace function public.appgt_autorizar_horas_extra_tareo_v1(
  p_id_local text,
  p_autorizar boolean,
  p_motivo text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public."GT-TAREO_PERSONAL"%rowtype;
begin
  if not public.appgt_puede_accion_tabla_v1('GT-TAREO_PERSONAL', 'APROBAR') then
    raise exception 'No tiene permiso para autorizar horas extra.' using errcode = '42501';
  end if;
  update public."GT-TAREO_PERSONAL"
  set "ESTADO_HORAS_EXTRA" = case when p_autorizar then 'AUTORIZADO' else 'RECHAZADO' end,
      "MOTIVO_HORAS_EXTRA" = coalesce(nullif(btrim(p_motivo), ''), "MOTIVO_HORAS_EXTRA"),
      "HORAS_EXTRA_AUTORIZADAS_POR" = auth.uid(),
      "HORAS_EXTRA_AUTORIZADAS_AT" = now()
  where public.appgt_jsonb_text(to_jsonb("GT-TAREO_PERSONAL"), array['id_local','id'])
        = p_id_local
    and "REQUIERE_HORAS_EXTRA"
    and "ESTADO_APROBACION" in ('CERRADO','REVISADO')
  returning * into v_row;
  if not found then
    raise exception 'Tareo no encontrado o sin horas extra pendientes.';
  end if;
  return to_jsonb(v_row);
end
$$;

-- ---------------------------------------------------------------------------
-- Separacion contable y enriquecimiento organizacional de cada fila.
-- ---------------------------------------------------------------------------

create or replace function public.appgt_planilla_separar_costos_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_worker jsonb;
  v_period public."PLANILLA_PERIODOS_APPGT"%rowtype;
begin
  new.empresa_id := coalesce(new.empresa_id, public.appgt_empresa_actual_id());
  select to_jsonb(p) into v_worker
  from public."GH-REGISTRO_PERSONAL_PLANILLA" p
  where public.appgt_normalizar_clave(
    public.appgt_jsonb_text(to_jsonb(p), array['DNI','DOCUMENTO'])
  ) = public.appgt_normalizar_clave(new.dni)
  limit 1;
  if v_worker is not null then
    new.area := coalesce(new.area,
      public.appgt_jsonb_text(v_worker, array['AREA','Area','AREA_TRABAJO']));
    new.grupo_costo := coalesce(new.grupo_costo,
      public.appgt_jsonb_text(v_worker, array['GRUPO_COSTO','Grupo de costo','TIPO_TRABAJADOR']));
    new.campana := coalesce(new.campana,
      public.appgt_jsonb_text(v_worker, array['CAMPANA','CAMPAÑA']));
  end if;

  if new.periodo_id is not null then
    select * into v_period from public."PLANILLA_PERIODOS_APPGT"
    where id = new.periodo_id;
    if found then
      new.empresa_id := v_period.empresa_id;
      new.campana := coalesce(v_period.campana, new.campana);
      new.moneda := v_period.moneda;
      new.tipo_cambio := v_period.tipo_cambio;
    end if;
  end if;

  -- ingreso_bruto ya incluye los beneficios pagados/prorrateados del regimen.
  -- Por ello no se vuelven a sumar como provision: solo conceptos separados.
  new.remuneracion_bruta := round(coalesce(new.ingreso_bruto, 0), 6);
  new.deducciones_trabajador := round(coalesce(new.descuento, 0), 6);
  new.neto_pagar := round(new.remuneracion_bruta - new.deducciones_trabajador, 6);
  new.aportes_empleador := round(coalesce(new.essalud_costo, 0), 6);
  new.beneficios_provisionados := greatest(coalesce(new.beneficios_provisionados, 0), 0);
  new.otros_costos_empresa := greatest(coalesce(new.otros_costos_empresa, 0), 0);
  new.costo_total_empresa := round(
    new.remuneracion_bruta + new.aportes_empleador +
    new.beneficios_provisionados + new.otros_costos_empresa, 6
  );
  new.costo_total_usd := case when new.tipo_cambio > 0
    then round(new.costo_total_empresa / new.tipo_cambio, 6) else 0 end;
  -- Alias heredados: se conservan para dashboards y formatos existentes.
  new.total_neto := new.neto_pagar;
  new.costo_empresa := new.costo_total_empresa;
  return new;
end
$$;

drop trigger if exists zzz_appgt_planilla_separar_costos_trigger
  on public."PLANILLA_TRABAJADORES_ZUMAC";
create trigger zzz_appgt_planilla_separar_costos_trigger
before insert or update on public."PLANILLA_TRABAJADORES_ZUMAC"
for each row execute function public.appgt_planilla_separar_costos_v1();

-- ---------------------------------------------------------------------------
-- Periodos cerrados: ningun origen puede cambiar sin reapertura autorizada.
-- ---------------------------------------------------------------------------

create or replace function public.appgt_periodo_cerrado_para_fecha_v1(
  p_empresa uuid,
  p_fecha date
)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.id
  from public."PLANILLA_PERIODOS_APPGT" p
  where p.empresa_id = p_empresa and p.estado = 'CERRADA'
    and p_fecha between p.fecha_inicio and p.fecha_fin
    and not p.eliminado and p.deleted_at is null
  order by p.cerrada_at desc nulls last limit 1
$$;

create or replace function public.appgt_bloquear_origen_planilla_cerrada_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_data jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_empresa uuid := coalesce(
    nullif(public.appgt_jsonb_text(v_data, array['empresa_id']), '')::uuid,
    public.appgt_empresa_actual_id()
  );
  v_desde date;
  v_hasta date;
  v_periodo uuid;
begin
  if tg_table_name = 'GH_PERMISOS_LICENCIAS_APPGT' then
    v_desde := public.appgt_jsonb_date(v_data, array['fecha_inicio']);
    v_hasta := public.appgt_jsonb_date(v_data, array['fecha_fin']);
    select p.id into v_periodo
    from public."PLANILLA_PERIODOS_APPGT" p
    where p.empresa_id = v_empresa and p.estado = 'CERRADA'
      and daterange(p.fecha_inicio, p.fecha_fin, '[]') && daterange(v_desde, v_hasta, '[]')
      and not p.eliminado and p.deleted_at is null limit 1;
  else
    v_desde := public.appgt_jsonb_date(v_data, array['FECHA','FECHA_INGRESO','fecha']);
    v_periodo := public.appgt_periodo_cerrado_para_fecha_v1(v_empresa, v_desde);
  end if;
  if v_periodo is not null then
    raise exception 'El periodo de planilla esta cerrado. Reabra el periodo con autorizacion antes de modificar este registro.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;

drop trigger if exists appgt_bloquear_tareo_planilla_cerrada
  on public."GT-TAREO_PERSONAL";
create trigger appgt_bloquear_tareo_planilla_cerrada
before insert or update or delete on public."GT-TAREO_PERSONAL"
for each row execute function public.appgt_bloquear_origen_planilla_cerrada_v1();

drop trigger if exists appgt_bloquear_asistencia_planilla_cerrada
  on public."GT-ASISTENCIA_PERSONAL";
create trigger appgt_bloquear_asistencia_planilla_cerrada
before insert or update or delete on public."GT-ASISTENCIA_PERSONAL"
for each row execute function public.appgt_bloquear_origen_planilla_cerrada_v1();

drop trigger if exists appgt_bloquear_permiso_planilla_cerrada
  on public."GH_PERMISOS_LICENCIAS_APPGT";
create trigger appgt_bloquear_permiso_planilla_cerrada
before insert or update or delete on public."GH_PERMISOS_LICENCIAS_APPGT"
for each row execute function public.appgt_bloquear_origen_planilla_cerrada_v1();

create or replace function public.appgt_bloquear_fila_planilla_cerrada_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_periodo uuid;
  v_estado text;
begin
  if tg_op = 'DELETE' then
    v_periodo := old.periodo_id;
  else
    v_periodo := coalesce(new.periodo_id, old.periodo_id);
  end if;
  if v_periodo is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  select estado into v_estado from public."PLANILLA_PERIODOS_APPGT" where id = v_periodo;
  if v_estado = 'CERRADA' then
    raise exception 'La fila pertenece a una planilla cerrada. Reabra el periodo antes de modificarla.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;

drop trigger if exists appgt_bloquear_fila_planilla_cerrada
  on public."PLANILLA_TRABAJADORES_ZUMAC";
create trigger appgt_bloquear_fila_planilla_cerrada
before update or delete on public."PLANILLA_TRABAJADORES_ZUMAC"
for each row execute function public.appgt_bloquear_fila_planilla_cerrada_v1();

-- ---------------------------------------------------------------------------
-- La planilla solo consume tareos APROBADOS. Se conserva el nombre del RPC
-- existente para que triggers, permisos y Flutter adopten la regla sin cambios.
-- ---------------------------------------------------------------------------

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
     or p_hasta < p_desde then return 0; end if;

  with worker as (
    select s.data,
      public.appgt_jsonb_text(s.data, array['id_local','id']) trabajador_id,
      public.appgt_jsonb_text(s.data, array['DNI','DOCUMENTO']) dni,
      public.appgt_jsonb_date(s.data, array['Fecha inicio de Contrato','FECHA_INICIO_CONTRATO']) contrato_inicio,
      public.appgt_jsonb_date(s.data, array['Fecha fin de Contrato','FECHA_FIN_CONTRATO']) contrato_fin,
      coalesce(public.appgt_jsonb_text(s.data, array['Regimen laboral','Régimen laboral','REGIMEN_LABORAL','Régimen']), 'Agrario 31110') regimen,
      public.appgt_jsonb_numeric(s.data, array['Sueldo','SUELDO_MENSUAL','REMUNERACION'], 0) sueldo,
      public.appgt_jsonb_bool(s.data, array['Asignacion familiar','Asignación familiar','ASIGNACION_FAMILIAR'], false) tiene_asignacion,
      public.appgt_jsonb_numeric(s.data, array['%comision','%comisión','PORCENTAJE_COMISION','AFP_COMISION'], 0) afp_comision,
      public.appgt_jsonb_text(s.data, array['Sistema pensionario','SISTEMA_PENSION','REGIMEN_PENSIONARIO','AFP/ONP']) sistema_pension,
      public.appgt_jsonb_text(s.data, array['Apellido_paterno','APELLIDO_PATERNO']) apellido_paterno,
      public.appgt_jsonb_text(s.data, array['Apellido_materno','APELLIDO_MATERNO']) apellido_materno,
      public.appgt_jsonb_text(s.data, array['Nombres','NOMBRES']) nombres,
      public.appgt_jsonb_text(s.data, array['Puesto','PUESTO','CARGO']) puesto,
      public.appgt_jsonb_text(s.data, array['Periodo de pago','PERIODO_PAGO']) periodo_pago
    from (select to_jsonb(p) data from public."GH-REGISTRO_PERSONAL_PLANILLA" p) s
    where public.appgt_normalizar_clave(
      public.appgt_jsonb_text(s.data, array['DNI','DOCUMENTO'])
    ) = public.appgt_normalizar_clave(p_dni)
      and public.appgt_normalizar_clave(
        public.appgt_jsonb_text(s.data, array['Status','ESTADO','ESTADO_PERSONAL'])
      ) = 'ACTIVO'
    limit 1
  ), dates as (
    select w.*, gs::date fecha
    from worker w
    cross join lateral generate_series(
      greatest(p_desde, w.contrato_inicio),
      least(p_hasta, w.contrato_fin, current_date), interval '1 day'
    ) gs
    where w.contrato_inicio is not null and w.contrato_fin is not null
      and greatest(p_desde, w.contrato_inicio)
          <= least(p_hasta, w.contrato_fin, current_date)
  ), source_rows as (
    select d.*, t.data tareo,
      coalesce(public.appgt_jsonb_text(t.data, array['id_local','id']),
               t.row_locator, 'SIN_TAREO') source_id,
      greatest(public.appgt_jsonb_numeric(t.data, array['HORAS_TRABAJADAS'], 0), 0) raw_hours,
      public.appgt_jsonb_time(t.data, array['HORA_INICIO','HORA INCIO']) hora_inicio,
      public.appgt_jsonb_time(t.data, array['HORA_FIN']) hora_fin,
      public.appgt_jsonb_text(t.data, array['LABOR']) labor,
      public.appgt_jsonb_text(t.data, array['CENTRO_COSTO','CENTRO COSTO']) centro_costo,
      public.appgt_jsonb_text(t.data, array['VARIEDAD']) variedad
    from dates d
    left join lateral (
      select to_jsonb(gt) data, gt.ctid::text row_locator
      from public."GT-TAREO_PERSONAL" gt
      where public.appgt_normalizar_clave(
        public.appgt_jsonb_text(to_jsonb(gt), array['DNI','DOCUMENTO'])
      ) = public.appgt_normalizar_clave(d.dni)
        and public.appgt_jsonb_date(to_jsonb(gt), array['FECHA']) = d.fecha
        and gt."ESTADO_APROBACION" = 'APROBADO'
        and not public.appgt_jsonb_bool(to_jsonb(gt), array['eliminado'], false)
        and public.appgt_jsonb_text(to_jsonb(gt), array['deleted_at']) is null
    ) t on true
  ), distributed as (
    select s.*,
      row_number() over (partition by s.fecha order by s.source_id) source_order,
      coalesce(sum(s.raw_hours) over (
        partition by s.fecha order by s.source_id
        rows between unbounded preceding and 1 preceding
      ), 0) prior_hours
    from source_rows s
  ), calculated as (
    select d.*,
      greatest(least(d.prior_hours + d.raw_hours, 8) - least(d.prior_hours, 8), 0) regular_hours,
      greatest(least(d.prior_hours + d.raw_hours, 10) - greatest(d.prior_hours, 8), 0) extra_25,
      greatest(d.prior_hours + d.raw_hours - greatest(d.prior_hours, 10), 0) extra_35,
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
      ) * 8.0 / 6.0 else 0 end weekly_rest
    from distributed d
  ), ready as (
    select c.*,
      public.appgt_jsonb_numeric(to_jsonb(b), array['RMV'], 0) benefit_rmv,
      public.appgt_jsonb_numeric(to_jsonb(b), array['Asignacion familiar','Asignación familiar'], 0) benefit_asignacion,
      public.appgt_jsonb_numeric(to_jsonb(b), array['CTS'], 0) benefit_cts,
      public.appgt_jsonb_numeric(to_jsonb(b), array['gratificacion','gratificación'], 0) benefit_gratificacion,
      public.appgt_jsonb_numeric(to_jsonb(b), array['bono extraordinario de gratificacion','bono extraordinario de gratificación'], 0) benefit_bono_gratificacion,
      public.appgt_jsonb_numeric(to_jsonb(b), array['bono beta'], 0) benefit_bono_beta,
      public.appgt_jsonb_numeric(to_jsonb(b), array['essalud'], 0) benefit_essalud,
      public.appgt_jsonb_numeric(to_jsonb(b), array['onp'], 0) benefit_onp,
      public.appgt_jsonb_numeric(to_jsonb(b), array['afp'], 0) benefit_afp,
      public.appgt_jsonb_numeric(to_jsonb(b), array['afp_seguro'], 0) benefit_afp_seguro
    from calculated c
    join lateral (
      select mb.* from public."MATRIZ_BENEFICIOS_SOCIALES" mb
      where mb.activo and not mb.eliminado
      order by case when public.appgt_normalizar_clave(
        public.appgt_jsonb_text(to_jsonb(mb), array['regimen','régimen'])
      ) = public.appgt_normalizar_clave(c.regimen) then 0 else 1 end,
      mb.created_at limit 1
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
  select r.trabajador_id,
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
    activo = true, eliminado = false, deleted_at = null,
    estado_sync = 'sincronizado';

  get diagnostics v_rows = row_count;

  delete from public."PLANILLA_TRABAJADORES_ZUMAC" p
  where public.appgt_normalizar_clave(p.dni) = public.appgt_normalizar_clave(p_dni)
    and p.fecha between p_desde and p_hasta and p.auto_generado
    and p.origen_clave like 'TAREO:%'
    and not exists (
      select 1 from public."GT-TAREO_PERSONAL" gt
      where public.appgt_normalizar_clave(
        public.appgt_jsonb_text(to_jsonb(gt), array['DNI','DOCUMENTO'])
      ) = public.appgt_normalizar_clave(p.dni)
        and public.appgt_jsonb_date(to_jsonb(gt), array['FECHA']) = p.fecha
        and 'TAREO:' || coalesce(
          public.appgt_jsonb_text(to_jsonb(gt), array['id_local','id']), gt.ctid::text
        ) = p.origen_clave
        and gt."ESTADO_APROBACION" = 'APROBADO'
        and not public.appgt_jsonb_bool(to_jsonb(gt), array['eliminado'], false)
        and public.appgt_jsonb_text(to_jsonb(gt), array['deleted_at']) is null
    );

  delete from public."PLANILLA_TRABAJADORES_ZUMAC" p
  where public.appgt_normalizar_clave(p.dni) = public.appgt_normalizar_clave(p_dni)
    and p.fecha between p_desde and p_hasta and p.auto_generado
    and p.origen_clave = 'SIN_TAREO'
    and exists (
      select 1 from public."GT-TAREO_PERSONAL" gt
      where public.appgt_normalizar_clave(
        public.appgt_jsonb_text(to_jsonb(gt), array['DNI','DOCUMENTO'])
      ) = public.appgt_normalizar_clave(p.dni)
        and public.appgt_jsonb_date(to_jsonb(gt), array['FECHA']) = p.fecha
        and gt."ESTADO_APROBACION" = 'APROBADO'
        and not public.appgt_jsonb_bool(to_jsonb(gt), array['eliminado'], false)
        and public.appgt_jsonb_text(to_jsonb(gt), array['deleted_at']) is null
    );
  return v_rows;
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
  if nullif(btrim(p_dni), '') is null or p_desde is null or p_hasta is null
     or p_hasta < p_desde then return; end if;
  perform public.appgt_recalcular_planilla_zumac(p_dni, p_desde, p_hasta);
  with ranked as (
    select p.id_local, p.fecha,
      row_number() over (partition by p.dni, p.fecha order by
        case when p.origen_clave = 'SIN_TAREO' then 0 else 1 end,
        p.origen_clave, p.id_local) row_number
    from public."PLANILLA_TRABAJADORES_ZUMAC" p
    where public.appgt_normalizar_clave(p.dni) = public.appgt_normalizar_clave(p_dni)
      and p.fecha between p_desde and p_hasta
      and p.activo and not p.eliminado and p.deleted_at is null
  ), resolved as (
    select r.id_local, r.row_number, q.tipo_permiso,
      coalesce(q.horas_permiso, 0) horas_permiso
    from ranked r
    left join lateral (
      select q.tipo_permiso,
        case when q.fecha_inicio = q.fecha_fin and q.hora_inicio is not null
             and q.hora_fin is not null then least(8::numeric, greatest(
               extract(epoch from (q.hora_fin - q.hora_inicio)) / 3600, 0
             )) else 8::numeric end horas_permiso
      from public."GH_PERMISOS_LICENCIAS_APPGT" q
      where q.empresa_id = public.appgt_empresa_actual_id()
        and public.appgt_normalizar_clave(q.dni) = public.appgt_normalizar_clave(p_dni)
        and r.fecha between q.fecha_inicio and q.fecha_fin
        and q.estado = 'APROBADO' and q."ESTADO_APROBACION" = 'APROBADO'
        and not q.eliminado and q.deleted_at is null
      order by q.fecha_aprobacion desc nulls last, q.updated_at desc, q.id limit 1
    ) q on true
  )
  update public."PLANILLA_TRABAJADORES_ZUMAC" p set
    horas_trabajadas = case
      when r.tipo_permiso in ('DESCANSO MEDICO','LICENCIA DE MATERNIDAD',
        'PERMISO SIN GOCE','COMISION DE SERVICIO','LICENCIA DE PATERNIDAD',
        'LICENCIA POR FALLECIMIENTO','VACACIONES') and r.horas_permiso >= 8 then 0
      when r.tipo_permiso is not null and r.row_number = 1
        then greatest(p.horas_trabajadas - r.horas_permiso, 0)
      else p.horas_trabajadas end,
    descanso_medico = case when r.row_number = 1 and r.tipo_permiso = 'DESCANSO MEDICO'
      then r.horas_permiso else 0 end,
    licencia_maternidad = case when r.row_number = 1 and r.tipo_permiso = 'LICENCIA DE MATERNIDAD'
      then r.horas_permiso else 0 end,
    licencia_paternidad = case when r.row_number = 1 and r.tipo_permiso = 'LICENCIA DE PATERNIDAD'
      then r.horas_permiso else 0 end,
    licencia_fallecimiento = case when r.row_number = 1 and r.tipo_permiso = 'LICENCIA POR FALLECIMIENTO'
      then r.horas_permiso else 0 end,
    comision = case when r.row_number = 1 and r.tipo_permiso = 'COMISION DE SERVICIO'
      then r.horas_permiso else 0 end,
    permiso_sin_goce = case when r.row_number = 1 and r.tipo_permiso = 'PERMISO SIN GOCE'
      then r.horas_permiso else 0 end,
    vacaciones = case when r.row_number = 1 and r.tipo_permiso = 'VACACIONES'
      then r.horas_permiso else 0 end,
    updated_at = now()
  from resolved r where p.id_local = r.id_local;
end
$$;

-- ---------------------------------------------------------------------------
-- Transiciones atomicas de planilla y reapertura restringida.
-- ---------------------------------------------------------------------------

create or replace function public.appgt_planilla_periodo_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'UPDATE' then
    if new.estado is distinct from old.estado
       and coalesce(current_setting('appgt.planilla_transition', true), '') <> '1' then
      raise exception 'Use las acciones Calcular, Revisar, Aprobar, Cerrar o Reabrir.';
    end if;
  end if;
  new.updated_at := now();
  new.updated_by := auth.uid();
  if tg_op = 'UPDATE' then new.version := old.version + 1; end if;
  return new;
end
$$;

drop trigger if exists appgt_planilla_periodo_guard_trigger
  on public."PLANILLA_PERIODOS_APPGT";
create trigger appgt_planilla_periodo_guard_trigger
before insert or update on public."PLANILLA_PERIODOS_APPGT"
for each row execute function public.appgt_planilla_periodo_guard_v1();

create or replace function public.appgt_planilla_periodo_totales_v1(p_periodo uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public."PLANILLA_PERIODOS_APPGT" pp set
    total_bruto = x.bruto,
    total_descuentos_trabajador = x.descuentos,
    total_neto_pagar = x.neto,
    total_aportes_empleador = x.aportes,
    total_beneficios_provisionados = x.beneficios,
    total_costo_empresa = x.costo
  from (
    select coalesce(sum(remuneracion_bruta),0) bruto,
      coalesce(sum(deducciones_trabajador),0) descuentos,
      coalesce(sum(neto_pagar),0) neto,
      coalesce(sum(aportes_empleador),0) aportes,
      coalesce(sum(beneficios_provisionados),0) beneficios,
      coalesce(sum(costo_total_empresa),0) costo
    from public."PLANILLA_TRABAJADORES_ZUMAC" where periodo_id = p_periodo
      and activo and not eliminado and deleted_at is null
  ) x where pp.id = p_periodo;
end
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
  v_accion text := upper(btrim(p_accion));
  v_anterior text;
begin
  select * into v_periodo from public."PLANILLA_PERIODOS_APPGT"
  where id = p_periodo_id and empresa_id = public.appgt_empresa_actual_id()
    and not eliminado and deleted_at is null for update;
  if not found then raise exception 'Periodo de planilla no encontrado.'; end if;
  v_anterior := v_periodo.estado;

  if v_accion = 'CALCULAR' then
    if v_periodo.estado not in ('BORRADOR','CALCULADA') then
      raise exception 'Solo una planilla BORRADOR o CALCULADA puede recalcularse.';
    end if;
    if not public.appgt_puede_accion_tabla_v1('PLANILLA_PERIODOS_APPGT','ACTUALIZAR') then
      raise exception 'No tiene permiso para calcular planilla.' using errcode='42501';
    end if;
    perform public.appgt_refrescar_planilla_zumac(v_periodo.fecha_inicio, v_periodo.fecha_fin);
    update public."PLANILLA_TRABAJADORES_ZUMAC" p set
      empresa_id = v_periodo.empresa_id, periodo_id = v_periodo.id,
      campana = coalesce(v_periodo.campana, p.campana),
      moneda = v_periodo.moneda, tipo_cambio = v_periodo.tipo_cambio
    where p.fecha between v_periodo.fecha_inicio and v_periodo.fecha_fin
      and (p.empresa_id is null or p.empresa_id = v_periodo.empresa_id)
      and p.activo and not p.eliminado and p.deleted_at is null;
    perform public.appgt_planilla_periodo_totales_v1(v_periodo.id);
    perform set_config('appgt.planilla_transition', '1', true);
    update public."PLANILLA_PERIODOS_APPGT" set estado='CALCULADA',
      calculada_por=auth.uid(), calculada_at=now(),
      revisada_por=null, revisada_at=null, aprobada_por=null, aprobada_at=null,
      cerrada_por=null, cerrada_at=null where id=v_periodo.id;
  elsif v_accion = 'REVISAR' then
    if v_periodo.estado <> 'CALCULADA' then raise exception 'La planilla debe estar CALCULADA.'; end if;
    if not public.appgt_puede_accion_tabla_v1('PLANILLA_PERIODOS_APPGT','REVISAR') then
      raise exception 'No tiene permiso para revisar planilla.' using errcode='42501';
    end if;
    perform set_config('appgt.planilla_transition', '1', true);
    update public."PLANILLA_PERIODOS_APPGT" set estado='REVISADA',
      revisada_por=auth.uid(), revisada_at=now() where id=v_periodo.id;
  elsif v_accion = 'APROBAR' then
    if v_periodo.estado <> 'REVISADA' then raise exception 'La planilla debe estar REVISADA.'; end if;
    if not public.appgt_puede_accion_tabla_v1('PLANILLA_PERIODOS_APPGT','APROBAR') then
      raise exception 'No tiene permiso para aprobar planilla.' using errcode='42501';
    end if;
    perform set_config('appgt.planilla_transition', '1', true);
    update public."PLANILLA_PERIODOS_APPGT" set estado='APROBADA',
      aprobada_por=auth.uid(), aprobada_at=now() where id=v_periodo.id;
  elsif v_accion = 'CERRAR' then
    if v_periodo.estado <> 'APROBADA' then raise exception 'La planilla debe estar APROBADA.'; end if;
    if not public.appgt_puede_accion_tabla_v1('PLANILLA_PERIODOS_APPGT','APROBAR') then
      raise exception 'No tiene permiso para cerrar planilla.' using errcode='42501';
    end if;
    perform public.appgt_planilla_periodo_totales_v1(v_periodo.id);
    perform set_config('appgt.planilla_transition', '1', true);
    update public."PLANILLA_PERIODOS_APPGT" set estado='CERRADA',
      cerrada_por=auth.uid(), cerrada_at=now() where id=v_periodo.id;
  elsif v_accion = 'REABRIR' then
    if v_periodo.estado <> 'CERRADA' then raise exception 'Solo una planilla CERRADA puede reabrirse.'; end if;
    if not public.appgt_puede_gestionar_configuracion(v_periodo.empresa_id) then
      raise exception 'Solo un administrador o gestor puede reabrir planillas.' using errcode='42501';
    end if;
    if nullif(btrim(p_motivo), '') is null then raise exception 'La reapertura requiere un motivo.'; end if;
    perform set_config('appgt.planilla_transition', '1', true);
    update public."PLANILLA_PERIODOS_APPGT" set estado='CALCULADA',
      ultima_reapertura_por=auth.uid(), ultima_reapertura_at=now(),
      motivo_ultima_reapertura=btrim(p_motivo),
      cantidad_reaperturas=cantidad_reaperturas+1,
      revisada_por=null, revisada_at=null, aprobada_por=null, aprobada_at=null,
      cerrada_por=null, cerrada_at=null where id=v_periodo.id;
  else
    raise exception 'Accion de planilla no reconocida: %.', v_accion;
  end if;

  select * into v_periodo from public."PLANILLA_PERIODOS_APPGT" where id=p_periodo_id;
  insert into public."PLANILLA_AUDITORIA_APPGT" (
    empresa_id, tabla_origen, entidad_id, periodo_id, accion,
    estado_anterior, estado_nuevo, motivo, datos_nuevos
  ) values (
    v_periodo.empresa_id, 'PLANILLA_PERIODOS_APPGT', v_periodo.id::text,
    v_periodo.id, v_accion, v_anterior, v_periodo.estado,
    nullif(btrim(p_motivo), ''), to_jsonb(v_periodo)
  );
  return to_jsonb(v_periodo);
end
$$;

-- Auditoria de los cambios materiales que alimentan o integran la planilla.
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

drop trigger if exists zzzz_appgt_auditar_tareo on public."GT-TAREO_PERSONAL";
create trigger zzzz_appgt_auditar_tareo
after insert or update or delete on public."GT-TAREO_PERSONAL"
for each row execute function public.appgt_auditar_operacion_planilla_v1();
drop trigger if exists zzzz_appgt_auditar_permiso on public."GH_PERMISOS_LICENCIAS_APPGT";
create trigger zzzz_appgt_auditar_permiso
after insert or update or delete on public."GH_PERMISOS_LICENCIAS_APPGT"
for each row execute function public.appgt_auditar_operacion_planilla_v1();
drop trigger if exists zzzz_appgt_auditar_planilla on public."PLANILLA_TRABAJADORES_ZUMAC";
create trigger zzzz_appgt_auditar_planilla
after insert or update or delete on public."PLANILLA_TRABAJADORES_ZUMAC"
for each row execute function public.appgt_auditar_operacion_planilla_v1();

-- ---------------------------------------------------------------------------
-- RLS y privilegios.
-- ---------------------------------------------------------------------------

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'GH_CAMPANAS_LABORALES_APPGT','FIN_TIPOS_CAMBIO_APPGT',
    'GT_INGRESO_MOVILIDADES_APPGT','GH_SANCIONES_PERSONAL_APPGT',
    'PLANILLA_PERIODOS_APPGT'
  ] loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format('drop policy if exists appgt_human_select on public.%I', v_table);
    execute format('drop policy if exists appgt_human_insert on public.%I', v_table);
    execute format('drop policy if exists appgt_human_update on public.%I', v_table);
    execute format('drop policy if exists appgt_human_delete on public.%I', v_table);
    execute format(
      'create policy appgt_human_select on public.%I for select to authenticated
       using (empresa_id=public.appgt_empresa_actual_id() and public.appgt_can_view_table(%L))',
      v_table, v_table
    );
    execute format(
      'create policy appgt_human_insert on public.%I for insert to authenticated
       with check (empresa_id=public.appgt_empresa_actual_id() and public.appgt_can_insert_table(%L))',
      v_table, v_table
    );
    execute format(
      'create policy appgt_human_update on public.%I for update to authenticated
       using (empresa_id=public.appgt_empresa_actual_id() and public.appgt_can_update_table(%L))
       with check (empresa_id=public.appgt_empresa_actual_id() and public.appgt_can_update_table(%L))',
      v_table, v_table, v_table
    );
    execute format(
      'create policy appgt_human_delete on public.%I for delete to authenticated
       using (empresa_id=public.appgt_empresa_actual_id() and public.appgt_can_delete_table(%L))',
      v_table, v_table
    );
    execute format('grant select,insert,update,delete on public.%I to authenticated', v_table);
    execute format('grant all on public.%I to service_role', v_table);
  end loop;
end
$$;

alter table public."PLANILLA_AUDITORIA_APPGT" enable row level security;
drop policy if exists planilla_auditoria_select on public."PLANILLA_AUDITORIA_APPGT";
create policy planilla_auditoria_select
  on public."PLANILLA_AUDITORIA_APPGT" for select to authenticated
  using (
    empresa_id = public.appgt_empresa_actual_id()
    and public.appgt_can_view_table('PLANILLA_AUDITORIA_APPGT')
  );
grant select on public."PLANILLA_AUDITORIA_APPGT" to authenticated;
grant usage, select on sequence public."PLANILLA_AUDITORIA_APPGT_id_seq" to authenticated;
grant all on public."PLANILLA_AUDITORIA_APPGT" to service_role;

revoke all on function public.appgt_autorizar_horas_extra_tareo_v1(text,boolean,text) from public, anon;
revoke all on function public.appgt_cambiar_estado_planilla_periodo_v1(uuid,text,text) from public, anon;
revoke all on function public.appgt_puede_accion_tabla_v1(text,text) from public, anon;
grant execute on function public.appgt_autorizar_horas_extra_tareo_v1(text,boolean,text) to authenticated, service_role;
grant execute on function public.appgt_cambiar_estado_planilla_periodo_v1(uuid,text,text) to authenticated, service_role;
grant execute on function public.appgt_puede_accion_tabla_v1(text,text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Navegacion y formatos. Los ids dependen de la empresa y no colisionan.
-- ---------------------------------------------------------------------------

do $$
declare
  v_rubro record;
  v_suffix text;
  v_attendance text;
  v_permissions text;
  v_payroll text;
  v_format record;
begin
  for v_rubro in
    select r.* from public."RUBROS_APPGT" r
    where r.activo and r.deleted_at is null
  loop
    v_suffix := substr(md5(v_rubro.empresa_id::text), 1, 10);
    v_attendance := 'gh_asistencia_tareo_' || v_suffix;
    v_permissions := 'gh_permisos_licencias_' || v_suffix;
    v_payroll := 'gh_planilla_' || v_suffix;

    for v_format in
      select * from (values
        ('gh_ingreso_movilidad_' || v_suffix, v_attendance,
         'Ingreso de Movilidades', 'GT_INGRESO_MOVILIDADES_APPGT',
         5, 'airport_shuttle', '{"scanner":true}'::jsonb),
        ('gh_sanciones_personal_' || v_suffix, v_permissions,
         'Sanciones de Personal', 'GH_SANCIONES_PERSONAL_APPGT',
         20, 'gavel', '{"auditoria":true}'::jsonb),
        ('gh_planilla_periodos_' || v_suffix, v_payroll,
         'Periodos de Planilla', 'PLANILLA_PERIODOS_APPGT',
         5, 'event_available', '{"ciclo_planilla":true}'::jsonb),
        ('gh_campanas_laborales_' || v_suffix, v_payroll,
         'Campanas Laborales', 'GH_CAMPANAS_LABORALES_APPGT',
         60, 'calendar_month', '{}'::jsonb),
        ('gh_tipos_cambio_' || v_suffix, v_payroll,
         'Tipos de Cambio', 'FIN_TIPOS_CAMBIO_APPGT',
         70, 'currency_exchange', '{}'::jsonb),
        ('gh_auditoria_planilla_' || v_suffix, v_payroll,
         'Auditoria de Planilla', 'PLANILLA_AUDITORIA_APPGT',
         80, 'history', '{"solo_lectura":true}'::jsonb)
      ) as x(id, modulo_id, nombre, tabla_destino, orden, icono, capacidades)
    loop
      insert into public."MATRIZ_FORMATOS_APPGT" (
        id, empresa_id, modulo_id, nombre, tabla_destino, ruta_flutter,
        tabla_visible_app, orden, activo, rubro_id, auditable, icono,
        capacidades, created_at, updated_at, deleted_at, estado_sync, eliminado
      ) values (
        v_format.id, v_rubro.empresa_id, v_format.modulo_id, v_format.nombre,
        v_format.tabla_destino, null, true, v_format.orden, true, v_rubro.id,
        true, v_format.icono, v_format.capacidades,
        now(), now(), null, 'sincronizado', false
      ) on conflict (id) do update set
        empresa_id=excluded.empresa_id, modulo_id=excluded.modulo_id,
        nombre=excluded.nombre, tabla_destino=excluded.tabla_destino,
        tabla_visible_app=true, orden=excluded.orden, activo=true,
        rubro_id=excluded.rubro_id, auditable=true, icono=excluded.icono,
        capacidades=excluded.capacidades, deleted_at=null, eliminado=false,
        updated_at=now();

      insert into public."MATRIZ_FORMATO_TABLAS_APPGT" (
        id, empresa_id, formato_id, nombre, tabla_destino, orden, activo,
        rubro_id, auditable, icono, created_at, updated_at, deleted_at
      ) values (
        v_format.id || '_table', v_rubro.empresa_id, v_format.id,
        v_format.nombre, v_format.tabla_destino, 0, true, v_rubro.id,
        true, v_format.icono, now(), now(), null
      ) on conflict (id) do update set
        empresa_id=excluded.empresa_id, formato_id=excluded.formato_id,
        nombre=excluded.nombre, tabla_destino=excluded.tabla_destino,
        activo=true, rubro_id=excluded.rubro_id, auditable=true,
        icono=excluded.icono, deleted_at=null, updated_at=now();
    end loop;

    update public."MATRIZ_FORMATOS_APPGT"
    set capacidades = coalesce(capacidades, '{}'::jsonb) ||
          '{"aprobaciones":true,"horas_extra":true}'::jsonb,
        auditable=true, updated_at=now()
    where empresa_id=v_rubro.empresa_id
      and upper(coalesce(tabla_destino,''))='GT-TAREO_PERSONAL';
    update public."MATRIZ_FORMATOS_APPGT"
    set capacidades = coalesce(capacidades, '{}'::jsonb) ||
          '{"aprobaciones":true,"firma":true}'::jsonb,
        auditable=true, updated_at=now()
    where empresa_id=v_rubro.empresa_id
      and upper(coalesce(tabla_destino,''))='GH_PERMISOS_LICENCIAS_APPGT';
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- Campos para formularios genericos, tablas, importacion y exportacion.
-- ---------------------------------------------------------------------------

insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id, tabla_destino, campo, etiqueta, tipo, tipo_ui, id_campo_dropdown,
  requerido, visible, visible_tabla, editable, orden, activo,
  created_at, updated_at, estado_sync, eliminado
) values
  ('gh_mov_fecha','GT_INGRESO_MOVILIDADES_APPGT','fecha','Fecha','date','date',null,true,true,true,true,1,true,now(),now(),'sincronizado',false),
  ('gh_mov_hora','GT_INGRESO_MOVILIDADES_APPGT','hora_ingreso','Hora de ingreso','time','time',null,true,true,true,true,2,true,now(),now(),'sincronizado',false),
  ('gh_mov_placa','GT_INGRESO_MOVILIDADES_APPGT','placa','Placa','text','scanner',null,true,true,true,true,3,true,now(),now(),'sincronizado',false),
  ('gh_mov_codigo','GT_INGRESO_MOVILIDADES_APPGT','movilidad_codigo','Codigo de movilidad','text','text',null,false,true,true,true,4,true,now(),now(),'sincronizado',false),
  ('gh_mov_proveedor','GT_INGRESO_MOVILIDADES_APPGT','proveedor','Proveedor','text','text',null,false,true,true,true,5,true,now(),now(),'sincronizado',false),
  ('gh_mov_dni','GT_INGRESO_MOVILIDADES_APPGT','conductor_dni','DNI del conductor','text','scanner',null,true,true,true,true,6,true,now(),now(),'sincronizado',false),
  ('gh_mov_conductor','GT_INGRESO_MOVILIDADES_APPGT','conductor_nombre','Conductor','text','text',null,true,true,true,true,7,true,now(),now(),'sincronizado',false),
  ('gh_mov_licencia','GT_INGRESO_MOVILIDADES_APPGT','licencia_conducir','Licencia de conducir','text','text',null,false,true,true,true,8,true,now(),now(),'sincronizado',false),
  ('gh_mov_licencia_vig','GT_INGRESO_MOVILIDADES_APPGT','licencia_vigencia','Vigencia de licencia','date','date',null,false,true,true,true,9,true,now(),now(),'sincronizado',false),
  ('gh_mov_doc_conductor','GT_INGRESO_MOVILIDADES_APPGT','documento_conductor','Documento del conductor','text','photo',null,false,true,true,true,10,true,now(),now(),'sincronizado',false),
  ('gh_mov_doc_vehiculo','GT_INGRESO_MOVILIDADES_APPGT','documento_vehiculo','Documento del vehiculo','text','photo',null,false,true,true,true,11,true,now(),now(),'sincronizado',false),
  ('gh_mov_soat','GT_INGRESO_MOVILIDADES_APPGT','soat_vigencia','Vigencia SOAT','date','date',null,false,true,true,true,12,true,now(),now(),'sincronizado',false),
  ('gh_mov_revision','GT_INGRESO_MOVILIDADES_APPGT','revision_tecnica_vigencia','Vigencia revision tecnica','date','date',null,false,true,true,true,13,true,now(),now(),'sincronizado',false),
  ('gh_mov_capacidad','GT_INGRESO_MOVILIDADES_APPGT','capacidad','Capacidad','integer','number',null,false,true,true,true,14,true,now(),now(),'sincronizado',false),
  ('gh_mov_personas','GT_INGRESO_MOVILIDADES_APPGT','cantidad_personas','Personas transportadas','integer','number',null,false,true,true,true,15,true,now(),now(),'sincronizado',false),
  ('gh_mov_estado','GT_INGRESO_MOVILIDADES_APPGT','estado','Estado','text','dropdown','[BORRADOR;ADMITIDA;RECHAZADA;CERRADA;ANULADA]',true,true,true,true,16,true,now(),now(),'sincronizado',false),
  ('gh_mov_obs','GT_INGRESO_MOVILIDADES_APPGT','observaciones','Observaciones','text','multiline',null,false,true,true,true,17,true,now(),now(),'sincronizado',false),

  ('gh_san_numero','GH_SANCIONES_PERSONAL_APPGT','numero_sancion','Numero de sancion','hidden_id','hidden_id',null,true,false,true,false,1,true,now(),now(),'sincronizado',false),
  ('gh_san_dni','GH_SANCIONES_PERSONAL_APPGT','dni','DNI','text','scanner',null,true,true,true,true,2,true,now(),now(),'sincronizado',false),
  ('gh_san_trabajador','GH_SANCIONES_PERSONAL_APPGT','trabajador','Trabajador','text','text',null,true,true,true,true,3,true,now(),now(),'sincronizado',false),
  ('gh_san_tipo','GH_SANCIONES_PERSONAL_APPGT','tipo_sancion','Tipo de sancion','text','dropdown','[AMONESTACION VERBAL;AMONESTACION ESCRITA;SUSPENSION DE LABORES;OTRA]',true,true,true,true,4,true,now(),now(),'sincronizado',false),
  ('gh_san_inicio','GH_SANCIONES_PERSONAL_APPGT','fecha_inicio','Fecha de inicio','date','date',null,true,true,true,true,5,true,now(),now(),'sincronizado',false),
  ('gh_san_fin','GH_SANCIONES_PERSONAL_APPGT','fecha_fin','Fecha de fin','date','date',null,true,true,true,true,6,true,now(),now(),'sincronizado',false),
  ('gh_san_bloquea','GH_SANCIONES_PERSONAL_APPGT','bloquea_asistencia','Bloquea asistencia','boolean','switch',null,true,true,true,true,7,true,now(),now(),'sincronizado',false),
  ('gh_san_motivo','GH_SANCIONES_PERSONAL_APPGT','motivo','Motivo','text','multiline',null,true,true,true,true,8,true,now(),now(),'sincronizado',false),
  ('gh_san_doc','GH_SANCIONES_PERSONAL_APPGT','documento_sustento','Documento de sustento','text','photo',null,false,true,true,true,9,true,now(),now(),'sincronizado',false),
  ('gh_san_estado','GH_SANCIONES_PERSONAL_APPGT','estado','Estado','text','dropdown','[BORRADOR;VIGENTE;CUMPLIDA;ANULADA]',true,true,true,true,10,true,now(),now(),'sincronizado',false),

  ('gh_periodo_codigo','PLANILLA_PERIODOS_APPGT','codigo','Codigo','text','text',null,true,true,true,true,1,true,now(),now(),'sincronizado',false),
  ('gh_periodo_desc','PLANILLA_PERIODOS_APPGT','descripcion','Descripcion','text','text',null,false,true,true,true,2,true,now(),now(),'sincronizado',false),
  ('gh_periodo_inicio','PLANILLA_PERIODOS_APPGT','fecha_inicio','Fecha de inicio','date','date',null,true,true,true,true,3,true,now(),now(),'sincronizado',false),
  ('gh_periodo_fin','PLANILLA_PERIODOS_APPGT','fecha_fin','Fecha de fin','date','date',null,true,true,true,true,4,true,now(),now(),'sincronizado',false),
  ('gh_periodo_campana','PLANILLA_PERIODOS_APPGT','campana','Campana','text','text',null,false,true,true,true,5,true,now(),now(),'sincronizado',false),
  ('gh_periodo_moneda','PLANILLA_PERIODOS_APPGT','moneda','Moneda','text','dropdown','[PEN;USD]',true,true,true,true,6,true,now(),now(),'sincronizado',false),
  ('gh_periodo_tc','PLANILLA_PERIODOS_APPGT','tipo_cambio','Tipo de cambio PEN/USD','numeric','number',null,true,true,true,true,7,true,now(),now(),'sincronizado',false),
  ('gh_periodo_estado','PLANILLA_PERIODOS_APPGT','estado','Estado','text','readonly',null,false,true,true,false,8,true,now(),now(),'sincronizado',false),
  ('gh_periodo_bruto','PLANILLA_PERIODOS_APPGT','total_bruto','Total bruto','numeric','number',null,false,false,true,false,9,true,now(),now(),'sincronizado',false),
  ('gh_periodo_descuentos','PLANILLA_PERIODOS_APPGT','total_descuentos_trabajador','Descuentos del trabajador','numeric','number',null,false,false,true,false,10,true,now(),now(),'sincronizado',false),
  ('gh_periodo_neto','PLANILLA_PERIODOS_APPGT','total_neto_pagar','Neto a pagar','numeric','number',null,false,false,true,false,11,true,now(),now(),'sincronizado',false),
  ('gh_periodo_aportes','PLANILLA_PERIODOS_APPGT','total_aportes_empleador','Aportes del empleador','numeric','number',null,false,false,true,false,12,true,now(),now(),'sincronizado',false),
  ('gh_periodo_beneficios','PLANILLA_PERIODOS_APPGT','total_beneficios_provisionados','Beneficios provisionados','numeric','number',null,false,false,true,false,13,true,now(),now(),'sincronizado',false),
  ('gh_periodo_costo','PLANILLA_PERIODOS_APPGT','total_costo_empresa','Costo total empresa','numeric','number',null,false,false,true,false,14,true,now(),now(),'sincronizado',false),
  ('gh_periodo_reaperturas','PLANILLA_PERIODOS_APPGT','cantidad_reaperturas','Reaperturas','integer','number',null,false,false,true,false,15,true,now(),now(),'sincronizado',false),
  ('gh_periodo_motivo_reap','PLANILLA_PERIODOS_APPGT','motivo_ultima_reapertura','Motivo ultima reapertura','text','readonly',null,false,false,true,false,16,true,now(),now(),'sincronizado',false),

  ('gh_camp_codigo','GH_CAMPANAS_LABORALES_APPGT','codigo','Codigo','text','text',null,true,true,true,true,1,true,now(),now(),'sincronizado',false),
  ('gh_camp_nombre','GH_CAMPANAS_LABORALES_APPGT','nombre','Campana','text','text',null,true,true,true,true,2,true,now(),now(),'sincronizado',false),
  ('gh_camp_inicio','GH_CAMPANAS_LABORALES_APPGT','fecha_inicio','Fecha de inicio','date','date',null,true,true,true,true,3,true,now(),now(),'sincronizado',false),
  ('gh_camp_fin','GH_CAMPANAS_LABORALES_APPGT','fecha_fin','Fecha de fin','date','date',null,true,true,true,true,4,true,now(),now(),'sincronizado',false),
  ('gh_camp_activa','GH_CAMPANAS_LABORALES_APPGT','activa','Activa','boolean','switch',null,true,true,true,true,5,true,now(),now(),'sincronizado',false),
  ('gh_camp_default','GH_CAMPANAS_LABORALES_APPGT','es_predeterminada','Predeterminada','boolean','switch',null,true,true,true,true,6,true,now(),now(),'sincronizado',false),

  ('gh_tc_fecha','FIN_TIPOS_CAMBIO_APPGT','fecha','Fecha','date','date',null,true,true,true,true,1,true,now(),now(),'sincronizado',false),
  ('gh_tc_origen','FIN_TIPOS_CAMBIO_APPGT','moneda_origen','Moneda origen','text','dropdown','[USD;EUR]',true,true,true,true,2,true,now(),now(),'sincronizado',false),
  ('gh_tc_destino','FIN_TIPOS_CAMBIO_APPGT','moneda_destino','Moneda destino','text','dropdown','[PEN]',true,true,true,true,3,true,now(),now(),'sincronizado',false),
  ('gh_tc_valor','FIN_TIPOS_CAMBIO_APPGT','tipo_cambio','Tipo de cambio','numeric','number',null,true,true,true,true,4,true,now(),now(),'sincronizado',false),
  ('gh_tc_fuente','FIN_TIPOS_CAMBIO_APPGT','fuente','Fuente','text','text',null,false,true,true,true,5,true,now(),now(),'sincronizado',false),

  ('gh_aud_fecha','PLANILLA_AUDITORIA_APPGT','ejecutado_at','Fecha y hora','datetime','datetime',null,false,true,true,false,1,true,now(),now(),'sincronizado',false),
  ('gh_aud_tabla','PLANILLA_AUDITORIA_APPGT','tabla_origen','Origen','text','readonly',null,false,true,true,false,2,true,now(),now(),'sincronizado',false),
  ('gh_aud_entidad','PLANILLA_AUDITORIA_APPGT','entidad_id','Registro','text','readonly',null,false,true,true,false,3,true,now(),now(),'sincronizado',false),
  ('gh_aud_dni','PLANILLA_AUDITORIA_APPGT','dni','DNI','text','readonly',null,false,true,true,false,4,true,now(),now(),'sincronizado',false),
  ('gh_aud_accion','PLANILLA_AUDITORIA_APPGT','accion','Accion','text','readonly',null,false,true,true,false,5,true,now(),now(),'sincronizado',false),
  ('gh_aud_anterior','PLANILLA_AUDITORIA_APPGT','estado_anterior','Estado anterior','text','readonly',null,false,true,true,false,6,true,now(),now(),'sincronizado',false),
  ('gh_aud_nuevo','PLANILLA_AUDITORIA_APPGT','estado_nuevo','Estado nuevo','text','readonly',null,false,true,true,false,7,true,now(),now(),'sincronizado',false),
  ('gh_aud_motivo','PLANILLA_AUDITORIA_APPGT','motivo','Motivo','text','readonly',null,false,true,true,false,8,true,now(),now(),'sincronizado',false)
on conflict (tabla_destino, campo) do update set
  etiqueta=excluded.etiqueta, tipo=excluded.tipo, tipo_ui=excluded.tipo_ui,
  id_campo_dropdown=excluded.id_campo_dropdown, requerido=excluded.requerido,
  visible=excluded.visible, visible_tabla=excluded.visible_tabla,
  editable=excluded.editable, orden=excluded.orden, activo=true,
  eliminado=false, updated_at=now();

insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id, tabla_destino, campo, etiqueta, tipo, tipo_ui, id_campo_dropdown,
  requerido, visible, visible_tabla, editable, orden, activo,
  created_at, updated_at, estado_sync, eliminado
) values
  ('gh_personal_area','GH-REGISTRO_PERSONAL_PLANILLA','AREA','Area','text','text',null,false,true,true,true,30,true,now(),now(),'sincronizado',false),
  ('gh_personal_grupo','GH-REGISTRO_PERSONAL_PLANILLA','GRUPO_COSTO','Grupo de costo','text','dropdown','[EMPLEADO;OBRERO;ADMINISTRATIVO;OTRO]',false,true,true,true,31,true,now(),now(),'sincronizado',false),
  ('gh_personal_campana','GH-REGISTRO_PERSONAL_PLANILLA','CAMPANA','Campana','text','text',null,false,true,true,true,32,true,now(),now(),'sincronizado',false),
  ('gh_tareo_estado_ap','GT-TAREO_PERSONAL','ESTADO_APROBACION','Estado de aprobacion','text','readonly',null,false,false,true,false,90,true,now(),now(),'sincronizado',false),
  ('gh_tareo_req_he','GT-TAREO_PERSONAL','REQUIERE_HORAS_EXTRA','Requiere horas extra','boolean','switch',null,false,false,true,false,91,true,now(),now(),'sincronizado',false),
  ('gh_tareo_horas_he','GT-TAREO_PERSONAL','HORAS_EXTRA_SOLICITADAS','Horas extra solicitadas','numeric','number',null,false,false,true,false,92,true,now(),now(),'sincronizado',false),
  ('gh_tareo_motivo_he','GT-TAREO_PERSONAL','MOTIVO_HORAS_EXTRA','Motivo de horas extra','text','multiline',null,false,true,true,true,93,true,now(),now(),'sincronizado',false),
  ('gh_tareo_estado_he','GT-TAREO_PERSONAL','ESTADO_HORAS_EXTRA','Estado de horas extra','text','readonly',null,false,false,true,false,94,true,now(),now(),'sincronizado',false),
  ('gh_perm_estado_ap','GH_PERMISOS_LICENCIAS_APPGT','ESTADO_APROBACION','Estado de aprobacion','text','readonly',null,false,false,true,false,20,true,now(),now(),'sincronizado',false),
  ('gh_perm_reincorp','GH_PERMISOS_LICENCIAS_APPGT','fecha_reincorporacion','Fecha de reincorporacion','date','readonly',null,false,false,true,false,21,true,now(),now(),'sincronizado',false),
  ('gh_perm_empresa','GH_PERMISOS_LICENCIAS_APPGT','empresa_nombre','Empresa','text','readonly',null,false,false,false,false,22,true,now(),now(),'sincronizado',false),
  ('gh_perm_ruc','GH_PERMISOS_LICENCIAS_APPGT','empresa_ruc','RUC','text','readonly',null,false,false,false,false,23,true,now(),now(),'sincronizado',false),
  ('gh_plan_area','PLANILLA_TRABAJADORES_ZUMAC','area','Area','text','readonly',null,false,true,true,false,60,true,now(),now(),'sincronizado',false),
  ('gh_plan_grupo','PLANILLA_TRABAJADORES_ZUMAC','grupo_costo','Grupo de costo','text','readonly',null,false,true,true,false,61,true,now(),now(),'sincronizado',false),
  ('gh_plan_campana','PLANILLA_TRABAJADORES_ZUMAC','campana','Campana','text','readonly',null,false,true,true,false,62,true,now(),now(),'sincronizado',false),
  ('gh_plan_moneda','PLANILLA_TRABAJADORES_ZUMAC','moneda','Moneda','text','readonly',null,false,true,true,false,63,true,now(),now(),'sincronizado',false),
  ('gh_plan_tc','PLANILLA_TRABAJADORES_ZUMAC','tipo_cambio','Tipo de cambio','numeric','number',null,false,true,true,false,64,true,now(),now(),'sincronizado',false),
  ('gh_plan_bruto_sep','PLANILLA_TRABAJADORES_ZUMAC','remuneracion_bruta','Remuneracion bruta','numeric','number',null,false,true,true,false,65,true,now(),now(),'sincronizado',false),
  ('gh_plan_deducciones','PLANILLA_TRABAJADORES_ZUMAC','deducciones_trabajador','Deducciones del trabajador','numeric','number',null,false,true,true,false,66,true,now(),now(),'sincronizado',false),
  ('gh_plan_neto','PLANILLA_TRABAJADORES_ZUMAC','neto_pagar','Neto a pagar','numeric','number',null,false,true,true,false,67,true,now(),now(),'sincronizado',false),
  ('gh_plan_aportes','PLANILLA_TRABAJADORES_ZUMAC','aportes_empleador','Aportes del empleador','numeric','number',null,false,true,true,false,68,true,now(),now(),'sincronizado',false),
  ('gh_plan_beneficios','PLANILLA_TRABAJADORES_ZUMAC','beneficios_provisionados','Beneficios provisionados','numeric','number',null,false,true,true,false,69,true,now(),now(),'sincronizado',false),
  ('gh_plan_otros','PLANILLA_TRABAJADORES_ZUMAC','otros_costos_empresa','Otros costos empresa','numeric','number',null,false,true,true,true,70,true,now(),now(),'sincronizado',false),
  ('gh_plan_costo_total','PLANILLA_TRABAJADORES_ZUMAC','costo_total_empresa','Costo total empresa','numeric','number',null,false,true,true,false,71,true,now(),now(),'sincronizado',false),
  ('gh_plan_costo_usd','PLANILLA_TRABAJADORES_ZUMAC','costo_total_usd','Costo total USD','numeric','number',null,false,true,true,false,72,true,now(),now(),'sincronizado',false)
on conflict (tabla_destino, campo) do update set
  etiqueta=excluded.etiqueta, tipo=excluded.tipo, tipo_ui=excluded.tipo_ui,
  id_campo_dropdown=excluded.id_campo_dropdown, requerido=excluded.requerido,
  visible=excluded.visible, visible_tabla=excluded.visible_tabla,
  editable=excluded.editable, orden=excluded.orden, activo=true,
  eliminado=false, updated_at=now();

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set id_generador='SAN', updated_at=now()
where tabla_destino='GH_SANCIONES_PERSONAL_APPGT' and campo='numero_sancion';

-- Hereda permisos de Gestion Humana y conserva Revisar/Aprobar. Los
-- administradores y gestores reciben todas las acciones de los formatos nuevos.
with human_access as (
  select p.empresa_id, p.user_id,
    bool_or(p.can_view) can_view, bool_or(p.can_insert) can_insert,
    bool_or(p.can_update) can_update, bool_or(p.can_delete) can_delete,
    bool_or(p.can_export) can_export, bool_or(p.can_import) can_import,
    bool_or(p.can_review) can_review, bool_or(p.can_approve) can_approve
  from public."PERMISOS_DE_USUARIOS_APPGT" p
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id=p.empresa_id and m.id=p.modulo
  join public."MATRIZ_SECCIONES_APPGT" s
    on s.empresa_id=m.empresa_id and s.id=m.seccion
  where p.user_id is not null and p.activo and not p.eliminado
    and public.appgt_normalizar_clave(s.nombre)='GESTIONHUMANA'
  group by p.empresa_id,p.user_id
), admin_access as (
  select ue.empresa_id,ue.user_id,
    true can_view,true can_insert,true can_update,true can_delete,
    true can_export,true can_import,true can_review,true can_approve
  from public."USUARIOS_EMPRESAS_APPGT" ue
  where ue.activo and ue.rol in ('ADMIN','GESTOR')
), access_by_user as (
  select empresa_id,user_id,bool_or(can_view) can_view,
    bool_or(can_insert) can_insert,bool_or(can_update) can_update,
    bool_or(can_delete) can_delete,bool_or(can_export) can_export,
    bool_or(can_import) can_import,bool_or(can_review) can_review,
    bool_or(can_approve) can_approve
  from (select * from human_access union all select * from admin_access) x
  group by empresa_id,user_id
), targets as (
  select f.empresa_id,f.id formato_id,f.tabla_destino,f.modulo_id,m.seccion
  from public."MATRIZ_FORMATOS_APPGT" f
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id=f.empresa_id and m.id=f.modulo_id
  where f.tabla_destino in (
    'GT_INGRESO_MOVILIDADES_APPGT','GH_SANCIONES_PERSONAL_APPGT',
    'PLANILLA_PERIODOS_APPGT','GH_CAMPANAS_LABORALES_APPGT',
    'FIN_TIPOS_CAMBIO_APPGT','PLANILLA_AUDITORIA_APPGT'
  ) and f.activo and not f.eliminado
)
insert into public."PERMISOS_DE_USUARIOS_APPGT" (
  empresa_id,user_id,seccion,modulo,formato,tabla_destino,
  can_view,can_insert,can_update,can_delete,can_export,can_import,
  can_review,can_approve,activo,created_at,updated_at,estado_sync,eliminado
)
select a.empresa_id,a.user_id,t.seccion,t.modulo_id,t.formato_id,t.tabla_destino,
  a.can_view,a.can_insert,a.can_update,a.can_delete,a.can_export,a.can_import,
  a.can_review,a.can_approve,true,now(),now(),'sincronizado',false
from access_by_user a join targets t on t.empresa_id=a.empresa_id
on conflict (user_id,modulo,formato) do update set
  empresa_id=excluded.empresa_id,seccion=excluded.seccion,
  tabla_destino=excluded.tabla_destino,can_view=excluded.can_view,
  can_insert=excluded.can_insert,can_update=excluded.can_update,
  can_delete=excluded.can_delete,can_export=excluded.can_export,
  can_import=excluded.can_import,can_review=excluded.can_review,
  can_approve=excluded.can_approve,activo=true,eliminado=false,updated_at=now();

commit;
