import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class CreatorAnalysisException implements Exception {
  const CreatorAnalysisException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class ConfigurationAdminRepository {
  final SupabaseClient _client;

  ConfigurationAdminRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<Map<String, dynamic>> loadContext() async {
    final values = await Future.wait<dynamic>([
      _client.rpc('appgt_contexto_constructor_v1'),
      _client.rpc('appgt_contexto_producto_v1'),
    ]);
    final builder = _map(values[0]);
    final product = _map(values[1]);
    return {
      ...builder,
      ...product,
      'puede_gestionar_empresa': builder['puede_gestionar'] == true,
      'puede_gestionar': builder['puede_gestionar'] == true &&
          product['zumac_creator_habilitado'] == true,
    };
  }

  Future<Map<String, dynamic>> loadProductContext() async {
    final value = await _client.rpc('appgt_contexto_producto_v1');
    return _map(value);
  }

  Future<Map<String, dynamic>> requestAdvancedAiPlan(
    String planCode,
  ) async {
    final value = await _client.rpc(
      'appgt_solicitar_plan_ia_v1',
      params: {'p_plan_codigo': planCode},
    );
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

  Future<Map<String, dynamic>> discardDraft(String draftId) async {
    final value = await _client.rpc(
      'appgt_descartar_borrador_configuracion',
      params: {'p_borrador_id': draftId},
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

  Future<List<Map<String, dynamic>>> listPublishedNavigation() async {
    try {
      // Creator no mantiene una fotografía paralela: antes de listar, refleja
      // las matrices canónicas vigentes (incluidos cambios hechos en Supabase).
      await _client.rpc('appgt_sincronizar_creator_desde_canonico_v2');
    } on PostgrestException catch (error) {
      // Permite desplegar la app antes que la migración sin ocultar errores
      // reales de permisos o integridad una vez que el RPC ya existe.
      if (error.code != 'PGRST202' && error.code != '42883') rethrow;
    }
    final results = await Future.wait(
      const ['RUBRO', 'SECCION', 'MODULO', 'FORMATO', 'TABLA']
          .map(_listAllPublishedTemplates),
    );
    final items = <Map<String, dynamic>>[];
    for (final result in results) {
      items.addAll(result);
    }
    return items;
  }

  Future<List<Map<String, dynamic>>> _listAllPublishedTemplates(
    String entityType,
  ) async {
    const pageSize = 200;
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await listTemplates(
        entityType: entityType,
        limit: pageSize,
        offset: offset,
      );
      final pageRows = _list(page['items']);
      rows.addAll(pageRows);
      final total =
          int.tryParse('${page['total'] ?? rows.length}') ?? rows.length;
      if (pageRows.isEmpty || rows.length >= total) break;
      offset += pageRows.length;
    }
    return rows;
  }

  Future<Map<String, dynamic>> createDraftFromPublished(
    String templateId,
  ) async {
    final value = await _client.rpc(
      'appgt_crear_borrador_desde_publicado',
      params: {'p_plantilla_id': templateId},
    );
    return _map(value);
  }

  Future<Map<String, dynamic>> previewConfiguration({
    required String entityType,
    required String entityId,
  }) async {
    final value = await _client.rpc(
      'appgt_previsualizar_configuracion',
      params: {
        'p_entidad_tipo': entityType,
        'p_entidad_id': entityId,
      },
    );
    return _map(value);
  }

  Future<Map<String, dynamic>> configurationHistory({
    required String entityType,
    required String entityId,
  }) async {
    final value = await _client.rpc(
      'appgt_historial_configuracion',
      params: {
        'p_entidad_tipo': entityType,
        'p_entidad_id': entityId,
      },
    );
    return _map(value);
  }

  Future<List<Map<String, dynamic>>> searchBuilderFieldCatalog({
    String? search,
    int limit = 250,
  }) async {
    final value = await _client.rpc(
      'appgt_catalogo_campos_constructor_v1',
      params: {
        'p_busqueda': search,
        'p_limit': limit,
      },
    );
    return _list(value);
  }

  Future<Map<String, dynamic>> createAiFormatImport({
    required String sourceName,
    required String mimeType,
    required int sizeBytes,
    required String sourceHash,
    required String sourceType,
    required Map<String, dynamic> localQuality,
  }) async {
    final value = await _client.rpc(
      'appgt_crear_importacion_formato_ia_v1',
      params: {
        'p_archivo_nombre': sourceName,
        'p_mime_type': mimeType,
        'p_tamano_bytes': sizeBytes,
        'p_hash_archivo': sourceHash,
        'p_tipo_origen': sourceType,
        'p_calidad_local': localQuality,
      },
    );
    return _map(value);
  }

  Future<Map<String, dynamic>> updateAiFormatImport({
    required String importId,
    required String status,
    Map<String, dynamic>? serverQuality,
    Map<String, dynamic>? rawAnalysis,
    Map<String, dynamic>? reviewedDefinition,
    int? headerRow,
    String? formLayout,
    String? recordLayout,
    String? draftId,
    String? model,
    String? errorMessage,
  }) async {
    final value = await _client.rpc(
      'appgt_actualizar_importacion_formato_ia_v1',
      params: {
        'p_importacion_id': importId,
        'p_estado': status,
        'p_calidad_servidor': serverQuality,
        'p_analisis_ia': rawAnalysis,
        'p_definicion_revisada': reviewedDefinition,
        'p_fila_encabezados': headerRow,
        'p_layout_formulario': formLayout,
        'p_layout_registros': recordLayout,
        'p_borrador_id': draftId,
        'p_modelo_ia': model,
        'p_error_mensaje': errorMessage,
      },
    );
    return _map(value);
  }

  Future<Map<String, dynamic>> analyzeFormatDocument({
    required String sourceName,
    required String mimeType,
    required Uint8List bytes,
    required String importId,
    String engine = 'ZUMAC',
  }) async {
    final response = await _client.functions.invoke(
      'appgt-analyze-format',
      body: {
        'file_name': sourceName,
        'mime_type': mimeType,
        'file_base64': base64Encode(bytes),
        'import_id': importId,
        'engine': engine,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      final payload = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      final message = payload['error']?.toString() ??
          response.data?.toString() ??
          'El analizador de documentos no respondió.';
      throw CreatorAnalysisException(
        payload['code']?.toString() ?? 'ANALYSIS_FAILED',
        message,
      );
    }
    return _map(response.data);
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
