import 'package:appgt_offline_subtables/core/services/attendance_sync_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('una asistencia nueva conserva su id local para subirla', () {
    final resolution = reconcileAttendanceForSync(
      localPayload: {
        'id_local': 'local-1',
        'DNI': '12345678',
        'FECHA': '2026-10-05',
        'HORA_INGRESO': '07:30',
      },
    );

    expect(resolution.action, AttendanceSyncAction.upload);
    expect(resolution.payload['id_local'], 'local-1');
  });

  test('omite un ingreso que ya existe en Supabase con otro id', () {
    final resolution = reconcileAttendanceForSync(
      localPayload: {
        'id_local': 'local-nuevo',
        'DNI': '12345678',
        'FECHA': '2026-10-05',
        'HORA_INGRESO': '08:15',
      },
      remotePayload: {
        'id_local': 'remoto-original',
        'DNI': '12345678',
        'FECHA': '2026-10-05',
        'HORA_INGRESO': '07:30',
      },
    );

    expect(resolution.action, AttendanceSyncAction.skipExistingIngress);
    expect(resolution.shouldUpload, isFalse);
  });

  test('fusiona una salida local con el ingreso remoto existente', () {
    final resolution = reconcileAttendanceForSync(
      localPayload: {
        'id_local': 'local-nuevo',
        'DNI': '12345678',
        'FECHA': '2026-10-05',
        'HORA_INGRESO': '08:15',
        'HORA_SALIDA': '15:30',
        'FECHA_SALIDA': '2026-10-05',
      },
      remotePayload: {
        'id_local': 'remoto-original',
        'DNI': '12345678',
        'FECHA': '2026-10-05',
        'HORA_INGRESO': '07:30',
        'HORA_SALIDA': null,
      },
    );

    expect(resolution.action, AttendanceSyncAction.updateRemoteExit);
    expect(resolution.payload['id_local'], 'remoto-original');
    expect(resolution.payload['HORA_INGRESO'], '07:30');
    expect(resolution.payload['HORA_SALIDA'], '15:30');
    expect(resolution.payload['HORAS_ASISTENCIA'], 8.0);
  });

  test('omite una salida si Supabase ya tiene la salida diaria', () {
    final resolution = reconcileAttendanceForSync(
      localPayload: {
        'id_local': 'local-nuevo',
        'DNI': '12345678',
        'FECHA': '2026-10-05',
        'HORA_SALIDA': '15:35',
      },
      remotePayload: {
        'id_local': 'remoto-original',
        'DNI': '12345678',
        'FECHA': '2026-10-05',
        'HORA_INGRESO': '07:30',
        'HORA_SALIDA': '15:30',
      },
    );

    expect(resolution.action, AttendanceSyncAction.skipExistingExit);
    expect(resolution.shouldUpload, isFalse);
  });
}
