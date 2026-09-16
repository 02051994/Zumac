begin;

-- ---------------------------------------------------------------------------
-- Integridad de negocio: evita altas simultáneas con claves de negocio iguales.
-- id_local continúa siendo la clave técnica de reintentos; estas reglas cubren
-- el caso multiusuario/dispositivo y excluyen siempre los borrados lógicos.
-- ---------------------------------------------------------------------------

create table if not exists public."APPGT_REGLAS_DUPLICADO_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  tabla_destino text not null,
  campos_clave text[] not null check (cardinality(campos_clave) > 0),
  activo boolean not null default true,
  descripcion text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (empresa_id, tabla_destino)
);

create or replace function public.appgt_evitar_duplicado_semantico_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_regla record;
  v_new jsonb := to_jsonb(new);
  v_empresa text := coalesce(v_new ->> 'empresa_id', '');
  v_id text := coalesce(v_new ->> 'id_local', v_new ->> 'id', '');
  v_campo text;
  v_valor text;
  v_firma text := '';
  v_where text := '';
  v_sql text;
  v_duplicado boolean := false;
begin
  if coalesce(lower(v_new ->> 'eliminado'), 'false') in ('true','1','si','sí')
     or nullif(v_new ->> 'deleted_at', '') is not null then
    return new;
  end if;

  select * into v_regla
  from public."APPGT_REGLAS_DUPLICADO_APPGT" r
  where r.empresa_id::text = v_empresa
    and upper(r.tabla_destino) = upper(tg_table_name)
    and r.activo
  limit 1;
  if not found then return new; end if;

  foreach v_campo in array v_regla.campos_clave loop
    v_valor := lower(btrim(coalesce(v_new ->> v_campo, '')));
    -- Una clave parcial no se bloquea: los campos requeridos siguen siendo
    -- responsabilidad del formulario y de sus validaciones propias.
    if v_valor = '' then return new; end if;
    v_firma := v_firma || '|' || lower(v_campo) || '=' || v_valor;
    v_where := v_where || format(
      ' and lower(btrim(coalesce(to_jsonb(t)->>%L, ''''))) = %L',
      v_campo, v_valor
    );
  end loop;

  -- El candado transaccional hace que dos inserciones concurrentes con la
  -- misma firma se serialicen antes de comprobar la existencia de la fila.
  perform pg_advisory_xact_lock(hashtextextended(
    upper(tg_table_name) || '|' || v_empresa || v_firma, 0
  ));

  v_sql := format(
    'select exists (select 1 from public.%I t where '
    || 'coalesce(lower(to_jsonb(t)->>''eliminado''),''false'') not in (''true'',''1'',''si'',''sí'') '
    || 'and nullif(to_jsonb(t)->>''deleted_at'','''') is null '
    || 'and coalesce(to_jsonb(t)->>''empresa_id'','''') = %L '
    || 'and coalesce(to_jsonb(t)->>''id_local'',to_jsonb(t)->>''id'','''') is distinct from %L %s)',
    tg_table_name, v_empresa, v_id, v_where
  );
  execute v_sql into v_duplicado;
  if v_duplicado then
    raise exception 'APPGT_DUPLICATE: Ya existe un registro activo con la misma clave de negocio (%).',
      array_to_string(v_regla.campos_clave, ', ')
      using errcode = '23505';
  end if;
  return new;
end;
$$;

