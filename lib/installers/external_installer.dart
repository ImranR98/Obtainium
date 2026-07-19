import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/installers/installer.dart';
import 'package:obtainium/providers/installer_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

/// Installs by handing the downloaded file to a user-chosen installer app
/// (Settings → Third-Party mode). This delegates to the existing native
/// `launchInstallIntent` bridge via [installApkViaThirdParty] — the exact
/// mechanism fork main uses — rather than reinventing the handoff. The target
/// package + activity are what the settings UI writes
/// (externalInstallerPackage / externalInstallerComponent).
class ExternalInstaller extends Installer {
  ExternalInstaller(super.settingsProvider);

  @override
  String get modeKey => 'external';

  @override
  bool get wantsContainerHandoff => true;

  @override
  Future<bool> canInstallSilently(App app) async {
    unawaited(
      LogsProvider().add(
        'App will not be installed silently: the external installer always '
        'requires user interaction: ${app.id}',
      ),
    );
    return false;
  }

  @override
  Future<bool> checkPermission() async =>
      settingsProvider.externalInstallerPackage != null;

  @override
  Future<void> ensurePermission() async {
    if (settingsProvider.externalInstallerPackage == null) {
      throw ObtainiumError(tr('externalInstallerRequired'));
    }
  }

  @override
  Future<InstallResult> installApk(
    List<String> apkFilePaths, {
    required String appId,
    Map<String, dynamic> installOptions = const {},
  }) async {
    final String? targetPackage = settingsProvider.externalInstallerPackage;
    final String? targetActivity = settingsProvider.externalInstallerComponent;
    if (targetPackage == null ||
        targetActivity == null ||
        apkFilePaths.isEmpty) {
      throw ObtainiumError(tr('externalInstallerRequired'));
    }
    // Hand off to the chosen installer via the existing, working native
    // `launchInstallIntent` path. The comma-joined convention lets split /
    // bundle installs be handed off whole (matches fork main).
    final bool ok = await installApkViaThirdParty(
      apkFilePaths.join(','),
      targetPackage: targetPackage,
      targetActivity: targetActivity,
      expectedPackageName: appId,
    );
    return ok ? InstallResult.success() : InstallResult.cancelled();
  }
}
