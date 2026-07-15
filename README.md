# APPGT Offline First - Formatos con tablas internas

## Qué incluye
- Login con Supabase Auth.
- Descarga local de módulos, formatos, tablas internas de formato, permisos y perfil.
- Menú de módulos permitidos.
- Menú de formatos permitidos.
- Si el formato tiene varias tablas internas, muestra lista desplegable.
- Guardado local en SQLite como pendiente.
- Sincronización de pendientes contra la tabla_destino de Supabase.

## Configurar Supabase
Editar:

lib/config/supabase_config.dart

Colocar:
- supabaseUrl: URL base del proyecto, sin /rest/v1
- supabaseAnonKey: Publishable key, nunca Secret key

## Tablas esperadas en Supabase
- MATRIZ_MODULOS_APPGT
- MATRIZ_FORMATOS_APPGT
- MATRIZ_FORMATO_TABLAS_APPGT
- PERMISOS_DE_USUARIOS_APPGT
- PERFILES_DE_USUARIOS_APPGT

## Importante
Este zip trae lib/ y pubspec.yaml. Si falta android/, ejecutar:

flutter create .
flutter pub get
flutter run

## Flujo
Login online -> descarga matrices -> trabaja offline -> guarda local -> sincroniza con internet.
