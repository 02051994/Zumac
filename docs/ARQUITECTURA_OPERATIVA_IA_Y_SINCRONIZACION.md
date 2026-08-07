# Zumac Consultor, Creator, IA y sincronización

## Propósito

Este documento describe cómo funcionan las piezas que convierten a Zumac en
una plataforma multiempresa, cómo se protegen los datos y qué decisiones deben
mantenerse cuando aumenten empresas, formatos y registros.

La arquitectura separa cuatro responsabilidades:

1. Flutter presenta la experiencia y mantiene una caché local controlada.
2. Supabase autentica, aplica RLS, almacena configuración, conocimiento y datos.
3. Zumac AI Engine analiza documentos con OCR sin costo por consulta.
4. OpenAI es un motor avanzado opcional, con plan y saldo por usuario.

## Estado de producción

| Componente | Estado | Acción pendiente |
| --- | --- | --- |
| Aplicación web | Publicada | Volver a compilar tras estos cambios |
| Migraciones 001–019 | Aplicadas | Ninguna |
| Migraciones 020–021 | En el proyecto | Ejecutar `supabase db push` |
| Clave de OpenAI | Configurada en Supabase | Mantenerla solo como secreto |
| Edge Function de análisis | Código listo | Redesplegar después de configurar el motor |
| APIs de Google Cloud | Habilitadas | Ninguna |
| Zumac AI Engine en Cloud Run | No desplegado | Ejecutar `gcloud run deploy` |
| Cobro automático | No conectado | Elegir proveedor, crear cuenta y configurar webhook |

## Zumac Creator: motores Básico y Avanzado

### Básico

El modo Básico usa `services/zumac_ai_engine`. Es gratuito por consulta y no
envía el documento a OpenAI. Sus fortalezas son:

- validar tamaño, contraste, exposición y nitidez;
- leer texto impreso mediante OCR;
- proponer fila de encabezados;
- detectar campos y tipos comunes;
- construir relaciones simples;
- devolver el contrato JSON que consume Creator.

Sus límites naturales son documentos manuscritos, tablas irregulares, texto
dañado, encabezados ambiguos y fotografías con perspectiva compleja. Si el
archivo no es legible se bloquea la conversión y se solicita otra imagen.

### Avanzado

El modo Avanzado usa OpenAI y mejora principalmente:

- interpretación del contexto visual, no solo del texto OCR;
- comprensión de formularios complejos o con secciones irregulares;
- corrección de nombres ambiguos y typos;
- inferencia de grupos, relaciones y tipos de campo;
- explicación de dudas que el usuario debe confirmar.

No convierte texto ilegible en información confiable. Ambos motores mantienen
la revisión humana y el estado `GENERADA_IA` antes de publicar.

La opción Avanzado solo se puede usar si la empresa autoriza la función y el
usuario autenticado tiene una suscripción vigente con créditos. Los créditos
son personales: otro usuario de la misma empresa no puede consumirlos.

## Zumac Consultor

### Preguntas conceptuales

`KnowledgeRetrievalEngine` consulta fuentes configurables por prioridad. Aplica
coincidencia exacta, difusa y semántica opcional, y responde solo con contenido
recuperado. Las citas incluyen fuente y estado de revisión. Cuando una relación
contiene `documento_destino_id`, también recupera el documento conectado y
puede usar su contenido como evidencia. La expansión está acotada por
profundidad, cantidad y relevancia para impedir ciclos o respuestas ruidosas.

La conversación actual se conserva solamente en memoria. La interfaz mantiene
todos los turnos visibles, deja el campo de la siguiente pregunta al final y
el botón **Limpiar** borra mensajes y contexto. No se persiste historial en
Supabase mientras esta función no sea habilitada expresamente.

### Preguntas operativas y cálculos

`ZumacConsultantService` descubre tablas y campos desde la configuración; no
codifica una respuesta para cada pregunta. Puede:

- filtrar por hoy, ayer, fecha exacta, semana, mes actual o mes escrito;
- contar personas únicas por DNI/identificador/nombre;
- contar registros y distribuir estados;
- comparar umbrales numéricos;
- cruzar asistencia, tareo, plagas, productos y stock;
- mantener el tema en preguntas de seguimiento.

