begin;

create extension if not exists pgcrypto;

-- Un único documento laboral para permisos, licencias y descansos. Los datos
-- operativos anteriores no se eliminan; sus formatos se retiran del menú.
create table if not exists public."GH_PERMISOS_LICENCIAS_APPGT" (
  id uuid primary key default gen_random_uuid(),
  id_local uuid not null default gen_random_uuid() unique,
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  numero_solicitud text not null,
  fecha_solicitud date not null default current_date,
  dni text not null,
  trabajador text not null,
  puesto text,
  area text,
  tipo_permiso text not null check (tipo_permiso in (
    'DESCANSO MEDICO','LICENCIA DE MATERNIDAD','PERMISO SIN GOCE',
    'COMISION DE SERVICIO','LICENCIA DE PATERNIDAD',
    'LICENCIA POR FALLECIMIENTO','VACACIONES','OTRO'
  )),
  fecha_inicio date not null,
  fecha_fin date not null,
  hora_inicio time,
  hora_fin time,
  dias_solicitados integer not null default 1 check (dias_solicitados > 0),
  con_goce_haber boolean not null default true,
  motivo text not null,
  observaciones text,
  documento_sustento text,
  firma_trabajador text,
  documento_generado text,
  estado text not null default 'SOLICITADO' check (estado in (
    'BORRADOR','SOLICITADO','APROBADO','RECHAZADO','ANULADO'
  )),
  created_by uuid references auth.users(id) default auth.uid(),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  eliminado boolean not null default false,
  estado_sync text not null default 'sincronizado',
  version integer not null default 1,
  unique (empresa_id, numero_solicitud),
  check (fecha_fin >= fecha_inicio)
);

create or replace function public.appgt_gh_permisos_preparar_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  new.dias_solicitados := greatest(1, new.fecha_fin - new.fecha_inicio + 1);
  if new.tipo_permiso = 'PERMISO SIN GOCE' then
    new.con_goce_haber := false;
  end if;
  new.updated_at := now();
  new.updated_by := auth.uid();
  if tg_op = 'UPDATE' then new.version := old.version + 1; end if;
  return new;
end
$$;

drop trigger if exists appgt_gh_permisos_preparar_trigger
  on public."GH_PERMISOS_LICENCIAS_APPGT";
create trigger appgt_gh_permisos_preparar_trigger
before insert or update on public."GH_PERMISOS_LICENCIAS_APPGT"
for each row execute function public.appgt_gh_permisos_preparar_v1();

-- Conceptos que la planilla necesita conservar explícitamente. Los demás
-- conceptos legales ya existen desde la migración de planilla agraria.
alter table public."PLANILLA_TRABAJADORES_ZUMAC"
  add column if not exists permiso_sin_goce numeric(12,4) not null default 0,
  add column if not exists vacaciones numeric(12,4) not null default 0,
  add column if not exists vacaciones_costo numeric(18,6) not null default 0;

create or replace function public.appgt_planilla_costo_vacaciones_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  new.permiso_sin_goce := greatest(coalesce(new.permiso_sin_goce, 0), 0);
  new.vacaciones := greatest(coalesce(new.vacaciones, 0), 0);
  new.vacaciones_costo := round(
    new.vacaciones * coalesce(new.costo_hora_sueldo, 0), 6
  );
  new.ingreso_bruto := coalesce(new.ingreso_bruto, 0) + new.vacaciones_costo;
  new.inafecto := coalesce(new.inafecto, 0) + new.vacaciones_costo;
  new.total_neto := coalesce(new.total_neto, 0) + new.vacaciones_costo;
  return new;
end
$$;

drop trigger if exists zz_appgt_planilla_costo_vacaciones_trigger
  on public."PLANILLA_TRABAJADORES_ZUMAC";
