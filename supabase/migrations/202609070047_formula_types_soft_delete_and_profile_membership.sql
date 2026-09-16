begin;

-- El editor conserva cadenas vacías para controles opcionales. Antes de usar
-- jsonb_populate_record se eliminan únicamente cuando la columna real no es de
-- texto, evitando errores como: invalid input syntax for type numeric: "".
create or replace function public.appgt_expandir_campo_desde_borrador()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payload jsonb;
  v_key text;
  v_value text;
  v_type_category "char";
begin
  select b.definicion
  into v_payload
  from public."BORRADORES_CONFIGURACION_APPGT" b
  where b.empresa_id = new.empresa_id
    and b.entidad_tipo = 'CAMPO'
    and b.codigo = new.id
    and b.deleted_at is null
    and b.definicion ->> 'tabla_destino' = new.tabla_destino
    and b.definicion ->> 'campo' = new.campo
  order by b.updated_at desc
  limit 1;

  if v_payload is null then
    return new;
  end if;

  for v_key, v_value in
    select entry.key, entry.value #>> '{}'
    from jsonb_each(v_payload) entry
    where jsonb_typeof(entry.value) = 'string'
  loop
    if btrim(coalesce(v_value, '')) = ''
       or upper(btrim(coalesce(v_value, ''))) in ('NULL', 'EMPTY') then
      select t.typcategory
      into v_type_category
      from pg_attribute a
      join pg_type t on t.oid = a.atttypid
      where a.attrelid = 'public."MATRIZ_CAMPOS_FORMATO_APPGT"'::regclass
        and a.attname = v_key
        and a.attnum > 0
        and not a.attisdropped;

      if v_type_category is not null and v_type_category <> 'S' then
        v_payload := v_payload - v_key;
      end if;
    end if;
  end loop;

  v_payload := v_payload - array[
    'id', 'empresa_id', 'tabla_destino', 'campo', 'created_at',
    'updated_at', 'deleted_at', 'created_by', 'updated_by',
    'estado_sync', 'eliminado'
  ];
  new := jsonb_populate_record(new, jsonb_strip_nulls(v_payload));
  return new;
end
$$;

create or replace function public.appgt_formula_to_numeric(p_value text)
returns numeric language sql immutable as $$
  select nullif(btrim(p_value), '')::numeric;
$$;

create or replace function public.appgt_formula_to_bigint(p_value text)
returns bigint language sql immutable as $$
  select nullif(btrim(p_value), '')::numeric::bigint;
$$;

create or replace function public.appgt_formula_to_boolean(p_value text)
returns boolean language plpgsql immutable as $$
declare v_value text := lower(btrim(coalesce(p_value, '')));
begin
  if v_value = '' then return null; end if;
  if v_value in ('true', 't', '1', 'si', 'sí', 'yes') then return true; end if;
  if v_value in ('false', 'f', '0', 'no') then return false; end if;
  raise exception 'invalid boolean formula value: %', p_value;
end $$;

create or replace function public.appgt_formula_to_date(p_value text)
returns date language sql immutable as $$
  select nullif(btrim(p_value), '')::date;
$$;

create or replace function public.appgt_formula_to_time(p_value text)
returns time language sql immutable as $$
  select nullif(btrim(p_value), '')::time;
$$;

create or replace function public.appgt_formula_to_timestamptz(p_value text)
returns timestamptz language sql stable as $$
  select nullif(btrim(p_value), '')::timestamptz;
$$;

create or replace function public.appgt_formula_to_jsonb(p_value text)
returns jsonb language sql immutable as $$
  select nullif(btrim(p_value), '')::jsonb;
$$;

-- `tipo` define el dato almacenado; `tipo_ui` solo define el control visual.
-- Así una misma UI de fórmula puede producir texto, número, fecha, hora,
-- fecha-hora, booleano o JSON sin alterar el significado del campo.
create or replace function public.appgt_ajustar_tipo_fisico_campo()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tipo text := lower(btrim(coalesce(new.tipo, 'text')));
  v_sql_type text;
  v_expected_udt text;
  v_current_udt text;
