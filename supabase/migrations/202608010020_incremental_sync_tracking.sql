begin;

-- Instala seguimiento de cambios en todas las matrices y tablas operativas
-- conocidas. Esto permite que "Actualizar datos" sea incremental incluso
-- cuando un administrador edita una fila directamente en Supabase.
create or replace function public.appgt_instalar_seguimiento_tablas_v1()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_table_name text;
  v_table regclass;
  v_tracking_trigger text;
  v_updated_trigger text;
  v_installed integer := 0;
begin
  for v_table_name in
    select distinct candidate.table_name
    from (
      select unnest(array[
        'MATRIZ_CAMPOS_FORMATO_APPGT',
        'MATRIZ_FORMATOS_APPGT',
        'MATRIZ_FORMATO_TABLAS_APPGT',
        'MATRIZ_MODULOS_APPGT',
        'MATRIZ_SECCIONES_APPGT',
        'MATRIZ_VISTAS_DINAMICAS_APPGT',
        'MATRIZ_FORMATOS_ESPECIALES_APPGT',
        'MATRIZ_DROPDOWNS_APPGT',
        'MATRIZ_VALIDACIONES_APPGT',
        'MATRIZ_CONDICIONES_APPGT',
        'MATRIZ_FORMULAS_APPGT',
        'MATRIZ_ESTADOS_FLUJO_APPGT',
        'PERFILES_DE_USUARIOS_APPGT',
        'PERMISOS_DE_USUARIOS_APPGT',
        'PERMISOS_SECCIONES_APPGT',
        'LOTES_VARIEDADES_GT',
        'SN-MATRIZ_CONCEPTOS_ESTADIOS_PLAGAS',
        'SN-MATRIZ_ETAPAS_FENOLOGICAS',
        'SN-MATRIZ_ESTADIOS_CONTEO_FRUTA'
      ])::text as table_name

      union

      select nullif(btrim(f.tabla_destino::text), '')
      from public."MATRIZ_FORMATOS_APPGT" f

      union

      select nullif(btrim(ft.tabla_destino::text), '')
      from public."MATRIZ_FORMATO_TABLAS_APPGT" ft

      union

      select nullif(btrim(c.tabla_destino::text), '')
      from public."MATRIZ_CAMPOS_FORMATO_APPGT" c

      union

      select nullif(
        split_part(
          trim(both '[]' from btrim(c.id_campo_dropdown::text)),
          '.',
          1
        ),
        ''
      )
      from public."MATRIZ_CAMPOS_FORMATO_APPGT" c
      where c.id_campo_dropdown is not null
        and position('.' in c.id_campo_dropdown::text) > 0
    ) candidate
    where candidate.table_name is not null
      and candidate.table_name <> ''
      -- La bitácora no puede vigilarse a sí misma: cada INSERT produciría otro
      -- INSERT idéntico hasta agotar la pila de PostgreSQL.
      and candidate.table_name <> 'APPGT_TABLAS_CAMBIADAS'
  loop
    v_table := to_regclass(format('public.%I', v_table_name));
    if v_table is null then
      continue;
    end if;

    if to_regprocedure('public.appgt_registrar_tabla_modificada()') is not null
       and not exists (
         select 1
         from pg_trigger t
         join pg_proc p on p.oid = t.tgfoid
         join pg_namespace n on n.oid = p.pronamespace
         where t.tgrelid = v_table
           and not t.tgisinternal
           and n.nspname = 'public'
           and p.proname = 'appgt_registrar_tabla_modificada'
       ) then
      v_tracking_trigger :=
        'appgt_track_' || substr(md5(v_table_name), 1, 24);
      execute format(
        'create trigger %I after insert or update or delete on public.%I for each row execute function public.appgt_registrar_tabla_modificada()',
        v_tracking_trigger,
        v_table_name
      );
      v_installed := v_installed + 1;
    end if;

    if to_regprocedure('public.appgt_set_updated_at()') is not null
       and exists (
         select 1
         from pg_attribute a
         where a.attrelid = v_table
           and a.attname = 'updated_at'
           and a.attnum > 0
           and not a.attisdropped
       )
       and not exists (
         select 1
         from pg_trigger t
         join pg_proc p on p.oid = t.tgfoid
         join pg_namespace n on n.oid = p.pronamespace
         where t.tgrelid = v_table
           and not t.tgisinternal
           and n.nspname = 'public'
           and p.proname = 'appgt_set_updated_at'
       ) then
      v_updated_trigger :=
        'appgt_updated_' || substr(md5(v_table_name), 1, 22);
      execute format(
        'create trigger %I before update on public.%I for each row execute function public.appgt_set_updated_at()',
        v_updated_trigger,
        v_table_name
      );
      v_installed := v_installed + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'triggers_instalados', v_installed
  );
end;
$$;

revoke all on function public.appgt_instalar_seguimiento_tablas_v1()
from public, anon, authenticated;
grant execute on function public.appgt_instalar_seguimiento_tablas_v1()
to service_role;

select public.appgt_instalar_seguimiento_tablas_v1();

commit;
