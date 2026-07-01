import 'dart:convert';

import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

/// Fetches APKs from the last successful build of a Jenkins job.
///
/// The URL must point to a specific job (e.g. `https://jenkins.example.com/job/myapp`).
/// Version is the build number; release date is the build timestamp.
class Jenkins extends AppSource {
  Jenkins() {
    versionDetectionDisallowed = true;
    neverAutoSelect = true;
    showReleaseDateAsVersionToggle = true;
    changeLogPageIsStandardUrl = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegEx = RegExp('https?://[^/]+/job/[^/]+', caseSensitive: false);
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  String trimJobUrl(String url) => sourceSpecificStandardizeURL(url);

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
      DateTime? releaseDate;
      if (json['timestamp'] != null) {
        var ts = int.tryParse(json['timestamp'].toString());
        releaseDate = ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
      }
      var version = json['number'] == null
          ? null
          : (json['number'] as int).toString();
      if (version == null || version.isEmpty) {
        throw NoVersionError();
      }
      final artifacts = json['artifacts'] is List
          ? json['artifacts'] as List<dynamic>
          : <dynamic>[];
      var apkUrls = artifacts
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
                url.value.isNotEmpty && AppSource.isApkOrContainerFile(url.key),
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