create trigger zz_appgt_planilla_costo_vacaciones_trigger
before insert or update on public."PLANILLA_TRABAJADORES_ZUMAC"
for each row execute function public.appgt_planilla_costo_vacaciones_v1();

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
  if nullif(btrim(p_dni), '') is null
     or p_desde is null or p_hasta is null or p_hasta < p_desde then
    return;
  end if;

  -- Primero reconstruye asistencia/tareo; después aplica la novedad laboral.
  perform public.appgt_recalcular_planilla_zumac(p_dni, p_desde, p_hasta);

  with ranked as (
    select p.id_local, p.fecha,
      row_number() over (
        partition by p.dni, p.fecha
        order by case when p.origen_clave = 'SIN_TAREO' then 0 else 1 end,
                 p.origen_clave, p.id_local
      ) row_number
    from public."PLANILLA_TRABAJADORES_ZUMAC" p
    where public.appgt_normalizar_clave(p.dni)
          = public.appgt_normalizar_clave(p_dni)
      and p.fecha between p_desde and p_hasta
      and p.activo and not p.eliminado and p.deleted_at is null
  ), resolved as (
    select r.id_local, r.row_number,
      q.tipo_permiso,
      coalesce(q.horas_permiso, 0) horas_permiso
    from ranked r
    left join lateral (
      select q.tipo_permiso,
        case
          when q.fecha_inicio = q.fecha_fin
               and q.hora_inicio is not null and q.hora_fin is not null
            then least(
              8::numeric,
              greatest(
                extract(epoch from (q.hora_fin - q.hora_inicio)) / 3600,
                0
              )
            )
          else 8::numeric
        end horas_permiso
      from public."GH_PERMISOS_LICENCIAS_APPGT" q
      where q.empresa_id = public.appgt_empresa_actual_id()
        and public.appgt_normalizar_clave(q.dni)
            = public.appgt_normalizar_clave(p_dni)
        and r.fecha between q.fecha_inicio and q.fecha_fin
        and q.estado in ('SOLICITADO','APROBADO')
        and not q.eliminado and q.deleted_at is null
      order by case when q.estado = 'APROBADO' then 0 else 1 end,
               q.updated_at desc, q.id
      limit 1
    ) q on true
  )
  update public."PLANILLA_TRABAJADORES_ZUMAC" p
  set horas_trabajadas = case
        when r.tipo_permiso in (
          'DESCANSO MEDICO','LICENCIA DE MATERNIDAD','PERMISO SIN GOCE',
          'COMISION DE SERVICIO','LICENCIA DE PATERNIDAD',
          'LICENCIA POR FALLECIMIENTO','VACACIONES'
        ) and r.horas_permiso >= 8 then 0
        when r.tipo_permiso is not null and r.row_number = 1
          then greatest(p.horas_trabajadas - r.horas_permiso, 0)
        else p.horas_trabajadas
      end,
      descanso_medico = case
        when r.row_number = 1 and r.tipo_permiso = 'DESCANSO MEDICO'
          then r.horas_permiso else 0 end,
      licencia_maternidad = case
        when r.row_number = 1 and r.tipo_permiso = 'LICENCIA DE MATERNIDAD'
          then r.horas_permiso else 0 end,
      licencia_paternidad = case
        when r.row_number = 1 and r.tipo_permiso = 'LICENCIA DE PATERNIDAD'
          then r.horas_permiso else 0 end,
      licencia_fallecimiento = case
        when r.row_number = 1
             and r.tipo_permiso = 'LICENCIA POR FALLECIMIENTO'
          then r.horas_permiso else 0 end,
      comision = case
        when r.row_number = 1 and r.tipo_permiso = 'COMISION DE SERVICIO'
          then r.horas_permiso else 0 end,
      permiso_sin_goce = case
        when r.row_number = 1 and r.tipo_permiso = 'PERMISO SIN GOCE'
          then r.horas_permiso else 0 end,
      vacaciones = case
        when r.row_number = 1 and r.tipo_permiso = 'VACACIONES'
          then r.horas_permiso else 0 end,
      updated_at = now()
  from resolved r
  where p.id_local = r.id_local;
end
$$;

create or replace function public.appgt_gh_permisos_refrescar_planilla_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op in ('UPDATE','DELETE') then
    perform public.appgt_aplicar_permisos_planilla_rango_v1(
      old.dni, old.fecha_inicio, old.fecha_fin
    );
  end if;
  if tg_op in ('INSERT','UPDATE') then
    perform public.appgt_aplicar_permisos_planilla_rango_v1(
      new.dni, new.fecha_inicio, new.fecha_fin
    );
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;

drop trigger if exists appgt_gh_permisos_refrescar_planilla_trigger
  on public."GH_PERMISOS_LICENCIAS_APPGT";
create trigger appgt_gh_permisos_refrescar_planilla_trigger
after insert or update or delete on public."GH_PERMISOS_LICENCIAS_APPGT"
for each row execute function public.appgt_gh_permisos_refrescar_planilla_v1();

create index if not exists gh_permisos_empresa_fechas_idx
  on public."GH_PERMISOS_LICENCIAS_APPGT"
  (empresa_id, fecha_inicio desc, dni)
  where deleted_at is null;

alter table public."GH_PERMISOS_LICENCIAS_APPGT" enable row level security;
drop policy if exists gh_permisos_select
  on public."GH_PERMISOS_LICENCIAS_APPGT";
drop policy if exists gh_permisos_insert
  on public."GH_PERMISOS_LICENCIAS_APPGT";
drop policy if exists gh_permisos_update
  on public."GH_PERMISOS_LICENCIAS_APPGT";
drop policy if exists gh_permisos_delete
  on public."GH_PERMISOS_LICENCIAS_APPGT";
create policy gh_permisos_select
  on public."GH_PERMISOS_LICENCIAS_APPGT" for select to authenticated
  using (
    empresa_id = public.appgt_empresa_actual_id()
    and public.appgt_can_view_table('GH_PERMISOS_LICENCIAS_APPGT')
  );
