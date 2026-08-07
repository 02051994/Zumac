# Zumac AI Engine

Motor documental propio y sin costo por consulta. Usa OCR local para leer
fotografías y PDF, verifica nitidez, propone la fila de encabezados, infiere
campos y devuelve el mismo contrato JSON que consume Zumac Creator.

No sustituye una revisión humana: todo resultado se guarda como `GENERADA_IA`.

## Ejecución

```powershell
cd C:\app_zumac_14_07_12y10\services\zumac_ai_engine
$env:ZUMAC_AI_ENGINE_SHARED_SECRET = "GENERA_UN_SECRETO_LARGO"
docker compose up -d --build
```

La función de Supabase necesita una URL HTTPS accesible hacia este servicio y
el mismo secreto en `ZUMAC_AI_ENGINE_SHARED_SECRET`. En una instalación privada
puede alojarse dentro de la infraestructura de la empresa.

Variables requeridas en Supabase:

- `ZUMAC_AI_ENGINE_URL`: por ejemplo `https://ai.empresa.com`.
- `ZUMAC_AI_ENGINE_SHARED_SECRET`: secreto compartido con este contenedor.

`GET /health` permite comprobar el estado sin procesar archivos.
