import 'package:supabase_flutter/supabase_flutter.dart';

class PermissionManagementRepository {
  PermissionManagementRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> loadContext() async {
    final context =
        _map(await _client.rpc('appgt_contexto_gestion_permisos_v2'));
    try {
      final tools = _map(
        await _client.rpc('appgt_catalogo_permisos_herramientas_v1'),
      );
      context['herramientas'] = tools['herramientas'] ?? const [];
    } on PostgrestException catch (error) {
      if (error.code != 'PGRST202' && error.code != '42883') rethrow;
    }
    return context;
  }

  Future<Map<String, dynamic>> loadUserAccess(String userId) async {
    final access = _map(
      await _client.rpc(
        'appgt_acceso_usuario_v2',
        params: {'p_user_id': userId},
      ),
    );
    try {
      final tools = _map(
        await _client.rpc(
          'appgt_permisos_herramientas_usuario_v1',
          params: {'p_user_id': userId},
        ),
      );
      access['permisos_herramientas'] =
          tools['permisos_herramientas'] ?? const [];
    } on PostgrestException catch (error) {
      if (error.code != 'PGRST202' && error.code != '42883') rethrow;
    }
    return access;
  }

  Future<Map<String, dynamic>> loadCurrentToolAccess() async =>
      _map(await _client.rpc('appgt_acceso_herramientas_actual_v1'));

  Future<Map<String, dynamic>> saveToolPermissions({
    required String userId,
    required List<Map<String, dynamic>> permissions,
  }) async =>
      _map(await _client.rpc(
        'appgt_guardar_permisos_herramientas_v1',
        params: {'p_user_id': userId, 'p_permisos': permissions},
      ));

  Future<Map<String, dynamic>> assignRole({
    required String userId,
    required String role,
  }) async =>
      _map(await _client.rpc(
        'appgt_asignar_rol_empresa_v2',
        params: {'p_user_id': userId, 'p_rol': role},
      ));

  Future<Map<String, dynamic>> saveFormatPermissions({
    required String userId,
    required List<Map<String, dynamic>> permissions,
  }) async {
    final result = _map(await _client.rpc(
      'appgt_guardar_permisos_formatos_v1',
      params: {'p_user_id': userId, 'p_permisos': permissions},
    ));
    final withStates = permissions
        .where((item) => item['permisos_estado'] is Map)
        .toList(growable: false);
    if (withStates.isNotEmpty) {
      await _client.rpc(
        'appgt_guardar_permisos_estado_formatos_v1',
        params: {'p_user_id': userId, 'p_permisos': withStates},
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> revokeFormats({
    required String userId,
    required List<String> formatIds,
  }) async =>
      _map(await _client.rpc(
        'appgt_revocar_permisos_formatos_v1',
        params: {'p_user_id': userId, 'p_formatos': formatIds},
      ));

  Future<List<Map<String, dynamic>>> listMetricRequests() async {
    final response = _map(
      await _client.rpc('appgt_listar_solicitudes_metrics_v1'),
    );
    final rows = response['solicitudes'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> resolveMetricRequest({
    required String requestId,
    required bool approve,
    String? comment,
  }) async =>
      _map(await _client.rpc(
        'appgt_resolver_solicitud_metrics_v1',
        params: {
          'p_solicitud_id': requestId,
          'p_aprobar': approve,
          'p_comentario': comment,
        },
      ));

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}
