import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/tenant_config.dart';
import 'local_db.dart';

class LocalSession {
  static const _emailKey = 'offline_email';
  static const _loginKey = 'offline_login_identifier';
  static const _userIdKey = 'offline_user_id';
  static const _passwordHashKey = 'offline_password_hash';
  static const _aliasesKey = 'offline_login_aliases';
  static const _passwordPlainKey = 'offline_password_local_reauth';
  static const _offlineUsersKey = 'offline_users_v2';
  static const _securePasswordKey = 'appgt_secure_reauth_password';
  static const _empresaIdKey = 'offline_empresa_id';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();


  static String _hashPassword(String email, String password) {
    final normalizedEmail = email.trim().toLowerCase();
    final raw = utf8.encode('$normalizedEmail::$password::APPGT_LOCAL_AUTH');
    return sha256.convert(raw).toString();
  }

  Future<List<Map<String, dynamic>>> _offlineUsers(SharedPreferences prefs) async {
    final raw = prefs.getString(_offlineUsersKey);
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  Future<void> _saveOfflineUsers(
    SharedPreferences prefs,
    List<Map<String, dynamic>> users,
  ) async {
    await prefs.setString(_offlineUsersKey, jsonEncode(users));
  }

  Future<List<String>> _trustedAliasesForStoredUser({
    required String userId,
    required String email,
    required String loginIdentifier,
    required List<String> storedAliases,
  }) async {
    final output = <String>{
      email.trim().toLowerCase(),
      loginIdentifier.trim().toLowerCase(),
    };

    try {
      final profiles = await LocalDb.instance.getAll('local_profile');
      for (final profile in profiles) {
        final profileId = profile['id']?.toString().trim();
        final profileEmail = (profile['email'] ?? profile['correo'] ?? profile['CORREO'])?.toString().trim().toLowerCase();
        if (profileId != userId && profileEmail != email.trim().toLowerCase()) continue;

        for (final key in ['dni', 'DNI', 'documento', 'DOCUMENTO', 'numero_documento', 'NUMERO_DOCUMENTO', 'email', 'correo', 'CORREO']) {
          final value = profile[key]?.toString().trim().toLowerCase();
          if (value != null && value.isNotEmpty && value != 'null') output.add(value);
        }
      }
    } catch (_) {
      // Sin perfil local, se usan solo correo/login guardados. No se confía
      // en alias heredados porque versiones anteriores podían contener DNIs
      // de otros usuarios.
    }

    // Compatibilidad controlada: solo conserva alias heredados que sean el correo
    // o login principal. Los demás se descartan para cerrar el hueco de cruce.
    for (final alias in storedAliases) {
      final value = alias.trim().toLowerCase();
      if (value == email.trim().toLowerCase() || value == loginIdentifier.trim().toLowerCase()) {
        output.add(value);
      }
    }

    output.removeWhere((e) => e.isEmpty || e == 'null');
    return output.toList();
  }

  Future<void> _setActiveSession({
    required SharedPreferences prefs,
    required String email,
    required String password,
    required String userId,
    required String loginIdentifier,
    required List<String> aliases,
  }) async {
    await prefs.setString(_emailKey, email.trim().toLowerCase());
    await prefs.setString(_loginKey, loginIdentifier.trim().toLowerCase());
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_passwordHashKey, _hashPassword(email, password));
    // La clave real ya no se guarda en SharedPreferences. Se conserva solo en
    // almacenamiento seguro para reautenticar antes de sincronizar después de trabajar offline.
    await _secureStorage.write(key: _securePasswordKey, value: password);
    await prefs.remove(_passwordPlainKey);
    await prefs.setStringList(_aliasesKey, aliases);
  }

