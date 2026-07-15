# Implementacion de la arquitectura maestra de ZUMAC

## Linea base

- Proyecto Supabase: `dfyfdtlgmyjbxjpojhnc` (`DataFundoGT`).
- Rama local: `architecture-master-implementation`.
- La aplicacion existente es offline-first, pero aun mezcla snapshots completos, deltas incrementales y consultas directas.
- La implementacion se realizara por migraciones versionadas y cambios Flutter pequenos y verificables.

## Etapas

1. [Completada] Proteccion, Git, linea base y pruebas.
2. [Completada] Sincronizacion atomica, distincion snapshot/delta y checkpoints.
3. [Completada] Limpieza de metadatos y relaciones.
4. [Completada] Seguridad, usuarios y aislamiento por empresa.
5. [Completada] Matrices faltantes y reduccion de logica fija.
6. [Completada] Conflictos, estados offline, archivos, publicacion y versiones.
7. [Completada con limitacion Android] Validacion integral y despliegue controlado.

El detalle de cambios, comprobaciones y limitaciones se encuentra en
`docs/ARCHITECTURE_IMPLEMENTATION_REPORT.md`.

## Condiciones de avance

- No se avanza un checkpoint si alguna entidad requerida no pudo guardarse.
- Un delta nunca reemplaza una fotografia completa.
- La ultima configuracion valida permanece disponible ante un corte de red.
- Los permisos y datos locales se aislan por usuario y empresa.
- Cada cambio de Supabase nace en `supabase/migrations/` y se valida antes de produccion.
