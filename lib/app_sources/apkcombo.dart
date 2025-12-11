import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class APKCombo extends AppSource {
  APKCombo() {
    hosts = ['apkcombo.com'];
    showReleaseDateAsVersionToggle = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegEx = RegExp(
      '^https?://(www\\.)?${getSourceRegex(hosts)}/+[^/]+/+[^/]+',
      caseSensitive: false,
    );
    var match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    return Uri.parse(standardUrl).pathSegments.last;
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    return {
      "User-Agent": "curl/8.0.1",
      "Accept": "*/*",
      "Connection": "keep-alive",
      "Host": hosts[0],
    };
  }

  Future<List<MapEntry<String, String>>> getApkUrls(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var res = await sourceRequest('$standardUrl/download/apk', {});
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var html = parse(res.body);
    return html
        .querySelectorAll('#variants-tab > div > ul > li')
        .map((e) {
          String? arch = e
              .querySelector('code')
              ?.text
              .trim()
              .replaceAll(',', '')
              .replaceAll(':', '-')
              .replaceAll(' ', '-');
          return e.querySelectorAll('a').map((e) {
            String? url = e.attributes['href'];
            if (url != null &&
                !Uri.parse(url).path.toLowerCase().endsWith('.apk')) {
              url = null;
            }
            String verCode =
                e.querySelector('.info .header .vercode')?.text.trim() ?? '';
            return MapEntry<String, String>(
              arch != null ? '$arch-$verCode.apk' : '',
              url ?? '',
            );
          }).toList();
        })
        .reduce((value, element) => [...value, ...element])
        .where((element) => element.value.isNotEmpty)
        .toList();
  }

  @override
  Future<String> assetUrlPrefetchModifier(
    String assetUrl,
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var freshURLs = await getApkUrls(standardUrl, additionalSettings);
    var path2Match = Uri.parse(assetUrl).path;
    for (var url in freshURLs) {
      if (Uri.parse(url.value).path == path2Match) {
        return url.value;
      }
    }
    throw NoAPKError();
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    String appId = (await tryInferringAppId(standardUrl))!;
    var preres = await sourceRequest(standardUrl, additionalSettings);
    if (preres.statusCode != 200) {
      throw getObtainiumHttpError(preres);
    }
    var res = parse(preres.body);
    String? version = res.querySelector('div.version')?.text.trim();
    if (version == null) {
      throw NoVersionError();
    }
    String appName = res.querySelector('div.app_name')?.text.trim() ?? appId;
    String author = res.querySelector('div.author')?.text.trim() ?? appName;
    List<String> infoArray = res
        .querySelectorAll('div.information-table > .item > div.value')
        .map((e) => e.text.trim())
        .toList();
    DateTime? releaseDate;
    if (infoArray.length >= 2) {
      try {
        releaseDate = DateFormat('MMMM d, yyyy').parse(infoArray[1]);
      } catch (e) {
        // ignore
      }
    }
    return APKDetails(
      version,
      await getApkUrls(standardUrl, additionalSettings),
      AppNames(author, appName),
      releaseDate: releaseDate,
    );
  }
}
