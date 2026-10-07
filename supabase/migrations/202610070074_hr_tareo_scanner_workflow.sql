begin;

-- Datos adicionales solicitados para la ficha empresarial.
alter table public."EMPRESAS_APPGT"
  add column if not exists cel_representante_legal text,
  add column if not exists cel_representante_cargo text,
  add column if not exists domicilio_fiscal text;

-- El refrigerio conserva 45 minutos como valor inicial, pero el usuario puede
-- ajustar sus dos extremos mientras la duración sea mayor que cero y no pase
-- de una hora.
alter table public."GT-TAREO_PERSONAL"
  drop constraint if exists gt_tareo_refrigerio_45_minutos_check,
  drop constraint if exists gt_tareo_refrigerio_hasta_60_minutos_check;

alter table public."GT-TAREO_PERSONAL"
  add constraint gt_tareo_refrigerio_hasta_60_minutos_check
  check (
    "MINUTOS_REFRIGERIO" between 1 and 60
    and mod(
      (extract(epoch from ("REFRIGERIO_FIN" - "REFRIGERIO_INICIO")) / 60)::integer
        + 1440,
      1440
    ) = "MINUTOS_REFRIGERIO"
  );

create or replace function public.appgt_tareo_control_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_data jsonb;
  v_dni text;
  v_fecha date;
  v_horas numeric := 0;
  v_previas numeric := 0;
  v_id text;
  v_cierre_nuevo boolean := false;
  v_work_start timestamp without time zone;
  v_work_end timestamp without time zone;
  v_meal_start timestamp without time zone;
  v_meal_end timestamp without time zone;
  v_candidate_start timestamp without time zone;
  v_candidate_end timestamp without time zone;
  v_best_start timestamp without time zone;
  v_best_end timestamp without time zone;
  v_candidate_overlap numeric;
  v_overlap_minutes numeric := 0;
  v_gross_minutes numeric;
  v_meal_minutes integer;
  v_offset integer;
begin
  new.empresa_id := coalesce(new.empresa_id, public.appgt_empresa_actual_id());
  new."REFRIGERIO_INICIO" := coalesce(new."REFRIGERIO_INICIO", time '12:00');
  new."REFRIGERIO_FIN" := coalesce(new."REFRIGERIO_FIN", time '12:45');

  v_meal_minutes := mod(
    (extract(epoch from
      (new."REFRIGERIO_FIN" - new."REFRIGERIO_INICIO")) / 60)::integer + 1440,
    1440
  );
  if v_meal_minutes < 1 or v_meal_minutes > 60 then
    raise exception 'El refrigerio debe durar entre 1 y 60 minutos.';
  end if;
  new."MINUTOS_REFRIGERIO" := v_meal_minutes;

  if new."HORA_INICIO" is not null and new."HORA_FIN" is not null then
    v_work_start := new."FECHA" + new."HORA_INICIO";
    v_work_end := new."FECHA" + new."HORA_FIN";
    if v_work_end < v_work_start then
      v_work_end := v_work_end + interval '1 day';
    end if;

    for v_offset in -1..1 loop
      v_candidate_start := new."FECHA" + new."REFRIGERIO_INICIO"
        + make_interval(days => v_offset);
      v_candidate_end := new."FECHA" + new."REFRIGERIO_FIN"
        + make_interval(days => v_offset);
      if v_candidate_end < v_candidate_start then
        v_candidate_end := v_candidate_end + interval '1 day';
      end if;
      v_candidate_overlap := greatest(
        extract(epoch from (
          least(v_work_end, v_candidate_end)
          - greatest(v_work_start, v_candidate_start)
        )) / 60,
        0
      );
      if v_candidate_overlap > v_overlap_minutes then
        v_overlap_minutes := v_candidate_overlap;
        v_best_start := v_candidate_start;
        v_best_end := v_candidate_end;
      end if;
    end loop;

    if v_overlap_minutes > 0 and not (
      v_work_start <= v_best_start and v_work_end >= v_best_end
    ) then
      raise exception 'En ese horario el personal estuvo en refrigerio';
    end if;

    v_gross_minutes := extract(epoch from (v_work_end - v_work_start)) / 60;
    new."HORAS_TRABAJADAS" := round((
      v_gross_minutes
      - case
          when v_overlap_minutes = v_meal_minutes then v_meal_minutes
          else 0
        end
    ) / 60, 2);
  end if;

  v_data := to_jsonb(new);
  v_dni := public.appgt_jsonb_text(v_data, array['DNI','DOCUMENTO']);
  v_fecha := public.appgt_jsonb_date(v_data, array['FECHA']);
  v_horas := greatest(
    public.appgt_jsonb_numeric(v_data, array['HORAS_TRABAJADAS'], 0), 0
  );
  v_id := public.appgt_jsonb_text(v_data, array['id_local','id']);

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
      raise exception
        'Indique el motivo de las horas extra antes de cerrar el tareo.';
    end if;
  end if;

  if new."ESTADO_APROBACION" = 'APROBADO'
     and new."REQUIERE_HORAS_EXTRA"
     and new."ESTADO_HORAS_EXTRA" <> 'AUTORIZADO' then
    raise exception
      'Las horas extra deben estar autorizadas antes de aprobar el tareo.';
  end if;
  return new;
