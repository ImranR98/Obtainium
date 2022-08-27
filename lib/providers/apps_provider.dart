// Manages state related to the list of Apps tracked by Obtainium,
// Exposes related functions such as those used to add, remove, download, and install Apps.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_fgbg/flutter_fgbg.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:http/http.dart';
import 'package:install_plugin_v2/install_plugin_v2.dart';

class AppInMemory {
  late App app;
  double? downloadProgress;

  AppInMemory(this.app, this.downloadProgress);
}

class ApkFile {
  String appId;
  File file;
  ApkFile(this.appId, this.file);
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

  AppsProvider({bool bg = false}) {
    // Subscribe to changes in the app foreground status
    foregroundStream = FGBGEvents.stream.asBroadcastStream();
    foregroundSubscription = foregroundStream.listen((event) async {
      isForeground = event == FGBGType.foreground;
      if (isForeground) await loadApps();
    });
    loadApps();
  }

  Future<ApkFile> downloadApp(String apkUrl, String appId) async {
    StreamedResponse response =
        await Client().send(Request('GET', Uri.parse(apkUrl)));
    File downloadFile =
        File('${(await getExternalStorageDirectory())!.path}/$appId.apk');
    if (downloadFile.existsSync()) {
      downloadFile.deleteSync();
    }
    var length = response.contentLength;
    var received = 0;
    var sink = downloadFile.openWrite();

    await response.stream.map((s) {
      received += s.length;
      apps[appId]!.downloadProgress =
          (length != null ? received / length * 100 : 30);
      notifyListeners();
      return s;
    }).pipe(sink);

    await sink.close();
    apps[appId]!.downloadProgress = null;
    notifyListeners();

    if (response.statusCode != 200) {
      downloadFile.deleteSync();
      throw response.reasonPhrase ?? 'Unknown Error';
    }
    return ApkFile(appId, downloadFile);
  }

  bool areDownloadsRunning() => apps.values
      .where((element) => element.downloadProgress != null)
      .isNotEmpty;

  // Given an AppId, uses stored info about the app to download an APK (with user input if needed) and install it
  // Installs can only be done in the foreground, so a notification is sent to get the user's attention if needed
  // Returns upon successful download, regardless of installation result
  Future<bool> downloadAndInstallLatestApp(
      List<String> appIds, BuildContext context) async {
    NotificationsProvider notificationsProvider =
        context.read<NotificationsProvider>();
    Map<String, String> appsToInstall = {};
    for (var id in appIds) {
      if (apps[id] == null) {
        throw 'App not found';
      }
      String? apkUrl = apps[id]!.app.apkUrls[apps[id]!.app.preferredApkIndex];
      if (apps[id]!.app.apkUrls.length > 1) {
        apkUrl = await showDialog(
            context: context,
            builder: (BuildContext ctx) {
              return APKPicker(app: apps[id]!.app, initVal: apkUrl);
            });
      }
      if (apkUrl != null) {
        int urlInd = apps[id]!.app.apkUrls.indexOf(apkUrl);
        if (urlInd != apps[id]!.app.preferredApkIndex) {
          apps[id]!.app.preferredApkIndex = urlInd;
          await saveApp(apps[id]!.app);
        }
        appsToInstall.putIfAbsent(id, () => apkUrl!);
      }
    }

    List<ApkFile> downloadedFiles = await Future.wait(appsToInstall.entries
        .map((entry) => downloadApp(entry.value, entry.key)));

    if (!isForeground) {
      await notificationsProvider.notify(completeInstallationNotification,
          cancelExisting: true);
      await FGBGEvents.stream.first == FGBGType.foreground;
      await notificationsProvider.cancel(completeInstallationNotification.id);
      // We need to wait for the App to come to the foreground to install it
      // Can't try to call install plugin in a background isolate (may not have worked anyways) because of:
      // https://github.com/flutter/flutter/issues/13937
    }

    // Unfortunately this 'await' does not actually wait for the APK to finish installing
    // So we only know that the install prompt was shown, but the user could still cancel w/o us knowing
    // This also does not use the 'session-based' installer API, so background/silent updates are impossible
    for (var f in downloadedFiles) {
      await InstallPlugin.installApk(f.file.path, 'dev.imranr.obtainium');
      apps[f.appId]!.app.installedVersion = apps[f.appId]!.app.latestVersion;
      await saveApp(apps[f.appId]!.app);
    }

    return downloadedFiles.isNotEmpty;
  }

