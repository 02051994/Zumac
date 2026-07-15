begin;

-- El proyecto posee un event trigger heredado que agrega automáticamente a
-- MATRIZ_CAMPOS_FORMATO_APPGT cada columna creada en cualquier tabla pública.
-- Estas tablas son administrativas, no formularios, por lo que se suspende
-- solo dentro de esta transacción. Un error revierte también la suspensión.
do $$
begin
  if exists (
    select 1 from pg_event_trigger
    where evtname = 'trg_appgt_auto_insertar_campos'
  ) then
    execute 'alter event trigger trg_appgt_auto_insertar_campos disable';
  end if;
end
$$;

-- Paquetes inmutables que agrupan una plantilla completa por rubro. Un
-- paquete puede contener secciones, módulos, formatos, tablas, campos y
-- matrices. La configuración publicada continúa en sus tablas actuales.
create table if not exists public."PAQUETES_PLANTILLA_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  rubro_id text not null references public."RUBROS_APPGT"(id),
  codigo text not null,
  nombre text not null,
  descripcion text,
  origen text not null default 'EMPRESA'
    check (origen in ('SISTEMA', 'EMPRESA', 'CLONADA')),
  tipo_plantilla text not null default 'BASE_RUBRO'
    check (tipo_plantilla in ('BASE_RUBRO', 'EMPRESA', 'PERSONALIZADA')),
  version integer not null default 1 check (version > 0),
  estado text not null default 'BORRADOR'
    check (estado in (
      'BORRADOR', 'VALIDANDO', 'VALIDADO', 'PUBLICADO',
      'ARCHIVADO', 'ERROR_PUBLICACION'
    )),
  editable boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (empresa_id, codigo, version)
);

create table if not exists public."PLANTILLAS_CONFIGURACION_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id),
  paquete_id uuid references public."PAQUETES_PLANTILLA_APPGT"(id),
  rubro_id text not null references public."RUBROS_APPGT"(id),
  entidad_tipo text not null
    check (entidad_tipo in (
      'RUBRO', 'SECCION', 'MODULO', 'FORMATO', 'TABLA', 'CAMPO', 'MATRIZ'
    )),
  entidad_origen_id text not null,
  padre_tipo text,
  padre_origen_id text,
  codigo text not null,
  nombre text not null,
  descripcion text,
  origen text not null default 'EMPRESA'
    check (origen in ('SISTEMA', 'EMPRESA', 'CLONADA')),
  tipo_plantilla text not null default 'BASE_RUBRO'
    check (tipo_plantilla in ('BASE_RUBRO', 'EMPRESA', 'PERSONALIZADA')),
  plantilla_origen_id uuid references public."PLANTILLAS_CONFIGURACION_APPGT"(id),
  definicion jsonb not null default '{}'::jsonb,
  dependencias jsonb not null default '[]'::jsonb,
  editable boolean not null default true,
  version integer not null default 1 check (version > 0),
  estado text not null default 'BORRADOR'
    check (estado in (
      'BORRADOR', 'VALIDANDO', 'VALIDADO', 'PUBLICADO',
      'ARCHIVADO', 'ERROR_PUBLICACION'
    )),
  es_actual boolean not null default true,
  activo boolean not null default true,
  created_by uuid references auth.users(id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (empresa_id, entidad_tipo, entidad_origen_id, version)
);

create index if not exists idx_paquetes_plantilla_rubro
  on public."PAQUETES_PLANTILLA_APPGT"
  (empresa_id, rubro_id, estado, version desc);
create index if not exists idx_plantillas_configuracion_arbol
  on public."PLANTILLAS_CONFIGURACION_APPGT"
  (empresa_id, rubro_id, entidad_tipo, padre_origen_id, activo);
create index if not exists idx_plantillas_configuracion_paquete
  on public."PLANTILLAS_CONFIGURACION_APPGT"
  (paquete_id, entidad_tipo, entidad_origen_id);

