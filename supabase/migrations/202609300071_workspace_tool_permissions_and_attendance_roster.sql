begin;

create table if not exists public."PERMISOS_HERRAMIENTAS_USUARIO_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  herramienta text not null,
  permitido boolean not null default false,
  otorgado_por uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint permisos_herramientas_usuario_unique
    unique (empresa_id, user_id, herramienta),
  constraint permisos_herramientas_codigo_check check (
    herramienta in (
      'ZUMAC_CONSULTOR', 'ZUMAC_CREATOR', 'ZUMAC_METRICS',
      'ZUMAC_ALERTS', 'ZUMAC_ACTIONS'
    )
  )
);

create index if not exists permisos_herramientas_usuario_lookup_idx
  on public."PERMISOS_HERRAMIENTAS_USUARIO_APPGT"(empresa_id, user_id, permitido);

drop trigger if exists trg_permisos_herramientas_updated_at
  on public."PERMISOS_HERRAMIENTAS_USUARIO_APPGT";
create trigger trg_permisos_herramientas_updated_at
before update on public."PERMISOS_HERRAMIENTAS_USUARIO_APPGT"
for each row execute function public.appgt_set_updated_at();

alter table public."PERMISOS_HERRAMIENTAS_USUARIO_APPGT" enable row level security;
drop policy if exists permisos_herramientas_select
  on public."PERMISOS_HERRAMIENTAS_USUARIO_APPGT";
create policy permisos_herramientas_select
on public."PERMISOS_HERRAMIENTAS_USUARIO_APPGT"
for select to authenticated
using (
  user_id = auth.uid()
  or public.appgt_puede_gestionar_permisos_empresa(empresa_id)
);

revoke insert, update, delete
  on public."PERMISOS_HERRAMIENTAS_USUARIO_APPGT" from authenticated;
grant select on public."PERMISOS_HERRAMIENTAS_USUARIO_APPGT" to authenticated;

create or replace function public.appgt_herramienta_empresa_habilitada_v1(
  p_empresa_id uuid,
  p_herramienta text
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(case upper(btrim(coalesce(p_herramienta, '')))
    when 'ZUMAC_CONSULTOR' then e.habilitar_zumac_consultor
    when 'ZUMAC_CREATOR' then e.habilitar_zumac_creator
    when 'ZUMAC_METRICS' then e.habilitar_zumac_metrics
    when 'ZUMAC_ALERTS' then e.habilitar_zumac_alerts
    when 'ZUMAC_ACTIONS' then e.habilitar_zumac_actions
    else false
  end, false)
  from public."EMPRESAS_APPGT" e
  where e.id = p_empresa_id and e.activo
$$;

create or replace function public.appgt_usuario_puede_herramienta_v1(
  p_herramienta text,
  p_user_id uuid default auth.uid()
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_codigo text := upper(btrim(coalesce(p_herramienta, '')));
  v_rol text;
begin
  if v_empresa_id is null or p_user_id is null
     or not public.appgt_herramienta_empresa_habilitada_v1(v_empresa_id, v_codigo) then
    return false;
  end if;
  v_rol := public.appgt_rol_empresa(v_empresa_id, p_user_id);
  if v_rol = 'ADMIN' then
    return true;
  end if;
  return exists (
    select 1
    from public."PERMISOS_HERRAMIENTAS_USUARIO_APPGT" p
    where p.empresa_id = v_empresa_id
      and p.user_id = p_user_id
      and p.herramienta = v_codigo
      and p.permitido
  );
end
$$;

create or replace function public.appgt_acceso_herramientas_actual_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_rol text := public.appgt_rol_empresa_actual();
begin
  if v_empresa_id is null or v_rol is null then
    raise exception 'active company membership required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'empresa_id', v_empresa_id,
    'rol', v_rol,
    'herramientas', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'codigo', x.codigo,
        'habilitada_empresa', public.appgt_herramienta_empresa_habilitada_v1(
          v_empresa_id, x.codigo
        ),
        'permitida_usuario', case when v_rol = 'ADMIN' then true else coalesce(p.permitido, false) end,
        'habilitada', public.appgt_usuario_puede_herramienta_v1(x.codigo, auth.uid())
      ) order by x.orden), '[]'::jsonb)
      from (values
        (1, 'ZUMAC_CONSULTOR'),
        (2, 'ZUMAC_CREATOR'),
        (3, 'ZUMAC_METRICS'),
        (4, 'ZUMAC_ALERTS'),
        (5, 'ZUMAC_ACTIONS')
      ) x(orden, codigo)
      left join public."PERMISOS_HERRAMIENTAS_USUARIO_APPGT" p
        on p.empresa_id = v_empresa_id
       and p.user_id = auth.uid()
       and p.herramienta = x.codigo
    )
  );
