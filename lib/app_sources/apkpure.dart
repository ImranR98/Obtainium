import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

parseDateTimeMMMddCommayyyy(String? dateString) {
  DateTime? releaseDate;
  try {
    releaseDate = dateString != null
        ? DateFormat('MMM dd, yyyy').parse(dateString)
        : null;
    releaseDate = dateString != null && releaseDate == null
        ? DateFormat('MMMM dd, yyyy').parse(dateString)
        : releaseDate;
  } catch (err) {
    // ignore
  }
  return releaseDate;
}

class APKPure extends AppSource {
  APKPure() {
    host = 'apkpure.com';
    allowSubDomains = true;
    naiveStandardVersionDetection = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    RegExp standardUrlRegExB =
        RegExp('^https?://m.$host/+[^/]+/+[^/]+(/+[^/]+)?');
    RegExpMatch? match = standardUrlRegExB.firstMatch(url.toLowerCase());
    if (match != null) {
      url = 'https://$host${Uri.parse(url).path}';
    }
    RegExp standardUrlRegExA =
        RegExp('^https?://$host/+[^/]+/+[^/]+(/+[^/]+)?');
    match = standardUrlRegExA.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
  }

  @override
  Future<String?> tryInferringAppId(String standardUrl,
      {Map<String, dynamic> additionalSettings = const {}}) async {
    return Uri.parse(standardUrl).pathSegments.last;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    String appId = (await tryInferringAppId(standardUrl))!;
    String host = Uri.parse(standardUrl).host;
    var res = await sourceRequest('$standardUrl/download');
    var resChangelog = await sourceRequest(standardUrl);
    if (res.statusCode == 200 && resChangelog.statusCode == 200) {
      var html = parse(res.body);
      var htmlChangelog = parse(resChangelog.body);
      String? version = html.querySelector('span.info-sdk span')?.text.trim();
      if (version == null) {
        throw NoVersionError();
      }
      String? dateString =
          html.querySelector('span.info-other span.date')?.text.trim();
      DateTime? releaseDate = parseDateTimeMMMddCommayyyy(dateString);
      String type = html.querySelector('a.info-tag')?.text.trim() ?? 'APK';
      List<MapEntry<String, String>> apkUrls = [
        MapEntry('$appId.apk', 'https://d.$host/b/$type/$appId?version=latest')
      ];
      String author = html
              .querySelector('span.info-sdk')
              ?.text
              .trim()
              .substring(version.length + 4) ??
          Uri.parse(standardUrl).pathSegments.reversed.last;
      String appName =
          html.querySelector('h1.info-title')?.text.trim() ?? appId;
      String? changeLog = htmlChangelog
          .querySelector("div.whats-new-info p:not(.date)")
          ?.innerHtml
          .trim()
          .replaceAll("<br>", "  \n");
      return APKDetails(version, apkUrls, AppNames(author, appName),
          releaseDate: releaseDate, changeLog: changeLog);
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
