// ========================================================================
// App source definitions, models, services, and JSON migration logic.
//
// AppSource is an abstract class with a concrete implementation for each source.
// ========================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:obtainium/app_sources/apkcombo.dart';
import 'package:obtainium/app_sources/apkmirror.dart';
import 'package:obtainium/app_sources/apkpure.dart';
import 'package:obtainium/app_sources/aptoide.dart';
import 'package:obtainium/app_sources/apk4free.dart';
import 'package:obtainium/app_sources/codeberg.dart';
import 'package:obtainium/app_sources/coolapk.dart';
import 'package:obtainium/app_sources/direct_apk_link.dart';
import 'package:obtainium/app_sources/farsroid.dart';
import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/app_sources/fdroidrepo.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/app_sources/gitlab.dart';
import 'package:obtainium/app_sources/huaweiappgallery.dart';
import 'package:obtainium/app_sources/samsunggalaxystore.dart';
import 'package:obtainium/app_sources/itchio.dart';
import 'package:obtainium/app_sources/izzyondroid.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/app_sources/jenkins.dart';
import 'package:obtainium/app_sources/liteapks.dart';
import 'package:obtainium/app_sources/neutroncode.dart';
import 'package:obtainium/app_sources/rockmods.dart';
import 'package:obtainium/app_sources/rustore.dart';
import 'package:obtainium/app_sources/sourceforge.dart';
import 'package:obtainium/app_sources/sourcehut.dart';
import 'package:obtainium/app_sources/telegramapp.dart';
import 'package:obtainium/app_sources/tencent.dart';
import 'package:obtainium/app_sources/uptodown.dart';
import 'package:obtainium/app_sources/vivoappstore.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/app_sources/githubstars.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/providers/settings_provider.dart';

part 'app_json_migration.dart';

const int kDefaultFetchConcurrency = 4;

// ------------------------------------------------------------------------
// AppNames
// ------------------------------------------------------------------------

class AppNames {
  final String author;
  final String name;

  const AppNames(this.author, this.name);

  AppNames copyWith({String? author, String? name}) {
    return AppNames(author ?? this.author, name ?? this.name);
  }
}

// ------------------------------------------------------------------------
// APKDetails
// ------------------------------------------------------------------------

class APKDetails {
  final String version;
  final List<MapEntry<String, String>> apkUrls;
  final AppNames names;
  final DateTime? releaseDate;
  final String? changeLog;
  final List<MapEntry<String, String>> allAssetUrls;

  const APKDetails(
    this.version,
    this.apkUrls,
    this.names, {
    this.releaseDate,
    this.changeLog,
    this.allAssetUrls = const [],
  });

  APKDetails copyWith({
    String? version,
    List<MapEntry<String, String>>? apkUrls,
    AppNames? names,
    Object? releaseDate = _sentinel,
    Object? changeLog = _sentinel,
    List<MapEntry<String, String>>? allAssetUrls,
  }) {
    return APKDetails(
      version ?? this.version,
      apkUrls ?? this.apkUrls,
      names ?? this.names,
      releaseDate: releaseDate == _sentinel
          ? this.releaseDate
          : releaseDate as DateTime?,
      changeLog: changeLog == _sentinel ? this.changeLog : changeLog as String?,
      allAssetUrls: allAssetUrls ?? this.allAssetUrls,
    );
  }
}

/// Converts a list of [MapEntry] pairs into a 2D list of strings for JSON encoding.
List<List<String>> stringMapListTo2DList(
  List<MapEntry<String, String>> mapList,
) => mapList.map((e) => [e.key, e.value]).toList();

/// Converts a 2D list (decoded from JSON) back into a list of [MapEntry] pairs.
List<MapEntry<String, String>> assumed2DlistToStringMapList(
  List<dynamic> arr,
) => arr.map((e) => MapEntry(e[0] as String, e[1] as String)).toList();

// ------------------------------------------------------------------------
// Top-level delegation helpers — convenience wrappers that forward to the
// corresponding service classes. New code should use the services directly.
// ------------------------------------------------------------------------

/// Delegates to [HttpService.ensureAbsoluteUrl].
String ensureAbsoluteUrl(String ambiguousUrl, Uri referenceAbsoluteUrl) =>
    HttpService().ensureAbsoluteUrl(ambiguousUrl, referenceAbsoluteUrl);

// ------------------------------------------------------------------------
// App
// ------------------------------------------------------------------------

class App {
  final String id;
  final String url;
  final String author;
  final String name;
  final String? installedVersion;
  final String latestVersion;
  final List<MapEntry<String, String>> apkUrls;
  final List<MapEntry<String, String>> otherAssetUrls;
  final int preferredApkIndex;
  final Map<String, dynamic> additionalSettings;
  final DateTime? lastUpdateCheck;
  final bool pinned;
  final List<String> categories;
  final DateTime? releaseDate;
  final String? changeLog;
  final String? overrideSource;
  final bool allowIdChange;
  final String? pendingRepoRenameUrl;

  const App({
    required this.id,
    required this.url,
    required this.author,
    required this.name,
    this.installedVersion,
    required this.latestVersion,
    this.apkUrls = const [],
    this.otherAssetUrls = const [],
    required this.preferredApkIndex,
    required this.additionalSettings,
    this.lastUpdateCheck,
    this.pinned = false,
    this.categories = const [],
    this.releaseDate,
    this.changeLog,
    this.overrideSource,
    this.allowIdChange = false,
    this.pendingRepoRenameUrl,
  });

  @override
  String toString() {
    return 'ID: $id URL: $url INSTALLED: $installedVersion LATEST: $latestVersion APK: $apkUrls PREFERREDAPK: $preferredApkIndex ADDITIONALSETTINGS: ${additionalSettings.toString()} LASTCHECK: ${lastUpdateCheck.toString()} PINNED $pinned';
  }

  bool get hasPendingRepoRename =>
      pendingRepoRenameUrl != null && pendingRepoRenameUrl!.isNotEmpty;

  String? get overrideName {
    final n = settings.getStringOrNull('appName');
    return n != null && n.trim().isNotEmpty ? n : null;
  }

  String get finalName {
    return overrideName ?? name;
  }

  String? get overrideAuthor {
    final a = settings.getStringOrNull('appAuthor');
    return a != null && a.trim().isNotEmpty ? a : null;
  }

  String get finalAuthor {
    return overrideAuthor ?? author;
  }

  /// Type-safe accessor for [additionalSettings].
  TypedSettings get settings => TypedSettings(additionalSettings);

