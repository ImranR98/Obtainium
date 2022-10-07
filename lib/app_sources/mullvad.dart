import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/providers/source_provider.dart';

class Mullvad implements AppSource {
  @override
  late String host = 'mullvad.net';

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host');
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
    Response res = await get(Uri.parse('$standardUrl/en/download/android'));
    if (res.statusCode == 200) {
      var version = parse(res.body)
          .querySelector('p.subtitle.is-6')
          ?.querySelector('a')
          ?.attributes['href']
          ?.split('/')
          .last;
      if (version == null) {
        throw couldNotFindLatestVersion;
      }
      return APKDetails(
          version, ['https://mullvad.net/download/app/apk/latest']);
    } else {
      throw couldNotFindReleases;
    }
  }

  @override
  AppNames getAppNames(String standardUrl) {
    return AppNames('Mullvad-VPN', 'Mullvad-VPN');
  }

  @override
  List<List<GeneratedFormItem>> additionalDataFormItems = [];

  @override
  List<String> additionalDataDefaults = [];

  @override
  List<GeneratedFormItem> moreSourceSettingsFormItems = [];
}
