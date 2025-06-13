import 'dart:convert';

import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Jenkins extends AppSource {
  Jenkins() {
    versionDetectionDisallowed = true;
    neverAutoSelect = true;
    showReleaseDateAsVersionToggle = true;
  }

  String trimJobUrl(String url) {
    RegExp standardUrlRegEx = RegExp('.*/job/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/-/releases';

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    standardUrl = trimJobUrl(standardUrl);
    Response res = await sourceRequest(
      '$standardUrl/lastSuccessfulBuild/api/json',
      additionalSettings,
    );
    if (res.statusCode == 200) {
      var json = jsonDecode(res.body);
      var releaseDate = json['timestamp'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int);
      var version = json['number'] == null
          ? null
          : (json['number'] as int).toString();
      if (version == null) {
        throw NoVersionError();
      }
      var apkUrls = (json['artifacts'] as List<dynamic>)
          .map((e) {
            var path = (e['relativePath'] as String?);
            if (path != null && path.isNotEmpty) {
              path = '$standardUrl/lastSuccessfulBuild/artifact/$path';
            }
            return path == null
                ? const MapEntry<String, String>('', '')
                : MapEntry<String, String>(
                    (e['fileName'] ?? e['relativePath']) as String,
                    path,
                  );
          })
          .where(
            (url) =>
                url.value.isNotEmpty && url.key.toLowerCase().endsWith('.apk'),
          )
          .toList();
      return APKDetails(
        version,
        apkUrls,
        releaseDate: releaseDate,
        AppNames(Uri.parse(standardUrl).host, standardUrl.split('/').last),
      );
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
