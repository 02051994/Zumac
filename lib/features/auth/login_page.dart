import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/local_db.dart';
import '../../core/services/local_session.dart';
import '../../core/services/sync_service.dart';
import '../../config/app_version.dart';
import '../../core/widgets/branded_loading.dart';
import '../modules/modules_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final userCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final session = LocalSession();
  bool loading = false;
  bool updatingUsers = false;
  bool updatedDataThisSession = false;
  String? updateMessage;
  bool passwordVisible = false;
  double loadingProgress = 0;
  String loadingMessage = 'Preparando...';

  @override
  void initState() {
    super.initState();
    _loadCachedEmail();
  }

  Future<void> _loadCachedEmail() async {
    final loginId = await session.cachedLoginIdentifier();
    if (!mounted || loginId == null) return;
    userCtrl.text = loginId;
  }

  String _friendlyError(Object error) {
    final raw = error.toString();
    final msg = raw.toLowerCase();
    if (msg.contains('invalid login') ||
        msg.contains('invalid credentials') ||
        msg.contains('password')) {
      return 'Usuario o contraseña incorrectos.';
    }
    if (msg.contains('over_email_send_rate_limit') ||
        msg.contains('email rate limit') ||
        msg.contains('429')) {
      return 'Supabase bloqueó temporalmente el envío de correos por muchos intentos. Espera unos minutos y vuelve a probar.';
    }
    if (msg.contains('network') ||
        msg.contains('socketexception') ||
        msg.contains('internet')) {
      return 'Se necesita conexión a internet para actualizar datos.';
    }
    if (msg.contains('no existe un usuario activo')) {
      return raw.replaceFirst('Exception: ', '');
    }
    if (msg.contains('not authorized') ||
        msg.contains('unauthorized') ||
        msg.contains('permission denied') ||
        msg.contains('jwt')) {
      return 'No autorizado. Revisa que el usuario esté activo y tenga permisos asignados.';
    }
    return raw.replaceFirst('Exception: ', '').trim().isEmpty
        ? 'No se pudo completar la operación.'
        : raw.replaceFirst('Exception: ', '').trim();
  }

  Future<void> updateUsersAndPermissions() async {
    setState(() {
      updatingUsers = true;
      updateMessage = 'Preparando actualización...';
      loadingProgress = 0.06;
      loadingMessage = 'Preparando actualización...';
    });
    await Future<void>.delayed(const Duration(milliseconds: 48));
    try {
      if (!await SyncService().hasInternet()) {
        throw Exception(
            'Se necesita conexión a internet para actualizar datos.');
      }

      // Este botón NO debe pedir usuario ni contraseña.
      // Descarga el paquete completo necesario para operar offline:
      // usuarios/perfiles, permisos, secciones, módulos, formatos, matrices y catálogos.
      final hasCache = await LocalDb.instance.hasOfflineBootstrapCache();
      await SyncService().downloadAllForOffline(
        allowFullFallback: !hasCache,
        onProgress: (message) {
          if (mounted) {
            setState(() {
              updateMessage = message;
              loadingMessage = message;
              loadingProgress =
                  (loadingProgress + 0.045).clamp(0.0, 0.94).toDouble();
            });
          }
        },
      );

      if (mounted) setState(() => loadingProgress = 1);
      updatedDataThisSession = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Datos actualizados: usuarios, permisos, formatos, matrices y catálogos.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    } finally {
      if (mounted) {
        setState(() {
          updatingUsers = false;
          updateMessage = null;
        });
      }
    }
  }

  Future<void> recoverPassword() async {
    if (loading || updatingUsers) return;
    try {
      if (!await SyncService().hasInternet()) {
        throw Exception('Conéctate a internet para recuperar contraseña.');
      }

      final loginIdentifier = userCtrl.text.trim();
      if (loginIdentifier.isEmpty) {
        throw Exception('Escribe tu DNI o correo para recuperar contraseña.');
      }

      final email = await _resolveAuthEmail(loginIdentifier);
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'appgt://reset-password',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Se envió el correo de recuperación a $email.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    }
  }

  Future<String> _resolveAuthEmail(String loginIdentifier) async {
    final value = loginIdentifier.trim();
    if (value.contains('@')) return value.toLowerCase();

    // Primero intenta resolver por la caché local descargada con "Actualizar datos".
    // Así el primer login por DNI no depende de que el operador escriba un correo.
    try {
      final profiles = await LocalDb.instance.getAll('local_profile');
      for (final profile in profiles) {
        final dni = (profile['dni'] ??
                profile['DNI'] ??
                profile['documento'] ??
                profile['DOCUMENTO'])
            ?.toString()
            .trim();
        final email =
            (profile['email'] ?? profile['correo'] ?? profile['CORREO'])
                ?.toString()
                .trim();
        final active = profile['activo'];
        final isActive = active == null ||
            active == 1 ||
            active == true ||
            active.toString().toLowerCase() == 'true';
        if (isActive && dni == value && email != null && email.isNotEmpty) {
          return email.toLowerCase();
        }
      }
    } catch (_) {}

    final result = await Supabase.instance.client.rpc(
      'appgt_auth_email_by_dni',
      params: {'p_dni': value},
    );

    final email = result?.toString().trim() ?? '';
    if (email.isEmpty) {
      throw Exception('No existe un usuario activo vinculado al DNI $value.');
    }
    return email.toLowerCase();
  }

  Future<List<String>> _offlineAliasesFromProfile({
    required String fallbackEmail,
    required String typedLogin,
    required String userId,
  }) async {
    // Seguridad: un usuario offline solo debe aceptar sus propios alias
    // (correo/DNI del perfil autenticado). Antes se agregaban alias de todos
    // los perfiles locales y eso permitía ingresar con DNI de otro usuario.
    final aliases = <String>{
      fallbackEmail.trim().toLowerCase(),
      typedLogin.trim().toLowerCase()
    };
    try {
      final profiles = await LocalDb.instance.getAll('local_profile');
      for (final profile in profiles) {
        final profileId = profile['id']?.toString().trim();
        final email =
            (profile['email'] ?? profile['correo'] ?? profile['CORREO'])
                ?.toString()
                .trim()
                .toLowerCase();
        final dni = (profile['dni'] ??
                profile['DNI'] ??
                profile['documento'] ??
                profile['DOCUMENTO'] ??
                profile['numero_documento'] ??
                profile['NUMERO_DOCUMENTO'])
            ?.toString()
            .trim()
            .toLowerCase();
        final belongsToUser =
            profileId == userId || email == fallbackEmail.trim().toLowerCase();
        if (!belongsToUser) continue;
        if (email != null && email.isNotEmpty && email != 'null')
          aliases.add(email);
        if (dni != null && dni.isNotEmpty && dni != 'null') aliases.add(dni);
      }
    } catch (_) {
      // Si el perfil local todavía no existe, el login offline seguirá funcionando
      // con el correo o identificador usado en el login online exitoso.
    }
    aliases.removeWhere(
        (e) => e.trim().isEmpty || e.trim().toLowerCase() == 'null');
    return aliases.toList();
  }

  bool _isCredentialError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('invalid login') ||
        msg.contains('invalid credentials') ||
        msg.contains('email not confirmed') ||
        msg.contains('password');
  }

  bool _isNetworkError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('timeout') ||
        msg.contains('internet');
  }

  Future<void> login() async {
    setState(() {
      loading = true;
      loadingProgress = 0.08;
      loadingMessage = 'Validando conexión y credenciales...';
    });
    await Future<void>.delayed(const Duration(milliseconds: 48));
    final loginIdentifier = userCtrl.text.trim();
    final password = passCtrl.text.trim();

    try {
      final online = await SyncService().hasInternet();
      if (mounted) setState(() => loadingProgress = 0.20);

      if (online) {
        try {
          final email = await _resolveAuthEmail(loginIdentifier);
          if (mounted)
            setState(() {
              loadingProgress = 0.34;
              loadingMessage = 'Iniciando sesión...';
            });
          await Supabase.instance.client.auth.signInWithPassword(
            email: email,
            password: password,
          );
          final user = Supabase.instance.client.auth.currentUser;
          if (user == null)
            throw Exception('No se pudo obtener usuario autenticado.');
          if (mounted)
            setState(() {
              loadingProgress = 0.56;
              loadingMessage = 'Verificando datos locales...';
            });
          final hasCache = await LocalDb.instance.hasOfflineBootstrapCache();
          if (hasCache) {
            // Si el usuario acaba de presionar Actualizar datos en esta misma pantalla,
            // no repetimos una segunda descarga al presionar Ingresar. Mantiene el login rápido.
            if (mounted)
              setState(() {
                loadingProgress = 0.70;
                loadingMessage = 'Actualizando permisos...';
              });
            await SyncService().refreshLoginPermissionsOnly();
          } else {
            if (mounted)
              setState(() {
                loadingProgress = 0.64;
                loadingMessage = 'Descargando datos para uso offline...';
              });
            await SyncService().downloadAllForOffline(onProgress: (message) {
              if (mounted)
                setState(() {
                  loadingMessage = message;
                  loadingProgress =
                      (loadingProgress + 0.04).clamp(0.0, 0.93).toDouble();
                });
            });
          }
          final aliases = await _offlineAliasesFromProfile(
            fallbackEmail: email,
            typedLogin: loginIdentifier,
            userId: user.id,
          );
          if (mounted)
            setState(() {
              loadingProgress = 0.90;
              loadingMessage = 'Preparando la aplicación...';
            });
          await session.saveSuccessfulLogin(
            email: email,
            password: password,
            userId: user.id,
            loginIdentifier: loginIdentifier,
            aliases: aliases,
          );
        } catch (e) {
          // Si hay internet y Supabase responde que la clave es incorrecta, NO
          // se permite caer a modo offline. Así se respeta el cambio de clave.
          if (_isCredentialError(e) || !_isNetworkError(e)) rethrow;
          final okOffline = await session.canLoginOffline(
            loginIdentifier: loginIdentifier,
            password: password,
          );
          if (!okOffline) rethrow;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Ingreso offline por falla de conexión. Se usarán los datos locales.')),
          );
        }
      } else {
        final okOffline = await session.canLoginOffline(
          loginIdentifier: loginIdentifier,
          password: password,
        );
        if (!okOffline)
          throw Exception(
              'Usuario o contraseña incorrectos para modo offline. Ingresa una vez con internet para actualizar credenciales locales.');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Ingreso offline. Se usarán los datos locales.')),
        );
      }

      if (!mounted) return;
      setState(() {
        loadingProgress = 1;
        loadingMessage = 'Listo';
      });
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ModulesPage()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFEAF4E5), Color(0xFFF8FAF4)],
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(54),
                            child: Image.asset(
                              'assets/images/logo_zumac.jpeg',
                              width: 108,
                              height: 108,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.eco, size: 64),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text('ZUMAC',
                              style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          const Text('Ingreso online/offline',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.black54)),
                          const SizedBox(height: 22),
                          TextField(
                            controller: userCtrl,
                            keyboardType: TextInputType.text,
                            style: const TextStyle(fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: 'DNI o correo',
                              prefixIcon: Icon(Icons.badge_outlined),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: passCtrl,
                            obscureText: !passwordVisible,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: passwordVisible
                                    ? 'Ocultar contraseña'
                                    : 'Mostrar contraseña',
                                onPressed: () => setState(
                                    () => passwordVisible = !passwordVisible),
                                icon: Icon(passwordVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
                              ),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: (loading || updatingUsers)
                                  ? null
                                  : recoverPassword,
                              child: const Text('Recuperar contraseña'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed:
                                  (loading || updatingUsers) ? null : login,
                              icon: const Icon(Icons.login),
                              label:
                                  Text(loading ? 'Ingresando...' : 'Ingresar'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: (loading || updatingUsers)
                                  ? null
                                  : updateUsersAndPermissions,
                              icon: const Icon(Icons.cloud_sync_outlined),
                              label: Text(updatingUsers
                                  ? 'Actualizando...'
                                  : 'Actualizar datos'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(appVersionLabel,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (loading || updatingUsers)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.white.withOpacity(0.94),
                child: Center(
                  child: BrandedLoading(
                    progress: loadingProgress,
                    message: updatingUsers
                        ? (updateMessage ?? loadingMessage)
                        : loadingMessage,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
