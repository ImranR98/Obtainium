import 'dart:io';
import 'package:flutter/services.dart';

const _channel = MethodChannel('dev.imranr.obtainium/installer');

Future<List<Map<String, String>>> getApkInstallerApps() async {
  if (!Platform.isAndroid) return [];
  final rawList =
      await _channel.invokeMethod<List<dynamic>>('queryApkInstallerActivities');
  if (rawList == null) return [];
  return rawList.map((entry) {
    final map = Map<String, dynamic>.from(entry as Map);
    return map.map((key, value) => MapEntry(key, value.toString()));
  }).toList();
}

Future<void> installApkViaLegacy(
  String apkFilePath, {
  required String targetPackage,
  required String targetActivity,
}) async {
  if (!Platform.isAndroid) return;
  await _channel.invokeMethod<void>('launchInstallIntent', <String, dynamic>{
    'path': apkFilePath,
    'package': targetPackage,
    'activity': targetActivity,
  });
}
