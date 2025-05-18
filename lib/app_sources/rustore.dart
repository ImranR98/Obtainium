import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_charset_detector/flutter_charset_detector.dart';
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

  Future<String> decodeString(String str) async {
    try {
      return (await CharsetDetector.autoDecode(
              Uint8List.fromList(str.codeUnits)))
          .string;
    } catch (e) {
      return str;
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    String? appId = await tryInferringAppId(standardUrl);
    Response res0 = await sourceRequest(
        'https://backapi.rustore.ru/applicationData/overallInfo/$appId',
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
    String? changeLog = appDetails['whatsNew'];
    if (version == null) {
      throw NoVersionError();
    }
    DateTime? relDate;
    if (dateStr != null) {
      relDate = DateTime.parse(dateStr);
    }

    Response res1 = await sourceRequest(
        'https://backapi.rustore.ru/applicationData/download-link',
        additionalSettings,
        followRedirects: false,
        postBody: {"appId": appDetails['appId'], "firstInstall": true});
    var downloadDetails = jsonDecode(res1.body)['body'];
    if (res1.statusCode != 200 || downloadDetails['apkUrl'] == null) {
      throw NoAPKError();
    }

    appName = await decodeString(appName);
    author = await decodeString(author);
    changeLog = changeLog != null ? await decodeString(changeLog) : null;

    return APKDetails(
        version,
        getApkUrlsFromUrls([
          (downloadDetails['apkUrl'] as String)
              .replaceAll(RegExp('\\.zip\$'), '.apk')
        ]),
        AppNames(author, appName),
        releaseDate: relDate,
        changeLog: changeLog);
  }
}
