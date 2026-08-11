begin;

create temporary table appgt_matrix_module_map (
  empresa_id uuid not null,
  rubro_id text not null,
  section_id text not null,
  base_id text not null,
  module_id text not null,
  primary key (empresa_id, base_id)
) on commit drop;

do $$
declare
  v_company record;
  v_module record;
  v_format record;
  v_section_id text;
  v_module_id text;
  v_format_id text;
  v_suffix text;
begin
  for v_company in
    select r.empresa_id, r.id as rubro_id
    from public."RUBROS_APPGT" r
    where coalesce(r.activo, true) and r.deleted_at is null
  loop
    select s.id into v_section_id
    from public."MATRIZ_SECCIONES_APPGT" s
    where s.empresa_id = v_company.empresa_id
      and public.appgt_normalizar_clave(s.nombre) = 'MATRICES'
      and coalesce(s.activo, true) and s.deleted_at is null
    order by case when s.rubro_id is not distinct from v_company.rubro_id then 0 else 1 end,
             s.orden, s.id
    limit 1;
    if v_section_id is null then
      continue;
    end if;
    v_suffix := substr(md5(v_company.empresa_id::text), 1, 10);

    for v_module in
      select * from (values
        ('matrices_fenologia_zumac', 'fenología', 10, 'eco'),
        ('matrices_maquinaria_zumac', 'maquinaria', 20, 'agriculture'),
        ('matrices_proyeccion_zumac', 'proyección', 30, 'trending_up'),
        ('matrices_sanidad_zumac', 'sanidad', 40, 'pest_control'),
        ('matrices_sst_zumac', 'sst', 50, 'health_and_safety'),
        ('matrices_transporte_zumac', 'transporte', 60, 'local_shipping'),
        ('matriz_mantenimiento', 'mantenimiento', 70, 'build'),
        ('matrices_general_zumac', 'general', 80, 'dataset'),
        ('matrices_gestion_humana_zumac', 'gestión humana', 90, 'people')
      ) as desired(base_id, name, sort_order, icon_name)
    loop
      select m.id into v_module_id
      from public."MATRIZ_MODULOS_APPGT" m
      where m.empresa_id = v_company.empresa_id
        and (
          m.id = v_module.base_id
          or m.id like v_module.base_id || '\_%' escape '\'
          or (
            m.seccion = v_section_id
            and public.appgt_normalizar_clave(m.nombre) =
                public.appgt_normalizar_clave(v_module.name)
          )
        )
      order by case when m.id = v_module.base_id then 0 else 1 end,
               m.activo desc, m.id
      limit 1;

      if v_module_id is null then
        if not exists (
          select 1 from public."MATRIZ_MODULOS_APPGT" m
          where m.id = v_module.base_id
        ) then
          v_module_id := v_module.base_id;
        else
          v_module_id := v_module.base_id || '_' || v_suffix;
        end if;
      end if;

      insert into public."MATRIZ_MODULOS_APPGT" (
        id, empresa_id, nombre, seccion, orden, activo, rubro_id, icono, color
      ) values (
        v_module_id, v_company.empresa_id, v_module.name, v_section_id,
        v_module.sort_order, true, v_company.rubro_id,
        v_module.icon_name, '#4F6575'
      )
      on conflict (id) do update set
        nombre = excluded.nombre, seccion = excluded.seccion,
        orden = excluded.orden, activo = true, rubro_id = excluded.rubro_id,
        icono = excluded.icono, color = excluded.color,
        deleted_at = null, eliminado = false, updated_at = now();

      insert into appgt_matrix_module_map(
        empresa_id, rubro_id, section_id, base_id, module_id
      ) values (
        v_company.empresa_id, v_company.rubro_id, v_section_id,
        v_module.base_id, v_module_id
      );
    end loop;

    for v_format in
      select * from (values
        ('matrices_fenologia_zumac','SN-MATRIZ_ETAPAS_FENOLOGICAS','Etapas fenológicas',10),
        ('matrices_maquinaria_zumac','MQ-MATRIZ_IMPLEMENTOS','Implementos',10),
        ('matrices_maquinaria_zumac','MQ-MATRIZ_MAQUINARIAS','Maquinarias',20),
        ('matrices_proyeccion_zumac','SN-MATRIZ_ESTADIOS_CONTEO_FRUTA','Estadios de conteo de fruta',10),
        ('matrices_sanidad_zumac','MATRIZ_ESTACIONES_DE_ROEDORES','Estaciones de roedores',10),
        ('matrices_sanidad_zumac','MATRIZ_OPERADORES_SANIDAD_MAQUINARIA','Operadores de sanidad y maquinaria',20),
        ('matrices_sanidad_zumac','SN-MATRIZ_CONCEPTOS_ESTADIOS_PLAGAS','Conceptos y estadios de plagas',30),
        ('matrices_sst_zumac','MATRIZ_EPPS','EPPs',10),
        ('matriz_mantenimiento','MATRIZ_EQUIPOS_DE_MEDICION','Equipos de medición',10),
        ('matriz_mantenimiento','MATRIZ_MATERIALES_CALIBRACION_EQUIPOS_DE_MEDICION','Materiales para calibración de equipos de medición',20),
        ('matriz_mantenimiento','MATRIZ_MATERIALES_PARA_LIMPIEZA_AMBIENTES','Materiales para limpieza de ambientes',30),
        ('matrices_general_zumac','MATRIZ_FRECUENCIA_DE_ACTIVIDADES','Frecuencia de actividades',10),
        ('matrices_general_zumac','MATRIZ_JEFATURAS','Jefaturas',20),
        ('matrices_gestion_humana_zumac','MATRIZ-PHOTOCHEK','Photocheck',10)
      ) as desired(base_module, table_name, display_name, sort_order)
    loop
      select map.module_id into v_module_id
      from appgt_matrix_module_map map
      where map.empresa_id = v_company.empresa_id
        and map.base_id = v_format.base_module;

      select f.id into v_format_id
      from public."MATRIZ_FORMATOS_APPGT" f
      where f.empresa_id = v_company.empresa_id
        and upper(coalesce(f.tabla_destino, '')) = upper(v_format.table_name)
      order by f.activo desc, f.updated_at desc nulls last, f.id
      limit 1;

      if v_format_id is null then
        v_format_id := 'matrix_' || substr(
          md5(v_company.empresa_id::text || '|' || v_format.table_name), 1, 24
        );
      end if;

      insert into public."MATRIZ_FORMATOS_APPGT" (
        id, empresa_id, modulo_id, nombre, tabla_destino, ruta_flutter,
        tabla_visible_app, orden, activo, rubro_id, auditable, icono,
        capacidades, created_at, updated_at, deleted_at, estado_sync, eliminado
      ) values (
        v_format_id, v_company.empresa_id, v_module_id, v_format.display_name,
        v_format.table_name, null, true, v_format.sort_order, true,
        v_company.rubro_id, true, 'table_view',
        '{"importar":true,"exportar":true}'::jsonb,
        now(), now(), null, 'sincronizado', false
      )
      on conflict (id) do update set
        empresa_id = excluded.empresa_id, modulo_id = excluded.modulo_id,
        nombre = excluded.nombre, tabla_destino = excluded.tabla_destino,
        tabla_visible_app = true, orden = excluded.orden, activo = true,
        rubro_id = excluded.rubro_id, auditable = true, icono = excluded.icono,
        capacidades = coalesce(public."MATRIZ_FORMATOS_APPGT".capacidades, '{}'::jsonb)
          || excluded.capacidades,
        deleted_at = null, eliminado = false, updated_at = now();

      insert into public."MATRIZ_FORMATO_TABLAS_APPGT" (
        id, empresa_id, formato_id, nombre, tabla_destino, orden, activo,
        rubro_id, auditable, icono, created_at, updated_at, deleted_at
      )
      select
        'matrix_table_' || substr(md5(v_company.empresa_id::text || '|' || v_format.table_name), 1, 22),
        v_company.empresa_id, v_format_id, v_format.display_name,
        v_format.table_name, 0, true, v_company.rubro_id, true,
        'table_view', now(), now(), null
      where not exists (
        select 1 from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
        where ft.empresa_id = v_company.empresa_id
          and ft.formato_id = v_format_id
          and upper(ft.tabla_destino) = upper(v_format.table_name)
      );
    end loop;
  end loop;
