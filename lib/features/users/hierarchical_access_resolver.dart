class EffectiveAccessTree {
  final Map<String, Map<String, List<Map<String, dynamic>>>> bySection;
  final int formatCount;

  const EffectiveAccessTree({
    required this.bySection,
    required this.formatCount,
  });

  int get moduleCount => bySection.values.fold<int>(
        0,
        (total, modules) => total + modules.length,
      );
}

EffectiveAccessTree resolveEffectiveAccessTree({
  required List<Map<String, dynamic>> sections,
  required List<Map<String, dynamic>> modules,
  required List<Map<String, dynamic>> formats,
  required List<Map<String, dynamic>> sectionPermissions,
  required List<Map<String, dynamic>> formatPermissions,
}) {
  String text(dynamic value) => value?.toString().trim() ?? '';
  String key(dynamic value) => text(value).toLowerCase();
  bool same(dynamic left, dynamic right) => key(left) == key(right);
  bool boolValue(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const {'true', 't', '1', 'si', 'sí', 'yes'}.contains(key(value));
  }

  bool active(Map<String, dynamic> row) =>
      boolValue(row['activo'], fallback: true) &&
      text(row['deleted_at']).isEmpty &&
      !boolValue(row['eliminado']);
  String sectionPermissionId(Map<String, dynamic> row) {
    final canonical = text(row['seccion_id']);
    return canonical.isNotEmpty ? canonical : text(row['seccion']);
  }

  String moduleSectionId(Map<String, dynamic> row) {
    for (final field in const ['seccion_id', 'seccion', 'id_seccion']) {
      final value = text(row[field]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String formatModuleId(Map<String, dynamic> row) {
    for (final field in const ['modulo_id', 'modulo', 'id_modulo']) {
      final value = text(row[field]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  final sectionByKey = <String, Map<String, dynamic>>{
    for (final section in sections) key(section['id']): section,
  };
  final moduleByKey = <String, Map<String, dynamic>>{
    for (final module in modules) key(module['id']): module,
  };
  final rawTree = <String, Map<String, List<Map<String, dynamic>>>>{};
  final visibleFormatIds = <String>{};

  void ensureSection(String sectionId) {
    final section = sectionByKey[key(sectionId)];
    if (section == null) return;
    rawTree.putIfAbsent(
      text(section['id']),
      () => <String, List<Map<String, dynamic>>>{},
    );
  }

  void addFormat(Map<String, dynamic> format) {
    final module = moduleByKey[key(formatModuleId(format))];
    if (module == null) return;
    final section = sectionByKey[key(moduleSectionId(module))];
    if (section == null) return;
    final formatId = key(format['id']);
    if (formatId.isEmpty || !visibleFormatIds.add(formatId)) return;
    rawTree
        .putIfAbsent(
          text(section['id']),
          () => <String, List<Map<String, dynamic>>>{},
        )
        .putIfAbsent(text(module['id']), () => <Map<String, dynamic>>[])
        .add(format);
  }

  for (final permission in sectionPermissions) {
    if (!active(permission) ||
        !boolValue(permission['can_view'], fallback: true)) {
      continue;
    }
    final sectionId = sectionPermissionId(permission);
    ensureSection(sectionId);
    for (final module in modules) {
      if (!same(moduleSectionId(module), sectionId)) continue;
      final moduleId = text(module['id']);
      for (final format in formats) {
        if (same(formatModuleId(format), moduleId)) addFormat(format);
      }
    }
  }

  for (final permission in formatPermissions) {
    if (!active(permission) || !boolValue(permission['can_view'])) continue;
    for (final format in formats) {
      final matches = same(format['id'], permission['formato']) ||
          same(format['id'], permission['formato_id']) ||
          same(format['tabla_destino'], permission['formato']) ||
          same(format['tabla_destino'], permission['tabla_destino']);
      if (matches) {
        addFormat(format);
        break;
      }
    }
  }

  final orderedTree = <String, Map<String, List<Map<String, dynamic>>>>{};
  for (final section in sections) {
    final sectionId = text(section['id']);
    final rawModules = rawTree[sectionId];
    if (rawModules == null) continue;
    final orderedModules = <String, List<Map<String, dynamic>>>{};
    for (final module in modules) {
      final moduleId = text(module['id']);
      final rows = rawModules[moduleId];
      if (rows != null) orderedModules[moduleId] = rows;
    }
    orderedTree[sectionId] = orderedModules;
  }

  return EffectiveAccessTree(
    bySection: orderedTree,
    formatCount: visibleFormatIds.length,
  );
}
