import 'dart:async';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:intl/intl.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/utils/min_update_age.dart';

class SourceHut extends AppSource {
  SourceHut() {
    name = 'SourceHut';
    hosts = ['git.sr.ht'];
    changeLogPageIsStandardUrl = true;
    showReleaseDateAsVersionToggle = true;
  }

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
    AppSource.fallbackToOlderReleasesFormItem,
  ];

  @override
  String sourceSpecificStandardizeURL(
    String url, {
    bool forSelection = false,
  }) => standardizeUrlWithRegex(
    url,
    subdomainPrefix: r'(www\.)?',
    pathPattern: r'/[^/]+/[^/]+',
  );

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      if (standardUrl.endsWith('/refs')) {
        standardUrl = standardUrl
            .split('/')
            .reversed
            .toList()
            .sublist(1)
            .reversed
            .join('/');
      }
      final Uri standardUri = Uri.parse(standardUrl);
      final String appName = standardUri.pathSegments.last;
      final bool fallbackToOlderReleases =
          additionalSettings['fallbackToOlderReleases'] == true;
      final Response res = await sourceRequest(
        '$standardUrl/refs/rss.xml',
        additionalSettings,
      );
      if (res.statusCode == 200) {
        final parsedHtml = parse(res.body);
        List<APKDetails> apkDetailsList = [];
        final int minAgeDays = await effectiveMinUpdateAgeDays(
          additionalSettings,
        );
        int ind = 0;
        int releaseSkipped = 0;

        for (var entry in parsedHtml.querySelectorAll('item').take(6)) {
          ind++;
          final String releasePage =
              entry.querySelector('guid')?.innerHtml.trim() ?? '';
          if (!releasePage.startsWith('$standardUrl/refs')) {
            continue;
          }
          if (!fallbackToOlderReleases && ind > releaseSkipped + 1) {
            break;
          }
          final String? version = entry.querySelector('title')?.text.trim();
          if (version == null || version.isEmpty) {
            throw NoVersionError();
          }
          final String? releaseDateString = entry
              .querySelector('pubDate')
              ?.innerHtml;
          DateTime? releaseDate;
          try {
            releaseDate = releaseDateString != null
                ? DateFormat(
                    'EEE, dd MMM yyyy HH:mm:ss Z',
                  ).parse(releaseDateString)
                : null;
          } catch (e) {
            AppLogger.warn(
              'Failed to parse SourceHut release date: ${e.toString()}',
            );
          }
          if (isReleaseTooYoung(releaseDate, minAgeDays)) {
            releaseSkipped++;
          }
          final res2 = await sourceRequest(releasePage, additionalSettings);
          List<MapEntry<String, String>> apkUrls = [];
          if (res2.statusCode == 200) {
            apkUrls = getApkUrlsFromUrls(
              parse(res2.body)
                  .querySelectorAll('a')
                  .map((e) => e.attributes['href'] ?? '')
                  .where((e) => AppSource.isApkOrContainerFile(e))
                  .map((e) => ensureAbsoluteUrl(e, standardUri))
                  .toList(),
            );
          }
          apkDetailsList.add(
            APKDetails(
              version,
              apkUrls,
              AppNames(
                entry.querySelector('author')?.innerHtml.trim() ?? appName,
                appName,
              ),
              releaseDate: releaseDate,
            ),
          );
        }
        if (apkDetailsList.isEmpty) {
          throw NoReleasesError();
        }
        // Prefer the newest release old enough for the minimum update age; if
        // none is, keep the newest so it can be suppressed until it ages.
        if (minAgeDays > 0) {
          final eligible = apkDetailsList
              .where((e) => !isReleaseTooYoung(e.releaseDate, minAgeDays))
              .toList();
          if (eligible.isNotEmpty) {
            apkDetailsList = eligible;
          }
        }
        if (fallbackToOlderReleases) {
          if (additionalSettings['trackOnly'] != true) {
            apkDetailsList = apkDetailsList
                .where((e) => e.apkUrls.isNotEmpty)
                .toList();
          }
          if (apkDetailsList.isEmpty) {
            throw NoReleasesError();
          }
        }
        return apkDetailsList.first;
      } else {
        throw getObtainiumHttpError(res);
      }
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
