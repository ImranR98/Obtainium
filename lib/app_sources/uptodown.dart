import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

DateTime? parseUptodownDate(String? dateString) {
  if (dateString == null) return null;
  try {
    return DateFormat('MMM dd, yyyy').parse(dateString);
  } catch (_) {
    LogsProvider().add('Failed to parse Uptodown release date (short format): $dateString', level: LogLevel.error);
  }
  try {
    return DateFormat('MMMM dd, yyyy').parse(dateString);
  } catch (_) {
    LogsProvider().add('Failed to parse Uptodown release date: $dateString', level: LogLevel.error);
  }
  return null;
}

class Uptodown extends AppSource {
  Uptodown() {
    hosts = ['uptodown.com'];
    allowSubDomains = true;
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
    urlsAlwaysHaveExtension = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    return '${standardizeUrlWithRegex(url, subdomainPrefix: r'([^\\.]+\.)+', pathPattern: '')}/android/download';
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    return (await getAppDetailsFromPage(
      standardUrl,
      additionalSettings,
    ))['appId'];
  }

  Future<Map<String, String?>> getAppDetailsFromPage(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var res = await sourceRequest(standardUrl, additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var html = parse(res.body);
    String? version = html.querySelector('div.version')?.innerHtml;
    String? name = html.querySelector('#detail-app-name')?.innerHtml.trim();
    String? author = html.querySelector('#author-link')?.innerHtml.trim();
    var detailElements = html
        .querySelectorAll('#technical-information td')
        .map((e) => e.text.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    String? appId = detailElements.lastOrNull;
    String? dateStr = detailElements.elementAtOrNull(detailElements.length - 5);
    String? fileId = html
        .querySelector('#detail-app-name')
        ?.attributes['data-file-id'];
    String? extension = detailElements
        .elementAtOrNull(detailElements.length - 4)
        ?.toLowerCase();
    return Map.fromEntries([
      MapEntry('version', version),
      MapEntry('appId', appId),
      MapEntry('name', name),
      MapEntry('author', author),
      MapEntry('dateStr', dateStr),
      MapEntry('fileId', fileId),
      MapEntry('extension', extension),
    ]);
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      var appDetails = await getAppDetailsFromPage(
      standardUrl,
      additionalSettings,
    );
    var version = appDetails['version'];
    var appId = appDetails['appId'];
    var fileId = appDetails['fileId'];
    var extension = appDetails['extension'];
    if (version == null || version.isEmpty) {
      throw NoVersionError();
    }
    if (fileId == null) {
      throw NoAPKError();
    }
    var apkUrl = '$standardUrl/$fileId-x';
    if (appId == null) {
      throw NoReleasesError();
    }
    String appName = appDetails['name'] ?? tr('app');
    String author = appDetails['author'] ?? name;
    String? dateStr = appDetails['dateStr'];
    DateTime? relDate;
    if (dateStr != null) {
      relDate = parseUptodownDate(dateStr);
    }
    return APKDetails(
      version,
      [MapEntry('$appId.${extension ?? 'apk'}', apkUrl)],
      AppNames(author, appName),
      releaseDate: relDate,
    );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }

  @override
  Future<String> assetUrlPrefetchModifier(
    String assetUrl,
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var res = await sourceRequest(assetUrl, additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var html = parse(res.body);
    var finalUrlKey = html
        .querySelector('#detail-download-button')
        ?.attributes['data-url'];
    if (finalUrlKey == null) {
      throw NoAPKError();
    }
    return 'https://dw.${hosts[0]}/dwn/$finalUrlKey';
  }
}
