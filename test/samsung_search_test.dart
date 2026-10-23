import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/samsunggalaxystore.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:xml/xml.dart';

class _SearchGalaxyStore extends SamsungGalaxyStore {
  final List<Object> responses;
  final requests =
      <
        ({
          Uri uri,
          XmlDocument body,
          Map<String, dynamic> settings,
          bool followRedirects,
        })
      >[];

  _SearchGalaxyStore(this.responses);

  @override
  Future<Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    requests.add((
      uri: Uri.parse(url),
      body: XmlDocument.parse(postBody as String),
      settings: Map.of(additionalSettings),
      followRedirects: followRedirects,
    ));
    final response = responses.removeAt(0);
    if (response is Response) return response;
    if (response is Future<Response>) return response;
    throw response;
  }
}

Response _response(
  List<Map<String, String>> items, {
  String id = '2040',
  String root = 'SamsungProtocol',
  String returnCode = '0',
  String errorCode = '0',
  String errorString = '',
  String itemExtra = '',
  String responseExtra = '',
}) {
  final builder = XmlBuilder();
  builder.element(
    root,
    nest: () {
      builder.element(
        'response',
        attributes: {'id': id, 'returnCode': returnCode},
        nest: () {
          builder.element(
            'errorInfo',
            nest: () {
              builder.element(
                'errorString',
                attributes: {'errorCode': errorCode},
                nest: errorString,
              );
            },
          );
          for (final item in items) {
            builder.element(
              'list',
              nest: () {
                for (final value in item.entries) {
                  builder.element(
                    'value',
                    attributes: {'name': value.key},
                    nest: value.value,
                  );
                }
                if (itemExtra.isNotEmpty) builder.xml(itemExtra);
              },
            );
          }
          if (responseExtra.isNotEmpty) builder.xml(responseExtra);
        },
      );
    },
  );
  return Response(builder.buildDocument().toXmlString(), 200);
}

Response _discovery({bool china = false}) => _response([
  {
    'countryURL': china
        ? 'http://cn-ms.galaxyappstore.com/ods.as'
        : 'http://il-odc.samsungapps.com/ods.as',
    'countryCode': china ? 'CHN' : 'ISR',
    'MCC': china ? '460' : '425',
  },
], id: '2300');

