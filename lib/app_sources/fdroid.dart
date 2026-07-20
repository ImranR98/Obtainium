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
  static const String _verificationReportBaseUrl =
      'https://verification.f-droid.org/unsigned';
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
      final String host = Uri.parse(standardUrl).host.toLowerCase();
      final bool usesOfficialFDroidHost =
          host == 'f-droid.org' || host == 'www.f-droid.org';
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
      // Reuse only a terminal verified result for the same source version.
      // Missing and mismatched reports are deliberately checked again because
      // F-Droid can publish a successful verification report after the APK.
      final App? prevApp = previouslyCheckedApp;
      final bool canReuseCachedVerification =
          prevApp != null &&
          prevApp.rawLatestVersionFromSource != null &&
          prevApp.rawLatestVersionFromSource == details.version &&
          details.apkUrls.length == 1 &&
          _apkUrlsMatch(prevApp.apkUrls, details.apkUrls) &&
          prevApp.latestReproducibleVersionCode == details.versionCode &&
          prevApp.latestReproducibleStatus == reproducibleBuildStatusVerified;
      // Fork addition (icon / APK size / display name): reuse the previous
      // check's icon, APK size and name whenever the upstream version is
      // unchanged. This is deliberately separate from verification caching
      // above — it keys off the version alone and does NOT also require the
      // reproducible status to be 'verified', because icon/size/name never
      // change without a version change, whereas the reproducible verdict can.
      final bool versionUnchanged =
          prevApp != null &&
          prevApp.rawLatestVersionFromSource != null &&
          prevApp.rawLatestVersionFromSource == details.version;
      if (usesOfficialFDroidHost && canReuseCachedVerification) {
        details.reproducibleStatus = prevApp.latestReproducibleStatus;
        details.isReproducible = reproducibleBuildBoolFromStatus(
          prevApp.latestReproducibleStatus,
        );
      } else if (usesOfficialFDroidHost && details.versionCode != null) {
        details.reproducibleStatus = await getReproducibleBuildStatus(
          appId,
          details.versionCode!,
          additionalSettings,
        );
        details.isReproducible = reproducibleBuildBoolFromStatus(
          details.reproducibleStatus,
        );
      } else if (usesOfficialFDroidHost) {
        details.reproducibleStatus = reproducibleBuildStatusError;
        details.isReproducible = null;
      }

      if (usesOfficialFDroidHost && canReuseCachedVerification) {
        if (prevApp.changeLog?.isNotEmpty == true) {
          details.changeLog = prevApp.changeLog;
        }
        if (prevApp.author.trim().isNotEmpty) {
          details.names.author = prevApp.author;
        }
      }
      if (usesOfficialFDroidHost && !canReuseCachedVerification) {
        try {
          final res = await sourceRequest(
            'https://gitlab.com/fdroid/fdroiddata/-/raw/master/metadata/$appId.yml',
            additionalSettings,
          );
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

  Future<String> getReproducibleBuildStatus(
    String appId,
    int versionCode,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final String reportFileName = '${appId}_$versionCode.apk.json';
      final Response response = await sourceRequest(
        '$_verificationReportBaseUrl/$reportFileName',
        additionalSettings,
      );
      if (response.statusCode == 404) {
        return reproducibleBuildStatusNoData;
      }
      if (response.statusCode != 200) {
        throw getObtainiumHttpError(response);
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Invalid F-Droid verification report');
      }

      Map<String, dynamic>? latestMatchingReport;
      double? latestTimestamp;
      for (final reportEntry in decoded.entries) {
        if (reportEntry.value is! Map) {
          continue;
        }
        final Map<String, dynamic> report = Map<String, dynamic>.from(
          reportEntry.value as Map,
        );
        if (!_verificationDescriptorMatches(
              report['local'],
              appId,
              versionCode,
            ) ||
            !_verificationDescriptorMatches(
              report['remote'],
              appId,
              versionCode,
            )) {
          continue;
        }
        final String? reportUrl = report['url'] is String
            ? report['url'] as String
            : null;
        final Uri? parsedReportUrl = reportUrl == null
            ? null
            : Uri.tryParse(reportUrl);
        final String? reportApkName =
            parsedReportUrl == null || parsedReportUrl.pathSegments.isEmpty
            ? null
            : parsedReportUrl.pathSegments.last;
        if (reportApkName != '${appId}_$versionCode.apk') {
          continue;
        }
        final double? reportTimestamp = double.tryParse(
          reportEntry.key.toString(),
        );
        if (reportTimestamp == null) {
          continue;
        }
        if (latestTimestamp == null || reportTimestamp > latestTimestamp) {
          latestTimestamp = reportTimestamp;
          latestMatchingReport = report;
        }
      }
      final Object? verified = latestMatchingReport?['verified'];
      if (verified is! bool) {
        throw const FormatException(
          'F-Droid verification report has no matching verdict',
        );
      }
      return verified
          ? reproducibleBuildStatusVerified
          : reproducibleBuildStatusNotReproducible;
    } catch (e) {
      unawaited(
        LogsProvider().add(
          'Failed to check F-Droid reproducible build status for '
          '$appId ($versionCode): $e',
        ),
      );
      return reproducibleBuildStatusError;
    }
  }

  static bool _verificationDescriptorMatches(
    Object? rawDescriptor,
    String appId,
    int versionCode,
  ) {
    if (rawDescriptor is! Map) {
      return false;
    }
    return rawDescriptor['packageName'] == appId &&
        rawDescriptor['versionCode']?.toString() == versionCode.toString();
  }

  static bool _apkUrlsMatch(
    List<MapEntry<String, String>> previousUrls,
    List<MapEntry<String, String>> currentUrls,
  ) {
    if (previousUrls.length != currentUrls.length) {
      return false;
    }
    for (var index = 0; index < previousUrls.length; index++) {
      if (previousUrls[index].key != currentUrls[index].key ||
          previousUrls[index].value != currentUrls[index].value) {
        return false;
      }
    }
    return true;
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
      final List<dynamic> selectedReleases = releaseChoices.toList();
      final List<String> apkUrls = selectedReleases
          .map((e) => '${apkUrlPrefix}_${e['versionCode']}.apk')
          .toList();
      final List<String> uniqueApkUrls = apkUrls.toSet().toList();
      final App? prevApp = previouslyCheckedApp;
      final int preferredReleaseIndex =
          prevApp != null &&
              prevApp.preferredApkIndex >= 0 &&
              prevApp.preferredApkIndex < selectedReleases.length
          ? prevApp.preferredApkIndex
          : selectedReleases.length - 1;
      final int? selectedVersionCode = int.tryParse(
        selectedReleases[preferredReleaseIndex]['versionCode']?.toString() ??
            '',
      );
      // Skip the per-check APK-size HEAD and the package-page fetch (icon/name)
      // when the upstream version is unchanged since the last check. getApp()
      // reuses the previous apkSizeBytes / iconUrl / name in that case, so these
      // network round-trips would just be wasted work on a no-op refresh.
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
        versionCode: selectedVersionCode,
        iconUrl: iconUrl,
        rawReleaseTitleCandidates: rawVersionNameCandidates,
        apkSizeBytes: apkSizeBytes,
        reproducibleStatus: reproducibleBuildStatusNoData,
      );
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
