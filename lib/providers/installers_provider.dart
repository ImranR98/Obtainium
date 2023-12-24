import 'dart:async';
import 'package:flutter/services.dart';

class Installers {
  static const MethodChannel _channel = MethodChannel('installers');
  static bool _callbacksApplied = false;
  static int _resPermShizuku = -2;  // not set

  static Future waitWhile(bool Function() test,
      [Duration pollInterval = const Duration(milliseconds: 250)]) {
    var completer = Completer();
    check() {
      if (test()) {
        Timer(pollInterval, check);
      } else {
        completer.complete();
      }
    }
    check();
    return completer.future;
  }

  static Future handleCalls(MethodCall call) async {
    if (call.method == 'resPermShizuku') {
      _resPermShizuku = call.arguments['res'];
    }
  }

  static Future<int> checkPermissionShizuku() async {
    if (!_callbacksApplied) {
      _channel.setMethodCallHandler(handleCalls);
      _callbacksApplied = true;
    }
    int res = await _channel.invokeMethod('checkPermissionShizuku');
    if(res == -2) {
      await waitWhile(() => _resPermShizuku == -2);
      res = _resPermShizuku;
      _resPermShizuku = -2;
    }
    return res;
  }

  static Future<bool> checkPermissionRoot() async {
    return await _channel.invokeMethod('checkPermissionRoot');
  }

  static Future<bool> installWithShizuku({required String apkFileUri}) async {
    return await _channel.invokeMethod(
        'installWithShizuku', {'apkFileUri': apkFileUri});
  }

  static Future<bool> installWithRoot({required String apkFilePath}) async {
    return await _channel.invokeMethod(
        'installWithRoot', {'apkFilePath': apkFilePath});
  }
}
