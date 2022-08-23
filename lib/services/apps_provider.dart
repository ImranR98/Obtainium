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
      String channelName, String channelDescription) {
    return downloaderNotifications.show(
        id,
        title,
        message,
        NotificationDetails(
            android: AndroidNotificationDetails(channelCode, channelName,
                channelDescription: channelDescription,
                importance: Importance.max,
                priority: Priority.max,
                groupKey: 'dev.imranr.obtainium.$channelCode')));
  }

  // Given a App (assumed valid), initiate an APK download (will trigger install callback when complete)
  Future<void> downloadAndInstallLatestApp(String appId) async {
    if (apps[appId] == null) {
      throw 'App not found';
    }
    StreamedResponse response =
        await Client().send(Request('GET', Uri.parse(apps[appId]!.app.apkUrl)));
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

    // Unfortunately this 'await' does not actually wait for the APK to finish installing
    // So we only know that the install prompt was shown, but the user could still cancel w/o us knowing
    // This also does not use the 'session-based' installer API, so background/silent updates are impossible
    await InstallPlugin.installApk(downloadFile.path, 'dev.imranr.obtainium');

    apps[appId]!.app.installedVersion = apps[appId]!.app.latestVersion;
    saveApp(apps[appId]!.app);
  }

  Future<Directory> getAppsDir() async {
    Directory appsDir = Directory(
        '${(await getExternalStorageDirectory())?.path as String}/app_data');
    if (!appsDir.existsSync()) {
      appsDir.createSync();
    }
    return appsDir;
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

  Future<List<App>> getUpdates() async {
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

  Future<void> installUpdates() async {
    List<String> appIds = apps.keys.toList();
    for (int i = 0; i < appIds.length; i++) {
      App? app = apps[appIds[i]]!.app;
      if (app.installedVersion != app.latestVersion) {
        await downloadAndInstallLatestApp(app.id);
      }
    }
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    foregroundSubscription?.cancel();
    super.dispose();
  }
}
