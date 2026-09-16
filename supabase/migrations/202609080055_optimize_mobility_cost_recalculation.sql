-- El costo de movilidad se invoca desde cada fila diaria de planilla. Estas
-- llaves evitan convertir toda la asistencia/movilidad a JSON en cada cálculo.
create index if not exists appgt_asistencia_planilla_movilidad_idx
  on public."GT-ASISTENCIA_PERSONAL" (empresa_id, "DNI", "FECHA")
  where not coalesce(eliminado, false) and deleted_at is null;

create index if not exists appgt_movilidad_planilla_placa_idx
  on public."GT-MATRIZ_MOVILIDADES" (empresa_id, lower(btrim("PLACA")))
  where not coalesce(eliminado, false) and deleted_at is null;

create or replace function public.appgt_costo_movilidad_diaria_v1(
  p_empresa uuid,
  p_dni text,
  p_fecha date
)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum(
    case
      when coalesce(m.costo_asiento, 0) > 0 then m.costo_asiento::numeric
      when coalesce(m.costo_total, 0) > 0
        and coalesce(m."CAPACIDAD_ASIENTOS", 0) > 0
      then round(m.costo_total::numeric / m."CAPACIDAD_ASIENTOS", 6)
      else 0
    end
  ), 0)
  from public."GT-ASISTENCIA_PERSONAL" a
  join public."GT-MATRIZ_MOVILIDADES" m
    on m.empresa_id = p_empresa
   and lower(btrim(m."PLACA")) = lower(btrim(a."PLACA"))
   and not coalesce(m.eliminado, false)
   and m.deleted_at is null
  where a.empresa_id = p_empresa
    and a."DNI" = p_dni
    and a."FECHA" = p_fecha
    and not coalesce(a.eliminado, false)
    and a.deleted_at is null
$$;

comment on function public.appgt_costo_movilidad_diaria_v1(uuid, text, date) is
  'Costo de movilidad por asistencia activa; usa costo_asiento o costo_total/capacidad sin incluir registros eliminados.';
