import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class WhatsApp extends AppSource {
  WhatsApp() {
    host = 'whatsapp.com';
  }

  @override
  String standardizeURL(String url) {
    return 'https://$host';
  }

  @override
  Future<String> apkUrlPrefetchModifier(String apkUrl) async {
    Response res = await get(Uri.parse('https://www.whatsapp.com/android'));
    if (res.statusCode == 200) {
      var targetLinks = parse(res.body)
          .querySelectorAll('a')
          .map((e) => e.attributes['href'])
          .where((e) => e != null)
          .where((e) =>
              e!.contains('scontent.whatsapp.net') &&
              e.contains('WhatsApp.apk'))
          .toList();
      if (targetLinks.isEmpty) {
        throw NoAPKError();
      }
      return targetLinks[0]!;
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    Response res = await get(Uri.parse('https://www.whatsapp.com/android'));
    if (res.statusCode == 200) {
      var targetElements = parse(res.body)
          .querySelectorAll('p')
          .where((element) => element.innerHtml.contains('Version '))
          .toList();
      if (targetElements.isEmpty) {
        throw NoVersionError();
      }
      var vLines = targetElements[0]
          .innerHtml
          .split('\n')
          .where((element) => element.contains('Version '))
          .toList();
      if (vLines.isEmpty) {
        throw NoVersionError();
      }
      var versionMatch = RegExp('[0-9]+(\\.[0-9]+)+').firstMatch(vLines[0]);
      if (versionMatch == null) {
        throw NoVersionError();
      }
      String version =
          vLines[0].substring(versionMatch.start, versionMatch.end);
      return APKDetails(
          version,
          getApkUrlsFromUrls([
            'https://www.whatsapp.com/android?v=$version&=thisIsaPlaceholder&a=realURLPrefetchedAtDownloadTime'
          ]),
          AppNames('Meta', 'WhatsApp'));
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
