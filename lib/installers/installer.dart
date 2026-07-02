import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

/// Android PackageInstaller status codes: 0 = success, 3 = already installed / pending.
const int installSuccessCode = 0;
const int installAlreadyPendingCode = 3;

enum InstallOutcome { success, cancelled, error }

/// Unified result of an install operation, replacing the previous
/// "nullable int code" pattern used by the platform install APIs.
class InstallResult {
  final InstallOutcome outcome;
  final int? errorCode;

  const InstallResult({required this.outcome, this.errorCode});

  factory InstallResult.success() =>
      const InstallResult(outcome: InstallOutcome.success);

  factory InstallResult.cancelled() =>
      const InstallResult(outcome: InstallOutcome.cancelled);

  factory InstallResult.error(int code) =>
      InstallResult(outcome: InstallOutcome.error, errorCode: code);

  /// Maps a raw platform install status code to an [InstallResult].
  /// [installSuccessCode] is a completed install, [installAlreadyPendingCode]
  /// (and a null code) is a pending/no-op that is not treated as an error, and
  /// any other value is an error carrying the original code.
  factory InstallResult.fromPlatformCode(int? code) {
    if (code == null || code == installAlreadyPendingCode) {
      return InstallResult.cancelled();
    }
    if (code == installSuccessCode) {
      return InstallResult.success();
    }
    return InstallResult.error(code);
  }

  bool get isSuccess => outcome == InstallOutcome.success;
  bool get isCancelled => outcome == InstallOutcome.cancelled;
  bool get isError => outcome == InstallOutcome.error;
}

/// Strategy that performs the platform-specific parts of an app installation.
///
/// Implementations are intentionally thin: the surrounding harness in
/// [AppsProvider] handles download validation, downgrade checks, the background
/// completion workaround, persistence, file cleanup, and notifications. An
/// installer only decides silent-install eligibility, manages its own
/// permissions, and performs the terminal platform call.
abstract class Installer {
  final SettingsProvider settingsProvider;

  Installer(this.settingsProvider);

  /// Unique key identifying this installer mode (e.g. 'stock', 'shizuku',
  /// 'external').
  String get modeKey;

  /// Whether directory/bundle installs should hand off the original container
  /// file (XAPK/ZIP/tarball) rather than extracted split APKs.
  bool get wantsContainerHandoff => false;

  /// The installer-specific portion of the silent-install decision. Shared
  /// pre-checks (background updates enabled, exemptions, multi-URL, target SDK)
  /// are handled by the caller before this is invoked.
  Future<bool> canInstallSilently(App app);

  /// Whether the installer currently has the privileges needed to install
  /// without prompting the user. Does not prompt.
  Future<bool> checkPermission();

  /// Ensures the installer has the privileges needed to install, prompting the
  /// user if necessary. Throws an [ObtainiumError] if permission is denied.
  Future<void> ensurePermission();

  /// Installs one or more APK file paths (a base APK plus optional splits).
  Future<InstallResult> installApk(
    List<String> apkFilePaths, {
    required String appId,
    bool shizukuPretendToBeGooglePlay = false,
  });
}
