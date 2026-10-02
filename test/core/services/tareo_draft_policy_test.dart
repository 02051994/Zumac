import 'package:flutter_test/flutter_test.dart';
import 'package:appgt_offline_subtables/core/services/tareo_draft_policy.dart';
import 'dart:convert';

void main() {
  group('isOpenTareoDraft', () {
    test('mantiene pendiente un tareo sin hora fin', () {
      expect(
        isOpenTareoDraft({
          'HORA_INICIO': '07:00',
          'HORA_FIN': '',
          'ESTADO_APROBACION': 'BORRADOR',
        }),
        isTrue,
      );
    });

    test('permite sincronizar un tareo cerrado', () {
      expect(
        isOpenTareoDraft({
          'HORA_INICIO': '07:00',
          'HORA_FIN': '15:30',
          'ESTADO_APROBACION': 'CERRADO',
          'estado_registro': 'COMPLETO',
        }),
        isFalse,
      );
    });
  });

  group('tareoHoursMissingForFullDay', () {
    test('calcula la alerta de jornada menor a ocho horas', () {
      expect(tareoHoursMissingForFullDay(6.5), 1.5);
      expect(tareoHoursMissingForFullDay(8), 0);
      expect(tareoHoursMissingForFullDay(9.25), 0);
    });
  });

  group('refrigerio de tareo', () {
    test('descuenta los 45 minutos del turno que contiene el refrigerio', () {
      expect(
        tareoWorkedHours('09:00', '17:45'),
        8,
      );
      expect(tareoConflictsWithMealBreak('09:00', '17:45', '12:00', '12:45'),
          isFalse);
    });

    test('no descuenta refrigerio si el turno termina antes', () {
      expect(tareoWorkedHours('09:00', '12:00'), 3);
    });

    test('acepta un turno que contiene el refrigerio hasta su límite', () {
      expect(tareoWorkedHours('09:00', '12:45'), 3);
      expect(tareoConflictsWithMealBreak('09:00', '12:45', '12:00', '12:45'),
          isFalse);
    });

    test('rechaza un tareo dentro o parcialmente encima del refrigerio', () {
      expect(tareoConflictsWithMealBreak('12:10', '12:30', '12:00', '12:45'),
          isTrue);
      expect(tareoConflictsWithMealBreak('12:30', '16:00', '12:00', '12:45'),
          isTrue);
      expect(tareoWorkedHours('12:30', '16:00'), isNull);
    });

    test('permite cambiar el horario manteniendo 45 minutos', () {
      expect(tareoMealBreakMinutes('13:00', '13:45'), 45);
      expect(
        tareoWorkedHours(
          '09:00',
          '17:45',
          mealStart: '13:00',
          mealEnd: '13:45',
        ),
        8,
      );
    });

    test('calcula correctamente un turno nocturno sin refrigerio superpuesto',
        () {
      expect(tareoWorkedHours('22:00', '06:00'), 8);
    });
  });

  group('groupTareoQueueRows', () {
    Map<String, dynamic> row(
      String id,
      String dni, {
      String approval = 'BORRADOR',
      String end = '',
      String state = 'pendiente',
      String date = '2026-09-24',
    }) =>
        {
          'id_local': id,
          'tabla_destino': 'GT-TAREO_PERSONAL',
          'estado': state,
          'created_at': '2026-09-24T10:00:00',
          'payload_json': jsonEncode({
            'id_local': id,
            'FECHA': date,
            'LABOR': 'REGADOR',
            'CENTRO_COSTO': 'LOTE 5',
            'DNI': dni,
            'APELLIDOS Y NOMBRES': 'Trabajador $dni',
            'HORA_INICIO': '07:00',
            'HORA_FIN': end,
            'ESTADO_APROBACION': approval,
            'estado_registro': approval == 'CERRADO' ? 'COMPLETO' : 'PENDIENTE',
          }),
        };

    test('agrupa las filas de trabajadores como un solo tareo diario', () {
      final groups = groupTareoQueueRows([
        row('grupo-1_1', '11111111'),
        row('grupo-1_2', '22222222'),
      ], fecha: '2026-09-24');

      expect(groups, hasLength(1));
      expect(groups.single.idLocal, 'grupo-1');
      expect(groups.single.peopleCount, 2);
      expect(groups.single.labor, 'REGADOR');
      expect(groups.single.centroCosto, 'LOTE 5');
      expect(groups.single.closed, isFalse);
      expect(groups.single.editPayload['__tareo_rows'], hasLength(2));
    });

    test('distingue cerrado, sincronizado y filtra por fecha', () {
      final groups = groupTareoQueueRows([
        row('cerrado_1', '11111111',
            approval: 'CERRADO', end: '15:00', state: 'sincronizado'),
        row('ayer_1', '22222222', date: '2026-09-23'),
      ], fecha: '2026-09-24');

      expect(groups, hasLength(1));
      expect(groups.single.closed, isTrue);
      expect(groups.single.synchronized, isTrue);
    });
  });
}
