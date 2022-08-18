// Provider that manages App-related state and provides functions to retrieve App info download/install Apps

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_fgbg/flutter_fgbg.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:obtainium/services/source_service.dart';

class AppsProvider with ChangeNotifier {
  // In memory App state (should always be kept in sync with local storage versions)
  Map<String, App> apps = {};
  bool loadingApps = false;

  AppsProvider() {
    initializeDownloader();
    loadApps();
  }

  // Notifications plugin for downloads
  FlutterLocalNotificationsPlugin downloaderNotifications =
      FlutterLocalNotificationsPlugin();

  // Port for FlutterDownloader background/foreground communication
  final ReceivePort _port = ReceivePort();

  // Variables to keep track of the app foreground status (installs can't run in the background)
  bool isForeground = true;
  StreamSubscription<FGBGType>? foregroundSubscription;

  // Setup the FlutterDownloader plugin (call only once)
  Future<void> initializeDownloader() async {
    // Make sure FlutterDownloader can be used
    await FlutterDownloader.initialize();
    // Set up the status update callback for FlutterDownloader
    FlutterDownloader.registerCallback(downloadCallbackBackground);
    // The actual callback is in the background isolate
    // So setup a port to pass the data to a foreground callback
    IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');
    _port.listen((dynamic data) {
      String id = data[0];
      DownloadTaskStatus status = data[1];
      int progress = data[2];
      downloadCallbackForeground(id, status, progress);
    });
    // Initialize the notifications service
    await downloaderNotifications.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher')));
    // Subscribe to changes in the app foreground status
    foregroundSubscription = FGBGEvents.stream.listen((event) async {
      isForeground = event == FGBGType.foreground;
    });
  }

  // Callback that receives FlutterDownloader status and forwards to a foreground function
  @pragma('vm:entry-point')
  static void downloadCallbackBackground(
      String id, DownloadTaskStatus status, int progress) {
    final SendPort? send =
        IsolateNameServer.lookupPortByName('downloader_send_port');
    send!.send([id, status, progress]);
  }

  // Foreground function to act on FlutterDownloader status updates (install downloaded APK)
  void downloadCallbackForeground(
      String id, DownloadTaskStatus status, int progress) async {
    if (status == DownloadTaskStatus.complete) {
      // Wait for app to come to the foreground if not already, and notify the user
      while (!isForeground) {
        await downloaderNotifications.show(
            1,
            'Complete App Installation',
            'Obtainium must be open to install Apps',
            const NotificationDetails(
                android: AndroidNotificationDetails(
                    'COMPLETE_INSTALL', 'Complete App Installation',
                    channelDescription:
                        'Ask the user to return to Obtanium to finish installing an App',
                    importance: Importance.max,
                    priority: Priority.max,
                    groupKey: 'dev.imranr.obtainium.COMPLETE_INSTALL')));
        if (await FGBGEvents.stream.first == FGBGType.foreground) {
          break;
        }
      }
      // Change App status to no longer downloading
      App? foundApp;
      apps.forEach((id, app) {
        if (app.currentDownloadId == id) {
          foundApp = apps[app.id];
        }
      });
      foundApp!.currentDownloadId = null;
      saveApp(foundApp!);
      // Install the App (and remove warning notification if any)
      FlutterDownloader.open(taskId: id);
      downloaderNotifications.cancel(1);
    }
  }

  // Given a App (assumed valid), initiate an APK download (will trigger install callback when complete)
  Future<void> backgroundDownloadAndInstallApp(App app) async {
    Directory apkDir = Directory(
        '${(await getExternalStorageDirectory())?.path as String}/apks/${app.id}');
    if (apkDir.existsSync()) apkDir.deleteSync(recursive: true);
    apkDir.createSync(recursive: true);
    String? downloadId = await FlutterDownloader.enqueue(
      url: app.url,
      savedDir: apkDir.path,
      showNotification: true,
      openFileFromNotification: false,
    );
    if (downloadId != null) {
      app.currentDownloadId = downloadId;
      saveApp(app);
    } else {
      throw "Could not start download";
    }
  }

  Future<Directory> getAppsDir() async {
    Directory appsDir = Directory(
        '${(await getExternalStorageDirectory())?.path as String}/apps');
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
      apps.putIfAbsent(app.id, () => app);
    }
    loadingApps = false;
    notifyListeners();
  }

  Future<void> saveApp(App app) async {
    File('${(await getAppsDir()).path}/${app.id}.json')
        .writeAsStringSync(jsonEncode(app.toJson()));
    apps.update(app.id, (value) => app, ifAbsent: () => app);
    notifyListeners();
  }

  bool checkUpdate(App app) {
    if (!apps.containsKey(app.id)) {
      throw 'App not found';
    }
    return app.latestVersion != apps[app.id]?.installedVersion;
  }

  Future<List<App>> checkUpdates() async {
    List<App> updates = [];
    List<String> appIds = apps.keys.toList();
    for (int i = 0; i < appIds.length; i++) {
      App? currentApp = apps[appIds[i]];
      App newApp = await SourceService().getApp(currentApp!.url);
      if (newApp.latestVersion != currentApp.latestVersion) {
        newApp.installedVersion = currentApp.installedVersion;
        updates.add(newApp);
        await saveApp(newApp);
      }
    }
    return updates;
  }

  Future<void> installUpdates() async {
    List<String> appIds = apps.keys.toList();
    for (int i = 0; i < appIds.length; i++) {
      App? app = apps[appIds[i]];
      if (app!.installedVersion != app.latestVersion) {
        await backgroundDownloadAndInstallApp(app);
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
