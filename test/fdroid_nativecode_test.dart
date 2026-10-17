import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/models/app.dart';

const _appId = 'org.proninyaroslav.libretorrent';
const _apiUrl = 'https://f-droid.org/api/v1/packages/$_appId';
const _pageUrl = 'https://f-droid.org/en/packages/$_appId/';
const _standardUrl = 'https://f-droid.org/packages/$_appId';

const _apiResponse =
    '''
{
  "packageName": "$_appId",
  "suggestedVersionCode": 9000354,
  "packages": [
    {"versionName": "4.1.1", "versionCode": 9000354},
    {"versionName": "4.1.1", "versionCode": 9000353},
    {"versionName": "4.1.1", "versionCode": 9000352},
    {"versionName": "4.1.1", "versionCode": 9000351}
  ]
}
''';

String _versionBlock(
  String versionName,
  int versionCode,
  String? nativecode, {
  String? addedOn,
}) =>
    '''
<li class="package-version">
  <div class="package-version-header">
    <a name="$versionName"></a>
    <a name="$versionCode"></a>
    <b>Version $versionName</b> ($versionCode)
    ${addedOn == null ? '' : 'Added on $addedOn'}
  </div>
  ${nativecode == null ? '' : '<p class="package-version-nativecode"><code class="package-nativecode">$nativecode</code></p>'}
  <p class="package-version-download">
    <b><a href="https://f-droid.org/repo/${_appId}_$versionCode.apk">Download APK</a></b>
    <a href="https://f-droid.org/repo/${_appId}_$versionCode.apk.asc">PGP Signature</a>
  </p>
</li>
''';

final _page =
    '''
<html><body><ul>
${_versionBlock('4.1.1', 9000354, 'x86_64')}
${_versionBlock('4.1.1', 9000353, 'x86')}
${_versionBlock('4.1.1', 9000352, 'arm64-v8a')}
${_versionBlock('4.1.1', 9000351, 'armeabi-v7a')}
${_versionBlock('4.1', 9000344, 'x86_64')}
</ul></body></html>
''';

class _TestFDroid extends FDroid {
  final Map<String, String> responses;
  final List<String> abis;
  final List<String> requestedUrls = [];

  _TestFDroid(this.responses, this.abis);

  @override
  Future<List<String>> getSupportedAbis() async => abis;

  @override
  Future<http.Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    requestedUrls.add(url);
    final body = responses[url];
    if (body == null) {
      return http.Response('Not found', 404);
    }
    return http.Response(
      body,
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }
}

const _defaultSettings = {
  'trySelectingSuggestedVersionCode': true,
  'autoApkFilterByArch': true,
};

