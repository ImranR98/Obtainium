import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/services/html_parse_isolate.dart';

/// Single consolidated debug-logging flag for the APKMirror size code path.
///
/// One global, referenced by the lazy size resolver here, by
/// [SourceProvider.getApp] (to log the size that survived the update-check
/// merge), and by the AppPage button-rendering code (to log how the size
/// surfaces in the UI). When `false`, every guarded block short-circuits
/// without doing any work, so leaving the flag turned off has zero cost
/// in release builds.
const bool apkMirrorSizeDebug = false;
const String _apkMirrorSizeDebugPrefix = 'OBTAINX-APK-SIZE-DEBUG';

class _ApkMirrorSizeCandidate {
  final String key;
  final String url;
  final int sizeBytes;
  final bool isBundle;

  const _ApkMirrorSizeCandidate({
    required this.key,
    required this.url,
    required this.sizeBytes,
    required this.isBundle,
  });
}

Future<void> _logApkMirrorSizeDebug(String message) async {
  if (!apkMirrorSizeDebug) {
    return;
  }
  try {
    await LogsProvider(runDefaultClear: false).add(
      '$_apkMirrorSizeDebugPrefix APKMirror: $message',
      level: LogLevel.debug,
    );
  } catch (_) {
    // Debug logging must never affect callers.
  }
}

/// Image and static asset URL suffixes that appear in page HTML after a string
/// that looks like `com.vendor.app`, e.g. `com.google.android.calendar.png`.
const _apkMirrorTrailingNonPackageSegments = <String>{
  'avif',
  'bmp',
  'gif',
  'ico',
  'jpeg',
  'jpg',
  'png',
  'svg',
  'webp',
};

const _apkMirrorCanonicalAppSlugByAlias = <String, String>{
  'youtube-music-android-automotive': 'youtube-music',
  'youtube-music-wear-os': 'youtube-music',
};

String _apkMirrorNormalizeInferredPackageCandidate(String rawCandidate) {
  var normalized = rawCandidate;
  while (true) {
    final lastDotIndex = normalized.lastIndexOf('.');
    if (lastDotIndex <= 0) break;
    final tailSegment = normalized.substring(lastDotIndex + 1).toLowerCase();
    if (_apkMirrorTrailingNonPackageSegments.contains(tailSegment)) {
      normalized = normalized.substring(0, lastDotIndex);
    } else {
      break;
    }
  }
  return normalized;
}

/// RSS puts the release URL in `<link>https://...</link>`. The HTML parser
/// treats `<link>` as void, so [parse] drops that text. Read from raw XML.
String? releaseUrlFromApkMirrorRssItemInner(String itemInnerXml) {
  final linkText = RegExp(
    r'<link>([^<]+)</link>',
    caseSensitive: false,
  ).firstMatch(itemInnerXml);
  if (linkText != null) {
    final url = linkText.group(1)!.trim();
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
  }
  final linkHref = RegExp(
    r'''<link[^>]+href=["']([^"']+)["']''',
    caseSensitive: false,
  ).firstMatch(itemInnerXml);
  if (linkHref != null) {
    final url = linkHref.group(1)!.trim();
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
  }
  final guidMatch = RegExp(
    r'<guid[^>]*>([^<]+)</guid>',
    caseSensitive: false,
  ).firstMatch(itemInnerXml);
  if (guidMatch != null) {
    final url = guidMatch.group(1)!.trim();
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
  }
  return null;
}

/// When [itemInnerBlocks] is empty, HTML-parsed item index still matches the
/// Nth `<item>...</item>` region in raw XML for link extraction.
String? releaseUrlFromApkMirrorFeedBodyForItemIndex(
  String body,
  int itemIndex,
) {
  if (itemIndex < 0) return null;
  final segments = body.split(RegExp(r'<item\b[^>]*>', caseSensitive: false));
  if (itemIndex + 1 >= segments.length) return null;
  final afterItemOpen = segments[itemIndex + 1];
  final lower = afterItemOpen.toLowerCase();
  final closeIdx = lower.indexOf('</item>');
  if (closeIdx < 0) return null;
  return releaseUrlFromApkMirrorRssItemInner(
    afterItemOpen.substring(0, closeIdx),
  );
}