begin
  if lower(coalesce(new.tipo_ui, '')) not in ('formula', 'lookup')
     or new.tabla_destino is null
     or new.campo is null
     or to_regclass(format('public.%I', new.tabla_destino)) is null then
    return new;
  end if;

  v_sql_type := case
    when v_tipo in (
      'number', 'numeric', 'decimal', 'double', 'float', 'real',
      'percent', 'currency', 'money'
    ) then 'numeric'
    when v_tipo in ('integer', 'int', 'bigint', 'boolean_int', 'boolean_01')
      then 'bigint'
    when v_tipo = 'date' then 'date'
    when v_tipo = 'time' then 'time'
    when v_tipo in ('datetime', 'timestamp', 'timestamptz') then 'timestamptz'
    when v_tipo in ('boolean', 'bool') then 'boolean'
    when v_tipo in ('json', 'jsonb') then 'jsonb'
    else 'text'
  end;
  v_expected_udt := case v_sql_type
    when 'bigint' then 'int8'
    when 'boolean' then 'bool'
    else v_sql_type
  end;

  select t.typname
  into v_current_udt
  from pg_attribute a
  join pg_type t on t.oid = a.atttypid
  where a.attrelid = to_regclass(format('public.%I', new.tabla_destino))
    and a.attname = new.campo
    and a.attnum > 0
    and not a.attisdropped;

  if v_current_udt is null or v_current_udt = v_expected_udt then
    return new;
  end if;

  begin
    case v_sql_type
    when 'numeric' then execute format(
      'alter table public.%1$I alter column %2$I type numeric using public.appgt_formula_to_numeric(%2$I::text)',
      new.tabla_destino, new.campo
    );
    when 'bigint' then execute format(
      'alter table public.%1$I alter column %2$I type bigint using public.appgt_formula_to_bigint(%2$I::text)',
      new.tabla_destino, new.campo
    );
    when 'boolean' then execute format(
      'alter table public.%1$I alter column %2$I type boolean using public.appgt_formula_to_boolean(%2$I::text)',
      new.tabla_destino, new.campo
    );
    when 'date' then execute format(
      'alter table public.%1$I alter column %2$I type date using public.appgt_formula_to_date(%2$I::text)',
      new.tabla_destino, new.campo
    );
    when 'time' then execute format(
      'alter table public.%1$I alter column %2$I type time using public.appgt_formula_to_time(%2$I::text)',
      new.tabla_destino, new.campo
    );
    when 'timestamptz' then execute format(
      'alter table public.%1$I alter column %2$I type timestamptz using public.appgt_formula_to_timestamptz(%2$I::text)',
      new.tabla_destino, new.campo
    );
    when 'jsonb' then execute format(
      'alter table public.%1$I alter column %2$I type jsonb using public.appgt_formula_to_jsonb(%2$I::text)',
      new.tabla_destino, new.campo
    );
    else execute format(
      'alter table public.%1$I alter column %2$I type text using %2$I::text',
      new.tabla_destino, new.campo
    );
    end case;
  exception
    when feature_not_supported or dependent_objects_still_exist then
      -- Columnas estructurales usadas por RLS, vistas o constraints no deben
      -- cambiar de tipo por una preferencia visual del Creator. Se conserva el
      -- tipo físico y continúa la publicación del resto de campos.
      raise notice 'APPGT: se conserva el tipo de %.% porque tiene dependencias',
        new.tabla_destino, new.campo;
  end;
  return new;
end
$$;

-- No se republican masivamente configuraciones históricas: algunas contienen
-- datos deliberadamente mixtos (por ejemplo, "300 kg" en un campo marcado como
-- numeric). La función corregida se aplica al publicar o editar cada campo sin
-- arriesgar cambios destructivos en columnas existentes.

create or replace function public.appgt_rol_desde_cargo(p_cargo text)
returns text
language sql
immutable
as $$
  select case
    when upper(btrim(coalesce(p_cargo, ''))) in ('ADMIN', 'ADMINISTRADOR', 'ADMINISTRADORA')
      then 'ADMIN'
    when upper(btrim(coalesce(p_cargo, ''))) in ('GESTOR', 'GESTORA')
      then 'GESTOR'
    when upper(btrim(coalesce(p_cargo, ''))) in ('VISUALIZADOR', 'LECTOR', 'CONSULTA')
      then 'VISUALIZADOR'
    else 'COLABORADOR'
  end;
$$;

