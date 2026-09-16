# Guía operativa de Planilla Zumac

## Fuente única y resultado de cada etapa

El flujo vigente es lineal. No se debe llenar una segunda planilla ni editar los
importes calculados.

1. `GH-REGISTRO_PERSONAL_PLANILLA` es el maestro laboral. Define contrato,
   sueldo, régimen (`AGRARIO_31110` o `GENERAL_728`), jornada, tipo de
   remuneración, frecuencia de pago, pensión y elecciones de beneficios.
2. `GT-ASISTENCIA_PERSONAL` acredita la presencia diaria.
3. `GT-TAREO_PERSONAL` distribuye las horas presentes por labor y centro de
   costo. Solo el tareo `APROBADO` llega a planilla.
4. `GH_PERMISOS_LICENCIAS_APPGT` justifica y clasifica días u horas no
   trabajados. Solo se consideran documentos aprobados.
5. `PLANILLA_TRABAJADORES_ZUMAC` es únicamente el costeo diario distribuido.
   No es una boleta ni el monto final a pagar.
6. `PLANILLA_LIQUIDACION_TRABAJADOR_APPGT` es la liquidación monetaria
   autoritativa por período y trabajador.
7. `PLANILLA_PERIODOS_APPGT` controla el ciclo `BORRADOR → CALCULADA →
   REVISADA → APROBADA → CERRADA`.

## Configuración obligatoria antes del primer cálculo

En **Configuración legal de planilla** se debe confirmar y sustentar que la
actividad de la empresa está comprendida en la Ley 31110 antes de usar el régimen
agrario. La clasificación histórica EsSalud puede conservarse como dato de la
empresa, pero no cambia la tasa durante 2026: la Ley 31969 fijó 6 % para los
trabajadores comprendidos desde enero de 2024 hasta diciembre de 2028. Allí
también se registra EPS y las tasas contratadas de SCTR, si corresponde. Las
tasas SCTR se ingresan en decimal (por ejemplo, `0.0125` para 1.25 %); la tasa
legal de bonificación con EPS queda fija en 6.75 % y no es editable.

En cada trabajador deben estar completos:

- régimen laboral;
- remuneración mensual equivalente y horas diarias promedio;
- tipo de remuneración (`MENSUAL` o `JORNAL`);
- frecuencia (`QUINCENAL` o `MENSUAL`);
- ONP o AFP; para AFP, administradora y tipo de comisión;
- asignación familiar y necesidad de SCTR;
- modalidad de CTS/gratificación y modalidad BETA.

El personal de áreas administrativas o de soporte técnico no puede asignarse al
régimen agrario; la Ley 31110 lo excluye expresamente. Esos trabajadores deben
configurarse, por ejemplo, bajo `GENERAL_728` cuando corresponda.

En el régimen agrario, la ausencia de una elección escrita mantiene CTS y
gratificación prorrateadas. Un cambio posterior exige fecha y documento. El
BETA se paga mensualmente por defecto; prorratearlo exige acuerdo escrito. En
el régimen general CTS y gratificación siempre siguen la oportunidad legal.
Al cambiar de régimen no se arrastran elecciones incompatibles: al ingresar al
régimen agrario, sin elección escrita, se aplica el prorrateo legal.

## Qué valida el botón Calcular

El cálculo se bloquea si existe cualquiera de estas condiciones:

- dato laboral obligatorio incompleto o remuneración inferior a la RMV
  aplicable a la jornada;
- empresa que usa el régimen agrario sin sustento de aplicación de la Ley 31110;
- AFP o SCTR sin tasa vigente/configurada;
- parámetro legal sin vigencia para las fechas del período;
- período superpuesto o con fechas distintas de una quincena/mes;
- tareo pendiente de aprobación;
- asistencia sin tareo aprobado o tareo aprobado sin asistencia;
- permisos aprobados superpuestos;
- elección semestral agraria o prorrateo de BETA sin documento escrito;
- trabajador activo sin asistencia, tareo ni permiso en todo el período.

La ventana de validaciones muestra código, DNI y corrección pendiente. No se
puede revisar, aprobar ni cerrar mientras reaparezca un error.

## Reglas monetarias principales

- Jornada ordinaria máxima: 8 horas diarias; las dos primeras horas extra se
  pagan con 25 % y las siguientes con 35 %.
- Asignación familiar: 10 % de la RMV cuando corresponde; en el régimen agrario
  se proporcionaliza según los días computables.