-- El contenido ya productivo se registra como paquete base inmutable. No se
-- duplica ni se modifica la navegación publicada: se conserva una fotografía
-- JSON que los asistentes podrán clonar a un borrador editable.
insert into public."PAQUETES_PLANTILLA_APPGT" (
  id, empresa_id, rubro_id, codigo, nombre, descripcion, origen,
  tipo_plantilla, version, estado, editable, metadata, published_at
)
select
  md5('PAQUETE_BASE|' || r.empresa_id::text || '|' || r.id)::uuid,
  r.empresa_id,
  r.id,
  'BASE_' || upper(regexp_replace(r.codigo, '[^A-Za-z0-9]+', '_', 'g')),
  'Plantilla base ' || r.nombre,
  'Fotografía versionada de la configuración productiva existente.',
  'SISTEMA',
  'BASE_RUBRO',
  1,
  'PUBLICADO',
  false,
  jsonb_build_object('migracion', '202607150005', 'fuente', 'CONFIGURACION_PRODUCTIVA'),
  now()
from public."RUBROS_APPGT" r
where coalesce(r.activo, true) and r.deleted_at is null
on conflict (empresa_id, codigo, version) do update set
  nombre = excluded.nombre,
  descripcion = excluded.descripcion,
  estado = 'PUBLICADO',
  editable = false,
  metadata = excluded.metadata,
  deleted_at = null,
  updated_at = now();

insert into public."PLANTILLAS_CONFIGURACION_APPGT" (
  id, empresa_id, paquete_id, rubro_id, entidad_tipo, entidad_origen_id,
  codigo, nombre, descripcion, origen, tipo_plantilla, definicion,
  editable, version, estado, published_at
)
select
  md5('RUBRO|' || r.empresa_id::text || '|' || r.id)::uuid,
  r.empresa_id,
  md5('PAQUETE_BASE|' || r.empresa_id::text || '|' || r.id)::uuid,
  r.id,
  'RUBRO',
  r.id,
  coalesce(nullif(r.codigo, ''), r.id),
  r.nombre,
  r.descripcion,
  'SISTEMA',
  'BASE_RUBRO',
  to_jsonb(r),
  false,
  1,
  'PUBLICADO',
  now()
from public."RUBROS_APPGT" r
where coalesce(r.activo, true) and r.deleted_at is null
on conflict (empresa_id, entidad_tipo, entidad_origen_id, version) do update set
  definicion = excluded.definicion,
  nombre = excluded.nombre,
  estado = 'PUBLICADO',
  editable = false,
  es_actual = true,
  activo = true,
  deleted_at = null,
  updated_at = now();

insert into public."PLANTILLAS_CONFIGURACION_APPGT" (
  id, empresa_id, paquete_id, rubro_id, entidad_tipo, entidad_origen_id,
  padre_tipo, padre_origen_id, codigo, nombre, origen, tipo_plantilla,
  definicion, editable, version, estado, published_at
)
select
  md5('SECCION|' || s.empresa_id::text || '|' || s.id)::uuid,
  s.empresa_id,
  md5('PAQUETE_BASE|' || s.empresa_id::text || '|' || s.rubro_id)::uuid,
  s.rubro_id,
  'SECCION',
  s.id,
  'RUBRO',
  s.rubro_id,
  s.id,
  s.nombre,
  'SISTEMA',
  'BASE_RUBRO',
  to_jsonb(s),
  false,
  1,
  'PUBLICADO',
  now()
from public."MATRIZ_SECCIONES_APPGT" s
where coalesce(s.activo, true) and s.deleted_at is null and s.rubro_id is not null
on conflict (empresa_id, entidad_tipo, entidad_origen_id, version) do update set
  definicion = excluded.definicion,
  nombre = excluded.nombre,
  padre_origen_id = excluded.padre_origen_id,
  estado = 'PUBLICADO',
  editable = false,
  es_actual = true,
  activo = true,
  deleted_at = null,
  updated_at = now();

insert into public."PLANTILLAS_CONFIGURACION_APPGT" (
  id, empresa_id, paquete_id, rubro_id, entidad_tipo, entidad_origen_id,
  padre_tipo, padre_origen_id, codigo, nombre, origen, tipo_plantilla,
  definicion, editable, version, estado, published_at
)
select
  md5('MODULO|' || m.empresa_id::text || '|' || m.id)::uuid,
  m.empresa_id,
  md5('PAQUETE_BASE|' || m.empresa_id::text || '|' || s.rubro_id)::uuid,
  s.rubro_id,
  'MODULO',
  m.id,
  'SECCION',
  m.seccion,
  m.id,
  m.nombre,
  'SISTEMA',
  'BASE_RUBRO',
  to_jsonb(m),
  false,
  1,
  'PUBLICADO',
  now()
