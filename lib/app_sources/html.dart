import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/utils/string_compare.dart';

List<String> collectAllStringsFromJSONObject(dynamic obj) {
  List<String> extractor(dynamic obj) {
    final results = <String>[];
    if (obj is String) {
      results.add(obj);
    } else if (obj is List) {
      for (final item in obj) {
        results.addAll(extractor(item));
      }
    } else if (obj is Map<String, dynamic>) {
      for (final value in obj.values) {
        results.addAll(extractor(value));
      }
    }

    return results;
  }

  return extractor(obj);
}

List<MapEntry<String, String>> getLinksInLines(String lines) =>
    RegExp(r'''(?:(?:http|https|ftp)://)[^\s"'<>()\[\]{}]+''')
        .allMatches(lines)
        .map(
          (match) => match
              .group(0)!
              // Punctuation usually belongs to the surrounding text/code
              // rather than to the URL itself.
              .replaceFirst(RegExp(r'[.,;:!?]+$'), ''),
        )
        .where((url) => url.isNotEmpty)
        .map((url) => MapEntry(url, url.split('/').last))
        .toList();

/// Collects absolute and root-relative URLs found in element attributes
/// (e.g. `<script src="/js/app.js">`), resolved against [reqUrl].
List<MapEntry<String, String>> getLinksInHtmlAttributes(
  Document html,
  Uri reqUrl,
) {
  final links = <MapEntry<String, String>>[];
  for (final element in html.querySelectorAll('*')) {
    for (final value in element.attributes.values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final isAbsolute = RegExp(
        r'^(https?|ftp)://',
        caseSensitive: false,
      ).hasMatch(trimmed);
      if (!isAbsolute && !trimmed.startsWith('/')) continue;
      final resolved = ensureAbsoluteUrl(trimmed, reqUrl);
      final uri = Uri.tryParse(resolved);
      if (uri == null ||
          !['http', 'https', 'ftp'].contains(uri.scheme.toLowerCase())) {
        continue;
      }
      links.add(MapEntry(resolved, resolved.split('/').last));
    }
  }
  return links;
}

/// Given an HTTP response, grab some links according to the common additional settings
/// (those that apply to intermediate and final steps)
Future<List<MapEntry<String, String>>> grabLinksCommonFromRes(
  Response res,
  Map<String, dynamic> additionalSettings,
) async {
  ensureHttpSuccess(res);
  final reqUrl = res.request?.url ?? Uri.parse('');
  return grabLinksCommon(res.body, reqUrl, additionalSettings);
}