create policy gh_permisos_insert
  on public."GH_PERMISOS_LICENCIAS_APPGT" for insert to authenticated
  with check (
    empresa_id = public.appgt_empresa_actual_id()
    and public.appgt_can_insert_table('GH_PERMISOS_LICENCIAS_APPGT')
  );
create policy gh_permisos_update
  on public."GH_PERMISOS_LICENCIAS_APPGT" for update to authenticated
  using (
    empresa_id = public.appgt_empresa_actual_id()
    and public.appgt_can_update_table('GH_PERMISOS_LICENCIAS_APPGT')
  )
  with check (
    empresa_id = public.appgt_empresa_actual_id()
    and public.appgt_can_update_table('GH_PERMISOS_LICENCIAS_APPGT')
  );
create policy gh_permisos_delete
  on public."GH_PERMISOS_LICENCIAS_APPGT" for delete to authenticated
  using (
    empresa_id = public.appgt_empresa_actual_id()
    and public.appgt_can_delete_table('GH_PERMISOS_LICENCIAS_APPGT')
  );
grant select, insert, update, delete
  on public."GH_PERMISOS_LICENCIAS_APPGT" to authenticated;
grant all on public."GH_PERMISOS_LICENCIAS_APPGT" to service_role;

-- Corrige la jerarquía creada por las migraciones ERP sin tocar registros de
-- negocio. Cada empresa conserva ids propios y permisos por formato.
do $$
declare
  v_rubro record;
  v_suffix text;
  v_operations text;
  v_finance text;
  v_warehouse text;
  v_human text;
  v_matrices text;
  v_attendance text;
  v_permissions text;
  v_payroll text;
  v_matrix_human text;
  v_permission_format text;
