import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/samsunggalaxystore.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:xml/xml.dart';

class _OdsGalaxyStore extends SamsungGalaxyStore {
  final List<Object> responses;
  final requests = <({Uri uri, Object? body, bool followRedirects})>[];
  final bool explicitDiscovery;
  final bool explicitDetails;

  _OdsGalaxyStore(
    this.responses, {
    this.explicitDiscovery = false,
    this.explicitDetails = false,
  });

  Iterable<({Uri uri, Object? body, bool followRedirects})> get coreRequests =>
      requests.where(
        (r) =>
            !['2300', '2290', '2291'].contains(r.uri.queryParameters['reqId']),
      );

  @override
  Future<Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    requests.add((
      uri: Uri.parse(url),
      body: postBody,
      followRedirects: followRedirects,
    ));
    final id = Uri.parse(url).queryParameters['reqId'];
    if (id == '2300' && !explicitDiscovery) return _ods({}, id: id);
    if (['2290', '2291'].contains(id) && !explicitDetails) {
      return _ods({}, id: id);
    }
    final response = responses.removeAt(0);
    if (response is Future<Response>) return response;
    if (response is Response) {
      if (response.body.contains('id="AUTO"')) {
        return Response(
          response.body.replaceFirst('id="AUTO"', 'id="$id"'),
          response.statusCode,
          headers: response.headers,
        );
      }
      return response;
    }
    throw response;
  }
}

class _StatusResponse extends Response {
  var _status = 200;

  _StatusResponse(int status) : super('', 200) {
    // The http constructor rejects status 0, so override it after construction.
    _status = status;
  }

  @override
  int get statusCode => _status;
}

Response _ods(
  Map<String, String> fields, {
  String? code = '0',
  String extra = '',
  String? id = 'AUTO',
}) {
  final builder = XmlBuilder();
  builder.element(
    'SamsungProtocol',
    nest: () {
      builder.element(
        'response',
        attributes: {
          'id': ?id,
          'returnCode':
              code != null && RegExp(r'^-?\d+$').hasMatch(code) && code != '0'
              ? '1'
              : '0',
        },
        nest: () {
          builder.element(
            'errorInfo',
            nest: () {
              builder.element('errorString', attributes: {'errorCode': ?code});
            },
          );
          builder.element(
            'list',
            nest: () {
              for (final field in fields.entries) {
                builder.element(
                  'value',
                  attributes: {'name': field.key},
                  nest: field.value,
                );
              }
              if (extra.isNotEmpty) builder.xml(extra);
            },
          );
        },
      );
    },
  );
  return Response(
    builder.buildDocument().toXmlString(),
    200,
    headers: {'content-type': 'text/xml; charset=utf-8'},
  );
}

Response _stubResponse([Map<String, String> changes = const {}]) {
  final builder = XmlBuilder();
  builder.element(
    'result',
    nest: () {
      for (final field in {
        'resultCode': '1',
        'appId': 'com.samsung.android.app.sreminder',
        'productId': '000009060570',
        'productName': 'Samsung Assistant',
        'versionName': '9.4.02.7',
        'versionCode': '940207000',
        'contentSize': '106232505',
        'downloadURI': 'https://apps.samsungapps.com/app_20260923000000.apk',
        ...changes,
      }.entries) {
        builder.element(field.key, nest: field.value);
      }
    },
  );
  return Response(builder.buildDocument().toXmlString(), 200);
}

const _metadata = {
  'GUID': 'com.samsung.android.app.sreminder',
  'productID': '000009060570',
  'productName': '三星生活助手',
  'version': '9.4.02.7',
  'versionCode': '940207000',
  'needToLogin': '0',
  'installableYN': 'Y',
  'realContentsSize': '106232505',
};
const _grant = {
  'productID': '000009060570',
  'version': '9.4.02.7',
  'versionCode': '940207000',
  'contentsSize': '106232505',
  'binaryArch': '32n64',
  'downLoadURI':
      'https://cdnet-dn.galaxyappstore.com/App_20260923000000.apk?token=temporary',
  'deltaDownloadURI': 'https://cdnet-dn.galaxyappstore.com/delta.apk',
};
const _china = {'deviceId': 'SM-S9480', 'csc': 'CHC'};
const _linkedUrl = 'https://apps.galaxyappstore.com/detail/com.shuge.fitness';
const _linkedMetadata = {
  'GUID': 'com.shuge.fitness',
  'productID': '000006798608',
  'productName': 'Example Linked App',
  'version': '4.6.32',
  'versionCode': '103',
  'needToLogin': '0',
  'installableYN': 'Y',
  'realContentsSize': '93625737',
  'linkProductYn': '1',
};
const _linkedGrant = {
  'appId': 'tencent-catalog-id',
  'version': '4.6.32',
  'versionCode': '103',
  'contentsSize': '93625737',
  'downLoadURI': 'https://auto-dd.myapp.com/synthetic/full.apk?token=temporary',
};
const _overview = {
  'version': '9.4.02.7',
  'realContentsSize': '106232505',
  'lastUpdateDate': '2026;08;25;',
  'updateDescription': 'Publisher notes.\nKeep & preserve <original> text.',
};

_OdsGalaxyStore _withDetails({
  Response? before,
  Response? overview,
  Response? after,
}) => _OdsGalaxyStore([
  Response('Unavailable', 503),
  _ods(_metadata),
  _ods(_grant),
  before ?? _ods(_metadata),
  overview ?? _ods(_overview),
  after ?? _ods(_metadata),
], explicitDetails: true);

class _RecordingGalaxyStore extends SamsungGalaxyStore {
  late Uri requestUri;

  @override
  Future<Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    if (Uri.parse(url).queryParameters.containsKey('reqId')) {
      return _ods({}, id: Uri.parse(url).queryParameters['reqId']);
    }
    requestUri = Uri.parse(url);
    return _stubResponse();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url =
      'https://apps.galaxyappstore.com/detail/com.samsung.android.app.sreminder';

  test('keeps existing network defaults for unset or blank settings', () async {
    for (final value in [null, '', '   ']) {
      final source = _RecordingGalaxyStore();
      await source.getLatestAPKDetails(url, {'mcc': ?value, 'mnc': ?value});
      expect(source.requestUri.queryParameters['mcc'], '425');
      expect(source.requestUri.queryParameters['mnc'], '01');
      expect(source.requestUri.queryParameters['deviceId'], 'SM-S948B');
      expect(source.requestUri.queryParameters['csc'], 'DBT');
    }
  });

