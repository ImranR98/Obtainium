part of 'apps_provider.dart';

/// App persistence (load/save/remove), icons, and version-detection helpers.
extension AppsProviderLifecycle on AppsProvider {
  Future<Directory> getAppsDir() async {
    Directory appsDir = Directory(
      '${(await getAppStorageDir()).path}/app_data',
    );
    if (!appsDir.existsSync()) {
      appsDir.createSync();
    }
    return appsDir;
  }

  bool isVersionDetectionPossible(AppInMemory? app) {
    if (app?.app == null) {
      return false;
    }
    var source = SourceProvider().getSource(
      app!.app.url,
      overrideSource: app.app.overrideSource,
    );
    var naiveStandardVersionDetection =
        app.app.additionalSettings['naiveStandardVersionDetection'] == true ||
        source.naiveStandardVersionDetection;
    String? realInstalledVersion =
        app.app.additionalSettings['useVersionCodeAsOSVersion'] == true
        ? app.installedInfo?.versionCode.toString()
        : app.installedInfo?.versionName;
    bool isHTMLWithNoVersionDetection =
        (source.runtimeType == HTML().runtimeType &&
        (app.app.additionalSettings['versionExtractionRegEx'] as String?)
                ?.isNotEmpty !=
            true);
    bool isDirectAPKLink = source.runtimeType == DirectAPKLink().runtimeType;
    return app.app.additionalSettings['trackOnly'] != true &&
        app.app.additionalSettings['releaseDateAsVersion'] != true &&
        !isHTMLWithNoVersionDetection &&
        !isDirectAPKLink &&
        realInstalledVersion != null &&
        app.app.installedVersion != null &&
        (reconcileVersionDifferences(
                  realInstalledVersion,
                  app.app.installedVersion!,
                ) !=
                null ||
            naiveStandardVersionDetection);
  }

  // Given an App and it's on-device info...
  // Reconcile unexpected differences between its reported installed version, real installed version, and reported latest version
  App? getCorrectedInstallStatusAppIfPossible(
    App app,
    PackageInfo? installedInfo,
  ) {
    var modded = false;
    var trackOnly = app.additionalSettings['trackOnly'] == true;
    var versionDetectionIsStandard =
        app.additionalSettings['versionDetection'] == true;
    var naiveStandardVersionDetection =
        app.additionalSettings['naiveStandardVersionDetection'] == true ||
        SourceProvider()
            .getSource(app.url, overrideSource: app.overrideSource)
            .naiveStandardVersionDetection;
    String? realInstalledVersion =
        app.additionalSettings['useVersionCodeAsOSVersion'] == true
        ? installedInfo?.versionCode.toString()
        : installedInfo?.versionName;
    // FIRST, COMPARE THE APP'S REPORTED AND REAL INSTALLED VERSIONS, WHERE ONE IS NULL
    if (installedInfo == null && app.installedVersion != null && !trackOnly) {
      // App says it's installed but isn't really (and isn't track only) - set to not installed
      app.installedVersion = null;
      modded = true;
    } else if (realInstalledVersion != null && app.installedVersion == null) {
      // App says it's not installed but really is - set to installed and use real package versionName (or versionCode if chosen)
      app.installedVersion = realInstalledVersion;
      modded = true;
    }
    // SECOND, RECONCILE DIFFERENCES BETWEEN THE APP'S REPORTED AND REAL INSTALLED VERSIONS, WHERE NEITHER IS NULL
    if (realInstalledVersion != null &&
        realInstalledVersion != app.installedVersion &&
        versionDetectionIsStandard) {
      // App's reported version and real version don't match (and it uses standard version detection)
      // If they share a standard format (and are still different under it), update the reported version accordingly
      var correctedInstalledVersion = reconcileVersionDifferences(
        realInstalledVersion,
        app.installedVersion!,
      );
      if (correctedInstalledVersion?.key == false) {
        app.installedVersion = correctedInstalledVersion!.value;
        modded = true;
      } else if (naiveStandardVersionDetection) {
        app.installedVersion = realInstalledVersion;
        modded = true;
      }
    }
    // THIRD, RECONCILE THE APP'S REPORTED INSTALLED AND LATEST VERSIONS
    if (app.installedVersion != null &&
        app.installedVersion != app.latestVersion &&
        versionDetectionIsStandard) {
      // App's reported installed and latest versions don't match (and it uses standard version detection)
      // If they share a standard format, make sure the App's reported installed version uses that format
      var correctedInstalledVersion = reconcileVersionDifferences(
        app.installedVersion!,
        app.latestVersion,
      );
      if (correctedInstalledVersion?.key == true) {
        app.installedVersion = correctedInstalledVersion!.value;
        modded = true;
      }
    }
    // FOURTH, DISABLE VERSION DETECTION IF ENABLED AND THE REPORTED/REAL INSTALLED VERSIONS ARE NOT STANDARDIZED
    if (installedInfo != null &&
        versionDetectionIsStandard &&
        !isVersionDetectionPossible(
          AppInMemory(app, null, installedInfo, null),
        )) {
      app.additionalSettings['versionDetection'] = false;
      app.installedVersion = app.latestVersion;
      logs.add('Could not reconcile version formats for: ${app.id}');
      modded = true;
    }

    return modded ? app : null;
  }