end
$$;

-- Movimientos solicitados dentro de MATRICES.
update public."MATRIZ_FORMATOS_APPGT" f
set modulo_id = map.module_id, rubro_id = map.rubro_id,
    activo = true, eliminado = false, deleted_at = null, updated_at = now()
from appgt_matrix_module_map map
where f.empresa_id = map.empresa_id
  and (
    (upper(f.tabla_destino) = 'GT-MATRIZ_MOVILIDADES'
      and map.base_id = 'matrices_transporte_zumac')
    or (upper(f.tabla_destino) = 'MATRIZ_TURNOS_APPGT'
      and map.base_id = 'matrices_general_zumac')
    or (upper(f.tabla_destino) = 'MATRIZ_EVALUADORES_FITOSANIDAD_FENOLOGIA'
      and map.base_id = 'matrices_sanidad_zumac')
    or (upper(f.tabla_destino) = 'MATRIZ-PHOTOCHEK'
      and map.base_id = 'matrices_gestion_humana_zumac')
  );

-- Asistencia de Personal es un registro de Gestión Humana, no una matriz.
update public."MATRIZ_FORMATOS_APPGT" f
set modulo_id = target.id, rubro_id = target.rubro_id,
    activo = true, eliminado = false, deleted_at = null, updated_at = now()
