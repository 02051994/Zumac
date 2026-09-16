begin;

-- Gobierno de permisos por empresa.
-- La fuente única del rol es USUARIOS_EMPRESAS_APPGT. El rol ADMIN se crea
-- únicamente desde Supabase/service_role; la aplicación nunca puede promover
-- un usuario a ADMIN.

alter table public."PERMISOS_DE_USUARIOS_APPGT"
  add column if not exists otorgado_por uuid references auth.users(id) on delete set null,
  add column if not exists otorgado_at timestamptz,
  add column if not exists version_permiso bigint not null default 1;

create table if not exists public."APPGT_REVISIONES_PERMISOS_EMPRESA" (
  empresa_id uuid primary key references public."EMPRESAS_APPGT"(id) on delete cascade,
  revision bigint not null default 1,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

insert into public."APPGT_REVISIONES_PERMISOS_EMPRESA"(empresa_id)
select id from public."EMPRESAS_APPGT"
on conflict (empresa_id) do nothing;

alter table public."APPGT_REVISIONES_PERMISOS_EMPRESA" enable row level security;
revoke all on table public."APPGT_REVISIONES_PERMISOS_EMPRESA"
  from public, anon, authenticated;

create or replace function public.appgt_rol_empresa(
  p_empresa_id uuid,
  p_user_id uuid default auth.uid()
)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select ue.rol
  from public."USUARIOS_EMPRESAS_APPGT" ue
  where ue.user_id = p_user_id
    and ue.empresa_id = p_empresa_id
    and ue.activo
  limit 1
$$;

create or replace function public.appgt_rol_empresa_actual()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.appgt_rol_empresa(public.appgt_empresa_actual_id(), auth.uid())
$$;

create or replace function public.appgt_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.appgt_rol_empresa_actual() = 'ADMIN', false)
$$;

create or replace function public.appgt_puede_gestionar_permisos_empresa(
  p_empresa_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.appgt_rol_empresa(p_empresa_id, auth.uid())
    in ('ADMIN', 'GESTOR'), false)
$$;

