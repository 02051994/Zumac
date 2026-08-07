# Motor de conocimiento de Zumac Consultor

## Resultado

Zumac Consultor dispone de una capa de conocimiento separada del análisis de
registros operativos. Una pregunta conceptual se resuelve exclusivamente con
documentos recuperados; una pregunta como “¿hay pH mayores a 6 hoy?” conserva
el flujo dinámico de consulta de registros existente.

## Flujo de recuperación

1. `FUENTES_CONOCIMIENTO_APPGT` entrega las fuentes activas ordenadas por
   `prioridad`. La primera fuente inicial es `MATRIZ_FORMATOS_APPGT` con
   prioridad 10.
2. El motor prueba coincidencia exacta, coincidencia difusa y, cuando la fuente
   y un proveedor de embeddings están habilitados, coincidencia semántica.
3. Si el mejor resultado no alcanza `umbral_suficiencia`, continúa con la
   siguiente fuente automáticamente.
4. La respuesta se compone solo con secciones presentes en los documentos
   recuperados y siempre conserva citas y estado de revisión.
5. Si ninguna fuente aporta evidencia suficiente, responde que la información
   no fue encontrada en la base de conocimiento de la empresa.

La memoria inmediata vive en `KnowledgeConversationMemory`. Por decisión de
producto, los turnos no se persisten actualmente en
`CONVERSACIONES_CONSULTOR_APPGT` ni `MENSAJES_CONSULTOR_APPGT`: permanecen en
la memoria de la pantalla y desaparecen al presionar **Limpiar**, cerrar sesión
o reiniciar la aplicación. Las tablas quedan reservadas para una futura función
de historial expresamente autorizada.

## Base inicial y revisión

La migración `202607310017_zumac_knowledge_engine.sql` analiza los nombres y la
jerarquía de secciones, módulos, formatos, tablas y campos. Para cada formato
genera:

- descripción general;
- objetivo y utilidad;
- usuarios, momento y frecuencia;
- ejemplo;
- conceptos relacionados;
- errores y buenas prácticas;
- indicadores y riesgos;
- preguntas frecuentes;
- campos identificados y contexto de módulo/sección.

El perfil técnico se adapta a familias de agroexportación como riego y
nutrición, fitosanidad, cosecha/calidad/trazabilidad, y personas/seguridad. El
contenido general que no encaja en una familia recibe un perfil de gestión
agroexportadora, nunca una respuesta manual asociada a una pregunta.

Toda generación usa `ON CONFLICT DO NOTHING`: no actualiza ni sobrescribe
documentos existentes. Los documentos y relaciones nacen en
`GENERADA_IA`. La pantalla **Revisar base de conocimiento IA** permite a un
administrador editar la estructura, aprobar, rechazar y cambiar la prioridad o
activación de una fuente.

## Grafo inicial

Las relaciones se almacenan en `RELACIONES_CONOCIMIENTO_APPGT`. Por ejemplo,
un formato identificado como drenaje queda conectado, según corresponda, con
Riego, Fertirriego, pH, CE, Lavado de sales, Calidad del agua, Variedades,
Sectores y Macetas.

El motor diferencia dos clases de conexión:

- si solo existe `concepto_destino`, el concepto amplía la búsqueda y las
  sugerencias;
- si existe `documento_destino_id`, el motor recupera y lee automáticamente el
  documento exacto de destino.

La expansión está limitada a dos niveles, evita ciclos, respeta estados de
revisión y admite como máximo seis documentos conectados. En una consulta
normal solo incorpora destinos que coinciden con la pregunta; en preguntas de
relaciones lee los destinos directos. De esta manera una conexión lejana no
contamina una respuesta y cada afirmación continúa respaldada por una cita.

## Conversación temporal

La pantalla presenta los turnos del usuario y del Consultor como una sola
sesión. El compositor permanece debajo de la última respuesta y el botón
**Limpiar**, representado por un borrador, elimina simultáneamente los mensajes,
el tema conceptual y la última consulta operativa. No se escribe ningún turno
en Supabase.

En consultas operativas ambiguas, la memoria también conserva la fuente y el
tema seleccionado. Por ejemplo, ante una pregunta sobre pH que coincide con
varios formatos, el Consultor pide primero el registro, luego una fecha o rango
y solo después ejecuta la consulta. La respuesta resume fechas y lotes y ofrece
**Ver registros**; no incrusta tablas extensas dentro de la conversación. Se
admiten días, meses, año actual y rangos como `01/07/2026 al 31/07/2026`.

## Pipeline documental futuro

`TRABAJOS_INDEXACION_CONOCIMIENTO_APPGT` define el contrato para archivos PDF,
Word, Excel y texto:

```text
archivo → extracción → normalización → segmentación → metadatos
        → embedding opcional → BASE_CONOCIMIENTO_APPGT → relaciones
```

Cada conector nuevo crea una fila en `FUENTES_CONOCIMIENTO_APPGT` y escribe
segmentos en `BASE_CONOCIMIENTO_APPGT`. No requiere modificar el algoritmo de
recuperación. Para habilitar búsqueda semántica se configura
`permite_semantica = true` y se inyecta un `KnowledgeSemanticSearch`; los demás
métodos siguen funcionando si el servicio de embeddings no está disponible.

## Aplicación

1. Aplicar las migraciones de Supabase en orden.
2. Entrar como administrador y abrir **Revisar base de conocimiento IA**.
3. Usar **Generar faltantes**, revisar sugerencias y aprobar las adecuadas.
4. Probar preguntas conceptuales y de seguimiento desde Consultor Zumac.

La generación es idempotente, por lo que el paso 3 puede repetirse después de
incorporar nuevos formatos sin alterar lo ya documentado.
