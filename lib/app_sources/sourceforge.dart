import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class SourceForge extends AppSource {
  SourceForge() {
    hosts = ['sourceforge.net'];
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    var sourceRegex = getSourceRegex(hosts);
    RegExp standardUrlRegExC = RegExp(
      '^https?://(www\\.)?$sourceRegex/p/.+',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegExC.firstMatch(url);
    if (match != null) {
      url =
          'https://${Uri.parse(match.group(0)!).host}/projects/${url.substring(Uri.parse(match.group(0)!).host.length + '/projects/'.length + 1)}';
    }
    RegExp standardUrlRegExB = RegExp(
      '^https?://(www\\.)?$sourceRegex/projects/[^/]+',
      caseSensitive: false,
    );
    match = standardUrlRegExB.firstMatch(url);
    if (match != null && match.group(0) == url) {
      url = '$url/files';
    }
    RegExp standardUrlRegExA = RegExp(
      '^https?://(www\\.)?$sourceRegex/projects/[^/]+/files(/.+)?',
      caseSensitive: false,
    );
    match = standardUrlRegExA.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var standardUri = Uri.parse(standardUrl);
    if (standardUri.pathSegments.length == 2) {
      standardUrl = '$standardUrl/files';
      standardUri = Uri.parse(standardUrl);
    }
    Response res = await sourceRequest(
      '${standardUri.origin}/${standardUri.pathSegments.sublist(0, 2).join('/')}/rss?path=/',
      additionalSettings,
    );
    if (res.statusCode == 200) {
      var parsedHtml = parse(res.body);
      var allDownloadLinks = parsedHtml
          .querySelectorAll('guid')
          .map((e) => e.innerHtml)
          .where((element) => element.startsWith(standardUrl))
          .toList();
      getVersion(String url) {
        try {
          var segments = url
              .substring(standardUrl.length)
              .split('/')
              .where((element) => element.isNotEmpty)
              .toList()
              .reversed
              .toList()
              .sublist(1)
              .reversed
              .toList();
          segments = segments.length > 1
              ? segments.reversed.toList().sublist(1).reversed.toList()
              : segments;
          var version = segments.isNotEmpty ? segments.join('/') : null;
          if (version != null) {
            try {
              var extractedVersion = extractVersion(
                additionalSettings['versionExtractionRegEx'] as String?,
                additionalSettings['matchGroupToUse'] as String?,
                version,
              );
              if (extractedVersion != null) {
                version = extractedVersion;
              }
            } catch (e) {
              if (e is NoVersionError) {
                version = null;
              } else {
                rethrow;
              }
            }
          }
          return version;
        } catch (e) {
          return null;
        }
      }

      var apkUrlListAllReleases = allDownloadLinks
          .where((element) => element.toLowerCase().endsWith('.apk/download'))
          .where((element) => getVersion(element) != null)
          .toList();
      if (apkUrlListAllReleases.isEmpty) {
        throw NoReleasesError();
      }
      String? version = getVersion(apkUrlListAllReleases[0]);
      if (version == null) {
        throw NoVersionError();
      }

      var apkUrlList =
          apkUrlListAllReleases // This can be used skipped for fallback support later
              .where((element) => getVersion(element) == version)
              .toList();
      var segments = standardUrl.split('/');
      return APKDetails(
        version,
        getApkUrlsFromUrls(apkUrlList),
        AppNames(name, segments[segments.indexOf('files') - 1]),
      );
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
