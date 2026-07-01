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
    return standardizeUrlWithRegex(
      url,
      subdomainPrefix: r'([^\.]+\.)+',
      pathPattern: '',
    );
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
    final res = await sourceRequest(standardUrl, additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    final idMatch = RegExp(
      r'"app"\s*:\s*\{\s*"id"\s*:\s*([0-9]+)',
    ).firstMatch(res.body);
    String? id;
    if (idMatch != null) {
      id = idMatch.group(1)!;
    } else {
      throw NoReleasesError();
    }
    final res2 = await sourceRequest(
      'https://ws2.aptoide.com/api/7/getApp/app_id/$id',
      additionalSettings,
    );
    if (res2.statusCode != 200) {
      throw getObtainiumHttpError(res2);
    }
    final data = jsonDecode(res2.body)?['nodes']?['meta']?['data'];
    if (data == null) {
      throw NoReleasesError();
    }
    return data;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final appDetails = await getAppDetailsJSON(
        standardUrl,
        additionalSettings,
      );
      final String appName = appDetails['name'] ?? tr('app');
      final String author = appDetails['developer']?['name'] ?? name;
      final String? dateStr = appDetails['updated'];
      final String? version = appDetails['file']?['vername'];
      final String? apkUrl = appDetails['file']?['path'];
      if (version == null || version.isEmpty) {
        throw NoVersionError();
      }
      if (apkUrl == null) {
        throw NoAPKError();
      }
      DateTime? relDate;
      if (dateStr != null) {
        relDate = DateTime.tryParse(dateStr);
      }

      return APKDetails(
        version,
        getApkUrlsFromUrls([apkUrl]),
        AppNames(author, appName),
        releaseDate: relDate,
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