  MapEntry<bool, String>? reconcileVersionDifferences(
    String templateVersion,
    String comparisonVersion,
  ) {
    // Returns null if the versions don't share a common standard format
    // Returns <true, comparisonVersion> if they share a common format and are equal
    // Returns <false, templateVersion> if they share a common format but are not equal
    // templateVersion must fully match a standard format, while comparisonVersion can have a substring match
    var templateVersionFormats = findStandardFormatsForVersion(
      templateVersion,
      true,
    );
    var comparisonVersionFormats = findStandardFormatsForVersion(
      comparisonVersion,
      true,
    );
    if (comparisonVersionFormats.isEmpty) {
      comparisonVersionFormats = findStandardFormatsForVersion(
        comparisonVersion,
        false,
      );
    }
    var commonStandardFormats = templateVersionFormats.intersection(
      comparisonVersionFormats,
    );
    if (commonStandardFormats.isEmpty) {
      return null;
    }
    for (String pattern in commonStandardFormats) {
      if (doStringsMatchUnderRegEx(
        pattern,
        comparisonVersion,
        templateVersion,
      )) {
        return MapEntry(true, comparisonVersion);
      }
    }
    return MapEntry(false, templateVersion);
  }

  bool doStringsMatchUnderRegEx(String pattern, String value1, String value2) {
    var r = RegExp(pattern);
    var m1 = r.firstMatch(value1);
    var m2 = r.firstMatch(value2);
    return m1 != null && m2 != null
        ? value1.substring(m1.start, m1.end) ==
              value2.substring(m2.start, m2.end)
        : false;
  }

  Future<void> loadApps({String? singleId}) async {
    while (loadingApps) {
      await Future.delayed(const Duration(microseconds: 1));
    }
    loadingApps = true;
    notify();
    var sp = SourceProvider();
    List<List<String>> errors = [];
    var installedAppsData = await getAllInstalledInfo();
    List<String> removedAppIds = [];
    await Future.wait(
      (await getAppsDir()) // Parse Apps from JSON
          .listSync()
          .map((item) async {
            App? app;
            if (item.path.toLowerCase().endsWith('.json') &&
                (singleId == null ||
                    item.path.split('/').last.toLowerCase() ==
                        '${singleId.toLowerCase()}.json')) {
              try {
                app = App.fromJson(
                  jsonDecode(File(item.path).readAsStringSync()),
                );
              } catch (err) {
                if (err is FormatException) {
                  logs.add(
                    'Corrupt JSON when loading App (will be ignored): $err',
                  );
                  item.renameSync('${item.path}.corrupt');
                } else {
                  rethrow;
                }
              }
            }
            if (app != null) {
              // Save the app to the in-memory list without grabbing any OS info first
              apps.update(
                app.id,
                (value) => AppInMemory(
                  app!,
                  value.downloadProgress,
                  value.installedInfo,
                  value.icon,
                ),
                ifAbsent: () => AppInMemory(app!, null, null, null),
              );
              notify();
              try {
                // Try getting the app's source to ensure no invalid apps get loaded
                sp.getSource(app.url, overrideSource: app.overrideSource);
                // If the app is installed, grab its OS data and reconcile install statuses
                PackageInfo? installedInfo;
                try {
                  installedInfo = installedAppsData.firstWhere(
                    (i) => i.packageName == app!.id,
                  );
                } catch (e) {
                  // If the app isn't installed the above throws an error
                }
                // Reconcile differences between the installed and recorded install info
                var moddedApp = getCorrectedInstallStatusAppIfPossible(
                  app,
                  installedInfo,
                );
                if (moddedApp != null) {
                  app = moddedApp;
                  // Note the app ID if it was uninstalled externally
                  if (moddedApp.installedVersion == null) {
                    removedAppIds.add(moddedApp.id);
                  }
                }
                // Update the app in memory with install info and corrections
                apps.update(
                  app.id,
                  (value) => AppInMemory(
                    app!,
                    value.downloadProgress,
                    installedInfo,
                    value.icon,
                  ),
                  ifAbsent: () => AppInMemory(app!, null, installedInfo, null),
                );
                notify();
              } catch (e) {
                errors.add([app!.id, app.finalName, e.toString()]);
              }
            }
          }),
    );
    if (errors.isNotEmpty) {
      removeApps(errors.map((e) => e[0]).toList());
      NotificationsProvider().notify(
        AppsRemovedNotification(errors.map((e) => [e[1], e[2]]).toList()),
      );
    }
    // Delete externally uninstalled Apps if needed
    if (removedAppIds.isNotEmpty &&
        settingsProvider.removeOnExternalUninstall) {
      await removeApps(removedAppIds);
    }
    loadingApps = false;
    notify();
  }

