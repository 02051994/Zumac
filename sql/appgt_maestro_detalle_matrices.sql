-- APPGT - Soporte maestro-detalle / wizard por iterador
-- Ejecutar en Supabase SQL Editor.

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

ALTER TABLE public."MATRIZ_CAMPOS_FORMATO_APPGT"
ADD COLUMN IF NOT EXISTS grupo_captura text;

COMMENT ON COLUMN public."MATRIZ_FORMATO_TABLAS_APPGT".tipo_relacion IS 'Tipo de relación entre tablas del formato: maestro, detalle, cabecera.';
COMMENT ON COLUMN public."MATRIZ_FORMATO_TABLAS_APPGT".tabla_padre IS 'Tabla padre/cabecera para una tabla detalle.';
COMMENT ON COLUMN public."MATRIZ_FORMATO_TABLAS_APPGT".campo_pk_padre IS 'Campo llave en tabla padre. Recomendado: id_local.';
COMMENT ON COLUMN public."MATRIZ_FORMATO_TABLAS_APPGT".campo_fk_hijo IS 'Campo en tabla detalle que recibirá el id de cabecera. Ejemplo: id_inspeccion.';
COMMENT ON COLUMN public."MATRIZ_FORMATO_TABLAS_APPGT".es_cabecera IS 'Marca la tabla como cabecera del formulario.';
COMMENT ON COLUMN public."MATRIZ_FORMATO_TABLAS_APPGT".es_detalle IS 'Marca la tabla como detalle repetible del formulario.';
COMMENT ON COLUMN public."MATRIZ_FORMATO_TABLAS_APPGT".campo_iterador IS 'Campo que identifica la repetición. Ejemplo: numero_muestra.';
COMMENT ON COLUMN public."MATRIZ_FORMATO_TABLAS_APPGT".iterador_desde IS 'Valor inicial del iterador. Ejemplo: 1.';
COMMENT ON COLUMN public."MATRIZ_FORMATO_TABLAS_APPGT".iterador_hasta IS 'Valor final del iterador. Ejemplo: 4.';
COMMENT ON COLUMN public."MATRIZ_FORMATO_TABLAS_APPGT".copiar_campos_desde_padre IS 'Campos separados por coma que se copian desde cabecera hacia detalle.';
COMMENT ON COLUMN public."MATRIZ_FORMATO_TABLAS_APPGT".modo_captura IS 'Modo de captura. Ejemplo: cabecera, wizard_iterador.';
COMMENT ON COLUMN public."MATRIZ_CAMPOS_FORMATO_APPGT".grupo_captura IS 'Grupo lógico del campo dentro del formulario. Ejemplo: CABECERA o DETALLE.';
