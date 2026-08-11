begin;

-- Asistencia de Personal pertenece siempre a Gestión Humana / asistencia y
-- tareo. Se reconstruyen los destinos canónicos por empresa para que la
-- corrección no dependa del nombre o ubicación heredada del módulo actual.
do $$
declare
  v_rubro record;
  v_suffix text;
  v_human text;
  v_attendance text;
  v_misplaced jsonb;
begin
  for v_rubro in
    select r.*
    from public."RUBROS_APPGT" r
    where r.activo and r.deleted_at is null
  loop
    v_suffix := substr(md5(v_rubro.empresa_id::text), 1, 10);
    v_human := 'erp_gestion_humana_' || v_suffix;
    v_attendance := 'gh_asistencia_tareo_' || v_suffix;

    insert into public."MATRIZ_SECCIONES_APPGT" (
      id, empresa_id, nombre, icono, color, orden, activo, rubro_id,
      tipo_contenido, ruta_flutter
    ) values (
      v_human, v_rubro.empresa_id, 'GESTIÓN HUMANA', 'groups', '#A33E5C',
      60, true, v_rubro.id, 'FORMATOS', null
    )
    on conflict (id) do update set
      nombre = excluded.nombre,
      icono = excluded.icono,
      color = excluded.color,
      activo = true,
      rubro_id = excluded.rubro_id,
      tipo_contenido = 'FORMATOS',
      deleted_at = null,
      eliminado = false,
      updated_at = now();

    insert into public."MATRIZ_MODULOS_APPGT" (
      id, empresa_id, nombre, seccion, orden, activo, rubro_id, icono, color
    ) values (
      v_attendance, v_rubro.empresa_id, 'asistencia y tareo', v_human,
      10, true, v_rubro.id, 'schedule', '#A33E5C'
    )
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
    set modulo_id = v_attendance,
        rubro_id = v_rubro.id,
        activo = true,
        eliminado = false,
        deleted_at = null,
        updated_at = now()
    where f.empresa_id = v_rubro.empresa_id
      and (
        upper(btrim(coalesce(f.tabla_destino, ''))) in (
          'GT-ASISTENCIA_PERSONAL', 'ASISTENCIA_PERSONAL'
        )
        or (
          public.appgt_normalizar_clave(
            coalesce(f.nombre, '') || ' ' || coalesce(f.tabla_destino, '')
          ) like '%ASISTENCIA%'
          and public.appgt_normalizar_clave(
            coalesce(f.nombre, '') || ' ' || coalesce(f.tabla_destino, '')
          ) like '%PERSONAL%'
        )
      );

    -- Evita una colisión si una versión anterior dejó simultáneamente un
    -- permiso en el módulo correcto y otro en MATRICES.
    delete from public."PERMISOS_DE_USUARIOS_APPGT" old_permission
    using public."MATRIZ_FORMATOS_APPGT" f
    where f.empresa_id = v_rubro.empresa_id
      and f.modulo_id = v_attendance
      and old_permission.empresa_id = f.empresa_id
      and old_permission.formato = f.id
      and old_permission.modulo is distinct from v_attendance
      and exists (
        select 1
        from public."PERMISOS_DE_USUARIOS_APPGT" current_permission
        where current_permission.empresa_id = old_permission.empresa_id
          and current_permission.user_id = old_permission.user_id
          and current_permission.formato = old_permission.formato
          and current_permission.modulo = v_attendance
      );

    update public."PERMISOS_DE_USUARIOS_APPGT" p
    set seccion = v_human,
        modulo = v_attendance,
        activo = true,
        eliminado = false,
        deleted_at = null,
        updated_at = now()
    from public."MATRIZ_FORMATOS_APPGT" f
    where f.empresa_id = v_rubro.empresa_id
      and f.modulo_id = v_attendance
      and p.empresa_id = f.empresa_id
      and p.formato = f.id;
  end loop;

  select jsonb_agg(jsonb_build_object(
           'empresa_id', f.empresa_id,
           'formato_id', f.id,
           'formato', f.nombre,
           'tabla', f.tabla_destino,
           'modulo', m.nombre,
           'seccion', s.nombre,
           'rubro_id', f.rubro_id
         ))
  into v_misplaced
  from public."MATRIZ_FORMATOS_APPGT" f
    join public."MATRIZ_MODULOS_APPGT" m
      on m.empresa_id = f.empresa_id and m.id = f.modulo_id
    join public."MATRIZ_SECCIONES_APPGT" s
      on s.empresa_id = m.empresa_id and s.id = m.seccion
    where f.activo and not coalesce(f.eliminado, false)
      and (
        upper(btrim(coalesce(f.tabla_destino, ''))) in (
          'GT-ASISTENCIA_PERSONAL', 'ASISTENCIA_PERSONAL'
        )
        or (
          public.appgt_normalizar_clave(
            coalesce(f.nombre, '') || ' ' || coalesce(f.tabla_destino, '')
          ) like '%ASISTENCIA%'
          and public.appgt_normalizar_clave(
            coalesce(f.nombre, '') || ' ' || coalesce(f.tabla_destino, '')
          ) like '%PERSONAL%'
        )
      )
      and (
        public.appgt_normalizar_clave(s.nombre) <> 'GESTIONHUMANA'
        or public.appgt_normalizar_clave(m.nombre) <> 'ASISTENCIAYTAREO'
      );

  if v_misplaced is not null then
    raise exception
      'La migración no pudo ubicar todos los formatos Asistencia de Personal: %',
      v_misplaced;
  end if;
