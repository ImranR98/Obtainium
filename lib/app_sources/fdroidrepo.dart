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
    excludeFromMassSearch = true;
    neverAutoSelect = true;
    showReleaseDateAsVersionToggle = true;

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
    if (pathSegments.isNotEmpty && pathSegments.last == 'index.xml') {
      pathSegments.removeLast();
      standardUri = standardUri.replace(path: pathSegments.join('/'));
    }
    return removeQueryParamsFromUrl(standardUri.toString(), keep: ['appId']);
  }

  @override
  Future<Map<String, List<String>>> search(String query,
      {Map<String, dynamic> querySettings = const {}}) async {
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
          results[
              '${res.request!.url.toString().split('/').reversed.toList().sublist(1).reversed.join('/')}?appId=$appId'] = [
            appName,
            appDesc
          ];
        }
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

  Future<Response> sourceRequestWithURLVariants(
    String url,
    Map<String, dynamic> additionalSettings,
  ) async {
    var res = await sourceRequest(
        '$url${url.endsWith('/index.xml') ? '' : '/index.xml'}',
        additionalSettings);
    if (res.statusCode != 200) {
      var base = url.endsWith('/index.xml')
          ? url.split('/').reversed.toList().sublist(1).reversed.join('/')
          : url;
      res = await sourceRequest('$base/repo/index.xml', additionalSettings);
      if (res.statusCode != 200) {
        res = await sourceRequest(
            '$base/fdroid/repo/index.xml', additionalSettings);
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
    if (appIdOrName == null) {
      throw NoReleasesError();
    }
    var res =
        await sourceRequestWithURLVariants(standardUrl, additionalSettings);
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
          .map((e) =>
              '${res.request!.url.toString().split('/').reversed.toList().sublist(1).reversed.join('/')}/${e.querySelector('apkname')!.innerHtml}')
          .toList();
      return APKDetails(latestVersion, getApkUrlsFromUrls(apkUrls),
          AppNames(authorName, appName),
          releaseDate: releaseDate);
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