String? titleFromApkMirrorRssItemInner(String itemInnerXml) {
  Match? titleMatch = RegExp(
    r'<title>\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*</title>',
    caseSensitive: false,
  ).firstMatch(itemInnerXml);
  if (titleMatch != null) {
    return titleMatch.group(1)?.trim();
  }
  titleMatch = RegExp(
    r'<title>([^<]*)</title>',
    caseSensitive: false,
  ).firstMatch(itemInnerXml);
  return titleMatch?.group(1)?.trim();
}

/// Resolves Open Graph / Twitter image URL from an APKMirror app listing page.
Future<String?> iconUrlFromApkMirrorAppPageHtml(
  String html,
  String pageUrl,
) async {
  final doc = await parseHtmlOffIsolate(html);
  final String? raw =
      doc.querySelector('meta[property="og:image"]')?.attributes['content'] ??
      doc.querySelector('meta[name="twitter:image"]')?.attributes['content'] ??
      doc
          .querySelector('meta[name="twitter:image:src"]')
          ?.attributes['content'];
  if (raw == null || raw.trim().isEmpty) return null;
  final baseUri = Uri.parse(pageUrl);
  return baseUri.resolveUri(Uri.parse(raw.trim())).toString();
}

int? apkSizeBytesFromApkMirrorSizeText(String sizeText) {
  final match = RegExp(
    r'([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB)',
    caseSensitive: false,
  ).firstMatch(sizeText);
  if (match == null) {
    return null;
  }
  final double? sizeNumber = double.tryParse(match.group(1)!);
  if (sizeNumber == null) {
    return null;
  }
  final String unit = match.group(2)!.toUpperCase();
  double multiplier = 1;
  if (unit == 'KB') {
    multiplier = 1024;
  } else if (unit == 'MB') {
    multiplier = 1024 * 1024;
  } else if (unit == 'GB') {
    multiplier = 1024 * 1024 * 1024;
  }
  return (sizeNumber * multiplier).round();
}

Future<int?> apkSizeBytesFromApkMirrorReleasePageHtml(String html) async {
  final pageText = (await parseHtmlOffIsolate(html)).body?.text ?? html;
  final exactBytesMatch = RegExp(
    r'\(([0-9][0-9,]*)\s*bytes\)',
    caseSensitive: false,
  ).firstMatch(pageText);
  if (exactBytesMatch != null) {
    return int.tryParse(exactBytesMatch.group(1)!.replaceAll(',', ''));
  }

  final directDownloadSizeTexts = RegExp(
    r'Download[^\n]*,\s*([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB)',
    caseSensitive: false,
  ).allMatches(pageText).map((match) => match.group(0)!).toSet().toList();
  if (directDownloadSizeTexts.isNotEmpty) {
    return apkSizeBytesFromApkMirrorSizeText(directDownloadSizeTexts.first);
  }

  final fileSizeTexts = RegExp(
    r'File size:\s*([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB)',
    caseSensitive: false,
  ).allMatches(pageText).map((match) => match.group(0)!).toSet().toList();
  if (fileSizeTexts.isNotEmpty) {
    return apkSizeBytesFromApkMirrorSizeText(fileSizeTexts.first);
  }
  return null;
}

String? _apkMirrorSameReleaseDownloadPageUrlFromElement(
  html_dom.Element linkElement,
  String releasePageUrl,
) {
  final href = linkElement.attributes['href']?.trim();
  if (href == null || href.isEmpty) {
    return null;
  }
  final releaseUri = Uri.parse(releasePageUrl);
  final resolvedUri = releaseUri.resolve(href).removeFragment();
  final resolvedPathWithSlash = resolvedUri.path.endsWith('/')
      ? resolvedUri.path
      : '${resolvedUri.path}/';
  final resolved = resolvedUri.replace(path: resolvedPathWithSlash).toString();
  final releasePrefix = releasePageUrl.endsWith('/')
      ? releasePageUrl
      : '$releasePageUrl/';
  if (!resolved.startsWith(releasePrefix)) {
    return null;
  }
  final resolvedPath = Uri.parse(resolved).path;
  if (!resolvedPath.endsWith('-apk-download/') &&
      !resolvedPath.endsWith('-apk-download')) {
    return null;
  }
  return resolved;
}

