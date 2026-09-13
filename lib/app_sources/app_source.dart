// AppSource — abstract base class for all app sources.

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;

import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/services/apk_filter_service.dart';
import 'package:obtainium/services/http_service.dart';
import 'package:obtainium/services/version_service.dart';
import 'package:obtainium/utils/signing_cert_utils.dart';
import 'package:obtainium/utils/string_utils.dart';
import 'package:obtainium/utils/url_utils.dart';

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

  RegExp? _hostMatchRegExp;

  /// Whether [host] matches this source's [hosts], honoring [allowSubDomains].
  /// The compiled pattern is cached because this runs for every app loaded and
  /// every URL resolved.
  bool matchesHost(String host) {
    return (_hostMatchRegExp ??= RegExp(
      '^${allowSubDomains ? '([^\\.]+\\.)*' : '(www\\.)?'}(${getSourceRegex(hosts)})\$',
    )).hasMatch(host);
  }

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
    final streamedResponseUrlWithResponseAndClient = await HttpService()
        .sourceRequestStreamResponse(
          method,
          requestHeaders,
          additionalSettingsPlusSourceConfig,
          followRedirects: followRedirects,
          postBody: postBody,
        );
    return await HttpService().httpClientResponseStreamToFinalResponse(
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
      GeneratedFormTextField(
        'allowedSigningCertHashes',
        label: tr('allowedSigningCertHashes'),
        hint: 'AA:BB:CC:…',
        required: false,
        max: 4,
        helpUrl: 'https://developer.android.com/tools/apksigner',
        additionalValidators: [
          (value) =>
              isValidCertHashList(value) ? null : tr('invalidSigningCertHash'),
        ],
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
    String standardUrl,
  ) async {
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

// ========================================================================
// MassAppUrlSource — abstract base for mass URL import sources.
// ========================================================================

abstract class MassAppUrlSource {
  String get name;
  List<String> get requiredArgs;
  Future<Map<String, List<String>>> getUrlsWithDescriptions(List<String> args);
}