const _product = {
  'GUID': 'com.sec.android.easyMover',
  'productID': '000004936714',
  'productName': 'Samsung Smart Switch Mobile',
  'sellerName': 'Samsung Electronics Co., Ltd.',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/device_info'),
          (_) async => throw MissingPluginException(),
        );
  });

  test(
    'provides separate search and persistent app settings for each catalog',
    () {
      final source = SamsungGalaxyStore();
      expect(source.canSearch, isTrue);
      final profiles = source.searchProfiles;
      expect(profiles.map((profile) => profile.id), [
        'SamsungGalaxyStore/global',
        'SamsungGalaxyStore/china',
      ]);
      expect(profiles[0].querySettings, {'deviceId': 'SM-S948B', 'csc': 'DBT'});
      expect(profiles[1].querySettings, {'deviceId': 'SM-S9480', 'csc': 'CHC'});
      for (final profile in profiles) {
        expect(profile.appSettings, profile.querySettings);
        expect(profile.appSettings.keys, unorderedEquals(['deviceId', 'csc']));
      }
    },
  );

  test(
    'uses discovered global endpoint and the selected profile without authorizing results',
    () async {
      final source = _SearchGalaxyStore([
        _discovery(),
        _response([_product]),
      ]);
      final profile = source.searchProfiles.first;
      final results = await source.search(
        '  Samsung & tools  ',
        querySettings: profile.querySettings,
      );
      expect(results, {
        'https://apps.galaxyappstore.com/detail/com.sec.android.easyMover': [
          'Samsung Smart Switch Mobile',
          'Samsung Electronics Co., Ltd.',
        ],
      });
      expect(
        source.requests.map((request) => request.uri.queryParameters['reqId']),
        ['2300', '2040'],
      );
      expect(source.requests.first.uri.host, 'hub-odc.samsungapps.com');
      final search = source.requests.last;
      expect(search.uri.host, 'il-odc.samsungapps.com');
      expect(search.uri.scheme, 'https');
      expect(search.followRedirects, isFalse);
      expect(search.settings, profile.querySettings);
      final root = search.body.rootElement;
      expect(root.getAttribute('deviceModel'), 'SM-S948B');
      expect(root.getAttribute('csc'), 'DBT');
      expect(root.getAttribute('mcc'), '425');
      expect(root.getAttribute('mnc'), '01');
      final request = root.findElements('request').single;
      expect(request.getAttribute('name'), 'searchProductListEx2Notc');
      final params = {
        for (final param in request.findElements('param'))
          param.getAttribute('name')!: param.innerText,
      };
      expect(params['keyword'], 'Samsung & tools');
      expect(params['startNum'], '1');
      expect(params['endNum'], '20');
      expect(params['storeContentType'], 'Apps');
      expect(params['imei'], isNotEmpty);
      expect(params['stduk'], params['imei']);
      expect(params['extuk'], params['imei']);
      expect(source.responses, isEmpty);
    },
  );

  test('uses China profile for both discovery and search', () async {
    final source = _SearchGalaxyStore([
      _discovery(china: true),
      _response([_product]),
    ]);
    await source.search(
      '微信',
      querySettings: source.searchProfiles.last.querySettings,
    );
    expect(
      source.requests.every(
        (request) => request.uri.host == 'cn-ms.galaxyappstore.com',
      ),
      isTrue,
    );
    for (final request in source.requests) {
      final root = request.body.rootElement;
      expect(root.getAttribute('deviceModel'), 'SM-S9480');
      expect(root.getAttribute('csc'), 'CHC');
      expect(root.getAttribute('mcc'), '460');
      expect(root.getAttribute('mnc'), '00');
      expect(root.getAttribute('lang'), 'zh_CN');
    }
  });

  test('does not request empty queries', () async {
    final source = _SearchGalaxyStore([]);
    expect(await source.search('   '), isEmpty);
    expect(source.requests, isEmpty);
  });

  test(
    'ignores nested display records while keeping direct app identity',
    () async {
      final source = _SearchGalaxyStore([
        _discovery(),
        _response(
          [_product],
          itemExtra:
              '<extList><list><value name="GUID">com.other.app</value><value name="productName">Other app</value></list></extList>',
        ),
      ]);
      final results = await source.search('Samsung');
      expect(results.keys, [
        'https://apps.galaxyappstore.com/detail/com.sec.android.easyMover',
      ]);
      expect(results.values.single.first, 'Samsung Smart Switch Mobile');
    },
  );

  test(
    'deduplicates packages and skips invalid or explicitly unavailable results',
    () async {
      final source = _SearchGalaxyStore([
        _discovery(),
        _response([
          _product,
          {..._product, 'productName': 'Duplicate title'},
          {..._product, 'GUID': 'com.example.bad/path'},
          {..._product, 'GUID': 'com.example. bad'},
          {..._product, 'GUID': '12345'},
          {..._product, 'GUID': ''},
          {..._product, 'GUID': 'com.example.play', 'playStoreProductYN': 'Y'},
          {..._product, 'GUID': 'com.example.disabled', 'installable': 'N'},
          {
            ..._product,
            'GUID': 'com.example.unavailable',
            'installableYN': 'N',
          },
          {
            'GUID': 'com.example.available',
            'productName': '',
            'sellerName': '',
          },
        ]),
      ]);
      final results = await source.search('Samsung');
      expect(results, {
        'https://apps.galaxyappstore.com/detail/com.sec.android.easyMover': [
          'Samsung Smart Switch Mobile',
          'Samsung Electronics Co., Ltd.',
        ],
        'https://apps.galaxyappstore.com/detail/com.example.available': [
          'com.example.available',
          'Samsung Galaxy Store',
        ],
      });
    },
  );

  for (final response in <String, Response>{
    'wrong root': _response([_product], root: 'Unrelated'),
    'wrong response id': _response([_product], id: '2298'),
    'missing status': _response([_product], errorCode: ''),
    'rejected status': _response([_product], errorCode: '-1'),
    'nonzero return code': _response([_product], returnCode: '1'),
    'unexpected error message': _response([_product], errorString: 'Rejected'),
    'duplicate critical field': _response([
      _product,
    ], itemExtra: '<value name="GUID">com.other.app</value>'),
    'critical field as non-value': _response([
      _product,
    ], itemExtra: '<GUID>com.other.app</GUID>'),
    'duplicate error info': _response([
      _product,
    ], responseExtra: '<errorInfo><errorString errorCode="0"/></errorInfo>'),
    'nested field value': _response(
      [_product],
      itemExtra:
          '<value name="extra"><value name="GUID">com.other.app</value></value>',
    ),
  }.entries) {
    test(
      'rejects ${response.key} instead of returning ambiguous results',
      () async {
        final source = _SearchGalaxyStore([_discovery(), response.value]);
        await expectLater(
          source.search('Samsung'),
          throwsA(isA<ObtainiumError>()),
        );
        expect(source.requests.length, 2);
      },
    );
  }

  test('accepts an empty successful search result', () async {
    final source = _SearchGalaxyStore([_discovery(), _response([])]);
    expect(await source.search('No matching application'), isEmpty);
  });

  test(
    'propagates search rate limiting without retrying another catalog',
    () async {
      final source = _SearchGalaxyStore([
        _discovery(),
        Response('', 429, headers: {'retry-after': '120'}),
      ]);
      await expectLater(
        source.search('Samsung'),
        throwsA(isA<RateLimitError>()),
      );
      expect(source.requests.length, 2);
    },
  );

  test('propagates discovery rate limiting before searching', () async {
    final source = _SearchGalaxyStore([
      Response('', 429, headers: {'retry-after': '120'}),
    ]);
    await expectLater(source.search('Samsung'), throwsA(isA<RateLimitError>()));
    expect(source.requests.length, 1);
  });

  testWidgets(
    'search times out after forty seconds without additional requests',
    (tester) async {
      final source = _SearchGalaxyStore([
        _discovery(),
        Completer<Response>().future,
      ]);
      var completed = false;
      Object? failure;
      final operation = source
          .search('Samsung')
          .then<void>(
            (_) => completed = true,
            onError: (Object error) {
              completed = true;
              failure = error;
            },
          );
      await tester.pump();
      expect(source.requests.last.uri.queryParameters['reqId'], '2040');
      await tester.pump(const Duration(seconds: 39));
      expect(completed, isFalse);
      await tester.pump(const Duration(seconds: 1));
      await operation;
      expect(completed, isTrue);
      expect(failure, isA<TimeoutException>());
      expect(source.requests.length, 2);
    },
  );
}
