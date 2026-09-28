import 'dart:convert';

import 'package:flutter/material.dart' hide ScaffoldMessenger;

import '../../core/widgets/zumac_scaffold_messenger.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/platform/app_platform.dart';
import '../../core/services/local_db.dart';
import '../../core/services/local_session.dart';
import '../../core/services/soft_delete.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/tareo_draft_policy.dart';
import 'form_runner_page.dart';

Future<void> _showAppGtAlert(
  BuildContext context,
  String message, {
  String title = 'Alerta',
  IconData icon = Icons.warning_amber_rounded,
  bool playSound = false,
}) async {
  if (playSound) {
    await SystemSound.play(SystemSoundType.alert);
  }
  if (!context.mounted) return;
  final theme = Theme.of(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3E6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF9CB693)),
            ),
            child: Icon(icon, color: const Color(0xFF31552F)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF31552F),
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Aceptar'),
        ),
      ],
    ),
  );
}

Future<Set<String>?> _showMissingAttendanceAlert(
    BuildContext context, List<Map<String, String>> missing) async {
  await SystemSound.play(SystemSoundType.alert);
  if (!context.mounted) return null;
  final theme = Theme.of(context);
  final removedDnis = <String>{};
  final result = await showDialog<Set<String>>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final visible = missing
            .where((worker) => !removedDnis.contains(worker['dni']))
            .toList();
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3E6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF9CB693)),
                ),
                child: const Icon(Icons.person_off_rounded,
                    color: Color(0xFF31552F)),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text('Hay personal sin asistencia',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800))),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estas personas no tienen asistencia registrada para la fecha del tareo. Quita de la lista a quienes no deban incluirse o continúa con las restantes.',
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: visible.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Center(
                              child: Text(
                                  'Quitaste a todo el personal sin asistencia.')),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final worker = visible[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title:
                                  Text(worker['label'] ?? worker['dni'] ?? ''),
                              trailing: IconButton(
                                tooltip: 'Quitar del tareo',
                                icon: const Icon(Icons.person_remove_alt_1,
                                    color: Color(0xFF8B2F28)),
                                onPressed: () => setDialogState(
                                    () => removedDnis.add(worker['dni'] ?? '')),
                              ),
                            );
                          },
                        ),
                ),
                if (removedDnis.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                      '${removedDnis.length} persona(s) se quitarán del tareo.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF8B2F28),
                          fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF31552F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(dialogContext)
                  .pop(Set<String>.from(removedDnis)),
              child: Text(removedDnis.isEmpty
                  ? 'Continuar de todas formas'
                  : 'Aplicar y continuar'),
            ),
          ],
        );
      },
    ),
  );
  return result;
}

DateTime _safeDatePickerInitialDate(
    DateTime value, DateTime minDate, DateTime maxDate) {
  final date = DateTime(value.year, value.month, value.day);
  if (date.isBefore(minDate)) return minDate;
  if (date.isAfter(maxDate)) return maxDate;
  return date;
}

const Color _zumacFormatBlue = Color(0xFF0F5265);

AppBar _zumacFormatAppBar({
  required Widget title,
  VoidCallback? onBack,
  List<Widget>? actions,
}) {
  return AppBar(
    toolbarHeight: 52,
    backgroundColor: _zumacFormatBlue,
    foregroundColor: Colors.white,
    elevation: 0,
    titleSpacing: 2,
    leading: onBack == null
        ? null
        : IconButton(
            tooltip: 'Volver',
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
    title: title,
    actions: actions,
  );
}

/// Respaldo determinista cuando la metadata de formatos especiales todavía no
/// terminó de descargarse. Evita que Asistencia o Tareo aparezcan como un
/// formulario genérico durante el arranque del APK.
Map<String, dynamic>? appGtSpecialFormatFallback(Map<String, dynamic> format) {
  final table = _specialNorm(format['tabla_destino']?.toString() ?? '');
  if (table == 'GT_ASISTENCIA_PERSONAL') {
    return <String, dynamic>{
      'tipo_pantalla': 'asistencia_personal',
      'activo': 1,
    };
  }
  if (table == 'GT_TAREO_PERSONAL') {
    return <String, dynamic>{
      'tipo_pantalla': 'tareo_personal',
      'activo': 1,
    };
  }
  return null;
}

class SpecialFormRouterPage extends StatelessWidget {
  final String moduleId;
  final Map<String, dynamic> format;
  final Map<String, dynamic> special;
  final Map<String, dynamic>? initialPayload;
  final String? editIdLocal;
  final VoidCallback? onLocalChanged;
  final VoidCallback? onSavedAndExit;

  const SpecialFormRouterPage({
    super.key,
    required this.moduleId,
    required this.format,
    required this.special,
    this.initialPayload,
    this.editIdLocal,
    this.onLocalChanged,
    this.onSavedAndExit,
  });

  @override
  Widget build(BuildContext context) {
    final tipo = special['tipo_pantalla']?.toString() ?? '';
    if (tipo == 'fenologia_plantas') {
      return PlagasEnfermedadesSpecialPage(
        moduleId: moduleId,
        format: format,
        initialPayload: initialPayload,
        editIdLocal: editIdLocal,
        onLocalChanged: onLocalChanged,
        onSavedAndExit: onSavedAndExit,
      );
    }
    if (tipo == 'conteo_fruta_plantas') {
      return PlagasEnfermedadesSpecialPage(
        moduleId: moduleId,
        format: format,
        initialPayload: initialPayload,
        editIdLocal: editIdLocal,
        isConteoFruta: true,
        onLocalChanged: onLocalChanged,
        onSavedAndExit: onSavedAndExit,
      );
    }
    if (tipo == 'asistencia_personal' ||
        tipo == 'asistencia_qr' ||
        tipo == 'asistencia_movilidad') {
      if (!isMobileCaptureRuntime) {
        return const _AttendanceCaptureUnavailablePage();
      }
      return AsistenciaPersonalSpecialPage(
        moduleId: moduleId,
        format: format,
        initialPayload: initialPayload,
        editIdLocal: editIdLocal,
        onLocalChanged: onLocalChanged,
        onSavedAndExit: onSavedAndExit,
      );
    }
    if (tipo == 'tareo_personal' ||
        tipo == 'tareo_qr' ||
        (format['tabla_destino']?.toString() ?? '') == 'GT-TAREO_PERSONAL') {
      if (initialPayload == null && editIdLocal == null) {
        return TareoPersonalDayPage(
          moduleId: moduleId,
          format: format,
          onLocalChanged: onLocalChanged,
          onBack: onSavedAndExit,
        );
      }
      return TareoPersonalSpecialPage(
        moduleId: moduleId,
        format: format,
        initialPayload: initialPayload,
        editIdLocal: editIdLocal,
        onLocalChanged: onLocalChanged,
        onSavedAndExit: onSavedAndExit,
      );
    }
    if (tipo == 'control_maquinaria') {
      return MachinerySpecialPage(
        moduleId: moduleId,
        format: format,
        initialPayload: initialPayload,
        editIdLocal: editIdLocal,
        onLocalChanged: onLocalChanged,
        onSavedAndExit: onSavedAndExit,
      );
    }
    return FormRunnerPage(
        moduleId: moduleId,
        format: format,
        initialPayload: initialPayload,
        editIdLocal: editIdLocal);
  }
}

class _AttendanceCaptureUnavailablePage extends StatelessWidget {
  const _AttendanceCaptureUnavailablePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _zumacFormatAppBar(
        title: const Text('Asistencia de Personal'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.phonelink_lock_outlined,
                        size: 54, color: Color(0xFF31552F)),
                    SizedBox(height: 16),
                    Text(
                      'Marcación disponible solo en el APK',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Desde la versión web puedes consultar la tabla de '
                      'asistencias, pero los ingresos y salidas se registran '
                      'únicamente desde la aplicación móvil.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _specialNorm(String v) {
  var s = v.trim().toUpperCase();
  const map = {
    'Á': 'A',
    'É': 'E',
    'Í': 'I',
    'Ó': 'O',
    'Ú': 'U',
    'Ü': 'U',
    'Ñ': 'N'
  };
  map.forEach((k, value) => s = s.replaceAll(k, value));
  return s
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

bool _specialAsBool(dynamic value, {bool defaultValue = false}) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  if (text.isEmpty || text == 'null') return defaultValue;
  return text == '1' ||
      text == 'true' ||
      text == 'si' ||
      text == 'sí' ||
      text == 'yes' ||
      text == 'x';
}

String _specialDateIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _specialTimeHm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _SpecialMatrixHeader {
  final LocalDb local;
  final String tableName;
  final Set<String>? onlyNormalizedFields;
  final Map<String, TextEditingController> controllers = {};
  List<Map<String, dynamic>> fields = [];
  bool loading = true;

  _SpecialMatrixHeader(this.local, this.tableName, {List<String>? onlyFields})
      : onlyNormalizedFields =
            onlyFields == null ? null : onlyFields.map(_specialNorm).toSet();

  Future<void> load({Map<String, dynamic>? initialPayload}) async {
    final rows = await local.where(
      'local_form_fields',
      'tabla_destino = ?',
      [tableName],
      orderBy:
          'coalesce(grid_fila, orden, 999), coalesce(grid_columna, 1), coalesce(orden, 999)',
    );
    fields = rows
        .where((row) {
          final campo = row['campo']?.toString() ?? '';
          if (campo.trim().isEmpty) return false;
          if (!_specialAsBool(row['activo'], defaultValue: true)) return false;
          if (!_specialAsBool(row['visible'], defaultValue: true)) return false;
          if (onlyNormalizedFields != null &&
              !onlyNormalizedFields!.contains(_specialNorm(campo)))
            return false;
          final tipo = row['tipo']?.toString().trim().toLowerCase() ?? '';
          final ui = row['tipo_ui']?.toString().trim().toLowerCase() ?? '';
          return tipo != 'hidden' &&
              tipo != 'hidden_id' &&
              ui != 'hidden' &&
              ui != 'hidden_id';
        })
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    for (final c in controllers.values) {
      c.dispose();
    }
    controllers.clear();
    for (final field in fields) {
      final campo = field['campo']?.toString() ?? '';
      controllers[campo] = TextEditingController(
          text: _initialValue(
              field, initialPayload ?? const <String, dynamic>{}));
    }
    await _recalculateFormulaControllers();
    loading = false;
  }

  Future<void> _recalculateFormulaControllers() async {
    for (final field in fields) {
      final campo = field['campo']?.toString() ?? '';
      if (campo.isEmpty) continue;
      final tipo = field['tipo']?.toString().trim().toLowerCase() ?? '';
      final ui = field['tipo_ui']?.toString().trim().toLowerCase() ?? '';
      final formula = field['formula_funcion']?.toString().trim() ?? '';
      if (formula.isEmpty || (ui != 'formula' && tipo != 'formula')) continue;
      final value = await _evaluateSimpleFormula(formula);
      if (value != null) controllers[campo]?.text = value;
    }
  }

  Future<String?> _evaluateSimpleFormula(String formula) async {
    final text = formula.trim();
    final upper = text.toUpperCase();
    final now = DateTime.now();
    if (upper.contains('FECHA_ACTUAL') ||
        upper.contains('HOY()') ||
        upper == 'HOY') return _specialDateIso(now);
    if (upper.contains('HORA_ACTUAL')) return _specialTimeHm(now);

    final match = RegExp(r'^(?:BUSCAR|LOOKUP|LOOKUPR|LOOKUPP)\s*\((.*)\)\s*$',
            caseSensitive: false)
        .firstMatch(text);
    if (match == null) return null;
    final args = _splitFormulaArgs(match.group(1) ?? '');
    if (args.length < 4) return null;
    final sourceTable = args[0].trim();
    final sourceLookupField = args[1].trim();
    final localRef = _unwrapRef(args[2].trim());
    final sourceReturnField = args[3].trim();
    final localValue = valueByCandidates([localRef]);
    if (sourceTable.isEmpty ||
        sourceLookupField.isEmpty ||
        sourceReturnField.isEmpty ||
        localValue.isEmpty) return '';

    final rows = await local
        .where('local_matrix_rows', 'source_table = ?', [sourceTable]);
    final wantedLookup = _specialNorm(sourceLookupField);
    final wantedReturn = _specialNorm(sourceReturnField);
    final targetValue = localValue.trim().toLowerCase();
    for (final row in rows) {
      try {
        final decoded = jsonDecode(row['payload_json']?.toString() ?? '{}');
        if (decoded is! Map) continue;
        final payload = Map<String, dynamic>.from(decoded);
        if (isSoftDeletedAppgtRow(payload)) continue;
        dynamic lookup;
        dynamic ret;
        for (final e in payload.entries) {
          final keyNorm = _specialNorm(e.key.toString());
          if (keyNorm == wantedLookup) lookup = e.value;
          if (keyNorm == wantedReturn) ret = e.value;
        }
        if ((lookup?.toString().trim().toLowerCase() ?? '') == targetValue)
          return ret?.toString().trim() ?? '';
      } catch (_) {}
    }
    return '';
  }

  List<String> _splitFormulaArgs(String raw) {
    final out = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '(') depth++;
      if (ch == ')') depth = depth > 0 ? depth - 1 : 0;
      if ((ch == ';' || ch == ',') && depth == 0) {
        out.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    out.add(buffer.toString().trim());
    return out;
  }

  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    controllers.clear();
  }

  String _initialValue(
      Map<String, dynamic> field, Map<String, dynamic> payload) {
    final campo = field['campo']?.toString() ?? '';
    final wanted = _specialNorm(campo);
    for (final e in payload.entries) {
      if (_specialNorm(e.key) == wanted) return e.value?.toString() ?? '';
    }
    final def = field['valor_default']?.toString().trim() ?? '';
    if (def.isNotEmpty && def.toLowerCase() != 'null') return def;
    final formula =
        field['formula_funcion']?.toString().trim().toUpperCase() ?? '';
    final now = DateTime.now();
    if (formula.contains('FECHA_ACTUAL') ||
        formula.contains('HOY()') ||
        formula == 'HOY') return _specialDateIso(now);
    if (formula.contains('HORA_ACTUAL')) return _specialTimeHm(now);
    if (_specialNorm(campo) == 'FECHA') return _specialDateIso(now);
    return '';
  }

  Map<String, dynamic> payload() {
    final out = <String, dynamic>{};
    for (final field in fields) {
      final campo = field['campo']?.toString() ?? '';
      if (campo.isEmpty) continue;
      out[campo] = controllers[campo]?.text.trim() ?? '';
    }
    return out;
  }

  String valueByCandidates(List<String> candidates, {String fallback = ''}) {
    final wanted = candidates.map(_specialNorm).toSet();
    for (final entry in controllers.entries) {
      if (wanted.contains(_specialNorm(entry.key)))
        return entry.value.text.trim();
    }
    return fallback;
  }

  bool hasField(List<String> candidates) {
    final wanted = candidates.map(_specialNorm).toSet();
    return controllers.keys.any((key) => wanted.contains(_specialNorm(key)));
  }

  List<Map<String, dynamic>> fieldsWhere(
          bool Function(Map<String, dynamic>) test) =>
      fields.where(test).toList();

  String _unwrapRef(String value) {
    final text = value.trim();
    if (text.startsWith('[') && text.endsWith(']') && text.length >= 2) {
      return text.substring(1, text.length - 1).trim();
    }
    return text;
  }

  Map<String, dynamic>? _fieldByIdentifier(String identifier) {
    final wanted = _specialNorm(_unwrapRef(identifier));
    if (wanted.isEmpty) return null;
    Map<String, dynamic>? fallback;
    for (final field in fields) {
      final candidates = [field['id'], field['campo'], field['etiqueta']];
      if (candidates.any((v) => _specialNorm(v?.toString() ?? '') == wanted))
        return field;
    }
    // Respaldo global: permite que GT-CABECERA_TAREO_PERSONAL use id_campo_dropdown
    // apuntando a un campo/catálogo definido en otra tabla de la matriz.
    // Es clave para que los dropdowns especiales se comporten igual que FormRunnerPage.
    // La búsqueda se hace en memoria local, no en Supabase.
    return fallback;
  }

  Future<Map<String, dynamic>?> _globalFieldByIdentifier(
      String identifier) async {
    final wanted = _specialNorm(_unwrapRef(identifier));
    if (wanted.isEmpty) return null;
    final all = await local.getAll('local_form_fields');
    Map<String, dynamic>? fallback;
    for (final row in all) {
      final field = Map<String, dynamic>.from(row);
      final candidates = [field['id'], field['campo'], field['etiqueta']];
      if (!candidates.any((v) => _specialNorm(v?.toString() ?? '') == wanted))
        continue;
      if (_specialNorm(field['tabla_destino']?.toString() ?? '') ==
          _specialNorm(tableName)) return field;
      fallback ??= field;
    }
    return fallback;
  }

  Future<String> _resolveDropdownKey(String raw) async {
    final clean = _unwrapRef(raw);
    if (clean.isEmpty) return '';
    if (clean.contains('.') || clean.contains(':')) return clean;
    final localField = _fieldByIdentifier(clean);
    final field = localField ?? await _globalFieldByIdentifier(clean);
    if (field == null) return raw.trim();
    final nested = field['id_campo_dropdown']?.toString().trim() ?? '';
    if (nested.isNotEmpty && _unwrapRef(nested) != clean) {
      final resolvedNested = await _resolveDropdownKey(nested);
      if (resolvedNested.isNotEmpty) return resolvedNested;
    }
    final sourceTable = field['tabla_destino']?.toString().trim() ?? '';
    final sourceColumn = field['campo']?.toString().trim() ?? '';
    if (sourceTable.isNotEmpty && sourceColumn.isNotEmpty)
      return '$sourceTable.$sourceColumn';
    return raw.trim();
  }

  Future<List<String>> _dynamicOptions(String raw) async {
    final key = await _resolveDropdownKey(raw);
    if (key.isEmpty) return const [];
    final values = <String>{};
    for (final catalogKey in <String>{key, raw.trim(), _unwrapRef(raw)}) {
      if (catalogKey.trim().isEmpty) continue;
      final catalogRows = await local.where(
          'local_catalog_values', 'catalog_key = ?', [catalogKey],
          orderBy: 'value');
      for (final row in catalogRows) {
        final value = row['value']?.toString().trim() ?? '';
        if (value.isNotEmpty) values.add(value);
      }
    }
    final source = key.replaceAll('[', '').replaceAll(']', '').trim();
    if (source.isNotEmpty) {
      final parts = source
          .split(RegExp(r'[.|:]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) {
        final sourceTable = parts.first;
        final sourceField = parts.length > 1 ? parts.last : '';
        final rows = await local
            .where('local_matrix_rows', 'source_table = ?', [sourceTable]);
        for (final row in rows) {
          try {
            final payload = jsonDecode(row['payload_json']?.toString() ?? '{}');
            if (payload is! Map) continue;
            final mapped = Map<String, dynamic>.from(payload);
            if (isSoftDeletedAppgtRow(mapped)) continue;
            if (sourceField.isEmpty) {
              for (final v in mapped.values) {
                final value = v?.toString().trim() ?? '';
                if (value.isNotEmpty) values.add(value);
              }
            } else {
              final target = _specialNorm(sourceField);
              for (final e in mapped.entries) {
                if (_specialNorm(e.key.toString()) == target) {
                  final value = e.value?.toString().trim() ?? '';
                  if (value.isNotEmpty) values.add(value);
                }
              }
            }
          } catch (_) {}
        }
      }
    }
    final list = values.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<String>? _literalOptions(Map<String, dynamic> field) {
    final raw = field['id_campo_dropdown']?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final isLiteral = raw.startsWith('[') &&
        raw.endsWith(']') &&
        !raw.contains('.') &&
        !raw.contains(':');
    if (!isLiteral) return null;
    final clean = raw.substring(1, raw.length - 1);
    return clean
        .split(RegExp(r'[;,|]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  String _label(Map<String, dynamic> field) {
    final campo = field['campo']?.toString() ?? '';
    final etiqueta = field['etiqueta']?.toString().trim() ?? '';
    final requerido = _specialAsBool(field['requerido']);
    final label = etiqueta.isNotEmpty && etiqueta.toLowerCase() != 'null'
        ? etiqueta
        : campo;
    return requerido ? '$label *' : label;
  }

  Future<void> _pickSearchable(BuildContext context, Map<String, dynamic> field,
      List<String> options, void Function(void Function()) setState) async {
    final campo = field['campo']?.toString() ?? '';
    final searchCtrl = TextEditingController();
    var filtered = List<String>.from(options);
    try {
      final selected = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            backgroundColor: const Color(0xFFF4F8F7),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Text(_label(field).replaceAll(' *', '')),
            content: SizedBox(
              width: 430,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: searchCtrl,
                  autofocus: false,
                  decoration: const InputDecoration(
                      labelText: 'Buscar',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true),
                  onChanged: (value) {
                    final q = value.trim().toLowerCase();
                    setLocalState(() => filtered = q.isEmpty
                        ? List<String>.from(options)
                        : options
                            .where((e) => e.toLowerCase().contains(q))
                            .toList());
                  },
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: filtered.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No hay coincidencias.'))
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => ListTile(
                              dense: true,
                              title: Text(filtered[i]),
                              onTap: () =>
                                  Navigator.pop(dialogContext, filtered[i])),
                        ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar')),
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, ''),
                  child: const Text('Limpiar')),
            ],
          ),
        ),
      );
      if (selected != null) {
        setState(() => controllers[campo]?.text = selected);
        await _recalculateFormulaControllers();
        setState(() {});
      }
    } finally {
      searchCtrl.dispose();
    }
  }

  Widget buildField(BuildContext context, Map<String, dynamic> field,
      void Function(void Function()) setState,
      {DateTime? firstDate, DateTime? lastDate}) {
    final campo = field['campo']?.toString() ?? '';
    final ctrl = controllers[campo];
    if (ctrl == null) return const SizedBox.shrink();
    final tipo = field['tipo']?.toString().trim().toLowerCase() ?? '';
    final ui = field['tipo_ui']?.toString().trim().toLowerCase() ?? '';
    final editable = _specialAsBool(field['editable'], defaultValue: true);
    final label = _label(field);
    final rawDropdown = field['id_campo_dropdown']?.toString().trim() ?? '';
    final literal = (ui == 'dropdown' || ui == 'multiselect')
        ? _literalOptions(field)
        : null;

    if ((ui == 'dropdown' || ui == 'multiselect') && literal != null) {
      return InkWell(
        onTap: editable
            ? () => _pickSearchable(context, field, literal, setState)
            : null,
        child: InputDecorator(
          decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              suffixIcon: const Icon(Icons.search)),
          child: Text(
              ctrl.text.trim().isEmpty
                  ? 'Seleccione o busque...'
                  : ctrl.text.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      );
    }

    if ((ui == 'dropdown' || ui == 'multiselect') && rawDropdown.isNotEmpty) {
      return FutureBuilder<List<String>>(
        future: _dynamicOptions(rawDropdown),
        builder: (context, snap) {
          final opts = snap.data ?? const <String>[];
          return InkWell(
            onTap: editable && opts.isNotEmpty
                ? () => _pickSearchable(context, field, opts, setState)
                : null,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                suffixIcon: const Icon(Icons.search),
                helperText: opts.isEmpty
                    ? 'Sin valores locales para $rawDropdown. Actualiza datos con internet.'
                    : null,
              ),
              child: Text(
                  ctrl.text.trim().isEmpty
                      ? 'Seleccione o busque...'
                      : ctrl.text.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          );
        },
      );
    }

    if (ui == 'date' || tipo == 'date') {
      return TextField(
        controller: ctrl,
        readOnly: true,
        decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today)),
        onTap: editable
            ? () async {
                final today = DateTime.now();
                final minDate = firstDate ?? DateTime(today.year - 3);
                final maxDate = lastDate ?? DateTime(today.year + 3);
                final current = _safeDatePickerInitialDate(
                    DateTime.tryParse(ctrl.text.trim()) ?? today,
                    minDate,
                    maxDate);
                final picked = await showDatePicker(
                    context: context,
                    initialDate: current,
                    firstDate: minDate,
                    lastDate: maxDate);
                if (picked != null) {
                  setState(() => ctrl.text = _specialDateIso(picked));
                  await _recalculateFormulaControllers();
                  setState(() {});
                }
              }
            : null,
      );
    }

    if (ui == 'time' || tipo == 'time') {
      return TextField(
        controller: ctrl,
        readOnly: true,
        decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.access_time)),
        onTap: editable
            ? () async {
                final parts = ctrl.text.trim().split(':');
                final initial = parts.length >= 2
                    ? TimeOfDay(
                        hour: int.tryParse(parts[0]) ?? TimeOfDay.now().hour,
                        minute:
                            int.tryParse(parts[1]) ?? TimeOfDay.now().minute)
                    : TimeOfDay.now();
                final picked = await showTimePicker(
                    context: context, initialTime: initial);
                if (picked != null) {
                  setState(() => ctrl.text =
                      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
                  await _recalculateFormulaControllers();
                  setState(() {});
                }
              }
            : null,
      );
    }

    final readOnly = !editable || ui == 'formula' || tipo == 'formula';
    return TextField(
      controller: ctrl,
      readOnly: readOnly,
      keyboardType: (ui == 'number' ||
              tipo == 'numeric' ||
              tipo == 'decimal' ||
              tipo == 'integer' ||
              tipo == 'int')
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: readOnly ? const Icon(Icons.lock_outline) : null),
      onChanged: readOnly
          ? null
          : (_) async {
              await _recalculateFormulaControllers();
              setState(() {});
            },
    );
  }

  int _gridNumber(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is num) return value.toInt();
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
    return int.tryParse(text) ?? fallback;
  }

  List<Widget> buildFields(
      BuildContext context, void Function(void Function()) setState,
      {bool Function(Map<String, dynamic>)? filter,
      DateTime? firstDate,
      DateTime? lastDate}) {
    final visibleFields =
        filter == null ? fields : fields.where(filter).toList();
    if (loading) return const [LinearProgressIndicator()];
    if (visibleFields.isEmpty) {
      return const [Text('Este formato todavía no tiene campos configurados.')];
    }

    final rows = <int, List<Map<String, dynamic>>>{};
    for (var i = 0; i < visibleFields.length; i++) {
      final field = visibleFields[i];
      final row = _gridNumber(field['grid_fila'], i + 1);
      rows.putIfAbsent(row, () => <Map<String, dynamic>>[]).add(field);
    }

    final widgets = <Widget>[];
    final sortedRows = rows.keys.toList()..sort();
    for (final row in sortedRows) {
      final rowFields = rows[row]!
        ..sort((a, b) {
          final ca = _gridNumber(a['grid_columna'], 1);
          final cb = _gridNumber(b['grid_columna'], 1);
          if (ca != cb) return ca.compareTo(cb);
          return _gridNumber(a['orden'], 999)
              .compareTo(_gridNumber(b['orden'], 999));
        });
      final columns = rowFields
          .map((field) => Expanded(
              child: buildField(context, field, setState,
                  firstDate: firstDate, lastDate: lastDate)))
          .toList();
      widgets.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < columns.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          columns[i],
        ],
      ]));
      widgets.add(const SizedBox(height: 12));
    }
    return widgets;
  }
}

