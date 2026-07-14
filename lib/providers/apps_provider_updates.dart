import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

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
    if (currentApp.preferredApkIndex < newApp.apkUrls.length) {
      newApp = newApp.copyWith(preferredApkIndex: currentApp.preferredApkIndex);
    } else if (newApp.apkUrls.isNotEmpty) {
      newApp = newApp.copyWith(preferredApkIndex: 0);
    }
    return newApp;
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
    if (updateCheckCompleter != null) {
      return updateCheckCompleter!.future;
    }
    final completer = updateCheckCompleter = Completer<List<App>>();
    var completed = 0;
    var total = 0;
    refreshProgress = 0.0;
    notify();
    final progressTimer = Timer.periodic(const Duration(milliseconds: 250), (
      _,
    ) {
      refreshProgress = total > 0 ? completed / total : 0.0;
      notify();
    });
    try {
      final List<App> updates = [];
      final MultiAppMultiError errors = MultiAppMultiError();
      List<String> appIds;
      if (specificIds != null) {
        appIds = List.from(specificIds);
      } else if (forceAll) {
        appIds = apps.values.map((e) => e.app.id).toList();
        appIds.sort(
          (a, b) =>
              (apps[a]!.app.lastUpdateCheck ??
                      DateTime.fromMicrosecondsSinceEpoch(0))
                  .compareTo(
                    apps[b]!.app.lastUpdateCheck ??
                        DateTime.fromMicrosecondsSinceEpoch(0),
                  ),
        );
        if (settingsProvider.onlyCheckInstalledOrTrackOnlyApps) {
          appIds.removeWhere((id) {
            final a = apps[id]?.app;
            return a?.installedVersion == null &&
                a?.settings.getBool('trackOnly') != true;
          });
        }
      } else {
        appIds = getAppsSortedByUpdateCheckTime(
          onlyCheckInstalledOrTrackOnlyApps:
              settingsProvider.onlyCheckInstalledOrTrackOnlyApps,
        );
      }
      total = appIds.length;
      final results = await Future.wait(
        appIds
            .map((appId) async {
              final currentApp = apps[appId]?.app;
              try {
                final newApp = await fetchUpdate(appId);
                if (newApp == null) return null;
                final isUpdate =
                    currentApp != null &&
                    newApp.latestVersion != currentApp.latestVersion;
                return MapEntry(newApp, isUpdate);
              } on HandshakeException {
                // Concurrent TLS handshakes to the same host can fail on
                // certain devices/networks. Retry up to 5 times with
                // staggered random delays to avoid all retries colliding.
                const maxRetries = 5;
                final rng = Random();
                for (var attempt = 0; attempt < maxRetries; attempt++) {
                  await Future.delayed(
                    Duration(
                      milliseconds: 250 + rng.nextInt(501),
                    ),
                  );
                  try {
                    final newApp = await fetchUpdate(appId);
                    if (newApp == null) return null;
                    final isUpdate =
                        currentApp != null &&
                        newApp.latestVersion != currentApp.latestVersion;
                    return MapEntry(newApp, isUpdate);
                  } on HandshakeException {
                    if (attempt == maxRetries - 1) rethrow;
                  }
                }
                return null;
              } catch (e) {
                if ((e is RateLimitError || e is SocketException) &&
                    throwErrorsForRetry) {
                  rethrow;
                }
                if (e is RepositoryRenamedError) {
                  await updatePendingRepoRename(appId, e.newUrl);
                  return null;
                }
                errors.add(appId, e, appName: apps[appId]?.name);
                return null;
              }
            })
            .map(
              (f) => f.whenComplete(() {
                completed++;
              }),
            ),
        eagerError: true,
      );
      final List<App> fetched = [];
      for (final r in results) {
        if (r == null) continue;
        fetched.add(r.key);
        if (r.value) updates.add(r.key);
      }
      if (fetched.isNotEmpty) {
        await saveApps(fetched);
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
      refreshProgress = null;
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
}
