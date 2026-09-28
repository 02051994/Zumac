# Flujo Git y despliegue de Zumac

## Responsabilidad de cada rama

- `main`: código fuente estable e integrado. Debe permitir reconstruir Zumac
  desde un clon limpio.
- `codex/*` y `feature/*`: trabajo en curso. Se validan y luego se integran
  en `main`.
- `gh-pages`: únicamente el artefacto generado por `flutter build web`.
  Nunca se usa como respaldo del código fuente ni se edita manualmente.

Las ramas locales `architecture-master-implementation` y
`feature/visual-builder` ya están contenidas en la historia fuente de
`main`. No deben eliminarse sin volver a comprobar que no tengan commits
exclusivos.

## Flujo obligatorio para cambios

1. Modificar el código fuente en una rama de trabajo.
2. Revisar `git diff` y `git status`.
3. Ejecutar `flutter analyze` y las pruebas pertinentes.
4. Confirmar que cachés, respaldos, resultados y secretos estén ignorados.
5. Agregar rutas concretas; no usar `git add .` sin revisar el estado.
6. Crear un commit descriptivo y publicarlo en su upstream.
7. Integrar el cambio verificado en `main` y publicar `main`.
8. Generar y publicar la web con `scripts/publish_web.ps1`.
9. Verificar que GitHub Pages esté construido desde `gh-pages:/`.

Ejemplo:

```powershell
git status --short
git diff --check
flutter analyze
flutter test
git add lib test supabase/migrations
git diff --cached --check
git commit -m "feat: describe el cambio"
git push
git switch main
git merge --ff-only nombre-de-la-rama
git push origin main
.\scripts\publish_web.ps1 -Message "deploy(web): describe la versión"
git status --short --branch
```

El publicador se detiene si encuentra cambios sin commit, si la rama actual no
tiene upstream o si `HEAD` todavía no coincide con el commit remoto. Después
compila con la ruta base `/Zumac/`, copia solo `build/web` a un clon
temporal de `gh-pages` y publica esa rama.

## Archivos que no pertenecen al repositorio

Las carpetas `.temp/`, `.video_runtime/`, `artifacts/`, `output/`,
`tmp/` y `build/` son cachés, material de trabajo o resultados generados.
El respaldo local `supabase/backup_supabase_proyecto_zumac/` contiene datos y
credenciales sensibles y jamás debe subirse a GitHub.

Los archivos `.env`, claves privadas, certificados y almacenes de claves
también están excluidos. Una plantilla versionable debe llamarse
`.env.example` o `.env.<entorno>.example` y no contener valores reales.
