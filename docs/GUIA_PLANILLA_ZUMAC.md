# Guía operativa de Planilla Zumac

## Qué archivos intervienen

El cálculo implementado tiene tres fuentes y una salida:

1. **Trabajadores** (`GH-REGISTRO_PERSONAL_PLANILLA`)
   - Es el maestro de personal.
   - Debe contener DNI, estado activo, inicio y fin de contrato, régimen laboral,
     sueldo, asignación familiar, sistema pensionario y porcentaje de comisión AFP.
   - Los cambios de contrato o del trabajador disparan el recálculo automático.

2. **Tareo de Personal** (`GT-TAREO_PERSONAL`)
   - Distribuye las horas de cada DNI por fecha, labor, centro de costo y variedad.
   - Las primeras 8 horas del día son ordinarias; las 2 siguientes se calculan al
     25 % y el exceso al 35 %.
   - También alimenta horas nocturnas y el descanso semanal.
   - Insertar, editar o eliminar un tareo recalcula la fecha afectada.

3. **Matriz de Beneficios Sociales** (`MATRIZ_BENEFICIOS_SOCIALES`)
   - Está en **MATRICES > GESTIÓN HUMANA**.
   - Define por régimen la RMV y las tasas de asignación familiar, CTS,
     gratificación, bono extraordinario, bono beta, EsSalud, ONP y AFP.
   - Debe existir por lo menos una fila activa. Cuando el régimen no coincide de
     forma exacta se usa la primera fila activa como respaldo.

4. **Planilla de Trabajadores Zumac** (`PLANILLA_TRABAJADORES_ZUMAC`)
   - Es la salida diaria calculada, no un archivo que se tenga que volver a llenar.
   - Conserva una fila por DNI, fecha y distribución de tareo.
   - Permite completar ajustes que aún son manuales: descanso médico,
     teletrabajo, licencias, comisión y bonos de cargo, labor o movilidad.
   - Los costos, ingreso bruto, afecto/inafecto, aportes y total neto se recalculan
     al guardar esos ajustes.

## Flujo recomendado

1. Mantener actualizado **Trabajadores** y verificar que el estado sea `Activo`.
2. Revisar una sola vez las tasas de la **Matriz de Beneficios Sociales** y
   actualizarlas cuando cambie la normativa o la política de la empresa.
3. Registrar diariamente el **Tareo de Personal**.
4. Abrir **Planilla de Trabajadores Zumac** para revisar el resultado y completar
   únicamente los ajustes manuales del periodo.
5. Usar **Actualizar datos** para descargar configuración nueva y **Sincronizar**
   para enviar registros locales pendientes.

## Qué se retiró de la navegación

Los accesos históricos **Cabecera de Tareo Personal, Ausencias del Personal,
Horas Extras, Consolidado Diario, Planilla Cabecera, Planilla Detalle, Planilla
Conceptos y Boletas de Pago** no alimentan el motor actual y se ocultan para
evitar duplicidad. La migración usa borrado lógico: no elimina sus tablas ni sus
datos históricos.

**Asistencia de Personal** se conserva como proceso operativo, aunque actualmente
no modifica el cálculo monetario. **Tareo de Personal** sí modifica la planilla.