create or replace function public.appgt_instalar_antiduplicado_tabla_v1(p_tabla text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_tabla is null or btrim(p_tabla) = ''
     or to_regclass(format('public.%I', p_tabla)) is null then
    return;
  end if;
  execute format('drop trigger if exists appgt_10_evitar_duplicado_semantico on public.%I', p_tabla);
  execute format(
    'create trigger appgt_10_evitar_duplicado_semantico '
    || 'before insert or update on public.%I '
    || 'for each row execute function public.appgt_evitar_duplicado_semantico_v1()',
    p_tabla
  );
end;
$$;

create or replace function public.appgt_instalar_antiduplicado_desde_matriz_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.appgt_instalar_antiduplicado_tabla_v1(new.tabla_destino);
  return new;
end;
$$;

drop trigger if exists appgt_90_instalar_antiduplicado_desde_matriz
  on public."MATRIZ_FORMATO_TABLAS_APPGT";
create trigger appgt_90_instalar_antiduplicado_desde_matriz
after insert or update of tabla_destino on public."MATRIZ_FORMATO_TABLAS_APPGT"
for each row execute function public.appgt_instalar_antiduplicado_desde_matriz_v1();

insert into public."APPGT_REGLAS_DUPLICADO_APPGT" (
  empresa_id, tabla_destino, campos_clave, descripcion
)
select e.id, x.tabla_destino, x.campos_clave, x.descripcion
from public."EMPRESAS_APPGT" e
cross join (values
  ('GH-REGISTRO_PERSONAL_PLANILLA', array['DNI'],
    'Una ficha laboral activa por DNI.'),
  ('GT-ASISTENCIA_PERSONAL', array['DNI','FECHA'],
    'Una marcación de asistencia por trabajador y fecha.'),
  ('GT-TAREO_PERSONAL', array['DNI','FECHA','LABOR'],
    'Un tareo por trabajador, fecha y labor.'),
  ('GH_PERMISOS_LICENCIAS_APPGT', array['dni','fecha_inicio','fecha_fin','tipo_ausencia'],
    'Evita solicitudes idénticas de permiso o licencia.'),
  ('PLANILLA_PERIODOS_APPGT', array['fecha_inicio','fecha_fin'],
    'Un único período de planilla para el mismo rango.'),
  ('GT-MATRIZ_MOVILIDADES', array['placa'],
    'Una movilidad maestra activa por placa.')
) as x(tabla_destino, campos_clave, descripcion)
on conflict (empresa_id, tabla_destino) do update set
  campos_clave = excluded.campos_clave,
  descripcion = excluded.descripcion,
  activo = true,
  updated_at = now();

do $$
declare v_tabla text;
begin
  for v_tabla in select distinct tabla_destino
    from public."APPGT_REGLAS_DUPLICADO_APPGT" where activo
  loop
    perform public.appgt_instalar_antiduplicado_tabla_v1(v_tabla);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Movilidad: costo por asiento a cargo de la empresa, separado del importe
-- que aparece en la boleta del trabajador.
-- ---------------------------------------------------------------------------

alter table public."GT-MATRIZ_MOVILIDADES"
  add column if not exists costo_total numeric(18,6) not null default 0,
  add column if not exists costo_asiento numeric(18,6) not null default 0;

alter table public."PLANILLA_TRABAJADORES_ZUMAC"
  add column if not exists costo_boleta_trabajador numeric(18,6) not null default 0,
  add column if not exists costo_movilidad_empresa numeric(18,6) not null default 0,
  add column if not exists costo_total_con_movilidad numeric(18,6) not null default 0;

alter table public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT"
  add column if not exists costo_boleta_trabajador numeric(18,6) not null default 0,
  add column if not exists costo_movilidad_empresa numeric(18,6) not null default 0,
  add column if not exists costo_total_con_movilidad numeric(18,6) not null default 0;

alter table public."PLANILLA_PERIODOS_APPGT"
  add column if not exists total_movilidad_empresa numeric(20,6) not null default 0,
  add column if not exists validada_por uuid references auth.users(id),
  add column if not exists validada_at timestamptz;

create or replace function public.appgt_costo_movilidad_diaria_v1(
  p_empresa uuid, p_dni text, p_fecha date
)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum(
    case
      when coalesce(m.costo_asiento, 0) > 0 then m.costo_asiento
      when coalesce(m.costo_total, 0) > 0
        and coalesce(nullif(public.appgt_jsonb_numeric(to_jsonb(m), array['capacidad','CAPACIDAD'], 0), 0), 0) > 0
      then round(m.costo_total / public.appgt_jsonb_numeric(to_jsonb(m), array['capacidad','CAPACIDAD'], 0), 6)
      else 0
    end
  ), 0)
  from public."GT-ASISTENCIA_PERSONAL" a
  join public."GT-MATRIZ_MOVILIDADES" m
    on public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(m), array['placa','PLACA']))
     = public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(a), array['PLACA','placa','MOVILIDAD']))
  where a.empresa_id = p_empresa
    and m.empresa_id = p_empresa
    and public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(a), array['DNI','dni','DOCUMENTO']))
      = public.appgt_normalizar_clave(p_dni)
    and public.appgt_jsonb_date(to_jsonb(a), array['FECHA','FECHA_INGRESO']) = p_fecha
    and not coalesce(a.eliminado, false) and a.deleted_at is null
    and not coalesce(m.eliminado, false) and m.deleted_at is null
