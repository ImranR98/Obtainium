import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

import 'e2e_helpers.dart';

/// A download whose URL redirects to a ZIP served as application/zip without a
/// filename must be treated as an archive, not parsed (and rejected) as an APK
/// (#3372).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('redirected ZIP download is extracted for the APK', (
    tester,
  ) async {
    if (await skipIfTV()) return;

    final apkBytes = await _fetchBytes('$e2eBaseUrl/testapp-v2.apk');
    final zipBytes = _zipContaining('nested/testapp-v2.apk', apkBytes);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      final response = request.response;
      if (request.uri.path == '/dl') {
        response.statusCode = HttpStatus.found;
        response.headers.set(
          'location',
          'http://127.0.0.1:${server.port}/app.zip',
        );
      } else if (request.uri.path == '/app.zip') {
        response.headers.contentType = ContentType('application', 'zip');
        response.add(zipBytes);
      } else if (request.uri.path == '/noapk.zip') {
        response.headers.contentType = ContentType('application', 'zip');
        response.add(_zipContaining('readme.txt', utf8.encode('no apk here')));
      } else if (request.uri.path == '/corrupt.apk') {
        response.headers.contentType = ContentType(
          'application',
          'vnd.android.package-archive',
        );
        response.add(List<int>.generate(2048, (i) => i % 251));
      } else {
        response.statusCode = HttpStatus.notFound;
      }
      unawaited(response.close());
    });

    try {
      await clearAppData();
      await launchApp(tester);

      final url = 'http://127.0.0.1:${server.port}/dl';
      final source = SourceProvider().getSource(
        url,
        overrideSource: 'DirectAPKLink',
      );
      final app = await SourceProvider().getApp(source, url, {
        'defaultPseudoVersioningMethod': 'APKLinkHash',
        'allowInsecure': true,
        'versionDetection': true,
      });

      final artifact = await readProvider<AppsProvider>().downloadApp(
        app,
        null,
      );
      final resolvedId = artifact is DownloadedApk
          ? artifact.appId
          : (artifact as DownloadedDir).appId;
      expect(resolvedId, e2eTestPackageId);

      Future<Object> download(String path) async {
        final url = 'http://127.0.0.1:${server.port}$path';
        final app = await SourceProvider().getApp(source, url, {
          'defaultPseudoVersioningMethod': 'APKLinkHash',
          'allowInsecure': true,
          'versionDetection': true,
        });
        return readProvider<AppsProvider>().downloadApp(app, null);
      }

      await expectLater(download('/noapk.zip'), throwsA(isA<NoAPKError>()));
      await expectLater(
        download('/corrupt.apk'),
        throwsA(
          isA<ObtainiumError>().having(
            (e) => e.message,
            'message',
            isNot(contains('unzip_error')),
          ),
        ),
      );
    } finally {
      await server.close(force: true);
    }

    restoreErrorWidgetBuilder();
  });
}

Future<Uint8List> _fetchBytes(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    final builder = BytesBuilder();
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  } finally {
    client.close();
  }
}

Uint8List _zipContaining(String name, List<int> bytes) {
  final archiveFile = archive.Archive()
    ..addFile(archive.ArchiveFile(name, bytes.length, bytes));
  return Uint8List.fromList(archive.ZipEncoder().encode(archiveFile));
}
