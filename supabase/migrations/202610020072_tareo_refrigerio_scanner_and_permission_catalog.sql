begin;

-- Refrigerio legal de 45 minutos. Los valores se guardan junto al tareo para
-- que el cálculo sea reproducible incluso si el horario predeterminado cambia.
alter table public."GT-TAREO_PERSONAL"
  add column if not exists "REFRIGERIO_INICIO" time without time zone
    not null default time '12:00',
  add column if not exists "REFRIGERIO_FIN" time without time zone
    not null default time '12:45',
  add column if not exists "MINUTOS_REFRIGERIO" integer
    not null default 45;

alter table public."GT-TAREO_PERSONAL"
  drop constraint if exists gt_tareo_refrigerio_45_minutos_check;
alter table public."GT-TAREO_PERSONAL"
  add constraint gt_tareo_refrigerio_45_minutos_check
  check (
    "MINUTOS_REFRIGERIO" = 45
    and mod(
      (extract(epoch from ("REFRIGERIO_FIN" - "REFRIGERIO_INICIO")) / 60)::integer
        + 1440,
      1440
    ) = 45
  );

insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id, tabla_destino, campo, etiqueta, tipo, tipo_ui, requerido, visible,
  visible_tabla, editable, orden, activo, created_at, updated_at, estado_sync,
  eliminado, valor_default
) values
  ('tareo_refrigerio_inicio','GT-TAREO_PERSONAL','REFRIGERIO_INICIO',
    'Inicio refrigerio','time','time',true,false,true,true,90,true,now(),now(),
    'sincronizado',false,'12:00'),
  ('tareo_refrigerio_fin','GT-TAREO_PERSONAL','REFRIGERIO_FIN',
    'Fin refrigerio','time','time',true,false,true,true,91,true,now(),now(),
    'sincronizado',false,'12:45'),
  ('tareo_refrigerio_minutos','GT-TAREO_PERSONAL','MINUTOS_REFRIGERIO',
    'Minutos refrigerio','number','number',true,false,false,false,92,true,now(),
    now(),'sincronizado',false,'45')
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
  valor_default = excluded.valor_default,
  updated_at = now();

-- Se admite la misma persona, fecha y labor cuando cambia el centro de costo.
update public."APPGT_REGLAS_DUPLICADO_APPGT"
set campos_clave = array['DNI','FECHA','LABOR','CENTRO_COSTO'],
    descripcion =
      'Un tareo por trabajador, fecha, labor y centro de costo.',
    activo = true,
    updated_at = now()
where upper(tabla_destino) = 'GT-TAREO_PERSONAL';

-- El servidor vuelve a calcular horas netas y rechaza cualquier tramo que
-- empiece o termine dentro del refrigerio. Así se conserva la regla aunque el
-- registro provenga de una versión anterior o se sincronice después de estar
-- offline.
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
  new."MINUTOS_REFRIGERIO" := 45;

  v_meal_minutes := mod(
    (extract(epoch from
      (new."REFRIGERIO_FIN" - new."REFRIGERIO_INICIO")) / 60)::integer + 1440,
    1440
  );
  if v_meal_minutes <> 45 then
    raise exception 'El refrigerio debe durar exactamente 45 minutos.';
  end if;

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
      - case when v_overlap_minutes = 45 then 45 else 0 end
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

-- Acepta el nombre o el código del catálogo, usa la empresa de la sesión si
-- el cliente no la envió y canonicaliza el valor guardado. Esto elimina el
-- falso "ya no está disponible" después de crear o renombrar un tipo.
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

  new.con_goce_haber := coalesce(v_tipo.con_goce_haber, true);
  new.dias_solicitados := greatest(1, new.fecha_fin - new.fecha_inicio + 1);
  new.updated_at := now();
  new.updated_by := auth.uid();
  if tg_op = 'UPDATE' then new.version := old.version + 1; end if;
  return new;
end
$$;

commit;