$$;

create or replace function public.appgt_asignar_costos_visibles_planilla_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  new.costo_boleta_trabajador := round(coalesce(new.neto_pagar, new.total_neto, 0), 6);
  new.costo_movilidad_empresa := round(
    public.appgt_costo_movilidad_diaria_v1(new.empresa_id, new.dni, new.fecha), 6
  );
  new.costo_total_con_movilidad := round(
    new.costo_boleta_trabajador + new.costo_movilidad_empresa, 6
  );
  return new;
end;
$$;

drop trigger if exists zzzz_appgt_asignar_costos_visibles_planilla
  on public."PLANILLA_TRABAJADORES_ZUMAC";
create trigger zzzz_appgt_asignar_costos_visibles_planilla
before insert or update on public."PLANILLA_TRABAJADORES_ZUMAC"
for each row execute function public.appgt_asignar_costos_visibles_planilla_v1();

create or replace function public.appgt_asignar_costos_liquidacion_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_periodo record;
begin
  select fecha_inicio, fecha_fin into v_periodo
  from public."PLANILLA_PERIODOS_APPGT" where id = new.periodo_id;
  new.costo_boleta_trabajador := round(coalesce(new.neto_pagar, 0), 6);
  new.costo_movilidad_empresa := round(coalesce((
    select sum(public.appgt_costo_movilidad_diaria_v1(new.empresa_id, new.dni, d::date))
    from generate_series(v_periodo.fecha_inicio, v_periodo.fecha_fin, interval '1 day') d
  ), 0), 6);
  new.costo_total_con_movilidad := round(
    coalesce(new.costo_total_empresa, 0) + new.costo_movilidad_empresa, 6
  );
  return new;
end;
$$;

drop trigger if exists zzzz_appgt_asignar_costos_liquidacion
  on public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT";
create trigger zzzz_appgt_asignar_costos_liquidacion
before insert or update on public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT"
for each row execute function public.appgt_asignar_costos_liquidacion_v1();

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
    total_movilidad_empresa=x.movilidad,
    total_costo_empresa=x.costo,
    cantidad_trabajadores=x.trabajadores,
    motor_calculo='PERU_LEGAL_V2_CON_MOVILIDAD', updated_at=now()
  from (
    select coalesce(sum(remuneracion_bruta),0) bruto,
      coalesce(sum(total_descuentos),0) descuentos,
      coalesce(sum(neto_pagar),0) neto,
      coalesce(sum(deposito_cts),0) cts,
      coalesce(sum(total_desembolso_trabajador),0) desembolso,
      coalesce(sum(essalud_empleador+sctr_salud+sctr_pension),0) aportes,
      coalesce(sum(total_provisiones),0) provisiones,
      coalesce(sum(costo_movilidad_empresa),0) movilidad,
      coalesce(sum(costo_total_con_movilidad),0) costo,
      count(*)::integer trabajadores
    from public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT"
    where periodo_id=p_periodo
  ) x where p.id=p_periodo;
end;
$$;

-- Un cesado se liquida en su período final cuando la fecha de cese está dentro
-- del rango. La fórmula legal existente se conserva; solo se amplía el universo
-- de trabajadores que entra a ella.
do $$
declare
  v_sql text;
  v_old text := $find$
      and public.appgt_normalizar_clave(
      public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
    )='ACTIVO'$find$;
  v_new text := $replace$
      and (
        public.appgt_normalizar_clave(
          public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
        )='ACTIVO'
        or (
          public.appgt_normalizar_clave(
            public.appgt_jsonb_text(to_jsonb(p),array['Status','ESTADO','ESTADO_PERSONAL'])
          )='CESADO'
          and public.appgt_jsonb_date(to_jsonb(p),array['Fecha fin de Contrato','FECHA_FIN_CONTRATO'])
              between v_periodo.fecha_inicio and v_periodo.fecha_fin
        )
      )$replace$;
begin
  select pg_get_functiondef('public.appgt_calcular_liquidacion_periodo_v2(uuid)'::regprocedure)
    into v_sql;
  if position(v_old in v_sql) = 0 then
    raise exception 'No se pudo ampliar el motor de liquidación para ceses: definición inesperada.';
  end if;
  execute replace(v_sql, v_old, v_new);
