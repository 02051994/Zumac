-- ================================================================
-- MATRICES PARA REPORTES / GRAFICOS DINAMICOS - APP OPERACIONES GT
-- PostgreSQL / Supabase
-- ================================================================

create extension if not exists pgcrypto;

-- 1) Vistas o pantallas de reportes.
-- Ejemplo: Reportes > Riego > Humedad de Maceta
create table if not exists public."MATRIZ_VISTAS_REPORTES" (
    id text primary key,
    nombre_vista text not null,
    descripcion text,

    modulo text,
    seccion text default 'reportes',
    subseccion text,

    icono text default 'bar_chart',
    orden integer default 0,
    activo boolean default true,

    requiere_filtros boolean default true,
    propiedades_extra jsonb not null default '{}'::jsonb,

    creado_en timestamptz not null default now(),
    actualizado_en timestamptz not null default now()
);

-- 2) Filtros dinámicos por vista.
-- Importante: Flutter NO trae toda la tabla. Solo usa estos filtros para armar consultas filtradas.
create table if not exists public."MATRIZ_FILTROS_DINAMICOS" (
    id uuid primary key default gen_random_uuid(),

    vista_id text not null references public."MATRIZ_VISTAS_REPORTES"(id) on delete cascade,
    codigo_filtro text not null,
    nombre_filtro text not null,
    descripcion text,

    tabla_origen text,
    campo text not null,
    operador text not null default 'eq',
    -- eq, neq, gte, lte, gt, lt, like

    tipo_dato text default 'text',
    -- text, number, date, datetime, boolean

    disenio text default 'text',
    -- text, date, dropdown, lista_desplegable

    requerido boolean default false,
    valor_default text,
    valores_estaticos jsonb not null default '[]'::jsonb,

    -- Para dropdowns grandes: mejor usar RPC que devuelva valores filtrados/distinct, no toda la tabla.
    usa_rpc_valores boolean default false,
    nombre_rpc_valores text,
    parametro_rpc text,

    color_fondo text,
    color_titulo text,
    color_valores text,
    tamanio_letra numeric,
    color_borde text,

    orden integer default 0,
    activo boolean default true,
    propiedades_extra jsonb not null default '{}'::jsonb,

    creado_en timestamptz not null default now(),
    actualizado_en timestamptz not null default now(),

    constraint uq_matriz_filtros_dinamicos unique (vista_id, codigo_filtro)
);

-- 3) Gráficos dinámicos por vista.
-- Si usa_rpc = true, Supabase calcula y Flutter solo dibuja.
-- Si usa_rpc = false, Flutter consulta tabla_origen con filtros y límite.
create table if not exists public."MATRIZ_GRAFICOS_DINAMICOS" (
    id uuid primary key default gen_random_uuid(),

    vista_id text not null references public."MATRIZ_VISTAS_REPORTES"(id) on delete cascade,
    codigo_grafico text not null,
    nombre_grafico text not null,
    descripcion text,

    tabla_origen text,
    tipo_grafico text not null default 'linea',
    -- linea, barra, tabla, area, combinado, indicador

    campos_select jsonb not null default '[]'::jsonb,
    eje_x jsonb not null default '{}'::jsonb,
    eje_y_1 jsonb not null default '{}'::jsonb,
    eje_y_2 jsonb not null default '{}'::jsonb,
    series jsonb not null default '[]'::jsonb,

    usa_rpc boolean default false,
    nombre_rpc text,
    parametros_rpc jsonb not null default '{}'::jsonb,

    limite_registros integer default 500,

    titulo jsonb not null default '{}'::jsonb,
    leyenda jsonb not null default '{}'::jsonb,
    tooltip_informe jsonb not null default '{}'::jsonb,
    grilla jsonb not null default '{}'::jsonb,
    estilos jsonb not null default '{}'::jsonb,

    orden integer default 0,
    activo boolean default true,
    propiedades_extra jsonb not null default '{}'::jsonb,

    creado_en timestamptz not null default now(),
    actualizado_en timestamptz not null default now(),

    constraint uq_matriz_graficos_dinamicos unique (vista_id, codigo_grafico)
);

-- Índices básicos.
create index if not exists idx_vistas_reportes_activo_orden
on public."MATRIZ_VISTAS_REPORTES" (activo, orden);

create index if not exists idx_filtros_dinamicos_vista_orden
on public."MATRIZ_FILTROS_DINAMICOS" (vista_id, activo, orden);

create index if not exists idx_graficos_dinamicos_vista_orden
on public."MATRIZ_GRAFICOS_DINAMICOS" (vista_id, activo, orden);

-- Trigger genérico para actualizado_en.
create or replace function public.set_actualizado_en_appgt()
returns trigger
language plpgsql
as $$
begin
    new.actualizado_en = now();
    return new;
end;
$$;

