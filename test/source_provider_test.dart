import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:device_info_plus_platform_interface/device_info_plus_platform_interface.dart';
import 'package:obtainium/app_sources/apkmirror.dart';
import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/app_sources/fdroidrepo.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/app_sources/izzyondroid.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:http/http.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Stub source that returns a controllable [APKDetails] from
/// [getLatestAPKDetails] without doing any network or HTML work.
///
/// Inherits APKMirror so [APKMirror]'s `enforceTrackOnly = true` flag is
/// kept (the size-keying branch we're testing only ever fires for
/// track-only APKMirror apps in production), and so [SourceProvider.getApp]
/// recognizes it via `source is APKMirror` for its (now removed) special
/// case checks. If those special cases ever come back, this stub will
/// surface the regression.
class _StubAPKMirror extends APKMirror {
  _StubAPKMirror({required this.version, this.apkSizeFromSource});
  final String version;
  final int? apkSizeFromSource;

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    return APKDetails(
      version,
      const <MapEntry<String, String>>[],
      AppNames('Example', 'example'),
      apkSizeBytes: apkSizeFromSource,
    );
  }

  // tryInferringAppId hits the network in the real APKMirror; short-circuit
  // it so tests never reach out. We always pass an explicit appId via the
  // currentApp/additionalSettings path anyway, so this never fires — it's
  // here as a safety net.
  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async => null;
}

class _StubSource extends AppSource {
  _StubSource({
    this.apkUrls = const <MapEntry<String, String>>[
      MapEntry('example.apk', 'https://example.com/example.apk'),
    ],
  }) {
    hosts = <String>['example.com'];
    name = 'Example';
  }

  final List<MapEntry<String, String>> apkUrls;

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    return url;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    return APKDetails(
      '2.0',
      apkUrls,
      AppNames('Example Author', 'Readable Name'),
    );
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    return 'org.example.app';
  }
}

class _StubFDroid extends FDroid {
  _StubFDroid(
    this.pageHtml, {
    bool hostChanged = false,
    bool hostIdenticalDespiteAnyChange = false,
  }) {
    this.hostChanged = hostChanged;
    this.hostIdenticalDespiteAnyChange = hostIdenticalDespiteAnyChange;
  }

  final String pageHtml;

  @override
  Future<Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    return Response(pageHtml, 200);
  }
}

class _StubFDroidVerification extends FDroid {
  _StubFDroidVerification(this.verificationResponses);

  final List<Response> verificationResponses;
  int verificationRequestCount = 0;

  @override
  Future<Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    if (url ==
        'https://f-droid.org/api/v1/packages/app.pwhs.universalinstaller') {
      return Response(
        jsonEncode({
          'packageName': 'app.pwhs.universalinstaller',
          'suggestedVersionCode': 31,
          'packages': [
            {'versionName': '1.9.11', 'versionCode': 31},
          ],
        }),
        200,
      );
    }
    if (url ==
        'https://verification.f-droid.org/unsigned/app.pwhs.universalinstaller_31.apk.json') {
      final int responseIndex =
          verificationRequestCount < verificationResponses.length
          ? verificationRequestCount
          : verificationResponses.length - 1;
      verificationRequestCount++;
      return verificationResponses[responseIndex];
    }
    return Response('', 404);
  }
}

class _StubIzzyOnDroid extends IzzyOnDroid {
  @override
  Future<Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    if (url == 'https://apt.izzysoft.de/fdroid/repo/index.xml') {
      return _fdroidRepoResponse('''
<fdroid><repo name="IzzyOnDroid"/><application id="org.example.app">
  <name>Example App</name>
  <marketvercode>3</marketvercode>
  <package>
    <version>3.0</version>
    <versioncode>3</versioncode>
    <apkname>org.example.app_3.apk</apkname>
  </package>
</application></fdroid>
''');
    }
    if (url == 'https://apt.izzysoft.de/fdroid/rbtlogs/izzy.json') {
      return Response('{}', 200);
    }
    if (url == 'https://apt.izzysoft.de/fdroid/index/apk/org.example.app') {
      return Response('''
<html><head>
<meta property="og:image" content="/fdroid/repo/org.example.app/en-US/icon.png" />
</head><body></body></html>
''', 200);
    }
    return Response('', 404);
  }
}

