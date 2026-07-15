import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_version.dart';

class AppUpdateInfo {
  final String plataforma;
  final String version;
  final String storagePath;
  final bool obligatorio;
  final String notas;

  const AppUpdateInfo({
    required this.plataforma,
    required this.version,
    required this.storagePath,
    required this.obligatorio,
    required this.notas,
  });

  factory AppUpdateInfo.fromMap(Map<String, dynamic> map) {
    return AppUpdateInfo(
      plataforma: (map['plataforma'] ?? '').toString(),
      version: (map['version'] ?? '').toString(),
      storagePath: (map['storage_path'] ?? '').toString(),
      obligatorio: map['obligatorio'] == true,
      notas: (map['notas'] ?? '').toString(),
    );
  }
}

class AppUpdateResult {
  final bool hasUpdate;
  final String message;
  final AppUpdateInfo? info;
  final String? localFilePath;

  const AppUpdateResult({
    required this.hasUpdate,
    required this.message,
    this.info,
    this.localFilePath,
  });
}

class AppUpdateService {
  static const String bucket = 'actualizaciones-appgt';
  static const String table = 'appgt_versiones';

  final SupabaseClient _client;

  AppUpdateService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  String get platformKey {
    if (kIsWeb) return 'web';
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  Future<AppUpdateResult> checkAndDownloadLatest() async {
    final platform = platformKey;
    if (platform != 'windows' && platform != 'android') {
      return AppUpdateResult(
        hasUpdate: false,
        message: 'Actualización automática disponible solo para Windows y Android.',
      );
    }

    final response = await _client
        .from(table)
        .select('plataforma, version, storage_path, obligatorio, notas, activo, created_at')
        .eq('plataforma', platform)
        .eq('activo', true)
        .order('created_at', ascending: false)
        .limit(1);

    final rows = List<Map<String, dynamic>>.from(response as List);
    if (rows.isEmpty) {
      return AppUpdateResult(
        hasUpdate: false,
        message: 'No hay versión activa publicada para $platform.',
      );
    }

    final info = AppUpdateInfo.fromMap(rows.first);
    if (info.version.trim().isEmpty || info.storagePath.trim().isEmpty) {
      return AppUpdateResult(
        hasUpdate: false,
        info: info,
        message: 'La versión publicada no tiene version o storage_path válido.',
      );
    }

    if (!_isRemoteVersionNewer(info.version, appVersion)) {
      return AppUpdateResult(
        hasUpdate: false,
        info: info,
        message: 'Ya tienes la última versión: $appVersionLabel.',
      );
    }

    final bytes = await _client.storage.from(bucket).download(info.storagePath);
    final localPath = await _saveUpdateFile(info, bytes);

    try {
      await OpenFilex.open(localPath);
    } catch (_) {
      // Si el sistema no permite abrir el instalador/ZIP, igual queda descargado.
    }

    final tipo = platform == 'android' ? 'APK' : 'ZIP';
    return AppUpdateResult(
      hasUpdate: true,
      info: info,
      localFilePath: localPath,
      message: 'Versión ${info.version} descargada ($tipo). Archivo: $localPath',
    );
  }

  Future<String> _saveUpdateFile(AppUpdateInfo info, List<int> bytes) async {
    final fileName = info.storagePath.split('/').where((e) => e.trim().isNotEmpty).last;
    final baseDir = await _updatesDirectory();
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    final file = File('${baseDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Directory> _updatesDirectory() async {
    if (!kIsWeb && Platform.isWindows) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return Directory('${downloads.path}${Platform.pathSeparator}Zumac Actualizaciones');
      }
    }

    if (!kIsWeb && Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        return Directory('${external.path}${Platform.pathSeparator}actualizaciones');
      }
    }

    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}${Platform.pathSeparator}actualizaciones_appgt');
  }

  bool _isRemoteVersionNewer(String remote, String local) {
    final r = _parseVersion(remote);
    final l = _parseVersion(local);
    final maxLen = r.length > l.length ? r.length : l.length;
    for (var i = 0; i < maxLen; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv > lv) return true;
      if (rv < lv) return false;
    }
    return false;
  }

  List<int> _parseVersion(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[^0-9.]'), '')
        .split('.')
        .where((p) => p.isNotEmpty)
        .map((p) => int.tryParse(p) ?? 0)
        .toList(growable: false);
  }
}
