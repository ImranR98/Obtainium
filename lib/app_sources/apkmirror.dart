// APKMirror tracking improvements include code and research adapted from ObtainX by Bikram Agarwal (@bikram-agarwal).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/utils/min_update_age.dart';

/// The APKMirror maintainers do not allow for directly downloading APKs (PR #44)
class APKMirror extends AppSource {
  APKMirror() {
    name = 'APKMirror';
    hosts = ['apkmirror.com'];
    enforceTrackOnly = true;
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
    inferAppIdEvenWhenTrackOnly = true;
    changeLogIfAnyIsMarkDown = false;
    enableHostRequestGate = true;
    maxConcurrentRequestsPerHost = 2;
  }

  static const String _fallbackVersion = '1.0.0';

  // APKUpdater's public API credential. Replace with Obtainium's own key once
  // APKMirror issues one; nothing else needs to change.
  static const String _apiBasicAuth =
      'Basic YXBpLWFwa3VwZGF0ZXI6cm01cmNmcnVVakt5MDRzTXB5TVBKWFc4';
  static const String _apiUrl =
      'https://www.apkmirror.com/wp-json/apkm/v1/app_exists/';
  static const int _apiBatchSize = 100;
  static const Duration _apiCacheTtl = Duration(minutes: 5);
  static const Duration _apiAuthBlockDuration = Duration(hours: 24);
  static const Duration _apiTransientBlockDuration = Duration(minutes: 5);

