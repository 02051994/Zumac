enum AttendanceSyncAction {
  upload,
  updateRemoteExit,
  skipExistingIngress,
  skipExistingExit,
}

class AttendanceSyncResolution {
  final AttendanceSyncAction action;
  final Map<String, dynamic> payload;

  const AttendanceSyncResolution({
    required this.action,
    required this.payload,
  });

  bool get shouldUpload =>
      action == AttendanceSyncAction.upload ||
      action == AttendanceSyncAction.updateRemoteExit;
}

String _attendanceDigits(String value) =>
    value.replaceAll(RegExp(r'[^0-9]'), '');

dynamic _attendanceValue(
  Map<String, dynamic> payload,
  List<String> candidates,
) {
  final wanted = candidates.map((value) => value.trim().toUpperCase()).toSet();
  for (final entry in payload.entries) {
    if (wanted.contains(entry.key.trim().toUpperCase())) return entry.value;
  }
  return null;
}

String attendanceBusinessKey(Map<String, dynamic> payload) {
  final dni = _attendanceDigits(
    (_attendanceValue(payload, const ['DNI', 'DOCUMENTO']) ?? '').toString(),
  );
  final rawDate =
      (_attendanceValue(payload, const ['FECHA', 'FECHA_INGRESO']) ?? '')
          .toString()
          .trim();
  final date = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
  if (dni.isEmpty || date.isEmpty) return '';
  return '$dni|$date';
}

bool attendancePayloadHasExit(Map<String, dynamic> payload) {
  final value = (_attendanceValue(payload, const ['HORA_SALIDA']) ?? '')
      .toString()
      .trim();
  return value.isNotEmpty && value.toLowerCase() != 'null';
}

double? _attendanceHoursBetween(String start, String end) {
  List<int>? parts(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) return null;
    return [hour, minute];
  }

  final startParts = parts(start);
  final endParts = parts(end);
  if (startParts == null || endParts == null) return null;
  final startMinutes = startParts[0] * 60 + startParts[1];
  var endMinutes = endParts[0] * 60 + endParts[1];
  if (endMinutes < startMinutes) endMinutes += 24 * 60;
  return double.parse(((endMinutes - startMinutes) / 60).toStringAsFixed(2));
}

AttendanceSyncResolution reconcileAttendanceForSync({
  required Map<String, dynamic> localPayload,
  Map<String, dynamic>? remotePayload,
}) {
  if (remotePayload == null || remotePayload.isEmpty) {
    return AttendanceSyncResolution(
      action: AttendanceSyncAction.upload,
      payload: Map<String, dynamic>.from(localPayload),
    );
  }

  final localId =
      (_attendanceValue(localPayload, const ['id_local', 'ID_LOCAL']) ?? '')
          .toString()
          .trim();
  final remoteId =
      (_attendanceValue(remotePayload, const ['id_local', 'ID_LOCAL']) ?? '')
          .toString()
          .trim();
  if (localId.isNotEmpty && localId == remoteId) {
    return AttendanceSyncResolution(
      action: AttendanceSyncAction.upload,
      payload: Map<String, dynamic>.from(localPayload),
    );
  }

  final localHasExit = attendancePayloadHasExit(localPayload);
  final remoteHasExit = attendancePayloadHasExit(remotePayload);
  if (!localHasExit) {
    return AttendanceSyncResolution(
      action: AttendanceSyncAction.skipExistingIngress,
      payload: Map<String, dynamic>.from(remotePayload),
    );
  }
  if (remoteHasExit) {
    return AttendanceSyncResolution(
      action: AttendanceSyncAction.skipExistingExit,
      payload: Map<String, dynamic>.from(remotePayload),
    );
  }

  final merged = Map<String, dynamic>.from(remotePayload);
  for (final field in const [
    'HORA_SALIDA',
    'FECHA_SALIDA',
    'estado_registro',
    'ESTADO_REGISTRO',
  ]) {
    final value = _attendanceValue(localPayload, [field]);
    if (value != null && value.toString().trim().isNotEmpty) {
      merged[field] = value;
    }
  }
  merged.remove('id');
  merged.remove('created_at');
  merged.remove('updated_at');

  final ingreso =
      (_attendanceValue(remotePayload, const ['HORA_INGRESO']) ?? '')
          .toString();
  final salida =
      (_attendanceValue(localPayload, const ['HORA_SALIDA']) ?? '').toString();
  final hours = _attendanceHoursBetween(ingreso, salida);
  if (hours != null) merged['HORAS_ASISTENCIA'] = hours;

  return AttendanceSyncResolution(
    action: AttendanceSyncAction.updateRemoteExit,
    payload: merged,
  );
}