from public."MATRIZ_MODULOS_APPGT" m
join public."MATRIZ_SECCIONES_APPGT" s
  on s.id = m.seccion and s.empresa_id = m.empresa_id
where coalesce(m.activo, true) and m.deleted_at is null
on conflict (empresa_id, entidad_tipo, entidad_origen_id, version) do update set
  definicion = excluded.definicion,
  nombre = excluded.nombre,
  padre_origen_id = excluded.padre_origen_id,
  estado = 'PUBLICADO',
  editable = false,
  es_actual = true,
  activo = true,
  deleted_at = null,
  updated_at = now();

insert into public."PLANTILLAS_CONFIGURACION_APPGT" (
  id, empresa_id, paquete_id, rubro_id, entidad_tipo, entidad_origen_id,
  padre_tipo, padre_origen_id, codigo, nombre, origen, tipo_plantilla,
  definicion, editable, version, estado, published_at
)
select
  md5('FORMATO|' || f.empresa_id::text || '|' || f.id)::uuid,
  f.empresa_id,
  md5('PAQUETE_BASE|' || f.empresa_id::text || '|' || coalesce(s.rubro_id, r.id))::uuid,
  coalesce(s.rubro_id, r.id),
  'FORMATO',
  f.id,
  'MODULO',
  f.modulo_id,
  f.id,
  f.nombre,
  'SISTEMA',
  'BASE_RUBRO',
  to_jsonb(f),
  false,
  1,
  'PUBLICADO',
  now()
from public."MATRIZ_FORMATOS_APPGT" f
left join public."MATRIZ_MODULOS_APPGT" m
  on m.id = f.modulo_id and m.empresa_id = f.empresa_id
left join public."MATRIZ_SECCIONES_APPGT" s
  on s.id = m.seccion and s.empresa_id = m.empresa_id
join lateral (
  select id from public."RUBROS_APPGT" r0
  where r0.empresa_id = f.empresa_id and coalesce(r0.activo, true)
  order by r0.orden, r0.id limit 1
) r on true
where coalesce(f.activo, true) and f.deleted_at is null
on conflict (empresa_id, entidad_tipo, entidad_origen_id, version) do update set
  definicion = excluded.definicion,
  nombre = excluded.nombre,
  padre_origen_id = excluded.padre_origen_id,
  estado = 'PUBLICADO',
  editable = false,
  es_actual = true,
  activo = true,
  deleted_at = null,
  updated_at = now();

insert into public."PLANTILLAS_CONFIGURACION_APPGT" (
  id, empresa_id, paquete_id, rubro_id, entidad_tipo, entidad_origen_id,
  padre_tipo, padre_origen_id, codigo, nombre, origen, tipo_plantilla,
  definicion, editable, version, estado, published_at
)
select
  md5('TABLA|' || t.empresa_id::text || '|' || t.id)::uuid,
  t.empresa_id,
  md5('PAQUETE_BASE|' || t.empresa_id::text || '|' || coalesce(s.rubro_id, r.id))::uuid,
  coalesce(s.rubro_id, r.id),
  'TABLA',
  t.id,
  'FORMATO',
  t.formato_id,
  t.id,
  t.nombre,
  'SISTEMA',
  'BASE_RUBRO',
  to_jsonb(t),
  false,
  1,
  'PUBLICADO',
  now()
from public."MATRIZ_FORMATO_TABLAS_APPGT" t
join public."MATRIZ_FORMATOS_APPGT" f
  on f.id = t.formato_id and f.empresa_id = t.empresa_id
left join public."MATRIZ_MODULOS_APPGT" m
  on m.id = f.modulo_id and m.empresa_id = f.empresa_id
left join public."MATRIZ_SECCIONES_APPGT" s
  on s.id = m.seccion and s.empresa_id = m.empresa_id
