import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:easy_localization/easy_localization.dart';

class GitLab extends AppSource {
  // Reused for getAppNames, API URL building, search, and getRequestHeaders
  // so a single GitHub instance handles all delegated behaviour.
  final GitHub _gh = GitHub(hostChanged: true);

  GitLab({bool hostChanged = false}) {
    name = 'GitLab';
    hosts = ['gitlab.com'];
    canSearch = true;
    showReleaseDateAsVersionToggle = true;
    this.hostChanged = hostChanged;
  }

  @override
  List<GeneratedFormItem> get sourceConfigSettingFormItems => [
    GeneratedFormTextField(
      'gitlab-creds',
      label: tr('gitlabPATLabel'),
      password: true,
      required: false,
      helpUrl:
          'https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html#create-a-personal-access-token',
    ),
  ];

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
    AppSource.fallbackToOlderReleasesFormItem,
  ];

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    final urlSegments = url.split('/');
    final cutOffIndex = urlSegments.indexWhere((s) => s == '-');
    url = urlSegments
        .sublist(0, cutOffIndex <= 0 ? null : cutOffIndex)
        .join('/');
    final RegExp standardUrlRegEx = RegExp(
      '^https?://(www\\.)?${getSourceRegex(hosts)}/[^/]+(/[^/]+){1,20}',
      caseSensitive: false,
    );
    final RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  Future<String?> getPATIfAny(Map<String, dynamic> additionalSettings) async {
    final SettingsProvider settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    final sourceConfig = await getSourceConfigValues(
      additionalSettings,
      settingsProvider,
    );
    final String? creds = sourceConfig['gitlab-creds'];
    return creds != null && creds.isNotEmpty ? creds : null;
  }

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    final url =
        'https://${hosts[0]}/api/v4/projects?search=${Uri.encodeQueryComponent(query)}';
    final res = await sourceRequest(url, {});
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    final json = jsonDecode(res.body) as List<dynamic>;
    final Map<String, List<String>> results = {};
    for (var element in json) {
      results['https://${hosts[0]}/${element['path_with_namespace']}'] = [
        element['name_with_namespace'],
        element['description'] ?? tr('noDescription'),
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
    String url, {
    bool forAPKDownload = false,
  }) async {
    // Provide headers acceptable to, e.g. Cloudflare protection
    final headers = <String, String>{};
    headers[HttpHeaders.refererHeader] = 'https://${hosts[0]}';
    return headers;
  }

  @override
  Future<String> assetUrlPrefetchModifier(
    String assetUrl,
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final String? pat = await getPATIfAny(
      hostChanged ? additionalSettings : {},
    );
    final String optionalAuth = (pat != null) ? 'private_token=$pat' : '';
    return optionalAuth.isEmpty
        ? assetUrl
        : '$assetUrl${Uri.parse(assetUrl).query.isEmpty ? '?' : '&'}$optionalAuth';
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final names = _gh.getAppNames(standardUrl);
      final String projectUriComponent =
          '${Uri.encodeComponent(names.author)}%2F${Uri.encodeComponent(names.name)}';
      final String? pat = await getPATIfAny(
        hostChanged ? additionalSettings : {},
      );
      final String optionalAuth = (pat != null) ? 'private_token=$pat' : '';

      final bool trackOnly = additionalSettings['trackOnly'] == true;

      // Get project ID
      final Response res0 = await sourceRequest(
        'https://${hosts[0]}/api/v4/projects/$projectUriComponent?$optionalAuth',
        additionalSettings,
      );
      if (res0.statusCode != 200) {
        throw getObtainiumHttpError(res0);
      }
      final int? projectId = jsonDecode(res0.body)['id'];
      if (projectId == null) {
        throw NoReleasesError();
      }

      // Request data from REST API
      final String releasesPath = trackOnly ? 'repository/tags' : 'releases';
      final String query = [
        if (optionalAuth.isNotEmpty) optionalAuth,
        'per_page=100',
      ].join('&');
      final Response res = await sourceRequest(
        'https://${hosts[0]}/api/v4/projects/$projectUriComponent/$releasesPath?$query',
        additionalSettings,
      );
      if (res.statusCode != 200) {
        throw getObtainiumHttpError(res);
      }

      // Extract .apk details from received data
      Iterable<APKDetails> apkDetailsList = [];
      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        throw NoReleasesError();
      }
      final json = decoded;
      apkDetailsList = json.map((e) {
        final apkUrlsFromAssets =
            (e['assets']?['links'] as List<dynamic>? ?? [])
                .map((e) {
                  final url =
                      (e['direct_asset_url'] ?? e['url'] ?? '') as String;
                  final parsedUrl = url.isNotEmpty ? Uri.parse(url) : null;
                  return MapEntry(
                    (e['name'] ??
                            (parsedUrl != null &&
                                    parsedUrl.pathSegments.isNotEmpty
                                ? parsedUrl.pathSegments.last
                                : 'unknown'))
                        as String,
                    (e['direct_asset_url'] ?? e['url'] ?? '') as String,
                  );
                })
                .where(
                  (s) =>
                      s.key.isNotEmpty &&
                      (AppSource.isApkOrContainerFile(s.key) ||
                          AppSource.isApkOrContainerFile(s.value)),
                )
                .toList();
        final uploadedAPKsFromDescription = ((e['description'] ?? '') as String)
            .split('](')
            .join('\n')
            .split('.apk)')
            .join('.apk\n')
            .split('.xapk)')
            .join('.xapk\n')
            .split('.apkm)')
            .join('.apkm\n')
            .split('.apks)')
            .join('.apks\n')
            .split('\n')
            .where(
              (s) =>
                  s.startsWith('/uploads/') &&
                  AppSource.isApkOrContainerFile(s),
            )
            .map((s) => 'https://${hosts[0]}/-/project/$projectId$s')
            .map((l) => MapEntry(Uri.parse(l).pathSegments.last, l))
            .toList();
        final Map<String, String> apkUrls = {};
        for (var entry in apkUrlsFromAssets) {
          apkUrls[entry.key] = entry.value;
        }
        for (var entry in uploadedAPKsFromDescription) {
          apkUrls[entry.key] = entry.value;
        }
        final releaseDateString =
            e['released_at'] ?? e['created_at'] ?? e['commit']?['created_at'];
        final DateTime? releaseDate = releaseDateString != null
            ? DateTime.tryParse(releaseDateString.toString())
            : null;
        return APKDetails(
          e['tag_name'] ?? e['name'],
          apkUrls.entries.toList(),
          AppNames(names.author, names.name.split('/').last),
          releaseDate: releaseDate,
        );
      });
      if (apkDetailsList.isEmpty) {
        throw NoReleasesError();
      }
      var finalResult = apkDetailsList.first;

      final bool fallbackToOlderReleases =
          additionalSettings['fallbackToOlderReleases'] == true;
      if (finalResult.apkUrls.isEmpty &&
          fallbackToOlderReleases &&
          !trackOnly) {
        apkDetailsList = apkDetailsList
            .where((e) => e.apkUrls.isNotEmpty)
            .toList();
        if (apkDetailsList.isEmpty) {
          throw NoReleasesError();
        }
        finalResult = apkDetailsList.first;
      }

      if (finalResult.apkUrls.isEmpty && !trackOnly) {
        throw NoAPKError();
      }

      finalResult.apkUrls = finalResult.apkUrls.map((apkUrl) {
        if (RegExp(
          '^${RegExp.escape(standardUrl)}/-/jobs/[0-9]+/artifacts/file/[^/]+',
        ).hasMatch(apkUrl.value)) {
          return MapEntry(
            apkUrl.key,
            apkUrl.value.replaceFirst('/file/', '/raw/'),
          );
        } else {
          return apkUrl;
        }
      }).toList();

      return finalResult;
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
