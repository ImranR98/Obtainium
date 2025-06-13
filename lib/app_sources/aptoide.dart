import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Aptoide extends AppSource {
  Aptoide() {
    hosts = ['aptoide.com'];
    name = 'Aptoide';
    allowSubDomains = true;
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegEx = RegExp(
      '^https?://([^\\.]+\\.){2,}${getSourceRegex(hosts)}',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
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
    return (await getAppDetailsJSON(
      standardUrl,
      additionalSettings,
    ))['package'];
  }

  Future<Map<String, dynamic>> getAppDetailsJSON(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var res = await sourceRequest(standardUrl, additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var idMatch = RegExp('"app":{"id":[0-9]+').firstMatch(res.body);
    String? id;
    if (idMatch != null) {
      id = res.body.substring(idMatch.start + 12, idMatch.end);
    } else {
      throw NoReleasesError();
    }
    var res2 = await sourceRequest(
      'https://ws2.aptoide.com/api/7/getApp/app_id/$id',
      additionalSettings,
    );
    if (res2.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    return jsonDecode(res2.body)?['nodes']?['meta']?['data'];
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var appDetails = await getAppDetailsJSON(standardUrl, additionalSettings);
    String appName = appDetails['name'] ?? tr('app');
    String author = appDetails['developer']?['name'] ?? name;
    String? dateStr = appDetails['updated'];
    String? version = appDetails['file']?['vername'];
    String? apkUrl = appDetails['file']?['path'];
    if (version == null) {
      throw NoVersionError();
    }
    if (apkUrl == null) {
      throw NoAPKError();
    }
    DateTime? relDate;
    if (dateStr != null) {
      relDate = DateTime.parse(dateStr);
    }

    return APKDetails(
      version,
      getApkUrlsFromUrls([apkUrl]),
      AppNames(author, appName),
      releaseDate: relDate,
    );
  }
}