  App copyWith({
    String? id,
    String? url,
    String? author,
    String? name,
    Object? installedVersion = _sentinel,
    String? latestVersion,
    List<MapEntry<String, String>>? apkUrls,
    List<MapEntry<String, String>>? otherAssetUrls,
    int? preferredApkIndex,
    Map<String, dynamic>? additionalSettings,
    Object? lastUpdateCheck = _sentinel,
    bool? pinned,
    List<String>? categories,
    Object? releaseDate = _sentinel,
    Object? changeLog = _sentinel,
    Object? overrideSource = _sentinel,
    bool? allowIdChange,
    Object? pendingRepoRenameUrl = _sentinel,
  }) {
    return App(
      id: id ?? this.id,
      url: url ?? this.url,
      author: author ?? this.author,
      name: name ?? this.name,
      installedVersion: installedVersion == _sentinel
          ? this.installedVersion
          : installedVersion as String?,
      latestVersion: latestVersion ?? this.latestVersion,
      apkUrls: apkUrls ?? List<MapEntry<String, String>>.from(this.apkUrls),
      otherAssetUrls:
          otherAssetUrls ??
          List<MapEntry<String, String>>.from(this.otherAssetUrls),
      preferredApkIndex: preferredApkIndex ?? this.preferredApkIndex,
      additionalSettings:
          additionalSettings ??
          Map<String, dynamic>.from(this.additionalSettings),
      lastUpdateCheck: lastUpdateCheck == _sentinel
          ? this.lastUpdateCheck
          : lastUpdateCheck as DateTime?,
      pinned: pinned ?? this.pinned,
      categories: categories ?? List<String>.from(this.categories),
      releaseDate: releaseDate == _sentinel
          ? this.releaseDate
          : releaseDate as DateTime?,
      changeLog: changeLog == _sentinel ? this.changeLog : changeLog as String?,
      overrideSource: overrideSource == _sentinel
          ? this.overrideSource
          : overrideSource as String?,
      allowIdChange: allowIdChange ?? this.allowIdChange,
      pendingRepoRenameUrl: pendingRepoRenameUrl == _sentinel
          ? this.pendingRepoRenameUrl
          : pendingRepoRenameUrl as String?,
    );
  }

  factory App.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> originalJson = Map.from(json);
    try {
      json = appJSONCompatibilityModifiers(Map.from(json));
    } catch (e) {
      // Fall back to the unmigrated JSON so the app still loads rather than
      // being lost (e.g. when its saved URL no longer matches any source).
      json = originalJson;
      AppLogger.warn(
        'Error running JSON compat modifiers (using original JSON): ${e.toString()}',
      );
    }
    try {
      return App(
        id: json['id'] as String,
        url: json['url'] as String,
        author: json['author'] as String,
        name: json['name'] as String,
        installedVersion: json['installedVersion'] == null
            ? null
            : json['installedVersion'] as String,
        latestVersion: (json['latestVersion'] ?? tr('unknown')) as String,
        apkUrls: assumed2DlistToStringMapList(
          jsonDecode((json['apkUrls'] ?? '[["placeholder", "placeholder"]]')),
        ),
        preferredApkIndex: (json['preferredApkIndex'] ?? -1) as int,
        additionalSettings:
            jsonDecode(json['additionalSettings']) as Map<String, dynamic>,
        lastUpdateCheck: json['lastUpdateCheck'] == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(json['lastUpdateCheck']),
        pinned: json['pinned'] ?? false,
        categories: json['categories'] != null
            ? (json['categories'] as List<dynamic>)
                  .map((e) => e.toString())
                  .toList()
            : json['category'] != null
            ? [json['category'] as String]
            : [],
        releaseDate: json['releaseDate'] == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(json['releaseDate']),
        changeLog: json['changeLog'] == null
            ? null
            : json['changeLog'] as String,
        overrideSource: json['overrideSource'],
        allowIdChange: json['allowIdChange'] ?? false,
        otherAssetUrls: assumed2DlistToStringMapList(
          jsonDecode((json['otherAssetUrls'] ?? '[]')),
        ),
        pendingRepoRenameUrl: json['pendingRepoRenameUrl'] as String?,
      );
    } on TypeError catch (e) {
      AppLogger.error(
        e,
        stackTrace: e.stackTrace,
        message: 'Type mismatch in App.fromJson',
      );
      rethrow;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'author': author,
    'name': name,
    'installedVersion': installedVersion,
    'latestVersion': latestVersion,
    'apkUrls': jsonEncode(stringMapListTo2DList(apkUrls)),
    'otherAssetUrls': jsonEncode(stringMapListTo2DList(otherAssetUrls)),
    'preferredApkIndex': preferredApkIndex,
    'additionalSettings': jsonEncode(additionalSettings),
    'lastUpdateCheck': lastUpdateCheck?.microsecondsSinceEpoch,
    'pinned': pinned,
    'categories': categories,
    'releaseDate': releaseDate?.microsecondsSinceEpoch,
    'changeLog': changeLog,
    'overrideSource': overrideSource,
    'allowIdChange': allowIdChange,
    'pendingRepoRenameUrl': pendingRepoRenameUrl,
  };
}

/// Sentinel value used by [App.copyWith] to distinguish "not provided" from
/// an explicitly supplied `null` for nullable fields. Since [Object] uses
/// identity-based equality, a `const` sentinel guarantees it never collides
/// with any real value the caller could pass.
const _sentinel = Object();

/// Ensures the URL is well-formed and starts with HTTPS.
String preStandardizeUrl(String url) {
  final firstDotIndex = url.indexOf('.');
  if (!(firstDotIndex >= 0 && firstDotIndex != url.length - 1) &&
      !url.contains('[')) {
    throw UnsupportedURLError();
  }
  if (!url.toLowerCase().startsWith('http://') &&
      !url.toLowerCase().startsWith('https://')) {
    url = 'https://$url';
  }
  final uri = Uri.tryParse(url);
  final trailingSlash =
      ((uri?.path.endsWith('/') ?? false) ||
          ((uri?.path.isEmpty ?? false) && url.endsWith('/'))) &&
      (uri?.queryParameters.isEmpty ?? false);

  // Only normalize duplicate slashes in the scheme/host/path portion; leave the
  // query string and fragment untouched so any slashes they contain (e.g. a URL
  // passed as a query parameter) aren't mangled.
  var splitIndex = url.length;
  final queryStart = url.indexOf('?');
  if (queryStart >= 0 && queryStart < splitIndex) {
    splitIndex = queryStart;
  }
  final fragmentStart = url.indexOf('#');
  if (fragmentStart >= 0 && fragmentStart < splitIndex) {
    splitIndex = fragmentStart;
  }
  var mainPart = url.substring(0, splitIndex);
  final rest = url.substring(splitIndex);
  mainPart = mainPart
      .split('/')
      .where((e) => e.isNotEmpty)
      .join('/')
      .replaceFirst(':/', '://');
  url = mainPart + (trailingSlash ? '/' : '') + rest;
  return url;
}

/// Delegates to [ApkFilterService.getApkUrlsFromUrls].
List<MapEntry<String, String>> getApkUrlsFromUrls(List<String> urls) =>
    ApkFilterService().getApkUrlsFromUrls(urls);

/// Delegates to [ApkFilterService.filterApksByArch].
Future<List<MapEntry<String, String>>> filterApksByArch(
  List<MapEntry<String, String>> apkUrls,
) async {
  final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
  return ApkFilterService().filterApksByArch(apkUrls, abis);
}

/// Builds a regex alternation pattern from a list of hostname strings, escaping dots.
String getSourceRegex(List<String> hosts) {
  return '(${hosts.join('|').replaceAll('.', '\\.')})';
}

/// Delegates to [HttpService.createHttpClient].
Future<HttpClient> createHttpClient(
  Map<String, dynamic> additionalSettings,
) async => await HttpService().createHttpClient(additionalSettings);

// ------------------------------------------------------------------------
// More top-level delegation helpers (continued)
// ------------------------------------------------------------------------

/// Delegates to [HttpService.sourceRequestStreamResponse].
Future<MapEntry<Uri, MapEntry<HttpClient, HttpClientResponse>>>
sourceRequestStreamResponse(
  String method,
  Map<String, String>? requestHeaders,
  Map<String, dynamic> additionalSettings, {
  bool followRedirects = true,
  Object? postBody,
}) => HttpService().sourceRequestStreamResponse(
  method,
  requestHeaders,
  additionalSettings,
  followRedirects: followRedirects,
  postBody: postBody,
);

