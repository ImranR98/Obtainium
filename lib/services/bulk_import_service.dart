import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/providers/settings_provider.dart';

const _deviceAppsChannel = MethodChannel('dev.imranr.obtainium/device_apps');

typedef _ApkMirrorAvailability = ({bool exists, String? link, String? iconUrl});

@visibleForTesting
String? apkMirrorIconUrlFromAvailabilityItem(dynamic item) {
  if (item is! Map) return null;
  final dynamic app = item['app'];
  if (app is! Map) return null;
  final dynamic iconUrl = app['icon_url'];
  if (iconUrl is! String || iconUrl.trim().isEmpty) return null;
  return iconUrl.trim();
}

class InstalledAppInfo {
  final String packageName;
  final String name;
  final Uint8List? icon;
  final bool isSystemApp;
  // Path to the APK on the device — used to identify non-replaceable system apps.
  final String? sourceDir;
  // Pre-computed lowercase variants of [name] / [packageName] used by the
  // bulk-add search filter. Computing these once at construction turns each
  // keystroke from a 2N-string-lowering pass into a 2N-substring-check pass,
  // measurably reducing per-keystroke CPU on devices with 200+ apps.
  final String nameLower;
  final String packageNameLower;

  InstalledAppInfo({
    required this.packageName,
    required this.name,
    this.icon,
    required this.isSystemApp,
    this.sourceDir,
  }) : nameLower = name.toLowerCase(),
       packageNameLower = packageName.toLowerCase();

  /// True when this system app lives in a privileged or vendor partition that
  /// third-party stores never supply APKs for (priv-app, framework, vendor,
  /// odm, etc.). Apps with FLAG_UPDATED_SYSTEM_APP are always considered
  /// replaceable even if their sourceDir says otherwise.
  bool get isLikelyNonReplaceable {
    if (!isSystemApp) return false;
    final dir = sourceDir;
    if (dir == null) return false;
    return dir.contains('/priv-app/') ||
        dir.contains('/framework/') ||
        dir.startsWith('/vendor/') ||
        dir.startsWith('/odm/') ||
        dir.startsWith('/oem/');
  }
}

class SigningCertificateInfo {
  const SigningCertificateInfo({
    required this.signatures,
    required this.hasMultipleSigners,
  });

  final List<Uint8List> signatures;
  final bool hasMultipleSigners;
}

class BulkImportService {
  static const Map<String, String> _apkMirrorPreferredPackageUrls = {
    // APKMirror's app_exists endpoint can return Wear OS / Android Automotive
    // sibling listings for this shared package ID. Prefer the phone listing.
    'com.google.android.apps.youtube.music':
        'https://www.apkmirror.com/apk/google-inc/youtube-music/',
  };

  static Future<Map<String, String>> getApplicationLabels(
    List<String> packageNames,
  ) async {
    if (packageNames.isEmpty) {
      return const <String, String>{};
    }
    Map<String, String>? labelsByPackageName;
    try {
      labelsByPackageName = await _deviceAppsChannel
          .invokeMapMethod<String, String>('getApplicationLabels', {
            'packageNames': packageNames,
          });
    } on MissingPluginException {
      // Background update engines do not run MainActivity.configureFlutterEngine,
      // where this app-owned channel is registered. Labels are cosmetic, so let
      // callers fall back to ApplicationInfo/package names instead of failing the check.
      return const <String, String>{};
    }
    return Map<String, String>.from(
      labelsByPackageName ?? const <String, String>{},
    );
  }

