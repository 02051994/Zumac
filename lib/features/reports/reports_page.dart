import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReportsPage extends StatefulWidget {
  final bool embedded;
  final String? initialModuleId;
  final String? initialViewId;
  final bool showRail;

  const ReportsPage({
    super.key,
    this.embedded = false,
    this.initialModuleId,
    this.initialViewId,
    this.showRail = true,
  });

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _supabase = Supabase.instance.client;

  bool loadingViews = true;
  bool loadingConfig = false;
  bool loadingData = false;
  String? error;

  List<Map<String, dynamic>> reportModules = [];
  List<Map<String, dynamic>> allViews = [];
  List<Map<String, dynamic>> views = [];
  List<Map<String, dynamic>> reportPermissions = [];
  List<Map<String, dynamic>> filters = [];
  List<Map<String, dynamic>> charts = [];
  Map<String, dynamic>? selectedModule;
  Map<String, dynamic>? selectedView;
  final Map<String, dynamic> selectedFilters = {};
  final Map<String, List<Map<String, dynamic>>> chartRows = {};
  final Map<String, List<Map<String, dynamic>>> _reportFieldsByTable = {};

  @override
  void initState() {
    super.initState();
    _loadReportShell();
  }

  bool _asBool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    final s = value.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'si' || s == 'sí' || s == 'yes';
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _asDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  List<dynamic> _asList(dynamic value) {
    if (value == null) return const [];
    if (value is List) return value;
    return const [];
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value == null) return const {};
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  String _normKey(dynamic value) {
    var s = _text(value).toLowerCase();
    const map = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n'
    };
    map.forEach((k, v) => s = s.replaceAll(k, v));
    return s
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _stripReference(dynamic value) {
    var out = _text(value);
    if (out.startsWith('[') && out.endsWith(']'))
      out = out.substring(1, out.length - 1);
    if (out.startsWith('{{') && out.endsWith('}}'))
      out = out.substring(2, out.length - 2);
    return out.trim();
  }

  String _fieldColumn(String table, dynamic identifier) {
    final clean = _stripReference(identifier);
    if (clean.isEmpty) return '';
    final wanted = _normKey(clean);
    final fields =
        _reportFieldsByTable[_normKey(table)] ?? const <Map<String, dynamic>>[];
    for (final field in fields) {
      final matches = [
        field['id'],
        field['campo'],
        field['etiqueta'],
      ].any((value) => _normKey(value) == wanted);
      if (matches)
        return _text(field['campo']).isNotEmpty ? _text(field['campo']) : clean;
    }
    return clean;
  }

  String _quoteColumn(String column) => column.contains(' ') ||
          column.contains('-') ||
          column.contains('/') ||
          column.contains('(') ||
          column.contains(')')
      ? '"$column"'
      : column;

  Future<void> _ensureReportFieldsForTable(String table) async {
    final tableName = _text(table);
    final key = _normKey(tableName);
    if (tableName.isEmpty || _reportFieldsByTable.containsKey(key)) return;
    try {
      final rows = await _supabase
          .from('MATRIZ_CAMPOS_FORMATO_APPGT')
          .select()
          .eq('tabla_destino', tableName)
          .order('orden');
      _reportFieldsByTable[key] = List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      _reportFieldsByTable[key] = const <Map<String, dynamic>>[];
    }
  }

  String _chartTitle(Map<String, dynamic> chart) {
    final titulo = _asMap(chart['titulo']);
    final dynamicText = _text(titulo['texto']);
    if (dynamicText.isNotEmpty) {
      var output = dynamicText;
      selectedFilters.forEach((key, value) {
        output = output.replaceAll('{$key}', value?.toString() ?? '');
      });
      return output;
    }
    return _text(chart['nombre_grafico']).isNotEmpty
        ? _text(chart['nombre_grafico'])
        : _text(chart['codigo_grafico']);
  }

  String _viewModuleId(Map<String, dynamic> view) {
    final direct = _text(view['id_modulo_reporte']);
    if (direct.isNotEmpty) return direct;

    // Compatibilidad con la matriz anterior: si aún no agregaste id_modulo_reporte,
    // se intenta resolver por modulo/subseccion. Lo correcto desde ahora es usar id_modulo_reporte.
    final candidates = [view['modulo'], view['subseccion'], view['seccion']];
    for (final candidate in candidates) {
      final n = _normKey(candidate);
      if (n.isEmpty || n == 'reportes') continue;
      final module = reportModules
          .where((m) => _normKey(m['id']) == n || _normKey(m['nombre']) == n)
          .toList();
      if (module.isNotEmpty) return _text(module.first['id']);
    }
    return '';
  }

  bool _hasPermissionForView(String viewId, String moduleId) {
    final user = _supabase.auth.currentUser;
    if (user == null) return true;

    // Si no hay registros de permisos, se deja visible para no bloquear el desarrollo inicial.
    // Cuando empieces a llenar PERMISOS_REPORTES_USUARIOS_APPGT, solo se mostrarán los permitidos.
    if (reportPermissions.isEmpty) return true;

    return reportPermissions.any((p) {
      final sameView = _text(p['id_vista_reporte']) == viewId;
      final sameModule = _text(p['id_modulo_reporte']) == moduleId;
      return sameView &&
          sameModule &&
          _asBool(p['puede_ver'], fallback: true) &&
          _asBool(p['activo'], fallback: true);
    });
  }

  List<Map<String, dynamic>> _viewsForModule(Map<String, dynamic> module) {
    final moduleId = _text(module['id']);
    final moduleViews = allViews.where((view) {
      final viewId = _text(view['id']);
      if (viewId.isEmpty) return false;
      final viewModuleId = _viewModuleId(view);
      if (viewModuleId != moduleId) return false;
      return _hasPermissionForView(viewId, moduleId);
    }).toList();

    moduleViews
        .sort((a, b) => _asInt(a['orden']).compareTo(_asInt(b['orden'])));
    return moduleViews;
  }

  Future<void> _loadReportShell() async {
    setState(() {
      loadingViews = true;
      error = null;
    });

    try {
      // Lectura tolerante: algunas matrices nuevas pueden estar recién creadas,
      // con RLS/policies en ajuste o con cache de esquema. Por eso primero leemos
      // todo y filtramos/ordenamos en Flutter.
      final moduleRows =
          await _supabase.from('MATRIZ_MODULOS_GRAFICOS_DINAMICOS').select();

      final viewRows = await _supabase.from('MATRIZ_VISTAS_REPORTES').select();

      List<Map<String, dynamic>> permissionRows = [];
      final user = _supabase.auth.currentUser;
      if (user != null) {
        try {
          final perms = await _supabase
              .from('PERMISOS_REPORTES_USUARIOS_APPGT')
              .select()
              .eq('user_id', user.id)
              .eq('activo', true);
          permissionRows = List<Map<String, dynamic>>.from(perms);
        } catch (_) {
          permissionRows = [];
        }
      }

      final loadedViews = List<Map<String, dynamic>>.from(viewRows)
          .where((v) => _asBool(v['activo'], fallback: true))
          .toList()
        ..sort((a, b) => _asInt(a['orden']).compareTo(_asInt(b['orden'])));

      var loadedModules = List<Map<String, dynamic>>.from(moduleRows)
          .where((m) => _asBool(m['activo'], fallback: true))
          .toList()
        ..sort((a, b) => _asInt(a['orden']).compareTo(_asInt(b['orden'])));

      // Respaldo: si por cualquier motivo la tabla de módulos devuelve vacío,
      // se derivan módulos desde las vistas activas para no dejar la pantalla en blanco.
      if (loadedModules.isEmpty && loadedViews.isNotEmpty) {
        final derived = <String, Map<String, dynamic>>{};
        for (final view in loadedViews) {
          final moduleId = _text(view['id_modulo_reporte']);
          if (moduleId.isEmpty) continue;
          derived[moduleId] = {
            'id': moduleId,
            'nombre': moduleId
                .replaceAll('grafico_', '')
                .replaceAll('_', ' ')
                .toUpperCase(),
            'orden': _asInt(view['orden']),
            'activo': true,
          };
        }
        loadedModules = derived.values.toList()
          ..sort((a, b) => _asInt(a['orden']).compareTo(_asInt(b['orden'])));
      }

      if (!mounted) return;
      setState(() {
        reportModules = loadedModules;
        allViews = loadedViews;
        reportPermissions = permissionRows;
        loadingViews = false;
      });

      if (loadedModules.isNotEmpty) {
        final preferredModule = loadedModules.firstWhere(
          (m) => _text(m['id']) == _text(widget.initialModuleId),
          orElse: () => loadedModules.first,
        );
        await _selectModule(preferredModule,
            preferredViewId: widget.initialViewId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingViews = false;
        error = 'No se pudo leer matrices de reportes: $e';
      });
    }
  }

  Future<void> _selectModule(Map<String, dynamic> module,
      {String? preferredViewId}) async {
    final moduleViews = _viewsForModule(module);
    setState(() {
      selectedModule = module;
      views = moduleViews;
      selectedView = null;
      filters = [];
      charts = [];
      selectedFilters.clear();
      chartRows.clear();
      error = null;
    });

    if (moduleViews.isNotEmpty && _text(preferredViewId).isNotEmpty) {
      final preferredView = moduleViews.firstWhere(
        (v) => _text(v['id']) == _text(preferredViewId),
        orElse: () => moduleViews.first,
      );
      await _selectView(preferredView);
    }
  }

  Future<List<Map<String, dynamic>>> _readConfigByVista(
      String table, String vistaId) async {
    try {
      final rows = await _supabase
          .from(table)
          .select()
          .eq('vista_id', vistaId)
          .eq('activo', true)
          .order('orden');
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      final rows = await _supabase
          .from(table)
          .select()
          .eq('id_vista_reporte', vistaId)
          .eq('activo', true)
          .order('orden');
      return List<Map<String, dynamic>>.from(rows);
    }
  }

  Future<void> _selectView(Map<String, dynamic> view) async {
    setState(() {
      selectedView = view;
      selectedFilters.clear();
      chartRows.clear();
      loadingConfig = true;
      error = null;
    });

    final vistaId = _text(view['id']);
    try {
      final filterRows =
          await _readConfigByVista('MATRIZ_FILTROS_DINAMICOS', vistaId);
      final chartConfigRows =
          await _readConfigByVista('MATRIZ_GRAFICOS_DINAMICOS', vistaId);

      if (!mounted) return;
      setState(() {
        filters = filterRows;
        charts = chartConfigRows;
        loadingConfig = false;
      });
      await _loadChartData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingConfig = false;
        error = 'No se pudo leer filtros/gráficos de la vista: $e';
      });
    }
  }

  String _selectColumns(String table, Map<String, dynamic> chart) {
    final columns = <String>{};
    final ejeX = _asMap(chart['eje_x']);
    final ejeY1 = _asMap(chart['eje_y_1']);
    final ejeY2 = _asMap(chart['eje_y_2']);

    for (final ref in [ejeX['campo'], ejeY1['campo'], ejeY2['campo']]) {
      final column = _fieldColumn(table, ref);
      if (column.isNotEmpty) columns.add(_quoteColumn(column));
    }

    for (final filter in filters) {
      final column = _fieldColumn(table, filter['campo']);
      if (column.isNotEmpty &&
          selectedFilters.containsKey(_text(filter['codigo_filtro']))) {
        columns.add(_quoteColumn(column));
      }
    }

    final extra = _asList(chart['campos_select']);
    for (final value in extra) {
      final column = _fieldColumn(table, value);
      if (column.isNotEmpty) columns.add(_quoteColumn(column));
    }

    return columns.isEmpty ? '*' : columns.join(',');
  }

  dynamic _applyFilter(
      dynamic query, String column, String operator, dynamic value) {
    switch (operator) {
      case 'gte':
      case '>=':
        return query.gte(column, value);
      case 'lte':
      case '<=':
        return query.lte(column, value);
      case 'gt':
      case '>':
        return query.gt(column, value);
      case 'lt':
      case '<':
        return query.lt(column, value);
      case 'neq':
      case '!=':
        return query.neq(column, value);
      case 'like':
        return query.like(column, '%$value%');
      default:
        return query.eq(column, value);
    }
  }

  Future<List<Map<String, dynamic>>> _queryChartRows(
      Map<String, dynamic> chart) async {
    final useRpc = _asBool(chart['usa_rpc']);
    final rpcName = _text(chart['nombre_rpc']);

    if (useRpc && rpcName.isNotEmpty) {
      final params = <String, dynamic>{};
      for (final filter in filters) {
        final code = _text(filter['codigo_filtro']);
        final param = _text(filter['parametro_rpc']);
        if (code.isEmpty || param.isEmpty || !selectedFilters.containsKey(code))
          continue;
        final value = selectedFilters[code];
        if (value == null || value.toString().trim().isEmpty) continue;
        params[param] = value;
      }
      final rows = await _supabase.rpc(rpcName, params: params);
      return List<Map<String, dynamic>>.from(rows);
    }

    final table = _text(chart['tabla_origen']);
    if (table.isEmpty) return const [];

    await _ensureReportFieldsForTable(table);

    dynamic query = _supabase.from(table).select(_selectColumns(table, chart));
    for (final filter in filters) {
      final code = _text(filter['codigo_filtro']);
      final column = _fieldColumn(table, filter['campo']);
      if (code.isEmpty || column.isEmpty || !selectedFilters.containsKey(code))
        continue;
      final value = selectedFilters[code];
      if (value == null || value.toString().trim().isEmpty) continue;
      query = _applyFilter(
          query,
          column,
          _text(filter['operador']).isEmpty ? 'eq' : _text(filter['operador']),
          value);
    }

    final orderColumn = _fieldColumn(table, _asMap(chart['eje_x'])['campo']);
    if (orderColumn.isNotEmpty) {
      query = query.order(_quoteColumn(orderColumn), ascending: true);
    }

    // Windows/reportes: no limitar a 500. Se pagina en bloques para traer todos
    // los registros que cumplan los filtros configurados para la vista.
    const pageSize = 1000;
    var from = 0;
    final allRows = <Map<String, dynamic>>[];

    while (true) {
      final page = await query.range(from, from + pageSize - 1);
      final pageRows = List<Map<String, dynamic>>.from(page);
      allRows.addAll(pageRows);
      if (pageRows.length < pageSize) break;
      from += pageSize;
    }

    return allRows;
  }

  Future<void> _loadChartData() async {
    if (charts.isEmpty) return;
    setState(() {
      loadingData = true;
      error = null;
    });

    final output = <String, List<Map<String, dynamic>>>{};
    try {
      for (final chart in charts) {
        final code = _text(chart['codigo_grafico']).isNotEmpty
            ? _text(chart['codigo_grafico'])
            : _text(chart['id']);
        output[code] = await _queryChartRows(chart);
      }
      if (!mounted) return;
      setState(() {
        chartRows
          ..clear()
          ..addAll(output);
        loadingData = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingData = false;
        error = 'No se pudieron cargar los datos filtrados: $e';
      });
    }
  }

  Widget _buildFilter(Map<String, dynamic> filter) {
    final code = _text(filter['codigo_filtro']);
    final label = _text(filter['nombre_filtro']).isEmpty
        ? code
        : _text(filter['nombre_filtro']);
    final design = _text(filter['disenio']).toLowerCase();
    final values = _asList(filter['valores_estaticos']);

    if (design == 'date' || design == 'fecha') {
      return SizedBox(
        width: 210,
        child: TextFormField(
          initialValue: selectedFilters[code]?.toString() ?? '',
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          readOnly: true,
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
              initialDate: DateTime.now(),
            );
            if (picked == null) return;
            setState(() => selectedFilters[code] =
                picked.toIso8601String().substring(0, 10));
          },
        ),
      );
    }

    if (values.isNotEmpty ||
        design == 'dropdown' ||
        design == 'lista_desplegable') {
      return SizedBox(
        width: 230,
        child: DropdownButtonFormField<String>(
          value: selectedFilters[code]?.toString().isEmpty == false
              ? selectedFilters[code]?.toString()
              : null,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          items: values
              .map((e) => DropdownMenuItem<String>(
                  value: e.toString(), child: Text(e.toString())))
              .toList(),
          onChanged: (value) => setState(() => selectedFilters[code] = value),
        ),
      );
    }

    return SizedBox(
      width: 230,
      child: TextFormField(
        initialValue: selectedFilters[code]?.toString() ?? '',
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        onChanged: (value) => selectedFilters[code] = value,
      ),
    );
  }

  Widget _filtersPanel() {
    if (filters.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final filter in filters) _buildFilter(filter),
            FilledButton.icon(
              onPressed: loadingData ? null : _loadChartData,
              icon: const Icon(Icons.filter_alt),
              label: const Text('Aplicar filtros'),
            ),
            TextButton.icon(
              onPressed: loadingData
                  ? null
                  : () {
                      setState(selectedFilters.clear);
                      _loadChartData();
                    },
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Limpiar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewsRail() {
    if (loadingViews) return const Center(child: CircularProgressIndicator());
    if (reportModules.isEmpty) {
      return const Center(
          child: Text('No hay módulos de reportes configurados.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 18),
      itemCount: reportModules.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
            child: Text(
              'Módulos de reportes',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          );
        }

        final module = reportModules[index - 1];
        final moduleId = _text(module['id']);
        final moduleName = _text(module['nombre']).isEmpty
            ? moduleId
            : _text(module['nombre']);
        final moduleViews = _viewsForModule(module);
        final selectedModuleId = _text(selectedModule?['id']);
        final initiallyExpanded = selectedModuleId == moduleId;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            key: PageStorageKey<String>('report_module_$moduleId'),
            initiallyExpanded: initiallyExpanded,
            leading: const Icon(Icons.folder_copy_outlined),
            title:
                Text(moduleName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${moduleViews.length} vistas', maxLines: 1),
            onExpansionChanged: (expanded) {
              if (expanded && selectedModuleId != moduleId) {
                _selectModule(module);
              }
            },
            children: moduleViews.isEmpty
                ? const [
                    ListTile(
                      dense: true,
                      title: Text('Sin vistas activas o permitidas'),
                    ),
                  ]
                : moduleViews.map((view) {
                    final selected =
                        _text(selectedView?['id']) == _text(view['id']);
                    return ListTile(
                      dense: true,
                      leading: Icon(selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                      title: Text(
                        _text(view['nombre_vista']).isEmpty
                            ? _text(view['id'])
                            : _text(view['nombre_vista']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: selected,
                      selectedTileColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withOpacity(.55),
                      onTap: () async {
                        if (selectedModuleId != moduleId) {
                          await _selectModule(module);
                        }
                        await _selectView(view);
                      },
                    );
                  }).toList(),
          ),
        );
      },
    );
  }

  dynamic _rowValue(Map<String, dynamic> row, String column) {
    final wanted = _normKey(column);
    for (final entry in row.entries) {
      if (_normKey(entry.key) == wanted) return entry.value;
    }
    return null;
  }

  List<_ChartPoint> _pointsFor(
      Map<String, dynamic> chart, List<Map<String, dynamic>> rows) {
    final table = _text(chart['tabla_origen']);
    final ejeX = _asMap(chart['eje_x']);
    final ejeY1 = _asMap(chart['eje_y_1']);
    final xField = _fieldColumn(table, ejeX['campo']);
    final yField = _fieldColumn(table, ejeY1['campo']);
    if (xField.isEmpty || yField.isEmpty) return const [];

    final grouped = <String, List<double>>{};
    for (final row in rows) {
      final x = _text(_rowValue(row, xField));
      if (x.isEmpty) continue;
      grouped
          .putIfAbsent(x, () => <double>[])
          .add(_asDouble(_rowValue(row, yField)));
    }

    final aggregation = _text(ejeY1['agregacion']).toLowerCase();
    final points = <_ChartPoint>[];
    grouped.forEach((key, values) {
      if (values.isEmpty) return;
      double y;
      switch (aggregation) {
        case 'suma':
        case 'sum':
          y = values.fold<double>(0, (a, b) => a + b);
          break;
        case 'max':
        case 'maximo':
        case 'máximo':
          y = values.reduce(math.max);
          break;
        case 'min':
        case 'minimo':
        case 'mínimo':
          y = values.reduce(math.min);
          break;
        case 'contar':
        case 'count':
          y = values.length.toDouble();
          break;
        default:
          y = values.fold<double>(0, (a, b) => a + b) / values.length;
      }
      points.add(_ChartPoint(key, y));
    });
    return points;
  }

  Widget _chartCard(Map<String, dynamic> chart) {
    final code = _text(chart['codigo_grafico']).isNotEmpty
        ? _text(chart['codigo_grafico'])
        : _text(chart['id']);
    final rows = chartRows[code] ?? const <Map<String, dynamic>>[];
    final type = _text(chart['tipo_grafico']).toLowerCase();
    final points = _pointsFor(chart, rows);

    Widget chartBody;
    if (rows.isEmpty) {
      chartBody =
          const Center(child: Text('Sin datos para los filtros actuales.'));
    } else if (type == 'tabla') {
      chartBody = _SimpleTable(rows: rows);
    } else if (type == 'indicador' || type == 'kpi' || type == 'tarjeta') {
      final value = points.isEmpty
          ? 0
          : points.map((e) => e.y).fold<double>(0, (a, b) => a + b);
      chartBody = Center(
        child: Text(
          value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2),
          style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w900),
        ),
      );
    } else {
      chartBody = _SimpleChart(points: points, chartType: type);
    }

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _chartTitle(chart),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(height: 280, child: chartBody),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    if (loadingConfig) return const Center(child: CircularProgressIndicator());

    if (selectedView == null) {
      return Center(
        child: Opacity(
          opacity: .92,
          child: Image.asset(
            'assets/images/logo_bienvenida.png',
            width: 150,
            cacheWidth: 450,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      );
    }

    return Column(
      children: [
        _filtersPanel(),
        if (loadingData) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: charts.isEmpty
              ? const Center(
                  child: Text('Esta vista aún no tiene gráficos configurados.'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: charts.length,
                  itemBuilder: (_, index) => _chartCard(charts[index]),
                ),
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(covariant ReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialModuleId != widget.initialModuleId ||
        oldWidget.initialViewId != widget.initialViewId) {
      if (reportModules.isEmpty) return;
      final module = reportModules
          .where((m) => _text(m['id']) == _text(widget.initialModuleId))
          .toList();
      if (module.isNotEmpty) {
        _selectModule(module.first, preferredViewId: widget.initialViewId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (!widget.showRail) {
          return _content();
        }
        if (!wide) {
          final railHeight =
              math.min(360.0, math.max(230.0, constraints.maxHeight * .38));
          return Column(
            children: [
              SizedBox(height: railHeight, child: _viewsRail()),
              const Divider(height: 1),
              Expanded(child: _content()),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 320, child: _viewsRail()),
            const VerticalDivider(width: 1),
            Expanded(child: _content()),
          ],
        );
      },
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Reportes')),
      body: body,
    );
  }
}

class _ChartPoint {
  final String x;
  final double y;

  const _ChartPoint(this.x, this.y);
}

class _SimpleChart extends StatelessWidget {
  final List<_ChartPoint> points;
  final String chartType;

  const _SimpleChart({required this.points, required this.chartType});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty)
      return const Center(child: Text('No hay puntos para graficar.'));
    return CustomPaint(
      painter: _SimpleChartPainter(points: points, chartType: chartType),
      child: const SizedBox.expand(),
    );
  }
}

class _SimpleChartPainter extends CustomPainter {
  final List<_ChartPoint> points;
  final String chartType;

  _SimpleChartPainter({required this.points, required this.chartType});

  String _normalizedType() {
    final t = chartType.toLowerCase().trim();
    if (t.contains('barra_horizontal') ||
        t.contains('horizontal_bar') ||
        t.contains('bar_horizontal')) return 'barra_horizontal';
    if (t.contains('barra') || t == 'bar' || t == 'column' || t == 'columna')
      return 'barra';
    if (t.contains('circular') ||
        t.contains('circulo') ||
        t == 'pie' ||
        t == 'pastel' ||
        t == 'torta') return 'pie';
    if (t == 'dona' || t == 'donut' || t.contains('anillo')) return 'dona';
    if (t.contains('dispersion') || t == 'scatter' || t == 'xy')
      return 'dispersion';
    if (t.contains('area')) return 'area';
    if (t.contains('escalon') || t == 'step' || t == 'stepline') return 'step';
    if (t.contains('lollipop') || t.contains('palito')) return 'lollipop';
    if (t.contains('linea') ||
        t.contains('línea') ||
        t == 'line' ||
        t == 'spline' ||
        t == 'curva') return 'linea';
    return t.isEmpty ? 'linea' : t;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = 46.0;
    const right = 18.0;
    const top = 18.0;
    const bottom = 46.0;
    final plot =
        Rect.fromLTRB(left, top, size.width - right, size.height - bottom);

    final axisPaint = Paint()
      ..strokeWidth = 1
      ..color = const Color(0xFF777777);
    final gridPaint = Paint()
      ..strokeWidth = .6
      ..color = const Color(0xFFE2E2E2);
    final dataPaint = Paint()
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF1565C0);
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF1565C0).withOpacity(.72);
    final type = _normalizedType();

    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axisPaint);
    canvas.drawLine(plot.bottomLeft, plot.topLeft, axisPaint);

    final maxY = points.map((e) => e.y).fold<double>(0, math.max);
    final safeMax = maxY <= 0 ? 1.0 : maxY;

    for (var i = 1; i <= 4; i++) {
      final y = plot.bottom - (plot.height * i / 4);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _drawText(canvas, (safeMax * i / 4).toStringAsFixed(1), Offset(4, y - 7),
          10, const Color(0xFF555555));
    }

    if (type == 'pie' || type == 'dona') {
      final total =
          points.map((e) => e.y.abs()).fold<double>(0, (a, b) => a + b);
      if (total <= 0) return;
      final radius = math.min(plot.width, plot.height) / 2.4;
      final center = plot.center;
      var start = -math.pi / 2;
      final palette = <Color>[
        const Color(0xFF1565C0),
        const Color(0xFF2E7D32),
        const Color(0xFFE65100),
        const Color(0xFF6A1B9A),
        const Color(0xFF00838F),
        const Color(0xFFC62828),
        const Color(0xFF455A64),
        const Color(0xFF827717),
      ];
      for (var i = 0; i < points.length; i++) {
        final sweep = (points[i].y.abs() / total) * math.pi * 2;
        final paint = Paint()
          ..style = PaintingStyle.fill
          ..color = palette[i % palette.length].withOpacity(.82);
        canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start,
            sweep, true, paint);
        start += sweep;
      }
      if (type == 'dona') {
        canvas.drawCircle(
            center,
            radius * .48,
            Paint()
              ..style = PaintingStyle.fill
              ..color = const Color(0xFFF8FAF4));
      }
      return;
    }

    if (type == 'barra_horizontal') {
      final gap = plot.height / points.length;
      final barHeight = math.max(7.0, gap * .58);
      for (var i = 0; i < points.length; i++) {
        final p = points[i];
        final y = plot.top + gap * i + gap / 2;
        final x = plot.left + (p.y / safeMax) * plot.width;
        canvas.drawRect(
            Rect.fromLTRB(plot.left, y - barHeight / 2, x, y + barHeight / 2),
            fillPaint);
        if (i % math.max(1, points.length ~/ 7) == 0) {
          _drawText(canvas, p.x, Offset(4, y - 7), 9, const Color(0xFF333333));
        }
      }
      return;
    }

    if (type == 'barra') {
      final gap = plot.width / points.length;
      final barWidth = math.max(8.0, gap * .58);
      for (var i = 0; i < points.length; i++) {
        final p = points[i];
        final x = plot.left + gap * i + gap / 2;
        final y = plot.bottom - (p.y / safeMax) * plot.height;
        canvas.drawRect(
            Rect.fromLTRB(x - barWidth / 2, y, x + barWidth / 2, plot.bottom),
            fillPaint);
        if (i % math.max(1, points.length ~/ 6) == 0) {
          _drawRotatedText(canvas, p.x, Offset(x - 4, plot.bottom + 8), 10,
              const Color(0xFF333333));
        }
      }
      return;
    }

    final path = Path();
    final areaPath = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? plot.center.dx
          : plot.left + (plot.width * i / (points.length - 1));
      final y = plot.bottom - (points[i].y / safeMax) * plot.height;
      if (i == 0) {
        path.moveTo(x, y);
        areaPath.moveTo(x, plot.bottom);
        areaPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        areaPath.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y),
          type == 'dispersion' || type == 'lollipop' ? 4.5 : 3, fillPaint);
      if (type == 'lollipop') {
        canvas.drawLine(Offset(x, plot.bottom), Offset(x, y), dataPaint);
      }
      if (i % math.max(1, points.length ~/ 6) == 0) {
        _drawRotatedText(canvas, points[i].x, Offset(x - 4, plot.bottom + 8),
            10, const Color(0xFF333333));
      }
    }
    if (type == 'area') {
      areaPath.lineTo(plot.right, plot.bottom);
      areaPath.close();
      canvas.drawPath(
          areaPath,
          Paint()
            ..style = PaintingStyle.fill
            ..color = const Color(0xFF1565C0).withOpacity(.18));
    }
    if (type == 'step') {
      final stepPath = Path();
      for (var i = 0; i < points.length; i++) {
        final x = points.length == 1
            ? plot.center.dx
            : plot.left + (plot.width * i / (points.length - 1));
        final y = plot.bottom - (points[i].y / safeMax) * plot.height;
        if (i == 0) {
          stepPath.moveTo(x, y);
        } else {
          final previousX = points.length == 1
              ? plot.center.dx
              : plot.left + (plot.width * (i - 1) / (points.length - 1));
          stepPath.lineTo(
              x,
              stepPath.getBounds().isEmpty
                  ? y
                  : plot.bottom - (points[i - 1].y / safeMax) * plot.height);
          stepPath.lineTo(x, y);
        }
      }
      canvas.drawPath(stepPath, dataPaint);
    } else if (type != 'dispersion' && type != 'lollipop') {
      canvas.drawPath(path, dataPaint);
    }
  }

  void _drawText(
      Canvas canvas, String text, Offset offset, double size, Color color) {
    final tp = TextPainter(
      text:
          TextSpan(text: text, style: TextStyle(fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 44);
    tp.paint(canvas, offset);
  }

  void _drawRotatedText(
      Canvas canvas, String text, Offset offset, double size, Color color) {
    final short = text.length > 12 ? '${text.substring(0, 12)}…' : text;
    final tp = TextPainter(
      text:
          TextSpan(text: short, style: TextStyle(fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 80);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.rotate(-math.pi / 5);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SimpleChartPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.chartType != chartType;
  }
}

class _SimpleTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;

  const _SimpleTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows.first.keys.toList();
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columns: columns.map((c) => DataColumn(label: Text(c))).toList(),
            rows: rows.take(100).map((row) {
              return DataRow(
                cells: columns
                    .map((c) => DataCell(Text(row[c]?.toString() ?? '')))
                    .toList(),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