/// Delegates to [HttpService.httpClientResponseStreamToFinalResponse].
Future<http.Response> httpClientResponseStreamToFinalResponse(
  HttpClient httpClient,
  String method,
  String url,
  HttpClientResponse response,
) => HttpService().httpClientResponseStreamToFinalResponse(
  httpClient,
  method,
  url,
  response,
);

// ========================================================================
// AppSource — abstract base class for all app sources.
// ========================================================================

/// Options (in days) for the minimum-age-for-updates setting. Zero disables
/// the delay; the empty string means "use the global default" for per-app
/// overrides.
const List<int> minimumUpdateAgeOptions = [0, 1, 2, 3, 5, 7, 14, 30];

abstract class AppSource {
  List<String> hosts = [];
  List<String> trustedApkHosts = [];
  bool hostChanged = false;
  bool hostIdenticalDespiteAnyChange = false;
  late String name;
  bool enforceTrackOnly = false;
  bool changeLogIfAnyIsMarkDown = true;
  bool changeLogPageIsStandardUrl = false;
  bool appIdInferIsOptional = false;
  bool inferAppIdFromUrlPath = false;
  bool allowSubDomains = false;
  bool naiveStandardVersionDetection = false;
  bool allowOverride = true;
  bool neverAutoSelect = false;
  bool showReleaseDateAsVersionToggle = false;
  bool versionDetectionDisallowed = false;
  bool suppressStandardVersionExtraction = false;
  List<String> excludeCommonSettingKeys = [];
  bool urlsAlwaysHaveExtension = false;
  bool allowInsecureRedirects = false;
  bool allowIncludeZips = false;
  bool allowIncludeTarballs = false;
  String get sourceIdentifier => runtimeType.toString();

  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    return null;
  }

  AppSource() {
    name = runtimeType.toString();
  }

  String standardizeUrl(String url) {
    url = preStandardizeUrl(url);
    if (!hostChanged) {
      url = sourceSpecificStandardizeURL(url);
    }
    return url;
  }

  App postProcessApp(App app) {
    return app;
  }

  Future<Map<String, dynamic>> buildMergedSettings(
    Map<String, dynamic> additionalSettings,
    SettingsProvider settingsProvider,
  ) async {
    return {
      ...additionalSettings,
      ...(await getSourceConfigValues(additionalSettings, settingsProvider)),
    };
  }

  Future<http.Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    final sp = SettingsProvider();
    await sp.initializeSettings();
    final additionalSettingsPlusSourceConfig = await buildMergedSettings(
      additionalSettings,
      sp,
    );
    url = await generalReqPrefetchModifier(
      url,
      additionalSettingsPlusSourceConfig,
    );
    additionalSettingsPlusSourceConfig['url'] = url;
    additionalSettingsPlusSourceConfig['enableCertificatePinning'] =
        sp.enableCertificatePinning;
    additionalSettingsPlusSourceConfig['allowInsecureRedirects'] =
        allowInsecureRedirects;
    final method = postBody == null ? 'GET' : 'POST';
    final requestHeaders = await getRequestHeaders(
      additionalSettingsPlusSourceConfig,
      url,
    );
    final streamedResponseUrlWithResponseAndClient =
        await sourceRequestStreamResponse(
          method,
          requestHeaders,
          additionalSettingsPlusSourceConfig,
          followRedirects: followRedirects,
          postBody: postBody,
        );
    return await httpClientResponseStreamToFinalResponse(
      streamedResponseUrlWithResponseAndClient.value.key,
      method,
      streamedResponseUrlWithResponseAndClient.key.toString(),
      streamedResponseUrlWithResponseAndClient.value.value,
    );
  }

  Map<String, dynamic> runOnAddAppInputChange(String inputUrl) => {};

  /// Delegates to [ApkFilterService.apkContainerExtensions].
  static List<String> get apkContainerExtensions =>
      ApkFilterService.apkContainerExtensions;

  /// Delegates to [ApkFilterService.archiveExtensions].
  static List<String> get archiveExtensions =>
      ApkFilterService.archiveExtensions;

  /// Delegates to [ApkFilterService.tarballExtensions].
  static List<String> get tarballExtensions =>
      ApkFilterService.tarballExtensions;

  /// Delegates to [ApkFilterService.isApkOrContainerFile].
  static bool isApkOrContainerFile(
    String name, {
    bool includeArchives = false,
    bool includeTarballs = false,
  }) => ApkFilterService.isApkOrContainerFile(
    name,
    includeArchives: includeArchives,
    includeTarballs: includeTarballs,
  );

  /// A convenience for the common standardize-by-regex pattern: build a regex
  /// from the source's [hosts] plus the given subdomain prefix and path, match
  /// against [url], and return the match or throw [InvalidURLError].  Many
  /// sources (16+) repeat this block verbatim; subclasses can call this
  /// helper instead.
  String standardizeUrlWithRegex(
    String url, {
    required String subdomainPrefix,
    required String pathPattern,
  }) {
    final re = RegExp(
      '^https?://$subdomainPrefix${getSourceRegex(hosts)}$pathPattern',
      caseSensitive: false,
    );
    final match = re.firstMatch(url);
    if (match == null) throw InvalidURLError(name)..url = url;
    return match.group(0)!;
  }

  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    throw NotImplementedError();
  }

  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) {
    throw NotImplementedError();
  }

  /// Per-source additional form items (e.g. GitHub's sort method, HTML's version regex).
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [];

  static List<GeneratedFormItem> get fallbackToOlderReleasesFormItem => [
    GeneratedFormSwitch(
      'fallbackToOlderReleases',
      label: tr('fallbackToOlderReleases'),
      value: true,
    ),
  ];

  /// Some additional data may be needed for Apps regardless of Source
  List<List<GeneratedFormItem>> get _commonAppSettingFormItems => [
    [GeneratedFormSwitch('trackOnly', label: tr('trackOnly'))],
    [
      GeneratedFormTextField(
        'versionExtractionRegEx',
        label: tr('trimVersionString'),
        required: false,
        additionalValidators: [(value) => regExValidator(value)],
      ),
    ],
    [
      GeneratedFormTextField(
        'matchGroupToUse',
        label: tr('matchGroupToUseForX', args: [tr('trimVersionString')]),
        required: false,
        hint: '\$0',
      ),
    ],
    [
      GeneratedFormSwitch(
        'versionDetection',
        label: tr('versionDetectionExplanation'),
        value: true,
      ),
    ],
    [
      GeneratedFormSwitch(
        'useVersionCodeAsOSVersion',
        label: tr('useVersionCodeAsOSVersion'),
        value: false,
      ),
    ],
    [
      GeneratedFormTextField(
        'apkFilterRegEx',
        label: tr('filterAPKsByRegEx'),
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
        'invertAPKFilter',
        label: '${tr('invertRegEx')} (${tr('filterAPKsByRegEx')})',
        value: false,
      ),
    ],
    [
      GeneratedFormSwitch(
        'autoApkFilterByArch',
        label: tr('autoApkFilterByArch'),
        value: true,
      ),
    ],
    [
      GeneratedFormSlider(
        'minimumUpdateAgeDays',
        [
          const MapEntry('', 'useGlobalDefault'),
          for (final days in minimumUpdateAgeOptions)
            MapEntry(days.toString(), days == 0 ? 'none' : days.toString()),
        ],
        label: tr('minimumUpdateAgeDays'),
        value: '',
        required: false,
      ),
    ],
    [GeneratedFormTextField('appName', label: tr('appName'), required: false)],
    [GeneratedFormTextField('appAuthor', label: tr('author'), required: false)],
    [
      GeneratedFormSwitch(
        'shizukuPretendToBeGooglePlay',
        label: tr('shizukuPretendToBeGooglePlay'),
        value: false,
      ),
    ],
    [
      GeneratedFormSwitch(
        'allowInsecure',
        label: tr('allowInsecure'),
        value: false,
      ),
    ],
    [
      GeneratedFormSwitch(
        'exemptFromBackgroundUpdates',
        label: tr('exemptFromBackgroundUpdates'),
      ),
    ],
    [
      GeneratedFormSwitch(
        'skipUpdateNotifications',
        label: tr('skipUpdateNotifications'),
      ),
    ],
    [GeneratedFormTextField('about', label: tr('about'), required: false)],
    [
      GeneratedFormSwitch(
        'refreshBeforeDownload',
        label: tr('refreshBeforeDownload'),
      ),
    ],
  ];

  /// Combines per-source form items with the common app-setting form items,
  /// interspersing conditional items (zip/tarball options, version toggles) and
  /// filtering out excluded keys. Cloned so that callers cannot mutate the
  /// shared source-owned form items. Rebuilt on every access so that labels
  /// pick up the current locale via tr().
  List<List<GeneratedFormItem>> get combinedAppSpecificSettingFormItems {
    var agnosticItems = cloneFormItems(_commonAppSettingFormItems);

    final versionDetectionIdx = agnosticItems.indexWhere(
      (row) => row.any((item) => item.key == 'versionDetection'),
    );
    if (showReleaseDateAsVersionToggle &&
        versionDetectionIdx >= 0 &&
        !agnosticItems.any(
          (row) => row.any((item) => item.key == 'releaseDateAsVersion'),
        )) {
      agnosticItems.insert(versionDetectionIdx + 1, [
        GeneratedFormSwitch(
          'releaseDateAsVersion',
          label: '${tr('releaseDateAsVersion')} (${tr('pseudoVersion')})',
          value: false,
        ),
      ]);
    }

    agnosticItems = agnosticItems
        .map(
          (e) => e
              .where((ee) => !excludeCommonSettingKeys.contains(ee.key))
              .toList(),
        )
        .where((e) => e.isNotEmpty)
        .toList();

    final moreConditionalItems = <List<GeneratedFormItem>>[];
    if (allowIncludeZips) {
      moreConditionalItems.addAll([
        [
          GeneratedFormSwitch(
            'includeZips',
            label: tr('includeZips'),
            value: false,
          ),
        ],
        [
          GeneratedFormTextField(
            'zippedApkFilterRegEx',
            label: tr('zippedApkFilterRegEx'),
            required: false,
            additionalValidators: [
              (value) {
                return regExValidator(value);
              },
            ],
          ),
        ],
      ]);
    }

    if (allowIncludeTarballs) {
      moreConditionalItems.addAll([
        [
          GeneratedFormSwitch(
            'includeTarballs',
            label: tr('includeTarballs'),
            value: false,
          ),
        ],
        [
          GeneratedFormTextField(
            'tarballedApkFilterRegEx',
            label: tr('tarballedApkFilterRegEx'),
            required: false,
            additionalValidators: [
              (value) {
                return regExValidator(value);
              },
            ],
          ),
        ],
      ]);
    }

    if (versionDetectionDisallowed) {
      for (var item in agnosticItems.expand((row) => row)) {
        if (item.key == 'versionDetection' ||
            item.key == 'useVersionCodeAsOSVersion') {
          (item as GeneratedFormSwitch).disabled = true;
          item.value = false;
        }
      }
    }

    return [
      // Clone so callers (e.g. the add-app form pre-filling default values)
      // can't mutate the source-owned items. Sources are now cached/shared, so
      // an in-place edit here would otherwise leak across apps.
      ...cloneFormItems(additionalSourceAppSpecificSettingFormItems),
      ...agnosticItems,
      ...moreConditionalItems,
    ];
  }

  bool get hasAppSpecificSettings =>
      combinedAppSpecificSettingFormItems.isNotEmpty;

  /// Flattened, read-only view of [combinedAppSpecificSettingFormItems],
  /// used by callers that only need to enumerate keys without cloning.
  List<GeneratedFormItem> get flatCombinedFormItemsReadOnly =>
      combinedAppSpecificSettingFormItems.expand((row) => row).toList();

  /// Source-level additional settings (not specific to Apps) backed by [SettingsProvider].
  /// If the source has been overridden, per-app additional settings take precedence.
  List<GeneratedFormItem> get sourceConfigSettingFormItems => [];
  Future<Map<String, String>> getSourceConfigValues(
    Map<String, dynamic> additionalSettings,
    SettingsProvider settingsProvider,
  ) async {
    final Map<String, String> results = {};
    for (var e in sourceConfigSettingFormItems) {
      var val = hostChanged && !hostIdenticalDespiteAnyChange
          ? additionalSettings[e.key]
          : (additionalSettings[e.key] is String &&
                (additionalSettings[e.key] as String).isNotEmpty)
          ? additionalSettings[e.key]
          : (e is GeneratedFormSwitch
                ? settingsProvider.getSettingBool(e.key).toString()
                : settingsProvider.getSettingString(e.key));
      if (val != null) {
        if (e is GeneratedFormSwitch) {
          val = val.toString();
        }
        results[e.key] = val;
      }
    }
    return results;
  }

  String? changeLogPageFromStandardUrl(String standardUrl) {
    return changeLogPageIsStandardUrl ? standardUrl : null;
  }

  Future<String?> getSourceNote() async {
    return null;
  }

  Future<String> assetUrlPrefetchModifier(
    String assetUrl,
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    return assetUrl;
  }

  Future<String> generalReqPrefetchModifier(
    String reqUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    return reqUrl;
  }

  bool canSearch = false;
  bool includeAdditionalOptsInMainSearch = false;
  List<GeneratedFormItem> get searchQuerySettingFormItems => [];
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) {
    throw NotImplementedError();
  }

  static String stripLastPathSegment(String url) {
    final uri = Uri.parse(url);
    return uri
        .replace(
          pathSegments: uri.pathSegments.sublist(
            0,
            uri.pathSegments.length - 1,
          ),
        )
        .toString();
  }

  static Future<String?> tryInferAppIdFromLastPathSegment(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    return Uri.parse(
      standardUrl,
    ).pathSegments.where((s) => s.isNotEmpty).lastOrNull;
  }

  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    if (inferAppIdFromUrlPath) {
      return tryInferAppIdFromLastPathSegment(standardUrl);
    }
    return null;
  }
}