end;
$$;

-- ---------------------------------------------------------------------------
-- Validación previa, aprobaciones de fuente y boletas de pago.
-- La asistencia es marcación única; tareo y permisos sí deben estar aprobados.
-- ---------------------------------------------------------------------------

do $$
begin
  if to_regprocedure('public.appgt_generar_validaciones_planilla_legacy_048(uuid)') is null
     and to_regprocedure('public.appgt_generar_validaciones_planilla_v2(uuid)') is not null then
    alter function public.appgt_generar_validaciones_planilla_v2(uuid)
      rename to appgt_generar_validaciones_planilla_legacy_048;
  end if;
end;
$$;

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
  v_count := public.appgt_generar_validaciones_planilla_legacy_048(p_periodo);
  select * into v_periodo from public."PLANILLA_PERIODOS_APPGT"
  where id=p_periodo and empresa_id=public.appgt_empresa_actual_id()
    and not eliminado and deleted_at is null;
  if not found then raise exception 'Periodo de planilla no encontrado.'; end if;

  insert into public."PLANILLA_VALIDACIONES_APPGT"
    (empresa_id,periodo_id,nivel,codigo,dni,mensaje)
  select distinct v_periodo.empresa_id,p_periodo,'ERROR','PERMISO_NO_APROBADO',q.dni,
    'Existe permiso o licencia pendiente de aprobación dentro del período.'
  from public."GH_PERMISOS_LICENCIAS_APPGT" q
  where q.empresa_id=v_periodo.empresa_id
    and daterange(q.fecha_inicio,q.fecha_fin,'[]') &&
      daterange(v_periodo.fecha_inicio,v_periodo.fecha_fin,'[]')
    and coalesce(q."ESTADO_APROBACION",'PENDIENTE') not in ('APROBADO','RECHAZADO','ANULADO')
    and not coalesce(q.eliminado,false) and q.deleted_at is null;

  select count(*) into v_count from public."PLANILLA_VALIDACIONES_APPGT"
  where periodo_id=p_periodo and nivel='ERROR' and not resuelto;
  return v_count;
end;
$$;

create or replace function public.appgt_validar_autorizacion_fuente_planilla_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_tabla text := upper(tg_table_name);
begin
  if coalesce(new."ESTADO_APROBACION",'') = 'APROBADO'
     and coalesce(old."ESTADO_APROBACION",'') is distinct from 'APROBADO'
     and not public.appgt_puede_accion_tabla_v1(tg_table_name,'APROBAR') then
    raise exception 'No tiene permiso de aprobación para %.',
      case when v_tabla='GT-TAREO_PERSONAL' then 'tareos' else 'permisos y licencias' end
      using errcode='42501';
  end if;
  return new;
end;
$$;

drop trigger if exists appgt_20_validar_autorizacion_tareo on public."GT-TAREO_PERSONAL";
create trigger appgt_20_validar_autorizacion_tareo
before update of "ESTADO_APROBACION" on public."GT-TAREO_PERSONAL"
for each row execute function public.appgt_validar_autorizacion_fuente_planilla_v1();
drop trigger if exists appgt_20_validar_autorizacion_permiso on public."GH_PERMISOS_LICENCIAS_APPGT";
create trigger appgt_20_validar_autorizacion_permiso
before update of "ESTADO_APROBACION" on public."GH_PERMISOS_LICENCIAS_APPGT"
for each row execute function public.appgt_validar_autorizacion_fuente_planilla_v1();

create table if not exists public."PLANILLA_BOLETAS_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  periodo_id uuid not null references public."PLANILLA_PERIODOS_APPGT"(id) on delete cascade,
  liquidacion_id uuid not null references public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT"(id) on delete restrict,
  fecha_inicio date not null,
  fecha_fin date not null,
  dni text not null,
  nombres text not null,
  pdf_url text,
  pdf_generado_at timestamptz,
  estado text not null default 'PENDIENTE' check (estado in ('PENDIENTE','GENERADA','ANULADA')),
  liquidacion_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (periodo_id,dni)
);

create index if not exists planilla_boletas_empresa_periodo_idx
  on public."PLANILLA_BOLETAS_APPGT" (empresa_id,periodo_id,dni);

