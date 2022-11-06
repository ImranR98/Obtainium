import 'dart:convert';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Signal implements AppSource {
  @override
  late String host = 'signal.org';

  @override
  String standardizeURL(String url) {
    return 'https://$host';
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) => null;

  @override
  Future<String> apkUrlPrefetchModifier(String apkUrl) async => apkUrl;

  @override
  Future<APKDetails> getLatestAPKDetails(
      String standardUrl, List<String> additionalData) async {
    Response res =
        await get(Uri.parse('https://updates.$host/android/latest.json'));
    if (res.statusCode == 200) {
      var json = jsonDecode(res.body);
      String? apkUrl = json['url'];
      if (apkUrl == null) {
        throw NoAPKError();
      }
      String? version = json['versionName'];
      if (version == null) {
        throw NoVersionError();
      }
      return APKDetails(version, [apkUrl]);
    } else {
      throw NoReleasesError();
    }
  }

  @override
  AppNames getAppNames(String standardUrl) => AppNames('Signal', 'Signal');

  @override
  List<List<GeneratedFormItem>> additionalDataFormItems = [];

  @override
  List<String> additionalDataDefaults = [];

  @override
  List<GeneratedFormItem> moreSourceSettingsFormItems = [];
}
