import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/app_sources/gitlab.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class FDroidPageMetadata {
  final Map<int, List<String>> nativecodes;
  final Map<int, DateTime> addedOn;

  const FDroidPageMetadata({
    this.nativecodes = const {},
    this.addedOn = const {},
  });
}

class FDroid extends AppSource {
  static const _maxChangeLogCodeUnits = 2048;
  static const _pageCacheDuration = Duration(minutes: 10);
  final Map<String, ({FDroidPageMetadata data, DateTime at})> _pageCache = {};
  static const String _fdroidDataBaseUrl =
      'https://gitlab.com/fdroid/fdroiddata/-/raw/master/metadata';
  @override
  String get name => tr('fdroid');

  FDroid() {
    hosts = ['f-droid.org'];
    naiveStandardVersionDetection = true;
    canSearch = true;
    inferAppIdFromUrlPath = true;
  }

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
    [GeneratedFormHeader(label: tr('sectionVersionSelection'))],
    [
      GeneratedFormTextField(
        'filterVersionsByRegEx',
        label: tr('filterVersionsByRegEx'),
        required: false,
        additionalValidators: [
          (value) {
            return regExValidator(value);
          },
        ],
      ),
    ],
    [
      GeneratedFormSwitch(
        'trySelectingSuggestedVersionCode',
        label: tr('trySelectingSuggestedVersionCode'),
        value: true,
      ),
    ],
    [
      GeneratedFormSwitch(
        'autoSelectHighestVersionCode',
        label: tr('autoSelectHighestVersionCode'),
      ),
    ],
  ];

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    final RegExp standardUrlRegExB = RegExp(
      '^https?://(www\\.)?${getSourceRegex(hosts)}/+[^/]+/+packages/+[^/]+',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegExB.firstMatch(url);
    if (match != null) {
      url =
          'https://${Uri.parse(match.group(0)!).host}/packages/${Uri.parse(url).pathSegments.where((s) => s.trim().isNotEmpty).last}';
    }
    final RegExp standardUrlRegExA = RegExp(
      '^https?://(www\\.)?${getSourceRegex(hosts)}/+packages/+[^/]+',
      caseSensitive: false,
    );
    match = standardUrlRegExA.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
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
      final String host = Uri.parse(standardUrl).host;
      final isOfficialHost = !hostChanged || hostIdenticalDespiteAnyChange;
      var details = await getAPKUrlsFromFDroidPackagesAPIResponse(
        await sourceRequest(
          'https://$host/api/v1/packages/$appId',
          additionalSettings,
        ),
        'https://$host/repo/$appId',
        standardUrl,
        name,
        additionalSettings: additionalSettings,
        nativecodePageUrl: isOfficialHost
            ? 'https://$host/en/packages/$appId/'
            : null,
      );
      if (isOfficialHost) {
        try {
          final res = await sourceRequest(
            '$_fdroidDataBaseUrl/$appId.yml',
            additionalSettings,
          );
          final lines = res.body.split('\n');
          final authorLines = lines.where((l) => l.startsWith('AuthorName: '));
          if (authorLines.isNotEmpty) {
            details = details.copyWith(
              names: details.names.copyWith(
                author: authorLines.first.split(': ').sublist(1).join(': '),
              ),
            );
          }
          final changelogUrls = lines
              .where((l) => l.startsWith('Changelog: '))
              .map((e) => e.split(' ').sublist(1).join(' '));
          if (changelogUrls.isNotEmpty) {
            details = details.copyWith(changeLog: changelogUrls.first);
            bool isGitHub = false;
            bool isGitLab = false;
            try {
              GitHub(
                hostChanged: true,
              ).sourceSpecificStandardizeURL(details.changeLog!);
              isGitHub = true;
            } on InvalidURLError {
              // URL does not match GitHub format, silently skipped
            }
            try {
              GitLab(
                hostChanged: true,
              ).sourceSpecificStandardizeURL(details.changeLog!);
              isGitLab = true;
            } on InvalidURLError {
              // URL does not match GitLab format, silently skipped
            }
            if ((isGitHub || isGitLab) &&
                (details.changeLog?.indexOf('/blob/') ?? -1) >= 0) {
              details = details.copyWith(
                changeLog: (await sourceRequest(
                  details.changeLog!.replaceFirst('/blob/', '/raw/'),
                  additionalSettings,
                )).body,
              );
            }
          }
        } catch (e) {
          AppLogger.info(
            'Failed to process changelog for F-Droid app: ${e.toString()}',
          );
        }
        if ((details.changeLog?.length ?? 0) > _maxChangeLogCodeUnits) {
          final cl = details.changeLog!;
          var end = _maxChangeLogCodeUnits;
          if (end > 0 &&
              cl.codeUnitAt(end - 1) >= 0xD800 &&
              cl.codeUnitAt(end - 1) <= 0xDBFF) {
            end--;
          }
          details = details.copyWith(changeLog: '${cl.substring(0, end)}...');
        }
      }
      return details;
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    final Response res = await sourceRequest(
      'https://search.${hosts[0]}/?q=${Uri.encodeQueryComponent(query)}',
      {},
    );
    if (res.statusCode == 200) {
      final Map<String, List<String>> urlsWithDescriptions = {};
      parse(res.body).querySelectorAll('.package-header').forEach((e) {
        String? url = e.attributes['href'];
        if (url != null) {
          try {
            // Keep the canonical form so search results match stored app URLs
            // and duplicate detection works.
            url = standardizeUrl(url);
          } catch (e) {
            url = null;
          }
        }
        if (url != null) {
          urlsWithDescriptions[url] = [
            e.querySelector('.package-name')?.text.trim() ?? '',
            e.querySelector('.package-summary')?.text.trim() ??
                tr('noDescription'),
          ];
        }
      });
      return urlsWithDescriptions;
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  Future<APKDetails> getAPKUrlsFromFDroidPackagesAPIResponse(
    Response res,
    String apkUrlPrefix,
    String standardUrl,
    String sourceName, {
    Map<String, dynamic> additionalSettings = const {},
    String? nativecodePageUrl,
  }) async {
    final autoSelectHighestVersionCode =
        additionalSettings['autoSelectHighestVersionCode'] == true;
    final trySelectingSuggestedVersionCode =
        additionalSettings['trySelectingSuggestedVersionCode'] == true;
    final filterVersionsByRegEx =
        (additionalSettings['filterVersionsByRegEx'] as String?)?.isNotEmpty ==
            true
        ? additionalSettings['filterVersionsByRegEx']
        : null;
    final apkFilterRegEx =
        (additionalSettings['apkFilterRegEx'] as String?)?.isNotEmpty == true
        ? additionalSettings['apkFilterRegEx']
        : null;
    if (res.statusCode == 200) {
      final response = jsonDecode(res.body);
      List<dynamic> releases = response is Map
          ? (response['packages'] ?? [])
          : [];
      if (apkFilterRegEx != null) {
        releases = releases.where((rel) {
          final String apk = '${apkUrlPrefix}_${rel['versionCode']}.apk';
          return filterApks(
            [MapEntry(apk, apk)],
            apkFilterRegEx,
            false,
          ).isNotEmpty;
        }).toList();
      }
      if (releases.isEmpty) {
        throw NoReleasesError();
      }
      String? version;
      Iterable<dynamic> releaseChoices = [];
      // Grab the versionCode suggested if the user chose to do that
      // Only do so at this stage if the user has no release filter
      if (trySelectingSuggestedVersionCode &&
          response['suggestedVersionCode'] != null &&
          filterVersionsByRegEx == null) {
        final suggestedReleases = releases.where(
          (element) =>
              element['versionCode'] == response['suggestedVersionCode'],
        );
        if (suggestedReleases.isNotEmpty) {
          releaseChoices = suggestedReleases;
          version = suggestedReleases.first['versionName'];
        }
      }
      // Apply the release filter if any
      if (filterVersionsByRegEx?.isNotEmpty == true) {
        version = null;
        releaseChoices = [];
        final versionFilter = RegExp(filterVersionsByRegEx!);
        for (var i = 0; i < releases.length; i++) {
          if (versionFilter.hasMatch(releases[i]['versionName'])) {
            version = releases[i]['versionName'];
            break;
          }
        }
        if (version == null || version.isEmpty) {
          throw NoVersionError();
        }
      }
      // Default to the highest version
      version ??= releases[0]['versionName'];
      if (version == null || version.isEmpty) {
        throw NoVersionError();
      }
      // If a suggested release was not already picked, pick all those with the selected version
      if (releaseChoices.isEmpty) {
        releaseChoices = releases.where(
          (element) => element['versionName'] == version,
        );
      }
      // The F-Droid API exposes neither per-APK architectures nor release
      // dates. Read them from the package page. Any failure leaves the
      // unfiltered selection and undated result in place (#2529, #779).
      final List<dynamic> sameVersionReleases = releases
          .where((element) => element['versionName'] == version)
          .toList();
      FDroidPageMetadata? pageMetadata;
      if (nativecodePageUrl != null) {
        pageMetadata = await _getPageMetadata(
          nativecodePageUrl,
          additionalSettings,
        );
      }
      if (pageMetadata != null &&
          additionalSettings['autoApkFilterByArch'] == true &&
          sameVersionReleases.length > 1 &&
          pageMetadata.nativecodes.isNotEmpty) {
        try {
          final filtered = filterReleasesByNativecode(
            sameVersionReleases,
            pageMetadata.nativecodes,
            await getSupportedAbis(),
          );
          if (filtered != null && filtered.isNotEmpty) {
            releaseChoices = filtered;
          }
        } catch (e) {
          AppLogger.info(
            'Failed to filter F-Droid APKs by architecture: ${e.toString()}',
          );
        }
      }
      // For the remaining releases, use the toggles to auto-select one if possible
      if (releaseChoices.length > 1) {
        if (autoSelectHighestVersionCode) {
          releaseChoices = [releaseChoices.first];
        } else if (trySelectingSuggestedVersionCode &&
            response['suggestedVersionCode'] != null) {
          final suggestedReleases = releaseChoices.where(
            (element) =>
                element['versionCode'] == response['suggestedVersionCode'],
          );
          if (suggestedReleases.isNotEmpty) {
            releaseChoices = suggestedReleases;
          }
        }
      }
      if (releaseChoices.isEmpty) {
        throw NoReleasesError();
      }
      if (additionalSettings['useVersionCodeAsOSVersion'] == true) {
        version = releaseChoices.first['versionCode']?.toString() ?? version;
      }
      final List<String> apkUrls = releaseChoices
          .map((e) => '${apkUrlPrefix}_${e['versionCode']}.apk')
          .toList();
      DateTime? releaseDate;
      if (pageMetadata != null) {
        final selectedCode = releaseChoices.first['versionCode'];
        if (selectedCode is int) {
          releaseDate = pageMetadata.addedOn[selectedCode];
        }
        if (releaseDate == null) {
          final versionCode = sameVersionReleases.first['versionCode'];
          if (versionCode is int) {
            releaseDate = pageMetadata.addedOn[versionCode];
          }
        }
      }
      return APKDetails(
        version,
        getApkUrlsFromUrls(apkUrls.toSet().toList()),
        AppNames(sourceName, Uri.parse(standardUrl).pathSegments.last),
        releaseDate: releaseDate,
      );
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  /// This device's supported ABIs, in preference order.
  Future<List<String>> getSupportedAbis() async =>
      (await DeviceInfoPlugin().androidInfo).supportedAbis;

  Future<FDroidPageMetadata?> _getPageMetadata(
    String url,
    Map<String, dynamic> additionalSettings,
  ) async {
    final cached = _pageCache[url];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _pageCacheDuration) {
      return cached.data;
    }
    try {
      final res = await sourceRequest(url, additionalSettings);
      if (res.statusCode == 200) {
        final metadata = parsePackagePageMetadata(res.body);
        _pageCache[url] = (data: metadata, at: DateTime.now());
        return metadata;
      }
      AppLogger.info(
        'F-Droid package page request failed with HTTP ${res.statusCode}: $url',
      );
    } catch (e) {
      AppLogger.info(
        'Failed to fetch F-Droid package page ($url): ${e.toString()}',
      );
    }
    return null;
  }

  static int? _versionCodeFromApkUrl(String url) =>
      int.tryParse(RegExp(r'_(\d+)\.apk$').firstMatch(url)?.group(1) ?? '');

  @override
  Future<Map<String, List<String>>> getApkAbisByUrl(App app) async {
    if (hostChanged && !hostIdenticalDespiteAnyChange) return const {};
    final appId = await tryInferringAppId(app.url);
    if (appId == null) return const {};
    final host = Uri.parse(app.url).host;
    final metadata = await _getPageMetadata(
      'https://$host/en/packages/$appId/',
      app.additionalSettings,
    );
    if (metadata == null) return const {};
    final abis = <String, List<String>>{};
    for (final apk in app.apkUrls) {
      final versionCode = _versionCodeFromApkUrl(apk.value);
      if (versionCode != null &&
          metadata.nativecodes.containsKey(versionCode)) {
        abis[apk.value] = metadata.nativecodes[versionCode]!;
      }
    }
    return abis;
  }

  /// Parses the nativecode and "Added on" metadata from an F-Droid package
  /// page. Each version block lists the native architectures of its APK;
  /// builds without a nativecode note are universal.
  static FDroidPageMetadata parsePackagePageMetadata(String html) {
    final nativecodes = <int, List<String>>{};
    final addedOn = <int, DateTime>{};
    final versionCodeRegEx = RegExp(r'_(\d+)\.apk$');
    final addedOnRegEx = RegExp(r'Added on\s+(.+)');
    for (final element in parse(html).querySelectorAll('li.package-version')) {
      int? versionCode;
      for (final anchor in element.querySelectorAll(
        '.package-version-download a',
      )) {
        final match = versionCodeRegEx.firstMatch(
          anchor.attributes['href'] ?? '',
        );
        if (match != null) {
          versionCode = int.tryParse(match.group(1)!);
          break;
        }
      }
      if (versionCode == null) {
        continue;
      }
      final code = element.querySelector('.package-nativecode')?.text.trim();
      nativecodes[versionCode] = code == null || code.isEmpty
          ? const []
          : code
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
      final header = element.querySelector('.package-version-header')?.text;
      final rawDate = addedOnRegEx.firstMatch(header ?? '')?.group(1);
      final date = parseAddedOnDate(rawDate);
      if (date != null) {
        addedOn[versionCode] = date;
      }
    }
    return FDroidPageMetadata(nativecodes: nativecodes, addedOn: addedOn);
  }

  static DateTime? parseAddedOnDate(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return null;
    for (final pattern in [
      'MMM d, yyyy',
      'MMM dd, yyyy',
      'd MMM yyyy',
      'yyyy-MM-dd',
    ]) {
      final parsed = DateFormat(pattern, 'en_US').tryParse(cleaned);
      if (parsed != null) return parsed;
    }
    return DateTime.tryParse(cleaned);
  }

  static Map<int, List<String>> parseNativecodesFromPackagePage(String html) =>
      parsePackagePageMetadata(html).nativecodes;

  static Map<int, DateTime> parseAddedOnDatesFromPackagePage(String html) =>
      parsePackagePageMetadata(html).addedOn;

  /// Narrows [releases] to the build that fits this device's [abis], using the
  /// given versionCode -> nativecode map. The device ABI order is used as the
  /// preference order, and builds without nativecode are treated as universal.
  /// Returns null when no nativecode information applies, so the caller can
  /// keep its unfiltered selection.
  static List<dynamic>? filterReleasesByNativecode(
    List<dynamic> releases,
    Map<int, List<String>> nativecodes,
    List<String> abis,
  ) {
    if (releases.length <= 1 || abis.isEmpty) {
      return null;
    }
    List<String> nativecodeOf(dynamic release) =>
        nativecodes[release['versionCode']] ?? const [];
    if (!releases.any((element) => nativecodeOf(element).isNotEmpty)) {
      return null;
    }
    final compatible = releases
        .where(
          (element) =>
              nativecodeOf(element).isEmpty ||
              nativecodeOf(element).any(abis.contains),
        )
        .toList();
    if (compatible.isEmpty) {
      return null;
    }
    for (final abi in abis) {
      final abiReleases = compatible
          .where((element) => nativecodeOf(element).contains(abi))
          .toList();
      if (abiReleases.isNotEmpty) {
        return abiReleases;
      }
    }
    return compatible;
  }
}
