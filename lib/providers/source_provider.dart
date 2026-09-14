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
    if (explicitId != null && explicitId.trim().isNotEmpty) return explicitId;
    if ((!trackOnly || source.inferAppIdEvenWhenTrackOnly) &&
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
      releaseUrl: apk.releaseUrl,
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

  static const Map<String, List<String>> _certificatePinAssetNames = {
    'github.com': [
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
    ],
    'codeberg.org': [
      'assets/ca-certs/isrg-root-x1.crt',
      'assets/ca-certs/isrg-root-x2.crt',
      'assets/ca-certs/isrg-root-ye.crt',
      'assets/ca-certs/isrg-root-yr.crt',
    ],
    'gitlab.com': [
      'assets/ca-certs/sectigo-pub-serv-auth-r46.crt',
      'assets/ca-certs/sectigo-pub-serv-auth-e46.crt',
    ],
    'rustore.ru': [
      'assets/ca-certs/harica-tls-root-2021-rsa.crt',
      'assets/ca-certs/harica-tls-root-2021-ecc.crt',
      'assets/ca-certs/russian-mintsifry-root.crt',
    ],
  };

  static final Map<String, Future<List<Uint8List>>> _certificatePins =
      _certificatePinAssetNames.map(
        (host, assets) => MapEntry(host, _loadCertificateFromAsset(assets)),
      );

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

  /// Resolves TLS policy using the same exact-host-then-root-host lookup used
  /// by [_createCertPinning]. A null result means system trust only.
  static Map<String, dynamic>? tlsPolicyForUrl(
    String url, {
    required bool certificatePinning,
  }) {
    final host = Uri.parse(url).host;
    final rootHost = _extractRootHost(host);
    final policyHost = certificatePinning
        ? (_certificatePinAssetNames.containsKey(host)
              ? host
              : _certificatePinAssetNames.containsKey(rootHost)
              ? rootHost
              : null)
        : null;

    if (policyHost != null) {
      return {
        'certificates': _certificatePinAssetNames[policyHost],
        'useSystemRoots': false,
      };
    }

    // RuStore needs its additional CA even when certificate pinning is off.
    if (!certificatePinning &&
        (host == 'rustore.ru' || rootHost == 'rustore.ru')) {
      return {
        'certificates': ['assets/ca-certs/russian-mintsifry-root.crt'],
        'useSystemRoots': true,
      };
    }
    return null;
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