class _StubFDroidRepo extends FDroidRepo {
  _StubFDroidRepo(this.indexXml);

  final String indexXml;

  @override
  Future<Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    return Response(indexXml, 200, request: Request('GET', Uri.parse(url)));
  }
}

class _StubGitHub extends GitHub {
  @override
  Future<Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    if (url.endsWith('/releases?per_page=100')) {
      return Response(
        jsonEncode([
          {
            'tag_name': '1.0',
            'name': '1.0',
            'draft': false,
            'prerelease': false,
            'published_at': '2026-01-01T00:00:00Z',
            'body': '',
            'assets': [
              {
                'name': 'example.apk',
                'browser_download_url':
                    'https://github.com/example/app/releases/download/1.0/example.apk',
                'url':
                    'https://api.github.com/repos/example/app/releases/assets/1',
                'size': 123,
                'digest': 'sha256:abc123',
              },
            ],
          },
        ]),
        200,
      );
    }
    if (url.endsWith('/attestations/sha256:abc123')) {
      return Response(
        jsonEncode({
          'attestations': [{}],
        }),
        200,
      );
    }
    if (url.endsWith('/attestations/sha256:empty123')) {
      return Response(jsonEncode({'attestations': []}), 200);
    }
    if (url.endsWith('/attestations/sha256:error123')) {
      return Response('', 500);
    }
    return Response('', 404);
  }
}

App _buildCurrentApp({required String latestVersion, int? apkSizeBytes}) {
  return App(
    id: 'com.example.app',
    url: 'https://www.apkmirror.com/apk/example/example',
    author: 'Example',
    name: 'Example',
    installedVersion: null,
    latestVersion: latestVersion,
    apkUrls: const <MapEntry<String, String>>[],
    preferredApkIndex: 0,
    additionalSettings: {'trackOnly': true, 'appId': 'com.example.app'},
    lastUpdateCheck: DateTime.now(),
    pinned: false,
    apkSizeBytes: apkSizeBytes,
  );
}

App _buildCurrentNamedApp({required String name}) {
  return App(
    id: 'org.example.app',
    url: 'https://example.com/app',
    author: 'Example Author',
    name: name,
    installedVersion: null,
    latestVersion: '1.0',
    apkUrls: const <MapEntry<String, String>>[
      MapEntry('example.apk', 'https://example.com/example.apk'),
    ],
    preferredApkIndex: 0,
    additionalSettings: <String, dynamic>{},
    lastUpdateCheck: DateTime.now(),
    pinned: false,
  );
}

App _buildCurrentTempIdNamedApp({required String name}) {
  return App(
    id: '123456789',
    url: 'https://example.com/app',
    author: 'Example Author',
    name: name,
    installedVersion: null,
    latestVersion: '1.0',
    apkUrls: const <MapEntry<String, String>>[
      MapEntry('example.apk', 'https://example.com/example.apk'),
    ],
    preferredApkIndex: 0,
    additionalSettings: <String, dynamic>{},
    lastUpdateCheck: DateTime.now(),
    pinned: false,
  );
}

Response _fdroidRepoResponse(String xml) {
  return Response(
    xml,
    200,
    request: Request(
      'GET',
      Uri.parse('https://apt.izzysoft.de/fdroid/repo/index.xml'),
    ),
  );
}