void main() {
  group('parseNativecodesFromPackagePage', () {
    test('maps each version code to its native architectures', () {
      final nativecodes = FDroid.parseNativecodesFromPackagePage(_page);
      expect(nativecodes, {
        9000354: ['x86_64'],
        9000353: ['x86'],
        9000352: ['arm64-v8a'],
        9000351: ['armeabi-v7a'],
        9000344: ['x86_64'],
      });
    });

    test('maps versions without a nativecode note to an empty list', () {
      final nativecodes = FDroid.parseNativecodesFromPackagePage(
        _versionBlock('1.0', 1234, null),
      );
      expect(nativecodes, {1234: <String>[]});
    });

    test('parses the Added on date for each version code', () {
      final metadata = FDroid.parsePackagePageMetadata(
        _versionBlock('1.0', 1234, 'arm64-v8a', addedOn: 'Oct 12, 2026'),
      );
      expect(metadata.nativecodes, {
        1234: ['arm64-v8a'],
      });
      expect(metadata.addedOn, {1234: DateTime(2026, 10, 12)});
    });

    test('ignores blocks without a downloadable APK', () {
      expect(
        FDroid.parseNativecodesFromPackagePage(
          '<li class="package-version">'
          '<div class="package-version-header">Version 1.0 (1)</div>'
          '</li>',
        ),
        isEmpty,
      );
    });
  });

  group('FDroid architecture filtering (#2529)', () {
    test('prefers the device ABI over the suggested APK', () async {
      final source = _TestFDroid(
        {_apiUrl: _apiResponse, _pageUrl: _page},
        ['arm64-v8a', 'armeabi-v7a'],
      );
      final details = await source.getLatestAPKDetails(
        _standardUrl,
        _defaultSettings,
      );
      expect(details.apkUrls, hasLength(1));
      expect(details.apkUrls.single.value, endsWith('${_appId}_9000352.apk'));
      expect(details.version, '4.1.1');
      expect(source.requestedUrls, contains(_pageUrl));
    });

    test('uses the device ABI order as preference order', () async {
      final source = _TestFDroid(
        {_apiUrl: _apiResponse, _pageUrl: _page},
        ['armeabi-v7a'],
      );
      final details = await source.getLatestAPKDetails(
        _standardUrl,
        _defaultSettings,
      );
      expect(details.apkUrls, hasLength(1));
      expect(details.apkUrls.single.value, endsWith('${_appId}_9000351.apk'));
    });

    test('keeps the suggested APK when it matches the device', () async {
      final source = _TestFDroid(
        {_apiUrl: _apiResponse, _pageUrl: _page},
        ['x86_64', 'x86'],
      );
      final details = await source.getLatestAPKDetails(
        _standardUrl,
        _defaultSettings,
      );
      expect(details.apkUrls, hasLength(1));
      expect(details.apkUrls.single.value, endsWith('${_appId}_9000354.apk'));
    });

    test('does not filter when the setting is disabled', () async {
      final source = _TestFDroid(
        {_apiUrl: _apiResponse, _pageUrl: _page},
        ['arm64-v8a', 'armeabi-v7a'],
      );
      final details = await source.getLatestAPKDetails(_standardUrl, {
        ..._defaultSettings,
        'autoApkFilterByArch': false,
      });
      expect(details.apkUrls, hasLength(1));
      expect(details.apkUrls.single.value, endsWith('${_appId}_9000354.apk'));
      expect(source.requestedUrls, contains(_pageUrl));
    });

    test(
      'falls back to the suggested APK when the page cannot be read',
      () async {
        final source = _TestFDroid(
          {_apiUrl: _apiResponse},
          ['arm64-v8a', 'armeabi-v7a'],
        );
        final details = await source.getLatestAPKDetails(
          _standardUrl,
          _defaultSettings,
        );
        expect(details.apkUrls, hasLength(1));
        expect(details.apkUrls.single.value, endsWith('${_appId}_9000354.apk'));
      },
    );

    test(
      'keeps the suggested APK when nativecode info is unavailable',
      () async {
        final olderPage =
            '''
<html><body><ul>
${_versionBlock('4.1', 9000344, 'x86_64')}
${_versionBlock('4.1', 9000343, 'x86')}
</ul></body></html>
''';
        final source = _TestFDroid(
          {_apiUrl: _apiResponse, _pageUrl: olderPage},
          ['arm64-v8a', 'armeabi-v7a'],
        );
        final details = await source.getLatestAPKDetails(
          _standardUrl,
          _defaultSettings,
        );
        expect(details.apkUrls, hasLength(1));
        expect(details.apkUrls.single.value, endsWith('${_appId}_9000354.apk'));
      },
    );

    test('keeps the suggested APK when the version is universal', () async {
      final universalPage =
          '''
<html><body><ul>
${_versionBlock('4.1.1', 9000354, null)}
${_versionBlock('4.1.1', 9000353, null)}
</ul></body></html>
''';
      final source = _TestFDroid(
        {_apiUrl: _apiResponse, _pageUrl: universalPage},
        ['arm64-v8a', 'armeabi-v7a'],
      );
      final details = await source.getLatestAPKDetails(
        _standardUrl,
        _defaultSettings,
      );
      expect(details.apkUrls, hasLength(1));
      expect(details.apkUrls.single.value, endsWith('${_appId}_9000354.apk'));
    });

    test('fetches the page for a date even with a single APK', () async {
      const singleResponse =
          '''
{
  "packageName": "$_appId",
  "suggestedVersionCode": 9000354,
  "packages": [
    {"versionName": "4.1.1", "versionCode": 9000354}
  ]
}
''';
      final singlePage = _versionBlock(
        '4.1.1',
        9000354,
        'x86_64',
        addedOn: 'Oct 12, 2026',
      );
      final source = _TestFDroid(
        {_apiUrl: singleResponse, _pageUrl: singlePage},
        ['arm64-v8a'],
      );
      final details = await source.getLatestAPKDetails(
        _standardUrl,
        _defaultSettings,
      );
      expect(details.apkUrls, hasLength(1));
      expect(source.requestedUrls, contains(_pageUrl));
      expect(details.releaseDate, DateTime(2026, 10, 12));
    });

    test(
      'supports page metadata when the official host was overridden',
      () async {
        final source = _TestFDroid(
          {_apiUrl: _apiResponse, _pageUrl: _page},
          ['arm64-v8a'],
        );
        source.hostChanged = true;
        source.hostIdenticalDespiteAnyChange = true;
        final details = await source.getLatestAPKDetails(
          _standardUrl,
          _defaultSettings,
        );
        expect(source.requestedUrls, contains(_pageUrl));
        expect(details.apkUrls, hasLength(1));
      },
    );

    test('exposes per-APK ABIs for the picker', () async {
      final source = _TestFDroid(
        {_apiUrl: _apiResponse, _pageUrl: _page},
        ['arm64-v8a'],
      );
      const app = App(
        id: _appId,
        url: _standardUrl,
        author: 'F-Droid',
        name: 'LibreTorrent',
        latestVersion: '4.1.1',
        apkUrls: [
          MapEntry('arm64', 'https://f-droid.org/repo/${_appId}_9000352.apk'),
          MapEntry(
            'universal',
            'https://f-droid.org/repo/${_appId}_9000354.apk',
          ),
        ],
        preferredApkIndex: 0,
        additionalSettings: {},
      );
      expect(await source.getApkAbisByUrl(app), {
        'https://f-droid.org/repo/${_appId}_9000352.apk': ['arm64-v8a'],
        'https://f-droid.org/repo/${_appId}_9000354.apk': ['x86_64'],
      });
    });
  });

  group('filterReleasesByNativecode', () {
    test('returns null when no release has nativecode info', () {
      expect(
        FDroid.filterReleasesByNativecode(
          [
            {'versionCode': 1},
            {'versionCode': 2},
          ],
          const {},
          const ['arm64-v8a'],
        ),
        isNull,
      );
    });

    test('returns null when nothing matches the device ABIs', () {
      expect(
        FDroid.filterReleasesByNativecode(
          [
            {'versionCode': 1},
            {'versionCode': 2},
          ],
          const {
            1: ['arm64-v8a'],
            2: ['x86_64'],
          },
          const ['riscv64'],
        ),
        isNull,
      );
    });

    test('prefers the first matching device ABI', () {
      final filtered = FDroid.filterReleasesByNativecode(
        [
          {'versionCode': 1},
          {'versionCode': 2},
        ],
        const {
          1: ['armeabi-v7a'],
          2: ['arm64-v8a'],
        },
        const ['arm64-v8a', 'armeabi-v7a'],
      );
      expect(filtered, hasLength(1));
      expect(filtered!.single['versionCode'], 2);
    });
  });
}
