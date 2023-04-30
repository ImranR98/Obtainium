import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class VLC extends AppSource {
  VLC() {
    host = 'videolan.org';
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    return 'https://$host';
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    Response res = await get(
        Uri.parse('https://www.videolan.org/vlc/download-android.html'));
    if (res.statusCode == 200) {
      var dwUrlBase = 'get.videolan.org/vlc-android';
      var dwLinks = parse(res.body)
          .querySelectorAll('a')
          .where((element) =>
              element.attributes['href']?.contains(dwUrlBase) ?? false)
          .toList();
      String? version = dwLinks.isNotEmpty
          ? dwLinks.first.attributes['href']
              ?.split('/')
              .where((s) => s.isNotEmpty)
              .last
          : null;
      if (version == null) {
        throw NoVersionError();
      }
      String? targetUrl = 'https://$dwUrlBase/$version/';
      Response res2 = await get(Uri.parse(targetUrl));
      String mirrorDwBase =
          'https://plug-mirror.rcac.purdue.edu/vlc/vlc-android/$version/';
      List<String> apkUrls = [];
      if (res2.statusCode == 200) {
        apkUrls = parse(res2.body)
            .querySelectorAll('a')
            .map((e) => e.attributes['href'])
            .where((h) =>
                h != null && h.isNotEmpty && h.toLowerCase().endsWith('.apk'))
            .map((e) => mirrorDwBase + e!)
            .toList();
      } else {
        throw getObtainiumHttpError(res2);
      }

      return APKDetails(
          version, getApkUrlsFromUrls(apkUrls), AppNames('VideoLAN', 'VLC'));
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
