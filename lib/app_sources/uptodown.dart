import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/app_sources/apkpure.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Uptodown extends AppSource {
  Uptodown() {
    hosts = ['uptodown.com'];
    allowSubDomains = true;
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp(
        '^https?://([^\\.]+\\.){2,}${getSourceRegex(hosts)}',
        caseSensitive: false);
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return '${match.group(0)!}/android/download';
  }

  @override
  Future<String?> tryInferringAppId(String standardUrl,
      {Map<String, dynamic> additionalSettings = const {}}) async {
    return (await getAppDetailsFromPage(
        standardUrl, additionalSettings))['appId'];
  }

  Future<Map<String, String?>> getAppDetailsFromPage(
      String standardUrl, Map<String, dynamic> additionalSettings) async {
    var res = await sourceRequest(standardUrl, additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var html = parse(res.data);
    String? version = html.querySelector('div.version')?.innerHtml;
    String? apkUrl =
        '${standardUrl.split('/').reversed.toList().sublist(1).reversed.join('/')}/post-download';
    String? name = html.querySelector('#detail-app-name')?.innerHtml.trim();
    String? author = html.querySelector('#author-link')?.innerHtml.trim();
    var detailElements = html.querySelectorAll('#technical-information td');
    String? appId = (detailElements.elementAtOrNull(2))?.innerHtml.trim();
    String? dateStr = (detailElements.elementAtOrNull(29))?.innerHtml.trim();
    return Map.fromEntries([
      MapEntry('version', version),
      MapEntry('apkUrl', apkUrl),
      MapEntry('appId', appId),
      MapEntry('name', name),
      MapEntry('author', author),
      MapEntry('dateStr', dateStr)
    ]);
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var appDetails =
        await getAppDetailsFromPage(standardUrl, additionalSettings);
    var version = appDetails['version'];
    var apkUrl = appDetails['apkUrl'];
    var appId = appDetails['appId'];
    if (version == null) {
      throw NoVersionError();
    }
    if (apkUrl == null) {
      throw NoAPKError();
    }
    if (appId == null) {
      throw NoReleasesError();
    }
    String appName = appDetails['name'] ?? tr('app');
    String author = appDetails['author'] ?? name;
    String? dateStr = appDetails['dateStr'];
    DateTime? relDate;
    if (dateStr != null) {
      relDate = parseDateTimeMMMddCommayyyy(dateStr);
    }
    return APKDetails(
        version, getApkUrlsFromUrls([apkUrl]), AppNames(author, appName),
        releaseDate: relDate);
  }

  @override
  Future<String> apkUrlPrefetchModifier(String apkUrl, String standardUrl,
      Map<String, dynamic> additionalSettings) async {
    var res = await sourceRequest(apkUrl, additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var html = parse(res.data);
    var finalUrlKey =
        html.querySelector('.post-download')?.attributes['data-url'];
    if (finalUrlKey == null) {
      throw NoAPKError();
    }
    return 'https://dw.${hosts[0]}/dwn/$finalUrlKey';
  }
}
