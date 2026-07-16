// Thin wrapper over the native "applyPatches" method call.

import 'package:flutter/services.dart';
import 'package:obtainium/providers/revanced/keystore_provider.dart';
import 'package:obtainium/providers/revanced/patch_config.dart';

const String _channelName = 'dev.imranr.obtainium/revanced';

class PatchApplyResult {
  final bool success;
  final String? outputPath;
  final String? error;

  PatchApplyResult({required this.success, this.outputPath, this.error});
}

class PatchEngineChannel {
  PatchEngineChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  final MethodChannel _channel;

  Future<PatchApplyResult> applyPatches({
    required String bundlePath,
    required String inputApkPath,
    required String outputApkPath,
    required String packageName,
    required PatchConfig patchConfig,
    required KeystoreProvider keystoreProvider,
    bool signOnly = false,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'applyPatches',
        {
          'bundlePath': bundlePath,
          'inputApkPath': inputApkPath,
          'outputApkPath': outputApkPath,
          'packageName': packageName,
          'patchNames': patchConfig.patchNames,
          'options': patchConfig.toNativeOptions(),
          'alias': keystoreProvider.alias,
          'password': keystoreProvider.password,
          'signOnly': signOnly,
        },
      );
      return PatchApplyResult(
        success: result?['success'] == true,
        outputPath: result?['outputPath']?.toString(),
        error: result?['error']?.toString(),
      );
    } on PlatformException catch (e) {
      return PatchApplyResult(success: false, error: e.message ?? e.code);
    } on MissingPluginException {
      return PatchApplyResult(
        success: false,
        error: 'ReVanced patching is not available on this build',
      );
    }
  }
}