/// Delegates to [HttpService.getHttpError].
ObtainiumError getObtainiumHttpError(http.Response res) =>
    HttpService().getHttpError(res);

// ========================================================================
// MassAppUrlSource — abstract base for mass URL import sources.
// ========================================================================

abstract class MassAppUrlSource {
  String get name;
  List<String> get requiredArgs;
  Future<Map<String, List<String>>> getUrlsWithDescriptions(List<String> args);
}

/// Delegates to [VersionService.regExValidator].
String? regExValidator(String? value) => VersionService().regExValidator(value);

/// Returns true if the app's ID is a temporary placeholder rather than a real
/// package name. Matches [generateTempID]'s sha256-hex prefix and legacy numeric
/// IDs; real package names contain a dot and never match.
bool isTempId(App app) {
  return RegExp(r'^[0-9]+$').hasMatch(app.id) ||
      RegExp(r'^[0-9a-f]{12}$').hasMatch(app.id);
}

/// Delegates to [VersionService.replaceMatchGroupsInString].
String? replaceMatchGroupsInString(
  RegExpMatch match,
  String matchGroupString,
) => VersionService().replaceMatchGroupsInString(match, matchGroupString);

/// Delegates to [VersionService.extractVersion].
String? extractVersion(
  String? versionExtractionRegEx,
  String? matchGroupString,
  String stringToCheck,
) => VersionService().extractVersion(
  versionExtractionRegEx,
  matchGroupString,
  stringToCheck,
);

