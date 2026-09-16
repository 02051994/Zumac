begin;

-- Conserva la implementación probada y coloca delante un control estricto.
-- Gestionar configuración no concede acceso operativo a los datos.
alter function public.appgt_select_format_records(text,text,integer,integer)
  rename to appgt_select_format_records_internal_v1;

revoke all on function public.appgt_select_format_records_internal_v1(
  text,text,integer,integer
) from public,anon,authenticated,service_role;

create function public.appgt_select_format_records(
  p_format_id text,
  p_table_name text,
  p_limit integer default null,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa_id uuid:=public.appgt_empresa_actual_id();
begin
  if auth.role() <> 'service_role'
     and not public.appgt_es_admin_empresa(v_empresa_id)
     and not exists (
       select 1
       from public."PERMISOS_DE_USUARIOS_APPGT" p
       join public."MATRIZ_FORMATOS_APPGT" f
         on f.empresa_id=p.empresa_id and f.id=p.formato
       where p.empresa_id=v_empresa_id and p.user_id=auth.uid()
         and p.formato=p_format_id and coalesce(p.can_view,false)
         and coalesce(p.activo,true) and not coalesce(p.eliminado,false)
         and p.deleted_at is null
         and coalesce(f.activo,true) and not coalesce(f.eliminado,false)
         and f.deleted_at is null
         and (
           f.tabla_destino=p_table_name
           or exists (
             select 1 from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
             where ft.empresa_id=v_empresa_id and ft.formato_id=f.id
               and ft.tabla_destino=p_table_name
               and coalesce(ft.activo,true)
               and not coalesce(ft.eliminado,false)
               and ft.deleted_at is null
           )
         )
     ) then
    raise exception 'Usuario sin permiso de visualización para el formato %',
      p_format_id using errcode='42501';
  end if;
  return public.appgt_select_format_records_internal_v1(
    p_format_id,p_table_name,p_limit,p_offset
  );
end
$$;

revoke all on function public.appgt_select_format_records(
  text,text,integer,integer
) from public,anon;
grant execute on function public.appgt_select_format_records(
  text,text,integer,integer
) to authenticated,service_role;

alter function public.fn_importar_registros_sin_duplicados(text,jsonb,text[])
  rename to fn_importar_registros_sin_duplicados_internal_v1;

revoke all on function public.fn_importar_registros_sin_duplicados_internal_v1(
  text,jsonb,text[]
) from public,anon,authenticated,service_role;

create function public.fn_importar_registros_sin_duplicados(
  p_tabla text,
  p_registros jsonb,
  p_ignorar_campos text[] default array[
    'id','ID','id_local','ID_LOCAL','ID_REGISTRO','id_registro',
    'hash_fila_sin_ids','HASH_FILA_SIN_IDS','ID_FILA_SERIAL','id_fila_serial',
    'PK_ID','pk_id','ID_PK','id_pk','empresa_id','EMPRESA_ID',
    'created_at','updated_at','creado_en','actualizado_en','created_by',
    'updated_by','user_id','estado_sync','eliminado','activo'
  ]
)
returns table(
  filas_recibidas integer,
  filas_insertadas integer,
  filas_omitidas integer
)
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa_id uuid:=public.appgt_empresa_actual_id();
begin
  if auth.role() <> 'service_role'
     and not public.appgt_es_admin_empresa(v_empresa_id)
     and not exists (
       select 1
       from public."PERMISOS_DE_USUARIOS_APPGT" p
       join public."MATRIZ_FORMATOS_APPGT" f
         on f.empresa_id=p.empresa_id and f.id=p.formato
       where p.empresa_id=v_empresa_id and p.user_id=auth.uid()
         and coalesce(p.can_import,false)
         and coalesce(p.activo,true) and not coalesce(p.eliminado,false)
         and p.deleted_at is null
         and coalesce(f.activo,true) and not coalesce(f.eliminado,false)
         and f.deleted_at is null
         and (
           f.tabla_destino=p_tabla
           or exists (
             select 1 from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
             where ft.empresa_id=v_empresa_id and ft.formato_id=f.id
               and ft.tabla_destino=p_tabla
               and coalesce(ft.activo,true)
               and not coalesce(ft.eliminado,false)
               and ft.deleted_at is null
           )
         )
     ) then
    raise exception 'Usuario sin permiso de importación para %',p_tabla
      using errcode='42501';
  end if;
  return query
  select * from public.fn_importar_registros_sin_duplicados_internal_v1(
    p_tabla,p_registros,p_ignorar_campos
  );
end
$$;

revoke all on function public.fn_importar_registros_sin_duplicados(
  text,jsonb,text[]
) from public,anon;
grant execute on function public.fn_importar_registros_sin_duplicados(
  text,jsonb,text[]
) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
