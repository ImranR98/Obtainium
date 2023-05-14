import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher_string.dart';

class GitLab extends AppSource {
  GitLab() {
    host = 'gitlab.com';
    canSearch = true;

    additionalSourceSpecificSettingFormItems = [
      GeneratedFormTextField('gitlab-creds',
          label: tr('gitlabPATLabel'),
          password: true,
          required: false,
          belowWidgets: [
            const SizedBox(
              height: 4,
            ),
            GestureDetector(
                onTap: () {
                  launchUrlString(
                      'https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html#create-a-personal-access-token',
                      mode: LaunchMode.externalApplication);
                },
                child: Text(
                  tr('about'),
                  style: const TextStyle(
                      decoration: TextDecoration.underline, fontSize: 12),
                )),
            const SizedBox(
              height: 4,
            )
          ])
    ];

    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormSwitch('fallbackToOlderReleases',
            label: tr('fallbackToOlderReleases'), defaultValue: true)
      ]
    ];
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/[^/]+/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
  }

  Future<String?> getPATIfAny() async {
    SettingsProvider settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    String? creds = settingsProvider
        .getSettingString(additionalSourceSpecificSettingFormItems[0].key);
    return creds != null && creds.isNotEmpty ? creds : null;
  }

  @override
  Future<Map<String, List<String>>> search(String query) async {
    String? PAT = await getPATIfAny();
    if (PAT == null) {
      throw CredsNeededError(name);
    }
    var url =
        'https://$host/api/v4/search?private_token=$PAT&scope=projects&search=${Uri.encodeQueryComponent(query)}';
    var res = await sourceRequest(url);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var json = jsonDecode(res.body) as List<dynamic>;
    Map<String, List<String>> results = {};
    for (var element in json) {
      results['https://$host/${element['path_with_namespace']}'] = [
        element['name_with_namespace'],
        element['description'] ?? tr('noDescription')
      ];
    }
    return results;
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/-/releases';

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    bool fallbackToOlderReleases =
        additionalSettings['fallbackToOlderReleases'] == true;
    Response res = await sourceRequest('$standardUrl/-/tags?format=atom');
    if (res.statusCode == 200) {
      var standardUri = Uri.parse(standardUrl);
      var parsedHtml = parse(res.body);
      var apkDetailsList = parsedHtml.querySelectorAll('entry').map((entry) {
        var entryContent = parse(
            parseFragment(entry.querySelector('content')!.innerHtml).text);
        var apkUrls = [
          ...getLinksFromParsedHTML(
              entryContent,
              RegExp(
                  '^${standardUri.path.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (x) {
                    return '\\${x[0]}';
                  })}/uploads/[^/]+/[^/]+\\.apk\$',
                  caseSensitive: false),
              standardUri.origin),
          // GitLab releases may contain links to externally hosted APKs
          ...getLinksFromParsedHTML(entryContent,
                  RegExp('/[^/]+\\.apk\$', caseSensitive: false), '')
              .where((element) => Uri.parse(element).host != '')
              .toList()
        ];

        var entryId = entry.querySelector('id')?.innerHtml;
        var version =
            entryId == null ? null : Uri.parse(entryId).pathSegments.last;
        var releaseDateString = entry.querySelector('updated')?.innerHtml;
        DateTime? releaseDate = releaseDateString != null
            ? DateTime.parse(releaseDateString)
            : null;
        if (version == null) {
          throw NoVersionError();
        }
        return APKDetails(version, getApkUrlsFromUrls(apkUrls),
            GitHub().getAppNames(standardUrl),
            releaseDate: releaseDate);
      });
      if (apkDetailsList.isEmpty) {
        throw NoReleasesError();
      }
      if (fallbackToOlderReleases) {
        if (additionalSettings['trackOnly'] != true) {
          apkDetailsList =
              apkDetailsList.where((e) => e.apkUrls.isNotEmpty).toList();
        }
        if (apkDetailsList.isEmpty) {
          throw NoReleasesError();
        }
      }
      return apkDetailsList.first;
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
