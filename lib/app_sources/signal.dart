import 'dart:convert';
import 'package:http/http.dart';
import 'package:obtainium/providers/source_provider.dart';

class Signal implements AppSource {
  @override
  late String host = 'signal.org';

  @override
  String standardizeURL(String url) {
    return 'https://$host';
  }

  @override
  Future<APKDetails> getLatestAPKDetails(String standardUrl) async {
    Response res =
        await get(Uri.parse('https://updates.$host/android/latest.json'));
    if (res.statusCode == 200) {
      var json = jsonDecode(res.body);
      String? apkUrl = json['url'];
      if (apkUrl == null) {
        throw noAPKFound;
      }
      String? version = json['versionName'];
      if (version == null) {
        throw couldNotFindLatestVersion;
      }
      return APKDetails(version, [apkUrl]);
    } else {
      throw couldNotFindReleases;
    }
  }

  @override
  AppNames getAppNames(String standardUrl) => AppNames('Signal', 'Signal');
}