/// Delegates to [ApkFilterService.filterApks].
List<MapEntry<String, String>> filterApks(
  List<MapEntry<String, String>> apkUrls,
  String? apkFilterRegEx,
  bool? invert,
) => ApkFilterService().filterApks(apkUrls, apkFilterRegEx, invert);

/// Returns true when the app uses pseudo-versioning (track-only or disabled version detection).
bool isVersionPseudo(App app) =>
    app.settings.getBool('trackOnly') ||
    (app.installedVersion != null && !app.settings.getBool('versionDetection'));

// ========================================================================
// SourceProvider — singleton that manages available AppSource instances,
// URL-to-source resolution, and app construction from URLs.
// ========================================================================

class SourceProvider {
  static final SourceProvider _instance = SourceProvider._();
  factory SourceProvider() => _instance;
  SourceProvider._();

  // Builds a fresh set of source instances. Adding a source here makes it
  // available via the service. Kept private so callers go through [sources]
  // (cached) or, when per-call mutation is needed, [_buildSources] directly.
  static List<AppSource> _buildSources() => [
    GitHub(),
    GitLab(),
    Codeberg(),
    FDroid(),
    FDroidRepo(),
    IzzyOnDroid(),
    SourceHut(),
    APKPure(),
    Aptoide(),
    Uptodown(),
    ItchIO(),
    HuaweiAppGallery(),
    Tencent(),
    VivoAppStore(),
    RuStore(),
    Farsroid(),
    SamsungGalaxyStore(),
    LiteAPKs(),
    Apk4Free(),
    CoolApk(),
    SourceForge(),
    Jenkins(),
    APKMirror(),
    APKCombo(),
    RockMods(),
    TelegramApp(),
    NeutronCode(),
    DirectAPKLink(),
    HTML(), // Must be the last entry — hostless sources are tried in order and HTML is the catch-all fallback
  ];

  /// Cached, read-only source list built lazily by [_buildSources].
  /// Because sources are immutable after construction, the cache is safe.
  static List<AppSource>? _cachedSources;
  List<AppSource> get sources => _cachedSources ??= _buildSources();

  /// Add mass URL source classes here so they are available via the service.
  List<MassAppUrlSource> massUrlSources = [GitHubStars()];

  AppSource getSource(String url, {String? overrideSource}) {
    url = preStandardizeUrl(url);
    if (overrideSource != null) {
      // The override path mutates the chosen source's host config, so build a
      // throwaway instance here rather than touching the shared cache.
      final srcs = _buildSources().where(
        (e) => e.sourceIdentifier == overrideSource,
      );
      if (srcs.isEmpty) {
        throw UnsupportedURLError()..url = url;
      }
      final res = srcs.first;
      final originalHosts = res.hosts;
      final newHost = Uri.parse(url).host;
      res.hosts = [newHost];
      res.hostChanged = true;
      if (originalHosts.contains(newHost)) {
        res.hostIdenticalDespiteAnyChange = true;
      }
      return res;
    }
    // The non-override path is read-only, so reuse the cached source set.
    final allSources = sources;
    AppSource? source;
    for (var s in allSources.where((element) => element.hosts.isNotEmpty)) {
      // A non-match here is expected control flow during source auto-detection,
      // so failures are intentionally not logged (they are just noise).
      try {
        if (RegExp(
          '^${s.allowSubDomains ? '([^\\.]+\\.)*' : '(www\\.)?'}(${getSourceRegex(s.hosts)})\$',
        ).hasMatch(Uri.parse(url).host)) {
          source = s;
          break;
        }
      } on ObtainiumError {
        // Ignore and try the next source.
      }
    }
    if (source == null) {
      for (var s in allSources.where(
        (element) => element.hosts.isEmpty && !element.neverAutoSelect,
      )) {
        // As above, hostless sources are tried in order until one accepts the
        // URL; a rejection is normal and must not be logged as an error.
        try {
          s.sourceSpecificStandardizeURL(url, forSelection: true);
          source = s;
          break;
        } on ObtainiumError {
          // Ignore and try the next source.
        }
      }
    }
    if (source == null) {
      throw UnsupportedURLError()..url = url;
    }
    return source;
  }

  String generateTempID(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) => sha256
      .convert(utf8.encode(standardUrl + additionalSettings.toString()))
      .toString()
      .substring(0, 12);

  Future<String> _resolveAppId(
    AppSource source,
    App? currentApp,
    Map<String, dynamic> additionalSettings,
    bool trackOnly,
    String standardUrl,
    bool inferAppIdIfOptional,
  ) async {
    if (currentApp?.id != null) return currentApp!.id;
    final explicitId = additionalSettings['appId'] as String?;
    if (explicitId != null) return explicitId;
    if (!trackOnly &&
        (!source.appIdInferIsOptional ||
            (source.appIdInferIsOptional && inferAppIdIfOptional))) {
      final inferred = await source.tryInferringAppId(
        standardUrl,
        additionalSettings: additionalSettings,
      );
      if (inferred != null) return inferred;
    }
    return generateTempID(standardUrl, additionalSettings);
  }

  Future<App> getApp(
    AppSource source,
    String url,
    Map<String, dynamic> additionalSettings, {
    App? currentApp,
    bool trackOnlyOverride = false,
    bool sourceIsOverriden = false,
    bool inferAppIdIfOptional = false,
  }) async {
    additionalSettings = Map<String, dynamic>.from(additionalSettings);
    if (trackOnlyOverride || source.enforceTrackOnly) {
      additionalSettings['trackOnly'] = true;
    }
    final trackOnly = additionalSettings['trackOnly'] == true;
    final String standardUrl;
    try {
      standardUrl = source.standardizeUrl(url);
    } on ObtainiumError catch (e) {
      throw e..withUrlContext(url);
    }
    APKDetails apk;
    try {
      apk = await source.getLatestAPKDetails(standardUrl, additionalSettings);
    } on ObtainiumError catch (e) {
      throw e..withUrlContext(standardUrl);
    }

    if (!source.suppressStandardVersionExtraction) {
      final String? extractedVersion = extractVersion(
        additionalSettings['versionExtractionRegEx'] as String?,
        additionalSettings['matchGroupToUse'] as String?,
        apk.version,
      );
      if (extractedVersion != null) {
        apk = apk.copyWith(version: extractedVersion);
      }
    }

    if (additionalSettings['releaseDateAsVersion'] == true &&
        apk.releaseDate != null) {
      apk = apk.copyWith(
        version: apk.releaseDate!.microsecondsSinceEpoch.toString(),
      );
    }
    final settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    apk = apk.copyWith(
      apkUrls: filterApks(
        apk.apkUrls,
        additionalSettings['apkFilterRegEx'] ??
            settingsProvider.globalApkFilterRegEx,
        additionalSettings['invertAPKFilter'],
      ),
    );
    if (apk.apkUrls.isEmpty && !trackOnly) {
      throw NoAPKError()..url = standardUrl;
    }
    if (additionalSettings['autoApkFilterByArch'] == true) {
      apk = apk.copyWith(apkUrls: await filterApksByArch(apk.apkUrls));
      if (apk.apkUrls.isEmpty && !trackOnly) {
        throw NoAPKError()..url = standardUrl;
      }
    }
    var name = currentApp != null ? currentApp.name.trim() : '';
    name = name.isNotEmpty ? name : apk.names.name;
    final App finalApp = App(
      id: await _resolveAppId(
        source,
        currentApp,
        additionalSettings,
        trackOnly,
        standardUrl,
        inferAppIdIfOptional,
      ),
      url: standardUrl,
      author: apk.names.author,
      name: name,
      installedVersion: currentApp?.installedVersion,
      latestVersion: apk.version,
      apkUrls: apk.apkUrls,
      preferredApkIndex:
          currentApp?.preferredApkIndex ??
          (apk.apkUrls.isNotEmpty ? apk.apkUrls.length - 1 : 0),
      additionalSettings: additionalSettings,
      lastUpdateCheck: DateTime.now(),
      pinned: currentApp?.pinned ?? false,
      categories: currentApp?.categories ?? const [],
      releaseDate: apk.releaseDate,
      changeLog: apk.changeLog,
      overrideSource: sourceIsOverriden
          ? source.sourceIdentifier
          : currentApp?.overrideSource,
      allowIdChange:
          currentApp?.allowIdChange ??
          trackOnly || (source.appIdInferIsOptional && inferAppIdIfOptional),
      otherAssetUrls: apk.allAssetUrls
          .where((a) => apk.apkUrls.indexWhere((p) => a.key == p.key) < 0)
          .toList(),
    );
    return source.postProcessApp(finalApp);
  }

