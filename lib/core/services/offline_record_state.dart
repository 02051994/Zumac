enum OfflineRecordState {
  draft('borrador'),
  pending('pendiente'),
  syncing('sincronizando'),
  synced('sincronizado'),
  error('error'),
  conflict('conflicto'),
  deletedPending('eliminado_pendiente'),
  blocked('bloqueado');

  const OfflineRecordState(this.storageValue);

  final String storageValue;

  static OfflineRecordState fromStorage(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return OfflineRecordState.values.firstWhere(
      (state) => state.storageValue == normalized,
      orElse: () => OfflineRecordState.pending,
    );
  }

  bool get canRetry => this == pending || this == error;

  bool canTransitionTo(OfflineRecordState next) {
    if (this == next) return true;
    return switch (this) {
      draft => next == pending || next == deletedPending,
      pending => next == syncing ||
          next == error ||
          next == conflict ||
          next == blocked ||
          next == deletedPending,
      syncing => next == synced ||
          next == error ||
          next == conflict ||
          next == blocked ||
          next == pending,
      synced => next == pending || next == deletedPending,
      error => next == pending ||
          next == syncing ||
          next == conflict ||
          next == blocked ||
          next == deletedPending,
      conflict => next == pending || next == blocked || next == deletedPending,
      deletedPending => next == syncing || next == synced || next == error,
      blocked => next == pending || next == deletedPending,
    };
  }
}

class OfflineConflictPolicy {
  const OfflineConflictPolicy._();

  static bool hasRemoteChange({
    required Object? baseUpdatedAt,
    required Object? remoteUpdatedAt,
  }) {
    final base = DateTime.tryParse(baseUpdatedAt?.toString().trim() ?? '');
    final remote = DateTime.tryParse(remoteUpdatedAt?.toString().trim() ?? '');
    if (base == null || remote == null) return false;
    return remote.toUtc().isAfter(base.toUtc());
  }
}
