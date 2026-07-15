-- Ejecutar en Supabase SQL Editor si la vista Windows muestra 0 registros
-- aunque la tabla tenga datos. Esto habilita SELECT para usuarios autenticados.

ALTER TABLE public."SN-REGISTRO_PLAGAS_ENFERMEDADES" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "appgt_select_sn_registro_plagas_enfermedades" ON public."SN-REGISTRO_PLAGAS_ENFERMEDADES";
CREATE POLICY "appgt_select_sn_registro_plagas_enfermedades"
ON public."SN-REGISTRO_PLAGAS_ENFERMEDADES"
FOR SELECT
TO authenticated
USING (true);

GRANT SELECT ON public."SN-REGISTRO_PLAGAS_ENFERMEDADES" TO authenticated;
