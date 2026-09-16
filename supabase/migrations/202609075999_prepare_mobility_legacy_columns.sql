-- Compatibilidad para instalaciones antiguas: la migración de planilla posterior
-- puede coexistir con matrices de movilidad creadas antes de los campos técnicos.
begin;

alter table if exists public."GT-MATRIZ_MOVILIDADES"
  add column if not exists empresa_id uuid references public."EMPRESAS_APPGT"(id),
  add column if not exists eliminado boolean not null default false,
  add column if not exists deleted_at timestamptz;

alter table if exists public."GT-ASISTENCIA_PERSONAL"
  add column if not exists empresa_id uuid references public."EMPRESAS_APPGT"(id),
  add column if not exists eliminado boolean not null default false,
  add column if not exists deleted_at timestamptz;

commit;
