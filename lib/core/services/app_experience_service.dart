import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Guarda únicamente estado de experiencia local: navegación, filtros y
/// borradores automáticos. Los datos operativos continúan en SQLite/Supabase.
class AppExperienceService {
  static const _navigationKey = 'appgt.experience.navigation.v1';
  static const _creatorViewKey = 'appgt.experience.creator_view.v1';
  static const _lastSyncKey = 'appgt.experience.last_sync.v1';

  Future<Map<String, dynamic>> loadNavigation() => _loadMap(_navigationKey);

  Future<void> saveNavigation(Map<String, dynamic> value) =>
      _saveMap(_navigationKey, value);

  Future<Map<String, dynamic>> loadCreatorView() => _loadMap(_creatorViewKey);

  Future<void> saveCreatorView(Map<String, dynamic> value) =>
      _saveMap(_creatorViewKey, value);

  Future<DateTime?> loadLastSync() async {
    final preferences = await SharedPreferences.getInstance();
    return DateTime.tryParse(preferences.getString(_lastSyncKey) ?? '');
  }

  Future<void> saveLastSync(DateTime value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lastSyncKey, value.toIso8601String());
  }

  Future<Map<String, dynamic>> loadToolAccess({
    required String userId,
    required String empresaId,
  }) =>
      _loadMap(_toolAccessKey(userId, empresaId));

  Future<void> saveToolAccess({
    required String userId,
    required String empresaId,
    required Map<String, dynamic> value,
  }) =>
      _saveMap(_toolAccessKey(userId, empresaId), value);

  Future<Map<String, dynamic>> loadBuilderDraft(String key) =>
      _loadMap(_draftKey(key));

  Future<void> saveBuilderDraft(
    String key,
    Map<String, dynamic> value,
  ) =>
      _saveMap(_draftKey(key), value);

  Future<void> clearBuilderDraft(String key) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_draftKey(key));
  }

  Future<Map<String, dynamic>> loadRecordView(String key) =>
      _loadMap(_recordViewKey(key));

  Future<void> saveRecordView(String key, Map<String, dynamic> value) =>
      _saveMap(_recordViewKey(key), value);

  String _draftKey(String key) => 'appgt.experience.builder.$key.v1';

  String _recordViewKey(String key) => 'appgt.experience.records.$key.v1';

  String _toolAccessKey(String userId, String empresaId) =>
      'appgt.experience.tool_access.$empresaId.$userId.v1';

  Future<Map<String, dynamic>> _loadMap(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _saveMap(String key, Map<String, dynamic> value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, jsonEncode(value));
  }
}