  static Future<SigningCertificateInfo?> getSigningCertificates(
    String packageName,
  ) async {
    Map<String, dynamic>? certificateData;
    try {
      certificateData = await _deviceAppsChannel
          .invokeMapMethod<String, dynamic>('getSigningCertificates', {
            'packageName': packageName,
          });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
    if (certificateData == null) return null;

    final List<dynamic> rawSignatures =
        certificateData['signatures'] as List<dynamic>? ?? const <dynamic>[];
    final signatures = rawSignatures
        .map((rawSignature) {
          if (rawSignature is Uint8List) return rawSignature;
          return Uint8List.fromList(
            List<int>.from(rawSignature as List<dynamic>),
          );
        })
        .toList(growable: false);
    return SigningCertificateInfo(
      signatures: signatures,
      hasMultipleSigners:
          certificateData['hasMultipleSigners'] as bool? ?? false,
    );
  }

  static Future<bool?> uses24HourFormat() async {
    try {
      return await _deviceAppsChannel.invokeMethod<bool>('uses24HourFormat');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Returns all installed apps, filtered by system/user.
  ///
  /// Backed by the app's own `getInstalledAppsLight` platform method, which
  /// returns only the four primitive fields a row needs (package name, label,
  /// system flag, source dir) in one native pass. This replaces the previous
  /// `AndroidPackageManager.getInstalledPackages` path, which marshalled a full
  /// PackageInfo + ApplicationInfo per app across the channel and decoded it on
  /// the Flutter UI isolate — hundreds of objects, the cause of the bulk-scan
  /// slide-in stutter. The enumeration + label lookup now happen natively on a
  /// background thread and the tiny reply decodes in negligible time.
  static Future<List<InstalledAppInfo>> getInstalledApps({
    bool includeSystem = false,
    bool includeUser = true,
  }) async {
    List<Object?>? raw;
    try {
      raw = await _deviceAppsChannel.invokeListMethod<Object?>(
        'getInstalledAppsLight',
      );
    } on MissingPluginException {
      // Background update engines don't register this app-owned channel.
      return const <InstalledAppInfo>[];
    }

    final result = <InstalledAppInfo>[];
    for (final entry in raw ?? const <Object?>[]) {
      if (entry is! Map) continue;
      final pkgName = entry['packageName'] as String? ?? '';
      if (pkgName.isEmpty || pkgName == obtainiumId) continue;
      final isSystem = entry['isSystem'] as bool? ?? false;
      if (isSystem && !includeSystem) continue;
      if (!isSystem && !includeUser) continue;
      final label = entry['label'] as String?;
      result.add(
        InstalledAppInfo(
          packageName: pkgName,
          name: (label != null && label.isNotEmpty) ? label : pkgName,
          icon: null,
          isSystemApp: isSystem,
          sourceDir: entry['sourceDir'] as String?,
        ),
      );
    }

    // Sorting a few hundred pre-lowercased strings in place is sub-millisecond;
    // the compact payload no longer justifies an off-isolate round-trip (which
    // would copy the whole list twice across the isolate boundary).
    result.sort((a, b) => a.nameLower.compareTo(b.nameLower));
    return result;
  }

  /// Gets an app icon for a given package name, for lazy list loading.
  ///
  /// Rendered natively (adaptive icons composited to a size-capped PNG) via the
  /// app's `getAppIcon` platform method, so no ApplicationInfo handle needs to
  /// survive from [getInstalledApps] on the Dart side.
  static Future<Uint8List?> getAppIcon(String packageName) async {
    try {
      return await _deviceAppsChannel.invokeMethod<Uint8List>('getAppIcon', {
        'packageName': packageName,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Returns a list of candidate package IDs, including the original and any
  /// flavor derivatives (e.g. stripping suffixes like .gh, .github, .fdroid).
  static List<String> getPackageIdCandidates(String packageId) {
    final List<String> candidates = [packageId];
    const List<String> suffixes = [
      '.gh',
      '.github',
      '.fdroid',
      '.foss',
      '.dev',
      '.debug',
      '.play',
      '.playstore',
      '.gp',
      '.beta',
      '.lite',
      '.pro',
      '.free',
    ];
    for (final String suffix in suffixes) {
      if (packageId.endsWith(suffix)) {
        final String base = packageId.substring(
          0,
          packageId.length - suffix.length,
        );
        if (base.contains('.')) {
          candidates.add(base);
        }
        break;
      }
    }
    return candidates;
  }

  /// Checks APKMirror for a list of package names.
  /// Returns a map of packageName -> apkmirror URL (null if not found).
  /// Uses APKMirror's REST API with batch requests of 100 apps.
  /// When supplied, [resolvedIconUrls] is populated from the same response;
  /// resolving these URLs does not issue another metadata request.
  static Future<Map<String, String?>> checkApkMirror(
    List<String> packageNames, {
    void Function(int done, int total)? onProgress,
    Map<String, String?>? alreadyKnown,
    Map<String, String>? resolvedIconUrls,
    bool Function()? shouldAbort,
  }) async {
    final result = <String, String?>{};
    if (alreadyKnown != null) {
      for (final String packageName in packageNames) {
        if (alreadyKnown.containsKey(packageName)) {
          result[packageName] =
              _apkMirrorPreferredPackageUrls[packageName] ??
              alreadyKnown[packageName];
        }
      }
    }
    void reportProgress() {
      int resolved = 0;
      for (final String packageName in packageNames) {
        if (result.containsKey(packageName)) resolved++;
      }
      onProgress?.call(resolved, packageNames.length);
    }

    reportProgress();
    final List<String> toQuery = packageNames
        .where((String packageName) => !result.containsKey(packageName))
        .toList();
    if (toQuery.isEmpty) {
      return result;
    }

    final List<String> queryCandidates = [];
    final Map<String, List<String>> candidateToOriginal = {};
    final Map<String, Set<String>> pendingCandidates = {};

    for (final String pkg in toQuery) {
      final candidates = getPackageIdCandidates(pkg);
      pendingCandidates[pkg] = candidates.toSet();
      for (final String candidate in candidates) {
        if (!queryCandidates.contains(candidate)) {
          queryCandidates.add(candidate);
        }
        candidateToOriginal.putIfAbsent(candidate, () => []).add(pkg);
      }
    }

    const batchSize = 100;
    // Authorization header uses APKUpdater credentials to access the API endpoint
    const auth = 'Basic YXBpLWFwa3VwZGF0ZXI6cm01cmNmcnVVakt5MDRzTXB5TVBKWFc4';

    for (int i = 0; i < queryCandidates.length; i += batchSize) {
      if (shouldAbort?.call() == true) {
        return result;
      }
      final batch = queryCandidates.sublist(
        i,
        min(i + batchSize, queryCandidates.length),
      );
      try {
        final response = await http
            .post(
              Uri.parse(
                'https://www.apkmirror.com/wp-json/apkm/v1/app_exists/',
              ),
              headers: {
                'Authorization': auth,
                'Content-Type': 'application/json',
                'User-Agent': 'APKUpdater-v3.5.9',
              },
              body: jsonEncode({
                'pnames': batch,
                'exclude': ['alpha', 'beta'],
              }),
            )
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final dataList = data['data'] as List? ?? [];

          final Map<String, _ApkMirrorAvailability> batchResults = {};
          for (final item in dataList) {
            final pname = item['pname'] as String?;
            if (pname != null) {
              batchResults[pname] = (
                exists: item['exists'] as bool? ?? false,
                link: item['app']?['link'] as String?,
                iconUrl: apkMirrorIconUrlFromAvailabilityItem(item),
              );
            }
          }

          for (final String candidate in batch) {
            final res = batchResults[candidate];
            final exists = res?.exists ?? false;
            final appLink = res?.link;

            final originals = candidateToOriginal[candidate] ?? [];
            for (final original in originals) {
              if (exists && appLink != null) {
                if (result[original] == null || original == candidate) {
                  result[original] =
                      _apkMirrorPreferredPackageUrls[candidate] ??
                      'https://www.apkmirror.com$appLink';
                  final String? iconUrl = res?.iconUrl;
                  if (iconUrl != null) {
                    resolvedIconUrls?[original] = iconUrl;
                  }
                }
              }
              pendingCandidates[original]?.remove(candidate);
              if (pendingCandidates[original]?.isEmpty == true) {
                result.putIfAbsent(original, () => null);
              }
            }
          }
        }
      } catch (_) {
        // Network error or timeout — don't cache; retry next scan.
      }
      reportProgress();
      if (shouldAbort?.call() == true) {
        return result;
      }
      // Small delay between batches to respect rate limits
      if (i + batchSize < queryCandidates.length) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    return result;
  }

  /// Checks APKPure for a list of package names using the same per-app endpoint
  /// that the APKPure app source uses (tapi.pureapk.com/v3/get_app_his_version).
  /// Returns a map of packageName -> apkpure URL (null if not found).
  static Future<Map<String, String?>> checkApkPure(
    List<String> packageNames, {
    void Function(int done, int total)? onProgress,
    Map<String, String?>? alreadyKnown,
    bool Function()? shouldAbort,
  }) async {
    final result = <String, String?>{};
    if (alreadyKnown != null) {
      for (final String packageName in packageNames) {
        if (alreadyKnown.containsKey(packageName)) {
          result[packageName] = alreadyKnown[packageName];
        }
      }
    }
    void reportProgress() {
      int resolved = 0;
      for (final String packageName in packageNames) {
        if (result.containsKey(packageName)) resolved++;
      }
      onProgress?.call(resolved, packageNames.length);
    }

    reportProgress();
    final List<String> toQuery = packageNames
        .where((String packageName) => !result.containsKey(packageName))
        .toList();
    if (toQuery.isEmpty) {
      return result;
    }

    // Same endpoint the APKPure app source uses — known to work.
    // Sub-batches so [shouldAbort] is checked between groups (not only after
    // an entire large [Future.wait] completes).
    const int concurrency = 10;
    const int subBatchSize = 4;
    const headers = {
      'Ual-Access-Businessid': 'projecta',
      'Ual-Access-ProjectA': '{"device_info":{"os_ver":"30"}}',
      'User-Agent': 'APKPure/3.19.39 (Aegon)',
    };

    for (int i = 0; i < toQuery.length; i += concurrency) {
      if (shouldAbort?.call() == true) return result;
      final chunk = toQuery.sublist(i, min(i + concurrency, toQuery.length));
      for (
        int subStart = 0;
        subStart < chunk.length;
        subStart += subBatchSize
      ) {
        if (shouldAbort?.call() == true) return result;
        final subChunk = chunk.sublist(
          subStart,
          min(subStart + subBatchSize, chunk.length),
        );
        await Future.wait(
          subChunk.map((pkg) async {
            final candidates = getPackageIdCandidates(pkg);
            for (final candidate in candidates) {
              try {
                final response = await http
                    .get(
                      Uri.parse(
                        'https://tapi.pureapk.com/v3/get_app_his_version'
                        '?package_name=$candidate&hl=en',
                      ),
                      headers: headers,
                    )
                    .timeout(const Duration(seconds: 15));

                if (response.statusCode == 200) {
                  final body = jsonDecode(response.body);
                  final List<dynamic> versions = body is Map
                      ? (body['version_list'] as List? ?? [])
                      : [];
                  if (versions.isNotEmpty) {
                    final first = versions.first;
                    final appName = first is Map
                        ? (first['title'] as String? ?? '')
                        : '';
                    result[pkg] = appName.isNotEmpty
                        ? 'https://apkpure.net/${_slugify(appName)}/$candidate'
                        : 'https://apkpure.net/$candidate';
                    return;
                  }
                }
              } catch (e) {
                debugPrint('APKPure check failed for $candidate: $e');
                if (candidate == pkg) {
                  rethrow;
                }
              }
            }
            result[pkg] = null;
            reportProgress();
          }),
        );
        if (shouldAbort?.call() == true) return result;
      }
    }
    return result;
  }

  /// F-Droid-style APIs have no batch endpoint; we fire one GET per package.
  /// The global [http.get] client caps connections per host (~6), so bulk scans
  /// share this [IOClient] with a raised [HttpClient.maxConnectionsPerHost] and
  /// one [Future.wait] per chunk of [_bulkPackageApiChunkSize] packages.
  static const int _bulkPackageApiChunkSize = 20;
  static const int _bulkPackageApiMaxConnectionsPerHost =
      _bulkPackageApiChunkSize;

  /// Ensures [recordStoreCoverage] sees every package (null means not in store).
  static void _putMissingPackageKeysAsNull(
    Map<String, String?> result,
    Iterable<String> packageNames,
  ) {
    for (final String packageName in packageNames) {
      result.putIfAbsent(packageName, () => null);
    }
  }

  static Future<void> _runBulkPerPackageApiLookups({
    required List<String> toQuery,
    required List<String> allPackageNames,
    required Map<String, String?> result,
    void Function(int done, int total)? onProgress,
    bool Function()? shouldAbort,
    required Future<void> Function(http.Client client, String packageName)
    runLookup,
  }) async {
    int finishedAttempts = result.length;
    void reportAttemptProgress() {
      onProgress?.call(finishedAttempts, allPackageNames.length);
    }

    reportAttemptProgress();

    final HttpClient rawHttpClient = HttpClient()
      ..maxConnectionsPerHost = _bulkPackageApiMaxConnectionsPerHost;
    final http.Client client = IOClient(rawHttpClient);
    try {
      for (
        int chunkStart = 0;
        chunkStart < toQuery.length;
        chunkStart += _bulkPackageApiChunkSize
      ) {
        if (shouldAbort?.call() == true) {
          return;
        }
        final List<String> chunk = toQuery.sublist(
          chunkStart,
          min(chunkStart + _bulkPackageApiChunkSize, toQuery.length),
        );
        await Future.wait(
          chunk.map((String pkg) async {
            try {
              await runLookup(client, pkg);
            } catch (_) {
              //
            } finally {
              finishedAttempts++;
              reportAttemptProgress();
            }
          }),
        );
        if (shouldAbort?.call() == true) {
          return;
        }
      }
    } finally {
      _putMissingPackageKeysAsNull(result, toQuery);
      client.close();
    }
  }

  /// Checks F-Droid for a list of package names using their REST API.
  /// Returns a map of packageName -> fdroid URL (null if not found).
  static Future<Map<String, String?>> checkFDroid(
    List<String> packageNames, {
    void Function(int done, int total)? onProgress,
    Map<String, String?>? alreadyKnown,
    bool Function()? shouldAbort,
  }) async {
    final result = <String, String?>{};
    if (alreadyKnown != null) {
      for (final String packageName in packageNames) {
        if (alreadyKnown.containsKey(packageName)) {
          result[packageName] = alreadyKnown[packageName];
        }
      }
    }

    final List<String> toQuery = packageNames
        .where((String packageName) => !result.containsKey(packageName))
        .toList();
    if (toQuery.isEmpty) {
      onProgress?.call(result.length, packageNames.length);
      _putMissingPackageKeysAsNull(result, packageNames);
      return result;
    }

    await _runBulkPerPackageApiLookups(
      toQuery: toQuery,
      allPackageNames: packageNames,
      result: result,
      onProgress: onProgress,
      shouldAbort: shouldAbort,
      runLookup: (http.Client client, String pkg) async {
        final candidates = getPackageIdCandidates(pkg);
        for (final candidate in candidates) {
          try {
            final http.Response response = await client
                .get(
                  Uri.parse('https://f-droid.org/api/v1/packages/$candidate'),
                  headers: {'User-Agent': 'ObtainX/1.4.0'},
                )
                .timeout(const Duration(seconds: 10));
            if (response.statusCode == 200) {
              result[pkg] = 'https://f-droid.org/packages/$candidate/';
              return;
            }
          } catch (_) {
            if (candidate == pkg) {
              rethrow;
            }
          }
        }
        result[pkg] = null;
      },
    );
    _putMissingPackageKeysAsNull(result, packageNames);
    return result;
  }

  static const String _izzyOnDroidRepoIndexUrl =
      'https://apt.izzysoft.de/fdroid/repo/index.xml';
  static const String _izzyOnDroidRepoApkUrlPrefix =
      'https://apt.izzysoft.de/fdroid/repo/';

  /// Picks the suggested APK filename for an `<application>` from [index.xml].
  static String? _izzyApkStoreUrlFromIndexApplication(html_dom.Element app) {
    final List<html_dom.Element> packageElements = app.getElementsByTagName(
      'package',
    );
    if (packageElements.isEmpty) {
      return null;
    }
    final String? marketVerCodeText = app
        .querySelector('marketvercode')
        ?.innerHtml
        .trim();
    final int? marketVerCode = int.tryParse(marketVerCodeText ?? '');
    html_dom.Element? selectedPackage;
    if (marketVerCode != null) {
      for (final html_dom.Element packageElement in packageElements) {
        final String? versionCodeText = packageElement
            .querySelector('versioncode')
            ?.innerHtml
            .trim();
        final int? versionCode = int.tryParse(versionCodeText ?? '');
        final String? apkName = packageElement
            .querySelector('apkname')
            ?.innerHtml
            .trim();
        if (versionCode == marketVerCode &&
            apkName != null &&
            apkName.isNotEmpty) {
          selectedPackage = packageElement;
          break;
        }
      }
    }
    if (selectedPackage == null) {
      int bestVersionCode = -1;
      for (final html_dom.Element packageElement in packageElements) {
        final String? versionCodeText = packageElement
            .querySelector('versioncode')
            ?.innerHtml
            .trim();
        final int versionCode = int.tryParse(versionCodeText ?? '') ?? -1;
        final String? apkName = packageElement
            .querySelector('apkname')
            ?.innerHtml
            .trim();
        if (apkName != null &&
            apkName.isNotEmpty &&
            versionCode > bestVersionCode) {
          bestVersionCode = versionCode;
          selectedPackage = packageElement;
        }
      }
    }
    final String? apkName = selectedPackage
        ?.querySelector('apkname')
        ?.innerHtml
        .trim();
    if (apkName == null || !apkName.toLowerCase().endsWith('.apk')) {
      return null;
    }
    return '$_izzyOnDroidRepoApkUrlPrefix$apkName';
  }

  /// Isolate entry for [compute]; must stay in sync with [_izzyApkStoreUrlFromIndexApplication].
  static Map<String, String> _izzyIndexBodyToPackageStoreUrls(
    String indexBody,
  ) {
    final html_dom.Document document = parse(indexBody);
    final Map<String, String> packageIdToStoreUrl = <String, String>{};
    for (final html_dom.Element applicationElement in document.querySelectorAll(
      'application',
    )) {
      final String? applicationId = applicationElement.attributes['id'];
      if (applicationId == null || applicationId.isEmpty) {
        continue;
      }
      final String? storeUrl = _izzyApkStoreUrlFromIndexApplication(
        applicationElement,
      );
      if (storeUrl != null) {
        packageIdToStoreUrl[applicationId] = storeUrl;
      }
    }
    return packageIdToStoreUrl;
  }

  /// One [index.xml] fetch and in-memory lookups (fast). Parsing runs in an
  /// isolate via [compute]. Progress updates are throttled so the UI stays
  /// responsive. Falls back to the per-package API if the index path fails.
  static Future<Map<String, String?>> checkIzzyOnDroid(
    List<String> packageNames, {
    void Function(int done, int total)? onProgress,
    Map<String, String?>? alreadyKnown,
    bool Function()? shouldAbort,
  }) async {
    final result = <String, String?>{};
    if (alreadyKnown != null) {
      for (final String packageName in packageNames) {
        if (alreadyKnown.containsKey(packageName)) {
          result[packageName] = alreadyKnown[packageName];
        }
      }
    }

    final List<String> toQuery = packageNames
        .where((String packageName) => !result.containsKey(packageName))
        .toList();
    if (toQuery.isEmpty) {
      onProgress?.call(result.length, packageNames.length);
      _putMissingPackageKeysAsNull(result, packageNames);
      return result;
    }

    onProgress?.call(result.length, packageNames.length);

    if (shouldAbort?.call() == true) {
      _putMissingPackageKeysAsNull(result, packageNames);
      return result;
    }

    const Map<String, String> requestHeaders = <String, String>{
      'User-Agent': 'F-Droid/1.0 (+https://f-droid.org)',
    };
    final Uri indexUri = Uri.parse(_izzyOnDroidRepoIndexUrl);

    final HttpClient indexRawClient = HttpClient();
    final http.Client indexClient = IOClient(indexRawClient);

    try {
      http.Response indexResponse = await indexClient
          .get(indexUri, headers: requestHeaders)
          .timeout(const Duration(seconds: 120));
      if (indexResponse.statusCode == 429) {
        await Future<void>.delayed(const Duration(seconds: 1));
        indexResponse = await indexClient
            .get(indexUri, headers: requestHeaders)
            .timeout(const Duration(seconds: 120));
      }
      if (indexResponse.statusCode != 200) {
        throw StateError('Izzy index HTTP ${indexResponse.statusCode}');
      }
      onProgress?.call(result.length, packageNames.length);

      final Map<String, String> packageIdToStoreUrl = await compute(
        _izzyIndexBodyToPackageStoreUrls,
        indexResponse.body,
      );

      onProgress?.call(result.length, packageNames.length);

      final int lookupTotal = toQuery.length;
      int lookupDone = 0;
      const int progressEvery = 48;
      for (final String packageName in toQuery) {
        if (shouldAbort?.call() == true) {
          return result;
        }
        final candidates = getPackageIdCandidates(packageName);
        String? foundUrl;
        for (final candidate in candidates) {
          if (packageIdToStoreUrl.containsKey(candidate)) {
            foundUrl = packageIdToStoreUrl[candidate];
            break;
          }
        }
        result[packageName] = foundUrl;
        lookupDone++;
        if (lookupDone == 1 ||
            lookupDone == lookupTotal ||
            lookupDone % progressEvery == 0) {
          onProgress?.call(result.length, packageNames.length);
        }
      }
      return result;
    } catch (error, stackTrace) {
      debugPrint(
        'IzzyOnDroid index bulk check failed, falling back to API per package: $error\n$stackTrace',
      );
      await _runBulkPerPackageApiLookups(
        toQuery: toQuery,
        allPackageNames: packageNames,
        result: result,
        onProgress: onProgress,
        shouldAbort: shouldAbort,
        runLookup: (http.Client client, String pkg) async {
          final candidates = getPackageIdCandidates(pkg);
          for (final candidate in candidates) {
            try {
              final Uri uri = Uri.parse(
                'https://apt.izzysoft.de/fdroid/api/v1/packages/$candidate',
              );
              http.Response response = await client
                  .get(uri, headers: requestHeaders)
                  .timeout(const Duration(seconds: 15));
              if (response.statusCode == 429) {
                await Future<void>.delayed(const Duration(seconds: 1));
                response = await client
                    .get(uri, headers: requestHeaders)
                    .timeout(const Duration(seconds: 15));
              }
              if (response.statusCode == 200) {
                final dynamic decoded = jsonDecode(response.body);
                String? versionCodeStr = decoded['suggestedVersionCode']
                    ?.toString();
                if (versionCodeStr == null || versionCodeStr.isEmpty) {
                  final List<dynamic>? packages =
                      decoded['packages'] as List<dynamic>?;
                  if (packages != null && packages.isNotEmpty) {
                    final first = packages.first;
                    if (first is Map) {
                      versionCodeStr = first['versionCode']?.toString();
                    }
                  }
                }
                if (versionCodeStr != null && versionCodeStr.isNotEmpty) {
                  result[pkg] =
                      'https://apt.izzysoft.de/fdroid/repo/${candidate}_$versionCodeStr.apk';
                  return;
                }
              }
            } catch (_) {
              if (candidate == pkg) {
                rethrow;
              }
            }
          }
          result[pkg] = null;
        },
      );
      return result;
    } finally {
      _putMissingPackageKeysAsNull(result, packageNames);
      indexClient.close();
    }
  }

  /// GitHub code search by package id. Results are best-effort: many repos match
  /// generic strings, and the API is rate-limited without a PAT (set under GitHub
  /// source settings). Uses the same search approach as common tooling: quoted
  /// package id in file contents, then prefers AndroidManifest / Gradle paths.
  static Future<Map<String, String?>> checkGitHub(
    List<String> packageNames, {
    void Function(int done, int total)? onProgress,
    Map<String, String?>? alreadyKnown,
    bool Function()? shouldAbort,
    void Function(bool hadToken)? onRateLimit,
  }) async {
    final Map<String, String?> result = <String, String?>{};
    if (alreadyKnown != null) {
      for (final String packageName in packageNames) {
        if (alreadyKnown.containsKey(packageName)) {
          result[packageName] = alreadyKnown[packageName];
        }
      }
    }
    void reportProgress() {
      int resolved = 0;
      for (final String packageName in packageNames) {
        if (result.containsKey(packageName)) resolved++;
      }
      onProgress?.call(resolved, packageNames.length);
    }

    reportProgress();
    final List<String> toQuery = packageNames
        .where((String packageName) => !result.containsKey(packageName))
        .toList();
    if (toQuery.isEmpty) {
      return result;
    }

    final GitHub githubSource = GitHub();
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'ObtainX-BulkImport',
    };
    final Map<String, String>? authHeaders = await githubSource
        .getRequestHeaders(
          <String, dynamic>{},
          'https://api.github.com/search/code',
        );
    if (authHeaders != null) {
      headers.addAll(authHeaders);
    }
    final bool hasAuthToken =
        headers.containsKey('Authorization') ||
        headers.containsKey('authorization');

    // GitHub's search API has a low primary limit and aggressive secondary/
    // burst limits (code search especially). Pace requests well apart so we
    // don't trip the limit: authenticated search is ~30/min (→ ~2s spacing),
    // unauthenticated ~10/min (→ ~6s). The old 120ms/850ms pacing fired a burst
    // that tripped the secondary limit after a handful of apps.
    final Duration baseDelay = hasAuthToken
        ? const Duration(milliseconds: 2000)
        : const Duration(milliseconds: 6000);
    // Cap how long a single throttle wait may be before we give up, and how
    // many consecutive throttles to ride out per package.
    const Duration maxBackoff = Duration(seconds: 90);
    const int maxRateLimitRetries = 5;

    for (final String pkg in toQuery) {
      if (shouldAbort?.call() == true) {
        return result;
      }
      bool aborted = false;
      Duration pacing = baseDelay;
      try {
        final String searchPkg = _cleanPackageNameForSearch(pkg);
        // Quoted id reduces unrelated matches; "in:file" scopes to file contents.
        final Uri uri = Uri(
          scheme: 'https',
          host: 'api.github.com',
          path: '/search/code',
          queryParameters: <String, String>{
            'q': '"$searchPkg" in:file',
            'per_page': '15',
          },
        );
        http.Response response = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 25));
        // On a throttle (403/429), honour Retry-After / X-RateLimit-Reset and
        // retry the SAME package instead of aborting the scan on the first hit.
        int rateLimitRetries = 0;
        while (response.statusCode == 403 || response.statusCode == 429) {
          final Duration wait = _githubRateLimitWait(response);
          if (rateLimitRetries >= maxRateLimitRetries || wait > maxBackoff) {
            debugPrint('GitHub search rate limit exceeded; stopping scan');
            onRateLimit?.call(hasAuthToken);
            aborted = true;
            break;
          }
          rateLimitRetries++;
          debugPrint(
            'GitHub search rate-limited for $pkg; waiting '
            '${wait.inSeconds}s (retry $rateLimitRetries)',
          );
          await Future<void>.delayed(wait + const Duration(milliseconds: 500));
          if (shouldAbort?.call() == true) {
            return result;
          }
          response = await http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 25));
        }
        if (aborted) break;
        if (response.statusCode == 200) {
          final Object? decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            final List<dynamic> items =
                decoded['items'] as List<dynamic>? ?? <dynamic>[];

            final Map<String, int> repoScores = <String, int>{};
            for (final dynamic raw in items) {
              if (raw is! Map<String, dynamic>) continue;
              final Object? repo = raw['repository'];
              if (repo is! Map<String, dynamic>) continue;
              final String? repoName = repo['name'] as String?;
              final String? htmlUrl = repo['html_url'] as String?;
              if (htmlUrl == null ||
                  !htmlUrl.contains('github.com') ||
                  repoName == null) {
                continue;
              }
              repoScores.putIfAbsent(htmlUrl, () {
                final String lowerRepo = repoName.toLowerCase();
                final List<String> pkgSegments = searchPkg.toLowerCase().split(
                  '.',
                );
                final Set<String> ignoreSegments = {
                  'com',
                  'org',
                  'net',
                  'dev',
                  'github',
                  'android',
                  'app',
                  'apps',
                  'application',
                };
                int score = 0;
                for (final String segment in pkgSegments) {
                  if (ignoreSegments.contains(segment)) continue;
                  if (lowerRepo == segment) {
                    score += 100;
                  } else if (lowerRepo.contains(segment)) {
                    score += 50;
                  } else if (segment.contains(lowerRepo)) {
                    score += 30;
                  }
                }
                return score;
              });
            }

            int maxScore = 0;
            for (final int score in repoScores.values) {
              if (score > maxScore) {
                maxScore = score;
              }
            }

            String? chosenUrl;
            for (final dynamic raw in items) {
              if (raw is! Map<String, dynamic>) continue;
              final String path = (raw['path'] as String? ?? '').toLowerCase();
              final Object? repo = raw['repository'];
              if (repo is! Map<String, dynamic>) continue;
              final String? htmlUrl = repo['html_url'] as String?;
              if (htmlUrl == null || !htmlUrl.contains('github.com')) continue;

              final bool isDefinitionFile =
                  path.contains('androidmanifest') ||
                  path.endsWith('build.gradle') ||
                  path.endsWith('build.gradle.kts');

              // If the repository name similarity score is 0, we only accept matches
              // in definition files to avoid false positives from sibling/reference files.
              final int score = repoScores[htmlUrl] ?? 0;
              if (score == 0 && !isDefinitionFile) {
                continue;
              }

              if (maxScore > 0 && score < maxScore) {
                continue;
              }

              if (isDefinitionFile) {
                chosenUrl = htmlUrl;
                break;
              }
              chosenUrl ??= htmlUrl;
            }
            result[pkg] = chosenUrl;
          } else {
            result[pkg] = null;
          }
          // If the search budget is nearly spent, wait for the window to reset
          // before the next request rather than plowing into the limit.
          pacing = _githubPacingDelay(response, baseDelay);
        } else if (response.statusCode == 401) {
          // Auth failure — the token is missing or invalid, NOT a rate limit.
          debugPrint('GitHub search auth failed for $pkg (401)');
          onRateLimit?.call(hasAuthToken);
          break;
        } else {
          debugPrint(
            'GitHub search failed for $pkg: status ${response.statusCode}',
          );
          // Non-rate-limit failure — leave uncached so it retries next scan.
        }
      } catch (e, s) {
        debugPrint('GitHub search exception for $pkg: $e\n$s');
        // Network error or timeout — don't cache; retry next scan.
      }
      reportProgress();
      await Future<void>.delayed(pacing);
    }
    return result;
  }

  /// How long to wait after a 403/429 from GitHub's search API, derived from
  /// the `Retry-After` (secondary limit) or `X-RateLimit-Reset` (primary limit)
  /// headers, falling back to a fixed cooldown when neither is present.
  static Duration _githubRateLimitWait(http.Response response) {
    final int? retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
    if (retryAfter != null && retryAfter > 0) {
      return Duration(seconds: retryAfter);
    }
    final int? reset = int.tryParse(
      response.headers['x-ratelimit-reset'] ?? '',
    );
    if (reset != null) {
      final DateTime resetAt = DateTime.fromMillisecondsSinceEpoch(
        reset * 1000,
      );
      final Duration remaining = resetAt.difference(DateTime.now());
      if (remaining > Duration.zero) {
        return remaining;
      }
    }
    return const Duration(seconds: 30);
  }

  /// Pacing after a successful search: normally [baseDelay], but if the search
  /// budget is nearly spent (`X-RateLimit-Remaining` ≤ 1), wait until the window
  /// resets so the next request doesn't hit the primary limit.
  static Duration _githubPacingDelay(
    http.Response response,
    Duration baseDelay,
  ) {
    final int? remaining = int.tryParse(
      response.headers['x-ratelimit-remaining'] ?? '',
    );
    if (remaining != null && remaining <= 1) {
      final int? reset = int.tryParse(
        response.headers['x-ratelimit-reset'] ?? '',
      );
      if (reset != null) {
        final DateTime resetAt = DateTime.fromMillisecondsSinceEpoch(
          reset * 1000,
        );
        final Duration untilReset = resetAt.difference(DateTime.now());
        if (untilReset > Duration.zero) {
          return untilReset + const Duration(milliseconds: 500);
        }
      }
    }
    return baseDelay;
  }

  static String _slugify(String label) {
    return label
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'[\s_]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-');
  }

  static String _cleanPackageNameForSearch(String pkg) {
    final Set<String> commonSuffixes = {
      'gh',
      'dev',
      'debug',
      'release',
      'obt',
      'obtainium',
      'fdroid',
      'play',
      'normal',
      'foss',
      'lite',
      'free',
    };
    final List<String> parts = pkg.split('.');
    if (parts.length > 3) {
      final String lastPart = parts.last.toLowerCase();
      if (commonSuffixes.contains(lastPart)) {
        return parts.sublist(0, parts.length - 1).join('.');
      }
    }
    return pkg;
  }
}