Response _fdroidVerificationResponse({required bool verified}) {
  return Response(
    jsonEncode({
      '1783233447.4899063': {
        'local': {
          'packageName': 'app.pwhs.universalinstaller',
          'versionCode': 31,
          'versionName': '1.9.11',
        },
        'remote': {
          'packageName': 'app.pwhs.universalinstaller',
          'versionCode': 31,
          'versionName': '1.9.11',
        },
        'url': 'https://f-droid.org/repo/app.pwhs.universalinstaller_31.apk',
        'verified': verified,
      },
    }),
    200,
  );
}

App _previousUniversalInstaller({required String reproducibleStatus}) {
  return App(
    id: 'app.pwhs.universalinstaller',
    url: 'https://f-droid.org/packages/app.pwhs.universalinstaller',
    author: 'Nguyen Quang Minh (NQM)',
    name: 'Universal Installer',
    latestVersion: '1.9.11',
    apkUrls: const <MapEntry<String, String>>[
      MapEntry(
        'app.pwhs.universalinstaller_31.apk',
        'https://f-droid.org/repo/app.pwhs.universalinstaller_31.apk',
      ),
    ],
    preferredApkIndex: 0,
    additionalSettings: const <String, dynamic>{
      'trySelectingSuggestedVersionCode': true,
    },
    rawLatestVersionFromSource: '1.9.11',
    latestReproducibleStatus: reproducibleStatus,
    latestReproducibleVersionCode: 31,
  );
}