  // Returns errors in [results, errors] instead of throwing them
  Future<List<dynamic>> getAppsByURLNaive(
    List<String> urls, {
    Set<String> alreadyAddedUrls = const {},
    AppSource? sourceOverride,
  }) async {
    final List<App> apps = [];
    final Map<String, dynamic> errors = {};
    const concurrency = kDefaultFetchConcurrency;
    for (var i = 0; i < urls.length; i += concurrency) {
      final end = i + concurrency > urls.length ? urls.length : i + concurrency;
      final batch = urls.sublist(i, end);
      final results = await Future.wait(
        batch.map((url) async {
          try {
            if (alreadyAddedUrls.contains(url)) {
              throw ObtainiumError('${tr('appAlreadyAdded')} ($url)');
            }
            final source = sourceOverride ?? getSource(url);
            return await getApp(
              source,
              url,
              sourceIsOverriden: sourceOverride != null,
              getDefaultValuesFromFormItems(
                source.combinedAppSpecificSettingFormItems,
              ),
            );
          } catch (e) {
            return e;
          }
        }),
      );
      for (var j = 0; j < batch.length; j++) {
        final result = results[j];
        if (result is App) {
          apps.add(result);
        } else {
          errors[batch[j]] = result;
        }
      }
    }
    return [apps, errors];
  }
}

// ========================================================================
// TypedSettings — type-safe wrapper around App.additionalSettings.
// ========================================================================

/// Type-safe wrapper around [App.additionalSettings] that eliminates
/// manual casts and null checks when reading per-source configuration values.
///
/// Usage:
/// ```dart
/// if (app.settings.getBool('trackOnly')) { ... }
/// String? regex = app.settings.getStringOrNull('apkFilterRegEx');
/// ```
class TypedSettings {
  final Map<String, dynamic> _raw;

  const TypedSettings(Map<String, dynamic> raw) : _raw = raw;

  bool getBool(String key, {bool defaultValue = false}) {
    final val = _raw[key];
    if (val == null) return defaultValue;
    if (val is bool) return val;
    if (val is String) return val == 'true';
    return defaultValue;
  }

  int? getIntOrNull(String key) {
    final val = _raw[key];
    if (val is int) return val;
    if (val is String) return int.tryParse(val);
    return null;
  }

  String? getStringOrNull(String key) {
    final val = _raw[key];
    if (val == null) return null;
    if (val is String) return val.isNotEmpty ? val : null;
    return val.toString();
  }

  String getString(String key, {String defaultValue = ''}) =>
      getStringOrNull(key) ?? defaultValue;

  @override
  String toString() => _raw.toString();
}

// ========================================================================
// HttpService — HTTP client creation, streaming requests, and error mapping.
// ========================================================================

class HttpService {
  static const int maxRedirects = 10;

  /// Headers that must never be forwarded to a different origin on redirect.
  static const Set<String> sensitiveRedirectHeaders = {
    'authorization',
    'proxy-authorization',
    'cookie',
  };

  static final Map<String, Future<List<Uint8List>>> _certificatePins = {
    'github.com': _loadCertificateFromAsset([
      'assets/ca-certs/sectigo-pub-serv-auth-r46.crt',
      'assets/ca-certs/sectigo-pub-serv-auth-e46.crt',

      // redirects from api.github.com for obtaining release assets point to
      // release-assets.githubusercontent.com which uses ISRG (Let's Encrypt)
      // adding that as another section doesn't work because of
      // HttpClient follows redirects (as intended)
      'assets/ca-certs/isrg-root-x1.crt',
      'assets/ca-certs/isrg-root-x2.crt',
      'assets/ca-certs/isrg-root-ye.crt',
      'assets/ca-certs/isrg-root-yr.crt',
    ]),
    'codeberg.org': _loadCertificateFromAsset([
      'assets/ca-certs/isrg-root-x1.crt',
      'assets/ca-certs/isrg-root-x2.crt',
      'assets/ca-certs/isrg-root-ye.crt',
      'assets/ca-certs/isrg-root-yr.crt',
    ]),
    'gitlab.com': _loadCertificateFromAsset([
      'assets/ca-certs/sectigo-pub-serv-auth-r46.crt',
      'assets/ca-certs/sectigo-pub-serv-auth-e46.crt',
    ]),
    'rustore.ru': _loadCertificateFromAsset([
      'assets/ca-certs/harica-tls-root-2021-rsa.crt',
      'assets/ca-certs/harica-tls-root-2021-ecc.crt',
      'assets/ca-certs/russian-mintsifry-root.crt',
    ])
  };

  static Future<List<Uint8List>> _loadCertificateFromAsset(
    List<String> assetsPath,
  ) async {
    final List<Uint8List> certsBytes = [];
    for (final certPath in assetsPath) {
      final cert = await rootBundle.load(certPath);
      certsBytes.add(cert.buffer.asUint8List());
    }
    return certsBytes;
  }

  static String _extractRootHost(String host) {
    final parts = host.split('.');
    return parts.length > 2
        ? parts.sublist(parts.length - 2).join('.')
        : host;
  }

  Future<SecurityContext?> _createCertPinning(String url) async {
    final uri = Uri.parse(url);
    final host = uri.host;
    final rootHost = _extractRootHost(host);
    if (_certificatePins.containsKey(host)) {
      final certsBytes = await _certificatePins[host]!;
      final securityContext = SecurityContext();
      for (final certBytes in certsBytes) {
        securityContext.setTrustedCertificatesBytes(certBytes);
      }
      return securityContext;
    }
    else if (_certificatePins.containsKey(rootHost)) {
      final certsBytes = await _certificatePins[rootHost]!;
      final securityContext = SecurityContext();
      for (final certBytes in certsBytes) {
        securityContext.setTrustedCertificatesBytes(certBytes);
      }
      return securityContext;
    }
    else {
      return null;
    }
  }

  /* Basically RuStore switched partially (and in the future it may be fully)
     to russian government Mintsifry CA, which isnt trusted by Android nor
     Chrome Root Store. This is workaround to trust Mintsifry CA for network
     requests made to RuStore domains and subdomains
   */
  Future<SecurityContext> _ruStoreWorkaroundSecurityContext() async {
    final securityContext = SecurityContext(withTrustedRoots: true);
    final cert = await rootBundle.load('assets/ca-certs/russian-mintsifry-root.crt');
    securityContext.setTrustedCertificatesBytes(cert.buffer.asUint8List());
    return securityContext;
  }

