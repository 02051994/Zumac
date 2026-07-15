-- APPGT - Asistencia, Tareo y Photocheck
-- Ejecutar en Supabase SQL Editor.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1) Agregar FOTO a GH-REGISTRO_PERSONAL_PLANILLA
ALTER TABLE public."GH-REGISTRO_PERSONAL_PLANILLA"
ADD COLUMN IF NOT EXISTS "FOTO" text;

-- Registrar el campo FOTO en MATRIZ_CAMPOS_FORMATO_APPGT si no existe.
-- Ajusta formato_id si tu formato usa otro id. Se toma el primer formato/tabla que apunte a GH-REGISTRO_PERSONAL_PLANILLA.
INSERT INTO public."MATRIZ_CAMPOS_FORMATO_APPGT" (
  id, formato_id, tabla_destino, campo, etiqueta, tipo, tipo_ui, requerido, visible, visible_tabla,
  numero_fotos, orden, activo
)
SELECT
  gen_random_uuid()::text,
  ft.formato_id,
  'GH-REGISTRO_PERSONAL_PLANILLA',
  'FOTO',
  'FOTO',
  'photo',
  'photo',
  false,
  true,
  true,
  1,
  COALESCE((SELECT MAX(NULLIF(orden::text,'')::int) + 1 FROM public."MATRIZ_CAMPOS_FORMATO_APPGT" WHERE tabla_destino = 'GH-REGISTRO_PERSONAL_PLANILLA'), 999),
  true
FROM public."MATRIZ_FORMATO_TABLAS_APPGT" ft
WHERE ft.tabla_destino = 'GH-REGISTRO_PERSONAL_PLANILLA'
LIMIT 1
ON CONFLICT DO NOTHING;

-- 2) Matriz de diseños de Photocheck
CREATE TABLE IF NOT EXISTS public."MATRIZ-PHOTOCHEK" (
  id_local uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "DISEÑO" integer NOT NULL,
  "LOGO" text,
  "CAMPOS" text DEFAULT 'DNI,APELLIDOS Y NOMBRES,FOTO,PUESTO,AREA',
  "tipo de trabajador" text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz,
  estado_sync text DEFAULT 'pendiente',
  estado_registro text DEFAULT 'COMPLETO',
  activo boolean DEFAULT true,
  eliminado boolean DEFAULT false,
  UNIQUE ("DISEÑO", "tipo de trabajador")
);

INSERT INTO public."MATRIZ-PHOTOCHEK" ("DISEÑO", "LOGO", "CAMPOS", "tipo de trabajador")
VALUES (1, NULL, 'DNI,APELLIDOS Y NOMBRES,FOTO,PUESTO,AREA', NULL)
ON CONFLICT DO NOTHING;

-- 3) Tabla de asistencia por movilidad/campo
CREATE TABLE IF NOT EXISTS public."GT-ASISTENCIA_PERSONAL" (
  id_local uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "FECHA" date NOT NULL DEFAULT CURRENT_DATE,
  "DNI" text NOT NULL,
  "APELLIDOS Y NOMBRES" text,
  "TURNO" text,
  "PLACA" text,
  "AREA" text,
  "PUESTO" text,
  "HORA_INGRESO" time DEFAULT CURRENT_TIME,
  "HORA_SALIDA" time,
  "HORAS_ASISTENCIA" numeric(10,2),
  "ESTADO_ASISTENCIA" text DEFAULT 'ASISTIO',
  "OBSERVACION" text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz,
  estado_sync text DEFAULT 'pendiente',
  estado_registro text DEFAULT 'COMPLETO',
  activo boolean DEFAULT true,
  eliminado boolean DEFAULT false,
  CONSTRAINT uq_gt_asistencia_personal UNIQUE ("FECHA", "DNI", "TURNO", "PLACA")
);

