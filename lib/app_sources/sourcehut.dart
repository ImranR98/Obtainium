import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:easy_localization/easy_localization.dart';

class SourceHut extends AppSource {
  SourceHut() {
    host = 'git.sr.ht';
    overrideEligible = true;

    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormSwitch('fallbackToOlderReleases',
            label: tr('fallbackToOlderReleases'), defaultValue: true)
      ]
    ];
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/[^/]+/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) => standardUrl;

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    Uri standardUri = Uri.parse(standardUrl);
    String appName = standardUri.pathSegments.last;
    bool fallbackToOlderReleases =
        additionalSettings['fallbackToOlderReleases'] == true;
    Response res = await sourceRequest('$standardUrl/refs/rss.xml');
    if (res.statusCode == 200) {
      var parsedHtml = parse(res.body);
      List<APKDetails> apkDetailsList = [];
      int ind = 0;

      for (var entry in parsedHtml.querySelectorAll('item').sublist(0, 6)) {
        // Limit 5 for speed
        if (!fallbackToOlderReleases && ind > 0) {
          break;
        }
        String? version = entry.querySelector('title')?.text.trim();
        if (version == null) {
          throw NoVersionError();
        }
        String? releaseDateString = entry.querySelector('pubDate')?.innerHtml;
        var link = entry.querySelector('link');
        String releasePage = '$standardUrl/refs/$version';
        DateTime? releaseDate = releaseDateString != null
            ? DateFormat('EEE, dd MMM yyyy HH:mm:ss Z').parse(releaseDateString)
            : null;
        var res2 = await sourceRequest(releasePage);
        List<MapEntry<String, String>> apkUrls = [];
        if (res2.statusCode == 200) {
          apkUrls = getApkUrlsFromUrls(parse(res2.body)
              .querySelectorAll('a')
              .map((e) => e.attributes['href'] ?? '')
              .where((e) => e.toLowerCase().endsWith('.apk'))
              .map((e) => ensureAbsoluteUrl(e, standardUri))
              .toList());
        }
        apkDetailsList.add(APKDetails(
            version,
            apkUrls,
            AppNames(entry.querySelector('author')?.innerHtml.trim() ?? appName,
                appName),
            releaseDate: releaseDate));
        ind++;
      }
      if (apkDetailsList.isEmpty) {
        throw NoReleasesError();
      }
      if (fallbackToOlderReleases) {
        if (additionalSettings['trackOnly'] != true) {
          apkDetailsList =
              apkDetailsList.where((e) => e.apkUrls.isNotEmpty).toList();
        }
        if (apkDetailsList.isEmpty) {
          throw NoReleasesError();
        }
      }
      return apkDetailsList.first;
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