  static final RegExp _packagePattern = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
  );

  final Map<String, _ApiAppInfo> _apiCache = {};
  final Map<String, DateTime> _apiCacheTimestamps = {};
  DateTime? _apiBlockedUntil;

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
    [GeneratedFormHeader(label: tr('sectionReleaseSelection'))],
    AppSource.fallbackToOlderReleasesFormItem,
    [
      GeneratedFormTextField(
        'filterReleaseTitlesByRegEx',
        label: tr('filterReleaseTitlesByRegEx'),
        required: false,
        additionalValidators: [
          (value) {
            return regExValidator(value);
          },
        ],
      ),
    ],
    [
      GeneratedFormSwitch(
        'invertReleaseTitlesFilter',
        label: '${tr('invertRegEx')} (${tr('filterReleaseTitlesByRegEx')})',
        value: false,
      ),
    ],
  ];

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    final headers = {
      'User-Agent':
          'Obtainium/${(await getInstalledInfo(obtainiumId))?.versionName ?? _fallbackVersion} (+https://github.com/ImranR98/Obtainium)',
    };
    final uri = Uri.tryParse(url);
    if (uri != null &&
        _apiHostAllowed(uri) &&
        uri.path.startsWith('/wp-json/apkm/v1/')) {
      headers['Authorization'] = _apiBasicAuth;
    }
    return headers;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    return standardizeUrlWithRegex(
      url,
      subdomainPrefix: r'(www\.)?',
      pathPattern: r'/apk/[^/]+/[^/]+',
    );
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/#whatsnew';

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) => getLatestAPKDetailsWithContext(
    standardUrl,
    additionalSettings,
    currentApp: null,
  );

  @override
  Future<APKDetails> getLatestAPKDetailsWithContext(
    String standardUrl,
    Map<String, dynamic> additionalSettings, {
    App? currentApp,
  }) async {
    final apiDetails = await _apiDetailsIfAvailable(
      standardUrl,
      additionalSettings,
      currentApp,
    );
    if (apiDetails != null) {
      return apiDetails;
    }
    return _feedDetails(standardUrl, additionalSettings, currentApp);
  }

  Future<APKDetails?> _apiDetailsIfAvailable(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
    App? currentApp,
  ) async {
    final pname = _packageIdFor(currentApp, additionalSettings);
    if (pname == null) return null;
    final uri = Uri.tryParse(standardUrl);
    if (uri == null || !_apiHostAllowed(uri)) return null;
    if (hostChanged && !hostIdenticalDespiteAnyChange) return null;
    final blockedMinutes = _apiBlockedMinutes;
    if (blockedMinutes != null) {
      throw RateLimitError(blockedMinutes);
    }
    final info = await _getApiInfo(pname, additionalSettings);
    if (info == null) {
      final blockedMinutes = _apiBlockedMinutes;
      if (blockedMinutes != null) {
        throw RateLimitError(blockedMinutes);
      }
      return null;
    }
    if (!info.exists ||
        info.version == null ||
        info.version!.isEmpty ||
        info.releaseLink == null) {
      throw NoReleasesError();
    }
    if (!apkMirrorApiEntryMatchesStandardUrl(info.appLink, standardUrl)) {
      return null;
    }
    final bool fallbackToOlderReleases =
        additionalSettings['fallbackToOlderReleases'] == true;
    final String? regexFilter =
        (additionalSettings['filterReleaseTitlesByRegEx'] as String?)
                ?.isNotEmpty ==
            true
        ? additionalSettings['filterReleaseTitlesByRegEx']
        : null;
    if (regexFilter != null) {
      final title =
          '${info.appName ?? ''} ${info.version} by ${info.developerName ?? ''}'
              .trim();
      if (!passesRegExFilter(
        RegExp(regexFilter),
        title,
        invert: additionalSettings['invertReleaseTitlesFilter'] == true,
      )) {
        if (fallbackToOlderReleases) return null;
        throw NoReleasesError(note: tr('noMatchingReleaseFound'));
      }
    }
    final releaseUrl = _absoluteApiLink(info.releaseLink!, standardUrl);
    final releaseUri = Uri.tryParse(releaseUrl);
    if (releaseUri == null || !_apiHostAllowed(releaseUri)) return null;
    final bool isNewRelease = releaseUrl != currentApp?.releaseUrl;
    final int minAgeDays = await effectiveMinUpdateAgeDays(additionalSettings);
    final bool tooYoung = isReleaseTooYoung(info.releaseDate, minAgeDays);
    if (tooYoung && fallbackToOlderReleases) return null;
    _ReleaseScrape? scrape;
    if (isNewRelease && !tooYoung) {
      scrape = await _scrapeReleaseDetails(releaseUrl, additionalSettings);
    }
    return APKDetails(
      info.version!,
      [],
      getAppNames(standardUrl),
      releaseDate: info.releaseDate,
      changeLog: isNewRelease
          ? (info.whatsNew ?? scrape?.changeLog)
          : (info.whatsNew ?? currentApp?.changeLog),
      releaseUrl: releaseUrl,
      appId: pname,
      apkSizeBytes: isNewRelease ? scrape?.sizeBytes : currentApp?.apkSizeBytes,
    );
  }

  Future<APKDetails> _feedDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
    App? currentApp,
  ) async {
    try {
      final bool fallbackToOlderReleases =
          additionalSettings['fallbackToOlderReleases'] == true;
      final String? regexFilter =
          (additionalSettings['filterReleaseTitlesByRegEx'] as String?)
                  ?.isNotEmpty ==
              true
          ? additionalSettings['filterReleaseTitlesByRegEx']
          : null;
      final Response res = await sourceRequest(
        '$standardUrl/feed/',
        additionalSettings,
      );
      if (res.statusCode == 200) {
        final items = parse(res.body).querySelectorAll('item');
        final int minAgeDays = await effectiveMinUpdateAgeDays(
          additionalSettings,
        );
        DateTime? releaseDateFor(dynamic item) {
          final pubDateRaw = item?.querySelector('pubDate')?.innerHtml;
          final dateString = pubDateRaw?.split(' ').take(5).join(' ');
          if (dateString == null) return null;
          try {
            return HttpDate.parse('$dateString GMT');
          } catch (e) {
            AppLogger.warn(
              'Failed to parse APKMirror release date: ${e.toString()}',
            );
            return null;
          }
        }

        dynamic targetRelease;
        dynamic tooYoungRelease;
        int? targetReleaseIndex;
        int? tooYoungReleaseIndex;
        int releaseSkipped = 0;
        for (int i = 0; i < items.length; i++) {
          if (!fallbackToOlderReleases && i > releaseSkipped) break;
          final String? nameToFilter = items[i]
              .querySelector('title')
              ?.innerHtml;
          if (regexFilter != null &&
              nameToFilter != null &&
              !passesRegExFilter(
                RegExp(regexFilter),
                nameToFilter.trim(),
                invert: additionalSettings['invertReleaseTitlesFilter'] == true,
              )) {
            continue;
          }
          if (isReleaseTooYoung(releaseDateFor(items[i]), minAgeDays)) {
            if (tooYoungRelease == null) {
              tooYoungRelease = items[i];
              tooYoungReleaseIndex = i;
            }
            releaseSkipped++;
            continue;
          }
          targetRelease = items[i];
          targetReleaseIndex = i;
          break;
        }
        // No release old enough: use the newest so the provider can suppress
        // it until it ages.
        targetRelease ??= tooYoungRelease;
        targetReleaseIndex ??= tooYoungReleaseIndex;
        final String? titleString = targetRelease
            ?.querySelector('title')
            ?.innerHtml;
        if (targetRelease == null) {
          throw NoReleasesError(
            note: regexFilter != null ? tr('noMatchingReleaseFound') : null,
          );
        }
        final DateTime? releaseDate = releaseDateFor(targetRelease);
        final String? releaseUrl = targetReleaseIndex != null
            ? apkMirrorReleaseUrlFromFeedBodyForItemIndex(
                res.body,
                targetReleaseIndex,
              )
            : null;
        String? version;
        if (titleString != null) {
          version = apkMirrorVersionFromTitle(titleString);
          version ??= apkMirrorCleanReleaseTitle(titleString);
        }
        if (version == null || version.isEmpty) {
          version = titleString;
        }
        if (version == null || version.isEmpty) {
          throw NoVersionError();
        }
        final bool hasReleaseUrl = releaseUrl != null && releaseUrl.isNotEmpty;
        final bool isNewRelease =
            hasReleaseUrl && releaseUrl != currentApp?.releaseUrl;
        final bool tooYoung = isReleaseTooYoung(releaseDate, minAgeDays);
        _ReleaseScrape? scrape;
        if (isNewRelease && !tooYoung) {
          scrape = await _scrapeReleaseDetails(releaseUrl, additionalSettings);
        }
        return APKDetails(
          version,
          [],
          getAppNames(standardUrl),
          releaseDate: releaseDate,
          changeLog: isNewRelease ? scrape?.changeLog : currentApp?.changeLog,
          releaseUrl: releaseUrl,
          appId: apkMirrorPackageFromFeedBody(res.body),
          apkSizeBytes: isNewRelease
              ? scrape?.sizeBytes
              : currentApp?.apkSizeBytes,
        );
      } else {
        throw getObtainiumHttpError(res);
      }
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }

  Future<_ReleaseScrape?> _scrapeReleaseDetails(
    String releaseUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final Response releaseRes = await sourceRequest(
        releaseUrl,
        additionalSettings,
      );
      if (releaseRes.statusCode != 200) return null;
      final changeLog = apkMirrorChangeLogFromReleasePageHtml(releaseRes.body);
      int? size = apkMirrorSizeBytesFromPageText(
        parse(releaseRes.body).body?.text ?? releaseRes.body,
      );
      if (size == null) {
        final String? downloadPageUrl = apkMirrorDownloadPageUrlFromReleasePage(
          releaseRes.body,
          releaseUrl,
        );
        if (downloadPageUrl != null) {
          final Response downloadRes = await sourceRequest(
            downloadPageUrl,
            additionalSettings,
          );
          if (downloadRes.statusCode == 200) {
            size = apkMirrorSizeBytesFromPageText(
              parse(downloadRes.body).body?.text ?? downloadRes.body,
            );
          }
        }
      }
      return _ReleaseScrape(changeLog, size);
    } catch (e) {
      AppLogger.info('APKMirror release scrape failed: $e');
      return null;
    }
  }

  @override
  Future<void> prefetchUpdateInfo(List<App> apps) async {
    if (_apiBlockedMinutes != null) return;
    final pnames = <String>{};
    Map<String, dynamic>? settings;
    for (final app in apps) {
      final uri = Uri.tryParse(app.url);
      if (uri == null || !_apiHostAllowed(uri)) continue;
      if (!_packagePattern.hasMatch(app.id)) continue;
      pnames.add(app.id);
      settings ??= app.additionalSettings;
    }
    if (pnames.isEmpty) return;
    final list = pnames.toList();
    for (var i = 0; i < list.length; i += _apiBatchSize) {
      final end = i + _apiBatchSize > list.length
          ? list.length
          : i + _apiBatchSize;
      try {
        await _fetchAppInfoBatch(list.sublist(i, end), settings ?? const {});
      } catch (e) {
        AppLogger.info('APKMirror batch prefetch failed: $e');
        return;
      }
      if (_apiBlockedMinutes != null) return;
    }
  }

  String? _packageIdFor(
    App? currentApp,
    Map<String, dynamic> additionalSettings,
  ) {
    final currentId = currentApp?.id;
    if (currentId != null && _packagePattern.hasMatch(currentId)) {
      return currentId;
    }
    final explicitId = additionalSettings['appId'];
    if (explicitId is String && _packagePattern.hasMatch(explicitId)) {
      return explicitId;
    }
    return null;
  }

  bool _apiHostAllowed(Uri uri) =>
      uri.host == 'www.apkmirror.com' || uri.host == 'apkmirror.com';

  int? get _apiBlockedMinutes {
    final until = _apiBlockedUntil;
    if (until == null) return null;
    final now = DateTime.now();
    if (!now.isBefore(until)) {
      _apiBlockedUntil = null;
      return null;
    }
    return max(1, (until.difference(now).inSeconds / 60).ceil());
  }

  void _recordApiFailure(int statusCode, Map<String, String> headers) {
    final now = DateTime.now();
    if (headers['cf-mitigated']?.toLowerCase().trim() == 'challenge') {
      _apiBlockedUntil = now.add(_apiTransientBlockDuration);
      return;
    }
    if (statusCode == 401 || statusCode == 403) {
      _apiBlockedUntil = now.add(_apiAuthBlockDuration);
      return;
    }
    if (statusCode == 429 || statusCode == 503) {
      final retryAfter = int.tryParse(headers['retry-after']?.trim() ?? '');
      _apiBlockedUntil = now.add(
        Duration(
          seconds: retryAfter != null && retryAfter > 0 ? retryAfter : 300,
        ),
      );
      return;
    }
    _apiBlockedUntil = now.add(_apiTransientBlockDuration);
  }

  _ApiAppInfo? _cachedApiInfo(String pname) {
    final info = _apiCache[pname];
    final fetchedAt = _apiCacheTimestamps[pname];
    if (info == null || fetchedAt == null) return null;
    if (DateTime.now().difference(fetchedAt) > _apiCacheTtl) {
      _apiCache.remove(pname);
      _apiCacheTimestamps.remove(pname);
      return null;
    }
    return info;
  }

  Future<_ApiAppInfo?> _getApiInfo(
    String pname,
    Map<String, dynamic> additionalSettings,
  ) async {
    final cached = _cachedApiInfo(pname);
    if (cached != null) return cached;
    final fetched = await _fetchAppInfoBatch([pname], additionalSettings);
    return fetched[pname];
  }

  Future<Map<String, _ApiAppInfo>> _fetchAppInfoBatch(
    List<String> pnames,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final Response res = await sourceRequest(
        _apiUrl,
        additionalSettings,
        postBody: {'pnames': pnames},
      );
      if (res.statusCode != 200) {
        _recordApiFailure(res.statusCode, res.headers);
        return const {};
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final data = decoded['data'] as List<dynamic>? ?? const [];
      final result = <String, _ApiAppInfo>{};
      for (final raw in data) {
        if (raw is! Map<String, dynamic>) continue;
        final info = _ApiAppInfo.fromJson(raw);
        result[info.pname] = info;
        _apiCache[info.pname] = info;
        _apiCacheTimestamps[info.pname] = DateTime.now();
      }
      return result;
    } catch (e) {
      AppLogger.info('APKMirror API request failed: $e');
      rethrow;
    }
  }

  String _absoluteApiLink(String link, String standardUrl) {
    if (link.startsWith('http://') || link.startsWith('https://')) return link;
    return Uri.parse(standardUrl).resolve(link).toString();
  }

  AppNames getAppNames(String standardUrl) {
    final String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    final pathStart = temp.indexOf('/');
    if (pathStart < 0 || pathStart + 1 >= temp.length) {
      throw InvalidURLError(name);
    }
    final List<String> names = temp.substring(pathStart + 1).split('/');
    if (names.length < 3) throw InvalidURLError(name);
    return AppNames(names[1], names[2]);
  }
}

