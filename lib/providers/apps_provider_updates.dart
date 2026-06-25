part of 'apps_provider.dart';

/// Update checking and pending-update bookkeeping for [AppsProvider].
extension AppsProviderUpdates on AppsProvider {
  Future<App?> checkUpdate(String appId) async {
    App? currentApp = apps[appId]!.app;
    // Pause update checks until the user resolves a pending repo rename.
    if (currentApp.hasPendingRepoRename) {
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
        await Future.wait(
          appIds.map((appId) async {
            App? newApp;
            try {
              newApp = await checkUpdate(appId);
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
            }
            if (newApp != null) {
              updates.add(newApp);
            }
          }),
          eagerError: true,
        );
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
    List<String> appIds = apps.keys.toList();
    for (int i = 0; i < appIds.length; i++) {
      App? app = apps[appIds[i]]!.app;
      if (app.installedVersion != app.latestVersion &&
          (!installedOnly || !nonInstalledOnly)) {
        if ((app.installedVersion == null &&
                (nonInstalledOnly || !installedOnly) ||
            (app.installedVersion != null &&
                (installedOnly || !nonInstalledOnly)))) {
          updateAppIds.add(app.id);
        }
      }
    }
    return updateAppIds;
  }
}
