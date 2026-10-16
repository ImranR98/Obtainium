import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/apps_provider.dart';

void main() {
  group('downloadFileWithRetry', () {
    late HttpServer server;
    late Directory destDir;
    late int requests;
    final body = List<int>.generate(4096, (i) => i % 256);

    setUp(() async {
      requests = 0;
      destDir = await Directory.systemTemp.createTemp('download_retry_test');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests++;
        if (requests == 1) {
          // Drop the first connection, like a download cut off when Android
          // blocks network access for a backgrounded app (#2894).
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.destroy();
          return;
        }
        request.response.contentLength = body.length;
        request.response.add(body);
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await destDir.delete(recursive: true);
    });

    Future<File> download({required Future<bool> Function() holdRetry}) =>
        downloadFileWithRetry('app', false, null, destDir.path, {
          'url': 'http://127.0.0.1:${server.port}/app.apk',
        }, holdRetry: holdRetry);

    test('holds the retry until holdRetry completes', () async {
      final release = Completer<void>();
      var holds = 0;

      final file = download(
        holdRetry: () async {
          holds++;
          await release.future;
          return true;
        },
      );

      // While holdRetry has not completed, no retry may reach the server.
      await Future.delayed(const Duration(seconds: 7));
      expect(holds, 1);
      expect(requests, 1);

      release.complete();

      expect(await (await file).readAsBytes(), body);
      expect(holds, 1);
      expect(requests, greaterThan(1));
    });

    test('reports the original error when holdRetry returns false', () async {
      var holds = 0;

      await expectLater(
        download(
          holdRetry: () async {
            holds++;
            return false;
          },
        ),
        throwsA(isA<HttpException>()),
      );

      expect(holds, 1);
      expect(requests, 1);
    });
  });
}
