import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class VivoAppStore extends AppSource {
  static const appDetailUrl =
      'https://h5coml.vivo.com.cn/h5coml/appdetail_h5/browser_v2/index.html?appId=';

  VivoAppStore() {
    name = tr('vivoAppStore');
    hosts = ['h5.appstore.vivo.com.cn', 'h5coml.vivo.com.cn'];
    naiveStandardVersionDetection = true;
    canSearch = true;
    allowOverride = false;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    var vivoAppId = parseVivoAppId(url);
    return '$appDetailUrl$vivoAppId';
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    var json = await getDetailJson(standardUrl, additionalSettings);
    return json['package_name'];
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var json = await getDetailJson(standardUrl, additionalSettings);
    var appName = json['title_zh'].toString();
    var packageName = json['package_name'].toString();
    var versionName = json['version_name'].toString();
    var versionCode = json['version_code'].toString();
    var developer = json['developer'].toString();
    var uploadTime = json['upload_time'].toString();
    var apkUrl = json['download_url'].toString();
    var apkName = '${packageName}_$versionCode.apk';
    return APKDetails(
      versionName,
      [MapEntry(apkName, apkUrl)],
      AppNames(developer, appName),
      releaseDate: DateTime.parse(uploadTime),
    );
  }

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    var apiBaseUrl =
        'https://h5-api.appstore.vivo.com.cn/h5appstore/search/result-list?app_version=2100&page_index=1&apps_per_page=20&target=local&cfrom=2&key=';
    var searchUrl = '$apiBaseUrl${Uri.encodeQueryComponent(query)}';
    var response = await sourceRequest(searchUrl, {});
    if (response.statusCode != 200) {
      throw getObtainiumHttpError(response);
    }
    var json = jsonDecode(response.body);
    if (json['code'] != 0 || !json['data']['appSearchResponse']['result']) {
      throw NoReleasesError();
    }
    Map<String, List<String>> results = {};
    var resultsJson = json['data']['appSearchResponse']?['value'];
    if (resultsJson != null) {
      for (var item in (resultsJson as List<dynamic>)) {
        results['$appDetailUrl${item['id']}'] = [
          item['title_zh'].toString(),
          item['developer'].toString(),
        ];
      }
    }
    return results;
  }

  Future<Map<String, dynamic>> getDetailJson(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var vivoAppId = parseVivoAppId(standardUrl);
    var apiBaseUrl = 'https://h5-api.appstore.vivo.com.cn/detail/';
    var params = '?frompage=messageh5&app_version=2100';
    var detailUrl = '$apiBaseUrl$vivoAppId$params';
    var response = await sourceRequest(detailUrl, additionalSettings);
    if (response.statusCode != 200) {
      throw getObtainiumHttpError(response);
    }
    var json = jsonDecode(response.body);
    if (json['id'] == null) {
      throw NoReleasesError();
    }
    return json;
  }

  String parseVivoAppId(String url) {
    var appId = Uri.parse(url.replaceAll('/#', '')).queryParameters['appId'];
    if (appId == null || appId.isEmpty) {
      throw InvalidURLError(name);
    }
    return appId;
  }
}
