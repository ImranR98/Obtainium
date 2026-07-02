import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_fgbg/flutter_fgbg.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/installers/installer.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/external_install_bridge.dart';
import 'package:obtainium/providers/source_provider.dart';

const String _apkMime = 'application/vnd.android.package-archive';
const String _bundleMime = 'application/zip';

/// Fallback ceiling for how long we wait for the user to come back from the
/// external installer. FGBG is reliable, so this only guards against the rare
/// case where a foreground event is never delivered.
const Duration _foregroundReturnFallback = Duration(hours: 2);

/// After the user returns, re-check the package a few times to absorb any brief
/// finalization lag before deciding the outcome.
const int _confirmAttempts = 12;

/// Installs by handing the downloaded file to a user-chosen installer app. All
/// orchestration lives here in Dart; the native side only resolves a content
/// URI and enumerates candidate apps.
class ExternalInstaller extends Installer {
  ExternalInstaller(super.settingsProvider);

  @override
  String get modeKey => 'external';

  @override
  bool get wantsContainerHandoff => true;

  @override
  Future<bool> canInstallSilently(App app) async => false;

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
    bool shizukuPretendToBeGooglePlay = false,
  }) async {
    final targetPackage = settingsProvider.externalInstallerPackage;
    if (targetPackage == null || apkFilePaths.isEmpty) {
      throw ObtainiumError(tr('externalInstallerRequired'));
    }

    final filePath = apkFilePaths.first;
    final contentUri = await ExternalInstallerBridge.instance.contentUriForFile(
      filePath,
    );
    if (contentUri == null) {
      throw ObtainiumError(tr('badDownload'));
    }

    final baseline = await captureInstallBaseline(appId);

    // Begin listening for the return-to-foreground before firing the intent so
    // the event isn't missed if the installer opens instantly.
    final foregroundReturn = FGBGEvents.instance.stream
        .firstWhere((event) => event == FGBGType.foreground)
        .timeout(_foregroundReturnFallback, onTimeout: () => FGBGType.foreground);

    final intent = AndroidIntent(
      action: 'action_view',
      data: contentUri,
      type: _mimeForPath(filePath),
      package: targetPackage,
      componentName: settingsProvider.externalInstallerComponent,
      flags: [
        Flag.FLAG_GRANT_READ_URI_PERMISSION,
        Flag.FLAG_ACTIVITY_NEW_TASK,
      ],
    );
    await intent.launch();

    await foregroundReturn;

    return (await waitForPackageInstall(appId, baseline, attempts: _confirmAttempts))
        ? InstallResult.success()
        : InstallResult.cancelled();
  }

  String _mimeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.xapk') ||
        lower.endsWith('.apkm') ||
        lower.endsWith('.zip')) {
      return _bundleMime;
    }
    return _apkMime;
  }
}
