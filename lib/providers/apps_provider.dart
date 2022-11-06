// Manages state related to the list of Apps tracked by Obtainium,
// Exposes related functions such as those used to add, remove, download, and install Apps.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
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
  AppInfo? installedInfo;

  AppInMemory(this.app, this.downloadProgress, this.installedInfo);
}

class DownloadedApk {
  String appId;
  File file;
  DownloadedApk(this.appId, this.file);
}

// Useful for collecting errors by App ID
class MapOfAppIdsByString {
  Map<String, List<String>> content = {};

  add(String appId, String string) {
    var tempIds = content.remove(string);
    tempIds ??= [];
    tempIds.add(appId);
    content.putIfAbsent(string, () => tempIds!);
  }

  String asString(Map<String, AppInMemory> apps) {
    String finalString = '';
    for (var e in content.keys) {
      finalString +=
          '$e ${content[e]!.map((e) => apps[e]?.app.name).toString()}. ';
    }
    return finalString;
  }
}

class AppsProvider with ChangeNotifier {
  // In memory App state (should always be kept in sync with local storage versions)
  Map<String, AppInMemory> apps = {};
  bool loadingApps = false;
  bool gettingUpdates = false;
  bool forBGTask = false;

  // Variables to keep track of the app foreground status (installs can't run in the background)
  bool isForeground = true;
  late Stream<FGBGType>? foregroundStream;
  late StreamSubscription<FGBGType>? foregroundSubscription;

  AppsProvider({this.forBGTask = false}) {
    // Many setup tasks should only be done in the foreground isolate
    if (!forBGTask) {
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
            .where((element) => element.path.endsWith('.apk'))
            .forEach((apk) {
          apk.delete();
        });
      }();
    }
  }

  downloadFile(String url, String fileName, Function? onProgress) async {
    var destDir = (await getExternalStorageDirectory())!.path;
    StreamedResponse response =
        await Client().send(Request('GET', Uri.parse(url)));
    File downloadedFile = File('$destDir/$fileName');

    if (downloadedFile.existsSync()) {
      downloadedFile.deleteSync();
    }
    var length = response.contentLength;
    var received = 0;
    double? progress;
    var sink = downloadedFile.openWrite();

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
      downloadedFile.deleteSync();
      throw response.reasonPhrase ?? 'Unknown Error';
    }
    return downloadedFile;
  }

  Future<DownloadedApk> downloadApp(App app) async {
    var fileName =
        '${app.id}-${app.latestVersion}-${app.preferredApkIndex}.apk';
    String downloadUrl = await SourceProvider()
        .getSource(app.url)
        .apkUrlPrefetchModifier(app.url);
    int? prevProg;
    File downloadedFile =
        await downloadFile(downloadUrl, fileName, (double? progress) {
      int? prog = progress?.ceil();
      if (apps[app.id] != null) {
        apps[app.id]!.downloadProgress = progress;
        notifyListeners();
      } else if ((prog == 25 || prog == 50 || prog == 75) && prevProg != prog) {
        Fluttertoast.showToast(
            msg: 'Progress: $prog%', toastLength: Toast.LENGTH_SHORT);
      }
      prevProg = prog;
    });
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
      if (apps[app.id] != null) {
        throw IDChangedError();
      }
      app.id = newInfo.packageName;
      downloadedFile = downloadedFile.renameSync(
          '${downloadedFile.parent.path}/${app.id}-${app.latestVersion}-${app.preferredApkIndex}.apk');
    }
    return DownloadedApk(app.id, downloadedFile);
  }

  bool areDownloadsRunning() => apps.values
      .where((element) => element.downloadProgress != null)
      .isNotEmpty;

  Future<bool> canInstallSilently(App app) async {
    return false;
    // TODO: Uncomment the below once silentupdates are ever figured out
    // // TODO: This is unreliable - try to get from OS in the future
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
        int.parse(newInfo.buildNumber) < appInfo.versionCode!) {
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
    // For all specified Apps, filter out those for which:
    // 1. A URL cannot be picked
    // 2. That cannot be installed silently (IF no buildContext was given for interactive install)
    for (var id in appIds) {
      if (apps[id] == null) {
        throw ObtainiumError('App not found');
      }
      String? apkUrl = await confirmApkUrl(apps[id]!.app, context);
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
    }
    // Download APKs for all Apps to be installed
    MapOfAppIdsByString errors = MapOfAppIdsByString();
    List<DownloadedApk?> downloadedFiles =
        await Future.wait(appsToInstall.map((id) async {
      try {
        return await downloadApp(apps[id]!.app);
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

    // Move everything to the regular install list (since silent updates don't currently work) - TODO
    regularInstalls.addAll(silentUpdates);

    // If Obtainium is being installed, it should be the last one
    List<DownloadedApk> moveObtainiumToStart(List<DownloadedApk> items) {
      String obtainiumId = 'imranr98_obtainium_${GitHub().host}';
      DownloadedApk? temp;
      items.removeWhere((element) {
        bool res = element.appId == obtainiumId;
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
      throw errors.asString(apps);
    }

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

  // If the App says it is installed but installedInfo is null, set it to not installed
  // If the App says is is not installed but installedInfo exists, try to set it to installed as latest version...
  // ...if the latestVersion seems to match the version in installedInfo (not guaranteed)
  // If that fails, just set it to the actual version string (all we can do at that point)
  // Don't save changes, just return the object if changes were made (else null)
  // If in a background isolate, return null straight away as the required plugin won't work anyways
  App? getCorrectedInstallStatusAppIfPossible(App app, AppInfo? installedInfo) {
    if (forBGTask) {
      return null; // Can't correct in the background isolate
    }
    var modded = false;
    if (installedInfo == null && app.installedVersion != null) {
      app.installedVersion = null;
      modded = true;
    }
    if (installedInfo != null && app.installedVersion == null) {
      if (app.latestVersion.characters
              .where((p0) => [
                    '0',
                    '1',
                    '2',
                    '3',
                    '4',
                    '5',
                    '6',
                    '7',
                    '8',
                    '9',
                    '.'
                  ].contains(p0))
              .join('') ==
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
    while (loadingApps) {
      await Future.delayed(const Duration(microseconds: 1));
    }
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
    List<App> modifiedApps = [];
    for (var app in apps.values) {
      var moddedApp =
          getCorrectedInstallStatusAppIfPossible(app.app, app.installedInfo);
      if (moddedApp != null) {
        modifiedApps.add(moddedApp);
      }
    }
    if (modifiedApps.isNotEmpty) {
      await saveApps(modifiedApps);
    }
  }

  Future<void> saveApps(List<App> apps,
      {bool attemptToCorrectInstallStatus = true}) async {
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
      {DateTime? ignoreAppsCheckedAfter,
      bool throwErrorsForRetry = false}) async {
    List<App> updates = [];
    MapOfAppIdsByString errors = MapOfAppIdsByString();
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
      throw errors.asString(apps);
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
