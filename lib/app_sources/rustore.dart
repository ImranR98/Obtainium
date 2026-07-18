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
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    return {'ruStoreVerCode': '1105002'};
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
      final Response overallInfoResponse = await sourceRequest(
        'https://backapi.rustore.ru/applicationData/overallInfo/$appId',
        additionalSettings,
      );
      if (overallInfoResponse.statusCode != 200) {
        throw getObtainiumHttpError(overallInfoResponse);
      }
      final decoded = await decodeJsonBody(overallInfoResponse.bodyBytes);
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

      final Response downloadLinksResponse = await sourceRequest(
        'https://backapi.rustore.ru/v3/showcase/apps/download-link',
        additionalSettings,
        followRedirects: false,
        postBody: {'appId': appDetails['appId'], 'firstInstall': true},
      );
      final downloadDetails = await decodeJsonBody(
        downloadLinksResponse.bodyBytes,
      );
      if (downloadLinksResponse.statusCode != 200 || downloadDetails == null) {
        throw getObtainiumHttpError(downloadLinksResponse);
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
