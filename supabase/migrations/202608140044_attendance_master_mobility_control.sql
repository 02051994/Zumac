begin;

-- La movilidad se administra en una sola ficha maestra. La tabla de ingresos
-- diarios se conserva únicamente para no destruir registros históricos.
alter table public."GT-MATRIZ_MOVILIDADES"
  add column if not exists id_local uuid,
  add column if not exists licencia_conducir text,
  add column if not exists licencia_vigencia date,
  add column if not exists soat_vigencia date,
  add column if not exists revision_tecnica_vigencia date;

update public."GT-MATRIZ_MOVILIDADES"
set id_local = gen_random_uuid()
where id_local is null;

alter table public."GT-MATRIZ_MOVILIDADES"
  alter column id_local set default gen_random_uuid(),
  alter column id_local set not null;

create unique index if not exists gt_matriz_movilidades_id_local_uq
  on public."GT-MATRIZ_MOVILIDADES" (id_local);

alter table public."GT-ASISTENCIA_PERSONAL"
  add column if not exists "MOVILIDAD_ALERTA_ACEPTADA" boolean
    not null default false,
  add column if not exists "MOVILIDAD_ALERTA_DETALLE" text;

comment on column public."GT-ASISTENCIA_PERSONAL"."MOVILIDAD_ALERTA_ACEPTADA" is
  'Confirma que el usuario decidió continuar después de revisar documentación de movilidad faltante o vencida.';

comment on table public."GT_INGRESO_MOVILIDADES_APPGT" is
  'Tabla histórica. Desde 2026-08-14 la asistencia valida directamente GT-MATRIZ_MOVILIDADES.';

-- Campos disponibles en la matriz maestra y campos técnicos auditables de la
-- asistencia. El on conflict conserva un único campo por tabla y nombre.
insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id, tabla_destino, campo, etiqueta, tipo, tipo_ui, id_campo_dropdown,
  requerido, visible, visible_tabla, editable, orden, activo,
  created_at, updated_at, estado_sync, eliminado
) values
  ('gt_movilidad_licencia_conducir','GT-MATRIZ_MOVILIDADES',
   'licencia_conducir','Licencia de conducir','text','text',null,
   true,true,true,true,90,true,now(),now(),'sincronizado',false),
  ('gt_movilidad_licencia_vigencia','GT-MATRIZ_MOVILIDADES',
   'licencia_vigencia','Vigencia de licencia','date','date',null,
   true,true,true,true,91,true,now(),now(),'sincronizado',false),
  ('gt_movilidad_soat_vigencia','GT-MATRIZ_MOVILIDADES',
   'soat_vigencia','Vigencia SOAT','date','date',null,
   true,true,true,true,92,true,now(),now(),'sincronizado',false),
  ('gt_movilidad_revision_vigencia','GT-MATRIZ_MOVILIDADES',
   'revision_tecnica_vigencia','Vigencia de revisión técnica','date','date',null,
   true,true,true,true,93,true,now(),now(),'sincronizado',false),
  ('gt_asistencia_movilidad_alerta_ok','GT-ASISTENCIA_PERSONAL',
   'MOVILIDAD_ALERTA_ACEPTADA','Alerta de movilidad aceptada',
   'boolean','hidden',null,false,false,true,false,90,true,
   now(),now(),'sincronizado',false),
  ('gt_asistencia_movilidad_alerta_det','GT-ASISTENCIA_PERSONAL',
   'MOVILIDAD_ALERTA_DETALLE','Detalle de alerta de movilidad',
   'text','hidden',null,false,false,true,false,91,true,
   now(),now(),'sincronizado',false)
on conflict (tabla_destino, campo) do update set
  etiqueta = excluded.etiqueta,
  tipo = excluded.tipo,
  tipo_ui = excluded.tipo_ui,
  id_campo_dropdown = excluded.id_campo_dropdown,
  requerido = excluded.requerido,
  visible = excluded.visible,
  visible_tabla = excluded.visible_tabla,
  editable = excluded.editable,
  orden = excluded.orden,
  activo = true,
  eliminado = false,
  updated_at = now();

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set requerido = true, activo = true, eliminado = false, updated_at = now()
where tabla_destino = 'GT-MATRIZ_MOVILIDADES'
  and lower(campo) in ('placa','conductor','dni_conductor');

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set tipo = 'text', tipo_ui = 'dropdown',
    id_campo_dropdown = 'GT-MATRIZ_MOVILIDADES.placa',
    updated_at = now()
where tabla_destino = 'GT-CABECERA_ASISTENCIA'
  and upper(campo) = 'PLACA';

-- Se retira el formulario redundante de la navegación y de los permisos, sin
-- eliminar su tabla ni los registros que ya existan.
update public."MATRIZ_FORMATOS_APPGT"
set activo = false, tabla_visible_app = false, updated_at = now()
where upper(coalesce(tabla_destino, '')) = 'GT_INGRESO_MOVILIDADES_APPGT';

update public."MATRIZ_FORMATO_TABLAS_APPGT"
set activo = false, updated_at = now()
where upper(coalesce(tabla_destino, '')) = 'GT_INGRESO_MOVILIDADES_APPGT';

update public."PERMISOS_DE_USUARIOS_APPGT"
set activo = false, updated_at = now()
where upper(coalesce(tabla_destino, '')) = 'GT_INGRESO_MOVILIDADES_APPGT';

