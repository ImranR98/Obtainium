import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

String ensureAbsoluteUrl(String ambiguousUrl, Uri referenceAbsoluteUrl) {
  if (ambiguousUrl.startsWith('//')) {
    ambiguousUrl = '${referenceAbsoluteUrl.scheme}:$ambiguousUrl';
  }
  try {
    Uri.parse(ambiguousUrl).origin;
    return ambiguousUrl;
  } catch (err) {
    // is relative
  }
  var currPathSegments = referenceAbsoluteUrl.path
      .split('/')
      .where((element) => element.trim().isNotEmpty)
      .toList();
  String absoluteUrl;
  if (ambiguousUrl.startsWith('/')) {
    absoluteUrl = '${referenceAbsoluteUrl.origin}$ambiguousUrl';
  } else if (currPathSegments.isEmpty) {
    absoluteUrl = '${referenceAbsoluteUrl.origin}/$ambiguousUrl';
  } else if (ambiguousUrl.split('/').where((e) => e.isNotEmpty).length == 1) {
    absoluteUrl =
        '${referenceAbsoluteUrl.origin}/${currPathSegments.join('/')}/$ambiguousUrl';
  } else {
    absoluteUrl =
        '${referenceAbsoluteUrl.origin}/${currPathSegments.sublist(0, currPathSegments.length - (currPathSegments.last.contains('.') ? 1 : 0)).join('/')}/$ambiguousUrl';
  }
  return Uri.parse(absoluteUrl).toString();
}

