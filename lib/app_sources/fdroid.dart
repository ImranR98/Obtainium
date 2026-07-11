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

class FDroid extends AppSource {
  static const _maxChangeLogCodeUnits = 2048;
  FDroid() {
    hosts = ['f-droid.org'];
    name = tr('fdroid');
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
      final details = getAPKUrlsFromFDroidPackagesAPIResponse(
        await sourceRequest(
          'https://$host/api/v1/packages/$appId',
          additionalSettings,
        ),
        'https://$host/repo/$appId',
        standardUrl,
        name,
        additionalSettings: additionalSettings,
      );
      if (!hostChanged) {
        try {
          final res = await sourceRequest(
            'https://gitlab.com/fdroid/fdroiddata/-/raw/master/metadata/$appId.yml',
            additionalSettings,
          );
          final lines = res.body.split('\n');
          final authorLines = lines.where((l) => l.startsWith('AuthorName: '));
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

  APKDetails getAPKUrlsFromFDroidPackagesAPIResponse(
    Response res,
    String apkUrlPrefix,
    String standardUrl,
    String sourceName, {
    Map<String, dynamic> additionalSettings = const {},
  }) {
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
      String? version;
      Iterable<dynamic> releaseChoices = [];
      // Grab the versionCode suggested if the user chose to do that
      // Only do so at this stage if the user has no release filter
      if (trySelectingSuggestedVersionCode &&
          response['suggestedVersionCode'] != null &&
          filterVersionsByRegEx == null) {
        final suggestedReleases = releases.where(
          (element) =>
              element['versionCode'] == response['suggestedVersionCode'],
        );
        if (suggestedReleases.isNotEmpty) {
          releaseChoices = suggestedReleases;
          version = suggestedReleases.first['versionName'];
        }
      }
      // Apply the release filter if any
      if (filterVersionsByRegEx?.isNotEmpty == true) {
        version = null;
        releaseChoices = [];
        final versionFilter = RegExp(filterVersionsByRegEx!);
        for (var i = 0; i < releases.length; i++) {
          if (versionFilter.hasMatch(releases[i]['versionName'])) {
            version = releases[i]['versionName'];
            break;
          }
        }
        if (version == null || version.isEmpty) {
          throw NoVersionError();
        }
      }
      // Default to the highest version
      version ??= releases[0]['versionName'];
      if (version == null || version.isEmpty) {
        throw NoVersionError();
      }
      // If a suggested release was not already picked, pick all those with the selected version
      if (releaseChoices.isEmpty) {
        releaseChoices = releases.where(
          (element) => element['versionName'] == version,
        );
      }
      // For the remaining releases, use the toggles to auto-select one if possible
      if (releaseChoices.length > 1) {
        if (autoSelectHighestVersionCode) {
          releaseChoices = [releaseChoices.first];
        } else if (trySelectingSuggestedVersionCode &&
            response['suggestedVersionCode'] != null) {
          final suggestedReleases = releaseChoices.where(
            (element) =>
                element['versionCode'] == response['suggestedVersionCode'],
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
      return APKDetails(
        version,
        getApkUrlsFromUrls(apkUrls.toSet().toList()),
        AppNames(sourceName, Uri.parse(standardUrl).pathSegments.last),
      );
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
