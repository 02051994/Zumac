begin;

-- La version 026 consultaba PERFILES_APPGT, una tabla que no existe en este
-- proyecto. Al ejecutar el RPC, Postgres lanzaba 42P01 y la portada interpretaba
-- el error como Metrics deshabilitado. Se conserva la misma respuesta y se usa
-- el directorio canonico de perfiles.
create or replace function public.appgt_metrics_contexto_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa_id uuid:=public.appgt_empresa_actual_id();
  v_enabled boolean;
  v_manage boolean;
begin
  if v_empresa_id is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select habilitar_zumac_metrics into v_enabled
  from public."EMPRESAS_APPGT" where id=v_empresa_id and activo;
  v_manage:=public.appgt_puede_gestionar_configuracion(v_empresa_id);
  return jsonb_build_object(
    'empresa_id',v_empresa_id,
    'metrics_habilitado',coalesce(v_enabled,false),
    'puede_gestionar',v_manage,
    'usuarios',case when v_manage then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,
        'nombres',p.nombres,
        'apellidos',concat_ws(' ',p.apellido_paterno,p.apellido_materno),
        'email',''
      ) order by p.nombres,p.apellido_paterno,p.apellido_materno)
      from public."PERFILES_DE_USUARIOS_APPGT" p
      where p.empresa_id=v_empresa_id and coalesce(p.activo,true)
    ),'[]'::jsonb) else '[]'::jsonb end,
    'fuentes',coalesce((
      select jsonb_agg(source order by source->>'nombre') from (
        select jsonb_build_object(
          'tabla',ft.tabla_destino,
          'nombre',coalesce(nullif(f.nombre,''),nullif(ft.nombre,''),ft.tabla_destino),
          'formato_id',ft.formato_id,
          'modulo_id',f.modulo_id,
          'campos',coalesce((
            select jsonb_agg(jsonb_build_object(
              'campo',c.campo,
              'etiqueta',coalesce(nullif(c.etiqueta,''),c.campo),
              'tipo',coalesce(nullif(c.tipo,''),'text')
            ) order by c.orden,c.campo)
            from public."MATRIZ_CAMPOS_FORMATO_APPGT" c
            join information_schema.columns pc
              on pc.table_schema='public'
              and pc.table_name=ft.tabla_destino
              and pc.column_name=c.campo
            where c.empresa_id=v_empresa_id
              and c.tabla_destino=ft.tabla_destino
              and coalesce(c.activo,true)
              and not coalesce(c.eliminado,false)
          ),'[]'::jsonb)
        ) source
        from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
        left join public."MATRIZ_FORMATOS_APPGT" f
          on f.empresa_id=ft.empresa_id and f.id=ft.formato_id
        where ft.empresa_id=v_empresa_id
          and coalesce(ft.activo,true)
          and ft.deleted_at is null
          and public.appgt_tabla_alertable_v1(v_empresa_id,ft.tabla_destino)
        group by ft.tabla_destino,ft.nombre,f.nombre,ft.formato_id,f.modulo_id
      ) sources
    ),'[]'::jsonb)
  );
end
$$;

revoke all on function public.appgt_metrics_contexto_v1() from public,anon;
grant execute on function public.appgt_metrics_contexto_v1() to authenticated;

commit;