class AsistenciaPersonalSpecialPage extends StatefulWidget {
  final String moduleId;
  final Map<String, dynamic> format;
  final Map<String, dynamic>? initialPayload;
  final String? editIdLocal;
  final VoidCallback? onLocalChanged;
  final VoidCallback? onSavedAndExit;

  const AsistenciaPersonalSpecialPage({
    super.key,
    required this.moduleId,
    required this.format,
    this.initialPayload,
    this.editIdLocal,
    this.onLocalChanged,
    this.onSavedAndExit,
  });

  @override
  State<AsistenciaPersonalSpecialPage> createState() =>
      _AsistenciaPersonalSpecialPageState();
}

class _AsistenciaPersonalSpecialPageState
    extends State<AsistenciaPersonalSpecialPage> {
  final local = LocalDb.instance;
  final uuid = const Uuid();
  final fechaCtrl = TextEditingController();
  final placaCtrl = TextEditingController();
  final reclutadorCtrl = TextEditingController();
  final scannerCtrl = TextEditingController();
  final scannerFocus = FocusNode();
  final ScrollController _asistenciaVerticalCtrl = ScrollController();
  late final _SpecialMatrixHeader asistenciaHeader;
  final List<Map<String, dynamic>> scannedRows = [];
  List<Map<String, dynamic>> asistenciaWorkers = [];
  List<Map<String, dynamic>> mobilityRows = [];
  Map<String, dynamic>? selectedMobility;
  String tipoMovimiento = 'INGRESO';
  bool saving = false;
  String mobilityValidationMessage = '';
  bool validatingMobility = false;
  bool loadingMobilities = true;
  String? acceptedMobilityWarningKey;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    fechaCtrl.text = _dateIso(now);
    asistenciaHeader = _SpecialMatrixHeader(local, 'GT-CABECERA_ASISTENCIA');
    _hydrateFromInitialPayload();
    _loadAsistenciaHeader();
    _loadAsistenciaWorkers();
    _loadMobilities();
    _loadDailyAttendanceRows();
    // No enfocar automáticamente: evita abrir el teclado al entrar a Asistencia.
  }

  @override
  void dispose() {
    fechaCtrl.dispose();
    placaCtrl.dispose();
    reclutadorCtrl.dispose();
    scannerCtrl.dispose();
    scannerFocus.dispose();
    asistenciaHeader.dispose();
    _asistenciaVerticalCtrl.dispose();
    super.dispose();
  }

  String _dateIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _dateTitle(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year.toString().substring(2)}';
  String _timeHm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _norm(String v) =>
      v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  String _digits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');

  dynamic _rowValue(Map<String, dynamic> row, List<String> keys) {
    final wanted = keys.map(_norm).toSet();
    for (final e in row.entries) {
      if (wanted.contains(_norm(e.key))) return e.value;
    }
    return null;
  }

  Future<Set<String>> _destinationFieldNorms(String table,
      {Iterable<String> extra = const []}) async {
    final rows =
        await local.where('local_form_fields', 'tabla_destino = ?', [table]);
    final out = extra.map(_norm).toSet();
    for (final row in rows) {
      final campo = row['campo']?.toString().trim() ?? '';
      if (campo.isNotEmpty) out.add(_norm(campo));
    }
    return out;
  }

  Map<String, dynamic> _filterPayloadForNorms(
      Map<String, dynamic> payload, Set<String> allowed) {
    final out = <String, dynamic>{};
    for (final entry in payload.entries) {
      final key = entry.key.toString();
      if (allowed.contains(_norm(key))) out[key] = entry.value;
    }
    return out;
  }

  Future<String> _activeUserName() async {
    final session = LocalSession();
    final userId = (Supabase.instance.client.auth.currentUser?.id ??
                await session.cachedUserId())
            ?.trim() ??
        '';
    final login =
        (await session.cachedLoginIdentifier())?.trim().toLowerCase() ?? '';
    final aliases = (await session.cachedLoginAliases())
        .map((e) => e.trim().toLowerCase())
        .toSet();
    final profiles = await local.getAll('local_profile');
    for (final p in profiles) {
      final id = p['id']?.toString().trim() ?? '';
      final dni = p['dni']?.toString().trim().toLowerCase() ?? '';
      final email = p['email']?.toString().trim().toLowerCase() ?? '';
      final matches = (userId.isNotEmpty && id == userId) ||
          (login.isNotEmpty && (login == dni || login == email)) ||
          aliases.contains(dni) ||
          aliases.contains(email);
      if (!matches) continue;
      final name = p['nombres']?.toString().trim() ?? '';
      if (name.isNotEmpty) return name;
    }
    return '';
  }

  String _normalizeScan(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    if (v.startsWith('{') && v.endsWith('}')) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map) {
          for (final k in [
            'dni',
            'DNI',
            'Dni',
            'documento',
            'codigo_personal',
            'QR_PERSONAL',
            'id_local'
          ]) {
            final value = decoded[k]?.toString().trim() ?? '';
            if (value.isNotEmpty) return value;
          }
        }
      } catch (_) {}
    }
    final digits = _digits(v);
    if (digits.length == 8) return digits;
    if (digits.length > 8) {
      final match = RegExp(r'(?<!\d)\d{8}(?!\d)').firstMatch(v)?.group(0);
      return match ?? digits.substring(0, 8);
    }
    return v;
  }

  void _hydrateFromInitialPayload() {
    final payload = widget.initialPayload;
    if (payload == null || payload.isEmpty) return;
    fechaCtrl.text =
        (_rowValue(payload, ['FECHA', 'Fecha']) ?? fechaCtrl.text).toString();
    placaCtrl.text = (_rowValue(payload, ['PLACA', 'Placa']) ?? '').toString();
    reclutadorCtrl.text =
        (_rowValue(payload, ['RECLUTADOR', 'Reclutador']) ?? '').toString();
    scannedRows.add(Map<String, dynamic>.from(payload));
  }

  Future<void> _loadAsistenciaHeader() async {
    await asistenciaHeader.load(initialPayload: widget.initialPayload);
    final fecha = asistenciaHeader.valueByCandidates(['FECHA', 'Fecha']);
    if (fecha.isNotEmpty) fechaCtrl.text = fecha;
    final placa = asistenciaHeader
        .valueByCandidates(['PLACA', 'MOVILIDAD', 'PLACA_MOVILIDAD']);
    if (placa.isNotEmpty) placaCtrl.text = placa;
    final reclutador = asistenciaHeader.valueByCandidates(['RECLUTADOR']);
    if (reclutador.isNotEmpty) reclutadorCtrl.text = reclutador;
    final movimiento = asistenciaHeader.valueByCandidates(
        ['MOVIMIENTO', 'TIPO_MOVIMIENTO', 'TIPO MOVIMIENTO']);
    if (movimiento.trim().isNotEmpty) {
      final upper = movimiento.trim().toUpperCase();
      tipoMovimiento = upper.contains('SAL') ? 'SALIDA' : 'INGRESO';
    }
    if (mounted) setState(() {});
    if (!loadingMobilities) await _ensureMobilityReady(prompt: false);
    await _loadDailyAttendanceRows();
  }

  String _headerValue(List<String> fields, {String fallback = ''}) =>
      asistenciaHeader.valueByCandidates(fields, fallback: fallback);

  Map<String, dynamic> _asistenciaHeaderPayload() {
    final payload = asistenciaHeader.payload();
    final fecha = _headerValue(['FECHA'], fallback: fechaCtrl.text.trim());
    if (fecha.isNotEmpty) payload['FECHA'] = fecha;
    final placa = _headerValue(['PLACA', 'MOVILIDAD', 'PLACA_MOVILIDAD'],
        fallback: placaCtrl.text.trim());
    if (placa.isNotEmpty) payload['PLACA'] = placa;
    final reclutador =
        _headerValue(['RECLUTADOR'], fallback: reclutadorCtrl.text.trim());
    if (reclutador.isNotEmpty) payload['RECLUTADOR'] = reclutador;
    payload['TIPO_MOVIMIENTO'] =
        tipoMovimiento == 'SALIDA' ? 'Salida' : 'Ingreso';
    return payload;
  }

  Future<void> _loadDailyAttendanceRows() async {
    final fecha = _headerValue(['FECHA'], fallback: fechaCtrl.text.trim());
    final rows = await local.allRecords();
    final dayRows = <Map<String, dynamic>>[];
    for (final r in rows) {
      if ((r['tabla_destino']?.toString() ?? '') != 'GT-ASISTENCIA_PERSONAL')
        continue;
      try {
        final payload = jsonDecode(r['payload_json']?.toString() ?? '{}')
            as Map<String, dynamic>;
        if (isSoftDeletedAppgtRow(payload)) continue;
        final f = (payload['FECHA'] ?? payload['FECHA_INGRESO'] ?? '')
            .toString()
            .trim();
        if (f == fecha) dayRows.add(payload);
      } catch (_) {}
    }
    dayRows.sort((a, b) => (b['HORA_INGRESO']?.toString() ?? '')
        .compareTo(a['HORA_INGRESO']?.toString() ?? ''));
    if (mounted)
      setState(() {
        scannedRows
          ..clear()
          ..addAll(dayRows);
      });
  }

  Future<void> _loadAsistenciaWorkers() async {
    final out = <String, Map<String, dynamic>>{};
    void addWorker(Map<String, dynamic> payload) {
      if (isSoftDeletedAppgtRow(payload)) return;
      final dni = (_rowValue(payload, ['DNI', 'Dni', 'DOCUMENTO']) ?? '')
          .toString()
          .trim();
      if (dni.isEmpty) return;
      out[_digits(dni).isNotEmpty ? _digits(dni) : dni] = payload;
    }

    for (final source in [
      'GH-REGISTRO_PERSONAL_PLANILLA',
      'GH_REGISTRO_PERSONAL_PLANILLA'
    ]) {
      final rows =
          await local.where('local_matrix_rows', 'source_table = ?', [source]);
      for (final r in rows) {
        try {
          addWorker(jsonDecode(r['payload_json']?.toString() ?? '{}')
              as Map<String, dynamic>);
        } catch (_) {}
      }
    }
    final pending = await local.allRecords();
    for (final r in pending) {
      final table = (r['tabla_destino']?.toString() ?? '').toUpperCase();
      if (table != 'GH-REGISTRO_PERSONAL_PLANILLA' &&
          table != 'GH_REGISTRO_PERSONAL_PLANILLA') continue;
      try {
        addWorker(jsonDecode(r['payload_json']?.toString() ?? '{}')
            as Map<String, dynamic>);
      } catch (_) {}
    }
    if (mounted) setState(() => asistenciaWorkers = out.values.toList());
  }

  Map<String, dynamic>? _findWorkerInLoaded(String raw) {
    final code = _normalizeScan(raw);
    final q = code.trim().toLowerCase();
    final qDigits = _digits(q);
    if (q.isEmpty) return null;
    for (final payload in asistenciaWorkers) {
      final dni = (_rowValue(payload, ['DNI', 'Dni', 'DOCUMENTO']) ?? '')
          .toString()
          .trim();
      final nombre = (_rowValue(payload, [
                'APELLIDOS Y NOMBRES',
                'Apellidos y Nombres',
                'NOMBRE COMPLETO'
              ]) ??
              '')
          .toString()
          .trim();
      final qr =
          (_rowValue(payload, ['QR_PERSONAL', 'CODIGO_PERSONAL', 'id_local']) ??
                  '')
              .toString()
              .trim();
      final haystack = '$dni $nombre $qr'.toLowerCase();
      if ((qDigits.isNotEmpty &&
              (_digits(dni).contains(qDigits) ||
                  _digits(qr).contains(qDigits))) ||
          haystack.contains(q)) return payload;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _findWorker(String raw) async {
    final loaded = _findWorkerInLoaded(raw);
    if (loaded != null) return loaded;
    final code = _normalizeScan(raw);
    if (code.isEmpty) return null;
    for (final source in [
      'GH-REGISTRO_PERSONAL_PLANILLA',
      'GH_REGISTRO_PERSONAL_PLANILLA'
    ]) {
      final rows =
          await local.where('local_matrix_rows', 'source_table = ?', [source]);
      for (final r in rows) {
        try {
          final payload = jsonDecode(r['payload_json']?.toString() ?? '{}')
              as Map<String, dynamic>;
          if (isSoftDeletedAppgtRow(payload)) continue;
          final candidates = [
            _rowValue(payload, ['DNI', 'Dni', 'DOCUMENTO']),
            _rowValue(payload, ['QR_PERSONAL', 'CODIGO_PERSONAL', 'id_local']),
          ].map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty);
          for (final c in candidates) {
            if (c == code || _digits(c) == _digits(code)) return payload;
          }
        } catch (_) {}
      }
    }
    final pending = await local.allRecords();
    for (final r in pending) {
      final table = (r['tabla_destino']?.toString() ?? '').toUpperCase();
      if (table != 'GH-REGISTRO_PERSONAL_PLANILLA' &&
          table != 'GH_REGISTRO_PERSONAL_PLANILLA') continue;
      try {
        final payload = jsonDecode(r['payload_json']?.toString() ?? '{}')
            as Map<String, dynamic>;
        if (isSoftDeletedAppgtRow(payload)) continue;
        final candidates = [
          _rowValue(payload, ['DNI', 'Dni', 'DOCUMENTO']),
          _rowValue(payload, ['QR_PERSONAL', 'CODIGO_PERSONAL', 'id_local']),
        ].map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty);
        for (final c in candidates) {
          if (c == code || _digits(c) == _digits(code)) return payload;
        }
      } catch (_) {}
    }
    return null;
  }

  bool _boolValue(dynamic value) {
    if (value == true || value == 1) return true;
    final text = value?.toString().trim().toUpperCase() ?? '';
    return text == 'TRUE' ||
        text == 'SI' ||
        text == 'SÍ' ||
        text == 'YES' ||
        text == '1';
  }

  DateTime? _dateValue(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    final iso =
        DateTime.tryParse(text.length >= 10 ? text.substring(0, 10) : text);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    final parts = text.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _localPayloadsForTable(
      String table) async {
    final out = <Map<String, dynamic>>[];
    final wanted = table.trim().toUpperCase();
    for (final source in {table, table.replaceAll('_', '-')}) {
      final rows = await local.where(
        'local_matrix_rows',
        'source_table = ?',
        [source],
      );
      for (final row in rows) {
        try {
          final decoded = jsonDecode(row['payload_json']?.toString() ?? '{}');
          if (decoded is Map) {
            final payload = Map<String, dynamic>.from(decoded);
            if (!isSoftDeletedAppgtRow(payload)) out.add(payload);
          }
        } catch (_) {}
      }
    }
    for (final row in await local.allRecords()) {
      if ((row['tabla_destino']?.toString() ?? '').trim().toUpperCase() !=
          wanted) {
        continue;
      }
      try {
        final decoded = jsonDecode(row['payload_json']?.toString() ?? '{}');
        if (decoded is Map) {
          final payload = Map<String, dynamic>.from(decoded);
          if (!isSoftDeletedAppgtRow(payload)) out.add(payload);
        }
      } catch (_) {}
    }
    return out;
  }

  Future<String?> _attendanceBlockReason(
    Map<String, dynamic> worker,
    String dni,
    DateTime attendanceDate,
  ) async {
    final status = _norm(
      (_rowValue(worker, ['Status', 'ESTADO', 'ESTADO_PERSONAL']) ?? '')
          .toString(),
    );
    final contractStart = _dateValue(_rowValue(worker, [
      'Fecha inicio de Contrato',
      'FECHA_INICIO_CONTRATO',
      'FECHA INICIO DE CONTRATO',
    ]));
    final contractEnd = _dateValue(_rowValue(worker, [
      'Fecha fin de Contrato',
      'FECHA_FIN_CONTRATO',
      'FECHA FIN DE CONTRATO',
    ]));
    if (status.isNotEmpty && status != 'ACTIVO') {
      return status == 'PENDIENTERENOVACION'
          ? 'Contrato vencido. Derivar a Gestión Humana para su renovación.'
          : 'El trabajador no está activo: ${status.replaceAll('_', ' ')}.';
    }
    if (contractStart == null) {
      return 'El trabajador no tiene fecha de inicio de contrato configurada.';
    }
    if (contractEnd == null) {
      return 'El trabajador no tiene fecha de fin de contrato configurada.';
    }
    final day =
        DateTime(attendanceDate.year, attendanceDate.month, attendanceDate.day);
    if (day.isBefore(contractStart)) {
      return 'El contrato inicia el ${contractStart.day.toString().padLeft(2, '0')}/'
          '${contractStart.month.toString().padLeft(2, '0')}/${contractStart.year}.';
    }
    if (contractEnd.isBefore(day)) {
      return 'Contrato vencido el ${contractEnd.day.toString().padLeft(2, '0')}/'
          '${contractEnd.month.toString().padLeft(2, '0')}/${contractEnd.year}.';
    }

    final sanctions =
        await _localPayloadsForTable('GH_SANCIONES_PERSONAL_APPGT');
    for (final sanction in sanctions.reversed) {
      final sanctionDni = _digits(
        (_rowValue(sanction, ['dni', 'DNI', 'DOCUMENTO']) ?? '').toString(),
      );
      if (sanctionDni != _digits(dni)) continue;
      final state = _norm(
        (_rowValue(sanction, ['estado', 'ESTADO']) ?? '').toString(),
      );
      if (state != 'VIGENTE' ||
          !_boolValue(_rowValue(
              sanction, ['bloquea_asistencia', 'BLOQUEA_ASISTENCIA']))) {
        continue;
      }
      final start =
          _dateValue(_rowValue(sanction, ['fecha_inicio', 'FECHA_INICIO']));
      final end = _dateValue(_rowValue(sanction, ['fecha_fin', 'FECHA_FIN']));
      if (start == null ||
          end == null ||
          day.isBefore(start) ||
          day.isAfter(end)) {
        continue;
      }
      final type = (_rowValue(sanction, ['tipo_sancion', 'TIPO_SANCION']) ??
              'sanción vigente')
          .toString()
          .trim()
          .toLowerCase();
      return 'El trabajador cuenta con $type hasta '
          '${end.day.toString().padLeft(2, '0')}/'
          '${end.month.toString().padLeft(2, '0')}/${end.year}.';
    }
    return null;
  }

  // La asistencia usa la ficha maestra de movilidad. El antiguo formato de
  // ingresos por día ya no forma parte de este flujo.
  String _mobilityPlate(Map<String, dynamic> row) =>
      (_rowValue(row, ['placa', 'PLACA']) ?? '').toString().trim();

  String _selectedPlate() {
    final raw = _headerValue(
      ['PLACA', 'MOVILIDAD', 'PLACA_MOVILIDAD'],
      fallback: placaCtrl.text.trim(),
    ).trim();
    return _norm(raw) == 'SINMOVILIDAD' ? '' : raw;
  }

  void _setHeaderPlate(String plate) {
    placaCtrl.text = plate;
    for (final entry in asistenciaHeader.controllers.entries) {
      final normalized = _specialNorm(entry.key);
      if (normalized == 'PLACA' ||
          normalized == 'MOVILIDAD' ||
          normalized == 'PLACA_MOVILIDAD') {
        entry.value.text = plate;
      }
    }
  }

  Map<String, dynamic>? _mobilityForPlate(String plate) {
    final wanted = _norm(plate);
    if (wanted.isEmpty) return null;
    for (final row in mobilityRows) {
      if (_norm(_mobilityPlate(row)) == wanted) return row;
    }
    return null;
  }

  Future<void> _loadMobilities() async {
    final entries = <Map<String, dynamic>>[];
    for (final table in {
      'GT-MATRIZ_MOVILIDADES',
      'GT_MATRIZ_MOVILIDADES',
    }) {
      entries.addAll(await _localPayloadsForTable(table));
    }

    final byPlate = <String, Map<String, dynamic>>{};
    for (final entry in entries) {
      if (_boolValue(_rowValue(entry, ['eliminado', 'ELIMINADO']))) continue;
      final active = _rowValue(entry, ['activo', 'ACTIVO']);
      if (active != null && !_boolValue(active)) continue;
      final plate = _mobilityPlate(entry);
      if (plate.isEmpty) continue;
      final key = _norm(plate);
      byPlate[key] = <String, dynamic>{
        ...?byPlate[key],
        ...entry,
      };
    }
    final loaded = byPlate.values.toList()
      ..sort((a, b) => _mobilityPlate(a)
          .toLowerCase()
          .compareTo(_mobilityPlate(b).toLowerCase()));
    if (!mounted) return;
    final currentPlate = _selectedPlate();
    Map<String, dynamic>? currentMobility;
    for (final row in loaded) {
      if (_norm(_mobilityPlate(row)) == _norm(currentPlate)) {
        currentMobility = row;
        break;
      }
    }
    setState(() {
      mobilityRows = loaded;
      loadingMobilities = false;
      selectedMobility = currentMobility;
      if (currentPlate.isEmpty) {
        mobilityValidationMessage =
            'Sin movilidad: el personal ingresará caminando.';
      } else if (currentMobility == null) {
        mobilityValidationMessage =
            'La placa $currentPlate no está registrada en GT-MATRIZ_MOVILIDADES.';
      }
    });
    if (currentPlate.isNotEmpty && currentMobility != null) {
      await _ensureMobilityReady(prompt: false);
    }
  }

  String _dateDisplay(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  List<String> _mobilityIssues(
      Map<String, dynamic> mobility, DateTime attendanceDate) {
    final issues = <String>[];
    final dni = (_rowValue(mobility,
                ['dni_conductor', 'conductor_dni', 'DNI_CONDUCTOR']) ??
            '')
        .toString()
        .trim();
    final driver =
        (_rowValue(mobility, ['conductor', 'conductor_nombre', 'CONDUCTOR']) ??
                '')
            .toString()
            .trim();
    final license =
        (_rowValue(mobility, ['licencia_conducir', 'LICENCIA_CONDUCIR']) ?? '')
            .toString()
            .trim();
    if (dni.isEmpty) issues.add('El DNI del conductor no está registrado.');
    if (driver.isEmpty) {
      issues.add('El nombre del conductor no está registrado.');
    }
    if (license.isEmpty) {
      issues.add('La licencia de conducir no está registrada.');
    }

    void validateExpiration(List<String> fields, String label) {
      final expiration = _dateValue(_rowValue(mobility, fields));
      if (expiration == null) {
        issues.add('La vigencia de $label no está registrada.');
      } else if (expiration.isBefore(attendanceDate)) {
        issues.add('$label venció el ${_dateDisplay(expiration)}.');
      }
    }

    validateExpiration(
        ['licencia_vigencia', 'LICENCIA_VIGENCIA'], 'la licencia de conducir');
    validateExpiration(['soat_vigencia', 'SOAT_VIGENCIA'], 'el SOAT');
    validateExpiration(
        ['revision_tecnica_vigencia', 'REVISION_TECNICA_VIGENCIA'],
        'la revisión técnica');
    return issues;
  }

  String _mobilityWarningKey(
          String plate, DateTime date, List<String> issues) =>
      '${_norm(plate)}|${_dateIso(date)}|${issues.join('|')}';

  List<String> _currentMobilityIssues() {
    final mobility = selectedMobility;
    final date = _dateValue(
      _headerValue(['FECHA'], fallback: fechaCtrl.text.trim()),
    );
    if (mobility == null || date == null) return const [];
    return _mobilityIssues(mobility, date);
  }

  bool get _mobilityWarningAccepted {
    final plate = _selectedPlate();
    final date = _dateValue(
      _headerValue(['FECHA'], fallback: fechaCtrl.text.trim()),
    );
    final issues = _currentMobilityIssues();
    if (plate.isEmpty || date == null || issues.isEmpty) return false;
    return acceptedMobilityWarningKey ==
        _mobilityWarningKey(plate, date, issues);
  }

  Future<bool> _ensureMobilityReady({bool prompt = true}) async {
    final plate = _selectedPlate();
    if (plate.isEmpty) {
      if (mounted) {
        setState(() {
          selectedMobility = null;
          acceptedMobilityWarningKey = null;
          mobilityValidationMessage =
              'Sin movilidad: el personal ingresará caminando.';
        });
      }
      return true;
    }
    final attendanceDate = _dateValue(
      _headerValue(['FECHA'], fallback: fechaCtrl.text.trim()),
    );
    if (attendanceDate == null) {
      if (mounted) {
        setState(() => mobilityValidationMessage =
            'Seleccione una fecha válida antes de marcar asistencia.');
      }
      return false;
    }
    final mobility = _mobilityForPlate(plate);
    if (mobility == null) {
      if (mounted) {
        setState(() {
          selectedMobility = null;
          acceptedMobilityWarningKey = null;
          mobilityValidationMessage =
              'La placa $plate no está registrada en GT-MATRIZ_MOVILIDADES.';
        });
      }
      if (prompt && mounted) {
        await _showAppGtAlert(context, mobilityValidationMessage,
            playSound: true);
      }
      return false;
    }

    final issues = _mobilityIssues(mobility, attendanceDate);
    final warningKey = _mobilityWarningKey(plate, attendanceDate, issues);
    if (issues.isEmpty) {
      if (mounted) {
        setState(() {
          selectedMobility = mobility;
          acceptedMobilityWarningKey = null;
          mobilityValidationMessage = 'Movilidad habilitada: $plate · '
              '${(_rowValue(mobility, [
                        'conductor',
                        'conductor_nombre'
                      ]) ?? 'conductor registrado')}';
        });
      }
      return true;
    }
    if (acceptedMobilityWarningKey == warningKey) return true;
    if (!prompt) {
      if (mounted) {
        setState(() {
          selectedMobility = mobility;
          mobilityValidationMessage =
              'La movilidad $plate tiene documentación pendiente o vencida.';
        });
      }
      return false;
    }

    await SystemSound.play(SystemSoundType.alert);
    if (!mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Alerta de movilidad'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('La placa $plate presenta lo siguiente:'),
            const SizedBox(height: 12),
            ...issues.map((issue) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.warning_amber_rounded,
                      color: Colors.orange),
                  title: Text(issue),
                )),
            const SizedBox(height: 8),
            const Text('¿Desea continuar de todas formas?'),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar registro'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (proceed != true) {
      _setHeaderPlate('');
      if (mounted) {
        setState(() {
          selectedMobility = null;
          acceptedMobilityWarningKey = null;
          mobilityValidationMessage =
              'Registro cancelado por alerta de movilidad.';
        });
        await Navigator.maybePop(context);
      }
      return false;
    }
    if (mounted) {
      setState(() {
        selectedMobility = mobility;
        acceptedMobilityWarningKey = warningKey;
        mobilityValidationMessage =
            'Alerta aceptada para $plate. Puede continuar con la asistencia.';
      });
    }
    return true;
  }

  Future<void> _selectMobilityPlate(String plate) async {
    _setHeaderPlate(plate);
    if (!mounted) return;
    setState(() {
      selectedMobility = _mobilityForPlate(plate);
      acceptedMobilityWarningKey = null;
    });
    await _ensureMobilityReady(prompt: plate.isNotEmpty);
  }

  Future<Map<String, String>?> _showDriverEditor(
      Map<String, dynamic> mobility) async {
    final dniCtrl = TextEditingController(
      text: (_rowValue(mobility,
                  ['dni_conductor', 'conductor_dni', 'DNI_CONDUCTOR']) ??
              '')
          .toString(),
    );
    final driverCtrl = TextEditingController(
      text: (_rowValue(
                  mobility, ['conductor', 'conductor_nombre', 'CONDUCTOR']) ??
              '')
          .toString(),
    );
    final licenseCtrl = TextEditingController(
      text: (_rowValue(mobility, ['licencia_conducir', 'LICENCIA_CONDUCIR']) ??
              '')
          .toString(),
    );
    var licenseDate =
        (_rowValue(mobility, ['licencia_vigencia', 'LICENCIA_VIGENCIA']) ?? '')
            .toString()
            .trim();
    String? error;
    try {
      return await showDialog<Map<String, String>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: Text('Actualizar conductor · ${_mobilityPlate(mobility)}'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    controller: dniCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'DNI del conductor *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: driverCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Conductor *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: licenseCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Licencia de conducir *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final today = DateTime.now();
                      final current = _dateValue(licenseDate) ?? today;
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: current,
                        firstDate: DateTime(today.year - 10),
                        lastDate: DateTime(today.year + 20),
                      );
                      if (picked != null) {
                        setLocalState(() => licenseDate = _dateIso(picked));
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Vigencia de licencia *',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(licenseDate.isEmpty
                          ? 'Seleccione una fecha'
                          : licenseDate),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final dni = dniCtrl.text.trim();
                  final driver = driverCtrl.text.trim();
                  final license = licenseCtrl.text.trim().toUpperCase();
                  if (dni.length != 8 ||
                      driver.isEmpty ||
                      license.isEmpty ||
                      _dateValue(licenseDate) == null) {
                    setLocalState(() => error =
                        'Complete los cuatro campos; el DNI debe tener 8 dígitos.');
                    return;
                  }
                  Navigator.pop(dialogContext, {
                    'dni_conductor': dni,
                    'conductor': driver,
                    'licencia_conducir': license,
                    'licencia_vigencia': licenseDate,
                  });
                },
                child: const Text('Actualizar'),
              ),
            ],
          ),
        ),
      );
    } finally {
      dniCtrl.dispose();
      driverCtrl.dispose();
      licenseCtrl.dispose();
    }
  }

  bool _isUuid(String value) => RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(value);

  Future<void> _editSelectedDriver() async {
    final mobility = selectedMobility;
    if (mobility == null) return;
    final values = await _showDriverEditor(mobility);
    if (values == null || !mounted) return;
    final idLocal =
        (_rowValue(mobility, ['id_local', 'ID_LOCAL']) ?? '').toString().trim();
    if (!_isUuid(idLocal)) {
      await _showAppGtAlert(
        context,
        'Esta ficha aún no tiene identificador de sincronización. Actualice los datos con internet y vuelva a intentar.',
      );
      return;
    }
    final userId = Supabase.instance.client.auth.currentUser?.id ??
        await LocalSession().cachedUserId();
    if (!mounted) return;
    if (userId == null) {
      await _showAppGtAlert(
          context, 'No hay un usuario local para actualizar el conductor.');
      return;
    }
    final updated = <String, dynamic>{
      ...mobility,
      ...values,
      'id_local': idLocal,
    };
    final formats = await local.getAll('local_formats', orderBy: 'orden');
    Map<String, dynamic>? format;
    for (final row in formats) {
      if (_norm(row['tabla_destino']?.toString() ?? '') ==
          _norm('GT-MATRIZ_MOVILIDADES')) {
        format = row;
        break;
      }
    }
    await local.insertPending({
      'id_local': idLocal,
      'user_id': userId,
      'modulo_id': format?['modulo_id'] ?? widget.moduleId,
      'formato_id': format?['id'] ?? widget.format['id'],
      'formato_tabla_id': null,
      'tabla_destino': 'GT-MATRIZ_MOVILIDADES',
      'payload_json': jsonEncode(updated),
      'estado': 'pendiente',
      'intentos': 0,
      'base_updated_at':
          _rowValue(mobility, ['updated_at', 'UPDATED_AT'])?.toString(),
      'created_at': DateTime.now().toIso8601String(),
    });
    await local.upsertMatrixRowPayload('GT-MATRIZ_MOVILIDADES', updated);
    if (!mounted) return;
    setState(() {
      selectedMobility = updated;
      mobilityRows = mobilityRows
          .map((row) =>
              _norm(_mobilityPlate(row)) == _norm(_mobilityPlate(updated))
                  ? updated
                  : row)
          .toList();
      acceptedMobilityWarningKey = null;
    });
    widget.onLocalChanged?.call();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Datos del conductor actualizados localmente.'),
    ));
    await _ensureMobilityReady(prompt: true);
  }

  double? _hoursBetween(String ingreso, String salida) {
    try {
      final i = ingreso.split(':');
      final s = salida.split(':');
      final a = DateTime(2000, 1, 1, int.parse(i[0]), int.parse(i[1]));
      var b = DateTime(2000, 1, 1, int.parse(s[0]), int.parse(s[1]));
      if (b.isBefore(a)) b = b.add(const Duration(days: 1));
      return double.parse(
          (b.difference(a).inMinutes / 60.0).toStringAsFixed(2));
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _existingAttendancePayload(String dni) async {
    final fecha = _headerValue(['FECHA'], fallback: fechaCtrl.text.trim());
    final rows = await local.allRecords();
    Map<String, dynamic>? firstSameDay;
    for (final r in rows) {
      if ((r['tabla_destino']?.toString() ?? '') != 'GT-ASISTENCIA_PERSONAL')
        continue;
      try {
        final payload = jsonDecode(r['payload_json']?.toString() ?? '{}')
            as Map<String, dynamic>;
        if (isSoftDeletedAppgtRow(payload)) continue;
        final samePersonDay = (payload['FECHA']?.toString() ?? '') == fecha &&
            (payload['DNI']?.toString() ?? '') == dni;
        if (!samePersonDay) continue;

        final match = {'record': r, 'payload': payload};
        firstSameDay ??= match;

        // For SALIDA, update the open attendance row first. This prevents
        // creating a second row when the plate/mobility text differs.
        if (tipoMovimiento == 'SALIDA') {
          final salida = payload['HORA_SALIDA']?.toString().trim() ?? '';
          if (salida.isEmpty || salida.toLowerCase() == 'null') return match;
        } else {
          return match;
        }
      } catch (_) {}
    }
    return firstSameDay;
  }

  Future<Map<String, dynamic>?> _findPlanillaFormat() async {
    final formats = await local.getAll('local_formats', orderBy: 'orden');
    for (final f in formats) {
      final table = (f['tabla_destino']?.toString() ?? '').toUpperCase();
      final id = (f['id']?.toString() ?? '').toUpperCase();
      if (table == 'GH-REGISTRO_PERSONAL_PLANILLA' ||
          id.contains('REGISTRO_PERSONAL_PLANILLA')) {
        return Map<String, dynamic>.from(f);
      }
    }
    return null;
  }

  Future<bool> _confirmUnknownWorker(String dni) async {
    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Personal no encontrado'),
        content: Text(
            'El DNI $dni no existe en el registro de personal local. ¿Qué deseas hacer?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'omit'),
              child: const Text('Omitir')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'add'),
              child: const Text('Agregar personal')),
        ],
      ),
    );
    if (action == 'add') {
      final fmt = await _findPlanillaFormat();
      if (fmt == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'No se encontró el formato Registro de personal en los datos locales.')));
        return false;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FormRunnerPage(
          moduleId: fmt['modulo_id']?.toString() ?? widget.moduleId,
          format: fmt,
          initialPayload: {
            'DNI': dni,
            'Dni': dni,
            'dni': dni,
            'DOCUMENTO': dni
          },
        ),
      ));
      await _loadAsistenciaWorkers();
      return true;
    }
    return action == 'omit';
  }

  Future<void> _saveAttendancePayload(Map<String, dynamic> payload,
      String idLocal, Map<String, dynamic>? existing) async {
    final userId = Supabase.instance.client.auth.currentUser?.id ??
        await LocalSession().cachedUserId();
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay usuario local para guardar asistencia.')));
      return;
    }
    setState(() => saving = true);
    try {
      if (existing != null) await local.deleteRecord(idLocal);
      await local.insertPending({
        'id_local': idLocal,
        'user_id': userId,
        'modulo_id': widget.moduleId,
        'formato_id': widget.format['id'],
        'formato_tabla_id': null,
        'tabla_destino': 'GT-ASISTENCIA_PERSONAL',
        'payload_json': jsonEncode(payload),
        'estado': 'pendiente',
        'intentos': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      final dni = payload['DNI']?.toString() ?? '';
      setState(() {
        scannedRows.removeWhere((e) => e['DNI'] == dni);
        scannedRows.insert(0, payload);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar asistencia: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _processScan(String raw) async {
    final code = _normalizeScan(raw);
    if (code.isEmpty || saving) return;
    scannerCtrl.clear();
    scannerFocus.requestFocus();
    final worker = await _findWorker(code);
    if (!mounted) return;
    Map<String, dynamic>? resolvedWorker = worker;
    if (resolvedWorker == null) {
      final proceed = await _confirmUnknownWorker(code);
      if (!proceed || !mounted) return;
      resolvedWorker = await _findWorker(code);
    }
    final dni = (_rowValue(resolvedWorker ?? const <String, dynamic>{},
                ['DNI', 'Dni', 'DOCUMENTO']) ??
            code)
        .toString()
        .trim();
    final nombre = (_rowValue(resolvedWorker ?? const <String, dynamic>{}, [
              'APELLIDOS Y NOMBRES',
              'Apellidos y Nombres',
              'NOMBRE COMPLETO'
            ]) ??
            '')
        .toString();
    final puesto = (_rowValue(resolvedWorker ?? const <String, dynamic>{},
                ['PUESTO', 'Puesto', 'CARGO']) ??
            '')
        .toString();
    final attendanceDate = _dateValue(
          _headerValue(['FECHA'], fallback: fechaCtrl.text.trim()),
        ) ??
        DateTime.now();
    if (tipoMovimiento == 'INGRESO') {
      final blockReason = await _attendanceBlockReason(
        resolvedWorker ?? const <String, dynamic>{},
        dni,
        attendanceDate,
      );
      if (blockReason != null) {
        await _showAppGtAlert(context, blockReason, playSound: true);
        return;
      }
      final headerPlate = _headerValue(
        ['PLACA', 'MOVILIDAD', 'PLACA_MOVILIDAD'],
        fallback: placaCtrl.text.trim(),
      );
      if (headerPlate.trim().isNotEmpty) {
        if (!await _ensureMobilityReady(prompt: true)) return;
      }
    }
    final now = DateTime.now();
    final time = _timeHm(now);
    final headerPayload = _asistenciaHeaderPayload();
    final headerFecha =
        headerPayload['FECHA']?.toString().trim() ?? fechaCtrl.text.trim();
    final headerPlaca =
        headerPayload['PLACA']?.toString().trim() ?? placaCtrl.text.trim();
    final headerReclutador = headerPayload['RECLUTADOR']?.toString().trim() ??
        reclutadorCtrl.text.trim();
    final existing = await _existingAttendancePayload(dni);
    if (tipoMovimiento == 'INGRESO' && existing != null) {
      await _showAppGtAlert(context, 'Personal ya tiene asistencia',
          playSound: true);
      return;
    }
    if (tipoMovimiento == 'SALIDA') {
      final ingresoPrevio = existing == null
          ? ''
          : ((existing['payload'] as Map)['HORA_INGRESO']?.toString().trim() ??
              '');
      if (ingresoPrevio.isEmpty || ingresoPrevio.toLowerCase() == 'null') {
        await _showAppGtAlert(context, 'Personal no tiene ingreso');
        return;
      }
    }
    final idLocal = existing?['payload']?['id_local']?.toString() ?? uuid.v4();
    final payload = existing == null
        ? <String, dynamic>{
            ...headerPayload,
            'id_local': idLocal,
            'FECHA': headerFecha,
            'DNI': dni,
            'APELLIDOS Y NOMBRES': nombre,
            'PUESTO': puesto,
            'PLACA': headerPlaca,
            'RECLUTADOR': headerReclutador,
            'MARCADOR_ASISTENCIA': await _activeUserName(),
            'MOVILIDAD_ALERTA_ACEPTADA': _mobilityWarningAccepted,
            if (_currentMobilityIssues().isNotEmpty)
              'MOVILIDAD_ALERTA_DETALLE': _currentMobilityIssues().join(' '),
            'VALIDACION_LABORAL': 'VALIDADO',
            'estado_registro': 'COMPLETO',
          }
        : Map<String, dynamic>.from(existing['payload'] as Map);

    if (tipoMovimiento == 'INGRESO') {
      payload['HORA_INGRESO'] = time;
      payload['FECHA_INGRESO'] =
          headerFecha.isNotEmpty ? headerFecha : _dateIso(now);
      payload['PLACA'] = headerPlaca;
      payload['RECLUTADOR'] = headerReclutador;
    } else {
      payload['HORA_SALIDA'] = time;
      payload['FECHA_SALIDA'] = _dateIso(now);
      final ingreso = payload['HORA_INGRESO']?.toString() ?? '';
      final horas = _hoursBetween(ingreso, time);
      if (horas != null) payload['HORAS_ASISTENCIA'] = horas;
      if ((payload['PLACA']?.toString().trim() ?? '').isEmpty)
        payload['PLACA'] = headerPlaca;
      if ((payload['RECLUTADOR']?.toString().trim() ?? '').isEmpty)
        payload['RECLUTADOR'] = headerReclutador;
    }
    payload.addAll(headerPayload);
    payload['FECHA'] = headerFecha;
    payload['DNI'] = dni;
    payload['APELLIDOS Y NOMBRES'] = nombre;
    if (puesto.isNotEmpty) payload['PUESTO'] = puesto;
    payload['MARCADOR_ASISTENCIA'] = await _activeUserName();

    final allowed =
        await _destinationFieldNorms('GT-ASISTENCIA_PERSONAL', extra: [
      'id_local',
      'FECHA',
      'DNI',
      'APELLIDOS Y NOMBRES',
      'PUESTO',
      'PLACA',
      'RECLUTADOR',
      'HORA_INGRESO',
      'HORA_SALIDA',
      'FECHA_INGRESO',
      'FECHA_SALIDA',
      'HORAS_ASISTENCIA',
      'MARCADOR_ASISTENCIA',
      'MOVILIDAD_ALERTA_ACEPTADA',
      'MOVILIDAD_ALERTA_DETALLE',
      'VALIDACION_LABORAL',
      'BLOQUEO_MOTIVO',
      'estado_registro'
    ]);
    await _saveAttendancePayload(
        _filterPayloadForNorms(payload, allowed), idLocal, existing);
  }

  Future<void> _openCameraScanner() async {
    final code = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const _AsistenciaScannerPage()));
    if (code != null && code.trim().isNotEmpty) await _processScan(code);
  }

  Widget _workerSearchBox() {
    final q = scannerCtrl.text.trim().toLowerCase();
    final qDigits = _digits(q);
    final options = q.isEmpty
        ? <Map<String, dynamic>>[]
        : asistenciaWorkers
            .where((w) {
              final dni =
                  (_rowValue(w, ['DNI', 'Dni', 'DOCUMENTO']) ?? '').toString();
              final nombre = (_rowValue(w, [
                        'APELLIDOS Y NOMBRES',
                        'Apellidos y Nombres',
                        'NOMBRE COMPLETO'
                      ]) ??
                      '')
                  .toString();
              final haystack = '$dni $nombre'.toLowerCase();
              return haystack.contains(q) ||
                  (qDigits.isNotEmpty && _digits(dni).contains(qDigits));
            })
            .take(8)
            .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: scannerCtrl,
        focusNode: scannerFocus,
        autofocus: false,
        decoration: InputDecoration(
          labelText: 'Escanear DNI / QR / código de barras',
          helperText: 'Escribe DNI o nombre, o usa lector físico/cámara.',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
              onPressed: _openCameraScanner,
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Abrir cámara'),
        ),
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: _processScan,
      ),
      if (options.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 8),
          constraints: const BoxConstraints(maxHeight: 190),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FCFA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD8E5DD)),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final w = options[i];
              final dni =
                  (_rowValue(w, ['DNI', 'Dni', 'DOCUMENTO']) ?? '').toString();
              final nombre = (_rowValue(w, [
                        'APELLIDOS Y NOMBRES',
                        'Apellidos y Nombres',
                        'NOMBRE COMPLETO'
                      ]) ??
                      '')
                  .toString();
              return ListTile(
                dense: true,
                leading:
                    const Icon(Icons.badge_outlined, color: Color(0xFF2E6B37)),
                title: Text('$dni - $nombre'),
                onTap: () => _processScan(dni),
              );
            },
          ),
        ),
    ]);
  }

  bool _isAsistenciaMovementField(Map<String, dynamic> field) {
    final n = _specialNorm(field['campo']?.toString() ?? '');
    return n == 'MOVIMIENTO' ||
        n == 'TIPO_MOVIMIENTO' ||
        n == 'TIPO_MOVIMIENTO_ASISTENCIA';
  }

  bool _isAsistenciaPlateField(Map<String, dynamic> field) {
    final n = _specialNorm(field['campo']?.toString() ?? '');
    return n == 'PLACA' || n == 'MOVILIDAD' || n == 'PLACA_MOVILIDAD';
  }

  bool _isAsistenciaDateField(Map<String, dynamic> field) =>
      _specialNorm(field['campo']?.toString() ?? '') == 'FECHA';

  String _mobilityValue(List<String> fields,
      {String fallback = 'No registrado'}) {
    final mobility = selectedMobility;
    if (mobility == null) return fallback;
    final value = (_rowValue(mobility, fields) ?? '').toString().trim();
    return value.isEmpty ? fallback : value;
  }

  Widget _mobilitySelector() {
    final current = _selectedPlate();
    final plates = mobilityRows.map(_mobilityPlate).toList();
    if (current.isNotEmpty && !plates.any((p) => _norm(p) == _norm(current))) {
      plates.add(current);
    }
    final selected = current.isEmpty
        ? ''
        : plates.firstWhere((plate) => _norm(plate) == _norm(current));
    final issues = _currentMobilityIssues();
    final hasMobility = selectedMobility != null && current.isNotEmpty;
    final statusColor = current.isEmpty
        ? const Color(0xFF0D5F78)
        : issues.isEmpty
            ? Colors.green.shade700
            : _mobilityWarningAccepted
                ? Colors.orange.shade800
                : Colors.red.shade700;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<String>(
        key: ValueKey('attendance_plate_$selected'),
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Placa',
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.directions_car_outlined),
          helperText: loadingMobilities
              ? 'Cargando movilidades...'
              : mobilityRows.isEmpty
                  ? 'No hay placas locales. Actualice los datos con internet.'
                  : null,
        ),
        items: [
          const DropdownMenuItem<String>(
            value: '',
            child: Text('Sin movilidad'),
          ),
          ...plates.map((plate) => DropdownMenuItem<String>(
                value: plate,
                child: Text(plate),
              )),
        ],
        onChanged: loadingMobilities || validatingMobility
            ? null
            : (value) => _selectMobilityPlate(value ?? ''),
      ),
      const SizedBox(height: 10),
      if (hasMobility)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD8E5DD)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.person_pin_outlined, color: Color(0xFF31552F)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _mobilityValue(['conductor', 'conductor_nombre']),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: _editSelectedDriver,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar conductor'),
              ),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 18, runSpacing: 8, children: [
              Text(
                  'DNI: ${_mobilityValue(['dni_conductor', 'conductor_dni'])}'),
              Text('Licencia: ${_mobilityValue(['licencia_conducir'])}'),
              Text('Vigencia: ${_mobilityValue(['licencia_vigencia'])}'),
              Text('SOAT: ${_mobilityValue(['soat_vigencia'])}'),
              Text('Revisión técnica: ${_mobilityValue([
                    'revision_tecnica_vigencia'
                  ])}'),
            ]),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            current.isEmpty
                ? Icons.directions_walk
                : issues.isEmpty
                    ? Icons.verified_outlined
                    : Icons.warning_amber_rounded,
            size: 20,
            color: statusColor,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              mobilityValidationMessage.isEmpty
                  ? 'Seleccione Sin movilidad o una placa registrada.'
                  : mobilityValidationMessage,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
    ]);
  }

  void _setTipoMovimiento(String value) {
    setState(() {
      tipoMovimiento = value;
      final text = value == 'SALIDA' ? 'Salida' : 'Ingreso';
      for (final entry in asistenciaHeader.controllers.entries) {
        final n = _specialNorm(entry.key);
        if (n == 'MOVIMIENTO' ||
            n == 'TIPO_MOVIMIENTO' ||
            n == 'TIPO_MOVIMIENTO_ASISTENCIA') {
          entry.value.text = text;
        }
      }
    });
  }

  Widget _movementButtons(Color primary) {
    final isIngreso = tipoMovimiento == 'INGRESO';
    return Row(children: [
      Expanded(
        child: FilledButton.icon(
          onPressed: () => _setTipoMovimiento('INGRESO'),
          icon: Icon(isIngreso ? Icons.check_circle : Icons.login),
          label: const Text('Ingreso'),
          style: FilledButton.styleFrom(
              backgroundColor: isIngreso ? primary : Colors.grey.shade600),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: FilledButton.icon(
          onPressed: () => _setTipoMovimiento('SALIDA'),
          icon: Icon(!isIngreso ? Icons.check_circle : Icons.logout),
          label: const Text('Salida'),
          style: FilledButton.styleFrom(
              backgroundColor: !isIngreso ? primary : Colors.grey.shade600),
        ),
      ),
    ]);
  }

  Widget _headerCard() {
    final primary = const Color(0xFF0D5F78);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1EEF1)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _movementButtons(primary),
        const SizedBox(height: 14),
        ...asistenciaHeader.buildFields(context, setState,
            filter: _isAsistenciaDateField),
        _mobilitySelector(),
        ...asistenciaHeader.buildFields(context, setState,
            filter: (field) =>
                !_isAsistenciaMovementField(field) &&
                !_isAsistenciaDateField(field) &&
                !_isAsistenciaPlateField(field)),
        const SizedBox(height: 2),
        _workerSearchBox(),
      ]),
    );
  }

  String _attendanceDateLabel() {
    final raw = _headerValue(['FECHA'], fallback: fechaCtrl.text.trim());
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? raw : _dateTitle(parsed);
  }

  Future<void> _openWorkersPage() async {
    await _loadDailyAttendanceRows();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _AttendanceWorkersPage(
          dateLabel: _attendanceDateLabel(),
          rows: scannedRows
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false),
        ),
      ),
    );
  }

  Widget _workersButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: OutlinedButton.icon(
        onPressed: _openWorkersPage,
        icon: const Icon(Icons.groups_2_outlined),
        label: Text(
          scannedRows.isEmpty
              ? 'Ver Trabajadores'
              : 'Ver Trabajadores (${scannedRows.length})',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F7),
      appBar: _zumacFormatAppBar(
        title: const Text(
          'Asistencia de Personal',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        onBack: () {
          if (widget.onSavedAndExit != null) {
            widget.onSavedAndExit!.call();
          } else {
            Navigator.maybePop(context);
          }
        },
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Scrollbar(
            controller: _asistenciaVerticalCtrl,
            thumbVisibility: true,
            child: ListView(
                controller: _asistenciaVerticalCtrl,
                padding: const EdgeInsets.all(18),
                children: [
                  _headerCard(),
                  _workersButton(),
                ]),
          ),
        ),
      ),
    );
  }
}

