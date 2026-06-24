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
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegEx = RegExp(
      '^https?://(www\\.)?${getSourceRegex(hosts)}/apps/[^/]+',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    return Uri.parse(standardUrl).pathSegments.last;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      var res = await sourceRequest(standardUrl, additionalSettings);
      if (res.statusCode != 200) {
        throw getObtainiumHttpError(res);
      }

      String? appName;
      String? appVersion;
      String? appAuthor;

      var jsonLdMatch = RegExp(
        '<script type="application/ld\\+json">(.*?)</script>',
        dotAll: true,
      ).firstMatch(res.body);

      if (jsonLdMatch != null) {
        var json = jsonDecode(jsonLdMatch.group(1)!);
        if (json is Map && json['@type'] == 'SoftwareApplication') {
          appName = (json['name'] as String?)?.trim();
          appVersion = (json['softwareVersion'] as String?)?.trim();
          appAuthor = (json['author'] as Map?)?['name'] as String?;
        }
      }

      if (appName == null || appName.isEmpty) {
        var html = parse(res.body);
        var h1 = html.querySelector('h1');
        appName = h1?.text?.trim() ?? standardUrl.split('/').last;
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
      if (e is ObtainiumError) rethrow;
      throw ObtainiumError('RockMods Error: $e');
    }
  }
}
