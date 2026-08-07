# Zumac Metrics

## Propósito

Metrics es el espacio configurable de análisis visual de cada empresa. No es un
alias de la pantalla heredada **Reportes**: tiene modelo, permisos y experiencia
propios. Descubre tablas y campos desde las matrices de Zumac, por lo que una
nueva fuente autorizada aparece sin modificar el motor Flutter.

## Modelo

- `ZUMAC_METRICS_DASHBOARDS_APPGT`: una vista o pestaña, por ejemplo
  `Evaluaciones de riego`.
- `ZUMAC_METRICS_WIDGETS_APPGT`: KPI, barras, líneas, áreas, circular, tabla,
  dispersión u objetos de texto/figuras. Guarda fuente, dimensiones, valores,
  series, agregaciones, presentación y coordenadas del lienzo.
- `ZUMAC_METRICS_RELACIONES_APPGT`: igualdad entre las claves de dos tablas para
  propagar un filtro global.

Las tres tablas contienen `empresa_id`, RLS, borrado lógico y trazabilidad de
creación/actualización. ADMIN y GESTOR administran; los miembros autorizados de
la empresa pueden visualizar. Los RPC vuelven a comprobar la empresa y que la
tabla exista en `MATRIZ_FORMATO_TABLAS_APPGT`.

## Constructor de gráficos

Cada widget permite configurar:

- tabla, dimensión, valor y serie;
- cálculo `COUNT`, `SUM`, `AVG`, `MIN` o `MAX`;
- tipo de gráfico;
- título, descripción, tamaño del título, ejes, color y leyenda;
- subtítulo opcional, separador, títulos reales de ejes y estilos tipográficos;
- línea de tendencia;
- varias líneas de alerta independientes;
- regla visual por umbral y color condicional;
- filtro propio;
- ancho, alto y posición libre dentro del lienzo del dashboard;
- objetos de texto con círculos, triángulos y líneas configurables.

Cada gráfico abre un editor identificado por su propio `id`. Esto evita que un
objeto nuevo herede accidentalmente campos o estilos del objeto editado antes.
La posición (`pixel_x`, `pixel_y`) y el tamaño (`pixel_width`, `pixel_height`)
se guardan dentro de `configuracion`, sin intercambiar el orden de otros
gráficos. En móvil se conserva un flujo vertical adaptable.

Cuando el eje X contiene varias dimensiones, Metrics conserva su jerarquía.
Por ejemplo, `Año > Mes > Lote` dibuja el valor más detallado junto al gráfico
y agrupa debajo los niveles superiores. Si las categorías exceden el ancho,
aparece desplazamiento horizontal en el propio gráfico.

La lectura selecciona únicamente los campos requeridos y limita la vista a
5,000 filas para impedir una descarga accidentalmente ilimitada. La agregación
se realiza en el cliente en esta primera versión. Para volúmenes analíticos muy
grandes, el contrato `MetricDataset` permite cambiar la lectura por una función
SQL, vista materializada o almacén analítico sin rediseñar la interfaz.

## Relaciones y filtros compartidos

Una relación declara que dos campos representan la misma clave. Ejemplo:

```text
RIEGO.LOTE_ID ↔ LOTES.ID
```

Si el usuario filtra `LOTES.VARIEDAD = Arándano`, Metrics obtiene los
`LOTES.ID` correspondientes y aplica esos valores a `RIEGO.LOTE_ID`. Así el
mismo filtro afecta gráficos creados con ambas tablas. La relación no modifica
ni copia registros; describe cómo navegar entre ellos.

Los filtros se administran desde el panel lateral del dashboard. Cada filtro
es un acordeón con búsqueda, desplazamiento interno y selección múltiple. El
modo disponible depende del dato:

- fecha: lista, rango, después de y antes de;
- texto: lista, igual a, contiene, no es igual a y no contiene;
- número: lista, mayor que, menor que, entre y no es.

## Navegación desde Alerts

La bandeja de Alerts consulta qué tablas tienen widgets activos. Cuando existe
uno, muestra **Ver gráfico** y abre el dashboard que contiene esa fuente. Si no
existe, el botón no aparece.

## Archivos principales

- `lib/features/metrics/metrics_page.dart`: entorno, constructor, filtros,
  relaciones y renderizado con `CustomPainter`.
- `lib/features/metrics/metrics_repository.dart`: RPC, configuración y lectura
  limitada de datos.
- `supabase/migrations/202608030023_zumac_live_alerts_and_metrics.sql`: modelo,
  RLS y RPC.
- `supabase/migrations/202608040026_metrics_dashboard_experience.sql`:
  dashboards, permisos de visualización y editor ampliado.
- `supabase/migrations/202608060029_metrics_free_canvas_and_text.sql`: objetos
  de texto sin tabla de origen y soporte persistente del lienzo libre.