class _AttendanceWorkerColumn {
  final String label;
  final List<String> keys;
  final double width;

  const _AttendanceWorkerColumn(this.label, this.keys, this.width);
}

class _AttendanceWorkersPage extends StatefulWidget {
  final String dateLabel;
  final List<Map<String, dynamic>> rows;

  const _AttendanceWorkersPage({
    required this.dateLabel,
    required this.rows,
  });

  @override
  State<_AttendanceWorkersPage> createState() => _AttendanceWorkersPageState();
}

class _AttendanceWorkersPageState extends State<_AttendanceWorkersPage> {
  static const double _rowHeight = 58;
  static const double _headerHeight = 56;
  static const double _dniWidth = 126;
  static const _columns = <_AttendanceWorkerColumn>[
    _AttendanceWorkerColumn('Apellidos y nombres',
        ['APELLIDOS Y NOMBRES', 'APELLIDOS_NOMBRES', 'NOMBRE COMPLETO'], 270),
    _AttendanceWorkerColumn(
        'Placa', ['PLACA', 'MOVILIDAD', 'PLACA_MOVILIDAD'], 150),
    _AttendanceWorkerColumn('Reclutador', ['RECLUTADOR'], 180),
    _AttendanceWorkerColumn('Puesto', ['PUESTO', 'CARGO'], 190),
    _AttendanceWorkerColumn(
        'Fecha ingreso', ['FECHA_INGRESO', 'FECHA INGRESO'], 130),
    _AttendanceWorkerColumn(
        'Ingreso (hora)', ['HORA_INGRESO', 'HORA INGRESO'], 120),
    _AttendanceWorkerColumn(
        'Fecha salida', ['FECHA_SALIDA', 'FECHA SALIDA'], 130),
    _AttendanceWorkerColumn(
        'Salida (hora)', ['HORA_SALIDA', 'HORA SALIDA'], 120),
    _AttendanceWorkerColumn(
        'Horas', ['HORAS_ASISTENCIA', 'HORAS ASISTENCIA', 'HORAS'], 100),
  ];

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  String _normalize(String value) => value
      .trim()
      .toUpperCase()
      .replaceAll('Á', 'A')
      .replaceAll('É', 'E')
      .replaceAll('Í', 'I')
      .replaceAll('Ó', 'O')
      .replaceAll('Ú', 'U')
      .replaceAll('Ü', 'U')
      .replaceAll('Ñ', 'N')
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '');

  String _value(Map<String, dynamic> row, Iterable<String> keys) {
    final wanted = keys.map(_normalize).toSet();
    for (final entry in row.entries) {
      if (wanted.contains(_normalize(entry.key))) {
        final value = entry.value?.toString().trim() ?? '';
        if (value.toLowerCase() != 'null') return value;
      }
    }
    return '';
  }

  List<Map<String, dynamic>> get _filteredRows {
    final query = _normalize(_searchController.text);
    if (query.isEmpty) return widget.rows;
    return widget.rows.where((row) {
      return row.values.any(
        (value) => _normalize(value?.toString() ?? '').contains(query),
      );
    }).toList(growable: false);
  }

  Widget _cell({
    required double width,
    required String text,
    required bool header,
    required bool alternate,
  }) {
    return Container(
      width: width,
      height: header ? _headerHeight : _rowHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: header
            ? const Color(0xFF3F5B73)
            : (alternate ? const Color(0xFFF7FAFB) : Colors.white),
        border: const Border(
          right: BorderSide(color: Color(0xFFDDE7EC)),
          bottom: BorderSide(color: Color(0xFFDDE7EC)),
        ),
      ),
      child: Text(
        text.isEmpty && !header ? '—' : text,
        maxLines: header ? 2 : 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: header ? Colors.white : const Color(0xFF263B4A),
          fontSize: header ? 12.5 : 13,
          fontWeight: header ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;
    final scrollingWidth =
        _columns.fold<double>(0, (total, column) => total + column.width);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F7),
      appBar: _zumacFormatAppBar(
        title: Text(
          'Trabajadores - ${widget.dateLabel}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar trabajador',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: Text('No se encontraron trabajadores.'),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFDDE7EC)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Scrollbar(
                            controller: _verticalController,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _verticalController,
                              child: SizedBox(
                                width: constraints.maxWidth,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Material(
                                      elevation: 5,
                                      shadowColor: Colors.black26,
                                      child: Column(
                                        children: [
                                          _cell(
                                            width: _dniWidth,
                                            text: 'DNI',
                                            header: true,
                                            alternate: false,
                                          ),
                                          for (var index = 0;
                                              index < rows.length;
                                              index++)
                                            _cell(
                                              width: _dniWidth,
                                              text: _value(rows[index],
                                                  const ['DNI', 'DOCUMENTO']),
                                              header: false,
                                              alternate: index.isOdd,
                                            ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Scrollbar(
                                        controller: _horizontalController,
                                        thumbVisibility: true,
                                        trackVisibility: true,
                                        scrollbarOrientation:
                                            ScrollbarOrientation.bottom,
                                        notificationPredicate: (notification) =>
                                            notification.metrics.axis ==
                                            Axis.horizontal,
                                        child: SingleChildScrollView(
                                          controller: _horizontalController,
                                          scrollDirection: Axis.horizontal,
                                          padding:
                                              const EdgeInsets.only(bottom: 12),
                                          child: SizedBox(
                                            width: scrollingWidth,
                                            child: Column(
                                              children: [
                                                Row(
                                                  children: [
                                                    for (final column
                                                        in _columns)
                                                      _cell(
                                                        width: column.width,
                                                        text: column.label,
                                                        header: true,
                                                        alternate: false,
                                                      ),
                                                  ],
                                                ),
                                                for (var index = 0;
                                                    index < rows.length;
                                                    index++)
                                                  Row(
                                                    children: [
                                                      for (final column
                                                          in _columns)
                                                        _cell(
                                                          width: column.width,
                                                          text: _value(
                                                              rows[index],
                                                              column.keys),
                                                          header: false,
                                                          alternate:
                                                              index.isOdd,
                                                        ),
                                                    ],
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AsistenciaScannerPage extends StatefulWidget {
  const _AsistenciaScannerPage();
  @override
  State<_AsistenciaScannerPage> createState() => _AsistenciaScannerPageState();
}

class _AsistenciaScannerPageState extends State<_AsistenciaScannerPage> {
  bool returned = false;
  void _returnCode(String raw) {
    final code = raw.trim();
    if (returned || code.isEmpty) return;
    returned = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _zumacFormatAppBar(
        title: const Text('Escanear asistencia'),
      ),
      body: MobileScanner(onDetect: (capture) {
        for (final b in capture.barcodes) {
          final raw = b.rawValue?.trim() ?? '';
          if (raw.isNotEmpty) {
            _returnCode(raw);
            break;
          }
        }
      }),
    );
  }
}

class TareoPersonalDayPage extends StatefulWidget {
  final String moduleId;
  final Map<String, dynamic> format;
  final VoidCallback? onLocalChanged;
  final VoidCallback? onBack;

  const TareoPersonalDayPage({
    super.key,
    required this.moduleId,
    required this.format,
    this.onLocalChanged,
    this.onBack,
  });

  @override
  State<TareoPersonalDayPage> createState() => _TareoPersonalDayPageState();
}

class _TareoPersonalDayPageState extends State<TareoPersonalDayPage> {
  final local = LocalDb.instance;
  late DateTime selectedDate;
  List<TareoDayGroup> groups = const [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedDate = DateTime(now.year, now.month, now.day);
    _load();
  }

  String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  Future<void> _load() async {
    if (mounted) setState(() => loading = true);
    final session = LocalSession();
    final userId = Supabase.instance.client.auth.currentUser?.id ??
        await session.cachedUserId();
    final empresaId = await session.cachedEmpresaId();
    final rows = await local.allRecords(
      userId: userId,
      empresaId: empresaId,
    );
    final formatId = widget.format['id']?.toString() ?? '';
    final scoped = rows.where((row) {
      if ((row['tabla_destino']?.toString() ?? '').toUpperCase() !=
          'GT-TAREO_PERSONAL') return false;
      final rowFormat = row['formato_id']?.toString() ?? '';
      return formatId.isEmpty || rowFormat.isEmpty || rowFormat == formatId;
    });
    final loaded = groupTareoQueueRows(scoped, fecha: _dateIso(selectedDate));
    if (!mounted) return;
    setState(() {
      groups = loaded;
      loading = false;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _safeDatePickerInitialDate(selectedDate, yesterday, today),
      firstDate: yesterday,
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    setState(
        () => selectedDate = DateTime(picked.year, picked.month, picked.day));
    await _load();
  }

  Future<void> _openForm({TareoDayGroup? group, bool close = false}) async {
    final initialPayload = group == null
        ? <String, dynamic>{'FECHA': _dateIso(selectedDate)}
        : group.editPayload;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TareoPersonalSpecialPage(
        moduleId: widget.moduleId,
        format: widget.format,
        initialPayload: initialPayload,
        editIdLocal: group?.idLocal,
        closeOnSave: close,
        onLocalChanged: () {
          widget.onLocalChanged?.call();
          _load();
        },
        onSavedAndExit: widget.onLocalChanged,
      ),
    ));
    await _load();
  }

  Future<void> _showActions(TareoDayGroup group) async {
    if (group.closed) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_rounded,
                  size: 42, color: Color(0xFF31552F)),
              const SizedBox(height: 12),
              Text(group.synchronized ? 'Tareo enviado' : 'Tareo cerrado',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                group.synchronized
                    ? 'Este tareo ya fue enviado a la nube y no se puede modificar.'
                    : 'Este tareo ya fue cerrado y no se puede modificar.',
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
      );
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar tareo'),
              subtitle: const Text('Modificar labor, personal u horas'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_clock_outlined,
                  color: Color(0xFF31552F)),
              title: const Text('Cerrar tareo'),
              subtitle: const Text('Revisar horas y confirmar el cierre'),
              onTap: () => Navigator.pop(sheetContext, 'close'),
            ),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') await _openForm(group: group);
    if (action == 'close') await _openForm(group: group, close: true);
  }

  String _statusLabel(TareoDayGroup group) => group.synchronized
      ? 'Enviado'
      : group.closed
          ? 'Cerrado'
          : 'Pendiente';

  Widget _summaryLine(String label, String value) => Text(
        '$label: $value',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 13.5,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: Color(0xFF263B4A),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = selectedDate == today;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F7),
      appBar: _zumacFormatAppBar(
        title: const Text(
          'Tareo de personal',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        onBack: widget.onBack,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            child: InkWell(
              onTap: _pickDate,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_outlined,
                        size: 20, color: _zumacFormatBlue),
                    const SizedBox(width: 9),
                    Text(
                      _dateLabel(selectedDate),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _zumacFormatBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: loading
                  ? ListView(children: const [
                      SizedBox(height: 220),
                      Center(child: CircularProgressIndicator()),
                    ])
                  : groups.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 150),
                          Icon(Icons.assignment_outlined,
                              size: 58, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text('Sin tareos aún',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(
                            isToday
                                ? 'Agrega el primer tareo del día.'
                                : 'No registraste tareos en esta fecha.',
                            textAlign: TextAlign.center,
                          ),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
                          itemCount: groups.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final group = groups[index];
                            final people = group.peopleCount;
                            return Card(
                              margin: EdgeInsets.zero,
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _showActions(group),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _summaryLine(
                                        'Labor',
                                        group.labor.isEmpty
                                            ? 'Sin labor'
                                            : group.labor,
                                      ),
                                      _summaryLine(
                                        'Cc',
                                        group.centroCosto.isEmpty
                                            ? 'Sin centro de costo'
                                            : group.centroCosto,
                                      ),
                                      _summaryLine(
                                        'Persona',
                                        '$people ${people == 1 ? 'persona' : 'personas'}',
                                      ),
                                      _summaryLine(
                                        'Estado',
                                        _statusLabel(group),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Agregar nuevo tareo',
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class TareoPersonalSpecialPage extends StatefulWidget {
  final String moduleId;
  final Map<String, dynamic> format;
  final Map<String, dynamic>? initialPayload;
  final String? editIdLocal;
  final bool closeOnSave;
  final VoidCallback? onLocalChanged;
  final VoidCallback? onSavedAndExit;

  const TareoPersonalSpecialPage({
    super.key,
    required this.moduleId,
    required this.format,
    this.initialPayload,
    this.editIdLocal,
    this.closeOnSave = false,
    this.onLocalChanged,
    this.onSavedAndExit,
  });

  @override
  State<TareoPersonalSpecialPage> createState() =>
      _TareoPersonalSpecialPageState();
}

class _TareoPersonalSpecialPageState extends State<TareoPersonalSpecialPage> {
  final local = LocalDb.instance;
  final uuid = const Uuid();
  final fechaCtrl = TextEditingController();
  final laborCtrl = TextEditingController();
  final turnoCtrl = TextEditingController();
  final variedadCtrl = TextEditingController();
  final areaCtrl = TextEditingController();
  final centroCostoCtrl = TextEditingController();
  final trabajadorCtrl = TextEditingController();
  final horaInicioCtrl = TextEditingController();
  final horaFinCtrl = TextEditingController();
  final observacionCtrl = TextEditingController();
  late final _SpecialMatrixHeader tareoHeader;

  List<Map<String, dynamic>> fields = [];
  List<Map<String, dynamic>> workers = [];
  List<Map<String, dynamic>> lotesVariedades = [];
  final List<Map<String, dynamic>> selectedWorkers = [];
  bool showHours = false;
  bool showObservation = false;
  bool saving = false;
  String draftIdLocal = '';

  @override
  void initState() {
    super.initState();
    showHours = widget.closeOnSave;
    final now = DateTime.now();
    fechaCtrl.text = _dateIso(now);
    horaInicioCtrl.text = _timeHm(now);
    tareoHeader = _SpecialMatrixHeader(local, 'GT-CABECERA_TAREO_PERSONAL');
    final rawDraftId = widget.editIdLocal ??
        widget.initialPayload?['id_local']?.toString() ??
        uuid.v4();
    draftIdLocal = rawDraftId.replaceFirst(RegExp(r'_[0-9]+$'), '');
    _load();
  }

  @override
  void dispose() {
    fechaCtrl.dispose();
    laborCtrl.dispose();
    turnoCtrl.dispose();
    variedadCtrl.dispose();
    areaCtrl.dispose();
    centroCostoCtrl.dispose();
    trabajadorCtrl.dispose();
    horaInicioCtrl.dispose();
    horaFinCtrl.dispose();
    observacionCtrl.dispose();
    tareoHeader.dispose();
    super.dispose();
  }

  String _dateIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _timeHm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _digits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');
  String _norm(String v) {
    var s = v.trim().toUpperCase();
    const map = {
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'Ü': 'U',
      'Ñ': 'N'
    };
    map.forEach((k, value) => s = s.replaceAll(k, value));
    return s
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  dynamic _rowValue(Map<String, dynamic> row, List<String> keys) {
    final wanted = keys.map(_norm).toSet();
    for (final e in row.entries) {
      if (wanted.contains(_norm(e.key))) return e.value;
    }
    return null;
  }

  Future<Set<String>> _destinationFieldNorms(String table,
      {Iterable<String> extra = const []}) async {
    final rows =
        await local.where('local_form_fields', 'tabla_destino = ?', [table]);
    final out = extra.map(_norm).toSet();
    for (final row in rows) {
      final campo = row['campo']?.toString().trim() ?? '';
      if (campo.isNotEmpty) out.add(_norm(campo));
    }
    return out;
  }

  Future<List<Map<String, String>>> _workersWithoutAttendanceForDay() async {
    final fecha = tareoHeader
        .valueByCandidates(['FECHA'], fallback: fechaCtrl.text.trim()).trim();
    if (fecha.isEmpty || selectedWorkers.isEmpty) return const [];
    final attended = <String>{};
    final rows = await local.allRecords();
    for (final r in rows) {
      final table = (r['tabla_destino']?.toString() ?? '').toUpperCase();
      if (table != 'GT-ASISTENCIA_PERSONAL') continue;
      try {
        final payload = jsonDecode(r['payload_json']?.toString() ?? '{}')
            as Map<String, dynamic>;
        if (isSoftDeletedAppgtRow(payload)) continue;
        final rowFecha = (_rowValue(payload, ['FECHA', 'FECHA_INGRESO']) ?? '')
            .toString()
            .trim();
        if (rowFecha != fecha) continue;
        final dni = _digits(
            (_rowValue(payload, ['DNI', 'Dni', 'DOCUMENTO']) ?? '').toString());
        if (dni.isNotEmpty) attended.add(dni);
      } catch (_) {}
    }
    final missing = <Map<String, String>>[];
    for (final w in selectedWorkers) {
      final dniRaw = (w['DNI']?.toString() ?? '').trim();
      final dni = _digits(dniRaw);
      if (dni.isEmpty || attended.contains(dni)) continue;
      final name = (w['APELLIDOS Y NOMBRES']?.toString() ?? '').trim();
      missing.add({
        'dni': dni,
        'label': name.isEmpty ? dniRaw : '$dniRaw - $name',
      });
    }
    return missing;
  }

  Map<String, dynamic> _filterPayloadForNorms(
      Map<String, dynamic> payload, Set<String> allowed) {
    final out = <String, dynamic>{};
    for (final entry in payload.entries) {
      final key = entry.key.toString();
      if (allowed.contains(_norm(key))) out[key] = entry.value;
    }
    return out;
  }

  Future<void> _load() async {
    await tareoHeader.load(initialPayload: widget.initialPayload);
    final requestedDate = widget.initialPayload == null
        ? ''
        : (_rowValue(widget.initialPayload!, ['FECHA']) ?? '')
            .toString()
            .trim();
    if (requestedDate.isNotEmpty) {
      for (final entry in tareoHeader.controllers.entries) {
        if (_norm(entry.key) == 'FECHA') entry.value.text = requestedDate;
      }
      fechaCtrl.text = requestedDate;
    }
    final fs = tareoHeader.fields;
    final planilla = await local.where('local_matrix_rows', 'source_table = ?',
        ['GH-REGISTRO_PERSONAL_PLANILLA']);
    final loadedWorkers = <Map<String, dynamic>>[];
    for (final r in planilla) {
      try {
        final payload = jsonDecode(r['payload_json']?.toString() ?? '{}')
            as Map<String, dynamic>;
        if (!isSoftDeletedAppgtRow(payload)) loadedWorkers.add(payload);
      } catch (_) {}
    }

    final loadedLotes = <Map<String, dynamic>>[];
    for (final source in ['LOTES_VARIEDADES_GT', 'LOTES-VARIEDADES-GT']) {
      final rows =
          await local.where('local_matrix_rows', 'source_table = ?', [source]);
      for (final r in rows) {
        try {
          final payload = jsonDecode(r['payload_json']?.toString() ?? '{}');
          if (payload is Map<String, dynamic>) {
            if (!isSoftDeletedAppgtRow(payload)) loadedLotes.add(payload);
          } else if (payload is Map) {
            final mapped = Map<String, dynamic>.from(payload);
            if (!isSoftDeletedAppgtRow(mapped)) loadedLotes.add(mapped);
          }
        } catch (_) {}
      }
    }

    if (widget.initialPayload != null)
      _hydrateFromPayload(widget.initialPayload!);
    final fecha = tareoHeader
        .valueByCandidates(['FECHA'], fallback: fechaCtrl.text.trim());
    if (fecha.isNotEmpty) fechaCtrl.text = fecha;
    final hi = tareoHeader.valueByCandidates(['HORA_INICIO', 'HORA INICIO'],
        fallback: horaInicioCtrl.text.trim());
    if (hi.isNotEmpty) horaInicioCtrl.text = hi;
    final hf = tareoHeader.valueByCandidates(['HORA_FIN', 'HORA FIN'],
        fallback: horaFinCtrl.text.trim());
    if (hf.isNotEmpty) horaFinCtrl.text = hf;
    final observation = tareoHeader.valueByCandidates(
      ['OBSERVACION', 'OBSERVACIÓN'],
      fallback: observacionCtrl.text.trim(),
    );
    if (observation.isNotEmpty) observacionCtrl.text = observation;
    if (mounted)
      setState(() {
        fields = fs;
        workers = loadedWorkers;
        lotesVariedades = loadedLotes;
      });
  }

  void _hydrateFromPayload(Map<String, dynamic> p) {
    fechaCtrl.text = (_rowValue(p, ['FECHA']) ?? fechaCtrl.text).toString();
    laborCtrl.text = (_rowValue(p, ['LABOR']) ?? '').toString();
    turnoCtrl.text = (_rowValue(p, ['TURNO']) ?? '').toString();
    variedadCtrl.text = (_rowValue(p, ['VARIEDAD']) ?? '').toString();
    areaCtrl.text = (_rowValue(p, ['AREA']) ?? '').toString();
    centroCostoCtrl.text =
        (_rowValue(p, ['CENTRO_COSTO', 'CENTRO COSTO']) ?? '').toString();
    horaInicioCtrl.text =
        (_rowValue(p, ['HORA_INICIO', 'HORA_INCIO', 'HORA INICIO']) ??
                horaInicioCtrl.text)
            .toString();
    horaFinCtrl.text =
        (_rowValue(p, ['HORA_FIN', 'HORA FIN']) ?? '').toString();
    observacionCtrl.text =
        (_rowValue(p, ['OBSERVACION', 'OBSERVACIÓN']) ?? '').toString();
    final raw = p['__TRABAJADORES__'] ?? p['__tareo_rows'];
    if (raw is List) {
      selectedWorkers
        ..clear()
        ..addAll(raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
    } else {
      final dni = (_rowValue(p, ['DNI']) ?? '').toString();
      final nombre = (_rowValue(p, ['APELLIDOS Y NOMBRES']) ?? '').toString();
      if (dni.isNotEmpty || nombre.isNotEmpty)
        selectedWorkers.add({'DNI': dni, 'APELLIDOS Y NOMBRES': nombre});
    }
  }

  Map<String, dynamic>? _field(String campo) {
    final n = _norm(campo);
    for (final f in fields) {
      if (_norm(f['campo']?.toString() ?? '') == n ||
          _norm(f['etiqueta']?.toString() ?? '') == n) return f;
    }
    return null;
  }

  List<String> _dropdownOptions(String campo) {
    final raw = _field(campo)?['id_campo_dropdown']?.toString().trim() ?? '';
    if (raw.isEmpty) return const [];
    final clean = raw.startsWith('[') && raw.endsWith(']')
        ? raw.substring(1, raw.length - 1)
        : raw;
    return clean
        .split(RegExp(r'[;,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  Widget _matrixField(String label, TextEditingController ctrl,
      {String? displayLabel, bool readOnly = false}) {
    final visibleLabel = displayLabel ?? label;
    final opts = _dropdownOptions(label);
    if (opts.isNotEmpty && !readOnly) {
      return _searchableSelectField(
        label: visibleLabel,
        controller: ctrl,
        options: opts,
        onSelected: (_) {},
      );
    }
    return TextField(
      controller: ctrl,
      readOnly: readOnly,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: visibleLabel,
        border: const OutlineInputBorder(),
        suffixIcon: readOnly ? const Icon(Icons.lock_outline) : null,
      ),
    );
  }

  List<String> _loteOptions() {
    final out = <String>{};
    for (final row in lotesVariedades) {
      final value = (_rowValue(row, ['TURNO', 'LOTE']) ?? '').toString().trim();
      if (value.isNotEmpty) out.add(value);
    }
    final list = out.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  void _setVariedadFromLote(String? lote) {
    final selected = (lote ?? '').trim().toLowerCase();
    if (selected.isEmpty) {
      variedadCtrl.clear();
      return;
    }
    for (final row in lotesVariedades) {
      final turno = (_rowValue(row, ['TURNO', 'LOTE']) ?? '').toString().trim();
      if (turno.toLowerCase() != selected) continue;
      variedadCtrl.text =
          (_rowValue(row, ['VARIEDAD']) ?? '').toString().trim();
      return;
    }
  }

  Future<String?> _showSearchablePicker(
      {required String title,
      required List<String> options,
      String? currentValue}) async {
    final unique = <String>[];
    final seen = <String>{};
    for (final option in options) {
      final value = option.trim();
      if (value.isEmpty) continue;
      if (seen.add(value.toLowerCase())) unique.add(value);
    }
    unique.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final searchCtrl = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          var filtered = List<String>.from(unique);
          return AlertDialog(
            backgroundColor: const Color(0xFFF4F8F7),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Text(title,
                style: const TextStyle(
                    color: Color(0xFF0D5F78), fontWeight: FontWeight.w800)),
            content: SizedBox(
              width: 430,
              child: StatefulBuilder(
                builder: (context, setLocalState) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchCtrl,
                      autofocus: false,
                      decoration: const InputDecoration(
                        labelText: 'Buscar',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        final q = value.trim().toLowerCase();
                        setLocalState(() {
                          filtered = q.isEmpty
                              ? List<String>.from(unique)
                              : unique
                                  .where((e) => e.toLowerCase().contains(q))
                                  .toList();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: filtered.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No hay coincidencias.'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final option = filtered[index];
                                final selected = option == currentValue;
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.list_alt_outlined,
                                      color: Color(0xFF2E6B37)),
                                  title: Text(option,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  trailing: selected
                                      ? const Icon(Icons.check,
                                          color: Color(0xFF2E6B37))
                                      : null,
                                  onTap: () =>
                                      Navigator.pop(dialogContext, option),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar')),
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, ''),
                  child: const Text('Limpiar')),
            ],
          );
        },
      );
    } finally {
      searchCtrl.dispose();
    }
  }

  Widget _searchableSelectField({
    required String label,
    required TextEditingController controller,
    required List<String> options,
    required void Function(String?) onSelected,
  }) {
    final current = controller.text.trim();
    final hasValue = current.isNotEmpty;
    return InkWell(
      onTap: () async {
        final selected = await _showSearchablePicker(
            title: label,
            options: options,
            currentValue: hasValue ? current : null);
        if (selected == null) return;
        setState(() {
          controller.text = selected;
          onSelected(selected);
        });
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.search),
          helperText: options.isEmpty
              ? 'Sin valores locales. Presiona Actualizar con internet.'
              : null,
        ),
        child: Text(
          hasValue ? current : 'Seleccione o busque...',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: hasValue ? null : Colors.grey[600]),
        ),
      ),
    );
  }

  Widget _loteField() {
    return _searchableSelectField(
      label: 'LOTE',
      controller: turnoCtrl,
      options: _loteOptions(),
      onSelected: _setVariedadFromLote,
    );
  }

  Future<void> _pickTime(TextEditingController controller) async {
    final parts = controller.text.trim().split(':');
    final initial = parts.length >= 2
        ? TimeOfDay(
            hour: int.tryParse(parts[0]) ?? TimeOfDay.now().hour,
            minute: int.tryParse(parts[1]) ?? TimeOfDay.now().minute)
        : TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() => controller.text =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<String> _activeUserName() async {
    final session = LocalSession();
    final userId = (Supabase.instance.client.auth.currentUser?.id ??
                await session.cachedUserId())
            ?.trim() ??
        '';
    final login =
        (await session.cachedLoginIdentifier())?.trim().toLowerCase() ?? '';
    final aliases = (await session.cachedLoginAliases())
        .map((e) => e.trim().toLowerCase())
        .toSet();
    final profiles = await local.getAll('local_profile');
    for (final p in profiles) {
      final id = p['id']?.toString().trim() ?? '';
      final dni = p['dni']?.toString().trim().toLowerCase() ?? '';
      final email = p['email']?.toString().trim().toLowerCase() ?? '';
      final matches = (userId.isNotEmpty && id == userId) ||
          (login.isNotEmpty && (login == dni || login == email)) ||
          aliases.contains(dni) ||
          aliases.contains(email);
      if (!matches) continue;
      final name = p['nombres']?.toString().trim() ?? '';
      if (name.isNotEmpty) return name;
    }
    return '';
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final min = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 1));
    final max = DateTime(today.year, today.month, today.day);
    final current = DateTime.tryParse(fechaCtrl.text) ?? max;
    final picked = await showDatePicker(
        context: context,
        initialDate: _safeDatePickerInitialDate(current, min, max),
        firstDate: min,
        lastDate: max);
    if (picked != null) setState(() => fechaCtrl.text = _dateIso(picked));
  }

  Map<String, dynamic>? _findWorker(String text) {
    final q = text.trim().toLowerCase();
    final qDigits = _digits(q);
    if (q.isEmpty) return null;
    for (final w in workers) {
      final dni = (_rowValue(w, ['DNI', 'Dni', 'DOCUMENTO']) ?? '').toString();
      final nombre = (_rowValue(w, [
                'APELLIDOS Y NOMBRES',
                'Apellidos y Nombres',
                'NOMBRE COMPLETO'
              ]) ??
              '')
          .toString();
      final haystack = '$dni $nombre'.toLowerCase();
      if ((qDigits.isNotEmpty && _digits(dni).contains(qDigits)) ||
          haystack.contains(q)) return w;
    }
    return null;
  }

  Future<void> _addWorker(Map<String, dynamic> w) async {
    final dni =
        (_rowValue(w, ['DNI', 'Dni', 'DOCUMENTO']) ?? '').toString().trim();
    if (dni.isEmpty) return;
    final normalizedDni = _digits(dni);
    if (selectedWorkers
        .any((e) => _digits(e['DNI']?.toString() ?? '') == normalizedDni)) {
      await _showAppGtAlert(
        context,
        'El trabajador con DNI $dni ya está considerado en este tareo.',
        title: 'Trabajador ya considerado',
        icon: Icons.info_outline_rounded,
        playSound: true,
      );
      return;
    }
    final nombre = (_rowValue(w, [
              'APELLIDOS Y NOMBRES',
              'Apellidos y Nombres',
              'NOMBRE COMPLETO'
            ]) ??
            '')
        .toString()
        .trim();
    setState(() {
      selectedWorkers.add({'DNI': dni, 'APELLIDOS Y NOMBRES': nombre});
      trabajadorCtrl.clear();
    });
  }

  Future<void> _openQr() async {
    final code = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const _AsistenciaScannerPage()));
    if (code == null || code.trim().isEmpty) return;
    final w = _findWorker(code) ?? _findWorker(_digits(code));
    if (w == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Trabajador no encontrado: $code')));
      return;
    }
    await _addWorker(w);
  }

  double? _hoursBetween(String ingreso, String salida) {
    if (salida.trim().isEmpty) return null;
    try {
      final i = ingreso.split(':');
      final s = salida.split(':');
      final a = DateTime(2000, 1, 1, int.parse(i[0]), int.parse(i[1]));
      var b = DateTime(2000, 1, 1, int.parse(s[0]), int.parse(s[1]));
      if (b.isBefore(a)) b = b.add(const Duration(days: 1));
      return double.parse((b.difference(a).inMinutes / 60).toStringAsFixed(2));
    } catch (_) {
      return null;
    }
  }

  Future<double> _existingTareoHours(String dni, String fecha) async {
    var total = 0.0;
    for (final record in await local.allRecords()) {
      if ((record['tabla_destino']?.toString() ?? '').toUpperCase() !=
          'GT-TAREO_PERSONAL') {
        continue;
      }
      final id = record['id_local']?.toString() ?? '';
      if (id == draftIdLocal || id.startsWith('${draftIdLocal}_')) continue;
      try {
        final payload = jsonDecode(record['payload_json']?.toString() ?? '{}');
        if (payload is! Map) continue;
        final row = Map<String, dynamic>.from(payload);
        if (isSoftDeletedAppgtRow(row)) continue;
        final rowDni = _digits(
          (_rowValue(row, ['DNI', 'DOCUMENTO']) ?? '').toString(),
        );
        final rowDate = (_rowValue(row, ['FECHA']) ?? '').toString().trim();
        final state = _norm(
          (_rowValue(row, ['ESTADO_APROBACION']) ?? 'BORRADOR').toString(),
        );
        if (rowDni != _digits(dni) ||
            rowDate != fecha ||
            state == 'RECHAZADO' ||
            state == 'ANULADO') {
          continue;
        }
        total += double.tryParse(
              (_rowValue(row, ['HORAS_TRABAJADAS']) ?? '0')
                  .toString()
                  .replaceAll(',', '.'),
            ) ??
            0;
      } catch (_) {}
    }
    return total;
  }

  Future<String?> _requestOvertimeReason(double maxOvertime) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Autorización de horas extra'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Este tareo genera hasta ${maxOvertime.toStringAsFixed(2)} '
                'hora(s) extra por trabajador. Indique el motivo para enviar '
                'la solicitud de autorización.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo de horas extra',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) return;
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Solicitar y cerrar'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<bool> _confirmShortWorkday(
    Map<String, double> dailyHoursByDni,
  ) async {
    final shortWorkers =
        dailyHoursByDni.entries.where((entry) => entry.value < 8).map((entry) {
      final worker = selectedWorkers.cast<Map<String, dynamic>?>().firstWhere(
            (item) =>
                _digits(item?['DNI']?.toString() ?? '') == _digits(entry.key),
            orElse: () => null,
          );
      final name = worker?['APELLIDOS Y NOMBRES']?.toString().trim() ?? '';
      return (
        dni: entry.key,
        name: name,
        hours: entry.value,
        missing: tareoHoursMissingForFullDay(entry.value),
      );
    }).toList(growable: false);
    if (shortWorkers.isEmpty) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
            SizedBox(width: 10),
            Expanded(child: Text('Jornada menor a 8 horas')),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Los siguientes trabajadores no completan 8 horas acumuladas '
                'en la fecha del tareo:',
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: shortWorkers.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, index) {
                    final worker = shortWorkers[index];
                    final label = worker.name.isEmpty
                        ? worker.dni
                        : '${worker.dni} - ${worker.name}';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule_outlined),
                      title: Text(label),
                      subtitle: Text(
                        '${worker.hours.toStringAsFixed(2)} h registradas · '
                        'faltan ${worker.missing.toStringAsFixed(2)} h',
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Puedes volver para completar otro tareo o cerrar de todas '
                'formas si la jornada corta es correcta.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Volver y corregir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cerrar de todas formas'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  bool _timeEndsBeforeStart(String start, String end) {
    try {
      final startParts = start.trim().split(':');
      final endParts = end.trim().split(':');
      if (startParts.length < 2 || endParts.length < 2) return false;
      final startMinutes =
          int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
      return endMinutes < startMinutes;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _confirmOvernightShift(String horaInicio, String horaFin) async {
    if (!_timeEndsBeforeStart(horaInicio, horaFin)) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Horario nocturno'),
        content: Text(
          'La hora de fin ($horaFin) es menor que la hora de inicio '
          '($horaInicio). ¿Son horas nocturnas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('No, corregir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sí, continuar'),
          ),
        ],
      ),
    );
    if (confirmed == true) return true;

    horaFinCtrl.clear();
    for (final entry in tareoHeader.controllers.entries) {
      if (_norm(entry.key) == 'HORA_FIN') entry.value.clear();
    }
    if (mounted) {
      setState(() => showHours = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Corrige la HORA_FIN para continuar.')),
      );
    }
    return false;
  }

  bool _isTareoTimeField(Map<String, dynamic> field) {
    final campo = _norm(field['campo']?.toString() ?? '');
    return campo == 'HORA_INICIO' ||
        campo == 'HORA_FIN' ||
        campo == 'HORA_INCIO';
  }

  bool _isTareoObservationField(Map<String, dynamic> field) {
    final campo = _norm(field['campo']?.toString() ?? '');
    return campo == 'OBSERVACION';
  }

  Map<String, dynamic> _tareoHeaderPayload() {
    final payload = tareoHeader.payload();
    final hi = tareoHeader.valueByCandidates(
        ['HORA_INICIO', 'HORA INICIO', 'HORA_INCIO'],
        fallback: horaInicioCtrl.text.trim());
    final hf = tareoHeader.valueByCandidates(['HORA_FIN', 'HORA FIN'],
        fallback: horaFinCtrl.text.trim());
    if (hi.isNotEmpty) payload['HORA_INICIO'] = hi;
    if (hf.isNotEmpty) payload['HORA_FIN'] = hf;
    final observation = tareoHeader.valueByCandidates(
      ['OBSERVACION', 'OBSERVACIÓN'],
      fallback: observacionCtrl.text.trim(),
    );
    if (observation.isNotEmpty) payload['OBSERVACION'] = observation;
    return payload;
  }

  Future<void> _saveDraft({bool closeTareo = false}) async {
    if (selectedWorkers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agrega al menos un trabajador.')));
      return;
    }
    final userId = Supabase.instance.client.auth.currentUser?.id ??
        await LocalSession().cachedUserId();
    if (!mounted) return;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay usuario local para guardar tareo.')));
      return;
    }
    final missingAttendance = await _workersWithoutAttendanceForDay();
    if (!mounted) return;
    if (missingAttendance.isNotEmpty) {
      final removedDnis =
          await _showMissingAttendanceAlert(context, missingAttendance);
      if (removedDnis == null || !mounted) return;
      if (removedDnis.isNotEmpty) {
        setState(() {
          selectedWorkers.removeWhere((worker) =>
              removedDnis.contains(_digits(worker['DNI']?.toString() ?? '')));
        });
        if (selectedWorkers.isEmpty) {
          await _showAppGtAlert(
            context,
            'No queda personal en el tareo. Agrega al menos un trabajador para continuar.',
            title: 'Tareo sin personal',
            icon: Icons.group_off_outlined,
          );
          return;
        }
      }
    }
    final tareador = await _activeUserName();
    if (!mounted) return;
    final headerPayload = _tareoHeaderPayload();
    final horaInicio = headerPayload['HORA_INICIO']?.toString().trim() ?? '';
    final horaFin = headerPayload['HORA_FIN']?.toString().trim() ?? '';
    if (!await _confirmOvernightShift(horaInicio, horaFin)) return;
    if (!mounted) return;
    final horasMatriz =
        tareoHeader.valueByCandidates(['HORAS_TRABAJADAS', 'HORAS TRABAJADAS']);
    final horas = horasMatriz.trim().isNotEmpty
        ? horasMatriz.trim()
        : _hoursBetween(horaInicio, horaFin);
    if (closeTareo && (horaFin.isEmpty || horas == null)) {
      setState(() => showHours = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Complete HORA_FIN antes de cerrar el tareo.'),
      ));
      return;
    }
    final currentHours = double.tryParse(
          (horas ?? 0).toString().replaceAll(',', '.'),
        ) ??
        0;
    final fecha = tareoHeader
        .valueByCandidates(['FECHA'], fallback: fechaCtrl.text.trim());
    final overtimeByDni = <String, double>{};
    final dailyHoursByDni = <String, double>{};
    if (closeTareo) {
      for (final worker in selectedWorkers) {
        final dni = worker['DNI']?.toString().trim() ?? '';
        final previous = await _existingTareoHours(dni, fecha);
        final dailyHours = previous + currentHours;
        dailyHoursByDni[dni] = dailyHours;
        overtimeByDni[dni] = (dailyHours - 8).clamp(0, double.infinity);
      }
    }
    if (closeTareo &&
        dailyHoursByDni.isNotEmpty &&
        (!mounted || !await _confirmShortWorkday(dailyHoursByDni))) {
      return;
    }
    final maxOvertime = overtimeByDni.values.fold<double>(
      0,
      (maximum, value) => value > maximum ? value : maximum,
    );
    String? overtimeReason;
    if (maxOvertime > 0) {
      overtimeReason = await _requestOvertimeReason(maxOvertime);
      if (overtimeReason == null || !mounted) return;
    }
    final basePayloadRaw = <String, dynamic>{
      ...headerPayload,
      'FECHA': tareoHeader
          .valueByCandidates(['FECHA'], fallback: fechaCtrl.text.trim()),
      'CENTRO_COSTO': tareoHeader.valueByCandidates(
          ['CENTRO_COSTO', 'CENTRO COSTO'],
          fallback: centroCostoCtrl.text.trim()),
      'LABOR': tareoHeader
          .valueByCandidates(['LABOR'], fallback: laborCtrl.text.trim()),
      'VARIEDAD': tareoHeader
          .valueByCandidates(['VARIEDAD'], fallback: variedadCtrl.text.trim()),
      'HORA_INICIO': horaInicio,
      'HORA_FIN': horaFin,
      'HORAS_TRABAJADAS': horas,
      'TAREADOR': tareador,
      'estado_registro': closeTareo ? 'COMPLETO' : 'PENDIENTE',
    };
    final allowed = await _destinationFieldNorms('GT-TAREO_PERSONAL', extra: [
      'id_local',
      'FECHA',
      'CENTRO_COSTO',
      'LABOR',
      'VARIEDAD',
      'OBSERVACION',
      'HORA_INICIO',
      'HORA_FIN',
      'HORAS_TRABAJADAS',
      'TAREADOR',
      'DNI',
      'APELLIDOS Y NOMBRES',
      'ESTADO_APROBACION',
      'REQUIERE_HORAS_EXTRA',
      'HORAS_EXTRA_SOLICITADAS',
      'MOTIVO_HORAS_EXTRA',
      'ESTADO_HORAS_EXTRA',
      'CERRADO_POR',
      'CERRADO_AT',
      'estado_registro'
    ]);
    final basePayload = _filterPayloadForNorms(basePayloadRaw, allowed);
    setState(() => saving = true);
    try {
      await local.deletePendingRecordsByPrefix(draftIdLocal);
      final createdAt = DateTime.now().toIso8601String();
      for (var i = 0; i < selectedWorkers.length; i++) {
        final worker = selectedWorkers[i];
        final rowIdLocal = selectedWorkers.length == 1
            ? draftIdLocal
            : '${draftIdLocal}_${i + 1}';
        final payload = <String, dynamic>{
          ...basePayload,
          'id_local': rowIdLocal,
          'DNI': worker['DNI']?.toString().trim() ?? '',
          'APELLIDOS Y NOMBRES':
              worker['APELLIDOS Y NOMBRES']?.toString().trim() ?? '',
          'ESTADO_APROBACION': closeTareo ? 'CERRADO' : 'BORRADOR',
          'REQUIERE_HORAS_EXTRA':
              (overtimeByDni[worker['DNI']?.toString().trim() ?? ''] ?? 0) > 0,
          'HORAS_EXTRA_SOLICITADAS':
              overtimeByDni[worker['DNI']?.toString().trim() ?? ''] ?? 0,
          'MOTIVO_HORAS_EXTRA': overtimeReason,
          'ESTADO_HORAS_EXTRA':
              (overtimeByDni[worker['DNI']?.toString().trim() ?? ''] ?? 0) > 0
                  ? 'SOLICITADO'
                  : 'NO_REQUIERE',
        };
        await local.insertPending({
          'id_local': rowIdLocal,
          'user_id': userId,
          'modulo_id': widget.moduleId,
          'formato_id': widget.format['id'],
          'formato_tabla_id': null,
          'tabla_destino': 'GT-TAREO_PERSONAL',
          'payload_json': jsonEncode(payload),
          'estado': 'pendiente',
          'intentos': 0,
          'created_at': createdAt,
          'created_by': tareador,
        });
      }
      var sent = false;
      String? sendFailure;
      if (closeTareo && isOnlineFirstRuntime) {
        try {
          final syncService = SyncService();
          await syncService.syncPending();
          final storedRows = await local.allRecords(userId: userId);
          final tareoRows = storedRows.where((row) {
            final id = row['id_local']?.toString() ?? '';
            return id == draftIdLocal || id.startsWith('${draftIdLocal}_');
          }).toList(growable: false);
          sent = tareoRows.isNotEmpty &&
              tareoRows.every((row) =>
                  row['estado']?.toString().toLowerCase() == 'sincronizado');
          if (!sent) {
            sendFailure = 'el servidor no confirmó el envío';
          }
        } catch (error) {
          sendFailure = SyncService().friendlyError(error);
        }
      }
      widget.onLocalChanged?.call();
      if (mounted) {
        final String message;
        if (!closeTareo) {
          message = 'Tareo guardado como borrador.';
        } else if (sent) {
          message = 'Tareo cerrado y enviado.';
        } else if (isOnlineFirstRuntime) {
          message =
              'Tareo cerrado, pero no se pudo enviar: ${sendFailure ?? 'inténtalo nuevamente'}.';
        } else {
          message = 'Tareo cerrado. Sincronízalo para enviarlo.';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
        ));
        widget.onSavedAndExit?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo guardar tareo local: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _workersPicker() {
    final options = trabajadorCtrl.text.trim().isEmpty
        ? workers.take(20).toList()
        : workers
            .where((w) {
              final dni =
                  (_rowValue(w, ['DNI', 'Dni', 'DOCUMENTO']) ?? '').toString();
              final nombre = (_rowValue(w, [
                        'APELLIDOS Y NOMBRES',
                        'Apellidos y Nombres',
                        'NOMBRE COMPLETO'
                      ]) ??
                      '')
                  .toString();
              final q = trabajadorCtrl.text.toLowerCase();
              return '$dni $nombre'.toLowerCase().contains(q) ||
                  _digits(dni).contains(_digits(q));
            })
            .take(20)
            .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: trabajadorCtrl,
        decoration: InputDecoration(
            labelText: 'TRABAJADORES',
            helperText: 'Busca por DNI o nombre. Cámara/QR disponible.',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner), onPressed: _openQr)),
        onChanged: (_) => setState(() {}),
        onSubmitted: (v) async {
          final w = _findWorker(v);
          if (w != null) await _addWorker(w);
        },
      ),
      const SizedBox(height: 8),
      if (trabajadorCtrl.text.trim().isNotEmpty)
        SizedBox(
          height: 150,
          child: ListView.builder(
            itemCount: options.length,
            itemBuilder: (_, i) {
              final w = options[i];
              final dni =
                  (_rowValue(w, ['DNI', 'Dni', 'DOCUMENTO']) ?? '').toString();
              final nombre = (_rowValue(w, [
                        'APELLIDOS Y NOMBRES',
                        'Apellidos y Nombres',
                        'NOMBRE COMPLETO'
                      ]) ??
                      '')
                  .toString();
              return ListTile(
                  dense: true,
                  title: Text('$dni-$nombre'),
                  onTap: () async => _addWorker(w));
            },
          ),
        ),
    ]);
  }

  String _currentTareoHoursLabel() {
    final configured =
        tareoHeader.valueByCandidates(['HORAS_TRABAJADAS', 'HORAS TRABAJADAS']);
    if (configured.trim().isNotEmpty) return configured.trim();
    final start = tareoHeader.valueByCandidates(
      ['HORA_INICIO', 'HORA INICIO', 'HORA_INCIO'],
      fallback: horaInicioCtrl.text.trim(),
    );
    final end = tareoHeader.valueByCandidates(
      ['HORA_FIN', 'HORA FIN'],
      fallback: horaFinCtrl.text.trim(),
    );
    final hours = _hoursBetween(start, end);
    if (hours == null) return 'Pendiente';
    return hours == hours.roundToDouble()
        ? '${hours.toInt()} h'
        : '${hours.toStringAsFixed(2)} h';
  }

  Future<void> _openTareoWorkersPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _TareoWorkersPage(
          workers: selectedWorkers,
          hoursLabel: _currentTareoHoursLabel(),
          onRemove: (worker) {
            if (!mounted) return;
            setState(() => selectedWorkers.remove(worker));
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _quickAction({
    required String tooltip,
    required IconData icon,
    required bool selected,
    required VoidCallback onPressed,
    int? badge,
  }) {
    final button = IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(54, 54),
        backgroundColor:
            selected ? const Color(0xFFD5EBF0) : const Color(0xFFEAF2F4),
        foregroundColor: _zumacFormatBlue,
      ),
      icon: Icon(icon),
    );
    if (badge == null) return button;
    return Badge(
      label: Text('$badge'),
      backgroundColor: const Color(0xFF31552F),
      child: button,
    );
  }

  Widget _quickActions() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _quickAction(
              tooltip: 'Horas del tareo',
              icon: Icons.access_time_rounded,
              selected: showHours,
              onPressed: () => setState(() => showHours = !showHours),
            ),
            _quickAction(
              tooltip: 'Observación',
              icon: Icons.chat_bubble_outline_rounded,
              selected: showObservation,
              onPressed: () =>
                  setState(() => showObservation = !showObservation),
            ),
            _quickAction(
              tooltip: 'Trabajadores agregados',
              icon: Icons.person_outline_rounded,
              selected: false,
              badge: selectedWorkers.length,
              onPressed: _openTareoWorkersPage,
            ),
          ],
        ),
      );

  List<Widget> _hoursEditor() {
    final timeFields = tareoHeader.fieldsWhere(_isTareoTimeField);
    if (timeFields.isNotEmpty) {
      return tareoHeader.buildFields(
        context,
        setState,
        filter: _isTareoTimeField,
      );
    }
    return [
      TextField(
        controller: horaInicioCtrl,
        readOnly: true,
        onTap: () => _pickTime(horaInicioCtrl),
        decoration: const InputDecoration(
          labelText: 'HORA_INICIO',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.access_time),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: horaFinCtrl,
        readOnly: true,
        onTap: () => _pickTime(horaFinCtrl),
        decoration: const InputDecoration(
          labelText: 'HORA_FIN',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.access_time),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _observationEditor() {
    final observationFields = tareoHeader.fieldsWhere(_isTareoObservationField);
    if (observationFields.isNotEmpty) {
      return tareoHeader.buildFields(
        context,
        setState,
        filter: _isTareoObservationField,
      );
    }
    return [
      TextField(
        controller: observacionCtrl,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Observación',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  Widget _editorBody() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    return ListView(padding: const EdgeInsets.all(14), children: [
      ...tareoHeader.buildFields(
        context,
        setState,
        filter: (field) =>
            !_isTareoTimeField(field) && !_isTareoObservationField(field),
        firstDate: yesterday,
        lastDate: today,
      ),
      _quickActions(),
      if (showHours) ..._hoursEditor(),
      if (showObservation) ..._observationEditor(),
      _workersPicker(),
      const SizedBox(height: 22),
      Center(
        child: IconButton.filled(
          key: const ValueKey('tareo-save-icon'),
          tooltip: widget.closeOnSave ? 'Guardar y cerrar tareo' : 'Guardar',
          onPressed:
              saving ? null : () => _saveDraft(closeTareo: widget.closeOnSave),
          style: IconButton.styleFrom(
            minimumSize: const Size(58, 58),
            backgroundColor: _zumacFormatBlue,
            foregroundColor: Colors.white,
          ),
          icon: saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined, size: 28),
        ),
      ),
      const SizedBox(height: 24),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF4F8F7),
        appBar: _zumacFormatAppBar(
          title: const Text(
            'Tareo de personal',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        body: _editorBody(),
      );
}

class _TareoWorkersPage extends StatefulWidget {
  final List<Map<String, dynamic>> workers;
  final String hoursLabel;
  final ValueChanged<Map<String, dynamic>> onRemove;

  const _TareoWorkersPage({
    required this.workers,
    required this.hoursLabel,
    required this.onRemove,
  });

  @override
  State<_TareoWorkersPage> createState() => _TareoWorkersPageState();
}

class _TareoWorkersPageState extends State<_TareoWorkersPage> {
  static const double _headerHeight = 52;
  static const double _rowHeight = 58;
  static const double _dniWidth = 124;
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  Widget _cell({
    required double width,
    required double height,
    required Widget child,
    required bool header,
    required bool alternate,
  }) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: header
            ? const Color(0xFF3F5B73)
            : (alternate ? const Color(0xFFF7FAFB) : Colors.white),
        border: const Border(
          right: BorderSide(color: Color(0xFFDDE7EC)),
          bottom: BorderSide(color: Color(0xFFDDE7EC)),
        ),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: header ? Colors.white : const Color(0xFF263B4A),
          fontSize: header ? 12.5 : 13,
          fontWeight: header ? FontWeight.w800 : FontWeight.w500,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workers = widget.workers;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F7),
      appBar: _zumacFormatAppBar(
        title: Text(
          'Trabajadores (${workers.length})',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: workers.isEmpty
          ? const Center(child: Text('Aún no agregaste trabajadores.'))
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDDE7EC)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Scrollbar(
                  controller: _verticalController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _verticalController,
                    child: Row(
                      key: const ValueKey('tareo-workers-fixed-dni'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            _cell(
                              width: _dniWidth,
                              height: _headerHeight,
                              child: const Text('DNI'),
                              header: true,
                              alternate: false,
                            ),
                            for (var index = 0; index < workers.length; index++)
                              _cell(
                                width: _dniWidth,
                                height: _rowHeight,
                                child: Text(
                                  workers[index]['DNI']?.toString() ?? '—',
                                ),
                                header: false,
                                alternate: index.isOdd,
                              ),
                          ],
                        ),
                        Expanded(
                          child: Scrollbar(
                            controller: _horizontalController,
                            thumbVisibility: true,
                            trackVisibility: true,
                            scrollbarOrientation: ScrollbarOrientation.bottom,
                            notificationPredicate: (notification) =>
                                notification.metrics.axis == Axis.horizontal,
                            child: SingleChildScrollView(
                              controller: _horizontalController,
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SizedBox(
                                width: 470,
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        _cell(
                                          width: 290,
                                          height: _headerHeight,
                                          child:
                                              const Text('Apellidos y nombres'),
                                          header: true,
                                          alternate: false,
                                        ),
                                        _cell(
                                          width: 110,
                                          height: _headerHeight,
                                          child: const Text('Horas totales'),
                                          header: true,
                                          alternate: false,
                                        ),
                                        _cell(
                                          width: 70,
                                          height: _headerHeight,
                                          child: const SizedBox.shrink(),
                                          header: true,
                                          alternate: false,
                                        ),
                                      ],
                                    ),
                                    for (var index = 0;
                                        index < workers.length;
                                        index++)
                                      Row(
                                        children: [
                                          _cell(
                                            width: 290,
                                            height: _rowHeight,
                                            child: Text(workers[index]
                                                        ['APELLIDOS Y NOMBRES']
                                                    ?.toString() ??
                                                '—'),
                                            header: false,
                                            alternate: index.isOdd,
                                          ),
                                          _cell(
                                            width: 110,
                                            height: _rowHeight,
                                            child: Text(widget.hoursLabel),
                                            header: false,
                                            alternate: index.isOdd,
                                          ),
                                          _cell(
                                            width: 70,
                                            height: _rowHeight,
                                            child: IconButton(
                                              tooltip: 'Quitar trabajador',
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 20),
                                              onPressed: () {
                                                final worker = workers[index];
                                                widget.onRemove(worker);
                                                setState(() {});
                                              },
                                            ),
                                            header: false,
                                            alternate: index.isOdd,
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _PlagaHallazgo {
  String? concepto;
  final Map<String, TextEditingController> valores = {};
}

class PlagasEnfermedadesSpecialPage extends StatefulWidget {
  final String moduleId;
  final Map<String, dynamic> format;
  final Map<String, dynamic>? initialPayload;
  final String? editIdLocal;
  final bool isConteoFruta;
  final VoidCallback? onLocalChanged;
  final VoidCallback? onSavedAndExit;

  const PlagasEnfermedadesSpecialPage({
    super.key,
    required this.moduleId,
    required this.format,
    this.initialPayload,
    this.editIdLocal,
    this.isConteoFruta = false,
    this.onLocalChanged,
    this.onSavedAndExit,
  });

  @override
  State<PlagasEnfermedadesSpecialPage> createState() =>
      _PlagasEnfermedadesSpecialPageState();
}

class _PlagasEnfermedadesSpecialPageState
    extends State<PlagasEnfermedadesSpecialPage> {
  final local = LocalDb.instance;
  final picker = ImagePicker();
  final uuid = const Uuid();

  String? tableDestino;
  List<Map<String, dynamic>> fields = [];
  List<Map<String, dynamic>> lotesVariedades = [];
  List<Map<String, dynamic>> conceptosEstadios = [];
  List<Map<String, dynamic>> etapasFenologicas = [];

  final fechaCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10));
  final loteCtrl = TextEditingController();
  final variedadCtrl = TextEditingController();
  final valTurCtrl = TextEditingController();
  final fenologiaCtrl = TextEditingController();

  final Map<String, String?> fotos = {
    'FOTO1': null,
    'FOTO2': null,
    'FOTO3': null
  };
  final Map<String, Map<int, String>> matriz =
      {}; // descripcion|estadio -> planta -> valor
  final Set<int> plantasGuardadas = {};
  final List<_PlagaHallazgo> hallazgos = [_PlagaHallazgo()];

  int currentPlant = 1;
  int currentHallazgo = 0;
  bool loading = true;
  bool headerOpen = true;
  bool saving = false;
  bool pickingPhoto = false;
  String idRegistro = '';

  @override
  void initState() {
    super.initState();
    idRegistro = _nuevoIdRegistro();
    _load();
  }

  @override
  void dispose() {
    fechaCtrl.dispose();
    loteCtrl.dispose();
    variedadCtrl.dispose();
    valTurCtrl.dispose();
    fenologiaCtrl.dispose();
    for (final h in hallazgos) {
      for (final c in h.valores.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  String _nuevoIdRegistro() {
    // ID técnico local para agrupar borradores/filas antes de sincronizar.
    // No es el código visible incremental de negocio.
    return uuid.v4();
  }

  Future<void> _load() async {
    final table = await _resolveTableDestino();
    final rows = table == null
        ? <Map<String, dynamic>>[]
        : await local.where(
            'local_form_fields', 'tabla_destino = ? and activo = 1', [table],
            orderBy: 'orden');
    final lotes =
        await local.getAll('local_lotes_variedades', orderBy: 'turno');
    await _refreshSanidadCatalogsIfNeeded();
    final conceptos = widget.isConteoFruta
        ? await _loadConteoEstadios()
        : await local.getAll('local_plagas_conceptos',
            orderBy: 'concepto, estadio');
    final etapas =
        await local.getAll('local_fenologias', orderBy: 'etapa_fenologica');
    if (!mounted) return;
    setState(() {
      tableDestino = table;
      fields = rows;
      lotesVariedades = lotes;
      conceptosEstadios = conceptos;
      etapasFenologicas = etapas;
      loading = false;
    });
    _applyInitialPayloadIfAny();
  }

  Future<String?> _resolveTableDestino() async {
    final direct = _clean(widget.format['tabla_destino']);
    if (direct != null) return direct;
    final tableRows = await local.where(
      'local_format_tables',
      'formato_id = ? and activo = 1',
      [widget.format['id']],
      orderBy: 'orden',
    );
    if (tableRows.isEmpty) return null;
    return _clean(tableRows.first['tabla_destino']);
  }

  String? _clean(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty || s.toUpperCase() == 'EMPTY' || s.toUpperCase() == 'NULL')
      return null;
    return s;
  }

  dynamic _valueByColumn(Map<String, dynamic> row, List<String> candidates) {
    final wanted = candidates.map(_norm).toSet();
    for (final entry in row.entries) {
      if (wanted.contains(_norm(entry.key))) return entry.value;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _fetchSupabaseRows(
      String table, String select) async {
    // Primero se consulta sin lista explícita de columnas.
    // En tablas con nombres/columnas en mayúsculas, PostgREST puede devolver vacío o fallar
    // cuando el select viene con comillas dentro del string. Con select() traemos el registro
    // completo y luego mapeamos por nombre de columna normalizado.
    try {
      final rows = await Supabase.instance.client.from(table).select();
      final parsed = withoutSoftDeletedAppgtRows(
        List<Map<String, dynamic>>.from(rows),
      );
      // Una respuesta vacía es válida: puede significar que todas las filas
      // quedaron eliminadas lógicamente. No volver a consultarlas sin flags.
      return parsed;
    } catch (_) {}

    try {
      final rows = await Supabase.instance.client.from(table).select(select);
      return withoutSoftDeletedAppgtRows(
        List<Map<String, dynamic>>.from(rows),
      );
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  List<Map<String, dynamic>> _mapFenologiaRows(
      List<Map<String, dynamic>> source) {
    final rows = <String, Map<String, dynamic>>{};
    for (final e in source) {
      final etapa = _valueByColumn(e, [
            'ETAPA_FENOLOGICA',
            'ETAPA FENOLOGICA',
            'ETAPA FENOLÓGICA',
            'FENOLOGIA',
            'FENOLOGÍA',
            'FENOLOGICA',
            'FENOLÓGICA',
            'ETAPA',
          ])?.toString().trim() ??
          '';
      if (etapa.isEmpty) continue;
      rows[etapa] = {'etapa_fenologica': etapa};
    }
    return rows.values.toList();
  }

  List<Map<String, dynamic>> _mapConteoRows(List<Map<String, dynamic>> source) {
    final rows = <String, Map<String, dynamic>>{};
    for (final e in source) {
      final estadio = _valueByColumn(e, [
            'ESTADIO O TIPO',
            'ESTADIOS O TIPOS',
            'ESTADIOS O TIPO',
            'ESTADIO_O_TIPO',
            'ESTADIOS_O_TIPOS',
            'ESTADIO',
            'TIPO'
          ])?.toString().trim() ??
          '';
      if (estadio.isEmpty) continue;
      rows[estadio] = {
        'concepto': 'CONTEO_FRUTA',
        'estadio': estadio,
        'formula': _valueByColumn(e, ['FORMULA'])?.toString().trim() ?? '',
      };
    }
    return rows.values.toList();
  }

  Future<List<Map<String, dynamic>>> _loadConteoEstadios() async {
    final localRows =
        await local.getAll('local_conteo_estadios', orderBy: 'estadio');
    List<Map<String, dynamic>> rows = localRows
        .map((e) => <String, dynamic>{
              'concepto': 'CONTEO_FRUTA',
              'estadio': e['estadio']?.toString().trim() ?? '',
              'formula': e['formula']?.toString().trim() ?? '',
            })
        .where((e) => (e['estadio'] ?? '').toString().isNotEmpty)
        .toList();
    if (rows.isNotEmpty) return rows;

    // Respaldo offline: si la tabla especial fue descargada como matriz genérica,
    // reconstruimos los estadios desde local_matrix_rows sin consultar internet.
    final cachedMatrixRows = await local.where(
      'local_matrix_rows',
      'source_table = ?',
      ['SN-MATRIZ_ESTADIOS_CONTEO_FRUTA'],
    );
    final decoded = <Map<String, dynamic>>[];
    for (final row in cachedMatrixRows) {
      try {
        final raw = row['payload_json']?.toString() ?? '';
        final data = jsonDecode(raw);
        if (data is Map) {
          final payload = Map<String, dynamic>.from(data);
          if (!isSoftDeletedAppgtRow(payload)) decoded.add(payload);
        }
      } catch (_) {}
    }
    rows = _mapConteoRows(decoded);
    if (rows.isNotEmpty) {
      await local.replaceTable(
          'local_conteo_estadios',
          rows
              .map((e) => {
                    'estadio': e['estadio'],
                    'formula': e['formula'],
                  })
              .toList());
      return rows;
    }

    final remote = await _fetchSupabaseRows(
      'SN-MATRIZ_ESTADIOS_CONTEO_FRUTA',
      '"ESTADIO O TIPO",FORMULA,ID',
    );
    rows = _mapConteoRows(remote);
    if (rows.isNotEmpty) {
      await local.replaceTable(
          'local_conteo_estadios',
          rows
              .map((e) => {
                    'estadio': e['estadio'],
                    'formula': e['formula'],
                  })
              .toList());
      return rows;
    }

    // Último respaldo visual/operativo: evita que la sección quede vacía si la matriz
    // SN-MATRIZ_ESTADIOS_CONTEO_FRUTA no fue descargada por permisos/RLS o caché.
    // Cuando Actualizar matrices descargue la matriz real, esta lista queda reemplazada.
    rows = _fallbackConteoRows();
    await local.replaceTable(
        'local_conteo_estadios',
        rows
            .map((e) => {
                  'estadio': e['estadio'],
                  'formula': e['formula'],
                })
            .toList());
    return rows;
  }

  List<Map<String, dynamic>> _fallbackFenologiaRows() {
    const etapas = <String>[
      'PODA',
      'BROTACION',
      'FLORACION',
      'CUAJADO',
      'FRUTO VERDE',
      'FRUTO GUINDA',
      'FRUTO ROSADO',
      'FRUTO AZUL',
    ];
    return etapas.map((e) => {'etapa_fenologica': e}).toList();
  }

  List<Map<String, dynamic>> _fallbackConteoRows() {
    const estadios = <String>[
      'FLORES',
      'FRUTO CUAJADO',
      'FRUTO VERDE',
      'FRUTO GUINDA',
      'FRUTO ROSADO',
      'FRUTO AZUL',
    ];
    return estadios
        .map((e) => {
              'concepto': 'CONTEO_FRUTA',
              'estadio': e,
              'formula': 'INDIVIDUO',
            })
        .toList();
  }

  Future<void> _refreshSanidadCatalogsIfNeeded() async {
    var conceptos = await local.getAll('local_plagas_conceptos',
        orderBy: 'concepto, estadio');
    var etapas =
        await local.getAll('local_fenologias', orderBy: 'etapa_fenologica');

    if (conceptos.isEmpty) {
      final remoteConceptos = await _fetchSupabaseRows(
        'SN-MATRIZ_CONCEPTOS_ESTADIOS_PLAGAS',
        'CONCEPTO,"ESTADIO O TIPO",FORMULA',
      );
      final rows = <String, Map<String, dynamic>>{};
      for (final e in remoteConceptos) {
        final concepto =
            _valueByColumn(e, ['CONCEPTO'])?.toString().trim() ?? '';
        final estadio = _valueByColumn(e, [
              'ESTADIO O TIPO',
              'ESTADIOS O TIPOS',
              'ESTADIOS O TIPO',
              'ESTADIO_O_TIPO',
              'ESTADIOS_O_TIPOS',
              'ESTADIO',
              'TIPO'
            ])?.toString().trim() ??
            '';
        if (concepto.isEmpty || estadio.isEmpty) continue;
        final id = '$concepto$estadio';
        rows[id] = {
          'id': id,
          'concepto': concepto,
          'estadio': estadio,
          'formula': _valueByColumn(e, ['FORMULA'])?.toString().trim() ?? '',
        };
      }
      if (rows.isNotEmpty) {
        await local.replaceTable(
            'local_plagas_conceptos', rows.values.toList());
        conceptos = await local.getAll('local_plagas_conceptos',
            orderBy: 'concepto, estadio');
      }
    }

    if (etapas.isEmpty) {
      final remoteEtapas = await _fetchSupabaseRows(
        'SN-MATRIZ_ETAPAS_FENOLOGICAS',
        'ETAPA_FENOLOGICA,CULTIVO,ID',
      );
      var rows = _mapFenologiaRows(remoteEtapas);
      if (rows.isEmpty) {
        // Respaldo operativo: evita que la pantalla quede inutilizable si Supabase
        // devuelve vacío por RLS/permisos o por una consulta remota fallida.
        rows = _fallbackFenologiaRows();
      }
      await local.replaceTable('local_fenologias', rows);
    }
  }

  String _norm(String value) {
    var s = value.trim().toUpperCase();
    const map = {
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'Ü': 'U',
      'Ñ': 'N'
    };
    map.forEach((k, v) => s = s.replaceAll(k, v));
    return s
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String? _fieldName(List<String> candidates) {
    final wanted = candidates.map(_norm).toSet();
    for (final f in fields) {
      final campo = f['campo']?.toString() ?? '';
      if (wanted.contains(_norm(campo))) return campo;
    }
    return null;
  }

  String? _plantField(int plant) =>
      _fieldName(['PLANTA $plant', 'PLANTA$plant', 'PLANTA_$plant']);
  String? get _idField => _fieldName(['ID_REGISTRO', 'ID']);
  String? get _fechaField => _fieldName(['FECHA']);
  String? get _loteField => _fieldName(['LOTE', 'TURNO']);
  String? get _turnoField => _fieldName(['TURNO']);
  String? get _variedadField => _fieldName(['VARIEDAD']);
  String? get _valTurField => _fieldName(['VAL/TUR', 'VAL_TUR', 'VALTUR']);
  String? get _fenologiaField => _fieldName(['FENOLOGIA', 'FENOLOGÍA']);
  String? get _descripcionField => _fieldName(['DESCRIPCION', 'DESCRIPCIÓN']);
  String? get _estadioField =>
      _fieldName(['ESTADIO O TIPO', 'ESTADIO', 'TIPO']);
  String? get _formulaField => _fieldName(['FORMULA', 'FÓRMULA']);
  String? get _muestraField => _fieldName(['MUESTRA']);
  String? get _promedioField => _fieldName(['PROMEDIO', 'RESULTADO']);
  String? get _idFilaSerialField =>
      _fieldName(['id_fila_serial', 'ID_FILA_SERIAL']);

  List<String> _turnosUnicos() {
    final seen = <String>{};
    final out = <String>[];
    for (final row in lotesVariedades) {
      final t = row['turno']?.toString().trim() ?? '';
      if (t.isEmpty || seen.contains(t)) continue;
      seen.add(t);
      out.add(t);
    }
    return out;
  }

  void _setVariedad(String? turno) {
    if (turno == null || turno.isEmpty) return;
    final match = lotesVariedades
        .where((e) => e['turno']?.toString().trim() == turno)
        .toList();
    variedadCtrl.text =
        match.isEmpty ? '' : (match.first['variedad']?.toString() ?? '');
  }

  List<String> _conceptos() {
    if (widget.isConteoFruta) return const ['CONTEO_FRUTA'];
    final seen = <String>{};
    final out = <String>[];
    for (final r in conceptosEstadios) {
      final c = r['concepto']?.toString().trim() ?? '';
      if (c.isEmpty || seen.contains(c)) continue;
      seen.add(c);
      out.add(c);
    }
    return out;
  }

  List<String> _fenologias() {
    final seen = <String>{};
    final out = <String>[];
    for (final r in etapasFenologicas) {
      final etapa = r['etapa_fenologica']?.toString().trim() ?? '';
      if (etapa.isEmpty || seen.contains(etapa)) continue;
      seen.add(etapa);
      out.add(etapa);
    }
    return out;
  }

  Future<List<String>> _reloadFenologias() async {
    // Recarga directa desde Supabase. No dependemos únicamente del cache local,
    // porque este catálogo puede quedar vacío si el usuario todavía no hizo
    // una actualización completa de matrices.
    final remoteEtapas = await _fetchSupabaseRows(
      'SN-MATRIZ_ETAPAS_FENOLOGICAS',
      'ETAPA_FENOLOGICA,CULTIVO,ID',
    );

    var rows = _mapFenologiaRows(remoteEtapas);

    if (rows.isEmpty) {
      rows = _fallbackFenologiaRows();
    }
    await local.replaceTable('local_fenologias', rows);

    final etapas =
        await local.getAll('local_fenologias', orderBy: 'etapa_fenologica');
    if (mounted) {
      setState(() => etapasFenologicas = etapas);
    } else {
      etapasFenologicas = etapas;
    }
    return _fenologias();
  }

  dynamic _payloadValue(Map<String, dynamic> payload, List<String> candidates) {
    final wanted = candidates.map(_norm).toSet();
    for (final entry in payload.entries) {
      if (wanted.contains(_norm(entry.key))) return entry.value;
    }
    return null;
  }

  void _applyInitialPayloadIfAny() {
    final payload = widget.initialPayload;
    if (payload == null || payload.isEmpty) return;
    setState(() {
      _applyBasePayload(payload);

      final rawRows = payload['__plagas_rows'];
      if (rawRows is List && rawRows.isNotEmpty) {
        _rebuildMatrizFromPayloadRows(
          rawRows
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        );
      } else {
        _rebuildMatrizFromPayloadRows([payload]);
      }

      if (plantasGuardadas.isNotEmpty) {
        currentPlant = plantasGuardadas.reduce((a, b) => a > b ? a : b);
      }
      _loadHallazgosForCurrentPlant();
    });
  }

  void _applyBasePayload(Map<String, dynamic> payload) {
    final id = _payloadValue(payload, ['ID_REGISTRO', 'ID'])?.toString().trim();
    if (id != null && id.isNotEmpty) idRegistro = id;
    fechaCtrl.text =
        _payloadValue(payload, ['FECHA'])?.toString().trim() ?? fechaCtrl.text;
    loteCtrl.text =
        _payloadValue(payload, ['LOTE', 'TURNO'])?.toString().trim() ??
            loteCtrl.text;
    variedadCtrl.text =
        _payloadValue(payload, ['VARIEDAD'])?.toString().trim() ??
            variedadCtrl.text;
    valTurCtrl.text = _payloadValue(payload, ['VAL/TUR', 'VAL_TUR', 'VALTUR'])
            ?.toString()
            .trim() ??
        valTurCtrl.text;
    fenologiaCtrl.text =
        _payloadValue(payload, ['FENOLOGIA', 'FENOLOGÍA'])?.toString().trim() ??
            fenologiaCtrl.text;
  }

  void _rebuildMatrizFromPayloadRows(List<Map<String, dynamic>> rows) {
    matriz.clear();
    plantasGuardadas.clear();

    final plantRegex = RegExp(r'^PLANTA_?(\d+)$');
    for (final payload in rows) {
      final concepto = widget.isConteoFruta
          ? 'CONTEO_FRUTA'
          : _payloadValue(payload, ['DESCRIPCION', 'DESCRIPCIÓN'])
              ?.toString()
              .trim();
      final estadio =
          _payloadValue(payload, ['ESTADIO O TIPO', 'ESTADIO', 'TIPO'])
              ?.toString()
              .trim();
      if (concepto == null ||
          concepto.isEmpty ||
          estadio == null ||
          estadio.isEmpty) continue;

      for (final entry in payload.entries) {
        final keyNorm = _norm(entry.key);
        final match = plantRegex.firstMatch(keyNorm);
        if (match == null) continue;
        final plant = int.tryParse(match.group(1) ?? '');
        final value = entry.value?.toString().trim() ?? '';
        if (plant == null || value.isEmpty) continue;
        final key = '$concepto\u001f$estadio';
        matriz.putIfAbsent(key, () => <int, String>{});
        matriz[key]![plant] = value;
        plantasGuardadas.add(plant);
      }
    }
  }

  void _loadHallazgosForCurrentPlant() {
    for (final h in hallazgos) {
      for (final c in h.valores.values) {
        c.dispose();
      }
    }
    hallazgos.clear();

    final byConcepto = <String, Map<String, String>>{};
    for (final entry in matriz.entries) {
      final parts = entry.key.split('\u001f');
      if (parts.length != 2) continue;
      final value = entry.value[currentPlant];
      if (value == null || value.trim().isEmpty) continue;
      byConcepto.putIfAbsent(parts[0], () => <String, String>{});
      byConcepto[parts[0]]![parts[1]] = value;
    }

    if (widget.isConteoFruta) {
      final h = _PlagaHallazgo()..concepto = 'CONTEO_FRUTA';
      _ensureControllers(h);
      for (final estadioEntry
          in (byConcepto['CONTEO_FRUTA'] ?? const <String, String>{}).entries) {
        h.valores
            .putIfAbsent(estadioEntry.key, () => TextEditingController())
            .text = estadioEntry.value;
      }
      hallazgos.add(h);
    } else if (byConcepto.isEmpty) {
      hallazgos.add(_PlagaHallazgo());
    } else {
      for (final conceptEntry in byConcepto.entries) {
        final h = _PlagaHallazgo()..concepto = conceptEntry.key;
        _ensureControllers(h);
        for (final estadioEntry in conceptEntry.value.entries) {
          h.valores
              .putIfAbsent(estadioEntry.key, () => TextEditingController())
              .text = estadioEntry.value;
        }
        hallazgos.add(h);
      }
    }
    currentHallazgo = 0;
  }

  String _formulaFor(String? concepto, String estadio) {
    for (final r in conceptosEstadios) {
      final c = r['concepto']?.toString().trim() ?? '';
      final e = r['estadio']?.toString().trim() ?? '';
      final sameConcept =
          widget.isConteoFruta || (concepto != null && c == concepto.trim());
      if (sameConcept && e == estadio.trim()) {
        return _norm(r['formula']?.toString() ?? '');
      }
    }
    return '';
  }

  String _rawFormulaForEstadio(String estadio) {
    for (final r in conceptosEstadios) {
      final e = r['estadio']?.toString().trim() ?? '';
      if (e == estadio.trim()) return r['formula']?.toString().trim() ?? '';
    }
    return '';
  }

  bool _isIncidencia(String? concepto, String estadio) =>
      _formulaFor(concepto, estadio) == 'INCIDENCIA';
  bool _isIndividuo(String? concepto, String estadio) =>
      _formulaFor(concepto, estadio) == 'INDIVIDUO';
  bool _isIndividuoCm(String? concepto, String estadio) =>
      _formulaFor(concepto, estadio) == 'INDIVIDUOCM';

  List<String> _estadios(String? concepto) {
    if (widget.isConteoFruta) {
      return conceptosEstadios
          .map((e) => e['estadio']?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (concepto == null || concepto.isEmpty) return const [];
    return conceptosEstadios
        .where((e) => e['concepto']?.toString().trim() == concepto)
        .map((e) => e['estadio']?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  void _ensureControllers(_PlagaHallazgo h) {
    final estadios = _estadios(h.concepto);
    for (final e in estadios) {
      h.valores.putIfAbsent(e, () => TextEditingController());
    }
    final remove = h.valores.keys.where((e) => !estadios.contains(e)).toList();
    for (final key in remove) {
      h.valores.remove(key)?.dispose();
    }
  }

  Future<void> _pickPhoto() async {
    if (pickingPhoto || saving) return;
    FocusScope.of(context).unfocus();
    final pendientes = fotos.entries
        .where((e) => e.value == null || e.value!.isEmpty)
        .map((e) => e.key)
        .toList();
    final next = pendientes.isEmpty ? null : pendientes.first;
    if (next == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ya tienes 3 fotos registradas.')));
      return;
    }
    setState(() => pickingPhoto = true);
    try {
      final file = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 45,
          maxWidth: 800,
          maxHeight: 800);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(
          () => fotos[next] = 'data:image/jpeg;base64,${base64Encode(bytes)}');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$next registrada.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir la cámara: $e')));
    } finally {
      if (mounted) setState(() => pickingPhoto = false);
    }
  }

  void _commitCurrentPlant() {
    for (final h in hallazgos) {
      final concepto = widget.isConteoFruta ? 'CONTEO_FRUTA' : h.concepto;
      if (concepto == null || concepto.trim().isEmpty) continue;
      _ensureControllers(h);
      for (final entry in h.valores.entries) {
        final valor = entry.value.text.trim();
        if (valor.isEmpty) continue;
        final key = '${concepto.trim()}\u001f${entry.key.trim()}';
        matriz.putIfAbsent(key, () => <int, String>{});
        matriz[key]![currentPlant] = valor;
      }
    }
    plantasGuardadas.add(currentPlant);
  }

  Future<void> _newPlant() async {
    final saved = await _autoSaveDraft();
    if (!saved || !mounted) return;
    setState(() {
      currentPlant++;
      currentHallazgo = 0;
      for (final h in hallazgos) {
        for (final c in h.valores.values) {
          c.dispose();
        }
      }
      hallazgos
        ..clear()
        ..add(_PlagaHallazgo()
          ..concepto = widget.isConteoFruta ? 'CONTEO_FRUTA' : null);
      headerOpen = false;
    });
  }

  void _addHallazgo() {
    if (widget.isConteoFruta) return;
    _commitCurrentPlant();
    setState(() {
      hallazgos.add(_PlagaHallazgo());
      currentHallazgo = hallazgos.length - 1;
    });
  }

  Map<String, dynamic> _basePayload() {
    final payload = <String, dynamic>{};
    void put(String? campo, dynamic value) {
      if (campo != null && value != null && value.toString().trim().isNotEmpty)
        payload[campo] = value;
    }

    put(_idField, idRegistro);
    put(_fechaField, fechaCtrl.text.trim());
    put(_loteField, loteCtrl.text.trim());
    put(_turnoField, loteCtrl.text.trim());
    put(_variedadField, variedadCtrl.text.trim());
    put(_valTurField, valTurCtrl.text.trim());
    put(_fenologiaField, fenologiaCtrl.text.trim());
    for (final f in fields) {
      final campo = f['campo']?.toString() ?? '';
      final n = _norm(campo);
      if (n == 'FOTO1' && fotos['FOTO1'] != null)
        payload[campo] = fotos['FOTO1'];
      if (n == 'FOTO2' && fotos['FOTO2'] != null)
        payload[campo] = fotos['FOTO2'];
      if (n == 'FOTO3' && fotos['FOTO3'] != null)
        payload[campo] = fotos['FOTO3'];
    }
    return payload;
  }

  Map<String, dynamic> _cleanPayloadForInsert(Map<String, dynamic> payload) {
    final cleaned = Map<String, dynamic>.from(payload);
    final keysToRemove = cleaned.keys.where((key) {
      if (_norm(key) != 'ID_FILA_SERIAL') return false;
      final value = cleaned[key];
      return value == null || value.toString().trim().isEmpty;
    }).toList();
    for (final key in keysToRemove) {
      cleaned.remove(key);
    }
    cleaned.remove('__plagas_rows');
    return cleaned;
  }

  List<Map<String, dynamic>> _buildPendingRows(String userId, String table) {
    final rows = <Map<String, dynamic>>[];
    final base = _basePayload();
    int maxPlantaEvaluada = 0;
    for (final entry in matriz.entries) {
      for (final plantNumber in entry.value.keys) {
        if (plantNumber > maxPlantaEvaluada) maxPlantaEvaluada = plantNumber;
      }
    }
    int i = 0;
    for (final entry in matriz.entries) {
      final parts = entry.key.split('\u001f');
      if (parts.length != 2) continue;
      final payload = Map<String, dynamic>.from(base);
      final descripcion = _descripcionField;
      final estadio = _estadioField;
      final formula = _formulaField;
      final muestra = _muestraField;
      final promedio = _promedioField;
      if (!widget.isConteoFruta && descripcion != null)
        payload[descripcion] = parts[0];
      if (estadio != null) payload[estadio] = parts[1];
      if (formula != null) payload[formula] = _rawFormulaForEstadio(parts[1]);

      final numericValues = <num>[];
      for (final plantEntry in entry.value.entries) {
        final campoPlanta = _plantField(plantEntry.key);
        if (campoPlanta == null) continue;
        payload[campoPlanta] = plantEntry.value;
        final parsed =
            num.tryParse(plantEntry.value.toString().replaceAll(',', '.'));
        if (parsed != null) numericValues.add(parsed);
      }
      if (muestra != null && maxPlantaEvaluada > 0)
        payload[muestra] = maxPlantaEvaluada;
      if (promedio != null && numericValues.isNotEmpty) {
        payload[promedio] =
            numericValues.reduce((a, b) => a + b) / numericValues.length;
      }

      final idFilaSerial = _idFilaSerialField;
      if (idFilaSerial != null && idFilaSerial.trim().isNotEmpty) {
        payload[idFilaSerial] = DateTime.now().microsecondsSinceEpoch + i;
      }

      final idLocal = '${idRegistro}_${i++}';
      payload['id_local'] = idLocal;

      rows.add({
        'id_local': idLocal,
        'user_id': userId,
        'modulo_id': widget.moduleId,
        'formato_id': widget.format['id'],
        'formato_tabla_id': null,
        'tabla_destino': table,
        'payload_json': jsonEncode(_cleanPayloadForInsert(payload)),
        'estado': 'pendiente',
        'intentos': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    return rows;
  }

  Future<bool> _autoSaveDraft() async {
    final table = tableDestino;
    if (table == null || table.isEmpty) return false;
    _commitCurrentPlant();
    if (matriz.isEmpty) return false;

    final cachedUserId = await LocalSession().cachedUserId();
    final userId =
        Supabase.instance.client.auth.currentUser?.id ?? cachedUserId;
    if (userId == null) return false;

    await local.deletePendingRecordsByPrefix('${idRegistro}_');
    await local.deletePendingRecordsByLogicalId(
      formatoId: widget.format['id']?.toString() ?? '',
      tablaDestino: table,
      idRegistro: idRegistro,
    );
    for (final row in _buildPendingRows(userId, table)) {
      await local.insertPending(row);
    }
    widget.onLocalChanged?.call();
    return true;
  }

  Future<void> _saveAndExit() async {
    if (saving || pickingPhoto) return;
    FocusScope.of(context).unfocus();
    final table = tableDestino;
    if (table == null || table.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tabla destino no configurada.')));
      return;
    }
    _commitCurrentPlant();
    if (matriz.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay evaluaciones para guardar.')));
      return;
    }
    setState(() => saving = true);
    try {
      final cachedUserId = await LocalSession().cachedUserId();
      final userId =
          Supabase.instance.client.auth.currentUser?.id ?? cachedUserId;
      if (userId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay usuario local disponible.')));
        return;
      }

      await local.deletePendingRecordsByPrefix('${idRegistro}_');
      await local.deletePendingRecordsByLogicalId(
        formatoId: widget.format['id']?.toString() ?? '',
        tablaDestino: table,
        idRegistro: idRegistro,
      );
      if (widget.editIdLocal != null && widget.editIdLocal!.isNotEmpty) {
        await local.deleteRecord(widget.editIdLocal!);
      }

      for (final row in _buildPendingRows(userId, table)) {
        await local.insertPending(row);
      }
      widget.onLocalChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro guardado localmente.')));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.onSavedAndExit != null) {
          widget.onSavedAndExit!.call();
        } else {
          Navigator.of(context).maybePop();
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar localmente: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _fieldBox({required Widget child, double? width}) {
    return SizedBox(
        width: width, height: _FormVisuals.headerFieldHeight, child: child);
  }

  Widget _textInput(String label, TextEditingController c,
      {bool readOnly = false}) {
    return TextField(
      controller: c,
      readOnly: readOnly,
      maxLines: 1,
      style: const TextStyle(fontSize: 13),
      textAlignVertical: TextAlignVertical.center,
      decoration: _FormVisuals.decoration(label),
    );
  }

  Widget _catalogPicker({
    required String label,
    required String? value,
    required List<String> values,
    required ValueChanged<String?> onSelected,
    Future<List<String>> Function()? onReloadValues,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        FocusScope.of(context).unfocus();
        var availableValues = List<String>.from(values);
        if (availableValues.isEmpty && onReloadValues != null) {
          availableValues = await onReloadValues();
        }
        if (!mounted) return;
        if (availableValues.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('No hay opciones disponibles para $label.')));
          return;
        }
        final selected = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          builder: (ctx) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.55,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Text(label,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: availableValues.length,
                        itemBuilder: (_, i) {
                          final item = availableValues[i];
                          return ListTile(
                            dense: true,
                            title: Text(item, overflow: TextOverflow.ellipsis),
                            onTap: () => Navigator.of(ctx).pop(item),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
        if (selected != null) onSelected(selected);
      },
      child: SizedBox(
        height: _FormVisuals.headerFieldHeight,
        child: InputDecorator(
          decoration: _FormVisuals.decoration(label).copyWith(
            suffixIcon: const Icon(Icons.arrow_drop_down),
            enabled: true,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              (value == null || value.isEmpty) ? 'Seleccionar' : value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateField(BuildContext context) {
    return TextField(
      controller: fechaCtrl,
      readOnly: true,
      style: const TextStyle(fontSize: 13),
      textAlignVertical: TextAlignVertical.center,
      decoration: _FormVisuals.decoration('Fecha', icon: Icons.calendar_month),
      onTap: () async {
        final now = DateTime.now();
        final minDate = DateTime(1900);
        final maxDate = DateTime(now.year + 20);
        final initial = _safeDatePickerInitialDate(
            DateTime.tryParse(fechaCtrl.text) ?? now, minDate, maxDate);
        final picked = await showDatePicker(
          context: context,
          firstDate: minDate,
          lastDate: maxDate,
          initialDate: initial,
        );
        if (picked != null)
          fechaCtrl.text = picked.toIso8601String().substring(0, 10);
      },
    );
  }

  Widget _equalRow(List<Widget> children) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _fieldBox(child: children[i])),
        ],
      ],
    );
  }

  Widget _cabecera(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () => setState(() => headerOpen = !headerOpen),
            child: Row(children: [
              const Expanded(
                  child: Text('Cabecera',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800))),
              Icon(headerOpen
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down),
            ]),
          ),
          if (headerOpen) ...[
            const SizedBox(height: 8),
            _equalRow([
              _dateField(context),
              _catalogPicker(
                label: 'Fenología',
                value: fenologiaCtrl.text,
                values: _fenologias(),
                onSelected: (v) => setState(() => fenologiaCtrl.text = v ?? ''),
                onReloadValues: _reloadFenologias,
              ),
            ]),
            const SizedBox(height: 8),
            _equalRow([
              DropdownButtonFormField<String>(
                value: loteCtrl.text.isNotEmpty ? loteCtrl.text : null,
                isExpanded: true,
                decoration: _FormVisuals.decoration('Lote'),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                items: _turnosUnicos()
                    .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setState(() {
                  loteCtrl.text = v ?? '';
                  _setVariedad(v);
                }),
              ),
              _textInput('Variedad', variedadCtrl, readOnly: true),
              _textInput('Val/Tur', valTurCtrl),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _plantSelector(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(children: [
          Expanded(
              child: Text('Evaluación PLANTA $currentPlant',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800))),
          SizedBox(
            width: 130,
            child: DropdownButtonFormField<int>(
              value: currentPlant,
              decoration: _FormVisuals.decoration('Plantas'),
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              items: List.generate(50, (i) => i + 1)
                  .map((p) => DropdownMenuItem(
                      value: p,
                      child: Text('PLANTA $p',
                          style: const TextStyle(fontSize: 12))))
                  .toList(),
              onChanged: (v) => setState(() {
                if (v != null) {
                  _commitCurrentPlant();
                  currentPlant = v;
                  _loadHallazgosForCurrentPlant();
                }
              }),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _valorPorFormula(
      _PlagaHallazgo h, String estadio, TextEditingController ctrl) {
    if (widget.isConteoFruta) {
      return TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly
        ],
        style: const TextStyle(fontSize: 13),
        decoration: _FormVisuals.decoration('Valor'),
      );
    }
    if (_isIncidencia(h.concepto, estadio)) {
      return DropdownButtonFormField<String>(
        value: ctrl.text == '0' || ctrl.text == '1' ? ctrl.text : null,
        decoration: _FormVisuals.decoration('Valor'),
        style: const TextStyle(fontSize: 13, color: Colors.black87),
        items: const [
          DropdownMenuItem(value: '0', child: Text('0')),
          DropdownMenuItem(value: '1', child: Text('1')),
        ],
        onChanged: (v) => setState(() => ctrl.text = v ?? ''),
      );
    }

    final isDecimal = _isIndividuoCm(h.concepto, estadio);
    final inputFormatters = isDecimal
        ? <TextInputFormatter>[
            TextInputFormatter.withFunction((oldValue, newValue) {
              final text = newValue.text;
              if (text.isEmpty ||
                  RegExp(r'^\d{0,8}(\.\d{0,2})?$').hasMatch(text)) {
                return newValue;
              }
              return oldValue;
            }),
          ]
        : <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly];

    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: isDecimal),
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 13),
      decoration: _FormVisuals.decoration('Valor'),
    );
  }

  Widget _hallazgos(BuildContext context) {
    if (widget.isConteoFruta && hallazgos.isNotEmpty) {
      hallazgos[currentHallazgo].concepto = 'CONTEO_FRUTA';
    }
    final h = hallazgos[currentHallazgo];
    _ensureControllers(h);
    final estadios = _estadios(h.concepto);
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 86),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(
                    widget.isConteoFruta ? 'Estadios o tipos' : 'Hallazgos',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800))),
            if (!widget.isConteoFruta)
              IconButton(
                  onPressed: currentHallazgo > 0
                      ? () => setState(() => currentHallazgo--)
                      : null,
                  icon: const Icon(Icons.chevron_left)),
            if (!widget.isConteoFruta)
              IconButton(
                  onPressed: currentHallazgo < hallazgos.length - 1
                      ? () => setState(() => currentHallazgo++)
                      : null,
                  icon: const Icon(Icons.chevron_right)),
          ]),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFFF1F4F6),
                borderRadius: BorderRadius.circular(12)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  widget.isConteoFruta
                      ? 'Conteo por planta'
                      : 'Hallazgo ${currentHallazgo + 1}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              if (!widget.isConteoFruta) ...[
                const SizedBox(height: 8),
                Builder(
                  builder: (_) {
                    final conceptos = _conceptos();
                    return _catalogPicker(
                      label: 'DESCRIPCION',
                      value: h.concepto,
                      values: conceptos,
                      onSelected: (v) => setState(() {
                        h.concepto = v;
                        _ensureControllers(h);
                      }),
                    );
                  },
                ),
              ],
              const SizedBox(height: 10),
              ...estadios.map((estadio) {
                final ctrl = h.valores[estadio]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF2B7180)),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(estadio,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF166273))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 92,
                      child: _valorPorFormula(h, estadio, ctrl),
                    ),
                  ]),
                );
              }),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _zumacFormatAppBar(
        title: Text(
            widget.isConteoFruta ? 'Conteo de Fruta' : 'Plagas y Enfermedades',
            style: const TextStyle(fontSize: 16)),
        onBack: widget.onSavedAndExit == null
            ? null
            : () => widget.onSavedAndExit!.call(),
        actions: [
          IconButton(
              onPressed: (saving || pickingPhoto) ? null : _pickPhoto,
              icon: const Icon(Icons.photo_camera))
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(
          onPressed: saving ? null : _saveAndExit,
          child: saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save)),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 88, 8),
          child: Row(children: [
            if (!widget.isConteoFruta) ...[
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: _addHallazgo,
                      icon: const Icon(Icons.add),
                      label: const Text('Hallazgo'))),
              const SizedBox(width: 8),
            ],
            Expanded(
                child: FilledButton.icon(
                    onPressed: () => _newPlant(),
                    icon: const Icon(Icons.add),
                    label: const Text('Planta'))),
          ]),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _cabecera(context),
                  _plantSelector(context),
                  Expanded(
                      child: SingleChildScrollView(child: _hallazgos(context))),
                ],
              ),
      ),
    );
  }
}

enum PlantScreenKind { fenologia, conteoFruta }

class _FormVisuals {
  static const double headerFieldHeight = 54;
  static const fieldTextStyle = TextStyle(fontSize: 12.5);
  static const labelStyle = TextStyle(fontSize: 12);

  static InputDecoration decoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: labelStyle,
      border: const OutlineInputBorder(),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      suffixIcon: icon == null ? null : Icon(icon, size: 18),
    );
  }
}

class PlantEvaluationSpecialPage extends StatefulWidget {
  final String moduleId;
  final Map<String, dynamic> format;
  final PlantScreenKind screenKind;
  final VoidCallback? onLocalChanged;
  final VoidCallback? onSavedAndExit;

  const PlantEvaluationSpecialPage({
    super.key,
    required this.moduleId,
    required this.format,
    required this.screenKind,
    this.onLocalChanged,
    this.onSavedAndExit,
  });

  @override
  State<PlantEvaluationSpecialPage> createState() =>
      _PlantEvaluationSpecialPageState();
}

class _PlantEvaluationSpecialPageState
    extends State<PlantEvaluationSpecialPage> {
  final local = LocalDb.instance;
  final uuid = const Uuid();
  final picker = ImagePicker();

  String? tableDestino;
  List<Map<String, dynamic>> fields = [];
  List<Map<String, dynamic>> lotesVariedades = [];
  final controllers = <String, TextEditingController>{};
  final dropdownValues = <String, int?>{};
  final imageValues = <String, String?>{};
  final savedPlants = <int>{};
  int currentPlant = 1;
  bool loading = true;
  bool pickingPhoto = false;
  bool savingPlant = false;

  String get title => widget.screenKind == PlantScreenKind.fenologia
      ? 'Plagas y Enfermedades'
      : 'Conteo de Fruta';

  String get plantTitle => widget.screenKind == PlantScreenKind.fenologia
      ? 'Evaluación Planta $currentPlant'
      : 'Evaluación Planta $currentPlant';

  String get findingTitle =>
      widget.screenKind == PlantScreenKind.fenologia ? 'Hallazgos' : 'Estadios';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final table = await _resolveTableDestino();
    final rows = table == null
        ? <Map<String, dynamic>>[]
        : await local.where(
            'local_form_fields',
            'tabla_destino = ? and activo = 1',
            [table],
            orderBy: 'orden',
          );

    final lotes =
        await local.getAll('local_lotes_variedades', orderBy: 'turno');

    for (final c in controllers.values) {
      c.dispose();
    }
    controllers.clear();
    dropdownValues.clear();
    imageValues.clear();

    for (final field in rows) {
      final campo = _campo(field);
      final tipo = _tipo(field);
      if (campo.isEmpty ||
          tipo == 'hidden' ||
          tipo == 'hidden_id' ||
          tipo == 'calculated') continue;
      if (tipo == 'boolean_int') {
        dropdownValues[campo] = null;
      } else if (tipo == 'photo') {
        imageValues[campo] = null;
      } else {
        final c = TextEditingController();
        if (tipo == 'date')
          c.text = DateTime.now().toIso8601String().substring(0, 10);
        controllers[campo] = c;
      }
    }

    if (!mounted) return;
    setState(() {
      tableDestino = table;
      fields = rows;
      lotesVariedades = lotes;
      loading = false;
    });
  }

  Future<String?> _resolveTableDestino() async {
    final direct = _clean(widget.format['tabla_destino']);
    if (direct != null) return direct;
    final tableRows = await local.where(
      'local_format_tables',
      'formato_id = ? and activo = 1',
      [widget.format['id']],
      orderBy: 'orden',
    );
    if (tableRows.isEmpty) return null;
    return _clean(tableRows.first['tabla_destino']);
  }

  String? _clean(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty || s.toUpperCase() == 'EMPTY' || s.toUpperCase() == 'NULL')
      return null;
    return s;
  }

  String _campo(Map<String, dynamic> f) => f['campo']?.toString() ?? '';
  String _etiqueta(Map<String, dynamic> f) =>
      f['etiqueta']?.toString() ?? _campo(f);
  String _tipo(Map<String, dynamic> f) {
    final raw = (f['tipo']?.toString() ?? 'text').trim().toLowerCase();
    if (raw == 'boolean' ||
        raw == 'bool' ||
        raw == 'boolean_int' ||
        raw == 'boolean_01') return 'boolean_int';
    if (raw == 'checkbox' || raw == 'check') return 'checkbox';
    if (raw == 'switch' || raw == 'toggle') return 'switch';
    if (raw == 'rating' || raw == 'stars') return 'rating';
    if (raw == 'slider' || raw == 'range') return 'slider';
    if (raw == 'email' || raw == 'phone' || raw == 'url' || raw == 'percent')
      return raw;
    if (raw == 'hidden_id') return 'hidden_id';
    if (raw == 'integer' || raw == 'int') return 'integer';
    return raw;
  }

  String _normalizarNombreCampo(String value) {
    var s = value.trim().toUpperCase();
    const acentos = {
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'Ü': 'U',
      'Ñ': 'N',
    };
    acentos.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    return s.replaceAll(RegExp(r'^_|_$'), '');
  }

  bool _isTurnoOrLoteCampo(String campo, [String? etiqueta]) {
    final valores = {
      _normalizarNombreCampo(campo),
      if (etiqueta != null) _normalizarNombreCampo(etiqueta),
    };
    return valores.any(
        (c) => c == 'TURNO' || c == 'TURNOS' || c == 'LOTE' || c == 'LOTES');
  }

  bool _isVariedadCampo(String campo, [String? etiqueta]) {
    final valores = {
      _normalizarNombreCampo(campo),
      if (etiqueta != null) _normalizarNombreCampo(etiqueta),
    };
    return valores.any((c) => c == 'VARIEDAD' || c == 'VARIEDADES');
  }

  List<String> _turnosUnicos() {
    final seen = <String>{};
    final out = <String>[];
    for (final row in lotesVariedades) {
      final turno = row['turno']?.toString().trim() ?? '';
      if (turno.isEmpty || seen.contains(turno)) continue;
      seen.add(turno);
      out.add(turno);
    }
    return out;
  }

  void _setVariedadFromTurno(String? turno) {
    if (turno == null || turno.trim().isEmpty) return;
    final t = turno.trim();
    final matches = lotesVariedades
        .where((e) => e['turno']?.toString().trim() == t)
        .toList();
    if (matches.isEmpty) return;
    final variedad = matches.first['variedad']?.toString().trim() ?? '';
    for (final field in fields) {
      final campo = _campo(field);
      final etiqueta = _etiqueta(field);
      if (_isVariedadCampo(campo, etiqueta) && controllers.containsKey(campo)) {
        controllers[campo]!.text = variedad;
      }
    }
  }

  bool _isPhotoField(Map<String, dynamic> f) =>
      _tipo(f) == 'photo' || _campo(f).toUpperCase().startsWith('FOTO');

  bool _isHeaderField(Map<String, dynamic> f) {
    final campo = _campo(f).toUpperCase();
    final tipo = _tipo(f);
    if (tipo == 'hidden' ||
        tipo == 'hidden_id' ||
        tipo == 'photo' ||
        tipo == 'signature' ||
        tipo == 'calculated') return false;
    if (tipo == 'boolean_int' || tipo == 'checkbox' || tipo == 'switch')
      return false;
    if (campo.contains('OBSERV')) return false;
    if (campo.contains('PLANTA')) return false;
    if (campo.contains('HALLAZGO')) return false;
    if (widget.screenKind == PlantScreenKind.conteoFruta &&
        (campo.contains('ESTADIO') || campo.contains('TIPO'))) return false;
    return true;
  }

  bool _isEvaluationField(Map<String, dynamic> f) {
    final tipo = _tipo(f);
    final campo = _campo(f).toUpperCase();
    if (_isHeaderField(f) || _isPhotoField(f)) return false;
    if (tipo == 'hidden' ||
        tipo == 'hidden_id' ||
        tipo == 'signature' ||
        tipo == 'calculated') return false;
    if (campo.contains('OBSERV')) return true;
    return true;
  }

  Future<void> _pickPhoto(String campo) async {
    if (pickingPhoto || savingPlant) return;
    FocusScope.of(context).unfocus();
    final count =
        imageValues.values.where((v) => v != null && v.isNotEmpty).length;
    if (imageValues[campo] == null && count >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Máximo 3 fotos por registro.')),
      );
      return;
    }
    setState(() => pickingPhoto = true);
    try {
      final file = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 45,
          maxWidth: 800,
          maxHeight: 800);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() =>
          imageValues[campo] = 'data:image/jpeg;base64,${base64Encode(bytes)}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir la cámara: $e')));
    } finally {
      if (mounted) setState(() => pickingPhoto = false);
    }
  }

  dynamic _valueForField(Map<String, dynamic> f, String idFilaSerial) {
    final campo = _campo(f);
    final tipo = _tipo(f);
    if (tipo == 'hidden_id') return null;
    if (tipo == 'hidden') return idFilaSerial;
    if (_isPhotoField(f)) return imageValues[campo];
    if (tipo == 'boolean_int' || tipo == 'checkbox' || tipo == 'switch')
      return dropdownValues[campo] ?? 0;
    if (tipo == 'calculated') return null;
    final raw = controllers[campo]?.text.trim() ?? '';
    if (raw.isEmpty) return null;
    if (tipo == 'number') return double.tryParse(raw.replaceAll(',', '.'));
    if (tipo == 'integer') return int.tryParse(raw);
    return raw;
  }

  Future<void> _savePlant({required bool moveNext}) async {
    if (savingPlant || pickingPhoto) return;
    FocusScope.of(context).unfocus();
    final table = tableDestino;
    if (table == null || table.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tabla destino no configurada.')));
      return;
    }
    final cachedUserId = await LocalSession().cachedUserId();
    final userId =
        Supabase.instance.client.auth.currentUser?.id ?? cachedUserId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay usuario local disponible.')));
      return;
    }

    final idLocal = uuid.v4();
    final idFilaSerial = '${uuid.v4()}_P$currentPlant';
    final payload = <String, dynamic>{
      'id_local': idLocal,
    };
    for (final f in fields) {
      final campo = _campo(f);
      if (campo.isEmpty) continue;
      final value = _valueForField(f, idFilaSerial);
      if (value != null) payload[campo] = value;
    }

    setState(() => savingPlant = true);
    try {
      await local.insertPending({
        'id_local': idLocal,
        'user_id': userId,
        'modulo_id': widget.moduleId,
        'formato_id': widget.format['id'],
        'formato_tabla_id': null,
        'tabla_destino': table,
        'payload_json': jsonEncode(payload),
        'estado': 'pendiente',
        'intentos': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar localmente: $e')));
      setState(() => savingPlant = false);
      return;
    }

    widget.onLocalChanged?.call();
    if (!mounted) return;
    setState(() {
      savingPlant = false;
      savedPlants.add(currentPlant);
      if (moveNext) currentPlant++;
      for (final entry in dropdownValues.entries.toList()) {
        dropdownValues[entry.key] = null;
      }
      for (final f in fields.where(_isEvaluationField)) {
        controllers[_campo(f)]?.clear();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Planta ${moveNext ? currentPlant - 1 : currentPlant} guardada localmente.')),
    );
    if (!moveNext) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.onSavedAndExit != null) {
          widget.onSavedAndExit!.call();
        } else {
          Navigator.of(context).maybePop();
        }
      });
    }
  }

  Widget _twoColumnFields(List<Map<String, dynamic>> rows) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: rows.map((f) {
        return SizedBox(
          width: (MediaQuery.of(context).size.width - 38) / 2,
          child: _inputForField(f),
        );
      }).toList(),
    );
  }

  Widget _inputForField(Map<String, dynamic> f) {
    final campo = _campo(f);
    final etiqueta = _etiqueta(f);
    final tipo = _tipo(f);

    final turnosDisponibles = _turnosUnicos();
    if (_isTurnoOrLoteCampo(campo, etiqueta) && turnosDisponibles.isNotEmpty) {
      final current = controllers[campo]?.text.trim();
      return DropdownButtonFormField<String>(
        value: (current != null &&
                current.isNotEmpty &&
                turnosDisponibles.contains(current))
            ? current
            : null,
        decoration: _FormVisuals.decoration(etiqueta),
        style: const TextStyle(fontSize: 12.5, color: Colors.black87),
        items: turnosDisponibles.map((turno) {
          return DropdownMenuItem<String>(value: turno, child: Text(turno));
        }).toList(),
        onChanged: (value) => setState(() {
          controllers[campo]?.text = value ?? '';
          _setVariedadFromTurno(value);
        }),
      );
    }
    if (_isVariedadCampo(campo)) {
      return TextField(
        controller: controllers[campo],
        readOnly: true,
        style: _FormVisuals.fieldTextStyle,
        decoration: _FormVisuals.decoration(etiqueta),
      );
    }
    if (tipo == 'date') {
      return TextField(
        controller: controllers[campo],
        readOnly: true,
        style: _FormVisuals.fieldTextStyle,
        decoration:
            _FormVisuals.decoration(etiqueta, icon: Icons.calendar_month),
        onTap: () async {
          final now = DateTime.now();
          final minDate = DateTime(1900);
          final maxDate = DateTime(now.year + 20);
          final picked = await showDatePicker(
              context: context,
              firstDate: minDate,
              lastDate: maxDate,
              initialDate: _safeDatePickerInitialDate(
                  DateTime.tryParse(controllers[campo]?.text.trim() ?? '') ??
                      now,
                  minDate,
                  maxDate));
          if (picked != null)
            controllers[campo]?.text =
                picked.toIso8601String().substring(0, 10);
        },
      );
    }
    if (tipo == 'checkbox') {
      final checked = (dropdownValues[campo] ?? 0) == 1;
      return CheckboxListTile(
        value: checked,
        title: Text(etiqueta, style: const TextStyle(fontSize: 12.5)),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        onChanged: (v) =>
            setState(() => dropdownValues[campo] = v == true ? 1 : 0),
      );
    }
    if (tipo == 'switch') {
      final checked = (dropdownValues[campo] ?? 0) == 1;
      return SwitchListTile(
        value: checked,
        title: Text(etiqueta, style: const TextStyle(fontSize: 12.5)),
        subtitle: Text(checked ? 'Sí / 1' : 'No / 0'),
        contentPadding: EdgeInsets.zero,
        onChanged: (v) => setState(() => dropdownValues[campo] = v ? 1 : 0),
      );
    }
    if (tipo == 'boolean_int') {
      return DropdownButtonFormField<int>(
        value: dropdownValues[campo],
        decoration: _FormVisuals.decoration(etiqueta),
        style: const TextStyle(fontSize: 12.5, color: Colors.black87),
        items: const [
          DropdownMenuItem(value: 1, child: Text('1 / Sí')),
          DropdownMenuItem(value: 0, child: Text('0 / No'))
        ],
        onChanged: (v) => setState(() => dropdownValues[campo] = v),
      );
    }
    return TextField(
      controller: controllers[campo],
      style: _FormVisuals.fieldTextStyle,
      minLines: tipo == 'multiline' ? 2 : 1,
      maxLines: tipo == 'multiline' ? 4 : 1,
      keyboardType: (tipo == 'number' || tipo == 'percent')
          ? const TextInputType.numberWithOptions(decimal: true)
          : tipo == 'email'
              ? TextInputType.emailAddress
              : tipo == 'phone'
                  ? TextInputType.phone
                  : tipo == 'url'
                      ? TextInputType.url
                      : TextInputType.text,
      decoration: _FormVisuals.decoration(etiqueta),
    );
  }

  Widget _photoBar() {
    final photos = fields.where(_isPhotoField).take(3).toList();
    if (photos.isEmpty) return const SizedBox.shrink();
    return Row(
      children: photos.map((f) {
        final campo = _campo(f);
        final has = imageValues[campo] != null;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: OutlinedButton.icon(
              onPressed: () => _pickPhoto(campo),
              icon:
                  Icon(has ? Icons.check_circle : Icons.photo_camera, size: 16),
              label: Text(_etiqueta(f), style: const TextStyle(fontSize: 11)),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final headerFields = fields.where(_isHeaderField).take(8).toList();
    final evalFields = fields.where(_isEvaluationField).toList();

    return Scaffold(
      appBar: _zumacFormatAppBar(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        onBack: widget.onSavedAndExit == null
            ? null
            : () => widget.onSavedAndExit!.call(),
        actions: [
          IconButton(
              onPressed: savingPlant ? null : () => _savePlant(moveNext: false),
              icon: const Icon(Icons.save))
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: savingPlant ? null : () => _savePlant(moveNext: false),
        tooltip: 'Guardar',
        child: savingPlant
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.save),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(10),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Cabecera',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          _twoColumnFields(headerFields),
                          const SizedBox(height: 8),
                          _photoBar(),
                        ]),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(plantTitle,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800))),
                            Text('Guardadas: ${savedPlants.length}',
                                style: const TextStyle(fontSize: 11.5)),
                          ]),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                  onPressed: currentPlant > 1
                                      ? () => setState(() => currentPlant--)
                                      : null,
                                  icon: const Icon(Icons.chevron_left)),
                              Expanded(
                                child: Center(
                                    child: Text('Planta $currentPlant',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700))),
                              ),
                              IconButton(
                                  onPressed: () =>
                                      setState(() => currentPlant++),
                                  icon: const Icon(Icons.chevron_right)),
                            ],
                          ),
                          const Divider(),
                          Text(findingTitle,
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          _twoColumnFields(evalFields.isEmpty
                              ? fields
                                  .where((f) => !_isPhotoField(f))
                                  .skip(headerFields.length)
                                  .take(8)
                                  .toList()
                              : evalFields),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {},
                                  icon: const Icon(Icons.add, size: 16),
                                  label: Text(widget.screenKind ==
                                          PlantScreenKind.fenologia
                                      ? '+ Hallazgo'
                                      : '+ Estadio'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: savingPlant
                                      ? null
                                      : () => _savePlant(moveNext: true),
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Planta'),
                                ),
                              ),
                            ],
                          ),
                        ]),
                  ),
                ),
                const SizedBox(height: 84),
              ],
            ),
    );
  }
}

