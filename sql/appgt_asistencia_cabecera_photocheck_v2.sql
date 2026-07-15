-- APPGT - Asistencia QR/PDA + cabecera + diseño photocheck V2
-- Ejecutar en Supabase SQL Editor y luego presionar Actualizar datos en la app.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1) Foto en planilla
ALTER TABLE public."GH-REGISTRO_PERSONAL_PLANILLA"
ADD COLUMN IF NOT EXISTS "FOTO" text;

-- 2) Cabecera de asistencia: movilidad/fecha/reclutador
CREATE TABLE IF NOT EXISTS public."GT-CABECERA_ASISTENCIA" (
  id_local uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "FECHA" date NOT NULL DEFAULT CURRENT_DATE,
  "PLACA" text,
  "RECLUTADOR" text,
  "TIPO_MOVIMIENTO" text DEFAULT 'INGRESO',
  "OBSERVACION" text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz,
  estado_sync text DEFAULT 'pendiente',
  estado_registro text DEFAULT 'COMPLETO',
  activo boolean DEFAULT true,
  eliminado boolean DEFAULT false
);

-- 3) Detalle de asistencia: se genera automático al escanear DNI/QR/barra
CREATE TABLE IF NOT EXISTS public."GT-ASISTENCIA_PERSONAL" (
  id_local uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  id_cabecera uuid,
  "FECHA" date NOT NULL DEFAULT CURRENT_DATE,
  "DNI" text NOT NULL,
  "APELLIDOS Y NOMBRES" text,
  "TURNO" text,
  "PLACA" text,
  "AREA" text,
  "PUESTO" text,
  "HORA_INGRESO" time,
  "HORA_SALIDA" time,
  "HORAS_ASISTENCIA" numeric(10,2),
  "ESTADO_ASISTENCIA" text,
  "RECLUTADOR" text,
  "OBSERVACION" text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz,
  estado_sync text DEFAULT 'pendiente',
  estado_registro text DEFAULT 'COMPLETO',
  activo boolean DEFAULT true,
  eliminado boolean DEFAULT false
);

ALTER TABLE public."GT-ASISTENCIA_PERSONAL"
ADD COLUMN IF NOT EXISTS id_cabecera uuid,
ADD COLUMN IF NOT EXISTS "RECLUTADOR" text;

CREATE UNIQUE INDEX IF NOT EXISTS uq_gt_asistencia_fecha_dni_placa
ON public."GT-ASISTENCIA_PERSONAL" ("FECHA", "DNI", COALESCE("PLACA", ''));

-- 4) Tareo: reparto de horas por centro de costo y labor
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

-- 5) Diseño de photocheck. El campo PUESTO decide qué diseño aplica.
CREATE TABLE IF NOT EXISTS public."GT-DISEÑO_PHOTOCHEK" (
  id_local uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "DISEÑO" integer NOT NULL,
  "LOGO" text,
  "CAMPOS" text DEFAULT 'DNI,APELLIDOS Y NOMBRES,FOTO,PUESTO,AREA',
  "PUESTO" text,
  "OBSERVACION" text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz,
  estado_sync text DEFAULT 'pendiente',
  estado_registro text DEFAULT 'COMPLETO',
  activo boolean DEFAULT true,
  eliminado boolean DEFAULT false,
  UNIQUE ("DISEÑO", "PUESTO")
);

INSERT INTO public."GT-DISEÑO_PHOTOCHEK" ("DISEÑO", "LOGO", "CAMPOS", "PUESTO")
VALUES (1, NULL, 'DNI,APELLIDOS Y NOMBRES,FOTO,PUESTO,AREA', NULL)
ON CONFLICT DO NOTHING;

-- Compatibilidad con versión anterior si ya la ejecutaste.
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

