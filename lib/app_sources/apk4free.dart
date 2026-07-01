import 'package:html/parser.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Apk4Free extends AppSource {
  Apk4Free() {
    name = 'Apk4Free';
    hosts = ['apk4free.net'];
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    return standardizeUrlWithRegex(
      url,
      subdomainPrefix: r'(www\.)?',
      pathPattern: r'/[^/]+/?',
    );
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final res = await sourceRequest(standardUrl, additionalSettings);
      if (res.statusCode != 200) {
        throw getObtainiumHttpError(res);
      }
      final html = parse(res.body);

      final titleElement = html.querySelector('h1.main-box-title');
      var fullTitle = titleElement?.text.trim();

      if (fullTitle == null || fullTitle.isEmpty) {
        fullTitle = standardUrl.split('/').last;
      } else {
        fullTitle = fullTitle.replaceAll(RegExp(r'\[.*?\]|\{.*?\}'), '');

        fullTitle = fullTitle.replaceAll(
          RegExp(r'\b(APK|MOD|XAPK|HACK)\b', caseSensitive: false),
          '',
        );

        fullTitle = fullTitle.replaceAll(
          RegExp(
            r'\((?:[^)]*?(?:Unlocked|Mod|Premium|Money|Menu|Full|Patched|Subscribed|AdFree|BG Play|Paid|Unlimited|God Mode)[^)]*?)\)',
            caseSensitive: false,
          ),
          '',
        );

        fullTitle = fullTitle.replaceAll(
          RegExp(r'\s+v?\d+(\.\d+)+.*$', caseSensitive: false),
          '',
        );

        fullTitle = fullTitle
            .replaceAll(RegExp(r'\s+[\+\-]\s+'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }

      var appVersion = html.querySelector('div.version')?.text.trim();
      if (appVersion?.isNotEmpty != true) appVersion = null;

      if (appVersion == null) {
        final rawTitle = titleElement?.text.trim() ?? '';
        final versionRegex = RegExp(r'v?(\d+(\.\d+)+)');
        final match = versionRegex.firstMatch(rawTitle);
        if (match != null) {
          appVersion = match.group(1);
        }
      }

      var downloadPageLink = html
          .querySelectorAll('a.downloadAPK')
          .firstWhere(
            (e) => (e.attributes['href'] ?? '').contains('/download/'),
            orElse: () => html.createElement('a'),
          )
          .attributes['href'];

      if (downloadPageLink == null || downloadPageLink.isEmpty) {
        downloadPageLink = html
            .querySelectorAll('a')
            .firstWhere(
              (e) => (e.attributes['href'] ?? '').contains('/download/'),
              orElse: () => html.createElement('a'),
            )
            .attributes['href'];
      }

      if (downloadPageLink == null || downloadPageLink.isEmpty) {
        throw NoReleasesError();
      }

      final resDlPage = await sourceRequest(
        downloadPageLink,
        additionalSettings,
      );
      if (resDlPage.statusCode != 200) {
        throw getObtainiumHttpError(resDlPage);
      }
      final htmlDlPage = parse(resDlPage.body);

      final List<MapEntry<String, String>> apkUrls = [];

      final verifiedButtons = htmlDlPage.querySelectorAll('a.downloadAPK');
      for (var btn in verifiedButtons) {
        final href = btn.attributes['href'];
        if (href != null) {
          apkUrls.add(MapEntry(btn.text.trim(), href.trim()));
        }
      }

      if (apkUrls.isEmpty) {
        final allLinks = htmlDlPage.querySelectorAll('a');
        for (var link in allLinks) {
          var href = link.attributes['href'];
          if (href == null) continue;
          href = href.trim();
          if (AppSource.isApkOrContainerFile(href)) {
            var linkText = link.text.trim();
            if (linkText.isEmpty) linkText = href.split('/').last;
            apkUrls.add(MapEntry(linkText, href));
          }
        }
      }

      if (apkUrls.isEmpty) {
        throw NoAPKError();
      }

      if (appVersion == null) {
        final versionRegex = RegExp(r'v?(\d+(\.\d+)+)');
        for (var entry in apkUrls) {
          var match = versionRegex.firstMatch(entry.key);
          match ??= versionRegex.firstMatch(entry.value);
          if (match != null) {
            appVersion = match.group(1);
            break;
          }
        }
      }

      if (appVersion == null) {
        throw NoVersionError();
      }

      return APKDetails(appVersion.trim(), apkUrls, AppNames(name, fullTitle));
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
