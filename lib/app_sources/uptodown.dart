import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/providers/source_provider.dart';

DateTime? _parseUptodownDate(String? dateString) {
  if (dateString == null) return null;
  try {
    return DateFormat('MMM dd, yyyy').parse(dateString);
  } catch (_) {
    AppLogger.error(
      'Failed to parse Uptodown release date (short format): $dateString',
      message:
          'Failed to parse Uptodown release date (short format): $dateString',
    );
  }
  try {
    return DateFormat('MMMM dd, yyyy').parse(dateString);
  } catch (_) {
    AppLogger.error(
      'Failed to parse Uptodown release date: $dateString',
      message: 'Failed to parse Uptodown release date: $dateString',
    );
  }
  return null;
}

class Uptodown extends AppSource {
  Uptodown() {
    name = 'Uptodown';
    hosts = ['uptodown.com'];
    allowSubDomains = true;
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
    urlsAlwaysHaveExtension = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    url = url.replaceFirst(
      RegExp(r'\.([a-z]{2,3})\.uptodown\.', caseSensitive: false),
      '.en.uptodown.',
    );
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
    final res = await sourceRequest(standardUrl, additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    final html = parse(res.body);
    final String? version = html.querySelector('div.version')?.innerHtml;
    final appNameElement = html.querySelector('#detail-app-name');
    final String? name = appNameElement?.innerHtml.trim();
    final String? author = html.querySelector('#author-link')?.innerHtml.trim();
    // Pair each technical-information row's <th> label with its value <td>, so
    // values are found by label instead of by position (which breaks whenever
    // Uptodown inserts or removes a row).
    final Map<String, String> info = {};
    for (final row in html.querySelectorAll('#technical-information tr')) {
      final label = row.querySelector('th')?.text.trim().toLowerCase();
      if (label == null || label.isEmpty) continue;
      final cells = row.querySelectorAll('td');
      final value = cells.isEmpty ? null : cells.last.text.trim();
      if (value != null && value.isNotEmpty) {
        info[label] = value;
      }
    }
    // Fallback for older layouts. Indexing is guarded because the old
    // elementAtOrNull calls threw on negative indices.
    final List<String> detailElements = html
        .querySelectorAll('#technical-information td')
        .map((e) => e.text.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final String? appId =
        info['package name'] ?? detailElements.lastOrNull;
    final String? dateStr =
        info['date'] ??
        (detailElements.length >= 5
            ? detailElements[detailElements.length - 5]
            : null);
    final String? extension = (info['file type'] ??
            (detailElements.length >= 4
                ? detailElements[detailElements.length - 4]
                : null))
        ?.toLowerCase();
    final String? fileId = appNameElement?.attributes['data-file-id'];
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
      final appDetails = await getAppDetailsFromPage(
        standardUrl,
        additionalSettings,
      );
      final version = appDetails['version'];
      final appId = appDetails['appId'];
      final fileId = appDetails['fileId'];
      final extension = appDetails['extension'];
      if (version == null || version.isEmpty) {
        throw NoVersionError();
      }
      if (fileId == null) {
        throw NoAPKError();
      }
      final apkUrl = '$standardUrl/$fileId-x';
      if (appId == null) {
        throw NoReleasesError();
      }
      final String appName = appDetails['name'] ?? tr('app');
      final String author = appDetails['author'] ?? name;
      final String? dateStr = appDetails['dateStr'];
      DateTime? relDate;
      if (dateStr != null) {
        relDate = _parseUptodownDate(dateStr);
      }
      return APKDetails(
        version,
        [
          MapEntry(
            '$appId.${(extension != null && extension.isNotEmpty) ? extension : 'apk'}',
            apkUrl,
          ),
        ],
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
    final res = await sourceRequest(assetUrl, additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    final html = parse(res.body);
    final urlDataKey = html
        .querySelector('#detail-download-button')
        ?.attributes['data-url'];
    if (urlDataKey == null) {
      throw NoAPKError();
    }
    return 'https://dw.${hosts[0]}/dwn/$urlDataKey';
  }
}
