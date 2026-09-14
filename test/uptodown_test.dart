import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:obtainium/app_sources/uptodown.dart';
import 'package:obtainium/custom_errors.dart';

class _UptodownWithPage extends Uptodown {
  final String page;

  _UptodownWithPage(this.page);

  @override
  Future<http.Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async => http.Response(
    page,
    200,
    headers: {'content-type': 'text/html; charset=utf-8'},
  );
}

void main() {
  const url = 'https://character-ai.en.uptodown.com/android/download';

  test('standardizes app URLs to English', () {
    final source = Uptodown();
    for (final input in [
      'https://character-ai.uptodown.com/android/download',
      'https://character-ai.ru.uptodown.com/android',
      'https://character-ai.en.uptodown.com/android/download/1213975188-x',
      'https://character-ai.uptodown.com/android?lang=ru',
    ]) {
      expect(source.standardizeUrl(input), url, reason: input);
    }
    expect(
      source.standardizeUrl('https://ai.uptodown.com/android'),
      'https://ai.en.uptodown.com/android/download',
    );
  });

  // Keep the size fourth from the end, as in the reported page layout.
  String page(String fileType) =>
      '''
<div class="version">1.17.3</div>
<h1 id="detail-app-name" data-file-id="1213975188">Character AI</h1>
<a id="author-link">Character.AI</a>
<section id="technical-information"><table>
  <tr><th>File type</th><td> $fileType </td></tr>
  <tr><th>Date</th><td>Sep 11, 2026</td></tr>
  <tr><th>Size</th><td>174.92 MB</td></tr>
  <tr><th>SHA256</th><td>checksum</td></tr>
  <tr><th>Google Play</th><td>Matches the published version</td></tr>
  <tr><th>Package Name</th><td>ai.character.app</td></tr>
</table></section>
''';

  test('parses all app details from the download page', () async {
    final source = _UptodownWithPage(page('XAPK'));

    expect(await source.getAppDetailsFromPage(url, {}), {
      'version': '1.17.3',
      'appId': 'ai.character.app',
      'name': 'Character AI',
      'author': 'Character.AI',
      'dateStr': 'Sep 11, 2026',
      'fileId': '1213975188',
      'extension': 'xapk',
    });
  });

  test('builds release details with the labeled XAPK extension', () async {
    final source = _UptodownWithPage(page('XAPK'));
    final details = await source.getLatestAPKDetails(url, {});

    expect(details.version, '1.17.3');
    expect(details.names.name, 'Character AI');
    expect(details.names.author, 'Character.AI');
    expect(details.apkUrls.single.key, 'ai.character.app.xapk');
    expect(details.apkUrls.single.value, '$url/1213975188-x');
    expect(details.releaseDate, DateTime(2026, 9, 11));
  });

  test('uses icons for localized technical information labels', () async {
    final source = _UptodownWithPage('''
<section id="technical-information"><table>
  <tr>
    <td><img src="https://stc.utdstc.com/img/icons-info.svg#icon-40-downloads"></td>
    <th>Descargas</th><td>3.031.714</td>
  </tr>
  <tr>
    <td><img src="https://stc.utdstc.com/img/icons-info.svg#icon-40-date"></td>
    <th>Fecha</th><td>14 sep. 2026</td>
  </tr>
  <tr>
    <td><img src="https://stc.utdstc.com/img/icons-info.svg#icon-40-type"></td>
    <th>Tipo de archivo</th><td>XAPK</td>
  </tr>
  <tr>
    <td><img src="https://stc.utdstc.com/img/icons-info.svg#icon-40-package"></td>
    <th>Nombre de paquete</th><td>ai.character.app</td>
  </tr>
</table></section>
''');
    final details = await source.getAppDetailsFromPage(url, {});

    expect(details['appId'], 'ai.character.app');
    expect(details['dateStr'], '14 sep. 2026');
    expect(details['extension'], 'xapk');
  });

  test('uses icon fragments when labels are missing or empty', () async {
    for (final heading in ['', '<th> </th>']) {
      final source = _UptodownWithPage('''
<section id="technical-information"><table>
  <tr>
    <td><img src="/img/icons-info.svg#icon-40-package"></td>
    $heading<td>ai.character.app</td>
  </tr>
</table></section>
''');
      final details = await source.getAppDetailsFromPage(url, {});

      expect(details['appId'], 'ai.character.app', reason: heading);
    }
  });

  test('prefers recognized labels and ignores unknown icons', () async {
    final source = _UptodownWithPage('''
<section id="technical-information"><table>
  <tr>
    <td><img src="/img/icons-info.svg#icon-40-date"></td>
    <th> Package Name </th><td>ai.character.app</td>
  </tr>
  <tr>
    <td><img src="/img/icons-info.svg#icon-40-downloads"></td>
    <th>Descargas</th><td>3.031.714</td>
  </tr>
</table></section>
''');
    final details = await source.getAppDetailsFromPage(url, {});

    expect(details['appId'], 'ai.character.app');
    expect(details['dateStr'], isNull);
    expect(details['extension'], isNull);
  });

  test('prefers the download button file ID over the heading', () async {
    final source = _UptodownWithPage(
      '${page('XAPK')}'
      '<button id="detail-download-button" data-file-id="1213975189">'
      'Download</button>',
    );
    final details = await source.getLatestAPKDetails(url, {});

    expect(details.apkUrls.single.value, '$url/1213975189-x');
  });

  test('normalizes the APK extension', () async {
    final source = _UptodownWithPage(page('ApK'));
    final details = await source.getLatestAPKDetails(url, {});

    expect(details.apkUrls.single.key, 'ai.character.app.apk');
  });

  test('rejects an unrecognized file type', () async {
    final source = _UptodownWithPage(page('duck'));

    await expectLater(
      source.getLatestAPKDetails(url, {}),
      throwsA(isA<NoAPKError>()),
    );
  });

  test('leaves the release date unset when its label is missing', () async {
    final source = _UptodownWithPage(
      page('XAPK').replaceFirst('<th>Date</th>', '<th>Other</th>'),
    );
    final details = await source.getLatestAPKDetails(url, {});

    expect(details.releaseDate, isNull);
  });
}