begin
  for v_rubro in
    select r.*
    from public."RUBROS_APPGT" r
    where r.activo and r.deleted_at is null
  loop
    v_suffix := substr(md5(v_rubro.empresa_id::text), 1, 10);
    v_operations := 'erp_operaciones_' || v_suffix;
    v_finance := 'erp_finanzas_' || v_suffix;
    v_warehouse := 'erp_almacen_' || v_suffix;
    v_human := 'erp_gestion_humana_' || v_suffix;
    v_attendance := 'gh_asistencia_tareo_' || v_suffix;
    v_permissions := 'gh_permisos_licencias_' || v_suffix;
    v_payroll := 'gh_planilla_' || v_suffix;
    v_matrix_human := 'matrices_gestion_humana_' || v_suffix;
    v_permission_format := 'gh_permiso_licencia_' || v_suffix;

    insert into public."MATRIZ_SECCIONES_APPGT" (
      id, empresa_id, nombre, icono, color, orden, activo, rubro_id,
      tipo_contenido, ruta_flutter
    ) values
      (v_operations, v_rubro.empresa_id, 'OPERACIONES',
       'precision_manufacturing', '#176B87', 10, true, v_rubro.id,
       'FORMATOS', null),
      (v_finance, v_rubro.empresa_id, 'FINANZAS',
       'payments', '#3957A5', 20, true, v_rubro.id, 'FORMATOS', null),
      (v_warehouse, v_rubro.empresa_id, 'ALMACENES E INVENTARIOS',
       'warehouse', '#A0621A', 30, true, v_rubro.id, 'FORMATOS', null),
      (v_human, v_rubro.empresa_id, 'GESTIÓN HUMANA',
       'groups', '#A33E5C', 60, true, v_rubro.id, 'FORMATOS', null)
    on conflict (id) do update set
      nombre = excluded.nombre,
      icono = excluded.icono,
      color = excluded.color,
      orden = excluded.orden,
      activo = true,
      rubro_id = excluded.rubro_id,
      tipo_contenido = 'FORMATOS',
      deleted_at = null,
      eliminado = false,
      updated_at = now();

    select s.id into v_matrices
    from public."MATRIZ_SECCIONES_APPGT" s
    where s.empresa_id = v_rubro.empresa_id
      and (
        s.rubro_id is not distinct from v_rubro.id
        or s.rubro_id is null
      )
      and public.appgt_normalizar_clave(s.nombre) = 'MATRICES'
    order by s.activo desc, s.orden, s.id
    limit 1;

    if v_matrices is null then
      v_matrices := 'erp_matrices_' || v_suffix;
      insert into public."MATRIZ_SECCIONES_APPGT" (
        id, empresa_id, nombre, icono, color, orden, activo, rubro_id,
        tipo_contenido, ruta_flutter
      ) values (
        v_matrices, v_rubro.empresa_id, 'MATRICES', 'grid_view',
        '#4F6575', 55, true, v_rubro.id, 'FORMATOS', null
      )
      on conflict (id) do update set
        nombre = 'MATRICES', icono = 'grid_view', activo = true,
        rubro_id = excluded.rubro_id, deleted_at = null,
        eliminado = false, updated_at = now();
    else
      update public."MATRIZ_SECCIONES_APPGT"
      set nombre = 'MATRICES', icono = 'grid_view', activo = true,
          rubro_id = v_rubro.id, deleted_at = null,
          eliminado = false, updated_at = now()
      where id = v_matrices and empresa_id = v_rubro.empresa_id;
    end if;

    -- Todo módulo que aún estaba en el contenedor Formatos vuelve a Operaciones.
    update public."MATRIZ_MODULOS_APPGT" m
    set seccion = v_operations, updated_at = now()
    where m.empresa_id = v_rubro.empresa_id
      and m.rubro_id is not distinct from v_rubro.id
      and exists (
        select 1 from public."MATRIZ_SECCIONES_APPGT" s
        where s.empresa_id = m.empresa_id and s.id = m.seccion
          and public.appgt_normalizar_clave(s.nombre) in ('FORMATO','FORMATOS')
      );

    -- Los catálogos generales (labores, lotes y supervisores) son matrices.
    update public."MATRIZ_MODULOS_APPGT" m
    set seccion = v_matrices, updated_at = now()
    where m.empresa_id = v_rubro.empresa_id
      and m.rubro_id is not distinct from v_rubro.id
      and public.appgt_normalizar_clave(m.nombre) = 'GENERAL'
      and exists (
        select 1 from public."MATRIZ_FORMATOS_APPGT" f
        where f.empresa_id = m.empresa_id and f.modulo_id = m.id
          and public.appgt_normalizar_clave(
            coalesce(f.nombre, '') || ' ' || coalesce(f.tabla_destino, '')
          ) ~ 'LABOR|LOTE|SUPERVISOR'
      );

    -- El ALMACEN heredado registra supervisión de labores; el módulo ERP de
    -- inventario permanece en ALMACENES E INVENTARIOS.
    update public."MATRIZ_MODULOS_APPGT" m
    set seccion = v_operations, updated_at = now()
    where m.empresa_id = v_rubro.empresa_id
      and m.rubro_id is not distinct from v_rubro.id
      and m.id not like 'erp\_%' escape '\'
      and public.appgt_normalizar_clave(m.nombre) = 'ALMACEN';

    insert into public."MATRIZ_MODULOS_APPGT" (
      id, empresa_id, nombre, seccion, orden, activo, rubro_id, icono, color
    ) values
      (v_attendance, v_rubro.empresa_id, 'asistencia y tareo', v_human,
       10, true, v_rubro.id, 'schedule', '#A33E5C'),
      (v_permissions, v_rubro.empresa_id, 'permisos/licencias', v_human,
       20, true, v_rubro.id, 'health_and_safety', '#A33E5C'),
      (v_payroll, v_rubro.empresa_id, 'planilla', v_human,
       30, true, v_rubro.id, 'payments', '#A33E5C'),
      (v_matrix_human, v_rubro.empresa_id, 'gestión humana', v_matrices,
       20, true, v_rubro.id, 'people', '#6A5B82')
    on conflict (id) do update set
      nombre = excluded.nombre,
      seccion = excluded.seccion,
      orden = excluded.orden,
      activo = true,
      rubro_id = excluded.rubro_id,
      icono = excluded.icono,
      color = excluded.color,
      deleted_at = null,
      eliminado = false,
      updated_at = now();

    update public."MATRIZ_FORMATOS_APPGT" f
    set modulo_id = v_attendance, rubro_id = v_rubro.id, updated_at = now()
    where f.empresa_id = v_rubro.empresa_id
      and upper(coalesce(f.tabla_destino, '')) in (
        'GT-ASISTENCIA_PERSONAL','GT-TAREO_PERSONAL'
      )
      and coalesce(f.activo, true) and not coalesce(f.eliminado, false);

    update public."MATRIZ_FORMATOS_APPGT" f
    set modulo_id = v_payroll, rubro_id = v_rubro.id, updated_at = now()
    where f.empresa_id = v_rubro.empresa_id
      and upper(coalesce(f.tabla_destino, '')) in (
        'PLANILLA_TRABAJADORES_ZUMAC','MATRIZ_BENEFICIOS_SOCIALES',
        'GH-REGISTRO_PERSONAL_PLANILLA'
      )
      and coalesce(f.activo, true) and not coalesce(f.eliminado, false);

    -- Un solo formato reemplaza las ausencias/licencias antiguas en el menú.
    update public."MATRIZ_FORMATOS_APPGT" f
    set activo = false, eliminado = true,
        deleted_at = coalesce(f.deleted_at, now()), updated_at = now()
    where f.empresa_id = v_rubro.empresa_id
      and f.id <> v_permission_format
      and public.appgt_normalizar_clave(
        coalesce(f.nombre, '') || ' ' || coalesce(f.tabla_destino, '')
      ) ~ 'AUSENCIA|PERMISO|LICENCIA'
      and f.modulo_id in (
        select m.id from public."MATRIZ_MODULOS_APPGT" m
        where m.empresa_id = v_rubro.empresa_id and m.seccion = v_human
      );

    -- Movilidad, reclutadores, calendario y cualquier catálogo humano restante
    -- vuelven a MATRICES / gestión humana.
    update public."MATRIZ_FORMATOS_APPGT" f
    set modulo_id = v_matrix_human, rubro_id = v_rubro.id, updated_at = now()
    where f.empresa_id = v_rubro.empresa_id
      and coalesce(f.activo, true) and not coalesce(f.eliminado, false)
      and f.modulo_id in (
        select m.id from public."MATRIZ_MODULOS_APPGT" m
        where m.empresa_id = v_rubro.empresa_id and m.seccion = v_human
          and m.id not in (v_attendance, v_permissions, v_payroll)
      );

    insert into public."MATRIZ_FORMATOS_APPGT" (
      id, empresa_id, modulo_id, nombre, tabla_destino, ruta_flutter,
      tabla_visible_app, orden, activo, rubro_id, auditable, icono,
      capacidades, created_at, updated_at, deleted_at, estado_sync, eliminado
    ) values (
      v_permission_format, v_rubro.empresa_id, v_permissions,
      'Permisos y Licencias', 'GH_PERMISOS_LICENCIAS_APPGT', null,
      true, 10, true, v_rubro.id, true, 'health_and_safety',
      '{"firma":true}'::jsonb, now(), now(), null, 'sincronizado', false
    )
    on conflict (id) do update set
      empresa_id = excluded.empresa_id,
      modulo_id = excluded.modulo_id,
      nombre = excluded.nombre,
      tabla_destino = excluded.tabla_destino,
      tabla_visible_app = true,
      orden = excluded.orden,
      activo = true,
      rubro_id = excluded.rubro_id,
      auditable = true,
      icono = excluded.icono,
      capacidades = excluded.capacidades,
      deleted_at = null,
      eliminado = false,
      updated_at = now();

    insert into public."MATRIZ_FORMATO_TABLAS_APPGT" (
      id, empresa_id, formato_id, nombre, tabla_destino, orden, activo,
      rubro_id, auditable, icono, created_at, updated_at, deleted_at
    ) values (
      v_permission_format || '_table', v_rubro.empresa_id,
      v_permission_format, 'Solicitud', 'GH_PERMISOS_LICENCIAS_APPGT',
      0, true, v_rubro.id, true, 'health_and_safety',
      now(), now(), null
    )
    on conflict (id) do update set
      empresa_id = excluded.empresa_id,
      formato_id = excluded.formato_id,
      nombre = excluded.nombre,
      tabla_destino = excluded.tabla_destino,
      activo = true,
      rubro_id = excluded.rubro_id,
      auditable = true,
      icono = excluded.icono,
      deleted_at = null,
      updated_at = now();

    -- Los módulos humanos heredados ya quedaron vacíos y no deben duplicarse.
    update public."MATRIZ_MODULOS_APPGT" m
    set activo = false, updated_at = now()
    where m.empresa_id = v_rubro.empresa_id and m.seccion = v_human
      and m.id not in (v_attendance, v_permissions, v_payroll)
      and not exists (
        select 1 from public."MATRIZ_FORMATOS_APPGT" f
        where f.empresa_id = m.empresa_id and f.modulo_id = m.id
          and coalesce(f.activo, true) and not coalesce(f.eliminado, false)
      );

    -- Producción y Planificación ERP se retira de esta navegación; sus tablas y
    -- registros permanecen intactos para una ubicación funcional posterior.
    update public."MATRIZ_MODULOS_APPGT"
    set activo = false, updated_at = now()
    where empresa_id = v_rubro.empresa_id
      and id = 'erp_produccion_planificacion_' || v_suffix;

    -- El contenedor Formatos queda obsoleto después de mover sus módulos.
    update public."MATRIZ_SECCIONES_APPGT" s
    set activo = false, eliminado = true,
        deleted_at = coalesce(s.deleted_at, now()), updated_at = now()
    where s.empresa_id = v_rubro.empresa_id
      and s.id not in (v_operations, v_finance, v_warehouse, v_human, v_matrices)
      and public.appgt_normalizar_clave(s.nombre) in ('FORMATO','FORMATOS');
  end loop;
