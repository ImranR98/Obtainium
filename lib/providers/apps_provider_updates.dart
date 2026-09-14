import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/utils/min_update_age.dart';

/// Update checking and pending-update bookkeeping for [AppsProvider].
extension AppsProviderUpdates on AppsProvider {
  /// Fetches the latest [App] metadata from its source WITHOUT persisting it.
  /// Returns null if the app is missing or has a pending repo rename.
  ///
  /// Keeping fetch and save separate lets [checkUpdates] batch many checks into
  /// a few [saveApps] calls instead of saving (and triggering a full UI
  /// rebuild) once per app.
  Future<App?> fetchUpdate(String appId) async {
    final App? currentApp = apps[appId]?.app;
    // Pause update checks until the user resolves a pending repo rename.
    if (currentApp == null || currentApp.hasPendingRepoRename) {
      return null;
    }
    final SourceProvider sourceProvider = SourceProvider();
    App newApp = await sourceProvider.getApp(
      sourceProvider.getSource(
        currentApp.url,
        overrideSource: currentApp.overrideSource,
      ),
      currentApp.url,
      currentApp.additionalSettings,
      currentApp: currentApp,
    );
    if (await _isReleaseYoungerThanMinAge(currentApp, newApp)) {
      // Suppress the update until the release has reached the configured
      // minimum age (supply-chain delay).
      newApp = applyMinAgeSuppression(currentApp, newApp);
    }
    if (currentApp.preferredApkIndex < newApp.apkUrls.length) {
      newApp = newApp.copyWith(preferredApkIndex: currentApp.preferredApkIndex);
    } else if (newApp.apkUrls.isNotEmpty) {
      newApp = newApp.copyWith(preferredApkIndex: 0);
    }
    return newApp;
  }

  /// Fetches [appId] with a short retry for transient TLS handshake failures.
  ///
  /// Concurrent TLS handshakes to the same host can fail on certain
  /// devices/networks. Retry up to 2 times with staggered random delays to
  /// avoid all retries colliding. Any error that is not a handshake failure
  /// (including one raised by a retry) propagates to the caller so it can take
  /// the normal per-app error path instead of aborting the whole batch.
  Future<App?> fetchUpdateWithHandshakeRetry(String appId) async {
    try {
      return await fetchUpdate(appId);
    } on HandshakeException {
      const maxRetries = 2;
      final rng = Random();
      for (var attempt = 0; attempt < maxRetries; attempt++) {
        await Future.delayed(Duration(milliseconds: 250 + rng.nextInt(501)));
        try {
          return await fetchUpdate(appId);
        } on HandshakeException {
          if (attempt == maxRetries - 1) rethrow;
        }
      }
      return null;
    }
  }

  /// Returns true when [newApp]'s release is newer than the configured
  /// minimum update age and should therefore be suppressed.
  Future<bool> _isReleaseYoungerThanMinAge(App currentApp, App newApp) async {
    if (newApp.latestVersion == currentApp.latestVersion) {
      return false;
    }
    final minAgeDays = await effectiveMinUpdateAgeDays(
      currentApp.additionalSettings,
      settingsProvider: settingsProvider,
    );
    return isReleaseTooYoung(newApp.releaseDate, minAgeDays);
  }