-- Auth + perfil no era suficiente: todas las funciones de permisos obtienen la
-- empresa desde USUARIOS_EMPRESAS_APPGT. Esta función mantiene ambas entidades
-- sincronizadas sin sobrescribir un rol que el administrador ya asignó allí.
create or replace function public.appgt_sincronizar_membresia_desde_perfil()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_activo boolean := coalesce(new.activo, true)
    and not coalesce(new.eliminado, false)
    and new.deleted_at is null;
  v_predeterminada boolean;
begin
  if new.id is null or new.empresa_id is null
     or not exists (select 1 from auth.users u where u.id = new.id) then
    return new;
  end if;

  if tg_op = 'UPDATE' and old.empresa_id is distinct from new.empresa_id then
    update public."USUARIOS_EMPRESAS_APPGT"
    set activo = false, updated_at = now()
    where user_id = old.id and empresa_id = old.empresa_id;
  end if;

  if not v_activo then
    update public."USUARIOS_EMPRESAS_APPGT"
    set activo = false, updated_at = now()
    where user_id = new.id and empresa_id = new.empresa_id;
    return new;
  end if;

  select not exists (
    select 1 from public."USUARIOS_EMPRESAS_APPGT" ue
    where ue.user_id = new.id and ue.activo and ue.es_predeterminada
  ) into v_predeterminada;

  insert into public."USUARIOS_EMPRESAS_APPGT" (
    user_id, empresa_id, rol, es_predeterminada, activo
  ) values (
    new.id, new.empresa_id, public.appgt_rol_desde_cargo(new.cargo),
    v_predeterminada, true
  )
  on conflict (user_id, empresa_id) do nothing;
  return new;
end
$$;

drop trigger if exists appgt_sincronizar_membresia_desde_perfil_trigger
  on public."PERFILES_DE_USUARIOS_APPGT";
create trigger appgt_sincronizar_membresia_desde_perfil_trigger
after insert or update of cargo, empresa_id, activo, eliminado, deleted_at
on public."PERFILES_DE_USUARIOS_APPGT"
for each row execute function public.appgt_sincronizar_membresia_desde_perfil();

-- Repara perfiles ya creados (incluido el usuario Gestor descrito en el caso).
insert into public."USUARIOS_EMPRESAS_APPGT" (
  user_id, empresa_id, rol, es_predeterminada, activo
)
select
  p.id,
  p.empresa_id,
  public.appgt_rol_desde_cargo(p.cargo),
  not exists (
    select 1 from public."USUARIOS_EMPRESAS_APPGT" existing
    where existing.user_id = p.id
      and existing.activo
      and existing.es_predeterminada
  ),
  true
from public."PERFILES_DE_USUARIOS_APPGT" p
join auth.users u on u.id = p.id
where coalesce(p.activo, true)
  and not coalesce(p.eliminado, false)
  and p.deleted_at is null
  and not exists (
    select 1 from public."USUARIOS_EMPRESAS_APPGT" existing
    where existing.user_id = p.id and existing.empresa_id = p.empresa_id
  )
on conflict (user_id, empresa_id) do nothing;

-- Respaldo de lectura durante despliegues: si un perfil válido aún no pasó por
-- el trigger, la sesión puede resolver su empresa y completar el arranque.
create or replace function public.appgt_empresa_actual_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select candidate.empresa_id
  from (
    select ue.empresa_id, 0 as source_order,
           case when ue.es_predeterminada then 0 else 1 end as preferred,
           ue.created_at
    from public."USUARIOS_EMPRESAS_APPGT" ue
    where ue.user_id = auth.uid() and ue.activo
    union all
    select p.empresa_id, 1, 1, p.created_at
    from public."PERFILES_DE_USUARIOS_APPGT" p
    where p.id = auth.uid()
      and coalesce(p.activo, true)
      and not coalesce(p.eliminado, false)
      and p.deleted_at is null
      and not exists (
        select 1 from public."USUARIOS_EMPRESAS_APPGT" any_membership
        where any_membership.user_id = p.id
      )
  ) candidate
  join public."EMPRESAS_APPGT" e
    on e.id = candidate.empresa_id and e.activo
  order by candidate.source_order, candidate.preferred, candidate.created_at
  limit 1;
$$;

revoke all on function public.appgt_empresa_actual_id() from public, anon;
grant execute on function public.appgt_empresa_actual_id() to authenticated;

notify pgrst, 'reload schema';
commit;
