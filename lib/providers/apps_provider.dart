// Manages state related to the list of Apps tracked by Obtainium,
// Exposes related functions such as those used to add, remove, download, and install Apps.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:install_plugin_v2/install_plugin_v2.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:package_archive_info/package_archive_info.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_fgbg/flutter_fgbg.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:http/http.dart';

class AppInMemory {
  late App app;
  double? downloadProgress;
  AppInfo? installedInfo;

  AppInMemory(this.app, this.downloadProgress, this.installedInfo);
}

class DownloadedApk {
  String appId;
  File file;
  DownloadedApk(this.appId, this.file);
}

List<String> generateStandardVersionRegExStrings() {
  // TODO: Look into RegEx for non-Latin characters / non-Arabic numerals
  var basics = [
    '[0-9]+',
    '[0-9]+\\.[0-9]+',
    '[0-9]+\\.[0-9]+\\.[0-9]+',
    '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+'
  ];
  var preSuffixes = ['-', '\\+'];
  var suffixes = ['alpha', 'beta', 'ose'];
  var finals = ['\\+[0-9]+', '[0-9]+'];
  List<String> results = [];
  for (var b in basics) {
    results.add(b);
    for (var p in preSuffixes) {
      for (var s in suffixes) {
        results.add('$b$s');
        results.add('$b$p$s');
        for (var f in finals) {
          results.add('$b$s$f');
          results.add('$b$p$s$f');
        }
      }
    }
  }
  return results;
}

List<String> standardVersionRegExStrings =
    generateStandardVersionRegExStrings();

class AppsProvider with ChangeNotifier {
  // In memory App state (should always be kept in sync with local storage versions)
  Map<String, AppInMemory> apps = {};
  bool loadingApps = false;
  bool gettingUpdates = false;
  LogsProvider logs = LogsProvider();

  // Variables to keep track of the app foreground status (installs can't run in the background)
  bool isForeground = true;
  late Stream<FGBGType>? foregroundStream;
  late StreamSubscription<FGBGType>? foregroundSubscription;

  AppsProvider() {
    // Subscribe to changes in the app foreground status
    foregroundStream = FGBGEvents.stream.asBroadcastStream();
    foregroundSubscription = foregroundStream?.listen((event) async {
      isForeground = event == FGBGType.foreground;
      if (isForeground) await loadApps();
    });
    () async {
      // Load Apps into memory (in background, this is done later instead of in the constructor)
      await loadApps();
      // Delete existing APKs
      (await getExternalStorageDirectory())
          ?.listSync()
          .where((element) =>
              element.path.endsWith('.apk') ||
              element.path.endsWith('.apk.part'))
          .forEach((apk) {
        apk.delete();
      });
    }();
  }

