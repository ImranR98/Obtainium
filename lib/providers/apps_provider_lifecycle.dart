import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_package_manager/android_package_manager.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:path_provider/path_provider.dart';

/// App persistence (load/save/remove), icons, and version-detection helpers.
const _corruptFileSuffix = '.corrupt';

class VersionComparison {
  final bool areEqual;
  final String version;
  const VersionComparison({required this.areEqual, required this.version});
}

extension AppsProviderLifecycle on AppsProvider {
  bool _getNaiveStandardVersionDetection(App app) {
    final source = SourceProvider().getSource(
      app.url,
      overrideSource: app.overrideSource,
    );
    return app.settings.getBool('naiveStandardVersionDetection') ||
        source.naiveStandardVersionDetection;
  }

  String? _getRealInstalledVersion(App app, PackageInfo? installedInfo) {
    if (installedInfo == null) return null;
    return app.settings.getBool('useVersionCodeAsOSVersion')
        ? installedInfo.versionCode?.toString()
        : installedInfo.versionName;
  }

  Future<Directory> getAppsDir() async {
    final Directory appsDir = Directory(
      '${(await getAppStorageDir()).path}/app_data',
    );
    if (!appsDir.existsSync()) {
      try {
        appsDir.createSync();
      } catch (_) {
        final fallbackDir = Directory(
          '${(await getApplicationDocumentsDirectory()).path}/app_data',
        );
        if (!fallbackDir.existsSync()) {
          fallbackDir.createSync(recursive: true);
        }
        return fallbackDir;
      }
    }
    return appsDir;
  }

  bool isVersionDetectionPossible(AppInMemory? app) {
    if (app?.app == null) {
      return false;
    }
    final source = SourceProvider().getSource(
      app!.app.url,
      overrideSource: app.app.overrideSource,
    );
    final naiveStandardVersionDetection = _getNaiveStandardVersionDetection(
      app.app,
    );
    final String? realInstalledVersion = _getRealInstalledVersion(
      app.app,
      app.installedInfo,
    );
    final bool isHTMLWithNoVersionDetection =
        (source is HTML &&
        app.app.settings
                .getStringOrNull('versionExtractionRegEx')
                ?.isNotEmpty !=
            true);
    return !app.app.settings.getBool('trackOnly') &&
        !app.app.settings.getBool('releaseDateAsVersion') &&
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
    final trackOnly = app.settings.getBool('trackOnly');
    final versionDetectionIsStandard = app.settings.getBool('versionDetection');
    final naiveStandardVersionDetection = _getNaiveStandardVersionDetection(
      app,
    );
    final String? realInstalledVersion = _getRealInstalledVersion(
      app,
      installedInfo,
    );
    // 1. Compare reported vs. real installed versions where one is null.
    if (installedInfo == null && app.installedVersion != null && !trackOnly) {
      app = app.copyWith(installedVersion: null);
      modded = true;
    } else if (realInstalledVersion != null && app.installedVersion == null) {
      app = app.copyWith(installedVersion: realInstalledVersion);
      modded = true;
    }
    // 2. Reconcile differences between reported and real installed versions.
    if (realInstalledVersion != null &&
        realInstalledVersion != app.installedVersion &&
        versionDetectionIsStandard) {
      // App's reported version and real version don't match (and it uses standard version detection)
      // If they share a standard format (and are still different under it), update the reported version accordingly
      final correctedInstalledVersion = reconcileVersionDifferences(
        realInstalledVersion,
        app.installedVersion!,
      );
      if (correctedInstalledVersion?.areEqual == false) {
        app = app.copyWith(
          installedVersion: correctedInstalledVersion!.version,
        );
        modded = true;
      } else if (naiveStandardVersionDetection) {
        app = app.copyWith(installedVersion: realInstalledVersion);
        modded = true;
      }
    }
    // 3. Reconcile reported installed and latest versions.
    if (app.installedVersion != null &&
        app.installedVersion != app.latestVersion &&
        versionDetectionIsStandard) {
      // App's reported installed and latest versions don't match (and it uses standard version detection)
      // If they share a standard format, make sure the App's reported installed version uses that format
      final correctedInstalledVersion = reconcileVersionDifferences(
        app.installedVersion!,
        app.latestVersion,
      );
      if (correctedInstalledVersion?.areEqual == true) {
        app = app.copyWith(
          installedVersion: correctedInstalledVersion!.version,
        );
        modded = true;
      }
    }
    // 4. Disable version detection if versions are not standardizable.
    if (installedInfo != null &&
        versionDetectionIsStandard &&
        !isVersionDetectionPossible(
          AppInMemory(app, null, installedInfo, null),
        )) {
      app = app.copyWith(
        additionalSettings: Map<String, dynamic>.from(app.additionalSettings)
          ..['versionDetection'] = false,
        installedVersion: app.latestVersion,
      );
      unawaited(logs.add('Could not reconcile version formats for: ${app.id}'));
      modded = true;
    }

    return modded ? app : null;
  }

  VersionComparison? reconcileVersionDifferences(
    String templateVersion,
    String comparisonVersion,
  ) {
    final templateVersionFormats = VersionService()
        .findStandardFormatsForVersion(templateVersion, true);
    var comparisonVersionFormats = VersionService()
        .findStandardFormatsForVersion(comparisonVersion, true);
    if (comparisonVersionFormats.isEmpty) {
      comparisonVersionFormats = VersionService().findStandardFormatsForVersion(
        comparisonVersion,
        false,
      );
    }
    final commonStandardFormats = templateVersionFormats.intersection(
      comparisonVersionFormats,
    );
    if (commonStandardFormats.isEmpty) {
      return null;
    }
    for (String pattern in commonStandardFormats) {
      if (VersionService().doStringsMatchUnderRegEx(
        pattern,
        comparisonVersion,
        templateVersion,
      )) {
        return VersionComparison(areEqual: true, version: comparisonVersion);
      }
    }
    return VersionComparison(areEqual: false, version: templateVersion);
  }

