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
    changeLogIfAnyIsMarkDown = false;
    inferAppIdFromUrlPath = true;
  }

  @override
  String sourceSpecificStandardizeURL(
    String url, {
    bool forSelection = false,
  }) => standardizeUrlWithRegex(
    url,
    subdomainPrefix: r'(www\.)?',
    pathPattern: r'/catalog/app/+[^/]+',
  );

  Future<dynamic> decodeJsonBody(Uint8List bytes) async {
    try {
      return jsonDecode((await CharsetDetector.autoDecode(bytes)).string);
    } catch (e) {
      return jsonDecode(utf8.decode(bytes));
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
      final Response res0 = await sourceRequest(
        'https://backapi.rustore.ru/applicationData/overallInfo/$appId',
        additionalSettings,
      );
      if (res0.statusCode != 200) {
        throw getObtainiumHttpError(res0);
      }
      final decoded = await decodeJsonBody(res0.bodyBytes);
      final appDetails = decoded is Map ? decoded['body'] : null;
      if (appDetails is! Map || appDetails['appId'] == null) {
        throw NoReleasesError();
      }

      final String appName = appDetails['appName'] ?? tr('app');
      final String author = appDetails['companyName'] ?? name;
      final String? dateStr = appDetails['appVerUpdatedAt'];
      final String? version = appDetails['versionName'];
      final String? changeLog = appDetails['whatsNew'];
      if (version == null || version.isEmpty) {
        throw NoVersionError();
      }
      DateTime? relDate;
      if (dateStr != null) {
        relDate = DateTime.tryParse(dateStr);
      }

      final Response res1 = await sourceRequest(
        'https://backapi.rustore.ru/applicationData/v2/download-link',
        additionalSettings,
        followRedirects: false,
        postBody: {'appId': appDetails['appId'], 'firstInstall': true},
      );
      final downloadDecoded = await decodeJsonBody(res1.bodyBytes);
      final downloadDetails = downloadDecoded is Map
          ? downloadDecoded['body']
          : null;
      if (res1.statusCode != 200 || downloadDetails == null) {
        throw getObtainiumHttpError(res1);
      }
      final url = downloadDetails['downloadUrls']?[0]?['url'] as String?;
      if (url == null) {
        throw NoAPKError();
      }

      return APKDetails(
        version,
        // RuStore returns a .zip URL for what is actually an APK.
        getApkUrlsFromUrls([url.replaceAll(RegExp(r'\.zip$'), '.apk')]),
        AppNames(author, appName),
        releaseDate: relDate,
        changeLog: changeLog,
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