/// Note: keys are URLs, values are filenames (opposite to the AppSource apkUrls)
Future<List<MapEntry<String, String>>> grabLinksCommon(
  String rawBody,
  Uri reqUrl,
  Map<String, dynamic> additionalSettings,
) async {
  final bool matchLinksOutsideATags =
      additionalSettings['matchLinksOutsideATags'] == true;
  final html = parse(rawBody);
  List<MapEntry<String, String>> allLinks = html
      .querySelectorAll('a')
      .map(
        (element) => MapEntry(
          element.attributes['href'] ?? '',
          element.text.isNotEmpty
              ? element.text
              : (element.attributes['href'] ?? '').split('/').last,
        ),
      )
      .where((element) => element.key.isNotEmpty)
      .map((e) => MapEntry(ensureAbsoluteUrl(e.key, reqUrl), e.value))
      .toList();
  if (allLinks.isEmpty || matchLinksOutsideATags) {
    // Merge every link source instead of replacing one set with another:
    // <a> links, URLs in the raw text and URLs in element attributes are all
    // valid candidates when [matchLinksOutsideATags] is enabled.
    final merged = <String, MapEntry<String, String>>{
      for (final link in allLinks) link.key: link,
    };
    void addAll(Iterable<MapEntry<String, String>> links) {
      for (final link in links) {
        merged.putIfAbsent(link.key, () => link);
      }
    }

    if (allLinks.isEmpty) {
      try {
        final jsonStrings = collectAllStringsFromJSONObject(
          jsonDecode(rawBody),
        );
        var jsonLinks = getLinksInLines(jsonStrings.join('\n'));
        if (jsonLinks.isEmpty) {
          jsonLinks = getLinksInLines(
            jsonStrings
                .map((l) {
                  return ensureAbsoluteUrl(l, reqUrl);
                })
                .join('\n'),
          );
        }
        addAll(jsonLinks);
      } catch (e) {
        AppLogger.warn('Failed to parse HTML links: ${e.toString()}');
        addAll(getLinksInLines(rawBody));
      }
    }
    if (matchLinksOutsideATags) {
      addAll(getLinksInLines(rawBody));
      addAll(getLinksInHtmlAttributes(html, reqUrl));
    }
    allLinks = merged.values.toList();
  }
  List<MapEntry<String, String>> links = [];
  final bool skipSort = additionalSettings['skipSort'] == true;
  final bool filterLinkByText = additionalSettings['filterByLinkText'] == true;
  if ((additionalSettings['customLinkFilterRegex'] as String?)?.isNotEmpty ==
      true) {
    final reg = RegExp(additionalSettings['customLinkFilterRegex']);
    links = allLinks.where((element) {
      var link = element.key;
      try {
        link = Uri.decodeFull(element.key);
      } catch (e) {
        AppLogger.debug('Failed to decode URI in HTML filter: ${e.toString()}');
      }
      return reg.hasMatch(filterLinkByText ? element.value : link);
    }).toList();
  } else {
    links = allLinks.where((element) {
      var link = element.key;
      try {
        link = Uri.decodeFull(element.key);
      } catch (e) {
        AppLogger.debug(
          'Failed to decode URI in HTML APK filter: ${e.toString()}',
        );
      }
      return AppSource.isApkOrContainerFile(
        Uri.parse((filterLinkByText ? element.value : link).trim()).path,
      );
    }).toList();
  }
  if (!skipSort) {
    links.sort(
      (a, b) => additionalSettings['sortByLastLinkSegment'] == true
          ? compareAlphaNumeric(
              a.key.split('/').where((e) => e.isNotEmpty).last,
              b.key.split('/').where((e) => e.isNotEmpty).last,
            )
          : compareAlphaNumeric(a.key, b.key),
    );
  }
  if (additionalSettings['reverseSort'] == true) {
    links = links.reversed.toList();
  }
  return links;
}

DateTime? _parseHtmlReleaseDateText(
  String? releaseDateRegEx,
  String? matchGroupString,
  String? dateFormatString,
  String stringToCheck,
) {
  if (releaseDateRegEx?.isNotEmpty != true) return null;
  String? extracted;
  try {
    extracted = extractVersion(
      releaseDateRegEx,
      matchGroupString,
      stringToCheck,
    );
  } on ObtainiumError catch (e) {
    AppLogger.debug('Release date RegEx did not match: ${e.toString()}');
    return null;
  }
  if (extracted?.isNotEmpty != true) return null;
  // intl's parser is case-sensitive for AM/PM and expects bare day numbers,
  // while scraped pages often use lowercase `pm` and ordinal suffixes (`3rd`).
  final normalized = extracted!
      .replaceAllMapped(
        RegExp(r'(\d+)(st|nd|rd|th)\b', caseSensitive: false),
        (m) => m.group(1)!,
      )
      .replaceAllMapped(
        RegExp(r'(?<=\d)\s*([ap]m)\b', caseSensitive: false),
        (m) => m.group(1)!.toUpperCase(),
      );
  final dateFormat = dateFormatString?.trim();
  if (dateFormat?.isNotEmpty == true) {
    try {
      final parsed = DateFormat(dateFormat, 'en_US').tryParse(normalized);
      if (parsed != null) return parsed;
    } catch (e) {
      AppLogger.debug('Invalid release date format: ${e.toString()}');
    }
  }
  return DateTime.tryParse(normalized);
}

bool _sameHtmlLink(String a, String b) {
  final uriA = Uri.tryParse(a);
  final uriB = Uri.tryParse(b);
  if (uriA == null || uriB == null) return a == b;
  return uriA.replace(fragment: '').normalizePath().toString() ==
      uriB.replace(fragment: '').normalizePath().toString();
}

