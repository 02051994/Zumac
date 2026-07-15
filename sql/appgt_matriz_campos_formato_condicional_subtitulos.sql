ALTER TABLE public."MATRIZ_CAMPOS_FORMATO_APPGT"
ADD COLUMN IF NOT EXISTS formato_condicional_campo text,
ADD COLUMN IF NOT EXISTS color_texto text,
ADD COLUMN IF NOT EXISTS color_fondo text,
ADD COLUMN IF NOT EXISTS color_borde text,
ADD COLUMN IF NOT EXISTS sub_titulo text,
ADD COLUMN IF NOT EXISTS fila_sub_titulo integer;