  Future<HttpClient> createHttpClient(
    Map<String, dynamic> additionalSettings,
  ) async {
    final insecure = additionalSettings['allowInsecure'] == true;
    final url = additionalSettings['url'] as String;
    final pinning = additionalSettings['enableCertificatePinning'] == true;
    SecurityContext? securityContext;
    final host = Uri.parse(url).host;
    if (pinning) {
      securityContext = await _createCertPinning(url);
    }
    else if (_extractRootHost(host) == 'rustore.ru') {
      securityContext = await _ruStoreWorkaroundSecurityContext();
    }
    final client = securityContext != null
        ? HttpClient(context: securityContext)
        : HttpClient();
    if (insecure) {
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
            if (_certificatePins.containsKey(host) && pinning) {
              return false;
            }
            return true;
          };
    }
    return client;
  }

  /// Whether two URIs share the same origin (scheme, host, and port — Dart
  /// normalizes default ports for http/https, so explicit and implicit
  /// default ports compare equal).
  static bool isSameOrigin(Uri a, Uri b) =>
      a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
      a.host.toLowerCase() == b.host.toLowerCase() &&
      a.port == b.port;

  String ensureAbsoluteUrl(String ambiguousUrl, Uri referenceAbsoluteUrl) {
    try {
      ambiguousUrl = ambiguousUrl.trim();
      if (Uri.parse(ambiguousUrl).isAbsolute) {
        return ambiguousUrl;
      }
    } on FormatException {
      // Non-parsable URL, fall through to resolve logic below
    }
    return referenceAbsoluteUrl.resolve(ambiguousUrl).toString();
  }

  /// Performs an HTTP request with redirect following, returning the final URL, client, and streamed response.
  Future<MapEntry<Uri, MapEntry<HttpClient, HttpClientResponse>>>
  sourceRequestStreamResponse(
    String method,
    Map<String, String>? requestHeaders,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    final url = additionalSettings['url'] as String;
    var currentUrl = Uri.parse(url);
    var redirectCount = 0;
    List<Cookie> cookies = [];
    HttpClient? httpClient;
    while (redirectCount < maxRedirects) {
      httpClient = await createHttpClient(additionalSettings);
      final request = await httpClient.openUrl(method, currentUrl);
      if (requestHeaders != null) {
        requestHeaders.forEach((key, value) {
          request.headers.set(key, value);
        });
      }
      request.cookies.addAll(cookies);
      request.followRedirects = false;
      if (postBody != null) {
        if (postBody is String) {
          request.write(postBody);
        } else {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(postBody));
        }
      }
      final response = await request.close();

      if (followRedirects &&
          (response.statusCode >= 300 && response.statusCode <= 399)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location != null) {
          final nextUrl = Uri.parse(ensureAbsoluteUrl(location, currentUrl));
          if (currentUrl.scheme == 'https' &&
              nextUrl.scheme == 'http' &&
              additionalSettings['allowInsecure'] != true &&
              additionalSettings['allowInsecureRedirects'] != true) {
            // Never follow a redirect that downgrades to cleartext HTTP.
            httpClient.close();
            throw ObtainiumError(tr('insecureRedirect'));
          }
          if (!isSameOrigin(currentUrl, nextUrl)) {
            // Do not forward credentials or session cookies to a
            // different origin.
            requestHeaders = requestHeaders == null
                ? null
                : (Map<String, String>.from(requestHeaders)..removeWhere(
                    (key, _) =>
                        sensitiveRedirectHeaders.contains(key.toLowerCase()),
                  ));
            cookies = [];
          } else {
            cookies = response.cookies;
          }
          currentUrl = nextUrl;
          redirectCount++;
          httpClient.close();
          httpClient = null;
          continue;
        }
      }

      return MapEntry(currentUrl, MapEntry(httpClient, response));
    }
    httpClient?.close();
    throw ObtainiumError(tr('tooManyRedirects'));
  }

  Future<http.Response> httpClientResponseStreamToFinalResponse(
    HttpClient httpClient,
    String method,
    String url,
    HttpClientResponse response,
  ) async {
    try {
      final bytes = (await response.fold<BytesBuilder>(
        BytesBuilder(),
        (b, d) => b..add(d),
      )).toBytes();

      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name] = values.join(', ');
      });

      return http.Response.bytes(
        bytes,
        response.statusCode,
        headers: headers,
        request: http.Request(method, Uri.parse(url)),
      );
    } finally {
      httpClient.close();
    }
  }

  ObtainiumError getHttpError(http.Response res) {
    if (res.statusCode == 404) return NoReleasesError();
    if (res.statusCode == 429 || res.statusCode == 403) {
      final retryAfter = res.headers['retry-after'];
      final secs = retryAfter != null ? int.tryParse(retryAfter) : null;
      if (secs != null) return RateLimitError((secs / 60).ceil());
      return RateLimitError(1);
    }
    return ObtainiumError(
      (res.reasonPhrase != null && res.reasonPhrase!.isNotEmpty)
          ? res.reasonPhrase!
          : tr('errorWithHttpStatusCode', args: [res.statusCode.toString()]),
      code: 'HTTP_ERROR',
    );
  }
}

// ========================================================================
// VersionService — regex-based version extraction, validation, and matching.
// ========================================================================

class VersionService {
  static const defaultMatchGroup = '0';

  static final List<String> standardVersionRegExStrings =
      _generateStandardVersionRegExStrings();

  static final List<MapEntry<String, RegExp>> strictStandardVersionRegExes =
      standardVersionRegExStrings
          .map((p) => MapEntry(p, RegExp('^$p\$')))
          .toList();

  static final List<MapEntry<String, RegExp>> looseStandardVersionRegExes =
      standardVersionRegExStrings.map((p) => MapEntry(p, RegExp(p))).toList();

  static List<String> _generateStandardVersionRegExStrings() {
    final basics = [
      '[0-9]+',
      '[0-9]+\\.[0-9]+',
      '[0-9]+\\.[0-9]+\\.[0-9]+',
      '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+',
    ];
    final preSuffixes = ['-', '\\+'];
    final suffixes = [
      'alpha',
      'beta',
      'rc',
      'pre',
      'dev',
      'snapshot',
      'nightly',
      'ose',
      '[0-9]+',
    ];
    final finals = ['\\+[0-9]+', '[0-9]+'];
    final List<String> results = [];
    for (var b in basics) {
      results.add(b);
      for (var p in preSuffixes) {
        for (var s in suffixes) {
          results.add('$b$s');
          results.add('$b$p$s');
          for (var f in finals) {
            results.add('$b$s$f');
            results.add('$b$p$s$f');
          }
        }
      }
    }
    return results.toSet().toList();
  }