end
$$;

insert into public."MATRIZ_TIPOS_AUSENCIA_APPGT" (
  empresa_id, codigo, nombre, descripcion, con_goce_haber,
  documento_requerido, activo, eliminado
)
select e.id,
       'PERMISOS_POR_HORAS_' || upper(substr(md5(e.id::text), 1, 8)),
       'PERMISOS POR HORAS',
       'Permiso delimitado por una hora de inicio y una hora de fin',
       true, false, true, false
from public."EMPRESAS_APPGT" e
where coalesce(e.activo, true)
  and not exists (
    select 1
    from public."MATRIZ_TIPOS_AUSENCIA_APPGT" t
    where t.empresa_id = e.id
      and public.appgt_normalizar_clave(t.nombre) in (
        'PERMISOPORHORAS','PERMISOSPORHORAS'
      )
      and not coalesce(t.eliminado, false)
  );

-- Las horas pertenecen únicamente al concepto "Permisos por horas". Para
-- cualquier otro concepto se limpian en servidor, incluso si llega un cliente
-- antiguo que todavía las envía.
create or replace function public.appgt_gh_permisos_preparar_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tipo record;
  v_empresa_id uuid;
  v_requiere_documento boolean;
  v_permiso_por_horas boolean;
begin
  v_empresa_id := coalesce(new.empresa_id, public.appgt_empresa_actual_id());
  new.empresa_id := v_empresa_id;

  select t.nombre, t.con_goce_haber, t.documento_requerido
    into v_tipo
  from public."MATRIZ_TIPOS_AUSENCIA_APPGT" t
  where (t.empresa_id = v_empresa_id or t.empresa_id is null)
    and (
      public.appgt_normalizar_clave(t.nombre) =
        public.appgt_normalizar_clave(new.tipo_permiso)
      or public.appgt_normalizar_clave(t.codigo) =
        public.appgt_normalizar_clave(new.tipo_permiso)
    )
    and coalesce(t.activo, true)
    and not coalesce(t.eliminado, false)
  order by (t.empresa_id = v_empresa_id) desc, t.updated_at desc nulls last
  limit 1;

  if not found then
    raise exception
      'El tipo de permiso o licencia seleccionado ya no esta disponible.';
  end if;

  new.tipo_permiso := v_tipo.nombre;
  v_requiere_documento := coalesce(v_tipo.documento_requerido, false);
  if v_requiere_documento
      and nullif(btrim(coalesce(new.documento_sustento, '')), '') is null then
    raise exception 'Debe adjuntar el documento de sustento en formato PDF.';
  end if;
  if not v_requiere_documento then
    new.documento_sustento := null;
  end if;

  v_permiso_por_horas := public.appgt_normalizar_clave(new.tipo_permiso) in (
    'PERMISOPORHORAS', 'PERMISOSPORHORAS'
  );
  if v_permiso_por_horas then
    if new.hora_inicio is null or new.hora_fin is null then
      raise exception 'Indique la hora de inicio y la hora de fin del permiso.';
    end if;
  else
    new.hora_inicio := null;
    new.hora_fin := null;
  end if;

  new.con_goce_haber := coalesce(v_tipo.con_goce_haber, true);
  new.dias_solicitados := greatest(1, new.fecha_fin - new.fecha_inicio + 1);
  new.updated_at := now();
  new.updated_by := auth.uid();
  if tg_op = 'UPDATE' then new.version := old.version + 1; end if;
  return new;
