import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class FDroidRepo extends AppSource {
  FDroidRepo() {
    name = tr('fdroidThirdPartyRepo');
    canSearch = true;
    includeAdditionalOptsInMainSearch = true;
    neverAutoSelect = true;
    showReleaseDateAsVersionToggle = true;

    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormTextField(
          'appIdOrName',
          label: tr('appIdOrName'),
          hint: tr('reposHaveMultipleApps'),
          required: true,
        ),
      ],
      [
        GeneratedFormSwitch(
          'pickHighestVersionCode',
          label: tr('pickHighestVersionCode'),
          defaultValue: false,
        ),
      ],
      [
        GeneratedFormSwitch(
          'trySelectingSuggestedVersionCode',
          label: tr('trySelectingSuggestedVersionCode'),
          defaultValue: true,
        ),
      ],
    ];
  }

  String removeQueryParamsFromUrl(String url, {List<String> keep = const []}) {
    var uri = Uri.parse(url);
    Map<String, dynamic> resultParams = {};
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
    var pathSegments = standardUri.pathSegments;
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
    var res = await sourceRequestWithURLVariants(url, {});
    if (res.statusCode == 200) {
      var body = parse(res.body);
      Map<String, List<String>> results = {};
      body.querySelectorAll('application').toList().forEach((app) {
        String appId = app.attributes['id']!;
        String appName = app.querySelector('name')?.innerHtml ?? appId;
        String appDesc = app.querySelector('desc')?.innerHtml ?? '';
        if (query.isEmpty ||
            appId.contains(query) ||
            appName.contains(query) ||
            appDesc.contains(query)) {
          results['${res.request!.url.toString().split('/').reversed.toList().sublist(1).reversed.join('/')}?appId=$appId'] =
              [appName, appDesc];
        }
      });
      return results;
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  @override
  void runOnAddAppInputChange(String userInput) {
    additionalSourceAppSpecificSettingFormItems =
        additionalSourceAppSpecificSettingFormItems.map((row) {
          row = row.map((item) {
            if (item.key == 'appIdOrName') {
              try {
                var appId = Uri.parse(userInput).queryParameters['appId'];
                if (appId != null && item is GeneratedFormTextField) {
                  item.required = false;
                }
              } catch (e) {
                //
              }
            }
            return item;
          }).toList();
          return row;
        }).toList();
  }

  @override
  App endOfGetAppChanges(App app) {
    var uri = Uri.parse(app.url);
    String? appId;
    if (!isTempId(app)) {
      appId = app.id;
    } else if (uri.queryParameters['appId'] != null) {
      appId = uri.queryParameters['appId'];
    }
    if (appId != null) {
      app.url = uri
          .replace(
            queryParameters: Map.fromEntries([
              ...uri.queryParameters.entries,
              MapEntry('appId', appId),
            ]),
          )
          .toString();
      app.additionalSettings['appIdOrName'] = appId;
      app.id = appId;
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
      var base = url.endsWith('/index.xml')
          ? url.split('/').reversed.toList().sublist(1).reversed.join('/')
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
    String? appIdOrName = additionalSettings['appIdOrName'];
    var standardUri = Uri.parse(standardUrl);
    if (standardUri.queryParameters['appId'] != null) {
      appIdOrName = standardUri.queryParameters['appId'];
    }
    standardUrl = removeQueryParamsFromUrl(standardUrl);
    bool pickHighestVersionCode = additionalSettings['pickHighestVersionCode'];
    bool trySelectingSuggestedVersionCode = additionalSettings['trySelectingSuggestedVersionCode'];
    if (appIdOrName == null) {
      throw NoReleasesError();
    }
    additionalSettings['appIdOrName'] = appIdOrName;
    var res = await sourceRequestWithURLVariants(
      standardUrl,
      additionalSettings,
    );
    if (res.statusCode == 200) {
      var body = parse(res.body);
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
      String appId = foundApps[0].attributes['id']!;
      foundApps[0].querySelector('name')?.innerHtml ?? appId;
      var appName = foundApps[0].querySelector('name')?.innerHtml ?? appId;
      var releases = foundApps[0].querySelectorAll('package');
      if (releases.isEmpty) {
        throw NoReleasesError();
      }
      String? changeLog = foundApps[0].querySelector('changelog')?.innerHtml;
      String? latestVersion = releases[0].querySelector('version')?.innerHtml;
      if (latestVersion == null) {
        throw NoVersionError();
      }
      String? marketvercodeStr = foundApps[0].querySelector('marketvercode')?.innerHtml;
      int? marketvercode = int.tryParse(marketvercodeStr ?? '');
      List selectedReleases = [];
      if (trySelectingSuggestedVersionCode && marketvercode != null) {
        selectedReleases = releases.where((e) =>
          int.tryParse(e.querySelector('versioncode')?.innerHtml ?? '') == marketvercode &&
          e.querySelector('apkname') != null
        ).toList();
      }
      String? appAuthorName = foundApps[0].querySelector('author')?.innerHtml;
      if (appAuthorName != null) {
        authorName = appAuthorName;
      }
      if (selectedReleases.isEmpty) {
        selectedReleases = releases.where((e) =>
          e.querySelector('version')?.innerHtml == latestVersion &&
          e.querySelector('apkname') != null
        ).toList();
        if (selectedReleases.length > 1 && pickHighestVersionCode) {
          selectedReleases.sort((e1, e2) {
            return int.parse(e2.querySelector('versioncode')!.innerHtml)
              .compareTo(int.parse(e1.querySelector('versioncode')!.innerHtml));
        });
          selectedReleases = [selectedReleases[0]];
        }
      }
      String? selectedVersion = selectedReleases[0].querySelector('version')?.innerHtml;
      if (selectedVersion == null) {
        throw NoVersionError();
      }
      String? added = selectedReleases[0].querySelector('added')?.innerHtml;
      DateTime? releaseDate = added != null ? DateTime.parse(added) : null;
      List<String> apkUrls = selectedReleases
          .map(
            (e) =>
                '${res.request!.url.toString().split('/').reversed.toList().sublist(1).reversed.join('/')}/${e.querySelector('apkname')!.innerHtml}',
          )
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
  }
}
