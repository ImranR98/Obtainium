import 'dart:io';

import 'package:android_system_font/android_system_font.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

class NativeFeatures {
  static bool _systemFontAttempted = false;

  static Future<ByteData> _readFileBytes(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    return ByteData.sublistView(bytes);
  }

  static Future<void> loadSystemFont() async {
    if (_systemFontAttempted) return;
    _systemFontAttempted = true;
    try {
      final fontLoader = FontLoader('SystemFont');
      final fontFilePath = await AndroidSystemFont().getFilePath();
      if (fontFilePath == null) return;
      fontLoader.addFont(_readFileBytes(fontFilePath));
      await fontLoader.load();
    } catch (e) {
      // Reset so enabling the system font later in the session can retry.
      _systemFontAttempted = false;
      debugPrint('Failed to load system font: $e');
    }
  }
}
