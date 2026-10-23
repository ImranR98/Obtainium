import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/huaweiappgallery.dart';
import 'package:obtainium/app_sources/vivoappstore.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Vivo extends VivoAppStore {
  _Vivo(this.response);

  final Map<String, dynamic> response;
  int requests = 0;

  @override
  String get name => 'Vivo App Store';

  @override
  Future<Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    requests++;
    return Response(jsonEncode(response), 200);
  }
}

class _Huawei extends HuaweiAppGallery {
  _Huawei(this.detail, {this.statusCode = 200});

  final Map<String, dynamic> detail;
  final int statusCode;
  int requests = 0;

  @override
  String get name => 'Huawei AppGallery';

  @override
  Future<Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    requests++;
    return Response(
      jsonEncode({
        'rtnCode': 0,
        'detailInfo': [detail],
      }),
      statusCode,
      headers: {'retry-after': '125'},
    );
  }
}

const _vivoUrl = 'https://detail-browser.vivo.com.cn/v115/index.html?appId=1';
const _huaweiUrl = 'https://appgallery.huawei.com/app/C1';
const _vivoDetail = {
  'id': 1,
  'version_name': '1.2.3',
  'version_code': 123,
  'package_name': 'com.example.app',
  'title_zh': 'Example App',
  'developer': 'Example Developer',
};
const _huaweiDetail = {
  'versionName': '1.2.3',
  'package': 'com.example.app',
  'name': 'Example App',
  'developer': 'Example Developer',
  'url': 'https://example.com/app.apk',
};

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storage;

  setUpAll(() {
    Localization.load(
      const Locale('en'),
      translations: Translations(
        jsonDecode(File('assets/translations/en.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
    );
    storage = Directory.systemTemp.createTempSync('obtainium-store-test-');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => storage.path,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/device_info'),
      (_) async => {
        'version': {
          'codename': 'REL',
          'incremental': '1',
          'release': '16',
          'sdkInt': 36,
        },
        for (final key in [
          'board',
          'bootloader',
          'brand',
          'device',
          'display',
          'fingerprint',
          'hardware',
          'host',
          'id',
          'manufacturer',
          'model',
          'product',
          'tags',
          'type',
        ])
          key: 'test',
        for (final key in [
          'time',
          'freeDiskSize',
          'totalDiskSize',
          'physicalRamSize',
          'availableRamSize',
        ])
          key: 0,
        'isPhysicalDevice': false,
        'isLowRamDevice': false,
        'systemFeatures': <String>[],
      },
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'huaweiAppGallery-session':
          'store-dre.hispace.dbankcloud.com|synthetic-test-sign|test-device|${DateTime.now().millisecondsSinceEpoch}',
    });
  });

  tearDownAll(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/device_info'),
      null,
    );
    storage.deleteSync(recursive: true);
  });

  group('store package metadata', () {
    test('Vivo adds an app without repeating its detail request', () async {
      final source = _Vivo(_vivoDetail);
      final app = await SourceProvider().getApp(source, _vivoUrl, {});

      expect(app.id, 'com.example.app');
      expect(source.requests, 1);
    });

    test('Huawei adds an app without repeating its detail request', () async {
      final source = _Huawei(_huaweiDetail);
      final app = await SourceProvider().getApp(source, _huaweiUrl, {});

      expect(app.id, 'com.example.app');
      expect(source.requests, 1);
    });

    test(
      'explicit package IDs retain precedence over store metadata',
      () async {
        for (final entry in <(AppSource, String)>[
          (_Vivo(_vivoDetail), _vivoUrl),
          (_Huawei(_huaweiDetail), _huaweiUrl),
        ]) {
          final app = await SourceProvider().getApp(entry.$1, entry.$2, {
            'appId': 'com.example.override',
          });
          expect(app.id, 'com.example.override');
        }
      },
    );

    test(
      'existing package IDs retain precedence over store metadata',
      () async {
        for (final entry in <(AppSource, String)>[
          (_Vivo(_vivoDetail), _vivoUrl),
          (_Huawei(_huaweiDetail), _huaweiUrl),
        ]) {
          final app = await SourceProvider().getApp(entry.$1, entry.$2, {
            'appId': 'com.example.existing',
          });
          final updated = await SourceProvider().getApp(entry.$1, entry.$2, {
            'appId': 'com.example.override',
          }, currentApp: app);
          expect(updated.id, 'com.example.existing');
        }
      },
    );

    test(
      'invalid store package IDs are not accepted as inferred IDs',
      () async {
        for (final package in ['', ' ', 'not a package', 'null', 123]) {
          final vivo = _Vivo({..._vivoDetail, 'package_name': package});
          final huawei = _Huawei({..._huaweiDetail, 'package': package});
          expect((await vivo.getLatestAPKDetails(_vivoUrl, {})).appId, isNull);
          expect(
            (await huawei.getLatestAPKDetails(_huaweiUrl, {})).appId,
            isNull,
          );
          expect(await vivo.tryInferringAppId(_vivoUrl), isNull);
          expect(await huawei.tryInferringAppId(_huaweiUrl), isNull);
        }
      },
    );
  });

  group('Vivo response validation', () {
    test('rejects missing or blank versions', () async {
      for (final version in [null, '', '  ']) {
        final source = _Vivo({..._vivoDetail, 'version_name': version});
        await expectLater(
          source.getLatestAPKDetails(_vivoUrl, {}),
          throwsA(isA<NoVersionError>()),
        );
      }
    });

    test('rejects missing or blank store IDs', () async {
      for (final id in [null, '', '  ']) {
        final source = _Vivo({..._vivoDetail, 'id': id});
        await expectLater(
          source.getLatestAPKDetails(_vivoUrl, {}),
          throwsA(isA<NoReleasesError>()),
        );
      }
    });

    test(
      'falls back from blank display names without losing the release',
      () async {
        final source = _Vivo({
          ..._vivoDetail,
          'title_zh': ' ',
          'developer': '',
        });
        final details = await source.getLatestAPKDetails(_vivoUrl, {});
        expect(details.names.name, 'com.example.app');
        expect(details.names.author, 'Vivo App Store');
      },
    );

    test('skips malformed search rows and preserves valid results', () async {
      final source = _Vivo({
        'code': 0,
        'data': {
          'appSearchResponse': {
            'result': true,
            'value': [
              null,
              7,
              {},
              {'id': '', 'title_zh': 'Empty ID'},
              {'id': 2, 'title_zh': ' '},
              {'id': 3, 'title_zh': 'Example', 'developer': ' '},
              {'id': 4, 'title_zh': 'Other', 'developer': 'Developer'},
            ],
          },
        },
      });
      expect(await source.search('example'), {
        '${VivoAppStore.appDetailUrl}3': ['Example', 'Vivo App Store'],
        '${VivoAppStore.appDetailUrl}4': ['Other', 'Developer'],
      });
    });
  });

  group('Huawei rate limiting', () {
    test(
      'preserves Retry-After instead of replacing it with an API error',
      () async {
        final source = _Huawei({}, statusCode: 429);
        await expectLater(
          source.getLatestAPKDetails(_huaweiUrl, {}),
          throwsA(
            isA<RateLimitError>().having(
              (e) => e.remainingMinutes,
              'remainingMinutes',
              3,
            ),
          ),
        );
        expect(source.requests, 1);
      },
    );

    test('does not swallow rate limits during package inference', () async {
      final source = _Huawei({}, statusCode: 429);
      await expectLater(
        source.tryInferringAppId(_huaweiUrl),
        throwsA(
          isA<RateLimitError>().having(
            (e) => e.remainingMinutes,
            'remainingMinutes',
            3,
          ),
        ),
      );
      expect(source.requests, 1);
    });
  });
}