end
$$;

-- Definición dinámica del formato laboral.
insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id, tabla_destino, campo, etiqueta, tipo, tipo_ui, id_campo_dropdown,
  requerido, visible, visible_tabla, editable, orden, activo,
  created_at, updated_at, estado_sync, eliminado
) values
  ('gh_perm_numero','GH_PERMISOS_LICENCIAS_APPGT','numero_solicitud',
   'Número de solicitud','hidden_id','hidden_id',null,true,false,true,false,1,true,now(),now(),'sincronizado',false),
  ('gh_perm_fecha','GH_PERMISOS_LICENCIAS_APPGT','fecha_solicitud',
   'Fecha de solicitud','date','date',null,true,true,true,true,2,true,now(),now(),'sincronizado',false),
  ('gh_perm_dni','GH_PERMISOS_LICENCIAS_APPGT','dni',
   'DNI','text','scanner',null,true,true,true,true,3,true,now(),now(),'sincronizado',false),
  ('gh_perm_trabajador','GH_PERMISOS_LICENCIAS_APPGT','trabajador',
   'Apellidos y nombres','text','text',null,true,true,true,true,4,true,now(),now(),'sincronizado',false),
  ('gh_perm_puesto','GH_PERMISOS_LICENCIAS_APPGT','puesto',
   'Puesto','text','text',null,false,true,true,true,5,true,now(),now(),'sincronizado',false),
  ('gh_perm_area','GH_PERMISOS_LICENCIAS_APPGT','area',
   'Área','text','text',null,false,true,true,true,6,true,now(),now(),'sincronizado',false),
  ('gh_perm_tipo','GH_PERMISOS_LICENCIAS_APPGT','tipo_permiso',
   'Tipo de permiso o licencia','text','dropdown',
   '[DESCANSO MEDICO;LICENCIA DE MATERNIDAD;PERMISO SIN GOCE;COMISION DE SERVICIO;LICENCIA DE PATERNIDAD;LICENCIA POR FALLECIMIENTO;VACACIONES;OTRO]',
   true,true,true,true,7,true,now(),now(),'sincronizado',false),
  ('gh_perm_inicio','GH_PERMISOS_LICENCIAS_APPGT','fecha_inicio',
   'Fecha de inicio','date','date',null,true,true,true,true,8,true,now(),now(),'sincronizado',false),
  ('gh_perm_fin','GH_PERMISOS_LICENCIAS_APPGT','fecha_fin',
   'Fecha de fin','date','date',null,true,true,true,true,9,true,now(),now(),'sincronizado',false),
  ('gh_perm_hora_inicio','GH_PERMISOS_LICENCIAS_APPGT','hora_inicio',
   'Hora de inicio','time','time',null,false,true,true,true,10,true,now(),now(),'sincronizado',false),
  ('gh_perm_hora_fin','GH_PERMISOS_LICENCIAS_APPGT','hora_fin',
   'Hora de fin','time','time',null,false,true,true,true,11,true,now(),now(),'sincronizado',false),
  ('gh_perm_dias','GH_PERMISOS_LICENCIAS_APPGT','dias_solicitados',
   'Días solicitados','integer','number',null,false,false,true,false,12,true,now(),now(),'sincronizado',false),
  ('gh_perm_goce','GH_PERMISOS_LICENCIAS_APPGT','con_goce_haber',
   'Con goce de haber','boolean','switch',null,false,true,true,true,13,true,now(),now(),'sincronizado',false),
  ('gh_perm_motivo','GH_PERMISOS_LICENCIAS_APPGT','motivo',
   'Motivo','text','multiline',null,true,true,true,true,14,true,now(),now(),'sincronizado',false),
  ('gh_perm_observaciones','GH_PERMISOS_LICENCIAS_APPGT','observaciones',
   'Observaciones','text','multiline',null,false,true,true,true,15,true,now(),now(),'sincronizado',false),
  ('gh_perm_sustento','GH_PERMISOS_LICENCIAS_APPGT','documento_sustento',
   'Documento de sustento','text','text',null,false,true,true,true,16,true,now(),now(),'sincronizado',false),
  ('gh_perm_firma','GH_PERMISOS_LICENCIAS_APPGT','firma_trabajador',
   'Firma del trabajador','signature','signature',null,false,true,true,true,17,true,now(),now(),'sincronizado',false),
  ('gh_perm_documento','GH_PERMISOS_LICENCIAS_APPGT','documento_generado',
   'Documento generado','text','readonly',null,false,false,true,false,18,true,now(),now(),'sincronizado',false),
  ('gh_perm_estado','GH_PERMISOS_LICENCIAS_APPGT','estado',
   'Estado','text','readonly',null,false,false,true,false,19,true,now(),now(),'sincronizado',false)
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

