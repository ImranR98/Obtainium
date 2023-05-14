import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

class GitHub extends AppSource {
  GitHub() {
    host = 'github.com';

    additionalSourceSpecificSettingFormItems = [
      GeneratedFormTextField('github-creds',
          label: tr('githubPATLabel'),
          password: true,
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
              height: 4,
            ),
            GestureDetector(
                onTap: () {
                  launchUrlString(
                      'https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token',
                      mode: LaunchMode.externalApplication);
                },
                child: Text(
                  tr('about'),
                  style: const TextStyle(
                      decoration: TextDecoration.underline, fontSize: 12),
                )),
            const SizedBox(
              height: 4,
            ),
          ])
    ];

    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormSwitch('includePrereleases',
            label: tr('includePrereleases'), defaultValue: false)
      ],
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

    canSearch = true;
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

  Future<APKDetails> getLatestAPKDetailsCommon(String requestUrl,
      String standardUrl, Map<String, dynamic> additionalSettings,
      {Function(Response)? onHttpErrorCode}) async {
    bool includePrereleases = additionalSettings['includePrereleases'] == true;
    bool fallbackToOlderReleases =
        additionalSettings['fallbackToOlderReleases'] == true;
    String? regexFilter =
        (additionalSettings['filterReleaseTitlesByRegEx'] as String?)
                    ?.isNotEmpty ==
                true
            ? additionalSettings['filterReleaseTitlesByRegEx']
            : null;
    Response res = await sourceRequest(requestUrl);
    if (res.statusCode == 200) {
      var releases = jsonDecode(res.body) as List<dynamic>;

      List<MapEntry<String, String>> getReleaseAPKUrls(dynamic release) =>
          (release['assets'] as List<dynamic>?)
              ?.map((e) {
                return e['name'] != null && e['browser_download_url'] != null
                    ? MapEntry(e['name'] as String,
                        e['browser_download_url'] as String)
                    : const MapEntry('', '');
              })
              .where((element) => element.key.toLowerCase().endsWith('.apk'))
              .toList() ??
          [];

      DateTime? getReleaseDateFromRelease(dynamic rel) =>
          rel?['published_at'] != null
              ? DateTime.parse(rel['published_at'])
              : null;
      releases.sort((a, b) {
        // See #478 and #534
        if (a == b) {
          return 0;
        } else if (a == null) {
          return -1;
        } else if (b == null) {
          return 1;
        } else {
          var nameA = a['tag_name'] ?? a['name'];
          var nameB = b['tag_name'] ?? b['name'];
          var stdFormats = findStandardFormatsForVersion(nameA, true)
              .intersection(findStandardFormatsForVersion(nameB, true));
          if (stdFormats.isNotEmpty) {
            var reg = RegExp(stdFormats.first);
            var matchA = reg.firstMatch(nameA);
            var matchB = reg.firstMatch(nameB);
            return compareAlphaNumeric(
                (nameA as String).substring(matchA!.start, matchA.end),
                (nameB as String).substring(matchB!.start, matchB.end));
          } else {
            return getReleaseDateFromRelease(a)!
                .compareTo(getReleaseDateFromRelease(b)!);
          }
        }
      });
      releases = releases.reversed.toList();
      dynamic targetRelease;
      var prerrelsSkipped = 0;
      for (int i = 0; i < releases.length; i++) {
        if (!fallbackToOlderReleases && i > prerrelsSkipped) break;
        if (!includePrereleases && releases[i]['prerelease'] == true) {
          prerrelsSkipped++;
          continue;
        }
        if (releases[i]['draft'] == true) {
          // Draft releases not supported
          continue;
        }
        var nameToFilter = releases[i]['name'] as String?;
        if (nameToFilter == null || nameToFilter.trim().isEmpty) {
          // Some leave titles empty so tag is used
          nameToFilter = releases[i]['tag_name'] as String;
        }
        if (regexFilter != null &&
            !RegExp(regexFilter).hasMatch(nameToFilter.trim())) {
          continue;
        }
        var apkUrls = getReleaseAPKUrls(releases[i]);
        if (apkUrls.isEmpty && additionalSettings['trackOnly'] != true) {
          continue;
        }
        targetRelease = releases[i];
        targetRelease['apkUrls'] = apkUrls;
        break;
      }
      if (targetRelease == null) {
        throw NoReleasesError();
      }
      String? version = targetRelease['tag_name'] ?? targetRelease['name'];
      DateTime? releaseDate = getReleaseDateFromRelease(targetRelease);
      if (version == null) {
        throw NoVersionError();
      }
      var changeLog = targetRelease['body'].toString();
      return APKDetails(
          version,
          targetRelease['apkUrls'] as List<MapEntry<String, String>>,
          getAppNames(standardUrl),
          releaseDate: releaseDate,
          changeLog: changeLog.isEmpty ? null : changeLog);
    } else {
      if (onHttpErrorCode != null) {
        onHttpErrorCode(res);
      }
      throw getObtainiumHttpError(res);
    }
  }

  getLatestAPKDetailsCommon2(
      String standardUrl,
      Map<String, dynamic> additionalSettings,
      Future<String> Function(bool) reqUrlGenerator,
      dynamic Function(Response)? onHttpErrorCode) async {
    try {
      return await getLatestAPKDetailsCommon(
          await reqUrlGenerator(false), standardUrl, additionalSettings,
          onHttpErrorCode: onHttpErrorCode);
    } catch (err) {
      if (err is NoReleasesError && additionalSettings['trackOnly'] == true) {
        return await getLatestAPKDetailsCommon(
            await reqUrlGenerator(true), standardUrl, additionalSettings,
            onHttpErrorCode: onHttpErrorCode);
      } else {
        rethrow;
      }
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    return await getLatestAPKDetailsCommon2(standardUrl, additionalSettings,
        (bool useTagUrl) async {
      return 'https://${await getCredentialPrefixIfAny()}api.$host/repos${standardUrl.substring('https://$host'.length)}/${useTagUrl ? 'tags' : 'releases'}?per_page=100';
    }, (Response res) {
      rateLimitErrorCheck(res);
    });
  }

  AppNames getAppNames(String standardUrl) {
    String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    List<String> names = temp.substring(temp.indexOf('/') + 1).split('/');
    return AppNames(names[0], names[1]);
  }

  Future<Map<String, List<String>>> searchCommon(
      String query, String requestUrl, String rootProp,
      {Function(Response)? onHttpErrorCode}) async {
    Response res = await sourceRequest(requestUrl);
    if (res.statusCode == 200) {
      Map<String, List<String>> urlsWithDescriptions = {};
      for (var e in (jsonDecode(res.body)[rootProp] as List<dynamic>)) {
        urlsWithDescriptions.addAll({
          e['html_url'] as String: [
            e['full_name'] as String,
            ((e['archived'] == true ? '[ARCHIVED] ' : '') +
                (e['description'] != null
                    ? e['description'] as String
                    : tr('noDescription')))
          ]
        });
      }
      return urlsWithDescriptions;
    } else {
      if (onHttpErrorCode != null) {
        onHttpErrorCode(res);
      }
      throw getObtainiumHttpError(res);
    }
  }

  @override
  Future<Map<String, List<String>>> search(String query) async {
    return searchCommon(
        query,
        'https://${await getCredentialPrefixIfAny()}api.$host/search/repositories?q=${Uri.encodeQueryComponent(query)}&per_page=100',
        'items', onHttpErrorCode: (Response res) {
      rateLimitErrorCheck(res);
    });
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
