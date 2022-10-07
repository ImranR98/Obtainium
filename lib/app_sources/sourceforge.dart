import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/providers/source_provider.dart';

class SourceForge implements AppSource {
  @override
  late String host = 'sourceforge.net';

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/projects/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw notValidURL(runtimeType.toString());
    }
    return url.substring(0, match.end);
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) => null;

  @override
  Future<APKDetails> getLatestAPKDetails(
      String standardUrl, List<String> additionalData) async {
    Response res = await get(Uri.parse('$standardUrl/rss?path=/'));
    if (res.statusCode == 200) {
      var parsedHtml = parse(res.body);
      var allDownloadLinks =
          parsedHtml.querySelectorAll('guid').map((e) => e.innerHtml).toList();
      getVersion(String url) {
        try {
          var tokens = url.split('/');
          return tokens[tokens.length - 3];
        } catch (e) {
          return null;
        }
      }

      String? version = getVersion(allDownloadLinks[0]);
      if (version == null) {
        throw couldNotFindLatestVersion;
      }
      var apkUrlListAllReleases = allDownloadLinks
          .where((element) => element.toLowerCase().endsWith('.apk/download'))
          .toList();
      var apkUrlList =
          apkUrlListAllReleases // This can be used skipped for fallback support later
              .where((element) => getVersion(element) == version)
              .toList();
      if (apkUrlList.isEmpty) {
        throw noAPKFound;
      }
      return APKDetails(version, apkUrlList);
    } else {
      throw couldNotFindReleases;
    }
  }

  @override
  AppNames getAppNames(String standardUrl) {
    return AppNames(runtimeType.toString(),
        standardUrl.substring(standardUrl.lastIndexOf('/') + 1));
  }

  @override
  List<List<GeneratedFormItem>> additionalDataFormItems = [];

  @override
  List<String> additionalDataDefaults = [];

  @override
  List<GeneratedFormItem> moreSourceSettingsFormItems = [];
}