String _apkMirrorNormalizedText(String text) {
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _apkMirrorIsWhatsNewHeading(String text) =>
    text.toLowerCase().startsWith("what's new in ");

bool _apkMirrorIsChangeLogStopHeading(String text) {
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

String _apkMirrorBlockText(html_dom.Element element) {
  final parts = <String>[];
  for (final child in element.children) {
    if (child.localName == 'ul' || child.localName == 'ol') {
      parts.addAll(
        child
            .querySelectorAll('li')
            .map((item) => _apkMirrorNormalizedText(item.text))
            .where((text) => text.isNotEmpty)
            .map((text) => '- $text'),
      );
    } else {
      final text = _apkMirrorNormalizedText(child.text);
      if (text.isNotEmpty) parts.add(text);
    }
  }
  if (parts.isNotEmpty) {
    return parts.join('\n');
  }
  return _apkMirrorNormalizedText(element.text);
}

String? _apkMirrorChangeLogFromPageText(String pageText) {
  final lines = pageText
      .split('\n')
      .map(_apkMirrorNormalizedText)
      .where((line) => line.isNotEmpty)
      .toList();
  final startIndex = lines.indexWhere(_apkMirrorIsWhatsNewHeading);
  if (startIndex < 0) return null;
  final changeLogLines = <String>[];
  for (int lineIndex = startIndex + 1; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex];
    if (_apkMirrorIsChangeLogStopHeading(line)) break;
    if (_apkMirrorIsChangeLogNoise(line)) continue;
    changeLogLines.add(line);
  }
  final changeLog = changeLogLines.join('\n').trim();
  return changeLog.isEmpty ? null : changeLog;
}

Future<String?> apkMirrorChangeLogFromReleasePageHtml(String html) async {
  final doc = await parseHtmlOffIsolate(html);
  html_dom.Element? whatsNewHeading;
  for (final heading in doc.querySelectorAll('h1,h2,h3,h4,h5,h6')) {
    if (_apkMirrorIsWhatsNewHeading(_apkMirrorNormalizedText(heading.text))) {
      whatsNewHeading = heading;
      break;
    }
  }
  if (whatsNewHeading != null) {
    final changeLogParts = <String>[];
    html_dom.Element? sibling = whatsNewHeading.nextElementSibling;
    while (sibling != null) {
      final text = _apkMirrorBlockText(sibling);
      if (_apkMirrorIsChangeLogStopHeading(text)) break;
      if (text.isNotEmpty && !_apkMirrorIsChangeLogNoise(text)) {
        changeLogParts.add(text);
      }
      sibling = sibling.nextElementSibling;
    }
    final changeLog = changeLogParts.join('\n\n').trim();
    if (changeLog.isNotEmpty) return changeLog;
  }
  return _apkMirrorChangeLogFromPageText(doc.body?.text ?? html);
}

bool _apkMirrorTextIncludesVariantHint(String text) {
  return RegExp(
    r'\b(APK|BUNDLE|arm64-v8a|armeabi-v7a|arm-v7a|x86_64|x86)\b',
    caseSensitive: false,
  ).hasMatch(text);
}

String _apkMirrorDownloadPageKeyFromLinkElement(html_dom.Element linkElement) {
  final linkText = _apkMirrorNormalizedText(linkElement.text);
  html_dom.Element? parent = linkElement.parent;
  String bestText = linkText;
  for (int depth = 0; depth < 6 && parent != null; depth++) {
    final candidateText = _apkMirrorNormalizedText('$linkText ${parent.text}');
    if (RegExp(
      r'\b(arm64-v8a|armeabi-v7a|arm-v7a|x86_64|x86)\b',
      caseSensitive: false,
    ).hasMatch(candidateText)) {
      return candidateText;
    }
    if (_apkMirrorTextIncludesVariantHint(candidateText)) {
      bestText = candidateText;
    }
    parent = parent.parent;
  }
  return bestText.isNotEmpty ? bestText : linkElement.outerHtml;
}

Future<List<MapEntry<String, String>>>
_apkMirrorDownloadPageUrlEntriesFromReleasePageHtml(
  String html,
  String releasePageUrl,
) async {
  final doc = await parseHtmlOffIsolate(html);
  final Map<String, int> weightedUrls = {};
  final Map<String, String> urlKeys = {};
  for (final linkElement in doc.querySelectorAll('a[href]')) {
    final resolved = _apkMirrorSameReleaseDownloadPageUrlFromElement(
      linkElement,
      releasePageUrl,
    );
    if (resolved == null) {
      continue;
    }
    final normalizedParentText = _apkMirrorDownloadPageKeyFromLinkElement(
      linkElement,
    );
    var weight = 50;
    if (RegExp(r'(^|\s)APK(\s|$)').hasMatch(normalizedParentText)) {
      weight -= 20;
    }
    if (RegExp(r'(^|\s)BUNDLE(\s|$)').hasMatch(normalizedParentText)) {
      weight += 20;
    }
    final existingWeight = weightedUrls[resolved];
    if (existingWeight == null || weight < existingWeight) {
      weightedUrls[resolved] = weight;
      urlKeys[resolved] = normalizedParentText;
    }
  }
  final sortedEntries = weightedUrls.entries.toList()
    ..sort((left, right) {
      final weightCompare = left.value.compareTo(right.value);
      if (weightCompare != 0) {
        return weightCompare;
      }
      return left.key.compareTo(right.key);
    });
  return sortedEntries
      .map((entry) => MapEntry(urlKeys[entry.key] ?? entry.key, entry.key))
      .toList();
}

Future<List<String>> apkMirrorDownloadPageUrlsFromReleasePageHtml(
  String html,
  String releasePageUrl,
) async {
  return (await _apkMirrorDownloadPageUrlEntriesFromReleasePageHtml(
    html,
    releasePageUrl,
  )).map((entry) => entry.value).toList();
}

Future<bool> apkMirrorDownloadPageHtmlIsBundle(String html) async {
  final pageText = (await parseHtmlOffIsolate(html)).body?.text ?? html;
  return RegExp(
    r'Download\s+APK\s+Bundle',
    caseSensitive: false,
  ).hasMatch(pageText);
}

Future<List<MapEntry<String, String>>> _filterApkMirrorDownloadPageEntries(
  List<MapEntry<String, String>> downloadPageEntries,
  Map<String, dynamic> additionalSettings,
) async {
  var filteredEntries = filterApks(
    downloadPageEntries,
    additionalSettings['apkFilterRegEx'],
    additionalSettings['invertAPKFilter'],
  );
  if (additionalSettings['autoApkFilterByArch'] == true) {
    filteredEntries = await filterApksByArch(filteredEntries);
  }
  return filteredEntries;
}

Future<List<_ApkMirrorSizeCandidate>> _filterApkMirrorSizeCandidates(
  List<_ApkMirrorSizeCandidate> candidates,
  Map<String, dynamic> additionalSettings,
) async {
  if (candidates.isEmpty) {
    return candidates;
  }
  final filteredEntries = await _filterApkMirrorDownloadPageEntries(
    candidates
        .map((candidate) => MapEntry(candidate.key, candidate.url))
        .toList(),
    additionalSettings,
  );
  final filteredUrls = filteredEntries.map((entry) => entry.value).toSet();
  return candidates.where((candidate) {
    return filteredUrls.contains(candidate.url);
  }).toList();
}

_ApkMirrorSizeCandidate? _pickApkMirrorSizeCandidate(
  List<_ApkMirrorSizeCandidate> candidates,
) {
  if (candidates.isEmpty) {
    return null;
  }
  final apkCandidates = candidates.where((candidate) {
    return !candidate.isBundle;
  }).toList();
  if (apkCandidates.isNotEmpty) {
    return apkCandidates.first;
  }
  return candidates.first;
}

DateTime? releaseDateFromApkMirrorRssItemInner(String itemInnerXml) {
  final pubDateMatch = RegExp(
    r'<pubDate>([^<]+)</pubDate>',
    caseSensitive: false,
  ).firstMatch(itemInnerXml);
  final raw = pubDateMatch?.group(1)?.trim();
  if (raw == null || raw.isEmpty) return null;
  try {
    return HttpDate.parse(raw);
  } catch (_) {
    try {
      final parts = raw.split(RegExp(r'\s+'));
      if (parts.length >= 5) {
        return HttpDate.parse('${parts.sublist(0, 5).join(' ')} GMT');
      }
    } catch (_) {}
  }
  return null;
}

class APKMirror extends AppSource {
  APKMirror() {
    name = 'APKMirror';
    hosts = ['apkmirror.com'];
    enforceTrackOnly = true;
    // APKMirror's release titles rarely match the versionName inside the APK
    // (they carry architecture/dpi/build suffixes), so shared-format matching
    // can't reconcile the two and step 2 of
    // getCorrectedInstallStatusAppIfPossible would otherwise never adopt the
    // device's version — leaving a stale installedVersion that pull-to-refresh
    // cannot correct. RockMods (also track-only) sets this for the same reason.
    // Trade-off: the device's version now wins whenever the two differ, so if
    // it can't be reconciled with latestVersion either, an update stays on
    // offer. Track-only apps are excluded from the auto-disable fallback in
    // step 4, so there's no automatic cleanup for that case — "mark updated"
    // can also be re-overwritten on the next reconcile.
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
    appIdInferIsOptional = true;
  }

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
    final packageInfo = await getInstalledInfo(
      obtainiumId,
      includeOwnDebugBuild: true,
    );
    return {
      'user-agent':
          'Mozilla/5.0 (Linux; Android 15; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36 ObtainX/${packageInfo?.versionName ?? '1.0.0'}',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    };
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    // Adopt upstream's base helper for the core standardization, then apply
    // the fork-only canonical-slug alias remapping on top (e.g. the
    // youtube-music automotive/wear-os slugs both collapse to youtube-music).
    final standardizedUrl = standardizeUrlWithRegex(
      url,
      subdomainPrefix: r'(www\.)?',
      pathPattern: r'/apk/[^/]+/[^/]+',
    );
    final lowerStandardizedUrl = standardizedUrl.toLowerCase();
    for (final aliasEntry in _apkMirrorCanonicalAppSlugByAlias.entries) {
      final aliasSuffix = '/${aliasEntry.key}';
      if (lowerStandardizedUrl.endsWith(aliasSuffix)) {
        return '${standardizedUrl.substring(0, standardizedUrl.length - aliasSuffix.length)}/${aliasEntry.value}';
      }
    }
    return standardizedUrl;
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/#whatsnew';

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    final Response res = await sourceRequest(standardUrl, additionalSettings);
    if (res.statusCode != 200) return null;
    const packagePattern = r'com(?:\.[a-zA-Z0-9_]+){2,}';
    final packageFullMatch = RegExp('^$packagePattern\$');
    for (final match in RegExp(packagePattern).allMatches(res.body)) {
      final candidate = _apkMirrorNormalizeInferredPackageCandidate(
        match.group(0)!,
      );
      if (candidate.length >= 10 &&
          !candidate.startsWith('com.apkmirror') &&
          !candidate.contains('apkmirror') &&
          packageFullMatch.hasMatch(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
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
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    final itemInnerBlocks = RegExp(
      r'<item>([\s\S]*?)</item>',
      caseSensitive: false,
    ).allMatches(res.body).map((match) => match.group(1)!).toList();

    final List<String> rawReleaseTitleCandidates = <String>[];
    void collectReleaseTitleCandidate(String? title) {
      if (title == null) {
        return;
      }
      final String trimmed = title.trim();
      if (trimmed.isEmpty) {
        return;
      }
      if (rawReleaseTitleCandidates.length >= 40) {
        return;
      }
      if (!rawReleaseTitleCandidates.contains(trimmed)) {
        rawReleaseTitleCandidates.add(trimmed);
      }
    }

    String? titleString;
    String? releasePageUrl;
    DateTime? releaseDate;

    if (itemInnerBlocks.isNotEmpty) {
      for (int scanIndex = 0; scanIndex < itemInnerBlocks.length; scanIndex++) {
        collectReleaseTitleCandidate(
          titleFromApkMirrorRssItemInner(itemInnerBlocks[scanIndex]),
        );
      }
      final RegExp? titleFilterPattern = regexFilter != null
          ? RegExp(regexFilter)
          : null;
      String? chosenBlock;
      for (int itemIndex = 0; itemIndex < itemInnerBlocks.length; itemIndex++) {
        if (!fallbackToOlderReleases && itemIndex > 0) break;
        final block = itemInnerBlocks[itemIndex];
        final nameToFilter = titleFromApkMirrorRssItemInner(block);
        if (titleFilterPattern != null &&
            nameToFilter != null &&
            !titleFilterPattern.hasMatch(nameToFilter.trim())) {
          continue;
        }
        chosenBlock = block;
        titleString = nameToFilter;
        break;
      }
      if (chosenBlock != null) {
        releasePageUrl = releaseUrlFromApkMirrorRssItemInner(chosenBlock);
        releaseDate = releaseDateFromApkMirrorRssItemInner(chosenBlock);
      }
    } else {
      final parsedItems = (await parseHtmlOffIsolate(
        res.body,
      )).querySelectorAll('item');
      for (int scanIndex = 0; scanIndex < parsedItems.length; scanIndex++) {
        collectReleaseTitleCandidate(
          parsedItems[scanIndex].querySelector('title')?.innerHtml,
        );
      }
      dynamic targetRelease;
      int chosenParsedItemIndex = -1;
      for (int itemIndex = 0; itemIndex < parsedItems.length; itemIndex++) {
        if (!fallbackToOlderReleases && itemIndex > 0) break;
        final nameToFilter = parsedItems[itemIndex]
            .querySelector('title')
            ?.innerHtml;
        if (regexFilter != null &&
            nameToFilter != null &&
            !RegExp(regexFilter).hasMatch(nameToFilter.trim())) {
          continue;
        }
        targetRelease = parsedItems[itemIndex];
        chosenParsedItemIndex = itemIndex;
        break;
      }
      titleString = targetRelease?.querySelector('title')?.innerHtml;
      final dateString = targetRelease
          ?.querySelector('pubDate')
          ?.innerHtml
          .split(' ')
          .sublist(0, 5)
          .join(' ');
      releaseDate = dateString != null
          ? HttpDate.parse('$dateString GMT')
          : null;
      if (chosenParsedItemIndex >= 0) {
        releasePageUrl = releaseUrlFromApkMirrorFeedBodyForItemIndex(
          res.body,
          chosenParsedItemIndex,
        );
      }
    }
    if (releasePageUrl != null && !releasePageUrl.startsWith('$standardUrl/')) {
      releasePageUrl = null;
    }
    String? version = titleString
        ?.substring(
          RegExp('[0-9]').firstMatch(titleString)?.start ?? 0,
          RegExp(' by ').allMatches(titleString).last.start,
        )
        .trim();
    if (version == null || version.isEmpty) {
      version = titleString;
    }
    if (version == null || version.isEmpty) {
      throw NoVersionError();
    }

    // Icon resolution is intentionally decoupled from size resolution. Size
    // resolution requires walking the release page + N download pages and
    // is now done lazily on the AppPage. The icon, by contrast, is one
    // cheap GET against the listing page and is fine to do here.
    String? iconUrl;
    try {
      final pageRes = await sourceRequest(standardUrl, additionalSettings);
      if (pageRes.statusCode == 200) {
        iconUrl = await iconUrlFromApkMirrorAppPageHtml(
          pageRes.body,
          standardUrl,
        );
      }
    } catch (_) {
      // Icon is optional - ignore errors.
    }

    // [apkSizeBytes] is intentionally not resolved here. The APKMirror size
    // walk is expensive (1 release page + 1 GET per download candidate, per
    // app, per refresh) and the result is only ever shown as " · 43 MB" on
    // the AppPage. It is therefore resolved lazily by AppPage on first
    // open via [resolveLatestApkSizeBytes], and persisted onto the App via
    // [AppsProvider.saveApps] so subsequent opens hit the in-memory copy.
    return APKDetails(
      version,
      [],
      getAppNames(standardUrl),
      releaseDate: releaseDate,
      changeLog: releasePageUrl,
      iconUrl: iconUrl,
      rawReleaseTitleCandidates: rawReleaseTitleCandidates,
    );
  }

  AppNames getAppNames(String standardUrl) {
    final String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    final List<String> names = temp.substring(temp.indexOf('/') + 1).split('/');
    return AppNames(names[1], names[2]);
  }

  /// Lazy resolver: walks the release page → ranked download pages → picks
  /// the smallest non-bundle APK and returns its size in bytes. The result
  /// is intended to be persisted onto the app's [App.apkSizeBytes] and
  /// stays valid until [App.latestVersion] changes - at which point
  /// [SourceProvider.getApp] clears the size and the next AppPage open
  /// re-runs this walk.
  ///
  /// Returns null when:
  /// - [releasePageUrl] is null or empty (e.g. older app records that
  ///   haven't run an update check since the new schema landed),
  /// - the release page returns non-200,
  /// - none of the download candidates resolve a size, or
  /// - any HTTP error along the walk surfaces (caught and logged).
  ///
  /// Honors the same per-app filtering as the install path
  /// (`apkFilterRegEx`, `invertAPKFilter`, `autoApkFilterByArch`) so the
  /// reported size matches what the user would actually download.
  Future<int?> resolveLatestApkSizeBytes({
    required String? releasePageUrl,
    required Map<String, dynamic> additionalSettings,
  }) async {
    if (releasePageUrl == null || releasePageUrl.isEmpty) {
      return null;
    }
    try {
      final releasePageResponse = await sourceRequest(
        releasePageUrl,
        additionalSettings,
      );
      await _logApkMirrorSizeDebug(
        'lazy release page status=${releasePageResponse.statusCode} bytes=${releasePageResponse.body.length} url=$releasePageUrl',
      );
      if (releasePageResponse.statusCode != 200) {
        return null;
      }
      // Best-effort: a release page often lists the picked APK's size
      // directly without us having to walk the per-variant download pages.
      final int? releasePageSize =
          await apkSizeBytesFromApkMirrorReleasePageHtml(
            releasePageResponse.body,
          );
      final downloadPageEntries =
          await _apkMirrorDownloadPageUrlEntriesFromReleasePageHtml(
            releasePageResponse.body,
            releasePageUrl,
          );
      final filteredEntries = await _filterApkMirrorDownloadPageEntries(
        downloadPageEntries,
        additionalSettings,
      );
      // No actual download links on the release page → only what we found
      // textually counts. We DO NOT fall back to URL-pattern guessing -
      // that path made up to 20 speculative HTTP requests per app per
      // refresh and the success rate was abysmal.
      if (filteredEntries.isEmpty) {
        return releasePageSize;
      }
      final List<_ApkMirrorSizeCandidate> sizeCandidates = [];
      for (final candidateDownloadPageEntry in filteredEntries) {
        final downloadPageResponse = await sourceRequest(
          candidateDownloadPageEntry.value,
          additionalSettings,
        );
        if (downloadPageResponse.statusCode != 200) {
          continue;
        }
        final candidateSize = await apkSizeBytesFromApkMirrorReleasePageHtml(
          downloadPageResponse.body,
        );
        if (candidateSize == null) {
          continue;
        }
        final candidateIsBundle = await apkMirrorDownloadPageHtmlIsBundle(
          downloadPageResponse.body,
        );
        sizeCandidates.add(
          _ApkMirrorSizeCandidate(
            key: candidateDownloadPageEntry.key,
            url: candidateDownloadPageEntry.value,
            sizeBytes: candidateSize,
            isBundle: candidateIsBundle,
          ),
        );
      }
      final filteredSizeCandidates = await _filterApkMirrorSizeCandidates(
        sizeCandidates,
        additionalSettings,
      );
      final pickedSizeCandidate = _pickApkMirrorSizeCandidate(
        filteredSizeCandidates,
      );
      if (pickedSizeCandidate != null) {
        await _logApkMirrorSizeDebug(
          'lazy picked bundle=${pickedSizeCandidate.isBundle} size=${pickedSizeCandidate.sizeBytes} key=${pickedSizeCandidate.key} url=${pickedSizeCandidate.url}',
        );
        return pickedSizeCandidate.sizeBytes;
      }
      return releasePageSize;
    } catch (error) {
      await _logApkMirrorSizeDebug('lazy resolver error=${error.toString()}');
      return null;
    }
  }
}
