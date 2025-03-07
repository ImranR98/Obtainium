import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

class GitHub extends AppSource {
  GitHub() {
    hosts = ['github.com'];
    appIdInferIsOptional = true;
    showReleaseDateAsVersionToggle = true;

    sourceConfigSettingFormItems = [
      GeneratedFormTextField('github-creds',
          label: tr('githubPATLabel'),
          password: true,
          required: false,
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
      ],
      [
        GeneratedFormTextField('filterReleaseNotesByRegEx',
            label: tr('filterReleaseNotesByRegEx'),
            required: false,
            additionalValidators: [
              (value) {
                return regExValidator(value);
              }
            ])
      ],
      [GeneratedFormSwitch('verifyLatestTag', label: tr('verifyLatestTag'))],
      [
        GeneratedFormDropdown(
            'sortMethodChoice',
            [
              MapEntry('date', tr('releaseDate')),
              MapEntry('smartname', tr('smartname')),
              MapEntry('none', tr('none')),
              MapEntry('smartname-datefallback',
                  '${tr('smartname')} x ${tr('releaseDate')}'),
              MapEntry('name', tr('name')),
            ],
            label: tr('sortMethod'),
            defaultValue: 'date')
      ],
      [
        GeneratedFormSwitch('useLatestAssetDateAsReleaseDate',
            label: tr('useLatestAssetDateAsReleaseDate'), defaultValue: false)
      ],
      [
        GeneratedFormSwitch('releaseTitleAsVersion',
            label: tr('releaseTitleAsVersion'), defaultValue: false)
      ]
    ];

    canSearch = true;
    searchQuerySettingFormItems = [
      GeneratedFormTextField('minStarCount',
          label: tr('minStarCount'),
          defaultValue: '0',
          additionalValidators: [
            (value) {
              try {
                int.parse(value ?? '0');
              } catch (e) {
                return tr('invalidInput');
              }
              return null;
            }
          ])
    ];
  }