-- 6) Registrar formato especial para que al abrir Asistencia no salga formulario plano.
INSERT INTO public."MATRIZ_FORMATOS_APPGT" (
  "id", "modulo_id", "nombre", "tabla_destino", "ruta_flutter", "orden", "activo", "updated_at", "created_at", "deleted_at", "estado_sync", "eliminado"
)
VALUES (
  'asistencia_personal', 'gestion_humana', 'Asistencia de Personal', 'GT-CABECERA_ASISTENCIA', NULL, 0, true, now(), now(), NULL, 'sincronizado', false
)
ON CONFLICT ("id") DO UPDATE SET
  "tabla_destino" = EXCLUDED."tabla_destino",
  "nombre" = EXCLUDED."nombre",
  "activo" = true,
  "updated_at" = now(),
  "eliminado" = false;

-- Requiere que exista MATRIZ_FORMATOS_ESPECIALES_APPGT, que tu app ya descarga como local_special_formats.
CREATE TABLE IF NOT EXISTS public."MATRIZ_FORMATOS_ESPECIALES_APPGT" (
  id text PRIMARY KEY,
  modulo_id text,
  formato_id text,
  tipo_pantalla text,
  descripcion text,
  activo boolean DEFAULT true,
  orden integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz,
  eliminado boolean DEFAULT false,
  estado_sync text DEFAULT 'sincronizado'
);

INSERT INTO public."MATRIZ_FORMATOS_ESPECIALES_APPGT" (id, modulo_id, formato_id, tipo_pantalla, descripcion, activo, orden, updated_at, estado_sync, eliminado)
VALUES ('esp_asistencia_personal', 'gestion_humana', 'asistencia_personal', 'asistencia_personal', 'Pantalla especial de asistencia con QR/barra/PDA', true, 0, now(), 'sincronizado', false)
ON CONFLICT (id) DO UPDATE SET
  tipo_pantalla = EXCLUDED.tipo_pantalla,
  descripcion = EXCLUDED.descripcion,
  activo = true,
  updated_at = now(),
  eliminado = false;

-- 7) Configuración padre-hijo en MATRIZ_FORMATO_TABLAS_APPGT
ALTER TABLE public."MATRIZ_FORMATO_TABLAS_APPGT"
ADD COLUMN IF NOT EXISTS tipo_relacion text,
ADD COLUMN IF NOT EXISTS tabla_padre text,
ADD COLUMN IF NOT EXISTS campo_pk_padre text,
ADD COLUMN IF NOT EXISTS campo_fk_hijo text,
ADD COLUMN IF NOT EXISTS es_cabecera boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS es_detalle boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS campo_iterador text,
ADD COLUMN IF NOT EXISTS iterador_desde integer,
ADD COLUMN IF NOT EXISTS iterador_hasta integer,
ADD COLUMN IF NOT EXISTS copiar_campos_desde_padre text,
ADD COLUMN IF NOT EXISTS modo_captura text;

INSERT INTO public."MATRIZ_FORMATO_TABLAS_APPGT" (
  id, formato_id, nombre, tabla_destino, orden, activo,
  tipo_relacion, es_cabecera, es_detalle, tabla_padre, campo_pk_padre, campo_fk_hijo,
  copiar_campos_desde_padre, modo_captura
)
VALUES
('asistencia_personal_cab', 'asistencia_personal', 'Cabecera Asistencia', 'GT-CABECERA_ASISTENCIA', 1, true,
 'cabecera', true, false, NULL, 'id_local', NULL, NULL, 'cabecera_asistencia'),
('asistencia_personal_det', 'asistencia_personal', 'Detalle Asistencia', 'GT-ASISTENCIA_PERSONAL', 2, true,
 'detalle', false, true, 'GT-CABECERA_ASISTENCIA', 'id_local', 'id_cabecera', 'FECHA,PLACA,RECLUTADOR', 'scanner_detalle')
ON CONFLICT (id) DO UPDATE SET
  tabla_destino = EXCLUDED.tabla_destino,
  orden = EXCLUDED.orden,
  activo = true,
  tipo_relacion = EXCLUDED.tipo_relacion,
  es_cabecera = EXCLUDED.es_cabecera,
  es_detalle = EXCLUDED.es_detalle,
  tabla_padre = EXCLUDED.tabla_padre,
  campo_pk_padre = EXCLUDED.campo_pk_padre,
  campo_fk_hijo = EXCLUDED.campo_fk_hijo,
  copiar_campos_desde_padre = EXCLUDED.copiar_campos_desde_padre,
  modo_captura = EXCLUDED.modo_captura;