end
$$;

create or replace function public.appgt_catalogo_permisos_herramientas_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_rol text := public.appgt_rol_empresa_actual();
begin
  if v_empresa_id is null or v_rol not in ('ADMIN', 'GESTOR') then
    raise exception 'permission manager role required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'herramientas', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'codigo', x.codigo,
        'nombre', x.nombre,
        'descripcion', x.descripcion,
        'habilitada_empresa', public.appgt_herramienta_empresa_habilitada_v1(
          v_empresa_id, x.codigo
        ),
        'delegable', public.appgt_herramienta_empresa_habilitada_v1(
          v_empresa_id, x.codigo
        ) and (
          v_rol = 'ADMIN'
          or public.appgt_usuario_puede_herramienta_v1(x.codigo, auth.uid())
        )
      ) order by x.orden), '[]'::jsonb)
      from (values
        (1, 'ZUMAC_CONSULTOR', 'Consultor', 'Consultas sobre los datos de la empresa.'),
        (2, 'ZUMAC_CREATOR', 'Creator', 'Creación y edición de la estructura de la empresa.'),
        (3, 'ZUMAC_METRICS', 'Metrics', 'Dashboards, indicadores y análisis visual.'),
        (4, 'ZUMAC_ALERTS', 'Alerts', 'Vigilancia de condiciones y anomalías.'),
        (5, 'ZUMAC_ACTIONS', 'Actions', 'Tareas, aprobaciones y evidencias.')
      ) x(orden, codigo, nombre, descripcion)
    )
  );
end
$$;

create or replace function public.appgt_permisos_herramientas_usuario_v1(
  p_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_actor_role text := public.appgt_rol_empresa_actual();
  v_target_role text := public.appgt_rol_empresa(v_empresa_id, p_user_id);
begin
  if v_empresa_id is null or v_actor_role not in ('ADMIN', 'GESTOR') then
    raise exception 'permission manager role required' using errcode = '42501';
  end if;
  if p_user_id <> auth.uid()
     and not public.appgt_actor_puede_gestionar_usuario(v_empresa_id, p_user_id)
     and not (v_actor_role = 'ADMIN' and v_target_role = 'ADMIN') then
    raise exception 'target user is outside delegated authority' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'user_id', p_user_id,
    'permisos_herramientas', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'herramienta', x.codigo,
        'permitido', case when v_target_role = 'ADMIN' then true else coalesce(p.permitido, false) end
      ) order by x.orden), '[]'::jsonb)
      from (values
        (1, 'ZUMAC_CONSULTOR'),
        (2, 'ZUMAC_CREATOR'),
        (3, 'ZUMAC_METRICS'),
        (4, 'ZUMAC_ALERTS'),
        (5, 'ZUMAC_ACTIONS')
      ) x(orden, codigo)
      left join public."PERMISOS_HERRAMIENTAS_USUARIO_APPGT" p
        on p.empresa_id = v_empresa_id
       and p.user_id = p_user_id
       and p.herramienta = x.codigo
    )
  );
end
$$;

