import 'dart:convert';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Signal extends AppSource {
  Signal() {
    hosts = ['signal.org'];
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    return 'https://${hosts[0]}';
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    Response res = await sourceRequest(
        'https://updates.${hosts[0]}/android/latest.json', additionalSettings);
    if (res.statusCode == 200) {
      var json = jsonDecode(res.body);
      String? apkUrl = json['url'];
      List<String> apkUrls = apkUrl == null ? [] : [apkUrl];
      String? version = json['versionName'];
      if (version == null) {
        throw NoVersionError();
      }
      return APKDetails(
          version, getApkUrlsFromUrls(apkUrls), AppNames(name, 'Signal'));
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
