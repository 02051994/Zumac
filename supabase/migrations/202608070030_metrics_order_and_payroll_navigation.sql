begin;

-- El orden se guarda en una sola transacción. Las escrituras individuales
-- permitían que una recarga leyera un estado intermedio o parcialmente guardado.
create or replace function public.appgt_reordenar_dashboards_metrics_v1(
  p_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_expected integer;
  v_received integer := coalesce(array_length(p_ids, 1), 0);
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'Sin permiso' using errcode = '42501';
  end if;

  select count(*) into v_expected
  from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  where d.empresa_id = v_empresa_id
    and d.activo
    and d.deleted_at is null
    and d.id = any(coalesce(p_ids, '{}'::uuid[]));

  if v_received = 0 or v_expected <> v_received
     or (select count(distinct ids.id) from unnest(p_ids) as ids(id)) <> v_received then
    raise exception 'La lista de dashboards es inválida o contiene duplicados.';
  end if;

  -- Primera fase fuera del rango visible; evita colisiones si una instalación
  -- antigua agregó una restricción única sobre empresa/orden.
  update public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  set orden = 100000 + ordered.position::integer,
      updated_at = now()
  from unnest(p_ids) with ordinality as ordered(id, position)
  where d.id = ordered.id
    and d.empresa_id = v_empresa_id
    and d.activo
    and d.deleted_at is null;

  update public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  set orden = ordered.position::integer - 1,
      updated_at = now()
  from unnest(p_ids) with ordinality as ordered(id, position)
  where d.id = ordered.id
    and d.empresa_id = v_empresa_id
    and d.activo
    and d.deleted_at is null;

  return jsonb_build_object('guardado', true, 'total', v_received);
end
$$;

revoke all on function public.appgt_reordenar_dashboards_metrics_v1(uuid[])
  from public, anon;
grant execute on function public.appgt_reordenar_dashboards_metrics_v1(uuid[])
  to authenticated, service_role;

-- Ordena Gestión Humana sin destruir tablas históricas. Las filas antiguas se
-- retiran de navegación mediante borrado lógico; sus datos permanecen intactos.
do $$
declare
  v_source record;
  v_matrix_section_id text;
  v_matrix_module_id text;
begin
  for v_source in
    select m.*
    from public."MATRIZ_MODULOS_APPGT" m
    where public.appgt_normalizar_clave(m.nombre) = 'GESTIONHUMANA'
      and coalesce(m.activo, true)
      and not coalesce(m.eliminado, false)
  loop
    select s.id into v_matrix_section_id
    from public."MATRIZ_SECCIONES_APPGT" s
    where s.empresa_id = v_source.empresa_id
      and s.rubro_id is not distinct from v_source.rubro_id
      and (
        public.appgt_normalizar_clave(s.id) = 'MATRICES'
        or public.appgt_normalizar_clave(s.nombre) = 'MATRICES'
      )
      and coalesce(s.activo, true)
      and not coalesce(s.eliminado, false)
    order by s.orden, s.id
    limit 1;

    if v_matrix_section_id is null then
      v_matrix_section_id := v_source.seccion || '_matrices';
      insert into public."MATRIZ_SECCIONES_APPGT" (
        id, empresa_id, nombre, icono, orden, activo, rubro_id,
        tipo_contenido, ruta_flutter
      ) values (
        v_matrix_section_id, v_source.empresa_id, 'MATRICES', 'grid_view',
        20, true, v_source.rubro_id, 'FORMATOS', null
      )
      on conflict (id) do update set
        nombre = 'MATRICES',
        activo = true,
        deleted_at = null,
        eliminado = false,
        updated_at = now();
    end if;

    select m.id into v_matrix_module_id
    from public."MATRIZ_MODULOS_APPGT" m
    where m.empresa_id = v_source.empresa_id
      and m.seccion = v_matrix_section_id
      and public.appgt_normalizar_clave(m.nombre) = 'GESTIONHUMANA'
      and coalesce(m.activo, true)
      and not coalesce(m.eliminado, false)
    order by m.orden, m.id
    limit 1;

    if v_matrix_module_id is null then
      v_matrix_module_id := v_source.id || '_matrices';
      insert into public."MATRIZ_MODULOS_APPGT" (
        id, empresa_id, nombre, seccion, orden, activo, rubro_id, icono, color
      ) values (
        v_matrix_module_id, v_source.empresa_id, v_source.nombre,
        v_matrix_section_id, v_source.orden, true, v_source.rubro_id,
        coalesce(nullif(v_source.icono, ''), 'groups_outlined'),
        v_source.color
      )
      on conflict (id) do update set
        nombre = excluded.nombre,
        seccion = excluded.seccion,
        rubro_id = excluded.rubro_id,
        activo = true,
        deleted_at = null,
        eliminado = false,
        updated_at = now();
    end if;

    update public."MATRIZ_FORMATOS_APPGT" f
    set modulo_id = v_matrix_module_id,
        rubro_id = v_source.rubro_id,
        updated_at = now()
    where f.empresa_id = v_source.empresa_id
      and f.modulo_id = v_source.id
      and (
        public.appgt_normalizar_clave(f.nombre) like 'MATRIZ%'
        or public.appgt_normalizar_clave(f.tabla_destino) like 'MATRIZ%'
      )
      and coalesce(f.activo, true)
      and not coalesce(f.eliminado, false);

    update public."PERMISOS_DE_USUARIOS_APPGT" p
    set seccion = v_matrix_section_id,
        modulo = v_matrix_module_id,
        updated_at = now()
    where p.empresa_id = v_source.empresa_id
      and exists (
        select 1
        from public."MATRIZ_FORMATOS_APPGT" f
        where f.empresa_id = p.empresa_id
          and f.id = p.formato
          and f.modulo_id = v_matrix_module_id
      );

    update public."MATRIZ_FORMATOS_APPGT" f
    set activo = false,
        eliminado = true,
        deleted_at = coalesce(f.deleted_at, now()),
        estado_sync = 'sincronizado',
        updated_at = now()
    where f.empresa_id = v_source.empresa_id
      and f.modulo_id = v_source.id
      and public.appgt_normalizar_clave(f.nombre) in (
        'CABECERADETAREOPERSONAL',
        'AUSENCIASDELPERSONAL',
        'HORASEXTRAS',
        'CONSOLIDADODIARIO',
        'PLANILLACABECERA',
        'PLANILLADETALLE',
        'PLANILLACONCEPTOS',
        'BOLETASDEPAGO'
      );

    update public."PERMISOS_DE_USUARIOS_APPGT" p
    set activo = false,
        eliminado = true,
        updated_at = now()
    where p.empresa_id = v_source.empresa_id
      and exists (
        select 1
        from public."MATRIZ_FORMATOS_APPGT" f
        where f.empresa_id = p.empresa_id
          and f.id = p.formato
          and f.eliminado
          and f.deleted_at is not null
      );
  end loop;
end
$$;

commit;