int compareAlphaNumeric(String a, String b) {
  List<String> aParts = _splitAlphaNumeric(a);
  List<String> bParts = _splitAlphaNumeric(b);

  for (int i = 0; i < aParts.length && i < bParts.length; i++) {
    String aPart = aParts[i];
    String bPart = bParts[i];

    bool aIsNumber = _isNumeric(aPart);
    bool bIsNumber = _isNumeric(bPart);

    if (aIsNumber && bIsNumber) {
      int aNumber = int.parse(aPart);
      int bNumber = int.parse(bPart);
      int cmp = aNumber.compareTo(bNumber);
      if (cmp != 0) {
        return cmp;
      }
    } else if (!aIsNumber && !bIsNumber) {
      int cmp = aPart.compareTo(bPart);
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

List<String> _splitAlphaNumeric(String s) {
  List<String> parts = [];
  StringBuffer sb = StringBuffer();

  bool isNumeric = _isNumeric(s[0]);
  sb.write(s[0]);

  for (int i = 1; i < s.length; i++) {
    bool currentIsNumeric = _isNumeric(s[i]);
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

bool _isNumeric(String s) {
  return s.codeUnitAt(0) >= 48 && s.codeUnitAt(0) <= 57;
}

// Given an HTTP response, grab some links according to the common additional settings
// (those that apply to intermediate and final steps)
Future<List<MapEntry<String, String>>> grabLinksCommon(
    Response res, Map<String, dynamic> additionalSettings) async {
  if (res.statusCode != 200) {
    throw getObtainiumHttpError(res);
  }
  var html = parse(res.body);
  List<MapEntry<String, String>> allLinks = html
      .querySelectorAll('a')
      .map((element) => MapEntry(
          element.attributes['href'] ?? '',
          element.text.isNotEmpty
              ? element.text
              : (element.attributes['href'] ?? '').split('/').last))
      .where((element) => element.key.isNotEmpty)
      .map((e) => MapEntry(ensureAbsoluteUrl(e.key, res.request!.url), e.value))
      .toList();
  if (allLinks.isEmpty) {
    allLinks = RegExp(
            r'(http|ftp|https)://([\w_-]+(?:(?:\.[\w_-]+)+))([\w.,@?^=%&:/~+#-]*[\w@?^=%&/~+#-])?')
        .allMatches(res.body)
        .map((match) =>
            MapEntry(match.group(0)!, match.group(0)?.split('/').last ?? ''))
        .toList();
  }
  List<MapEntry<String, String>> links = [];
  bool skipSort = additionalSettings['skipSort'] == true;
  bool filterLinkByText = additionalSettings['filterByLinkText'] == true;
  if ((additionalSettings['customLinkFilterRegex'] as String?)?.isNotEmpty ==
      true) {
    var reg = RegExp(additionalSettings['customLinkFilterRegex']);
    links = allLinks.where((element) {
      var link = element.key;
      try {
        link = Uri.decodeFull(element.key);
      } catch (e) {
        // Some links may not have valid encoding
      }
      return reg.hasMatch(filterLinkByText ? element.value : link);
    }).toList();
  } else {
    links = allLinks.where((element) {
      var link = element.key;
      try {
        link = Uri.decodeFull(element.key);
      } catch (e) {
        // Some links may not have valid encoding
      }
      return Uri.parse(filterLinkByText ? element.value : link)
          .path
          .toLowerCase()
          .endsWith('.apk');
    }).toList();
  }
  if (!skipSort) {
    links.sort((a, b) => additionalSettings['sortByLastLinkSegment'] == true
        ? compareAlphaNumeric(a.key.split('/').where((e) => e.isNotEmpty).last,
            b.key.split('/').where((e) => e.isNotEmpty).last)
        : compareAlphaNumeric(a.key, b.key));
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

  var finalStepFormitems = [
    [
      GeneratedFormTextField('customLinkFilterRegex',
          label: tr('customLinkFilterRegex'),
          hint: 'download/(.*/)?(android|apk|mobile)',
          required: false,
          additionalValidators: [
            (value) {
              return regExValidator(value);
            }
          ])
    ],
    [
      GeneratedFormSwitch('versionExtractWholePage',
          label: tr('versionExtractWholePage'))
    ]
  ];
  var commonFormItems = [
    [GeneratedFormSwitch('filterByLinkText', label: tr('filterByLinkText'))],
    [GeneratedFormSwitch('skipSort', label: tr('skipSort'))],
    [GeneratedFormSwitch('reverseSort', label: tr('takeFirstLink'))],
    [
      GeneratedFormSwitch('sortByLastLinkSegment',
          label: tr('sortByLastLinkSegment'))
    ],
  ];
  var intermediateFormItems = [
    [
      GeneratedFormTextField('customLinkFilterRegex',
          label: tr('intermediateLinkRegex'),
          hint: '([0-9]+.)*[0-9]+/\$',
          required: true,
          additionalValidators: [(value) => regExValidator(value)])
    ],
    [
      GeneratedFormSwitch('autoLinkFilterByArch',
          label: tr('autoLinkFilterByArch'), defaultValue: false)
    ],
  ];
  HTML() {
    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormSubForm(
            'intermediateLink', [...intermediateFormItems, ...commonFormItems],
            label: tr('intermediateLink'))
      ],
      finalStepFormitems[0],
      ...commonFormItems,
      ...finalStepFormitems.sublist(1),
      [
        GeneratedFormSubForm(
            'requestHeader',
            [
              [
                GeneratedFormTextField('requestHeader',
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
                      }
                    ])
              ]
            ],
            label: tr('requestHeader'),
            defaultValue: [
              {
                'requestHeader':
                    'User-Agent: Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36'
              }
            ])
      ],
      [
        GeneratedFormDropdown(
            'defaultPseudoVersioningMethod',
            [
              MapEntry('partialAPKHash', tr('partialAPKHash')),
              MapEntry('APKLinkHash', tr('APKLinkHash'))
            ],
            label: tr('defaultPseudoVersioningMethod'),
            defaultValue: 'partialAPKHash')
      ]
    ];
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
      Map<String, dynamic> additionalSettings,
      {bool forAPKDownload = false}) async {
    if (additionalSettings.isNotEmpty) {
      if (additionalSettings['requestHeader']?.isNotEmpty != true) {
        additionalSettings['requestHeader'] = [];
      }
      additionalSettings['requestHeader'] = additionalSettings['requestHeader']
          .where((l) => l['requestHeader'].isNotEmpty == true)
          .toList();
      Map<String, String> requestHeaders = {};
      for (int i = 0; i < (additionalSettings['requestHeader'].length); i++) {
        var temp =
            (additionalSettings['requestHeader'][i]['requestHeader'] as String)
                .split(':');
        requestHeaders[temp[0].trim()] = temp.sublist(1).join(':').trim();
      }
      return requestHeaders;
    }
    return null;
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
    var currentUrl = standardUrl;
    if (additionalSettings['intermediateLink']?.isNotEmpty != true) {
      additionalSettings['intermediateLink'] = [];
    }
    additionalSettings['intermediateLink'] =
        additionalSettings['intermediateLink']
            .where((l) => l['customLinkFilterRegex'].isNotEmpty == true)
            .toList();
    for (int i = 0; i < (additionalSettings['intermediateLink'].length); i++) {
      var intLinks = await grabLinksCommon(
          await sourceRequest(currentUrl, additionalSettings),
          additionalSettings['intermediateLink'][i]);
      if (intLinks.isEmpty) {
        throw NoReleasesError(note: currentUrl);
      } else {
        if (additionalSettings['intermediateLink'][i]['autoLinkFilterByArch'] ==
            true) {
          intLinks = await filterApksByArch(intLinks);
        }
        currentUrl = intLinks.last.key;
      }
    }
    var uri = Uri.parse(currentUrl);
    List<MapEntry<String, String>> links = [];
    String versionExtractionWholePageString = currentUrl;
    if (additionalSettings['directAPKLink'] != true) {
      Response res = await sourceRequest(currentUrl, additionalSettings);
      versionExtractionWholePageString =
          res.body.split('\r\n').join('\n').split('\n').join('\\n');
      links = await grabLinksCommon(res, additionalSettings);
      links = filterApks(links, additionalSettings['apkFilterRegEx'],
          additionalSettings['invertAPKFilter']);
      if (links.isEmpty) {
        throw NoReleasesError(note: currentUrl);
      }
    } else {
      links = [MapEntry(currentUrl, currentUrl)];
    }
    var rel = links.last.key;
    var relDecoded = rel;
    try {
      relDecoded = Uri.decodeFull(rel);
    } catch (e) {
      // Some links may not have valid encoding
    }
    String? version;
    version = extractVersion(
        additionalSettings['versionExtractionRegEx'] as String?,
        additionalSettings['matchGroupToUse'] as String?,
        additionalSettings['versionExtractWholePage'] == true
            ? versionExtractionWholePageString
            : relDecoded);
    version ??= additionalSettings['defaultPseudoVersioningMethod'] ==
            'APKLinkHash'
        ? rel.hashCode.toString()
        : (await checkPartialDownloadHashDynamic(rel,
                headers: await getRequestHeaders(additionalSettings,
                    forAPKDownload: true),
                allowInsecure: additionalSettings['allowInsecure'] == true))
            .toString();
    return APKDetails(
        version,
        [rel].map((e) {
          var uri = Uri.parse(e);
          var fileName =
              uri.pathSegments.isNotEmpty ? uri.pathSegments.last : uri.origin;
          return MapEntry('${e.hashCode}-$fileName', e);
        }).toList(),
        AppNames(uri.host, tr('app')));
  }
}
