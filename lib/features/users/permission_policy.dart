import 'dart:convert';

class WorkflowStateActions {
  const WorkflowStateActions({
    this.view = false,
    this.create = false,
    this.update = false,
    this.delete = false,
  });

  final bool view;
  final bool create;
  final bool update;
  final bool delete;

  factory WorkflowStateActions.fromMap(Map<String, dynamic>? map) {
    bool enabled(String key) {
      final raw = map?[key];
      if (raw is bool) return raw;
      if (raw is num) return raw != 0;
      return const {'true', 't', '1', 'si', 'sí', 'yes'}
          .contains(raw?.toString().trim().toLowerCase());
    }

    return WorkflowStateActions(
      view: enabled('view') || enabled('ver'),
      create: enabled('create') || enabled('insert') || enabled('crear'),
      update: enabled('update') || enabled('edit') || enabled('editar'),
      delete: enabled('delete') || enabled('eliminar'),
    );
  }

  WorkflowStateActions copyWith({
    bool? view,
    bool? create,
    bool? update,
    bool? delete,
  }) =>
      WorkflowStateActions(
        view: view ?? this.view,
        create: create ?? this.create,
        update: update ?? this.update,
        delete: delete ?? this.delete,
      );

  Map<String, dynamic> toMap() => {
        'view': view,
        'create': create,
        'update': update,
        'delete': delete,
      };

  bool get hasAny => view || create || update || delete;
}

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
    this.workflowStates = const <String, WorkflowStateActions>{},
  });

  final bool view;
  final bool insert;
  final bool update;
  final bool delete;
  final bool export;
  final bool import;
  final bool review;
  final bool approve;
  final Map<String, WorkflowStateActions> workflowStates;

  factory PermissionActions.fromMap(Map<String, dynamic>? map) {
    bool value(String key) {
      final raw = map?[key];
      if (raw is bool) return raw;
      if (raw is num) return raw != 0;
      return const {'true', 't', '1', 'si', 'sí', 'yes'}
          .contains(raw?.toString().trim().toLowerCase());
    }

    dynamic rawStates = map?['permisos_estado'];
    if (rawStates is String && rawStates.trim().isNotEmpty) {
      try {
        rawStates = jsonDecode(rawStates);
      } catch (_) {
        rawStates = null;
      }
    }
    final states = <String, WorkflowStateActions>{};
    if (rawStates is Map) {
      for (final entry in rawStates.entries) {
        if (entry.value is Map) {
          states[entry.key.toString().trim().toUpperCase()] =
              WorkflowStateActions.fromMap(
                  Map<String, dynamic>.from(entry.value as Map));
        }
      }
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
      workflowStates: states,
    );
  }

  PermissionActions normalizedForRole(String? role) {
    final normalized = role?.trim().toUpperCase() ?? '';
    if (normalized == 'VISUALIZADOR') {
      return PermissionActions(
        view: view || workflowStates.values.any((e) => e.view),
        workflowStates: {
          for (final entry in workflowStates.entries)
            entry.key: WorkflowStateActions(view: entry.value.view),
        },
      );
    }
    final canUseGlobalApproval =
        normalized == 'ADMIN' || normalized == 'GESTOR';
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
      review: canUseGlobalApproval && review,
      approve: canUseGlobalApproval && approve,
      workflowStates: workflowStates,
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
        workflowStates: {
          for (final entry in workflowStates.entries)
            entry.key: WorkflowStateActions(
              view: entry.value.view && ceiling.view,
              create: entry.value.create && ceiling.insert,
              update: entry.value.update && ceiling.update,
              delete: entry.value.delete && ceiling.delete,
            ),
        },
      );

  bool get hasAny =>
      view ||
      insert ||
      update ||
      delete ||
      export ||
      import ||
      review ||
      approve ||
      workflowStates.values.any((value) => value.hasAny);

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

  Map<String, dynamic> toMap({String? formatId}) {
    final stateView = workflowStates.values.any((value) => value.view);
    final stateInsert = workflowStates.values.any((value) => value.create);
    final stateUpdate = workflowStates.values.any((value) => value.update);
    final stateDelete = workflowStates.values.any((value) => value.delete);
    return {
      if (formatId != null) 'formato_id': formatId,
      'can_view': view || stateView,
      'can_insert': insert || stateInsert,
      'can_update': update || stateUpdate,
      'can_delete': delete || stateDelete,
      'can_export': export,
      'can_import': import,
      'can_review': review,
      'can_approve': approve,
      'permisos_estado': {
        for (final entry in workflowStates.entries)
          entry.key: entry.value.toMap(),
      },
    };
  }
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
