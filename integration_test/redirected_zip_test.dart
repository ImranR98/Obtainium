import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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
      if (request.uri.path == '/dl') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          'location',
          'http://127.0.0.1:${server.port}/app.zip',
        );
      } else {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'application',
          'zip',
        );
        request.response.add(zipBytes);
      }
      unawaited(request.response.close());
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
