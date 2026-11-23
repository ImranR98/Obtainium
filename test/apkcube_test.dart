import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/app_sources/apkcube.dart';
import 'package:obtainium/custom_errors.dart';

void main() {
  group('parseAPKCubeAvailability', () {
    final body = jsonEncode({
      'items': [
        {
          'packageName': 'com.openai.chatgpt',
          'appName': 'ChatGPT',
          'available': true,
          'latestVersionName': '1.2026.293',
          'latestVersionCode': 2026293,
          'latestUploadedAt': '2026-10-23T10:00:00Z',
          'url': 'https://apkcube.com/chatgpt/com.openai.chatgpt',
          'versions': [
            {'versionCode': 2026293, 'versionName': '1.2026.293'},
          ],
        },
        {
          'packageName': 'com.example.empty',
          'appName': 'Empty',
          'available': false,
          'latestVersionName': null,
          'latestVersionCode': null,
          'latestUploadedAt': null,
          'url': 'https://apkcube.com/empty/com.example.empty',
          'versions': [],
        },
      ],
      'notFound': ['com.example.missing'],
      'refused': [
        {
          'packageName': 'com.example.paid',
          'code': 'APP_PAID',
          'message': 'This app is paid on Google Play.',
        },
      ],
    });

    test('maps each package to a release or an error', () {
      final results = parseAPKCubeAvailability(body);
      final release = results['com.openai.chatgpt'] as APKCubeRelease;
      expect(release.versionName, '1.2026.293');
      expect(release.versionCode, 2026293);
      expect(release.uploadedAt, DateTime.utc(2026, 10, 23, 10));
      expect(release.appName, 'ChatGPT');
      expect(results['com.example.empty'], isA<NoAPKError>());
      expect(results['com.example.missing'], isA<NoReleasesError>());
      final refused = results['com.example.paid'] as NoReleasesError;
      expect(refused.data['note'], 'This app is paid on Google Play.');
    });

    test('leaves appName null when the API sends none', () {
      final results = parseAPKCubeAvailability(
        jsonEncode({
          'items': [
            {
              'packageName': 'com.example.noname',
              'appName': null,
              'available': true,
              'latestVersionName': '1.0',
              'latestVersionCode': 1,
              'latestUploadedAt': null,
              'url': 'https://apkcube.com/x/com.example.noname',
              'versions': [],
            },
          ],
          'notFound': [],
          'refused': [],
        }),
      );
      final release = results['com.example.noname'] as APKCubeRelease;
      expect(release.appName, isNull);
      expect(release.uploadedAt, isNull);
    });
  });

  group('download marker URL', () {
    test('round-trips package, version code and build id', () {
      final plain = apkCubeDownloadMarkerUrl('com.openai.chatgpt', 42);
      expect(plain, 'apkcube:com.openai.chatgpt:42');
      final parsed = parseAPKCubeMarkerUrl(plain)!;
      expect(parsed.packageName, 'com.openai.chatgpt');
      expect(parsed.versionCode, 42);
      expect(parsed.apkId, isNull);
      final withId = parseAPKCubeMarkerUrl(
        apkCubeDownloadMarkerUrl('com.openai.chatgpt', 42, apkId: 'apk_1'),
      )!;
      expect(withId.apkId, 'apk_1');
      expect(
        apkCubeDownloadMarkerUrl('com.openai.chatgpt', 42, apkId: 'apk_1'),
        'apkcube:com.openai.chatgpt:42:apk_1',
      );
    });

    test('ignores URLs and malformed markers', () {
      for (final url in [
        'apkcube:com.openai.chatgpt',
        'apkcube:not-a-package:42',
        'apkcube:com.openai.chatgpt:abc',
        'https://apkcube.com/api/v1/apps/com.openai.chatgpt/download',
        'https://apkcube.com/api/v1/apps/com.openai.chatgpt/versions?versionCode=1',
        'https://cdn.example.com/a/download?versionCode=1',
        'https://apkcube.com/chatgpt/com.x',
      ]) {
        expect(parseAPKCubeMarkerUrl(url), isNull, reason: url);
      }
    });
  });

  test('apkCubeIsValidApiKey', () {
    expect(apkCubeIsValidApiKey('akc_abc_secret'), isTrue);
    expect(apkCubeIsValidApiKey('akc_'), isFalse);
    expect(apkCubeIsValidApiKey('sk_abc'), isFalse);
    expect(apkCubeIsValidApiKey(null), isFalse);
  });

  group('parseAPKCubeBuilds', () {
    final body = jsonEncode({
      'packageName': 'com.example.app',
      'appName': 'Example',
      'versions': [
        {
          'apkId': 'a1',
          'versionName': '2.0',
          'versionCode': 20,
          'arch': 'arm64-v8a',
          'fileSize': 1000,
          'sha256': 'x',
          'format': 'apk',
          'changelog': 'Fixes',
        },
        {
          'apkId': 'a2',
          'versionName': '2.0',
          'versionCode': 20,
          'arch': 'universal',
          'fileSize': 3000,
          'sha256': 'y',
          'format': 'XAPK',
          'changelog': null,
        },
        {
          'apkId': 'a0',
          'versionName': '1.0',
          'versionCode': 10,
          'arch': 'universal',
          'fileSize': 900,
          'sha256': 'z',
          'format': 'apk',
        },
      ],
    });

    test('keeps only the latest version code builds', () {
      final builds = parseAPKCubeBuilds(body, 20);
      expect(builds.map((b) => b.apkId), ['a1', 'a2']);
      expect(builds.first.changelog, 'Fixes');
      expect(builds.last.format, 'xapk');
      final assets = apkCubeBuildAssets('com.example.app', 20, builds);
      expect(assets.map((e) => e.key), [
        'com.example.app-20-arm64-v8a.apk',
        'com.example.app-20-universal.xapk',
      ]);
      expect(parseAPKCubeMarkerUrl(assets.last.value)!.apkId, 'a2');
    });

    test('returns nothing for an empty list', () {
      expect(parseAPKCubeBuilds('{"versions":[]}', 20), isEmpty);
    });

    test('falls back to one generic asset without builds', () {
      final assets = apkCubeBuildAssets('com.example.app', 20, const []);
      expect(assets.single.key, 'com.example.app-20.apk');
      expect(parseAPKCubeMarkerUrl(assets.single.value)!.apkId, isNull);
    });
  });

  test('apkCubeCreditsRemaining reads the balance header', () {
    expect(apkCubeCreditsRemaining({'x-credits-remaining': '120'}), 120);
    expect(apkCubeCreditsRemaining({}), isNull);
  });

  group('apkCubePackageNameFromUrl', () {
    test('takes a valid package from the listing URL', () {
      expect(
        apkCubePackageNameFromUrl(
          'https://apkcube.com/chatgpt/com.openai.chatgpt',
        ),
        'com.openai.chatgpt',
      );
    });

    test('rejects ids that would fail the whole batch', () {
      expect(
        apkCubePackageNameFromUrl('https://apkcube.com/chatgpt/not-a-package'),
        isNull,
      );
      expect(
        apkCubePackageNameFromUrl('https://apkcube.com/x/1com.bad'),
        isNull,
      );
    });
  });

  group('apkCubeCooldownFor', () {
    test('blocks bad keys for a day', () {
      expect(
        apkCubeCooldownFor(401, 'API_UNAUTHORIZED'),
        apkCubeAuthBlockDuration,
      );
      expect(apkCubeCooldownFor(403, 'KEY_SCOPE'), apkCubeAuthBlockDuration);
    });

    test('blocks briefly on server errors the request gate does not cover', () {
      expect(apkCubeCooldownFor(502, null), apkCubeTransientBlockDuration);
      expect(apkCubeCooldownFor(503, 'UPSTREAM_BUSY'), isNull);
      expect(apkCubeCooldownFor(429, 'RATE_LIMITED'), isNull);
    });

    test('does not block on answers about one app or site-wide switches', () {
      expect(apkCubeCooldownFor(403, 'DOWNLOADS_DISABLED'), isNull);
      expect(apkCubeCooldownFor(402, 'INSUFFICIENT_CREDITS'), isNull);
      expect(apkCubeCooldownFor(404, 'APK_NOT_FOUND'), isNull);
      expect(apkCubeCooldownFor(451, 'APP_BLACKLISTED'), isNull);
    });
  });

  test('apkCubeApiError extracts the API error', () {
    final error = apkCubeApiError(
      '{"error":{"code":"INSUFFICIENT_CREDITS","message":"Not enough credits."}}',
    );
    expect(error.code, 'INSUFFICIENT_CREDITS');
    expect(error.message, 'Not enough credits.');
    expect(apkCubeApiError('not json').code, isNull);
  });
}
