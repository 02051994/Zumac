begin;

-- La configuración histórica ya era la línea de Agroexportación. Conservamos
-- el identificador técnico para no romper llaves foráneas y corregimos el nombre
-- visible con el que se administrará desde Zumac Creator.
update public."RUBROS_APPGT"
set codigo = 'AGROEXPORTACION',
    nombre = 'Agroexportación',
    descripcion = 'Procesos de campo, planta, calidad, almacén y despacho agroexportador.',
    icono = coalesce(nullif(icono, ''), 'agriculture'),
    updated_at = now(),
    deleted_at = null,
    activo = true
where id = 'rubro_general_zumac';

update public."PLANTILLAS_CONFIGURACION_APPGT"
set nombre = 'Agroexportación',
    definicion = jsonb_set(
      coalesce(definicion, '{}'::jsonb),
      '{icono}',
      to_jsonb(coalesce(nullif(definicion ->> 'icono', ''), 'agriculture')),
      true
    ),
    updated_at = now()
where entidad_tipo = 'RUBRO'
  and entidad_origen_id = 'rubro_general_zumac'
  and deleted_at is null;

-- Completa cualquier fila histórica que todavía no hubiera heredado el rubro.
update public."MATRIZ_SECCIONES_APPGT"
set rubro_id = 'rubro_general_zumac'
where rubro_id is null;

update public."MATRIZ_MODULOS_APPGT" m
set rubro_id = s.rubro_id
from public."MATRIZ_SECCIONES_APPGT" s
where s.empresa_id = m.empresa_id
  and s.id = m.seccion
  and m.rubro_id is distinct from s.rubro_id;

update public."MATRIZ_FORMATOS_APPGT" f
set rubro_id = m.rubro_id
from public."MATRIZ_MODULOS_APPGT" m
where m.empresa_id = f.empresa_id
  and m.id = f.modulo_id
  and f.rubro_id is distinct from m.rubro_id;

update public."MATRIZ_FORMATO_TABLAS_APPGT" t
set rubro_id = f.rubro_id
from public."MATRIZ_FORMATOS_APPGT" f
where f.empresa_id = t.empresa_id
  and f.id = t.formato_id
  and t.rubro_id is distinct from f.rubro_id;

-- El módulo ahora conserva también el color elegido por el administrador.
alter table public."MATRIZ_MODULOS_APPGT"
  add column if not exists color text;

update public."MATRIZ_MODULOS_APPGT" m
set color = nullif(p.definicion ->> 'color', '')
from public."PLANTILLAS_CONFIGURACION_APPGT" p
where p.empresa_id = m.empresa_id
  and p.entidad_tipo = 'MODULO'
  and p.entidad_origen_id = m.id
  and p.es_actual
  and p.activo
  and p.deleted_at is null
  and nullif(p.definicion ->> 'color', '') is not null;

create or replace function public.appgt_expandir_navegacion_desde_borrador()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_definicion jsonb;
begin
  select b.definicion into v_definicion
  from public."BORRADORES_CONFIGURACION_APPGT" b
  where b.empresa_id = new.empresa_id
    and b.codigo = new.id
    and b.entidad_tipo = case tg_table_name
      when 'MATRIZ_SECCIONES_APPGT' then 'SECCION'
      when 'MATRIZ_MODULOS_APPGT' then 'MODULO'
    end
    and b.deleted_at is null
  order by b.updated_at desc
  limit 1;

  if tg_table_name = 'MATRIZ_SECCIONES_APPGT' then
    new.color := coalesce(nullif(v_definicion ->> 'color', ''), new.color);
  elsif tg_table_name = 'MATRIZ_MODULOS_APPGT' then
    new.icono := coalesce(nullif(v_definicion ->> 'icono', ''), new.icono);
    new.color := coalesce(nullif(v_definicion ->> 'color', ''), new.color);
  end if;
  return new;
end
$$;

drop trigger if exists appgt_00_expandir_navegacion_trigger
  on public."MATRIZ_SECCIONES_APPGT";
create trigger appgt_00_expandir_navegacion_trigger
before insert or update on public."MATRIZ_SECCIONES_APPGT"
for each row execute function public.appgt_expandir_navegacion_desde_borrador();

drop trigger if exists appgt_00_expandir_navegacion_trigger
  on public."MATRIZ_MODULOS_APPGT";
create trigger appgt_00_expandir_navegacion_trigger
before insert or update on public."MATRIZ_MODULOS_APPGT"
for each row execute function public.appgt_expandir_navegacion_desde_borrador();

revoke all on function public.appgt_expandir_navegacion_desde_borrador()
  from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;
