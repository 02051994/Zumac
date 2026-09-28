begin;

-- Gestión Humana no tiene dos dominios de matrices. El catálogo histórico
-- creó "Matriz Gestión Humana" y una carga posterior creó "Gestión Humana"
-- para Photocheck. Se conserva un único módulo por empresa y sección, se
-- trasladan todos sus formatos y permisos, y se retiran los duplicados.
create temporary table appgt_gh_matrix_candidates on commit drop as
select
  m.empresa_id,
  m.seccion,
  m.id as module_id,
  row_number() over (
    partition by m.empresa_id, m.seccion
    order by
      case
        when public.appgt_normalizar_clave(m.nombre) =
             'MATRIZ GESTION HUMANA' then 0
        else 1
      end,
      (
        select count(*)
        from public."MATRIZ_FORMATOS_APPGT" f
        where f.empresa_id = m.empresa_id
          and f.modulo_id = m.id
          and coalesce(f.activo, true)
          and not coalesce(f.eliminado, false)
          and f.deleted_at is null
      ) desc,
      m.orden,
      m.id
  ) as preference
from public."MATRIZ_MODULOS_APPGT" m
join public."MATRIZ_SECCIONES_APPGT" s
  on s.empresa_id = m.empresa_id and s.id = m.seccion
where public.appgt_normalizar_clave(s.nombre) = 'MATRICES'
  and public.appgt_normalizar_clave(m.nombre) in (
    'MATRIZ GESTION HUMANA',
    'GESTION HUMANA'
  )
  and coalesce(s.activo, true)
  and coalesce(m.activo, true)
  and not coalesce(m.eliminado, false)
  and m.deleted_at is null;

create temporary table appgt_gh_matrix_merge on commit drop as
select
  source.empresa_id,
  source.seccion,
  source.module_id as source_module_id,
  target.module_id as target_module_id
from appgt_gh_matrix_candidates source
join appgt_gh_matrix_candidates target
  on target.empresa_id = source.empresa_id
 and target.seccion = source.seccion
 and target.preference = 1
where source.preference > 1;

update public."MATRIZ_FORMATOS_APPGT" f
set modulo_id = merge.target_module_id,
    updated_at = now(),
    estado_sync = 'sincronizado'
from appgt_gh_matrix_merge merge
where f.empresa_id = merge.empresa_id
  and f.modulo_id = merge.source_module_id;

update public."MATRIZ_FORMATOS_ESPECIALES_APPGT" special
set modulo_id = merge.target_module_id,
    updated_at = now(),
    estado_sync = 'sincronizado'
from appgt_gh_matrix_merge merge
where special.empresa_id = merge.empresa_id
  and special.modulo_id = merge.source_module_id;

update public."PERMISOS_DE_USUARIOS_APPGT" permission
set modulo = merge.target_module_id,
    updated_at = now(),
    estado_sync = 'sincronizado'
from appgt_gh_matrix_merge merge
where permission.empresa_id = merge.empresa_id
  and permission.modulo = merge.source_module_id;

update public."MATRIZ_VISTAS_DINAMICAS_APPGT" view_config
set modulo = merge.target_module_id,
    updated_at = now(),
    estado_sync = 'sincronizado'
from appgt_gh_matrix_merge merge
where view_config.empresa_id = merge.empresa_id
  and view_config.modulo = merge.source_module_id;

update public."MATRIZ_MODULOS_APPGT" target
set nombre = 'Matriz Gestión Humana',
    icono = coalesce(nullif(target.icono, ''), 'people'),
    activo = true,
    eliminado = false,
    deleted_at = null,
    updated_at = now(),
    estado_sync = 'sincronizado'
from appgt_gh_matrix_candidates candidate
where candidate.preference = 1
  and target.empresa_id = candidate.empresa_id
  and target.id = candidate.module_id;

update public."MATRIZ_MODULOS_APPGT" duplicate
set activo = false,
    eliminado = true,
    deleted_at = coalesce(duplicate.deleted_at, now()),
    updated_at = now(),
    estado_sync = 'sincronizado'
from appgt_gh_matrix_merge merge
where duplicate.empresa_id = merge.empresa_id
  and duplicate.id = merge.source_module_id;

-- Conserva el orden laboral existente y coloca Photocheck al final del único
-- módulo. Se usan intervalos de diez para permitir inserciones posteriores.
with ordered as (
  select
    f.id,
    row_number() over (
      partition by f.empresa_id, f.modulo_id
      order by
        case when f.tabla_destino = 'MATRIZ-PHOTOCHEK' then 1 else 0 end,
        f.orden,
        f.nombre,
        f.id
    ) * 10 as new_order
  from public."MATRIZ_FORMATOS_APPGT" f
  join appgt_gh_matrix_candidates candidate
    on candidate.empresa_id = f.empresa_id
   and candidate.module_id = f.modulo_id
   and candidate.preference = 1
  where coalesce(f.activo, true)
    and not coalesce(f.eliminado, false)
    and f.deleted_at is null
)
update public."MATRIZ_FORMATOS_APPGT" f
set orden = ordered.new_order,
    updated_at = now()
from ordered
where f.id = ordered.id;

do $$
begin
  if exists (
    select 1
    from public."MATRIZ_MODULOS_APPGT" m
    join public."MATRIZ_SECCIONES_APPGT" s
      on s.empresa_id = m.empresa_id and s.id = m.seccion
    where public.appgt_normalizar_clave(s.nombre) = 'MATRICES'
      and public.appgt_normalizar_clave(m.nombre) in (
        'MATRIZ GESTION HUMANA',
        'GESTION HUMANA'
      )
      and coalesce(m.activo, true)
      and not coalesce(m.eliminado, false)
      and m.deleted_at is null
    group by m.empresa_id, m.seccion
    having count(*) > 1
  ) then
    raise exception 'Persisten módulos duplicados de matrices de Gestión Humana';
  end if;
end
$$;

commit;
