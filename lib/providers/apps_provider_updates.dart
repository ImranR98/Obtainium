import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/folders/app_folder.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

// ── Bounded update-check parallelism (device-tuned) ─────────────────────────
// Start fast on capable devices, but keep a bounded worker pool so a large app
// list does not fan out unbounded HTTP + parse work.
// [AppsProviderUpdates._maxParallelUpdateChecksForDevice] lowers this on low-end
// devices using Android's low-RAM flag and total physical RAM.
const int _defaultParallelUpdateChecks = 8;
const int _modestDeviceParallelUpdateChecks = 4;
const int _lowEndDeviceParallelUpdateChecks = 2;
const int _lowEndRamThresholdMb = 3072;
const int _modestRamThresholdMb = 6144;

// ── Version-reasoning helpers (update detection) ────────────────────────────
// Pure, read-only functions that decide whether an installed app is behind its
// source, ahead of it, or in an ambiguous ordering the user must resolve.

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39; // '0'..'9'

final RegExp _digitsOnlySegmentPattern = RegExp(r'^\d+$');

DateTime? _dateFromReleaseDateVersionString(String version) {
  final String trimmedVersion = version.trim();
  if (trimmedVersion.isEmpty) {
    return null;
  }
  if (RegExp(r'^\d{15,17}$').hasMatch(trimmedVersion)) {
    try {
      return DateTime.fromMicrosecondsSinceEpoch(int.parse(trimmedVersion));
    } catch (_) {
      return null;
    }
  }
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}(?:[T ].*)?$').hasMatch(trimmedVersion)) {
    return null;
  }
  return DateTime.tryParse(trimmedVersion);
}

int? compareReleaseDateVersionStrings(String installed, String latest) {
  final DateTime? installedDate = _dateFromReleaseDateVersionString(installed);
  final DateTime? latestDate = _dateFromReleaseDateVersionString(latest);
  if (installedDate == null || latestDate == null) {
    return null;
  }
  return installedDate.toUtc().compareTo(latestDate.toUtc()).sign;
}

/// True when [needle] appears in [longer] as a contiguous substring with
/// boundaries so we do not treat [2.0] as inside [12.0] or [.0] as inside [8.0].
bool _boundedVersionSubstringInHaystack(
  String longer,
  String needle,
  int startIndex,
) {
  final int needleLen = needle.length;
  if (needleLen == 0 ||
      startIndex < 0 ||
      startIndex + needleLen > longer.length) {
    return false;
  }
  if (longer.substring(startIndex, startIndex + needleLen) != needle) {
    return false;
  }
  final int endIndex = startIndex + needleLen;
  final int firstUnit = needle.codeUnitAt(0);
  if (startIndex > 0) {
    final int prevUnit = longer.codeUnitAt(startIndex - 1);
    if (_isDigit(firstUnit) && _isDigit(prevUnit)) {
      return false;
    }
    if (firstUnit == 0x2E && _isDigit(prevUnit)) {
      // ".0" inside "8.0" must not match as a standalone version.
      return false;
    }
  }
  if (endIndex < longer.length) {
    final int lastUnit = needle.codeUnitAt(needleLen - 1);
    final int nextUnit = longer.codeUnitAt(endIndex);
    if (_isDigit(lastUnit) && _isDigit(nextUnit)) {
      return false;
    }
  }
  return true;
}

/// True when the shorter of [a]/[b] appears inside the longer as a bounded
/// substring (covers [1.6.5-rc0] in [v1.6.5-rc0], build ids embedded in carrier
/// strings, and titles like [1Password: ... 8.12.8-27.BETA]).
bool _oneVersionStringContainsOtherAsBoundedSubstring(String a, String b) {
  if (a.isEmpty || b.isEmpty || a == b) {
    return false;
  }
  final String shorter = a.length <= b.length ? a : b;
  final String longer = a.length <= b.length ? b : a;
  if (shorter.length == longer.length) {
    return false;
  }
  int searchFrom = 0;
  while (true) {
    final int foundAt = longer.indexOf(shorter, searchFrom);
    if (foundAt < 0) {
      return false;
    }
    if (_boundedVersionSubstringInHaystack(longer, shorter, foundAt)) {
      return true;
    }
    searchFrom = foundAt + 1;
  }
}

/// True for 8-digit all-decimal tokens that look like YYYYMMDD (excludes them
/// from commit-hash intersection so shared build dates do not imply same build).
bool isPlausibleVersionDateTokenYYYYMMDD(String token) {
  if (token.length != 8) return false;
  if (!RegExp(r'^\d{8}$').hasMatch(token)) return false;
  final year = int.tryParse(token.substring(0, 4));
  final month = int.tryParse(token.substring(4, 6));
  final day = int.tryParse(token.substring(6, 8));
  if (year == null || month == null || day == null) return false;
  if (year < 1990 || year > 2100) return false;
  if (month < 1 || month > 12) return false;
  if (day < 1 || day > 31) return false;
  return true;
}

