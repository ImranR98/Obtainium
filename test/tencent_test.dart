import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/tencent.dart';

const _url = 'https://sj.qq.com/appdetail/com.example.app';
const _apkUrl = 'https://download.example.test/app.apk?fsname=example.apk';
const _digest = '0123456789abcdef0123456789abcdef';
const _record = {
  'pkg_name': 'com.example.app',
  'version_name': '1.2.3',
  'apk_size': '12345678',
  'md_5': _digest,
  'update_time': '1791812310',
};

class _Tencent extends Tencent {
  final List<Object> responses;
  final requests = <({String url, bool followRedirects})>[];

  _Tencent(this.responses);

  @override
  Future<Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    requests.add((url: url, followRedirects: followRedirects));
    final response = responses.removeAt(0);
    if (response is Future<Response>) return response;
    if (response is Response) return response;
    throw response;
  }
}

Response _legacy([Map<String, dynamic> changes = const {}]) => Response(
  'window.systemData=${jsonEncode({
    'appDetail': {
      'versionName': '1.2.3',
      'appName': 'Example app',
      'author': 'Example publisher',
      'apkUrl': _apkUrl,
      'apkUrl64': _apkUrl,
      'apkMd5': _digest.toUpperCase(),
      'fileSize': {'bytes': 12345678},
      ...changes,
    },
  })}',
  200,
);

Map<String, dynamic> _component(
  List<dynamic> records, {
  String cardId = 'yybn_game_basic_info',
  String name = 'GameDetail',
}) => {
  'cardId': cardId,
  'data': {'name': name, 'cardid': cardId, 'itemData': records},
};

Response _page(
  List<dynamic> components, {
  Map<String, dynamic> otherProps = const {},
}) => Response(
  '<html><script id="__NEXT_DATA__" type="application/json">${jsonEncode({
    'props': {
      'pageProps': {
        'dynamicCardResponse': {
          'data': {'components': components},
        },
        ...otherProps,
      },
    },
  })}</script></html>',
  200,
);