  String? regExValidator(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      RegExp(value);
    } catch (e) {
      return tr('invalidRegEx');
    }
    return null;
  }

  /// Replaces `$N` references in a string with the corresponding regex match groups.
  String? replaceMatchGroupsInString(
    RegExpMatch match,
    String matchGroupString,
  ) {
    if (RegExp('^\\d+\$').hasMatch(matchGroupString)) {
      matchGroupString = '\$$matchGroupString';
    }
    final numberRegex = RegExp(r'\$\d+');
    final numbers = numberRegex.allMatches(matchGroupString);
    if (numbers.isEmpty) {
      return null;
    }
    var outputString = matchGroupString;
    for (final numberMatch in numbers) {
      final number = numberMatch.group(0)!;
      final matchGroup = match.group(int.parse(number.substring(1))) ?? '';
      final isEscaped = outputString.contains('\\$number');
      if (!isEscaped) {
        outputString = outputString.replaceAll(number, matchGroup);
      } else {
        outputString = outputString.replaceAll('\\$number', number);
      }
    }
    return outputString;
  }

  /// Applies a version extraction regex to a string and returns the captured match group.
  String? extractVersion(
    String? versionExtractionRegEx,
    String? matchGroupString,
    String stringToCheck,
  ) {
    if (versionExtractionRegEx?.isNotEmpty == true) {
      String? version = stringToCheck;
      final match = RegExp(versionExtractionRegEx!).allMatches(version);
      if (match.isEmpty) {
        throw NoVersionError();
      }
      matchGroupString = matchGroupString?.trim() ?? '';
      if (matchGroupString.isEmpty) {
        matchGroupString = defaultMatchGroup;
      }
      version = replaceMatchGroupsInString(match.last, matchGroupString);
      if (version?.isNotEmpty != true) {
        throw NoVersionError();
      }
      return version!;
    } else {
      return null;
    }
  }

  static final Map<String, Set<String>> _strictFormatCache = {};
  static final Map<String, Set<String>> _looseFormatCache = {};
  static const int _maxFormatCacheSize = 4096;

  Set<String> findStandardFormatsForVersion(String version, bool strict) {
    final cache = strict ? _strictFormatCache : _looseFormatCache;
    final cached = cache[version];
    if (cached != null) return cached;

    final Set<String> results = {};
    final patterns = strict
        ? strictStandardVersionRegExes
        : looseStandardVersionRegExes;
    for (var entry in patterns) {
      if (entry.value.hasMatch(version)) {
        results.add(entry.key);
      }
    }
    if (cache.length >= _maxFormatCacheSize) cache.clear();
    cache[version] = results;
    return results;
  }

  bool doStringsMatchUnderRegEx(String pattern, String value1, String value2) {
    final r = RegExp(pattern);
    final m1 = r.firstMatch(value1);
    final m2 = r.firstMatch(value2);
    return m1 != null && m2 != null
        ? value1.substring(m1.start, m1.end) ==
              value2.substring(m2.start, m2.end)
        : false;
  }

  /// Compares two versions numerically when they share a common non-strict
  /// standard format. Returns a negative value if [version1] is older than
  /// [version2], a positive value if it is newer, 0 if they are numerically
  /// equal, and null if they cannot be compared in a valid way.
  int? compareVersionsNumerically(String version1, String version2) {
    final commonFormats = findStandardFormatsForVersion(
      version1,
      false,
    ).intersection(findStandardFormatsForVersion(version2, false));
    if (commonFormats.isEmpty) {
      return null;
    }
    final digitRunRegex = RegExp('[0-9]+');
    String mostSpecific = commonFormats.first;
    var mostSpecificRuns = digitRunRegex.allMatches(mostSpecific).length;
    for (final format in commonFormats) {
      final runs = digitRunRegex.allMatches(format).length;
      if (runs > mostSpecificRuns ||
          (runs == mostSpecificRuns && format.length > mostSpecific.length)) {
        mostSpecific = format;
        mostSpecificRuns = runs;
      }
    }
    List<int> extractNumericRuns(String version) {
      final match = RegExp(mostSpecific).firstMatch(version);
      return digitRunRegex
          .allMatches(match!.group(0)!)
          .map((e) => int.parse(e.group(0)!))
          .toList();
    }

    final runs1 = extractNumericRuns(version1);
    final runs2 = extractNumericRuns(version2);
    for (var i = 0; i < runs1.length; i++) {
      if (runs1[i] != runs2[i]) {
        return runs1[i] > runs2[i] ? 1 : -1;
      }
    }
    return 0;
  }
}

/// Whether [app] should be presented as having an update available: its
/// installed version differs from its latest version and is not numerically
/// newer than it. Numeric comparison only applies when both versions share a
/// common non-strict standard format (see
/// [VersionService.compareVersionsNumerically]) and the "hide downgrades"
/// setting is enabled — otherwise a downgrade is still presented as an update.
bool isAppUpdateable(App app, SettingsProvider settingsProvider) {
  final installed = app.installedVersion;
  final latest = app.latestVersion;
  if (installed == null || installed == latest) {
    return false;
  }
  if (!settingsProvider.hideDowngrades) {
    return true;
  }
  final comparison = VersionService().compareVersionsNumerically(
    installed,
    latest,
  );
  return comparison == null || comparison <= 0;
}

// ========================================================================
// ApkFilterService — APK file detection, filtering, and arch-splitting.
// ========================================================================

class ApkFilterService {
  static const List<String> apkContainerExtensions = [
    '.apk',
    '.xapk',
    '.apkm',
    '.apks',
  ];

  static const List<String> archiveExtensions = ['.zip'];

  static const List<String> tarballExtensions = [
    '.tar.gz',
    '.tgz',
    '.tar.bz2',
    '.tar.xz',
  ];

  static bool isApkOrContainerFile(
    String name, {
    bool includeArchives = false,
    bool includeTarballs = false,
  }) {
    final lower = name.toLowerCase();
    bool endsWithAny(List<String> exts) => exts.any(lower.endsWith);
    return endsWithAny(apkContainerExtensions) ||
        (includeArchives && endsWithAny(archiveExtensions)) ||
        (includeTarballs && endsWithAny(tarballExtensions));
  }

  List<MapEntry<String, String>> getApkUrlsFromUrls(List<String> urls) =>
      urls.map((e) {
        final segments = e.split('/').where((el) => el.trim().isNotEmpty);
        final apkSegs = segments.where((s) => isApkOrContainerFile(s));
        return MapEntry(apkSegs.isNotEmpty ? apkSegs.last : segments.last, e);
      }).toList();

  List<MapEntry<String, String>> filterApks(
    List<MapEntry<String, String>> apkUrls,
    String? apkFilterRegEx,
    bool? invert,
  ) {
    if (apkFilterRegEx?.isNotEmpty == true) {
      final reg = RegExp(apkFilterRegEx!);
      apkUrls = apkUrls.where((element) {
        final hasMatch = reg.hasMatch(element.key);
        return invert == true ? !hasMatch : hasMatch;
      }).toList();
    }
    return apkUrls;
  }

  /// Non-canonical ABI names commonly used in APK filenames, mapped to the
  /// canonical device ABI strings they correspond to (see #3249).
  static const Map<String, List<String>> abiNameAliases = {
    'arm64-v8a': ['aarch64', 'arm64'],
    'armeabi-v7a': ['armv7', 'armeabi'],
    'x86_64': ['x64'],
  };

  Future<List<MapEntry<String, String>>> filterApksByArch(
    List<MapEntry<String, String>> apkUrls,
    List<String> abis, {
    bool preferSplits = true, // TODO: Implement preferSplits filtering logic
  }) async {
    if (apkUrls.length > 1) {
      for (var abi in abis) {
        final variants = [abi, ...?abiNameAliases[abi]];
        final abiRegex = RegExp(
          '.*(?:${variants.join('|')}).*',
          caseSensitive: false,
        );
        final urls2 = apkUrls
            .where((element) => abiRegex.hasMatch(element.key))
            .toList();
        if (urls2.isNotEmpty && urls2.length < apkUrls.length) {
          apkUrls = urls2;
          break;
        }
      }
    }
    return apkUrls;
  }
}