class _ApiAppInfo {
  final String pname;
  final bool exists;
  final String? appName;
  final String? appLink;
  final String? developerName;
  final String? version;
  final DateTime? releaseDate;
  final String? whatsNew;
  final String? releaseLink;

  const _ApiAppInfo({
    required this.pname,
    required this.exists,
    this.appName,
    this.appLink,
    this.developerName,
    this.version,
    this.releaseDate,
    this.whatsNew,
    this.releaseLink,
  });

  factory _ApiAppInfo.fromJson(Map<String, dynamic> json) {
    final app = json['app'];
    final developer = json['developer'];
    final release = json['release'];
    return _ApiAppInfo(
      pname: (json['pname'] ?? '') as String,
      exists: json['exists'] == true,
      appName: app is Map ? app['name'] as String? : null,
      appLink: app is Map ? app['link'] as String? : null,
      developerName: developer is Map ? developer['name'] as String? : null,
      version: release is Map ? release['version'] as String? : null,
      releaseDate: release is Map
          ? apkMirrorApiDate(release['publish_date'] as String?)
          : null,
      whatsNew: release is Map
          ? apkMirrorPlainTextFromHtml(release['whats_new'] as String?)
          : null,
      releaseLink: release is Map ? release['link'] as String? : null,
    );
  }
}

