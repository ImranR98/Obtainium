import 'dart:async';

import 'package:obtainium/providers/apps_provider.dart' show getInstalledInfo;

class InstallBaseline {
  final bool wasInstalled;
  final int? versionCode;
  final int? updateTime;
  const InstallBaseline({
    required this.wasInstalled,
    this.versionCode,
    this.updateTime,
  });
}

Future<InstallBaseline> captureInstallBaseline(String appId) async {
  final info = await getInstalledInfo(appId);
  return InstallBaseline(
    wasInstalled: info != null,
    versionCode: info?.versionCode,
    updateTime: info?.lastUpdateTime,
  );
}

Future<bool> waitForPackageInstall(
  String appId,
  InstallBaseline baseline, {
  required int attempts,
  Duration interval = const Duration(milliseconds: 500),
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    final info = await getInstalledInfo(appId);
    if (info != null) {
      if (!baseline.wasInstalled) return true;
      if (baseline.updateTime != null) {
        final updateTimeAfter = info.lastUpdateTime;
        if (updateTimeAfter != null && updateTimeAfter != baseline.updateTime) {
          return true;
        }
      } else {
        final newCode = info.versionCode;
        if (newCode != null && newCode != baseline.versionCode) {
          return true;
        }
      }
    }
    if (attempt < attempts - 1) {
      await Future.delayed(interval);
    }
  }
  return false;
}