from lateral (
  select m.id, m.empresa_id, m.rubro_id
  from public."MATRIZ_MODULOS_APPGT" m
  join public."MATRIZ_SECCIONES_APPGT" s
    on s.empresa_id = m.empresa_id and s.id = m.seccion
  where public.appgt_normalizar_clave(m.nombre) = 'ASISTENCIA Y TAREO'
    and public.appgt_normalizar_clave(s.nombre) = 'GESTION HUMANA'
    and m.activo and s.activo
) target
where f.empresa_id = target.empresa_id
  and (
    upper(coalesce(f.tabla_destino, '')) = 'GT-ASISTENCIA_PERSONAL'
    or public.appgt_normalizar_clave(f.nombre) = 'ASISTENCIA DE PERSONAL'
  );

-- Los permisos siguen al formato cuando este cambia de módulo.
with rebuilt as (
  select p.empresa_id, p.user_id, m.seccion, f.modulo_id, f.id formato_id,
         f.tabla_destino,
         bool_or(p.can_view and p.activo and not p.eliminado) can_view,
         bool_or(p.can_insert and p.activo and not p.eliminado) can_insert,
         bool_or(p.can_update and p.activo and not p.eliminado) can_update,
         bool_or(p.can_delete and p.activo and not p.eliminado) can_delete,
         bool_or(p.can_export and p.activo and not p.eliminado) can_export,
         bool_or(p.can_import and p.activo and not p.eliminado) can_import
  from public."PERMISOS_DE_USUARIOS_APPGT" p
  join public."MATRIZ_FORMATOS_APPGT" f
    on f.empresa_id = p.empresa_id
   and (f.id = p.formato or f.tabla_destino = p.tabla_destino)
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id = f.empresa_id and m.id = f.modulo_id
  where f.activo and not f.eliminado
  group by p.empresa_id, p.user_id, m.seccion, f.modulo_id, f.id, f.tabla_destino
), admins as (
  select ue.empresa_id, ue.user_id, map.section_id as seccion,
         f.modulo_id, f.id formato_id, f.tabla_destino,
         true can_view, true can_insert, true can_update, true can_delete,
         true can_export, true can_import
  from public."USUARIOS_EMPRESAS_APPGT" ue
  join appgt_matrix_module_map map on map.empresa_id = ue.empresa_id
  join public."MATRIZ_FORMATOS_APPGT" f
    on f.empresa_id = map.empresa_id and f.modulo_id = map.module_id
  where ue.activo and ue.rol in ('ADMIN','GESTOR')
    and f.activo and not f.eliminado
), combined as (
  select * from rebuilt
  union all
  select * from admins
), merged as (
  select empresa_id, user_id, seccion, modulo_id, formato_id, tabla_destino,
         bool_or(can_view) can_view, bool_or(can_insert) can_insert,
         bool_or(can_update) can_update, bool_or(can_delete) can_delete,
         bool_or(can_export) can_export, bool_or(can_import) can_import
  from combined
  group by empresa_id, user_id, seccion, modulo_id, formato_id, tabla_destino
)
insert into public."PERMISOS_DE_USUARIOS_APPGT" (
  empresa_id, user_id, seccion, modulo, formato, tabla_destino,
  can_view, can_insert, can_update, can_delete, can_export, can_import,
  activo, created_at, updated_at, estado_sync, eliminado
)
select empresa_id, user_id, seccion, modulo_id, formato_id, tabla_destino,
       can_view, can_insert, can_update, can_delete, can_export, can_import,
       true, now(), now(), 'sincronizado', false
