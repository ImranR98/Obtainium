import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class SourceForge extends AppSource {
  SourceForge() {
    host = 'sourceforge.net';
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/projects/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    Response res = await get(Uri.parse('$standardUrl/rss?path=/'));
    if (res.statusCode == 200) {
      var parsedHtml = parse(res.body);
      var allDownloadLinks =
          parsedHtml.querySelectorAll('guid').map((e) => e.innerHtml).toList();
      getVersion(String url) {
        try {
          var tokens = url.split('/');
          var fi = tokens.indexOf('files');
          return tokens[tokens[fi + 2] == 'download' ? fi - 1 : fi + 1];
        } catch (e) {
          return null;
        }
      }

      String? version = getVersion(allDownloadLinks[0]);
      if (version == null) {
        throw NoVersionError();
      }
      var apkUrlListAllReleases = allDownloadLinks
          .where((element) => element.toLowerCase().endsWith('.apk/download'))
          .toList();
      var apkUrlList =
          apkUrlListAllReleases // This can be used skipped for fallback support later
              .where((element) => getVersion(element) == version)
              .toList();
      return APKDetails(
          version,
          getApkUrlsFromUrls(apkUrlList),
          AppNames(
              name, standardUrl.substring(standardUrl.lastIndexOf('/') + 1)));
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
