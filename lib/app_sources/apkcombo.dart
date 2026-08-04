import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class APKCombo extends AppSource {
  APKCombo() {
    name = 'APKCombo';
    hosts = ['apkcombo.com'];
    showReleaseDateAsVersionToggle = true;
    inferAppIdFromUrlPath = true;
  }

  @override
  String sourceSpecificStandardizeURL(
    String url, {
    bool forSelection = false,
  }) => standardizeUrlWithRegex(
    url,
    subdomainPrefix: '(www\\.)?',
    pathPattern: '/+[^/]+/+[^/]+',
  );

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    // A curl-style User-Agent is needed to get past Cloudflare when scraping
    // apkcombo.com. Do NOT set an explicit Host header: the APK download is
    // served by a Cloudflare R2 presigned URL on a different host, and sending
    // an apkcombo.com Host there makes R2 reject the signed request (403).
    return {
      'User-Agent': 'curl/8.0.1',
      'Accept': '*/*',
      'Connection': 'keep-alive',
    };
  }

  Future<List<MapEntry<String, String>>> getApkUrls(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final res = await sourceRequest(
      '$standardUrl/download/apk',
      additionalSettings,
    );
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    final html = parse(res.body);
    return html
        .querySelectorAll('#variants-tab > div > ul > li')
        .map((li) {
          final String? arch = li
              .querySelector('code')
              ?.text
              .trim()
              .replaceAll(',', '')
              .replaceAll(':', '-')
              .replaceAll(' ', '-');
          // Each variant lists its current build first, then older builds. Take
          // only the first valid (current) download link per variant, otherwise
          // every historical build is returned as a separate "APK" (dozens of
          // near-identical choices, and silent updates get disabled).
          for (final a in li.querySelectorAll('a')) {
            String? url = a.attributes['href'];
            // Current apkcombo download links are "/r2?u=<encoded R2 presigned
            // URL>" redirectors. Unwrap them to the actual (AWS4-signed) .apk
            // URL so the extension check passes and the link can later be
            // matched by its stable R2 object path. See issue #341.
            if (url != null) {
              final parsed = Uri.parse(url);
              if (parsed.path == '/r2' && parsed.queryParameters['u'] != null) {
                url = parsed.queryParameters['u'];
              }
            }
            if (url == null ||
                !AppSource.isApkOrContainerFile(Uri.parse(url).path)) {
              continue;
            }
            final String verCode =
                a.querySelector('.info .header .vercode')?.text.trim() ?? '';
            return MapEntry<String, String>(
              arch != null ? '$arch-$verCode.apk' : '',
              url,
            );
          }
          return null;
        })
        .nonNulls
        .toList();
  }

  @override
  Future<String> assetUrlPrefetchModifier(
    String assetUrl,
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    // The R2 presigned URLs expire (X-Amz-Expires), so re-scrape fresh links at
    // download time and match the stored asset by its (stable) R2 object path.
    final freshURLs = await getApkUrls(standardUrl, additionalSettings);
    final path2Match = Uri.parse(assetUrl).path;
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
    try {
      final String? appId = await tryInferringAppId(standardUrl);
      if (appId == null) {
        throw NoReleasesError();
      }
      final preres = await sourceRequest(standardUrl, additionalSettings);
      if (preres.statusCode != 200) {
        throw getObtainiumHttpError(preres);
      }
      final res = parse(preres.body);
      final String? version = res.querySelector('div.version')?.text.trim();
      if (version == null || version.isEmpty) {
        throw NoVersionError();
      }
      final String appName =
          res.querySelector('div.app_name')?.text.trim() ?? appId;
      final String author =
          res.querySelector('div.author')?.text.trim() ?? appName;
      final List<String> infoArray = res
          .querySelectorAll('div.information-table > .item > div.value')
          .map((e) => e.text.trim())
          .toList();
      DateTime? releaseDate;
      if (infoArray.length >= 2) {
        releaseDate = DateFormat('MMM d, yyyy', 'en_US').tryParse(infoArray[1]);
      }
      return APKDetails(
        version,
        await getApkUrls(standardUrl, additionalSettings),
        AppNames(author, appName),
        releaseDate: releaseDate,
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
