import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class FDroidRepo extends AppSource {
  FDroidRepo() {
    name = tr('fdroidThirdPartyRepo');
    canSearch = true;
    excludeFromMassSearch = true;
    neverAutoSelect = true;

    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormTextField('appIdOrName',
            label: tr('appIdOrName'),
            hint: tr('reposHaveMultipleApps'),
            required: true)
      ],
      [
        GeneratedFormSwitch('pickHighestVersionCode',
            label: tr('pickHighestVersionCode'), defaultValue: false)
      ]
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
  String sourceSpecificStandardizeURL(String url) {
    var standardUri = Uri.parse(url);
    var pathSegments = standardUri.pathSegments;
    if (pathSegments.last == 'index.xml') {
      pathSegments.removeLast();
      standardUri = standardUri.replace(path: pathSegments.join('/'));
    }
    return removeQueryParamsFromUrl(standardUri.toString(), keep: ['appId']);
  }

  @override
  Future<Map<String, List<String>>> search(String query,
      {Map<String, dynamic> querySettings = const {}}) async {
    query = removeQueryParamsFromUrl(standardizeUrl(query));
    var res = await sourceRequest('$query/index.xml');
    if (res.statusCode == 200) {
      var body = parse(res.body);
      Map<String, List<String>> results = {};
      body.querySelectorAll('application').toList().forEach((app) {
        String appId = app.attributes['id']!;
        results['$query?appId=$appId'] = [
          app.querySelector('name')?.innerHtml ?? appId,
          app.querySelector('desc')?.innerHtml ?? ''
        ];
      });
      return results;
    } else {
      throw getObtainiumHttpError(res);
    }
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
              queryParameters: Map.fromEntries(
                  [...uri.queryParameters.entries, MapEntry('appId', appId)]))
          .toString();
      app.additionalSettings['appIdOrName'] = appId;
      app.id = appId;
    }
    return app;
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
    if (appIdOrName == null) {
      throw NoReleasesError();
    }
    var res = await sourceRequest('$standardUrl/index.xml');
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
      String? latestVersion = releases[0].querySelector('version')?.innerHtml;
      String? added = releases[0].querySelector('added')?.innerHtml;
      DateTime? releaseDate = added != null ? DateTime.parse(added) : null;
      if (latestVersion == null) {
        throw NoVersionError();
      }
      var latestVersionReleases = releases
          .where((element) =>
              element.querySelector('version')?.innerHtml == latestVersion &&
              element.querySelector('apkname') != null)
          .toList();
      if (latestVersionReleases.length > 1 && pickHighestVersionCode) {
        latestVersionReleases.sort((e1, e2) {
          return int.parse(e2.querySelector('versioncode')!.innerHtml)
              .compareTo(int.parse(e1.querySelector('versioncode')!.innerHtml));
        });
        latestVersionReleases = [latestVersionReleases[0]];
      }
      List<String> apkUrls = latestVersionReleases
          .map((e) => '$standardUrl/${e.querySelector('apkname')!.innerHtml}')
          .toList();
      return APKDetails(latestVersion, getApkUrlsFromUrls(apkUrls),
          AppNames(authorName, appName),
          releaseDate: releaseDate);
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
