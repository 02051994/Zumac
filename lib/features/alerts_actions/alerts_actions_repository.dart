import 'package:supabase_flutter/supabase_flutter.dart';

/// Único punto de acceso remoto para Alerts y Actions.
///
/// La interfaz no escribe directamente eventos ni transiciones de estado: esas
/// operaciones pasan por RPC para que Supabase vuelva a comprobar empresa,
/// usuario, rol y transición aunque un cliente sea manipulado.
class AlertsActionsRepository {
  AlertsActionsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> loadContext() async =>
      _map(await _client.rpc('appgt_alertas_contexto_v1'));

  Future<List<Map<String, dynamic>>> listRules() async => _list(await _client
      .from('ZUMAC_ALERTAS_APPGT')
      .select()
      .filter('deleted_at', 'is', null)
      .order('activa', ascending: false)
      .order('updated_at', ascending: false));

  Future<List<Map<String, dynamic>>> listEvents({int limit = 100}) async =>
      _list(await _client
          .from('ZUMAC_ALERTA_EVENTOS_APPGT')
          .select()
          .order('ultima_ocurrencia_at', ascending: false)
          .limit(limit));

  Future<List<Map<String, dynamic>>> listActions({int limit = 100}) async =>
      _list(await _client
          .from('ZUMAC_ACCIONES_APPGT')
          .select()
          .filter('deleted_at', 'is', null)
          .order('updated_at', ascending: false)
          .limit(limit));

  /// Tablas que ya tienen al menos un gráfico activo en Metrics.
  Future<Set<String>> listTablesWithMetrics() async {
    try {
      final rows = _list(await _client
          .from('ZUMAC_METRICS_WIDGETS_APPGT')
          .select('tabla_origen')
          .eq('activo', true)
          .filter('deleted_at', 'is', null));
      return rows
          .map((row) => row['tabla_origen']?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .toSet();
    } catch (_) {
      // Permite abrir Alerts mientras la migración de Metrics aún no se publicó.
      return <String>{};
    }
  }

  Future<List<Map<String, dynamic>>> listComments(String actionId) async =>
      _list(await _client
          .from('ZUMAC_ACCION_COMENTARIOS_APPGT')
          .select()
          .eq('accion_id', actionId)
          .order('created_at'));

  Future<Map<String, dynamic>> saveRule(Map<String, dynamic> payload) async =>
      _map(await _client.rpc(
        'appgt_guardar_alerta_v1',
        params: {'p_payload': payload},
      ));

  Future<Map<String, dynamic>> testRule(Map<String, dynamic> payload) async =>
      _map(await _client.rpc(
        'appgt_probar_alerta_v1',
        params: {'p_payload': payload},
      ));

  Future<Map<String, dynamic>> evaluateNow() async => _map(await _client.rpc(
        'appgt_evaluar_alertas_v1',
        params: {'p_limit': 100},
      ));

  Future<Map<String, dynamic>> setRuleActive(
    String ruleId,
    bool active,
  ) async =>
      _map(await _client.rpc(
        'appgt_cambiar_alerta_activa_v1',
        params: {'p_alerta_id': ruleId, 'p_activa': active},
      ));

  Future<Map<String, dynamic>> deleteRule(String ruleId) async =>
      _map(await _client.rpc(
        'appgt_eliminar_alerta_v1',
        params: {'p_alerta_id': ruleId},
      ));

  Future<Map<String, dynamic>> updateEvent(
    String eventId, {
    String? state,
    String? responsibleId,
  }) async =>
      _map(await _client.rpc(
        'appgt_actualizar_evento_alerta_v1',
        params: {
          'p_evento_id': eventId,
          'p_estado': state,
          'p_responsable_id': responsibleId,
        },
      ));

  Future<Map<String, dynamic>> saveAction(Map<String, dynamic> payload) async =>
      _map(await _client.rpc(
        'appgt_guardar_accion_v1',
        params: {'p_payload': payload},
      ));

  Future<Map<String, dynamic>> updateAction(
    String actionId,
    String state, {
    Map<String, dynamic> result = const {},
  }) async =>
      _map(await _client.rpc(
        'appgt_actualizar_accion_v1',
        params: {
          'p_accion_id': actionId,
          'p_estado': state,
          'p_resultado': result,
        },
      ));

  Future<Map<String, dynamic>> addComment(
    String actionId,
    String comment, {
    List<Map<String, dynamic>> evidence = const [],
  }) async =>
      _map(await _client.rpc(
        'appgt_comentar_accion_v1',
        params: {
          'p_accion_id': actionId,
          'p_comentario': comment,
          'p_evidencia': evidence,
        },
      ));

  Future<Map<String, dynamic>> deleteAction(String actionId) async =>
      _map(await _client.rpc(
        'appgt_eliminar_accion_v1',
        params: {'p_accion_id': actionId},
      ));

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _list(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
}