Ejemplo: `¿Cuántos trabajadores asistieron en total en el mes de julio?`
detecta julio del año actual, selecciona formatos de asistencia, descarta
inasistencias y cuenta trabajadores únicos aunque tengan varias marcaciones.

Para evitar una carga infinita:

- se consultan como máximo cuatro tablas normales u ocho en cruces;
- las consultas con periodo filtran primero en Supabase;
- cada tabla remota tiene un límite de siete segundos;
- la pantalla detiene toda consulta que exceda treinta segundos y muestra una
  recomendación para precisar formato o fecha;
- la caché local sigue siendo una fuente válida si una tabla remota falla.

## Sincronización y rendimiento

### Primera entrada

En Windows, Android e iOS, la primera entrada descarga configuración,
catálogos y registros necesarios para trabajo offline. Las entradas siguientes
usan checkpoints y descargan deltas.

En web, la primera entrada guarda localmente configuración, permisos,
dropdowns y catálogos, pero no copia todas las tablas operativas. Los registros
se consultan directamente por páginas desde Supabase. Esto evita que IndexedDB
crezca con miles o millones de filas que ya están disponibles por internet.

### Actualización incremental

`appgt_tablas_cambiadas_desde` identifica qué tablas cambiaron desde el último
checkpoint. La migración 020 instala triggers sobre matrices, formatos, tablas
operativas y fuentes de dropdown conocidas. Por eso una modificación hecha en
Creator o directamente en Supabase invalida la caché correspondiente.

Existe una comprobación completa de configuración cada veinticuatro horas como
red de seguridad. El botón Actualizar ya no fuerza snapshots completos en cada
uso.

### Dropdowns y eliminaciones

Una fuente de dropdown que cambia se descarga como snapshot completo. La base
local elimina solamente los valores de ese catálogo y guarda su versión nueva.
No se borran catálogos de otras fuentes y no quedan opciones eliminadas en
Supabase. Esta operación es transaccional.

### Reglas para crecer sin degradación

- paginar siempre tablas de registros;
- no renderizar datasets completos en una grilla;
- agregar `updated_at` e índices a nuevas tablas sincronizables;
- registrar nuevas tablas como destinos o fuentes configuradas;
- filtrar agregaciones por fecha en el servidor;
- usar exportación completa solo bajo demanda;
- vigilar tamaño de respuesta, tiempo p95 y errores por tabla;
- no convertir la caché web en una réplica completa de Supabase.

## Mapa del código

| Archivo | Responsabilidad |
| --- | --- |
| `lib/core/services/zumac_consultant_service.dart` | Intenciones operativas, periodos, cruces, cálculos y respuestas |
| `lib/core/services/knowledge_retrieval_engine.dart` | Recuperación priorizada, memoria y citas |
| `lib/core/services/sync_service.dart` | Bootstrap, deltas, permisos, catálogos y política por plataforma |
| `lib/core/services/local_db.dart` | Transacciones locales, snapshots, deltas, cola y caché |
| `lib/features/modules/modules_page.dart` | Interfaz del Consultor, progreso y límites de tiempo |
| `lib/features/configuration_admin/creator_document_import_page.dart` | Flujo Documento → App y selector de motor |
| `lib/features/configuration_admin/creator_document_quality_service.dart` | Control local de calidad de imagen/PDF |
| `lib/features/configuration_admin/creator_document_models.dart` | Contrato del análisis y borrador compatible con Creator |
| `supabase/functions/appgt-analyze-format/index.ts` | Autenticación, enrutamiento de motor y consumo |
| `services/zumac_ai_engine/app/main.py` | OCR, calidad, encabezados, campos y relaciones |
| `supabase/migrations/202607310017_zumac_knowledge_engine.sql` | Conocimiento, fuentes, relaciones y revisión |
| `supabase/migrations/202607310018_creator_document_to_app.sql` | Importaciones y estado `GENERADA_IA` |
| `supabase/migrations/202607310019_zumac_ai_engine_billing_and_features.sql` | Productos, planes, saldo y consumo individual |
| `supabase/migrations/202608010020_incremental_sync_tracking.sql` | Seguimiento de cambios para sincronización incremental |
| `supabase/migrations/202608010021_permission_id_type_fixes.sql` | Compatibilidad de IDs de texto en RPC de permisos |

