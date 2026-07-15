-- Generador dinámico de códigos visibles para campos configurados como tipo_ui = 'hidden_id'.
-- Usa el prefijo de MATRIZ_CAMPOS_FORMATO_APPGT.id_generador.
-- Ejemplo: id_generador = 'ALM-' => ALM-1, ALM-2, ALM-3...
-- Importante: Flutter solo envía id_local. El código visible se asigna en Supabase al sincronizar.

CREATE TABLE IF NOT EXISTS public.appgt_hidden_id_counters (
  tabla_destino text NOT NULL,
  campo text NOT NULL,
  prefijo text NOT NULL DEFAULT '',
  ultimo bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (tabla_destino, campo, prefijo)
);

CREATE OR REPLACE FUNCTION public.appgt_set_hidden_ids()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  cfg record;
  siguiente bigint;
  payload jsonb;
BEGIN
  payload := to_jsonb(NEW);

  FOR cfg IN
    SELECT
      campo,
      COALESCE(NULLIF(id_generador, ''), '') AS prefijo
    FROM public."MATRIZ_CAMPOS_FORMATO_APPGT"
    WHERE tabla_destino = TG_TABLE_NAME
      AND COALESCE(activo, true) = true
      AND lower(COALESCE(tipo_ui, '')) = 'hidden_id'
      AND campo IS NOT NULL
      AND trim(campo) <> ''
  LOOP
    -- Solo genera si la columna existe en el registro y viene vacía/nula.
    IF payload ? cfg.campo THEN
      IF COALESCE(payload ->> cfg.campo, '') = '' THEN
        INSERT INTO public.appgt_hidden_id_counters(tabla_destino, campo, prefijo, ultimo)
        VALUES (TG_TABLE_NAME, cfg.campo, cfg.prefijo, 1)
        ON CONFLICT (tabla_destino, campo, prefijo)
        DO UPDATE SET ultimo = public.appgt_hidden_id_counters.ultimo + 1
        RETURNING ultimo INTO siguiente;

        payload := jsonb_set(
          payload,
          ARRAY[cfg.campo],
          to_jsonb(cfg.prefijo || siguiente::text),
          true
        );
      END IF;
    END IF;
  END LOOP;

  NEW := jsonb_populate_record(NEW, payload);
  RETURN NEW;
END;
$$;

-- Crea el trigger solo en tablas que tienen campos hidden_id configurados en la matriz.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT DISTINCT tabla_destino
    FROM public."MATRIZ_CAMPOS_FORMATO_APPGT"
    WHERE lower(COALESCE(tipo_ui, '')) = 'hidden_id'
      AND COALESCE(activo, true) = true
      AND tabla_destino IS NOT NULL
      AND trim(tabla_destino) <> ''
  LOOP
    IF EXISTS (
      SELECT 1
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name = r.tabla_destino
    ) THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_appgt_set_hidden_ids ON public.%I;', r.tabla_destino);
      EXECUTE format(
        'CREATE TRIGGER trg_appgt_set_hidden_ids BEFORE INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION public.appgt_set_hidden_ids();',
        r.tabla_destino
      );
    ELSE
      RAISE NOTICE 'Tabla no existe, no se crea trigger: %', r.tabla_destino;
    END IF;
  END LOOP;
END $$;

-- Refuerza el control anti-duplicado por id_local en las tablas que lo tengan.
DO $$
DECLARE
  r record;
  index_name text;
BEGIN
  FOR r IN
    SELECT table_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name = 'id_local'
  LOOP
    index_name := 'ux_' || regexp_replace(lower(r.table_name), '[^a-z0-9]+', '_', 'g') || '_id_local';
    EXECUTE format(
      'CREATE UNIQUE INDEX IF NOT EXISTS %I ON public.%I (id_local);',
      index_name,
      r.table_name
    );
  END LOOP;
END $$;