insert into public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id, tabla_destino, campo, etiqueta, tipo, tipo_ui,
  requerido, visible, visible_tabla, editable, orden, activo,
  created_at, updated_at, estado_sync, eliminado
) values
  ('planilla_permiso_sin_goce','PLANILLA_TRABAJADORES_ZUMAC',
   'permiso_sin_goce','Permiso sin goce','numeric','number',
   false,true,true,false,23,true,now(),now(),'sincronizado',false),
  ('planilla_vacaciones','PLANILLA_TRABAJADORES_ZUMAC',
   'vacaciones','Vacaciones','numeric','number',
   false,true,true,false,24,true,now(),now(),'sincronizado',false),
  ('planilla_vacaciones_costo','PLANILLA_TRABAJADORES_ZUMAC',
   'vacaciones_costo','Vacaciones costo','numeric','number',
   false,true,true,false,51,true,now(),now(),'sincronizado',false)
on conflict (tabla_destino, campo) do update set
  etiqueta = excluded.etiqueta,
  tipo = excluded.tipo,
  tipo_ui = excluded.tipo_ui,
  visible = true,
  visible_tabla = true,
  editable = false,
  orden = excluded.orden,
  activo = true,
  eliminado = false,
  updated_at = now();

update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set id_generador = 'PL', updated_at = now()
where tabla_destino = 'GH_PERMISOS_LICENCIAS_APPGT'
  and campo = 'numero_solicitud';