-- 8) Matriz de campos mínima. Tu app especial usa esta configuración para tabla, permisos e import/export.
ALTER TABLE public."MATRIZ_CAMPOS_FORMATO_APPGT"
ADD COLUMN IF NOT EXISTS visible_tabla boolean DEFAULT true,
ADD COLUMN IF NOT EXISTS tipo_ui text,
ADD COLUMN IF NOT EXISTS editable boolean DEFAULT true,
ADD COLUMN IF NOT EXISTS numero_fotos text;

-- FOTO en planilla
INSERT INTO public."MATRIZ_CAMPOS_FORMATO_APPGT" ("id", "tabla_destino", "campo", "etiqueta", "tipo", "tipo_ui", "requerido", "visible", "visible_tabla", "editable", "numero_fotos", "orden", "activo", "created_at", "updated_at", "estado_sync", "eliminado")
SELECT gen_random_uuid()::text, 'GH-REGISTRO_PERSONAL_PLANILLA', 'FOTO', 'Foto', 'text', 'photo', false, true, true, true, '1',
       COALESCE(MAX("orden") + 1, 999), true, now(), now(), 'sincronizado', false
FROM public."MATRIZ_CAMPOS_FORMATO_APPGT"
WHERE "tabla_destino" = 'GH-REGISTRO_PERSONAL_PLANILLA'
HAVING NOT EXISTS (
  SELECT 1 FROM public."MATRIZ_CAMPOS_FORMATO_APPGT" WHERE "tabla_destino"='GH-REGISTRO_PERSONAL_PLANILLA' AND "campo"='FOTO'
);

-- Campos de cabecera
INSERT INTO public."MATRIZ_CAMPOS_FORMATO_APPGT" ("id", "tabla_destino", "campo", "etiqueta", "tipo", "tipo_ui", "requerido", "visible", "visible_tabla", "editable", "orden", "activo", "created_at", "updated_at", "estado_sync", "eliminado") VALUES
('campo_cab_asistencia_fecha', 'GT-CABECERA_ASISTENCIA', 'FECHA', 'Fecha', 'date', 'date', true, true, true, true, 1, true, now(), now(), 'sincronizado', false),
('campo_cab_asistencia_placa', 'GT-CABECERA_ASISTENCIA', 'PLACA', 'Placa', 'text', 'text', false, true, true, true, 2, true, now(), now(), 'sincronizado', false),
('campo_cab_asistencia_reclutador', 'GT-CABECERA_ASISTENCIA', 'RECLUTADOR', 'Reclutador', 'text', 'text', false, true, true, true, 3, true, now(), now(), 'sincronizado', false),
('campo_cab_asistencia_mov', 'GT-CABECERA_ASISTENCIA', 'TIPO_MOVIMIENTO', 'Movimiento', 'text', 'dropdown', true, true, true, true, 4, true, now(), now(), 'sincronizado', false)
ON CONFLICT ("id") DO UPDATE SET activo=true, updated_at=now(), eliminado=false;

