import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';

const _channel = MethodChannel('dev.imranr.obtainium/installer');

class InstallerAppInfo {
  final String packageName;
  final String activityName;
  final String label;
  final Uint8List? icon;

  InstallerAppInfo({
    required this.packageName,
    required this.activityName,
    required this.label,
    this.icon,
  });
}

Future<List<InstallerAppInfo>> getApkInstallerApps() async {
  if (!Platform.isAndroid) return [];
  final rawList =
      await _channel.invokeMethod<List<dynamic>>('queryApkInstallerActivities');
  if (rawList == null) return [];
  return rawList.map((entry) {
    final map = Map<String, dynamic>.from(entry as Map);
    Uint8List? iconData;
    if (map['icon'] != null) {
      iconData = Uint8List.fromList(List<int>.from(map['icon']));
    }
    return InstallerAppInfo(
      packageName: map['packageName']?.toString() ?? '',
      activityName: map['activityName']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      icon: iconData,
    );
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