from merged
on conflict (user_id, modulo, formato) do update set
  empresa_id = excluded.empresa_id, seccion = excluded.seccion,
  tabla_destino = excluded.tabla_destino,
  can_view = public."PERMISOS_DE_USUARIOS_APPGT".can_view or excluded.can_view,
  can_insert = public."PERMISOS_DE_USUARIOS_APPGT".can_insert or excluded.can_insert,
  can_update = public."PERMISOS_DE_USUARIOS_APPGT".can_update or excluded.can_update,
  can_delete = public."PERMISOS_DE_USUARIOS_APPGT".can_delete or excluded.can_delete,
  can_export = public."PERMISOS_DE_USUARIOS_APPGT".can_export or excluded.can_export,
  can_import = public."PERMISOS_DE_USUARIOS_APPGT".can_import or excluded.can_import,
  activo = true, eliminado = false, deleted_at = null, updated_at = now();

delete from public."PERMISOS_DE_USUARIOS_APPGT" p
using public."MATRIZ_FORMATOS_APPGT" f
where p.empresa_id = f.empresa_id
  and p.formato = f.id
  and p.modulo is distinct from f.modulo_id;

with needed as (
  select distinct p.empresa_id, p.user_id, m.seccion
  from public."PERMISOS_DE_USUARIOS_APPGT" p
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id = p.empresa_id and m.id = p.modulo
  where p.activo and not p.eliminado and p.can_view
)
insert into public."PERMISOS_SECCIONES_APPGT" (
  empresa_id, user_id, seccion, seccion_id, can_view,
  can_insert, can_update, can_delete, activo, eliminado, created_at, updated_at
)
select empresa_id, user_id, seccion, seccion, true,
       false, false, false, true, false, now(), now()
from needed n
where not exists (
  select 1 from public."PERMISOS_SECCIONES_APPGT" p
  where p.empresa_id = n.empresa_id and p.user_id = n.user_id
    and coalesce(nullif(btrim(p.seccion), ''), btrim(p.seccion_id)) = n.seccion
);

