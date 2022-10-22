// Manages state related to the list of Apps tracked by Obtainium,
// Exposes related functions such as those used to add, remove, download, and install Apps.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:install_plugin_v2/install_plugin_v2.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:package_archive_info/package_archive_info.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_fgbg/flutter_fgbg.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:http/http.dart';

class AppInMemory {
  late App app;
  double? downloadProgress;
  AppInfo? installedInfo; // Also indicates that an App is installed

  AppInMemory(this.app, this.downloadProgress, this.installedInfo);
}

class DownloadedApp {
  String appId;
  File file;
  DownloadedApp(this.appId, this.file);
}

class AppsProvider with ChangeNotifier {
  // In memory App state (should always be kept in sync with local storage versions)
  Map<String, AppInMemory> apps = {};
  bool loadingApps = false;
  bool gettingUpdates = false;

  // Variables to keep track of the app foreground status (installs can't run in the background)
  bool isForeground = true;
  late Stream<FGBGType> foregroundStream;
  late StreamSubscription<FGBGType> foregroundSubscription;

  AppsProvider(
      {bool shouldLoadApps = false,
      bool shouldCheckUpdatesAfterLoad = false,
      bool shouldDeleteAPKs = false}) {
    // Subscribe to changes in the app foreground status
    foregroundStream = FGBGEvents.stream.asBroadcastStream();
    foregroundSubscription = foregroundStream.listen((event) async {
      isForeground = event == FGBGType.foreground;
      if (isForeground) await loadApps();
    });
    if (shouldLoadApps) {
      loadApps().then((_) {
        if (shouldDeleteAPKs) {
          deleteSavedAPKs();
        }
        if (shouldCheckUpdatesAfterLoad) {
          checkUpdates();
        }
      });
    }
  }

  downloadApk(String apkUrl, String fileName, Function? onProgress,
      Function? urlModifier,
      {bool useExistingIfExists = true}) async {
    var destDir = (await getExternalStorageDirectory())!.path;
    if (urlModifier != null) {
      apkUrl = await urlModifier(apkUrl);
    }
    StreamedResponse response =
        await Client().send(Request('GET', Uri.parse(apkUrl)));
    File downloadFile = File('$destDir/$fileName.apk');
    var alreadyExists = downloadFile.existsSync();
    if (!alreadyExists || !useExistingIfExists) {
      if (alreadyExists) {
        downloadFile.deleteSync();
      }

      var length = response.contentLength;
      var received = 0;
      double? progress;
      var sink = downloadFile.openWrite();

      await response.stream.map((s) {
        received += s.length;
        progress = (length != null ? received / length * 100 : 30);
        if (onProgress != null) {
          onProgress(progress);
        }
        return s;
      }).pipe(sink);

      await sink.close();
      progress = null;
      if (onProgress != null) {
        onProgress(progress);
      }

      if (response.statusCode != 200) {
        downloadFile.deleteSync();
        throw response.reasonPhrase ?? 'Unknown Error';
      }
    }
    return downloadFile;
  }

  // Downloads the App (preferred URL) and returns an ApkFile object
  // If the app was already saved, updates it's download progress % in memory
  // But also works for Apps that are not saved
  Future<DownloadedApp> downloadApp(App app) async {
    var fileName = '${app.id}-${app.latestVersion}-${app.preferredApkIndex}';
    File downloadFile = await downloadApk(app.apkUrls[app.preferredApkIndex],
        '${app.id}-${app.latestVersion}-${app.preferredApkIndex}',
        (double? progress) {
      if (apps[app.id] != null) {
        apps[app.id]!.downloadProgress = progress;
      }
      notifyListeners();
    }, SourceProvider().getSource(app.url).apkUrlPrefetchModifier);
    // Delete older versions of the APK if any
    for (var file in downloadFile.parent.listSync()) {
      var fn = file.path.split('/').last;
      if (fn.startsWith('${app.id}-') &&
          fn.endsWith('.apk') &&
          fn != '$fileName.apk') {
        file.delete();
      }
    }
    // If the ID has changed (as it should on first download), replace it
    var newInfo = await PackageArchiveInfo.fromPath(downloadFile.path);
    if (app.id != newInfo.packageName) {
      var originalAppId = app.id;
      app.id = newInfo.packageName;
      downloadFile = downloadFile.renameSync(
          '${downloadFile.parent.path}/${app.id}-${app.latestVersion}-${app.preferredApkIndex}.apk');
      if (apps[originalAppId] != null) {
        await removeApps([originalAppId]);
        await saveApps([app]);
      }
    }
    return DownloadedApp(app.id, downloadFile);
  }

