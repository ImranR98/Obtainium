import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/fdroid_index_cache.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('obtainium_fdroid_cache');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Response response(String body, int status, {Map<String, String>? headers}) =>
      Response(
        body,
        status,
        headers: headers ?? const {},
        request: Request('GET', Uri.parse('https://example.com/index-v2.json')),
      );

  test('caches the body and revalidates with ETag/Last-Modified', () async {
    var calls = 0;
    final cache = FdroidIndexCache(() async => dir);

    Future<Response> request(String url, Map<String, String> headers) async {
      calls++;
      if (calls == 1) {
        expect(headers, isEmpty);
        return response(
          'index-body',
          200,
          headers: {
            'etag': '"v1"',
            'last-modified': 'Mon, 01 Jan 2026 00:00:00 GMT',
          },
        );
      }
      expect(headers['If-None-Match'], '"v1"');
      expect(headers['If-Modified-Since'], 'Mon, 01 Jan 2026 00:00:00 GMT');
      return response('', 304);
    }

    final first = await cache.fetch(
      'https://example.com/index-v2.json',
      request,
    );
    expect(first.statusCode, 200);
    expect(first.body, 'index-body');

    final second = await cache.fetch(
      'https://example.com/index-v2.json',
      request,
    );
    expect(second.statusCode, 200);
    expect(second.body, 'index-body');
    expect(calls, 2);
  });

  test('does not keep a cache entry without validators', () async {
    var calls = 0;
    final cache = FdroidIndexCache(() async => dir);

    Future<Response> request(String url, Map<String, String> headers) async {
      calls++;
      expect(headers, isEmpty);
      return response('index-body', 200);
    }

    await cache.fetch('https://example.com/index-v2.json', request);
    expect(dir.listSync(), isEmpty);
    await cache.fetch('https://example.com/index-v2.json', request);
    expect(calls, 2);
  });

  test('retries without conditions when a 304 has no cached body', () async {
    var calls = 0;
    final cache = FdroidIndexCache(() async => dir);

    Future<Response> request(String url, Map<String, String> headers) async {
      calls++;
      if (calls == 1) return response('', 304);
      return response('fresh-body', 200);
    }

    final res = await cache.fetch('https://example.com/index-v2.json', request);
    expect(res.statusCode, 200);
    expect(res.body, 'fresh-body');
    expect(calls, 2);
  });

  test('falls back to a direct request when the cache dir fails', () async {
    var calls = 0;
    final cache = FdroidIndexCache(
      () async => throw const FileSystemException('no cache'),
    );

    Future<Response> request(String url, Map<String, String> headers) async {
      calls++;
      expect(headers, isEmpty);
      return response('index-body', 200);
    }

    final res = await cache.fetch('https://example.com/index-v2.json', request);
    expect(res.statusCode, 200);
    expect(res.body, 'index-body');
    expect(calls, 1);
  });
}
