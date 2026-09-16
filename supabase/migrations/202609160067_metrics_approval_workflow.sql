begin;

create table if not exists public."SOLICITUDES_METRICS_APPGT"(
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  solicitado_por uuid not null references auth.users(id) on delete restrict,
  tipo text not null check(tipo in('DASHBOARD','WIDGET','GEOMETRIA','RELACION','ITEM','DASHBOARDS')),
  operacion text not null check(operacion in('GUARDAR','ELIMINAR','REORDENAR')),
  entity_key text not null,
  payload jsonb not null default '{}'::jsonb,
  estado text not null default 'SOLICITADO'
    check(estado in('SOLICITADO','APROBADO','RECHAZADO')),
  revisado_por uuid references auth.users(id) on delete set null,
  revisado_at timestamptz,
  comentario_revision text,
  resultado jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists solicitudes_metrics_empresa_estado_idx
  on public."SOLICITUDES_METRICS_APPGT"(empresa_id,estado,created_at desc);
create unique index if not exists solicitudes_metrics_pendiente_unica_idx
  on public."SOLICITUDES_METRICS_APPGT"(
    empresa_id,solicitado_por,tipo,operacion,entity_key
  ) where estado='SOLICITADO';

alter table public."SOLICITUDES_METRICS_APPGT" enable row level security;
revoke all on table public."SOLICITUDES_METRICS_APPGT"
  from public,anon,authenticated;

drop trigger if exists trg_appgt_audit
  on public."SOLICITUDES_METRICS_APPGT";
create trigger trg_appgt_audit
after insert or update or delete on public."SOLICITUDES_METRICS_APPGT"
for each row execute function public.appgt_audit_trigger();

-- Las implementaciones publicadas se vuelven internas. Sus nombres públicos
-- se recrean más abajo como puertas de aprobación y permanecen compatibles.
alter function public.appgt_guardar_dashboard_metrics_v1(jsonb)
  rename to appgt_aplicar_dashboard_metrics_internal_v1;
alter function public.appgt_guardar_widget_metrics_v1(jsonb)
  rename to appgt_aplicar_widget_metrics_internal_v1;
alter function public.appgt_guardar_geometria_widget_metrics_v2(uuid,uuid,jsonb)
  rename to appgt_aplicar_geometria_metrics_internal_v2;
alter function public.appgt_guardar_relacion_metrics_v1(jsonb)
  rename to appgt_aplicar_relacion_metrics_internal_v1;
alter function public.appgt_eliminar_metrics_v1(text,uuid)
  rename to appgt_aplicar_eliminar_metrics_internal_v1;
alter function public.appgt_reordenar_dashboards_metrics_v4(uuid[])
  rename to appgt_aplicar_reorden_dashboards_internal_v4;

revoke all on function public.appgt_aplicar_dashboard_metrics_internal_v1(jsonb)
  from public,anon,authenticated,service_role;
revoke all on function public.appgt_aplicar_widget_metrics_internal_v1(jsonb)
  from public,anon,authenticated,service_role;
revoke all on function public.appgt_aplicar_geometria_metrics_internal_v2(uuid,uuid,jsonb)
  from public,anon,authenticated,service_role;
revoke all on function public.appgt_aplicar_relacion_metrics_internal_v1(jsonb)
  from public,anon,authenticated,service_role;
revoke all on function public.appgt_aplicar_eliminar_metrics_internal_v1(text,uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.appgt_aplicar_reorden_dashboards_internal_v4(uuid[])
  from public,anon,authenticated,service_role;

create function public.appgt_ejecutar_mutacion_metrics_internal_v1(
  p_tipo text,p_operacion text,p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_tipo text:=upper(btrim(coalesce(p_tipo,'')));
  v_operacion text:=upper(btrim(coalesce(p_operacion,'')));
  v_ids uuid[];
begin
  if v_tipo='DASHBOARD' and v_operacion='GUARDAR' then
    return public.appgt_aplicar_dashboard_metrics_internal_v1(p_payload);
  elsif v_tipo='WIDGET' and v_operacion='GUARDAR' then
    return public.appgt_aplicar_widget_metrics_internal_v1(p_payload);
  elsif v_tipo='GEOMETRIA' and v_operacion='GUARDAR' then
    return public.appgt_aplicar_geometria_metrics_internal_v2(
      (p_payload->>'widget_id')::uuid,
      (p_payload->>'dashboard_id')::uuid,
      coalesce(p_payload->'geometria','{}'::jsonb)
    );
  elsif v_tipo='RELACION' and v_operacion='GUARDAR' then
    return public.appgt_aplicar_relacion_metrics_internal_v1(p_payload);
  elsif v_tipo='ITEM' and v_operacion='ELIMINAR' then
    return public.appgt_aplicar_eliminar_metrics_internal_v1(
      p_payload->>'tipo',(p_payload->>'id')::uuid
    );
  elsif v_tipo='DASHBOARDS' and v_operacion='REORDENAR' then
    select coalesce(array_agg(value::uuid order by ordinality),'{}'::uuid[])
      into v_ids
    from jsonb_array_elements_text(coalesce(p_payload->'ids','[]'::jsonb))
      with ordinality;
    return public.appgt_aplicar_reorden_dashboards_internal_v4(v_ids);
  end if;
  raise exception 'Mutación Metrics inválida: %/%',v_tipo,v_operacion;
end
$$;

revoke all on function public.appgt_ejecutar_mutacion_metrics_internal_v1(
  text,text,jsonb
) from public,anon,authenticated,service_role;

create function public.appgt_mutar_o_solicitar_metrics_v1(
  p_tipo text,p_operacion text,p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa_id uuid:=public.appgt_empresa_actual_id();
  v_rol text:=public.appgt_rol_empresa_actual();
  v_tipo text:=upper(btrim(coalesce(p_tipo,'')));
  v_operacion text:=upper(btrim(coalesce(p_operacion,'')));
  v_entity_key text;
  v_id uuid;
  v_result jsonb;
begin
  if v_empresa_id is null or v_rol not in('ADMIN','GESTOR') then
    raise exception 'Sin permiso para administrar Metrics' using errcode='42501';
  end if;
  if v_rol='ADMIN' then
    return public.appgt_ejecutar_mutacion_metrics_internal_v1(
      v_tipo,v_operacion,p_payload
    ) || jsonb_build_object('estado','APLICADO','solicitado',false);
  end if;

  v_entity_key:=coalesce(
    nullif(p_payload->>'id',''),nullif(p_payload->>'widget_id',''),
    nullif(p_payload->>'dashboard_id',''),
    case when v_tipo='DASHBOARDS' then 'EMPRESA' end,
    'NUEVO:'||gen_random_uuid()::text
  );
  insert into public."SOLICITUDES_METRICS_APPGT"(
    empresa_id,solicitado_por,tipo,operacion,entity_key,payload
  ) values(
    v_empresa_id,auth.uid(),v_tipo,v_operacion,v_entity_key,p_payload
  )
  on conflict(empresa_id,solicitado_por,tipo,operacion,entity_key)
    where estado='SOLICITADO'
  do update set payload=excluded.payload,updated_at=now()
  returning id into v_id;

  return jsonb_build_object(
    'solicitado',true,'estado','SOLICITADO','solicitud_id',v_id,
    'guardado',false,'guardada',false,
    'id',coalesce(nullif(p_payload->>'id',''),v_id::text),
    'configuracion',coalesce(p_payload->'geometria','{}'::jsonb)
  );
end
$$;

create function public.appgt_listar_solicitudes_metrics_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare v_empresa_id uuid:=public.appgt_empresa_actual_id();
begin
  if not public.appgt_es_admin_empresa(v_empresa_id) then
    raise exception 'Se requiere ADMIN de la empresa' using errcode='42501';
  end if;
  return jsonb_build_object('solicitudes',coalesce((
    select jsonb_agg(
      to_jsonb(s)||jsonb_build_object(
        'solicitante',coalesce(p.nombres,p."DNI",s.solicitado_por::text)
      ) order by s.created_at desc
    )
    from public."SOLICITUDES_METRICS_APPGT" s
    left join public."PERFILES_DE_USUARIOS_APPGT" p
      on p.id=s.solicitado_por and p.empresa_id=s.empresa_id
    where s.empresa_id=v_empresa_id and s.estado='SOLICITADO'
  ),'[]'::jsonb));
end
$$;

create function public.appgt_resolver_solicitud_metrics_v1(
  p_solicitud_id uuid,p_aprobar boolean,p_comentario text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_empresa_id uuid:=public.appgt_empresa_actual_id();
  v_request public."SOLICITUDES_METRICS_APPGT"%rowtype;
  v_result jsonb;
begin
  if not public.appgt_es_admin_empresa(v_empresa_id) then
    raise exception 'Se requiere ADMIN de la empresa' using errcode='42501';
  end if;
  select * into v_request
  from public."SOLICITUDES_METRICS_APPGT"
  where id=p_solicitud_id and empresa_id=v_empresa_id
    and estado='SOLICITADO'
  for update;
  if v_request.id is null then
    raise exception 'Solicitud pendiente no encontrada';
  end if;
  if p_aprobar then
    v_result:=public.appgt_ejecutar_mutacion_metrics_internal_v1(
      v_request.tipo,v_request.operacion,v_request.payload
    );
  else
    v_result:=jsonb_build_object('rechazado',true);
  end if;
  update public."SOLICITUDES_METRICS_APPGT"
  set estado=case when p_aprobar then 'APROBADO' else 'RECHAZADO' end,
      revisado_por=auth.uid(),revisado_at=now(),
      comentario_revision=nullif(btrim(coalesce(p_comentario,'')),''),
      resultado=v_result,updated_at=now()
  where id=v_request.id;
  return jsonb_build_object(
    'resuelto',true,'solicitud_id',v_request.id,
    'estado',case when p_aprobar then 'APROBADO' else 'RECHAZADO' end,
    'resultado',v_result
  );
end
$$;

create function public.appgt_guardar_dashboard_metrics_v1(p_payload jsonb)
returns jsonb language sql security definer set search_path=public,pg_temp as $$
  select public.appgt_mutar_o_solicitar_metrics_v1(
    'DASHBOARD','GUARDAR',p_payload
  )
$$;

create function public.appgt_guardar_widget_metrics_v1(p_payload jsonb)
returns jsonb language sql security definer set search_path=public,pg_temp as $$
  select public.appgt_mutar_o_solicitar_metrics_v1(
    'WIDGET','GUARDAR',p_payload
  )
$$;

create function public.appgt_guardar_geometria_widget_metrics_v2(
  p_widget_id uuid,p_dashboard_id uuid,p_geometria jsonb
)
returns jsonb language sql security definer set search_path=public,pg_temp as $$
  select public.appgt_mutar_o_solicitar_metrics_v1(
    'GEOMETRIA','GUARDAR',jsonb_build_object(
      'widget_id',p_widget_id,'dashboard_id',p_dashboard_id,
      'geometria',p_geometria
    )
  )
$$;

create function public.appgt_guardar_relacion_metrics_v1(p_payload jsonb)
returns jsonb language sql security definer set search_path=public,pg_temp as $$
  select public.appgt_mutar_o_solicitar_metrics_v1(
    'RELACION','GUARDAR',p_payload
  )
$$;

create function public.appgt_eliminar_metrics_v1(p_tipo text,p_id uuid)
returns jsonb language sql security definer set search_path=public,pg_temp as $$
  select public.appgt_mutar_o_solicitar_metrics_v1(
    'ITEM','ELIMINAR',jsonb_build_object('tipo',p_tipo,'id',p_id)
  )
$$;

create function public.appgt_reordenar_dashboards_metrics_v4(p_ids uuid[])
returns jsonb language sql security definer set search_path=public,pg_temp as $$
  select public.appgt_mutar_o_solicitar_metrics_v1(
    'DASHBOARDS','REORDENAR',jsonb_build_object('ids',to_jsonb(p_ids))
  )
$$;

revoke all on function public.appgt_mutar_o_solicitar_metrics_v1(
  text,text,jsonb
) from public,anon;
revoke all on function public.appgt_listar_solicitudes_metrics_v1()
  from public,anon;
revoke all on function public.appgt_resolver_solicitud_metrics_v1(
  uuid,boolean,text
) from public,anon;
grant execute on function public.appgt_mutar_o_solicitar_metrics_v1(
  text,text,jsonb
) to authenticated;
grant execute on function public.appgt_listar_solicitudes_metrics_v1()
  to authenticated;
grant execute on function public.appgt_resolver_solicitud_metrics_v1(
  uuid,boolean,text
) to authenticated;

revoke all on function public.appgt_guardar_dashboard_metrics_v1(jsonb)
  from public,anon;
revoke all on function public.appgt_guardar_widget_metrics_v1(jsonb)
  from public,anon;
revoke all on function public.appgt_guardar_geometria_widget_metrics_v2(
  uuid,uuid,jsonb
) from public,anon;
revoke all on function public.appgt_guardar_relacion_metrics_v1(jsonb)
  from public,anon;
revoke all on function public.appgt_eliminar_metrics_v1(text,uuid)
  from public,anon;
revoke all on function public.appgt_reordenar_dashboards_metrics_v4(uuid[])
  from public,anon;
grant execute on function public.appgt_guardar_dashboard_metrics_v1(jsonb)
  to authenticated;
grant execute on function public.appgt_guardar_widget_metrics_v1(jsonb)
  to authenticated;
grant execute on function public.appgt_guardar_geometria_widget_metrics_v2(
  uuid,uuid,jsonb
) to authenticated;
grant execute on function public.appgt_guardar_relacion_metrics_v1(jsonb)
  to authenticated;
grant execute on function public.appgt_eliminar_metrics_v1(text,uuid)
  to authenticated;
grant execute on function public.appgt_reordenar_dashboards_metrics_v4(uuid[])
  to authenticated;

notify pgrst,'reload schema';
commit;