  Future<void> saveSuccessfulLogin({
    required String email,
    required String password,
    required String userId,
    String? loginIdentifier,
    List<String> aliases = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedLogin = (loginIdentifier ?? email).trim().toLowerCase();
    final normalizedAliases = <String>{
      normalizedEmail,
      normalizedLogin,
      ...aliases.map((e) => e.trim().toLowerCase()),
    }..removeWhere((e) => e.isEmpty || e == 'null');

    final users = await _offlineUsers(prefs);
    users.removeWhere((u) => u['userId']?.toString() == userId || u['email']?.toString().toLowerCase() == normalizedEmail);
    users.add({
      'email': normalizedEmail,
      'loginIdentifier': normalizedLogin,
      'userId': userId,
      'passwordHash': _hashPassword(normalizedEmail, password),
      'aliases': normalizedAliases.toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await _saveOfflineUsers(prefs, users);

    await _setActiveSession(
      prefs: prefs,
      email: normalizedEmail,
      password: password,
      userId: userId,
      loginIdentifier: normalizedLogin,
      aliases: normalizedAliases.toList(),
    );
  }

  Future<bool> canLoginOffline({
    required String loginIdentifier,
    String? email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final typed = loginIdentifier.trim().toLowerCase();

    final users = await _offlineUsers(prefs);
    for (final user in users) {
      final storedEmail = user['email']?.toString().trim().toLowerCase() ?? '';
      final storedLogin = user['loginIdentifier']?.toString().trim().toLowerCase() ?? '';
      final storedHash = user['passwordHash']?.toString() ?? '';
      final storedUserId = user['userId']?.toString() ?? '';
      final storedAliases = (user['aliases'] is List)
          ? List<String>.from((user['aliases'] as List).map((e) => e.toString().trim().toLowerCase()))
          : <String>[];
      if (storedEmail.isEmpty || storedHash.isEmpty || storedUserId.isEmpty) continue;

      final aliases = await _trustedAliasesForStoredUser(
        userId: storedUserId,
        email: storedEmail,
        loginIdentifier: storedLogin,
        storedAliases: storedAliases,
      );
      final matchesIdentifier = typed == storedEmail || typed == storedLogin || aliases.contains(typed);
      if (!matchesIdentifier) continue;

      final authEmail = storedEmail;
      final ok = storedHash == _hashPassword(authEmail, password);
      if (!ok) continue;

      await _setActiveSession(
        prefs: prefs,
        email: storedEmail,
        password: password,
        userId: storedUserId,
        loginIdentifier: storedLogin.isEmpty ? storedEmail : storedLogin,
        aliases: aliases.isEmpty ? <String>[storedEmail, storedLogin] : aliases,
      );
      return true;
    }

    // Compatibilidad con instalaciones anteriores que solo guardaban un usuario.
    final storedEmail = prefs.getString(_emailKey);
    final storedLogin = prefs.getString(_loginKey);
    final storedHash = prefs.getString(_passwordHashKey);
    if (storedEmail == null || storedHash == null) return false;

    final storedAliases = prefs.getStringList(_aliasesKey) ?? const <String>[];
    final aliases = await _trustedAliasesForStoredUser(
      userId: prefs.getString(_userIdKey) ?? '',
      email: storedEmail,
      loginIdentifier: storedLogin ?? storedEmail,
      storedAliases: storedAliases,
    );
    final matchesIdentifier = typed == storedEmail || typed == storedLogin || aliases.contains(typed);
    final ok = matchesIdentifier && storedHash == _hashPassword(storedEmail, password);
    if (ok) {
      await _setActiveSession(
        prefs: prefs,
        email: storedEmail,
        password: password,
        userId: prefs.getString(_userIdKey) ?? '',
        loginIdentifier: storedLogin ?? storedEmail,
        aliases: aliases,
      );
    }
    return ok;
  }

  Future<String?> cachedUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  Future<String> cachedEmpresaId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_empresaIdKey) ?? TenantConfig.defaultEmpresaId;
  }

  Future<void> saveActiveEmpresaId(String empresaId) async {
    final clean = empresaId.trim();
    if (clean.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_empresaIdKey, clean);
  }

  Future<void> clearActiveSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_loginKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_passwordHashKey);
    await prefs.remove(_aliasesKey);
    await prefs.remove(_empresaIdKey);
    await prefs.remove(_passwordPlainKey);
    await _secureStorage.delete(key: _securePasswordKey);
  }

  Future<String?> cachedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  Future<String?> cachedLoginIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_loginKey) ?? prefs.getString(_emailKey);
  }

  Future<List<String>> cachedLoginAliases() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_aliasesKey) ?? const <String>[];
  }

  Future<String?> cachedPasswordForReauth() async {
    final securePassword = await _secureStorage.read(key: _securePasswordKey);
    if (securePassword != null && securePassword.isNotEmpty) return securePassword;

    // Migración segura desde versiones antiguas que guardaban la contraseña en texto plano.
    final prefs = await SharedPreferences.getInstance();
    final legacyPassword = prefs.getString(_passwordPlainKey);
    if (legacyPassword != null && legacyPassword.isNotEmpty) {
      await _secureStorage.write(key: _securePasswordKey, value: legacyPassword);
      await prefs.remove(_passwordPlainKey);
      return legacyPassword;
    }
    return null;
  }
}
