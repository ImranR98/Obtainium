import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_charset_detector/flutter_charset_detector.dart';
import 'package:http/http.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

/// Maps RuStore download URLs to a single `apkUrls` entry. A lone URL is served
/// as an `.apk` beside its `.zip` container; several URLs are a base APK plus
/// config splits, joined so the download pipeline installs them as one split
/// set (#3298).
List<MapEntry<String, String>> apkUrlsFromDownloadUrls(List<String> urls) {
  if (urls.length == 1) {
    // RuStore has an .apk beside the .zip container
    return getApkUrlsFromUrls([
      urls.first.replaceAll(RegExp(r'\.zip$'), '.apk'),
    ]);
  }
  final String key = getApkUrlsFromUrls([urls.first]).first.key;
  return [MapEntry(key, joinMultiApkUrl(urls))];
}

typedef _SecureSession = ({String deviceId, String signature});

class RuStore extends AppSource {
  RuStore() {
    hosts = ['rustore.ru'];
    name = 'RuStore';
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
    changeLogIfAnyIsMarkDown = false;
    inferAppIdFromUrlPath = true;
    canSearch = true;
  }

  static const String _appInfoUrl =
      'https://backapi.rustore.ru/applicationData/overallInfo';
  static const String _searchUrl =
      'https://backapi.rustore.ru/applicationData/apps';
  static const String _downloadLinkUrl =
      'https://backapi.rustore.ru/v3/showcase/apps/download-link';
  static const String _nonceUrl = 'https://api.rustore.ru/v1/secure/nonce';

  // Extracted key from RuStore native. Seems to be static across versions.
  static final List<int> _hmacKey = base64Decode(
    'K+eeiCbnVFnZ71KEVal0g5siHaX6v6drh8upeLgEPoU=',
  );
  static final List<int> _apkCertSha256 = base64Decode(
    'Zh8ggo73gN4LebxZ8mowhkMWNV8w5Pkc+hSiB5GDmRQ=',
  );

  static const String _deviceManufacturer = 'Google';
  static const String _deviceModelName = 'Pixel 8 Pro';
  static const String _deviceHardware = 'husky';
  static const String _firmwareVer = '16';
  static const String _androidSdkVer = '36';
  static const String _firmwareLang = 'ru';
  static const String _ruStoreVerCode = '1105002';
  static const String _userAgent =
      'RuStore/1.105.0.2 (Android $_firmwareVer; SDK $_androidSdkVer; '
      'arm64-v8a; $_deviceManufacturer $_deviceModelName; $_firmwareLang)';

  // Last real screen density and locales, for background isolates without
  // view metrics.
  static const String _screenDensityPrefsKey = 'ruStore-screenDensity';
  static const String _localesPrefsKey = 'ruStore-locales';

  static _SecureSession? _session;
  static String? _deviceType;

  Future<String> _getDeviceType() async {
    if (_deviceType == null) {
      final settingsProvider = SettingsProvider();
      await settingsProvider.initializeSettings();
      _deviceType = settingsProvider.isTV ? 'TV' : 'mobile';
    }
    return _deviceType!;
  }

