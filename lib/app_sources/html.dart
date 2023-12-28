import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

String ensureAbsoluteUrl(String ambiguousUrl, Uri referenceAbsoluteUrl) {
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
  if (ambiguousUrl.startsWith('/') || currPathSegments.isEmpty) {
    return '${referenceAbsoluteUrl.origin}/$ambiguousUrl';
  } else if (ambiguousUrl.split('/').where((e) => e.isNotEmpty).length == 1) {
    return '${referenceAbsoluteUrl.origin}/${currPathSegments.join('/')}/$ambiguousUrl';
  } else {
    return '${referenceAbsoluteUrl.origin}/${currPathSegments.sublist(0, currPathSegments.length - (currPathSegments.last.contains('.') ? 1 : 0)).join('/')}/$ambiguousUrl';
  }
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

class HTML extends AppSource {
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
      GeneratedFormTextField('versionExtractionRegEx',
          label: tr('versionExtractionRegEx'),
          required: false,
          additionalValidators: [(value) => regExValidator(value)]),
    ],
    [
      GeneratedFormTextField('matchGroupToUse',
          label: tr('matchGroupToUse'),
          required: false,
          hint: '0',
          textInputType: const TextInputType.numberWithOptions(),
          additionalValidators: [
            (value) {
              if (value?.isEmpty == true) {
                value = null;
              }
              value ??= '0';
              return intValidator(value);
            }
          ])
    ],
    [
      GeneratedFormSwitch('versionExtractWholePage',
          label: tr('versionExtractWholePage'))
    ],
    [
      GeneratedFormSwitch('supportFixedAPKURL',
          defaultValue: true, label: tr('supportFixedAPKURL')),
    ],
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
  ];
  HTML() {
    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormSubForm(
            'intermediateLink', [...intermediateFormItems, ...commonFormItems],
            label: tr('intermediateLink'),
            minRepetitions: 0,
            repetitions: 0,
            maxRepetitions: 0)
      ],
      finalStepFormitems[0],
      ...commonFormItems,
      ...finalStepFormitems.sublist(1)
    ];
    overrideVersionDetectionFormDefault('noVersionDetection',
        disableStandard: false, disableRelDate: true);
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
      {Map<String, dynamic> additionalSettings = const <String, dynamic>{},
      bool forAPKDownload = false}) async {
    return {
      "User-Agent":
          "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36"
    };
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    return url;
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
      links = allLinks
          .where((element) =>
              reg.hasMatch(filterLinkByText ? element.value : element.key))
          .toList();
    } else {
      links = allLinks
          .where((element) =>
              Uri.parse(filterLinkByText ? element.value : element.key)
                  .path
                  .toLowerCase()
                  .endsWith('.apk'))
          .toList();
    }
    if (!skipSort) {
      links.sort((a, b) => additionalSettings['sortByLastLinkSegment'] == true
          ? compareAlphaNumeric(
              a.key.split('/').where((e) => e.isNotEmpty).last,
              b.key.split('/').where((e) => e.isNotEmpty).last)
          : compareAlphaNumeric(a.key, b.key));
    }
    if (additionalSettings['reverseSort'] == true) {
      links = links.reversed.toList();
    }
    return links;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var currentUrl = standardUrl;
    for (int i = 0;
        i < (additionalSettings['intermediateLink']?.length ?? 0);
        i++) {
      var intLinks = await grabLinksCommon(await sourceRequest(currentUrl),
          additionalSettings['intermediateLink'][i]);
      if (intLinks.isEmpty) {
        throw NoReleasesError();
      } else {
        currentUrl = intLinks.last.key;
      }
    }

    var uri = Uri.parse(currentUrl);
    Response res = await sourceRequest(currentUrl);
    var links = await grabLinksCommon(res, additionalSettings);

    if ((additionalSettings['apkFilterRegEx'] as String?)?.isNotEmpty == true) {
      var reg = RegExp(additionalSettings['apkFilterRegEx']);
      links = links.where((element) => reg.hasMatch(element.key)).toList();
    }
    if (links.isEmpty) {
      throw NoReleasesError();
    }
    var rel = links.last.key;
    String? version;
    if (additionalSettings['supportFixedAPKURL'] != true) {
      version = rel.hashCode.toString();
    }
    var versionExtractionRegEx =
        additionalSettings['versionExtractionRegEx'] as String?;
    if (versionExtractionRegEx?.isNotEmpty == true) {
      var match = RegExp(versionExtractionRegEx!).allMatches(
          additionalSettings['versionExtractWholePage'] == true
              ? res.body.split('\r\n').join('\n').split('\n').join('\\n')
              : rel);
      if (match.isEmpty) {
        throw NoVersionError();
      }
      String matchGroupString =
          (additionalSettings['matchGroupToUse'] as String).trim();
      if (matchGroupString.isEmpty) {
        matchGroupString = "0";
      }
      version = match.last.group(int.parse(matchGroupString));
      if (version?.isEmpty == true) {
        throw NoVersionError();
      }
    }
    rel = ensureAbsoluteUrl(rel, uri);
    version ??= (await checkDownloadHash(rel)).toString();
    return APKDetails(version, [rel].map((e) => MapEntry(e, e)).toList(),
        AppNames(uri.host, tr('app')));
  }
}
