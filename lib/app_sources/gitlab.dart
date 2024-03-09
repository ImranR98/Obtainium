import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
  Future<Map<String, String>?> getRequestHeaders(
      Map<String, dynamic> additionalSettings,
      {bool forAPKDownload = false}) async {
    // Change headers to pacify, e.g. cloudflare protection
    // Related to: (#1397, #1389, #1384, #1382, #1381, #1380, #1359, #854, #785, #697)
    var headers = <String, String>{};
    headers[HttpHeaders.refererHeader] = 'https://${hosts[0]}';
    if (headers.isNotEmpty) {
      return headers;
    } else {
      return null;
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    // Prepare request params
    var names = GitHub().getAppNames(standardUrl);
    String? PAT = await getPATIfAny(hostChanged ? additionalSettings : {});
    String optionalAuth = (PAT != null) ? 'private_token=$PAT' : '';

    // Request data from REST API
    Response res = await sourceRequest(
        'https://${hosts[0]}/api/v4/projects/${names.author}%2F${names.name}/releases?$optionalAuth',
        additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }

    // Extract .apk details from received data
    Iterable<APKDetails> apkDetailsList = [];
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
    if (apkDetailsList.isEmpty) {
      throw NoReleasesError();
    }

    // Fallback procedure
    bool fallbackToOlderReleases =
        additionalSettings['fallbackToOlderReleases'] == true;
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
  }
}