  Future<Directory> getAppsDir() async {
    Directory appsDir = Directory(
        '${(await getExternalStorageDirectory())?.path as String}/app_data');
    if (!appsDir.existsSync()) {
      appsDir.createSync();
    }
    return appsDir;
  }

  Future<void> deleteSavedAPKs() async {
    (await getExternalStorageDirectory())
        ?.listSync()
        .where((element) => element.path.endsWith('.apk'))
        .forEach((element) {
      element.deleteSync();
    });
  }

  Future<void> loadApps() async {
    loadingApps = true;
    notifyListeners();
    List<FileSystemEntity> appFiles = (await getAppsDir())
        .listSync()
        .where((item) => item.path.toLowerCase().endsWith('.json'))
        .toList();
    apps.clear();
    for (int i = 0; i < appFiles.length; i++) {
      App app =
          App.fromJson(jsonDecode(File(appFiles[i].path).readAsStringSync()));
      apps.putIfAbsent(app.id, () => AppInMemory(app, null));
    }
    loadingApps = false;
    notifyListeners();
  }

  Future<void> saveApp(App app) async {
    File('${(await getAppsDir()).path}/${app.id}.json')
        .writeAsStringSync(jsonEncode(app.toJson()));
    apps.update(app.id, (value) => AppInMemory(app, value.downloadProgress),
        ifAbsent: () => AppInMemory(app, null));
    notifyListeners();
  }

  Future<void> removeApp(String appId) async {
    File file = File('${(await getAppsDir()).path}/$appId.json');
    if (file.existsSync()) {
      file.deleteSync();
    }
    if (apps.containsKey(appId)) {
      apps.remove(appId);
    }
    notifyListeners();
  }

  bool checkAppObjectForUpdate(App app) {
    if (!apps.containsKey(app.id)) {
      throw 'App not found';
    }
    return app.latestVersion != apps[app.id]?.app.installedVersion;
  }

  Future<App?> getUpdate(String appId) async {
    App? currentApp = apps[appId]!.app;
    App newApp = await SourceProvider().getApp(currentApp.url);
    if (newApp.latestVersion != currentApp.latestVersion) {
      newApp.installedVersion = currentApp.installedVersion;
      if (currentApp.preferredApkIndex < newApp.apkUrls.length) {
        newApp.preferredApkIndex = currentApp.preferredApkIndex;
      }
      await saveApp(newApp);
      return newApp;
    }
    return null;
  }

  Future<List<App>> checkUpdates() async {
    List<App> updates = [];
    if (!gettingUpdates) {
      gettingUpdates = true;

      List<String> appIds = apps.keys.toList();
      for (int i = 0; i < appIds.length; i++) {
        App? newApp = await getUpdate(appIds[i]);
        if (newApp != null) {
          updates.add(newApp);
        }
      }
      gettingUpdates = false;
    }
    return updates;
  }

  List<String> getExistingUpdates() {
    List<String> updateAppIds = [];
    List<String> appIds = apps.keys.toList();
    for (int i = 0; i < appIds.length; i++) {
      App? app = apps[appIds[i]]!.app;
      if (app.installedVersion != app.latestVersion) {
        updateAppIds.add(app.id);
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
      await saveApp(a);
    }
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
            title: Text(Uri.parse(u).pathSegments.last),
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
              HapticFeedback.lightImpact();
              Navigator.of(context).pop(null);
            },
            child: const Text('Cancel')),
        TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.of(context).pop(apkUrl);
            },
            child: const Text('Continue'))
      ],
    );
  }
}