-- La protección del servidor replica la validación de Flutter para evitar que
-- una carga externa o una sincronización antigua omitan el control.
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
  v_mobility jsonb;
  v_mobility_issues text[] := array[]::text[];
  v_expiration date;
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
      when v_fin < v_fecha then
        'Contrato vencido el ' || to_char(v_fin, 'DD/MM/YYYY') || '.'
      else 'Estado laboral no activo: ' || coalesce(v_status, 'SIN ESTADO') || '.'
    end;
    raise exception '%', new."BLOQUEO_MOTIVO";
  end if;

  select s.numero_sancion, s.tipo_sancion, s.fecha_fin
  into v_sancion
  from public."GH_SANCIONES_PERSONAL_APPGT" s
  where s.empresa_id = v_empresa
    and public.appgt_normalizar_clave(s.dni) =
        public.appgt_normalizar_clave(v_dni)
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

  if public.appgt_normalizar_clave(coalesce(v_placa, '')) = 'SINMOVILIDAD' then
    v_placa := null;
  end if;

  new."INGRESO_MOVILIDAD_ID" := null;
  if nullif(btrim(v_placa), '') is not null then
    select to_jsonb(m) into v_mobility
    from public."GT-MATRIZ_MOVILIDADES" m
    where public.appgt_normalizar_clave(
            public.appgt_jsonb_text(to_jsonb(m), array['placa','PLACA'])
          ) = public.appgt_normalizar_clave(v_placa)
      and coalesce(
            nullif(public.appgt_jsonb_text(
              to_jsonb(m), array['empresa_id','EMPRESA_ID']
            ), ''),
            v_empresa::text
          ) = v_empresa::text
      and public.appgt_normalizar_clave(coalesce(
            public.appgt_jsonb_text(to_jsonb(m), array['eliminado','ELIMINADO']),
            'FALSE'
          )) not in ('TRUE','1','SI')
      and public.appgt_normalizar_clave(coalesce(
            public.appgt_jsonb_text(to_jsonb(m), array['activo','ACTIVO']),
            'TRUE'
          )) not in ('FALSE','0','NO')
    order by public.appgt_jsonb_date(
      to_jsonb(m), array['updated_at','UPDATED_AT']
    ) desc nulls last
    limit 1;

    if v_mobility is null then
      raise exception 'La placa % no está registrada en GT-MATRIZ_MOVILIDADES.',
        v_placa;
    end if;

    if nullif(btrim(public.appgt_jsonb_text(
         v_mobility, array['dni_conductor','conductor_dni','DNI_CONDUCTOR']
       )), '') is null then
      v_mobility_issues := array_append(
        v_mobility_issues, 'El DNI del conductor no está registrado.'
      );
    end if;
    if nullif(btrim(public.appgt_jsonb_text(
         v_mobility, array['conductor','conductor_nombre','CONDUCTOR']
       )), '') is null then
      v_mobility_issues := array_append(
        v_mobility_issues, 'El nombre del conductor no está registrado.'
      );
    end if;
    if nullif(btrim(public.appgt_jsonb_text(
         v_mobility, array['licencia_conducir','LICENCIA_CONDUCIR']
       )), '') is null then
      v_mobility_issues := array_append(
        v_mobility_issues, 'La licencia de conducir no está registrada.'
      );
    end if;

    v_expiration := public.appgt_jsonb_date(
      v_mobility, array['licencia_vigencia','LICENCIA_VIGENCIA']
    );
    if v_expiration is null then
      v_mobility_issues := array_append(
        v_mobility_issues, 'La vigencia de la licencia no está registrada.'
      );
    elsif v_expiration < v_fecha then
      v_mobility_issues := array_append(
        v_mobility_issues,
        'La licencia de conducir venció el ' ||
          to_char(v_expiration, 'DD/MM/YYYY') || '.'
      );
    end if;

    v_expiration := public.appgt_jsonb_date(
      v_mobility, array['soat_vigencia','SOAT_VIGENCIA']
    );
    if v_expiration is null then
      v_mobility_issues := array_append(
        v_mobility_issues, 'La vigencia del SOAT no está registrada.'
      );
    elsif v_expiration < v_fecha then
      v_mobility_issues := array_append(
        v_mobility_issues,
        'El SOAT venció el ' || to_char(v_expiration, 'DD/MM/YYYY') || '.'
      );
    end if;

    v_expiration := public.appgt_jsonb_date(
      v_mobility,
      array['revision_tecnica_vigencia','REVISION_TECNICA_VIGENCIA']
    );
    if v_expiration is null then
      v_mobility_issues := array_append(
        v_mobility_issues,
        'La vigencia de la revisión técnica no está registrada.'
      );
    elsif v_expiration < v_fecha then
      v_mobility_issues := array_append(
        v_mobility_issues,
        'La revisión técnica venció el ' ||
          to_char(v_expiration, 'DD/MM/YYYY') || '.'
      );
    end if;

    if cardinality(v_mobility_issues) > 0 then
      new."MOVILIDAD_ALERTA_DETALLE" :=
        array_to_string(v_mobility_issues, ' ');
      if not coalesce(new."MOVILIDAD_ALERTA_ACEPTADA", false) then
        raise exception 'La movilidad % presenta alertas: % ¿Desea continuar?',
          v_placa, array_to_string(v_mobility_issues, ' ');
      end if;
    else
      new."MOVILIDAD_ALERTA_ACEPTADA" := false;
      new."MOVILIDAD_ALERTA_DETALLE" := null;
    end if;
  else
    new."MOVILIDAD_ALERTA_ACEPTADA" := false;
    new."MOVILIDAD_ALERTA_DETALLE" := null;
  end if;

  new."VALIDACION_LABORAL" := case
    when coalesce(new."MOVILIDAD_ALERTA_ACEPTADA", false)
      then 'VALIDADO_CON_ALERTA_MOVILIDAD'
    else 'VALIDADO'
  end;
  new."BLOQUEO_MOTIVO" := null;
  return new;
end
$$;

commit;
