import 'dart:io';

import 'package:obtainium/core/logging/app_logger.dart';

Directory? prepareWritableDirectory(Directory dir) {
  File? probe;
  try {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    probe = File(
      '${dir.path}/.obtainium_write_probe_${pid}_${DateTime.now().microsecondsSinceEpoch}',
    );
    probe.createSync();
    probe.deleteSync();
    return dir;
  } catch (_) {
    try {
      probe?.deleteSync();
    } catch (_) {}
    return null;
  }
}

({Directory apkDir, Directory iconsDir}) resolveCacheDirectories({
  required Directory? externalCacheRoot,
  required Directory internalCacheRoot,
}) {
  if (externalCacheRoot != null) {
    final externalIcons = Directory('${externalCacheRoot.path}/icons');
    if (prepareWritableDirectory(externalCacheRoot) != null &&
        prepareWritableDirectory(externalIcons) != null) {
      return (apkDir: externalCacheRoot, iconsDir: externalIcons);
    }
    AppLogger.warn(
      'External cache directory is not writable; using internal cache',
    );
  }
  final internalApk = prepareWritableDirectory(
    Directory('${internalCacheRoot.path}/apks'),
  );
  final internalIcons = prepareWritableDirectory(
    Directory('${internalCacheRoot.path}/icons'),
  );
  if (internalApk == null || internalIcons == null) {
    throw const FileSystemException(
      'Unable to create internal cache directories',
    );
  }
  return (apkDir: internalApk, iconsDir: internalIcons);
}
