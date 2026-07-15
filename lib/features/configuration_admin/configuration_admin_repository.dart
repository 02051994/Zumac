import 'package:supabase_flutter/supabase_flutter.dart';

class ConfigurationAdminRepository {
  final SupabaseClient _client;

  ConfigurationAdminRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<Map<String, dynamic>> loadContext() async {
    final value = await _client.rpc('appgt_contexto_constructor_v1');
    return _map(value);
  }

  Future<Map<String, dynamic>> listTemplates({
    String? entityType,
    String? rubroId,
    String? parentId,
    String? search,
    int limit = 100,
    int offset = 0,
  }) async {
    final value = await _client.rpc(
      'appgt_listar_plantillas_configuracion',
      params: {
        'p_entidad_tipo': entityType,
        'p_rubro_id': rubroId,
        'p_padre_origen_id': parentId,
        'p_busqueda': search,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return _map(value);
  }

  Future<List<Map<String, dynamic>>> listDrafts({
    String? state,
    String? entityType,
  }) async {
    final value = await _client.rpc(
      'appgt_listar_borradores_configuracion',
      params: {
        'p_estado': state,
        'p_entidad_tipo': entityType,
      },
    );
    return _list(value);
  }

  Future<Map<String, dynamic>> saveDraft({
    required String entityType,
    required Map<String, dynamic> payload,
    String? draftId,
    String? templateId,
    int? lockVersion,
  }) async {
    final value = await _client.rpc(
      'appgt_guardar_borrador_configuracion',
      params: {
        'p_entidad_tipo': entityType,
        'p_payload': payload,
        'p_borrador_id': draftId,
        'p_plantilla_origen_id': templateId,
        'p_lock_version': lockVersion,
      },
    );
    return _map(value);
  }

  Future<Map<String, dynamic>> validateDraft(String draftId) async {
    final value = await _client.rpc(
      'appgt_validar_borrador_configuracion',
      params: {'p_borrador_id': draftId},
    );
    return _map(value);
  }

  Future<Map<String, dynamic>> publishDraft(
    String draftId, {
    String? notes,
  }) async {
    final value = await _client.rpc(
      'appgt_publicar_borrador_configuracion',
      params: {
        'p_borrador_id': draftId,
        'p_notas': notes,
      },
    );
    return _map(value);
  }

  Future<Map<String, dynamic>> loadFullFormatTemplate(
    String templateId,
  ) async {
    final value = await _client.rpc(
      'appgt_obtener_plantilla_formato_completa',
      params: {'p_plantilla_id': templateId},
    );
    return _map(value);
  }

  Future<Map<String, dynamic>> validateFormatStructure(String draftId) async {
    final value = await _client.rpc(
      'appgt_validar_estructura_formato',
      params: {'p_borrador_id': draftId},
    );
    return _map(value);
  }

  Future<Map<String, dynamic>> publishFormatStructure(
    String draftId, {
    String? notes,
  }) async {
    final value = await _client.rpc(
      'appgt_publicar_estructura_formato',
      params: {
        'p_borrador_id': draftId,
        'p_notas': notes,
      },
    );
    return _map(value);
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw StateError('El servidor devolvió una respuesta inesperada.');
  }

  List<Map<String, dynamic>> _list(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
}