  test(
    'only CHC selects China network defaults and normalizes its CSC',
    () async {
      for (final csc in ['CHC', 'chc', ' CHC ']) {
        final source = _RecordingGalaxyStore();
        await source.getLatestAPKDetails(url, {'csc': csc});
        expect(source.requestUri.queryParameters['csc'], 'CHC');
        expect(source.requestUri.queryParameters['mcc'], '460');
        expect(source.requestUri.queryParameters['mnc'], '00');
        expect(source.requestUri.queryParameters['deviceId'], 'SM-S948B');
      }
      for (final csc in ['DBT', 'XAA', 'dbt', ' DBT ']) {
        final source = _RecordingGalaxyStore();
        await source.getLatestAPKDetails(url, {'csc': csc});
        expect(source.requestUri.queryParameters['csc'], csc);
        expect(source.requestUri.queryParameters['mcc'], '425');
        expect(source.requestUri.queryParameters['mnc'], '01');
      }
    },
  );

  test(
    'uses persisted network overrides and preserves MNC leading zeros',
    () async {
      final source = _RecordingGalaxyStore();
      final result = await source.getLatestAPKDetails(url, {
        'deviceId': 'SM-S9480',
        'csc': 'CHC',
        'mcc': ' 310 ',
        'mnc': ' 00 ',
      });

      expect(source.requestUri.host, 'vas.samsungapps.com');
      expect(source.requestUri.path, '/stub/stubDownload.as');
      expect(source.requestUri.queryParameters, containsPair('mcc', '310'));
      expect(source.requestUri.queryParameters, containsPair('mnc', '00'));
      expect(source.requestUri.queryParameters, containsPair('csc', 'CHC'));
      expect(
        source.requestUri.queryParameters,
        containsPair('deviceId', 'SM-S9480'),
      );
      expect(
        source.requestUri.queryParameters,
        containsPair('appId', 'com.samsung.android.app.sreminder'),
      );
      expect(result.version, '9.4.02.7');
      expect(
        result.apkUrls.single.key,
        'com.samsung.android.app.sreminder.apk',
      );
    },
  );

  test(
    'allows persisted network codes to override either default independently',
    () async {
      final source = _RecordingGalaxyStore();
      await source.getLatestAPKDetails(url, {'mcc': '310'});
      expect(source.requestUri.queryParameters['mcc'], '310');
      expect(source.requestUri.queryParameters['mnc'], '01');

      await source.getLatestAPKDetails(url, {'mnc': '001'});
      expect(source.requestUri.queryParameters['mcc'], '425');
      expect(source.requestUri.queryParameters['mnc'], '001');

      await source.getLatestAPKDetails(url, {'csc': 'CHC', 'mcc': '310'});
      expect(source.requestUri.queryParameters['mcc'], '310');
      expect(source.requestUri.queryParameters['mnc'], '00');

      await source.getLatestAPKDetails(url, {'csc': 'CHC', 'mnc': '001'});
      expect(source.requestUri.queryParameters['mcc'], '460');
      expect(source.requestUri.queryParameters['mnc'], '001');

      await source.getLatestAPKDetails(url, {
        'csc': 'CHC',
        'mcc': ' ',
        'mnc': '',
      });
      expect(source.requestUri.queryParameters['mcc'], '460');
      expect(source.requestUri.queryParameters['mnc'], '00');
    },
  );

  test('keeps network codes out of the app settings form', () {
    final keys = SamsungGalaxyStore()
        .additionalSourceAppSpecificSettingFormItems
        .expand((row) => row)
        .whereType<GeneratedFormTextField>()
        .map((field) => field.key);
    expect(keys, containsAll(['deviceId', 'csc']));
    expect(keys, isNot(contains('mcc')));
    expect(keys, isNot(contains('mnc')));
  });

  test(
    'global stub failures use global ODS without changing network defaults',
    () async {
      final source = _OdsGalaxyStore(
        [
          Response('Unavailable', 503),
          _ods({
            'countryURL': 'http://il-odc.samsungapps.com/ods.as',
            'countryCode': 'ISR',
            'MCC': '425',
          }),
          _ods(_metadata),
          _ods(_grant),
          _ods(_metadata),
          _ods({
            'version': _metadata['version']!,
            'realContentsSize': _metadata['realContentsSize']!,
            'lastUpdateDate': '2026;08;25;',
            'updateDescription': 'Publisher notes.\nSecond line.',
          }),
          _ods(_metadata),
        ],
        explicitDiscovery: true,
        explicitDetails: true,
      );
      final result = await source.getLatestAPKDetails(url, {});
      expect(result.releaseDate, DateTime(2026, 8, 25));
      expect(result.changeLog, 'Publisher notes.\nSecond line.');
      expect(
        source.requests.skip(1).map((r) => r.uri.queryParameters['reqId']),
        ['2300', '2298', '2311', '2290', '2291', '2290'],
      );
      for (final request in source.requests.skip(1)) {
        final envelope = XmlDocument.parse(request.body as String).rootElement;
        expect(envelope.getAttribute('mcc'), '425');
        expect(envelope.getAttribute('mnc'), '01');
        expect(envelope.getAttribute('csc'), 'DBT');
      }
      expect(source.requests[1].uri.host, 'hub-odc.samsungapps.com');
      expect(
        source.requests
            .skip(2)
            .every((r) => r.uri.host == 'il-odc.samsungapps.com'),
        isTrue,
      );
    },
  );

  test('APK filename timestamps are not store release dates', () async {
    final result = await _RecordingGalaxyStore().getLatestAPKDetails(url, {});
    expect(result.releaseDate, isNull);
  });

  test('publisher notes preserve their original outer whitespace', () async {
    const notes = '\n  Publisher notes.\n Keep every line.  \n';
    final result = await _withDetails(
      overview: _ods({..._overview, 'updateDescription': notes}),
    ).getLatestAPKDetails(url, _china);
    expect(result.changeLog, notes);
  });