create or replace function public.appgt_sincronizar_creator_desde_canonico_v2()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_matrix record;
  v_count integer;
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'Sin permiso' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_empresa_id::text, 923));

  insert into public."PAQUETES_PLANTILLA_APPGT" (
    id, empresa_id, rubro_id, codigo, nombre, descripcion, origen,
    tipo_plantilla, version, estado, editable, metadata, published_at
  )
  select md5('PAQUETE_BASE|' || r.empresa_id::text || '|' || r.id)::uuid,
         r.empresa_id, r.id,
         'BASE_' || upper(regexp_replace(r.codigo, '[^A-Za-z0-9]+', '_', 'g')),
         'Plantilla base ' || r.nombre,
         'Vista viva de la configuración productiva.', 'SISTEMA',
         'BASE_RUBRO', 1, 'PUBLICADO', false,
         jsonb_build_object('fuente', 'CONFIGURACION_PRODUCTIVA_VIVA'), now()
  from public."RUBROS_APPGT" r
  where r.empresa_id = v_empresa_id and r.activo and r.deleted_at is null
  on conflict (id) do update set
    codigo = excluded.codigo, nombre = excluded.nombre,
    estado = 'PUBLICADO', deleted_at = null, updated_at = now();

  drop table if exists pg_temp.appgt_creator_sources;
  create temporary table appgt_creator_sources (
    empresa_id uuid, rubro_id text, entidad_tipo text,
    entidad_origen_id text, padre_tipo text, padre_origen_id text,
    codigo text, nombre text, descripcion text, definicion jsonb,
    dependencias jsonb default '[]'::jsonb,
    primary key (empresa_id, entidad_tipo, entidad_origen_id)
  ) on commit drop;

  insert into appgt_creator_sources
  select r.empresa_id, r.id, 'RUBRO', r.id, null, null,
         coalesce(nullif(r.codigo, ''), r.id), r.nombre, r.descripcion,
         to_jsonb(r), '[]'::jsonb
  from public."RUBROS_APPGT" r
  where r.empresa_id = v_empresa_id and r.activo and r.deleted_at is null;

  insert into appgt_creator_sources
  select s.empresa_id, s.rubro_id, 'SECCION', s.id, 'RUBRO', s.rubro_id,
         s.id, s.nombre, null, to_jsonb(s), '[]'::jsonb
  from public."MATRIZ_SECCIONES_APPGT" s
  where s.empresa_id = v_empresa_id and s.activo and s.deleted_at is null;

  insert into appgt_creator_sources
  select m.empresa_id, coalesce(m.rubro_id, s.rubro_id), 'MODULO', m.id,
         'SECCION', m.seccion, m.id, m.nombre, null, to_jsonb(m), '[]'::jsonb
  from public."MATRIZ_MODULOS_APPGT" m
  join public."MATRIZ_SECCIONES_APPGT" s
    on s.empresa_id = m.empresa_id and s.id = m.seccion
  where m.empresa_id = v_empresa_id and m.activo and m.deleted_at is null;

  insert into appgt_creator_sources
  select f.empresa_id, coalesce(f.rubro_id, m.rubro_id, s.rubro_id),
         'FORMATO', f.id, 'MODULO', f.modulo_id, f.id, f.nombre, null,
         to_jsonb(f), '[]'::jsonb
  from public."MATRIZ_FORMATOS_APPGT" f
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id = f.empresa_id and m.id = f.modulo_id
  join public."MATRIZ_SECCIONES_APPGT" s
    on s.empresa_id = m.empresa_id and s.id = m.seccion
  where f.empresa_id = v_empresa_id and f.activo and f.deleted_at is null;

  insert into appgt_creator_sources
  select t.empresa_id, coalesce(t.rubro_id, f.rubro_id, m.rubro_id, s.rubro_id),
         'TABLA', t.id, 'FORMATO', t.formato_id, t.id, t.nombre, null,
         to_jsonb(t), '[]'::jsonb
  from public."MATRIZ_FORMATO_TABLAS_APPGT" t
  join public."MATRIZ_FORMATOS_APPGT" f
    on f.empresa_id = t.empresa_id and f.id = t.formato_id
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id = f.empresa_id and m.id = f.modulo_id
  join public."MATRIZ_SECCIONES_APPGT" s
    on s.empresa_id = m.empresa_id and s.id = m.seccion
  where t.empresa_id = v_empresa_id and t.activo and t.deleted_at is null;

  insert into appgt_creator_sources
  select c.empresa_id, r.id, 'CAMPO', c.id, 'TABLA',
         coalesce(t.id, c.tabla_destino), c.id,
         coalesce(nullif(c.etiqueta, ''), c.campo), null, to_jsonb(c),
         jsonb_build_array(jsonb_build_object('tabla_destino', c.tabla_destino))
  from public."MATRIZ_CAMPOS_FORMATO_APPGT" c
  join lateral (
    select id from public."RUBROS_APPGT" r0
    where r0.empresa_id = c.empresa_id and r0.activo and r0.deleted_at is null
    order by r0.orden, r0.id limit 1
  ) r on true
  left join lateral (
    select t0.id from public."MATRIZ_FORMATO_TABLAS_APPGT" t0
    where t0.empresa_id = c.empresa_id
      and t0.tabla_destino = c.tabla_destino and t0.activo
      and t0.deleted_at is null
    order by t0.orden, t0.id limit 1
  ) t on true
  where c.empresa_id = v_empresa_id and c.activo and c.deleted_at is null;

  for v_matrix in
    select * from (values
      ('MATRIZ_DROPDOWNS_APPGT','DROPDOWNS'),
      ('MATRIZ_VALIDACIONES_APPGT','VALIDACIONES'),
      ('MATRIZ_CONDICIONES_APPGT','CONDICIONES'),
      ('MATRIZ_FORMULAS_APPGT','FORMULAS')
    ) as matrix_source(table_name, class_name)
  loop
    execute format($sql$
      insert into appgt_creator_sources
      select x.empresa_id, r.id, 'MATRIZ', %1$L || ':' || x.id,
             case when nullif(to_jsonb(x)->>'campo_id', '') is null
                  then null else 'CAMPO' end,
             nullif(to_jsonb(x)->>'campo_id', ''),
             coalesce(nullif(to_jsonb(x)->>'codigo', ''), x.id),
             %2$L || ' - ' || coalesce(nullif(to_jsonb(x)->>'codigo', ''), x.id),
             null, to_jsonb(x) || jsonb_build_object('clase_matriz', %2$L),
             '[]'::jsonb
      from public.%3$I x
      join lateral (
        select id from public."RUBROS_APPGT" r0
        where r0.empresa_id = x.empresa_id and r0.activo
          and r0.deleted_at is null
        order by r0.orden, r0.id limit 1
      ) r on true
      where x.empresa_id = $1
        and coalesce((to_jsonb(x)->>'activo')::boolean, true)
        and nullif(to_jsonb(x)->>'deleted_at', '') is null
      on conflict (empresa_id, entidad_tipo, entidad_origen_id) do update set
        padre_tipo = excluded.padre_tipo,
        padre_origen_id = excluded.padre_origen_id,
        codigo = excluded.codigo, nombre = excluded.nombre,
        definicion = excluded.definicion
    $sql$, v_matrix.table_name, v_matrix.class_name, v_matrix.table_name)
    using v_empresa_id;
  end loop;

  update public."PLANTILLAS_CONFIGURACION_APPGT" p
  set paquete_id = md5('PAQUETE_BASE|' || s.empresa_id::text || '|' || s.rubro_id)::uuid,
      rubro_id = s.rubro_id, padre_tipo = s.padre_tipo,
      padre_origen_id = s.padre_origen_id, codigo = s.codigo,
      nombre = s.nombre, descripcion = s.descripcion,
      definicion = s.definicion, dependencias = s.dependencias,
      estado = 'PUBLICADO', activo = true, deleted_at = null,
      published_at = coalesce(p.published_at, now()), updated_at = now()
  from appgt_creator_sources s
  where p.empresa_id = s.empresa_id and p.entidad_tipo = s.entidad_tipo
    and p.entidad_origen_id = s.entidad_origen_id and p.es_actual;

  update public."PLANTILLAS_CONFIGURACION_APPGT" p
  set activo = false, deleted_at = coalesce(p.deleted_at, now()), updated_at = now()
  where p.empresa_id = v_empresa_id and p.es_actual
    and p.entidad_tipo in ('RUBRO','SECCION','MODULO','FORMATO','TABLA','CAMPO','MATRIZ')
    and not exists (
      select 1 from appgt_creator_sources s
      where s.empresa_id = p.empresa_id and s.entidad_tipo = p.entidad_tipo
        and s.entidad_origen_id = p.entidad_origen_id
    );

  insert into public."PLANTILLAS_CONFIGURACION_APPGT" (
    id, empresa_id, paquete_id, rubro_id, entidad_tipo, entidad_origen_id,
    padre_tipo, padre_origen_id, codigo, nombre, descripcion, origen,
    tipo_plantilla, definicion, dependencias, editable, version, estado,
    es_actual, activo, published_at
  )
  select gen_random_uuid(), s.empresa_id,
         md5('PAQUETE_BASE|' || s.empresa_id::text || '|' || s.rubro_id)::uuid,
         s.rubro_id, s.entidad_tipo, s.entidad_origen_id,
         s.padre_tipo, s.padre_origen_id, s.codigo, s.nombre, s.descripcion,
         'SISTEMA', 'BASE_RUBRO', s.definicion, s.dependencias, false,
         coalesce((select max(old.version) + 1
                   from public."PLANTILLAS_CONFIGURACION_APPGT" old
                   where old.empresa_id = s.empresa_id
                     and old.entidad_tipo = s.entidad_tipo
                     and old.entidad_origen_id = s.entidad_origen_id), 1),
         'PUBLICADO', true, true, now()
  from appgt_creator_sources s
  where not exists (
    select 1 from public."PLANTILLAS_CONFIGURACION_APPGT" current_row
    where current_row.empresa_id = s.empresa_id
      and current_row.entidad_tipo = s.entidad_tipo
      and current_row.entidad_origen_id = s.entidad_origen_id
      and current_row.es_actual
  );

  select count(*) into v_count from appgt_creator_sources;
  return jsonb_build_object('sincronizado', true, 'elementos', v_count);
