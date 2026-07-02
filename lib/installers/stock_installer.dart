import 'dart:async';

import 'package:android_package_installer/android_package_installer.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/installers/installer.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

const int _androidApiLevelS = 31;

/// Installs using Android's session-based [AndroidPackageInstaller]. Requires
/// the `REQUEST_INSTALL_PACKAGES` permission and, for silent installs, that
/// Obtainium is the installing package on a new enough OS.
class StockInstaller extends Installer {
  StockInstaller(super.settingsProvider);

  @override
  String get modeKey => 'stock';

  @override
  Future<bool> canInstallSilently(App app) async {
    if (app.id == obtainiumId) {
      return false;
    }
    final osInfo = await DeviceInfoPlugin().androidInfo;
    String? installerPackageName;
    try {
      installerPackageName = osInfo.version.sdkInt >= 30
          ? (await packageManager.getInstallSourceInfo(
              packageName: app.id,
            ))?.installingPackageName
          : (await packageManager.getInstallerPackageName(packageName: app.id));
    } catch (e) {
      unawaited(
        LogsProvider().add(
          'Failed to get installed package details: ${app.id} (${e.toString()})',
        ),
      );
      return false;
    }
    if (installerPackageName != obtainiumId) {
      // If we did not install the app, silent install is not possible
      return false;
    }
    if (osInfo.version.sdkInt < _androidApiLevelS) {
      // The OS must also be new enough
      unawaited(
        LogsProvider().add('Android SDK too old: ${osInfo.version.sdkInt}'),
      );
      return false;
    }
    return true;
  }

  @override
  Future<bool> checkPermission() =>
      settingsProvider.getInstallPermission(enforce: false);

  @override
  Future<void> ensurePermission() async {
    if (!(await settingsProvider.getInstallPermission(enforce: false))) {
      throw ObtainiumError(tr('cancelled'));
    }
  }

  @override
  Future<InstallResult> installApk(
    List<String> apkFilePaths, {
    required String appId,
    bool shizukuPretendToBeGooglePlay = false,
  }) async {
    final code = await AndroidPackageInstaller.installApk(
      apkFilePath: apkFilePaths.join(','),
    );
    return InstallResult.fromPlatformCode(code);
  }
}
