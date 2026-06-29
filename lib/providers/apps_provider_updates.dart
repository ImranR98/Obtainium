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
    App? currentApp = apps[appId]?.app;
    // Pause update checks until the user resolves a pending repo rename.
    if (currentApp == null || currentApp.hasPendingRepoRename) {
      return null;
    }
    SourceProvider sourceProvider = SourceProvider();
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
      newApp.preferredApkIndex = currentApp.preferredApkIndex;
    }
    return newApp;
  }

  Future<App?> checkUpdate(String appId) async {
    App? currentApp = apps[appId]?.app;
    if (currentApp == null) return null;
    App? newApp = await fetchUpdate(appId);
    if (newApp == null) {
      return null;
    }
    await saveApps([newApp]);
    return newApp.latestVersion != currentApp.latestVersion ? newApp : null;
  }

  List<String> getAppsSortedByUpdateCheckTime({
    DateTime? ignoreAppsCheckedAfter,
    bool onlyCheckInstalledOrTrackOnlyApps = false,
  }) {
    List<String> appIds = apps.values
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
                app.app.additionalSettings['trackOnly'] == true;
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
    SettingsProvider settingsProvider = sp ?? this.settingsProvider;
    List<App> updates = [];
    MultiAppMultiError errors = MultiAppMultiError();
    if (!gettingUpdates) {
      gettingUpdates = true;
      try {
        List<String> appIds = getAppsSortedByUpdateCheckTime(
          ignoreAppsCheckedAfter: ignoreAppsCheckedAfter,
          onlyCheckInstalledOrTrackOnlyApps:
              settingsProvider.onlyCheckInstalledOrTrackOnlyApps,
        );
        if (specificIds != null) {
          appIds = appIds.where((aId) => specificIds.contains(aId)).toList();
        }
        // Check updates with bounded concurrency and persist results in
        // batches (one saveApps -> one notify -> one rebuild per chunk).
        // Previously every app saved itself the moment its check finished,
        // causing one full UI rebuild per app and firing unbounded parallel
        // network requests at once, which froze the UI during a refresh.
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
                } else {
                  errors.add(appId, e, appName: apps[appId]?.name);
                }
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
      } finally {
        gettingUpdates = false;
      }
    }
    if (errors.idsByErrorString.isNotEmpty) {
      var res = <String, dynamic>{};
      res['errors'] = errors;
      res['updates'] = updates;
      throw res;
    }
    return updates;
  }

  List<String> findExistingUpdates({
    bool installedOnly = false,
    bool nonInstalledOnly = false,
  }) {
    List<String> updateAppIds = [];
    for (final appId in apps.keys) {
      final app = apps[appId]!.app;
      if (installedOnly && nonInstalledOnly) {
        continue;
      }
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
