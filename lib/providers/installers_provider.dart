import 'dart:async';
import 'package:flutter/services.dart';

class Installers {
  static const MethodChannel _channel = MethodChannel('installers');

  static Future<int?> installWithShizuku({required String apkFilePath}) async {
    return await _channel.invokeMethod('installWithShizuku', {'apkFilePath': apkFilePath});
  }

  static Future<int?> installWithRoot({required String apkFilePath}) async {
    return await _channel.invokeMethod('installWithRoot', {'apkFilePath': apkFilePath});
  }
}
