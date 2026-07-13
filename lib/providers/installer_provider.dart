// @author Bikram Agarwal
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

const _channel = MethodChannel('dev.imranr.obtainium/installer');

typedef ThirdPartyInstallPackageChangedCallback =
    FutureOr<void> Function(String packageName);

ThirdPartyInstallPackageChangedCallback? _thirdPartyInstallPackageChanged;

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
  final rawList = await _channel.invokeMethod<List<dynamic>>(
    'queryApkInstallerActivities',
  );
  if (rawList == null) return [];
  return rawList
      .map((entry) {
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
      })
      .where(_isSelectableInstallerActivity)
      .toList();
}

bool _isSelectableInstallerActivity(InstallerAppInfo app) {
  if (app.packageName.toLowerCase() != 'io.github.muntashirakon.appmanager') {
    return true;
  }
  return app.activityName.toLowerCase().endsWith('packageinstalleractivity') ||
      app.label.trim().toLowerCase() == 'install';
}

void registerThirdPartyInstallPackageChangedCallback(
  ThirdPartyInstallPackageChangedCallback? callback,
) {
  _thirdPartyInstallPackageChanged = callback;
  if (!Platform.isAndroid) return;
  _channel.setMethodCallHandler((call) async {
    if (call.method != 'thirdPartyInstallPackageChanged') {
      throw MissingPluginException();
    }
    final arguments = call.arguments;
    if (arguments is! Map) return;
    final packageName = arguments['packageName']?.toString();
    if (packageName == null || packageName.isEmpty) return;
    await _thirdPartyInstallPackageChanged?.call(packageName);
  });
}

/// Sends one or more APK paths to a user-chosen third-party installer (Settings: Third-Party mode).
/// Multiple paths use the same comma-separated convention as [AndroidPackageInstaller.installApk]
/// so split / multi-APK installs are handed off whole (not only the base split).
/// Returns true if the system broadcast confirms the package was installed.
/// Times out after 2 minutes and returns false.
Future<bool> installApkViaThirdParty(
  String apkFilePathsCommaSeparated, {
  required String targetPackage,
  required String targetActivity,
  required String expectedPackageName,
}) async {
  if (!Platform.isAndroid) return false;
  final result = await _channel
      .invokeMethod<bool>('launchInstallIntent', <String, dynamic>{
        'path': apkFilePathsCommaSeparated,
        'package': targetPackage,
        'activity': targetActivity,
        'expectedPackageName': expectedPackageName,
      });
  return result ?? false;
}