void _expectDownload(dynamic result) {
  expect(result.version, '1.2.3');
  expect(result.names.author, 'Example publisher');
  expect(result.names.name, 'Example app');
  expect(result.apkUrls.single.key, 'example.apk');
  expect(result.apkUrls.single.value, _apkUrl);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('binds a UTC release date to the selected legacy APK', () async {
    for (final use64 in [false, true]) {
      final source = _Tencent([
        _legacy({'apkUrl64': use64 ? _apkUrl : null}),
        _page([
          _component([], cardId: 'container', name: 'GameDetailContainer'),
          _component([
            _record,
            {'comments': []},
          ]),
        ]),
      ]);
      final result = await source.getLatestAPKDetails(_url, {});
      _expectDownload(result);
      expect(
        result.releaseDate,
        DateTime.fromMillisecondsSinceEpoch(1791812310000, isUtc: true),
      );
      expect(result.releaseDate!.isUtc, isTrue);
      expect(source.requests.map((request) => request.url), [
        'https://a.app.qq.com/o/simple.jsp?pkgname=com.example.app',
        _url,
      ]);
      expect(source.requests.last.followRedirects, isFalse);
      expect(source.responses, isEmpty);
    }
  });

  test(
    'ignores client and recommendation timestamps outside the main detail',
    () async {
      final distraction = _component(
        [_record],
        cardId: 'yybn_game_related_game',
        name: 'YouMayAlsoLike',
      );
      for (final main in [
        <Map<String, dynamic>>[],
        [
          {..._record, 'pkg_name': 'com.other.app'},
        ],
        [
          {..._record, 'version_name': 'old version'},
        ],
      ]) {
        final source = _Tencent([
          _legacy(),
          _page(
            [distraction, _component(main)],
            otherProps: {'YYBAppInfo': _record},
          ),
        ]);
        final result = await source.getLatestAPKDetails(_url, {});
        _expectDownload(result);
        expect(result.releaseDate, isNull);
      }
      final source = _Tencent([
        _legacy(),
        _page(
          [
            distraction,
            _component([_record]),
          ],
          otherProps: {
            'YYBAppInfo': {..._record, 'update_time': '1'},
          },
        ),
      ]);
      expect(
        (await source.getLatestAPKDetails(_url, {})).releaseDate,
        DateTime.fromMillisecondsSinceEpoch(1791812310000, isUtc: true),
      );
    },
  );

  test('rejects mismatched or ambiguous main release metadata', () async {
    for (final records in [
      [
        {..._record, 'pkg_name': 'com.other.app'},
      ],
      [
        {..._record, 'version_name': '1.2.4'},
      ],
      [
        {..._record, 'md_5': 'ffffffffffffffffffffffffffffffff'},
      ],
      [
        {..._record, 'md_5': 'invalid'},
      ],
      [
        {..._record, 'apk_size': '12345679'},
      ],
      [
        {..._record, 'apk_size': null},
      ],
      [_record, _record],
      [
        _record,
        {..._record, 'version_name': '1.2.4'},
      ],
    ]) {
      final source = _Tencent([
        _legacy(),
        _page([_component(records)]),
      ]);
      final result = await source.getLatestAPKDetails(_url, {});
      _expectDownload(result);
      expect(result.releaseDate, isNull);
    }
  });

  test('invalid release timestamps preserve the existing APK', () async {
    for (final time in <Object?>[
      null,
      '',
      'not a timestamp',
      '1791812310.5',
      -1,
      0,
      1791812310000,
      DateTime.now().add(const Duration(days: 2)).millisecondsSinceEpoch ~/
          1000,
      '99999999999999999999999999999',
    ]) {
      final source = _Tencent([
        _legacy(),
        _page([
          _component([
            {..._record, 'update_time': time},
          ]),
        ]),
      ]);
      final result = await source.getLatestAPKDetails(_url, {});
      _expectDownload(result);
      expect(result.releaseDate, isNull);
    }
  });

  test('unbound legacy fingerprints skip the optional page request', () async {
    for (final changes in <Map<String, dynamic>>[
      {'apkUrl64': 'https://download.example.test/other64.apk'},
      {'apkMd5': ''},
      {'apkMd5': 'not a digest'},
      {'fileSize': null},
      {
        'fileSize': {'bytes': 0},
      },
      {
        'fileSize': {'bytes': 'invalid'},
      },
    ]) {
      final source = _Tencent([_legacy(changes)]);
      final result = await source.getLatestAPKDetails(_url, {});
      expect(result.version, '1.2.3');
      expect(result.releaseDate, isNull);
      expect(result.apkUrls.single.value, changes['apkUrl64'] ?? _apkUrl);
      expect(source.requests.length, 1);
    }
  });

  test(
    'optional transport and malformed page failures preserve the APK',
    () async {
      for (final failure in <Object>[
        const SocketException('unavailable'),
        Response('Unavailable', 503),
        Response('Rate limited', 429, headers: {'retry-after': '600'}),
        Response('<html>No metadata</html>', 200),
        Response('<script id="__NEXT_DATA__">invalid</script>', 200),
        Response('<script id="__NEXT_DATA__">{}</script>', 200),
        _page([
          {
            'data': {'itemData': 'invalid'},
          },
        ]),
        Response(
          '${_page([
            _component([_record]),
          ]).body}<script id="__NEXT_DATA__">{}</script>',
          200,
        ),
      ]) {
        final source = _Tencent([_legacy(), failure]);
        final result = await source.getLatestAPKDetails(_url, {});
        _expectDownload(result);
        expect(result.releaseDate, isNull);
        expect(source.requests.length, 2);
      }
    },
  );

  testWidgets('optional page timeout returns the existing APK', (tester) async {
    final source = _Tencent([_legacy(), Completer<Response>().future]);
    dynamic result;
    final operation = source
        .getLatestAPKDetails(_url, {})
        .then((value) => result = value);
    await tester.pump();
    expect(result, isNull);
    expect(source.requests.length, 2);
    await tester.pump(const Duration(seconds: 14));
    expect(result, isNull);
    await tester.pump(const Duration(seconds: 1));
    await operation;
    _expectDownload(result);
    expect(result.releaseDate, isNull);
  });
}