  bool areDownloadsRunning() => apps.values
      .where((element) => element.downloadProgress != null)
      .isNotEmpty;

  Future<bool> canInstallSilently(App app) async {
    // TODO: This is unreliable - try to get from OS in the future
    var osInfo = await DeviceInfoPlugin().androidInfo;
    return app.installedVersion != null &&
        osInfo.version.sdkInt >= 30 &&
        osInfo.version.release.compareTo('12') >= 0;
  }

  Future<void> askUserToReturnToForeground(BuildContext context,
      {bool waitForFG = false}) async {
    NotificationsProvider notificationsProvider =
        context.read<NotificationsProvider>();
    if (!isForeground) {
      await notificationsProvider.notify(completeInstallationNotification,
          cancelExisting: true);
      if (waitForFG) {
        await FGBGEvents.stream.first == FGBGType.foreground;
        await notificationsProvider.cancel(completeInstallationNotification.id);
      }
    }
  }

  // Unfortunately this 'await' does not actually wait for the APK to finish installing
  // So we only know that the install prompt was shown, but the user could still cancel w/o us knowing
  // If appropriate criteria are met, the update (never a fresh install) happens silently  in the background
  // But even then, we don't know if it actually succeeded
  Future<void> installApk(DownloadedApp file) async {
    var newInfo = await PackageArchiveInfo.fromPath(file.file.path);
    AppInfo? appInfo;
    try {
      appInfo = await InstalledApps.getAppInfo(apps[file.appId]!.app.id);
    } catch (e) {
      // OK
    }
    if (appInfo != null &&
        int.parse(newInfo.buildNumber) < appInfo.versionCode!) {
      throw 'Can\'t install an older version';
    }
    if (appInfo == null ||
        int.parse(newInfo.buildNumber) > appInfo.versionCode!) {
      await InstallPlugin.installApk(file.file.path, 'dev.imranr.obtainium');
    }
    apps[file.appId]!.app.installedVersion =
        apps[file.appId]!.app.latestVersion;
    // Don't correct install status as installation may not be done yet
    await saveApps([apps[file.appId]!.app], dontCorrectInstallStatus: true);
  }

  Future<String?> selectApkUrl(App app, BuildContext? context) async {
    // If the App has more than one APK, the user should pick one (if context provided)
    String? apkUrl = app.apkUrls[app.preferredApkIndex];
    if (app.apkUrls.length > 1 && context != null) {
      apkUrl = await showDialog(
          context: context,
          builder: (BuildContext ctx) {
            return APKPicker(app: app, initVal: apkUrl);
          });
    }
    // If the picked APK comes from an origin different from the source, get user confirmation (if context provided)
    if (apkUrl != null &&
        Uri.parse(apkUrl).origin != Uri.parse(app.url).origin &&
        context != null) {
      if (await showDialog(
              context: context,
              builder: (BuildContext ctx) {
                return APKOriginWarningDialog(
                    sourceUrl: app.url, apkUrl: apkUrl!);
              }) !=
          true) {
        apkUrl = null;
      }
    }
    return apkUrl;
  }