Set<String> commitHashLikeTokensFromVersion(String version) {
  final hexPattern = RegExp(r'[0-9a-fA-F]{6,}');
  final result = <String>{};
  for (final Match match in hexPattern.allMatches(version)) {
    final String token = match.group(0)!.toLowerCase();
    if (isPlausibleVersionDateTokenYYYYMMDD(token)) continue;
    // Decimal-only runs are Android versionCode / build numbers, not git hex.
    if (_digitsOnlySegmentPattern.hasMatch(token)) continue;
    result.add(token);
  }
  return result;
}

/// True if both versions are equal or one is a prefix of the other with a
/// non-digit next (e.g. 50.5.19 and 50.5.19-31), or both contain the same
/// commit-hash-like token (6+ hex chars). Avoids a false match of 1.0 in 10.0
/// by requiring a boundary after the shorter.
bool versionsEffectivelyEqual(String installed, String latest) {
  if (installed == latest) return true;
  if (installed.isEmpty || latest.isEmpty) return false;
  final int? releaseDateVersionComparison = compareReleaseDateVersionStrings(
    installed,
    latest,
  );
  if (releaseDateVersionComparison == 0) {
    return true;
  }
  final installedLen = installed.length;
  final latestLen = latest.length;
  if (latest.startsWith(installed) &&
      (installedLen == latestLen ||
          (latestLen > installedLen &&
              !_isDigit(latest.codeUnitAt(installedLen))))) {
    return true;
  }
  if (installed.startsWith(latest) &&
      (installedLen == latestLen ||
          (installedLen > latestLen &&
              !_isDigit(installed.codeUnitAt(latestLen))))) {
    return true;
  }
  if (_oneVersionStringContainsOtherAsBoundedSubstring(installed, latest)) {
    return true;
  }
  final installedHashes = commitHashLikeTokensFromVersion(installed);
  final latestHashes = commitHashLikeTokensFromVersion(latest);
  if (installedHashes.intersection(latestHashes).isNotEmpty) {
    return true;
  }
  return false;
}

/// Compare version strings by numeric segments (e.g. 2.0.0 vs 1.9.9).
/// Returns -1 if [installed] < [latest], 0 if equal, 1 if [installed] > [latest],
/// null if not comparable.
int? compareVersionsByNumericSegments(String installed, String latest) {
  final int? releaseDateVersionComparison = compareReleaseDateVersionStrings(
    installed,
    latest,
  );
  if (releaseDateVersionComparison != null) {
    return releaseDateVersionComparison;
  }
  final installedSegments = RegExp(
    r'\d+',
  ).allMatches(installed).map((m) => int.tryParse(m.group(0)!) ?? 0).toList();
  final latestSegments = RegExp(
    r'\d+',
  ).allMatches(latest).map((m) => int.tryParse(m.group(0)!) ?? 0).toList();
  if (installedSegments.isEmpty || latestSegments.isEmpty) return null;
  final maxLen = installedSegments.length > latestSegments.length
      ? installedSegments.length
      : latestSegments.length;
  for (int i = 0; i < maxLen; i++) {
    final inst = i < installedSegments.length ? installedSegments[i] : 0;
    final lat = i < latestSegments.length ? latestSegments[i] : 0;
    if (inst < lat) return -1;
    if (inst > lat) return 1;
  }
  return 0;
}

