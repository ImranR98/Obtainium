import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class VivoAppStore extends AppSource {
  static const appDetailUrl =
      'https://detail-browser.vivo.com.cn/v115/index.html?appId=';
  static const appDetailJsonUrl =
      'https://h5-api.appstore.vivo.com.cn/detailInfo?appId=';
  static const apkDownloadUrl =
      'https://appstore.vivo.com.cn/appinfo/downloadApkFile?id=';
  static const appSearchUrl =
      'https://h5-api.appstore.vivo.com.cn/h5appstore/search/result-list?app_version=2100&page_index=1&apps_per_page=20&target=local&cfrom=2&key=';

  @override
  String get name => tr('vivoAppStore');

  VivoAppStore() {
    hosts = [
      'h5.appstore.vivo.com.cn',
      'h5coml.vivo.com.cn',
      'detail-browser.vivo.com.cn',
    ];
    naiveStandardVersionDetection = true;
    canSearch = true;
    allowOverride = false;
    // Vivo's download/detail endpoints redirect to plain-HTTP CDN URLs.
    allowInsecureRedirects = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    final vivoAppId = parseVivoAppId(url);
    return '$appDetailUrl$vivoAppId';
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    final json = await getDetailJson(standardUrl, additionalSettings);
    return _packageName(json['package_name']);
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final json = await getDetailJson(standardUrl, additionalSettings);
      final versionName = json['version_name']?.toString().trim();
      final id = json['id']?.toString().trim();
      if (versionName == null || versionName.isEmpty) {
        throw NoVersionError();
      }
      if (id == null || id.isEmpty) {
        throw NoAPKError();
      }
      final apkUrl = '$apkDownloadUrl${Uri.encodeQueryComponent(id)}';
      final packageName = _packageName(json['package_name']);
      final appName = json['title_zh']?.toString().trim();
      final versionCode = json['version_code']?.toString() ?? '';
      final developer = json['developer']?.toString().trim();
      final uploadTime = json['upload_time']?.toString();
      final apkName = '${packageName ?? ''}_$versionCode.apk';
      return APKDetails(
        versionName,
        [MapEntry(apkName, apkUrl)],
        AppNames(
          developer != null && developer.isNotEmpty ? developer : name,
          appName != null && appName.isNotEmpty
              ? appName
              : packageName ?? tr('app'),
        ),
        releaseDate: uploadTime != null ? DateTime.tryParse(uploadTime) : null,
        appId: packageName,
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    final searchUrl = '$appSearchUrl${Uri.encodeQueryComponent(query)}';
    final response = await sourceRequest(searchUrl, {});
    ensureHttpSuccess(response);
    final json = jsonDecode(response.body);
    if (json['code'] != 0 ||
        json['data']?['appSearchResponse']?['result'] != true) {
      throw NoReleasesError();
    }
    final Map<String, List<String>> results = {};
    final resultsJson = json['data']?['appSearchResponse']?['value'];
    if (resultsJson is List) {
      for (final item in resultsJson) {
        if (item is! Map) continue;
        final rawId = item['id'];
        if (rawId is! String && rawId is! num) continue;
        final id = rawId.toString().trim();
        final title = item['title_zh'];
        if (id.isEmpty || title is! String || title.trim().isEmpty) continue;
        final developer = item['developer']?.toString().trim();
        results['$appDetailUrl${Uri.encodeQueryComponent(id)}'] = [
          title.trim(),
          developer != null && developer.isNotEmpty ? developer : name,
        ];
      }
    }
    return results;
  }

  Future<Map<String, dynamic>> getDetailJson(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final vivoAppId = parseVivoAppId(standardUrl);
    final detailUrl = '$appDetailJsonUrl${Uri.encodeComponent(vivoAppId)}';
    final response = await sourceRequest(detailUrl, additionalSettings);
    ensureHttpSuccess(response);
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic> ||
        json['id']?.toString().trim().isNotEmpty != true) {
      throw NoReleasesError();
    }
    return json;
  }

  String parseVivoAppId(String url) {
    final appId = Uri.parse(
      url.replaceFirst('/#', ''),
    ).queryParameters['appId'];
    if (appId == null || appId.isEmpty) {
      throw InvalidURLError(name);
    }
    return appId;
  }

  String? _packageName(Object? value) {
    if (value is! String) return null;
    final package = value.trim();
    return RegExp(
          r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
        ).hasMatch(package)
        ? package
        : null;
  }
}
