import 'dart:convert';

import 'package:html/parser.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class RockMods extends AppSource {
  RockMods() {
    name = 'RockMods';
    hosts = ['rockmods.net'];
    enforceTrackOnly = true;
    naiveStandardVersionDetection = true;
    inferAppIdFromUrlPath = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    return standardizeUrlWithRegex(
      url,
      subdomainPrefix: r'(www\.)?',
      pathPattern: r'/apps/[^/]+',
    );
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final res = await sourceRequest(standardUrl, additionalSettings);
      if (res.statusCode != 200) {
        throw getObtainiumHttpError(res);
      }

      String? appName;
      String? appVersion;
      String? appAuthor;

      final jsonLdMatches = RegExp(
        '<script type="application/ld\\+json">(.*?)</script>',
        dotAll: true,
      ).allMatches(res.body);

      Map<dynamic, dynamic>? appJson;
      for (var m in jsonLdMatches) {
        final j = jsonDecode(m.group(1)!);
        if (j is Map && j['@type'] == 'SoftwareApplication') {
          appJson = j;
          break;
        }
      }

      if (appJson != null) {
        appName = (appJson['name'] as String?)?.trim();
        appVersion = (appJson['softwareVersion'] as String?)?.trim();
        final tmpAuthor = appJson['author'];
        if (tmpAuthor is Map) {
          appAuthor = tmpAuthor['name'] as String?;
        }
      }

      if (appName == null || appName.isEmpty) {
        final html = parse(res.body);
        final h1 = html.querySelector('h1');
        appName = h1?.text.trim() ?? standardUrl.split('/').last;
      }

      if (appVersion == null || appVersion.isEmpty) {
        throw NoVersionError();
      }

      return APKDetails(
        appVersion,
        getApkUrlsFromUrls([]),
        AppNames(appAuthor ?? name, appName),
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