-- Campo scan referencial + detalle visible
INSERT INTO public."MATRIZ_CAMPOS_FORMATO_APPGT" ("id", "tabla_destino", "campo", "etiqueta", "tipo", "tipo_ui", "requerido", "visible", "visible_tabla", "editable", "orden", "activo", "created_at", "updated_at", "estado_sync", "eliminado") VALUES
('campo_asistencia_dni_scan', 'GT-ASISTENCIA_PERSONAL', 'DNI', 'DNI / QR', 'text', 'dni_scan', true, true, true, true, 1, true, now(), now(), 'sincronizado', false),
('campo_asistencia_nombre', 'GT-ASISTENCIA_PERSONAL', 'APELLIDOS Y NOMBRES', 'Apellidos y Nombres', 'text', 'text', false, true, true, false, 2, true, now(), now(), 'sincronizado', false),
('campo_asistencia_puesto', 'GT-ASISTENCIA_PERSONAL', 'PUESTO', 'Puesto', 'text', 'text', false, true, true, false, 3, true, now(), now(), 'sincronizado', false),
('campo_asistencia_placa', 'GT-ASISTENCIA_PERSONAL', 'PLACA', 'Placa', 'text', 'text', false, true, true, false, 4, true, now(), now(), 'sincronizado', false),
('campo_asistencia_hora_ingreso', 'GT-ASISTENCIA_PERSONAL', 'HORA_INGRESO', 'Hora ingreso', 'time', 'time', false, true, true, false, 5, true, now(), now(), 'sincronizado', false),
('campo_asistencia_hora_salida', 'GT-ASISTENCIA_PERSONAL', 'HORA_SALIDA', 'Hora salida', 'time', 'time', false, true, true, false, 6, true, now(), now(), 'sincronizado', false),
('campo_asistencia_horas', 'GT-ASISTENCIA_PERSONAL', 'HORAS_ASISTENCIA', 'Horas asistencia', 'numeric', 'number', false, true, true, false, 7, true, now(), now(), 'sincronizado', false)
ON CONFLICT ("id") DO UPDATE SET activo=true, updated_at=now(), eliminado=false;

-- 9) RLS, políticas y triggers APPGT
DO $$
DECLARE t text; suffix text;
BEGIN
  FOREACH t IN ARRAY ARRAY['GT-CABECERA_ASISTENCIA','GT-ASISTENCIA_PERSONAL','GT-TAREO_PERSONAL','GT-DISEÑO_PHOTOCHEK','MATRIZ-PHOTOCHEK'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    suffix := lower(replace(replace(replace(t,'-','_'),'Ñ','N'),' ','_'));
    EXECUTE format('DROP POLICY IF EXISTS appgt_select_perm_%s ON public.%I', suffix, t);
    EXECUTE format('CREATE POLICY appgt_select_perm_%s ON public.%I FOR SELECT TO authenticated USING (appgt_can_view_table(%L))', suffix, t, t);
    EXECUTE format('DROP POLICY IF EXISTS appgt_insert_perm_%s ON public.%I', suffix, t);
    EXECUTE format('CREATE POLICY appgt_insert_perm_%s ON public.%I FOR INSERT TO authenticated WITH CHECK (appgt_can_insert_table(%L))', suffix, t, t);
    EXECUTE format('DROP POLICY IF EXISTS appgt_update_perm_%s ON public.%I', suffix, t);
    EXECUTE format('CREATE POLICY appgt_update_perm_%s ON public.%I FOR UPDATE TO authenticated USING (appgt_can_update_table(%L)) WITH CHECK (appgt_can_update_table(%L))', suffix, t, t, t);
    EXECUTE format('DROP POLICY IF EXISTS appgt_delete_perm_%s ON public.%I', suffix, t);
    EXECUTE format('CREATE POLICY appgt_delete_perm_%s ON public.%I FOR DELETE TO authenticated USING (appgt_can_delete_table(%L))', suffix, t, t);

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

-- 10) Permisos base: ajusta user_id si prefieres usuario por usuario.
-- Inserta permisos para tablas nuevas a usuarios existentes que ya tienen permisos en gestión humana.
INSERT INTO public."PERMISOS_DE_USUARIOS_APPGT" (user_id, tabla_destino, can_view, can_insert, can_update, can_delete, can_export, can_import, activo, created_at, updated_at, estado_sync, eliminado)
SELECT DISTINCT user_id, t.tabla, true, true, true, false, true, true, true, now(), now(), 'sincronizado', false
FROM public."PERMISOS_DE_USUARIOS_APPGT" p
CROSS JOIN (VALUES ('GT-CABECERA_ASISTENCIA'), ('GT-ASISTENCIA_PERSONAL'), ('GT-TAREO_PERSONAL'), ('GT-DISEÑO_PHOTOCHEK')) AS t(tabla)
WHERE p.user_id IS NOT NULL
ON CONFLICT DO NOTHING;
