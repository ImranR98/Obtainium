import 'dart:io';

import 'package:android_package_manager/android_package_manager.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/installers/installer.dart';
import 'package:obtainium/providers/source_provider.dart';

String buildRootInstallCommand({
  required String installerPackageName,
  required int userId,
  required List<String> stagedApks,
  required bool bypassLowTargetSdkBlock,
}) {
  return [
    'pm',
    'install',
    '-r',
    if (installerPackageName.isNotEmpty) ...[
      '-i',
      RootInstaller._quoteShell(installerPackageName),
    ],
    '--user',
    '$userId',
    if (bypassLowTargetSdkBlock) '--bypass-low-target-sdk-block',
    ...stagedApks,
  ].join(' ');
}

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
      ];
      final installerPackageName =
          installOptions['installerPackageName'] as String? ?? '';
      final userId = await _userId();
      final bypassLowTargetSdkBlock =
          apkFilePaths.isNotEmpty &&
          await _shouldBypassLowTargetSdkBlock(apkFilePaths.first);
      final installLine = buildRootInstallCommand(
        installerPackageName: installerPackageName,
        userId: userId,
        stagedApks: stagedApks,
        bypassLowTargetSdkBlock: bypassLowTargetSdkBlock,
      );
      final script = [
        'd="\$(mktemp -d /data/local/tmp/obtainium.XXXXXX)" || exit 1',
        'trap \'rm -rf "\$d"\' EXIT',
        stagedCopies,
        installLine,
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

  Future<bool> _shouldBypassLowTargetSdkBlock(String apkPath) async {
    try {
      final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdkInt < 34) return false;
      final info = await AndroidPackageManager().getPackageArchiveInfo(
        archiveFilePath: apkPath,
      );
      final targetSdkVersion = info?.applicationInfo?.targetSdkVersion;
      return targetSdkVersion != null && targetSdkVersion < 23;
    } catch (e) {
      AppLogger.warn('Failed to inspect target SDK for $apkPath: $e');
      return false;
    }
  }

  Future<ProcessResult> _runAsRoot(String cmd) =>
      Process.run('su', ['-c', cmd]);

  Future<int> _userId() async {
    final status = await File('/proc/self/status').readAsString();
    final uid = int.tryParse(
      RegExp(r'^Uid:\s+(\d+)', multiLine: true).firstMatch(status)?.group(1) ??
          '',
    );
    return (uid ?? 0) ~/ 100000;
  }

  static String _quoteShell(String path) =>
      "'${path.replaceAll("'", "'\\''")}'";
}