join lateral (
  select id from public."RUBROS_APPGT" r0
  where r0.empresa_id = t.empresa_id and coalesce(r0.activo, true)
  order by r0.orden, r0.id limit 1
) r on true
where coalesce(t.activo, true) and t.deleted_at is null
on conflict (empresa_id, entidad_tipo, entidad_origen_id, version) do update set
  definicion = excluded.definicion,
  nombre = excluded.nombre,
  padre_origen_id = excluded.padre_origen_id,
  estado = 'PUBLICADO',
  editable = false,
  es_actual = true,
  activo = true,
  deleted_at = null,
  updated_at = now();

insert into public."PLANTILLAS_CONFIGURACION_APPGT" (
  id, empresa_id, paquete_id, rubro_id, entidad_tipo, entidad_origen_id,
  padre_tipo, padre_origen_id, codigo, nombre, origen, tipo_plantilla,
  definicion, dependencias, editable, version, estado, published_at
)
select
  md5('CAMPO|' || c.empresa_id::text || '|' || c.id)::uuid,
  c.empresa_id,
  md5('PAQUETE_BASE|' || c.empresa_id::text || '|' || r.id)::uuid,
  r.id,
  'CAMPO',
  c.id,
  'TABLA',
  coalesce(t.id, c.tabla_destino),
  c.id,
  coalesce(nullif(c.etiqueta, ''), c.campo),
  'SISTEMA',
  'BASE_RUBRO',
  to_jsonb(c),
  jsonb_build_array(jsonb_build_object('tabla_destino', c.tabla_destino)),
  false,
  1,
  'PUBLICADO',
  now()
from public."MATRIZ_CAMPOS_FORMATO_APPGT" c
join lateral (
  select id from public."RUBROS_APPGT" r0
  where r0.empresa_id = c.empresa_id and coalesce(r0.activo, true)
  order by r0.orden, r0.id limit 1
) r on true
left join lateral (
  select t0.id
  from public."MATRIZ_FORMATO_TABLAS_APPGT" t0
  where t0.empresa_id = c.empresa_id
    and t0.tabla_destino = c.tabla_destino
    and coalesce(t0.activo, true)
  order by t0.orden, t0.id
  limit 1
) t on true
where coalesce(c.activo, true) and c.deleted_at is null
on conflict (empresa_id, entidad_tipo, entidad_origen_id, version) do update set
  definicion = excluded.definicion,
  nombre = excluded.nombre,
  padre_origen_id = excluded.padre_origen_id,
  dependencias = excluded.dependencias,
  estado = 'PUBLICADO',
  editable = false,
  es_actual = true,
  activo = true,
  deleted_at = null,
  updated_at = now();

-- Las matrices declarativas forman parte de la plantilla, pero se mantienen
-- diferenciadas mediante clase_matriz dentro de la definición.
do $$
declare
  source_table text;
  matrix_class text;
  default_rubro record;
begin
  for default_rubro in
    select distinct on (empresa_id) empresa_id, id
    from public."RUBROS_APPGT"
    where coalesce(activo, true) and deleted_at is null
    order by empresa_id, orden, id
  loop
    foreach source_table in array array[
      'MATRIZ_DROPDOWNS_APPGT',
      'MATRIZ_VALIDACIONES_APPGT',
      'MATRIZ_CONDICIONES_APPGT',
      'MATRIZ_FORMULAS_APPGT'
    ] loop
      matrix_class := replace(replace(source_table, 'MATRIZ_', ''), '_APPGT', '');
      execute format($sql$
        insert into public."PLANTILLAS_CONFIGURACION_APPGT" (
          id, empresa_id, paquete_id, rubro_id, entidad_tipo,
          entidad_origen_id, padre_tipo, padre_origen_id, codigo, nombre,
          origen, tipo_plantilla, definicion, editable, version, estado,
          published_at
        )
        select
          md5(%L || '|' || x.empresa_id::text || '|' || x.id)::uuid,
          x.empresa_id,
          md5('PAQUETE_BASE|' || x.empresa_id::text || '|' || %L)::uuid,
          %L,
          'MATRIZ',
          %L || ':' || x.id,
          case when nullif(to_jsonb(x)->>'campo_id', '') is null then null else 'CAMPO' end,
          nullif(to_jsonb(x)->>'campo_id', ''),
          coalesce(nullif(to_jsonb(x)->>'codigo', ''), x.id),
          %L || ' - ' || coalesce(nullif(to_jsonb(x)->>'codigo', ''), x.id),
          'SISTEMA',
          'BASE_RUBRO',
          to_jsonb(x) || jsonb_build_object('clase_matriz', %L),
          false,
          1,
          'PUBLICADO',
          now()
        from public.%I x
        where x.empresa_id = %L::uuid
          and coalesce(x.activo, true)
          and x.deleted_at is null
        on conflict (empresa_id, entidad_tipo, entidad_origen_id, version)
        do update set
          definicion = excluded.definicion,
          nombre = excluded.nombre,
          padre_origen_id = excluded.padre_origen_id,
          estado = 'PUBLICADO',
          editable = false,
          es_actual = true,
          activo = true,
          deleted_at = null,
          updated_at = now()
      $sql$,
        matrix_class,
        default_rubro.id,
        default_rubro.id,
        matrix_class,
        matrix_class,
        matrix_class,
        source_table,
        default_rubro.empresa_id
      );
    end loop;
  end loop;