create or replace function public.appgt_incrementar_revision_permisos(
  p_empresa_id uuid
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revision bigint;
begin
  insert into public."APPGT_REVISIONES_PERMISOS_EMPRESA"(
    empresa_id, revision, updated_at, updated_by
  ) values (
    p_empresa_id, 1, now(), auth.uid()
  )
  on conflict (empresa_id) do update set
    revision = public."APPGT_REVISIONES_PERMISOS_EMPRESA".revision + 1,
    updated_at = now(),
    updated_by = auth.uid()
  returning revision into v_revision;
  return v_revision;
end
$$;

revoke all on function public.appgt_incrementar_revision_permisos(uuid)
  from public, anon, authenticated;

create or replace function public.appgt_actor_puede_gestionar_usuario(
  p_empresa_id uuid,
  p_target_user_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_role text := public.appgt_rol_empresa(p_empresa_id, auth.uid());
  v_target_role text := public.appgt_rol_empresa(p_empresa_id, p_target_user_id);
begin
  if auth.uid() is null or p_target_user_id is null
     or p_target_user_id = auth.uid() then
    return false;
  end if;
  if v_actor_role = 'ADMIN' then
    return v_target_role is null or v_target_role <> 'ADMIN';
  end if;
  if v_actor_role = 'GESTOR' then
    return v_target_role is null or v_target_role in ('COLABORADOR', 'VISUALIZADOR');
  end if;
  return false;
end
$$;

-- Esta función se invoca con service_role desde Supabase. No se concede a
-- authenticated, por lo que ningún ADMIN de la aplicación puede crear otro
-- ADMIN ni salir del límite de su empresa.
create or replace function public.appgt_supabase_asignar_admin_empresa_v1(
  p_user_id uuid,
  p_empresa_id uuid,
  p_predeterminada boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'auth user not found';
  end if;
  if not exists (
    select 1 from public."EMPRESAS_APPGT" where id = p_empresa_id and activo
  ) then
    raise exception 'active company not found';
  end if;
  if p_predeterminada then
    update public."USUARIOS_EMPRESAS_APPGT"
    set es_predeterminada = false, updated_at = now()
    where user_id = p_user_id and empresa_id <> p_empresa_id;
  end if;
  insert into public."USUARIOS_EMPRESAS_APPGT"(
    user_id, empresa_id, rol, es_predeterminada, activo
  ) values (
    p_user_id, p_empresa_id, 'ADMIN', p_predeterminada, true
  )
  on conflict (user_id, empresa_id) do update set
    rol = 'ADMIN',
    es_predeterminada = excluded.es_predeterminada,
    activo = true,
    updated_at = now()
  returning id into v_id;
  perform public.appgt_incrementar_revision_permisos(p_empresa_id);
  return jsonb_build_object(
    'guardado', true,
    'membresia_id', v_id,
    'empresa_id', p_empresa_id,
    'user_id', p_user_id,
    'rol', 'ADMIN'
  );
end
$$;

revoke all on function public.appgt_supabase_asignar_admin_empresa_v1(
  uuid,uuid,boolean
) from public, anon, authenticated;
grant execute on function public.appgt_supabase_asignar_admin_empresa_v1(
  uuid,uuid,boolean
) to service_role;

comment on function public.appgt_supabase_asignar_admin_empresa_v1(uuid,uuid,boolean)
is 'Crea o actualiza el ADMIN de una empresa. Solo service_role/Supabase.';

create or replace function public.appgt_seleccionar_empresa_v1(
  p_empresa_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public."USUARIOS_EMPRESAS_APPGT" ue
    join public."EMPRESAS_APPGT" e on e.id = ue.empresa_id and e.activo
    where ue.user_id = auth.uid() and ue.empresa_id = p_empresa_id and ue.activo
  ) then
    raise exception 'company membership required' using errcode = '42501';
  end if;
  update public."USUARIOS_EMPRESAS_APPGT"
  set es_predeterminada = (empresa_id = p_empresa_id), updated_at = now()
  where user_id = auth.uid() and activo;
  return jsonb_build_object('seleccionada', true, 'empresa_id', p_empresa_id);
end
$$;

revoke all on function public.appgt_seleccionar_empresa_v1(uuid)
  from public, anon;
grant execute on function public.appgt_seleccionar_empresa_v1(uuid)
  to authenticated;

create or replace function public.appgt_mis_empresas_v1()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'empresa_actual_id', public.appgt_empresa_actual_id(),
    'empresas', coalesce(jsonb_agg(jsonb_build_object(
      'id', e.id,
      'codigo', e.codigo,
      'nombre', e.nombre,
      'rol', ue.rol,
      'es_predeterminada', ue.es_predeterminada
    ) order by ue.es_predeterminada desc, e.nombre), '[]'::jsonb)
  )
  from public."USUARIOS_EMPRESAS_APPGT" ue
  join public."EMPRESAS_APPGT" e on e.id = ue.empresa_id and e.activo
  where ue.user_id = auth.uid() and ue.activo
$$;

revoke all on function public.appgt_mis_empresas_v1() from public, anon;
grant execute on function public.appgt_mis_empresas_v1() to authenticated;

create or replace function public.appgt_contexto_gestion_permisos_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_actor_role text := public.appgt_rol_empresa_actual();
  v_revision bigint := 1;
begin
  if v_empresa_id is null or v_actor_role not in ('ADMIN', 'GESTOR') then
    raise exception 'permission manager role required' using errcode = '42501';
  end if;
  select revision into v_revision
  from public."APPGT_REVISIONES_PERMISOS_EMPRESA"
  where empresa_id = v_empresa_id;

  return jsonb_build_object(
    'empresa', (
      select jsonb_build_object('id', e.id, 'codigo', e.codigo, 'nombre', e.nombre)
      from public."EMPRESAS_APPGT" e where e.id = v_empresa_id
    ),
    'actor', jsonb_build_object(
      'user_id', auth.uid(),
      'rol', v_actor_role,
      'puede_crear_admin', false,
      'roles_delegables', case when v_actor_role = 'ADMIN'
        then jsonb_build_array('GESTOR','COLABORADOR','VISUALIZADOR')
        else jsonb_build_array('COLABORADOR','VISUALIZADOR') end
    ),
    'revision_permisos', coalesce(v_revision, 1),
    'usuarios', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', p.id,
        'nombres', p.nombres,
        'cargo', p.cargo,
        'area', p.area,
        'dni', p."DNI",
        'activo', coalesce(p.activo, true),
        'rol', ue.rol,
        'membresia_activa', coalesce(ue.activo, false),
        'puede_gestionar', case
          when p.id = auth.uid() then false
          when v_actor_role = 'ADMIN' then coalesce(ue.rol, '') <> 'ADMIN'
          else coalesce(ue.rol, 'COLABORADOR') in ('COLABORADOR','VISUALIZADOR')
        end,
        'cantidad_formatos', coalesce((
          select count(*) from public."PERMISOS_DE_USUARIOS_APPGT" fp
          where fp.empresa_id = v_empresa_id and fp.user_id = p.id
            and coalesce(fp.activo, true) and not coalesce(fp.eliminado, false)
            and fp.deleted_at is null and coalesce(fp.can_view, false)
        ), 0)
      ) order by coalesce(p.nombres, ''), p.id::text)
      from public."PERFILES_DE_USUARIOS_APPGT" p
      left join public."USUARIOS_EMPRESAS_APPGT" ue
        on ue.user_id = p.id and ue.empresa_id = v_empresa_id
      where p.empresa_id = v_empresa_id
        and coalesce(p.activo, true)
        and not coalesce(p.eliminado, false)
        and p.deleted_at is null
        and (
          v_actor_role = 'ADMIN'
          or p.id = auth.uid()
          or ue.rol in ('COLABORADOR','VISUALIZADOR')
          or ue.rol is null
        )
    ), '[]'::jsonb),
    'secciones', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.orden, s.nombre, s.id)
      from public."MATRIZ_SECCIONES_APPGT" s
      where s.empresa_id = v_empresa_id
        and coalesce(s.activo, true) and not coalesce(s.eliminado, false)
        and s.deleted_at is null
        and (
          v_actor_role = 'ADMIN'
          or exists (
            select 1
            from public."MATRIZ_MODULOS_APPGT" m
            join public."MATRIZ_FORMATOS_APPGT" f
              on f.empresa_id = m.empresa_id and f.modulo_id = m.id
            join public."PERMISOS_DE_USUARIOS_APPGT" gp
              on gp.empresa_id = f.empresa_id and gp.user_id = auth.uid()
             and gp.formato = f.id
            where m.empresa_id = s.empresa_id and m.seccion = s.id
              and coalesce(gp.activo, true) and not coalesce(gp.eliminado, false)
              and gp.deleted_at is null and coalesce(gp.can_view, false)
          )
        )
    ), '[]'::jsonb),
    'modulos', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.orden, m.nombre, m.id)
      from public."MATRIZ_MODULOS_APPGT" m
      where m.empresa_id = v_empresa_id
        and coalesce(m.activo, true) and not coalesce(m.eliminado, false)
        and m.deleted_at is null
        and (
          v_actor_role = 'ADMIN'
          or exists (
            select 1 from public."MATRIZ_FORMATOS_APPGT" f
            join public."PERMISOS_DE_USUARIOS_APPGT" gp
              on gp.empresa_id = f.empresa_id and gp.user_id = auth.uid()
             and gp.formato = f.id
            where f.empresa_id = m.empresa_id and f.modulo_id = m.id
              and coalesce(gp.activo, true) and not coalesce(gp.eliminado, false)
              and gp.deleted_at is null and coalesce(gp.can_view, false)
          )
        )
    ), '[]'::jsonb),
    'formatos', coalesce((
      select jsonb_agg(
        to_jsonb(f) || jsonb_build_object(
          'acciones_delegables', case when v_actor_role = 'ADMIN'
            then jsonb_build_object(
              'can_view', true, 'can_insert', true, 'can_update', true,
              'can_delete', true, 'can_export', true, 'can_import', true,
              'can_review', true, 'can_approve', true
            ) else jsonb_build_object(
              'can_view', coalesce(gp.can_view, false),
              'can_insert', coalesce(gp.can_insert, false),
              'can_update', coalesce(gp.can_update, false),
              'can_delete', coalesce(gp.can_delete, false),
              'can_export', coalesce(gp.can_export, false),
              'can_import', coalesce(gp.can_import, false),
              'can_review', false,
              'can_approve', false
            ) end
        ) order by f.orden, f.nombre, f.id
      )
      from public."MATRIZ_FORMATOS_APPGT" f
      left join public."PERMISOS_DE_USUARIOS_APPGT" gp
        on gp.empresa_id = f.empresa_id and gp.user_id = auth.uid()
       and gp.formato = f.id and coalesce(gp.activo, true)
       and not coalesce(gp.eliminado, false) and gp.deleted_at is null
      where f.empresa_id = v_empresa_id
        and coalesce(f.activo, true) and not coalesce(f.eliminado, false)
        and f.deleted_at is null
        and (v_actor_role = 'ADMIN' or coalesce(gp.can_view, false))
    ), '[]'::jsonb)
  );
