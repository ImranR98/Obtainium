import 'package:flutter/services.dart';

class PrivilegeInstallFallback {
  static const _channel = MethodChannel(
    'dev.imranr.obtainium/privilege_install_fallback',
  );

  static Future<int?> installViaShizuku(
    String apkUri,
    String fakeInstallSource,
  ) async {
    return await _channel.invokeMethod<int>('installViaShizuku', {
      'apkUri': apkUri,
      'fakeInstallSource': fakeInstallSource,
    });
  }

  static Future<String?> checkShizukuPermission() async {
    return await _channel.invokeMethod<String>('checkShizukuPermission');
  }

  static Future<String?> getShizukuBackendKind() async {
    return await _channel.invokeMethod<String>('getShizukuBackendKind');
  }
}
