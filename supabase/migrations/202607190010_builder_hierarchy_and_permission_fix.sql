begin;

-- La jerarquía viva conserva el rubro explícitamente. Esto permite filtrar el
-- constructor sin depender de nombres técnicos ni de varias uniones en Flutter.
alter table public."MATRIZ_MODULOS_APPGT"
  add column if not exists rubro_id text references public."RUBROS_APPGT"(id),
  add column if not exists icono text;
alter table public."MATRIZ_FORMATOS_APPGT"
  add column if not exists rubro_id text references public."RUBROS_APPGT"(id);
alter table public."MATRIZ_FORMATO_TABLAS_APPGT"
  add column if not exists rubro_id text references public."RUBROS_APPGT"(id);
alter table public."MATRIZ_SECCIONES_APPGT"
  add column if not exists color text;

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

update public."MATRIZ_SECCIONES_APPGT" s
set color = nullif(p.definicion ->> 'color', '')
from public."PLANTILLAS_CONFIGURACION_APPGT" p
where p.empresa_id = s.empresa_id
  and p.entidad_tipo = 'SECCION'
  and p.entidad_origen_id = s.id
  and p.es_actual
  and p.activo
  and p.deleted_at is null
  and nullif(p.definicion ->> 'color', '') is not null;

update public."MATRIZ_MODULOS_APPGT" m
set icono = nullif(p.definicion ->> 'icono', '')
from public."PLANTILLAS_CONFIGURACION_APPGT" p
where p.empresa_id = m.empresa_id
  and p.entidad_tipo = 'MODULO'
  and p.entidad_origen_id = m.id
  and p.es_actual
  and p.activo
  and p.deleted_at is null
  and nullif(p.definicion ->> 'icono', '') is not null;

create index if not exists idx_modulos_appgt_empresa_rubro
  on public."MATRIZ_MODULOS_APPGT" (empresa_id, rubro_id, orden);
create index if not exists idx_formatos_appgt_empresa_rubro
  on public."MATRIZ_FORMATOS_APPGT" (empresa_id, rubro_id, modulo_id, orden);
create index if not exists idx_formato_tablas_appgt_empresa_rubro
  on public."MATRIZ_FORMATO_TABLAS_APPGT"
  (empresa_id, rubro_id, formato_id, orden);

create or replace function public.appgt_asignar_rubro_jerarquia()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rubro_id text;
begin
  if tg_table_name = 'MATRIZ_MODULOS_APPGT' then
    select s.rubro_id into v_rubro_id
    from public."MATRIZ_SECCIONES_APPGT" s
    where s.empresa_id = new.empresa_id and s.id = new.seccion
    limit 1;
  elsif tg_table_name = 'MATRIZ_FORMATOS_APPGT' then
    select m.rubro_id into v_rubro_id
    from public."MATRIZ_MODULOS_APPGT" m
    where m.empresa_id = new.empresa_id and m.id = new.modulo_id
    limit 1;
  elsif tg_table_name = 'MATRIZ_FORMATO_TABLAS_APPGT' then
    select f.rubro_id into v_rubro_id
    from public."MATRIZ_FORMATOS_APPGT" f
    where f.empresa_id = new.empresa_id and f.id = new.formato_id
    limit 1;
  end if;
  new.rubro_id := coalesce(v_rubro_id, new.rubro_id);
  return new;
end
$$;

-- La publicación base histórica no incluía el color de sección ni el icono de
-- módulo. Se completan desde el borrador antes de insertar o versionar la fila.
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
  end if;
  return new;
end
$$;

drop trigger if exists appgt_00_asignar_rubro_jerarquia_trigger
  on public."MATRIZ_MODULOS_APPGT";
create trigger appgt_00_asignar_rubro_jerarquia_trigger
before insert or update on public."MATRIZ_MODULOS_APPGT"
for each row execute function public.appgt_asignar_rubro_jerarquia();

drop trigger if exists appgt_00_expandir_navegacion_trigger
  on public."MATRIZ_SECCIONES_APPGT";
create trigger appgt_00_expandir_navegacion_trigger
before insert on public."MATRIZ_SECCIONES_APPGT"
for each row execute function public.appgt_expandir_navegacion_desde_borrador();

drop trigger if exists appgt_00_expandir_navegacion_trigger
  on public."MATRIZ_MODULOS_APPGT";
create trigger appgt_00_expandir_navegacion_trigger
before insert on public."MATRIZ_MODULOS_APPGT"
for each row execute function public.appgt_expandir_navegacion_desde_borrador();

drop trigger if exists appgt_00_asignar_rubro_jerarquia_trigger
  on public."MATRIZ_FORMATOS_APPGT";