end
$$;

create or replace function public.appgt_acceso_usuario_v2(
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
  if v_empresa_id is null or v_actor_role not in ('ADMIN','GESTOR') then
    raise exception 'permission manager role required' using errcode = '42501';
  end if;
  if p_user_id <> auth.uid()
     and not public.appgt_actor_puede_gestionar_usuario(v_empresa_id, p_user_id)
     and not (v_actor_role = 'ADMIN' and v_target_role = 'ADMIN') then
    raise exception 'target user is outside delegated authority' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'user_id', p_user_id,
    'rol', v_target_role,
    'permisos_formatos', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.seccion, p.modulo, p.formato)
      from public."PERMISOS_DE_USUARIOS_APPGT" p
      where p.empresa_id = v_empresa_id and p.user_id = p_user_id
        and coalesce(p.activo, true) and not coalesce(p.eliminado, false)
        and p.deleted_at is null
    ), '[]'::jsonb)
  );
end
$$;

create or replace function public.appgt_asignar_rol_empresa_v2(
  p_user_id uuid,
  p_rol text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_actor_role text := public.appgt_rol_empresa_actual();
  v_role text := upper(btrim(coalesce(p_rol, '')));
  v_existing_role text := public.appgt_rol_empresa(v_empresa_id, p_user_id);
  v_id uuid;
begin
  if v_empresa_id is null or v_actor_role not in ('ADMIN','GESTOR') then
    raise exception 'permission manager role required' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'cannot change own role' using errcode = '42501';
  end if;
  if v_role = 'ADMIN' then
    raise exception 'ADMIN can only be assigned from Supabase' using errcode = '42501';
  end if;
  if v_role not in ('GESTOR','COLABORADOR','VISUALIZADOR') then
    raise exception 'invalid company role';
  end if;
  if v_existing_role = 'ADMIN' then
    raise exception 'ADMIN memberships are protected' using errcode = '42501';
  end if;
  if v_actor_role = 'GESTOR' and v_role not in ('COLABORADOR','VISUALIZADOR') then
    raise exception 'GESTOR can only assign COLABORADOR or VISUALIZADOR'
      using errcode = '42501';
  end if;
  if v_actor_role = 'GESTOR'
     and v_existing_role is not null
     and v_existing_role not in ('COLABORADOR','VISUALIZADOR') then
    raise exception 'target user is outside delegated authority'
      using errcode = '42501';
  end if;
  if not exists (
    select 1 from public."PERFILES_DE_USUARIOS_APPGT" p
    where p.id = p_user_id and p.empresa_id = v_empresa_id
      and coalesce(p.activo, true) and not coalesce(p.eliminado, false)
      and p.deleted_at is null
  ) then
    raise exception 'target profile does not belong to the active company';
  end if;

  insert into public."USUARIOS_EMPRESAS_APPGT"(
    user_id, empresa_id, rol, es_predeterminada, activo
  ) values (
    p_user_id, v_empresa_id, v_role,
    not exists (
      select 1 from public."USUARIOS_EMPRESAS_APPGT" x
      where x.user_id = p_user_id and x.activo and x.es_predeterminada
    ), true
  )
  on conflict (user_id, empresa_id) do update set
    rol = excluded.rol, activo = true, updated_at = now()
  returning id into v_id;

  if v_role = 'VISUALIZADOR' then
    update public."PERMISOS_DE_USUARIOS_APPGT"
    set can_insert=false, can_update=false, can_delete=false,
        can_export=false, can_import=false, can_review=false, can_approve=false,
        updated_at=now(), version_permiso=version_permiso+1
    where empresa_id=v_empresa_id and user_id=p_user_id;
  elsif v_role = 'COLABORADOR' then
    update public."PERMISOS_DE_USUARIOS_APPGT"
    set can_review=false, can_approve=false,
        updated_at=now(), version_permiso=version_permiso+1
    where empresa_id=v_empresa_id and user_id=p_user_id;
  end if;
  perform public.appgt_incrementar_revision_permisos(v_empresa_id);
  return jsonb_build_object(
    'guardado', true, 'membresia_id', v_id,
    'user_id', p_user_id, 'empresa_id', v_empresa_id, 'rol', v_role
  );
end
$$;

create or replace function public.appgt_guardar_permisos_formatos_v1(
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
  v_format record;
  v_own public."PERMISOS_DE_USUARIOS_APPGT"%rowtype;
  v_id text;
  v_view boolean;
  v_insert boolean;
  v_update boolean;
  v_delete boolean;
  v_export boolean;
  v_import boolean;
  v_review boolean;
  v_approve boolean;
  v_count integer := 0;
begin
  if v_empresa_id is null or v_actor_role not in ('ADMIN','GESTOR') then
    raise exception 'permission manager role required' using errcode = '42501';
  end if;
  if not public.appgt_actor_puede_gestionar_usuario(v_empresa_id, p_user_id) then
    raise exception 'target user is outside delegated authority' using errcode = '42501';
  end if;
  if v_target_role is null then
    raise exception 'assign a company role before permissions';
  end if;
  if jsonb_typeof(p_permisos) <> 'array' then
    raise exception 'p_permisos must be a JSON array';
  end if;
  if jsonb_array_length(p_permisos) > 1000 then
    raise exception 'permission batch limit exceeded';
  end if;

  for v_item in select value from jsonb_array_elements(p_permisos)
  loop
    select
      f.id as formato_id,
      f.modulo_id,
      m.seccion as seccion_id,
      coalesce(ft.tabla_destino, f.tabla_destino) as tabla_destino
    into v_format
    from public."MATRIZ_FORMATOS_APPGT" f
    join public."MATRIZ_MODULOS_APPGT" m
      on m.empresa_id=f.empresa_id and m.id=f.modulo_id
    left join lateral (
      select x.tabla_destino
      from public."MATRIZ_FORMATO_TABLAS_APPGT" x
      where x.empresa_id=f.empresa_id and x.formato_id=f.id
        and coalesce(x.activo,true) and x.deleted_at is null
      order by x.orden, x.id limit 1
    ) ft on true
    where f.empresa_id=v_empresa_id
      and f.id=coalesce(v_item->>'formato_id', v_item->>'formato')
      and coalesce(f.activo,true) and not coalesce(f.eliminado,false)
      and f.deleted_at is null
      and coalesce(m.activo,true) and not coalesce(m.eliminado,false)
      and m.deleted_at is null
    limit 1;
    if v_format.formato_id is null or v_format.tabla_destino is null then
      raise exception 'active format hierarchy not found: %',
        coalesce(v_item->>'formato_id', v_item->>'formato');
    end if;

    v_insert := coalesce((v_item->>'can_insert')::boolean, false);
    v_update := coalesce((v_item->>'can_update')::boolean, false);
    v_delete := coalesce((v_item->>'can_delete')::boolean, false);
    v_export := coalesce((v_item->>'can_export')::boolean, false);
    v_import := coalesce((v_item->>'can_import')::boolean, false);
    v_review := coalesce((v_item->>'can_review')::boolean, false);
    v_approve := coalesce((v_item->>'can_approve')::boolean, false);
    v_view := coalesce((v_item->>'can_view')::boolean, false)
      or v_insert or v_update or v_delete or v_export or v_import
      or v_review or v_approve;

    if v_target_role = 'VISUALIZADOR' then
      v_insert:=false; v_update:=false; v_delete:=false;
      v_export:=false; v_import:=false; v_review:=false; v_approve:=false;
    elsif v_target_role = 'COLABORADOR' then
      v_review:=false; v_approve:=false;
    end if;

    if v_actor_role = 'GESTOR' then
      select * into v_own
      from public."PERMISOS_DE_USUARIOS_APPGT" p
      where p.empresa_id=v_empresa_id and p.user_id=auth.uid()
        and p.formato=v_format.formato_id
        and coalesce(p.activo,true) and not coalesce(p.eliminado,false)
        and p.deleted_at is null
      order by p.updated_at desc nulls last limit 1;
      if v_own.id is null
         or (v_view and not coalesce(v_own.can_view,false))
         or (v_insert and not coalesce(v_own.can_insert,false))
         or (v_update and not coalesce(v_own.can_update,false))
         or (v_delete and not coalesce(v_own.can_delete,false))
         or (v_export and not coalesce(v_own.can_export,false))
         or (v_import and not coalesce(v_own.can_import,false)) then
        raise exception 'GESTOR cannot delegate permissions outside own scope'
          using errcode = '42501';
      end if;
      v_review:=false; v_approve:=false;
    end if;

    select p.id into v_id
    from public."PERMISOS_DE_USUARIOS_APPGT" p
    where p.empresa_id=v_empresa_id and p.user_id=p_user_id
      and p.modulo=v_format.modulo_id and p.formato=v_format.formato_id
    order by p.updated_at desc nulls last limit 1;

    if v_id is null then
      insert into public."PERMISOS_DE_USUARIOS_APPGT"(
        empresa_id,user_id,seccion,modulo,formato,tabla_destino,
        can_view,can_insert,can_update,can_delete,can_export,can_import,
        can_review,can_approve,activo,eliminado,deleted_at,
        otorgado_por,otorgado_at,version_permiso
      ) values (
        v_empresa_id,p_user_id,v_format.seccion_id,v_format.modulo_id,
        v_format.formato_id,v_format.tabla_destino,
        v_view,v_insert,v_update,v_delete,v_export,v_import,v_review,v_approve,
        true,false,null,auth.uid(),now(),1
      ) returning id into v_id;
    else
      update public."PERMISOS_DE_USUARIOS_APPGT"
      set seccion=v_format.seccion_id, tabla_destino=v_format.tabla_destino,
          can_view=v_view, can_insert=v_insert, can_update=v_update,
          can_delete=v_delete, can_export=v_export, can_import=v_import,
          can_review=v_review, can_approve=v_approve,
          activo=true, eliminado=false, deleted_at=null,
          otorgado_por=auth.uid(), otorgado_at=now(),
          version_permiso=version_permiso+1, updated_at=now()
      where id=v_id;
    end if;
    v_count := v_count + 1;
  end loop;
  perform public.appgt_incrementar_revision_permisos(v_empresa_id);
  return jsonb_build_object(
    'guardado', true, 'formatos_actualizados', v_count,
    'revision_permisos', (
      select revision from public."APPGT_REVISIONES_PERMISOS_EMPRESA"
      where empresa_id=v_empresa_id
    )
  );
end
$$;

create or replace function public.appgt_revocar_permisos_formatos_v1(
  p_user_id uuid,
  p_formatos text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_actor_role text := public.appgt_rol_empresa_actual();
  v_format text;
  v_count integer := 0;
begin
  if not public.appgt_actor_puede_gestionar_usuario(v_empresa_id, p_user_id) then
    raise exception 'target user is outside delegated authority' using errcode='42501';
  end if;
  foreach v_format in array coalesce(p_formatos, array[]::text[])
  loop
    if v_actor_role = 'GESTOR' and not exists (
      select 1 from public."PERMISOS_DE_USUARIOS_APPGT" ownp
      where ownp.empresa_id=v_empresa_id and ownp.user_id=auth.uid()
        and ownp.formato=v_format and coalesce(ownp.can_view,false)
        and coalesce(ownp.activo,true) and not coalesce(ownp.eliminado,false)
        and ownp.deleted_at is null
    ) then
      raise exception 'GESTOR cannot revoke outside own scope' using errcode='42501';
    end if;
    update public."PERMISOS_DE_USUARIOS_APPGT"
    set activo=false, eliminado=true, deleted_at=now(), updated_at=now(),
        otorgado_por=auth.uid(), otorgado_at=now(),
        version_permiso=version_permiso+1
    where empresa_id=v_empresa_id and user_id=p_user_id and formato=v_format
      and coalesce(activo,true) and not coalesce(eliminado,false);
    v_count := v_count + case when found then 1 else 0 end;
  end loop;
  if v_count > 0 then
    perform public.appgt_incrementar_revision_permisos(v_empresa_id);
  end if;
  return jsonb_build_object('revocado', true, 'formatos_revocados', v_count);
end
$$;

-- Catálogo y acceso compatibles con clientes anteriores, ahora limitados por
-- empresa y por la autoridad delegada del actor.
create or replace function public.appgt_admin_permission_catalog_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_context jsonb;
begin
  v_context := public.appgt_contexto_gestion_permisos_v2();
  return jsonb_build_object(
    'secciones', v_context->'secciones',
    'modulos', v_context->'modulos',
    'formatos', v_context->'formatos'
  );
end
$$;

create or replace function public.appgt_admin_user_access_v1(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.appgt_acceso_usuario_v2(p_user_id)
    || jsonb_build_object('permisos_secciones', '[]'::jsonb)
$$;

create or replace function public.appgt_admin_upsert_user_permission_v3(
  p_user_id uuid,p_modulo text,p_formato text,p_can_view boolean,
  p_can_insert boolean,p_can_update boolean,p_can_delete boolean,
  p_can_export boolean default false,p_can_import boolean default false
)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.appgt_guardar_permisos_formatos_v1(
    p_user_id,
    jsonb_build_array(jsonb_build_object(
      'formato_id', p_formato, 'can_view', p_can_view,
      'can_insert', p_can_insert, 'can_update', p_can_update,
      'can_delete', p_can_delete, 'can_export', p_can_export,
      'can_import', p_can_import, 'can_review', false, 'can_approve', false
    ))
  ) || jsonb_build_object('modulo',p_modulo,'formato',p_formato)
$$;

create or replace function public.appgt_admin_upsert_user_permission_v4(
  p_user_id uuid,p_modulo text,p_formato text,p_can_view boolean,
  p_can_insert boolean,p_can_update boolean,p_can_delete boolean,
  p_can_export boolean default false,p_can_import boolean default false,
  p_can_review boolean default false,p_can_approve boolean default false
)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.appgt_guardar_permisos_formatos_v1(
    p_user_id,
    jsonb_build_array(jsonb_build_object(
      'formato_id', p_formato, 'can_view', p_can_view,
      'can_insert', p_can_insert, 'can_update', p_can_update,
      'can_delete', p_can_delete, 'can_export', p_can_export,
      'can_import', p_can_import, 'can_review', p_can_review,
      'can_approve', p_can_approve
    ))
  ) || jsonb_build_object('modulo',p_modulo,'formato',p_formato)
$$;

create or replace function public.appgt_admin_upsert_user_permission(
  p_user_id uuid,p_modulo text,p_formato text,p_can_view boolean,
  p_can_insert boolean,p_can_update boolean,p_can_delete boolean,
  p_can_export boolean default false,p_can_import boolean default false
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.appgt_guardar_permisos_formatos_v1(
    p_user_id,
    jsonb_build_array(jsonb_build_object(
      'formato_id', p_formato, 'can_view', p_can_view,
      'can_insert', p_can_insert, 'can_update', p_can_update,
      'can_delete', p_can_delete, 'can_export', p_can_export,
      'can_import', p_can_import, 'can_review', false, 'can_approve', false
    ))
  );
end
$$;

create or replace function public.appgt_admin_delete_user_permission(
  p_user_id uuid,p_modulo text,p_formato text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.appgt_revocar_permisos_formatos_v1(
    p_user_id, array[p_formato]
  );
end
$$;

create or replace function public.appgt_admin_list_profiles()
returns table(id uuid,nombres text,cargo text,area text,activo boolean,dni text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_actor_role text := public.appgt_rol_empresa_actual();
begin
  if v_actor_role not in ('ADMIN','GESTOR') then
    raise exception 'permission manager role required' using errcode='42501';
  end if;
  return query
  select p.id,p.nombres,p.cargo,p.area,p.activo,p."DNI"
  from public."PERFILES_DE_USUARIOS_APPGT" p
  left join public."USUARIOS_EMPRESAS_APPGT" ue
    on ue.user_id=p.id and ue.empresa_id=v_empresa_id
  where p.empresa_id=v_empresa_id
    and coalesce(p.activo,true) and not coalesce(p.eliminado,false)
    and p.deleted_at is null
    and (
      v_actor_role='ADMIN' or p.id=auth.uid()
      or ue.rol in ('COLABORADOR','VISUALIZADOR') or ue.rol is null
    )
  order by p.nombres;
end
$$;

create or replace function public.appgt_admin_list_user_permissions(
  p_user_id uuid
)
returns table(
  id text,user_id uuid,modulo text,formato text,can_view boolean,
  can_insert boolean,can_update boolean,can_delete boolean,
  can_export boolean,can_import boolean,created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_empresa_id uuid := public.appgt_empresa_actual_id();
begin
  if not public.appgt_actor_puede_gestionar_usuario(v_empresa_id,p_user_id)
     and p_user_id <> auth.uid() then
    raise exception 'target user is outside delegated authority' using errcode='42501';
  end if;
  return query
  select p.id,p.user_id,p.modulo,p.formato,
    coalesce(p.can_view,false),coalesce(p.can_insert,false),
    coalesce(p.can_update,false),coalesce(p.can_delete,false),
    coalesce(p.can_export,false),coalesce(p.can_import,false),p.created_at
  from public."PERMISOS_DE_USUARIOS_APPGT" p
  where p.empresa_id=v_empresa_id and p.user_id=p_user_id
    and coalesce(p.activo,true) and not coalesce(p.eliminado,false)
    and p.deleted_at is null
  order by p.modulo,p.formato;
end
$$;

-- Cierra escritura directa. Las mutaciones pasan por RPCs que aplican empresa,
-- jerarquía de rol, alcance y auditoría.
drop policy if exists usuarios_empresas_admin_all
  on public."USUARIOS_EMPRESAS_APPGT";
revoke insert,update,delete on public."USUARIOS_EMPRESAS_APPGT"
  from authenticated;
revoke insert,update,delete on public."PERMISOS_DE_USUARIOS_APPGT"
  from authenticated;
revoke insert,update,delete on public."PERMISOS_SECCIONES_APPGT"
  from authenticated;

drop trigger if exists trg_appgt_audit
  on public."USUARIOS_EMPRESAS_APPGT";
create trigger trg_appgt_audit
after insert or update or delete on public."USUARIOS_EMPRESAS_APPGT"
for each row execute function public.appgt_audit_trigger();

-- Todas las decisiones genéricas de tabla quedan limitadas a la empresa activa.
create or replace function public.appgt_formatos_por_tabla(p_table_name text)
returns table(formato text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select distinct f.id::text
  from public."MATRIZ_FORMATOS_APPGT" f
  where f.empresa_id=public.appgt_empresa_actual_id()
    and f.tabla_destino=p_table_name
    and coalesce(f.activo,true) and not coalesce(f.eliminado,false)
    and f.deleted_at is null
  union
  select distinct ft.formato_id::text
  from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
  where ft.empresa_id=public.appgt_empresa_actual_id()
    and ft.tabla_destino=p_table_name
    and coalesce(ft.activo,true) and not coalesce(ft.eliminado,false)
    and ft.deleted_at is null
$$;

create or replace function public.appgt_can_table(
  p_table_name text,
  p_action text
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when auth.uid() is null or public.appgt_empresa_actual_id() is null then false
    when public.appgt_es_admin_empresa(public.appgt_empresa_actual_id()) then true
    else exists (
      select 1
      from public."PERMISOS_DE_USUARIOS_APPGT" p
      where p.empresa_id=public.appgt_empresa_actual_id()
        and p.user_id=auth.uid()
        and p.formato in (
          select x.formato from public.appgt_formatos_por_tabla(p_table_name) x
        )
        and coalesce(p.activo,true) and not coalesce(p.eliminado,false)
        and p.deleted_at is null
        and case lower(btrim(coalesce(p_action,'view')))
          when 'view' then coalesce(p.can_view,false)
          when 'select' then coalesce(p.can_view,false)
          when 'insert' then coalesce(p.can_insert,false)
          when 'update' then coalesce(p.can_update,false)
          when 'delete' then coalesce(p.can_delete,false)
          when 'import' then coalesce(p.can_import,false)
          when 'export' then coalesce(p.can_export,false)
          else false
        end
    )
  end
$$;

create or replace function public.appgt_puede_accion_tabla_v1(
  p_tabla text,
  p_accion text
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when auth.uid() is null or public.appgt_empresa_actual_id() is null then false
    when public.appgt_es_admin_empresa(public.appgt_empresa_actual_id()) then true
    else exists (
      select 1
      from public."PERMISOS_DE_USUARIOS_APPGT" p
      where p.empresa_id=public.appgt_empresa_actual_id()
        and p.user_id=auth.uid()
        and coalesce(p.activo,true) and not coalesce(p.eliminado,false)
        and p.deleted_at is null
        and public.appgt_normalizar_clave(coalesce(p.tabla_destino,''))
            = public.appgt_normalizar_clave(p_tabla)
        and case upper(btrim(coalesce(p_accion,'')))
          when 'VER' then coalesce(p.can_view,false)
          when 'INSERTAR' then coalesce(p.can_insert,false)
          when 'ACTUALIZAR' then coalesce(p.can_update,false)
          when 'ELIMINAR' then coalesce(p.can_delete,false)
          when 'IMPORTAR' then coalesce(p.can_import,false)
          when 'EXPORTAR' then coalesce(p.can_export,false)
          when 'REVISAR' then coalesce(p.can_review,false)
          when 'APROBAR' then coalesce(p.can_approve,false)
          else false
        end
    )
  end
$$;

revoke all on function public.appgt_rol_empresa(uuid,uuid) from public,anon;
revoke all on function public.appgt_rol_empresa_actual() from public,anon;
revoke all on function public.appgt_puede_gestionar_permisos_empresa(uuid)
  from public,anon;
revoke all on function public.appgt_actor_puede_gestionar_usuario(uuid,uuid)
  from public,anon;
revoke all on function public.appgt_contexto_gestion_permisos_v2()
  from public,anon;
revoke all on function public.appgt_acceso_usuario_v2(uuid)
  from public,anon;
revoke all on function public.appgt_asignar_rol_empresa_v2(uuid,text)
  from public,anon;
revoke all on function public.appgt_guardar_permisos_formatos_v1(uuid,jsonb)
  from public,anon;
revoke all on function public.appgt_revocar_permisos_formatos_v1(uuid,text[])
  from public,anon;

grant execute on function public.appgt_rol_empresa(uuid,uuid) to authenticated;
grant execute on function public.appgt_rol_empresa_actual() to authenticated;
grant execute on function public.appgt_puede_gestionar_permisos_empresa(uuid)
  to authenticated;
grant execute on function public.appgt_actor_puede_gestionar_usuario(uuid,uuid)
  to authenticated;
grant execute on function public.appgt_contexto_gestion_permisos_v2()
  to authenticated;
grant execute on function public.appgt_acceso_usuario_v2(uuid)
  to authenticated;
grant execute on function public.appgt_asignar_rol_empresa_v2(uuid,text)
  to authenticated;
grant execute on function public.appgt_guardar_permisos_formatos_v1(uuid,jsonb)
  to authenticated;
grant execute on function public.appgt_revocar_permisos_formatos_v1(uuid,text[])
  to authenticated;

revoke all on function public.appgt_admin_delete_user_permission(uuid,text,text)
  from public,anon;
revoke all on function public.appgt_admin_list_profiles() from public,anon;
revoke all on function public.appgt_admin_list_user_permissions(uuid)
  from public,anon;
revoke all on function public.appgt_admin_upsert_user_permission_v3(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean
) from public,anon;
revoke all on function public.appgt_admin_upsert_user_permission_v4(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean
) from public,anon;
revoke all on function public.appgt_admin_upsert_user_permission(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean
) from public,anon;

grant execute on function public.appgt_admin_delete_user_permission(uuid,text,text)
  to authenticated;
grant execute on function public.appgt_admin_list_profiles() to authenticated;
grant execute on function public.appgt_admin_list_user_permissions(uuid)
  to authenticated;
grant execute on function public.appgt_admin_upsert_user_permission_v3(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean
) to authenticated;
grant execute on function public.appgt_admin_upsert_user_permission_v4(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean
) to authenticated;
grant execute on function public.appgt_admin_upsert_user_permission(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean
) to authenticated;

notify pgrst, 'reload schema';
commit;
