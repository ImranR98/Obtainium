import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/installers/installer.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:shizuku_apk_installer/shizuku_apk_installer.dart';

/// Installs via the Shizuku/Dhizuku/Sui binder API for elevated installs with
/// no user-facing permission dialog. Supports silent installs.
class ShizukuInstaller extends Installer {
  ShizukuInstaller(super.settingsProvider);

  @override
  String get modeKey => 'shizuku';

  @override
  Future<bool> canInstallSilently(App app) async => true;

  @override
  Future<bool> checkPermission() async =>
      (await ShizukuApkInstaller().checkPermission())?.startsWith('granted') ??
      false;

  @override
  Future<void> ensurePermission() async {
    switch ((await ShizukuApkInstaller().checkPermission())) {
      case 'services_not_found':
        throw ObtainiumError(tr('shizukuBinderNotFound'));
      case 'old_shizuku':
        throw ObtainiumError(tr('shizukuOld'));
      case 'old_android_with_adb':
        throw ObtainiumError(tr('shizukuOldAndroidWithADB'));
      case 'denied':
        throw ObtainiumError(tr('cancelled'));
    }
  }

  @override
  Future<InstallResult> installApk(
    List<String> apkFilePaths, {
    required String appId,
    Map<String, dynamic> installOptions = const {},
  }) async {
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