create trigger appgt_00_asignar_rubro_jerarquia_trigger
before insert or update on public."MATRIZ_FORMATOS_APPGT"
for each row execute function public.appgt_asignar_rubro_jerarquia();

drop trigger if exists appgt_00_asignar_rubro_jerarquia_trigger
  on public."MATRIZ_FORMATO_TABLAS_APPGT";
create trigger appgt_00_asignar_rubro_jerarquia_trigger
before insert or update on public."MATRIZ_FORMATO_TABLAS_APPGT"
for each row execute function public.appgt_asignar_rubro_jerarquia();

-- Guarda permisos con los identificadores canónicos del formato y módulo. La
-- tabla se obtiene de la estructura publicada, incluida una tabla recién creada.
create or replace function public.appgt_admin_upsert_user_permission_v2(
  p_user_id uuid,
  p_modulo text,
  p_formato text,
  p_can_view boolean,
  p_can_insert boolean,
  p_can_update boolean,
  p_can_delete boolean,
  p_can_export boolean default false,
  p_can_import boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_id uuid;
  v_seccion_id text;
  v_modulo_id text;
  v_formato_id text;
  v_tabla_destino text;
begin
  if v_empresa_id is null or not public.appgt_es_admin_empresa(v_empresa_id) then
    raise exception 'administrator permission required' using errcode = '42501';
  end if;
  if not public.appgt_validar_usuario_permisos_empresa(v_empresa_id, p_user_id) then
    raise exception 'target user does not belong to the active company';
  end if;

  select
    m.seccion,
    m.id,
    f.id,
    coalesce(t.tabla_destino, f.tabla_destino)
  into v_seccion_id, v_modulo_id, v_formato_id, v_tabla_destino
  from public."MATRIZ_FORMATOS_APPGT" f
  join public."MATRIZ_MODULOS_APPGT" m
    on m.empresa_id = f.empresa_id and m.id = f.modulo_id
  left join lateral (
    select ft.tabla_destino
    from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
    where ft.empresa_id = f.empresa_id
      and ft.formato_id = f.id
      and coalesce(ft.activo, true)
      and ft.deleted_at is null
    order by ft.orden, ft.id
    limit 1
  ) t on true
  where f.empresa_id = v_empresa_id
    and (f.id = p_formato or f.tabla_destino = p_formato)
    and (f.modulo_id = p_modulo or m.id = p_modulo)
    and coalesce(f.activo, true)
    and coalesce(m.activo, true)
  limit 1;

  if v_seccion_id is null or v_tabla_destino is null then
    raise exception 'active format/module/table hierarchy not found';
  end if;

  select p.id into v_id
  from public."PERMISOS_DE_USUARIOS_APPGT" p
  where p.empresa_id = v_empresa_id
    and p.user_id = p_user_id
    and p.modulo = v_modulo_id
    and p.formato = v_formato_id
  order by p.updated_at desc nulls last
  limit 1;

  if v_id is null then
    insert into public."PERMISOS_DE_USUARIOS_APPGT" (
      empresa_id, user_id, seccion, modulo, formato, tabla_destino,
      can_view, can_insert, can_update, can_delete, can_export, can_import,
      activo, eliminado
    ) values (
      v_empresa_id, p_user_id, v_seccion_id, v_modulo_id, v_formato_id,
      v_tabla_destino, p_can_view, p_can_insert, p_can_update, p_can_delete,
      p_can_export, p_can_import, true, false
    ) returning id into v_id;
  else
    update public."PERMISOS_DE_USUARIOS_APPGT" set
      seccion = v_seccion_id,
      tabla_destino = v_tabla_destino,
      can_view = p_can_view,
      can_insert = p_can_insert,
      can_update = p_can_update,
      can_delete = p_can_delete,
      can_export = p_can_export,
      can_import = p_can_import,
      activo = true,
      eliminado = false,
      updated_at = now()
    where id = v_id;
  end if;

  return jsonb_build_object(
    'id', v_id,
    'guardado', true,
    'modulo', v_modulo_id,
    'formato', v_formato_id,
    'tabla_destino', v_tabla_destino
  );
end
$$;

revoke all on function public.appgt_asignar_rubro_jerarquia()
  from public, anon, authenticated;
revoke all on function public.appgt_expandir_navegacion_desde_borrador()
  from public, anon, authenticated;
revoke all on function public.appgt_admin_upsert_user_permission_v2(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean
) from public, anon;
grant execute on function public.appgt_admin_upsert_user_permission_v2(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean
) to authenticated;

commit;
