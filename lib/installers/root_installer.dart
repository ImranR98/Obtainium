import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/installers/installer.dart';
import 'package:obtainium/providers/source_provider.dart';

class RootInstaller extends Installer {
  RootInstaller(super.settingsProvider);

  @override
  String get modeKey => 'root';

  @override
  Future<bool> canInstallSilently(App app) async => true;

  @override
  Future<bool> checkPermission() async {
    try {
      final result = await Process.run('which', ['su']);
      return result.exitCode == 0 && (result.stdout as String).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> ensurePermission() async {
    final hasSu = await checkPermission();
    if (!hasSu) {
      throw ObtainiumError(tr('rootNotFound'));
    }
  }

  @override
  Future<InstallResult> installApk(
    List<String> apkFilePaths, {
    required String appId,
    Map<String, dynamic> installOptions = const {},
  }) async {
    try {
      print('RootInstaller: Starting install for $appId');
      print('RootInstaller: APK paths: $apkFilePaths');
      
      final String sourcePath = apkFilePaths.first;
      final String tempPath = '/data/local/tmp/$appId.apk';
      
      print('RootInstaller: Source path: $sourcePath');
      print('RootInstaller: Temp path: $tempPath');
      
      final command = 'cp "$sourcePath" "$tempPath" && chmod 644 "$tempPath" && pm install -r "$tempPath" && rm "$tempPath"';
      print('RootInstaller: Executing command: $command');
      
      final result = await Process.run('su', ['-c', command]);
      final output = (result.stdout as String).toLowerCase();
      final error = (result.stderr as String).toLowerCase();
      
      print('RootInstaller: Exit code: ${result.exitCode}');
      print('RootInstaller: Output: $output');
      print('RootInstaller: Error: $error');

      if (result.exitCode == 0 && output.contains('success')) {
        print('RootInstaller: Install success for $appId');
        return InstallResult.success();
      } else if (output.contains('already installed')) {
        print('RootInstaller: App already installed for $appId');
        return InstallResult.alreadyInstalled();
      } else if (output.contains('cancelled')) {
        print('RootInstaller: Install cancelled for $appId');
        return InstallResult.cancelled();
      } else {
        print('RootInstaller: Install failed for $appId with exit code ${result.exitCode}');
        return InstallResult.error(result.exitCode);
      }
    } catch (e) {
      print('RootInstaller: Exception for $appId: $e');
      return InstallResult.error(-1);
    }
  }
}
