import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

/// One export written by [DocumentTreeBridge.downloadsExports].
class DownloadsExport {
  final Uri uri;
  final String name;
  final DateTime date;

  const DownloadsExport({
    required this.uri,
    required this.name,
    required this.date,
  });
}

/// Native storage helpers without a Flutter-plugin equivalent: picking a
/// document tree with read and write persistable access (needed because
/// shared_storage's `openDocumentTree` can only request one of the two flags,
/// so persisted export directories lose read access once the temporary grant
/// expires, #3227), and writing/reading exports in `Downloads/Obtainium/` on
/// devices - typically TVs - that have no document picker at all.
class DocumentTreeBridge {
  DocumentTreeBridge._();

  static final DocumentTreeBridge instance = DocumentTreeBridge._();

  static const MethodChannel _channel = MethodChannel(
    'dev.imranr.obtainium/document_tree',
  );

  /// Returns the picked tree URI, or null when the user cancelled.
  Future<Uri?> pickDocumentTree() async {
    final result = await _channel.invokeMethod<String>('pickDocumentTree');
    return result == null ? null : Uri.parse(result);
  }

  /// Writes [bytes] to `Downloads/Obtainium/[name]` through MediaStore.
  /// Returns the display path, or null below Android 10.
  Future<String?> exportToDownloads({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) {
    return _channel.invokeMethod<String>('exportToDownloads', {
      'name': name,
      'mimeType': mimeType,
      'bytes': bytes,
    });
  }

  /// Lists exports previously written to `Downloads/Obtainium/`, newest first.
  Future<List<DownloadsExport>> downloadsExports() async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'listDownloadsExports',
    );
    return [
      for (final entry in raw ?? const [])
        () {
          final map = Map<String, dynamic>.from(entry as Map);
          return DownloadsExport(
            uri: Uri.parse(map['uri'] as String),
            name: map['name'] as String,
            date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
          );
        }(),
    ];
  }

  Future<Uint8List?> readDownloadsExport(Uri uri) {
    return _channel.invokeMethod<Uint8List>('readDownloadsExport', {
      'uri': uri.toString(),
    });
  }

  Future<void> deleteDownloadsExport(Uri uri) {
    return _channel.invokeMethod('deleteDownloadsExport', {
      'uri': uri.toString(),
    });
  }

  /// Whether the MediaStore Downloads collection exists (Android 10+). The
  /// picker-less Downloads destination is unavailable without it, so the
  /// importing/exporting UI must hide that option on older devices.
  Future<bool> downloadsExportsSupported() async {
    if (!Platform.isAndroid) return false;
    final info = await DeviceInfoPlugin().androidInfo;
    return info.version.sdkInt >= 29;
  }
}
