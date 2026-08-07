# ZUMAC Offline First

Aplicación Flutter con Supabase y SQLite para navegación, formularios y tablas
dinámicas. Incluye trabajo online/offline, sincronización incremental,
multiempresa, reglas declarativas y constructor visual versionado.

## Funciones principales

- Login online/offline y actualización autenticada de datos.
- Navegación rubro → sección → módulo → formato.
- Formularios dinámicos con dropdowns, fórmulas, condiciones y validaciones.
- Tablas móviles responsive con búsqueda, paginación, edición y eliminación.
- Cola local SQLite, reintentos y conflictos trazables.
- Constructor ADMIN/GESTOR para rubros, secciones, módulos, formatos, tablas,
  campos y matrices.
- Plantillas inmutables, borradores, vista previa, versiones y auditoría.
- Publicación atómica desde RPC seguros; Flutter no ejecuta SQL administrativo.
- Zumac Alerts con reglas configurables, prueba previa, Cron, deduplicación y
  bandeja de eventos por empresa.
- Zumac Actions con tareas, aprobaciones, responsables, comentarios y evidencia.
- Zumac Metrics con dashboards por empresa, constructor de gráficos, relaciones
  entre tablas y filtros compartidos.
- Dictado por micrófono de preguntas cortas en Zumac Consultor.

## Configuración

Definir la URL y la clave publicable (nunca `service_role`) en:

`lib/config/supabase_config.dart`

## Verificación y compilación

```text
flutter clean
flutter pub get
flutter test
flutter build apk --release
```

APK esperado:

`build/app/outputs/flutter-apk/app-release.apk`

## Uso del constructor

1. Ingresar con un usuario `ADMIN` o `GESTOR`.
2. Abrir **Constructor visual** desde la navegación administrativa.
3. Crear desde cero, copiar una plantilla o abrir una configuración publicada y
   elegir **Nueva versión**.
4. Responder el asistente y guardar/validar.
5. Un usuario `ADMIN` confirma la publicación.
6. Los dispositivos ejecutan **Actualizar datos** para descargar el cambio.

La documentación técnica y las garantías de despliegue están en
`docs/ARCHITECTURE_IMPLEMENTATION_REPORT.md`.

La operación de Zumac Consultor, Creator, motores de IA, sincronización por
plataforma, escalabilidad y pasos pendientes de producción está documentada en
`docs/ARQUITECTURA_OPERATIVA_IA_Y_SINCRONIZACION.md`.

El modelo de datos, seguridad, programación automática y despliegue de Alerts,
Actions y dictado está en `docs/ZUMAC_ALERTS_ACTIONS_Y_DICTADO.md`.

El modelo y uso del constructor de dashboards está en `docs/ZUMAC_METRICS.md`.