create or replace function public.appgt_preparar_boletas_periodo_v1(p_periodo uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_count integer;
begin
  insert into public."PLANILLA_BOLETAS_APPGT" (
    empresa_id,periodo_id,liquidacion_id,fecha_inicio,fecha_fin,dni,nombres,
    estado,liquidacion_snapshot,pdf_url,pdf_generado_at
  )
  select p.empresa_id,p.id,l.id,p.fecha_inicio,p.fecha_fin,l.dni,l.trabajador,
    'PENDIENTE',to_jsonb(l),null,null
  from public."PLANILLA_PERIODOS_APPGT" p
  join public."PLANILLA_LIQUIDACION_TRABAJADOR_APPGT" l on l.periodo_id=p.id
  where p.id=p_periodo
  on conflict (periodo_id,dni) do update set
    liquidacion_id=excluded.liquidacion_id,
    fecha_inicio=excluded.fecha_inicio,
    fecha_fin=excluded.fecha_fin,
    nombres=excluded.nombres,
    estado='PENDIENTE',
    liquidacion_snapshot=excluded.liquidacion_snapshot,
    pdf_url=null,
    pdf_generado_at=null,
    updated_at=now();
  get diagnostics v_count = row_count;
  return v_count;
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
  v_accion text := upper(btrim(p_accion));
  v_anterior text;
  v_mes_inicio date;
begin
  select * into v_periodo from public."PLANILLA_PERIODOS_APPGT"
  where id=p_periodo_id and empresa_id=public.appgt_empresa_actual_id()
    and not eliminado and deleted_at is null for update;
  if not found then raise exception 'Periodo de planilla no encontrado.'; end if;
  v_anterior := v_periodo.estado;

  if v_accion in ('VALIDAR','CALCULAR') then
    if v_periodo.estado not in ('BORRADOR','CALCULADA') then
      raise exception 'Solo un período BORRADOR o CALCULADA puede validarse y recalcularse.';
    end if;
    if not public.appgt_puede_accion_tabla_v1('PLANILLA_PERIODOS_APPGT','ACTUALIZAR') then
      raise exception 'No tiene permiso para validar y calcular planilla.' using errcode='42501';
    end if;
    perform public.appgt_exigir_planilla_valida_v2(p_periodo_id);
    v_mes_inicio := date_trunc('month',v_periodo.fecha_fin)::date;
    if v_periodo.fecha_fin=(v_mes_inicio+interval '1 month - 1 day')::date then
      perform public.appgt_refrescar_planilla_zumac(v_mes_inicio,v_periodo.fecha_fin);
    else
      perform public.appgt_refrescar_planilla_zumac(v_periodo.fecha_inicio,v_periodo.fecha_fin);
    end if;
    update public."PLANILLA_TRABAJADORES_ZUMAC" d set
      empresa_id=v_periodo.empresa_id,periodo_id=v_periodo.id,
      campana=coalesce(v_periodo.campana,d.campana),moneda=v_periodo.moneda,
      tipo_cambio=v_periodo.tipo_cambio
    where d.fecha between v_periodo.fecha_inicio and v_periodo.fecha_fin
      and (d.empresa_id is null or d.empresa_id=v_periodo.empresa_id)
      and d.activo and not d.eliminado and d.deleted_at is null;
    perform public.appgt_reconstruir_permisos_periodo_v2(p_periodo_id);
    perform public.appgt_calcular_liquidacion_periodo_v2(p_periodo_id);
    perform public.appgt_planilla_periodo_totales_v2(p_periodo_id);
    perform set_config('appgt.planilla_transition','1',true);
    update public."PLANILLA_PERIODOS_APPGT" set
      estado='CALCULADA',validada_por=auth.uid(),validada_at=clock_timestamp(),
      calculada_por=auth.uid(),calculada_at=clock_timestamp(),
      revisada_por=null,revisada_at=null,aprobada_por=null,aprobada_at=null,
      cerrada_por=null,cerrada_at=null,updated_at=now()
    where id=p_periodo_id;
    v_accion := 'VALIDAR_Y_CALCULAR';
  elsif v_accion='REVISAR' then
    if v_periodo.estado <> 'CALCULADA' then raise exception 'La planilla debe estar CALCULADA.'; end if;
    if not public.appgt_puede_accion_tabla_v1('PLANILLA_PERIODOS_APPGT','REVISAR') then
      raise exception 'No tiene permiso para revisar planilla.' using errcode='42501';
    end if;
    perform set_config('appgt.planilla_transition','1',true);
    update public."PLANILLA_PERIODOS_APPGT" set estado='REVISADA',
      revisada_por=auth.uid(),revisada_at=clock_timestamp(),updated_at=now()
    where id=p_periodo_id;
  elsif v_accion='APROBAR' then
    if v_periodo.estado <> 'REVISADA' then raise exception 'La planilla debe estar REVISADA.'; end if;
    if not public.appgt_puede_accion_tabla_v1('PLANILLA_PERIODOS_APPGT','APROBAR') then
      raise exception 'No tiene permiso para aprobar planilla.' using errcode='42501';
    end if;
    perform set_config('appgt.planilla_transition','1',true);
    update public."PLANILLA_PERIODOS_APPGT" set estado='APROBADA',
      aprobada_por=auth.uid(),aprobada_at=clock_timestamp(),updated_at=now()
    where id=p_periodo_id;
  elsif v_accion='CERRAR' then
    if v_periodo.estado <> 'APROBADA' then raise exception 'La planilla debe estar APROBADA.'; end if;
    if not public.appgt_puede_accion_tabla_v1('PLANILLA_PERIODOS_APPGT','APROBAR') then
      raise exception 'No tiene permiso para cerrar planilla.' using errcode='42501';
    end if;
    perform public.appgt_planilla_periodo_totales_v2(p_periodo_id);
    perform public.appgt_preparar_boletas_periodo_v1(p_periodo_id);
    perform set_config('appgt.planilla_transition','1',true);
    update public."PLANILLA_PERIODOS_APPGT" set estado='CERRADA',
      cerrada_por=auth.uid(),cerrada_at=clock_timestamp(),updated_at=now()
    where id=p_periodo_id;
  elsif v_accion='REABRIR' then
    if v_periodo.estado <> 'CERRADA' then raise exception 'Solo una planilla CERRADA puede reabrirse.'; end if;
    if not public.appgt_puede_gestionar_configuracion(v_periodo.empresa_id) then
      raise exception 'Solo un administrador o gestor puede reabrir planillas.' using errcode='42501';
    end if;
    if nullif(btrim(p_motivo),'') is null then raise exception 'La reapertura requiere un motivo.'; end if;
    perform set_config('appgt.planilla_transition','1',true);
    update public."PLANILLA_PERIODOS_APPGT" set estado='BORRADOR',
      ultima_reapertura_por=auth.uid(),ultima_reapertura_at=clock_timestamp(),
      motivo_ultima_reapertura=btrim(p_motivo),cantidad_reaperturas=cantidad_reaperturas+1,
      validada_por=null,validada_at=null,calculada_por=null,calculada_at=null,
      revisada_por=null,revisada_at=null,aprobada_por=null,aprobada_at=null,
      cerrada_por=null,cerrada_at=null,updated_at=now()
    where id=p_periodo_id;
    update public."PLANILLA_BOLETAS_APPGT" set estado='ANULADA',updated_at=now()
    where periodo_id=p_periodo_id;
  else
    raise exception 'Acción de planilla no reconocida: %.',v_accion;
  end if;

  select * into v_periodo from public."PLANILLA_PERIODOS_APPGT" where id=p_periodo_id;
  insert into public."PLANILLA_AUDITORIA_APPGT" (
    empresa_id,tabla_origen,entidad_id,periodo_id,accion,estado_anterior,
    estado_nuevo,motivo,datos_nuevos
  ) values (
    v_periodo.empresa_id,'PLANILLA_PERIODOS_APPGT',v_periodo.id::text,
    v_periodo.id,v_accion,v_anterior,v_periodo.estado,
    nullif(btrim(p_motivo),''),to_jsonb(v_periodo)
  );
  return to_jsonb(v_periodo);
end;
$$;

-- La tabla se muestra dentro de Gestión Humana > Planilla. La boleta queda
-- disponible solo al cerrar el período y su PDF se guarda en Storage.
do $$
declare v_rubro record; v_suffix text; v_modulo text; v_formato text;
begin
  for v_rubro in select * from public."RUBROS_APPGT" where activo and deleted_at is null loop
    v_suffix := substr(md5(v_rubro.empresa_id::text),1,10);
    v_modulo := 'gh_planilla_' || v_suffix;
    v_formato := 'gh_planilla_boletas_' || v_suffix;
    insert into public."MATRIZ_FORMATOS_APPGT" (
      id,empresa_id,modulo_id,nombre,tabla_destino,ruta_flutter,tabla_visible_app,
      orden,activo,rubro_id,auditable,icono,capacidades,created_at,updated_at,estado_sync,eliminado
    ) values (
      v_formato,v_rubro.empresa_id,v_modulo,'Boletas de Pago','PLANILLA_BOLETAS_APPGT',
      null,true,25,true,v_rubro.id,true,'receipt_long',
      '{"boletas_pdf":true,"solo_cierre":true}'::jsonb,now(),now(),'sincronizado',false
    ) on conflict (id) do update set nombre=excluded.nombre,modulo_id=excluded.modulo_id,
      tabla_destino=excluded.tabla_destino,tabla_visible_app=true,orden=excluded.orden,
      activo=true,eliminado=false,updated_at=now();
    insert into public."MATRIZ_FORMATO_TABLAS_APPGT" (
      id,empresa_id,formato_id,nombre,tabla_destino,orden,activo,rubro_id,auditable,icono,created_at,updated_at
    ) values (
      v_formato || '_table',v_rubro.empresa_id,v_formato,'Boletas de Pago',
      'PLANILLA_BOLETAS_APPGT',0,true,v_rubro.id,true,'receipt_long',now(),now()
    ) on conflict (id) do update set activo=true,updated_at=now();
  end loop;
end;
$$;

insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id,tabla_destino,campo,etiqueta,tipo,tipo_ui,id_campo_dropdown,
  requerido,visible,visible_tabla,editable,orden,activo,created_at,updated_at,estado_sync,eliminado
) values
  ('pl_p_movilidad_empresa','PLANILLA_PERIODOS_APPGT','total_movilidad_empresa','Movilidad empresa','numeric','number',null,false,true,true,false,21,true,now(),now(),'sincronizado',false),
  ('pl_d_boleta','PLANILLA_TRABAJADORES_ZUMAC','costo_boleta_trabajador','Importe de boleta','numeric','number',null,false,true,true,false,73,true,now(),now(),'sincronizado',false),
  ('pl_d_movilidad','PLANILLA_TRABAJADORES_ZUMAC','costo_movilidad_empresa','Movilidad empresa','numeric','number',null,false,true,true,false,74,true,now(),now(),'sincronizado',false),
  ('pl_d_total_mov','PLANILLA_TRABAJADORES_ZUMAC','costo_total_con_movilidad','Boleta + movilidad','numeric','number',null,false,true,true,false,75,true,now(),now(),'sincronizado',false),
  ('pl_l_boleta','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','costo_boleta_trabajador','Importe de boleta','numeric','number',null,false,true,true,false,21,true,now(),now(),'sincronizado',false),
  ('pl_l_movilidad','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','costo_movilidad_empresa','Movilidad empresa','numeric','number',null,false,true,true,false,22,true,now(),now(),'sincronizado',false),
  ('pl_l_total_mov','PLANILLA_LIQUIDACION_TRABAJADOR_APPGT','costo_total_con_movilidad','Costo empresa + movilidad','numeric','number',null,false,true,true,false,23,true,now(),now(),'sincronizado',false),
  ('pl_b_inicio','PLANILLA_BOLETAS_APPGT','fecha_inicio','Fecha inicio de planilla','date','readonly',null,false,true,true,false,1,true,now(),now(),'sincronizado',false),
  ('pl_b_fin','PLANILLA_BOLETAS_APPGT','fecha_fin','Fecha fin de planilla','date','readonly',null,false,true,true,false,2,true,now(),now(),'sincronizado',false),
  ('pl_b_dni','PLANILLA_BOLETAS_APPGT','dni','DNI','text','readonly',null,false,true,true,false,3,true,now(),now(),'sincronizado',false),
  ('pl_b_nombres','PLANILLA_BOLETAS_APPGT','nombres','Nombres','text','readonly',null,false,true,true,false,4,true,now(),now(),'sincronizado',false),
  ('pl_b_pdf','PLANILLA_BOLETAS_APPGT','pdf_url','PDF','text','pdf',null,false,true,true,false,5,true,now(),now(),'sincronizado',false),
  ('pl_b_estado','PLANILLA_BOLETAS_APPGT','estado','Estado','text','readonly',null,false,true,true,false,6,true,now(),now(),'sincronizado',false)