end
$$;

-- Sanciones y despidos comparten el formato, pero el despido usa una sola
-- fecha y no un rango.
alter table public."GH_SANCIONES_PERSONAL_APPGT"
  add column if not exists fecha_despido date,
  alter column fecha_inicio drop not null,
  alter column fecha_fin drop not null;

do $$
declare v_constraint record;
begin
  for v_constraint in
    select conname
    from pg_constraint
    where conrelid = 'public."GH_SANCIONES_PERSONAL_APPGT"'::regclass
      and contype = 'c'
      and (
        pg_get_constraintdef(oid) ilike '%tipo_sancion%'
        or pg_get_constraintdef(oid) ilike '%fecha_fin%fecha_inicio%'
        or pg_get_constraintdef(oid) ilike '%bloquea_asistencia%'
      )
  loop
    execute format(
      'alter table public."GH_SANCIONES_PERSONAL_APPGT" drop constraint %I',
      v_constraint.conname
    );
  end loop;
end
$$;

alter table public."GH_SANCIONES_PERSONAL_APPGT"
  add constraint gh_sanciones_tipo_sancion_despido_check check (
    tipo_sancion in (
      'AMONESTACION VERBAL','AMONESTACION ESCRITA',
      'SUSPENSION DE LABORES','OTRA','DESPIDO'
    )
  ),
  add constraint gh_sanciones_fechas_despido_check check (
    (
      tipo_sancion = 'DESPIDO'
      and fecha_despido is not null
      and fecha_inicio is null
      and fecha_fin is null
    )
    or
    (
      tipo_sancion <> 'DESPIDO'
      and fecha_despido is null
      and fecha_inicio is not null
      and fecha_fin is not null
      and fecha_fin >= fecha_inicio
    )
  );

-- El servidor también exige la secuencia PENDIENTE -> REVISADO -> APROBADO.
create or replace function public.appgt_permiso_aprobacion_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa public."EMPRESAS_APPGT"%rowtype;
begin
  if tg_op = 'INSERT' then
    new."ESTADO_APROBACION" := 'PENDIENTE';
    new.estado := 'SOLICITADO';
    new.aprobado_por := null;
    new.fecha_aprobacion := null;
    return new;
  end if;

  if old."ESTADO_APROBACION" is distinct from new."ESTADO_APROBACION" then
    if new."ESTADO_APROBACION" = 'REVISADO' then
      if old."ESTADO_APROBACION" <> 'PENDIENTE' then
        raise exception 'Solo un permiso PENDIENTE puede pasar a REVISADO.';
      end if;
      if not public.appgt_puede_accion_tabla_v1(
        'GH_PERMISOS_LICENCIAS_APPGT','REVISAR'
      ) then
        raise exception 'No tiene permiso para revisar permisos o licencias.'
          using errcode='42501';
      end if;
    elsif new."ESTADO_APROBACION" = 'APROBADO' then
      if old."ESTADO_APROBACION" <> 'REVISADO' then
        raise exception 'El permiso debe estar REVISADO antes de aprobarse.';
      end if;
      if not public.appgt_puede_accion_tabla_v1(
        'GH_PERMISOS_LICENCIAS_APPGT','APROBAR'
      ) then
        raise exception 'No tiene permiso para aprobar permisos o licencias.'
          using errcode='42501';
      end if;
    elsif new."ESTADO_APROBACION" in ('RECHAZADO','ANULADO')
       and not public.appgt_puede_accion_tabla_v1(
         'GH_PERMISOS_LICENCIAS_APPGT','APROBAR'
       ) then
      raise exception 'No tiene permiso para resolver permisos o licencias.'
        using errcode='42501';
    end if;
  end if;

  if new."ESTADO_APROBACION" = 'APROBADO'
     and old."ESTADO_APROBACION" is distinct from 'APROBADO' then
    select * into v_empresa
    from public."EMPRESAS_APPGT"
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
  elsif new."ESTADO_APROBACION" = 'RECHAZADO' then
    new.estado := 'RECHAZADO';
  elsif new."ESTADO_APROBACION" = 'ANULADO' then
    new.estado := 'ANULADO';
  elsif new."ESTADO_APROBACION" in ('PENDIENTE','REVISADO') then
    new.estado := 'SOLICITADO';
    new.aprobado_por := null;
    new.fecha_aprobacion := null;
  end if;
  return new;
