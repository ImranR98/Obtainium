import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/forgejo_pagination.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _release(String tag, String name, DateTime publishedAt) =>
    {
      'tag_name': tag,
      'name': name,
      'body': '',
      'prerelease': false,
      'draft': false,
      'published_at': publishedAt.toIso8601String(),
      'assets': [
        <String, dynamic>{
          'name': 'app.apk',
          'url': 'https://example.com/$tag/app.apk',
          'browser_download_url': 'https://example.com/$tag/app.apk',
        },
      ],
      'tarball_url': null,
      'zipball_url': null,
      'html_url': 'https://example.com/$tag',
    };

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const deviceChannel = MethodChannel('dev.fluttercommunity.plus/device_info');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => Directory.systemTemp.path,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      deviceChannel,
      (_) async => {
        'version': {
          'codename': 'REL',
          'incremental': '',
          'release': '17',
          'sdkInt': 37,
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
          key: '',
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
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pathChannel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      deviceChannel,
      null,
    );
  });

  group('fetchAllForgejoPages', () {
    test('combines pages until a short page and uses limit/page', () async {
      final seen = <Uri>[];
      final result = await fetchAllForgejoPages(
        Uri.parse(
          'https://codeberg.org/api/v1/repos/o/r/releases?per_page=100',
        ),
        (uri) async {
          seen.add(uri);
          final page = int.parse(uri.queryParameters['page']!);
          final count = page == 3 ? 36 : 50;
          return Response(
            jsonEncode(List.generate(count, (i) => {'id': page * 100 + i})),
            200,
          );
        },
      );

      expect(result.length, 136);
      expect(seen.length, 3);
      expect(seen.first.queryParameters['limit'], '50');
      expect(seen.first.queryParameters.containsKey('per_page'), isFalse);
      expect(seen.map((u) => u.queryParameters['page']).toList(), [
        '1',
        '2',
        '3',
      ]);
    });

    test('stops at maxPages', () async {
      var calls = 0;
      final result = await fetchAllForgejoPages(
        Uri.parse('https://codeberg.org/api/v1/repos/o/r/releases'),
        (uri) async {
          calls++;
          return Response(jsonEncode(List.generate(50, (i) => i)), 200);
        },
        maxPages: 2,
      );

      expect(calls, 2);
      expect(result.length, 100);
    });

    test('throws on a non-200 page', () async {
      await expectLater(
        fetchAllForgejoPages(
          Uri.parse('https://codeberg.org/api/v1/repos/o/r/releases'),
          (uri) async => Response('nope', 500),
        ),
        throwsA(isA<ObtainiumError>()),
      );
    });

    test('throws NoReleasesError for a non-list response', () async {
      await expectLater(
        fetchAllForgejoPages(
          Uri.parse('https://codeberg.org/api/v1/repos/o/r/releases'),
          (uri) async => Response('{}', 200),
        ),
        throwsA(isA<NoReleasesError>()),
      );
    });
  });

  test('selects a stable release after filtering out nightlies', () async {
    final releases = [
      for (var i = 0; i < 30; i++)
        _release(
          'nightly-${20261103 - i}',
          'Nightly ${20261103 - i}',
          DateTime(2026, 11, 3).subtract(Duration(days: i)),
        ),
      _release('v0.7.2', 'v0.7.2', DateTime(2026, 9, 4)),
    ];
    final details = await GitHub().fetchReleaseDetailsWithTagFallback(
      'https://codeberg.org/unwanted9855/AppVerifierBG',
      {
        'versionDetection': true,
        'fallbackToOlderReleases': true,
        'sortMethodChoice': 'date',
        'filterReleaseTitlesByRegEx': '[Nn]ightly',
        'invertReleaseTitlesFilter': true,
        'updateHealthArchived': 'off',
      },
      (bool useTagUrl) async =>
          'https://codeberg.org/api/v1/repos/unwanted9855/AppVerifierBG/'
          '${useTagUrl ? 'tags' : 'releases'}?limit=50',
      null,
      releaseListLoader: (url) async => releases,
    );

    expect(details.version, 'v0.7.2');
  });
}