end
$$;

revoke all on function public.appgt_sincronizar_creator_desde_canonico_v2()
  from public, anon;
grant execute on function public.appgt_sincronizar_creator_desde_canonico_v2()
  to authenticated, service_role;

-- Una tabla agregada desde Creator o directamente desde Supabase empieza a
-- participar del delta en la misma transacción en la que se registra.
create or replace function public.appgt_refrescar_seguimiento_catalogo_trigger()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if to_regprocedure('public.appgt_instalar_seguimiento_tablas_v1()') is not null then
    perform public.appgt_instalar_seguimiento_tablas_v1();
  end if;
  return null;
end
$$;

drop trigger if exists appgt_refresh_tracking_after_format
  on public."MATRIZ_FORMATOS_APPGT";
create trigger appgt_refresh_tracking_after_format
after insert or update of tabla_destino, activo
on public."MATRIZ_FORMATOS_APPGT"
for each statement execute function public.appgt_refrescar_seguimiento_catalogo_trigger();

drop trigger if exists appgt_refresh_tracking_after_format_table
  on public."MATRIZ_FORMATO_TABLAS_APPGT";
create trigger appgt_refresh_tracking_after_format_table
after insert or update of tabla_destino, activo
on public."MATRIZ_FORMATO_TABLAS_APPGT"
for each statement execute function public.appgt_refrescar_seguimiento_catalogo_trigger();

do $$
begin
  if to_regprocedure('public.appgt_instalar_seguimiento_tablas_v1()') is not null then
    perform public.appgt_instalar_seguimiento_tablas_v1();
  end if;
end
$$;

notify pgrst, 'reload schema';
commit;
