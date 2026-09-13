// ========================================================================
// SourceProvider — resolves URLs to AppSource instances and builds Apps.
//
// App sources, models, and services live in their own libraries. This file
// re-exports them so existing `import source_provider.dart` call sites keep
// resolving the same names.
// ========================================================================

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:obtainium/app_sources/apk4free.dart';
import 'package:obtainium/app_sources/apkcombo.dart';
import 'package:obtainium/app_sources/apkmirror.dart';
import 'package:obtainium/app_sources/apkpure.dart';
import 'package:obtainium/app_sources/app_source.dart';
import 'package:obtainium/app_sources/aptoide.dart';
import 'package:obtainium/app_sources/codeberg.dart';
import 'package:obtainium/app_sources/coolapk.dart';
import 'package:obtainium/app_sources/direct_apk_link.dart';
import 'package:obtainium/app_sources/farsroid.dart';
import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/app_sources/fdroidrepo.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/app_sources/githubstars.dart';
import 'package:obtainium/app_sources/gitlab.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/app_sources/huaweiappgallery.dart';
import 'package:obtainium/app_sources/itchio.dart';
import 'package:obtainium/app_sources/izzyondroid.dart';
import 'package:obtainium/app_sources/jenkins.dart';
import 'package:obtainium/app_sources/liteapks.dart';
import 'package:obtainium/app_sources/neutroncode.dart';
import 'package:obtainium/app_sources/rockmods.dart';
import 'package:obtainium/app_sources/rustore.dart';
import 'package:obtainium/app_sources/samsunggalaxystore.dart';
import 'package:obtainium/app_sources/sourceforge.dart';
import 'package:obtainium/app_sources/sourcehut.dart';
import 'package:obtainium/app_sources/telegramapp.dart';
import 'package:obtainium/app_sources/tencent.dart';
import 'package:obtainium/app_sources/uptodown.dart';
import 'package:obtainium/app_sources/vivoappstore.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/services/apk_filter_service.dart';
import 'package:obtainium/services/version_service.dart';
import 'package:obtainium/utils/min_update_age.dart';
import 'package:obtainium/utils/url_utils.dart';

export 'package:obtainium/app_sources/app_source.dart';
export 'package:obtainium/models/app.dart';
export 'package:obtainium/models/typed_settings.dart';
export 'package:obtainium/services/apk_filter_service.dart';
export 'package:obtainium/services/http_service.dart';
export 'package:obtainium/services/version_service.dart';
export 'package:obtainium/utils/string_utils.dart' show getSourceRegex;
export 'package:obtainium/utils/url_utils.dart' show preStandardizeUrl;

const int kDefaultFetchConcurrency = 4;

// ========================================================================
// SourceProvider — singleton that manages available AppSource instances,
// URL-to-source resolution, and app construction from URLs.
// ========================================================================

class SourceProvider {
  static final SourceProvider _instance = SourceProvider._();
  factory SourceProvider() => _instance;
  SourceProvider._();

  // Factories for every source, in auto-detection order: sources with hosts
  // are matched by host, then hostless sources are tried in order. HTML is the
  // catch-all fallback and must stay last. Adding a source means adding one
  // entry here.
  static final List<AppSource Function()> _sourceFactories = [
    () => GitHub(),
    () => GitLab(),
    () => Codeberg(),
    () => FDroid(),
    () => FDroidRepo(),
    () => IzzyOnDroid(),
    () => SourceHut(),
    () => APKPure(),
    () => Aptoide(),
    () => Uptodown(),
    () => ItchIO(),
    () => HuaweiAppGallery(),
    () => Tencent(),
    () => VivoAppStore(),
    () => RuStore(),
    () => Farsroid(),
    () => SamsungGalaxyStore(),
    () => LiteAPKs(),
    () => Apk4Free(),
    () => CoolApk(),
    () => SourceForge(),
    () => Jenkins(),
    () => APKMirror(),
    () => APKCombo(),
    () => RockMods(),
    () => TelegramApp(),
    () => NeutronCode(),
    () => DirectAPKLink(),
    // HTML must stay last: hostless sources are tried in order and HTML is the
    // catch-all fallback.
    () => HTML(),
  ];

  /// Cached, read-only source list built lazily from [_sourceFactories].
  /// Because sources are immutable after construction, the cache is safe.
  static List<AppSource>? _cachedSources;
  List<AppSource> get sources =>
      _cachedSources ??= _sourceFactories.map((f) => f()).toList();

  /// Factory lookup by persisted source identifier.
  static Map<String, AppSource Function()>? _sourceFactoriesById;
  static Map<String, AppSource Function()> get _sourceFactoriesByIdCache =>
      _sourceFactoriesById ??= {
        for (final factory in _sourceFactories)
          factory().sourceIdentifier: factory,
      };

  /// Add mass URL source classes here so they are available via the service.
  List<MassAppUrlSource> massUrlSources = [GitHubStars()];

  AppSource getSource(String url, {String? overrideSource}) {
    url = preStandardizeUrl(url);
    if (overrideSource != null) {
      final factory = _sourceFactoriesByIdCache[overrideSource];
      if (factory == null) {
        throw UnsupportedURLError()..url = url;
      }
      // The override path mutates the chosen source's host config, so use a
      // throwaway instance rather than touching the shared cache.
      final res = factory();
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
      if (s.matchesHost(Uri.parse(url).host)) {
        source = s;
        break;
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

    // Adding an app must honor the minimum update age too. Sources that can
    // look back already return an older eligible release, so this only blocks
    // sources whose latest release is too young and has no older alternative.
    if (currentApp == null && !trackOnly) {
      final minAgeDays = await effectiveMinUpdateAgeDays(additionalSettings);
      if (isReleaseTooYoung(apk.releaseDate, minAgeDays)) {
        throw MinUpdateAgeError(apk.releaseDate!, minAgeDays)
          ..url = standardUrl;
      }
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
