import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart';
import 'package:obtainium/core/logging/app_logger.dart';

typedef FdroidIndexRequest =
    Future<Response> Function(String url, Map<String, String> headers);

class FdroidIndexCache {
  final Future<Directory> Function() cacheDirProvider;

  FdroidIndexCache(this.cacheDirProvider);

  Future<Response> fetch(String url, FdroidIndexRequest request) async {
    Directory? dir;
    try {
      dir = await cacheDirProvider();
    } catch (_) {}
    if (dir == null) return request(url, const {});

    final key = sha256.convert(utf8.encode(url)).toString();
    final bodyFile = File('${dir.path}/$key.body');
    final metaFile = File('${dir.path}/$key.meta');
    final meta = _readMeta(metaFile);
    final headers = <String, String>{};
    if (meta.etag != null) headers['If-None-Match'] = meta.etag!;
    if (meta.lastModified != null) {
      headers['If-Modified-Since'] = meta.lastModified!;
    }

    final res = await request(url, headers);
    if (res.statusCode == 304) {
      if (bodyFile.existsSync()) {
        try {
          final body = utf8.decode(await bodyFile.readAsBytes());
          _writeMeta(metaFile, res.headers);
          return Response(
            body,
            200,
            request: res.request ?? Request('GET', Uri.parse(url)),
            headers: res.headers,
          );
        } catch (e) {
          AppLogger.warn('Failed to read cached F-Droid index: $e');
          return request(url, const {});
        }
      }
      return request(url, const {});
    }

    if (res.statusCode == 200) {
      try {
        final etag = res.headers['etag'];
        final lastModified = res.headers['last-modified'];
        if ((etag == null || etag.isEmpty) &&
            (lastModified == null || lastModified.isEmpty)) {
          if (bodyFile.existsSync()) bodyFile.deleteSync();
          if (metaFile.existsSync()) metaFile.deleteSync();
        } else {
          await bodyFile.writeAsBytes(res.bodyBytes);
          _writeMeta(metaFile, res.headers);
        }
      } catch (e) {
        AppLogger.warn('Failed to cache F-Droid index: $e');
      }
    }
    return res;
  }

  _IndexMeta _readMeta(File file) {
    if (!file.existsSync()) return const _IndexMeta();
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return const _IndexMeta();
      final etag = decoded['etag'];
      final lastModified = decoded['lastModified'];
      return _IndexMeta(
        etag: etag is String && etag.isNotEmpty ? etag : null,
        lastModified: lastModified is String && lastModified.isNotEmpty
            ? lastModified
            : null,
      );
    } catch (_) {
      return const _IndexMeta();
    }
  }

  void _writeMeta(File file, Map<String, String> headers) {
    final etag = headers['etag'];
    final lastModified = headers['last-modified'];
    if ((etag == null || etag.isEmpty) &&
        (lastModified == null || lastModified.isEmpty)) {
      return;
    }
    try {
      file.writeAsStringSync(
        jsonEncode({'etag': etag, 'lastModified': lastModified}),
      );
    } catch (e) {
      AppLogger.warn('Failed to write F-Droid index metadata: $e');
    }
  }
}

class _IndexMeta {
  final String? etag;
  final String? lastModified;

  const _IndexMeta({this.etag, this.lastModified});
}
