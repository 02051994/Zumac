# Informe de implementacion de la arquitectura ZUMAC

Fecha de validacion: 2026-07-15

Proyecto productivo Supabase: `dfyfdtlgmyjbxjpojhnc` (`DataFundoGT`)

Rama local: `architecture-master-implementation`

## Resultado

Las siete etapas de estabilizacion y fundacion arquitectonica acordadas fueron
implementadas mediante cambios pequenos, commits independientes y cuatro
migraciones versionadas. Las migraciones se probaron primero dentro de
transacciones con `ROLLBACK` y luego se aplicaron al proyecto productivo.

Esta entrega establece la base para la arquitectura maestra. No pretende
implementar todavia el constructor visual completo ni un servicio administrativo
capaz de generar DDL: esas capacidades corresponden a las fases posteriores del
documento rector y deben construirse sobre esta base.

## Etapas y commits

| Etapa | Resultado | Commit |
| --- | --- | --- |
| Linea base | Rama, respaldo local, inventario y pruebas iniciales | `7ca18b7`, `8f1dcf3` |
| Sincronizacion | Aplicacion atomica de snapshots/deltas y checkpoints separados | `e55074b` |
| Metadatos | Jerarquia seccion-modulo-formato normalizada sin borrar compatibilidad | `3b38f3a` |
| Multiempresa | Empresa, rubro, roles, membresias, RLS y bootstrap autenticado | `6e21b17` |
| Matrices declarativas | Dropdowns, validaciones, condiciones, formulas y navegacion tipada | `5f34cf2` |
| Offline y publicacion | Estados, conflictos, evidencias, ejecuciones de sync y versiones | `cb759d7` |
| Validacion final | Suite, analisis, build Windows y verificacion productiva | commit de documentacion final |

## Mapa de archivos principales

- `lib/core/services/local_db.dart`: esquema SQLite v29, aislamiento local,
  snapshots/deltas atomicos, checkpoints y cola versionada.
- `lib/core/services/sync_service.dart`: bootstrap v2 autenticado, descarga
  incremental, matrices declarativas, conflictos optimistas, evidencias y
  telemetria de sincronizacion.
- `lib/core/services/local_session.dart`: empresa activa y sesion local.
- `lib/core/services/dynamic_rules_repository.dart`: prioridad de reglas
  declarativas sobre metadatos heredados.
- `lib/core/services/offline_record_state.dart`: estados y transiciones offline.
- `test/core/services/local_db_sync_test.dart`: integridad de snapshots/deltas,
  aislamiento, version local, reintentos y conflictos.
- `test/core/services/dynamic_rules_repository_test.dart`: precedencia e
  inactivacion de reglas declarativas.
- `supabase/migrations/202607150001_metadata_cleanup.sql`: saneamiento de
  jerarquia y metadatos.
- `supabase/migrations/202607150002_tenant_security_and_bootstrap_v2.sql`:
  multiempresa, roles, membresias, RLS y bootstrap seguro.
- `supabase/migrations/202607150003_configuration_matrices_and_navigation.sql`:
  matrices declarativas y navegacion tipada.
- `supabase/migrations/202607150004_offline_conflicts_and_publication.sql`:
  versiones, publicaciones, sync, conflictos y manifiesto de evidencias.

## Dependencias y flujo resultante

```text
Supabase protegido por RLS
  -> appgt_bootstrap_offline_data_v2(authenticated)
  -> configuracion + permisos + matrices + version
  -> SyncService
  -> transaccion SQLite
  -> navegacion y formularios dinamicos
  -> cola local versionada
  -> deteccion optimista de conflictos
  -> upsert confirmado por servidor
  -> estado SINCRONIZADO + manifiesto de evidencia vinculado
```

El bootstrap publico heredado permanece disponible solo para compatibilidad
controlada donde ya existia. El bootstrap v2, que incluye datos por empresa y
matrices nuevas, no concede ejecucion a `anon`.

## Comprobaciones en Supabase productivo

- Rubros activos: 1 (`AGROEXPORTACION`).
- Reglas declarativas descargables: 161 dropdowns, 104 validaciones, 23
  condiciones y 30 formulas.
- Secciones con tipo configurado: 11.
- Tablas nuevas de la etapa offline: 5 de 5 con RLS habilitado.
- Version de configuracion publicada: `1.0.0`.
- Estados offline publicados: 8.
- Ejecucion de `appgt_bootstrap_offline_data_v2` para `anon`: denegada.
- Ejecucion autenticada de bootstrap: confirmada para la empresa ZUMAC.
- Escritura autenticada bajo RLS en sincronizaciones, conflictos y evidencias:
  confirmada dentro de una transaccion revertida; no dejo datos de prueba.

## Validaciones locales

- `flutter test --no-pub`: 9 de 9 pruebas aprobadas.
- Analisis focalizado de los archivos modificados: 0 errores.
- Analisis integral: 0 errores; conserva 156 advertencias/informaciones
  heredadas que no fueron ocultadas ni ampliadas como parte de esta entrega.
- `flutter build windows --no-pub`: aprobado; genero
  `build/windows/x64/runner/Release/appgt_offline_subtables.exe`.
- `flutter build apk --debug --no-pub`: no aprobado. Gradle/Kotlin quedo sin
  salida y sin APK en dos intentos controlados de 20 y 10 minutos. Los procesos
  huerfanos fueron identificados y cerrados. No se obtuvo un error de Dart o
  Java que atribuya el bloqueo al codigo modificado.

## Riesgos y limites pendientes

1. El constructor visual, los asistentes de seccion/modulo/formato/matriz y la
   vista previa siguen siendo una fase futura; no debe exponerse DDL desde Flutter.
2. La API administrativa para validar, generar, aplicar y revertir migraciones
   todavia debe implementarse fuera del cliente con credenciales seguras.
3. La resolucion manual de conflictos tiene persistencia y RPC, pero falta una
   interfaz administrativa dedicada para comparar y resolver campo por campo.
4. Las tablas operativas historicas no tienen todas un campo numerico `version`;
   por compatibilidad, el primer control optimista usa `updated_at`.
5. Las advertencias heredadas del analizador requieren una campana separada para
   evitar mezclar limpieza masiva con cambios funcionales.
6. El entorno Android local debe diagnosticarse antes de liberar un APK; revisar
   daemon Kotlin, memoria de Gradle, SDK y compatibilidad de plugins.
7. No existe remoto Git configurado en esta copia, por lo que los commits estan
   respaldados localmente pero no fueron publicados.

## Reversa y compatibilidad

Las cuatro migraciones son aditivas y transaccionales. No eliminan tablas
operativas ni datos existentes. Los RPC anteriores se conservan como nucleo o
respaldo cuando la compatibilidad lo exige. Antes de una reversa productiva se
deben retirar primero los consumidores Flutter y luego revocar funciones/politicas;
no se recomienda borrar las tablas nuevas si ya contienen auditoria, conflictos o
manifiestos de evidencias.

## Siguiente incremento recomendado

Resolver primero el pipeline Android. Despues, construir la API administrativa
y el constructor visual empezando por secciones y modulos en BORRADOR, con
validacion y vista previa, sin permitir que Flutter ejecute SQL administrativo.
