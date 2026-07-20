import 'dart:convert';
import 'dart:io' show HttpHeaders;

import 'package:http/http.dart' show Response;
import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/app_sources/fdroidrepo.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/services/html_parse_isolate.dart';

class IzzyOnDroid extends AppSource {
  final FDroid fd = FDroid();

  static const String _officialRepoUrl = 'https://apt.izzysoft.de/fdroid/repo';
  static const String _rbtLogUrl =
      'https://apt.izzysoft.de/fdroid/rbtlogs/izzy.json';

  /// Canonical user-facing URL for one app (matches Izzy web index APK pages).
  static const String _izzyIndexApkBase =
      'https://apt.izzysoft.de/fdroid/index/apk/';

  IzzyOnDroid() {
    name = 'IzzyOnDroid';
    hosts = ['izzysoft.de'];
    canSearch = true;
    allowSubDomains = true;
  }

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems =>
      fd.additionalSourceAppSpecificSettingFormItems;

  static Map<String, dynamic>? _rbtLogByApkHash;
  static DateTime? _rbtLogFetchedAt;
  static const Duration _rbtLogCacheDuration = Duration(minutes: 1);

  Future<Map<String, dynamic>> _loadRbtLog(
    Map<String, dynamic> additionalSettings,
  ) async {
    final Map<String, dynamic>? cached = _rbtLogByApkHash;
    final DateTime? fetchedAt = _rbtLogFetchedAt;
    if (cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _rbtLogCacheDuration) {
      return cached;
    }
    final Response response = await sourceRequest(
      _rbtLogUrl,
      additionalSettings,
    );
    if (response.statusCode != 200) {
      throw getObtainiumHttpError(response);
    }
    final Object decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return <String, dynamic>{};
    }
    _rbtLogByApkHash = decoded;
    _rbtLogFetchedAt = DateTime.now();
    return decoded;
  }

  bool _rbtLogEntryMatchesRelease(
    Object? rawEntry,
    String appId,
    int versionCode,
  ) {
    if (rawEntry is! Map) {
      return false;
    }
    final Map<String, dynamic> entry = Map<String, dynamic>.from(rawEntry);
    return entry['appid'] == appId &&
        entry['version_code']?.toString() == versionCode.toString();
  }

  String _rbtLogEntryReproducibleStatus(Object? rawEntry) {
    if (rawEntry is! Map) {
      return reproducibleBuildStatusNoData;
    }
    final Object? reproducible = Map<String, dynamic>.from(
      rawEntry,
    )['reproducible'];
    if (reproducible == true) {
      return reproducibleBuildStatusVerified;
    }
    if (reproducible == false) {
      return reproducibleBuildStatusNotReproducible;
    }
    return reproducibleBuildStatusNoData;
  }

  String? _absoluteIzzyAppPageUrl(String appPageUrl, String? maybeRelativeUrl) {
    final String? trimmed = maybeRelativeUrl?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return Uri.parse(appPageUrl).resolve(trimmed).toString();
  }

  Future<String?> _iconUrlFromIzzyAppPage(
    String appId,
    Map<String, dynamic> additionalSettings,
  ) async {
    final String appPageUrl = '$_izzyIndexApkBase$appId';
    try {
      final Response pageResponse = await sourceRequest(
        appPageUrl,
        additionalSettings,
      );
      if (pageResponse.statusCode != 200) {
        return null;
      }
      final doc = await parseHtmlOffIsolate(pageResponse.body);
      return _absoluteIzzyAppPageUrl(
            appPageUrl,
            doc
                .querySelector('meta[property="og:image"]')
                ?.attributes['content'],
          ) ??
          _absoluteIzzyAppPageUrl(
            appPageUrl,
            doc.querySelector('img.appicon')?.attributes['src'],
          );
    } catch (_) {
      return null;
    }
  }

  Future<String> _rbtLogReleaseReproducibleStatus(
    String appId,
    int versionCode,
    String? apkSha256,
    Map<String, dynamic> additionalSettings,
  ) async {
    final Map<String, dynamic> rbtLogByApkHash = await _loadRbtLog(
      additionalSettings,
    );
    if (apkSha256 != null && apkSha256.isNotEmpty) {
      final Object? rawEntries = rbtLogByApkHash[apkSha256];
      for (final Object? rawEntry
          in rawEntries is List ? rawEntries : <Object?>[]) {
        if (_rbtLogEntryMatchesRelease(rawEntry, appId, versionCode)) {
          return _rbtLogEntryReproducibleStatus(rawEntry);
        }
      }
    }

    Object? newestMatchingEntry;
    int newestTimestamp = -1;
    for (final Object? rawEntries in rbtLogByApkHash.values) {
      for (final Object? rawEntry
          in rawEntries is List ? rawEntries : <Object?>[]) {
        if (!_rbtLogEntryMatchesRelease(rawEntry, appId, versionCode)) {
          continue;
        }
        final Map<String, dynamic> entry = Map<String, dynamic>.from(
          rawEntry as Map,
        );
        final int timestamp =
            int.tryParse(entry['timestamp']?.toString() ?? '') ?? 0;
        if (timestamp > newestTimestamp) {
          newestTimestamp = timestamp;
          newestMatchingEntry = rawEntry;
        }
      }
    }
    return _rbtLogEntryReproducibleStatus(newestMatchingEntry);
  }

  /// Izzy mirrors expect a normal F-Droid client user agent; bare Dart clients
  /// can get connection failures on some networks.
  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    final Uri? parsed = Uri.tryParse(url);
    if (parsed == null) {
      return null;
    }
    final String host = parsed.host.toLowerCase();
    if (host.endsWith('izzysoft.de')) {
      return <String, String>{
        HttpHeaders.userAgentHeader: 'F-Droid/1.0 (+https://f-droid.org)',
      };
    }
    return null;
  }

  // The fork keeps its own richer URL standardization instead of upstream's
  // pair of `standardizeUrlWithRegex` calls: it additionally rewrites the
  // legacy `apt.../fdroid/index/apk/<name>_<code>.apk` form into the canonical
  // `/fdroid/repo/<file>.apk` and accepts direct `/fdroid/repo/*.apk` URLs.
  // Upstream's helper only handles the `android.` and bare `index/apk` cases,
  // so adopting it would drop that extra handling.
  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    final RegExp standardUrlRegExA = RegExp(
      '^https?://android.${getSourceRegex(hosts)}/repo/apk/[^/]+',
      caseSensitive: false,
    );
    final RegExpMatch? matchA = standardUrlRegExA.firstMatch(url);
    if (matchA != null) {
      return matchA.group(0)!;
    }
    final RegExp standardUrlRegExB = RegExp(
      '^https?://apt.${getSourceRegex(hosts)}/fdroid/index/apk/[^/]+',
      caseSensitive: false,
    );
    final RegExpMatch? matchB = standardUrlRegExB.firstMatch(url);
    if (matchB != null) {
      final Uri parsedLegacy = Uri.parse(matchB.group(0)!);
      final String apkFileName = parsedLegacy.pathSegments.last;
      if (apkFileName.toLowerCase().endsWith('.apk')) {
        return '${parsedLegacy.scheme}://${parsedLegacy.host}/fdroid/repo/$apkFileName';
      }
      return matchB.group(0)!;
    }
    final RegExp standardUrlRegExC = RegExp(
      '^https?://apt.${getSourceRegex(hosts)}/fdroid/repo/[^/]+\\.apk\$',
      caseSensitive: false,
    );
    final RegExpMatch? matchC = standardUrlRegExC.firstMatch(url);
    if (matchC != null) {
      return matchC.group(0)!;
    }
    throw InvalidURLError(name);
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    final String? fromSettings = additionalSettings['appId'] as String?;
    if (fromSettings != null && fromSettings.isNotEmpty) {
      return fromSettings;
    }
    final Uri parsed = Uri.parse(standardUrl);
    final String? fromQuery = parsed.queryParameters['appId']?.trim();
    if (fromQuery != null && fromQuery.isNotEmpty) {
      return fromQuery;
    }
    final List<String> segments = parsed.pathSegments;
    for (
      int indexSegmentIndex = 0;
      indexSegmentIndex < segments.length;
      indexSegmentIndex++
    ) {
      if (segments[indexSegmentIndex].toLowerCase() != 'index') {
        continue;
      }
      if (indexSegmentIndex + 2 >= segments.length) {
        continue;
      }
      if (segments[indexSegmentIndex + 1].toLowerCase() != 'apk') {
        continue;
      }
      final String apkOrId = segments[indexSegmentIndex + 2];
      if (apkOrId.toLowerCase().endsWith('.apk')) {
        final String baseName = apkOrId.substring(0, apkOrId.length - 4);
        final RegExpMatch? versionSuffix = RegExp(
          r'^(.+)_([0-9]+)$',
        ).firstMatch(baseName);
        if (versionSuffix != null) {
          return versionSuffix.group(1);
        }
        return baseName;
      }
      return apkOrId;
    }
    final String lastSegment = parsed.pathSegments.last;
    if (lastSegment.endsWith('.apk')) {
      final String baseName = lastSegment.substring(0, lastSegment.length - 4);
      final RegExpMatch? versionSuffix = RegExp(
        r'^(.+)_([0-9]+)$',
      ).firstMatch(baseName);
      if (versionSuffix != null) {
        return versionSuffix.group(1);
      }
    }
    return fd.tryInferringAppId(
      standardUrl,
      additionalSettings: additionalSettings,
    );
  }

  @override
  App postProcessApp(App app) {
    String? appId = isTempId(app) ? null : app.id;
    final Uri uri = Uri.parse(app.url);
    appId ??= uri.queryParameters['appId']?.trim();
    if (appId == null || appId.isEmpty) {
      final List<String> segments = uri.pathSegments;
      for (
        int indexSegmentIndex = 0;
        indexSegmentIndex < segments.length;
        indexSegmentIndex++
      ) {
        if (segments[indexSegmentIndex].toLowerCase() != 'index') {
          continue;
        }
        if (indexSegmentIndex + 2 >= segments.length) {
          continue;
        }
        if (segments[indexSegmentIndex + 1].toLowerCase() != 'apk') {
          continue;
        }
        String candidate = segments[indexSegmentIndex + 2];
        if (candidate.toLowerCase().endsWith('.apk')) {
          final String baseName = candidate.substring(0, candidate.length - 4);
          final RegExpMatch? versionSuffix = RegExp(
            r'^(.+)_([0-9]+)$',
          ).firstMatch(baseName);
          candidate = versionSuffix?.group(1) ?? baseName;
        }
        appId = candidate;
        break;
      }
    }
    if (appId != null && appId.isNotEmpty) {
      app = app.copyWith(url: '$_izzyIndexApkBase$appId', id: appId);
      app.additionalSettings['appIdOrName'] = appId;
    }
    return app;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    String? appIdOrName = additionalSettings['appIdOrName'] as String?;
    final Uri standardUri = Uri.parse(standardUrl);
    if (standardUri.queryParameters['appId']?.trim().isNotEmpty == true) {
      appIdOrName = standardUri.queryParameters['appId']!.trim();
    }
    appIdOrName ??= await tryInferringAppId(
      standardUrl,
      additionalSettings: additionalSettings,
    );
    if (appIdOrName == null || appIdOrName.isEmpty) {
      throw NoReleasesError();
    }
    additionalSettings['appIdOrName'] = appIdOrName;
    final Response indexResponse = await fdroidRepoRequestIndexWithVariants(
      sourceRequest,
      _officialRepoUrl,
      additionalSettings,
    );
    if (indexResponse.statusCode != 200) {
      throw getObtainiumHttpError(indexResponse);
    }
    final APKDetails details = await FDroidRepo.apkDetailsFromIndexXmlResponse(
      indexResponse,
      appIdOrName,
      additionalSettings,
      name,
      reproducibleReleaseStatus:
          (String appId, int versionCode, String? apkSha256) {
            return _rbtLogReleaseReproducibleStatus(
              appId,
              versionCode,
              apkSha256,
              additionalSettings,
            );
          },
    );
    details.iconUrl ??= await _iconUrlFromIzzyAppPage(
      appIdOrName,
      additionalSettings,
    );
    return details;
  }

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    final Map<String, dynamic> mergedSettings = {
      ...querySettings,
      'url': _officialRepoUrl,
    };
    String? repoUrl = mergedSettings['url'] as String?;
    if (repoUrl == null) {
      throw NoReleasesError();
    }
    final FDroidRepo urlNormalizer = FDroidRepo();
    repoUrl = urlNormalizer.removeQueryParamsFromUrl(
      urlNormalizer.standardizeUrl(repoUrl),
    );
    final Response indexResponse = await fdroidRepoRequestIndexWithVariants(
      sourceRequest,
      repoUrl,
      mergedSettings,
    );
    if (indexResponse.statusCode != 200) {
      throw getObtainiumHttpError(indexResponse);
    }
    final Map<String, List<String>> parsed =
        await FDroidRepo.parseIndexXmlSearchResults(indexResponse, query);
    final Map<String, List<String>> out = <String, List<String>>{};
    for (final MapEntry<String, List<String>> entry in parsed.entries) {
      final String? packageId = Uri.parse(
        entry.key,
      ).queryParameters['appId']?.trim();
      if (packageId != null && packageId.isNotEmpty) {
        out['$_izzyIndexApkBase$packageId'] = entry.value;
      } else {
        out[entry.key] = entry.value;
      }
    }
    return out;
  }
}