DateTime? _extractHtmlReleaseDateFromLink(
  String? releaseDateRegEx,
  String? matchGroupString,
  String? dateFormatString,
  String pageHtml,
  String selectedLink,
  Uri baseUri,
) {
  Document document;
  try {
    document = parse(pageHtml);
  } catch (e) {
    AppLogger.debug('Failed to parse HTML for release date: ${e.toString()}');
    return null;
  }
  for (final anchor in document.querySelectorAll('a')) {
    final href = anchor.attributes['href']?.trim();
    if (href == null || href.isEmpty) continue;
    String resolved;
    try {
      resolved = ensureAbsoluteUrl(href, baseUri);
    } catch (_) {
      continue;
    }
    if (!_sameHtmlLink(resolved, selectedLink)) continue;
    Element? element = anchor;
    for (var depth = 0; depth < 4 && element != null; depth++) {
      final text =
          '${element.text.trim().replaceAll('\r\n', '\n').replaceAll('\n', '\\n')}\\n';
      if (text.isNotEmpty) {
        final date = _parseHtmlReleaseDateText(
          releaseDateRegEx,
          matchGroupString,
          dateFormatString,
          text,
        );
        if (date != null) return date;
      }
      element = element.parent;
    }
  }
  return null;
}

/// Extracts a release date from a scraped string using [releaseDateRegEx]
/// (optionally selecting a match group with [matchGroupString], `$N`-style).
/// The extracted text is parsed with [dateFormatString] when set (an `intl`
/// `DateFormat` pattern such as `EEE. MMMM do, yyyy - h:mma`), then falls back
/// to [DateTime.tryParse]. When [pageHtml] and [selectedLink] are supplied, the
/// date is first looked up in the selected link's own HTML block, so pages
/// with one date per APK do not return another build's date. Returns null when
/// nothing usable is found.
DateTime? extractHtmlReleaseDate(
  String? releaseDateRegEx,
  String? matchGroupString,
  String? dateFormatString,
  String stringToCheck, {
  String? pageHtml,
  String? selectedLink,
  Uri? baseUri,
}) {
  if (releaseDateRegEx?.isNotEmpty != true) return null;
  if (pageHtml != null && selectedLink != null) {
    final scoped = _extractHtmlReleaseDateFromLink(
      releaseDateRegEx,
      matchGroupString,
      dateFormatString,
      pageHtml,
      selectedLink,
      baseUri ?? Uri.parse(selectedLink),
    );
    if (scoped != null) return scoped;
  }
  return _parseHtmlReleaseDateText(
    releaseDateRegEx,
    matchGroupString,
    dateFormatString,
    stringToCheck,
  );
}

class HTML extends AppSource {
  @override
  List<List<GeneratedFormItem>> get combinedAppSpecificSettingFormItems {
    return super.combinedAppSpecificSettingFormItems.map((r) {
      return r.map((e) {
        if (e.key == 'versionExtractionRegEx') {
          e.label = tr('versionExtractionRegEx');
        }
        if (e.key == 'matchGroupToUse') {
          e.label = tr('matchGroupToUse');
        }
        return e;
      }).toList();
    }).toList();
  }

  List<List<GeneratedFormItem>> get _finalStepFormitems => [
    [
      GeneratedFormTextField(
        'customLinkFilterRegex',
        label: tr('customLinkFilterRegex'),
        hint: 'download/(.*/)?(android|apk|mobile)',
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
        'versionExtractWholePage',
        label: tr('versionExtractWholePage'),
      ),
    ],
  ];

  List<List<GeneratedFormItem>> get _commonFormItems => [
    [GeneratedFormSwitch('filterByLinkText', label: tr('filterByLinkText'))],
    [
      GeneratedFormSwitch(
        'matchLinksOutsideATags',
        label: tr('matchLinksOutsideATags'),
      ),
    ],
    [GeneratedFormSwitch('skipSort', label: tr('skipSort'))],
    [GeneratedFormSwitch('reverseSort', label: tr('takeFirstLink'))],
    [
      GeneratedFormSwitch(
        'sortByLastLinkSegment',
        label: tr('sortByLastLinkSegment'),
      ),
    ],
  ];

