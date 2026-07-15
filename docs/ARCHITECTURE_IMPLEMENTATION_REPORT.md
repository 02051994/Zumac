# Informe de implementación de la arquitectura ZUMAC

Fecha de validación: 2026-07-15

Proyecto Supabase productivo: `dfyfdtlgmyjbxjpojhnc` (`DataFundoGT`)

Rama local: `feature/visual-builder`

Versión Flutter: `0.0.12+12`

## Resultado

La arquitectura maestra quedó implementada desde la base offline existente hasta
el constructor visual versionado. Flutter no ejecuta SQL administrativo: guarda
borradores y llama RPC protegidos; Supabase valida, publica y audita. Las
migraciones se probaron primero dentro de transacciones con `ROLLBACK` y después
se aplicaron al proyecto productivo.

Los formatos existentes se conservaron como plantillas. Crear o editar una
configuración no modifica la plantilla original. La edición de una entidad
publicada crea una nueva versión y conserva el código técnico para mantener
navegación, permisos, sincronización y datos históricos.

## Etapas nuevas y commits

| Etapa | Resultado | Commit |
| --- | --- | --- |
| UI móvil | Tarjetas, búsqueda, paginación y formulario ancho/responsive | `835a8aa` |
| Plantillas | Fotografía versionada de rubros, navegación, formatos, tablas, campos y matrices | `a08bfb1` |
| Backend administrativo | Borradores, validación, publicación, migraciones y auditoría protegidas | `abeda65` |
| Asistentes iniciales | Creación guiada de secciones y módulos | `957770b` |
| Publicación atómica | Formato, tablas, campos y matrices en una sola transacción | `82e6bf4` |
| Constructor completo | Rubros y asistente encadenado de formato/tabla/campo/matriz | `0c5f94e` |
| Edición versionada | Nueva versión de configuraciones publicadas y vista previa segura | `11e7634` |
| Vista e historial | Búsqueda, jerarquía, estructura, versiones y auditoría en Flutter | `c68fa65` |

## Mapa de archivos

- `lib/features/configuration_admin/configuration_admin_page.dart`: panel del
  constructor, configuraciones publicadas y borradores.
- `lib/features/configuration_admin/configuration_entity_wizard_page.dart`:
  asistentes de rubro, sección y módulo.
- `lib/features/configuration_admin/format_structure_wizard_page.dart`:
  asistente formato → tabla → campo → matriz.
- `lib/features/configuration_admin/configuration_preview_page.dart`:
  previsualización de jerarquía/estructura e historial.
- `lib/features/configuration_admin/configuration_admin_repository.dart`:
  único punto Flutter para los RPC administrativos.
- `lib/features/configuration_admin/format_structure_validator.dart`:
  validación local y normalización de plantillas heredadas.
- `lib/features/formats/widgets/mobile_records_list.dart`: vista móvil rica de
  registros dinámicos.
- `lib/features/formats/form_runner_page.dart`: formulario dinámico responsive;
  conserva dropdowns, fórmulas y reglas declarativas.
- `supabase/migrations/202607150005_configuration_templates.sql`: paquetes y
  plantillas versionadas.
- `supabase/migrations/202607150006_configuration_admin_backend.sql`: backend
  seguro de borradores, validación, publicación, DDL controlado y auditoría.
- `supabase/migrations/202607150007_atomic_format_structures.sql`: validación y
  publicación atómica de estructuras completas.
- `supabase/migrations/202607150008_versioned_editing_and_preview.sql`: edición
  versionada, previsualización e historial.

## Flujo del constructor

```text
ADMIN/GESTOR
  -> selecciona desde cero, plantilla o nueva versión
  -> responde preguntas indispensables
  -> Flutter valida estructura y dependencias
  -> RPC guarda BORRADOR
  -> Supabase vuelve a validar
  -> GESTOR deja el borrador listo / ADMIN publica
  -> transacción atómica actualiza configuración + versión + auditoría
  -> usuarios ejecutan "Actualizar datos"
  -> SQLite recibe el delta y reconstruye navegación/formularios
```

## Garantías implementadas

- Las plantillas publicadas son inmutables; una copia recibe nuevos códigos.
- El código de una configuración ya publicada queda bloqueado al editarla.
- Una publicación estructural se revierte completa si falla cualquier hijo.
- Las tablas o columnas físicas existentes se actualizan sin duplicarlas.
- Quitar un campo de configuración no elimina automáticamente su columna física,
  evitando pérdida accidental de datos.
- Las funciones internas base no son ejecutables por `authenticated` ni `anon`.
- Solo `ADMIN` publica; `GESTOR` puede crear, editar y validar borradores.
- Cada publicación crea versión de configuración, plantilla e historial de
  auditoría.

## Verificación en Supabase productivo

- Plantillas totales: 2,796; versiones actuales duplicadas: 0.
- Plantillas actuales: 1 rubro, 5 secciones, 21 módulos, 96 formatos, 52 tablas,
  2,304 campos activos y 317 matrices activas.
- Filas fuente de campos intactas: 2,305.
- Funciones de formato atómico: 3; acceso `authenticated`: 3; acceso `anon`: 0.
- Wrappers administrativos públicos autenticados: 7; funciones base internas
  ejecutables por `authenticated`: 0.
- Triggers versionados: 11; event trigger de metadatos: habilitado (`O`).
- Restos de pruebas reversibles: 0.
- Se probó una edición real de sección: una fila activa y dos versiones dentro
  de la transacción antes de `ROLLBACK`.
- Se probó un formato real con 1 tabla, 9 campos y 8 matrices: publicación
  atómica correcta y reversión completa.

## Validaciones locales

- Análisis focalizado del constructor: 0 problemas.
- Suite integral: 26 de 26 pruebas aprobadas.
- Análisis integral: 0 errores y 157 advertencias/informaciones históricas; el
  comando retorna estado no cero por esas advertencias, no por fallos de build.
- Cobertura funcional: conectividad móvil, snapshots/deltas SQLite, aislamiento
  por usuario/empresa, conflictos, reglas dinámicas, asistentes, clonación de
  plantillas, normalización heredada y UI móvil de registros.
- APK release generado correctamente en
  `build/app/outputs/flutter-apk/app-release.apk`.
- Metadatos verificados: aplicación `Zumac`, `versionName=0.0.12`,
  `versionCode=12`.
- Tamaño: 91,461,184 bytes (87.2 MB).
- SHA-256:
  `A317653DAA9A2D29A9D651F10AFBD18F6D5F2E3B1CC9B2F7057B2340B0CCCB88`.

## Riesgos restantes

1. Las advertencias históricas del análisis integral no se corrigieron en masa
   para evitar mezclar una refactorización extensa con esta entrega funcional.
2. Eliminar físicamente columnas o tablas debe seguir siendo una operación
   administrativa separada, con respaldo y autorización explícita.
3. Antes de publicar el APK mediante el actualizador interno debe subirse el
   archivo al bucket `actualizaciones-appgt` y registrar `0.0.12` en
   `appgt_versiones`; generar el APK local no realiza esa publicación.
4. Los usuarios deben pulsar `Actualizar datos` después de una publicación para
   recibir la nueva configuración local.

## Reversa

Las migraciones son transaccionales y no borran datos operativos. Para una
reversa se debe retirar primero el consumidor Flutter y después restaurar las
funciones/versiones anteriores. No se recomienda borrar tablas de auditoría,
borradores, migraciones o plantillas si ya contienen actividad administrativa.
