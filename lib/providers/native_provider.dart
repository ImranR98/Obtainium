import 'dart:async';
import 'dart:io';
import 'package:android_system_font/android_system_font.dart';
import 'package:flutter/services.dart';

class NativeFeatures {
  static bool _systemFontLoaded = false;

  static Future<ByteData> _readFileBytes(String path) async {
    var bytes = await File(path).readAsBytes();
    return ByteData.view(bytes.buffer);
  }

  static Future loadSystemFont() async {
    if (_systemFontLoaded) return;
    var fontLoader = FontLoader('SystemFont');
    var fontFilePath = await AndroidSystemFont().getFilePath();
    fontLoader.addFont(_readFileBytes(fontFilePath!));
    fontLoader.load();
    _systemFontLoaded = true;
  }
}
