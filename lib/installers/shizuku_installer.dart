import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/installers/installer.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:shizuku_apk_installer/shizuku_apk_installer.dart';

/// How many times to re-check a transiently unavailable Shizuku/Dhizuku binder
/// before reporting that the service is not running.
const int _permissionCheckAttempts = 4;

/// Delay between transient binder availability checks.
const Duration _permissionCheckRetryDelay = Duration(milliseconds: 500);

/// Installs via the Shizuku/Dhizuku/Sui binder API for elevated installs with
/// no user-facing permission dialog. Supports silent installs.
class ShizukuInstaller extends Installer {
  ShizukuInstaller(super.settingsProvider);

  /// Maps the `shizukuInstallerMode` setting to the plugin's backend mode.
  static InstallerMode modeForSetting(String setting) => switch (setting) {
    'shizuku' => InstallerMode.shizuku,
    'dhizuku' => InstallerMode.dhizuku,
    _ => InstallerMode.auto,
  };

  Future<void> _applyBackend() => ShizukuApkInstaller().setInstallerMode(
    modeForSetting(settingsProvider.shizukuInstallerMode),
  );

  @override
  String get modeKey => 'shizuku';

  @override
  Future<bool> canInstallSilently(App app) async => true;

  @override
  Future<bool> checkPermission() async {
    await _applyBackend();
    return (await ShizukuApkInstaller().checkPermission())?.startsWith(
          'granted',
        ) ??
        false;
  }

  @override
  Future<void> ensurePermission() async {
    String? result;
    for (var attempt = 0; attempt < _permissionCheckAttempts; attempt++) {
      await _applyBackend();
      result = await ShizukuApkInstaller().checkPermission();
      if (result != 'services_not_found' ||
          attempt == _permissionCheckAttempts - 1) {
        break;
      }
      await Future<void>.delayed(_permissionCheckRetryDelay);
    }
    switch (result) {
      case 'granted_owner':
      case 'granted_root':
      case 'granted_adb':
        break;
      case 'services_not_found':
        throw ObtainiumError(tr('shizukuBinderNotFound'));
      case 'old_shizuku':
        throw ObtainiumError(tr('shizukuOld'));
      case 'old_android_with_adb':
        throw ObtainiumError(tr('shizukuOldAndroidWithADB'));
      case 'denied':
        throw ObtainiumError(tr('cancelled'));
      default:
        throw ObtainiumError(tr('cancelled'));
    }
  }

  @override
  Future<InstallResult> installApk(
    List<String> apkFilePaths, {
    required String appId,
    Map<String, dynamic> installOptions = const {},
  }) async {
    await _applyBackend();
    final fakeInstallSource =
        installOptions['shizukuPretendToBeGooglePlay'] == true
        ? 'com.android.vending'
        : '';
    final uris = apkFilePaths.map((p) => File(p).uri.toString()).toList();
    int? code;
    if (uris.length > 1) {
      code = await ShizukuApkInstaller().installAABSplits(
        uris,
        fakeInstallSource,
      );
    } else {
      code = await ShizukuApkInstaller().installAPK(
        uris.first,
        fakeInstallSource,
      );
    }
    return InstallResult.fromPlatformCode(code);
  }
}
