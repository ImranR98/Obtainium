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
      caseSensitive: false,
    );
    var match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    return Uri.parse(standardUrl).pathSegments.last;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    String appId = (await tryInferringAppId(standardUrl))!;
    String baseHost = Uri.parse(
      standardUrl,
    ).host.split('.').reversed.toList().sublist(0, 2).reversed.join('.');

    var res = await sourceRequest(
      'https://a.app.$baseHost/o/simple.jsp?pkgname=$appId',
      additionalSettings,
      followRedirects: false,
    );

    if (res.statusCode == 200) {
      dynamic json;
      try {
        json = jsonDecode(
          res.body
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.startsWith('window.systemData='))
              .first
              .substring(18),
        )['appDetail'];
      } catch (e) {
        throw NoReleasesError();
      }
      if (json == null) {
        throw NoReleasesError();
      }
      var version = json['versionName'];
      var apkUrl = json['apkUrl64'];
      apkUrl ??= json['apkUrl'];
      if (apkUrl == null) {
        throw NoAPKError();
      }
      var appName = json['appName'];
      var author = json['author'];
      var apkName =
          Uri.parse(apkUrl).queryParameters['fsname'] ??
          '${appId}_$version.apk';

      return APKDetails(version, [
        MapEntry(apkName, apkUrl),
      ], AppNames(author, appName));
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
