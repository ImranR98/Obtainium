import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Codeberg extends AppSource {
  final GitHub _gh = GitHub(hostChanged: true);
  Codeberg() {
    name = 'Forgejo (Codeberg)';
    hosts = ['codeberg.org'];
    canSearch = true;
  }

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems =>
      _gh.additionalSourceAppSpecificSettingFormItems;

  @override
  List<GeneratedFormItem> get searchQuerySettingFormItems =>
      _gh.searchQuerySettingFormItems;

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    return standardizeUrlWithRegex(
      url,
      subdomainPrefix: r'(www\.)?',
      pathPattern: r'/[^/]+/[^/]+',
    );
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/releases';

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      return await _gh.fetchReleaseDetailsWithTagFallback(
        standardUrl,
        additionalSettings,
        (bool useTagUrl) async {
          final standardUri = Uri.parse(standardUrl);
          final apiPath =
              '/api/v1/repos${standardUri.path}/${useTagUrl ? 'tags' : 'releases'}';
          return standardUri
              .replace(path: apiPath, queryParameters: {'per_page': '100'})
              .toString();
        },
        null,
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    return _gh.searchCommon(
      query,
      'https://${hosts[0]}/api/v1/repos/search?q=${Uri.encodeQueryComponent(query)}&limit=100',
      'data',
      querySettings: querySettings,
    );
  }
}