class _ReleaseScrape {
  final String? changeLog;
  final int? sizeBytes;

  const _ReleaseScrape(this.changeLog, this.sizeBytes);
}

/// Parses the API's `YYYY-MM-DD HH:MM:SS` (UTC) publish dates.
DateTime? apkMirrorApiDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  var normalized = raw.trim().replaceFirst(' ', 'T');
  if (!normalized.endsWith('Z')) normalized = '${normalized}Z';
  return DateTime.tryParse(normalized)?.toUtc();
}

/// Converts the API's `whats_new` HTML into the plain text the UI renders.
String? apkMirrorPlainTextFromHtml(String? html) {
  if (html == null || html.trim().isEmpty) return null;
  final withBreaks = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</(?:p|div|li|ul|ol|h[1-6])\s*>', caseSensitive: false),
        '\n',
      );
  final text = parse(withBreaks).body?.text ?? withBreaks;
  final normalized = text
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .join('\n')
      .trim();
  return normalized.isEmpty ? null : normalized;
}

/// Whether an `app_exists` entry describes the listing the user tracks.
/// Package names can map to several listings (Spotify phone/Wear/Automotive),
/// so mismatches fall back to the listing's feed.
bool apkMirrorApiEntryMatchesStandardUrl(String? appLink, String standardUrl) {
  if (appLink == null || appLink.trim().isEmpty) return false;
  final trackedPath = Uri.tryParse(standardUrl)?.path;
  if (trackedPath == null || trackedPath.isEmpty) return false;
  String normalize(String path) {
    var p = path.trim();
    if (!p.startsWith('/')) p = '/$p';
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p.toLowerCase();
  }

  return normalize(appLink) == normalize(trackedPath);
}

