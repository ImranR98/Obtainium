import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/core/logging/app_logger.dart';
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
  }

  static const String _fallbackVersion = '1.0.0';

  /// APKMirror's Cloudflare rule allowlists HTML pages for a User-Agent
  /// containing `APKUpdater`; any other UA (including plain `Obtainium`) is
  /// served a 403 challenge. The RSS feed is exempt. Keep our own identity
  /// appended so APKMirror can still attribute the traffic.
  static const String _allowlistedUserAgentToken = 'APKUpdater-v3.5.9';

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
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
  ];

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    return {
      'User-Agent':
          '$_allowlistedUserAgentToken Obtainium/${(await getInstalledInfo(obtainiumId))?.versionName ?? _fallbackVersion}',
    };
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
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    try {
      final Response res = await sourceRequest(standardUrl, additionalSettings);
      if (res.statusCode != 200) return null;
      final doc = parse(res.body);
      final String? iconUrl =
          doc
              .querySelector('meta[property="og:image"]')
              ?.attributes['content'] ??
          doc
              .querySelector('meta[name="twitter:image"]')
              ?.attributes['content'];
      return apkMirrorPackageFromIconUrl(iconUrl);
    } catch (e) {
      AppLogger.info('APKMirror package ID inference failed: $e');
      return null;
    }
  }

  @override
  Future<int?> resolveDownloadSize(
    String standardUrl,
    Map<String, dynamic> additionalSettings, {
    String? releaseUrl,
  }) async {
    if (releaseUrl == null || releaseUrl.isEmpty) return null;
    try {
      final Response releaseRes = await sourceRequest(
        releaseUrl,
        additionalSettings,
      );
      if (releaseRes.statusCode != 200) return null;
      final releasePageSize = apkMirrorSizeBytesFromPageText(
        parse(releaseRes.body).body?.text ?? releaseRes.body,
      );
      if (releasePageSize != null) return releasePageSize;
      final String? downloadPageUrl = apkMirrorDownloadPageUrlFromReleasePage(
        releaseRes.body,
        releaseUrl,
      );
      if (downloadPageUrl == null) return null;
      final Response downloadRes = await sourceRequest(
        downloadPageUrl,
        additionalSettings,
      );
      if (downloadRes.statusCode != 200) return null;
      return apkMirrorSizeBytesFromPageText(
        parse(downloadRes.body).body?.text ?? downloadRes.body,
      );
    } catch (e) {
      AppLogger.info('APKMirror size resolution failed: $e');
      return null;
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
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
              !RegExp(regexFilter).hasMatch(nameToFilter.trim())) {
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
        String? changeLog;
        if (releaseUrl != null && releaseUrl.isNotEmpty) {
          try {
            final Response releaseRes = await sourceRequest(
              releaseUrl,
              additionalSettings,
            );
            if (releaseRes.statusCode == 200) {
              changeLog = apkMirrorChangeLogFromReleasePageHtml(
                releaseRes.body,
              );
            }
          } catch (e) {
            AppLogger.info('APKMirror changelog fetch failed: $e');
          }
        }
        return APKDetails(
          version,
          [],
          getAppNames(standardUrl),
          releaseDate: releaseDate,
          changeLog: changeLog,
          releaseUrl: releaseUrl,
        );
      } else {
        throw getObtainiumHttpError(res);
      }
    } catch (e) {
      rethrowOrWrapError(e);
    }
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
/// Returns null when the filename carries no package-like segment.
String? apkMirrorPackageFromIconUrl(String? iconUrl) {
  if (iconUrl == null || iconUrl.trim().isEmpty) return null;
  final uri = Uri.tryParse(iconUrl.trim());
  if (uri == null || uri.pathSegments.isEmpty) return null;
  final fileName = uri.pathSegments.last;
  final dotIndex = fileName.lastIndexOf('.');
  final stem = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  final packagePattern = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
  );
  for (final segment in stem.split('_').reversed) {
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
