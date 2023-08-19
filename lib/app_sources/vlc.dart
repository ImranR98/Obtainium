import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class VLC extends AppSource {
  VLC() {
    host = 'videolan.org';
  }
  get dwUrlBase => 'https://get.$host/vlc-android/';

  @override
  Map<String, String>? get requestHeaders => HTML().requestHeaders;

  @override
  String sourceSpecificStandardizeURL(String url) {
    return 'https://$host';
  }

  Future<String?> getLatestVersion(String standardUrl) async {
    Response res = await sourceRequest(dwUrlBase);
    if (res.statusCode == 200) {
      var dwLinks = parse(res.body)
          .querySelectorAll('a')
          .where((element) => element.attributes['href'] != 'last/')
          .map((e) => e.attributes['href']?.split('/')[0])
          .toList();
      String? version = dwLinks.isNotEmpty ? dwLinks.last : null;
      if (version == null) {
        throw NoVersionError();
      }
      return version;
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    String? version = await getLatestVersion(standardUrl);
    if (version == null) {
      throw NoVersionError();
    }
    String? targetUrl = '$dwUrlBase$version/';
    Response res = await sourceRequest(targetUrl);
    List<String> apkUrls = [];
    if (res.statusCode == 200) {
      apkUrls = parse(res.body)
          .querySelectorAll('a')
          .map((e) => e.attributes['href']?.split('/').last)
          .where((h) =>
              h != null && h.isNotEmpty && h.toLowerCase().endsWith('.apk'))
          .map((e) => targetUrl + e!)
          .toList();
    } else {
      throw getObtainiumHttpError(res);
    }

    return APKDetails(
        version, getApkUrlsFromUrls(apkUrls), AppNames('VideoLAN', 'VLC'));
  }

  @override
  Future<String> apkUrlPrefetchModifier(
      String apkUrl, String standardUrl) async {
    Response res = await sourceRequest(apkUrl);
    if (res.statusCode == 200) {
      String? apkUrl =
          parse(res.body).querySelector('#alt_link')?.attributes['href'];
      if (apkUrl == null) {
        throw NoAPKError();
      }
      return apkUrl;
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