  Future<void> updateAppIcon(String? appId, {bool ignoreCache = false}) async {
    if (apps[appId]?.icon == null) {
      var cachedIcon = File('${iconsCacheDir.path}/$appId.png');
      var alreadyCached = cachedIcon.existsSync() && !ignoreCache;
      var icon = alreadyCached
          ? (await cachedIcon.readAsBytes())
          : (await apps[appId]?.installedInfo?.applicationInfo?.getAppIcon());
      if (icon != null && !alreadyCached) {
        cachedIcon.writeAsBytes(icon.toList());
      }
      if (icon != null) {
        apps.update(
          apps[appId]!.app.id,
          (value) => AppInMemory(
            apps[appId]!.app,
            value.downloadProgress,
            value.installedInfo,
            icon,
          ),
          ifAbsent: () => AppInMemory(
            apps[appId]!.app,
            null,
            apps[appId]?.installedInfo,
            icon,
          ),
        );
      }
    }
  }

  Future<void> saveApps(
    List<App> apps, {
    bool attemptToCorrectInstallStatus = true,
    bool onlyIfExists = true,
  }) async {
    await Future.wait(
      apps.map((a) async {
        var app = a.deepCopy();
        PackageInfo? info = await getInstalledInfo(app.id);
        var icon = await info?.applicationInfo?.getAppIcon();
        app.name = await (info?.applicationInfo?.getAppLabel()) ?? app.name;
        if (attemptToCorrectInstallStatus) {
          app = getCorrectedInstallStatusAppIfPossible(app, info) ?? app;
        }
        if (!onlyIfExists || this.apps.containsKey(app.id)) {
          String filePath = '${(await getAppsDir()).path}/${app.id}.json';
          File(
            '$filePath.tmp',
          ).writeAsStringSync(jsonEncode(app.toJson())); // #2089
          File('$filePath.tmp').renameSync(filePath);
        }
        try {
          this.apps.update(
            app.id,
            (value) => AppInMemory(app, value.downloadProgress, info, icon),
            ifAbsent: onlyIfExists
                ? null
                : () => AppInMemory(app, null, info, icon),
          );
        } catch (e) {
          if (e is! ArgumentError || e.name != 'key') {
            rethrow;
          }
        }
      }),
    );
    notify();
    export(isAuto: true);
  }

  Future<void> removeApps(List<String> appIds) async {
    var apkFiles = apkDir.listSync();
    await Future.wait(
      appIds.map((appId) async {
        File file = File('${(await getAppsDir()).path}/$appId.json');
        if (file.existsSync()) {
          deleteFile(file);
        }
        apkFiles
            .where(
              (element) => element.path.split('/').last.startsWith('$appId-'),
            )
            .forEach((element) {
              element.delete(recursive: true);
            });
        if (apps.containsKey(appId)) {
          apps.remove(appId);
        }
      }),
    );
    if (appIds.isNotEmpty) {
      notify();
      export(isAuto: true);
    }
  }

  Future<bool> removeAppsWithModal(BuildContext context, List<App> apps) async {
    var showUninstallOption = apps
        .where(
          (a) =>
              a.installedVersion != null &&
              a.additionalSettings['trackOnly'] != true,
        )
        .isNotEmpty;
    var values = await showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return GeneratedFormModal(
          primaryActionColour: Theme.of(context).colorScheme.error,
          title: plural('removeAppQuestion', apps.length),
          items: !showUninstallOption
              ? []
              : [
                  [
                    GeneratedFormSwitch(
                      'rmAppEntry',
                      label: tr('removeFromObtainium'),
                      defaultValue: true,
                    ),
                  ],
                  [
                    GeneratedFormSwitch(
                      'uninstallApp',
                      label: tr('uninstallFromDevice'),
                    ),
                  ],
                ],
          initValid: true,
        );
      },
    );
    if (values != null) {
      bool uninstall = values['uninstallApp'] == true && showUninstallOption;
      bool remove = values['rmAppEntry'] == true || !showUninstallOption;
      if (uninstall) {
        for (var i = 0; i < apps.length; i++) {
          if (apps[i].installedVersion != null) {
            uninstallApp(apps[i].id);
            apps[i].installedVersion = null;
          }
        }
        await saveApps(apps, attemptToCorrectInstallStatus: false);
      }
      if (remove) {
        await removeApps(apps.map((e) => e.id).toList());
      }
      return uninstall || remove;
    }
    return false;
  }

  Future<void> openAppSettings(String appId) async {
    final AndroidIntent intent = AndroidIntent(
      action: 'action_application_details_settings',
      data: 'package:$appId',
    );
    await intent.launch();
  }

  void addMissingCategories(SettingsProvider settingsProvider) {
    var cats = settingsProvider.categories;
    apps.forEach((key, value) {
      for (var c in value.app.categories) {
        if (!cats.containsKey(c)) {
          cats[c] = generateRandomLightColor().toARGB32();
        }
      }
    });
    settingsProvider.setCategories(cats, appsProvider: this);
  }
}