  test(
    'wrong interface responses cannot supply metadata or optional release details',
    () async {
      final metadataSource = _OdsGalaxyStore([
        Response('Unavailable', 503),
        _ods(_metadata, id: '2290'),
        _ods(_grant),
      ]);
      await expectLater(
        metadataSource.getLatestAPKDetails(url, _china),
        throwsA(isA<ObtainiumError>()),
      );
      expect(metadataSource.coreRequests.length, 2);
      for (final id in [null, '2290']) {
        final result = await _withDetails(
          overview: _ods(_overview, id: id),
        ).getLatestAPKDetails(url, _china);
        expect(result.releaseDate, isNull);
        expect(result.changeLog, isNull);
      }
    },
  );

  test(
    'critical fields disguised as complex lists cannot supply release details',
    () async {
      for (final key in [
        'GUID',
        'productID',
        'version',
        'versionCode',
        'realContentsSize',
        'lastUpdateDate',
        'updateDescription',
      ]) {
        final result = await _withDetails(
          overview: _ods(
            _overview,
            extra:
                '<extList name="$key"><value name="nested">shadow</value></extList>',
          ),
        ).getLatestAPKDetails(url, _china);
        expect(result.releaseDate, isNull);
        expect(result.changeLog, isNull);
      }
    },
  );

  test(
    'successful stub keeps its APK and binds optional details to the same global product',
    () async {
      final source = _OdsGalaxyStore(
        [
          _stubResponse(),
          _ods({
            'countryURL': 'http://us-odc.samsungapps.com/ods.as',
            'countryCode': 'USA',
            'MCC': '310',
          }),
          _ods(_metadata),
          _ods(_overview),
          _ods(_metadata),
        ],
        explicitDiscovery: true,
        explicitDetails: true,
      );
      final result = await source.getLatestAPKDetails(url, {
        'csc': 'XAA',
        'mcc': '310',
        'mnc': '260',
      });
      expect(
        result.apkUrls.single.value,
        'https://apps.samsungapps.com/app_20260923000000.apk',
      );
      expect(result.releaseDate, DateTime(2026, 8, 25));
      expect(result.changeLog, _overview['updateDescription']);
      expect(source.requests.map((r) => r.uri.queryParameters['reqId']), [
        null,
        '2300',
        '2290',
        '2291',
        '2290',
      ]);
      expect(
        source.requests
            .skip(2)
            .every(
              (r) =>
                  r.uri.scheme == 'https' &&
                  r.uri.host == 'us-odc.samsungapps.com',
            ),
        isTrue,
      );
      expect(SamsungGalaxyStore().changeLogIfAnyIsMarkDown, isFalse);
    },
  );

  test(
    'main and overview version drift never attaches other release details',
    () async {
      for (final changes in [
        {'GUID': 'com.other.app'},
        {'productID': '99999'},
        {'version': '1.0'},
        {'versionCode': '940207001'},
        {'realContentsSize': '1'},
      ]) {
        for (final before in [true, false]) {
          final source = _withDetails(
            before: before ? _ods({..._metadata, ...changes}) : null,
            after: before ? null : _ods({..._metadata, ...changes}),
          );
          final result = await source.getLatestAPKDetails(url, _china);
          expect(result.version, _metadata['version']);
          expect(result.apkUrls.single.value, _grant['downLoadURI']);
          expect(result.releaseDate, isNull);
          expect(result.changeLog, isNull);
          expect(
            source.requests
                .where((r) => r.uri.queryParameters['reqId'] == '2291')
                .length,
            before ? 0 : 1,
          );
        }
      }
      for (final changes in [
        {'version': '1.0'},
        {'realContentsSize': '1'},
        {'versionCode': '1'},
      ]) {
        final source = _withDetails(overview: _ods({..._overview, ...changes}));
        final result = await source.getLatestAPKDetails(url, _china);
        expect(result.releaseDate, isNull);
        expect(result.changeLog, isNull);
        expect(
          source.requests
              .where((r) => r.uri.queryParameters['reqId'] == '2290')
              .length,
          1,
        );
      }
    },
  );

  test(
    'missing or invalid store dates stay unknown without rewriting publisher notes',
    () async {
      for (final date in [
        null,
        '2026;02;30;',
        '2026-08-25',
        '20260825',
        '2026;8;25;',
      ]) {
        final fields = {..._overview}..remove('lastUpdateDate');
        if (date != null) fields['lastUpdateDate'] = date;
        final result = await _withDetails(
          overview: _ods(fields),
        ).getLatestAPKDetails(url, _china);
        expect(result.releaseDate, isNull);
        expect(result.changeLog, _overview['updateDescription']);
      }
    },
  );

  test(
    'overview ignores structured display branches but rejects duplicate release fields',
    () async {
      const complex =
          '<extList name="dataSafetyList"><value name="dataSafety">A</value><value name="dataSafety">B</value></extList>'
          '<extList name="curatedComponentList"><extList name="componentInfo"><value name="type">A</value></extList>'
          '<extList name="componentInfo"><value name="type">B</value></extList></extList>';
      final result = await _withDetails(
        overview: _ods(_overview, extra: complex),
      ).getLatestAPKDetails(url, _china);
      expect(result.releaseDate, DateTime(2026, 8, 25));
      expect(result.changeLog, _overview['updateDescription']);
      for (final field in [
        'version',
        'realContentsSize',
        'lastUpdateDate',
        'updateDescription',
      ]) {
        final result = await _withDetails(
          overview: _ods(
            _overview,
            extra: '<value name="$field">duplicate</value>',
          ),
        ).getLatestAPKDetails(url, _china);
        expect(result.releaseDate, isNull);
        expect(result.changeLog, isNull);
      }
    },
  );

