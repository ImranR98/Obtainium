import 'dart:convert';

import 'package:html/parser.dart';
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
  Future<String> apkUrlPrefetchModifier(String apkUrl) async => apkUrl;

  @override
  String? tryGettingAppIdFromURL(String standardUrl) {
    return Uri.parse(standardUrl).pathSegments.last;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
      String standardUrl, List<String> additionalData) async {
    String? appId = tryGettingAppIdFromURL(standardUrl);
    Response res =
        await get(Uri.parse('https://f-droid.org/api/v1/packages/$appId'));
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
          .map((e) =>
              'https://f-droid.org/repo/${appId}_${e['versionCode']}.apk')
          .toList();
      if (apkUrls.isEmpty) {
        throw NoAPKError();
      }
      return APKDetails(latestVersion, apkUrls);
    } else {
      throw NoReleasesError();
    }
  }

  @override
  AppNames getAppNames(String standardUrl) {
    return AppNames('F-Droid', Uri.parse(standardUrl).pathSegments.last);
  }
}