on conflict (tabla_destino,campo) do update set etiqueta=excluded.etiqueta,tipo=excluded.tipo,
  tipo_ui=excluded.tipo_ui,visible=excluded.visible,visible_tabla=excluded.visible_tabla,
  editable=excluded.editable,orden=excluded.orden,activo=true,eliminado=false,updated_at=now();

with source as (
  select * from public."PERMISOS_DE_USUARIOS_APPGT"
  where upper(coalesce(tabla_destino,''))='PLANILLA_PERIODOS_APPGT'
    and user_id is not null and activo and not eliminado
), target as (
  select f.empresa_id,f.id formato_id,f.modulo_id,m.seccion
  from public."MATRIZ_FORMATOS_APPGT" f join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id=f.empresa_id and m.id=f.modulo_id
  where f.tabla_destino='PLANILLA_BOLETAS_APPGT' and f.activo and not f.eliminado
)
insert into public."PERMISOS_DE_USUARIOS_APPGT" (
  empresa_id,user_id,seccion,modulo,formato,tabla_destino,can_view,can_insert,
  can_update,can_delete,can_export,can_import,can_review,can_approve,activo,
  created_at,updated_at,estado_sync,eliminado
)
select s.empresa_id,s.user_id,t.seccion,t.modulo_id,t.formato_id,'PLANILLA_BOLETAS_APPGT',
  s.can_view,false,false,false,s.can_export,false,s.can_review,s.can_approve,true,
  now(),now(),'sincronizado',false