## Inicio y acceso

Inicio presenta cinco herramientas centradas y con nombres simples:
**Consultor**, **Creator**, **Metrics**, **Alerts** y **Actions**. Consultor abre
la sesión temporal; Creator solicita elegir entre **Editar existentes** y
**Crear**; Metrics abre el sistema actual de reportes. Alerts y Actions se
muestran como componentes en preparación para no simular funciones que todavía
no tienen motor de servidor.

En el acceso, Enter desde el usuario mueve el foco a la contraseña y Enter
desde la contraseña ejecuta el mismo flujo seguro que el botón Ingresar. Antes
de mostrar la carga, se retira el foco y se vuelve a ocultar la contraseña para
que ningún fotograma de transición la deje visible.

## Despliegue pendiente del motor gratuito

Las APIs de Cloud Run, Cloud Build y Artifact Registry ya están habilitadas.
Ejecutar en una sola ventana de PowerShell:

```powershell
cd C:\app_zumac_14_07_12y10\services\zumac_ai_engine

$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$secretBytes = New-Object byte[] 48
$rng.GetBytes($secretBytes)
$rng.Dispose()
$engineSecret = [Convert]::ToBase64String($secretBytes)

gcloud.cmd run deploy zumac-ai-engine `
  --source . `
  --project zumac-ai-engine `
  --region southamerica-west1 `
  --platform managed `
  --allow-unauthenticated `
  --port 8080 `
  --cpu 1 `
  --memory 1Gi `
  --concurrency 1 `
  --min-instances 0 `
  --max-instances 2 `
  --timeout 300 `
  --set-env-vars "ZUMAC_AI_ENGINE_SHARED_SECRET=$engineSecret"

$engineUrl = (gcloud.cmd run services describe zumac-ai-engine `
  --region southamerica-west1 `
  --project zumac-ai-engine `
  --format="value(status.url)").Trim()

Invoke-RestMethod "$engineUrl/health"

cd C:\app_zumac_14_07_12y10
npx.cmd supabase@latest secrets set `
  "ZUMAC_AI_ENGINE_URL=$engineUrl" `
  "ZUMAC_AI_ENGINE_SHARED_SECRET=$engineSecret"

npx.cmd supabase@latest functions deploy appgt-analyze-format

Remove-Variable rng, secretBytes, engineSecret, engineUrl `
  -ErrorAction SilentlyContinue
```

`--allow-unauthenticated` permite que la Edge Function alcance la URL. El
endpoint de análisis sigue protegido por el secreto compartido; `/health` es
público y no procesa documentos.

## Cobro automático

Actualmente Zumac crea la solicitud, controla vigencia, saldo y consumo, pero
no confirma pagos por sí solo. Para completar el cobro automático se requiere:

1. elegir un proveedor de checkout compatible con la empresa;
2. crear la cuenta comercial y completar su validación;
3. obtener clave secreta, clave pública y secreto de webhook;
4. crear una Edge Function que genere la sesión de pago;
5. recibir el webhook firmado y validar monto, moneda, orden y estado;
6. llamar con `service_role` a `appgt_confirmar_pago_plan_ia_v1`;
7. probar pago aprobado, rechazado, duplicado, reembolso y webhook repetido.

La confirmación debe ser idempotente. Nunca se deben acreditar tokens desde
Flutter ni aceptar como prueba el retorno del navegador.

## Publicación de esta versión

Después de validar las pruebas:

```powershell
cd C:\app_zumac_14_07_12y10

npx.cmd supabase@latest db push

flutter clean
flutter pub get
flutter test
flutter build web --release --base-href /Zumac/

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\scripts\publish_web.ps1" `
  -SkipBuild `
  -Message "Optimiza Zumac Consultor, Creator IA y sincronización"
```

El script publica solo `build/web` en GitHub Pages. El código fuente local no
se mezcla con el contenido de la rama publicada.
