import 'package:appgt_offline_subtables/features/formats/record_import_utils.dart';
import 'package:excel/excel.dart' as xlsx;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecordImportUtils.excelCellToText', () {
    test('does not add .0 to numeric identifiers', () {
      expect(
        RecordImportUtils.excelCellToText(
          const xlsx.DoubleCellValue(74819362.0),
        ),
        '74819362',
      );
      expect(
        RecordImportUtils.excelCellToText(const xlsx.DoubleCellValue(7.5)),
        '7.5',
      );
    });

    test('keeps Excel dates as stable ISO dates', () {
      expect(
        RecordImportUtils.excelCellToText(
          const xlsx.DateCellValue(year: 1992, month: 4, day: 15),
        ),
        '1992-04-15',
      );
    });
  });

  group('RecordImportUtils.normalizeDate', () {
    test('accepts day-first dates and rejects invalid dates', () {
      expect(
        RecordImportUtils.normalizeDate('15/04/1992', dateOnly: true),
        '1992-04-15',
      );
      expect(
        RecordImportUtils.normalizeDate('31/02/2026', dateOnly: true),
        isNull,
      );
    });
  });

  group('RecordImportUtils.isAutomaticField', () {
    test('treats technical and configured hidden ids as automatic', () {
      expect(
        RecordImportUtils.isAutomaticField({'campo': 'id_local'}),
        isTrue,
      );
      expect(
        RecordImportUtils.isAutomaticField({
          'campo': 'CODIGO_TRABAJADOR',
          'tipo_ui': 'hidden_id',
        }),
        isTrue,
      );
      expect(
        RecordImportUtils.isAutomaticField({'campo': 'Dni'}),
        isFalse,
      );
    });
  });
}
