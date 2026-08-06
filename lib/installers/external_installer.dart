import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_fgbg/flutter_fgbg.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/installers/installer.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/external_install_bridge.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

const String _apkMime = 'application/vnd.android.package-archive';
const String _bundleMime = 'application/zip';

/// Ceiling for how long we wait for the user to return after the external
/// installer took them away from Obtainium.
const Duration _foregroundReturnFallback = Duration(hours: 2);

/// If the external installer doesn't take the user away from Obtainium
/// (modal overlay), we won't see a background event. This timeout caps how
/// long we wait before falling through to the install-confirmation poll.
const Duration _backgroundDetectionWindow = Duration(seconds: 30);

/// When the installer was a modal, wait this long before polling.
const Duration _modalPollDelay = Duration(seconds: 30);

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
  Future<bool> canInstallSilently(App app) async {
    unawaited(
      LogsProvider().add(
        'App will not be installed silently: the external installer always requires user interaction: ${app.id}',
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
    final targetPackage = settingsProvider.externalInstallerPackage;
    if (targetPackage == null || apkFilePaths.isEmpty) {
      throw ObtainiumError(tr('externalInstallerRequired'));
    }

    final baseline = await captureInstallBaseline(appId);

    for (final filePath in apkFilePaths) {
      final contentUri = await ExternalInstallerBridge.instance
          .contentUriForFile(filePath);
      if (contentUri == null) {
        throw ObtainiumError(tr('badDownload'));
      }

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

      // Detect whether the installer took the user away or is a modal.
      // Subscribe to both events before launch so we don't miss either.
      final wentAway = FGBGEvents.instance.stream
          .firstWhere((event) => event == FGBGType.background)
          .timeout(
            _backgroundDetectionWindow,
            onTimeout: () => FGBGType.foreground,
          );
      await intent.launch();

      if (await wentAway == FGBGType.background) {
        // The external installer opened as a separate app. Wait for the
        // user to return, with a generous fallback for long interactions.
        final returned = FGBGEvents.instance.stream
            .firstWhere((event) => event == FGBGType.foreground)
            .timeout(
              _foregroundReturnFallback,
              onTimeout: () => FGBGType.foreground,
            );
        await returned;
      } else {
        // The installer is a modal — we never left Obtainium. Give the
        // user time to interact with the modal before polling.
        await Future.delayed(_modalPollDelay);
      }
    }

    // The external installer app never reports a status code back to us, so
    // install completion can only be detected by polling the package state
    // rather than reading a return code from the installer.
    unawaited(
      LogsProvider().add(
        'Detecting install completion for $appId via fallback polling (external installer returns no status code).',
      ),
    );
    final installed = await waitForPackageInstall(
      appId,
      baseline,
      attempts: _confirmAttempts,
    );
    unawaited(
      LogsProvider().add(
        'Fallback polling ${installed ? 'confirmed' : 'could not confirm'} install completion for $appId.',
      ),
    );
    return installed ? InstallResult.success() : InstallResult.cancelled();
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