/// Reads the package name from the first icon URL in a feed body's
/// `content:encoded` HTML (`…_<pname>-384x384.png`).
String? apkMirrorPackageFromFeedBody(String feedBody) {
  final match = RegExp(
    r'<img[^>]+src="([^"]+)"',
    caseSensitive: false,
  ).firstMatch(feedBody);
  if (match == null) return null;
  return apkMirrorPackageFromIconUrl(match.group(1));
}

/// Reads the release page URL from an APKMirror RSS `<item>`. The `html`
/// parser drops `<link>` text (void element), so this works on the raw XML.
String? apkMirrorReleaseUrlFromFeedItemXml(String itemXml) {
  final match = RegExp(
    r'<link>\s*([^<]+?)\s*</link>',
    caseSensitive: false,
  ).firstMatch(itemXml);
  final url = match?.group(1);
  if (url == null) return null;
  return url.startsWith('http://') || url.startsWith('https://') ? url : null;
}

/// Extracts the release page URL of the Nth `<item>` from the raw feed body.
String? apkMirrorReleaseUrlFromFeedBodyForItemIndex(String body, int index) {
  if (index < 0) return null;
  final segments = body.split(RegExp(r'<item\b[^>]*>', caseSensitive: false));
  if (index + 1 >= segments.length) return null;
  final afterOpen = segments[index + 1];
  final closeIndex = afterOpen.toLowerCase().indexOf('</item>');
  final itemXml = closeIndex >= 0
      ? afterOpen.substring(0, closeIndex)
      : afterOpen;
  return apkMirrorReleaseUrlFromFeedItemXml(itemXml);
}

