import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/installers/installer.dart';
import 'package:obtainium/providers/source_provider.dart';

/// Installs via the Android `pm` CLI over root (`su`).
class RootInstaller extends Installer {
  RootInstaller(super.settingsProvider);

  @override
  String get modeKey => 'root';

  @override
  Future<bool> canInstallSilently(App app) async => checkPermission();

  @override
  Future<bool> checkPermission() async {
    try {
      // Magisk/su print the effective uid; uid 0 means root was granted.
      return (await _runAsRoot('id -u')).stdout.toString().trim() == '0';
    } on ProcessException {
      AppLogger.info(
        'Root check failed: su binary or caller is not available.',
      );
      return false;
    }
  }

  @override
  Future<void> ensurePermission() async {
    if (!await checkPermission()) {
      throw ObtainiumError(tr('rootNotGranted'));
    }
  }

  @override
  Future<InstallResult> installApk(
    List<String> apkFilePaths, {
    required String appId,
    Map<String, dynamic> installOptions = const {},
  }) async {
    try {
      // Stage the APKs under /data/local/tmp, which pm can read,
      // then install and remove the temp copies in the same session.
      // Paths are written by index so the base APK (index 0) stays first
      // for split-APK installs.
      final stagedCopies = [
        for (var i = 0; i < apkFilePaths.length; i++)
          'cp ${_quoteShell(apkFilePaths[i])} "\$d/obt$i.apk"',
      ].join('\n');
      final stagedApks = [
        for (var i = 0; i < apkFilePaths.length; i++) '"\$d/obt$i.apk"',
      ].join(' ');
      final script = [
        'd="\$(mktemp -d /data/local/tmp/obtainium.XXXXXX)" || exit 1',
        'trap \'rm -rf "\$d"\' EXIT',
        stagedCopies,
        'uid="\$(am get-current-user 2>/dev/null)"; uid="\${uid:-0}"',
        'pm install -r --user "\$uid" $stagedApks',
      ].join('\n');
      final result = await _runAsRoot(script);
      if (result.exitCode != 0) {
        final detail = result.stderr.toString().trim();
        AppLogger.warn('Root pm install failed for $appId: $detail');
        return InstallResult.error(result.exitCode);
      }
      return InstallResult.success();
    } on ProcessException catch (e) {
      AppLogger.error(e, message: 'Root pm install failed for $appId');
      return InstallResult.error(-1);
    } on IOException catch (e) {
      AppLogger.error(e, message: 'Root pm install I/O error for $appId');
      return InstallResult.error(-1);
    }
  }

  Future<ProcessResult> _runAsRoot(String cmd) =>
      Process.run('su', ['-c', cmd]);

  static String _quoteShell(String path) =>
      "'${path.replaceAll("'", "'\\''")}'";
}
