import 'package:excel/excel.dart' as xlsx;

class RecordImportUtils {
  RecordImportUtils._();

  static const Set<String> _technicalIdentifiers = {
    'ID',
    'ID_LOCAL',
    'ID_LOCA_L',
    'ID_REGISTRO',
    'ID_FILA_SERIAL',
    'PK_ID',
    'ID_PK',
    'HASH_FILA_SIN_IDS',
    'HASH_FILA_SIN_ID',
  };

  static String normalizeName(String value) {
    var normalized = value.trim().toUpperCase();
    const replacements = {
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'Ü': 'U',
      'Ñ': 'N',
    };
    replacements.forEach(
      (source, target) => normalized = normalized.replaceAll(source, target),
    );
    return normalized
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static bool isTechnicalIdentifierName(String name) =>
      _technicalIdentifiers.contains(normalizeName(name));

  static bool isAutomaticField(Map<String, dynamic>? field,
      {String? fallbackName}) {
    final name = field?['campo']?.toString().trim() ?? fallbackName ?? '';
    final type = field?['tipo']?.toString().trim().toLowerCase() ?? '';
    final uiType = field?['tipo_ui']?.toString().trim().toLowerCase() ?? '';
    final generator = field?['id_generador']?.toString().trim() ?? '';
    return isTechnicalIdentifierName(name) ||
        type == 'hidden' ||
        type == 'hidden_id' ||
        uiType == 'hidden' ||
        uiType == 'hidden_id' ||
        generator.isNotEmpty;
  }

  static String excelCellToText(xlsx.CellValue? value) {
    if (value == null) return '';
    if (value is xlsx.DoubleCellValue) {
      final number = value.value;
      return number.isFinite && number == number.truncateToDouble()
          ? number.toInt().toString()
          : number.toString();
    }
    if (value is xlsx.DateCellValue) {
      return _dateText(value.year, value.month, value.day);
    }
    if (value is xlsx.DateTimeCellValue) {
      return value.asDateTimeUtc().toIso8601String();
    }
    if (value is xlsx.TimeCellValue) return value.toString();
    if (value is xlsx.IntCellValue) return value.value.toString();
    if (value is xlsx.BoolCellValue) return value.value.toString();
    return value.toString();
  }

  static String? normalizeDate(String value, {required bool dateOnly}) {
    final text = value.trim();
    if (text.isEmpty) return null;

    final dayFirst = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text);
    DateTime? parsed;
    if (dayFirst != null) {
      final day = int.parse(dayFirst.group(1)!);
      final month = int.parse(dayFirst.group(2)!);
      final year = int.parse(dayFirst.group(3)!);
      final candidate = DateTime.utc(year, month, day);
      if (candidate.year != year ||
          candidate.month != month ||
          candidate.day != day) {
        return null;
      }
      parsed = candidate;
    } else {
      parsed = DateTime.tryParse(text);
    }
    if (parsed == null) return null;
    if (dateOnly) return _dateText(parsed.year, parsed.month, parsed.day);
    return parsed.toIso8601String();
  }

  static String _dateText(int year, int month, int day) =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}