-- 4) Tabla de tareo / reparto de horas por labor y centro de costo
CREATE TABLE IF NOT EXISTS public."GT-TAREO_PERSONAL" (
  id_local uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "FECHA" date NOT NULL,
  "DNI" text NOT NULL,
  "APELLIDOS Y NOMBRES" text,
  "TURNO" text,
  "AREA" text,
  "CENTRO_COSTO" text NOT NULL,
  "LABOR" text NOT NULL,
  "HORAS_TRABAJADAS" numeric(10,2) NOT NULL CHECK ("HORAS_TRABAJADAS" >= 0),
  "OBSERVACION" text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz,
  estado_sync text DEFAULT 'pendiente',
  estado_registro text DEFAULT 'COMPLETO',
  activo boolean DEFAULT true,
  eliminado boolean DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_gt_asistencia_fecha_dni ON public."GT-ASISTENCIA_PERSONAL" ("FECHA", "DNI");
CREATE INDEX IF NOT EXISTS idx_gt_tareo_fecha_dni ON public."GT-TAREO_PERSONAL" ("FECHA", "DNI");

-- 5) RLS básico APPGT por permisos existentes
ALTER TABLE public."GT-ASISTENCIA_PERSONAL" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."GT-TAREO_PERSONAL" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MATRIZ-PHOTOCHEK" ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['GT-ASISTENCIA_PERSONAL','GT-TAREO_PERSONAL','MATRIZ-PHOTOCHEK'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS appgt_select_perm_%s ON public.%I', lower(replace(replace(t,'-','_'),' ','_')), t);
    EXECUTE format('CREATE POLICY appgt_select_perm_%s ON public.%I FOR SELECT TO authenticated USING (appgt_can_view_table(%L))', lower(replace(replace(t,'-','_'),' ','_')), t, t);
    EXECUTE format('DROP POLICY IF EXISTS appgt_insert_perm_%s ON public.%I', lower(replace(replace(t,'-','_'),' ','_')), t);
    EXECUTE format('CREATE POLICY appgt_insert_perm_%s ON public.%I FOR INSERT TO authenticated WITH CHECK (appgt_can_insert_table(%L))', lower(replace(replace(t,'-','_'),' ','_')), t, t);
    EXECUTE format('DROP POLICY IF EXISTS appgt_update_perm_%s ON public.%I', lower(replace(replace(t,'-','_'),' ','_')), t);
    EXECUTE format('CREATE POLICY appgt_update_perm_%s ON public.%I FOR UPDATE TO authenticated USING (appgt_can_update_table(%L)) WITH CHECK (appgt_can_update_table(%L))', lower(replace(replace(t,'-','_'),' ','_')), t, t, t);
    EXECUTE format('DROP POLICY IF EXISTS appgt_delete_perm_%s ON public.%I', lower(replace(replace(t,'-','_'),' ','_')), t);
    EXECUTE format('CREATE POLICY appgt_delete_perm_%s ON public.%I FOR DELETE TO authenticated USING (appgt_can_delete_table(%L))', lower(replace(replace(t,'-','_'),' ','_')), t, t);
  END LOOP;
END $$;

-- 6) Triggers APPGT si las funciones existen
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['GT-ASISTENCIA_PERSONAL','GT-TAREO_PERSONAL','MATRIZ-PHOTOCHEK'] LOOP
    IF to_regprocedure('public.appgt_set_updated_at()') IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_appgt_updated_at ON public.%I', t);
      EXECUTE format('CREATE TRIGGER trg_appgt_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.appgt_set_updated_at()', t);
    END IF;
    IF to_regprocedure('public.appgt_audit_trigger()') IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_appgt_audit ON public.%I', t);
      EXECUTE format('CREATE TRIGGER trg_appgt_audit AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.appgt_audit_trigger()', t);
    END IF;
    IF to_regprocedure('public.appgt_registrar_cambio_tabla()') IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_appgt_registrar_cambio_tabla ON public.%I', t);
      EXECUTE format('CREATE TRIGGER trg_appgt_registrar_cambio_tabla AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.appgt_registrar_cambio_tabla()', t);
    END IF;
  END LOOP;
END $$;
