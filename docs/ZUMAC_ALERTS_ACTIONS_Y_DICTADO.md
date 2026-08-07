# Zumac Alerts, Actions y dictado del Consultor

## Resultado funcional

Alerts vigila los datos de la empresa mediante reglas configurables. Actions
convierte un hallazgo o una solicitud manual en trabajo trazable. Ninguno de los
dos motores contiene nombres de cultivos, formatos, tablas o campos codificados:
las fuentes se descubren desde `MATRIZ_FORMATO_TABLAS_APPGT` y
`MATRIZ_CAMPOS_FORMATO_APPGT` para la empresa activa.

El Consultor incorpora dictado de preguntas cortas. La voz se transforma en
texto en el dispositivo o mediante el servicio de reconocimiento disponible en
su sistema operativo; Zumac envía al Consultor únicamente el texto resultante.

## Flujo de Alerts

1. Un ADMIN o GESTOR crea una regla y selecciona una fuente configurada.
2. Añade una o varias condiciones con lógica **todas (Y)** o **cualquiera (O)**.
3. Prueba la regla contra un máximo de 500 registros antes de activarla.
4. Supabase Cron ejecuta `appgt_evaluar_alertas_v1()` cada minuto.
5. Cada regla respeta su frecuencia y su vigencia: siempre, hoy, esta semana,
   este año o un rango de fechas.
6. Cada regla mantiene **una sola alerta viva**. La evaluación más reciente
   reemplaza sus filas y su mensaje; si la condición deja de cumplirse, la
   tarjeta desaparece.
7. `detectada_at` conserva desde cuándo existe la condición y
   `ultima_ocurrencia_at` registra la evaluación más reciente que la confirmó.
8. La regla puede mantener una única tarea automática pendiente. Su contenido
   también se actualiza con el último hallazgo.
9. Un administrador puede pausar, reactivar o eliminar una regla. La eliminación
   es lógica y no borra ningún registro de los formatos de negocio.

Las reglas de tipo `AUSENCIA` se activan cuando ninguna fila cumple las
condiciones. Son útiles para controles como "no se registró el pH de hoy". Las
reglas `PROGRAMADA` y `EVENTO` detectan filas que sí cumplen las condiciones.

## Flujo de Actions

Una acción puede ser una tarea, solicitud de aprobación, notificación o cambio
de estado. Conserva prioridad, responsable, aprobador, fecha límite, resultado,
comentarios y evidencia estructurada. Los cambios de estado se realizan por RPC;
Supabase vuelve a validar empresa y autorización aunque el cliente sea alterado.

Una acción automática vinculada con una alerta se actualiza mientras la
condición continúe y se cancela cuando la condición desaparece. Las acciones
manuales mantienen comentarios y evidencia. Eliminar una acción la archiva como
cancelada; no borra datos de negocio ni comentarios mediante SQL del cliente.

## Tablas

- `ZUMAC_ALERTAS_APPGT`: definición y planificación de reglas.
- `ZUMAC_ALERTA_DESTINATARIOS_APPGT`: usuarios, roles y canales destinatarios.
- `ZUMAC_ALERTA_EVENTOS_APPGT`: estado vivo, con máximo una fila por regla.
- `ZUMAC_ACCIONES_APPGT`: tareas, aprobaciones y resultados.
- `ZUMAC_ACCION_COMENTARIOS_APPGT`: bitácora y evidencia.
- `ZUMAC_ALERTA_EJECUCIONES_APPGT`: auditoría técnica de cada evaluación.
- `ZUMAC_DISPOSITIVOS_APPGT`: tokens de dispositivos para la futura conexión FCM.

Todas incluyen `empresa_id` y políticas RLS. Las tablas operativas sin
`empresa_id` solo pueden usarse cuando su matriz pertenece a una única empresa;
si una misma tabla se comparte entre varias empresas, Alerts la rechaza para
evitar filtraciones. La solución correcta en ese caso es incorporar
`empresa_id` a la tabla operativa.

## Expresión de una regla

El editor produce JSON como este:

```json
{
  "logic": "AND",
  "conditions": [
    {
      "field": "PH",
      "operator": "gt",
      "value": "6",
      "value_type": "number"
    },
    {
      "field": "SECTOR",
      "operator": "eq",
      "value": "Sector 4",
      "value_type": "text"
    }
  ]
}
```

Operadores: igualdad, diferencia, mayor/menor, rangos, contiene, no contiene,
vacío y no vacío. Las plantillas admiten `[CAMPO]` y `{{CAMPO}}`. Si varias
filas cumplen, el motor reúne valores distintos con comas y una `y` final. Por
ejemplo `pH alto en [LOTE]` puede producir `pH alto en 3, 4 y 5`.

La bandeja muestra el formato, el mensaje, las coincidencias, desde cuándo está
activa y la última evaluación. `Ver registros` abre el formato relacionado y
`Ver gráfico` aparece cuando Metrics ya tiene un widget para esa tabla.

## Programación automática

La migración `202608030022_zumac_alerts_actions.sql` habilita `pg_cron` y crea el
trabajo `zumac-alerts-every-minute`. El trabajo despierta cada minuto, pero una
regla configurada cada 30 minutos solo se evalúa cuando llega su
`proxima_ejecucion`.

La migración `202608030023_zumac_live_alerts_and_metrics.sql` agrega vigencia,
pausa/eliminación segura, interpolación agregada y el índice único por regla.

Consultas útiles en Supabase SQL Editor:

```sql
select jobid, jobname, schedule, active
from cron.job
where jobname = 'zumac-alerts-every-minute';

select *
from public."ZUMAC_ALERTA_EJECUCIONES_APPGT"
order by iniciada_at desc
limit 50;
```

## Notificaciones

La bandeja dentro de Zumac funciona con Supabase y refresco de respaldo cada 25
segundos. Las tablas de eventos y acciones también se agregan a la publicación
Realtime.

Para notificar con la app cerrada falta la identidad externa de Firebase Cloud
Messaging. No se debe inventar ni guardar en Git. Se necesitan:

- proyecto Firebase;
- `google-services.json` para Android;
- `GoogleService-Info.plist` para iOS;
- configuración web y clave VAPID para navegador;
- cuenta de servicio Firebase como secreto del servidor.

La tabla de dispositivos y los destinatarios ya dejan preparado el contrato de
datos. Hasta incorporar esas credenciales, los canales `PUSH` y `EMAIL` no se
seleccionan en el editor y el canal operativo es `APP`.

## Dictado

El botón de micrófono aparece junto al botón Enviar. Al tocarlo:

- solicita permiso una sola vez según la plataforma;
- prefiere español de Perú y usa otro español si no está disponible;
- muestra resultados parciales en el campo de texto;
- se detiene tras una pausa, al tocar Detener o al enviar;
- conserva el texto que el usuario ya había escrito antes de dictar.

Android declara `RECORD_AUDIO` y el servicio de reconocimiento. iOS declara los
mensajes de uso del micrófono y reconocimiento. En Web la disponibilidad depende
del navegador y de que GitHub Pages se sirva mediante HTTPS.

## Despliegue

Desde PowerShell, en la raíz del proyecto:

```powershell
npx.cmd supabase@latest db push

C:\flutter\bin\flutter.bat build web --release --base-href /Zumac/

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\scripts\publish_web.ps1" `
  -SkipBuild `
  -Message "Publica Zumac Alerts, Actions y dictado"
```

El primer comando es imprescindible: sin la migración, Inicio mantiene Alerts y
Actions deshabilitados para no abrir una pantalla cuyo backend aún no existe.
