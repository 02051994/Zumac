# Zumac Creator — Documento a App

## Resultado

Zumac Creator incorpora un flujo guiado para convertir una foto, una imagen o
un PDF de un registro empresarial en un borrador de formato. El análisis de IA
no publica configuraciones ni reemplaza datos existentes. Todo contenido
propuesto conserva `estado_revision_ia = GENERADA_IA` hasta que un administrador
lo revise y ejecute la publicación normal del Creator.

## Flujo funcional

1. **Origen:** cámara, galería o PDF (`JPG`, `PNG`, `WEBP`, `PDF`, máximo 18 MB).
2. **Calidad local:** valida archivo, resolución, exposición, contraste y
   nitidez. Una imagen insuficiente se bloquea con el mensaje para repetirla.
3. **Motor seleccionable:** **Básico** usa `Zumac AI Engine` como opción
   predeterminada, gratuita y autocontenida. **Avanzado** usa OpenAI si la
   empresa lo autoriza y el usuario tiene una suscripción individual con saldo.
4. **Legibilidad visual:** la IA vuelve a evaluar cortes, sombras, texto pequeño
   y ambigüedad. No se permite continuar si el documento no puede leerse con
   seguridad.
5. **Encabezados:** se presenta una tabla de filas y columnas. El usuario
   confirma explícitamente en qué fila están los encabezados.
6. **Corrección:** se muestra el texto original y la sugerencia. El usuario puede
   corregir nombre, tabla, sección, tipo, obligatoriedad y visibilidad; también
   puede añadir u omitir campos.
7. **Diseño:** se elige el layout de captura (`VERTICAL`, `DOS_COLUMNAS`,
   `SECCIONES`, `COMPACTO`) y de registros (`TABLA`, `TARJETAS`, `LISTA`).
8. **Vista previa:** se visualizan tanto el formulario como registros de ejemplo
   antes de convertir.
9. **Conversión:** se crea un borrador mediante el repositorio y validador
   atómico existente. Se abre en el editor estándar para la revisión final.
10. **Aprobación:** sólo la publicación administrativa transforma la sesión en
    `APROBADA`. Los layouts se sincronizan al runtime offline.

## Componentes

- `creator_document_import_page.dart`: experiencia guiada completa.
- `creator_document_quality_service.dart`: control preventivo de imágenes.
- `creator_document_models.dart`: análisis estructurado y generación compatible
  con el validador de formatos.
- `appgt-analyze-format/index.ts`: análisis multimodal autenticado y salida JSON
  estricta; enruta al motor propio o a OpenAI según la selección autorizada.
- `services/zumac_ai_engine`: servicio OCR propio para imágenes y PDF, con
  detección de calidad, encabezados, campos, tipos y relaciones.
- `202607310018_creator_document_to_app.sql`: sesiones multiempresa, RLS,
  auditoría, estados y propagación de layouts.
- `202607310019_zumac_ai_engine_billing_and_features.sql`: autorizaciones por
  empresa, planes, solicitudes de pago, suscripciones y consumo por usuario.
- `MobileRecordsList`: renderizado real de tabla, tarjetas o lista en el runtime.

## Privacidad y seguridad

- El archivo original se procesa en memoria y no se guarda por defecto.
- La base conserva nombre, MIME, tamaño, SHA-256, métricas, análisis y revisión.
- Las sesiones están aisladas por `empresa_id` y requieren permisos de gestión
  del Creator.
- La Edge Function valida el JWT, la empresa activa y la propiedad de la
  importación antes de usar cualquier motor.
- `OPENAI_API_KEY` existe únicamente como secreto del servidor.
- El motor propio se protege con un secreto compartido y no cobra por consulta.
- OpenAI registra `input_tokens`, `cached_input_tokens` y `output_tokens`; el
  costo se descuenta solamente de la suscripción del usuario autenticado.
- La salida usa JSON Schema estricto para evitar respuestas libres o estructuras
  incompatibles.

## Despliegue

Aplicar primero las migraciones en orden y después desplegar la función:

```text
supabase db push
supabase secrets set ZUMAC_AI_ENGINE_URL=https://ai.ejemplo.com
supabase secrets set ZUMAC_AI_ENGINE_SHARED_SECRET=<secreto-interno>
supabase secrets set OPENAI_API_KEY=<secreto>
supabase secrets set OPENAI_DOCUMENT_MODEL=gpt-5.6-sol
supabase functions deploy appgt-analyze-format
```

`OPENAI_API_KEY` y `OPENAI_DOCUMENT_MODEL` solo son necesarios para el plan
avanzado. El motor gratuito requiere desplegar el contenedor de
`services/zumac_ai_engine` y configurar su URL HTTPS y secreto.

La función usa entradas de imagen/PDF y Structured Outputs conforme a las guías
oficiales:

- https://developers.openai.com/api/docs/guides/images-vision
- https://developers.openai.com/api/docs/guides/file-inputs
- https://developers.openai.com/api/docs/guides/structured-outputs

## Criterios operativos

- Una imagen debe tener al menos 900 píxeles en su lado corto.
- Se bloquean exposición extrema, contraste insuficiente y baja energía de
  bordes. La evaluación visual del modelo sigue siendo obligatoria.
- El umbral evita errores evidentes, pero no sustituye la revisión humana.
- Los PDF con firma válida pasan a análisis visual; un PDF escaneado ilegible se
  rechaza en el servidor.
- Los documentos con baja confianza muestran advertencias y preguntas al
  usuario antes de crear el borrador.

## Verificación

Las pruebas cubren:

- imagen uniforme rechazada;
- imagen contrastada y nítida aceptada;
- firma PDF válida e inválida;
- corrección sugerida `Vareidad → Variedad`;
- payload compatible con el validador de Zumac Creator;
- estructuras simples y cabecera–detalle;
- persistencia de fila de encabezados, estado y layouts;
- renderizado de registros como tabla, tarjetas y lista.

Zumac AI Engine funciona sin una API de IA de terceros. La opción avanzada
requiere que la migración, la Edge Function y el secreto de OpenAI estén
desplegados en el proyecto Supabase correspondiente.
