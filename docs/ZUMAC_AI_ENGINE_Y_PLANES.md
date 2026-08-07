# Zumac AI Engine, multiempresa y planes avanzados

## Decisión de arquitectura

Zumac utiliza una sola base Supabase multiempresa. No se crea otra base para
cada cliente. `EMPRESAS_APPGT` identifica la empresa y
`USUARIOS_EMPRESAS_APPGT` vincula cada usuario con una o varias empresas. La
función `appgt_empresa_actual_id()` selecciona su empresa activa, priorizando la
marcada como predeterminada, y todas las tablas funcionales conservan
`empresa_id` y RLS.

Las columnas siguientes controlan la oferta por empresa:

- `habilitar_zumac_consultor`;
- `habilitar_zumac_creator`;
- `habilitar_ia_avanzada`.

Si una función no está autorizada, no aparece en Inicio. El conocimiento también
queda protegido con una política restrictiva, de modo que ocultar el botón no es
la única barrera.

## Motores

`ZUMAC` aparece como **Básico** y es el motor predeterminado de Creator. Analiza nitidez, OCR, filas,
encabezados, tipos de campo y relaciones dentro de infraestructura controlada
por Zumac. No consume créditos de OpenAI.

`OPENAI` aparece como **Avanzado** y es opcional. Antes de cada llamada la Edge Function valida:

1. JWT y usuario;
2. empresa activa;
3. autorización de Creator e IA avanzada;
4. propiedad de la importación;
5. suscripción individual vigente;
6. créditos disponibles.

La clave de OpenAI nunca se entrega al cliente Flutter.

Zumac Consultor continúa usando su motor propio de recuperación exacta, difusa
y semántica opcional. No necesita OpenAI para responder con el conocimiento y
los registros recuperados.

## Precio, créditos y consumo

OpenAI no entrega una cantidad fija de tokens mensuales: entrada, entrada en
caché y salida tienen precios distintos. Por ello Zumac registra los tokens
reales devueltos por la API y los convierte a costo mediante
`TARIFAS_MODELOS_IA_APPGT`.

Los planes iniciales son configurables:

- mensual: USD 30, con USD 10 de presupuesto real del proveedor;
- anual: USD 360, con USD 120 de presupuesto real del proveedor.

El multiplicador es exactamente 3. Un crédito comercial equivale a USD 0.001
de costo del proveedor. La interfaz muestra saldo y tokens utilizados, mientras
que Supabase conserva el libro de consumo completo por `empresa_id` y `user_id`.

Al agotarse el saldo se bloquea OpenAI y se muestra: “¿Ya consumiste todos los
tokens, deseas más?”. Zumac AI Engine permanece disponible gratuitamente.

## Pago

`appgt_solicitar_plan_ia_v1` crea una orden `PENDIENTE_PAGO` en USD. El acceso
no se concede al crear la solicitud. Un webhook o proceso de administración con
`service_role` debe verificar el pago y ejecutar
`appgt_confirmar_pago_plan_ia_v1`. Esto impide que un usuario o administrador de
empresa se otorgue créditos sin un pago confirmado.

El proveedor de cobro se mantiene desacoplado. La tabla admite proveedor,
referencia y URL de pago para integrar Stripe, Mercado Pago u otro checkout sin
modificar el control de consumo.