  /// Delegates to [VersionService.doStringsMatchUnderRegEx].
  bool doStringsMatchUnderRegEx(String pattern, String value1, String value2) =>
      VersionService().doStringsMatchUnderRegEx(pattern, value1, value2);

  Future<void> loadApps({String? singleId}) async {
    await waitForAppsToLoad();
    appsLoadingCompleter = Completer<void>();
    loadingApps = true;
    notify();
    try {
      final sp = SourceProvider();
      final List<List<String>> errors = [];
      final installedAppsData = await getAllInstalledInfo();
      final Map<String, PackageInfo> installedAppsMap = {
        for (var i in installedAppsData)
          if (i.packageName != null) i.packageName!: i,
      };
      final List<String> removedAppIds = [];
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
                  if (err is FormatException) {
                    // Genuinely corrupt JSON: set it aside so it stops failing.
                    unawaited(
                      logs.add(
                        'Corrupt JSON, renaming ${item.path}: $err',
                        level: LogLevel.error,
                      ),
                    );
                    unawaited(item.rename('${item.path}$_corruptFileSuffix'));
                  } else {
                    // Other errors (e.g. a temporarily unresolvable source):
                    // skip but keep the file so it can load once resolved.
                    unawaited(
                      logs.add(
                        'Error loading app ${item.path} (skipped, file kept): $err',
                        level: LogLevel.warning,
                      ),
                    );
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
                  final src = sp.getSource(
                    app.url,
                    overrideSource: app.overrideSource,
                  );
                  final sourceType = src.name;
                  // If the app is installed, grab its OS data and reconcile install statuses
                  final PackageInfo? installedInfo = installedAppsMap[app.id];
                  // Reconcile differences between the installed and recorded install info
                  final moddedApp = getCorrectedInstallStatusAppIfPossible(
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
                  if (e is RateLimitError || e is SocketException) {
                    unawaited(
                      logs.add(
                        'Transient error loading app ${app!.id}, will retry: $e',
                      ),
                    );
                  } else {
                    errors.add([app!.id, app.finalName, e.toString()]);
                  }
                }
              }
            }),
      );
      if (errors.isNotEmpty) {
        for (var error in errors) {
          unawaited(
            logs.add(
              'Removing app ${error[0]} (${error[1]}) due to load error: ${error[2]}',
              level: LogLevel.error,
            ),
          );
        }
        unawaited(removeApps(errors.map((e) => e[0]).toList()));
        unawaited(
          NotificationsProvider().notify(
            AppsRemovedNotification(errors.map((e) => [e[1], e[2]]).toList()),
          ),
        );
      }
      // Delete externally uninstalled Apps if needed
      if (removedAppIds.isNotEmpty &&
          settingsProvider.removeOnExternalUninstall) {
        await removeApps(removedAppIds);
      }
    } finally {
      loadingApps = false;
      appsLoadingCompleter?.complete();
      appsLoadingCompleter = null;
      notify();
    }
    if (!isBg && apps.isNotEmpty) {
      unawaited(
        Future(() async {
          for (final entry in apps.entries.toList()) {
            await updateAppIcon(entry.key);
            await Future<void>.delayed(Duration.zero);
          }
          notify();
        }),
      );
    }
  }

  Future<void> updateAppIcon(String? appId, {bool ignoreCache = false}) async {
    if (apps[appId]?.icon == null) {
      final cachedIcon = File('${iconsCacheDir.path}/$appId.png');
      final alreadyCached = cachedIcon.existsSync() && !ignoreCache;
      final icon = alreadyCached
          ? (await cachedIcon.readAsBytes())
          : (await apps[appId]?.installedInfo?.applicationInfo?.getAppIcon());
      if (icon != null && !alreadyCached) {
        unawaited(cachedIcon.writeAsBytes(icon));
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
        var app = a.copyWith();
        final PackageInfo? info = await getInstalledInfo(app.id);
        final Uint8List? icon = await info?.applicationInfo?.getAppIcon();
        app = app.copyWith(
          name: await (info?.applicationInfo?.getAppLabel()) ?? app.name,
        );
        if (attemptToCorrectInstallStatus) {
          app = getCorrectedInstallStatusAppIfPossible(app, info) ?? app;
        }
        if (!onlyIfExists || this.apps.containsKey(app.id)) {
          final String filePath = '${(await getAppsDir()).path}/${app.id}.json';
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
    final apkFiles = apkDir.listSync();
    await Future.wait(
      appIds.map((appId) async {
        final File file = File('${(await getAppsDir()).path}/$appId.json');
        if (file.existsSync()) {
          deleteFile(file);
        }
        await Future.wait(
          apkFiles
              .where(
                (element) => element.path.split('/').last.startsWith('$appId-'),
              )
              .map((element) => element.delete(recursive: true)),
        );
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
    final showUninstallOption = apps
        .where(
          (a) => a.installedVersion != null && !a.settings.getBool('trackOnly'),
        )
        .isNotEmpty;
    final values = await showDialog(
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
                      value: true,
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
      final bool uninstall =
          values['uninstallApp'] == true && showUninstallOption;
      final bool remove = values['rmAppEntry'] == true || !showUninstallOption;
      if (uninstall) {
        for (var i = 0; i < apps.length; i++) {
          if (apps[i].installedVersion != null) {
            await uninstallApp(apps[i].id);
            apps[i] = apps[i].copyWith(installedVersion: null);
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
    final cats = Map<String, int>.from(settingsProvider.categories);
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
