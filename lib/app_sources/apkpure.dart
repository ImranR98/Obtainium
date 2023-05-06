import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class APKPure extends AppSource {
  APKPure() {
    host = 'apkpure.com';
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    RegExp standardUrlRegExB = RegExp('^https?://m.$host/+[^/]+/+[^/]+');
    RegExpMatch? match = standardUrlRegExB.firstMatch(url.toLowerCase());
    if (match != null) {
      url = 'https://$host/${Uri.parse(url).path}';
    }
    RegExp standardUrlRegExA = RegExp('^https?://$host/+[^/]+/+[^/]+');
    match = standardUrlRegExA.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
  }

  @override
  String? tryInferringAppId(String standardUrl,
      {Map<String, dynamic> additionalSettings = const {}}) {
    return Uri.parse(standardUrl).pathSegments.last;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    String appId = tryInferringAppId(standardUrl)!;
    String host = Uri.parse(standardUrl).host;
    var res = await sourceRequest('$standardUrl/download');
    if (res.statusCode == 200) {
      var html = parse(res.body);
      String? version = html.querySelector('span.info-sdk span')?.text.trim();
      if (version == null) {
        throw NoVersionError();
      }
      String? dateString =
          html.querySelector('span.info-other span.date')?.text.trim();
      DateTime? releaseDate = dateString != null
          ? DateFormat('MMMM d, yyyy').parse(dateString)
          : null;
      List<MapEntry<String, String>> apkUrls = [
        MapEntry('$appId.apk', 'https://d.$host/b/APK/$appId?version=latest')
      ];
      String author = html
              .querySelector('span.info-sdk')
              ?.text
              .trim()
              .substring(version.length + 4) ??
          Uri.parse(standardUrl).pathSegments.reversed.last;
      String appName =
          html.querySelector('h1.info-title')?.text.trim() ?? appId;
      return APKDetails(version, apkUrls, AppNames(author, appName),
          releaseDate: releaseDate);
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
