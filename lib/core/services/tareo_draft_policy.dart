import 'dart:convert';

/// Reglas puras del ciclo de vida de un tareo local.
///
/// Un tareo abierto se conserva en el dispositivo hasta que tenga hora fin y
/// haya sido cerrado explícitamente. No debe enviarse parcialmente ni bloquear
/// la sincronización de otros registros.
bool isOpenTareoDraft(Map<String, dynamic> payload) {
  String value(String key) => payload[key]?.toString().trim() ?? '';

  final horaFin =
      value('HORA_FIN').isNotEmpty ? value('HORA_FIN') : value('HORA FIN');
  final estadoAprobacion = value('ESTADO_APROBACION').toUpperCase();
  final estadoRegistro = value('estado_registro').toUpperCase();
  return horaFin.isEmpty ||
      horaFin.toLowerCase() == 'null' ||
      estadoAprobacion == 'BORRADOR' ||
      estadoRegistro == 'PENDIENTE';
}

double tareoHoursMissingForFullDay(
  double accumulatedHours, {
  double requiredHours = 8,
}) {
  if (requiredHours <= 0) return 0;
  return (requiredHours - accumulatedHours).clamp(0, double.infinity);
}

String tareoDraftBaseId(String idLocal) =>
    idLocal.trim().replaceFirst(RegExp(r'_[0-9]+$'), '');

dynamic _tareoPayloadValue(Map<String, dynamic> payload, List<String> keys) {
  String normalized(String value) => value
      .trim()
      .toUpperCase()
      .replaceAll('Á', 'A')
      .replaceAll('É', 'E')
      .replaceAll('Í', 'I')
      .replaceAll('Ó', 'O')
      .replaceAll('Ú', 'U')
      .replaceAll('Ü', 'U')
      .replaceAll('Ñ', 'N')
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  final wanted = keys.map(normalized).toSet();
  for (final entry in payload.entries) {
    if (wanted.contains(normalized(entry.key))) return entry.value;
  }
  return null;
}

Map<String, dynamic>? tareoPayloadFromQueueRow(Map<String, dynamic> row) {
  try {
    final decoded = jsonDecode(row['payload_json']?.toString() ?? '{}');
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

/// Un elemento de la vista diaria representa un tareo completo, aunque la
/// cola local guarde una fila independiente por cada trabajador.
class TareoDayGroup {
  final String idLocal;
  final String fecha;
  final String labor;
  final String centroCosto;
  final bool closed;
  final bool synchronized;
  final List<Map<String, dynamic>> queueRows;
  final List<Map<String, dynamic>> workerPayloads;

  const TareoDayGroup({
    required this.idLocal,
    required this.fecha,
    required this.labor,
    required this.centroCosto,
    required this.closed,
    required this.synchronized,
    required this.queueRows,
    required this.workerPayloads,
  });

  int get peopleCount {
    final dnis = workerPayloads
        .map((payload) =>
            (_tareoPayloadValue(payload, const ['DNI', 'DOCUMENTO']) ?? '')
                .toString()
                .trim())
        .where((dni) => dni.isNotEmpty)
        .toSet();
    return dnis.isEmpty ? workerPayloads.length : dnis.length;
  }

  Map<String, dynamic> get editPayload {
    if (workerPayloads.isEmpty) return const <String, dynamic>{};
    final payload = Map<String, dynamic>.from(workerPayloads.first);
    payload['__tareo_rows'] = workerPayloads
        .map((worker) => <String, dynamic>{
              'DNI':
                  (_tareoPayloadValue(worker, const ['DNI', 'DOCUMENTO']) ?? '')
                      .toString(),
              'APELLIDOS Y NOMBRES': (_tareoPayloadValue(worker, const [
                        'APELLIDOS Y NOMBRES',
                        'APELLIDOS_NOMBRES',
                        'NOMBRE COMPLETO'
                      ]) ??
                      '')
                  .toString(),
            })
        .toList();
    return payload;
  }
}

List<TareoDayGroup> groupTareoQueueRows(
  Iterable<Map<String, dynamic>> rows, {
  String? fecha,
}) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    if ((row['tabla_destino']?.toString() ?? '').toUpperCase() !=
        'GT-TAREO_PERSONAL') {
      continue;
    }
    final payload = tareoPayloadFromQueueRow(row);
    if (payload == null) continue;
    final rowDate =
        (_tareoPayloadValue(payload, const ['FECHA']) ?? '').toString().trim();
    if (fecha != null && rowDate != fecha) continue;
    final storedId = row['id_local']?.toString().trim() ?? '';
    final payloadId =
        (_tareoPayloadValue(payload, const ['id_local', 'ID_LOCAL']) ?? '')
            .toString()
            .trim();
    final baseId = tareoDraftBaseId(storedId.isNotEmpty ? storedId : payloadId);
    final fallback = [
      rowDate,
      (_tareoPayloadValue(payload, const ['CENTRO_COSTO', 'CENTRO COSTO']) ??
              '')
          .toString(),
      (_tareoPayloadValue(payload, const ['LABOR']) ?? '').toString(),
      (_tareoPayloadValue(payload, const ['HORA_INICIO', 'HORA INICIO']) ?? '')
          .toString(),
    ].join('|');
    grouped.putIfAbsent(baseId.isEmpty ? fallback : baseId, () => []).add(row);
  }

  final result = <TareoDayGroup>[];
  for (final entry in grouped.entries) {
    final payloads = entry.value
        .map(tareoPayloadFromQueueRow)
        .whereType<Map<String, dynamic>>()
        .toList();
    if (payloads.isEmpty) continue;
    final first = payloads.first;
    result.add(TareoDayGroup(
      idLocal: entry.key,
      fecha:
          (_tareoPayloadValue(first, const ['FECHA']) ?? '').toString().trim(),
      labor: (_tareoPayloadValue(first, const ['LABOR']) ?? 'Sin labor')
          .toString()
          .trim(),
      centroCosto:
          (_tareoPayloadValue(first, const ['CENTRO_COSTO', 'CENTRO COSTO']) ??
                  'Sin centro de costo')
              .toString()
              .trim(),
      closed: payloads.every((payload) => !isOpenTareoDraft(payload)),
      synchronized: entry.value
          .every((row) => (row['estado']?.toString() ?? '') == 'sincronizado'),
      queueRows: List<Map<String, dynamic>>.unmodifiable(entry.value),
      workerPayloads: List<Map<String, dynamic>>.unmodifiable(payloads),
    ));
  }
  result.sort((a, b) {
    final aCreated = a.queueRows.first['created_at']?.toString() ?? '';
    final bCreated = b.queueRows.first['created_at']?.toString() ?? '';
    return bCreated.compareTo(aCreated);
  });
  return result;
}
