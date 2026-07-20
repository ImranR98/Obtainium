import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/services/html_parse_isolate.dart';

/// Loads a third-party F-Droid repo [index.xml] by trying common URL shapes.
/// [doSourceRequest] should be the owning [AppSource.sourceRequest] so TLS,
/// headers, and any host-specific behavior match that source (for example
/// [IzzyOnDroid] must not use a bare [FDroidRepo] instance for network calls).
Future<Response> fdroidRepoRequestIndexWithVariants(
  Future<Response> Function(String url, Map<String, dynamic> settings)
  doSourceRequest,
  String normalizedRepoBaseUrl,
  Map<String, dynamic> additionalSettings,
) async {
  final String url = normalizedRepoBaseUrl;
  Response res = await doSourceRequest(
    '$url${url.endsWith('/index.xml') ? '' : '/index.xml'}',
    additionalSettings,
  );
  if (res.statusCode != 200) {
    final String base = url.endsWith('/index.xml')
        ? url.split('/').reversed.toList().sublist(1).reversed.join('/')
        : url;
    res = await doSourceRequest('$base/repo/index.xml', additionalSettings);
    if (res.statusCode != 200) {
      res = await doSourceRequest(
        '$base/fdroid/repo/index.xml',
        additionalSettings,
      );
    }
  }
  return res;
}

class FDroidRepo extends AppSource {
  bool _appIdFoundInUrl = false;

  @override
  String get name => tr('fdroidThirdPartyRepo');