  // Given a list of AppIds, uses stored info about the apps to download APKs and install them
  // If the APKs can be installed silently, they are
  // If no BuildContext is provided, apps that require user interaction are ignored
  // If user input is needed and the App is in the background, a notification is sent to get the user's attention
  // Returns an array of Ids for Apps that were successfully downloaded, regardless of installation result
  Future<List<String>> downloadAndInstallLatestApps(
      List<String> appIds, BuildContext? context) async {
    List<String> appsToInstall = [];
    for (var id in appIds) {
      if (apps[id] == null) {
        throw 'App not found';
      }

      String? apkUrl = await selectApkUrl(apps[id]!.app, context);

      if (apkUrl != null) {
        int urlInd = apps[id]!.app.apkUrls.indexOf(apkUrl);
        if (urlInd != apps[id]!.app.preferredApkIndex) {
          apps[id]!.app.preferredApkIndex = urlInd;
          await saveApps([apps[id]!.app]);
        }
        if (context != null ||
            (await canInstallSilently(apps[id]!.app) &&
                apps[id]!.app.apkUrls.length == 1)) {
          appsToInstall.add(id);
        }
      }
    }

    List<DownloadedApp> downloadedFiles = await Future.wait(
        appsToInstall.map((id) => downloadApp(apps[id]!.app)));

    List<DownloadedApp> silentUpdates = [];
    List<DownloadedApp> regularInstalls = [];
    for (var f in downloadedFiles) {
      bool willBeSilent = await canInstallSilently(apps[f.appId]!.app);
      if (willBeSilent) {
        silentUpdates.add(f);
      } else {
        regularInstalls.add(f);
      }
    }

    // If Obtainium is being installed, it should be the last one
    List<DownloadedApp> moveObtainiumToEnd(List<DownloadedApp> items) {
      String obtainiumId = 'imranr98_obtainium_${GitHub().host}';
      DownloadedApp? temp;
      items.removeWhere((element) {
        bool res = element.appId == obtainiumId;
        if (res) {
          temp = element;
        }
        return res;
      });
      if (temp != null) {
        items.add(temp!);
      }
      return items;
    }

    // TODO: Remove below line if silentupdates are ever figured out
    regularInstalls.addAll(silentUpdates);

    silentUpdates = moveObtainiumToEnd(silentUpdates);
    regularInstalls = moveObtainiumToEnd(regularInstalls);

    // TODO: Uncomment below if silentupdates are ever figured out
    // for (var u in silentUpdates) {
    //   await installApk(u, silent: true); // Would need to add silent option
    // }
    Map<String, List<String>> errors = {};
    if (context != null) {
      if (regularInstalls.isNotEmpty) {
        // ignore: use_build_context_synchronously
        await askUserToReturnToForeground(context, waitForFG: true);
      }
      for (var i in regularInstalls) {
        try {
          await installApk(i);
        } catch (e) {
          var tempIds = errors.remove(e.toString());
          tempIds ??= [];
          tempIds.add(i.appId);
          errors.putIfAbsent(e.toString(), () => tempIds!);
        }
      }
    }
    if (errors.isNotEmpty) {
      String finalError = '';
      for (var e in errors.keys) {
        finalError +=
            '$e ${errors[e]!.map((e) => apps[e]!.app.name).toString()}. ';
      }
      throw finalError;
    }

    return downloadedFiles.map((e) => e.appId).toList();
  }

  Future<Directory> getAppsDir() async {
    Directory appsDir = Directory(
        '${(await getExternalStorageDirectory())?.path as String}/app_data');
    if (!appsDir.existsSync()) {
      appsDir.createSync();
    }
    return appsDir;
  }

  // Delete all stored APKs except those likely to still be needed
  Future<void> deleteSavedAPKs() async {
    List<FileSystemEntity>? apks = (await getExternalStorageDirectory())
        ?.listSync()
        .where((element) => element.path.endsWith('.apk'))
        .toList();
    if (apks != null && apks.isNotEmpty) {
      for (var apk in apks) {
        var shouldDelete = true;
        var temp = apk.path.split('/').last;
        temp = temp.substring(0, temp.length - 4);
        var fn = temp.split('-');
        if (fn.length == 3) {
          var possibleId = fn[0];
          var possibleVersion = fn[1];
          var possibleApkUrlIndex = fn[2];
          if (apps[possibleId] != null) {
            if (apps[possibleId] != null &&
                apps[possibleId]?.app != null &&
                apps[possibleId]!.app.installedVersion !=
                    apps[possibleId]!.app.latestVersion &&
                apps[possibleId]!.app.latestVersion == possibleVersion &&
                apps[possibleId]!.app.preferredApkIndex.toString() ==
                    possibleApkUrlIndex) {
              shouldDelete = false;
            }
          }
        }

        if (shouldDelete) apk.delete();
      }
    }
  }

  Future<AppInfo?> getInstalledInfo(String? packageName) async {
    if (packageName != null) {
      try {
        return await InstalledApps.getAppInfo(packageName);
      } catch (e) {
        // OK
      }
    }
    return null;
  }

  String standardizeVersionString(String versionString) {
    return versionString.characters
        .where((p0) => ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.']
            .contains(p0))
        .join('');
  }