end
$$;

-- La lectura de dashboards usa la misma empresa resuelta por los RPC de
-- escritura. Esto evita mezclar órdenes de distintas empresas accesibles por
-- RLS y ofrece una lectura autoritativa para verificar cada reordenamiento.
create or replace function public.appgt_listar_dashboards_metrics_v1()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_dashboards jsonb;
  v_ids uuid[];
begin
  if v_empresa_id is null
     or not public.appgt_puede_acceder_empresa(v_empresa_id) then
    raise exception 'Sin permiso' using errcode = '42501';
  end if;

  select
    coalesce(jsonb_agg(to_jsonb(d) order by d.orden, d.created_at, d.id),
             '[]'::jsonb),
    coalesce(array_agg(d.id order by d.orden, d.created_at, d.id),
             '{}'::uuid[])
  into v_dashboards, v_ids
  from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  where d.empresa_id = v_empresa_id
    and d.activo
    and d.deleted_at is null;

  return jsonb_build_object(
    'dashboards', v_dashboards,
    'total', coalesce(array_length(v_ids, 1), 0),
    'firma_orden', md5(array_to_string(v_ids, ','))
  );
end
$$;

-- Reordenamiento V4: lista completa, bloqueo por empresa, órdenes temporales
-- sin colisiones, comprobación dentro de la transacción y respuesta ordenada.
create or replace function public.appgt_reordenar_dashboards_metrics_v4(
  p_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_received integer := coalesce(array_length(p_ids, 1), 0);
  v_active integer;
  v_temp_base integer;
  v_confirmed_ids uuid[];
  v_result jsonb;
begin
  if v_empresa_id is null
     or not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'Sin permiso' using errcode = '42501';
  end if;
  if v_received = 0
     or (select count(distinct value) from unnest(p_ids) value) <> v_received then
    raise exception 'La lista de dashboards es inválida o contiene duplicados.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_empresa_id::text, 831));

  select count(*)
  into v_active
  from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  where d.empresa_id = v_empresa_id
    and d.activo
    and d.deleted_at is null;

  if v_active <> v_received or exists (
    select 1
    from unnest(p_ids) requested(id)
    where not exists (
      select 1
      from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
      where d.empresa_id = v_empresa_id
        and d.id = requested.id
        and d.activo
        and d.deleted_at is null
    )
  ) then
    raise exception 'La lista debe contener todos los dashboards activos.';
  end if;

  perform 1
  from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  where d.empresa_id = v_empresa_id
    and d.activo
    and d.deleted_at is null
  for update;

  select coalesce(max(d.orden), 0) + v_received + 1024
  into v_temp_base
  from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  where d.empresa_id = v_empresa_id
    and d.activo
    and d.deleted_at is null;

  update public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  set orden = v_temp_base + ordered.position::integer,
      updated_at = clock_timestamp()
  from unnest(p_ids) with ordinality ordered(id, position)
  where d.empresa_id = v_empresa_id
    and d.id = ordered.id
    and d.activo
    and d.deleted_at is null;

  update public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  set orden = ordered.position::integer - 1,
      updated_at = clock_timestamp()
  from unnest(p_ids) with ordinality ordered(id, position)
  where d.empresa_id = v_empresa_id
    and d.id = ordered.id
    and d.activo
    and d.deleted_at is null;

  select
    array_agg(d.id order by d.orden, d.created_at, d.id),
    jsonb_agg(
      jsonb_build_object(
        'id', d.id,
        'orden', d.orden,
        'updated_at', d.updated_at
      ) order by d.orden, d.created_at, d.id
    )
  into v_confirmed_ids, v_result
  from public."ZUMAC_METRICS_DASHBOARDS_APPGT" d
  where d.empresa_id = v_empresa_id
    and d.activo
    and d.deleted_at is null;

  if v_confirmed_ids is distinct from p_ids then
    raise exception 'PostgreSQL no conservó la secuencia solicitada.';
  end if;

  return jsonb_build_object(
    'guardado', true,
    'total', v_active,
    'dashboards', coalesce(v_result, '[]'::jsonb),
    'firma_orden', md5(array_to_string(v_confirmed_ids, ','))
  );
end
$$;

revoke all on function public.appgt_listar_dashboards_metrics_v1()
  from public, anon;
grant execute on function public.appgt_listar_dashboards_metrics_v1()
  to authenticated, service_role;
revoke all on function public.appgt_reordenar_dashboards_metrics_v4(uuid[])
  from public, anon;
grant execute on function public.appgt_reordenar_dashboards_metrics_v4(uuid[])
  to authenticated, service_role;

notify pgrst, 'reload schema';
commit;