/// True when dot-separated segments match numerically through the shared prefix,
/// and the first differing part involves commit-hash-like material on at least
/// one side (e.g. [26.03.a4d75424] vs [26.03.0264c0ba]).
bool _dotSeparatedNumericPrefixThenIncomparableHashRemainder(
  String installed,
  String latest,
) {
  final installedParts = installed.split('.');
  final latestParts = latest.split('.');
  final int pairCount = installedParts.length <= latestParts.length
      ? installedParts.length
      : latestParts.length;
  for (int index = 0; index < pairCount; index++) {
    final String installedSegment = installedParts[index];
    final String latestSegment = latestParts[index];
    if (installedSegment == latestSegment) continue;
    final bool installedNumeric = _digitsOnlySegmentPattern.hasMatch(
      installedSegment,
    );
    final bool latestNumeric = _digitsOnlySegmentPattern.hasMatch(
      latestSegment,
    );
    if (installedNumeric && latestNumeric) {
      if (int.parse(installedSegment) != int.parse(latestSegment)) {
        return false;
      }
      continue;
    }
    if (installedNumeric != latestNumeric) {
      final bool hashInstalled = commitHashLikeTokensFromVersion(
        installedSegment,
      ).isNotEmpty;
      final bool hashLatest = commitHashLikeTokensFromVersion(
        latestSegment,
      ).isNotEmpty;
      if (hashInstalled || hashLatest) return true;
      return false;
    }
    final bool hashInstalled = commitHashLikeTokensFromVersion(
      installedSegment,
    ).isNotEmpty;
    final bool hashLatest = commitHashLikeTokensFromVersion(
      latestSegment,
    ).isNotEmpty;
    if (hashInstalled || hashLatest) return true;
    return false;
  }
  if (installedParts.length == latestParts.length) return false;
  final List<String> longerParts = installedParts.length > latestParts.length
      ? installedParts
      : latestParts;
  final int shorterLen = installedParts.length <= latestParts.length
      ? installedParts.length
      : latestParts.length;
  for (int index = shorterLen; index < longerParts.length; index++) {
    final String tailSegment = longerParts[index];
    if (tailSegment.isEmpty) continue;
    if (_digitsOnlySegmentPattern.hasMatch(tailSegment) &&
        int.parse(tailSegment) == 0) {
      continue;
    }
    if (commitHashLikeTokensFromVersion(tailSegment).isNotEmpty) return true;
  }
  return false;
}

/// True when ordering is ambiguous: [compareVersionsByNumericSegments] ties on
/// digit groups, or dot segments disagree in a hash-like way that overrides that
/// compare. Not [versionsEffectivelyEqual].
bool versionOrderIsUnclear(String installed, String latest) {
  if (installed.isEmpty || latest.isEmpty) return false;
  if (installed == latest) return false;
  if (versionsEffectivelyEqual(installed, latest)) return false;
  if (compareReleaseDateVersionStrings(installed, latest) != null) {
    return false;
  }
  if (compareVersionsByNumericSegments(installed, latest) == 0) {
    return true;
  }
  return _dotSeparatedNumericPrefixThenIncomparableHashRemainder(
    installed,
    latest,
  );
}

/// User skipped the current [App.latestVersion]; nagging and update badges are
/// suppressed.
bool isSkipActiveForCurrentLatest(App app) {
  final dynamic skipped = app.additionalSettings['skippedLatestVersion'];
  if (skipped is! String || skipped.isEmpty) return false;
  return skipped == app.latestVersion;
}

bool appIsUpToDateForFiltering(App app) {
  final installed = app.installedVersion;
  final latest = app.latestVersion;
  if (installed == null) return false;
  return isSkipActiveForCurrentLatest(app) ||
      installed == latest ||
      versionsEffectivelyEqual(installed, latest) ||
      (installedVersionIsNewerOrEqual(installed, latest) &&
          !versionOrderIsUnclear(installed, latest));
}

/// Removes a saved skip once it is stale or the installed app is already at
/// or ahead of the skipped release.
App normalizeSkippedLatestVersion(App app) {
  final dynamic skipped = app.additionalSettings['skippedLatestVersion'];
  if (skipped is! String || skipped.isEmpty) return app;

  var shouldRemove = skipped != app.latestVersion;
  final String? installed = app.installedVersion;
  if (!shouldRemove && installed != null && installed.isNotEmpty) {
    shouldRemove =
        installed == app.latestVersion ||
        versionsEffectivelyEqual(installed, app.latestVersion) ||
        (compareVersionsByNumericSegments(installed, app.latestVersion) == 1 &&
            !versionOrderIsUnclear(installed, app.latestVersion));
  }
  if (!shouldRemove) return app;

  return app.copyWith(
    additionalSettings: Map<String, dynamic>.from(app.additionalSettings)
      ..remove('skippedLatestVersion'),
  );
}

/// Installed app should show update affordances and count in update lists
/// (unless skipped).
bool appHasActionableUpdate(App app) {
  final String? installed = app.installedVersion;
  final String latest = app.latestVersion;
  if (installed == null || latest.isEmpty) return false;
  if (isSkipActiveForCurrentLatest(app)) return false;
  if (installed == latest) return false;
  if (versionsEffectivelyEqual(installed, latest)) return false;

  if (versionOrderIsUnclear(installed, latest)) {
    final dynamic lastInstalledTimeRaw =
        app.additionalSettings['lastInstalledTime'];
    if (lastInstalledTimeRaw is int && app.releaseDate != null) {
      final DateTime installedTime = DateTime.fromMillisecondsSinceEpoch(
        lastInstalledTimeRaw,
      );
      return app.releaseDate!.isAfter(installedTime);
    }
    // Pseudo-mode apps can't reliably compare versions; any difference is a
    // potential update regardless of ordering ambiguity.
    return app.additionalSettings['versionDetection'] == 'pseudo' ||
        app.additionalSettings['versionDetection'] == false;
  }

  final int? cmp = compareVersionsByNumericSegments(installed, latest);
  if (cmp == 1) return false;
  if (cmp == 0) return true;
  return true;
}

