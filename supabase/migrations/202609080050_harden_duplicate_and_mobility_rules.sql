begin;

-- Las matrices históricas no siempre tienen todas las columnas técnicas.
-- Esta revisión usa JSON de fila para que el control siga funcionando tanto
-- en tablas heredadas como en tablas creadas por Creator.
create or replace function public.appgt_evitar_duplicado_semantico_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_regla record;
  v_new jsonb := to_jsonb(new);
  v_empresa text := coalesce(nullif(v_new ->> 'empresa_id', ''), public.appgt_empresa_actual_id()::text);
  v_id text := coalesce(v_new ->> 'id_local', v_new ->> 'id', '');
  v_campo text;
  v_valor text;
  v_firma text := '';
  v_where text := '';
  v_sql text;
  v_duplicado boolean := false;
begin
  if coalesce(lower(v_new ->> 'eliminado'), 'false') in ('true','1','si','sí')
     or nullif(v_new ->> 'deleted_at', '') is not null then
    return new;
  end if;
  select * into v_regla
  from public."APPGT_REGLAS_DUPLICADO_APPGT" r
  where r.empresa_id::text=v_empresa
    and upper(r.tabla_destino)=upper(tg_table_name) and r.activo
  limit 1;
  if not found then return new; end if;

  foreach v_campo in array v_regla.campos_clave loop
    v_valor:=lower(btrim(coalesce(v_new->>v_campo,'')));
    if v_valor='' then return new; end if;
    v_firma:=v_firma||'|'||lower(v_campo)||'='||v_valor;
    v_where:=v_where||format(
      ' and lower(btrim(coalesce(to_jsonb(t)->>%L, '''')))=%L',v_campo,v_valor
    );
  end loop;
  perform pg_advisory_xact_lock(hashtextextended(
    upper(tg_table_name)||'|'||v_empresa||v_firma,0
  ));
  v_sql:=format(
    'select exists (select 1 from public.%I t where '
    || 'coalesce(lower(to_jsonb(t)->>''eliminado''),''false'') not in (''true'',''1'',''si'',''sí'') '
    || 'and nullif(to_jsonb(t)->>''deleted_at'','''') is null '
    || 'and coalesce(nullif(to_jsonb(t)->>''empresa_id'',''''),%L)=%L '
    || 'and coalesce(to_jsonb(t)->>''id_local'',to_jsonb(t)->>''id'','''') is distinct from %L %s)',
    tg_table_name,v_empresa,v_empresa,v_id,v_where
  );
  execute v_sql into v_duplicado;
  if v_duplicado then
    raise exception 'APPGT_DUPLICATE: Ya existe un registro activo con la misma clave de negocio (%).',
      array_to_string(v_regla.campos_clave,', ')
      using errcode='23505';
  end if;
  return new;
end;
$$;

create or replace function public.appgt_costo_movilidad_diaria_v1(
  p_empresa uuid,p_dni text,p_fecha date
)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum(
    case
      when public.appgt_jsonb_numeric(to_jsonb(m),array['costo_asiento','COSTO_ASIENTO'],0)>0
        then public.appgt_jsonb_numeric(to_jsonb(m),array['costo_asiento','COSTO_ASIENTO'],0)
      when public.appgt_jsonb_numeric(to_jsonb(m),array['costo_total','COSTO_TOTAL'],0)>0
        and public.appgt_jsonb_numeric(to_jsonb(m),array['capacidad','CAPACIDAD'],0)>0
        then round(
          public.appgt_jsonb_numeric(to_jsonb(m),array['costo_total','COSTO_TOTAL'],0)
          / public.appgt_jsonb_numeric(to_jsonb(m),array['capacidad','CAPACIDAD'],0),6
        )
      else 0
    end
  ),0)
  from public."GT-ASISTENCIA_PERSONAL" a
  join public."GT-MATRIZ_MOVILIDADES" m
    on public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(m),array['placa','PLACA']))
      =public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(a),array['PLACA','placa','MOVILIDAD']))
  where coalesce(nullif(to_jsonb(a)->>'empresa_id',''),p_empresa::text)=p_empresa::text
    and coalesce(nullif(to_jsonb(m)->>'empresa_id',''),p_empresa::text)=p_empresa::text
    and public.appgt_normalizar_clave(public.appgt_jsonb_text(to_jsonb(a),array['DNI','dni','DOCUMENTO']))
      =public.appgt_normalizar_clave(p_dni)
    and public.appgt_jsonb_date(to_jsonb(a),array['FECHA','FECHA_INGRESO'])=p_fecha
    and coalesce(lower(to_jsonb(a)->>'eliminado'),'false') not in ('true','1','si','sí')
    and nullif(to_jsonb(a)->>'deleted_at','') is null
    and coalesce(lower(to_jsonb(m)->>'eliminado'),'false') not in ('true','1','si','sí')
    and nullif(to_jsonb(m)->>'deleted_at','') is null
$$;

notify pgrst, 'reload schema';
commit;