class MachinerySpecialPage extends StatefulWidget {
  final String moduleId;
  final Map<String, dynamic> format;
  final Map<String, dynamic>? initialPayload;
  final String? editIdLocal;
  final VoidCallback? onLocalChanged;
  final VoidCallback? onSavedAndExit;

  const MachinerySpecialPage({
    super.key,
    required this.moduleId,
    required this.format,
    this.initialPayload,
    this.editIdLocal,
    this.onLocalChanged,
    this.onSavedAndExit,
  });

  @override
  State<MachinerySpecialPage> createState() => _MachinerySpecialPageState();
}

class _MachinerySpecialPageState extends State<MachinerySpecialPage> {
  final local = LocalDb.instance;
  final uuid = const Uuid();
  final picker = ImagePicker();

  String? tableDestino;
  List<Map<String, dynamic>> fields = [];
  List<Map<String, dynamic>> lotesVariedades = [];
  final controllers = <String, TextEditingController>{};
  final dropdownValues = <String, int?>{};
  final signatureValues = <String, String?>{};
  final imageValues = <String, String?>{};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final table = await _resolveTableDestino();
    final rows = table == null
        ? <Map<String, dynamic>>[]
        : await local.where(
            'local_form_fields', 'tabla_destino = ? and activo = 1', [table],
            orderBy: 'orden');