/// Installed app where installed vs latest differs but ordering is ambiguous
/// (user must decide). Mutually exclusive with [appHasActionableUpdate] for
/// normal version strings.
bool versionOrderUncertainUpdate(App app) {
  final String? installed = app.installedVersion;
  final String latest = app.latestVersion;
  if (installed == null || latest.isEmpty) return false;
  if (isSkipActiveForCurrentLatest(app)) return false;
  if (installed == latest) return false;
  if (versionsEffectivelyEqual(installed, latest)) return false;

  // Pseudo-mode apps cannot reliably order version strings; any version difference
  // is an update rather than "version order unclear" (parity with appHasActionableUpdate).
  if (app.additionalSettings['versionDetection'] == 'pseudo' ||
      app.additionalSettings['versionDetection'] == false) {
    return false;
  }

  if (versionOrderIsUnclear(installed, latest)) {
    final dynamic lastInstalledTimeRaw =
        app.additionalSettings['lastInstalledTime'];
    if (lastInstalledTimeRaw is int && app.releaseDate != null) {
      final DateTime installedTime = DateTime.fromMillisecondsSinceEpoch(
        lastInstalledTimeRaw,
      );
      // Suppress the uncertain indicator only when timestamps confirm the
      // release IS newer than the last install (appHasActionableUpdate already
      // covers that case). Otherwise the order is still ambiguous.
      return !app.releaseDate!.isAfter(installedTime);
    }
    return true;
  }
  return false;
}

/// True if we should not show "update available" because installed is newer than
/// or equal to latest by version math.
bool installedVersionIsNewerOrEqual(String? installed, String latest) {
  if (installed == null || installed.isEmpty || latest.isEmpty) return false;
  if (installed == latest || versionsEffectivelyEqual(installed, latest)) {
    return true;
  }
  final cmp = compareVersionsByNumericSegments(installed, latest);
  return cmp == null ? false : cmp >= 0;
}

/// Track-only open URL: RSS release page when [App.changeLog] is http(s), else
/// [App.url].
String trackOnlyDownloadPageUrl(App app) {
  final changeLogValue = app.changeLog;
  if (changeLogValue != null &&
      (changeLogValue.startsWith('http://') ||
          changeLogValue.startsWith('https://'))) {
    final appUrl = Uri.tryParse(app.url);
    final changeLogUrl = Uri.tryParse(changeLogValue);
    if (appUrl?.host.contains('apkmirror.com') == true &&
        changeLogUrl?.host.contains('apkmirror.com') == true) {
      final trackedPath = appUrl!.path.endsWith('/')
          ? appUrl.path
          : '${appUrl.path}/';
      if (!changeLogUrl!.path.startsWith(trackedPath)) {
        return app.url;
      }
    }
    return changeLogValue;
  }
  return app.url;
}

/// Returns the exact apps visible in the list surface being manually refreshed.
/// Passing these IDs to [AppsProviderUpdates.checkUpdates] bypasses the normal
/// freshness interval while preserving the fork's on-demand-only boundary.
List<String> appIdsForManualRefresh({
  required Iterable<App> apps,
  required bool onDemandOnlyList,
  required String? folderId,
  required bool showFolderedAppsOnMainPage,
  required Set<String> existingFolderIds,
}) {
  return apps
      .where((App app) {
        final bool onDemandOnly = app.settings.getBool('onDemandOnly');
        if (onDemandOnlyList) {
          return onDemandOnly;
        }
        if (onDemandOnly) {
          return false;
        }
        if (folderId != null) {
          return folderIdsForApp(app).contains(folderId);
        }
        if (showFolderedAppsOnMainPage) {
          return true;
        }
        return folderIdsForApp(app).where(existingFolderIds.contains).isEmpty;
      })
      .map((App app) => app.id)
      .toList();
}

