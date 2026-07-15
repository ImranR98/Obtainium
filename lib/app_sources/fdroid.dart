import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/app_sources/gitlab.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/services/html_parse_isolate.dart';

/// Returns a trimmed, non-empty display String from an F-Droid metadata value.
///
/// F-Droid's packages API may report a name either as a plain String or as a
/// map of locale -> String (localized names). This drills into the map,
/// preferring English locales, and recurses into nested maps.
String? _fdroidDisplayString(Object? rawValue) {
  if (rawValue is String) {
    final String trimmed = rawValue.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (rawValue is Map) {
    for (final String localeKey in const <String>['en-US', 'en']) {
      final String? localized = _fdroidDisplayString(rawValue[localeKey]);
      if (localized != null) {
        return localized;
      }
    }
    for (final Object? value in rawValue.values) {
      final String? localized = _fdroidDisplayString(value);
      if (localized != null) {
        return localized;
      }
    }
  }
  return null;
}

/// Extracts a human-friendly app display name from an F-Droid package page's
/// HTML, preferring the `og:title` meta tag then the document `<title>`, and
/// dropping any trailing " | F-Droid" suffix.
String? _fdroidDisplayNameFromHtml(String html) {
  for (final RegExp pattern in <RegExp>[
    RegExp(
      r'''<meta\s+property=["']og:title["']\s+content=["']([^"']+)["']''',
      caseSensitive: false,
    ),
    RegExp(
      r'<title[^>]*>([^<]+)</title>',
      caseSensitive: false,
      multiLine: true,
    ),
  ]) {
    final RegExpMatch? match = pattern.firstMatch(html);
    final String? title = match?.group(1)?.trim();
    if (title?.isNotEmpty == true) {
      final String displayName = title!.split('|').first.trim();
      if (displayName.isNotEmpty) {
        return displayName;
      }
    }
  }
  return null;
}

class FDroid extends AppSource {
  static const _maxChangeLogCodeUnits = 2048;
  @override
  String get name => tr('fdroid');

  FDroid() {
    hosts = ['f-droid.org'];
    naiveStandardVersionDetection = true;
    canSearch = true;
    inferAppIdFromUrlPath = true;
  }

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
    [
      GeneratedFormTextField(
        'filterVersionsByRegEx',
        label: tr('filterVersionsByRegEx'),
        required: false,
        additionalValidators: [
          (value) {
            return regExValidator(value);
          },
        ],
      ),
    ],
    [
      GeneratedFormSwitch(
        'trySelectingSuggestedVersionCode',
        label: tr('trySelectingSuggestedVersionCode'),
        value: true,
      ),
    ],
    [
      GeneratedFormSwitch(
        'autoSelectHighestVersionCode',
        label: tr('autoSelectHighestVersionCode'),
      ),
    ],
    // Fork addition: reproducible-build verification. When enabled, updates are
    // blocked unless F-Droid confirms the published APK reproducibly matches the
    // binary built from source.
    [
      GeneratedFormSwitch(
        'enforceReproducibleBuilds',
        label: tr('enforceReproducibleBuilds'),
        labelTooltip: tr('reproducibleBuildsTooltip'),
        value: false,
      ),
    ],
  ];

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    final RegExp standardUrlRegExB = RegExp(
      '^https?://(www\\.)?${getSourceRegex(hosts)}/+[^/]+/+packages/+[^/]+',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegExB.firstMatch(url);
    if (match != null) {
      url =
          'https://${Uri.parse(match.group(0)!).host}/packages/${Uri.parse(url).pathSegments.where((s) => s.trim().isNotEmpty).last}';
    }
    final RegExp standardUrlRegExA = RegExp(
      '^https?://(www\\.)?${getSourceRegex(hosts)}/+packages/+[^/]+',
      caseSensitive: false,
    );
    match = standardUrlRegExA.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final String? appId = await tryInferringAppId(standardUrl);
      if (appId == null) {
        throw NoReleasesError();
      }
      final String host = Uri.parse(standardUrl).host;
      // Fetch the packages API response and hand it to
      // getAPKUrlsFromFDroidPackagesAPIResponse, which owns all parsing
      // (version selection, name/icon/APK-size resolution).
      final Response packagesResponse = await sourceRequest(
        'https://$host/api/v1/packages/$appId',
        additionalSettings,
      );
      final details = await getAPKUrlsFromFDroidPackagesAPIResponse(
        packagesResponse,
        'https://$host/repo/$appId',
        standardUrl,
        name,
        additionalSettings: additionalSettings,
      );
      // Fork addition (reproducible-build verification): skip the per-refresh
      // fdroiddata metadata YAML fetch (gitlab.com) only when the upstream
      // release is unchanged AND the cached verdict is the terminal 'verified'
      // state. An F-Droid build's reproducible status can flip from
      // no_data / not_reproducible to verified hours after a release WITHOUT a
      // versionCode change (the reproducible-build verification completes after
      // the initial publish). So every non-verified status must keep
      // re-checking to catch that flip; only 'verified' (which does not revert)
      // is reused. This is never worse than always fetching, and saves the call
      // for the already-verified majority.
      final App? prevApp = previouslyCheckedApp;
      final bool canReuseCachedMetadata =
          prevApp != null &&
          prevApp.rawLatestVersionFromSource != null &&
          prevApp.rawLatestVersionFromSource == details.version &&
          prevApp.latestReproducibleStatus == reproducibleBuildStatusVerified;
      // Fork addition (icon / APK size / display name): reuse the previous
      // check's icon, APK size and name whenever the upstream version is
      // unchanged. This is deliberately SEPARATE from canReuseCachedMetadata
      // above — it keys off the version alone and does NOT also require the
      // reproducible status to be 'verified', because icon/size/name never
      // change without a version change, whereas the reproducible verdict can.
      final bool versionUnchanged =
          prevApp != null &&
          prevApp.rawLatestVersionFromSource != null &&
          prevApp.rawLatestVersionFromSource == details.version;
      if (!hostChanged && canReuseCachedMetadata) {
        details.reproducibleStatus = prevApp.latestReproducibleStatus;
        details.isReproducible = reproducibleBuildBoolFromStatus(
          prevApp.latestReproducibleStatus,
        );
        if (prevApp.changeLog?.isNotEmpty == true) {
          details.changeLog = prevApp.changeLog;
        }
        if (prevApp.author.trim().isNotEmpty) {
          details.names.author = prevApp.author;
        }
      } else if (!hostChanged) {
        try {
          final res = await sourceRequest(
            'https://gitlab.com/fdroid/fdroiddata/-/raw/master/metadata/$appId.yml',
            additionalSettings,
          );
          if (res.statusCode != 200 &&
              details.reproducibleStatus != reproducibleBuildStatusVerified) {
            details.reproducibleStatus = reproducibleBuildStatusError;
            details.isReproducible = null;
          }
          if (res.statusCode == 200) {
            final lines = res.body.split('\n');
            final authorLines = lines.where(
              (l) => l.startsWith('AuthorName: '),
            );
            if (authorLines.isNotEmpty) {
              details.names.author = authorLines.first
                  .split(': ')
                  .sublist(1)
                  .join(': ');
            }
            // A non-empty top-level `Binaries:` field in the fdroiddata
            // metadata means F-Droid publishes and verifies a reproducible
            // build against the source for this app.
            final bool hasBinaries = lines.any((l) {
              final t = l.trim();
              return t.startsWith('Binaries:') &&
                  t.substring('Binaries:'.length).trim().isNotEmpty;
            });
            details.reproducibleStatus = hasBinaries
                ? reproducibleBuildStatusVerified
                : reproducibleBuildStatusNoData;
            details.isReproducible = reproducibleBuildBoolFromStatus(
              details.reproducibleStatus,
            );
            final changelogUrls = lines
                .where((l) => l.startsWith('Changelog: '))
                .map((e) => e.split(' ').sublist(1).join(' '));
            if (changelogUrls.isNotEmpty) {
              details.changeLog = changelogUrls.first;
              bool isGitHub = false;
              bool isGitLab = false;
              try {
                GitHub(
                  hostChanged: true,
                ).sourceSpecificStandardizeURL(details.changeLog!);
                isGitHub = true;
              } on InvalidURLError {
                // URL does not match GitHub format, silently skipped
              }
              try {
                GitLab(
                  hostChanged: true,
                ).sourceSpecificStandardizeURL(details.changeLog!);
                isGitLab = true;
              } on InvalidURLError {
                // URL does not match GitLab format, silently skipped
              }
              if ((isGitHub || isGitLab) &&
                  (details.changeLog?.indexOf('/blob/') ?? -1) >= 0) {
                details.changeLog = (await sourceRequest(
                  details.changeLog!.replaceFirst('/blob/', '/raw/'),
                  additionalSettings,
                )).body;
              }
            }
          }
        } catch (e) {
          // Any metadata failure demotes an unverified status to 'error' so it
          // keeps being re-checked; a prior 'verified' is preserved.
          if (details.reproducibleStatus != reproducibleBuildStatusVerified) {
            details.reproducibleStatus = reproducibleBuildStatusError;
            details.isReproducible = null;
          }
          unawaited(
            LogsProvider().add(
              'Failed to process changelog for F-Droid app: ${e.toString()}',
            ),
          );
        }
        if ((details.changeLog?.length ?? 0) > _maxChangeLogCodeUnits) {
          final cl = details.changeLog!;
          var end = _maxChangeLogCodeUnits;
          if (end > 0 &&
              cl.codeUnitAt(end - 1) >= 0xD800 &&
              cl.codeUnitAt(end - 1) <= 0xDBFF) {
            end--;
          }
          details.changeLog = '${cl.substring(0, end)}...';
        }
      }
      // Fork addition (icon / APK size / display name): on a fresh version
      // these are resolved inside getAPKUrlsFromFDroidPackagesAPIResponse above;
      // on a no-op refresh (version unchanged) that method skips the network, so
      // reuse the previous check's values here instead of clobbering them with
      // nulls. Gated on versionUnchanged alone (see above).
      if (versionUnchanged) {
        // Reuse — never clobber a good previous value with null.
        if (prevApp.iconUrl != null) {
          details.iconUrl = prevApp.iconUrl;
        }
        if (prevApp.apkSizeBytes != null) {
          details.apkSizeBytes = prevApp.apkSizeBytes;
        }
        if (prevApp.name.trim().isNotEmpty) {
          details.names.name = prevApp.name;
        }
      }
      return details;
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    final Response res = await sourceRequest(
      'https://search.${hosts[0]}/?q=${Uri.encodeQueryComponent(query)}',
      {},
    );
    if (res.statusCode == 200) {
      final Map<String, List<String>> urlsWithDescriptions = {};
      parse(res.body).querySelectorAll('.package-header').forEach((e) {
        String? url = e.attributes['href'];
        if (url != null) {
          try {
            standardizeUrl(url);
          } catch (e) {
            url = null;
          }
        }
        if (url != null) {
          urlsWithDescriptions[url] = [
            e.querySelector('.package-name')?.text.trim() ?? '',
            e.querySelector('.package-summary')?.text.trim() ??
                tr('noDescription'),
          ];
        }
      });
      return urlsWithDescriptions;
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  Future<APKDetails> getAPKUrlsFromFDroidPackagesAPIResponse(
    Response res,
    String apkUrlPrefix,
    String standardUrl,
    String sourceName, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    final autoSelectHighestVersionCode =
        additionalSettings['autoSelectHighestVersionCode'] == true;
    final trySelectingSuggestedVersionCode =
        additionalSettings['trySelectingSuggestedVersionCode'] == true;
    final filterVersionsByRegEx =
        (additionalSettings['filterVersionsByRegEx'] as String?)?.isNotEmpty ==
            true
        ? additionalSettings['filterVersionsByRegEx']
        : null;
    final apkFilterRegEx =
        (additionalSettings['apkFilterRegEx'] as String?)?.isNotEmpty == true
        ? additionalSettings['apkFilterRegEx']
        : null;
    if (res.statusCode == 200) {
      final response = jsonDecode(res.body);
      List<dynamic> releases = response['packages'] ?? [];
      if (apkFilterRegEx != null) {
        releases = releases.where((rel) {
          final String apk = '${apkUrlPrefix}_${rel['versionCode']}.apk';
          return filterApks(
            [MapEntry(apk, apk)],
            apkFilterRegEx,
            false,
          ).isNotEmpty;
        }).toList();
      }
      if (releases.isEmpty) {
        throw NoReleasesError();
      }
      // Deduped release version-name candidates for the RegEx-assist feature
      // (rawReleaseTitlesFromSource). Coerced to String — the F-Droid API
      // normally returns versionName as a string, but guard against numbers.
      final List<String> rawVersionNameCandidates = <String>[];
      for (final release in releases) {
        final String? versionName = release['versionName']?.toString().trim();
        if (versionName == null ||
            versionName.isEmpty ||
            rawVersionNameCandidates.contains(versionName)) {
          continue;
        }
        rawVersionNameCandidates.add(versionName);
      }
      String? version;
      Iterable<dynamic> releaseChoices = [];
      // Grab the versionCode suggested if the user chose to do that
      // Only do so at this stage if the user has no release filter
      if (trySelectingSuggestedVersionCode &&
          response['suggestedVersionCode'] != null &&
          filterVersionsByRegEx == null) {
        final String suggestedVersionCodeText = response['suggestedVersionCode']
            .toString();
        final suggestedReleases = releases.where(
          (element) =>
              element['versionCode'].toString() == suggestedVersionCodeText,
        );
        if (suggestedReleases.isNotEmpty) {
          releaseChoices = suggestedReleases;
          version = suggestedReleases.first['versionName']?.toString();
        }
      }
      // Apply the release filter if any
      if (filterVersionsByRegEx?.isNotEmpty == true) {
        version = null;
        releaseChoices = [];
        final versionFilter = RegExp(filterVersionsByRegEx!);
        for (var i = 0; i < releases.length; i++) {
          if (versionFilter.hasMatch(
            releases[i]['versionName']?.toString() ?? '',
          )) {
            version = releases[i]['versionName']?.toString();
            break;
          }
        }
        if (version == null || version.isEmpty) {
          throw NoVersionError();
        }
      }
      // Default to the highest version
      version ??= releases[0]['versionName']?.toString();
      if (version == null || version.isEmpty) {
        throw NoVersionError();
      }
      // If a suggested release was not already picked, pick all those with the selected version
      if (releaseChoices.isEmpty) {
        releaseChoices = releases.where(
          (element) => element['versionName']?.toString() == version,
        );
      }
      // For the remaining releases, use the toggles to auto-select one if possible
      if (releaseChoices.length > 1) {
        if (autoSelectHighestVersionCode) {
          releaseChoices = [releaseChoices.first];
        } else if (trySelectingSuggestedVersionCode &&
            response['suggestedVersionCode'] != null) {
          final String suggestedVersionCodeText =
              response['suggestedVersionCode'].toString();
          final suggestedReleases = releaseChoices.where(
            (element) =>
                element['versionCode'].toString() == suggestedVersionCodeText,
          );
          if (suggestedReleases.isNotEmpty) {
            releaseChoices = suggestedReleases;
          }
        }
      }
      if (releaseChoices.isEmpty) {
        throw NoReleasesError();
      }
      final List<String> apkUrls = releaseChoices
          .map((e) => '${apkUrlPrefix}_${e['versionCode']}.apk')
          .toList();
      final List<String> uniqueApkUrls = apkUrls.toSet().toList();
      // Fork addition (reproducible-build verification): derive an initial
      // status from the F-Droid packages API. A `binaries` field on the
      // response or the selected release indicates a reproducible build; this
      // may be refined to 'verified' by the fdroiddata metadata in
      // getLatestAPKDetails.
      final bool hasBinaries =
          response['binaries'] != null ||
          (releaseChoices.isNotEmpty &&
              releaseChoices.first['binaries'] != null);
      final String reproducibleStatus = hasBinaries
          ? reproducibleBuildStatusVerified
          : reproducibleBuildStatusNoData;
      // Skip the per-check APK-size HEAD and the package-page fetch (icon/name)
      // when the upstream version is unchanged since the last check. getApp()
      // reuses the previous apkSizeBytes / iconUrl / name in that case, so these
      // network round-trips would just be wasted work on a no-op refresh.
      final App? prevApp = previouslyCheckedApp;
      final bool versionUnchanged =
          prevApp != null &&
          prevApp.rawLatestVersionFromSource != null &&
          prevApp.rawLatestVersionFromSource == version;
      int? apkSizeBytes;
      if (uniqueApkUrls.isNotEmpty && !versionUnchanged) {
        try {
          final headers = await getRequestHeaders(
            additionalSettings,
            uniqueApkUrls.last,
            forAPKDownload: true,
          );
          final responseWithClient = await sourceRequestStreamResponse(
            'HEAD',
            uniqueApkUrls.last,
            headers,
            additionalSettings,
          );
          final headResponse = responseWithClient.value.value;
          final contentLength = headResponse.contentLength;
          if (headResponse.statusCode >= 200 &&
              headResponse.statusCode < 300 &&
              contentLength >= 0) {
            apkSizeBytes = contentLength;
          }
          responseWithClient.value.key.close();
        } catch (_) {
          // File size is optional; update detection should still succeed.
        }
      }
      // Display name resolution (readable-app-name): prefer the localized name
      // from the packages API, then the official package page's parsed/title
      // name; fall back to the package id last. Icon is picked up from the same
      // package page when available.
      String? iconUrl;
      final String packageLabel;
      final Object? rawPackageName = response['packageName'];
      if (rawPackageName is String && rawPackageName.trim().isNotEmpty) {
        packageLabel = rawPackageName.trim();
      } else {
        final String? queryAppId = Uri.parse(
          standardUrl,
        ).queryParameters['appId']?.trim();
        if (queryAppId != null && queryAppId.isNotEmpty) {
          packageLabel = queryAppId;
        } else {
          packageLabel = Uri.parse(standardUrl).pathSegments.last;
        }
      }
      String appName = _fdroidDisplayString(response['name']) ?? packageLabel;
      final String pageHost = Uri.parse(standardUrl).host;
      final bool canUseOfficialPackagePage =
          !hostChanged ||
          hostIdenticalDespiteAnyChange ||
          pageHost == 'f-droid.org' ||
          pageHost == 'www.f-droid.org';
      if (canUseOfficialPackagePage && !versionUnchanged) {
        try {
          final pkgName = packageLabel;
          if (pageHost == 'f-droid.org' || pageHost == 'www.f-droid.org') {
            final pageRes = await sourceRequest(
              'https://$pageHost/packages/$pkgName/',
              additionalSettings,
            );
            if (pageRes.statusCode == 200) {
              final String? htmlTitleName = _fdroidDisplayNameFromHtml(
                pageRes.body,
              );
              if (htmlTitleName?.isNotEmpty == true) {
                appName = htmlTitleName!;
              }
              final doc = await parseHtmlOffIsolate(pageRes.body);
              iconUrl =
                  doc
                      .querySelector('meta[property="og:image"]')
                      ?.attributes['content'] ??
                  doc.querySelector('img.package-icon')?.attributes['src'];
              final String? parsedName =
                  doc.querySelector('h1.package-name')?.text.trim() ??
                  doc.querySelector('h3.package-name')?.text.trim() ??
                  doc.querySelector('.package-title h1')?.text.trim() ??
                  doc.querySelector('.package-title h3')?.text.trim();
              if (parsedName != null && parsedName.isNotEmpty) {
                appName = parsedName;
              } else if (htmlTitleName?.isNotEmpty != true) {
                final String? titleText =
                    doc
                        .querySelector('meta[property="og:title"]')
                        ?.attributes['content']
                        ?.trim() ??
                    doc.querySelector('title')?.text.trim();
                if (titleText != null && titleText.isNotEmpty) {
                  final parts = titleText.split('|');
                  if (parts.isNotEmpty) {
                    final String nameFromTitle = parts.first.trim();
                    if (nameFromTitle.isNotEmpty) {
                      appName = nameFromTitle;
                    }
                  }
                }
              }
            }
          }
        } catch (e) {
          // Icon is optional
        }
      }
      return APKDetails(
        version,
        getApkUrlsFromUrls(uniqueApkUrls),
        AppNames(sourceName, appName),
        iconUrl: iconUrl,
        rawReleaseTitleCandidates: rawVersionNameCandidates,
        apkSizeBytes: apkSizeBytes,
        isReproducible: reproducibleBuildBoolFromStatus(reproducibleStatus),
        reproducibleStatus: reproducibleStatus,
      );
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