  // If the App says it is installed by installedInfo is null, set it to not installed
  // If the App says is is not installed but installedInfo exists, try to set it to installed as latest version...
  // ...if the latestVersion seems to match the version in installedInfo (not guaranteed)
  App? correctInstallStatus(App app, AppInfo? installedInfo) {
    var modded = false;
    if (installedInfo == null && app.installedVersion != null) {
      app.installedVersion = null;
      modded = true;
    }
    if (installedInfo != null && app.installedVersion == null) {
      if (standardizeVersionString(app.latestVersion) ==
          installedInfo.versionName) {
        app.installedVersion = app.latestVersion;
      } else {
        app.installedVersion = installedInfo.versionName;
      }
      modded = true;
    }
    return modded ? app : null;
  }

  Future<void> loadApps() async {
    loadingApps = true;
    notifyListeners();
    List<FileSystemEntity> appFiles = (await getAppsDir())
        .listSync()
        .where((item) => item.path.toLowerCase().endsWith('.json'))
        .toList();
    apps.clear();
    var sp = SourceProvider();
    List<List<String>> errors = [];
    for (int i = 0; i < appFiles.length; i++) {
      App app =
          App.fromJson(jsonDecode(File(appFiles[i].path).readAsStringSync()));
      var info = await getInstalledInfo(app.id);
      try {
        sp.getSource(app.url);
        apps.putIfAbsent(app.id, () => AppInMemory(app, null, info));
      } catch (e) {
        errors.add([app.id, app.name, e.toString()]);
      }
    }
    if (errors.isNotEmpty) {
      removeApps(errors.map((e) => e[0]).toList());
      NotificationsProvider().notify(
          AppsRemovedNotification(errors.map((e) => [e[1], e[2]]).toList()));
    }
    loadingApps = false;
    notifyListeners();
    // For any that are not installed (by ID == package name), set to not installed if needed
    refreshInstalledAppInfo();
  }

  refreshInstalledAppInfo({List<String>? appIds}) {
    List<App> modifiedApps = [];
    appIds ??= apps.values.map((e) => e.app.id).toList();
    for (var id in appIds) {
      var moddedApp =
          correctInstallStatus(apps[id]!.app, apps[id]!.installedInfo);
      if (moddedApp != null) {
        modifiedApps.add(moddedApp);
      }
    }
    if (modifiedApps.isNotEmpty) {
      saveApps(modifiedApps, dontCorrectInstallStatus: true);
    }
  }

  Future<void> saveApps(List<App> apps,
      {bool dontCorrectInstallStatus = false}) async {
    for (var app in apps) {
      var info = await getInstalledInfo(app.id);
      app.name = info?.name ?? app.name;
      if (!dontCorrectInstallStatus) {
        app = correctInstallStatus(app, info) ?? app;
      }
      File('${(await getAppsDir()).path}/${app.id}.json')
          .writeAsStringSync(jsonEncode(app.toJson()));
      this.apps.update(
          app.id, (value) => AppInMemory(app, value.downloadProgress, info),
          ifAbsent: () => AppInMemory(app, null, info));
    }
    notifyListeners();
  }

  Future<void> removeApps(List<String> appIds) async {
    for (var appId in appIds) {
      File file = File('${(await getAppsDir()).path}/$appId.json');
      if (file.existsSync()) {
        file.deleteSync();
      }
      if (apps.containsKey(appId)) {
        apps.remove(appId);
      }
    }
    if (appIds.isNotEmpty) {
      notifyListeners();
    }
  }

  bool checkAppObjectForUpdate(App app) {
    if (!apps.containsKey(app.id)) {
      throw 'App not found';
    }
    return app.latestVersion != apps[app.id]?.app.installedVersion;
  }

  Future<App?> getUpdate(String appId) async {
    App? currentApp = apps[appId]!.app;
    SourceProvider sourceProvider = SourceProvider();
    App newApp = await sourceProvider.getApp(
        sourceProvider.getSource(currentApp.url),
        currentApp.url,
        currentApp.additionalData,
        name: currentApp.name,
        id: currentApp.id);
    newApp.installedVersion = currentApp.installedVersion;
    if (currentApp.preferredApkIndex < newApp.apkUrls.length) {
      newApp.preferredApkIndex = currentApp.preferredApkIndex;
    }
    await saveApps([newApp]);
    return newApp.latestVersion != currentApp.latestVersion ? newApp : null;
  }