end
$$;

-- La procedencia vive deliberadamente en las tablas de plantillas y borradores.
-- No se alteran las matrices publicadas: este proyecto posee automatizaciones
-- heredadas que reaccionan a cambios de esquema y materializan nuevos campos.
-- Mantenerlas intactas evita que formalizar una plantilla cambie la navegación.

alter table public."PAQUETES_PLANTILLA_APPGT" enable row level security;
alter table public."PLANTILLAS_CONFIGURACION_APPGT" enable row level security;

drop policy if exists paquetes_plantilla_select
  on public."PAQUETES_PLANTILLA_APPGT";
create policy paquetes_plantilla_select
  on public."PAQUETES_PLANTILLA_APPGT"
  for select to authenticated
  using (public.appgt_puede_acceder_empresa(empresa_id));
drop policy if exists paquetes_plantilla_admin
  on public."PAQUETES_PLANTILLA_APPGT";
create policy paquetes_plantilla_admin
  on public."PAQUETES_PLANTILLA_APPGT"
  for all to authenticated
  using (public.appgt_es_admin_empresa(empresa_id))
  with check (public.appgt_es_admin_empresa(empresa_id));

drop policy if exists plantillas_configuracion_select
  on public."PLANTILLAS_CONFIGURACION_APPGT";
create policy plantillas_configuracion_select
  on public."PLANTILLAS_CONFIGURACION_APPGT"
  for select to authenticated
  using (public.appgt_puede_acceder_empresa(empresa_id));
drop policy if exists plantillas_configuracion_admin
  on public."PLANTILLAS_CONFIGURACION_APPGT";
create policy plantillas_configuracion_admin
  on public."PLANTILLAS_CONFIGURACION_APPGT"
  for all to authenticated
  using (public.appgt_es_admin_empresa(empresa_id))
  with check (public.appgt_es_admin_empresa(empresa_id));

drop trigger if exists appgt_set_updated_at_trigger
  on public."PAQUETES_PLANTILLA_APPGT";
create trigger appgt_set_updated_at_trigger
before update on public."PAQUETES_PLANTILLA_APPGT"
for each row execute function public.appgt_set_updated_at();
drop trigger if exists appgt_set_updated_at_trigger
  on public."PLANTILLAS_CONFIGURACION_APPGT";
create trigger appgt_set_updated_at_trigger
before update on public."PLANTILLAS_CONFIGURACION_APPGT"
for each row execute function public.appgt_set_updated_at();

grant select on table public."PAQUETES_PLANTILLA_APPGT" to authenticated;
grant select on table public."PLANTILLAS_CONFIGURACION_APPGT" to authenticated;

do $$
begin
  if exists (
    select 1 from pg_event_trigger
    where evtname = 'trg_appgt_auto_insertar_campos'
  ) then
    execute 'alter event trigger trg_appgt_auto_insertar_campos enable';
  end if;
end
$$;

commit;
