import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class WhatsApp extends AppSource {
  WhatsApp() {
    hosts = ['whatsapp.com'];
    versionDetectionDisallowed = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    return 'https://${hosts[0]}';
  }

  @override
  Future<String> apkUrlPrefetchModifier(String apkUrl, String standardUrl,
      Map<String, dynamic> additionalSettings) async {
    Response res =
        await sourceRequest('$standardUrl/android', additionalSettings);
    if (res.statusCode == 200) {
      var targetLinks = parse(res.body)
          .querySelectorAll('a')
          .map((e) => e.attributes['href'] ?? '')
          .where((e) => e.isNotEmpty)
          .where((e) => e.contains('WhatsApp.apk'))
          .toList();
      if (targetLinks.isEmpty) {
        throw NoAPKError();
      }
      return targetLinks[0];
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    // This is a CDN link that is consistent per version
    // But it has query params that change constantly
    Uri apkUri = Uri.parse(await apkUrlPrefetchModifier(
        standardUrl, standardUrl, additionalSettings));
    var unusableApkUrl = '${apkUri.origin}/${apkUri.path}';
    // So we use the param-less URL is a pseudo-version to add the app and check for updates
    // See #357 for why we can't scrape the version number directly
    // But we re-fetch the URL again with its latest query params at the actual download time
    String version = unusableApkUrl.hashCode.toString();
    return APKDetails(version, getApkUrlsFromUrls([unusableApkUrl]),
        AppNames('Meta', 'WhatsApp'));
  }
}
