import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class RuStore extends AppSource {
  RuStore() {
    hosts = ['rustore.ru'];
    name = 'RuStore';
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegEx = RegExp(
        '^https?://(www\\.)?${getSourceRegex(hosts)}/catalog/app/+[^/]+',
        caseSensitive: false);
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
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
    String? appId = await tryInferringAppId(standardUrl);
    Response res0 = await sourceRequest(
        'https://backapi.${hosts[0]}/applicationData/overallInfo/${appId}',
        additionalSettings);
    if (res0.statusCode != 200) {
      throw getObtainiumHttpError(res0);
    }
    var appDetails = jsonDecode(res0.body)['body'];
    if (appDetails['appId'] == null) {
      throw NoReleasesError();
    }

    String appName = appDetails['appName'] ?? tr('app');
    String author = appDetails['companyName'] ?? name;
    String? dateStr = appDetails['updatedAt'];
    String? version = appDetails['versionName'];
    if (version == null) {
      throw NoVersionError();
    }
    DateTime? relDate;
    if (dateStr != null) {
      relDate = DateTime.parse(dateStr);
    }

    Response res1 = await sourceRequest(
        'https://backapi.${hosts[0]}/applicationData/download-link',
        additionalSettings,
        followRedirects: false,
        postBody: {"appId": appDetails['appId'], "firstInstall": true});
    var downloadDetails = jsonDecode(res0.body)['body'];
    if (res1.statusCode != 200 && downloadDetails['apkUrl'] == null) {
      throw NoAPKError();
    }

    return APKDetails(version, getApkUrlsFromUrls([downloadDetails['apkUrl']]),
        AppNames(author, appName),
        releaseDate: relDate);
  }
}