    final lotes =
        await local.getAll('local_lotes_variedades', orderBy: 'turno');

    for (final c in controllers.values) {
      c.dispose();
    }
    controllers.clear();
    dropdownValues.clear();
    signatureValues.clear();
    imageValues.clear();

    final initial = widget.initialPayload ?? <String, dynamic>{};
    for (final f in rows) {
      final campo = _campo(f);
      final tipo = _tipo(f);
      if (campo.isEmpty ||
          tipo == 'hidden' ||
          tipo == 'hidden_id' ||
          tipo == 'calculated') continue;
      final initialValue = initial[campo] ??
          initial[campo.toUpperCase()] ??
          initial[campo.toLowerCase()];
      if (tipo == 'boolean_int') {
        dropdownValues[campo] =
            initialValue == null ? null : int.tryParse(initialValue.toString());
      } else if (tipo == 'signature') {
        signatureValues[campo] = initialValue?.toString();
      } else if (tipo == 'photo') {
        imageValues[campo] = initialValue?.toString();
      } else {
        final c = TextEditingController();
        if (initialValue != null && initialValue.toString().trim().isNotEmpty) {
          c.text = initialValue.toString();
        } else if (tipo == 'date') {
          c.text = DateTime.now().toIso8601String().substring(0, 10);
        }
        controllers[campo] = c;
      }
    }
    if (!mounted) return;
    setState(() {
      tableDestino = table;
      fields = rows;
      lotesVariedades = lotes;
      loading = false;
    });
  }

  Future<String?> _resolveTableDestino() async {
    final direct = _clean(widget.format['tabla_destino']);
    if (direct != null) return direct;
    final rows = await local.where('local_format_tables',
        'formato_id = ? and activo = 1', [widget.format['id']],
        orderBy: 'orden');
    return rows.isEmpty ? null : _clean(rows.first['tabla_destino']);
  }

  String? _clean(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty || s.toUpperCase() == 'EMPTY' || s.toUpperCase() == 'NULL')
      return null;
    return s;
  }

  String _campo(Map<String, dynamic> f) => f['campo']?.toString() ?? '';
  String _etiqueta(Map<String, dynamic> f) =>
      f['etiqueta']?.toString() ?? _campo(f);
  String _tipo(Map<String, dynamic> f) {
    final raw = (f['tipo']?.toString() ?? 'text').trim().toLowerCase();
    if (raw == 'boolean' ||
        raw == 'bool' ||
        raw == 'boolean_int' ||
        raw == 'boolean_01') return 'boolean_int';
    if (raw == 'checkbox' || raw == 'check') return 'checkbox';
    if (raw == 'switch' || raw == 'toggle') return 'switch';
    if (raw == 'rating' || raw == 'stars') return 'rating';
    if (raw == 'slider' || raw == 'range') return 'slider';
    if (raw == 'email' || raw == 'phone' || raw == 'url' || raw == 'percent')
      return raw;
    if (raw == 'integer' || raw == 'int') return 'integer';
    if (raw == 'hidden_id') return 'hidden_id';
    return raw;
  }

  String _normalizarNombreCampo(String value) {
    var s = value.trim().toUpperCase();
    const acentos = {
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'Ü': 'U',
      'Ñ': 'N',
    };
    acentos.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    return s.replaceAll(RegExp(r'^_|_$'), '');
  }

  bool _isTurnoOrLoteCampo(String campo, [String? etiqueta]) {
    final valores = {
      _normalizarNombreCampo(campo),
      if (etiqueta != null) _normalizarNombreCampo(etiqueta),
    };
    return valores.any(
        (c) => c == 'TURNO' || c == 'TURNOS' || c == 'LOTE' || c == 'LOTES');
  }

  bool _isVariedadCampo(String campo, [String? etiqueta]) {
    final valores = {
      _normalizarNombreCampo(campo),
      if (etiqueta != null) _normalizarNombreCampo(etiqueta),
    };
    return valores.any((c) => c == 'VARIEDAD' || c == 'VARIEDADES');
  }

  List<String> _turnosUnicos() {
    final seen = <String>{};
    final out = <String>[];
    for (final row in lotesVariedades) {
      final turno = row['turno']?.toString().trim() ?? '';
      if (turno.isEmpty || seen.contains(turno)) continue;
      seen.add(turno);
      out.add(turno);
    }
    return out;
  }

  void _setVariedadFromTurno(String? turno) {
    if (turno == null || turno.trim().isEmpty) return;
    final t = turno.trim();
    final matches = lotesVariedades
        .where((e) => e['turno']?.toString().trim() == t)
        .toList();
    if (matches.isEmpty) return;
    final variedad = matches.first['variedad']?.toString().trim() ?? '';
    for (final field in fields) {
      final campo = _campo(field);
      final etiqueta = _etiqueta(field);
      if (_isVariedadCampo(campo, etiqueta) && controllers.containsKey(campo)) {
        controllers[campo]!.text = variedad;
      }
    }
  }

  bool _isChecklist(Map<String, dynamic> f) =>
      ['boolean_int', 'checkbox', 'switch'].contains(_tipo(f));
  bool _isPhoto(Map<String, dynamic> f) =>
      _tipo(f) == 'photo' || _campo(f).toUpperCase().startsWith('FOTO');
  bool _isSignature(Map<String, dynamic> f) => _tipo(f) == 'signature';
  bool _isHeader(Map<String, dynamic> f) {
    final tipo = _tipo(f);
    if (tipo == 'hidden' || tipo == 'hidden_id' || tipo == 'calculated')
      return false;
    return !_isChecklist(f) && !_isPhoto(f) && !_isSignature(f);
  }

  Future<void> _pickPhoto(String campo) async {
    final count =
        imageValues.values.where((v) => v != null && v.isNotEmpty).length;
    if (imageValues[campo] == null && count >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Máximo 3 fotos por registro.')));
      return;
    }
    try {
      final file = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 45,
          maxWidth: 800,
          maxHeight: 800);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() =>
          imageValues[campo] = 'data:image/jpeg;base64,${base64Encode(bytes)}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir la cámara: $e')));
    }
  }

  Future<void> _captureSignature(String campo) async {
    final bytes = await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const SignatureDialog());
    if (bytes == null) return;
    setState(() => signatureValues[campo] =
        'data:image/png;base64,${base64Encode(bytes)}');
  }

  Widget _field(Map<String, dynamic> f) {
    final campo = _campo(f);
    final tipo = _tipo(f);
    final etiqueta = _etiqueta(f);

    final turnosDisponibles = _turnosUnicos();
    if (_isTurnoOrLoteCampo(campo, etiqueta) && turnosDisponibles.isNotEmpty) {
      final current = controllers[campo]?.text.trim();
      return DropdownButtonFormField<String>(
        value: (current != null &&
                current.isNotEmpty &&
                turnosDisponibles.contains(current))
            ? current
            : null,
        decoration: _FormVisuals.decoration(etiqueta),
        style: const TextStyle(fontSize: 12.5, color: Colors.black87),
        items: turnosDisponibles.map((turno) {
          return DropdownMenuItem<String>(value: turno, child: Text(turno));
        }).toList(),
        onChanged: (value) => setState(() {
          controllers[campo]?.text = value ?? '';
          _setVariedadFromTurno(value);
        }),
      );
    }
    if (_isVariedadCampo(campo)) {
      return TextField(
        controller: controllers[campo],
        readOnly: true,
        style: _FormVisuals.fieldTextStyle,
        decoration: _FormVisuals.decoration(etiqueta),
      );
    }
    if (tipo == 'date') {
      return TextField(
        controller: controllers[campo],
        readOnly: true,
        style: _FormVisuals.fieldTextStyle,
        decoration:
            _FormVisuals.decoration(etiqueta, icon: Icons.calendar_month),
        onTap: () async {
          final now = DateTime.now();
          final minDate = DateTime(1900);
          final maxDate = DateTime(now.year + 20);
          final picked = await showDatePicker(
              context: context,
              firstDate: minDate,
              lastDate: maxDate,
              initialDate: _safeDatePickerInitialDate(
                  DateTime.tryParse(controllers[campo]?.text.trim() ?? '') ??
                      now,
                  minDate,
                  maxDate));
          if (picked != null)
            controllers[campo]?.text =
                picked.toIso8601String().substring(0, 10);
        },
      );
    }
    return TextField(
      controller: controllers[campo],
      style: _FormVisuals.fieldTextStyle,
      minLines: tipo == 'multiline' ? 2 : 1,
      maxLines: tipo == 'multiline' ? 4 : 1,
      keyboardType: (tipo == 'number' || tipo == 'percent')
          ? const TextInputType.numberWithOptions(decimal: true)
          : tipo == 'email'
              ? TextInputType.emailAddress
              : tipo == 'phone'
                  ? TextInputType.phone
                  : tipo == 'url'
                      ? TextInputType.url
                      : TextInputType.text,
      decoration: _FormVisuals.decoration(etiqueta),
    );
  }

  Widget _twoColumn(List<Map<String, dynamic>> rows) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: rows
          .map((f) => SizedBox(
              width: (MediaQuery.of(context).size.width - 38) / 2,
              child: _field(f)))
          .toList(),
    );
  }

  dynamic _valueFor(Map<String, dynamic> f, String idLocal) {
    final campo = _campo(f);
    final tipo = _tipo(f);
    if (tipo == 'hidden_id') return null;
    if (tipo == 'hidden') return idLocal;
    if (_isChecklist(f)) return dropdownValues[campo];
    if (_isPhoto(f)) return imageValues[campo];
    if (_isSignature(f)) return signatureValues[campo];
    if (tipo == 'calculated') return null;
    final raw = controllers[campo]?.text.trim() ?? '';
    if (raw.isEmpty) return null;
    if (tipo == 'number') return double.tryParse(raw.replaceAll(',', '.'));
    if (tipo == 'integer') return int.tryParse(raw);
    return raw;
  }

  Future<void> _save() async {
    final table = tableDestino;
    if (table == null || table.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tabla destino no configurada.')));
      return;
    }
    final cachedUserId = await LocalSession().cachedUserId();
    final userId =
        Supabase.instance.client.auth.currentUser?.id ?? cachedUserId;
    if (userId == null) return;
    final id =
        (widget.editIdLocal != null && widget.editIdLocal!.trim().isNotEmpty)
            ? widget.editIdLocal!.trim()
            : uuid.v4();
    final payload =
        Map<String, dynamic>.from(widget.initialPayload ?? <String, dynamic>{});
    payload['id_local'] = id;
    for (final f in fields) {
      final campo = _campo(f);
      if (campo.isEmpty) continue;
      final value = _valueFor(f, id);
      if (value != null) payload[campo] = value;
    }
    if (widget.editIdLocal != null && widget.editIdLocal!.isNotEmpty) {
      await local.deleteRecord(widget.editIdLocal!);
    }
    await local.insertPending({
      'id_local': id,
      'user_id': userId,
      'modulo_id': widget.moduleId,
      'formato_id': widget.format['id'],
      'formato_tabla_id': null,
      'tabla_destino': table,
      'payload_json': jsonEncode(payload),
      'estado': 'pendiente',
      'intentos': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    widget.onLocalChanged?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Registro de maquinaria guardado localmente.')));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.onSavedAndExit != null) {
        widget.onSavedAndExit!.call();
      } else {
        Navigator.of(context).maybePop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final header = fields.where(_isHeader).toList();
    final checklist = fields.where(_isChecklist).toList();
    final photos = fields.where(_isPhoto).take(3).toList();
    final signatures = fields.where(_isSignature).toList();

    return Scaffold(
      appBar: _zumacFormatAppBar(
        title: const Text('Horas Maquinaria', style: TextStyle(fontSize: 16)),
        onBack: widget.onSavedAndExit == null
            ? null
            : () => widget.onSavedAndExit!.call(),
        actions: [IconButton(onPressed: _save, icon: const Icon(Icons.save))],
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: _save, tooltip: 'Guardar', child: const Icon(Icons.save)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(10),
              children: [
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: _twoColumn(header))),
                const SizedBox(height: 8),
                if (photos.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                          children: photos.map((f) {
                        final campo = _campo(f);
                        final has = imageValues[campo] != null;
                        return Expanded(
                            child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: OutlinedButton.icon(
                              onPressed: () => _pickPhoto(campo),
                              icon: Icon(
                                  has ? Icons.check_circle : Icons.photo_camera,
                                  size: 16),
                              label: Text(_etiqueta(f),
                                  style: const TextStyle(fontSize: 11))),
                        ));
                      }).toList()),
                    ),
                  ),
                const SizedBox(height: 8),
                if (checklist.isNotEmpty)
                  Card(
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      title: const Text('Check List Maquinaria',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: checklist.map((f) {
                            final campo = _campo(f);
                            return SizedBox(
                              width:
                                  (MediaQuery.of(context).size.width - 38) / 2,
                              child: DropdownButtonFormField<int>(
                                value: dropdownValues[campo],
                                decoration:
                                    _FormVisuals.decoration(_etiqueta(f)),
                                style: const TextStyle(
                                    fontSize: 12.5, color: Colors.black87),
                                items: const [
                                  DropdownMenuItem(
                                      value: 1, child: Text('1 / Sí')),
                                  DropdownMenuItem(
                                      value: 0, child: Text('0 / No'))
                                ],
                                onChanged: (v) =>
                                    setState(() => dropdownValues[campo] = v),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                if (signatures.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: signatures.map((f) {
                          final campo = _campo(f);
                          final has = signatureValues[campo] != null;
                          return SizedBox(
                            width: (MediaQuery.of(context).size.width - 38) / 2,
                            child: OutlinedButton.icon(
                              onPressed: () => _captureSignature(campo),
                              icon: Icon(has ? Icons.check_circle : Icons.draw,
                                  size: 16),
                              label: Text(_etiqueta(f),
                                  style: const TextStyle(fontSize: 11)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                const SizedBox(height: 84),
              ],
            ),
    );
  }
}
