begin;

-- Encabezados configurables por formato y por tabla. Auditable siempre queda
-- explícito en la matriz; true conserva el bloque de código histórico.
alter table public."MATRIZ_FORMATOS_APPGT"
  add column if not exists auditable boolean not null default true,
  add column if not exists icono text not null default 'assignment',
  add column if not exists imagen_encabezado text;

alter table public."MATRIZ_FORMATO_TABLAS_APPGT"
  add column if not exists auditable boolean not null default true,
  add column if not exists icono text not null default 'assignment',
  add column if not exists imagen_encabezado text;

create or replace function public.appgt_expandir_formato_desde_borrador()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payload jsonb;
  v_capabilities jsonb;
begin
  select b.definicion
  into v_payload
  from public."BORRADORES_CONFIGURACION_APPGT" b
  where b.empresa_id = new.empresa_id
    and b.entidad_tipo = 'FORMATO'
    and b.codigo = new.id
    and b.deleted_at is null
  order by b.updated_at desc
  limit 1;

  if v_payload is null then return new; end if;

  v_capabilities := coalesce(v_payload -> 'capacidades', '{}'::jsonb);
  new.capacidades := v_capabilities;
  new.flujo_estados := coalesce(v_payload -> 'flujo_estados', '[]'::jsonb);
  new.workflow_enabled :=
    lower(coalesce(v_capabilities ->> 'workflow', 'false')) in ('true','1','yes','si','sí');
  new.geolocation_enabled :=
    lower(coalesce(v_capabilities ->> 'geolocalizacion', 'false')) in ('true','1','yes','si','sí');
  new.approvals_enabled :=
    lower(coalesce(v_capabilities ->> 'aprobaciones', 'false')) in ('true','1','yes','si','sí');
  new.auditable := lower(coalesce(v_payload ->> 'auditable', 'true'))
    in ('true','1','yes','si','sí');
  new.icono := coalesce(nullif(v_payload ->> 'icono', ''), 'assignment');
  new.imagen_encabezado := nullif(v_payload ->> 'imagen_encabezado', '');
  return new;
end
$$;

create or replace function public.appgt_expandir_tabla_desde_borrador()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_payload jsonb;
begin
  select b.definicion
  into v_payload
  from public."BORRADORES_CONFIGURACION_APPGT" b
  where b.empresa_id = new.empresa_id
    and b.entidad_tipo = 'TABLA'
    and b.codigo = new.id
    and b.deleted_at is null
  order by b.updated_at desc
  limit 1;

  if v_payload is null then return new; end if;
  new.auditable := lower(coalesce(v_payload ->> 'auditable', 'true'))
    in ('true','1','yes','si','sí');
  new.icono := coalesce(nullif(v_payload ->> 'icono', ''), 'assignment');
  new.imagen_encabezado := nullif(v_payload ->> 'imagen_encabezado', '');
  return new;
end
$$;

drop trigger if exists appgt_00_expandir_tabla_desde_borrador_trigger
  on public."MATRIZ_FORMATO_TABLAS_APPGT";
create trigger appgt_00_expandir_tabla_desde_borrador_trigger
before insert on public."MATRIZ_FORMATO_TABLAS_APPGT"
for each row execute function public.appgt_expandir_tabla_desde_borrador();

comment on column public."MATRIZ_FORMATOS_APPGT".auditable is
  'Sí muestra icono, título y código; No muestra icono y título centrado globalmente.';
comment on column public."MATRIZ_FORMATO_TABLAS_APPGT".auditable is
  'Configuración obligatoria del encabezado de la tabla.';

commit;
