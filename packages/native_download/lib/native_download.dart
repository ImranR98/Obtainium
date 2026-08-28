import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class NativeDownloadRequest {
  NativeDownloadRequest._(this._requestId, this.future);

  final String _requestId;
  final Future<File> future;

  static const MethodChannel _channel = MethodChannel(
    'dev.imranr.obtainium/native_download',
  );
  static final Map<String, void Function(double?, int?, int?)> _progress = {};
  static bool _handlerInstalled = false;

  void cancel() {
    unawaited(
      _channel.invokeMethod<void>('cancel', {'requestId': _requestId}),
    );
  }

  static void _installProgressHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'downloadProgress') return null;
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      final callback = _progress[args['requestId']];
      if (callback == null) return null;
      final received = (args['received'] as num?)?.toInt();
      final total = (args['total'] as num?)?.toInt();
      callback(
        total != null && total > 0
            ? (received! / total * 100).clamp(0, 100).toDouble()
            : 30,
        received,
        total,
      );
      return null;
    });
  }

  static NativeDownloadRequest start({
    required String url,
    required String outputPath,
    Map<String, String>? headers,
    int rangeStart = 0,
    int? totalLength,
    bool rangeSupported = false,
    void Function(double?, int?, int?)? onProgress,
  }) {
    _installProgressHandler();
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${url.hashCode}';
    if (onProgress != null) _progress[requestId] = onProgress;
    final future = _channel
        .invokeMethod<String>('download', {
          'requestId': requestId,
          'url': url,
          'outputPath': outputPath,
          'headers': headers ?? const <String, String>{},
          'rangeStart': rangeStart,
          'totalLength': totalLength,
          'rangeSupported': rangeSupported,
        })
        .then((path) => File(path ?? outputPath))
        .whenComplete(() => _progress.remove(requestId));
    return NativeDownloadRequest._(requestId, future);
  }
}
