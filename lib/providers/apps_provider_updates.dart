import 'dart:async';
import 'dart:io';

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

  /// Returns app IDs sorted by last update check time, oldest first, with optional filters.
  List<String> getAppsSortedByUpdateCheckTime({
    DateTime? ignoreAppsCheckedAfter,
    bool onlyCheckInstalledOrTrackOnlyApps = false,
  }) {
    final List<String> appIds = apps.values
        .where(
          (app) =>
              app.app.lastUpdateCheck == null ||
              ignoreAppsCheckedAfter == null ||
              app.app.lastUpdateCheck!.isBefore(ignoreAppsCheckedAfter),
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
    DateTime? ignoreAppsCheckedAfter,
    bool throwErrorsForRetry = false,
    List<String>? specificIds,
    SettingsProvider? sp,
  }) async {
    final SettingsProvider settingsProvider = sp ?? this.settingsProvider;
    if (updateCheckCompleter != null) {
      return updateCheckCompleter!.future;
    }
    final completer = updateCheckCompleter = Completer<List<App>>();
    try {
      final List<App> updates = [];
      final MultiAppMultiError errors = MultiAppMultiError();
      List<String> appIds = getAppsSortedByUpdateCheckTime(
        ignoreAppsCheckedAfter: ignoreAppsCheckedAfter,
        onlyCheckInstalledOrTrackOnlyApps:
            settingsProvider.onlyCheckInstalledOrTrackOnlyApps,
      );
      if (specificIds != null) {
        appIds = appIds.where((aId) => specificIds.contains(aId)).toList();
      }
      const int maxConcurrent = 8;
      for (var start = 0; start < appIds.length; start += maxConcurrent) {
        final end = (start + maxConcurrent < appIds.length)
            ? start + maxConcurrent
            : appIds.length;
        final chunk = appIds.sublist(start, end);
        final chunkResults = await Future.wait(
          chunk.map((appId) async {
            final currentApp = apps[appId]?.app;
            try {
              final newApp = await fetchUpdate(appId);
              if (newApp == null) return null;
              final isUpdate =
                  currentApp != null &&
                  newApp.latestVersion != currentApp.latestVersion;
              return MapEntry(newApp, isUpdate);
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
          }),
          eagerError: true,
        );
        final List<App> chunkFetched = [];
        for (final r in chunkResults) {
          if (r == null) continue;
          chunkFetched.add(r.key);
          if (r.value) updates.add(r.key);
        }
        if (chunkFetched.isNotEmpty) {
          await saveApps(chunkFetched);
        }
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
      updateCheckCompleter = null;
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
