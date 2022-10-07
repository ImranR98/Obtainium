import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/providers/source_provider.dart';

class FDroid implements AppSource {
  @override
  late String host = 'f-droid.org';

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegExB =
        RegExp('^https?://$host/+[^/]+/+packages/+[^/]+');
    RegExpMatch? match = standardUrlRegExB.firstMatch(url.toLowerCase());
    if (match != null) {
      url = 'https://$host/packages/${Uri.parse(url).pathSegments.last}';
    }
    RegExp standardUrlRegExA = RegExp('^https?://$host/+packages/+[^/]+');
    match = standardUrlRegExA.firstMatch(url.toLowerCase());
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
    Response res = await get(Uri.parse(standardUrl));
    if (res.statusCode == 200) {
      var latestReleaseDiv =
          parse(res.body).querySelector('#latest.package-version');
      var apkUrl = latestReleaseDiv
          ?.querySelector('.package-version-download a')
          ?.attributes['href'];
      if (apkUrl == null) {
        throw noAPKFound;
      }
      var version = latestReleaseDiv
          ?.querySelector('.package-version-header b')
          ?.innerHtml
          .split(' ')
          .last;
      if (version == null) {
        throw couldNotFindLatestVersion;
      }
      return APKDetails(version, [apkUrl]);
    } else {
      throw couldNotFindReleases;
    }
  }

  @override
  AppNames getAppNames(String standardUrl) {
    return AppNames('F-Droid', Uri.parse(standardUrl).pathSegments.last);
  }

  @override
  List<List<GeneratedFormItem>> additionalDataFormItems = [];

  @override
  List<String> additionalDataDefaults = [];

  @override
  List<GeneratedFormItem> moreSourceSettingsFormItems = [];
}
