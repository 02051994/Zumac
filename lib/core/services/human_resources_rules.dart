const Set<String> permissionTypesRequiringDocument = {
  'DESCANSO_MEDICO',
  'LICENCIA_DE_MATERNIDAD',
  'LICENCIA_DE_PATERNIDAD',
  'LICENCIA_POR_FALLECIMIENTO',
};

String normalizeHumanResourcesValue(Object? value) {
  var text = value?.toString().trim().toUpperCase() ?? '';
  const replacements = {
    'Á': 'A',
    'É': 'E',
    'Í': 'I',
    'Ó': 'O',
    'Ú': 'U',
    'Ü': 'U',
    'Ñ': 'N',
  };
  replacements.forEach((source, target) {
    text = text.replaceAll(source, target);
  });
  return text
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

bool permissionRequiresSupportingDocument(Object? permissionType) =>
    permissionTypesRequiringDocument
        .contains(normalizeHumanResourcesValue(permissionType));

bool permissionIsCompensation(Object? permissionType) =>
    normalizeHumanResourcesValue(permissionType) == 'COMPENSACION';

DateTime? parseHumanResourcesDate(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);
  final match = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(text);
  if (match == null) return null;
  final day = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final year = int.tryParse(match.group(3)!);
  if (day == null || month == null || year == null) return null;
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

bool mobilityIsAuthorized({
  required Object? soatExpiration,
  required Object? technicalReviewExpiration,
  required DateTime onDate,
}) {
  final day = DateTime(onDate.year, onDate.month, onDate.day);
  final soat = parseHumanResourcesDate(soatExpiration);
  final technicalReview = parseHumanResourcesDate(technicalReviewExpiration);
  return soat != null &&
      technicalReview != null &&
      !soat.isBefore(day) &&
      !technicalReview.isBefore(day);
}

bool isHumanResourcesApprovalTable(Object? table) {
  final normalized = normalizeHumanResourcesValue(table);
  return normalized == 'GH_PERMISOS_LICENCIAS_APPGT' ||
      normalized == 'GH_SANCIONES_PERSONAL_APPGT';
}

bool isApprovedHumanResourcesRecord(Map<String, dynamic> row) {
  for (final entry in row.entries) {
    if (normalizeHumanResourcesValue(entry.key) == 'ESTADO_APROBACION') {
      return normalizeHumanResourcesValue(entry.value) == 'APROBADO';
    }
  }
  return false;
}
