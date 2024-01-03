import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class NativeFeatures {
  static const MethodChannel _channel = MethodChannel('native');
  static bool _systemFontLoaded = false;
  static bool _callbacksApplied = false;
  static int _resPermShizuku = -2;  // not set

  static Future<ByteData> _readFileBytes(String path) async {
    var file = File(path);
    var bytes = await file.readAsBytes();
    return ByteData.view(bytes.buffer);
  }

  static Future _handleCalls(MethodCall call) async {
    if (call.method == 'resPermShizuku') {
      _resPermShizuku = call.arguments['res'];
    }
  }

  static Future _waitWhile(bool Function() test,
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

  static Future<String> loadSystemFont() async {
    if (_systemFontLoaded) { return "ok"; }
    var getFontRes = await _channel.invokeMethod('getSystemFont');
    if (getFontRes[0] != '/') { return getFontRes; }  // Error
    var fontLoader = FontLoader('SystemFont');
    fontLoader.addFont(_readFileBytes(getFontRes));
    await fontLoader.load();
    _systemFontLoaded = true;
    return "ok";
  }

  static Future<int> checkPermissionShizuku() async {
    if (!_callbacksApplied) {
      _channel.setMethodCallHandler(_handleCalls);
      _callbacksApplied = true;
    }
    int res = await _channel.invokeMethod('checkPermissionShizuku');
    if (res == -2) {
      await _waitWhile(() => _resPermShizuku == -2);
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
