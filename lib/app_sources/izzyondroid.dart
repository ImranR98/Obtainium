import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/providers/source_provider.dart';

class IzzyOnDroid implements AppSource {
  @override
  late String host = 'android.izzysoft.de';

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/repo/apk/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw notValidURL(runtimeType.toString());
    }
    return url.substring(0, match.end);
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
      String standardUrl, List<String> additionalData) async {
    Response res = await get(Uri.parse(standardUrl));
    if (res.statusCode == 200) {
      var parsedHtml = parse(res.body);
      var multipleVersionApkUrls = parsedHtml
          .querySelectorAll('a')
          .where((element) =>
              element.attributes['href']?.toLowerCase().endsWith('.apk') ??
              false)
          .map((e) => 'https://$host${e.attributes['href'] ?? ''}')
          .toList();
      if (multipleVersionApkUrls.isEmpty) {
        throw noAPKFound;
      }
      var version = parsedHtml
          .querySelector('#keydata')
          ?.querySelectorAll('b')
          .where(
              (element) => element.innerHtml.toLowerCase().contains('version'))
          .toList()[0]
          .parentNode
          ?.parentNode
          ?.children[1]
          .innerHtml;
      if (version == null) {
        throw couldNotFindLatestVersion;
      }
      return APKDetails(version, [multipleVersionApkUrls[0]]);
    } else {
      throw couldNotFindReleases;
    }
  }

  @override
  AppNames getAppNames(String standardUrl) {
    return AppNames('IzzyOnDroid', Uri.parse(standardUrl).pathSegments.last);
  }

  @override
  List<List<GeneratedFormItem>> additionalDataFormItems = [];

  @override
  List<String> additionalDataDefaults = [];
}