class _FakeAndroidDeviceInfoPlatform extends DeviceInfoPlatform {
  @override
  Future<BaseDeviceInfo> deviceInfo() async {
    return BaseDeviceInfo({
      'version': {
        'sdkInt': 35,
        'release': '15',
        'codename': 'REL',
        'incremental': '1',
        'previewSdkInt': 0,
        'securityPatch': '2026-05-01',
        'baseOS': '',
      },
      'board': '',
      'bootloader': '',
      'brand': '',
      'device': '',
      'display': '',
      'fingerprint': '',
      'hardware': '',
      'host': '',
      'id': '',
      'manufacturer': '',
      'model': '',
      'product': '',
      'supported32BitAbis': const ['armeabi-v7a'],
      'supported64BitAbis': const ['arm64-v8a'],
      'supportedAbis': const ['arm64-v8a', 'armeabi-v7a'],
      'tags': '',
      'type': 'user',
      'isPhysicalDevice': true,
      'freeDiskSize': 1,
      'totalDiskSize': 1,
      'isLowRamDevice': false,
      'physicalRamSize': 1,
      'availableRamSize': 1,
      'systemFeatures': const <String>[],
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The F-Droid reproducible-build error path logs via LogsProvider, which
  // opens a sqflite DB. Initialize the ffi factory so that best-effort write
  // succeeds in the test VM instead of throwing (matches version_order_test).
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DeviceInfoPlatform.instance = _FakeAndroidDeviceInfoPlatform();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'source resolution reuses templates but returns fresh mutable sources',
    () {
      final SourceProvider provider = SourceProvider();
      const String url = 'https://github.com/example/app';

      final AppSource firstSource = provider.getSource(url);
      final AppSource secondSource = provider.getSource(url);
      final AppSource firstTemplate = provider.getSourceTemplate(url);
      final AppSource secondTemplate = provider.getSourceTemplate(url);

      expect(firstSource, isA<GitHub>());
      expect(secondSource, isA<GitHub>());
      expect(identical(firstSource, secondSource), isFalse);
      expect(identical(firstTemplate, secondTemplate), isTrue);
    },
  );

  test('override resolution mutates only the fresh matched source', () {
    final SourceProvider provider = SourceProvider();
    final AppSource githubTemplate = provider.getSourceTemplate(
      'https://github.com/example/app',
    );
    final AppSource overriddenSource = provider.getSource(
      'https://git.example.com/example/app',
      overrideSource: githubTemplate.sourceIdentifier,
    );

    expect(overriddenSource, isA<GitHub>());
    expect(overriddenSource.hosts, <String>['git.example.com']);
    expect(overriddenSource.hostChanged, isTrue);
    expect(githubTemplate.hosts, contains('github.com'));
  });

  // ── Size cache key invalidation ─────────────────────────────────────
  // The contract: the size persisted onto an App is keyed implicitly by
  // (appId, latestVersion). When a refresh returns the same version,
  // any size already on the App should survive (nothing better is
  // available for APKMirror until the AppPage's lazy resolver runs).
  // When the version changes, the stale size MUST be cleared so the
  // next AppPage open re-resolves.

  test('apkSizeBytes is preserved when source version is unchanged', () async {
    final source = _StubAPKMirror(version: '2.0', apkSizeFromSource: null);
    final currentApp = _buildCurrentApp(
      latestVersion: '2.0',
      apkSizeBytes: 12345678,
    );
    final newApp = await SourceProvider().getApp(
      source,
      'https://www.apkmirror.com/apk/example/example',
      {'trackOnly': true, 'appId': 'com.example.app'},
      currentApp: currentApp,
    );
    expect(newApp.apkSizeBytes, 12345678);
    expect(newApp.latestVersion, '2.0');
  });

  test(
    'apkSizeBytes is cleared when source reports a different version',
    () async {
      final source = _StubAPKMirror(version: '3.0', apkSizeFromSource: null);
      final currentApp = _buildCurrentApp(
        latestVersion: '2.0',
        apkSizeBytes: 12345678,
      );
      final newApp = await SourceProvider().getApp(
        source,
        'https://www.apkmirror.com/apk/example/example',
        {'trackOnly': true, 'appId': 'com.example.app'},
        currentApp: currentApp,
      );
      expect(newApp.apkSizeBytes, isNull);
      expect(newApp.latestVersion, '3.0');
    },
  );

  test('apkSizeBytes from source wins over the cached value', () async {
    final source = _StubAPKMirror(version: '3.0', apkSizeFromSource: 99999999);
    final currentApp = _buildCurrentApp(
      latestVersion: '2.0',
      apkSizeBytes: 12345678,
    );
    final newApp = await SourceProvider().getApp(
      source,
      'https://www.apkmirror.com/apk/example/example',
      {'trackOnly': true, 'appId': 'com.example.app'},
      currentApp: currentApp,
    );
    expect(newApp.apkSizeBytes, 99999999);
  });

  test(
    'preferred APK index is clamped after filtering shrinks assets',
    () async {
      const List<MapEntry<String, String>> originalApkUrls = [
        MapEntry('first.apk', 'https://example.com/first.apk'),
        MapEntry('second.apk', 'https://example.com/second.apk'),
        MapEntry('third.apk', 'https://example.com/third.apk'),
        MapEntry('fourth.apk', 'https://example.com/fourth.apk'),
        MapEntry('last.apk', 'https://example.com/last.apk'),
      ];
      const App currentApp = App(
        id: 'org.example.app',
        url: 'https://example.com/app',
        author: 'Example Author',
        name: 'Example App',
        latestVersion: '1.0',
        apkUrls: originalApkUrls,
        preferredApkIndex: 4,
        additionalSettings: <String, dynamic>{},
      );

      final App refreshedApp = await SourceProvider().getApp(
        _StubSource(apkUrls: originalApkUrls),
        currentApp.url,
        <String, dynamic>{'apkFilterRegEx': r'^first\.apk$'},
        currentApp: currentApp,
      );

      expect(refreshedApp.apkUrls, hasLength(1));
      expect(refreshedApp.apkUrls.single.key, 'first.apk');
      expect(refreshedApp.preferredApkIndex, 0);
    },
  );

  test(
    'apkSizeBytes is null on first add when source returns no size',
    () async {
      final source = _StubAPKMirror(version: '1.0', apkSizeFromSource: null);
      final newApp = await SourceProvider().getApp(
        source,
        'https://www.apkmirror.com/apk/example/example',
        {'trackOnly': true, 'appId': 'com.example.app'},
        // No currentApp — simulating first-time add.
      );
      expect(newApp.apkSizeBytes, isNull);
    },
  );

  test(
    'F-Droid repo parser keeps latest release when enforcement is on',
    () async {
      final details = await FDroidRepo.apkDetailsFromIndexXmlResponse(
        _fdroidRepoResponse('''
<fdroid><repo name="IzzyOnDroid"/><application id="org.example.app">
  <name>Example App</name>
  <marketvercode>3</marketvercode>
  <package>
    <version>3.0</version>
    <versioncode>3</versioncode>
    <apkname>org.example.app_3.apk</apkname>
    <hash type="sha256">hash3</hash>
  </package>
  <package>
    <version>2.0</version>
    <versioncode>2</versioncode>
    <apkname>org.example.app_2.apk</apkname>
    <hash type="sha256">hash2</hash>
  </package>
</application></fdroid>
'''),
        'org.example.app',
        <String, dynamic>{'enforceReproducibleBuilds': true},
        'IzzyOnDroid',
        isReproducibleRelease:
            (String appId, int versionCode, String? apkSha256) async {
              return appId == 'org.example.app' &&
                  versionCode == 2 &&
                  apkSha256 == 'hash2';
            },
      );

      expect(details.version, '3.0');
      expect(details.names.name, 'Example App');
      expect(details.isReproducible, isFalse);
      expect(
        details.reproducibleStatus,
        reproducibleBuildStatusNotReproducible,
      );
      expect(
        details.apkUrls.single.value,
        'https://apt.izzysoft.de/fdroid/repo/org.example.app_3.apk',
      );
    },
  );

  test(
    'F-Droid repo parser keeps latest release when enforcement is off',
    () async {
      final details = await FDroidRepo.apkDetailsFromIndexXmlResponse(
        _fdroidRepoResponse('''
<fdroid><repo name="IzzyOnDroid"/><application id="org.example.app">
  <name>Example App</name>
  <marketvercode>3</marketvercode>
  <package>
    <version>3.0</version>
    <versioncode>3</versioncode>
    <apkname>org.example.app_3.apk</apkname>
    <hash type="sha256">hash3</hash>
  </package>
  <package>
    <version>2.0</version>
    <versioncode>2</versioncode>
    <apkname>org.example.app_2.apk</apkname>
    <hash type="sha256">hash2</hash>
  </package>
</application></fdroid>
'''),
        'org.example.app',
        <String, dynamic>{},
        'IzzyOnDroid',
        isReproducibleRelease:
            (String appId, int versionCode, String? apkSha256) async {
              return appId == 'org.example.app' &&
                  versionCode == 2 &&
                  apkSha256 == 'hash2';
            },
      );

      expect(details.version, '3.0');
      expect(details.isReproducible, isFalse);
      expect(
        details.reproducibleStatus,
        reproducibleBuildStatusNotReproducible,
      );
    },
  );

  test(
    'F-Droid repo parser marks missing reproducible metadata as no data',
    () async {
      final details = await FDroidRepo.apkDetailsFromIndexXmlResponse(
        _fdroidRepoResponse('''
<fdroid><repo name="IzzyOnDroid"/><application id="org.example.app">
  <name>Example App</name>
  <marketvercode>3</marketvercode>
  <package>
    <version>3.0</version>
    <versioncode>3</versioncode>
    <apkname>org.example.app_3.apk</apkname>
    <hash type="sha256">hash3</hash>
  </package>
</application></fdroid>
'''),
        'org.example.app',
        <String, dynamic>{},
        'IzzyOnDroid',
      );

      expect(details.version, '3.0');
      expect(details.isReproducible, isNull);
      expect(details.reproducibleStatus, reproducibleBuildStatusNoData);
    },
  );

  test(
    'F-Droid repo parser does not treat an empty binaries element as verified',
    () async {
      final details = await FDroidRepo.apkDetailsFromIndexXmlResponse(
        _fdroidRepoResponse('''
<fdroid><repo name="Example Repo"/><application id="org.example.app">
  <name>Example App</name>
  <marketvercode>3</marketvercode>
  <package>
    <version>3.0</version>
    <versioncode>3</versioncode>
    <apkname>org.example.app_3.apk</apkname>
    <binaries>   </binaries>
  </package>
</application></fdroid>
'''),
        'org.example.app',
        <String, dynamic>{},
        'Example Repo',
      );

      expect(details.reproducibleStatus, reproducibleBuildStatusNoData);
    },
  );

  test(
    'F-Droid repo source uses shared parser for valid releases and metadata',
    () async {
      final details =
          await _StubFDroidRepo('''
<fdroid><repo name="Example Repo"/><application id="org.example.app">
  <name>Example App</name>
  <icon>example.png</icon>
  <marketvercode>3</marketvercode>
  <package>
    <version>4.0</version>
    <versioncode>4</versioncode>
  </package>
  <package>
    <version>3.0</version>
    <versioncode>3</versioncode>
    <apkname>org.example.app_3.apk</apkname>
    <size>12345</size>
    <binaries>org.example.app_3.apk</binaries>
  </package>
</application></fdroid>
''').getLatestAPKDetails('https://repo.example/fdroid/repo', <String, dynamic>{
            'appIdOrName': 'org.example.app',
          });

      expect(details.version, '3.0');
      expect(details.names.name, 'Example App');
      expect(details.apkSizeBytes, 12345);
      expect(
        details.iconUrl,
        'https://repo.example/fdroid/repo/icons/example.png',
      );
      expect(details.reproducibleStatus, reproducibleBuildStatusVerified);
      expect(
        details.apkUrls.single.value,
        'https://repo.example/fdroid/repo/org.example.app_3.apk',
      );
    },
  );

  test('IzzyOnDroid uses app page metadata as icon fallback', () async {
    final details = await _StubIzzyOnDroid().getLatestAPKDetails(
      'https://apt.izzysoft.de/fdroid/index/apk/org.example.app',
      <String, dynamic>{'appIdOrName': 'org.example.app'},
    );

    expect(details.names.name, 'Example App');
    expect(
      details.iconUrl,
      'https://apt.izzysoft.de/fdroid/repo/org.example.app/en-US/icon.png',
    );
    expect(details.reproducibleStatus, reproducibleBuildStatusNoData);
  });

  test('GitHub verifies release asset attestation from digest', () async {
    final attestationStatus = await _StubGitHub()
        .getAttestationStatusForSha256Digest(
          'https://github.com/example/app',
          'sha256:abc123',
          <String, dynamic>{},
        );

    expect(attestationStatus, githubAttestationStatusVerified);
  });

  test(
    'GitHub marks missing release asset attestation as unsupported',
    () async {
      final attestationStatus = await _StubGitHub()
          .getAttestationStatusForSha256Digest(
            'https://github.com/example/app',
            'sha256:empty123',
            <String, dynamic>{},
          );

      expect(attestationStatus, githubAttestationStatusUnsupported);
    },
  );

  test('GitHub marks attestation API failures as error', () async {
    final attestationStatus = await _StubGitHub()
        .getAttestationStatusForSha256Digest(
          'https://github.com/example/app',
          'sha256:error123',
          <String, dynamic>{},
        );

    expect(attestationStatus, githubAttestationStatusError);
  });

  test(
    'F-Droid API parser uses localized response name when available',
    () async {
      final details = await FDroid().getAPKUrlsFromFDroidPackagesAPIResponse(
        Response(
          jsonEncode({
            'packageName': 'org.example.app',
            'name': {'en-US': 'Readable F-Droid Name'},
            'packages': [
              {'versionName': '1.0', 'versionCode': 1},
            ],
          }),
          200,
        ),
        'http://127.0.0.1:9/repo/org.example.app',
        'https://example.com/packages/org.example.app',
        'F-Droid',
      );

      expect(details.names.name, 'Readable F-Droid Name');
      expect(details.version, '1.0');
      expect(details.isReproducible, isNull);
      expect(details.reproducibleStatus, reproducibleBuildStatusNoData);
    },
  );

  test('App JSON preserves the reproducible verification version code', () {
    final original = _previousUniversalInstaller(
      reproducibleStatus: reproducibleBuildStatusVerified,
    );

    final restored = App.fromJson(original.toJson());

    expect(restored.latestReproducibleStatus, reproducibleBuildStatusVerified);
    expect(restored.latestReproducibleVersionCode, 31);
  });

  test(
    'F-Droid maps a matching successful version report to verified',
    () async {
      final source = _StubFDroidVerification(<Response>[
        _fdroidVerificationResponse(verified: true),
      ]);

      final status = await source.getReproducibleBuildStatus(
        'app.pwhs.universalinstaller',
        31,
        <String, dynamic>{},
      );

      expect(status, reproducibleBuildStatusVerified);
    },
  );

  test('F-Droid maps a matching failed version report to mismatched', () async {
    final source = _StubFDroidVerification(<Response>[
      _fdroidVerificationResponse(verified: false),
    ]);

    final status = await source.getReproducibleBuildStatus(
      'app.pwhs.universalinstaller',
      31,
      <String, dynamic>{},
    );

    expect(status, reproducibleBuildStatusNotReproducible);
  });

  test('F-Droid maps a missing version report to no data', () async {
    final source = _StubFDroidVerification(<Response>[Response('', 404)]);

    final status = await source.getReproducibleBuildStatus(
      'app.pwhs.universalinstaller',
      31,
      <String, dynamic>{},
    );

    expect(status, reproducibleBuildStatusNoData);
  });

  test('F-Droid maps an invalid version report to check error', () async {
    final source = _StubFDroidVerification(<Response>[
      Response('{"unexpected":true}', 200),
    ]);

    final status = await source.getReproducibleBuildStatus(
      'app.pwhs.universalinstaller',
      31,
      <String, dynamic>{},
    );

    expect(status, reproducibleBuildStatusError);
  });

  test('F-Droid maps a verification server failure to check error', () async {
    final source = _StubFDroidVerification(<Response>[Response('', 500)]);

    final status = await source.getReproducibleBuildStatus(
      'app.pwhs.universalinstaller',
      31,
      <String, dynamic>{},
    );

    expect(status, reproducibleBuildStatusError);
  });

  test(
    'F-Droid rechecks no data and observes a delayed verified report',
    () async {
      final source = _StubFDroidVerification(<Response>[
        Response('', 404),
        _fdroidVerificationResponse(verified: true),
      ]);
      source.previouslyCheckedApp = _previousUniversalInstaller(
        reproducibleStatus: reproducibleBuildStatusNoData,
      );

      final firstDetails = await source.getLatestAPKDetails(
        'https://f-droid.org/packages/app.pwhs.universalinstaller',
        <String, dynamic>{'trySelectingSuggestedVersionCode': true},
      );
      final secondDetails = await source.getLatestAPKDetails(
        'https://f-droid.org/packages/app.pwhs.universalinstaller',
        <String, dynamic>{'trySelectingSuggestedVersionCode': true},
      );

      expect(firstDetails.versionCode, 31);
      expect(firstDetails.reproducibleStatus, reproducibleBuildStatusNoData);
      expect(secondDetails.reproducibleStatus, reproducibleBuildStatusVerified);
      expect(source.verificationRequestCount, 2);
    },
  );

  test(
    'F-Droid rechecks legacy verified state without a version code',
    () async {
      final source = _StubFDroidVerification(<Response>[
        _fdroidVerificationResponse(verified: false),
      ]);
      source.previouslyCheckedApp = _previousUniversalInstaller(
        reproducibleStatus: reproducibleBuildStatusVerified,
      ).copyWith(latestReproducibleVersionCode: null);

      final details = await source.getLatestAPKDetails(
        'https://f-droid.org/packages/app.pwhs.universalinstaller',
        <String, dynamic>{'trySelectingSuggestedVersionCode': true},
      );

      expect(
        details.reproducibleStatus,
        reproducibleBuildStatusNotReproducible,
      );
      expect(source.verificationRequestCount, 1);
    },
  );

  test('F-Droid reuses an exact cached verified version report', () async {
    final source = _StubFDroidVerification(<Response>[
      _fdroidVerificationResponse(verified: true),
    ]);
    source.previouslyCheckedApp = _previousUniversalInstaller(
      reproducibleStatus: reproducibleBuildStatusVerified,
    );

    final details = await source.getLatestAPKDetails(
      'https://f-droid.org/packages/app.pwhs.universalinstaller',
      <String, dynamic>{'trySelectingSuggestedVersionCode': true},
    );

    expect(details.reproducibleStatus, reproducibleBuildStatusVerified);
    expect(source.verificationRequestCount, 0);
  });

  test('F-Droid API parser falls back to package page title', () async {
    final details =
        await _StubFDroid(
          '<html><head><title>NewPipe | F-Droid - Free and Open Source Android App Repository</title></head></html>',
        ).getAPKUrlsFromFDroidPackagesAPIResponse(
          Response(
            jsonEncode({
              'packageName': 'org.schabi.newpipe',
              'packages': [
                {'versionName': '0.28.8', 'versionCode': 1013},
              ],
            }),
            200,
          ),
          'http://127.0.0.1:9/repo/org.schabi.newpipe',
          'https://f-droid.org/packages/org.schabi.newpipe',
          'F-Droid',
        );

    expect(details.names.name, 'NewPipe');
  });

  test(
    'F-Droid overridden canonical host still falls back to package page title',
    () async {
      final details =
          await _StubFDroid(
            '<html><head><title>NewPipe | F-Droid - Free and Open Source Android App Repository</title></head></html>',
            hostChanged: true,
            hostIdenticalDespiteAnyChange: true,
          ).getAPKUrlsFromFDroidPackagesAPIResponse(
            Response(
              jsonEncode({
                'packageName': 'org.schabi.newpipe',
                'packages': [
                  {'versionName': '0.28.8', 'versionCode': 1013},
                ],
              }),
              200,
            ),
            'http://127.0.0.1:9/repo/org.schabi.newpipe',
            'https://f-droid.org/packages/org.schabi.newpipe',
            'F-Droid',
          );

      expect(details.names.name, 'NewPipe');
    },
  );

  test('source name replaces stale package-id app name', () async {
    final newApp = await SourceProvider().getApp(
      _StubSource(),
      'https://example.com/app',
      <String, dynamic>{},
      currentApp: _buildCurrentNamedApp(name: 'org.example.app'),
    );

    expect(newApp.name, 'Readable Name');
  });

  test('source name replaces stale package-looking app name', () async {
    final newApp = await SourceProvider().getApp(
      _StubSource(),
      'https://example.com/app',
      <String, dynamic>{},
      currentApp: _buildCurrentTempIdNamedApp(name: 'org.example.app'),
    );

    expect(newApp.name, 'Readable Name');
  });

  test('package-id name override is ignored when source name is readable', () {
    final app = App(
      id: 'org.example.app',
      url: 'https://example.com/app',
      author: 'Example Author',
      name: 'Readable Name',
      installedVersion: null,
      latestVersion: '1.0',
      apkUrls: const <MapEntry<String, String>>[
        MapEntry('example.apk', 'https://example.com/example.apk'),
      ],
      preferredApkIndex: 0,
      additionalSettings: <String, dynamic>{'appName': 'org.example.app'},
      lastUpdateCheck: DateTime.now(),
      pinned: false,
    );

    expect(app.finalName, 'Readable Name');
  });
}