/// Applies source-owned update fields to the latest live app row.
///
/// User-owned fields stay on [liveApp], so changes made while a network check
/// is running are not overwritten. A result is discarded when the URL or
/// source changed after the request started because it belongs to stale input.
App? mergeFetchedUpdateWithLiveState({
  required App requestedApp,
  required App? liveApp,
  required App fetchedApp,
}) {
  if (liveApp == null ||
      liveApp.url != requestedApp.url ||
      liveApp.overrideSource != requestedApp.overrideSource) {
    return null;
  }
  final int preferredApkIndex =
      liveApp.preferredApkIndex < fetchedApp.apkUrls.length
      ? liveApp.preferredApkIndex
      : fetchedApp.preferredApkIndex;
  final bool malwareScanStillMatchesRelease =
      liveApp.latestVersion == fetchedApp.latestVersion;
  return liveApp.copyWith(
    author: fetchedApp.author,
    name: fetchedApp.name,
    latestVersion: fetchedApp.latestVersion,
    apkUrls: fetchedApp.apkUrls,
    otherAssetUrls: fetchedApp.otherAssetUrls,
    preferredApkIndex: preferredApkIndex,
    lastUpdateCheck: fetchedApp.lastUpdateCheck,
    releaseDate: fetchedApp.releaseDate,
    changeLog: fetchedApp.changeLog,
    pendingRepoRenameUrl: fetchedApp.pendingRepoRenameUrl,
    iconUrl: fetchedApp.iconUrl,
    apkSizeBytes: fetchedApp.apkSizeBytes,
    rawLatestVersionFromSource: fetchedApp.rawLatestVersionFromSource,
    rawApkNamesFromSource: fetchedApp.rawApkNamesFromSource,
    rawReleaseTitlesFromSource: fetchedApp.rawReleaseTitlesFromSource,
    latestIsReproducible: fetchedApp.latestIsReproducible,
    latestReproducibleStatus: fetchedApp.latestReproducibleStatus,
    latestReproducibleVersionCode: fetchedApp.latestReproducibleVersionCode,
    latestAttestationStatus: fetchedApp.latestAttestationStatus,
    latestMalwareScanStatus: malwareScanStillMatchesRelease
        ? liveApp.latestMalwareScanStatus
        : null,
    latestMalwareScanDetail: malwareScanStillMatchesRelease
        ? liveApp.latestMalwareScanDetail
        : null,
    latestMalwareScanReportUrl: malwareScanStillMatchesRelease
        ? liveApp.latestMalwareScanReportUrl
        : null,
  );
}

typedef _FetchedAppUpdate = ({App requestedApp, App fetchedApp});

/// Update checking and pending-update bookkeeping for [AppsProvider].
extension AppsProviderUpdates on AppsProvider {
  /// Fetches the latest [App] metadata from its source WITHOUT persisting it.
  /// Returns null if the app is missing or has a pending repo rename.
  ///
  /// Keeping fetch and save separate lets [checkUpdates] batch many checks into
  /// a few [saveApps] calls instead of saving (and triggering a full UI
  /// rebuild) once per app.
  Future<_FetchedAppUpdate?> _fetchUpdateSnapshot(String appId) async {
    final App? currentApp = apps[appId]?.app;
    // Pause update checks until the user resolves a pending repo rename.
    if (currentApp == null || currentApp.hasPendingRepoRename) {
      return null;
    }
    final SourceProvider sourceProvider = SourceProvider();
    final AppSource source = sourceProvider.getSource(
      currentApp.url,
      overrideSource: currentApp.overrideSource,
    );
    App fetchedApp = await sourceProvider.getApp(
      source,
      currentApp.url,
      currentApp.additionalSettings,
      currentApp: currentApp,
    );
    fetchedApp = await _fillDownloadSizeIfUpdatePending(
      source,
      currentApp,
      fetchedApp,
    );
    return (requestedApp: currentApp, fetchedApp: fetchedApp);
  }

