-- APPGT FIX - Asistencia única por FECHA + DNI
-- Objetivo: ingreso y salida deben quedar en una sola fila por trabajador por día.

-- 1) Eliminar índice anterior que permitía duplicar por placa.
DROP INDEX IF EXISTS public.uq_gt_asistencia_fecha_dni_placa;
DROP INDEX IF EXISTS public.uq_gt_asistencia_fecha_dni;

-- 2) Fusionar duplicados existentes: conserva una fila por FECHA + DNI.
WITH base AS (
  SELECT
    MIN(id_local) AS keep_id,
    "FECHA",
    "DNI",
    MIN(NULLIF("APELLIDOS Y NOMBRES", '')) AS nombre,
    MIN(NULLIF("PUESTO", '')) AS puesto,
    MIN(NULLIF("AREA", '')) AS area,
    MIN(NULLIF("TURNO", '')) AS turno,
    MIN(NULLIF("PLACA", '')) AS placa,
    MIN(NULLIF("RECLUTADOR", '')) AS reclutador,
    MIN("HORA_INGRESO") FILTER (WHERE "HORA_INGRESO" IS NOT NULL) AS hora_ingreso,
    MAX("HORA_SALIDA") FILTER (WHERE "HORA_SALIDA" IS NOT NULL) AS hora_salida
  FROM public."GT-ASISTENCIA_PERSONAL"
  WHERE COALESCE(eliminado, false) = false
  GROUP BY "FECHA", "DNI"
), upd AS (
  UPDATE public."GT-ASISTENCIA_PERSONAL" a
  SET
    "APELLIDOS Y NOMBRES" = COALESCE(base.nombre, a."APELLIDOS Y NOMBRES"),
    "PUESTO" = COALESCE(base.puesto, a."PUESTO"),
    "AREA" = COALESCE(base.area, a."AREA"),
    "TURNO" = COALESCE(base.turno, a."TURNO"),
    "PLACA" = COALESCE(base.placa, a."PLACA"),
    "RECLUTADOR" = COALESCE(base.reclutador, a."RECLUTADOR"),
    "HORA_INGRESO" = base.hora_ingreso,
    "HORA_SALIDA" = base.hora_salida,
    "HORAS_ASISTENCIA" = CASE
      WHEN base.hora_ingreso IS NOT NULL AND base.hora_salida IS NOT NULL THEN
        ROUND((EXTRACT(EPOCH FROM ((base.hora_salida::time - base.hora_ingreso::time))) / 3600.0)::numeric, 2)
      ELSE a."HORAS_ASISTENCIA"
    END,
    updated_at = now(),
    estado_sync = 'pendiente'
  FROM base
  WHERE a.id_local = base.keep_id
)
UPDATE public."GT-ASISTENCIA_PERSONAL" a
SET eliminado = true,
    activo = false,
    deleted_at = now(),
    updated_at = now(),
    estado_sync = 'pendiente'
FROM base
WHERE a."FECHA" = base."FECHA"
  AND a."DNI" = base."DNI"
  AND a.id_local <> base.keep_id;

-- 3) Índice único parcial: solo una asistencia activa por trabajador por día.
CREATE UNIQUE INDEX IF NOT EXISTS uq_gt_asistencia_fecha_dni
ON public."GT-ASISTENCIA_PERSONAL" ("FECHA", "DNI")
WHERE COALESCE(eliminado, false) = false;

-- 4) Marcar tabla como cambiada para que la app refresque.
DO $$
BEGIN
  IF to_regclass('public.appgt_tablas_cambiadas_desde') IS NOT NULL THEN
    INSERT INTO public.appgt_tablas_cambiadas_desde (tabla, fecha_ultimo_cambio, tipo_cambio)
    VALUES ('GT-ASISTENCIA_PERSONAL', now(), 'UPDATE')
    ON CONFLICT DO NOTHING;
  END IF;
END $$;
