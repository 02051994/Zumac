begin;

select set_config('appgt.skip_auto_fields', 'on', true);

-- =============================================================================
-- Alerts vivas: una regla mantiene como máximo un hallazgo visible.
-- =============================================================================

alter table public."EMPRESAS_APPGT"
  add column if not exists habilitar_zumac_metrics boolean not null default false;

update public."EMPRESAS_APPGT"
set habilitar_zumac_metrics = true,
    updated_at = now()
where activo;

alter table public."ZUMAC_ALERTAS_APPGT"
  add column if not exists vigencia_tipo text not null default 'SIEMPRE',
  add column if not exists vigente_desde timestamptz,
  add column if not exists vigente_hasta timestamptz,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'zumac_alertas_vigencia_tipo_check'
  ) then
    alter table public."ZUMAC_ALERTAS_APPGT"
      add constraint zumac_alertas_vigencia_tipo_check
      check (vigencia_tipo in ('SIEMPRE', 'HOY', 'SEMANA', 'ANIO', 'RANGO'));
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'zumac_alertas_vigencia_rango_check'
  ) then
    alter table public."ZUMAC_ALERTAS_APPGT"
      add constraint zumac_alertas_vigencia_rango_check
      check (vigente_hasta is null or vigente_desde is null or vigente_hasta >= vigente_desde);
  end if;
end
$$;

alter table public."ZUMAC_ACCIONES_APPGT"
  add column if not exists generada_automaticamente boolean not null default false,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null;

-- Conserva solo el estado más reciente de cada regla. Las referencias de una
-- acción histórica quedan en NULL gracias al FK ON DELETE SET NULL.
delete from public."ZUMAC_ALERTA_EVENTOS_APPGT" older
using public."ZUMAC_ALERTA_EVENTOS_APPGT" newer
where older.alerta_id = newer.alerta_id
  and (older.ultima_ocurrencia_at, older.id::text)
      < (newer.ultima_ocurrencia_at, newer.id::text);

drop index if exists public.uq_zumac_alerta_evento_abierto;
create unique index if not exists uq_zumac_alerta_evento_vivo
  on public."ZUMAC_ALERTA_EVENTOS_APPGT" (alerta_id);

create index if not exists idx_zumac_alertas_vigentes
  on public."ZUMAC_ALERTAS_APPGT" (empresa_id, activa, vigente_desde, vigente_hasta)
  where deleted_at is null;

create index if not exists idx_zumac_acciones_vivas
  on public."ZUMAC_ACCIONES_APPGT" (empresa_id, updated_at desc)
  where deleted_at is null;

-- Interpola tanto [CAMPO] como {{CAMPO}}. Cuando coinciden varias filas, reúne
-- los valores distintos para producir mensajes como "Lotes 3, 4 y 5".
create or replace function public.appgt_alerta_interpolar_agregada_v1(
  p_template text,
  p_rows jsonb
)
returns text
language plpgsql immutable
set search_path = public, pg_temp
as $$
declare
  v_result text := coalesce(p_template, '');
  v_key text;
  v_value text;
  v_values text[];
begin
  for v_key in
    select distinct key
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) row_value,
         jsonb_object_keys(row_value) key
  loop
    select array_agg(value order by value)
    into v_values
    from (
      select distinct nullif(btrim(row_value ->> v_key), '') value
      from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) row_value
      where nullif(btrim(row_value ->> v_key), '') is not null
      limit 50
    ) values_found;

    if coalesce(array_length(v_values, 1), 0) = 0 then
      v_value := '';
    elsif array_length(v_values, 1) = 1 then
      v_value := v_values[1];
    elsif array_length(v_values, 1) = 2 then
      v_value := v_values[1] || ' y ' || v_values[2];
    else
      v_value := array_to_string(v_values[1:array_length(v_values, 1)-1], ', ')
        || ' y ' || v_values[array_length(v_values, 1)];
    end if;

    v_result := replace(v_result, '[' || v_key || ']', v_value);
    v_result := replace(v_result, '{{' || v_key || '}}', v_value);
  end loop;
  return v_result;
end
$$;

