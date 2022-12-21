import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class APKMirror extends AppSource {
  APKMirror() {
    host = 'apkmirror.com';
    enforceTrackOnly = true;
  }

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/apk/[^/]+/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/#whatsnew';

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    Response res = await get(Uri.parse('$standardUrl/feed'));
    if (res.statusCode == 200) {
      String? titleString = parse(res.body)
          .querySelector('item')
          ?.querySelector('title')
          ?.innerHtml;
      String? version = titleString
          ?.substring(RegExp('[0-9]').firstMatch(titleString)?.start ?? 0,
              RegExp(' by ').firstMatch(titleString)?.start ?? 0)
          .trim();
      if (version == null || version.isEmpty) {
        version = titleString;
      }
      if (version == null || version.isEmpty) {
        throw NoVersionError();
      }
      return APKDetails(version, [], getAppNames(standardUrl));
    } else {
      throw NoReleasesError();
    }
  }

  AppNames getAppNames(String standardUrl) {
    String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    List<String> names = temp.substring(temp.indexOf('/') + 1).split('/');
    return AppNames(names[1], names[2]);
  }
}
