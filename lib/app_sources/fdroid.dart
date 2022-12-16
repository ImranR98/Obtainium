import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class FDroid extends AppSource {
  FDroid() {
    host = 'f-droid.org';
    name = tr('fdroid');
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
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) => null;

  @override
  String? tryInferringAppId(String standardUrl,
      {List<String> additionalData = const []}) {
    return Uri.parse(standardUrl).pathSegments.last;
  }

  APKDetails getAPKUrlsFromFDroidPackagesAPIResponse(
      Response res, String apkUrlPrefix, String standardUrl) {
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
      return APKDetails(latestVersion, apkUrls,
          AppNames(name, Uri.parse(standardUrl).pathSegments.last));
    } else {
      throw NoReleasesError();
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
      String standardUrl, List<String> additionalData,
      {bool trackOnly = false}) async {
    String? appId = tryInferringAppId(standardUrl);
    return getAPKUrlsFromFDroidPackagesAPIResponse(
        await get(Uri.parse('https://f-droid.org/api/v1/packages/$appId')),
        'https://f-droid.org/repo/$appId',
        standardUrl);
  }
}
