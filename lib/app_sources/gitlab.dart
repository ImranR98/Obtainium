import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class GitLab extends AppSource {
  GitLab() {
    host = 'gitlab.com';
  }

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/[^/]+/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/-/releases';

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    Response res = await get(Uri.parse('$standardUrl/-/tags?format=atom'));
    if (res.statusCode == 200) {
      var standardUri = Uri.parse(standardUrl);
      var parsedHtml = parse(res.body);
      var entry = parsedHtml.querySelector('entry');
      var entryContent =
          parse(parseFragment(entry?.querySelector('content')!.innerHtml).text);
      var apkUrls = [
        ...getLinksFromParsedHTML(
            entryContent,
            RegExp(
                '^${standardUri.path.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (x) {
                  return '\\${x[0]}';
                })}/uploads/[^/]+/[^/]+\\.apk\$',
                caseSensitive: false),
            standardUri.origin),
        // GitLab releases may contain links to externally hosted APKs
        ...getLinksFromParsedHTML(entryContent,
                RegExp('/[^/]+\\.apk\$', caseSensitive: false), '')
            .where((element) => Uri.parse(element).host != '')
            .toList()
      ];

      var entryId = entry?.querySelector('id')?.innerHtml;
      var version =
          entryId == null ? null : Uri.parse(entryId).pathSegments.last;
      var releaseDateString = entry?.querySelector('updated')?.innerHtml;
      DateTime? releaseDate =
          releaseDateString != null ? DateTime.parse(releaseDateString) : null;
      if (version == null) {
        throw NoVersionError();
      }
      return APKDetails(version, apkUrls, GitHub().getAppNames(standardUrl),
          releaseDate: releaseDate);
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