-- Sincroniza permisos existentes con el nuevo módulo/sección. Cuando dos
-- módulos históricos terminan en el mismo destino, fusiona sus permisos antes
-- de cambiar la clave para no infringir (user_id, modulo, formato).
create temporary table appgt_permission_retarget
on commit drop
as
select
  p.id permission_id,
  f.modulo_id target_module,
  m.seccion target_section,
  f.tabla_destino target_table,
  first_value(p.id) over (
    partition by p.user_id, f.modulo_id, p.formato
    order by
      case when p.modulo = f.modulo_id then 0 else 1 end,
      case when p.activo and not p.eliminado then 0 else 1 end,
      p.updated_at desc nulls last,
      p.id::text
  ) keeper_id,
  bool_or(p.activo and not p.eliminado) over (
    partition by p.user_id, f.modulo_id, p.formato
  ) merged_active,
  bool_or(p.can_view and p.activo and not p.eliminado) over (
    partition by p.user_id, f.modulo_id, p.formato
  ) merged_can_view,
  bool_or(p.can_insert and p.activo and not p.eliminado) over (
    partition by p.user_id, f.modulo_id, p.formato
  ) merged_can_insert,
  bool_or(p.can_update and p.activo and not p.eliminado) over (
    partition by p.user_id, f.modulo_id, p.formato
  ) merged_can_update,
  bool_or(p.can_delete and p.activo and not p.eliminado) over (
    partition by p.user_id, f.modulo_id, p.formato
  ) merged_can_delete,
  bool_or(p.can_export and p.activo and not p.eliminado) over (
    partition by p.user_id, f.modulo_id, p.formato
  ) merged_can_export,
  bool_or(p.can_import and p.activo and not p.eliminado) over (
    partition by p.user_id, f.modulo_id, p.formato
  ) merged_can_import,
  bool_or(p.can_review and p.activo and not p.eliminado) over (
    partition by p.user_id, f.modulo_id, p.formato
  ) merged_can_review,
  bool_or(p.can_approve and p.activo and not p.eliminado) over (
    partition by p.user_id, f.modulo_id, p.formato
  ) merged_can_approve
from public."PERMISOS_DE_USUARIOS_APPGT" p
join lateral (
  select f0.modulo_id, f0.tabla_destino
  from public."MATRIZ_FORMATOS_APPGT" f0
  where f0.empresa_id = p.empresa_id
    and (p.formato = f0.id or p.tabla_destino = f0.tabla_destino)
    and f0.activo and not f0.eliminado
  order by case when p.formato = f0.id then 0 else 1 end,
           f0.updated_at desc nulls last,
           f0.id
  limit 1
) f on true
join public."MATRIZ_MODULOS_APPGT" m
  on m.empresa_id = p.empresa_id and m.id = f.modulo_id
where p.user_id is not null;

update public."PERMISOS_DE_USUARIOS_APPGT" p
set modulo = t.target_module,
    seccion = t.target_section,
    tabla_destino = t.target_table,
    can_view = t.merged_can_view,
    can_insert = t.merged_can_insert,
    can_update = t.merged_can_update,
    can_delete = t.merged_can_delete,
    can_export = t.merged_can_export,
    can_import = t.merged_can_import,
    can_review = t.merged_can_review,
    can_approve = t.merged_can_approve,
    activo = t.merged_active,
    eliminado = not t.merged_active,
    deleted_at = case when t.merged_active then null else p.deleted_at end,
    estado_sync = 'sincronizado',
    updated_at = now()
from appgt_permission_retarget t
where p.id = t.permission_id and t.permission_id = t.keeper_id;

delete from public."PERMISOS_DE_USUARIOS_APPGT" p
using appgt_permission_retarget t
where p.id = t.permission_id and t.permission_id <> t.keeper_id;

