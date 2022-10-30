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
  Future<String> apkUrlPrefetchModifier(String apkUrl) async => apkUrl;

  @override
  Future<APKDetails> getLatestAPKDetails(
      String standardUrl, List<String> additionalData) async {
    Response res = await get(Uri.parse(standardUrl));
    if (res.statusCode == 200) {
      var releases = parse(res.body).querySelectorAll('.package-version');
      if (releases.isEmpty) {
        throw couldNotFindReleases;
      }
      String? latestVersion = releases[0]
          .querySelector('.package-version-header b')
          ?.innerHtml
          .split(' ')
          .sublist(1)
          .join(' ');
      if (latestVersion == null) {
        throw couldNotFindLatestVersion;
      }
      List<String> apkUrls = releases
          .where((element) =>
              element
                  .querySelector('.package-version-header b')
                  ?.innerHtml
                  .split(' ')
                  .sublist(1)
                  .join(' ') ==
              latestVersion)
          .map((e) =>
              e
                  .querySelector('.package-version-download a')
                  ?.attributes['href'] ??
              '')
          .where((element) => element.isNotEmpty)
          .toList();
      if (apkUrls.isEmpty) {
        throw noAPKFound;
      }
      return APKDetails(latestVersion, apkUrls);
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