  @override
  Future<String?> tryInferringAppId(String standardUrl,
      {Map<String, dynamic> additionalSettings = const {}}) async {
    const possibleBuildGradleLocations = [
      '/app/build.gradle',
      'android/app/build.gradle',
      'src/app/build.gradle'
    ];
    for (var path in possibleBuildGradleLocations) {
      try {
        var res = await sourceRequest(
            '${await convertStandardUrlToAPIUrl(standardUrl, additionalSettings)}/contents/$path',
            additionalSettings);
        if (res.statusCode == 200) {
          try {
            var body = jsonDecode(res.body);
            var trimmedLines = utf8
                .decode(base64
                    .decode(body['content'].toString().split('\n').join('')))
                .split('\n')
                .map((e) => e.trim());
            var appIds = trimmedLines.where((l) =>
                l.startsWith('applicationId "') ||
                l.startsWith('applicationId \''));
            appIds = appIds.map((appId) => appId
                .split(appId.startsWith('applicationId "') ? '"' : '\'')[1]);
            appIds = appIds.map((appId) {
              if (appId.startsWith('\${') && appId.endsWith('}')) {
                appId = trimmedLines
                    .where((l) => l.startsWith(
                        'def ${appId.substring(2, appId.length - 1)}'))
                    .first;
                appId = appId.split(appId.contains('"') ? '"' : '\'')[1];
              }
              return appId;
            }).where((appId) => appId.isNotEmpty);
            if (appIds.length == 1) {
              return appIds.first;
            }
          } catch (err) {
            LogsProvider().add(
                'Error parsing build.gradle from ${res.request!.url.toString()}: ${err.toString()}');
          }
        }
      } catch (err) {
        // Ignore - ID will be extracted from the APK
      }
    }
    return null;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegEx = RegExp(
        '^https?://(www\\.)?${getSourceRegex(hosts)}/[^/]+/[^/]+',
        caseSensitive: false);
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
      Map<String, dynamic> additionalSettings,
      {bool forAPKDownload = false}) async {
    var token = await getTokenIfAny(additionalSettings);
    var headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Token $token';
    }
    if (forAPKDownload == true) {
      headers[HttpHeaders.acceptHeader] = 'application/octet-stream';
    }
    if (headers.isNotEmpty) {
      return headers;
    } else {
      return null;
    }
  }

  Future<String?> getTokenIfAny(Map<String, dynamic> additionalSettings) async {
    SettingsProvider settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    var sourceConfig =
        await getSourceConfigValues(additionalSettings, settingsProvider);
    String? creds = sourceConfig['github-creds'];
    if (creds != null) {
      var userNameEndIndex = creds.indexOf(':');
      if (userNameEndIndex > 0) {
        creds = creds.substring(
            userNameEndIndex + 1); // For old username-included token inputs
      }
      return creds;
    } else {
      return null;
    }
  }

  @override
  Future<String?> getSourceNote() async {
    if (!hostChanged && (await getTokenIfAny({})) == null) {
      return '${tr('githubSourceNote')} ${hostChanged ? tr('addInfoBelow') : tr('addInfoInSettings')}';
    }
    return null;
  }

  Future<String> getAPIHost(Map<String, dynamic> additionalSettings) async =>
      'https://api.${hosts[0]}';

  Future<String> convertStandardUrlToAPIUrl(
          String standardUrl, Map<String, dynamic> additionalSettings) async =>
      '${await getAPIHost(additionalSettings)}/repos${standardUrl.substring('https://${hosts[0]}'.length)}';

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
    String? regexNotesFilter =
        (additionalSettings['filterReleaseNotesByRegEx'] as String?)
                    ?.isNotEmpty ==
                true
            ? additionalSettings['filterReleaseNotesByRegEx']
            : null;
    bool verifyLatestTag = additionalSettings['verifyLatestTag'] == true;
    bool useLatestAssetDateAsReleaseDate =
        additionalSettings['useLatestAssetDateAsReleaseDate'] == true;
    String sortMethod =
        additionalSettings['sortMethodChoice'] ?? 'smartname-datefallback';
    dynamic latestRelease;
    if (verifyLatestTag) {
      var temp = requestUrl.split('?');
      Response res = await sourceRequest(
          '${temp[0]}/latest${temp.length > 1 ? '?${temp.sublist(1).join('?')}' : ''}',
          additionalSettings);
      if (res.statusCode != 200) {
        if (onHttpErrorCode != null) {
          onHttpErrorCode(res);
        }
        throw getObtainiumHttpError(res);
      }
      latestRelease = jsonDecode(res.body);
    }
    Response res = await sourceRequest(requestUrl, additionalSettings);
    if (res.statusCode == 200) {
      var releases = jsonDecode(res.body) as List<dynamic>;
      if (latestRelease != null) {
        var latestTag = latestRelease['tag_name'] ?? latestRelease['name'];
        if (releases
            .where((element) =>
                (element['tag_name'] ?? element['name']) == latestTag)
            .isEmpty) {
          releases = [latestRelease, ...releases];
        }
      }

      findReleaseAssetUrls(dynamic release) =>
          (release['assets'] as List<dynamic>?)?.map((e) {
            var url = !e['name'].toString().toLowerCase().endsWith('.apk')
                ? (e['browser_download_url'] ?? e['url'])
                : (e['url'] ?? e['browser_download_url']);
            e['final_url'] = (e['name'] != null) && (url != null)
                ? MapEntry(e['name'] as String, url as String)
                : const MapEntry('', '');
            return e;
          }).toList() ??
          [];

      DateTime? getPublishDateFromRelease(dynamic rel) =>
          rel?['published_at'] != null
              ? DateTime.parse(rel['published_at'])
              : rel?['commit']?['created'] != null
                  ? DateTime.parse(rel['commit']['created'])
                  : null;
      DateTime? getNewestAssetDateFromRelease(dynamic rel) {
        var allAssets = rel['assets'] as List<dynamic>?;
        var filteredAssets = rel['filteredAssets'] as List<dynamic>?;
        var t = (filteredAssets ?? allAssets)
            ?.map((e) {
              return e?['updated_at'] != null
                  ? DateTime.parse(e['updated_at'])
                  : null;
            })
            .where((e) => e != null)
            .toList();
        t?.sort((a, b) => b!.compareTo(a!));
        if (t?.isNotEmpty == true) {
          return t!.first;
        }
        return null;
      }

      DateTime? getReleaseDateFromRelease(dynamic rel, bool useAssetDate) =>
          !useAssetDate
              ? getPublishDateFromRelease(rel)
              : getNewestAssetDateFromRelease(rel);

      if (sortMethod == 'none') {
        releases = releases.reversed.toList();
      } else {
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
            var stdFormats = findStandardFormatsForVersion(nameA, false)
                .intersection(findStandardFormatsForVersion(nameB, false));
            if (sortMethod == 'date' ||
                (sortMethod == 'smartname-datefallback' &&
                    stdFormats.isEmpty)) {
              return (getReleaseDateFromRelease(
                          a, useLatestAssetDateAsReleaseDate) ??
                      DateTime(1))
                  .compareTo(getReleaseDateFromRelease(
                          b, useLatestAssetDateAsReleaseDate) ??
                      DateTime(0));
            } else {
              if (sortMethod != 'name' && stdFormats.isNotEmpty) {
                var reg = RegExp(stdFormats.last);
                var matchA = reg.firstMatch(nameA);
                var matchB = reg.firstMatch(nameB);
                return compareAlphaNumeric(
                    (nameA as String).substring(matchA!.start, matchA.end),
                    (nameB as String).substring(matchB!.start, matchB.end));
              } else {
                // 'name'
                return compareAlphaNumeric(
                    (nameA as String), (nameB as String));
              }
            }
          }
        });
      }
      if (latestRelease != null &&
          (latestRelease['tag_name'] ?? latestRelease['name']) != null &&
          releases.isNotEmpty &&
          latestRelease !=
              (releases[releases.length - 1]['tag_name'] ??
                  releases[0]['name'])) {
        var ind = releases.indexWhere((element) =>
            (latestRelease['tag_name'] ?? latestRelease['name']) ==
            (element['tag_name'] ?? element['name']));
        if (ind >= 0) {
          releases.add(releases.removeAt(ind));
        }
      }
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
        if (regexNotesFilter != null &&
            !RegExp(regexNotesFilter)
                .hasMatch(((releases[i]['body'] as String?) ?? '').trim())) {
          continue;
        }
        var allAssetsWithUrls = findReleaseAssetUrls(releases[i]);
        List<MapEntry<String, String>> allAssetUrls = allAssetsWithUrls
            .map((e) => e['final_url'] as MapEntry<String, String>)
            .toList();
        var apkAssetsWithUrls = allAssetsWithUrls
            .where((element) =>
                (element['final_url'] as MapEntry<String, String>)
                    .key
                    .toLowerCase()
                    .endsWith('.apk'))
            .toList();

        var filteredApkUrls = filterApks(
            apkAssetsWithUrls
                .map((e) => e['final_url'] as MapEntry<String, String>)
                .toList(),
            additionalSettings['apkFilterRegEx'],
            additionalSettings['invertAPKFilter']);
        var filteredApks = apkAssetsWithUrls
            .where((e) => filteredApkUrls
                .where((e2) =>
                    e2.key == (e['final_url'] as MapEntry<String, String>).key)
                .isNotEmpty)
            .toList();

        if (filteredApks.isEmpty && additionalSettings['trackOnly'] != true) {
          continue;
        }
        targetRelease = releases[i];
        targetRelease['apkUrls'] = filteredApkUrls;
        targetRelease['filteredAssets'] = filteredApks;
        targetRelease['version'] =
            additionalSettings['releaseTitleAsVersion'] == true
                ? nameToFilter
                : targetRelease['tag_name'] ?? targetRelease['name'];
        if (targetRelease['tarball_url'] != null) {
          allAssetUrls.add(MapEntry(
              (targetRelease['version'] ?? 'source') + '.tar.gz',
              targetRelease['tarball_url']));
        }
        if (targetRelease['zipball_url'] != null) {
          allAssetUrls.add(MapEntry(
              (targetRelease['version'] ?? 'source') + '.zip',
              targetRelease['zipball_url']));
        }
        targetRelease['allAssetUrls'] = allAssetUrls;
        break;
      }
      if (targetRelease == null) {
        throw NoReleasesError();
      }
      String? version = targetRelease['version'];

      DateTime? releaseDate = getReleaseDateFromRelease(
          targetRelease, useLatestAssetDateAsReleaseDate);
      if (version == null) {
        throw NoVersionError();
      }
      var changeLog = (targetRelease['body'] ?? '').toString();
      return APKDetails(
          version,
          targetRelease['apkUrls'] as List<MapEntry<String, String>>,
          getAppNames(standardUrl),
          releaseDate: releaseDate,
          changeLog: changeLog.isEmpty ? null : changeLog,
          allAssetUrls:
              targetRelease['allAssetUrls'] as List<MapEntry<String, String>>);
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
      return '${await convertStandardUrlToAPIUrl(standardUrl, additionalSettings)}/${useTagUrl ? 'tags' : 'releases'}?per_page=100';
    }, (Response res) {
      rateLimitErrorCheck(res);
    });
  }

  AppNames getAppNames(String standardUrl) {
    String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    List<String> names = temp.substring(temp.indexOf('/') + 1).split('/');
    return AppNames(names[0], names.sublist(1).join('/'));
  }

  Future<Map<String, List<String>>> searchCommon(
      String query, String requestUrl, String rootProp,
      {Function(Response)? onHttpErrorCode,
      Map<String, dynamic> querySettings = const {}}) async {
    Response res = await sourceRequest(requestUrl, {});
    if (res.statusCode == 200) {
      int minStarCount = querySettings['minStarCount'] != null
          ? int.parse(querySettings['minStarCount'])
          : 0;
      Map<String, List<String>> urlsWithDescriptions = {};
      for (var e in (jsonDecode(res.body)[rootProp] as List<dynamic>)) {
        if ((e['stargazers_count'] ?? e['stars_count'] ?? 0) >= minStarCount) {
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
  Future<Map<String, List<String>>> search(String query,
      {Map<String, dynamic> querySettings = const {}}) async {
    return searchCommon(
        query,
        '${await getAPIHost({})}/search/repositories?q=${Uri.encodeQueryComponent(query)}&per_page=100',
        'items', onHttpErrorCode: (Response res) {
      rateLimitErrorCheck(res);
    }, querySettings: querySettings);
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