  /// Device fields RuStore requires before it will return split APK URLs
  /// (ABI and SDK always; density for some apps; locales pick the language
  /// split).
  Future<Map<String, dynamic>> _deviceDownloadProfile() async {
    List<String> abis = const ['arm64-v8a'];
    int sdkVersion = int.tryParse(_androidSdkVer) ?? 36;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.supportedAbis.isNotEmpty) {
        abis = info.supportedAbis;
      }
      sdkVersion = info.version.sdkInt;
    } catch (e) {
      AppLogger.warn('RuStore: failed to read device info: $e', error: e);
    }
    final display = await _displayProfile();
    return {
      'supportedAbis': abis,
      'sdkVersion': sdkVersion,
      'screenDensity': display.density,
      if (display.locales.isNotEmpty) 'supportedLocales': display.locales,
    };
  }

  /// Screen density and system locales (Java `Locale.toString()` form).
  Future<({int density, List<String> locales})> _displayProfile() async {
    final settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    final dispatcher = PlatformDispatcher.instance;
    final view = dispatcher.views.firstOrNull;
    final savedDensity = int.tryParse(
      settingsProvider.getSettingString(_screenDensityPrefsKey) ?? '',
    );
    final savedLocales = settingsProvider.getSettingString(_localesPrefsKey);
    // A headless engine exposes the implicit view with default metrics with 160dpi.
    // RuStore may not return download URLs for that, so only trust attached views.
    if (view != null && !view.physicalSize.isEmpty) {
      final density = (view.devicePixelRatio * 160).round();
      final locales = dispatcher.locales.map((l) => l.toString()).toList();
      if (savedDensity != density) {
        settingsProvider.setSettingString(
          _screenDensityPrefsKey,
          density.toString(),
        );
      }
      final joinedLocales = locales.join(';');
      if (locales.isNotEmpty && savedLocales != joinedLocales) {
        settingsProvider.setSettingString(_localesPrefsKey, joinedLocales);
      }
      return (density: density, locales: locales);
    }
    // Reuse the last foreground values, else a plausible phone density and
    // whatever locales the engine reports.
    return (
      density: savedDensity ?? 420,
      locales:
          savedLocales?.split(';') ??
          dispatcher.locales.map((l) => l.toString()).toList(),
    );
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    final needsSignature =
        url.startsWith(_appInfoUrl) || url.startsWith(_downloadLinkUrl);
    final session = needsSignature ? await _getSecureSession() : _session;
    return _deviceHeaders(
      deviceType: await _getDeviceType(),
      // Some requests (currently search) don't require a signature but still
      // expect a deviceId
      deviceId: session?.deviceId ?? _randomDeviceId(),
      signature: needsSignature ? session?.signature : null,
    );
  }

  @override
  String sourceSpecificStandardizeURL(
    String url, {
    bool forSelection = false,
  }) => standardizeUrlWithRegex(
    url,
    subdomainPrefix: r'(www\.)?',
    pathPattern: r'/catalog/app/+[^/]+',
  );

  Future<dynamic> decodeJsonBody(Uint8List bytes) async {
    try {
      return jsonDecode((await CharsetDetector.autoDecode(bytes)).string);
    } catch (e) {
      return jsonDecode(utf8.decode(bytes));
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final String? appId = await tryInferringAppId(standardUrl);
      if (appId == null) {
        throw NoReleasesError();
      }
      final Response overallInfoResponse = await _sourceRequestWithSessionRetry(
        '$_appInfoUrl/$appId',
        additionalSettings,
      );
      ensureHttpSuccess(overallInfoResponse);
      final decoded = await decodeJsonBody(overallInfoResponse.bodyBytes);
      final appDetails = decoded is Map ? decoded['body'] : null;
      if (appDetails is! Map || appDetails['appId'] == null) {
        throw NoReleasesError();
      }

      final String appName = appDetails['appName'] ?? tr('app');
      final String author = appDetails['companyName'] ?? name;
      final String? dateStr = appDetails['appVerUpdatedAt'];
      final String? version = appDetails['versionName'];
      final String? changeLog = appDetails['whatsNew'];
      if (version == null || version.isEmpty) {
        throw NoVersionError();
      }
      DateTime? relDate;
      if (dateStr != null) {
        relDate = DateTime.tryParse(dateStr);
      }

      final downloadBody = {'appId': appDetails['appId'], 'firstInstall': true};
      var urls = await _fetchDownloadUrls(downloadBody, additionalSettings);
      if (urls.isEmpty) {
        // Include the device profile so RuStore returns split APKs for
        // apps that have no universal APK (all three fields required).
        urls = await _fetchDownloadUrls({
          ...downloadBody,
          'withoutSplits': false,
          ...await _deviceDownloadProfile(),
        }, additionalSettings);
      }
      if (urls.isEmpty) {
        throw NoAPKError();
      }

      return APKDetails(
        version,
        apkUrlsFromDownloadUrls(urls),
        AppNames(author, appName),
        releaseDate: relDate,
        changeLog: changeLog,
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }

  Future<List<String>> _fetchDownloadUrls(
    Map<String, dynamic> body,
    Map<String, dynamic> additionalSettings,
  ) async {
    final Response response = await _sourceRequestWithSessionRetry(
      _downloadLinkUrl,
      additionalSettings,
      followRedirects: false,
      postBody: body,
    );
    ensureHttpSuccess(response);
    final details = await decodeJsonBody(response.bodyBytes);
    if (details == null) {
      throw getObtainiumHttpError(response);
    }
    final downloadUrls = details is Map ? details['downloadUrls'] : null;
    return downloadUrls is List
        ? downloadUrls
              .whereType<Map>()
              .map((e) => e['url']?.toString())
              .whereType<String>()
              .where((e) => e.isNotEmpty)
              .toList()
        : const [];
  }

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    final uri = Uri.parse(_searchUrl).replace(
      queryParameters: {'query': query, 'pageNumber': '0', 'pageSize': '20'},
    );
    final response = await sourceRequest(uri.toString(), querySettings);
    ensureHttpSuccess(response);
    final decoded = await decodeJsonBody(response.bodyBytes);
    final content = decoded is Map && decoded['body'] is Map
        ? decoded['body']['content']
        : null;
    final Map<String, List<String>> results = {};
    if (content is List) {
      for (final app in content) {
        if (app is! Map) continue;
        final packageName = app['packageName']?.toString();
        final appName = app['appName']?.toString();
        if (packageName == null ||
            packageName.isEmpty ||
            appName == null ||
            appName.isEmpty) {
          continue;
        }
        results['https://${hosts[0]}/catalog/app/$packageName'] = [
          appName,
          packageName,
        ];
      }
    }
    return results;
  }

  Map<String, String> _deviceHeaders({
    required String deviceType,
    String? deviceId,
    String? signature,
  }) => {
    'deviceId': ?deviceId,
    'firmwareVer': _firmwareVer,
    'androidSdkVer': _androidSdkVer,
    'deviceManufacturerName': _deviceManufacturer,
    'deviceModelName': _deviceModelName,
    'deviceModel': '$_deviceManufacturer $_deviceModelName',
    'firmwareLang': _firmwareLang,
    'ruStoreVerCode': _ruStoreVerCode,
    'deviceType': deviceType,
    'User-Agent': _userAgent,
    'X-Client-Signature': ?signature,
  };

  Future<_SecureSession?> _getSecureSession() async =>
      _session ??= await _generateSecureSession();

  Future<_SecureSession?> _generateSecureSession() async {
    Future<String?> fetchNonce(String deviceId) async {
      final settingsProvider = SettingsProvider();
      await settingsProvider.initializeSettings();
      final response = await HttpService().request(
        'POST',
        _deviceHeaders(deviceType: await _getDeviceType(), deviceId: deviceId),
        {
          'url': _nonceUrl,
          'enableCertificatePinning': settingsProvider.enableCertificatePinning,
        },
      );
      if (response.statusCode != 200) {
        AppLogger.warn(
          'RuStore: nonce request returned ${response.statusCode}',
        );
        return null;
      }
      final decoded = await decodeJsonBody(response.bodyBytes);
      return decoded is Map ? decoded['nonce'] as String? : null;
    }

    // signature = base64(HMAC-SHA256(KEY, base64decode(nonce) || certSha256))
    String signNonce(String nonceB64) {
      final nonce = base64Decode(nonceB64);
      final digest = Hmac(
        sha256,
        _hmacKey,
      ).convert(Uint8List.fromList([...nonce, ..._apkCertSha256]));
      return base64Encode(digest.bytes);
    }

    try {
      final deviceId = _randomDeviceId();
      final nonce = await fetchNonce(deviceId);
      if (nonce == null) {
        return null;
      }
      final signature = signNonce(nonce);
      return _session = (deviceId: deviceId, signature: signature);
    } catch (e) {
      AppLogger.warn(
        'RuStore: failed to generate secure session: $e',
        error: e,
      );
      return null;
    }
  }

  String _randomDeviceId() {
    int i32(int x) => ((x + 0x80000000) & 0xFFFFFFFF) - 0x80000000;
    int javaStringHashCode(String s) {
      var h = 0;
      for (final ch in s.codeUnits) {
        h = (31 * h + ch) & 0xFFFFFFFF;
      }
      return h >= 0x80000000 ? h - 0x100000000 : h;
    }

    String deviceIdSuffix() {
      final m = javaStringHashCode(_deviceManufacturer);
      final mo = javaStringHashCode(_deviceModelName);
      final h = javaStringHashCode(_deviceHardware);
      final d = javaStringHashCode(_deviceHardware);
      return i32(d + i32((h + i32((mo + i32(m * 31)) * 31)) * 31)).toString();
    }

    final random = Random();
    final androidId = List.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '$androidId-${deviceIdSuffix()}';
  }

  /// [sourceRequest] with 419 (session rejected/missing) handling
  Future<Response> _sourceRequestWithSessionRetry(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    var response = await sourceRequest(
      url,
      additionalSettings,
      followRedirects: followRedirects,
      postBody: postBody,
    );
    if (response.statusCode == 419 && await _generateSecureSession() != null) {
      response = await sourceRequest(
        url,
        additionalSettings,
        followRedirects: followRedirects,
        postBody: postBody,
      );
    }
    return response;
  }
}
