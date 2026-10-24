import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:obtainium/app_sources/fdroidrepo.dart';

const _repo = 'https://cdn.kde.org/android/stable-releases/fdroid/repo';
const _appId = 'org.kde.itinerary';

Map<String, dynamic> _version(int code, String apk, String abi) => {
  'added': 1792000000000,
  'file': {'name': '/$apk'},
  'manifest': {
    'versionName': '26.08.2',
    'versionCode': code,
    'nativecode': [abi],
  },
};

// Shaped like the KDE repo's index-v2.json: two builds of 26.08.2, each split
// per architecture.
final _index = jsonEncode({
  'packages': {
    _appId: {
      'metadata': {
        'name': {'en-US': 'KDE Itinerary'},
      },
      'versions': {
        'a': _version(
          1792604176,
          'itinerary-20261021-arm64-v8a.apk',
          'arm64-v8a',
        ),
        'b': _version(1792604175, 'itinerary-20261021-x86_64.apk', 'x86_64'),
        'c': _version(
          1792168061,
          'itinerary-20261016-arm64-v8a.apk',
          'arm64-v8a',
        ),
        'd': _version(1792168060, 'itinerary-20261016-x86_64.apk', 'x86_64'),
      },
    },
  },
});

class _TestFDroidRepo extends FDroidRepo {
  final List<String> abis;

  _TestFDroidRepo(this.abis);

  @override
  Future<List<String>> getSupportedAbis() async => abis;

  @override
  Future<http.Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    if (url != '$_repo/index-v2.json') return http.Response('Not found', 404);
    return http.Response(
      _index,
      200,
      request: http.Request('GET', Uri.parse(url)),
    );
  }
}

void main() {
  test('only the newest build of a version name is offered per ABI', () async {
    final details = await _TestFDroidRepo(['arm64-v8a']).getLatestAPKDetails(
      '$_repo?appId=$_appId',
      {'trySelectingSuggestedVersionCode': true},
    );
    expect(details.version, '26.08.2');
    expect(details.apkUrls.map((e) => e.value), [
      '$_repo/itinerary-20261021-arm64-v8a.apk',
    ]);
  });

  test(
    'without a matching ABI, each ABI still gets its newest build',
    () async {
      final details = await _TestFDroidRepo(['armeabi-v7a'])
          .getLatestAPKDetails('$_repo?appId=$_appId', {
            'trySelectingSuggestedVersionCode': true,
          });
      expect(details.apkUrls.map((e) => e.value), [
        '$_repo/itinerary-20261021-arm64-v8a.apk',
        '$_repo/itinerary-20261021-x86_64.apk',
      ]);
    },
  );
}