  Future<App?> checkUpdate(String appId) async {
    final App? currentApp = apps[appId]?.app;
    if (currentApp == null) return null;
    final App? newApp = await fetchUpdate(appId);
    if (newApp == null) {
      return null;
    }
    await saveApps([newApp]);
    return newApp.latestVersion != currentApp.latestVersion ? newApp : null;
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
    // A check is already running. Its result may not cover the apps this
    // caller asked for (e.g. a deep-link refresh for one app arriving during a
    // full background check), so wait for it to finish and then run our own
    // instead of silently returning the other check's result.
    while (updateCheckCompleter != null) {
      final runningCheck = updateCheckCompleter!;
      await runningCheck.future.catchError((_) => <App>[]);
    }
    final completer = updateCheckCompleter = Completer<List<App>>();
    var completed = 0;
    var total = 0;
    refreshProgress.value = 0.0;
    final progressTimer = Timer.periodic(const Duration(milliseconds: 250), (
      _,
    ) {
      refreshProgress.value = total > 0 ? completed / total : 0.0;
    });
    try {
      final List<App> updates = [];
      final MultiAppMultiError errors = MultiAppMultiError();
      List<String> appIds;
      if (specificIds != null) {
        appIds = List.from(specificIds);
      } else {
        appIds = getAppsSortedByUpdateCheckTime(
          onlyCheckInstalledOrTrackOnlyApps:
              settingsProvider.onlyCheckInstalledOrTrackOnlyApps,
          forceAll: forceAll,
        );
      }
      total = appIds.length;
      final List<App> fetched = [];
      // Apps whose check failed: their check time is still advanced so the
      // background task doesn't retry them every 15 minutes; they become due
      // again after one full update interval (#3187).
      final List<App> failedApps = [];
      var lastSaveTime = DateTime.now();
      const saveInterval = Duration(seconds: 3);

      // Fetching an app runs synchronous, CPU-bound work (HTML/JSON parsing)
      // on the UI isolate. Firing every check at once saturates the event loop
      // and freezes the UI for the whole refresh. Bound the number of in-flight
      // checks so the isolate has room to render frames between them.
      const maxConcurrent = kDefaultFetchConcurrency;
      var nextIndex = 0;

      Future<MapEntry<App, bool>?> fetchOne(String appId) async {
        final currentApp = apps[appId]?.app;
        try {
          final newApp = await fetchUpdateWithHandshakeRetry(appId);
          if (newApp != null) {
            final isUpdate =
                currentApp != null &&
                newApp.latestVersion != currentApp.latestVersion &&
                isAppUpdateable(newApp, settingsProvider);
            return MapEntry(newApp, isUpdate);
          }
        } catch (e) {
          if ((e is RateLimitError || e is SocketException) &&
              throwErrorsForRetry) {
            rethrow;
          }
          if (e is RepositoryRenamedError) {
            await updatePendingRepoRename(appId, e.newUrl);
          } else {
            errors.add(appId, e, appName: apps[appId]?.name);
            final app = apps[appId]?.app;
            if (app != null) {
              failedApps.add(app.copyWith(lastUpdateCheck: DateTime.now()));
            }
          }
        }
        return null;
      }

      Future<void> worker() async {
        while (true) {
          final int i = nextIndex++;
          if (i >= appIds.length) return;
          final result = await fetchOne(appIds[i]);
          completed++;
          // Save on a fixed time interval rather than per-app or per-N apps,
          // so the UI rebuilds a bounded number of times regardless of how
          // many apps are checked or how fast they complete.
          if (result != null) {
            fetched.add(result.key);
            if (result.value) updates.add(result.key);
          }
          if (fetched.isNotEmpty &&
              DateTime.now().difference(lastSaveTime) >= saveInterval) {
            final batch = List<App>.from(fetched);
            fetched.clear();
            lastSaveTime = DateTime.now();
            await saveApps(batch, reuseInstalledInfo: true);
          }
        }
      }

      await Future.wait(
        List.generate(min(maxConcurrent, appIds.length), (_) => worker()),
        eagerError: true,
      );
      if (fetched.isNotEmpty) {
        await saveApps(fetched, reuseInstalledInfo: true);
      }
      if (failedApps.isNotEmpty) {
        await saveApps(
          failedApps,
          attemptToCorrectInstallStatus: false,
          reuseInstalledInfo: true,
        );
      }
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
      progressTimer.cancel();
      updateCheckCompleter = null;
      refreshProgress.value = null;
      notify();
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
      final installed = app.installedVersion;
      if (installedOnly) {
        if (installed == null) continue;
      } else if (nonInstalledOnly) {
        if (installed == null) updateAppIds.add(app.id);
        continue;
      }
      if (installed == null ||
          (_installedVersionDiffers(app, installed) &&
              isAppUpdateable(app, settingsProvider))) {
        updateAppIds.add(app.id);
      }
    }
    return updateAppIds;
  }

  /// Whether [installed] differs from the app's latest version, either
  /// directly or after extracting the app's `versionExtractionRegEx` portion.
  bool _installedVersionDiffers(App app, String installed) {
    final regex =
        (app.additionalSettings['versionExtractionRegEx'] as String?) ?? '';
    return regex.isEmpty
        ? installed != app.latestVersion
        : !doStringsMatchUnderRegEx(regex, installed, app.latestVersion);
  }
}
