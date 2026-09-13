import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/installers/installer.dart';
import 'package:obtainium/installers/install_utils.dart';
import 'package:obtainium/providers/external_install_bridge.dart';
import 'package:obtainium/providers/source_provider.dart';

const String _apkMime = 'application/vnd.android.package-archive';
const String _bundleMime = 'application/zip';
const String _tarMime = 'application/x-tar';
const String _gzipMime = 'application/gzip';

bool _isTarballPath(String lowerPath) =>
    lowerPath.endsWith('.tar.gz') ||
    lowerPath.endsWith('.tgz') ||
    lowerPath.endsWith('.tar.bz2') ||
    lowerPath.endsWith('.tar.xz');

/// Confirmation window (at 500ms intervals) after the native side reports an
/// install, before treating the package state as not updated.
const int _confirmAttempts = 60;

/// Single confirmation check for inconclusive outcomes (cancel/timeout), to
/// catch a background install that committed at the last moment.
const int _singleCheckAttempts = 2;

/// Installs by handing the downloaded file to a user-chosen installer app.
///
/// The native bridge launches the installer with
/// `Intent.EXTRA_RETURN_RESULT` and watches for the installer's own result, a
/// package-change broadcast, or a timeout, so the outcome is authoritative
/// instead of being inferred from app-lifecycle events. The package state is
/// still verified before reporting success.
class ExternalInstaller extends Installer {
  ExternalInstaller(super.settingsProvider);

  @override
  String get modeKey => 'external';

  @override
  bool get wantsContainerHandoff => true;

  @override
  Future<bool> canInstallSilently(App app) async {
    AppLogger.info(
      'App will not be installed silently: the external installer always requires user interaction: ${app.id}',
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

    ExternalInstallResult? lastResult;
    var reportedInstalled = false;
    for (final filePath in apkFilePaths) {
      final contentUri = await ExternalInstallerBridge.instance
          .contentUriForFile(filePath);
      if (contentUri == null) {
        throw ObtainiumError(tr('badDownload'));
      }
      AppLogger.info(
        'External installer $targetPackage is handling $appId; awaiting its result.',
      );
      lastResult = await ExternalInstallerBridge.instance.launchInstallIntent(
        uri: contentUri,
        type: _mimeForPath(filePath),
        package: targetPackage,
        activity: settingsProvider.externalInstallerComponent,
        expectedPackageName: appId,
      );
      if (lastResult == null) {
        // Result tracking unavailable: fall back to bounded polling.
        AppLogger.info(
          'External install result tracking unavailable; polling package state for $appId.',
        );
        final installed = await waitForPackageInstall(
          appId,
          baseline,
          attempts: _confirmAttempts,
        );
        return installed ? InstallResult.success() : InstallResult.cancelled();
      }
      if (lastResult.installed) {
        reportedInstalled = true;
        break;
      }
    }

    if (lastResult?.errorCode != null) {
      AppLogger.warn(
        'External installer reported failure for $appId (code ${lastResult!.errorCode}).',
      );
    }

    // Trust but verify: the installer's report (or the hard timeout) is only
    // conclusive once the package manager reflects the change.
    final verified = await waitForPackageInstall(
      appId,
      baseline,
      attempts: reportedInstalled ? _confirmAttempts : _singleCheckAttempts,
    );
    if (reportedInstalled && !verified) {
      AppLogger.warn(
        'External installer reported success for $appId but the package state did not change.',
      );
    } else if (!reportedInstalled && verified) {
      AppLogger.info(
        'External install for $appId was confirmed by the package state after an inconclusive result.',
      );
    }
    return verified ? InstallResult.success() : InstallResult.cancelled();
  }

  String _mimeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.xapk') ||
        lower.endsWith('.apkm') ||
        lower.endsWith('.apks') ||
        lower.endsWith('.zip')) {
      return _bundleMime;
    }
    if (_isTarballPath(lower)) {
      return lower.endsWith('.tgz') || lower.endsWith('.tar.gz')
          ? _gzipMime
          : _tarMime;
    }
    return _apkMime;
  }
}
