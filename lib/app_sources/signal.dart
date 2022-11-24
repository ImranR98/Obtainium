import 'dart:convert';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Signal extends AppSource {
  Signal() {
    host = 'signal.org';
  }

  @override
  String standardizeURL(String url) {
    return 'https://$host';
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) => null;

  @override
  Future<APKDetails> getLatestAPKDetails(
      String standardUrl, List<String> additionalData) async {
    Response res =
        await get(Uri.parse('https://updates.$host/android/latest.json'));
    if (res.statusCode == 200) {
      var json = jsonDecode(res.body);
      String? apkUrl = json['url'];
      List<String> apkUrls = apkUrl == null ? [] : [apkUrl];
      String? version = json['versionName'];
      if (version == null) {
        throw NoVersionError();
      }
      return APKDetails(version, apkUrls);
    } else {
      throw NoReleasesError();
    }
  }

  @override
  AppNames getAppNames(String standardUrl) => AppNames('Signal', 'Signal');
}
