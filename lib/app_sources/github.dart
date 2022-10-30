import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

class GitHub implements AppSource {
  @override
  late String host = 'github.com';

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/[^/]+/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw notValidURL(runtimeType.toString());
    }
    return url.substring(0, match.end);
  }

  Future<String> getCredentialPrefixIfAny() async {
    SettingsProvider settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    String? creds =
        settingsProvider.getSettingString(moreSourceSettingsFormItems[0].id);
    return creds != null && creds.isNotEmpty ? '$creds@' : '';
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/releases';

  @override
  Future<String> apkUrlPrefetchModifier(String apkUrl) async => apkUrl;

  @override
  Future<APKDetails> getLatestAPKDetails(
      String standardUrl, List<String> additionalData) async {
    var includePrereleases =
        additionalData.isNotEmpty && additionalData[0] == 'true';
    var fallbackToOlderReleases =
        additionalData.length >= 2 && additionalData[1] == 'true';
    var regexFilter = additionalData.length >= 3 && additionalData[2].isNotEmpty
        ? additionalData[2]
        : null;
    Response res = await get(Uri.parse(
        'https://${await getCredentialPrefixIfAny()}api.$host/repos${standardUrl.substring('https://$host'.length)}/releases'));
    if (res.statusCode == 200) {
      var releases = jsonDecode(res.body) as List<dynamic>;

      List<String> getReleaseAPKUrls(dynamic release) =>
          (release['assets'] as List<dynamic>?)
              ?.map((e) {
                return e['browser_download_url'] != null
                    ? e['browser_download_url'] as String
                    : '';
              })
              .where((element) => element.toLowerCase().endsWith('.apk'))
              .toList() ??
          [];

      dynamic targetRelease;

      for (int i = 0; i < releases.length; i++) {
        if (!fallbackToOlderReleases && i > 0) break;
        if (!includePrereleases && releases[i]['prerelease'] == true) {
          continue;
        }

        if (regexFilter != null &&
            !RegExp(regexFilter)
                .hasMatch((releases[i]['tag_name'] as String).trim())) {
          continue;
        }
        var apkUrls = getReleaseAPKUrls(releases[i]);
        if (apkUrls.isEmpty) {
          continue;
        }
        targetRelease = releases[i];
        targetRelease['apkUrls'] = apkUrls;
        break;
      }
      if (targetRelease == null) {
        throw couldNotFindReleases;
      }
      if ((targetRelease['apkUrls'] as List<String>).isEmpty) {
        throw noAPKFound;
      }
      String? version = targetRelease['tag_name'];
      if (version == null) {
        throw couldNotFindLatestVersion;
      }
      return APKDetails(version, targetRelease['apkUrls']);
    } else {
      if (res.headers['x-ratelimit-remaining'] == '0') {
        throw RateLimitError(
            (int.parse(res.headers['x-ratelimit-reset'] ?? '1800000000') /
                    60000000)
                .round());
      }

      throw couldNotFindReleases;
    }
  }

  @override
  AppNames getAppNames(String standardUrl) {
    String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    List<String> names = temp.substring(temp.indexOf('/') + 1).split('/');
    return AppNames(names[0], names[1]);
  }

  @override
  List<List<GeneratedFormItem>> additionalDataFormItems = [
    [GeneratedFormItem(label: 'Include prereleases', type: FormItemType.bool)],
    [
      GeneratedFormItem(
          label: 'Fallback to older releases', type: FormItemType.bool)
    ],
    [
      GeneratedFormItem(
          label: 'Filter Release Titles by Regular Expression',
          type: FormItemType.string,
          required: false,
          additionalValidators: [
            (value) {
              if (value == null || value.isEmpty) {
                return null;
              }
              try {
                RegExp(value);
              } catch (e) {
                return 'Invalid regular expression';
              }
              return null;
            }
          ])
    ]
  ];

  @override
  List<String> additionalDataDefaults = ['true', 'true', ''];

  @override
  List<GeneratedFormItem> moreSourceSettingsFormItems = [
    GeneratedFormItem(
        label: 'GitHub Personal Access Token (Increases Rate Limit)',
        id: 'github-creds',
        required: false,
        additionalValidators: [
          (value) {
            if (value != null && value.trim().isNotEmpty) {
              if (value
                      .split(':')
                      .where((element) => element.trim().isNotEmpty)
                      .length !=
                  2) {
                return 'PAT must be in this format: username:token';
              }
            }
            return null;
          }
        ],
        hint: 'username:token',
        belowWidgets: [
          const SizedBox(
            height: 8,
          ),
          GestureDetector(
              onTap: () {
                launchUrlString(
                    'https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token',
                    mode: LaunchMode.externalApplication);
              },
              child: const Text(
                'About GitHub PATs',
                style: TextStyle(
                    decoration: TextDecoration.underline, fontSize: 12),
              ))
        ])
  ];
}