- Régimen agrario: CTS 9.72 % y gratificación 16.66 % de la remuneración básica
  cuando se eligió prorrateo. BETA: 30 % de la RMV, mensual por defecto.
- BETA no integra pensiones, EsSalud ni otros beneficios, pero sí se considera
  renta de quinta categoría según la tabla PLAME de SUNAT.
- Nocturnidad agraria: 35 % de la RMV proporcional a las horas entre 22:00 y
  06:00. En el régimen general se aplica como piso remunerativo nocturno.
- ONP y AFP son excluyentes. Comisión sobre saldo no se descuenta de la
  remuneración; comisión sobre flujo sí usa la tasa SBS vigente.
- Gratificación no integra la base pensionaria/EsSalud. Su bonificación
  extraordinaria es 9 % para EsSalud o 6.75 % con EPS. No se confunde con el
  aporte patronal agrario temporal de 6 %.
- Quinta categoría usa proyección anual, deducción de 7 UIT, tramos 8 %, 14 %,
  17 %, 20 % y 30 %, y el divisor mensual publicado por SUNAT.

## Cómo leer los totales

- **Remuneración bruta**: ingresos pagados en ese período; no incluye un
  depósito semestral de CTS.
- **Neto de remuneración**: bruto menos ONP/AFP, quinta categoría y otros
  descuentos.
- **Depósito CTS**: desembolso separado a la cuenta CTS.
- **Desembolso total al trabajador**: neto de remuneración más depósito CTS.
- **Provisiones**: CTS, gratificación/bonificación y vacaciones todavía no
  pagadas. No se vuelven a sumar como pago.
- **Costo empresa**: remuneración devengada, aportes del empleador y provisiones,
  sin duplicar beneficios ya provisionados.

## Cierre y cambios posteriores

Al cerrar un período se bloquean las fuentes que lo alimentan. Una corrección
requiere reabrir con motivo, recalcular, revisar y aprobar otra vez. Cada cambio
queda en auditoría. Si asistencia, tareo, permisos, datos laborales o el costeo
diario cambian después del cálculo, Revisar/Aprobar/Cerrar se bloquean hasta
recalcular. La reconstrucción de permisos conserva las horas reales y reclasifica
las horas ordinarias/extra usando la jornada declarada; no resta nuevamente el
tareo en cada recálculo.

Los parámetros 2026 terminan el 31/12/2026 a propósito: la
planilla 2027 quedará bloqueada hasta incorporar mediante una migración
verificada la RMV, UIT y tasas oficialmente publicadas para esa vigencia. Las
matrices nacionales de parámetros y AFP son de solo lectura para los usuarios;
una empresa no puede cambiar valores legales que afectarían a las demás.

## Alcance exacto del motor

Este motor genera la **planilla periódica de remuneraciones** y sus provisiones.
No debe confundirse con procesos que tienen un hecho generador, período o
declaración propios. Continúan como procesos separados:

- liquidación de beneficios sociales por cese e indemnizaciones;
- participación anual en utilidades y su distribución entre trabajadores;
- declaración oficial en T-Registro/PLAME, AFPnet, emisión de boletas, asiento
  contable y archivo bancario;
- retenciones judiciales, préstamos y conceptos nacidos de convenios colectivos
  o condiciones particulares que no estén configurados expresamente.

Si un trabajador cesa dentro del período, la planilla periódica paga solo los
conceptos del período. La liquidación de cese debe calcularse y revisarse por
separado; nunca se debe asumir que el campo **Depósito CTS** reemplaza esa
liquidación. Las utilidades tampoco son una provisión mensual fija: requieren el
resultado anual y la población legalmente computable.

## Puerta obligatoria antes de pagar una planilla real

La aprobación técnica exige aplicar la migración completa en Supabase, obtener
cero validaciones bloqueantes y comparar una muestra representativa contra un
cálculo laboral independiente. La muestra debe incluir, como mínimo: régimen
agrario y general, pago mensual y quincenal, ONP, cada AFP/comisión utilizada,
CTS/gratificación prorrateada y semestral, BETA mensual y prorrateado, jornada
menor de cuatro horas, horas extra, nocturnidad, permisos con y sin goce, EPS y
SCTR cuando correspondan. Recién después se puede aprobar el período.

Las pruebas automáticas verifican la estructura y las reglas codificadas; no
sustituyen la revisión de contratos, convenios, documentos de elección ni la
responsabilidad del empleador sobre la información registrada.