  Future<List<App>> checkUpdates(
      {DateTime? ignoreAfter,
      bool immediatelyThrowRateLimitError = false}) async {
    List<App> updates = [];
    Map<String, List<String>> errors = {};
    if (!gettingUpdates) {
      gettingUpdates = true;

      List<String> appIds = apps.keys.toList();
      if (ignoreAfter != null) {
        appIds = appIds
            .where((id) =>
                apps[id]!.app.lastUpdateCheck == null ||
                apps[id]!.app.lastUpdateCheck!.isBefore(ignoreAfter))
            .toList();
      }
      appIds.sort((a, b) => (apps[a]!.app.lastUpdateCheck ??
              DateTime.fromMicrosecondsSinceEpoch(0))
          .compareTo(apps[b]!.app.lastUpdateCheck ??
              DateTime.fromMicrosecondsSinceEpoch(0)));

      for (int i = 0; i < appIds.length; i++) {
        App? newApp;
        try {
          newApp = await getUpdate(appIds[i]);
        } catch (e) {
          if (e is RateLimitError && immediatelyThrowRateLimitError) {
            rethrow;
          }
          var tempIds = errors.remove(e.toString());
          tempIds ??= [];
          tempIds.add(appIds[i]);
          errors.putIfAbsent(e.toString(), () => tempIds!);
        }
        if (newApp != null) {
          updates.add(newApp);
        }
      }
      gettingUpdates = false;
    }
    if (errors.isNotEmpty) {
      String finalError = '';
      for (var e in errors.keys) {
        finalError +=
            '$e ${errors[e]!.map((e) => apps[e]!.app.name).toString()}. ';
      }
      throw finalError;
    }
    return updates;
  }

  List<String> getExistingUpdates(
      {bool installedOnly = false, bool nonInstalledOnly = false}) {
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

  Future<String> exportApps() async {
    Directory? exportDir = Directory('/storage/emulated/0/Download');
    String path = 'Downloads';
    if (!exportDir.existsSync()) {
      exportDir = await getExternalStorageDirectory();
      path = exportDir!.path;
    }
    File export = File(
        '${exportDir.path}/obtainium-export-${DateTime.now().millisecondsSinceEpoch}.json');
    export.writeAsStringSync(
        jsonEncode(apps.values.map((e) => e.app.toJson()).toList()));
    return path;
  }

  Future<int> importApps(String appsJSON) async {
    // File picker does not work in android 13, so the user must paste the JSON directly into Obtainium to import Apps
    List<App> importedApps = (jsonDecode(appsJSON) as List<dynamic>)
        .map((e) => App.fromJson(e))
        .toList();
    for (App a in importedApps) {
      a.installedVersion =
          apps.containsKey(a.id) ? apps[a]?.app.installedVersion : null;
    }
    await saveApps(importedApps);
    notifyListeners();
    return importedApps.length;
  }

  @override
  void dispose() {
    foregroundSubscription.cancel();
    super.dispose();
  }
}

class APKPicker extends StatefulWidget {
  const APKPicker({super.key, required this.app, this.initVal});

  final App app;
  final String? initVal;

  @override
  State<APKPicker> createState() => _APKPickerState();
}

class _APKPickerState extends State<APKPicker> {
  String? apkUrl;

  @override
  Widget build(BuildContext context) {
    apkUrl ??= widget.initVal;
    return AlertDialog(
      scrollable: true,
      title: const Text('Pick an APK'),
      content: Column(children: [
        Text('${widget.app.name} has more than one package:'),
        const SizedBox(height: 16),
        ...widget.app.apkUrls.map((u) => RadioListTile<String>(
            title: Text(Uri.parse(u)
                .pathSegments
                .where((element) => element.isNotEmpty)
                .last),
            value: u,
            groupValue: apkUrl,
            onChanged: (String? val) {
              setState(() {
                apkUrl = val;
              });
            }))
      ]),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop(null);
            },
            child: const Text('Cancel')),
        TextButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(apkUrl);
            },
            child: const Text('Continue'))
      ],
    );
  }
}

class APKOriginWarningDialog extends StatefulWidget {
  const APKOriginWarningDialog(
      {super.key, required this.sourceUrl, required this.apkUrl});

  final String sourceUrl;
  final String apkUrl;

  @override
  State<APKOriginWarningDialog> createState() => _APKOriginWarningDialogState();
}

class _APKOriginWarningDialogState extends State<APKOriginWarningDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Warning'),
      content: Text(
          'The App source is \'${Uri.parse(widget.sourceUrl).host}\' but the release package comes from \'${Uri.parse(widget.apkUrl).host}\'. Continue?'),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop(null);
            },
            child: const Text('Cancel')),
        TextButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(true);
            },
            child: const Text('Continue'))
      ],
    );
  }
}