drop trigger if exists trg_vistas_reportes_actualizado_en on public."MATRIZ_VISTAS_REPORTES";
create trigger trg_vistas_reportes_actualizado_en
before update on public."MATRIZ_VISTAS_REPORTES"
for each row execute function public.set_actualizado_en_appgt();

drop trigger if exists trg_filtros_dinamicos_actualizado_en on public."MATRIZ_FILTROS_DINAMICOS";
create trigger trg_filtros_dinamicos_actualizado_en
before update on public."MATRIZ_FILTROS_DINAMICOS"
for each row execute function public.set_actualizado_en_appgt();

drop trigger if exists trg_graficos_dinamicos_actualizado_en on public."MATRIZ_GRAFICOS_DINAMICOS";
create trigger trg_graficos_dinamicos_actualizado_en
before update on public."MATRIZ_GRAFICOS_DINAMICOS"
for each row execute function public.set_actualizado_en_appgt();

-- Permisos mínimos para lectura desde Flutter autenticado.
grant usage on schema public to authenticated;
grant select on public."MATRIZ_VISTAS_REPORTES" to authenticated;
grant select on public."MATRIZ_FILTROS_DINAMICOS" to authenticated;
grant select on public."MATRIZ_GRAFICOS_DINAMICOS" to authenticated;

-- RLS simple de lectura para usuarios autenticados.
alter table public."MATRIZ_VISTAS_REPORTES" enable row level security;
alter table public."MATRIZ_FILTROS_DINAMICOS" enable row level security;
alter table public."MATRIZ_GRAFICOS_DINAMICOS" enable row level security;

drop policy if exists "lectura_vistas_reportes_auth" on public."MATRIZ_VISTAS_REPORTES";
create policy "lectura_vistas_reportes_auth"
on public."MATRIZ_VISTAS_REPORTES"
for select
to authenticated
using (true);

drop policy if exists "lectura_filtros_dinamicos_auth" on public."MATRIZ_FILTROS_DINAMICOS";
create policy "lectura_filtros_dinamicos_auth"
on public."MATRIZ_FILTROS_DINAMICOS"
for select
to authenticated
using (true);

drop policy if exists "lectura_graficos_dinamicos_auth" on public."MATRIZ_GRAFICOS_DINAMICOS";
create policy "lectura_graficos_dinamicos_auth"
on public."MATRIZ_GRAFICOS_DINAMICOS"
for select
to authenticated
using (true);

-- ================================================================
-- EJEMPLO DE CONFIGURACIÓN
-- Ajusta tabla_origen/campos a tus nombres reales.
-- ================================================================

insert into public."MATRIZ_VISTAS_REPORTES" (
    id, nombre_vista, descripcion, modulo, seccion, subseccion, orden, activo
)
values (
    'REPORTE_CLIMA_001',
    'Reporte de clima',
    'Vista dinámica para humedad y temperatura filtrada.',
    'Reportes',
    'reportes',
    'Riego',
    1,
    true
)
on conflict (id) do update set
    nombre_vista = excluded.nombre_vista,
    descripcion = excluded.descripcion,
    modulo = excluded.modulo,
    seccion = excluded.seccion,
    subseccion = excluded.subseccion,
    orden = excluded.orden,
    activo = excluded.activo;

insert into public."MATRIZ_FILTROS_DINAMICOS" (
    vista_id, codigo_filtro, nombre_filtro, tabla_origen, campo, operador, tipo_dato, disenio, orden, activo
)
values
    ('REPORTE_CLIMA_001', 'fecha_inicio', 'Fecha inicio', 'registro_estacion', 'fecha', 'gte', 'date', 'date', 1, true),
    ('REPORTE_CLIMA_001', 'fecha_fin', 'Fecha fin', 'registro_estacion', 'fecha', 'lte', 'date', 'date', 2, true),
    ('REPORTE_CLIMA_001', 'lote', 'Lote', 'registro_estacion', 'lote', 'eq', 'text', 'text', 3, true)
on conflict (vista_id, codigo_filtro) do update set
    nombre_filtro = excluded.nombre_filtro,
    tabla_origen = excluded.tabla_origen,
    campo = excluded.campo,
    operador = excluded.operador,
    tipo_dato = excluded.tipo_dato,
    disenio = excluded.disenio,
    orden = excluded.orden,
    activo = excluded.activo;

