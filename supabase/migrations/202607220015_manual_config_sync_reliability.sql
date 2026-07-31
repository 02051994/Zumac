begin;

-- Las ediciones hechas directamente desde Table Editor tambien deben invalidar
-- la cache offline. Algunas bases antiguas tienen la funcion de seguimiento,
-- pero no el trigger asociado a la matriz principal de campos.
do $$
declare
  v_tracking_trigger text;
begin
  if to_regclass('public."MATRIZ_CAMPOS_FORMATO_APPGT"') is null then
    raise exception 'MATRIZ_CAMPOS_FORMATO_APPGT does not exist';
  end if;

  if to_regprocedure('public.appgt_registrar_tabla_modificada()') is null then
    raise exception 'appgt_registrar_tabla_modificada() does not exist';
  end if;

  select t.tgname
  into v_tracking_trigger
  from pg_trigger t
  join pg_proc p on p.oid = t.tgfoid
  join pg_namespace n on n.oid = p.pronamespace
  where t.tgrelid = 'public."MATRIZ_CAMPOS_FORMATO_APPGT"'::regclass
    and not t.tgisinternal
    and n.nspname = 'public'
    and p.proname = 'appgt_registrar_tabla_modificada'
  order by t.tgname
  limit 1;

  if v_tracking_trigger is null then
    create trigger appgt_registrar_cambio_matriz_campos_trigger
    after insert or update or delete
    on public."MATRIZ_CAMPOS_FORMATO_APPGT"
    for each row
    execute function public.appgt_registrar_tabla_modificada();
  else
    execute format(
      'alter table public.%I enable trigger %I',
      'MATRIZ_CAMPOS_FORMATO_APPGT',
      v_tracking_trigger
    );
  end if;
end
$$;

-- El bootstrap incremental compara updated_at. Se asegura que las ediciones
-- manuales tambien muevan esa marca, sin duplicar un trigger ya existente.
do $$
declare
  v_updated_at_trigger text;
begin
  if to_regprocedure('public.appgt_set_updated_at()') is not null then
    select t.tgname
    into v_updated_at_trigger
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace n on n.oid = p.pronamespace
    where t.tgrelid = 'public."MATRIZ_CAMPOS_FORMATO_APPGT"'::regclass
      and not t.tgisinternal
      and n.nspname = 'public'
      and p.proname = 'appgt_set_updated_at'
    order by t.tgname
    limit 1;

    if v_updated_at_trigger is null then
      create trigger appgt_set_updated_at_trigger
      before update
      on public."MATRIZ_CAMPOS_FORMATO_APPGT"
      for each row
      execute function public.appgt_set_updated_at();
    else
      execute format(
        'alter table public.%I enable trigger %I',
        'MATRIZ_CAMPOS_FORMATO_APPGT',
        v_updated_at_trigger
      );
    end if;
  end if;
end
$$;

-- Reanuncia la configuracion ya modificada para que los clientes instalados
-- antes de este arreglo puedan encontrarla en su siguiente sincronizacion.
update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set updated_at = now()
where tabla_destino = 'SIG-CALIBRACION_DE_BALANZAS';

commit;