end
$$;

drop trigger if exists zz_appgt_permiso_aprobacion_trigger
  on public."GH_PERMISOS_LICENCIAS_APPGT";
create trigger zz_appgt_permiso_aprobacion_trigger
before insert or update of "ESTADO_APROBACION"
on public."GH_PERMISOS_LICENCIAS_APPGT"
for each row execute function public.appgt_permiso_aprobacion_v1();

create or replace function public.appgt_sancion_aprobacion_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    new."ESTADO_APROBACION" := 'PENDIENTE';
    new.estado := 'BORRADOR';
    new.aprobado_por := null;
    new.fecha_aprobacion := null;
    return new;
  end if;

  if old."ESTADO_APROBACION" is distinct from new."ESTADO_APROBACION" then
    if new."ESTADO_APROBACION" = 'REVISADO' then
      if old."ESTADO_APROBACION" <> 'PENDIENTE' then
        raise exception 'Solo una sanción o despido PENDIENTE puede pasar a REVISADO.';
      end if;
      if not public.appgt_puede_accion_tabla_v1(
        'GH_SANCIONES_PERSONAL_APPGT','REVISAR'
      ) then
        raise exception 'No tiene permiso para revisar sanciones o despidos.'
          using errcode='42501';
      end if;
    elsif new."ESTADO_APROBACION" = 'APROBADO' then
      if old."ESTADO_APROBACION" <> 'REVISADO' then
        raise exception 'La sanción o despido debe estar REVISADO antes de aprobarse.';
      end if;
      if not public.appgt_puede_accion_tabla_v1(
        'GH_SANCIONES_PERSONAL_APPGT','APROBAR'
      ) then
        raise exception 'No tiene permiso para aprobar sanciones o despidos.'
          using errcode='42501';
      end if;
    elsif new."ESTADO_APROBACION" in ('RECHAZADO','ANULADO')
       and not public.appgt_puede_accion_tabla_v1(
         'GH_SANCIONES_PERSONAL_APPGT','APROBAR'
       ) then
      raise exception 'No tiene permiso para resolver sanciones o despidos.'
        using errcode='42501';
    end if;
  end if;

  if new."ESTADO_APROBACION" = 'APROBADO' then
    new.estado := case
      when tg_op = 'UPDATE' and old.estado = 'CUMPLIDA' then 'CUMPLIDA'
      else 'VIGENTE'
    end;
    if tg_op = 'INSERT'
       or old."ESTADO_APROBACION" is distinct from 'APROBADO' then
      new.aprobado_por := auth.uid();
      new.fecha_aprobacion := now();
    end if;
  elsif new."ESTADO_APROBACION" = 'ANULADO' then
    new.estado := 'ANULADA';
  elsif new."ESTADO_APROBACION" in ('PENDIENTE','REVISADO','RECHAZADO') then
    new.estado := 'BORRADOR';
    new.aprobado_por := null;
    new.fecha_aprobacion := null;
  end if;
  return new;
end
$$;

drop trigger if exists zz_appgt_sancion_aprobacion_trigger
  on public."GH_SANCIONES_PERSONAL_APPGT";
create trigger zz_appgt_sancion_aprobacion_trigger
before insert or update of "ESTADO_APROBACION"
on public."GH_SANCIONES_PERSONAL_APPGT"
for each row execute function public.appgt_sancion_aprobacion_v1();

