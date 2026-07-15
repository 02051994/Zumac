ALTER TABLE public."MATRIZ_CAMPOS_FORMATO_APPGT"
ADD COLUMN IF NOT EXISTS aplicar_formato_condicional_tabla boolean DEFAULT false;
