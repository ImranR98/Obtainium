import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

int compareAlphaNumeric(String a, String b) {
  final List<String> aParts = _splitAlphaNumeric(a);
  final List<String> bParts = _splitAlphaNumeric(b);

  for (int i = 0; i < aParts.length && i < bParts.length; i++) {
    final String aPart = aParts[i];
    final String bPart = bParts[i];

    final bool aIsNumber = _isDigit(aPart);
    final bool bIsNumber = _isDigit(bPart);

    if (aIsNumber && bIsNumber) {
      final int aNumber = int.parse(aPart);
      final int bNumber = int.parse(bPart);
      final int cmp = aNumber.compareTo(bNumber);
      if (cmp != 0) {
        return cmp;
      }
    } else if (!aIsNumber && !bIsNumber) {
      final int cmp = aPart.compareTo(bPart);
      if (cmp != 0) {
        return cmp;
      }
    } else {
      // Alphanumeric strings come before numeric strings
      return aIsNumber ? 1 : -1;
    }
  }

  return aParts.length.compareTo(bParts.length);
}

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

List<String> _splitAlphaNumeric(String s) {
  if (s.isEmpty) return [];
  final List<String> parts = [];
  final StringBuffer sb = StringBuffer();

  bool isNumeric = _isDigit(s[0]);
  sb.write(s[0]);

  for (int i = 1; i < s.length; i++) {
    final bool currentIsNumeric = _isDigit(s[i]);
    if (currentIsNumeric == isNumeric) {
      sb.write(s[i]);
    } else {
      parts.add(sb.toString());
      sb.clear();
      sb.write(s[i]);
      isNumeric = currentIsNumeric;
    }
  }

  parts.add(sb.toString());

  return parts;
}

bool _isDigit(String s) {
  if (s.isEmpty) return false;
  return s.codeUnitAt(0) >= 48 && s.codeUnitAt(0) <= 57;
}

List<MapEntry<String, String>> getLinksInLines(String lines) =>
    RegExp(r'(?:(?:http|https|ftp)://)\S+')
        .allMatches(lines)
        .map(
          (match) =>
              MapEntry(match.group(0)!, match.group(0)?.split('/').last ?? ''),
        )
        .toList();

/// Given an HTTP response, grab some links according to the common additional settings
/// (those that apply to intermediate and final steps)
Future<List<MapEntry<String, String>>> grabLinksCommonFromRes(
  Response res,
  Map<String, dynamic> additionalSettings,
) async {
  if (res.statusCode != 200) {
    throw getObtainiumHttpError(res);
  }
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
    // Decode the body if the response is a JSON
    try {
      final jsonStrings = collectAllStringsFromJSONObject(jsonDecode(rawBody));
      allLinks = getLinksInLines(jsonStrings.join('\n'));
      if (allLinks.isEmpty) {
        allLinks = getLinksInLines(
          jsonStrings
              .map((l) {
                return ensureAbsoluteUrl(l, reqUrl);
              })
              .join('\n'),
        );
      }
    } catch (e) {
      unawaited(
        LogsProvider().add(
          'Failed to parse HTML links: ${e.toString()}',
          level: LogLevel.warning,
        ),
      );
      allLinks = getLinksInLines(rawBody);
    }
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
        unawaited(
          LogsProvider().add(
            'Failed to decode URI in HTML filter: ${e.toString()}',
            level: LogLevel.debug,
          ),
        );
      }
      return reg.hasMatch(filterLinkByText ? element.value : link);
    }).toList();
  } else {
    links = allLinks.where((element) {
      var link = element.key;
      try {
        link = Uri.decodeFull(element.key);
      } catch (e) {
        unawaited(
          LogsProvider().add(
            'Failed to decode URI in HTML APK filter: ${e.toString()}',
            level: LogLevel.debug,
          ),
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
  }

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
    [
      GeneratedFormSubForm('intermediateLink', [
        ..._intermediateFormItems,
        ..._commonFormItems,
      ], label: tr('intermediateLink')),
    ],
    _finalStepFormitems[0],
    ..._commonFormItems,
    ..._finalStepFormitems.sublist(1),
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
        if (intLinks.isEmpty) {
          throw NoReleasesError(note: currentUrl);
        } else {
          if (intermediateLinks[i]['autoLinkFilterByArch'] == true) {
            intLinks = await filterApksByArch(intLinks);
          }
          currentUrl = intLinks.last.key;
        }
      }
      final uri = Uri.parse(currentUrl);
      List<MapEntry<String, String>> links = [];
      String versionExtractionWholePageString = currentUrl;
      if (additionalSettings['directAPKLink'] != true) {
        final Response res = await sourceRequest(
          currentUrl,
          additionalSettings,
        );
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
        unawaited(
          LogsProvider().add(
            'Failed to decode URI for version extraction: ${e.toString()}',
            level: LogLevel.debug,
          ),
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
      final apkReqHeaders = await getRequestHeaders(
        additionalSettings,
        rel,
        forAPKDownload: true,
      );
      if (version == null &&
          additionalSettings['defaultPseudoVersioningMethod'] == 'ETag') {
        version = await checkETagHeader(
          rel,
          headers: apkReqHeaders,
          allowInsecure: additionalSettings['allowInsecure'] == true,
        );
        if (version == null || version.isEmpty) {
          throw NoVersionError();
        }
      }
      version ??=
          additionalSettings['defaultPseudoVersioningMethod'] == 'APKLinkHash'
          ? rel.hashCode.toString()
          : (await checkPartialDownloadHashDynamic(
              rel,
              headers: apkReqHeaders,
              allowInsecure: additionalSettings['allowInsecure'] == true,
            )).toString();
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
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