  FDroidRepo() {
    canSearch = true;
    includeAdditionalOptsInMainSearch = true;
    neverAutoSelect = true;
    showReleaseDateAsVersionToggle = true;
  }

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
    [
      GeneratedFormTextField(
        'appIdOrName',
        label: tr('appIdOrName'),
        hint: tr('reposHaveMultipleApps'),
        required: !_appIdFoundInUrl,
      ),
    ],
    [
      GeneratedFormSwitch(
        'pickHighestVersionCode',
        label: tr('pickHighestVersionCode'),
        value: false,
      ),
    ],
    [
      GeneratedFormSwitch(
        'trySelectingSuggestedVersionCode',
        label: tr('trySelectingSuggestedVersionCode'),
        value: true,
      ),
    ],
    // Fork addition: reproducible-build verification. When enabled, updates are
    // blocked unless the repo's index flags the release as a reproducible build.
    [
      GeneratedFormSwitch(
        'enforceReproducibleBuilds',
        label: tr('enforceReproducibleBuilds'),
        labelTooltip: tr('reproducibleBuildsTooltip'),
        value: false,
      ),
    ],
  ];

  String removeQueryParamsFromUrl(String url, {List<String> keep = const []}) {
    final uri = Uri.parse(url);
    final Map<String, dynamic> resultParams = {};
    uri.queryParameters.forEach((key, value) {
      if (keep.contains(key)) {
        resultParams[key] = value;
      }
    });
    url = uri.replace(queryParameters: resultParams).toString();
    if (url.endsWith('?')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    var standardUri = Uri.parse(url);
    final pathSegments = standardUri.pathSegments;
    if (pathSegments.isNotEmpty && pathSegments.last == 'index.xml') {
      pathSegments.removeLast();
      standardUri = standardUri.replace(path: pathSegments.join('/'));
    }
    return removeQueryParamsFromUrl(standardUri.toString(), keep: ['appId']);
  }

  /// Parses a successful F-Droid repo [index.xml] [Response] into search result
  /// entries. Fork addition: extracted so it can be reused and run off the UI
  /// isolate via [parseHtmlOffIsolate].
  static Future<Map<String, List<String>>> parseIndexXmlSearchResults(
    Response res,
    String query,
  ) async {
    final body = await parseHtmlOffIsolate(res.body);
    final Map<String, List<String>> results = <String, List<String>>{};
    body.querySelectorAll('application').toList().forEach((app) {
      final String? appId = app.attributes['id'];
      if (appId == null) return;
      final String appName = app.querySelector('name')?.innerHtml ?? appId;
      final String appDesc = app.querySelector('desc')?.innerHtml ?? '';
      if (query.isEmpty ||
          appId.contains(query) ||
          appName.contains(query) ||
          appDesc.contains(query)) {
        results['${AppSource.stripLastPathSegment((res.request?.url ?? Uri.parse('')).toString())}?appId=$appId'] =
            [appName, appDesc];
      }
    });
    return results;
  }

  /// Parses a successful [index.xml] [Response] into [APKDetails] for the app
  /// matching [appIdOrName]. [authorFallback] is used when the index has no
  /// repo or per-app author. Used by [IzzyOnDroid] (which supplies its own
  /// reproducible-status resolver).
  static Future<APKDetails> apkDetailsFromIndexXmlResponse(
    Response indexXmlResponse,
    String appIdOrName,
    Map<String, dynamic> additionalSettings,
    String authorFallback, {
    Future<bool?> Function(String appId, int versionCode, String? apkSha256)?
    isReproducibleRelease,
    Future<String?> Function(String appId, int versionCode, String? apkSha256)?
    reproducibleReleaseStatus,
  }) async {
    final body = await parseHtmlOffIsolate(indexXmlResponse.body);
    var foundApps = body.querySelectorAll('application').where((element) {
      return element.attributes['id'] == appIdOrName;
    }).toList();
    if (foundApps.isEmpty) {
      foundApps = body.querySelectorAll('application').where((element) {
        return element.querySelector('name')?.innerHtml.toLowerCase() ==
            appIdOrName.toLowerCase();
      }).toList();
    }
    if (foundApps.isEmpty) {
      foundApps = body.querySelectorAll('application').where((element) {
        return element
                .querySelector('name')
                ?.innerHtml
                .toLowerCase()
                .contains(appIdOrName.toLowerCase()) ??
            false;
      }).toList();
    }
    if (foundApps.isEmpty) {
      throw ObtainiumError(tr('appWithIdOrNameNotFound'));
    }
    var authorName =
        body.querySelector('repo')?.attributes['name'] ?? authorFallback;
    final String appId = foundApps[0].attributes['id']!;
    final appName = foundApps[0].querySelector('name')?.innerHtml ?? appId;
    List<dynamic> releases = foundApps[0].querySelectorAll('package').toList();
    releases = releases.where((release) {
      return release.querySelector('apkname') != null;
    }).toList();
    if (releases.isEmpty) {
      throw NoReleasesError();
    }
    Future<String> releaseReproducibleStatus(dynamic release) async {
      final String? binaries = release.querySelector('binaries')?.text.trim();
      if (binaries?.isNotEmpty == true) {
        return reproducibleBuildStatusVerified;
      }
      final int? versionCode = int.tryParse(
        release.querySelector('versioncode')?.innerHtml ?? '',
      );
      if (versionCode == null) {
        return reproducibleBuildStatusNoData;
      }
      final String? apkSha256 = release.querySelector('hash')?.innerHtml.trim();
      try {
        if (reproducibleReleaseStatus != null) {
          return await reproducibleReleaseStatus(
                appId,
                versionCode,
                apkSha256,
              ) ??
              reproducibleBuildStatusNoData;
        }
        if (isReproducibleRelease != null) {
          return reproducibleBuildStatusFromBool(
            await isReproducibleRelease(appId, versionCode, apkSha256),
          );
        }
        return reproducibleBuildStatusNoData;
      } catch (_) {
        return reproducibleBuildStatusError;
      }
    }

    final String? changeLog = foundApps[0]
        .querySelector('changelog')
        ?.innerHtml;
    final String? latestVersion = releases[0]
        .querySelector('version')
        ?.innerHtml;
    if (latestVersion == null) {
      throw NoVersionError();
    }
    final String? marketvercodeStr = foundApps[0]
        .querySelector('marketvercode')
        ?.innerHtml;
    final int? marketvercode = int.tryParse(marketvercodeStr ?? '');
    List selectedReleases = [];
    final bool trySelectingSuggestedVersionCode =
        additionalSettings['trySelectingSuggestedVersionCode'] != false;
    final bool pickHighestVersionCode =
        additionalSettings['pickHighestVersionCode'] == true ||
        additionalSettings['autoSelectHighestVersionCode'] == true;
    if (trySelectingSuggestedVersionCode && marketvercode != null) {
      selectedReleases = releases
          .where(
            (e) =>
                int.tryParse(e.querySelector('versioncode')?.innerHtml ?? '') ==
                    marketvercode &&
                e.querySelector('apkname') != null,
          )
          .toList();
    }
    final String? appAuthorName = foundApps[0]
        .querySelector('author')
        ?.innerHtml;
    if (appAuthorName != null) {
      authorName = appAuthorName;
    }
    if (selectedReleases.isEmpty) {
      selectedReleases = releases
          .where(
            (e) =>
                e.querySelector('version')?.innerHtml == latestVersion &&
                e.querySelector('apkname') != null,
          )
          .toList();
      if (selectedReleases.length > 1 && pickHighestVersionCode) {
        selectedReleases.sort((e1, e2) {
          return int.parse(
            e2.querySelector('versioncode')!.innerHtml,
          ).compareTo(int.parse(e1.querySelector('versioncode')!.innerHtml));
        });
        selectedReleases = [selectedReleases[0]];
      }
    }
    final String? selectedVersion = selectedReleases[0]
        .querySelector('version')
        ?.innerHtml;
    if (selectedVersion == null) {
      throw NoVersionError();
    }
    final String? added = selectedReleases[0].querySelector('added')?.innerHtml;
    final DateTime? releaseDate = added != null ? DateTime.parse(added) : null;
    final repoBase = indexXmlResponse.request!.url
        .toString()
        .split('/')
        .reversed
        .toList()
        .sublist(1)
        .reversed
        .join('/');
    final List<String> apkUrls = selectedReleases
        .map((e) => '$repoBase/${e.querySelector('apkname')!.innerHtml}')
        .toList();
    final String? apkSizeText = selectedReleases.isNotEmpty
        ? selectedReleases.last.querySelector('size')?.innerHtml
        : null;
    final int? apkSizeBytes = int.tryParse(apkSizeText ?? '');
    final String? iconFile = foundApps[0]
        .querySelector('icon')
        ?.innerHtml
        .trim();
    String? iconUrl;
    if (iconFile != null && iconFile.isNotEmpty) {
      iconUrl = '$repoBase/icons/$iconFile';
    }
    final String reproducibleStatus = selectedReleases.isNotEmpty
        ? await releaseReproducibleStatus(selectedReleases[0])
        : reproducibleBuildStatusNoData;
    return APKDetails(
      selectedVersion,
      getApkUrlsFromUrls(apkUrls),
      AppNames(authorName, appName),
      versionCode: int.tryParse(
        selectedReleases[0].querySelector('versioncode')?.innerHtml ?? '',
      ),
      releaseDate: releaseDate,
      changeLog: changeLog,
      iconUrl: iconUrl,
      apkSizeBytes: apkSizeBytes,
      isReproducible: reproducibleBuildBoolFromStatus(reproducibleStatus),
      reproducibleStatus: reproducibleStatus,
    );
  }

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    String? url = querySettings['url'];
    if (url == null) {
      throw NoReleasesError();
    }
    url = removeQueryParamsFromUrl(standardizeUrl(url));
    final res = await sourceRequestWithURLVariants(url, {});
    if (res.statusCode == 200) {
      return await parseIndexXmlSearchResults(res, query);
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  @override
  void runOnAddAppInputChange(String inputUrl) {
    try {
      final appId = Uri.parse(inputUrl).queryParameters['appId'];
      _appIdFoundInUrl = appId != null;
    } catch (e) {
      unawaited(LogsProvider().add('Failed to parse appId from URL: $e'));
    }
  }

  @override
  App postProcessApp(App app) {
    final uri = Uri.parse(app.url);
    String? appId;
    if (!isTempId(app)) {
      appId = app.id;
    } else if (uri.queryParameters['appId'] != null) {
      appId = uri.queryParameters['appId'];
    }
    if (appId != null) {
      app = app.copyWith(
        url: uri
            .replace(
              queryParameters: Map.fromEntries([
                ...uri.queryParameters.entries,
                MapEntry('appId', appId),
              ]),
            )
            .toString(),
      );
      app = app.copyWith(
        additionalSettings: Map<String, dynamic>.from(app.additionalSettings)
          ..['appIdOrName'] = appId,
      );
      app = app.copyWith(id: appId);
    }
    return app;
  }

  Future<Response> sourceRequestWithURLVariants(
    String url,
    Map<String, dynamic> additionalSettings,
  ) async {
    var res = await sourceRequest(
      '$url${url.endsWith('/index.xml') ? '' : '/index.xml'}',
      additionalSettings,
    );
    if (res.statusCode != 200) {
      final base = url.endsWith('/index.xml')
          ? AppSource.stripLastPathSegment(url)
          : url;
      res = await sourceRequest('$base/repo/index.xml', additionalSettings);
      if (res.statusCode != 200) {
        res = await sourceRequest(
          '$base/fdroid/repo/index.xml',
          additionalSettings,
        );
      }
    }
    return res;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      String? appIdOrName = additionalSettings['appIdOrName'];
      final standardUri = Uri.parse(standardUrl);
      if (standardUri.queryParameters['appId'] != null) {
        appIdOrName = standardUri.queryParameters['appId'];
      }
      standardUrl = removeQueryParamsFromUrl(standardUrl);
      if (appIdOrName == null) {
        throw NoReleasesError();
      }
      additionalSettings['appIdOrName'] = appIdOrName;
      final res = await sourceRequestWithURLVariants(
        standardUrl,
        additionalSettings,
      );
      if (res.statusCode == 200) {
        return await apkDetailsFromIndexXmlResponse(
          res,
          appIdOrName,
          additionalSettings,
          name,
        );
      } else {
        throw getObtainiumHttpError(res);
      }
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
