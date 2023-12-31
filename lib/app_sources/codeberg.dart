import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Codeberg extends AppSource {
  GitHub gh = GitHub();
  Codeberg() {
    host = 'codeberg.org';

    additionalSourceAppSpecificSettingFormItems =
        gh.additionalSourceAppSpecificSettingFormItems;

    canSearch = true;
    searchQuerySettingFormItems = gh.searchQuerySettingFormItems;
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://(www\\.)?$host/[^/]+/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/releases';

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    return await gh.getLatestAPKDetailsCommon2(standardUrl, additionalSettings,
        (bool useTagUrl) async {
      return 'https://$host/api/v1/repos${standardUrl.substring('https://$host'.length)}/${useTagUrl ? 'tags' : 'releases'}?per_page=100';
    }, null);
  }

  AppNames getAppNames(String standardUrl) {
    String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    List<String> names = temp.substring(temp.indexOf('/') + 1).split('/');
    return AppNames(names[0], names[1]);
  }

  @override
  Future<Map<String, List<String>>> search(String query,
      {Map<String, dynamic> querySettings = const {}}) async {
    return gh.searchCommon(
        query,
        'https://$host/api/v1/repos/search?q=${Uri.encodeQueryComponent(query)}&limit=100',
        'data',
        querySettings: querySettings);
  }
}