create or replace function public.appgt_guardar_alerta_v1(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_id uuid;
  v_dest jsonb;
  v_tipo text := coalesce(nullif(p_payload ->> 'vigencia_tipo', ''), 'SIEMPRE');
  v_desde timestamptz := nullif(p_payload ->> 'vigente_desde', '')::timestamptz;
  v_hasta timestamptz := nullif(p_payload ->> 'vigente_hasta', '')::timestamptz;
begin
  if v_empresa_id is null or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'No tienes permiso para administrar alertas' using errcode = '42501';
  end if;
  if not coalesce((select habilitar_zumac_alerts from public."EMPRESAS_APPGT" where id=v_empresa_id), false) then
    raise exception 'Alerts no está habilitado para esta empresa';
  end if;
  if nullif(btrim(p_payload ->> 'nombre'), '') is null then raise exception 'El nombre es obligatorio'; end if;
  if v_tipo not in ('SIEMPRE','HOY','SEMANA','ANIO','RANGO') then raise exception 'Vigencia inválida'; end if;
  if v_tipo = 'RANGO' and (v_desde is null or v_hasta is null) then raise exception 'Selecciona el rango completo'; end if;
  if v_hasta is not null and v_desde is not null and v_hasta < v_desde then raise exception 'La fecha final no puede ser anterior'; end if;
  perform public.appgt_validar_alerta_v1(v_empresa_id, p_payload ->> 'tabla_origen', p_payload -> 'expresion_regla');

  v_id := nullif(p_payload ->> 'id', '')::uuid;
  if v_id is null then
    insert into public."ZUMAC_ALERTAS_APPGT" (
      empresa_id, nombre, descripcion, tipo_disparador, tabla_origen,
      expresion_regla, plantilla_titulo, plantilla_mensaje, severidad,
      frecuencia_minutos, ventana_ausencia_minutos, cooldown_minutos,
      campos_agrupacion, accion_automatica, cerrar_automaticamente,
      activa, vigencia_tipo, vigente_desde, vigente_hasta, creada_por
    ) values (
      v_empresa_id, btrim(p_payload ->> 'nombre'), nullif(btrim(p_payload ->> 'descripcion'), ''),
      coalesce(nullif(p_payload ->> 'tipo_disparador', ''), 'PROGRAMADA'), p_payload ->> 'tabla_origen',
      p_payload -> 'expresion_regla', coalesce(nullif(p_payload ->> 'plantilla_titulo', ''), p_payload ->> 'nombre'),
      coalesce(nullif(p_payload ->> 'plantilla_mensaje', ''), 'Se detectó una condición que requiere revisión.'),
      coalesce(nullif(p_payload ->> 'severidad', ''), 'MEDIA'),
      greatest(coalesce((p_payload ->> 'frecuencia_minutos')::integer, 15), 1),
      nullif(p_payload ->> 'ventana_ausencia_minutos', '')::integer,
      greatest(coalesce((p_payload ->> 'cooldown_minutos')::integer, 60), 0),
      coalesce(p_payload -> 'campos_agrupacion', '[]'::jsonb),
      coalesce(p_payload -> 'accion_automatica', '{}'::jsonb),
      coalesce((p_payload ->> 'cerrar_automaticamente')::boolean, false),
      coalesce((p_payload ->> 'activa')::boolean, true), v_tipo,
      case when v_tipo='SIEMPRE' then null else v_desde end,
      case when v_tipo='SIEMPRE' then null else v_hasta end,
      auth.uid()
    ) returning id into v_id;
  else
    update public."ZUMAC_ALERTAS_APPGT" set
      nombre=btrim(p_payload ->> 'nombre'),
      descripcion=nullif(btrim(p_payload ->> 'descripcion'), ''),
      tipo_disparador=coalesce(nullif(p_payload ->> 'tipo_disparador',''), tipo_disparador),
      tabla_origen=p_payload ->> 'tabla_origen',
      expresion_regla=p_payload -> 'expresion_regla',
      plantilla_titulo=coalesce(nullif(p_payload ->> 'plantilla_titulo',''), p_payload ->> 'nombre'),
      plantilla_mensaje=coalesce(nullif(p_payload ->> 'plantilla_mensaje',''), plantilla_mensaje),
      severidad=coalesce(nullif(p_payload ->> 'severidad',''), severidad),
      frecuencia_minutos=greatest(coalesce((p_payload ->> 'frecuencia_minutos')::integer, frecuencia_minutos),1),
      ventana_ausencia_minutos=nullif(p_payload ->> 'ventana_ausencia_minutos','')::integer,
      cooldown_minutos=greatest(coalesce((p_payload ->> 'cooldown_minutos')::integer,cooldown_minutos),0),
      campos_agrupacion=coalesce(p_payload -> 'campos_agrupacion',campos_agrupacion),
      accion_automatica=coalesce(p_payload -> 'accion_automatica',accion_automatica),
      cerrar_automaticamente=coalesce((p_payload ->> 'cerrar_automaticamente')::boolean,cerrar_automaticamente),
      activa=coalesce((p_payload ->> 'activa')::boolean,activa),
      vigencia_tipo=v_tipo,
      vigente_desde=case when v_tipo='SIEMPRE' then null else v_desde end,
      vigente_hasta=case when v_tipo='SIEMPRE' then null else v_hasta end,
      deleted_at=null, deleted_by=null, proxima_ejecucion=now()
    where id=v_id and empresa_id=v_empresa_id;
    if not found then raise exception 'Alerta no encontrada'; end if;
  end if;

  if p_payload ? 'destinatarios' then
    delete from public."ZUMAC_ALERTA_DESTINATARIOS_APPGT" where alerta_id=v_id and empresa_id=v_empresa_id;
    for v_dest in select value from jsonb_array_elements(coalesce(p_payload -> 'destinatarios','[]'::jsonb))
    loop
      if v_dest ->> 'tipo_destinatario'='USUARIO' and not exists (
        select 1 from public."USUARIOS_EMPRESAS_APPGT" ue
        where ue.empresa_id=v_empresa_id and ue.user_id=nullif(v_dest ->> 'user_id','')::uuid and ue.activo
      ) then raise exception 'El destinatario no pertenece a la empresa'; end if;
      insert into public."ZUMAC_ALERTA_DESTINATARIOS_APPGT" (
        empresa_id, alerta_id, tipo_destinatario, user_id, rol, canal
      ) values (
        v_empresa_id, v_id, coalesce(v_dest ->> 'tipo_destinatario','TODOS'),
        nullif(v_dest ->> 'user_id','')::uuid, nullif(v_dest ->> 'rol',''),
        coalesce(nullif(v_dest ->> 'canal',''),'APP')
      );
    end loop;
  end if;
  if not exists(select 1 from public."ZUMAC_ALERTA_DESTINATARIOS_APPGT" where alerta_id=v_id) then
    insert into public."ZUMAC_ALERTA_DESTINATARIOS_APPGT"(empresa_id,alerta_id,tipo_destinatario)
    values(v_empresa_id,v_id,'TODOS');
  end if;
  return jsonb_build_object('id',v_id,'guardada',true);
end
$$;

create or replace function public.appgt_cambiar_alerta_activa_v1(p_alerta_id uuid, p_activa boolean)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_empresa_id uuid:=public.appgt_empresa_actual_id(); v_row public."ZUMAC_ALERTAS_APPGT"%rowtype;
begin
  if v_empresa_id is null or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then raise exception 'Sin permiso' using errcode='42501'; end if;
  update public."ZUMAC_ALERTAS_APPGT" set activa=p_activa, proxima_ejecucion=now()
  where id=p_alerta_id and empresa_id=v_empresa_id and deleted_at is null returning * into v_row;
  if v_row.id is null then raise exception 'Alerta no encontrada'; end if;
  if not p_activa then
    update public."ZUMAC_ACCIONES_APPGT" set estado='CANCELADA', completada_at=now()
    where alerta_id=p_alerta_id and generada_automaticamente and estado in ('PENDIENTE','EN_PROGRESO');
    delete from public."ZUMAC_ALERTA_EVENTOS_APPGT" where alerta_id=p_alerta_id;
  end if;
  return to_jsonb(v_row);
end
$$;

create or replace function public.appgt_eliminar_alerta_v1(p_alerta_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_empresa_id uuid:=public.appgt_empresa_actual_id();
begin
  if v_empresa_id is null or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then raise exception 'Sin permiso' using errcode='42501'; end if;
  update public."ZUMAC_ALERTAS_APPGT" set activa=false,deleted_at=now(),deleted_by=auth.uid()
  where id=p_alerta_id and empresa_id=v_empresa_id and deleted_at is null;
  if not found then raise exception 'Alerta no encontrada'; end if;
  update public."ZUMAC_ACCIONES_APPGT" set estado='CANCELADA',completada_at=now()
  where alerta_id=p_alerta_id and generada_automaticamente and estado in ('PENDIENTE','EN_PROGRESO');
  delete from public."ZUMAC_ALERTA_EVENTOS_APPGT" where alerta_id=p_alerta_id;
  return jsonb_build_object('eliminada',true,'id',p_alerta_id);
end
$$;

create or replace function public.appgt_eliminar_accion_v1(p_accion_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_empresa_id uuid:=public.appgt_empresa_actual_id();
begin
  if v_empresa_id is null then raise exception 'Sin acceso' using errcode='42501'; end if;
  update public."ZUMAC_ACCIONES_APPGT" set estado='CANCELADA',deleted_at=now(),deleted_by=auth.uid(),completada_at=coalesce(completada_at,now())
  where id=p_accion_id and empresa_id=v_empresa_id and deleted_at is null
    and (creada_por=auth.uid() or public.appgt_puede_gestionar_configuracion(v_empresa_id));
  if not found then raise exception 'Acción no encontrada o sin permiso'; end if;
  return jsonb_build_object('eliminada',true,'id',p_accion_id);
end
$$;

create or replace function public.appgt_evaluar_alertas_v1(p_limit integer default 100)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp
as $$
declare
  v_caller uuid:=auth.uid();
  v_current_company uuid:=public.appgt_empresa_actual_id();
  v_rule public."ZUMAC_ALERTAS_APPGT"%rowtype;
  v_row jsonb;
  v_rows jsonb;
  v_exec_id uuid;
  v_event_id uuid;
  v_source jsonb;
  v_reviewed integer;
  v_matches integer;
  v_created integer;
  v_total_rules integer:=0;
  v_total_events integer:=0;
  v_condition_hit boolean;
  v_existed boolean;
begin
  if v_caller is not null and (v_current_company is null or not public.appgt_puede_gestionar_configuracion(v_current_company)) then
    raise exception 'No tienes permiso para evaluar alertas' using errcode='42501';
  end if;

  for v_rule in
    select a.*
    from public."ZUMAC_ALERTAS_APPGT" a
    join public."EMPRESAS_APPGT" e on e.id=a.empresa_id and e.activo and e.habilitar_zumac_alerts
    where a.activa and a.deleted_at is null and a.proxima_ejecucion<=now()
      and (a.vigente_desde is null or now()>=a.vigente_desde)
      and (a.vigente_hasta is null or now()<=a.vigente_hasta)
      and (v_caller is null or a.empresa_id=v_current_company)
    order by a.proxima_ejecucion
    limit least(greatest(p_limit,1),500)
    for update of a skip locked
  loop
    v_total_rules:=v_total_rules+1; v_reviewed:=0; v_matches:=0; v_created:=0; v_rows:='[]'::jsonb;
    insert into public."ZUMAC_ALERTA_EJECUCIONES_APPGT"(empresa_id,alerta_id,estado)
    values(v_rule.empresa_id,v_rule.id,'INICIADA') returning id into v_exec_id;
    begin
      for v_row in select * from public.appgt_alerta_filas_v1(v_rule.empresa_id,v_rule.tabla_origen,500)
      loop
        v_reviewed:=v_reviewed+1;
        if public.appgt_alerta_cumple_v1(v_row,v_rule.expresion_regla) then
          v_matches:=v_matches+1;
          if v_rule.tipo_disparador<>'AUSENCIA' and jsonb_array_length(v_rows)<100 then
            v_rows:=v_rows||jsonb_build_array(v_row);
          end if;
        end if;
      end loop;

      v_condition_hit:=case when v_rule.tipo_disparador='AUSENCIA' then v_matches=0 else v_matches>0 end;
      if v_condition_hit then
        if v_rule.tipo_disparador='AUSENCIA' then v_rows:=jsonb_build_array('{}'::jsonb); end if;
        select jsonb_build_object(
          'formato_id',ft.formato_id,'modulo_id',f.modulo_id,
          'formato_nombre',coalesce(nullif(f.nombre,''),nullif(ft.nombre,''),v_rule.tabla_origen),
          'tabla_nombre',v_rule.tabla_origen
        ) into v_source
        from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
        left join public."MATRIZ_FORMATOS_APPGT" f on f.empresa_id=ft.empresa_id and f.id=ft.formato_id
        where ft.empresa_id=v_rule.empresa_id and ft.tabla_destino=v_rule.tabla_origen
          and coalesce(ft.activo,true) and ft.deleted_at is null
        order by ft.orden limit 1;
        v_source:=coalesce(v_source,jsonb_build_object('tabla_nombre',v_rule.tabla_origen,'formato_nombre',v_rule.tabla_origen));
        select exists(select 1 from public."ZUMAC_ALERTA_EVENTOS_APPGT" where alerta_id=v_rule.id) into v_existed;

        insert into public."ZUMAC_ALERTA_EVENTOS_APPGT"(
          empresa_id,alerta_id,tabla_origen,registro_origen_id,clave_dedupe,
          titulo,mensaje,severidad,estado,datos_origen,contexto,ocurrencias,
          detectada_at,ultima_ocurrencia_at
        ) values (
          v_rule.empresa_id,v_rule.id,v_rule.tabla_origen,
          coalesce(v_rows->0->>'id',v_rows->0->>'ID'),'LIVE',
          public.appgt_alerta_interpolar_agregada_v1(v_rule.plantilla_titulo,v_rows),
          public.appgt_alerta_interpolar_agregada_v1(v_rule.plantilla_mensaje,v_rows),
          v_rule.severidad,'DETECTADA',jsonb_build_object('rows',v_rows),
          v_source||jsonb_build_object('coincidencias',case when v_rule.tipo_disparador='AUSENCIA' then 0 else v_matches end,'evaluada_at',now()),
          case when v_rule.tipo_disparador='AUSENCIA' then 1 else v_matches end,now(),now()
        ) on conflict(alerta_id) do update set
          tabla_origen=excluded.tabla_origen,registro_origen_id=excluded.registro_origen_id,
          titulo=excluded.titulo,mensaje=excluded.mensaje,severidad=excluded.severidad,
          estado='DETECTADA',atendida_at=null,cerrada_at=null,
          datos_origen=excluded.datos_origen,contexto=excluded.contexto,
          ocurrencias=excluded.ocurrencias,ultima_ocurrencia_at=now()
        returning id into v_event_id;

        if not v_existed then v_created:=1; v_total_events:=v_total_events+1; end if;
        if coalesce((v_rule.accion_automatica->>'crear_tarea')::boolean,false) then
          update public."ZUMAC_ACCIONES_APPGT" set
            alerta_evento_id=v_event_id,
            titulo=coalesce(nullif(v_rule.accion_automatica->>'titulo',''),'Atender: '||v_rule.nombre),
            descripcion=public.appgt_alerta_interpolar_agregada_v1(v_rule.plantilla_mensaje,v_rows),
            updated_at=now()
          where alerta_id=v_rule.id and generada_automaticamente and deleted_at is null
            and estado in ('PENDIENTE','EN_PROGRESO');
          if not found then
            insert into public."ZUMAC_ACCIONES_APPGT"(
              empresa_id,alerta_evento_id,alerta_id,tipo,titulo,descripcion,prioridad,
              asignado_a,fecha_limite,creada_por,generada_automaticamente
            ) values (
              v_rule.empresa_id,v_event_id,v_rule.id,'TAREA',
              coalesce(nullif(v_rule.accion_automatica->>'titulo',''),'Atender: '||v_rule.nombre),
              public.appgt_alerta_interpolar_agregada_v1(v_rule.plantilla_mensaje,v_rows),
              case when v_rule.severidad in ('ALTA','CRITICA') then v_rule.severidad else 'MEDIA' end,
              nullif(v_rule.accion_automatica->>'asignado_a','')::uuid,
              case when (v_rule.accion_automatica->>'plazo_horas')~'^[0-9]+$'
                then now()+make_interval(hours=>(v_rule.accion_automatica->>'plazo_horas')::integer) else null end,
              v_rule.creada_por,true
            );
          end if;
        end if;
      else
        update public."ZUMAC_ACCIONES_APPGT" set estado='CANCELADA',completada_at=now()
        where alerta_id=v_rule.id and generada_automaticamente and estado in ('PENDIENTE','EN_PROGRESO');
        delete from public."ZUMAC_ALERTA_EVENTOS_APPGT" where alerta_id=v_rule.id;
      end if;

      update public."ZUMAC_ALERTAS_APPGT" set ultima_ejecucion=now(),proxima_ejecucion=now()+make_interval(mins=>v_rule.frecuencia_minutos) where id=v_rule.id;
      update public."ZUMAC_ALERTA_EJECUCIONES_APPGT" set estado='COMPLETADA',filas_revisadas=v_reviewed,coincidencias=v_matches,eventos_creados=v_created,finalizada_at=now() where id=v_exec_id;
    exception when others then
      update public."ZUMAC_ALERTA_EJECUCIONES_APPGT" set estado='ERROR',detalle=sqlerrm,finalizada_at=now() where id=v_exec_id;
      update public."ZUMAC_ALERTAS_APPGT" set ultima_ejecucion=now(),proxima_ejecucion=now()+interval '15 minutes' where id=v_rule.id;
    end;
  end loop;
  return jsonb_build_object('reglas_evaluadas',v_total_rules,'eventos_creados',v_total_events);
end
$$;

-- =============================================================================
-- Metrics: dashboards independientes del antiguo módulo Reportes.
-- =============================================================================

create table if not exists public."ZUMAC_METRICS_DASHBOARDS_APPGT"(
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  nombre text not null,
  descripcion text,
  color text not null default '#176B87',
  filtros_globales jsonb not null default '[]'::jsonb,
  orden integer not null default 0,
  activo boolean not null default true,
  creado_por uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public."ZUMAC_METRICS_WIDGETS_APPGT"(
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  dashboard_id uuid not null references public."ZUMAC_METRICS_DASHBOARDS_APPGT"(id) on delete cascade,
  titulo text not null,
  descripcion text,
  tabla_origen text not null,
  campo_dimension text,
  campo_valor text,
  campo_serie text,
  agregacion text not null default 'COUNT' check(agregacion in('COUNT','SUM','AVG','MIN','MAX')),
  tipo_grafico text not null default 'BAR' check(tipo_grafico in('KPI','BAR','LINE','AREA','PIE','TABLE','SCATTER')),
  filtros jsonb not null default '[]'::jsonb,
  configuracion jsonb not null default '{}'::jsonb,
  posicion_x integer not null default 0,
  posicion_y integer not null default 0,
  ancho integer not null default 6 check(ancho between 1 and 12),
  alto integer not null default 4 check(alto between 2 and 12),
  orden integer not null default 0,
  activo boolean not null default true,
  creado_por uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public."ZUMAC_METRICS_RELACIONES_APPGT"(
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  dashboard_id uuid not null references public."ZUMAC_METRICS_DASHBOARDS_APPGT"(id) on delete cascade,
  tabla_origen text not null,
  campo_origen text not null,
  tabla_destino text not null,
  campo_destino text not null,
  nombre text,
  activo boolean not null default true,
  creado_por uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check(tabla_origen<>tabla_destino or campo_origen<>campo_destino)
);

create index if not exists idx_zumac_metrics_dashboards on public."ZUMAC_METRICS_DASHBOARDS_APPGT"(empresa_id,orden) where deleted_at is null;
create index if not exists idx_zumac_metrics_widgets on public."ZUMAC_METRICS_WIDGETS_APPGT"(dashboard_id,orden) where deleted_at is null;
create index if not exists idx_zumac_metrics_relaciones on public."ZUMAC_METRICS_RELACIONES_APPGT"(dashboard_id) where deleted_at is null;

do $$
declare v_table text;
begin
  foreach v_table in array array['ZUMAC_METRICS_DASHBOARDS_APPGT','ZUMAC_METRICS_WIDGETS_APPGT','ZUMAC_METRICS_RELACIONES_APPGT'] loop
    execute format('drop trigger if exists zumac_touch_updated_at on public.%I',v_table);
    execute format('create trigger zumac_touch_updated_at before update on public.%I for each row execute function public.appgt_zumac_touch_updated_at()',v_table);
    execute format('alter table public.%I enable row level security',v_table);
    execute format('drop policy if exists zumac_metrics_select on public.%I',v_table);
    execute format('create policy zumac_metrics_select on public.%I for select using(public.appgt_puede_acceder_empresa(empresa_id))',v_table);
    execute format('drop policy if exists zumac_metrics_manage on public.%I',v_table);
    execute format('create policy zumac_metrics_manage on public.%I for all using(public.appgt_puede_gestionar_configuracion(empresa_id)) with check(public.appgt_puede_gestionar_configuracion(empresa_id))',v_table);
  end loop;
end
$$;

create or replace function public.appgt_metrics_contexto_v1()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_empresa_id uuid:=public.appgt_empresa_actual_id(); v_enabled boolean; v_manage boolean;
begin
  if v_empresa_id is null then raise exception 'authentication required' using errcode='42501'; end if;
  select habilitar_zumac_metrics into v_enabled from public."EMPRESAS_APPGT" where id=v_empresa_id and activo;
  v_manage:=public.appgt_puede_gestionar_configuracion(v_empresa_id);
  return jsonb_build_object(
    'empresa_id',v_empresa_id,'metrics_habilitado',coalesce(v_enabled,false),'puede_gestionar',v_manage,
    'fuentes',coalesce((
      select jsonb_agg(source order by source->>'nombre') from (
        select jsonb_build_object(
          'tabla',ft.tabla_destino,'nombre',coalesce(nullif(f.nombre,''),nullif(ft.nombre,''),ft.tabla_destino),
          'formato_id',ft.formato_id,'modulo_id',f.modulo_id,
          'campos',coalesce((select jsonb_agg(jsonb_build_object('campo',c.campo,'etiqueta',coalesce(nullif(c.etiqueta,''),c.campo),'tipo',coalesce(nullif(c.tipo,''),'text')) order by c.orden,c.campo)
            from public."MATRIZ_CAMPOS_FORMATO_APPGT" c
            join information_schema.columns pc on pc.table_schema='public' and pc.table_name=ft.tabla_destino and pc.column_name=c.campo
            where c.empresa_id=v_empresa_id and c.tabla_destino=ft.tabla_destino and coalesce(c.activo,true) and not coalesce(c.eliminado,false)),'[]'::jsonb)
        ) source
        from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
        left join public."MATRIZ_FORMATOS_APPGT" f on f.empresa_id=ft.empresa_id and f.id=ft.formato_id
        where ft.empresa_id=v_empresa_id and coalesce(ft.activo,true) and ft.deleted_at is null
          and public.appgt_tabla_alertable_v1(v_empresa_id,ft.tabla_destino)
        group by ft.tabla_destino,ft.nombre,f.nombre,ft.formato_id,f.modulo_id
      ) sources
    ),'[]'::jsonb)
  );
end
$$;

create or replace function public.appgt_guardar_dashboard_metrics_v1(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_empresa_id uuid:=public.appgt_empresa_actual_id(); v_id uuid:=nullif(p_payload->>'id','')::uuid;
begin
  if v_empresa_id is null or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then raise exception 'Sin permiso' using errcode='42501'; end if;
  if nullif(btrim(p_payload->>'nombre'),'') is null then raise exception 'El nombre es obligatorio'; end if;
  if v_id is null then
    insert into public."ZUMAC_METRICS_DASHBOARDS_APPGT"(empresa_id,nombre,descripcion,color,filtros_globales,orden,creado_por)
    values(v_empresa_id,btrim(p_payload->>'nombre'),nullif(btrim(p_payload->>'descripcion'),''),coalesce(nullif(p_payload->>'color',''),'#176B87'),coalesce(p_payload->'filtros_globales','[]'::jsonb),coalesce((p_payload->>'orden')::integer,0),auth.uid()) returning id into v_id;
  else
    update public."ZUMAC_METRICS_DASHBOARDS_APPGT" set nombre=btrim(p_payload->>'nombre'),descripcion=nullif(btrim(p_payload->>'descripcion'),''),color=coalesce(nullif(p_payload->>'color',''),color),filtros_globales=coalesce(p_payload->'filtros_globales',filtros_globales),deleted_at=null
    where id=v_id and empresa_id=v_empresa_id;
    if not found then raise exception 'Dashboard no encontrado'; end if;
  end if;
  return jsonb_build_object('id',v_id,'guardado',true);
end
$$;

create or replace function public.appgt_guardar_widget_metrics_v1(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_empresa_id uuid:=public.appgt_empresa_actual_id(); v_id uuid:=nullif(p_payload->>'id','')::uuid; v_dashboard uuid:=nullif(p_payload->>'dashboard_id','')::uuid;
begin
  if v_empresa_id is null or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then raise exception 'Sin permiso' using errcode='42501'; end if;
  if not exists(select 1 from public."ZUMAC_METRICS_DASHBOARDS_APPGT" where id=v_dashboard and empresa_id=v_empresa_id and deleted_at is null) then raise exception 'Dashboard no disponible'; end if;
  if not public.appgt_tabla_alertable_v1(v_empresa_id,p_payload->>'tabla_origen') then raise exception 'Fuente no disponible'; end if;
  if v_id is null then
    insert into public."ZUMAC_METRICS_WIDGETS_APPGT"(empresa_id,dashboard_id,titulo,descripcion,tabla_origen,campo_dimension,campo_valor,campo_serie,agregacion,tipo_grafico,filtros,configuracion,ancho,alto,orden,creado_por)
    values(v_empresa_id,v_dashboard,btrim(p_payload->>'titulo'),nullif(btrim(p_payload->>'descripcion'),''),p_payload->>'tabla_origen',nullif(p_payload->>'campo_dimension',''),nullif(p_payload->>'campo_valor',''),nullif(p_payload->>'campo_serie',''),coalesce(nullif(p_payload->>'agregacion',''),'COUNT'),coalesce(nullif(p_payload->>'tipo_grafico',''),'BAR'),coalesce(p_payload->'filtros','[]'::jsonb),coalesce(p_payload->'configuracion','{}'::jsonb),greatest(1,least(coalesce((p_payload->>'ancho')::integer,6),12)),greatest(2,least(coalesce((p_payload->>'alto')::integer,4),12)),coalesce((p_payload->>'orden')::integer,0),auth.uid()) returning id into v_id;
  else
    update public."ZUMAC_METRICS_WIDGETS_APPGT" set titulo=btrim(p_payload->>'titulo'),descripcion=nullif(btrim(p_payload->>'descripcion'),''),tabla_origen=p_payload->>'tabla_origen',campo_dimension=nullif(p_payload->>'campo_dimension',''),campo_valor=nullif(p_payload->>'campo_valor',''),campo_serie=nullif(p_payload->>'campo_serie',''),agregacion=coalesce(nullif(p_payload->>'agregacion',''),agregacion),tipo_grafico=coalesce(nullif(p_payload->>'tipo_grafico',''),tipo_grafico),filtros=coalesce(p_payload->'filtros',filtros),configuracion=coalesce(p_payload->'configuracion',configuracion),ancho=greatest(1,least(coalesce((p_payload->>'ancho')::integer,ancho),12)),alto=greatest(2,least(coalesce((p_payload->>'alto')::integer,alto),12)),deleted_at=null
    where id=v_id and empresa_id=v_empresa_id and dashboard_id=v_dashboard;
    if not found then raise exception 'Gráfico no encontrado'; end if;
  end if;
  return jsonb_build_object('id',v_id,'guardado',true);
end
$$;

create or replace function public.appgt_guardar_relacion_metrics_v1(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_empresa_id uuid:=public.appgt_empresa_actual_id(); v_id uuid:=nullif(p_payload->>'id','')::uuid; v_dashboard uuid:=nullif(p_payload->>'dashboard_id','')::uuid;
begin
  if v_empresa_id is null or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then raise exception 'Sin permiso' using errcode='42501'; end if;
  if not exists(select 1 from public."ZUMAC_METRICS_DASHBOARDS_APPGT" where id=v_dashboard and empresa_id=v_empresa_id and deleted_at is null) then raise exception 'Dashboard no disponible'; end if;
  if not public.appgt_tabla_alertable_v1(v_empresa_id,p_payload->>'tabla_origen') or not public.appgt_tabla_alertable_v1(v_empresa_id,p_payload->>'tabla_destino') then raise exception 'Fuente no disponible'; end if;
  if v_id is null then
    insert into public."ZUMAC_METRICS_RELACIONES_APPGT"(empresa_id,dashboard_id,tabla_origen,campo_origen,tabla_destino,campo_destino,nombre,creado_por)
    values(v_empresa_id,v_dashboard,p_payload->>'tabla_origen',p_payload->>'campo_origen',p_payload->>'tabla_destino',p_payload->>'campo_destino',nullif(btrim(p_payload->>'nombre'),''),auth.uid()) returning id into v_id;
  else
    update public."ZUMAC_METRICS_RELACIONES_APPGT" set tabla_origen=p_payload->>'tabla_origen',campo_origen=p_payload->>'campo_origen',tabla_destino=p_payload->>'tabla_destino',campo_destino=p_payload->>'campo_destino',nombre=nullif(btrim(p_payload->>'nombre'),''),deleted_at=null
    where id=v_id and empresa_id=v_empresa_id and dashboard_id=v_dashboard;
    if not found then raise exception 'Relación no encontrada'; end if;
  end if;
  return jsonb_build_object('id',v_id,'guardada',true);
end
$$;

create or replace function public.appgt_eliminar_metrics_v1(p_tipo text,p_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_empresa_id uuid:=public.appgt_empresa_actual_id();
begin
  if v_empresa_id is null or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then raise exception 'Sin permiso' using errcode='42501'; end if;
  case upper(p_tipo)
    when 'DASHBOARD' then update public."ZUMAC_METRICS_DASHBOARDS_APPGT" set deleted_at=now(),activo=false where id=p_id and empresa_id=v_empresa_id;
    when 'WIDGET' then update public."ZUMAC_METRICS_WIDGETS_APPGT" set deleted_at=now(),activo=false where id=p_id and empresa_id=v_empresa_id;
    when 'RELACION' then update public."ZUMAC_METRICS_RELACIONES_APPGT" set deleted_at=now(),activo=false where id=p_id and empresa_id=v_empresa_id;
    else raise exception 'Tipo inválido';
  end case;
  if not found then raise exception 'Elemento no encontrado'; end if;
  return jsonb_build_object('eliminado',true,'id',p_id,'tipo',upper(p_tipo));
end
$$;

revoke all on function public.appgt_metrics_contexto_v1() from public,anon;
revoke all on function public.appgt_guardar_dashboard_metrics_v1(jsonb) from public,anon;
revoke all on function public.appgt_guardar_widget_metrics_v1(jsonb) from public,anon;
revoke all on function public.appgt_guardar_relacion_metrics_v1(jsonb) from public,anon;
revoke all on function public.appgt_eliminar_metrics_v1(text,uuid) from public,anon;
revoke all on function public.appgt_cambiar_alerta_activa_v1(uuid,boolean) from public,anon;
revoke all on function public.appgt_eliminar_alerta_v1(uuid) from public,anon;
revoke all on function public.appgt_eliminar_accion_v1(uuid) from public,anon;

grant select on public."ZUMAC_METRICS_DASHBOARDS_APPGT",public."ZUMAC_METRICS_WIDGETS_APPGT",public."ZUMAC_METRICS_RELACIONES_APPGT" to authenticated;
grant execute on function public.appgt_metrics_contexto_v1() to authenticated;
grant execute on function public.appgt_guardar_dashboard_metrics_v1(jsonb) to authenticated;
grant execute on function public.appgt_guardar_widget_metrics_v1(jsonb) to authenticated;
grant execute on function public.appgt_guardar_relacion_metrics_v1(jsonb) to authenticated;
grant execute on function public.appgt_eliminar_metrics_v1(text,uuid) to authenticated;
grant execute on function public.appgt_cambiar_alerta_activa_v1(uuid,boolean) to authenticated;
grant execute on function public.appgt_eliminar_alerta_v1(uuid) to authenticated;
grant execute on function public.appgt_eliminar_accion_v1(uuid) to authenticated;
grant execute on function public.appgt_alerta_interpolar_agregada_v1(text,jsonb) to authenticated,service_role;

commit;
