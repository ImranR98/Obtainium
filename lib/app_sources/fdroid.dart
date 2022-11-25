import 'dart:convert';

import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class FDroid extends AppSource {
  FDroid() {
    host = 'f-droid.org';
  }

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegExB =
        RegExp('^https?://$host/+[^/]+/+packages/+[^/]+');
    RegExpMatch? match = standardUrlRegExB.firstMatch(url.toLowerCase());
    if (match != null) {
      url = 'https://$host/packages/${Uri.parse(url).pathSegments.last}';
    }
    RegExp standardUrlRegExA = RegExp('^https?://$host/+packages/+[^/]+');
    match = standardUrlRegExA.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(runtimeType.toString());
    }
    return url.substring(0, match.end);
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) => null;

  @override
  String? tryInferringAppId(String standardUrl) {
    return Uri.parse(standardUrl).pathSegments.last;
  }

  APKDetails getAPKUrlsFromFDroidPackagesAPIResponse(
      Response res, String apkUrlPrefix) {
    if (res.statusCode == 200) {
      List<dynamic> releases = jsonDecode(res.body)['packages'] ?? [];
      if (releases.isEmpty) {
        throw NoReleasesError();
      }
      String? latestVersion = releases[0]['versionName'];
      if (latestVersion == null) {
        throw NoVersionError();
      }
      List<String> apkUrls = releases
          .where((element) => element['versionName'] == latestVersion)
          .map((e) => '${apkUrlPrefix}_${e['versionCode']}.apk')
          .toList();
      return APKDetails(latestVersion, apkUrls);
    } else {
      throw NoReleasesError();
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
      String standardUrl, List<String> additionalData) async {
    String? appId = tryInferringAppId(standardUrl);
    return getAPKUrlsFromFDroidPackagesAPIResponse(
        await get(Uri.parse('https://f-droid.org/api/v1/packages/$appId')),
        'https://f-droid.org/repo/$appId');
  }

  @override
  AppNames getAppNames(String standardUrl) {
    return AppNames('F-Droid', Uri.parse(standardUrl).pathSegments.last);
  }
}