create or replace function public.appgt_guardar_permisos_herramientas_v1(
  p_user_id uuid,
  p_permisos jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_actor_role text := public.appgt_rol_empresa_actual();
  v_target_role text := public.appgt_rol_empresa(v_empresa_id, p_user_id);
  v_item jsonb;
  v_codigo text;
  v_permitido boolean;
  v_count integer := 0;
begin
  if v_empresa_id is null or v_actor_role not in ('ADMIN', 'GESTOR') then
    raise exception 'permission manager role required' using errcode = '42501';
  end if;
  if not public.appgt_actor_puede_gestionar_usuario(v_empresa_id, p_user_id) then
    raise exception 'target user is outside delegated authority' using errcode = '42501';
  end if;
  if v_target_role is null then
    raise exception 'assign a company role before permissions';
  end if;
  if v_target_role = 'ADMIN' then
    raise exception 'ADMIN access is implicit and protected' using errcode = '42501';
  end if;
  if jsonb_typeof(p_permisos) <> 'array' then
    raise exception 'p_permisos must be a JSON array';
  end if;

  for v_item in select value from jsonb_array_elements(p_permisos)
  loop
    v_codigo := upper(btrim(coalesce(v_item->>'herramienta', '')));
    v_permitido := coalesce((v_item->>'permitido')::boolean, false);
    if v_codigo not in (
      'ZUMAC_CONSULTOR', 'ZUMAC_CREATOR', 'ZUMAC_METRICS',
      'ZUMAC_ALERTS', 'ZUMAC_ACTIONS'
    ) then
      raise exception 'invalid workspace tool: %', v_codigo;
    end if;
    if v_permitido and not public.appgt_herramienta_empresa_habilitada_v1(
      v_empresa_id, v_codigo
    ) then
      raise exception 'tool is not enabled for the company: %', v_codigo;
    end if;
    if v_actor_role = 'GESTOR'
       and not public.appgt_usuario_puede_herramienta_v1(v_codigo, auth.uid()) then
      raise exception 'tool is outside delegated authority: %', v_codigo
        using errcode = '42501';
    end if;

    insert into public."PERMISOS_HERRAMIENTAS_USUARIO_APPGT"(
      empresa_id, user_id, herramienta, permitido, otorgado_por
    ) values (
      v_empresa_id, p_user_id, v_codigo, v_permitido, auth.uid()
    )
    on conflict (empresa_id, user_id, herramienta) do update set
      permitido = excluded.permitido,
      otorgado_por = auth.uid(),
      updated_at = now();
    v_count := v_count + 1;
  end loop;

  perform public.appgt_incrementar_revision_permisos(v_empresa_id);
  return jsonb_build_object('guardado', true, 'cantidad', v_count);
end
$$;

-- La asistencia necesita un directorio mínimo de personal aunque el usuario no
-- tenga permiso para abrir el formato completo de planilla. El RPC solo expone
-- filas activas de la empresa y exige acceso al formato de asistencia.
create or replace function public.appgt_personal_asistencia_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
begin
  if v_empresa_id is null then
    raise exception 'active company membership required' using errcode = '42501';
  end if;
  if not public.appgt_es_admin_empresa(v_empresa_id)
     and not public.appgt_puede_accion_tabla_v1('GT-ASISTENCIA_PERSONAL', 'VER')
     and not public.appgt_puede_accion_tabla_v1('GT-ASISTENCIA_PERSONAL', 'INSERTAR') then
    raise exception 'attendance permission required' using errcode = '42501';
  end if;
  return (
    select coalesce(jsonb_agg(persona.data), '[]'::jsonb)
    from (
      select to_jsonb(p) as data
      from public."GH-REGISTRO_PERSONAL_PLANILLA" p
      where p.empresa_id = v_empresa_id
        and coalesce(p.activo, true)
        and not coalesce(p.eliminado, false)
        and p.deleted_at is null
        and upper(btrim(coalesce(p."Status", 'ACTIVO')))
            not in ('INACTIVO', 'CESADO', 'BAJA')
      order by coalesce(p."Apellidos y Nombres", p."Nombres", ''), p."Dni"
    ) persona
  );
end
$$;

revoke all on function public.appgt_herramienta_empresa_habilitada_v1(uuid,text)
  from public, anon;
revoke all on function public.appgt_usuario_puede_herramienta_v1(text,uuid)
  from public, anon;
revoke all on function public.appgt_acceso_herramientas_actual_v1()
  from public, anon;
revoke all on function public.appgt_catalogo_permisos_herramientas_v1()
  from public, anon;
revoke all on function public.appgt_permisos_herramientas_usuario_v1(uuid)
  from public, anon;
revoke all on function public.appgt_guardar_permisos_herramientas_v1(uuid,jsonb)
  from public, anon;
revoke all on function public.appgt_personal_asistencia_v1()
  from public, anon;

grant execute on function public.appgt_usuario_puede_herramienta_v1(text,uuid)
  to authenticated;
grant execute on function public.appgt_acceso_herramientas_actual_v1()
  to authenticated;
grant execute on function public.appgt_catalogo_permisos_herramientas_v1()
  to authenticated;
grant execute on function public.appgt_permisos_herramientas_usuario_v1(uuid)
  to authenticated;
grant execute on function public.appgt_guardar_permisos_herramientas_v1(uuid,jsonb)
  to authenticated;
grant execute on function public.appgt_personal_asistencia_v1()
  to authenticated;

notify pgrst, 'reload schema';
commit;
