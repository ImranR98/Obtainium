import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

/// The APKMirror maintainers do not allow for directly downloading APKs (PR #44)
class APKMirror extends AppSource {
  APKMirror() {
    name = 'APKMirror';
    hosts = ['apkmirror.com'];
    enforceTrackOnly = true;
    showReleaseDateAsVersionToggle = true;
  }

  static const String _fallbackVersion = '1.0.0';

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
    AppSource.fallbackToOlderReleasesFormItem,
    [
      GeneratedFormTextField(
        'filterReleaseTitlesByRegEx',
        label: tr('filterReleaseTitlesByRegEx'),
        required: false,
        additionalValidators: [
          (value) {
            return regExValidator(value);
          },
        ],
      ),
    ],
  ];

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    return {
      'User-Agent':
          'Obtainium/${(await getInstalledInfo(obtainiumId))?.versionName ?? _fallbackVersion}',
    };
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    return standardizeUrlWithRegex(
      url,
      subdomainPrefix: r'(www\.)?',
      pathPattern: r'/apk/[^/]+/[^/]+',
    );
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/#whatsnew';

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final bool fallbackToOlderReleases =
          additionalSettings['fallbackToOlderReleases'] == true;
      final String? regexFilter =
          (additionalSettings['filterReleaseTitlesByRegEx'] as String?)
                  ?.isNotEmpty ==
              true
          ? additionalSettings['filterReleaseTitlesByRegEx']
          : null;
      final Response res = await sourceRequest(
        '$standardUrl/feed/',
        additionalSettings,
      );
      if (res.statusCode == 200) {
        final items = parse(res.body).querySelectorAll('item');
        dynamic targetRelease;
        for (int i = 0; i < items.length; i++) {
          if (!fallbackToOlderReleases && i > 0) break;
          final String? nameToFilter = items[i]
              .querySelector('title')
              ?.innerHtml;
          if (regexFilter != null &&
              nameToFilter != null &&
              !RegExp(regexFilter).hasMatch(nameToFilter.trim())) {
            continue;
          }
          targetRelease = items[i];
          break;
        }
        final String? titleString = targetRelease
            ?.querySelector('title')
            ?.innerHtml;
        if (targetRelease == null) {
          throw NoReleasesError(
            note: regexFilter != null ? tr('noMatchingReleaseFound') : null,
          );
        }
        final pubDateRaw = targetRelease?.querySelector('pubDate')?.innerHtml;
        final String? dateString = pubDateRaw?.split(' ').take(5).join(' ');
        DateTime? releaseDate;
        if (dateString != null) {
          try {
            releaseDate = HttpDate.parse('$dateString GMT');
          } catch (e) {
            AppLogger.warn(
              'Failed to parse APKMirror release date: ${e.toString()}',
            );
          }
        }
        String? version;
        if (titleString != null) {
          final match = RegExp(
            r'\b(\d[\d.]*(?:[- ]?\d[\d.]*)*)\b',
          ).firstMatch(titleString);
          version = match?.group(1);
        }
        if (version == null || version.isEmpty) {
          version = titleString;
        }
        if (version == null || version.isEmpty) {
          throw NoVersionError();
        }
        return APKDetails(
          version,
          [],
          getAppNames(standardUrl),
          releaseDate: releaseDate,
        );
      } else {
        throw getObtainiumHttpError(res);
      }
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }

  AppNames getAppNames(String standardUrl) {
    final String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    final pathStart = temp.indexOf('/');
    if (pathStart < 0 || pathStart + 1 >= temp.length) {
      throw InvalidURLError(name);
    }
    final List<String> names = temp.substring(pathStart + 1).split('/');
    if (names.length < 3) throw InvalidURLError(name);
    return AppNames(names[1], names[2]);
  }
}