/// Strips APKMirror title decorations (" by Author", "(arm64-v8a)",
/// "(Android 8.0+)", "[0]") so the version token can be found.
String apkMirrorCleanReleaseTitle(String title) {
  var cleaned = title;
  final byIndex = cleaned.toLowerCase().lastIndexOf(' by ');
  if (byIndex > 0) {
    cleaned = cleaned.substring(0, byIndex);
  }
  cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Extracts a bare version token (e.g. "42.5.15-21") from an APKMirror title.
String? apkMirrorVersionFromTitle(String title) {
  final cleaned = apkMirrorCleanReleaseTitle(title);
  final match = RegExp(r'(?:^|\s)v?(\d[\d.\-+_]*)(?=\s|$)').firstMatch(cleaned);
  return match?.group(1);
}

/// Extracts a package name from an APKMirror listing's `og:image` filename
/// (e.g. `65a71d34ecd19_com.android.chrome.png` -> `com.android.chrome`).
/// Feed icon URLs carry a `-384x384` size suffix, which is stripped first.
/// Returns null when the filename carries no package-like segment.
String? apkMirrorPackageFromIconUrl(String? iconUrl) {
  if (iconUrl == null || iconUrl.trim().isEmpty) return null;
  final uri = Uri.tryParse(iconUrl.trim());
  if (uri == null || uri.pathSegments.isEmpty) return null;
  final fileName = uri.pathSegments.last;
  final dotIndex = fileName.lastIndexOf('.');
  final stem = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  final unsizedStem = stem.replaceFirst(RegExp(r'-\d+x\d+$'), '');
  final packagePattern = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
  );
  for (final segment in unsizedStem.split('_').reversed) {
    if (!packagePattern.hasMatch(segment)) continue;
    if (segment.toLowerCase().contains('apkmirror')) continue;
    return segment;
  }
  return null;
}