from source s join target t on t.empresa_id=s.empresa_id
on conflict (user_id,modulo,formato) do update set tabla_destino=excluded.tabla_destino,
  can_view=excluded.can_view,can_insert=false,can_update=false,can_delete=false,
  can_export=excluded.can_export,can_import=false,activo=true,eliminado=false,updated_at=now();

alter table public."PLANILLA_BOLETAS_APPGT" enable row level security;
drop policy if exists planilla_boletas_select_v1 on public."PLANILLA_BOLETAS_APPGT";
create policy planilla_boletas_select_v1 on public."PLANILLA_BOLETAS_APPGT"
for select to authenticated using (
  empresa_id=public.appgt_empresa_actual_id()
  and public.appgt_can_view_table('PLANILLA_BOLETAS_APPGT')
);
grant select on public."PLANILLA_BOLETAS_APPGT" to authenticated;
grant all on public."PLANILLA_BOLETAS_APPGT" to service_role;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('planilla-boletas','planilla-boletas',false,5242880,array['application/pdf'])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists planilla_boletas_storage_select on storage.objects;
create policy planilla_boletas_storage_select on storage.objects for select to authenticated using (
  bucket_id='planilla-boletas'
  and split_part(name,'/',1)=public.appgt_empresa_actual_id()::text
);
drop policy if exists planilla_boletas_storage_insert on storage.objects;
create policy planilla_boletas_storage_insert on storage.objects for insert to authenticated with check (
  bucket_id='planilla-boletas'
  and split_part(name,'/',1)=public.appgt_empresa_actual_id()::text
);
drop policy if exists planilla_boletas_storage_update on storage.objects;
create policy planilla_boletas_storage_update on storage.objects for update to authenticated using (
  bucket_id='planilla-boletas'
  and split_part(name,'/',1)=public.appgt_empresa_actual_id()::text
) with check (
  bucket_id='planilla-boletas'
  and split_part(name,'/',1)=public.appgt_empresa_actual_id()::text
);

revoke all on function public.appgt_evitar_duplicado_semantico_v1() from public, anon;
revoke all on function public.appgt_costo_movilidad_diaria_v1(uuid,text,date) from public, anon;
grant execute on function public.appgt_cambiar_estado_planilla_periodo_v1(uuid,text,text)
  to authenticated, service_role;
grant execute on function public.appgt_generar_validaciones_planilla_v2(uuid)
  to authenticated, service_role;
grant execute on function public.appgt_preparar_boletas_periodo_v1(uuid)
  to authenticated, service_role;

notify pgrst, 'reload schema';
commit;
