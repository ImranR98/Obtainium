// Provider that manages App-related state and provides functions to retrieve App info download/install Apps

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_fgbg/flutter_fgbg.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:obtainium/services/source_service.dart';
import 'package:http/http.dart';
import 'package:install_plugin_v2/install_plugin_v2.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';

class AppInMemory {
  late App app;
  double? downloadProgress;

  AppInMemory(this.app, this.downloadProgress);
}

class AppsProvider with ChangeNotifier {
  // In memory App state (should always be kept in sync with local storage versions)
  Map<String, AppInMemory> apps = {};
  bool loadingApps = false;
  bool gettingUpdates = false;

  // Notifications plugin for downloads
  FlutterLocalNotificationsPlugin downloaderNotifications =
      FlutterLocalNotificationsPlugin();

  // Variables to keep track of the app foreground status (installs can't run in the background)
  bool isForeground = true;
  StreamSubscription<FGBGType>? foregroundSubscription;

  AppsProvider({bool bg = false}) {
    initializeNotifs();
    // Subscribe to changes in the app foreground status
    foregroundSubscription = FGBGEvents.stream.listen((event) async {
      isForeground = event == FGBGType.foreground;
      if (isForeground) await loadApps();
    });
    loadApps();
  }

  Future<void> initializeNotifs() async {
    // Initialize the notifications service
    await downloaderNotifications.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification')));
  }

  Future<void> notify(int id, String title, String message, String channelCode,
      String channelName, String channelDescription,
      {bool important = true}) {
    return downloaderNotifications.show(
        id,
        title,
        message,
        NotificationDetails(
            android: AndroidNotificationDetails(channelCode, channelName,
                channelDescription: channelDescription,
                importance: important ? Importance.max : Importance.min,
                priority: important ? Priority.max : Priority.min,
                groupKey: 'dev.imranr.obtainium.$channelCode')));
  }

  // Given a App (assumed valid), initiate an APK download (will trigger install callback when complete)
  Future<void> downloadAndInstallLatestApp(
      String appId, BuildContext context) async {
    if (apps[appId] == null) {
      throw 'App not found';
    }
    String apkUrl = apps[appId]!.app.apkUrls.last;
    if (apps[appId]!.app.apkUrls.length > 1) {
      await showDialog(
          context: context,
          builder: (BuildContext ctx) {
            return AlertDialog(
              scrollable: true,
              title: const Text('Pick an APK'),
              content: Column(children: [
                Text(
                    '${apps[appId]!.app.name} has more than one package - pick one.'),
                ...apps[appId]!.app.apkUrls.map((u) => ListTile(
                    title: Text(Uri.parse(u).pathSegments.last),
                    leading: Radio<String>(
                        value: u,
                        groupValue: apkUrl,
                        onChanged: (String? val) {
                          apkUrl = val!;
                        })))
              ]),
              actions: [
                TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Continue'))
              ],
            );
          });
    }
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

    if (!isForeground) {
      await downloaderNotifications.cancel(1);
      await notify(
          1,
          'Complete App Installation',
          'Obtainium must be open to install Apps',
          'COMPLETE_INSTALL',
          'Complete App Installation',
          'Asks the user to return to Obtanium to finish installing an App');
      while (await FGBGEvents.stream.first != FGBGType.foreground) {
        // We need to wait for the App to come to the foreground to install it
        // Can't try to call install plugin in a background isolate (may not have worked anyways) because of:
        // https://github.com/flutter/flutter/issues/13937
      }
    }

    // Unfortunately this 'await' does not actually wait for the APK to finish installing
    // So we only know that the install prompt was shown, but the user could still cancel w/o us knowing
    // This also does not use the 'session-based' installer API, so background/silent updates are impossible
    while (!(await Permission.requestInstallPackages.isGranted)) {
      // Explicit request as InstallPlugin request sometimes bugged
      Fluttertoast.showToast(
          msg: 'Please allow Obtainium to install Apps',
          toastLength: Toast.LENGTH_LONG);
      if ((await Permission.requestInstallPackages.request()) ==
          PermissionStatus.granted) {
        break;
      }
    }
    await InstallPlugin.installApk(downloadFile.path, 'dev.imranr.obtainium');

    apps[appId]!.app.installedVersion = apps[appId]!.app.latestVersion;
    await saveApp(apps[appId]!.app);
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
    App newApp = await SourceService().getApp(currentApp.url);
    if (newApp.latestVersion != currentApp.latestVersion) {
      newApp.installedVersion = currentApp.installedVersion;
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
    // FilePickerResult? result = await FilePicker.platform.pickFiles(); // Does not work on Android 13

    // if (result != null) {
    // String appsJSON = File(result.files.single.path!).readAsStringSync();
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
    // } else {
    // User canceled the picker
    // }
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    foregroundSubscription?.cancel();
    super.dispose();
  }
}
