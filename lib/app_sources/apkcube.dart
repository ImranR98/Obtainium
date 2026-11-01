import 'dart:convert';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

const String apkCubeApiKeySetting = 'apkcube-api-key';
const String _apiBase = 'https://apkcube.com/api/v1';
const String _apiKeyPrefix = 'akc_';
const String _markerPrefix = 'apkcube';
const int _batchSize = 100;
const int _versionsCost = 5;
const int _downloadCost = 10;
const Duration _cacheTtl = Duration(minutes: 5);
const Duration apkCubeAuthBlockDuration = Duration(hours: 24);
const Duration apkCubeTransientBlockDuration = Duration(minutes: 5);
final RegExp _packagePattern = RegExp(
  r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
);

String? _nonEmpty(Object? value) {
  final s = value?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

bool apkCubeIsValidApiKey(String? key) =>
    key != null &&
    key.startsWith(_apiKeyPrefix) &&
    key.length > _apiKeyPrefix.length;

String _appApiUrl(String packageName) =>
    '$_apiBase/apps/${Uri.encodeComponent(packageName)}';

String? apkCubePackageNameFromUrl(String standardUrl) {
  final id = Uri.tryParse(
    standardUrl,
  )?.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
  return id != null && _packagePattern.hasMatch(id) ? id : null;
}

({String? code, String? message}) apkCubeApiError(String body) {
  try {
    final error = jsonDecode(body)['error'];
    if (error is Map) {
      return (
        code: _nonEmpty(error['code']),
        message: _nonEmpty(error['message']),
      );
    }
  } catch (_) {}
  return (code: null, message: null);
}

bool _isAuthFailure(int statusCode, String? errorCode) =>
    statusCode == 401 || (statusCode == 403 && errorCode == 'KEY_SCOPE');

Duration? apkCubeCooldownFor(int statusCode, String? errorCode) {
  if (_isAuthFailure(statusCode, errorCode)) return apkCubeAuthBlockDuration;
  if (statusCode >= 500 && statusCode != 503) {
    return apkCubeTransientBlockDuration;
  }
  return null;
}

int? apkCubeCreditsRemaining(Map<String, String> headers) =>
    int.tryParse(headers['x-credits-remaining']?.trim() ?? '');

class APKCubeRelease {
  final String versionName;
  final int versionCode;
  final DateTime? uploadedAt;
  final String? appName;

  const APKCubeRelease(
    this.versionName,
    this.versionCode,
    this.uploadedAt, {
    this.appName,
  });
}

class APKCubeBuild {
  final String apkId;
  final String arch;
  final String format;
  final int? fileSize;
  final String? changelog;

  const APKCubeBuild(
    this.apkId,
    this.arch,
    this.format, {
    this.fileSize,
    this.changelog,
  });
}

String apkCubeDownloadMarkerUrl(
  String packageName,
  int versionCode, {
  String? apkId,
}) => [_markerPrefix, packageName, '$versionCode', ?_nonEmpty(apkId)].join(':');

({String packageName, int versionCode, String? apkId})? parseAPKCubeMarkerUrl(
  String url,
) {
  final parts = url.split(':');
  if (parts.length < 3 || parts.first != _markerPrefix) return null;
  final versionCode = int.tryParse(parts[2]);
  if (!_packagePattern.hasMatch(parts[1]) || versionCode == null) return null;
  return (
    packageName: parts[1],
    versionCode: versionCode,
    apkId: _nonEmpty(parts.skip(3).join(':')),
  );
}

Map<String, Object> parseAPKCubeAvailability(String body) {
  final Map<String, dynamic> json = jsonDecode(body);
  final Map<String, Object> results = {};
  for (final pkg in (json['notFound'] as List<dynamic>? ?? [])) {
    results[pkg.toString()] = NoReleasesError();
  }
  for (final refused
      in (json['refused'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()) {
    final pkg = _nonEmpty(refused['packageName']);
    if (pkg == null) continue;
    results[pkg] = NoReleasesError(
      note: _nonEmpty(refused['message']) ?? _nonEmpty(refused['code']),
    );
  }
  for (final item
      in (json['items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()) {
    final pkg = _nonEmpty(item['packageName']);
    if (pkg == null) continue;
    final versionName = _nonEmpty(item['latestVersionName']);
    final versionCode = item['latestVersionCode'];
    if (item['available'] != true || versionCode is! int) {
      results[pkg] = NoAPKError();
    } else if (versionName == null) {
      results[pkg] = NoVersionError();
    } else {
      results[pkg] = APKCubeRelease(
        versionName,
        versionCode,
        DateTime.tryParse(item['latestUploadedAt']?.toString() ?? ''),
        appName: _nonEmpty(item['appName']),
      );
    }
  }
  return results;
}

List<APKCubeBuild> parseAPKCubeBuilds(String body, int versionCode) {
  final versions = jsonDecode(body)['versions'];
  if (versions is! List) return [];
  final builds = <APKCubeBuild>[];
  final seen = <String>{};
  for (final v in versions.whereType<Map<String, dynamic>>()) {
    if (v['versionCode'] != versionCode) continue;
    final apkId = _nonEmpty(v['apkId']);
    if (apkId == null) continue;
    final arch = _nonEmpty(v['arch']) ?? 'universal';
    final format = _nonEmpty(v['format'])?.toLowerCase() ?? 'apk';
    if (!seen.add('$arch|$format')) continue;
    builds.add(
      APKCubeBuild(
        apkId,
        arch,
        format,
        fileSize: v['fileSize'] is int ? v['fileSize'] as int : null,
        changelog: _nonEmpty(v['changelog']),
      ),
    );
  }
  return builds;
}

List<MapEntry<String, String>> apkCubeBuildAssets(
  String packageName,
  int versionCode,
  List<APKCubeBuild> builds,
) => builds.isEmpty
    ? [
        MapEntry(
          '$packageName-$versionCode.apk',
          apkCubeDownloadMarkerUrl(packageName, versionCode),
        ),
      ]
    : [
        for (final b in builds)
          MapEntry(
            '$packageName-$versionCode-${b.arch}.${b.format}',
            apkCubeDownloadMarkerUrl(packageName, versionCode, apkId: b.apkId),
          ),
      ];

class APKCube extends AppSource {
  APKCube() {
    name = 'APKCube';
    hosts = ['apkcube.com'];
    inferAppIdFromUrlPath = true;
    showReleaseDateAsVersionToggle = true;
    enableHostRequestGate = true;
    maxConcurrentRequestsPerHost = 2;
  }

  final Map<String, ({Object result, DateTime at})> _cache = {};
  ({DateTime until, String? authKey})? _block;
  int? _creditsRemaining;

  @override
  List<GeneratedFormItem> get sourceConfigSettingFormItems => [
    GeneratedFormTextField(
      apkCubeApiKeySetting,
      label: tr('apkCubeApiKeyLabel'),
      password: true,
      required: false,
      helpUrl: 'https://apkcube.com/account/api',
      additionalValidators: [
        (value) {
          final key = _nonEmpty(value);
          return key == null || apkCubeIsValidApiKey(key)
              ? null
              : tr('invalidApiKey');
        },
      ],
    ),
  ];

  @override
  String sourceSpecificStandardizeURL(
    String url, {
    bool forSelection = false,
  }) => standardizeUrlWithRegex(
    url,
    subdomainPrefix: '(www\\.)?',
    pathPattern: '/+[^/]+/+[^/]+',
  );

  Future<String> _getApiKey(Map<String, dynamic> additionalSettings) async {
    final settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    final sourceConfig = await getSourceConfigValues(
      additionalSettings,
      settingsProvider,
    );
    final key = _nonEmpty(sourceConfig[apkCubeApiKeySetting]);
    if (!apkCubeIsValidApiKey(key)) throw CredsNeededError(name);
    return key!;
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    if (forAPKDownload || !url.startsWith(_apiBase)) return null;
    final provided = _nonEmpty(additionalSettings[apkCubeApiKeySetting]);
    final key = apkCubeIsValidApiKey(provided)
        ? provided!
        : await _getApiKey(additionalSettings);
    return {'Authorization': 'Bearer $key', 'Accept': 'application/json'};
  }

  void _throwIfBlocked(String apiKey) {
    final block = _block;
    if (block == null) return;
    final now = DateTime.now();
    if (!now.isBefore(block.until) ||
        (block.authKey != null && block.authKey != apiKey)) {
      _block = null;
      return;
    }
    if (block.authKey != null) throw CredsNeededError(name);
    throw RateLimitError(
      max(1, (block.until.difference(now).inSeconds / 60).ceil()),
    );
  }

  Future<Response> _api(
    String url,
    Map<String, dynamic> additionalSettings, {
    Object? postBody,
  }) async {
    final apiKey = await _getApiKey(additionalSettings);
    _throwIfBlocked(apiKey);
    final res = await sourceRequest(url, {
      ...additionalSettings,
      apkCubeApiKeySetting: apiKey,
    }, postBody: postBody);
    final remaining = apkCubeCreditsRemaining(res.headers);
    if (remaining != null) {
      _creditsRemaining = remaining;
    } else if (res.statusCode == 402) {
      _creditsRemaining = 0;
    }
    if (res.statusCode == 200) return res;
    final error = apkCubeApiError(res.body);
    final isAuthFailure = _isAuthFailure(res.statusCode, error.code);
    final cooldown = apkCubeCooldownFor(res.statusCode, error.code);
    if (cooldown != null) {
      _block = (
        until: DateTime.now().add(cooldown),
        authKey: isAuthFailure ? apiKey : null,
      );
    }
    if (isAuthFailure) throw CredsNeededError(name);
    if (res.statusCode != 429 && error.message != null) {
      final suffix = error.code != null ? ' (${error.code})' : '';
      throw ObtainiumError('$name: ${error.message}$suffix');
    }
    ensureHttpSuccess(res);
    return res;
  }

  Object? _cached(String packageName) {
    final entry = _cache[packageName];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.at) > _cacheTtl) {
      _cache.remove(packageName);
      return null;
    }
    return entry.result;
  }

  Future<Map<String, Object>> _fetchAvailability(
    List<String> packageNames,
    Map<String, dynamic> additionalSettings,
  ) async {
    final res = await _api(
      '$_apiBase/apps/availability',
      additionalSettings,
      postBody: {'packageNames': packageNames},
    );
    final results = parseAPKCubeAvailability(res.body);
    final now = DateTime.now();
    for (final packageName in packageNames) {
      final result = results.putIfAbsent(packageName, NoReleasesError.new);
      _cache[packageName] = (result: result, at: now);
    }
    return results;
  }

  @override
  Future<void> prefetchUpdateInfo(List<App> apps) async {
    final ids = apps
        .map((app) => apkCubePackageNameFromUrl(app.url))
        .nonNulls
        .where((id) => _cached(id) == null)
        .toSet()
        .toList();
    if (ids.isEmpty) return;
    final settings = apps.first.additionalSettings;
    for (var i = 0; i < ids.length; i += _batchSize) {
      try {
        await _fetchAvailability(
          ids.sublist(i, min(i + _batchSize, ids.length)),
          settings,
        );
      } catch (e) {
        AppLogger.info('APKCube batch prefetch failed: $e');
        return;
      }
    }
  }

  Future<APKCubeRelease> _getRelease(
    String appId,
    Map<String, dynamic> additionalSettings,
  ) async {
    final result =
        _cached(appId) ??
        (await _fetchAvailability([appId], additionalSettings))[appId];
    if (result is APKCubeRelease) return result;
    if (result is ObtainiumError) throw result;
    throw NoReleasesError();
  }

  @override
  Future<String> generalReqPrefetchModifier(
    String reqUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final marker = parseAPKCubeMarkerUrl(reqUrl);
    if (marker == null) return reqUrl;
    final res = await _api(
      '${_appApiUrl(marker.packageName)}/download',
      additionalSettings,
      postBody: <String, dynamic>{'apkId': ?marker.apkId},
    );
    final url = _nonEmpty(jsonDecode(res.body)['url']);
    if (url == null) throw NoAPKError();
    return url;
  }

  Future<List<APKCubeBuild>> _fetchBuildsIfAffordable(
    String packageName,
    int versionCode,
    Map<String, dynamic> additionalSettings,
  ) async {
    final credits = _creditsRemaining;
    if (credits == null || credits < _versionsCost + _downloadCost) {
      return [];
    }
    _creditsRemaining = credits - _versionsCost;
    try {
      final res = await _api(
        '${_appApiUrl(packageName)}/versions',
        additionalSettings,
      );
      return parseAPKCubeBuilds(res.body, versionCode);
    } catch (e) {
      AppLogger.info('APKCube versions lookup failed: $e');
      return [];
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) => getLatestAPKDetailsWithContext(standardUrl, additionalSettings);

  @override
  Future<APKDetails> getLatestAPKDetailsWithContext(
    String standardUrl,
    Map<String, dynamic> additionalSettings, {
    App? currentApp,
  }) async {
    try {
      final appId = apkCubePackageNameFromUrl(standardUrl);
      if (appId == null) throw InvalidURLError(name);
      final release = await _getRelease(appId, additionalSettings);
      final App? previous =
          currentApp != null &&
              currentApp.apkUrls.isNotEmpty &&
              currentApp.apkUrls.every(
                (e) =>
                    parseAPKCubeMarkerUrl(e.value)?.versionCode ==
                    release.versionCode,
              )
          ? currentApp
          : null;
      final builds = previous != null
          ? const <APKCubeBuild>[]
          : await _fetchBuildsIfAffordable(
              appId,
              release.versionCode,
              additionalSettings,
            );
      return APKDetails(
        release.versionName,
        previous?.apkUrls ??
            apkCubeBuildAssets(appId, release.versionCode, builds),
        AppNames(name, release.appName ?? appId),
        releaseDate: release.uploadedAt,
        changeLog:
            previous?.changeLog ??
            builds.map((b) => b.changelog).nonNulls.firstOrNull,
        apkSizeBytes:
            previous?.apkSizeBytes ??
            (builds.length == 1 ? builds.single.fileSize : null),
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
