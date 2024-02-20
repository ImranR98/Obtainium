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
    hosts = ['gitlab.com'];
    canSearch = true;
    showReleaseDateAsVersionToggle = true;

    sourceConfigSettingFormItems = [
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
    RegExp standardUrlRegEx = RegExp(
        '^https?://(www\\.)?${getSourceRegex(hosts)}/[^/]+/[^/]+',
        caseSensitive: false);
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  Future<String?> getPATIfAny(Map<String, dynamic> additionalSettings) async {
    SettingsProvider settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    var sourceConfig =
        await getSourceConfigValues(additionalSettings, settingsProvider);
    String? creds = sourceConfig['gitlab-creds'];
    return creds != null && creds.isNotEmpty ? creds : null;
  }

  @override
  Future<String?> getSourceNote() async {
    if ((await getPATIfAny({})) == null) {
      return '${tr('gitlabSourceNote')} ${hostChanged ? tr('addInfoBelow') : tr('addInfoInSettings')}';
    }
    return null;
  }

  @override
  Future<Map<String, List<String>>> search(String query,
      {Map<String, dynamic> querySettings = const {}}) async {
    var url =
        'https://${hosts[0]}/api/v4/projects?search=${Uri.encodeQueryComponent(query)}';
    var res = await sourceRequest(url, {});
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var json = jsonDecode(res.body) as List<dynamic>;
    Map<String, List<String>> results = {};
    for (var element in json) {
      results['https://${hosts[0]}/${element['path_with_namespace']}'] = [
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
    String? PAT = await getPATIfAny(hostChanged ? additionalSettings : {});
    Iterable<APKDetails> apkDetailsList = [];
    if (PAT != null) {
      var names = GitHub().getAppNames(standardUrl);
      Response res = await sourceRequest(
          'https://${hosts[0]}/api/v4/projects/${names.author}%2F${names.name}/releases?private_token=$PAT',
          additionalSettings);
      if (res.statusCode != 200) {
        throw getObtainiumHttpError(res);
      }
      var json = jsonDecode(res.body) as List<dynamic>;
      apkDetailsList = json.map((e) {
        var apkUrlsFromAssets = (e['assets']?['links'] as List<dynamic>? ?? [])
            .map((e) {
              return (e['direct_asset_url'] ?? e['url'] ?? '') as String;
            })
            .where((s) => s.isNotEmpty)
            .toList();
        List<String> uploadedAPKsFromDescription =
            ((e['description'] ?? '') as String)
                .split('](')
                .join('\n')
                .split('.apk)')
                .join('.apk\n')
                .split('\n')
                .where((s) => s.startsWith('/uploads/') && s.endsWith('apk'))
                .map((s) => '$standardUrl$s')
                .toList();
        var apkUrlsSet = apkUrlsFromAssets.toSet();
        apkUrlsSet.addAll(uploadedAPKsFromDescription);
        var releaseDateString = e['released_at'] ?? e['created_at'];
        DateTime? releaseDate = releaseDateString != null
            ? DateTime.parse(releaseDateString)
            : null;
        return APKDetails(
            e['tag_name'] ?? e['name'],
            getApkUrlsFromUrls(apkUrlsSet.toList()),
            GitHub().getAppNames(standardUrl),
            releaseDate: releaseDate);
      });
    } else {
      Response res = await sourceRequest(
          '$standardUrl/-/tags?format=atom', additionalSettings);
      if (res.statusCode != 200) {
        throw getObtainiumHttpError(res);
      }
      var standardUri = Uri.parse(standardUrl);
      var parsedHtml = parse(res.body);
      apkDetailsList = parsedHtml.querySelectorAll('entry').map((entry) {
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
    }
    if (apkDetailsList.isEmpty) {
      throw NoReleasesError(note: tr('gitlabSourceNote'));
    }
    if (fallbackToOlderReleases) {
      if (additionalSettings['trackOnly'] != true) {
        apkDetailsList =
            apkDetailsList.where((e) => e.apkUrls.isNotEmpty).toList();
      }
      if (apkDetailsList.isEmpty) {
        throw NoReleasesError(note: tr('gitlabSourceNote'));
      }
    }
    return apkDetailsList.first;
  }
}