  test(
    'detail transport or protocol failures preserve the authorized APK',
    () async {
      for (final failure in <Object>[
        const SocketException('unavailable'),
        Response('Unavailable', 503),
        Response('<html>Unavailable</html>', 200),
        _ods({}, code: '4002'),
      ]) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods(_metadata),
          _ods(_grant),
          failure,
        ], explicitDetails: true);
        final result = await source.getLatestAPKDetails(url, _china);
        expect(result.apkUrls.single.value, _grant['downLoadURI']);
        expect(result.releaseDate, isNull);
        expect(result.changeLog, isNull);
        expect(source.requests.last.uri.queryParameters['reqId'], '2290');
      }
    },
  );

  testWidgets('optional details timeout preserves a successful stub APK', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/device_info'),
      (_) async => throw MissingPluginException(),
    );
    final source = _OdsGalaxyStore([
      _stubResponse(),
      Completer<Response>().future,
      _ods(_overview),
      _ods(_metadata),
    ], explicitDetails: true);
    var completed = false;
    Object? failure;
    final urls = <String>[];
    DateTime? releaseDate;
    String? changeLog;
    final operation = source
        .getLatestAPKDetails(url, _china)
        .then<void>(
          (result) {
            completed = true;
            urls.addAll(result.apkUrls.map((entry) => entry.value));
            releaseDate = result.releaseDate;
            changeLog = result.changeLog;
          },
          onError: (Object error) {
            completed = true;
            failure = error;
          },
        );
    await tester.pump();
    expect(source.requests.last.uri.queryParameters['reqId'], '2290');
    await tester.pump(const Duration(seconds: 39));
    expect(completed, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(completed, isTrue);
    await operation;
    expect(failure, isNull);
    expect(urls, ['https://apps.samsungapps.com/app_20260923000000.apk']);
    expect(releaseDate, isNull);
    expect(changeLog, isNull);
    expect(source.responses.length, 2);
    expect(source.requests.last.uri.queryParameters['reqId'], '2290');
  });

  testWidgets(
    'stub timeout falls back with the same device and network profile',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/device_info'),
        (_) async => throw MissingPluginException(),
      );
      final source = _OdsGalaxyStore([
        Completer<Response>().future,
        _ods(_metadata),
        _ods(_grant),
      ]);
      var completed = false;
      Object? failure;
      final urls = <String>[];
      final operation = source
          .getLatestAPKDetails(url, {..._china, 'mnc': '001'})
          .then<void>(
            (result) {
              completed = true;
              urls.addAll(result.apkUrls.map((entry) => entry.value));
            },
            onError: (Object error) {
              completed = true;
              failure = error;
            },
          );
      await tester.pump();
      expect(source.requests.single.uri.host, 'vas.samsungapps.com');
      await tester.pump(const Duration(seconds: 39));
      expect(completed, isFalse);
      expect(source.requests.length, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(completed, isTrue);
      await operation;
      expect(failure, isNull);
      expect(urls, [_grant['downLoadURI']]);
      for (final request in source.requests.skip(1)) {
        final root = XmlDocument.parse(request.body as String).rootElement;
        expect(root.getAttribute('deviceModel'), 'SM-S9480');
        expect(root.getAttribute('csc'), 'CHC');
        expect(root.getAttribute('mcc'), '460');
        expect(root.getAttribute('mnc'), '001');
        expect(request.uri.host, 'cn-ms.galaxyappstore.com');
      }
    },
  );

  test('stub rate limits preserve retry timing without starting ODS', () async {
    for (final status in [403, 429]) {
      final source = _OdsGalaxyStore([
        Response('Rate limited', status, headers: {'retry-after': '600'}),
        _ods(_metadata),
        _ods(_grant),
      ]);
      await expectLater(
        source.getLatestAPKDetails(url, _china),
        throwsA(
          isA<RateLimitError>().having(
            (error) => error.remainingMinutes,
            'remainingMinutes',
            10,
          ),
        ),
      );
      expect(source.requests.length, 1);
      expect(source.responses.length, 2);
    }
  });

  test(
    'ODS rate limits stop discovery and every authorization stage',
    () async {
      final discovery = _ods({
        'countryURL': 'https://cn-ms.galaxyappstore.com/ods.as',
        'countryCode': 'CHN',
        'MCC': '460',
      });
      final cases = <String, List<Object>>{
        '2300': [],
        '2298': [discovery],
        '2311': [discovery, _ods(_metadata)],
        '2316': [discovery, _ods(_metadata), _ods({}, code: '4002')],
        '2801': [
          discovery,
          _ods(_metadata),
          _ods({}, code: '4002'),
          _ods({}, code: '4002'),
        ],
      };
      for (final entry in cases.entries) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          ...entry.value,
          Response('Rate limited', 429, headers: {'retry-after': '600'}),
          _ods(_grant),
        ], explicitDiscovery: true);
        await expectLater(
          source.getLatestAPKDetails(url, _china),
          throwsA(
            isA<RateLimitError>().having(
              (error) => error.remainingMinutes,
              'remainingMinutes',
              10,
            ),
          ),
        );
        expect(source.requests.last.uri.queryParameters['reqId'], entry.key);
        expect(source.responses.length, 1);
      }
    },
  );

  test(
    'optional discovery and details rate limits keep a valid stub APK',
    () async {
      for (final requestId in ['2300', '2290']) {
        final source = _OdsGalaxyStore(
          [
            _stubResponse(),
            if (requestId == '2290')
              _ods({
                'countryURL': 'https://cn-ms.galaxyappstore.com/ods.as',
                'countryCode': 'CHN',
                'MCC': '460',
              }),
            Response('Rate limited', 429, headers: {'retry-after': '600'}),
            _ods(_metadata),
          ],
          explicitDiscovery: true,
          explicitDetails: true,
        );
        final result = await source.getLatestAPKDetails(url, _china);
        expect(
          result.apkUrls.single.value,
          'https://apps.samsungapps.com/app_20260923000000.apk',
        );
        expect(result.releaseDate, isNull);
        expect(result.changeLog, isNull);
        expect(source.requests.last.uri.queryParameters['reqId'], requestId);
        expect(source.responses.length, 1);
      }
    },
  );

  test(
    'discovery upgrades only trusted same-region endpoints and safely falls back',
    () async {
      final valid = {
        'countryURL': 'http://cn-ms.galaxyappstore.com/ods.as',
        'countryCode': 'CHN',
        'MCC': '460',
      };
      for (final discovery in <Object>[
        _ods(valid),
        const SocketException('unavailable'),
        Response('Unavailable', 503),
        for (final changes in [
          {'countryURL': 'http://cn-ms.galaxyappstore.com.evil.test/ods.as'},
          {'countryURL': 'https://user@cn-ms.galaxyappstore.com/ods.as'},
          {'countryURL': 'https://cn-ms.galaxyappstore.com:444/ods.as'},
          {'countryURL': 'https://cn-ms.galaxyappstore.com/other'},
          {'countryURL': 'https://cn-ms.galaxyappstore.com/ods.as?secret=x'},
          {'countryURL': 'https://cn-ms.galaxyappstore.com/ods.as#fragment'},
          {'countryURL': 'https://us-odc.samsungapps.com/ods.as'},
          {'countryCode': 'USA'},
          {'MCC': '310'},
        ])
          _ods({...valid, ...changes}),
      ]) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          discovery,
          _ods(_metadata),
          _ods(_grant),
        ], explicitDiscovery: true);
        await source.getLatestAPKDetails(url, _china);
        expect(
          source.requests
              .skip(2)
              .every(
                (r) =>
                    r.uri.scheme == 'https' &&
                    r.uri.host == 'cn-ms.galaxyappstore.com' &&
                    r.uri.path == '/ods.as',
              ),
          isTrue,
        );
        final discoveryEnvelope = XmlDocument.parse(
          source.requests[1].body as String,
        ).rootElement.getElement('request')!;
        expect(
          discoveryEnvelope.childElements
              .firstWhere((n) => n.getAttribute('name') == 'latestCountryCode')
              .innerText,
          '460',
        );
        expect(source.responses, isEmpty);
      }
    },
  );

  test(
    'invalid stub identity or URI falls back without importing its metadata',
    () async {
      for (final changes in [
        {'appId': 'com.other.app'},
        {'productId': ''},
        {'versionCode': '0'},
        {'contentSize': '0'},
        {'downloadURI': 'http://apps.samsungapps.com/a.apk'},
        {'downloadURI': 'https://galaxyappstore.com.evil.test/a.apk'},
      ]) {
        final source = _OdsGalaxyStore([
          _stubResponse(changes),
          _ods(_metadata),
          _ods(_grant),
        ]);
        final result = await source.getLatestAPKDetails(url, _china);
        expect(result.names.name, _metadata['productName']);
        expect(result.apkUrls.single.value, _grant['downLoadURI']);
        expect(
          source.coreRequests.elementAt(1).uri.queryParameters['reqId'],
          '2298',
        );
      }
    },
  );

  test(
    'transport failures do not retry restore or mirror authorization',
    () async {
      for (final failure in <Object>[
        const SocketException('unavailable'),
        ObtainiumError('transport failure'),
      ]) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods(_metadata),
          failure,
          _ods(_grant),
        ]);
        await expectLater(
          source.getLatestAPKDetails(url, _china),
          throwsA(anything),
        );
        expect(source.coreRequests.map((r) => r.uri.queryParameters['reqId']), [
          null,
          '2298',
          '2311',
        ]);
        expect(source.responses.length, 1);
      }
    },
  );

  testWidgets('authorization timeout does not retry restore or mirror', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/device_info'),
      (_) async => throw MissingPluginException(),
    );
    final source = _OdsGalaxyStore([
      Response('Unavailable', 503),
      _ods(_metadata),
      Completer<Response>().future,
      _ods(_grant),
    ]);
    var completed = false;
    Object? failure;
    final operation = source
        .getLatestAPKDetails(url, _china)
        .then<void>(
          (_) => completed = true,
          onError: (Object error) {
            completed = true;
            failure = error;
          },
        );
    await tester.pump();
    expect(source.requests.last.uri.queryParameters['reqId'], '2311');
    await tester.pump(const Duration(seconds: 39));
    expect(completed, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(completed, isTrue);
    await operation;
    expect(failure, isA<TimeoutException>());
    expect(source.coreRequests.map((r) => r.uri.queryParameters['reqId']), [
      null,
      '2298',
      '2311',
    ]);
    expect(source.responses.length, 1);
  });

  test(
    'CN mirror is bounded to rejected authorization and exact full APK identity',
    () async {
      final source = _OdsGalaxyStore([
        Response('Unavailable', 503),
        _ods(_metadata),
        _ods({}, code: '4002'),
        _ods({}, code: '4002'),
        _ods({..._grant, 'GUID': _metadata['GUID']!}),
      ]);
      final result = await source.getLatestAPKDetails(url, _china);
      expect(result.version, _metadata['version']);
      expect(
        source.coreRequests.skip(1).map((r) => r.uri.queryParameters['reqId']),
        ['2298', '2311', '2316', '2801'],
      );
      expect(
        source.requests.every(
          (r) => [
            'vas.samsungapps.com',
            'cn-ms.galaxyappstore.com',
          ].contains(r.uri.host),
        ),
        isTrue,
      );
      final request = XmlDocument.parse(
        source.coreRequests.last.body as String,
      ).rootElement.getElement('request')!;
      expect(request.getAttribute('name'), 'downloadInfoForTencent');
      expect(
        request.childElements
            .firstWhere((n) => n.getAttribute('name') == 'lastInterfaceName')
            .innerText,
        'searchProductListEx2Notc',
      );
      expect(
        request.childElements.map((n) => n.getAttribute('name')),
        isNot(contains('orderID')),
      );
    },
  );

  test(
    'CN linked products use the version-bound Tencent full APK directly',
    () async {
      for (final identityFields in [
        <String, String>{},
        {
          'GUID': _linkedMetadata['GUID']!,
          'productID': _linkedMetadata['productID']!,
        },
      ]) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods(_linkedMetadata),
          _ods({..._linkedGrant, ...identityFields}),
        ]);
        final result = await source.getLatestAPKDetails(_linkedUrl, _china);
        expect(result.version, '4.6.32');
        expect(result.names.name, 'Example Linked App');
        expect(result.apkUrls.single.key, 'com.shuge.fitness.apk');
        expect(result.apkUrls.single.value, _linkedGrant['downLoadURI']);
        expect(source.coreRequests.map((r) => r.uri.queryParameters['reqId']), [
          null,
          '2298',
          '2801',
        ]);
        final request = XmlDocument.parse(
          source.coreRequests.last.body as String,
        ).rootElement.getElement('request')!;
        expect(request.getAttribute('name'), 'downloadInfoForTencent');
        final params = {
          for (final p in request.childElements)
            p.getAttribute('name')!: p.innerText,
        };
        expect(params['GUID'], 'com.shuge.fitness');
        expect(params['lastInterfaceName'], 'searchProductListEx2Notc');
        expect(params['stduk'], params['extuk']);
        expect(params, isNot(contains('orderID')));
        expect(source.responses, isEmpty);
      }
    },
  );

  test(
    'absent or native linked flags keep stateless Samsung authorization',
    () async {
      for (final flag in [null, '0']) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods({..._metadata, 'linkProductYn': ?flag}),
          _ods(_grant),
        ]);
        final result = await source.getLatestAPKDetails(url, _china);
        expect(result.apkUrls.single.value, _grant['downLoadURI']);
        expect(source.coreRequests.map((r) => r.uri.queryParameters['reqId']), [
          null,
          '2298',
          '2311',
        ]);
      }
    },
  );

  test('linked metadata rejects unknown flags and structured shadows', () async {
    for (final response in [
      for (final flag in ['', 'Y', '2', '-1'])
        _ods({..._linkedMetadata, 'linkProductYn': flag}),
      _ods(_linkedMetadata, extra: '<value name="linkProductYn">0</value>'),
      _ods(
        _linkedMetadata,
        extra:
            '<extList name="linkProductYn"><value name="nested">1</value></extList>',
      ),
    ]) {
      final source = _OdsGalaxyStore([
        Response('Unavailable', 503),
        response,
        _ods(_linkedGrant),
      ]);
      await expectLater(
        source.getLatestAPKDetails(_linkedUrl, _china),
        throwsA(isA<ObtainiumError>()),
      );
      expect(source.coreRequests.length, 2);
      expect(source.responses.length, 1);
    }
  });

  test(
    'linked authorization requires China and a known full package size',
    () async {
      for (final settings in [<String, dynamic>{}, _china]) {
        final metadata = {..._linkedMetadata};
        if (settings == _china) metadata.remove('realContentsSize');
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods(metadata),
          _ods(_linkedGrant),
        ]);
        await expectLater(
          source.getLatestAPKDetails(_linkedUrl, settings),
          throwsA(isA<NoAPKError>()),
        );
        expect(source.coreRequests.length, 2);
        expect(source.responses.length, 1);
      }
    },
  );

  test(
    'linked grants reject release drift and conflicting optional identities',
    () async {
      for (final changes in [
        {'GUID': ''},
        {'GUID': 'com.other.app'},
        {'productID': ''},
        {'productID': '000006759407'},
        {'version': ''},
        {'version': '4.6.33'},
        {'versionCode': ''},
        {'versionCode': '104'},
        {'contentsSize': ''},
        {'contentsSize': '125317027'},
      ]) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods(_linkedMetadata),
          _ods({..._linkedGrant, ...changes}),
          _ods(_grant),
        ]);
        await expectLater(
          source.getLatestAPKDetails(_linkedUrl, _china),
          throwsA(isA<ObtainiumError>()),
        );
        expect(source.coreRequests.last.uri.queryParameters['reqId'], '2801');
        expect(source.responses.length, 1);
      }
    },
  );

  test(
    'linked Tencent URLs retain exact host and HTTPS restrictions',
    () async {
      for (final apkUrl in [
        'http://auto-dd.myapp.com/a.apk',
        'https://myapp.com/a.apk',
        'https://other.myapp.com/a.apk',
        'https://auto-dd.myapp.com.evil.test/a.apk',
        'https://child.auto-dd.myapp.com/a.apk',
        'https://auto-dd.myapp.com:444/a.apk',
        'https://user@auto-dd.myapp.com/a.apk',
        'https://auto-dd.myapp.com/a.apk#fragment',
        'https://auto-dd.myapp.com/',
        'https://auto-dd.myapp.com/a b.apk',
      ]) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods(_linkedMetadata),
          _ods({..._linkedGrant, 'downLoadURI': apkUrl}),
        ]);
        await expectLater(
          source.getLatestAPKDetails(_linkedUrl, _china),
          throwsA(isA<NoAPKError>()),
        );
        expect(source.coreRequests.last.uri.queryParameters['reqId'], '2801');
        expect(source.responses, isEmpty);
      }
    },
  );

  test(
    'Tencent URLs remain invalid for native, restore and nonlinked mirrors',
    () async {
      final grant = _ods({
        ..._grant,
        'GUID': _metadata['GUID']!,
        'downLoadURI': _linkedGrant['downLoadURI']!,
      });
      for (final rejections in [0, 1, 2]) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods(_metadata),
          for (var i = 0; i < rejections; i++) _ods({}, code: '4002'),
          grant,
        ]);
        await expectLater(
          source.getLatestAPKDetails(url, _china),
          throwsA(isA<NoAPKError>()),
        );
        expect(source.responses, isEmpty);
      }
      final stub = _OdsGalaxyStore([
        _stubResponse({'downloadURI': _linkedGrant['downLoadURI']!}),
        _ods(_metadata),
        _ods(_grant),
      ]);
      expect(
        (await stub.getLatestAPKDetails(url, _china)).apkUrls.single.value,
        _grant['downLoadURI'],
      );
      expect(
        stub.coreRequests.elementAt(1).uri.queryParameters['reqId'],
        '2298',
      );
    },
  );

  test(
    'linked authorization rejection and rate limits never enter native fallback',
    () async {
      for (final response in [
        _ods({}, code: '4002'),
        Response('Rate limited', 429, headers: {'retry-after': '600'}),
      ]) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods(_linkedMetadata),
          response,
          _ods(_grant),
        ]);
        await expectLater(
          source.getLatestAPKDetails(_linkedUrl, _china),
          throwsA(
            response.statusCode == 429
                ? isA<RateLimitError>().having(
                    (error) => error.remainingMinutes,
                    'remainingMinutes',
                    10,
                  )
                : isA<ObtainiumError>(),
          ),
        );
        expect(source.coreRequests.last.uri.queryParameters['reqId'], '2801');
        expect(source.responses.length, 1);
      }
    },
  );

  testWidgets('linked authorization timeout stops after its single request', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/device_info'),
      (_) async => throw MissingPluginException(),
    );
    final source = _OdsGalaxyStore([
      Response('Unavailable', 503),
      _ods(_linkedMetadata),
      Completer<Response>().future,
      _ods(_grant),
    ]);
    var completed = false;
    Object? failure;
    final operation = source
        .getLatestAPKDetails(_linkedUrl, _china)
        .then<void>(
          (_) => completed = true,
          onError: (Object error) {
            completed = true;
            failure = error;
          },
        );
    await tester.pump();
    expect(source.coreRequests.last.uri.queryParameters['reqId'], '2801');
    await tester.pump(const Duration(seconds: 39));
    expect(completed, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(completed, isTrue);
    await operation;
    expect(failure, isA<TimeoutException>());
    expect(source.coreRequests.last.uri.queryParameters['reqId'], '2801');
    expect(source.responses.length, 1);
  });

  test(
    'mirror rejects partial identities, mismatches and third-party APK URLs',
    () async {
      for (final changes in [
        {'GUID': ''},
        {'GUID': 'com.other.app'},
        {'productID': '99999'},
        {'version': ''},
        {'versionCode': ''},
        {'contentsSize': '1'},
        {'downLoadURI': 'https://third-party.test/a.apk'},
        {'downLoadURI': 'https://cdnet-dn.galaxyappstore.com/'},
      ]) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods(_metadata),
          _ods({}, code: '4002'),
          _ods({}, code: '4002'),
          _ods({..._grant, 'GUID': _metadata['GUID']!, ...changes}),
        ]);
        await expectLater(
          source.getLatestAPKDetails(url, _china),
          throwsA(isA<ObtainiumError>()),
        );
        expect(source.coreRequests.length, 5);
        expect(source.requests.last.uri.queryParameters['reqId'], '2801');
        expect(source.responses, isEmpty);
      }
    },
  );

  test(
    'global or missing-full-size rejections never request the China mirror',
    () async {
      for (final settings in [<String, dynamic>{}, _china]) {
        final metadata = {..._metadata};
        if (settings == _china) metadata.remove('realContentsSize');
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods(metadata),
          _ods({}, code: '4002'),
          _ods({}, code: '4002'),
          _ods(_grant),
        ]);
        await expectLater(
          source.getLatestAPKDetails(url, settings),
          throwsA(isA<ObtainiumError>()),
        );
        expect(source.coreRequests.length, 4);
        expect(source.responses.length, 1);
        expect(
          source.requests.where(
            (r) => r.uri.queryParameters['reqId'] == '2801',
          ),
          isEmpty,
        );
      }
    },
  );

  test('CN stub failure uses stateless ODS full APK authorization', () async {
    final source = _OdsGalaxyStore([
      Response('<result><resultCode>0</resultCode></result>', 200),
      _ods(_metadata),
      _ods(_grant),
    ]);
    final result = await source.getLatestAPKDetails(url, _china);
    expect(result.version, '9.4.02.7');
    expect(result.names.name, '三星生活助手');
    expect(result.apkUrls.single.value, _grant['downLoadURI']);
    expect(result.releaseDate, isNull);
    expect(source.coreRequests.length, 3); // No APK bytes requested here.
    expect(source.coreRequests.first.uri.host, 'vas.samsungapps.com');
    final identities = <String>{};
    for (var i = 1; i < 3; i++) {
      final request = source.coreRequests.elementAt(i);
      expect(request.uri.host, 'cn-ms.galaxyappstore.com');
      expect(request.followRedirects, isFalse);
      final id = i == 1 ? '2298' : '2311';
      expect(request.uri.queryParameters['reqId'], id);
      final document = XmlDocument.parse(request.body as String);
      final root = document.rootElement;
      expect(root.getAttribute('deviceModel'), 'SM-S9480');
      expect(root.getAttribute('mcc'), '460');
      expect(root.getAttribute('mnc'), '00');
      expect(root.getAttribute('csc'), 'CHC');
      final envelope = root.getElement('request')!;
      expect(envelope.getAttribute('id'), id);
      final params = {
        for (final p in envelope.childElements)
          p.getAttribute('name')!: p.innerText,
      };
      expect(int.parse(envelope.getAttribute('numParam')!), params.length);
      identities.addAll([params['imei']!, params['extuk']!, params['stduk']!]);
      expect(
        params[i == 1 ? 'guid' : 'GUID'],
        'com.samsung.android.app.sreminder',
      );
      if (i == 2) {
        expect(envelope.getAttribute('name'), 'downloadEx2');
        expect(params['productID'], '000009060570');
        expect(params['dowloadType'], 'new');
        expect(params['deepLinkSource'], 'N');
        expect(params, isNot(contains('versionCode')));
        expect(params, isNot(contains('loadType')));
      }
    }
    expect(identities.length, 1);
    expect(identities.single, matches(RegExp(r'^[a-f0-9]{16}$')));
  });

  test('rejected stateless authorization retains the restore path', () async {
    final legacyGrant = Map<String, String>.from(_grant)
      ..remove('version')
      ..remove('versionCode');
    for (final rejection in [
      _ods({}, code: '4002'),
      _ods({}, code: '-9000'),
      Response('Unavailable', 400),
      Response('Unavailable', 503),
      Response('Unavailable', 599),
    ]) {
      final source = _OdsGalaxyStore([
        Response('Unavailable', 503),
        _ods(_metadata),
        rejection,
        _ods(legacyGrant),
      ]);
      final result = await source.getLatestAPKDetails(url, _china);
      expect(result.version, '9.4.02.7');
      expect(result.apkUrls.single.value, _grant['downLoadURI']);
      expect(
        source.coreRequests
            .skip(1)
            .map((request) => request.uri.queryParameters['reqId']),
        ['2298', '2311', '2316'],
      );
      final request = XmlDocument.parse(
        source.coreRequests.last.body as String,
      ).rootElement.getElement('request')!;
      expect(request.getAttribute('name'), 'downloadForRestore');
      final params = {
        for (final node in request.childElements)
          node.getAttribute('name')!: node.innerText,
      };
      expect(params['downloadType'], 'new');
      expect(params['triggeredFrom'], 'DETAIL_PAGE');
      expect(source.responses, isEmpty);
    }
  });

  test('invalid HTTP statuses never retry restore authorization', () async {
    for (final status in [0, 201, 302]) {
      final source = _OdsGalaxyStore([
        Response('Unavailable', 503),
        _ods(_metadata),
        _StatusResponse(status),
        _ods(_grant),
      ]);
      await expectLater(
        source.getLatestAPKDetails(url, _china),
        throwsA(
          isA<ObtainiumError>().having(
            (error) => error.unexpected,
            'unexpected',
            isTrue,
          ),
        ),
      );
      expect(source.coreRequests.length, 3);
      expect(source.responses.length, 1);
    }
  });

  test(
    'missing or nonnumeric API codes never retry restore authorization',
    () async {
      for (final code in [null, '', 'invalid']) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods(_metadata),
          _ods({}, code: code),
          _ods(_grant),
        ]);
        await expectLater(
          source.getLatestAPKDetails(url, _china),
          throwsA(
            isA<ObtainiumError>().having(
              (error) => error.unexpected,
              'unexpected',
              isTrue,
            ),
          ),
        );
        expect(source.coreRequests.length, 3);
        expect(source.responses.length, 1);
      }
    },
  );

  test(
    'restore authorization still rejects mismatches and unsafe URLs',
    () async {
      for (final changes in [
        {'productID': '99999'},
        {'version': '1.0'},
        {'versionCode': '1'},
        {'contentsSize': '1'},
        {'downLoadURI': 'https://galaxyappstore.com.evil.test/a.apk'},
      ]) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods(_metadata),
          _ods({}, code: '4002'),
          _ods({..._grant, ...changes}),
        ]);
        await expectLater(
          source.getLatestAPKDetails(url, _china),
          throwsA(isA<ObtainiumError>()),
        );
        expect(source.coreRequests.length, 4);
      }
    },
  );

  test(
    'stateless grants require version binding and never mask invalid XML',
    () async {
      for (final response in [
        _ods(Map<String, String>.from(_grant)..remove('version')),
        _ods(Map<String, String>.from(_grant)..remove('versionCode')),
        Response('<html>error</html>', 200),
      ]) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods(_metadata),
          response,
          _ods(_grant),
        ]);
        await expectLater(
          source.getLatestAPKDetails(url, _china),
          throwsA(isA<ObtainiumError>()),
        );
        expect(source.coreRequests.length, 3);
        expect(source.responses.length, 1);
      }
    },
  );

  test(
    'ODS routing retains configured CSC and legacy network overrides',
    () async {
      final cn = _OdsGalaxyStore([
        Response('Unavailable', 503),
        _ods(_metadata),
        _ods(_grant),
      ]);
      expect(
        (await cn.getLatestAPKDetails(url, {'csc': ' chc '})).version,
        '9.4.02.7',
      );
      for (final request in cn.coreRequests.skip(1)) {
        final root = XmlDocument.parse(request.body as String).rootElement;
        expect(root.getAttribute('csc'), 'CHC');
        expect(root.getAttribute('mcc'), '460');
        expect(root.getAttribute('mnc'), '00');
        expect(root.getAttribute('deviceModel'), 'SM-S948B');
      }
      final disconnected = _OdsGalaxyStore([
        const SocketException('stub unavailable'),
        _ods(_metadata),
        _ods(_grant),
      ]);
      expect(
        (await disconnected.getLatestAPKDetails(url, _china)).version,
        '9.4.02.7',
      );
      for (final settings in [
        <String, dynamic>{},
        {'csc': 'XAA', 'mcc': '310'},
        {'csc': 'CHC', 'mcc': '310'},
      ]) {
        final source = _OdsGalaxyStore([
          Response('<result><resultCode>0</resultCode></result>', 200),
          _ods(_metadata),
          _ods(_grant),
        ]);
        await source.getLatestAPKDetails(url, settings);
        expect(
          source.coreRequests
              .skip(1)
              .every((r) => r.uri.host == 'us-odc.samsungapps.com'),
          isTrue,
        );
        final envelope = XmlDocument.parse(
          source.coreRequests.elementAt(1).body as String,
        ).rootElement;
        expect(envelope.getAttribute('mcc'), settings['mcc'] ?? '425');
        expect(envelope.getAttribute('csc'), settings['csc'] ?? 'DBT');
      }
    },
  );

  test(
    'login, unavailable and mismatched metadata never request authorization',
    () async {
      for (final changes in [
        {'needToLogin': '1'},
        {'installableYN': 'N'},
        {'needToLogin': ''},
        {'GUID': 'com.other.app'},
        {'productID': ''},
        {'version': ''},
        {'versionCode': '0'},
        {'realContentsSize': 'invalid'},
      ]) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods({..._metadata, ...changes}),
        ]);
        await expectLater(
          source.getLatestAPKDetails(url, _china),
          throwsA(isA<ObtainiumError>()),
        );
        expect(source.coreRequests.length, 2);
      }
    },
  );

  test(
    'rejects mismatched authorization and non-Samsung download URLs',
    () async {
      for (final changes in [
        {'productID': '99999'},
        {'GUID': 'com.other.app'},
        {'version': '1.0'},
        {'versionCode': '1'},
        {'contentsSize': '1'},
        {'contentsSize': '0'},
        {'downLoadURI': ''},
        {'downLoadURI': 'http://cdnet-dn.galaxyappstore.com/a.apk'},
        {'downLoadURI': 'https://galaxyappstore.com.evil.test/a.apk'},
        {'downLoadURI': 'https://user@cdnet-dn.galaxyappstore.com/a.apk'},
      ]) {
        final source = _OdsGalaxyStore([
          Response('Unavailable', 503),
          _ods(_metadata),
          _ods({..._grant, ...changes}),
        ]);
        await expectLater(
          source.getLatestAPKDetails(url, _china),
          throwsA(isA<ObtainiumError>()),
        );
        expect(source.coreRequests.length, 3);
      }
    },
  );

  test('rejects ODS failures and malformed or ambiguous XML', () async {
    final valid = _ods(_metadata).body;
    for (final response in [
      _ods({}, code: '1000'),
      Response('<html>error</html>', 200),
      Response(
        valid.replaceFirst(
          '</list>',
          '<value name="GUID">com.other.app</value></list>',
        ),
        200,
        headers: {'content-type': 'text/xml; charset=utf-8'},
      ),
      Response('<SamsungProtocol>', 200),
      Response(
        '<!DOCTYPE SamsungProtocol>$valid',
        200,
        headers: {'content-type': 'text/xml; charset=utf-8'},
      ),
    ]) {
      final source = _OdsGalaxyStore([Response('Unavailable', 503), response]);
      await expectLater(
        source.getLatestAPKDetails(url, _china),
        throwsA(isA<ObtainiumError>()),
      );
      expect(source.coreRequests.length, 2);
    }
  });

  test('ODS headers do not affect stub or APK downloads', () async {
    final source = SamsungGalaxyStore();
    expect(
      await source.getRequestHeaders(
        {},
        'https://cn-ms.galaxyappstore.com/ods.as',
      ),
      containsPair('Content-Type', 'text/plain; charset=UTF-8'),
    );
    expect(
      await source.getRequestHeaders(
        {},
        'https://vas.samsungapps.com/stub/stubDownload.as',
      ),
      isNull,
    );
    expect(
      await source.getRequestHeaders(
        {},
        _grant['downLoadURI']!,
        forAPKDownload: true,
      ),
      isNull,
    );
  });
}