  /// For sources that don't publish an APK size in their metadata (GitLab,
  /// SourceForge, SourceHut, direct-APK links, HTML), probe the preferred APK's
  /// Content-Length so the update button can still show a size — but ONLY when
  /// an update is actually pending. GitHub/stores/F-Droid already fill
  /// [APKDetails.apkSizeBytes], and getApp carries a known size across
  /// same-version checks, so this adds at most one request per new release and
  /// never fires for up-to-date or track-only apps.
  Future<App> _fillDownloadSizeIfUpdatePending(
    AppSource source,
    App currentApp,
    App fetchedApp,
  ) async {
    if (fetchedApp.apkSizeBytes != null) return fetchedApp;
    if (currentApp.additionalSettings['trackOnly'] == true) return fetchedApp;
    // Only when there's something to download: not installed, or the source's
    // latest differs from what's installed.
    if (currentApp.installedVersion == fetchedApp.latestVersion) {
      return fetchedApp;
    }
    if (fetchedApp.apkUrls.isEmpty) return fetchedApp;
    final int idx =
        (fetchedApp.preferredApkIndex >= 0 &&
            fetchedApp.preferredApkIndex < fetchedApp.apkUrls.length)
        ? fetchedApp.preferredApkIndex
        : 0;
    final String url = fetchedApp.apkUrls[idx].value;
    if (url.isEmpty) return fetchedApp;
    try {
      // Resolve the real download URL first: sources like GitLab and Uptodown
      // rewrite the asset URL in assetUrlPrefetchModifier, so probing the
      // unresolved URL returns a wrong or missing Content-Length. The install
      // path already resolves before downloading; do the same here. (#3104)
      final String resolvedUrl = await source.assetUrlPrefetchModifier(
        url,
        currentApp.url,
        currentApp.additionalSettings,
      );
      if (resolvedUrl.isEmpty) return fetchedApp;
      final Map<String, String>? headers = await source.getRequestHeaders(
        currentApp.additionalSettings,
        resolvedUrl,
        forAPKDownload: true,
      );
      final int? size = await getDownloadSize(
        resolvedUrl,
        headers: headers,
        allowInsecure: currentApp.settings.getBool('allowInsecure'),
      );
      if (size != null && size > 0) {
        return fetchedApp.copyWith(apkSizeBytes: size);
      }
    } catch (_) {
      // Best-effort: leave the size unknown on any failure.
    }
    return fetchedApp;
  }

  Future<App?> fetchUpdate(String appId) async {
    final _FetchedAppUpdate? update = await _fetchUpdateSnapshot(appId);
    if (update == null) return null;
    return mergeFetchedUpdateWithLiveState(
      requestedApp: update.requestedApp,
      liveApp: apps[appId]?.app,
      fetchedApp: update.fetchedApp,
    );
  }

  Future<App?> checkUpdate(String appId) async {
    final _FetchedAppUpdate? update = await _fetchUpdateSnapshot(appId);
    if (update == null) return null;
    final App? mergedApp = mergeFetchedUpdateWithLiveState(
      requestedApp: update.requestedApp,
      liveApp: apps[appId]?.app,
      fetchedApp: update.fetchedApp,
    );
    if (mergedApp == null) return null;
    await saveApps([mergedApp]);
    return mergedApp.latestVersion != update.requestedApp.latestVersion
        ? mergedApp
        : null;
  }

  /// Returns app IDs sorted by last update check time, oldest first.
  /// When [forceAll] is false, only includes apps whose per-app lastUpdateCheck
  /// is older than the configured update interval (or null — never checked).
  /// When [forceAll] is true, includes all apps regardless of interval.
  List<String> getAppsSortedByUpdateCheckTime({
    bool onlyCheckInstalledOrTrackOnlyApps = false,
    bool forceAll = false,
  }) {
    final minAge = DateTime.now().subtract(
      Duration(minutes: settingsProvider.updateInterval),
    );
    final List<String> appIds = apps.values
        .where((app) => app.app.additionalSettings['onDemandOnly'] != true)
        .where(
          (app) =>
              forceAll ||
              app.app.lastUpdateCheck == null ||
              app.app.lastUpdateCheck!.isBefore(minAge),
        )
        .where((app) {
          if (!onlyCheckInstalledOrTrackOnlyApps) {
            return true;
          } else {
            return app.app.installedVersion != null ||
                app.app.settings.getBool('trackOnly');
          }
        })
        .map((e) => e.app.id)
        .toList();
    appIds.sort(
      (a, b) =>
          (apps[a]!.app.lastUpdateCheck ??
                  DateTime.fromMicrosecondsSinceEpoch(0))
              .compareTo(
                apps[b]!.app.lastUpdateCheck ??
                    DateTime.fromMicrosecondsSinceEpoch(0),
              ),
    );
    return appIds;
  }