-- Hereda acceso al documento unificado de quienes ya gestionaban RR. HH.; los
-- administradores y gestores mantienen acceso completo.
with human_access as (
  select p.empresa_id, p.user_id,
    bool_or(p.can_view) can_view,
    bool_or(p.can_insert) can_insert,
    bool_or(p.can_update) can_update,
    bool_or(p.can_delete) can_delete,
    bool_or(p.can_export) can_export,
    bool_or(p.can_import) can_import
  from public."PERMISOS_DE_USUARIOS_APPGT" p
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id = p.empresa_id and m.id = p.modulo
  join public."MATRIZ_SECCIONES_APPGT" s
    on s.empresa_id = m.empresa_id and s.id = m.seccion
  where p.user_id is not null and p.activo and not p.eliminado
    and public.appgt_normalizar_clave(s.nombre) = 'GESTIONHUMANA'
  group by p.empresa_id, p.user_id
), admin_access as (
  select ue.empresa_id, ue.user_id,
    true can_view, true can_insert, true can_update, true can_delete,
    true can_export, true can_import
  from public."USUARIOS_EMPRESAS_APPGT" ue
  where ue.activo and ue.rol in ('ADMIN','GESTOR')
), combined as (
  select * from human_access
  union all
  select * from admin_access
), access_by_user as (
  select empresa_id, user_id,
    bool_or(can_view) can_view,
    bool_or(can_insert) can_insert,
    bool_or(can_update) can_update,
    bool_or(can_delete) can_delete,
    bool_or(can_export) can_export,
    bool_or(can_import) can_import
  from combined
  group by empresa_id, user_id
), targets as (
  select f.empresa_id, f.id formato_id, f.tabla_destino,
         f.modulo_id, m.seccion
  from public."MATRIZ_FORMATOS_APPGT" f
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id = f.empresa_id and m.id = f.modulo_id
  where f.tabla_destino = 'GH_PERMISOS_LICENCIAS_APPGT'
    and f.activo and not f.eliminado
)
insert into public."PERMISOS_DE_USUARIOS_APPGT" (
  empresa_id, user_id, seccion, modulo, formato, tabla_destino,
  can_view, can_insert, can_update, can_delete, can_export, can_import,
  activo, created_at, updated_at, estado_sync, eliminado
)
select a.empresa_id, a.user_id, t.seccion, t.modulo_id, t.formato_id,
  t.tabla_destino, a.can_view, a.can_insert, a.can_update, a.can_delete,
  a.can_export, a.can_import, true, now(), now(), 'sincronizado', false
from access_by_user a
join targets t on t.empresa_id = a.empresa_id
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
  eliminado = false,
  updated_at = now();

-- Reactiva permisos de las secciones que ahora contienen formatos visibles.
with needed_sections as (
  select distinct p.empresa_id, p.user_id, m.seccion seccion_id
  from public."PERMISOS_DE_USUARIOS_APPGT" p
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id = p.empresa_id and m.id = p.modulo
  join public."MATRIZ_SECCIONES_APPGT" s
    on s.empresa_id = m.empresa_id and s.id = m.seccion
  where p.activo and not p.eliminado and p.can_view
    and m.activo and not m.eliminado
    and s.activo and not s.eliminado
)
update public."PERMISOS_SECCIONES_APPGT" p
set seccion = n.seccion_id,
    seccion_id = n.seccion_id,
    can_view = true,
    activo = true,
    eliminado = false,
    updated_at = now()
from needed_sections n
where p.empresa_id = n.empresa_id and p.user_id = n.user_id
  and coalesce(nullif(btrim(p.seccion), ''), btrim(p.seccion_id)) = n.seccion_id;

with needed_sections as (
  select distinct p.empresa_id, p.user_id, m.seccion seccion_id
  from public."PERMISOS_DE_USUARIOS_APPGT" p
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id = p.empresa_id and m.id = p.modulo
  join public."MATRIZ_SECCIONES_APPGT" s
    on s.empresa_id = m.empresa_id and s.id = m.seccion
  where p.activo and not p.eliminado and p.can_view
    and m.activo and not m.eliminado
    and s.activo and not s.eliminado
)
insert into public."PERMISOS_SECCIONES_APPGT" (
  empresa_id, user_id, seccion, seccion_id,
  can_view, can_insert, can_update, can_delete,
  activo, eliminado, created_at, updated_at
)
select n.empresa_id, n.user_id, n.seccion_id, n.seccion_id,
  true, false, false, false, true, false, now(), now()
from needed_sections n
where not exists (
  select 1 from public."PERMISOS_SECCIONES_APPGT" p
  where p.empresa_id = n.empresa_id and p.user_id = n.user_id
    and coalesce(nullif(btrim(p.seccion), ''), btrim(p.seccion_id)) = n.seccion_id
);

-- Los permisos de secciones retiradas no deben mantener Formatos en el menú.
update public."PERMISOS_SECCIONES_APPGT" p
set can_view = false, activo = false, eliminado = true, updated_at = now()
from public."MATRIZ_SECCIONES_APPGT" s
where s.empresa_id = p.empresa_id
  and coalesce(nullif(btrim(p.seccion), ''), btrim(p.seccion_id)) = s.id
  and (not s.activo or s.eliminado)
  and public.appgt_normalizar_clave(s.nombre) in ('FORMATO','FORMATOS');

-- Convención visual final: secciones en mayúsculas, módulos en minúsculas.
update public."MATRIZ_SECCIONES_APPGT"
set nombre = upper(nombre), updated_at = now()
where activo and not eliminado and nombre is not null;

update public."MATRIZ_MODULOS_APPGT"
set nombre = lower(nombre), updated_at = now()
where activo and not eliminado and nombre is not null;

select public.appgt_instalar_seguimiento_tablas_v1();
notify pgrst, 'reload schema';

commit;
