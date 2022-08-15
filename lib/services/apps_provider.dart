// Provider that manages App-related state and provides functions to retrieve App info download/install Apps

import 'dart:async';
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
      FlutterDownloader.open(taskId: id);
      downloaderNotifications.cancel(1);
    }
  }

  // Given a URL (assumed valid), initiate an APK download (will trigger install callback when complete)
  Future<void> backgroundDownloadAndInstallAPK(String url, String appId) async {
    var apkDir = Directory(
        '${(await getExternalStorageDirectory())?.path as String}/$appId');
    if (apkDir.existsSync()) apkDir.deleteSync(recursive: true);
    apkDir.createSync();
    await FlutterDownloader.enqueue(
      url: url,
      savedDir: apkDir.path,
      showNotification: true,
      openFileFromNotification: false,
    );
  }

  void loadApps() {
    // TODO: Load Apps JSON and fill the array
    notifyListeners();
  }

  void saveApp(App app) {
    // TODO: Save/update an App JSON and update the array
    notifyListeners();
  }

  bool checkUpdate(App app) {
    // TODO: Check the given App against the existing version in the array (if it does not exist, throw an error)
    return false;
  }

  Future<void> installApp(String url) async {
    var app = await SourceService().getApp(url);
    await backgroundDownloadAndInstallAPK(app.apkUrl, app.id);
    // TODO: Apps array should notify consumers about download progress (will need to change FlutterDownloader callbacks)
    saveApp(app);
  }

  Future<List<App>> checkUpdates() async {
    List<App> updates = [];
    var appIds = apps.keys.toList();
    for (var i = 0; i < appIds.length; i++) {
      var currentApp = apps[appIds[i]];
      var newApp = await SourceService().getApp(currentApp!.url);
      if (newApp.latestVersion != currentApp.latestVersion) {
        newApp.installedVersion = currentApp.installedVersion;
        updates.add(newApp);
        saveApp(newApp);
      }
    }
    return updates;
  }

  Future<void> installUpdates() async {
    var appIds = apps.keys.toList();
    for (var i = 0; i < appIds.length; i++) {
      var app = apps[appIds[i]];
      if (app != null) {
        if (app.installedVersion != app.latestVersion) {
          await installApp(app.apkUrl);
        }
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
