import 'package:dio/dio.dart';
import 'package:html/parser.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:easy_localization/easy_localization.dart';

class SourceHut extends AppSource {
  SourceHut() {
    hosts = ['git.sr.ht'];
    showReleaseDateAsVersionToggle = true;

    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormSwitch('fallbackToOlderReleases',
            label: tr('fallbackToOlderReleases'), defaultValue: true)
      ]
    ];
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp(
        '^https?://(www\\.)?${getSourceRegex(hosts)}/[^/]+/[^/]+',
        caseSensitive: false);
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) => standardUrl;

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    if (standardUrl.endsWith('/refs')) {
      standardUrl = standardUrl
          .split('/')
          .reversed
          .toList()
          .sublist(1)
          .reversed
          .join('/');
    }
    Uri standardUri = Uri.parse(standardUrl);
    String appName = standardUri.pathSegments.last;
    bool fallbackToOlderReleases =
        additionalSettings['fallbackToOlderReleases'] == true;
    Response res =
        await sourceRequest('$standardUrl/refs/rss.xml', additionalSettings);
    if (res.statusCode == 200) {
      var parsedHtml = parse(res.data);
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
        String releasePage = '$standardUrl/refs/$version';
        DateTime? releaseDate;
        try {
          releaseDate = releaseDateString != null
              ? DateFormat('E, dd MMM yyyy HH:mm:ss Z').parse(releaseDateString)
              : null;
          releaseDate = releaseDateString != null
              ? DateFormat('EEE, dd MMM yyyy HH:mm:ss Z')
                  .parse(releaseDateString)
              : null;
        } catch (e) {
          // ignore
        }
        var res2 = await sourceRequest(releasePage, additionalSettings);
        List<MapEntry<String, String>> apkUrls = [];
        if (res2.statusCode == 200) {
          apkUrls = getApkUrlsFromUrls(parse(res2.data)
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
