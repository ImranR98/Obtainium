import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_package_manager/android_package_manager.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

/// App persistence (load/save/remove), icons, and version-detection helpers.
const _corruptFileSuffix = '.corrupt';

class VersionComparison {
  final bool areEqual;
  final String version;
  const VersionComparison({required this.areEqual, required this.version});
}

extension AppsProviderLifecycle on AppsProvider {
  bool _getNaiveStandardVersionDetection(App app) {
    var source = SourceProvider()
        .getSource(app.url, overrideSource: app.overrideSource);
    return app.additionalSettings['naiveStandardVersionDetection'] == true ||
        source.naiveStandardVersionDetection;
  }

  String? _getRealInstalledVersion(
      App app, PackageInfo? installedInfo) {
    if (installedInfo == null) return null;
    return app.additionalSettings['useVersionCodeAsOSVersion'] == true
        ? installedInfo.versionCode?.toString()
        : installedInfo.versionName;
  }

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
        _getNaiveStandardVersionDetection(app.app);
    String? realInstalledVersion =
        _getRealInstalledVersion(app.app, app.installedInfo);
    bool isHTMLWithNoVersionDetection =
        (source is HTML &&
        (app.app.additionalSettings['versionExtractionRegEx'] as String?)
                ?.isNotEmpty !=
            true);
    return app.app.additionalSettings['trackOnly'] != true &&
        app.app.additionalSettings['releaseDateAsVersion'] != true &&
        !isHTMLWithNoVersionDetection &&
        !source.versionDetectionDisallowed &&
        realInstalledVersion != null &&
        app.app.installedVersion != null &&
        (reconcileVersionDifferences(
                  realInstalledVersion,
                  app.app.installedVersion!,
                ) !=
                null ||
            naiveStandardVersionDetection);
  }

  /// Reconciles reported vs. real installed/latest versions for [app].
  /// Returns the modified app if any corrections were made, or null.
  App? getCorrectedInstallStatusAppIfPossible(
    App app,
    PackageInfo? installedInfo,
  ) {
    var modded = false;
    var trackOnly = app.additionalSettings['trackOnly'] == true;
    var versionDetectionIsStandard =
        app.additionalSettings['versionDetection'] == true;
    var naiveStandardVersionDetection =
        _getNaiveStandardVersionDetection(app);
    String? realInstalledVersion =
        _getRealInstalledVersion(app, installedInfo);
    // 1. Compare reported vs. real installed versions where one is null.
    if (installedInfo == null && app.installedVersion != null && !trackOnly) {
      app.installedVersion = null;
      modded = true;
    } else if (realInstalledVersion != null && app.installedVersion == null) {
      app.installedVersion = realInstalledVersion;
      modded = true;
    }
    // 2. Reconcile differences between reported and real installed versions.
    if (realInstalledVersion != null &&
        realInstalledVersion != app.installedVersion &&
        versionDetectionIsStandard) {
      // App's reported version and real version don't match (and it uses standard version detection)
      // If they share a standard format (and are still different under it), update the reported version accordingly
      var correctedInstalledVersion = reconcileVersionDifferences(
        realInstalledVersion,
        app.installedVersion!,
      );
      if (correctedInstalledVersion?.areEqual == false) {
        app.installedVersion = correctedInstalledVersion!.version;
        modded = true;
      } else if (naiveStandardVersionDetection) {
        app.installedVersion = realInstalledVersion;
        modded = true;
      }
    }
    // 3. Reconcile reported installed and latest versions.
    if (app.installedVersion != null &&
        app.installedVersion != app.latestVersion &&
        versionDetectionIsStandard) {
      // App's reported installed and latest versions don't match (and it uses standard version detection)
      // If they share a standard format, make sure the App's reported installed version uses that format
      var correctedInstalledVersion = reconcileVersionDifferences(
        app.installedVersion!,
        app.latestVersion,
      );
      if (correctedInstalledVersion?.areEqual == true) {
        app.installedVersion = correctedInstalledVersion!.version;
        modded = true;
      }
    }
    // 4. Disable version detection if versions are not standardizable.
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

  VersionComparison? reconcileVersionDifferences(
    String templateVersion,
    String comparisonVersion,
  ) {
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
        return VersionComparison(areEqual: true, version: comparisonVersion);
      }
    }
    return VersionComparison(areEqual: false, version: templateVersion);
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
    await waitForAppsToLoad();
    final loadingCompleter = Completer<void>();
    appsLoadingCompleter = loadingCompleter;
    loadingApps = true;
    notify();
    try {
      var sp = SourceProvider();
      List<List<String>> errors = [];
      var installedAppsData = await getAllInstalledInfo();
      Map<String, PackageInfo> installedAppsMap = {
        for (var i in installedAppsData)
          if (i.packageName != null) i.packageName!: i,
      };
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
                    jsonDecode(await File(item.path).readAsString()),
                  );
                } catch (err) {
                  logs.add(
                    'Error when loading App (will be ignored): $err',
                  );
                  if (err is FormatException) {
                    item.rename('${item.path}$_corruptFileSuffix');
                  }
                }
              }
              if (app != null) {
                apps.update(
                  app.id,
                  (value) => value.copyWith(app: app!),
                  ifAbsent: () => AppInMemory(app!, null, null, null),
                );
                try {
                  // Try getting the app's source to ensure no invalid apps get loaded
                  var src = sp.getSource(
                    app.url,
                    overrideSource: app.overrideSource,
                  );
                  var sourceType = src.name;
                  // If the app is installed, grab its OS data and reconcile install statuses
                  PackageInfo? installedInfo = installedAppsMap[app.id];
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
                    (value) => value.copyWith(
                      app: app!,
                      installedInfo: installedInfo,
                      sourceType: sourceType,
                    ),
                    ifAbsent: () => AppInMemory(
                      app!,
                      null,
                      installedInfo,
                      null,
                      sourceType: sourceType,
                    ),
                  );
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
    } finally {
      loadingApps = false;
      appsLoadingCompleter = null;
      loadingCompleter.complete();
      notify();
    }
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
          (value) => value.copyWith(icon: icon),
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

  /// Persists a list of [App] objects to disk as JSON files and updates in-memory state.
  Future<void> saveApps(
    List<App> apps, {
    bool attemptToCorrectInstallStatus = true,
    bool onlyIfExists = true,
  }) async {
    await Future.wait(
      apps.map((a) async {
        var app = a.deepCopy();
        PackageInfo? info;
        Uint8List? icon;
        if (attemptToCorrectInstallStatus) {
          info = await getInstalledInfo(app.id);
          icon = await info?.applicationInfo?.getAppIcon();
          app.name = await (info?.applicationInfo?.getAppLabel()) ?? app.name;
          app = getCorrectedInstallStatusAppIfPossible(app, info) ?? app;
        } else {
          info = null;
          icon = null;
        }
        if (!onlyIfExists || this.apps.containsKey(app.id)) {
          String filePath = '${(await getAppsDir()).path}/${app.id}.json';
          await File(
            '$filePath.tmp',
          ).writeAsString(jsonEncode(app.toJson())); // #2089
          await File('$filePath.tmp').rename(filePath);
        }
        if (this.apps.containsKey(app.id)) {
          this.apps[app.id] = this.apps[app.id]!.copyWith(
            app: app,
            installedInfo: info,
            icon: icon,
          );
        } else if (!onlyIfExists) {
          this.apps[app.id] = AppInMemory(app, null, info, icon);
        }
        if (info == null) {
          final cachedIcon = File('${iconsCacheDir.path}/${app.id}.png');
          if (cachedIcon.existsSync()) cachedIcon.deleteSync();
        }
      }),
    );
    notify();
    scheduleAutoExport();
  }

  /// Deletes app JSON files, cached APKs, and icons for the given app IDs, then updates state.
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
        final cachedIcon = File('${iconsCacheDir.path}/$appId.png');
        if (cachedIcon.existsSync()) cachedIcon.deleteSync();
        if (apps.containsKey(appId)) {
          apps.remove(appId);
        }
      }),
    );
    if (appIds.isNotEmpty) {
      notify();
      scheduleAutoExport();
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
      return remove;
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
    var cats = Map<String, int>.from(settingsProvider.categories);
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
