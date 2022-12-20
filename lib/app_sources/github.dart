import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

class GitHub extends AppSource {
  GitHub() {
    host = 'github.com';

    additionalSourceSpecificSettingFormItems = [
      GeneratedFormItem('github-creds',
          label: tr('githubPATLabel'),
          required: false,
          additionalValidators: [
            (value) {
              if (value != null && value.trim().isNotEmpty) {
                if (value
                        .split(':')
                        .where((element) => element.trim().isNotEmpty)
                        .length !=
                    2) {
                  return tr('githubPATHint');
                }
              }
              return null;
            }
          ],
          hint: tr('githubPATFormat'),
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
                child: Text(
                  tr('githubPATLinkText'),
                  style: const TextStyle(
                      decoration: TextDecoration.underline, fontSize: 12),
                ))
          ])
    ];

    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormItem('includePrereleases',
            label: tr('includePrereleases'),
            type: FormItemType.bool,
            defaultValue: '')
      ],
      [
        GeneratedFormItem('fallbackToOlderReleases',
            label: tr('fallbackToOlderReleases'),
            type: FormItemType.bool,
            defaultValue: 'true')
      ],
      [
        GeneratedFormItem('filterReleaseTitlesByRegEx',
            label: tr('filterReleaseTitlesByRegEx'),
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
                  return tr('invalidRegEx');
                }
                return null;
              }
            ])
      ]
    ];

    canSearch = true;
  }

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/[^/]+/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
  }

  Future<String> getCredentialPrefixIfAny() async {
    SettingsProvider settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    String? creds = settingsProvider
        .getSettingString(additionalSourceSpecificSettingFormItems[0].key);
    return creds != null && creds.isNotEmpty ? '$creds@' : '';
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/releases';

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, String> additionalSettings,
  ) async {
    var includePrereleases = additionalSettings['includePrereleases'] == 'true';
    var fallbackToOlderReleases =
        additionalSettings['fallbackToOlderReleases'] == 'true';
    var regexFilter =
        additionalSettings['filterReleaseTitlesByRegEx']?.isNotEmpty == true
            ? additionalSettings['filterReleaseTitlesByRegEx']
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
                .hasMatch((releases[i]['name'] as String).trim())) {
          continue;
        }
        var apkUrls = getReleaseAPKUrls(releases[i]);
        if (apkUrls.isEmpty && additionalSettings['trackOnly'] != 'true') {
          continue;
        }
        targetRelease = releases[i];
        targetRelease['apkUrls'] = apkUrls;
        break;
      }
      if (targetRelease == null) {
        throw NoReleasesError();
      }
      String? version = targetRelease['tag_name'];
      if (version == null) {
        throw NoVersionError();
      }
      return APKDetails(version, targetRelease['apkUrls'] as List<String>,
          getAppNames(standardUrl));
    } else {
      rateLimitErrorCheck(res);
      throw getObtainiumHttpError(res);
    }
  }

  AppNames getAppNames(String standardUrl) {
    String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    List<String> names = temp.substring(temp.indexOf('/') + 1).split('/');
    return AppNames(names[0], names[1]);
  }

  @override
  Future<Map<String, String>> search(String query) async {
    Response res = await get(Uri.parse(
        'https://${await getCredentialPrefixIfAny()}api.$host/search/repositories?q=${Uri.encodeQueryComponent(query)}&per_page=100'));
    if (res.statusCode == 200) {
      Map<String, String> urlsWithDescriptions = {};
      for (var e in (jsonDecode(res.body)['items'] as List<dynamic>)) {
        urlsWithDescriptions.addAll({
          e['html_url'] as String: e['description'] != null
              ? e['description'] as String
              : tr('noDescription')
        });
      }
      return urlsWithDescriptions;
    } else {
      rateLimitErrorCheck(res);
      throw getObtainiumHttpError(res);
    }
  }

  rateLimitErrorCheck(Response res) {
    if (res.headers['x-ratelimit-remaining'] == '0') {
      throw RateLimitError(
          (int.parse(res.headers['x-ratelimit-reset'] ?? '1800000000') /
                  60000000)
              .round());
    }
  }
}