  Future<List<App>> checkUpdates({
    bool throwErrorsForRetry = false,
    List<String>? specificIds,
    bool forceAll = false,
    SettingsProvider? sp,
  }) async {
    final SettingsProvider settingsProvider = sp ?? this.settingsProvider;
    if (updateCheckCompleter != null) {
      return updateCheckCompleter!.future;
    }
    final completer = updateCheckCompleter = Completer<List<App>>();
    var completed = 0;
    var total = 0;
    DateTime lastProgressNotification = DateTime.fromMillisecondsSinceEpoch(0);
    refreshProgress = 0.0;
    void reportProgress({bool force = false}) {
      final DateTime now = DateTime.now();
      if (force ||
          now.difference(lastProgressNotification) >=
              const Duration(milliseconds: 250)) {
        lastProgressNotification = now;
        refreshProgress = total > 0 ? completed / total : 0.0;
      }
    }

    try {
      final List<App> updates = [];
      final MultiAppMultiError errors = MultiAppMultiError();
      List<String> appIds;
      if (specificIds != null) {
        appIds = specificIds.where(apps.containsKey).toSet().toList();
        if (settingsProvider.onlyCheckInstalledOrTrackOnlyApps) {
          appIds.removeWhere((id) {
            final App app = apps[id]!.app;
            return app.installedVersion == null &&
                !app.settings.getBool('trackOnly');
          });
        }
        appIds.sort(
          (a, b) =>
              (apps[a]!.app.lastUpdateCheck ??
                      DateTime.fromMicrosecondsSinceEpoch(0))
                  .compareTo(
                    apps[b]!.app.lastUpdateCheck ??
                        DateTime.fromMicrosecondsSinceEpoch(0),
                  ),
        );
      } else {
        appIds = getAppsSortedByUpdateCheckTime(
          onlyCheckInstalledOrTrackOnlyApps:
              settingsProvider.onlyCheckInstalledOrTrackOnlyApps,
          forceAll: forceAll,
        );
      }
      total = appIds.length;
      final List<_FetchedAppUpdate> pendingResults = [];
      DateTime lastSaveTime = DateTime.now();
      bool saveInProgress = false;
      const Duration saveInterval = Duration(seconds: 3);
      int nextIndex = 0;
      final int workerCount = min(
        total,
        await maxParallelUpdateChecksForDevice(),
      );

      Future<_FetchedAppUpdate?> fetchUpdateWithHandshakeRetry(
        String appId,
      ) async {
        try {
          return await _fetchUpdateSnapshot(appId);
        } on HandshakeException {
          // Concurrent TLS handshakes to the same host can fail on certain
          // devices or networks. Keep retries inside the bounded worker so
          // they cannot bypass the device-tuned concurrency limit.
          const int maxRetries = 5;
          final Random random = Random();
          for (int attempt = 0; attempt < maxRetries; attempt++) {
            await Future.delayed(
              Duration(milliseconds: 250 + random.nextInt(501)),
            );
            try {
              return await _fetchUpdateSnapshot(appId);
            } on HandshakeException {
              if (attempt == maxRetries - 1) rethrow;
            }
          }
          return null;
        }
      }

      Future<void> flushFetchedResults({bool force = false}) async {
        if (saveInProgress || pendingResults.isEmpty) return;
        final DateTime now = DateTime.now();
        if (!force && now.difference(lastSaveTime) < saveInterval) return;

        saveInProgress = true;
        final List<_FetchedAppUpdate> batch = List.from(pendingResults);
        pendingResults.clear();
        try {
          final List<App> fetched = [];
          for (final _FetchedAppUpdate result in batch) {
            final App? mergedApp = mergeFetchedUpdateWithLiveState(
              requestedApp: result.requestedApp,
              liveApp: apps[result.requestedApp.id]?.app,
              fetchedApp: result.fetchedApp,
            );
            if (mergedApp == null) continue;
            fetched.add(mergedApp);
            if (mergedApp.latestVersion != result.requestedApp.latestVersion) {
              updates.add(mergedApp);
            }
          }
          if (fetched.isNotEmpty) {
            // Reuse cached install info: this flush runs every few seconds for
            // the whole update check, and a refresh here costs a device-wide
            // package enumeration per flush (also in the background isolate).
            // Install state is refreshed by loadApps on launch and on every
            // foreground resume, which is where external installs get picked up.
            await saveApps(fetched, updateInstalledInfo: false);
          }
        } finally {
          lastSaveTime = DateTime.now();
          saveInProgress = false;
        }
      }

      Future<void> runWorker() async {
        while (nextIndex < total) {
          final String appId = appIds[nextIndex++];
          try {
            final _FetchedAppUpdate? update =
                await fetchUpdateWithHandshakeRetry(appId);
            if (update != null) {
              pendingResults.add(update);
            }
          } catch (e) {
            if ((e is RateLimitError ||
                    e is SocketException ||
                    e is HandshakeException) &&
                throwErrorsForRetry) {
              rethrow;
            }
            if (e is RepositoryRenamedError) {
              await updatePendingRepoRename(appId, e.newUrl);
            } else {
              errors.add(appId, e, appName: apps[appId]?.name);
            }
          } finally {
            completed++;
            reportProgress();
          }
          await flushFetchedResults();
        }
      }

      await Future.wait(List.generate(workerCount, (_) => runWorker()));
      reportProgress(force: true);
      await flushFetchedResults(force: true);
      if (errors.idsByErrorString.isNotEmpty) {
        final ex = CheckUpdatesException(updates, errors);
        completer.completeError(ex);
        throw ex;
      }
      completer.complete(updates);
      return updates;
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
      rethrow;
    } finally {
      updateCheckCompleter = null;
      refreshProgress = null;
    }
  }