/// Parses the "File size: 270.70 MB" line from APKMirror page text.
int? apkMirrorSizeBytesFromPageText(String text) {
  final match = RegExp(
    r'File size:\s*([0-9][0-9.]*)\s*(B|KB|MB|GB)\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  final size = double.tryParse(match.group(1)!);
  if (size == null) return null;
  final unit = match.group(2)!.toUpperCase();
  final int multiplier = switch (unit) {
    'GB' => 1 << 30,
    'MB' => 1 << 20,
    'KB' => 1 << 10,
    _ => 1,
  };
  return (size * multiplier).round();
}

/// Finds the first same-release `-apk-download/` page link on a release page.
String? apkMirrorDownloadPageUrlFromReleasePage(
  String html,
  String releasePageUrl,
) {
  final doc = parse(html);
  final releaseUri = Uri.tryParse(releasePageUrl);
  if (releaseUri == null) return null;
  final releaseBase = '${releaseUri.origin}${releaseUri.path}';
  final validPrefix = releaseBase.endsWith('/') ? releaseBase : '$releaseBase/';
  for (final link in doc.querySelectorAll('a[href]')) {
    final href = link.attributes['href'];
    if (href == null || href.trim().isEmpty) continue;
    final parsedHref = Uri.tryParse(href);
    if (parsedHref == null) continue;
    final absolute = releaseUri.resolveUri(parsedHref).removeFragment();
    final path = absolute.path.endsWith('/')
        ? absolute.path
        : '${absolute.path}/';
    if (!path.endsWith('-apk-download/')) continue;
    final url = absolute.replace(path: path).toString();
    if (!url.startsWith(validPrefix)) continue;
    return url;
  }
  return null;
}

bool _apkMirrorIsWhatsNewHeading(String text) =>
    text.toLowerCase().startsWith("what's new in ");

bool _apkMirrorIsChangeLogStop(String text) {
  final lowerText = text.toLowerCase();
  return lowerText.startsWith('about ') ||
      lowerText.startsWith('download ') ||
      lowerText.contains(' screenshots') ||
      lowerText.contains(' trailer');
}

bool _apkMirrorIsChangeLogNoise(String text) {
  final lowerText = text.toLowerCase();
  return lowerText == 'advertisement' ||
      lowerText.startsWith('verified safe to install') ||
      lowerText == 'scroll to available downloads' ||
      lowerText == 'a more recent upload may be available below!';
}

String _apkMirrorNormalizedText(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();

String _apkMirrorBlockText(dom.Element element) {
  final parts = <String>[];
  for (final child in element.children) {
    if (child.localName == 'ul' || child.localName == 'ol') {
      for (final item in child.querySelectorAll('li')) {
        final text = _apkMirrorNormalizedText(item.text);
        if (text.isNotEmpty) parts.add('- $text');
      }
    } else {
      final text = _apkMirrorNormalizedText(child.text);
      if (text.isNotEmpty) parts.add(text);
    }
  }
  if (parts.isNotEmpty) return parts.join('\n');
  return _apkMirrorNormalizedText(element.text);
}

/// Extracts the "What's new in ..." block from an APKMirror release page.
String? apkMirrorChangeLogFromReleasePageHtml(String html) {
  final doc = parse(html);
  dom.Element? heading;
  for (final candidate in doc.querySelectorAll('h1,h2,h3,h4,h5,h6')) {
    if (_apkMirrorIsWhatsNewHeading(_apkMirrorNormalizedText(candidate.text))) {
      heading = candidate;
      break;
    }
  }
  if (heading == null) return null;
  final parts = <String>[];
  dom.Element? sibling = heading.nextElementSibling;
  while (sibling != null) {
    final text = _apkMirrorBlockText(sibling);
    if (_apkMirrorIsChangeLogStop(text)) break;
    if (text.isNotEmpty && !_apkMirrorIsChangeLogNoise(text)) {
      parts.add(text);
    }
    sibling = sibling.nextElementSibling;
  }
  final changeLog = parts.join('\n\n').trim();
  return changeLog.isEmpty ? null : changeLog;
}
