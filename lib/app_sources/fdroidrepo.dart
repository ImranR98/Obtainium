import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

class FDroidRepo extends AppSource {
  bool _appIdFoundInUrl = false;

  FDroidRepo() {
    name = tr('fdroidThirdPartyRepo');
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
      final body = parse(res.body);
      final Map<String, List<String>> results = {};
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
      final bool pickHighestVersionCode =
          additionalSettings['pickHighestVersionCode'] == true;
      final bool trySelectingSuggestedVersionCode =
          additionalSettings['trySelectingSuggestedVersionCode'] == true;
      if (appIdOrName == null) {
        throw NoReleasesError();
      }
      additionalSettings['appIdOrName'] = appIdOrName;
      final res = await sourceRequestWithURLVariants(
        standardUrl,
        additionalSettings,
      );
      if (res.statusCode == 200) {
        final body = parse(res.body);
        var foundApps = body.querySelectorAll('application').where((element) {
          return element.attributes['id'] == appIdOrName;
        }).toList();
        if (foundApps.isEmpty) {
          foundApps = body.querySelectorAll('application').where((element) {
            return element.querySelector('name')?.innerHtml.toLowerCase() ==
                appIdOrName!.toLowerCase();
          }).toList();
        }
        if (foundApps.isEmpty) {
          foundApps = body.querySelectorAll('application').where((element) {
            return element
                    .querySelector('name')
                    ?.innerHtml
                    .toLowerCase()
                    .contains(appIdOrName!.toLowerCase()) ??
                false;
          }).toList();
        }
        if (foundApps.isEmpty) {
          throw ObtainiumError(tr('appWithIdOrNameNotFound'));
        }
        var authorName = body.querySelector('repo')?.attributes['name'] ?? name;
        final String appId = foundApps[0].attributes['id'] ?? appIdOrName;
        final appName = foundApps[0].querySelector('name')?.innerHtml ?? appId;
        final releases = foundApps[0].querySelectorAll('package');
        if (releases.isEmpty) {
          throw NoReleasesError();
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
        if (trySelectingSuggestedVersionCode && marketvercode != null) {
          selectedReleases = releases
              .where(
                (e) =>
                    int.tryParse(
                          e.querySelector('versioncode')?.innerHtml ?? '',
                        ) ==
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
              return (int.tryParse(
                        e2.querySelector('versioncode')?.innerHtml ?? '',
                      ) ??
                      0)
                  .compareTo(
                    int.tryParse(
                          e1.querySelector('versioncode')?.innerHtml ?? '',
                        ) ??
                        0,
                  );
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
        final String? added = selectedReleases[0]
            .querySelector('added')
            ?.innerHtml;
        final DateTime? releaseDate = added != null
            ? DateTime.parse(added)
            : null;
        final List<String> apkUrls = selectedReleases
            .map((e) {
              final apkName = e.querySelector('apkname')?.innerHtml;
              return apkName != null
                  ? '${AppSource.stripLastPathSegment((res.request?.url ?? Uri.parse('')).toString())}/$apkName'
                  : null;
            })
            .where((u) => u != null)
            .cast<String>()
            .toList();
        return APKDetails(
          selectedVersion,
          getApkUrlsFromUrls(apkUrls),
          AppNames(authorName, appName),
          releaseDate: releaseDate,
          changeLog: changeLog,
        );
      } else {
        throw getObtainiumHttpError(res);
      }
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
