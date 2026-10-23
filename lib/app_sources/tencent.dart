import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Tencent extends AppSource {
  @override
  String get name => tr('tencentAppStore');

  Tencent() {
    hosts = ['sj.qq.com'];
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
    inferAppIdFromUrlPath = true;
  }

  @override
  String sourceSpecificStandardizeURL(
    String url, {
    bool forSelection = false,
  }) => standardizeUrlWithRegex(
    url,
    subdomainPrefix: '',
    pathPattern: r'/appdetail/[^/]+',
  );

  Future<DateTime?> _getReleaseDate(
    String appId,
    String version,
    String apkUrl,
    Map<String, dynamic> metadata,
    Map<String, dynamic> settings,
  ) async {
    final digest = metadata['apkMd5']?.toString().toLowerCase() ?? '';
    final fileSize = metadata['fileSize'];
    final size = int.tryParse(
      (fileSize is Map ? fileSize['bytes'] : null)?.toString() ?? '',
    );
    if (apkUrl != metadata['apkUrl'] ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(digest) ||
        size == null ||
        size <= 0) {
      return null;
    }
    try {
      final response = await sourceRequest(
        'https://sj.qq.com/appdetail/${Uri.encodeComponent(appId)}',
        settings,
        followRedirects: false,
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.length > 2000000) {
        return null;
      }
      final scripts = parse(
        response.body,
      ).querySelectorAll('script#__NEXT_DATA__');
      if (scripts.length != 1) return null;
      final page = jsonDecode(scripts.single.text);
      final components =
          page['props']['pageProps']['dynamicCardResponse']['data']['components'];
      if (components is! List) return null;
      final records = <Map>[];
      for (final component in components) {
        if (component is! Map ||
            component['cardId'] != 'yybn_game_basic_info' ||
            component['data'] is! Map) {
          continue;
        }
        final data = component['data'] as Map;
        final items = data['itemData'];
        if (data['name'] != 'GameDetail' ||
            data['cardid'] != 'yybn_game_basic_info' ||
            items is! List) {
          continue;
        }
        records.addAll(
          items.whereType<Map>().where((item) => item['pkg_name'] == appId),
        );
      }
      if (records.length != 1) return null;
      final record = records.single;
      if (record['version_name'] != version ||
          record['md_5']?.toString().toLowerCase() != digest ||
          int.tryParse(record['apk_size']?.toString() ?? '') != size) {
        return null;
      }
      final timestamp = int.tryParse(record['update_time']?.toString() ?? '');
      if (timestamp == null ||
          timestamp <= 0 ||
          timestamp >
              DateTime.now()
                      .add(const Duration(days: 1))
                      .millisecondsSinceEpoch ~/
                  1000) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
    } catch (e) {
      AppLogger.info('Tencent release date unavailable: ${e.runtimeType}');
      return null;
    }
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
      final String baseHost = Uri.parse(
        standardUrl,
      ).host.split('.').reversed.toList().sublist(0, 2).reversed.join('.');

      final res = await sourceRequest(
        'https://a.app.$baseHost/o/simple.jsp?pkgname=$appId',
        additionalSettings,
        followRedirects: false,
      );

      if (res.statusCode == 200) {
        dynamic json;
        const jsVar = 'window.systemData=';
        try {
          json = jsonDecode(
            res.body
                .split('\n')
                .map((line) => line.trim())
                .where((line) => line.startsWith(jsVar))
                .first
                .substring(jsVar.length),
          )['appDetail'];
        } catch (e) {
          throw NoReleasesError();
        }
        if (json == null) {
          throw NoReleasesError();
        }
        final String? version = json['versionName']?.toString();
        String? apkUrl = json['apkUrl64']?.toString();
        apkUrl ??= json['apkUrl']?.toString();
        if (apkUrl == null) {
          throw NoAPKError();
        }
        if (version == null || version.isEmpty) {
          throw NoVersionError();
        }
        final String appName = json['appName']?.toString() ?? tr('app');
        final String author = json['author']?.toString() ?? name;
        final apkName =
            Uri.parse(apkUrl).queryParameters['fsname'] ??
            '${appId}_$version.apk';

        return APKDetails(
          version,
          [MapEntry(apkName, apkUrl)],
          AppNames(author, appName),
          releaseDate: await _getReleaseDate(
            appId,
            version,
            apkUrl,
            json,
            additionalSettings,
          ),
        );
      } else {
        throw getObtainiumHttpError(res);
      }
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
