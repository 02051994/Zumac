begin;

create or replace function public.appgt_registrar_pdf_boleta_v1(
  p_boleta_id uuid,
  p_pdf_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_boleta public."PLANILLA_BOLETAS_APPGT"%rowtype;
begin
  select * into v_boleta from public."PLANILLA_BOLETAS_APPGT"
  where id=p_boleta_id and empresa_id=public.appgt_empresa_actual_id();
  if not found then raise exception 'Boleta no encontrada.'; end if;
  if not public.appgt_can_view_table('PLANILLA_BOLETAS_APPGT') then
    raise exception 'No tiene permiso para generar esta boleta.' using errcode='42501';
  end if;
  if p_pdf_url !~ ('^storage://planilla-boletas/' || v_boleta.empresa_id::text || '/') then
    raise exception 'La ruta del PDF de boleta no es válida.';
  end if;
  update public."PLANILLA_BOLETAS_APPGT" set
    pdf_url=p_pdf_url,pdf_generado_at=clock_timestamp(),estado='GENERADA',updated_at=now()
  where id=v_boleta.id;
  select * into v_boleta from public."PLANILLA_BOLETAS_APPGT" where id=v_boleta.id;
  return to_jsonb(v_boleta);
end;
$$;

grant execute on function public.appgt_registrar_pdf_boleta_v1(uuid,text)
  to authenticated, service_role;
notify pgrst, 'reload schema';
commit;
