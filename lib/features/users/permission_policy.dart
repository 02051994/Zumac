class PermissionActions {
  const PermissionActions({
    this.view = false,
    this.insert = false,
    this.update = false,
    this.delete = false,
    this.export = false,
    this.import = false,
    this.review = false,
    this.approve = false,
  });

  final bool view;
  final bool insert;
  final bool update;
  final bool delete;
  final bool export;
  final bool import;
  final bool review;
  final bool approve;

  factory PermissionActions.fromMap(Map<String, dynamic>? map) {
    bool value(String key) {
      final raw = map?[key];
      if (raw is bool) return raw;
      if (raw is num) return raw != 0;
      return const {'true', 't', '1', 'si', 'sí', 'yes'}
          .contains(raw?.toString().trim().toLowerCase());
    }

    return PermissionActions(
      view: value('can_view'),
      insert: value('can_insert'),
      update: value('can_update'),
      delete: value('can_delete'),
      export: value('can_export'),
      import: value('can_import'),
      review: value('can_review'),
      approve: value('can_approve'),
    );
  }

  PermissionActions normalizedForRole(String? role) {
    final normalized = role?.trim().toUpperCase() ?? '';
    if (normalized == 'VISUALIZADOR') {
      return PermissionActions(view: view);
    }
    if (normalized == 'COLABORADOR') {
      return PermissionActions(
        view: view || insert || update || delete || export || import,
        insert: insert,
        update: update,
        delete: delete,
        export: export,
        import: import,
      );
    }
    return PermissionActions(
      view: view ||
          insert ||
          update ||
          delete ||
          export ||
          import ||
          review ||
          approve,
      insert: insert,
      update: update,
      delete: delete,
      export: export,
      import: import,
      review: review,
      approve: approve,
    );
  }

  PermissionActions boundedBy(PermissionActions ceiling) => PermissionActions(
        view: view && ceiling.view,
        insert: insert && ceiling.insert,
        update: update && ceiling.update,
        delete: delete && ceiling.delete,
        export: export && ceiling.export,
        import: import && ceiling.import,
        review: review && ceiling.review,
        approve: approve && ceiling.approve,
      );

  bool get hasAny =>
      view ||
      insert ||
      update ||
      delete ||
      export ||
      import ||
      review ||
      approve;

  int get enabledCount => [
        view,
        insert,
        update,
        delete,
        export,
        import,
        review,
        approve,
      ].where((value) => value).length;

  Map<String, dynamic> toMap({String? formatId}) => {
        if (formatId != null) 'formato_id': formatId,
        'can_view': view,
        'can_insert': insert,
        'can_update': update,
        'can_delete': delete,
        'can_export': export,
        'can_import': import,
        'can_review': review,
        'can_approve': approve,
      };
}

List<String> delegableRoles(String? actorRole) {
  switch (actorRole?.trim().toUpperCase()) {
    case 'ADMIN':
      return const ['GESTOR', 'COLABORADOR', 'VISUALIZADOR'];
    case 'GESTOR':
      return const ['COLABORADOR', 'VISUALIZADOR'];
    default:
      return const [];
  }
}

bool canManageTargetRole(String? actorRole, String? targetRole) {
  final target = targetRole?.trim().toUpperCase() ?? '';
  if (target == 'ADMIN') return false;
  final actor = actorRole?.trim().toUpperCase() ?? '';
  if (actor == 'ADMIN') return true;
  return actor == 'GESTOR' &&
      (target.isEmpty || target == 'COLABORADOR' || target == 'VISUALIZADOR');
}