  downloadFile(String url, String fileName, Function? onProgress,
      {bool useExisting = true}) async {
    var destDir = (await getExternalStorageDirectory())!.path;
    StreamedResponse response =
        await Client().send(Request('GET', Uri.parse(url)));
    File downloadedFile = File('$destDir/$fileName');
    if (!(downloadedFile.existsSync() && useExisting)) {
      File tempDownloadedFile = File('${downloadedFile.path}.part');
      if (tempDownloadedFile.existsSync()) {
        tempDownloadedFile.deleteSync();
      }
      var length = response.contentLength;
      var received = 0;
      double? progress;
      var sink = tempDownloadedFile.openWrite();
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
        tempDownloadedFile.deleteSync();
        throw response.reasonPhrase ?? tr('unexpectedError');
      }
      tempDownloadedFile.renameSync(downloadedFile.path);
    }
    return downloadedFile;
  }

  Future<DownloadedApk> downloadApp(App app, BuildContext? context) async {
    var fileName =
        '${app.id}-${app.latestVersion}-${app.preferredApkIndex}.apk';
    String downloadUrl = await SourceProvider()
        .getSource(app.url)
        .apkUrlPrefetchModifier(app.apkUrls[app.preferredApkIndex]);
    NotificationsProvider? notificationsProvider =
        context?.read<NotificationsProvider>();
    var notif = DownloadNotification(app.name, 100);
    notificationsProvider?.cancel(notif.id);
    int? prevProg;
    File downloadedFile =
        await downloadFile(downloadUrl, fileName, (double? progress) {
      int? prog = progress?.ceil();
      if (apps[app.id] != null) {
        apps[app.id]!.downloadProgress = progress;
        notifyListeners();
      }
      notif = DownloadNotification(app.name, prog ?? 100);
      if (prog != null && prevProg != prog) {
        notificationsProvider?.notify(notif);
      }
      prevProg = prog;
    });
    notificationsProvider?.cancel(notif.id);
    // Delete older versions of the APK if any
    for (var file in downloadedFile.parent.listSync()) {
      var fn = file.path.split('/').last;
      if (fn.startsWith('${app.id}-') &&
          fn.endsWith('.apk') &&
          fn != fileName) {
        file.delete();
      }
    }
    // If the APK package ID is different from the App ID, it is either new (using a placeholder ID) or the ID has changed
    // The former case should be handled (give the App its real ID), the latter is a security issue
    var newInfo = await PackageArchiveInfo.fromPath(downloadedFile.path);
    if (app.id != newInfo.packageName) {
      if (apps[app.id] != null && !SourceProvider().isTempId(app.id)) {
        throw IDChangedError();
      }
      var originalAppId = app.id;
      app.id = newInfo.packageName;
      downloadedFile = downloadedFile.renameSync(
          '${downloadedFile.parent.path}/${app.id}-${app.latestVersion}-${app.preferredApkIndex}.apk');
      if (apps[originalAppId] != null) {
        await removeApps([originalAppId]);
        await saveApps([app]);
      }
    }
    return DownloadedApk(app.id, downloadedFile);
  }

  bool areDownloadsRunning() => apps.values
      .where((element) => element.downloadProgress != null)
      .isNotEmpty;

  Future<bool> canInstallSilently(App app) async {
    return false;
    // TODO: Uncomment the below if silent updates are ever figured out
    // // NOTE: This is unreliable - try to get from OS in the future
    // if (app.apkUrls.length > 1) {
    //    return false;
    // }
    // var osInfo = await DeviceInfoPlugin().androidInfo;
    // return app.installedVersion != null &&
    //     osInfo.version.sdkInt >= 30 &&
    //     osInfo.version.release.compareTo('12') >= 0;
  }

  Future<void> waitForUserToReturnToForeground(BuildContext context) async {
    NotificationsProvider notificationsProvider =
        context.read<NotificationsProvider>();
    if (!isForeground) {
      await notificationsProvider.notify(completeInstallationNotification,
          cancelExisting: true);
      while (await FGBGEvents.stream.first != FGBGType.foreground) {}
      await notificationsProvider.cancel(completeInstallationNotification.id);
    }
  }

  Future<bool> canDowngradeApps() async {
    try {
      await InstalledApps.getAppInfo('com.berdik.letmedowngrade');
      return true;
    } catch (e) {
      return false;
    }
  }

  // Unfortunately this 'await' does not actually wait for the APK to finish installing
  // So we only know that the install prompt was shown, but the user could still cancel w/o us knowing
  // If appropriate criteria are met, the update (never a fresh install) happens silently  in the background
  // But even then, we don't know if it actually succeeded
  Future<void> installApk(DownloadedApk file) async {
    var newInfo = await PackageArchiveInfo.fromPath(file.file.path);
    AppInfo? appInfo;
    try {
      appInfo = await InstalledApps.getAppInfo(apps[file.appId]!.app.id);
    } catch (e) {
      // OK
    }
    if (appInfo != null &&
        int.parse(newInfo.buildNumber) < appInfo.versionCode! &&
        !(await canDowngradeApps())) {
      throw DowngradeError();
    }
    if (appInfo == null ||
        int.parse(newInfo.buildNumber) > appInfo.versionCode!) {
      await InstallPlugin.installApk(file.file.path, 'dev.imranr.obtainium');
    }
    apps[file.appId]!.app.installedVersion =
        apps[file.appId]!.app.latestVersion;
    // Don't correct install status as installation may not be done yet
    await saveApps([apps[file.appId]!.app],
        attemptToCorrectInstallStatus: false);
  }

  Future<String?> confirmApkUrl(App app, BuildContext? context) async {
    // If the App has more than one APK, the user should pick one (if context provided)
    String? apkUrl = app.apkUrls[app.preferredApkIndex];
    // get device supported architecture
    List<String> archs = (await DeviceInfoPlugin().androidInfo).supportedAbis;

    if (app.apkUrls.length > 1 && context != null) {
      apkUrl = await showDialog(
          context: context,
          builder: (BuildContext ctx) {
            return APKPicker(
              app: app,
              initVal: apkUrl,
              archs: archs,
            );
          });
    }
    getHost(String url) {
      var temp = Uri.parse(url).host.split('.');
      return temp.sublist(temp.length - 2).join('.');
    }

    // If the picked APK comes from an origin different from the source, get user confirmation (if context provided)
    if (apkUrl != null &&
        getHost(apkUrl) != getHost(app.url) &&
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
    List<String> trackOnlyAppsToUpdate = [];
    // For all specified Apps, filter out those for which:
    // 1. A URL cannot be picked
    // 2. That cannot be installed silently (IF no buildContext was given for interactive install)
    for (var id in appIds) {
      if (apps[id] == null) {
        throw ObtainiumError(tr('appNotFound'));
      }
      String? apkUrl;
      var trackOnly = apps[id]!.app.additionalSettings['trackOnly'] == true;
      if (!trackOnly) {
        apkUrl = await confirmApkUrl(apps[id]!.app, context);
      }
      if (apkUrl != null) {
        int urlInd = apps[id]!.app.apkUrls.indexOf(apkUrl);
        if (urlInd != apps[id]!.app.preferredApkIndex) {
          apps[id]!.app.preferredApkIndex = urlInd;
          await saveApps([apps[id]!.app]);
        }
        if (context != null || await canInstallSilently(apps[id]!.app)) {
          appsToInstall.add(id);
        }
      }
      if (trackOnly) {
        trackOnlyAppsToUpdate.add(id);
      }
    }
    // Mark all specified track-only apps as latest
    saveApps(trackOnlyAppsToUpdate.map((e) {
      var a = apps[e]!.app;
      a.installedVersion = a.latestVersion;
      return a;
    }).toList());
    // Download APKs for all Apps to be installed
    MultiAppMultiError errors = MultiAppMultiError();
    List<DownloadedApk?> downloadedFiles =
        await Future.wait(appsToInstall.map((id) async {
      try {
        return await downloadApp(apps[id]!.app, context);
      } catch (e) {
        errors.add(id, e.toString());
      }
      return null;
    }));
    downloadedFiles =
        downloadedFiles.where((element) => element != null).toList();
    // Separate the Apps to install into silent and regular lists
    List<DownloadedApk> silentUpdates = [];
    List<DownloadedApk> regularInstalls = [];
    for (var f in downloadedFiles) {
      bool willBeSilent = await canInstallSilently(apps[f!.appId]!.app);
      if (willBeSilent) {
        silentUpdates.add(f);
      } else {
        regularInstalls.add(f);
      }
    }

    // Move everything to the regular install list (since silent updates don't currently work)
    // TODO: Remove this when silent updates work
    regularInstalls.addAll(silentUpdates);

    // If Obtainium is being installed, it should be the last one
    List<DownloadedApk> moveObtainiumToStart(List<DownloadedApk> items) {
      DownloadedApk? temp;
      items.removeWhere((element) {
        bool res =
            element.appId == obtainiumId || element.appId == obtainiumTempId;
        if (res) {
          temp = element;
        }
        return res;
      });
      if (temp != null) {
        items = [temp!, ...items];
      }
      return items;
    }

    silentUpdates = moveObtainiumToStart(silentUpdates);
    regularInstalls = moveObtainiumToStart(regularInstalls);

    // // Install silent updates (uncomment when it works - TODO)
    // for (var u in silentUpdates) {
    //   await installApk(u, silent: true); // Would need to add silent option
    // }

    // Do regular installs
    if (regularInstalls.isNotEmpty && context != null) {
      // ignore: use_build_context_synchronously
      await waitForUserToReturnToForeground(context);
      for (var i in regularInstalls) {
        try {
          await installApk(i);
        } catch (e) {
          errors.add(i.appId, e.toString());
        }
      }
    }

    if (errors.content.isNotEmpty) {
      throw errors;
    }

    NotificationsProvider().cancel(UpdateNotification([]).id);

    return downloadedFiles.map((e) => e!.appId).toList();
  }

  Future<Directory> getAppsDir() async {
    Directory appsDir = Directory(
        '${(await getExternalStorageDirectory())?.path as String}/app_data');
    if (!appsDir.existsSync()) {
      appsDir.createSync();
    }
    return appsDir;
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

  Future<bool> doesInstalledAppsPluginWork() async {
    bool res = false;
    try {
      res = (await InstalledApps.getAppInfo(obtainiumId)).versionName != null;
    } catch (e) {
      //
    }
    if (!res) {
      logs.add(tr('versionCorrectionDisabled'));
    }
    return res;
  }

  // If the App says it is installed but installedInfo is null, set it to not installed
  // If there is any other mismatch between installedInfo and installedVersion, try reconciling them intelligently
  // If that fails, just set it to the actual version string (all we can do at that point)
  // Don't save changes, just return the object if changes were made (else null)
  App? getCorrectedInstallStatusAppIfPossible(App app, AppInfo? installedInfo) {
    var modded = false;
    var trackOnly = app.additionalSettings['trackOnly'] == true;
    var noVersionDetection =
        app.additionalSettings['noVersionDetection'] == true;
    if (installedInfo == null && app.installedVersion != null && !trackOnly) {
      app.installedVersion = null;
      modded = true;
    } else if (installedInfo?.versionName != null &&
        app.installedVersion == null) {
      app.installedVersion = installedInfo!.versionName;
      modded = true;
    } else if (installedInfo?.versionName != null &&
        installedInfo!.versionName != app.installedVersion &&
        !noVersionDetection) {
      String? correctedInstalledVersion = reconcileRealAndInternalVersions(
          installedInfo.versionName!, app.installedVersion!);
      if (correctedInstalledVersion != null) {
        app.installedVersion = correctedInstalledVersion;
        modded = true;
      }
    }
    if (app.installedVersion != null &&
        app.installedVersion != app.latestVersion &&
        !noVersionDetection) {
      app.installedVersion = reconcileRealAndInternalVersions(
              app.installedVersion!, app.latestVersion,
              matchMode: true) ??
          app.installedVersion;
      modded = true;
    }
    return modded ? app : null;
  }

  String? reconcileRealAndInternalVersions(
      String realVersion, String internalVersion,
      {bool matchMode = false}) {
    // 1. If one or both of these can't be converted to a "standard" format, return null (leave as is)
    // 2. If both have a "standard" format under which they are equal, return null (leave as is)
    // 3. If both have a "standard" format in common but are unequal, return realVersion (this means it was changed externally)
    // If in matchMode, the outcomes of rules 2 and 3 are reversed, and the "real" version is not matched strictly
    // Matchmode to be used when comparing internal install version and internal latest version

    bool doStringsMatchUnderRegEx(
        String pattern, String value1, String value2) {
      var r = RegExp(pattern);
      var m1 = r.firstMatch(value1);
      var m2 = r.firstMatch(value2);
      return m1 != null && m2 != null
          ? value1.substring(m1.start, m1.end) ==
              value2.substring(m2.start, m2.end)
          : false;
    }

    Set<String> findStandardFormatsForVersion(String version, bool strict) {
      Set<String> results = {};
      for (var pattern in standardVersionRegExStrings) {
        if (RegExp('${strict ? '^' : ''}$pattern${strict ? '\$' : ''}')
            .hasMatch(version)) {
          results.add(pattern);
        }
      }
      return results;
    }

    var realStandardVersionFormats =
        findStandardFormatsForVersion(realVersion, true);
    var internalStandardVersionFormats =
        findStandardFormatsForVersion(internalVersion, false);
    var commonStandardFormats =
        realStandardVersionFormats.intersection(internalStandardVersionFormats);
    if (commonStandardFormats.isEmpty) {
      return null; // Incompatible; no "enhanced detection"
    }
    for (String pattern in commonStandardFormats) {
      if (doStringsMatchUnderRegEx(pattern, internalVersion, realVersion)) {
        return matchMode
            ? internalVersion
            : null; // Enhanced detection says no change
      }
    }
    return matchMode
        ? null
        : realVersion; // Enhanced detection says something changed
  }

  Future<void> loadApps() async {
    while (loadingApps) {
      await Future.delayed(const Duration(microseconds: 1));
    }
    loadingApps = true;
    notifyListeners();
    List<App> newApps = (await getAppsDir())
        .listSync()
        .where((item) => item.path.toLowerCase().endsWith('.json'))
        .map((e) => App.fromJson(jsonDecode(File(e.path).readAsStringSync())))
        .toList();
    var idsToDelete = apps.values
        .map((e) => e.app.id)
        .toSet()
        .difference(newApps.map((e) => e.id).toSet());
    for (var id in idsToDelete) {
      apps.remove(id);
    }
    var sp = SourceProvider();
    List<List<String>> errors = [];
    for (int i = 0; i < newApps.length; i++) {
      var info = await getInstalledInfo(newApps[i].id);
      try {
        sp.getSource(newApps[i].url);
        apps[newApps[i].id] = AppInMemory(newApps[i], null, info);
      } catch (e) {
        errors.add([newApps[i].id, newApps[i].name, e.toString()]);
      }
    }
    if (errors.isNotEmpty) {
      removeApps(errors.map((e) => e[0]).toList());
      NotificationsProvider().notify(
          AppsRemovedNotification(errors.map((e) => [e[1], e[2]]).toList()));
    }
    loadingApps = false;
    notifyListeners();
    if (await doesInstalledAppsPluginWork()) {
      List<App> modifiedApps = [];
      for (var app in apps.values) {
        var moddedApp =
            getCorrectedInstallStatusAppIfPossible(app.app, app.installedInfo);
        if (moddedApp != null) {
          modifiedApps.add(moddedApp);
        }
      }
      if (modifiedApps.isNotEmpty) {
        await saveApps(modifiedApps, attemptToCorrectInstallStatus: false);
      }
    }
  }

  Future<void> saveApps(List<App> apps,
      {bool attemptToCorrectInstallStatus = true}) async {
    attemptToCorrectInstallStatus =
        attemptToCorrectInstallStatus && (await doesInstalledAppsPluginWork());
    for (var app in apps) {
      AppInfo? info = await getInstalledInfo(app.id);
      app.name = info?.name ?? app.name;
      if (attemptToCorrectInstallStatus) {
        app = getCorrectedInstallStatusAppIfPossible(app, info) ?? app;
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

  Future<App?> checkUpdate(String appId) async {
    App? currentApp = apps[appId]!.app;
    SourceProvider sourceProvider = SourceProvider();
    App newApp = await sourceProvider.getApp(
        sourceProvider.getSource(currentApp.url),
        currentApp.url,
        currentApp.additionalSettings,
        currentApp: currentApp);
    if (currentApp.preferredApkIndex < newApp.apkUrls.length) {
      newApp.preferredApkIndex = currentApp.preferredApkIndex;
    }
    await saveApps([newApp]);
    return newApp.latestVersion != currentApp.latestVersion ? newApp : null;
  }

  Future<List<App>> checkUpdates(
      {DateTime? ignoreAppsCheckedAfter,
      bool throwErrorsForRetry = false}) async {
    List<App> updates = [];
    MultiAppMultiError errors = MultiAppMultiError();
    if (!gettingUpdates) {
      gettingUpdates = true;
      try {
        List<String> appIds = apps.values
            .where((app) =>
                app.app.lastUpdateCheck == null ||
                ignoreAppsCheckedAfter == null ||
                app.app.lastUpdateCheck!.isBefore(ignoreAppsCheckedAfter))
            .map((e) => e.app.id)
            .toList();
        appIds.sort((a, b) => (apps[a]!.app.lastUpdateCheck ??
                DateTime.fromMicrosecondsSinceEpoch(0))
            .compareTo(apps[b]!.app.lastUpdateCheck ??
                DateTime.fromMicrosecondsSinceEpoch(0)));
        for (int i = 0; i < appIds.length; i++) {
          App? newApp;
          try {
            newApp = await checkUpdate(appIds[i]);
          } catch (e) {
            if ((e is RateLimitError || e is SocketException) &&
                throwErrorsForRetry) {
              rethrow;
            }
            errors.add(appIds[i], e.toString());
          }
          if (newApp != null) {
            updates.add(newApp);
          }
        }
      } finally {
        gettingUpdates = false;
      }
    }
    if (errors.content.isNotEmpty) {
      throw errors;
    }
    return updates;
  }

  List<String> findExistingUpdates(
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
    String path = 'Downloads'; // TODO: See if hardcoding this can be avoided
    if (!exportDir.existsSync()) {
      exportDir = await getExternalStorageDirectory();
      path = exportDir!.path;
    }
    if ((await DeviceInfoPlugin().androidInfo).version.sdkInt <= 28) {
      if (await Permission.storage.isDenied) {
        await Permission.storage.request();
      }
      if (await Permission.storage.isDenied) {
        throw ObtainiumError(tr('storagePermissionDenied'));
      }
    }
    File export = File(
        '${exportDir.path}/${tr('obtainiumExportHyphenatedLowercase')}-${DateTime.now().millisecondsSinceEpoch}.json');
    export.writeAsStringSync(
        jsonEncode(apps.values.map((e) => e.app.toJson()).toList()));
    return path;
  }

  Future<int> importApps(String appsJSON) async {
    List<App> importedApps = (jsonDecode(appsJSON) as List<dynamic>)
        .map((e) => App.fromJson(e))
        .toList();
    while (loadingApps) {
      await Future.delayed(const Duration(microseconds: 1));
    }
    for (App a in importedApps) {
      if (apps[a.id]?.app.installedVersion != null) {
        a.installedVersion = apps[a.id]?.app.installedVersion;
      }
    }
    await saveApps(importedApps);
    notifyListeners();
    return importedApps.length;
  }

  @override
  void dispose() {
    foregroundSubscription?.cancel();
    super.dispose();
  }

  Future<List<List<String>>> addAppsByURL(List<String> urls) async {
    List<dynamic> results = await SourceProvider().getAppsByURLNaive(urls,
        ignoreUrls: apps.values.map((e) => e.app.url).toList());
    List<App> pps = results[0];
    Map<String, dynamic> errorsMap = results[1];
    for (var app in pps) {
      if (apps.containsKey(app.id)) {
        errorsMap.addAll({app.id: tr('appAlreadyAdded')});
      } else {
        await saveApps([app]);
      }
    }
    List<List<String>> errors =
        errorsMap.keys.map((e) => [e, errorsMap[e].toString()]).toList();
    return errors;
  }
}

class APKPicker extends StatefulWidget {
  const APKPicker({super.key, required this.app, this.initVal, this.archs});

  final App app;
  final String? initVal;
  final List<String>? archs;

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
      title: Text(tr('pickAnAPK')),
      content: Column(children: [
        Text(tr('appHasMoreThanOnePackage', args: [widget.app.name])),
        const SizedBox(height: 16),
        ...widget.app.apkUrls.map(
          (u) => RadioListTile<String>(
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
              }),
        ),
        if (widget.archs != null)
          const SizedBox(
            height: 16,
          ),
        if (widget.archs != null)
          Text(
            widget.archs!.length == 1
                ? tr('deviceSupportsXArch', args: [widget.archs![0]])
                : tr('deviceSupportsFollowingArchs') +
                    list2FriendlyString(
                        widget.archs!.map((e) => '\'$e\'').toList()),
            style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
          ),
      ]),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop(null);
            },
            child: Text(tr('cancel'))),
        TextButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(apkUrl);
            },
            child: Text(tr('continue')))
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
      title: Text(tr('warning')),
      content: Text(tr('sourceIsXButPackageFromYPrompt', args: [
        Uri.parse(widget.sourceUrl).host,
        Uri.parse(widget.apkUrl).host
      ])),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop(null);
            },
            child: Text(tr('cancel'))),
        TextButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(true);
            },
            child: Text(tr('continue')))
      ],
    );
  }
}
