# Migraciones de Supabase

Esta carpeta es la fuente versionada de los cambios del proyecto DataFundoGT.

Reglas:

1. Ningun cambio de produccion se aplica manualmente sin una migracion equivalente.
2. Cada migracion debe ser idempotente cuando sea razonable y ejecutarse dentro de una transaccion.
3. Las migraciones de datos incluyen consultas de validacion antes y despues.
4. Los cambios destructivos requieren respaldo y una estrategia explicita de reversa.
5. Las funciones `security definer` deben fijar `search_path` y conceder solo los permisos necesarios.

Los scripts historicos de `sql/` se conservan como referencia y no se consideran una historia de migraciones confiable.