insert into public."MATRIZ_GRAFICOS_DINAMICOS" (
    vista_id,
    codigo_grafico,
    nombre_grafico,
    tabla_origen,
    tipo_grafico,
    campos_select,
    eje_x,
    eje_y_1,
    limite_registros,
    titulo,
    leyenda,
    grilla,
    estilos,
    orden,
    activo
)
values (
    'REPORTE_CLIMA_001',
    'GRAF_HUMEDAD_001',
    'Humedad por fecha',
    'registro_estacion',
    'linea',
    '["fecha", "humedad", "lote"]'::jsonb,
    '{"campo":"fecha", "tipo":"datetime", "titulo":"Fecha"}'::jsonb,
    '{"campo":"humedad", "agregacion":"promedio", "titulo":"Humedad", "color":"#1565C0"}'::jsonb,
    500,
    '{"texto":"Humedad filtrada - {lote}", "color":"#1F2937", "tamanio":18}'::jsonb,
    '{"visible":true, "posicion":"bottom"}'::jsonb,
    '{"visible":true, "color":"#E2E8F0"}'::jsonb,
    '{"color_fondo":"#FFFFFF", "color_titulo":"#1F2937"}'::jsonb,
    1,
    true
)
on conflict (vista_id, codigo_grafico) do update set
    nombre_grafico = excluded.nombre_grafico,
    tabla_origen = excluded.tabla_origen,
    tipo_grafico = excluded.tipo_grafico,
    campos_select = excluded.campos_select,
    eje_x = excluded.eje_x,
    eje_y_1 = excluded.eje_y_1,
    limite_registros = excluded.limite_registros,
    titulo = excluded.titulo,
    leyenda = excluded.leyenda,
    grilla = excluded.grilla,
    estilos = excluded.estilos,
    orden = excluded.orden,
    activo = excluded.activo;

-- ================================================================
-- ACTUALIZACIÓN: MÓDULOS Y PERMISOS PARA REPORTES DINÁMICOS
-- Flutter ahora lee estas 2 matrices:
--   MATRIZ_MODULOS_GRAFICOS_DINAMICOS
--   PERMISOS_REPORTES_USUARIOS_APPGT
-- ================================================================

create table if not exists public."MATRIZ_MODULOS_GRAFICOS_DINAMICOS" (
    id text primary key,
    nombre text not null,
    icono text,
    descripcion text,
    orden integer default 0,
    activo boolean default true,
    color_fondo text,
    color_texto text,
    color_borde text,
    created_at timestamptz default now()
);

alter table public."MATRIZ_VISTAS_REPORTES"
add column if not exists id_modulo_reporte text;

create table if not exists public."PERMISOS_REPORTES_USUARIOS_APPGT" (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,
    id_modulo_reporte text not null,
    id_vista_reporte text not null,
    puede_ver boolean default true,
    puede_exportar_excel boolean default false,
    puede_exportar_pdf boolean default false,
    puede_exportar_csv boolean default false,
    activo boolean default true,
    created_at timestamptz default now(),
    constraint fk_permiso_modulo_reporte
        foreign key (id_modulo_reporte)
        references public."MATRIZ_MODULOS_GRAFICOS_DINAMICOS"(id)
        on delete cascade
);

create index if not exists idx_vistas_reportes_modulo
on public."MATRIZ_VISTAS_REPORTES"(id_modulo_reporte, activo, orden);

create index if not exists idx_permiso_reportes_user
on public."PERMISOS_REPORTES_USUARIOS_APPGT"(user_id);

create index if not exists idx_permiso_reportes_modulo_vista
on public."PERMISOS_REPORTES_USUARIOS_APPGT"(id_modulo_reporte, id_vista_reporte);

grant select on public."MATRIZ_MODULOS_GRAFICOS_DINAMICOS" to authenticated;
grant select on public."PERMISOS_REPORTES_USUARIOS_APPGT" to authenticated;

alter table public."MATRIZ_MODULOS_GRAFICOS_DINAMICOS" enable row level security;
alter table public."PERMISOS_REPORTES_USUARIOS_APPGT" enable row level security;

drop policy if exists "lectura_modulos_graficos_auth" on public."MATRIZ_MODULOS_GRAFICOS_DINAMICOS";
create policy "lectura_modulos_graficos_auth"
on public."MATRIZ_MODULOS_GRAFICOS_DINAMICOS"
for select
to authenticated
using (true);

drop policy if exists "lectura_permisos_reportes_propios" on public."PERMISOS_REPORTES_USUARIOS_APPGT";
create policy "lectura_permisos_reportes_propios"
on public."PERMISOS_REPORTES_USUARIOS_APPGT"
for select
to authenticated
using (auth.uid() = user_id);

insert into public."MATRIZ_MODULOS_GRAFICOS_DINAMICOS" (id, nombre, icono, descripcion, orden, activo)
values
    ('riego', 'RIEGO', 'water_drop', 'Reportes del área de riego', 1, true),
    ('sanidad', 'SANIDAD', 'bug_report', 'Reportes del área de sanidad', 2, true),
    ('produccion', 'PRODUCCIÓN', 'factory', 'Reportes del área de producción', 3, true)
on conflict (id) do update set
    nombre = excluded.nombre,
    icono = excluded.icono,
    descripcion = excluded.descripcion,
    orden = excluded.orden,
    activo = excluded.activo;
