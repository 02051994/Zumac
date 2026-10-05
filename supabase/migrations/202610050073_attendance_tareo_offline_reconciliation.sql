begin;

-- Asistencia conserva una sola fila por trabajador y día. El ingreso crea la
-- fila y la salida completa HORA_SALIDA sobre ese mismo id_local. La app
-- concilia primero contra Supabase cuando el caché local fue borrado.
insert into public."APPGT_REGLAS_DUPLICADO_APPGT" (
  empresa_id, tabla_destino, campos_clave, descripcion, activo,
  created_at, updated_at
)
select
  e.id,
  'GT-ASISTENCIA_PERSONAL',
  array['DNI','FECHA']::text[],
  'Una fila diaria por trabajador; ingreso y salida se guardan en la misma asistencia.',
  true,
  now(),
  now()
from public."EMPRESAS_APPGT" e
on conflict (empresa_id, tabla_destino) do update set
  campos_clave = excluded.campos_clave,
  descripcion = excluded.descripcion,
  activo = true,
  updated_at = now();

-- Un trabajador puede tener varios tareos en el mismo día, labor, centro de
-- costo o lote. Solo se considera duplicado el mismo intervalo completo.
insert into public."APPGT_REGLAS_DUPLICADO_APPGT" (
  empresa_id, tabla_destino, campos_clave, descripcion, activo,
  created_at, updated_at
)
select
  e.id,
  'GT-TAREO_PERSONAL',
  array['DNI','FECHA','HORA_INICIO','HORA_FIN']::text[],
  'Un intervalo de tareo por trabajador, fecha, hora de inicio y hora de fin.',
  true,
  now(),
  now()
from public."EMPRESAS_APPGT" e
on conflict (empresa_id, tabla_destino) do update set
  campos_clave = excluded.campos_clave,
  descripcion = excluded.descripcion,
  activo = true,
  updated_at = now();

notify pgrst, 'reload schema';

commit;
