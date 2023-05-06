import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class FDroid extends AppSource {
  FDroid() {
    host = 'f-droid.org';
    name = tr('fdroid');
    canSearch = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    RegExp standardUrlRegExB =
        RegExp('^https?://$host/+[^/]+/+packages/+[^/]+');
    RegExpMatch? match = standardUrlRegExB.firstMatch(url.toLowerCase());
    if (match != null) {
      url =
          'https://${Uri.parse(url.substring(0, match.end)).host}/packages/${Uri.parse(url).pathSegments.last}';
    }
    RegExp standardUrlRegExA = RegExp('^https?://$host/+packages/+[^/]+');
    match = standardUrlRegExA.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
  }

  @override
  String? tryInferringAppId(String standardUrl,
      {Map<String, dynamic> additionalSettings = const {}}) {
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
      return APKDetails(latestVersion, getApkUrlsFromUrls(apkUrls),
          AppNames(name, Uri.parse(standardUrl).pathSegments.last));
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    String? appId = tryInferringAppId(standardUrl);
    String host = Uri.parse(standardUrl).host;
    return getAPKUrlsFromFDroidPackagesAPIResponse(
        await sourceRequest('https://$host/api/v1/packages/$appId'),
        'https://$host/repo/$appId',
        standardUrl);
  }

  @override
  Future<Map<String, List<String>>> search(String query) async {
    Response res = await sourceRequest(
        'https://search.$host/?q=${Uri.encodeQueryComponent(query)}');
    if (res.statusCode == 200) {
      Map<String, List<String>> urlsWithDescriptions = {};
      parse(res.body).querySelectorAll('.package-header').forEach((e) {
        String? url = e.attributes['href'];
        if (url != null) {
          try {
            standardizeUrl(url);
          } catch (e) {
            url = null;
          }
        }
        if (url != null) {
          urlsWithDescriptions[url] = [
            e.querySelector('.package-name')?.text.trim() ?? '',
            e.querySelector('.package-summary')?.text.trim() ??
                tr('noDescription')
          ];
        }
      });
      return urlsWithDescriptions;
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
