import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'metrics_layout.dart';

/// Acceso a la configuración y a los datos de Metrics.
///
/// Los dashboards, gráficos y relaciones son metadatos: agregar una nueva
/// tabla o formato no requiere cambiar este repositorio. Las fuentes y campos
/// autorizados llegan desde [appgt_metrics_contexto_v1].
class MetricsRepository {
  MetricsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> loadContext() async {
    final values = await Future.wait<dynamic>([
      _client.rpc('appgt_metrics_contexto_v1'),
      _client.rpc('appgt_rol_empresa_actual'),
    ]);
    return <String, dynamic>{
      ..._map(values[0]),
      'rol': _text(values[1]).toUpperCase(),
    };
  }

  Future<List<Map<String, dynamic>>> listDashboards() async {
    try {
      final response = _map(
        await _client.rpc('appgt_listar_dashboards_metrics_v1'),
      );
      return _list(response['dashboards']);
    } on PostgrestException catch (error) {
      if (_isMissingRpc(error)) {
        throw StateError(
          'Falta aplicar la migración 039 de Metrics en Supabase.',
        );
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> listWidgets(String dashboardId) async =>
      _list(await _client
          .from('ZUMAC_METRICS_WIDGETS_APPGT')
          .select()
          .eq('dashboard_id', dashboardId)
          .eq('activo', true)
          .filter('deleted_at', 'is', null)
          .order('orden')
          .order('created_at'));

  Future<List<Map<String, dynamic>>> listRelations(
    String dashboardId,
  ) async =>
      _list(await _client
          .from('ZUMAC_METRICS_RELACIONES_APPGT')
          .select()
          .eq('dashboard_id', dashboardId)
          .eq('activo', true)
          .filter('deleted_at', 'is', null)
          .order('created_at'));

  Future<String?> findDashboardForSource(String table) async {
    final rows = _list(await _client
        .from('ZUMAC_METRICS_WIDGETS_APPGT')
        .select('dashboard_id')
        .eq('tabla_origen', table)
        .eq('activo', true)
        .filter('deleted_at', 'is', null)
        .limit(1));
    return rows.isEmpty ? null : rows.first['dashboard_id']?.toString();
  }

  Future<Map<String, dynamic>> saveDashboard(
    Map<String, dynamic> payload,
  ) async =>
      _map(await _client.rpc(
        'appgt_guardar_dashboard_metrics_v1',
        params: {'p_payload': payload},
      ));

  Future<List<Map<String, dynamic>>> reorderDashboards(
    List<String> dashboardIds,
  ) async {
    late final Map<String, dynamic> response;
    try {
      response = _map(await _client.rpc(
        'appgt_reordenar_dashboards_metrics_v4',
        params: {'p_ids': dashboardIds},
      ));
    } on PostgrestException catch (error) {
      // V2/V3 no ofrecen la verificación independiente de este flujo. Volver a
      // ellas haría posible mostrar nuevamente un falso “guardado”.
      if (_isMissingRpc(error)) {
        throw StateError(
          'Falta aplicar la migración 039 de Metrics en Supabase.',
        );
      }
      rethrow;
    }
    if (response['solicitado'] == true) {
      return listDashboards();
    }
    if (response['guardado'] != true) {
      throw StateError('PostgreSQL no confirmó el nuevo orden de dashboards.');
    }
    metricsVerifiedDashboardOrder(
      _list(response['dashboards']),
      dashboardIds,
    );

    // Segunda solicitud, fuera de la transacción que acaba de escribir. Es la
    // misma lectura que se ejecutará al actualizar la página.
    final reloaded = await listDashboards();
    return metricsVerifiedDashboardOrder(reloaded, dashboardIds);
  }

  Future<Map<String, dynamic>> saveWidget(
    Map<String, dynamic> payload,
  ) async {
    final dashboardId = _text(payload['dashboard_id']);
    if (dashboardId.isEmpty) {
      throw StateError('El gráfico no tiene dashboard.');
    }
    final before = await listWidgets(dashboardId);
    final response = _map(await _client.rpc(
      'appgt_guardar_widget_metrics_v1',
      params: {'p_payload': payload},
    ));
    if (response['solicitado'] == true) return response;
    final savedId = _text(response['id']);
    if (savedId.isEmpty || response['guardado'] != true) {
      throw StateError('Supabase no confirmó el gráfico guardado.');
    }
    final after = await listWidgets(dashboardId);
    final saved = metricsVerifiedWidgetSave(
      before: before,
      after: after,
      expected: <String, dynamic>{...payload, 'id': savedId},
      savedId: savedId,
    );
    return <String, dynamic>{
      ...response,
      'widget': saved,
      'widgets': after,
    };
  }

  Future<Map<String, dynamic>> saveWidgetGeometry({
    required String widgetId,
    required String dashboardId,
    required Map<String, dynamic> geometry,
  }) async =>
      _map(await _client.rpc(
        'appgt_guardar_geometria_widget_metrics_v2',
        params: {
          'p_widget_id': widgetId,
          'p_dashboard_id': dashboardId,
          'p_geometria': geometry,
        },
      ));

  Future<Map<String, dynamic>> saveRelation(
    Map<String, dynamic> payload,
  ) async =>
      _map(await _client.rpc(
        'appgt_guardar_relacion_metrics_v1',
        params: {'p_payload': payload},
      ));

  Future<List<String>> listDistinctValues({
    required String table,
    required String field,
    int limit = 2500,
  }) async {
    final rows = _list(await _client
        .from(table)
        .select(_quotedIdentifier(field))
        .limit(limit));
    final values = rows
        .map((row) => _text(row[field]))
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  Future<Map<String, dynamic>> deleteItem(String type, String id) async {
    return _map(await _client.rpc(
      'appgt_eliminar_metrics_v1',
      params: {'p_tipo': type, 'p_id': id},
    ));
  }

  /// Lee únicamente las columnas necesarias y aplica filtros antes de agregar.
  /// El límite evita descargar una tabla completa accidentalmente. El backend
  /// puede sustituirse por una vista materializada sin cambiar la interfaz.
  Future<MetricDataset> queryWidget({
    required Map<String, dynamic> widget,
    required List<Map<String, dynamic>> relations,
    List<MetricGlobalFilter> globalFilters = const [],
    int rowLimit = 5000,
  }) async {
    final table = _text(widget['tabla_origen']);
    final dimension = _text(widget['campo_dimension']);
    final configuration = _map(widget['configuracion']);
    final dimensions = (configuration['dimensions'] as List? ?? const [])
        .map(_text)
        .where((value) => value.isNotEmpty)
        .toList();
    if (dimensions.isEmpty && dimension.isNotEmpty) dimensions.add(dimension);
    final valueField = _text(widget['campo_valor']);
    final valueFields = (configuration['values'] as List? ?? const [])
        .map(_text)
        .where((value) => value.isNotEmpty)
        .toList();
    if (valueFields.isEmpty && valueField.isNotEmpty) {
      valueFields.add(valueField);
    }
    final secondaryValueFields =
        (configuration['values_y2'] as List? ?? const [])
            .map(_text)
            .where((value) => value.isNotEmpty)
            .toList();
    final detailFields = (configuration['details'] as List? ?? const [])
        .map(_text)
        .where((value) => value.isNotEmpty)
        .toList();
    final valueAggregations = _map(configuration['value_aggregations']);
    final seriesField = _text(widget['campo_serie']);
    final fields = <String>{
      ...dimensions,
      ...valueFields,
      ...secondaryValueFields,
      ...detailFields,
      if (seriesField.isNotEmpty) seriesField,
    };
    final fixedFilters = _maps(widget['filtros']);
    for (final filter in fixedFilters) {
      final field = _text(filter['field']);
      if (field.isNotEmpty) fields.add(field);
    }
    dynamic query = _client
        .from(table)
        .select(fields.isEmpty ? '*' : fields.map(_quotedIdentifier).join(','));
    query = _applyFilters(query, fixedFilters);

    for (final globalFilter in globalFilters) {
      if (!_hasFilterValue(globalFilter.value)) continue;
      if (globalFilter.table == table) {
        query = _applyGlobalFilter(query, globalFilter);
      } else {
        final path = _relationshipPath(
          relations,
          globalFilter.table,
          table,
        );
        if (path != null && path.isNotEmpty) {
          final firstHop = path.first;
          dynamic relatedQuery = _client
              .from(globalFilter.table)
              .select(_quotedIdentifier(firstHop.fromField));
          relatedQuery = _applyGlobalFilter(relatedQuery, globalFilter);
          var relatedRows = _list(await relatedQuery.limit(2000));
          var keys = relatedRows
              .map((row) => row[firstHop.fromField])
              .where((value) => value != null)
              .toSet()
              .toList();
          if (keys.isEmpty) return const MetricDataset(points: [], rows: []);
          for (var index = 1; index < path.length; index++) {
            final previous = path[index - 1];
            final hop = path[index];
            relatedRows = _list(await _client
                .from(hop.fromTable)
                .select(_quotedIdentifier(hop.fromField))
                .inFilter(previous.toField, keys)
                .limit(5000));
            keys = relatedRows
                .map((row) => row[hop.fromField])
                .where((value) => value != null)
                .toSet()
                .toList();
            if (keys.isEmpty) {
              return const MetricDataset(points: [], rows: []);
            }
          }
          query = query.inFilter(path.last.toField, keys);
        }
      }
    }

    final rows = _list(await query.limit(rowLimit));
    final aggregation = _text(widget['agregacion']).toUpperCase();
    final grouped = <String, _Accumulator>{};
    final detailsByGroup = <String, String>{};
    final allValueFields = <String>[...valueFields, ...secondaryValueFields];
    for (final row in rows) {
      final label = dimensions.isEmpty
          ? 'Total'
          : dimensions.map((field) {
              final value = _text(row[field]);
              return value.isEmpty ? 'Sin valor' : value;
            }).join(' · ');
      for (final currentValueField
          in allValueFields.isEmpty ? const [''] : allValueFields) {
        final configuredSeries =
            seriesField.isEmpty ? '' : _text(row[seriesField]);
        final valueSeries = allValueFields.length > 1 ? currentValueField : '';
        final series = [configuredSeries, valueSeries]
            .where((value) => value.isNotEmpty)
            .join(' · ');
        final axis =
            secondaryValueFields.contains(currentValueField) ? 'y2' : 'y';
        final key = '$label\u0000$series\u0000$axis\u0000$currentValueField';
        final accumulator = grouped.putIfAbsent(key, _Accumulator.new);
        accumulator.add(_number(row[currentValueField]));
        if (detailFields.isNotEmpty) {
          detailsByGroup[key] = detailFields
              .map((field) => '${_text(field)}: ${_text(row[field])}')
              .join('\n');
        }
      }
    }
    final points = grouped.entries.map((entry) {
      final pieces = entry.key.split('\u0000');
      return MetricPoint(
        label: pieces.first,
        dimensionValues: pieces.first == 'Total'
            ? const <String>[]
            : pieces.first.split(' · '),
        series: pieces.length > 1 ? pieces[1] : '',
        axis: pieces.length > 2 ? pieces[2] : 'y',
        valueField: pieces.length > 3 ? pieces[3] : '',
        detail: detailsByGroup[entry.key] ?? '',
        value: entry.value.result(
          _text(valueAggregations[pieces.length > 3 ? pieces[3] : ''])
                  .toUpperCase()
                  .isNotEmpty
              ? _text(valueAggregations[pieces.length > 3 ? pieces[3] : ''])
                  .toUpperCase()
              : aggregation,
        ),
        count: entry.value.count,
      );
    }).toList();
    switch (_text(configuration['sort_mode'])) {
      case 'label_desc':
        points.sort((a, b) => b.label.compareTo(a.label));
        break;
      case 'value_asc':
        points.sort((a, b) => a.value.compareTo(b.value));
        break;
      case 'value_desc':
        points.sort((a, b) => b.value.compareTo(a.value));
        break;
      default:
        points.sort((a, b) => a.label.compareTo(b.label));
    }
    return MetricDataset(
        points: points, rows: rows, truncated: rows.length >= rowLimit);
  }

  dynamic _applyFilters(dynamic query, List<Map<String, dynamic>> filters) {
    var output = query;
    for (final filter in filters) {
      final field = _text(filter['field']);
      final operator = _text(filter['operator']).toLowerCase();
      final value = filter['value'];
      if (field.isEmpty || value == null || _text(value).isEmpty) continue;
      switch (operator) {
        case 'neq':
          output = output.neq(field, value);
          break;
        case 'gt':
          output = output.gt(field, value);
          break;
        case 'gte':
          output = output.gte(field, value);
          break;
        case 'lt':
          output = output.lt(field, value);
          break;
        case 'lte':
          output = output.lte(field, value);
          break;
        case 'contains':
          output = output.ilike(field, '%$value%');
          break;
        default:
          output = output.eq(field, value);
      }
    }
    return output;
  }

  bool _hasFilterValue(dynamic value) {
    if (value is List) return value.isNotEmpty;
    if (value is Map) {
      return value.values.any((item) => _text(item).isNotEmpty);
    }
    return _text(value).isNotEmpty;
  }

  dynamic _applyGlobalFilter(dynamic query, MetricGlobalFilter filter) {
    final operator = filter.operator.toLowerCase();
    final value = filter.value;
    if (operator == 'list') {
      final values = value is List
          ? value.where((item) => _text(item).isNotEmpty).toList()
          : <dynamic>[value];
      return values.isEmpty ? query : query.inFilter(filter.field, values);
    }
    if (operator == 'between' || operator == 'range') {
      final values = value is Map ? value : const <String, dynamic>{};
      final start = values['start'] ?? values['min'];
      final end = values['end'] ?? values['max'];
      if (_text(start).isNotEmpty) query = query.gte(filter.field, start);
      if (_text(end).isNotEmpty) query = query.lte(filter.field, end);
      return query;
    }
    switch (operator) {
      case 'neq':
      case 'not_equal':
        return query.neq(filter.field, value);
      case 'gt':
      case 'after':
        return query.gt(filter.field, value);
      case 'gte':
        return query.gte(filter.field, value);
      case 'lt':
      case 'before':
        return query.lt(filter.field, value);
      case 'lte':
        return query.lte(filter.field, value);
      case 'contains':
        return query.ilike(filter.field, '%$value%');
      case 'not_contains':
        return query.not(filter.field, 'ilike', '%$value%');
      default:
        return query.eq(filter.field, value);
    }
  }

  List<_RelationHop>? _relationshipPath(
    List<Map<String, dynamic>> relations,
    String start,
    String target,
  ) {
    if (start == target) return const [];
    final queue = <(String, List<_RelationHop>)>[(start, const [])];
    final visited = <String>{start};
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (current.$2.length >= 8) continue;
      for (final relation in relations) {
        final origin = _text(relation['tabla_origen']);
        final destination = _text(relation['tabla_destino']);
        _RelationHop? hop;
        if (origin == current.$1) {
          hop = _RelationHop(
            fromTable: origin,
            fromField: _text(relation['campo_origen']),
            toTable: destination,
            toField: _text(relation['campo_destino']),
          );
        } else if (destination == current.$1) {
          hop = _RelationHop(
            fromTable: destination,
            fromField: _text(relation['campo_destino']),
            toTable: origin,
            toField: _text(relation['campo_origen']),
          );
        }
        if (hop == null ||
            hop.fromField.isEmpty ||
            hop.toField.isEmpty ||
            visited.contains(hop.toTable)) {
          continue;
        }
        final nextPath = [...current.$2, hop];
        if (hop.toTable == target) return nextPath;
        visited.add(hop.toTable);
        queue.add((hop.toTable, nextPath));
      }
    }
    return null;
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String _quotedIdentifier(String value) {
    if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value)) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(_text(value).replaceAll(',', '.'));
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _list(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false)
      : const [];

  List<Map<String, dynamic>> _maps(dynamic value) => _list(value);

  bool _isMissingRpc(PostgrestException error) =>
      error.code == 'PGRST202' || error.code == '42883';
}

class MetricGlobalFilter {
  const MetricGlobalFilter({
    this.id = '',
    required this.table,
    required this.field,
    required this.value,
    this.operator = 'eq',
  });

  final String id;
  final String table;
  final String field;
  final dynamic value;
  final String operator;
}

class MetricPoint {
  const MetricPoint({
    required this.label,
    required this.value,
    required this.count,
    this.series = '',
    this.axis = 'y',
    this.valueField = '',
    this.detail = '',
    this.dimensionValues = const <String>[],
  });

  final String label;
  final String series;
  final String axis;
  final String valueField;
  final String detail;
  final List<String> dimensionValues;
  final double value;
  final int count;
}

class MetricDataset {
  const MetricDataset({
    required this.points,
    required this.rows,
    this.truncated = false,
  });

  final List<MetricPoint> points;
  final List<Map<String, dynamic>> rows;
  final bool truncated;
}

class _Accumulator {
  int count = 0;
  int numericCount = 0;
  double sum = 0;
  double? min;
  double? max;
  final List<double> values = [];

  void add(double? value) {
    count++;
    if (value == null) return;
    numericCount++;
    values.add(value);
    sum += value;
    min = min == null ? value : math.min(min!, value);
    max = max == null ? value : math.max(max!, value);
  }

  double result(String aggregation) {
    switch (aggregation) {
      case 'SUM':
        return sum;
      case 'NONE':
        return values.isEmpty ? 0 : values.last;
      case 'SUBTRACT':
        if (values.isEmpty) return 0;
        return values
            .skip(1)
            .fold(values.first, (total, value) => total - value);
      case 'AVG':
        return numericCount == 0 ? 0 : sum / numericCount;
      case 'MEDIAN':
        if (values.isEmpty) return 0;
        final ordered = [...values]..sort();
        final middle = ordered.length ~/ 2;
        return ordered.length.isOdd
            ? ordered[middle]
            : (ordered[middle - 1] + ordered[middle]) / 2;
      case 'MODE':
        if (values.isEmpty) return 0;
        final counts = <double, int>{};
        for (final value in values) {
          counts[value] = (counts[value] ?? 0) + 1;
        }
        return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      case 'MIN':
        return min ?? 0;
      case 'MAX':
        return max ?? 0;
      default:
        return count.toDouble();
    }
  }
}

class _RelationHop {
  const _RelationHop({
    required this.fromTable,
    required this.fromField,
    required this.toTable,
    required this.toField,
  });

  final String fromTable;
  final String fromField;
  final String toTable;
  final String toField;
}