  /// Finds app IDs whose installed version differs from the latest version, with optional filtering.
  List<String> findAppIdsWithPendingUpdates({
    bool installedOnly = false,
    bool nonInstalledOnly = false,
  }) {
    final List<String> updateAppIds = [];
    for (final appId in apps.keys) {
      final app = apps[appId]!.app;
      if (installedOnly) {
        if (app.installedVersion != null &&
            app.installedVersion != app.latestVersion) {
          updateAppIds.add(app.id);
        }
      } else if (nonInstalledOnly) {
        if (app.installedVersion == null) {
          updateAppIds.add(app.id);
        }
      } else if (app.installedVersion != app.latestVersion) {
        updateAppIds.add(app.id);
      }
    }
    return updateAppIds;
  }

  /// Returns app ids with an installable or attention-needed update.
  ///
  /// When [includeVersionOrderUncertain] is false (default), only
  /// [appHasActionableUpdate] counts for installed apps so "update all" and
  /// background install do not treat ambiguous ordering as a known
  /// behind-latest case. When true, [versionOrderUncertainUpdate] apps are
  /// included too (e.g. the tab badge).
  List<String> findExistingUpdates({
    bool installedOnly = false,
    bool nonInstalledOnly = false,
    bool excludeOnDemandOnly = false,
    bool includeVersionOrderUncertain = false,
  }) {
    if (installedOnly && nonInstalledOnly) {
      return [];
    }
    final List<String> updateAppIds = [];
    for (final appInMemory in apps.values) {
      final app = appInMemory.app;
      if (excludeOnDemandOnly &&
          app.additionalSettings['onDemandOnly'] == true) {
        continue;
      }
      final installed = app.installedVersion;
      final latest = app.latestVersion;

      if (installed == null) {
        if (!(nonInstalledOnly || !installedOnly)) continue;
        if (installed != latest) {
          updateAppIds.add(app.id);
        }
      } else {
        if (!(installedOnly || !nonInstalledOnly)) continue;
        if (appHasActionableUpdate(app) ||
            (includeVersionOrderUncertain &&
                versionOrderUncertainUpdate(app))) {
          updateAppIds.add(app.id);
        }
      }
    }
    return updateAppIds;
  }

  /// Device-tuned upper bound on how many update checks run in parallel. Low-RAM
  /// devices fan out less to avoid thrashing; capable devices keep the default.
  Future<int> maxParallelUpdateChecksForDevice() async {
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.isLowRamDevice ||
          (androidInfo.physicalRamSize > 0 &&
              androidInfo.physicalRamSize <= _lowEndRamThresholdMb)) {
        return _lowEndDeviceParallelUpdateChecks;
      }
      if (androidInfo.physicalRamSize > 0 &&
          androidInfo.physicalRamSize <= _modestRamThresholdMb) {
        return _modestDeviceParallelUpdateChecks;
      }
    } catch (_) {
      // If device info is unavailable, prefer speed and keep the bounded
      // default rather than silently falling back to the slowest path.
    }
    return _defaultParallelUpdateChecks;
  }

  void _pruneStaleDetailPageAutoCheckStarts(DateTime now, Duration cooldown) {
    lastDetailPageAutoCheckStartedAt.removeWhere(
      (String appId, DateTime startedAt) =>
          !detailPageAutoChecksInFlight.contains(appId) &&
          now.difference(startedAt) >= cooldown,
    );
  }

  /// Reserves an auto-check slot for the detail page of [appId], returning true
  /// only when a check should actually start now (not recently run/started and
  /// not already in flight).
  bool tryBeginDetailPageAutoCheck({
    required String appId,
    required DateTime now,
    required Duration cooldown,
    required DateTime? lastUpdateCheckAt,
  }) {
    _pruneStaleDetailPageAutoCheckStarts(now, cooldown);
    final DateTime? lastStartedAt = lastDetailPageAutoCheckStartedAt[appId];
    final bool recentlyCompleted =
        lastUpdateCheckAt != null &&
        now.difference(lastUpdateCheckAt) < cooldown;
    final bool recentlyStarted =
        lastStartedAt != null && now.difference(lastStartedAt) < cooldown;
    if (recentlyCompleted ||
        recentlyStarted ||
        detailPageAutoChecksInFlight.contains(appId)) {
      return false;
    }
    detailPageAutoChecksInFlight.add(appId);
    lastDetailPageAutoCheckStartedAt[appId] = now;
    return true;
  }

  void finishDetailPageAutoCheck(String appId) {
    detailPageAutoChecksInFlight.remove(appId);
  }
}
