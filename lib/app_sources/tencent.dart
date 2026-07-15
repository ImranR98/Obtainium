import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Tencent extends AppSource {
  @override
  String get name => tr('tencentAppStore');

  Tencent() {
    hosts = ['sj.qq.com'];
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
    canSearch = true;
    regionalStore = true;
    // Base flag replaces the old manual `tryInferringAppId` override, which
    // merely returned the last path segment.
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

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final String appId = (await tryInferringAppId(standardUrl))!;

    final res = await sourceRequest(
      'https://sj.qq.com/appdetail/$appId',
      additionalSettings,
    );

    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }

    const nextDataPrefix = '<script id="__NEXT_DATA__"';
    final idx = res.body.indexOf(nextDataPrefix);
    if (idx == -1) throw NoReleasesError();
    final tagStart = res.body.indexOf('>', idx);
    final tagEnd = res.body.indexOf('</script>', tagStart);
    if (tagStart == -1 || tagEnd == -1) throw NoReleasesError();
    final jsonStr = res.body.substring(tagStart + 1, tagEnd).trim();

    dynamic json;
    try {
      json = jsonDecode(jsonStr);
    } catch (_) {
      throw NoReleasesError();
    }

    final dynamic appDetail = _findAppDetail(json, appId);
    if (appDetail == null) throw NoReleasesError();

    final version = appDetail['version_name']?.toString();
    final apkUrl = appDetail['download_url']?.toString();
    if (version == null || apkUrl == null || apkUrl.isEmpty) {
      throw NoAPKError();
    }
    final appName = appDetail['name']?.toString() ?? appId;
    final author = appDetail['developer']?.toString() ?? '';
    final apkName =
        Uri.parse(apkUrl).queryParameters['fsname'] ?? '${appId}_$version.apk';

    final iconUrl = appDetail['icon']?.toString();
    int? apkSizeBytes;
    try {
      final rawSize = appDetail['apk_size']?.toString();
      if (rawSize != null) {
        apkSizeBytes = int.parse(rawSize);
      }
    } catch (_) {}

    DateTime? releaseDate;
    try {
      final rawTime = appDetail['update_time']?.toString();
      if (rawTime != null) {
        releaseDate = DateTime.fromMillisecondsSinceEpoch(
          int.parse(rawTime) * 1000,
        );
      }
    } catch (_) {}

    return APKDetails(
      version,
      [MapEntry(apkName, apkUrl)],
      AppNames(author, appName),
      releaseDate: releaseDate,
      iconUrl: iconUrl,
      apkSizeBytes: apkSizeBytes,
    );
  }

  dynamic _findAppDetail(dynamic node, String pkgName) {
    if (node is Map) {
      if (node['pkg_name']?.toString() == pkgName &&
          node['download_url']?.toString().isNotEmpty == true) {
        return node;
      }
      for (var value in node.values) {
        final result = _findAppDetail(value, pkgName);
        if (result != null) return result;
      }
    } else if (node is List) {
      for (var item in node) {
        final result = _findAppDetail(item, pkgName);
        if (result != null) return result;
      }
    }
    return null;
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    return {
      'user-agent':
          'Mozilla/5.0 (Linux; Android 5.0; SM-G900P Build/LRX21T) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/147.0.7727.138 Safari/537.36',
    };
  }

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    final body = {
      'head': {
        'cmd': 'dc_pcyyb_official',
        'authInfo': {'businessId': 'AuthName'},
        'deviceInfo': {'platformType': 2, 'platform': 1},
        'userInfo': {'guid': '1933d8ef-501b-49a7-89a0-46cbcb38a122'},
        'expSceneIds': '',
        'hostAppInfo': {'scene': 'search_result'},
      },
      'body': {
        'bid': 'yybhome',
        'offset': 0,
        'size': 10,
        'preview': false,
        'listS': {
          'region': {
            'repStr': ['CN'],
          },
          'keyword': {
            'repStr': [query],
          },
        },
        'layout': 'yybn_search_result_list',
      },
    };
    final res = await sourceRequest(
      'https://yybadaccess.3g.qq.com/v2/dc_pcyyb_official',
      querySettings,
      postBody: body,
    );
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    final json = jsonDecode(res.body);
    if (json['ret'] != 0) {
      throw NoReleasesError();
    }
    final Map<String, List<String>> results = {};
    final components = json['data']?['components'] as List<dynamic>?;
    if (components != null && components.isNotEmpty) {
      final itemData = components[0]?['data']?['itemData'] as List<dynamic>?;
      if (itemData != null) {
        for (var item in itemData) {
          final pkgName = item['pkg_name']?.toString();
          if (pkgName == null || pkgName.isEmpty) continue;
          var url = 'https://sj.qq.com/appdetail/$pkgName';
          try {
            url = standardizeUrl(url);
          } catch (_) {
            continue;
          }
          final name = item['name']?.toString() ?? '';
          final desc = item['developer']?.toString() ?? tr('noDescription');
          results[url] = [name, desc];
        }
      }
    }
    return results;
  }
}