create or replace function public.appgt_aplicar_despido_personal_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new."ESTADO_APROBACION" = 'APROBADO'
     and public.appgt_normalizar_clave(new.tipo_sancion) = 'DESPIDO'
     and new.fecha_despido is not null then
    update public."GH-REGISTRO_PERSONAL_PLANILLA" p
    set "Fecha fin de contrato" = new.fecha_despido,
        updated_at = now(),
        estado_sync = 'sincronizado'
    where p.empresa_id = new.empresa_id
      and public.appgt_normalizar_clave(p."Dni") =
          public.appgt_normalizar_clave(new.dni)
      and not coalesce(p.eliminado, false)
      and p.deleted_at is null;
  end if;
  return new;
end
$$;

drop trigger if exists zz_appgt_aplicar_despido_personal
  on public."GH_SANCIONES_PERSONAL_APPGT";
create trigger zz_appgt_aplicar_despido_personal
after insert or update of "ESTADO_APROBACION", tipo_sancion, fecha_despido
on public."GH_SANCIONES_PERSONAL_APPGT"
for each row execute function public.appgt_aplicar_despido_personal_v1();

-- Metadatos que consume Flutter y la tabla web.
update public."MATRIZ_FORMATOS_APPGT"
set nombre = 'Sanciones/Despido de Personal',
    capacidades = coalesce(capacidades, '{}'::jsonb) ||
      '{"aprobaciones":true}'::jsonb,
    approvals_enabled = true,
    flujo_estados = '["PENDIENTE","REVISADO","APROBADO"]'::jsonb,
    updated_at = now()
where upper(coalesce(tabla_destino, '')) = 'GH_SANCIONES_PERSONAL_APPGT';

update public."MATRIZ_FORMATO_TABLAS_APPGT"
set nombre = 'Sanciones/Despido de Personal', updated_at = now()
where upper(coalesce(tabla_destino, '')) = 'GH_SANCIONES_PERSONAL_APPGT';

update public."MATRIZ_FORMATOS_APPGT"
set capacidades = coalesce(capacidades, '{}'::jsonb) ||
      '{"aprobaciones":true}'::jsonb,
    approvals_enabled = true,
    flujo_estados = '["PENDIENTE","REVISADO","APROBADO"]'::jsonb,
    updated_at = now()
where upper(coalesce(tabla_destino, '')) = 'GH_PERMISOS_LICENCIAS_APPGT';

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set requerido = false,
    valor_default = 'false',
    updated_at = now()
where upper(coalesce(tabla_destino, '')) in (
    'GH_PERMISOS_LICENCIAS_APPGT','GH_SANCIONES_PERSONAL_APPGT'
  )
  and (
    public.appgt_normalizar_clave(campo) in (
      'BLOQUEAASISTENCIA','BLOQUEARASISTENCIA'
    )
    or public.appgt_normalizar_clave(etiqueta) in (
      'BLOQUEAASISTENCIA','BLOQUEARASISTENCIA'
    )
  );

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set etiqueta = 'Sanción/Despido',
    id_campo_dropdown =
      '[AMONESTACION VERBAL;AMONESTACION ESCRITA;SUSPENSION DE LABORES;OTRA;DESPIDO]',
    updated_at = now()
where upper(coalesce(tabla_destino, '')) = 'GH_SANCIONES_PERSONAL_APPGT'
  and upper(coalesce(campo, '')) = 'TIPO_SANCION';

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set requerido = false, updated_at = now()
where upper(coalesce(tabla_destino, '')) = 'GH_PERMISOS_LICENCIAS_APPGT'
  and upper(coalesce(campo, '')) in ('HORA_INICIO','HORA_FIN');

insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id, tabla_destino, campo, etiqueta, tipo, tipo_ui, requerido, visible,
  visible_tabla, editable, orden, activo, created_at, updated_at, estado_sync,
  eliminado
) values (
  'gh_san_fecha_despido','GH_SANCIONES_PERSONAL_APPGT','fecha_despido',
  'Fecha de despido','date','date',false,true,true,true,5,true,now(),now(),
  'sincronizado',false
)
on conflict (tabla_destino, campo) do update set
  etiqueta = excluded.etiqueta,
  tipo = excluded.tipo,
  tipo_ui = excluded.tipo_ui,
  requerido = false,
  visible = true,
  visible_tabla = true,
  editable = true,
  orden = excluded.orden,
  activo = true,
  eliminado = false,
  updated_at = now();

notify pgrst, 'reload schema';
commit;
