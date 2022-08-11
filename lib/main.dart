import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:install_plugin_v2/install_plugin_v2.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:app_installer/app_installer.dart';

// Port for FlutterDownloader background/foreground communication
ReceivePort _port = ReceivePort();

void main() async {
  await initializeDownloader();
  runApp(const MyApp());
}

// Setup the FlutterDownloader plugin
Future<void> initializeDownloader() async {
  // Make sure FlutterDownloader can be used
  WidgetsFlutterBinding.ensureInitialized();
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
}

// Callback that receives FlutterDownloader status and forwards to a foreground function
@pragma('vm:entry-point')
void downloadCallbackBackground(
    String id, DownloadTaskStatus status, int progress) {
  final SendPort? send =
      IsolateNameServer.lookupPortByName('downloader_send_port');
  send!.send([id, status, progress]);
}

// Foreground function to act on FlutterDownloader status updates (install then delete downloaded APK)
void downloadCallbackForeground(
    String id, DownloadTaskStatus status, int progress) async {
  if (status == DownloadTaskStatus.complete) {
    FlutterDownloader.open(taskId: id);
  }
}

// Given a URL (assumed valid), initiate an APK download (will trigger install callback when complete)
void downloadAPK(String url, String appId) async {
  var apkDir = Directory(
      "${(await getExternalStorageDirectory())?.path as String}/$appId");
  if (apkDir.existsSync()) apkDir.deleteSync(recursive: true);
  apkDir.createSync();
  await FlutterDownloader.enqueue(
    url: url,
    savedDir: apkDir.path,
    showNotification: true,
    openFileFromNotification: true,
  );
}

// Extract a GitHub project name and author account name from a GitHub URL (can be any sub-URL of the project)
Map<String, String>? getAppNamesFromGitHubURL(String url) {
  RegExp regex = RegExp(r"://github.com/[^/]*/[^/]*");
  var match = regex.firstMatch(url.toLowerCase());
  if (match != null) {
    var uri = url.substring(match.start + 14, match.end);
    var slashIndex = uri.indexOf("/");
    var author = uri.substring(0, slashIndex);
    var appName = uri.substring(slashIndex + 1);
    return {"author": author, "appName": appName};
  }
  return null;
}

// Future<Directory> getAPKDir() async {
//   var apkDir = Directory("${(await getExternalStorageDirectory())!.path}/apks");
//   if (!apkDir.existsSync()) {
//     apkDir.createSync();
//   }
//   return apkDir;
// }

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Obtainium',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Obtainium'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int ind = 0;
  var urls = [
    "https://github.com/Ashinch/ReadYou/releases/download/0.8.0/ReadYou-0.8.0-eec397e.apk",
    "https://github.com/Ashinch/ReadYou/releases/download/0.8.1/ReadYou-0.8.1-c741f19.apk",
    "https://github.com/Ashinch/ReadYou/releases/download/0.8.3/ReadYou-0.8.3-7a47329.apk"
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              urls[ind] + ind.toString(),
              style: Theme.of(context).textTheme.headline4,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          var names = getAppNamesFromGitHubURL(urls[ind]);
          if (names != null) {
            downloadAPK(urls[ind], "${names["author"]!}_${names["appName"]!}");
            setState(() {
              ind = ind == (urls.length - 1) ? 0 : ind + 1;
            });
          }
        },
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }

  @override
  void dispose() {
    // Remove the FlutterDownloader communication port
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    super.dispose();
  }
}
