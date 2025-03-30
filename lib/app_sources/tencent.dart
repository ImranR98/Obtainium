import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Tencent extends AppSource {
  Tencent() {
    name = tr('tencentAppStore');
    hosts = ['sj.qq.com'];
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegEx = RegExp(
        '^https?://${getSourceRegex(hosts)}/appdetail/[^/]+',
        caseSensitive: false);
    var match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  Future<String?> tryInferringAppId(String standardUrl,
      {Map<String, dynamic> additionalSettings = const {}}) async {
    return Uri.parse(standardUrl).pathSegments.last;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    String appId = (await tryInferringAppId(standardUrl))!;
    String baseHost = Uri.parse(standardUrl)
        .host
        .split('.')
        .reversed
        .toList()
        .sublist(0, 2)
        .reversed
        .join('.');

    var res = await sourceRequest(
        'https://upage.html5.$baseHost/wechat-apkinfo', additionalSettings,
        followRedirects: false, postBody: {"packagename": appId});

    if (res.statusCode == 200) {
      var json = jsonDecode(res.body);
      if (json['app_detail_records'][appId] == null) {
        throw NoReleasesError();
      }
      var version =
          json['app_detail_records'][appId]['apk_all_data']['version_name'];
      var apkUrl = json['app_detail_records'][appId]['apk_all_data']['url'];
      if (apkUrl == null) {
        throw NoAPKError();
      }
      var appName = json['app_detail_records'][appId]['app_info']['name'];
      var author = json['app_detail_records'][appId]['app_info']['author'];
      var releaseDate =
          json['app_detail_records'][appId]['app_info']['update_time'];
      var apkName = Uri.parse(apkUrl).queryParameters['fsname'] ??
          '${appId}_$version.apk';

      return APKDetails(
          version, [MapEntry(apkName, apkUrl)], AppNames(author, appName),
          releaseDate: releaseDate != null
              ? DateTime.fromMillisecondsSinceEpoch(releaseDate * 1000)
              : null);
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