  List<List<GeneratedFormItem>> get _intermediateFormItems => [
    [
      GeneratedFormTextField(
        'customLinkFilterRegex',
        label: tr('intermediateLinkRegex'),
        hint: '([0-9]+.)*[0-9]+/\$',
        required: true,
        additionalValidators: [(value) => regExValidator(value)],
      ),
    ],
    [
      GeneratedFormSwitch(
        'autoLinkFilterByArch',
        label: tr('autoLinkFilterByArch'),
        value: false,
      ),
    ],
  ];

  HTML() {
    name = 'HTML';
    suppressStandardVersionExtraction = true;
    showReleaseDateAsVersionToggle = true;
  }

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
    [GeneratedFormHeader(label: tr('sectionLinkOptions'))],
    [
      GeneratedFormSubForm('intermediateLink', [
        ..._intermediateFormItems,
        ..._commonFormItems,
      ], label: tr('intermediateLink')),
    ],
    _finalStepFormitems[0],
    ..._commonFormItems,
    [GeneratedFormHeader(label: tr('sectionVersionOptions'))],
    ..._finalStepFormitems.sublist(1),
    [
      GeneratedFormDropdown(
        'defaultPseudoVersioningMethod',
        [
          MapEntry('partialAPKHash', tr('partialAPKHash')),
          MapEntry('APKLinkHash', tr('APKLinkHash')),
          const MapEntry('ETag', 'ETag'),
        ],
        label: tr('defaultPseudoVersioningMethod'),
        value: 'partialAPKHash',
      ),
    ],
    [GeneratedFormHeader(label: tr('releaseDate'))],
    [
      GeneratedFormTextField(
        'releaseDateRegEx',
        label: tr('releaseDateRegEx'),
        required: false,
        hint: r'Last modified: (.*)',
        additionalValidators: [(value) => regExValidator(value)],
      ),
    ],
    [
      GeneratedFormTextField(
        'releaseDateMatchGroup',
        label: tr('matchGroupToUseForX', args: [tr('releaseDateRegEx')]),
        required: false,
        hint: r'$0',
      ),
    ],
    [
      GeneratedFormTextField(
        'releaseDateDateFormat',
        label: tr('releaseDateDateFormat'),
        required: false,
        hint: 'EEE. MMMM d, yyyy - h:mma',
      ),
    ],
    [GeneratedFormHeader(label: tr('sectionRequestHeaders'))],
    [
      GeneratedFormSubForm(
        'requestHeader',
        [
          [
            GeneratedFormTextField(
              'requestHeader',
              label: tr('requestHeader'),
              required: false,
              additionalValidators: [
                (value) {
                  if ((value ?? 'empty:valid')
                          .split(':')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .length <
                      2) {
                    return tr('invalidInput');
                  }
                  return null;
                },
              ],
            ),
          ],
        ],
        label: tr('requestHeader'),
        value: [
          {
            'requestHeader':
                'User-Agent: Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
          },
        ],
      ),
    ],
    [GeneratedFormHeader(label: tr('sectionZipOptions'))],
    [
      GeneratedFormTextField(
        'zippedApkFilterRegEx',
        label: tr('zippedApkFilterRegEx'),
        required: false,
        additionalValidators: [(value) => regExValidator(value)],
      ),
    ],
  ];

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    if (additionalSettings.isEmpty) {
      return null;
    }
    final settings = Map<String, dynamic>.from(additionalSettings);
    if (settings['requestHeader'] is! List ||
        (settings['requestHeader'] as List).isEmpty) {
      settings['requestHeader'] = [];
    }
    final headers = (settings['requestHeader'] as List)
        .where((l) => (l['requestHeader'] as String?)?.isNotEmpty == true)
        .toList();
    final Map<String, String> requestHeaders = {};
    for (int i = 0; i < headers.length; i++) {
      final temp = (headers[i]['requestHeader'] as String).split(':');
      requestHeaders[temp[0].trim()] = temp.sublist(1).join(':').trim();
    }
    return requestHeaders;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    return url;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      var currentUrl = standardUrl;
      final intermediateLinks =
          ((additionalSettings['intermediateLink'] as List?) ?? <dynamic>[])
              .where(
                (l) =>
                    (l['customLinkFilterRegex'] as String?)?.isNotEmpty == true,
              )
              .toList();
      const int maxIntermediateLinkDepth = 10;
      final int linkCount = intermediateLinks.length.clamp(
        0,
        maxIntermediateLinkDepth,
      );
      for (int i = 0; i < linkCount; i++) {
        var intLinks = await grabLinksCommonFromRes(
          await sourceRequest(currentUrl, additionalSettings),
          intermediateLinks[i],
        );
        if (intermediateLinks[i]['autoLinkFilterByArch'] == true) {
          intLinks = await filterApksByArch(intLinks);
        }
        if (intLinks.isEmpty) {
          throw NoReleasesError(note: currentUrl);
        } else {
          currentUrl = intLinks.last.key;
        }
      }
      final uri = Uri.parse(currentUrl);
      List<MapEntry<String, String>> links = [];
      String versionExtractionWholePageString = currentUrl;
      String? pageHtml;
      if (additionalSettings['directAPKLink'] != true) {
        final Response res = await sourceRequest(
          currentUrl,
          additionalSettings,
        );
        pageHtml = res.body;
        versionExtractionWholePageString = res.body
            .split('\r\n')
            .join('\n')
            .split('\n')
            .join('\\n');
        links = await grabLinksCommonFromRes(res, additionalSettings);
        links = filterApks(
          links,
          additionalSettings['apkFilterRegEx'],
          additionalSettings['invertAPKFilter'],
        );
        if (links.isEmpty) {
          throw NoReleasesError(note: currentUrl);
        }
      } else {
        links = [MapEntry(currentUrl, currentUrl)];
      }
      final rel = links.last.key;
      var relDecoded = rel;
      try {
        relDecoded = Uri.decodeFull(rel);
      } catch (e) {
        AppLogger.debug(
          'Failed to decode URI for version extraction: ${e.toString()}',
        );
      }
      String? version;
      version = extractVersion(
        additionalSettings['versionExtractionRegEx'] as String?,
        additionalSettings['matchGroupToUse'] as String?,
        additionalSettings['versionExtractWholePage'] == true
            ? versionExtractionWholePageString
            : relDecoded,
      );
      // Use a local copy for the request helpers: additionalSettings is stored
      // on the App, and writing the transient resolved URL into it would leak
      // into the app's persisted configuration.
      final requestSettings = Map<String, dynamic>.from(additionalSettings)
        ..['url'] = rel;
      final apkReqHeaders = await getRequestHeaders(
        requestSettings,
        rel,
        forAPKDownload: true,
      );
      if (version == null &&
          requestSettings['defaultPseudoVersioningMethod'] == 'ETag') {
        version = await checkETagHeader(
          requestSettings,
          headers: apkReqHeaders,
        );
        if (version == null || version.isEmpty) {
          throw NoVersionError();
        }
      }
      version ??=
          requestSettings['defaultPseudoVersioningMethod'] == 'APKLinkHash'
          ? rel.hashCode.toString()
          : (await checkPartialDownloadHashDynamic(
              requestSettings,
              headers: apkReqHeaders,
            )).toString();
      final releaseDate = extractHtmlReleaseDate(
        additionalSettings['releaseDateRegEx'] as String?,
        additionalSettings['releaseDateMatchGroup'] as String?,
        additionalSettings['releaseDateDateFormat'] as String?,
        versionExtractionWholePageString,
        pageHtml: pageHtml,
        selectedLink: rel,
        baseUri: uri,
      );
      return APKDetails(
        version,
        [rel].map((e) {
          final uri = Uri.parse(e);
          final fileName = uri.pathSegments.isNotEmpty
              ? uri.pathSegments.last
              : uri.origin;
          return MapEntry('${e.hashCode}-$fileName', e);
        }).toList(),
        AppNames(uri.host, tr('app')),
        releaseDate: releaseDate,
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
