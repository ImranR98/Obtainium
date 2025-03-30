import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

class APKMirror extends AppSource {
  APKMirror() {
    hosts = ['apkmirror.com'];
    enforceTrackOnly = true;
    showReleaseDateAsVersionToggle = true;

    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormSwitch('fallbackToOlderReleases',
            label: tr('fallbackToOlderReleases'), defaultValue: true)
      ],
      [
        GeneratedFormTextField('filterReleaseTitlesByRegEx',
            label: tr('filterReleaseTitlesByRegEx'),
            required: false,
            additionalValidators: [
              (value) {
                return regExValidator(value);
              }
            ])
      ]
    ];
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
      Map<String, dynamic> additionalSettings,
      {bool forAPKDownload = false}) async {
    return {
      "User-Agent":
          "Obtainium/${(await getInstalledInfo(obtainiumId))?.versionName ?? '1.0.0'}"
    };
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegEx = RegExp(
        '^https?://(www\\.)?${getSourceRegex(hosts)}/apk/[^/]+/[^/]+',
        caseSensitive: false);
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/#whatsnew';

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    bool fallbackToOlderReleases =
        additionalSettings['fallbackToOlderReleases'] == true;
    String? regexFilter =
        (additionalSettings['filterReleaseTitlesByRegEx'] as String?)
                    ?.isNotEmpty ==
                true
            ? additionalSettings['filterReleaseTitlesByRegEx']
            : null;
    Response res =
        await sourceRequest('$standardUrl/feed/', additionalSettings);
    if (res.statusCode == 200) {
      var items = parse(res.body).querySelectorAll('item');
      dynamic targetRelease;
      for (int i = 0; i < items.length; i++) {
        if (!fallbackToOlderReleases && i > 0) break;
        String? nameToFilter = items[i].querySelector('title')?.innerHtml;
        if (regexFilter != null &&
            nameToFilter != null &&
            !RegExp(regexFilter).hasMatch(nameToFilter.trim())) {
          continue;
        }
        targetRelease = items[i];
        break;
      }
      String? titleString = targetRelease?.querySelector('title')?.innerHtml;
      String? dateString = targetRelease
          ?.querySelector('pubDate')
          ?.innerHtml
          .split(' ')
          .sublist(0, 5)
          .join(' ');
      DateTime? releaseDate =
          dateString != null ? HttpDate.parse('$dateString GMT') : null;
      String? version = titleString
          ?.substring(RegExp('[0-9]').firstMatch(titleString)?.start ?? 0,
              RegExp(' by ').allMatches(titleString).last.start)
          .trim();
      if (version == null || version.isEmpty) {
        version = titleString;
      }
      if (version == null || version.isEmpty) {
        throw NoVersionError();
      }
      return APKDetails(version, [], getAppNames(standardUrl),
          releaseDate: releaseDate);
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  AppNames getAppNames(String standardUrl) {
    String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    List<String> names = temp.substring(temp.indexOf('/') + 1).split('/');
    return AppNames(names[1], names[2]);
  }
}
