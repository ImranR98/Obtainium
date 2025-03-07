// Manages state related to the list of Apps tracked by Obtainium,
// Exposes related functions such as those used to add, remove, download, and install Apps.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:battery_plus/battery_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'dart:typed_data';

import 'package:android_intent_plus/flag.dart';
import 'package:android_package_installer/android_package_installer.dart';
import 'package:android_package_manager/android_package_manager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/io_client.dart';
import 'package:obtainium/app_sources/directAPKLink.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_fgbg/flutter_fgbg.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:http/http.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_storage/shared_storage.dart' as saf;
import 'package:shizuku_apk_installer/shizuku_apk_installer.dart';

final pm = AndroidPackageManager();

class AppInMemory {
  late App app;
  double? downloadProgress;
  PackageInfo? installedInfo;
  Uint8List? icon;

  AppInMemory(this.app, this.downloadProgress, this.installedInfo, this.icon);
  AppInMemory deepCopy() =>
      AppInMemory(app.deepCopy(), downloadProgress, installedInfo, icon);

  String get name => app.overrideName ?? app.finalName;
  String get author => app.overrideAuthor ?? app.finalAuthor;
}

class DownloadedApk {
  String appId;
  File file;
  DownloadedApk(this.appId, this.file);
}

class DownloadedXApkDir {
  String appId;
  File file;
  Directory extracted;
  DownloadedXApkDir(this.appId, this.file, this.extracted);
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

Set<String> findStandardFormatsForVersion(String version, bool strict) {
  // If !strict, even a substring match is valid
  Set<String> results = {};
  for (var pattern in standardVersionRegExStrings) {
    if (RegExp('${strict ? '^' : ''}$pattern${strict ? '\$' : ''}')
        .hasMatch(version)) {
      results.add(pattern);
    }
  }
  return results;
}

moveStrToEnd(List<String> arr, String str, {String? strB}) {
  String? temp;
  arr.removeWhere((element) {
    bool res = element == str || element == strB;
    if (res) {
      temp = element;
    }
    return res;
  });
  if (temp != null) {
    arr = [...arr, temp!];
  }
  return arr;
}

List<MapEntry<String, int>> moveStrToEndMapEntryWithCount(
    List<MapEntry<String, int>> arr, MapEntry<String, int> str,
    {MapEntry<String, int>? strB}) {
  MapEntry<String, int>? temp;
  arr.removeWhere((element) {
    bool resA = element.key == str.key;
    bool resB = element.key == strB?.key;
    if (resA) {
      temp = str;
    } else if (resB) {
      temp = strB;
    }
    return resA || resB;
  });
  if (temp != null) {
    arr = [...arr, temp!];
  }
  return arr;
}

Future<File> downloadFileWithRetry(String url, String fileName,
    bool fileNameHasExt, Function? onProgress, String destDir,
    {bool useExisting = true,
    Map<String, String>? headers,
    int retries = 3,
    bool allowInsecure = false,
    LogsProvider? logs}) async {
  try {
    return await downloadFile(
        url, fileName, fileNameHasExt, onProgress, destDir,
        useExisting: useExisting,
        headers: headers,
        allowInsecure: allowInsecure,
        logs: logs);
  } catch (e) {
    if (retries > 0 && e is ClientException) {
      await Future.delayed(const Duration(seconds: 5));
      return await downloadFileWithRetry(
          url, fileName, fileNameHasExt, onProgress, destDir,
          useExisting: useExisting,
          headers: headers,
          retries: (retries - 1),
          allowInsecure: allowInsecure,
          logs: logs);
    } else {
      rethrow;
    }
  }
}

String hashListOfLists(List<List<int>> data) {
  var bytes = utf8.encode(jsonEncode(data));
  var digest = sha256.convert(bytes);
  var hash = digest.toString();
  return hash.hashCode.toString();
}

Future<String> checkPartialDownloadHashDynamic(String url,
    {int startingSize = 1024,
    int lowerLimit = 128,
    Map<String, String>? headers,
    bool allowInsecure = false}) async {
  for (int i = startingSize; i >= lowerLimit; i -= 256) {
    List<String> ab = await Future.wait([
      checkPartialDownloadHash(url, i,
          headers: headers, allowInsecure: allowInsecure),
      checkPartialDownloadHash(url, i,
          headers: headers, allowInsecure: allowInsecure)
    ]);
    if (ab[0] == ab[1]) {
      return ab[0];
    }
  }
  throw NoVersionError();
}

Future<String> checkPartialDownloadHash(String url, int bytesToGrab,
    {Map<String, String>? headers, bool allowInsecure = false}) async {
  var req = Request('GET', Uri.parse(url));
  if (headers != null) {
    req.headers.addAll(headers);
  }
  req.headers[HttpHeaders.rangeHeader] = 'bytes=0-$bytesToGrab';
  var client = IOClient(createHttpClient(allowInsecure));
  var response = await client.send(req);
  if (response.statusCode < 200 || response.statusCode > 299) {
    throw ObtainiumError(response.reasonPhrase ?? tr('unexpectedError'));
  }
  List<List<int>> bytes = await response.stream.take(bytesToGrab).toList();
  return hashListOfLists(bytes);
}

Future<File> downloadFile(String url, String fileName, bool fileNameHasExt,
    Function? onProgress, String destDir,
    {bool useExisting = true,
    Map<String, String>? headers,
    bool allowInsecure = false,
    LogsProvider? logs}) async {
  // Send the initial request but cancel it as soon as you have the headers
  var reqHeaders = headers ?? {};
  var req = Request('GET', Uri.parse(url));
  req.headers.addAll(reqHeaders);
  var client = IOClient(createHttpClient(allowInsecure));
  StreamedResponse response = await client.send(req);
  var resHeaders = response.headers;

  // Use the headers to decide what the file extension is, and
  // whether it supports partial downloads (range request), and
  // what the total size of the file is (if provided)
  String ext = resHeaders['content-disposition']?.split('.').last ?? 'apk';
  if (ext.endsWith('"') || ext.endsWith("other")) {
    ext = ext.substring(0, ext.length - 1);
  }
  if (((Uri.tryParse(url)?.path ?? url).toLowerCase().endsWith('.apk') ||
          ext == 'attachment') &&
      ext != 'apk') {
    ext = 'apk';
  }
  fileName = fileNameHasExt
      ? fileName
      : fileName.split('/').last; // Ensure the fileName is a file name
  File downloadedFile = File('$destDir/$fileName.$ext');
  if (fileNameHasExt) {
    // If the user says the filename already has an ext, ignore whatever you inferred from above
    downloadedFile = File('$destDir/$fileName');
  }

  bool rangeFeatureEnabled = false;
  if (resHeaders['accept-ranges']?.isNotEmpty == true) {
    rangeFeatureEnabled =
        resHeaders['accept-ranges']?.trim().toLowerCase() == 'bytes';
  }

  // If you have an existing file that is usable,
  // decide whether you can use it (either return full or resume partial)
  var fullContentLength = response.contentLength;
  if (useExisting && downloadedFile.existsSync()) {
    var length = downloadedFile.lengthSync();
    if (fullContentLength == null || !rangeFeatureEnabled) {
      // If there is no content length reported, assume it the existing file is fully downloaded
      // Also if the range feature is not supported, don't trust the content length if any (#1542)
      client.close();
      return downloadedFile;
    } else {
      // Check if resume needed/possible
      if (length == fullContentLength) {
        client.close();
        return downloadedFile;
      }
      if (length > fullContentLength) {
        useExisting = false;
      }
    }
  }

  // Download to a '.temp' file (to distinguish btn. complete/incomplete files)
  File tempDownloadedFile = File('${downloadedFile.path}.part');

  // If there is already a temp file, a download may already be in progress - account for this (see #2073)
  bool tempFileExists = tempDownloadedFile.existsSync();
  if (tempFileExists && useExisting) {
    logs?.add(
        'Partial download exists - will wait: ${tempDownloadedFile.uri.pathSegments.last}');
    bool isDownloading = true;
    int currentTempFileSize = await tempDownloadedFile.length();
    bool shouldReturn = false;
    while (isDownloading) {
      await Future.delayed(Duration(seconds: 7));
      if (tempDownloadedFile.existsSync()) {
        int newTempFileSize = await tempDownloadedFile.length();
        if (newTempFileSize > currentTempFileSize) {
          currentTempFileSize = newTempFileSize;
          logs?.add(
              'Existing partial download still in progress: ${tempDownloadedFile.uri.pathSegments.last}');
        } else {
          logs?.add(
              'Ignoring existing partial download: ${tempDownloadedFile.uri.pathSegments.last}');
          break;
        }
      } else {
        shouldReturn = downloadedFile.existsSync();
      }
    }
    if (shouldReturn) {
      logs?.add(
          'Existing partial download completed - not repeating: ${tempDownloadedFile.uri.pathSegments.last}');
      client.close();
      return downloadedFile;
    } else {
      logs?.add(
          'Existing partial download not in progress: ${tempDownloadedFile.uri.pathSegments.last}');
    }
  }

  // If the range feature is not available (or you need to start a ranged req from 0),
  // complete the already-started request, else cancel it and start a ranged request,
  // and open the file for writing in the appropriate mode
  var targetFileLength = useExisting && tempDownloadedFile.existsSync()
      ? tempDownloadedFile.lengthSync()
      : null;
  int rangeStart = targetFileLength ?? 0;
  IOSink? sink;
  if (rangeFeatureEnabled && fullContentLength != null && rangeStart > 0) {
    client.close();
    client = IOClient(createHttpClient(allowInsecure));
    req = Request('GET', Uri.parse(url));
    req.headers.addAll(reqHeaders);
    req.headers.addAll({'range': 'bytes=$rangeStart-${fullContentLength - 1}'});
    response = await client.send(req);
    sink = tempDownloadedFile.openWrite(mode: FileMode.writeOnlyAppend);
  } else if (tempDownloadedFile.existsSync()) {
    tempDownloadedFile.deleteSync(recursive: true);
  }
  sink ??= tempDownloadedFile.openWrite(mode: FileMode.writeOnly);

  // Perform the download
  var received = 0;
  double? progress;
  DateTime? lastProgressUpdate; // Track last progress update time
  if (rangeStart > 0 && fullContentLength != null) {
    received = rangeStart;
  }
  const downloadUIUpdateInterval = Duration(milliseconds: 500);
  const downloadBufferSize = 32 * 1024; // 32KB
  final downloadBuffer = BytesBuilder();
  await response.stream
      .map((chunk) {
        received += chunk.length;
        final now = DateTime.now();
        if (onProgress != null &&
            (lastProgressUpdate == null ||
                now.difference(lastProgressUpdate!) >=
                    downloadUIUpdateInterval)) {
          progress = fullContentLength != null
              ? (received / fullContentLength) * 100
              : 30;
          onProgress(progress);
          lastProgressUpdate = now;
        }
        return chunk;
      })
      .transform(StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (List<int> data, EventSink<List<int>> s) {
          downloadBuffer.add(data);
          if (downloadBuffer.length >= downloadBufferSize) {
            s.add(downloadBuffer.takeBytes());
          }
        },
        handleDone: (EventSink<List<int>> s) {
          if (downloadBuffer.isNotEmpty) {
            s.add(downloadBuffer.takeBytes());
          }
          s.close();
        },
      ))
      .pipe(sink);
  await sink.close();
  progress = null;
  if (onProgress != null) {
    onProgress(progress);
  }
  if (response.statusCode < 200 || response.statusCode > 299) {
    tempDownloadedFile.deleteSync(recursive: true);
    throw response.reasonPhrase ?? tr('unexpectedError');
  }
  if (tempDownloadedFile.existsSync()) {
    tempDownloadedFile.renameSync(downloadedFile.path);
  }
  client.close();
  return downloadedFile;
}

Future<Map<String, String>> getHeaders(String url,
    {Map<String, String>? headers, bool allowInsecure = false}) async {
  var req = http.Request('GET', Uri.parse(url));
  if (headers != null) {
    req.headers.addAll(headers);
  }
  var client = IOClient(createHttpClient(allowInsecure));
  var response = await client.send(req);
  if (response.statusCode < 200 || response.statusCode > 299) {
    throw ObtainiumError(response.reasonPhrase ?? tr('unexpectedError'));
  }
  var returnHeaders = response.headers;
  client.close();
  return returnHeaders;
}

Future<List<PackageInfo>> getAllInstalledInfo() async {
  return await pm.getInstalledPackages() ?? [];
}

Future<PackageInfo?> getInstalledInfo(String? packageName,
    {bool printErr = true}) async {
  if (packageName != null) {
    try {
      return await pm.getPackageInfo(packageName: packageName);
    } catch (e) {
      if (printErr) {
        print(e); // OK
      }
    }
  }
  return null;
}

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
  late Directory APKDir;
  late Directory iconsCacheDir;
  late SettingsProvider settingsProvider = SettingsProvider();

  Iterable<AppInMemory> getAppValues() => apps.values.map((a) => a.deepCopy());

  AppsProvider({isBg = false}) {
    // Subscribe to changes in the app foreground status
    foregroundStream = FGBGEvents.instance.stream.asBroadcastStream();
    foregroundSubscription = foregroundStream?.listen((event) async {
      isForeground = event == FGBGType.foreground;
      if (isForeground) {
        await loadApps();
      }
    });
    () async {
      await settingsProvider.initializeSettings();
      var cacheDirs = await getExternalCacheDirectories();
      if (cacheDirs?.isNotEmpty ?? false) {
        APKDir = cacheDirs!.first;
        iconsCacheDir = Directory('${cacheDirs.first.path}/icons');
        if (!iconsCacheDir.existsSync()) {
          iconsCacheDir.createSync();
        }
      } else {
        APKDir =
            Directory('${(await getExternalStorageDirectory())!.path}/apks');
        if (!APKDir.existsSync()) {
          APKDir.createSync();
        }
        iconsCacheDir =
            Directory('${(await getExternalStorageDirectory())!.path}/icons');
        if (!iconsCacheDir.existsSync()) {
          iconsCacheDir.createSync();
        }
      }
      if (!isBg) {
        // Load Apps into memory (in background processes, this is done later instead of in the constructor)
        await loadApps();
        // Delete any partial APKs (if safe to do so)
        var cutoff = DateTime.now().subtract(const Duration(days: 7));
        APKDir.listSync()
            .where((element) => element.statSync().modified.isBefore(cutoff))
            .forEach((partialApk) {
          if (!areDownloadsRunning()) {
            partialApk.delete(recursive: true);
          }
        });
      }
    }();
  }

  Future<File> handleAPKIDChange(App app, PackageInfo newInfo,
      File downloadedFile, String downloadUrl) async {
    // If the APK package ID is different from the App ID, it is either new (using a placeholder ID) or the ID has changed
    // The former case should be handled (give the App its real ID), the latter is a security issue
    var isTempIdBool = isTempId(app);
    if (app.id != newInfo.packageName) {
      if (apps[app.id] != null && !isTempIdBool && !app.allowIdChange) {
        throw IDChangedError(newInfo.packageName!);
      }
      var idChangeWasAllowed = app.allowIdChange;
      app.allowIdChange = false;
      var originalAppId = app.id;
      app.id = newInfo.packageName!;
      downloadedFile = downloadedFile.renameSync(
          '${downloadedFile.parent.path}/${app.id}-${downloadUrl.hashCode}.${downloadedFile.path.split('.').last}');
      if (apps[originalAppId] != null) {
        await removeApps([originalAppId]);
        await saveApps([app],
            onlyIfExists: !isTempIdBool && !idChangeWasAllowed);
      }
    }
    return downloadedFile;
  }

  Future<Object> downloadApp(App app, BuildContext? context,
      {NotificationsProvider? notificationsProvider,
      bool useExisting = true}) async {
    var notifId = DownloadNotification(app.finalName, 0).id;
    if (apps[app.id] != null) {
      apps[app.id]!.downloadProgress = 0;
      notifyListeners();
    }
    try {
      AppSource source = SourceProvider()
          .getSource(app.url, overrideSource: app.overrideSource);
      String downloadUrl = await source.apkUrlPrefetchModifier(
          app.apkUrls[app.preferredApkIndex].value,
          app.url,
          app.additionalSettings);
      var notif = DownloadNotification(app.finalName, 100);
      notificationsProvider?.cancel(notif.id);
      int? prevProg;
      var fileNameNoExt = '${app.id}-${downloadUrl.hashCode}';
      if (source.urlsAlwaysHaveExtension) {
        fileNameNoExt =
            '$fileNameNoExt.${app.apkUrls[app.preferredApkIndex].key.split('.').last}';
      }
      var headers = await source.getRequestHeaders(app.additionalSettings,
          forAPKDownload: true);
      var downloadedFile = await downloadFileWithRetry(
          downloadUrl, fileNameNoExt, source.urlsAlwaysHaveExtension,
          headers: headers, (double? progress) {
        int? prog = progress?.ceil();
        if (apps[app.id] != null) {
          apps[app.id]!.downloadProgress = progress;
          notifyListeners();
        }
        notif = DownloadNotification(app.finalName, prog ?? 100);
        if (prog != null && prevProg != prog) {
          notificationsProvider?.notify(notif);
        }
        prevProg = prog;
      }, APKDir.path,
          useExisting: useExisting,
          allowInsecure: app.additionalSettings['allowInsecure'] == true,
          logs: logs);
      // Set to 90 for remaining steps, will make null in 'finally'
      if (apps[app.id] != null) {
        apps[app.id]!.downloadProgress = -1;
        notifyListeners();
        notif = DownloadNotification(app.finalName, -1);
        notificationsProvider?.notify(notif);
      }
      PackageInfo? newInfo;
      var isAPK = downloadedFile.path.toLowerCase().endsWith('.apk');
      Directory? xapkDir;
      if (isAPK) {
        newInfo = await pm.getPackageArchiveInfo(
            archiveFilePath: downloadedFile.path);
      } else {
        // Assume XAPK
        String xapkDirPath = '${downloadedFile.path}-dir';
        await unzipFile(downloadedFile.path, '${downloadedFile.path}-dir');
        xapkDir = Directory(xapkDirPath);
        var apks = xapkDir
            .listSync()
            .where((e) => e.path.toLowerCase().endsWith('.apk'))
            .toList();

        FileSystemEntity? temp;
        apks.removeWhere((element) {
          bool res = element.uri.pathSegments.last.startsWith(app.id);
          if (res) {
            temp = element;
          }
          return res;
        });
        if (temp != null) {
          apks = [
            temp!,
            ...apks,
          ];
        }

        for (var i = 0; i < apks.length; i++) {
          try {
            newInfo =
                await pm.getPackageArchiveInfo(archiveFilePath: apks[i].path);
            if (newInfo != null) {
              break;
            }
          } catch (e) {
            if (i == apks.length - 1) {
              rethrow;
            }
          }
        }
      }
      if (newInfo == null) {
        downloadedFile.delete();
        throw ObtainiumError('Could not get ID from APK');
      }
      downloadedFile =
          await handleAPKIDChange(app, newInfo, downloadedFile, downloadUrl);
      // Delete older versions of the file if any
      for (var file in downloadedFile.parent.listSync()) {
        var fn = file.path.split('/').last;
        if (fn.startsWith('${app.id}-') &&
            FileSystemEntity.isFileSync(file.path) &&
            file.path != downloadedFile.path) {
          file.delete(recursive: true);
        }
      }
      if (isAPK) {
        return DownloadedApk(app.id, downloadedFile);
      } else {
        return DownloadedXApkDir(app.id, downloadedFile, xapkDir!);
      }
    } finally {
      notificationsProvider?.cancel(notifId);
      if (apps[app.id] != null) {
        apps[app.id]!.downloadProgress = null;
        notifyListeners();
      }
    }
  }

  bool areDownloadsRunning() => apps.values
      .where((element) => element.downloadProgress != null)
      .isNotEmpty;

  Future<bool> canInstallSilently(App app) async {
    if (!settingsProvider.enableBackgroundUpdates) {
      return false;
    }
    if (app.additionalSettings['exemptFromBackgroundUpdates'] == true) {
      logs.add('Exempted from BG updates: ${app.id}');
      return false;
    }
    if (app.apkUrls.length > 1) {
      logs.add('Multiple APK URLs: ${app.id}');
      return false; // Manual API selection means silent install is not possible
    }

    var osInfo = await DeviceInfoPlugin().androidInfo;
    String? installerPackageName;
    try {
      installerPackageName = osInfo.version.sdkInt >= 30
          ? (await pm.getInstallSourceInfo(packageName: app.id))
              ?.installingPackageName
          : (await pm.getInstallerPackageName(packageName: app.id));
    } catch (e) {
      logs.add(
          'Failed to get installed package details: ${app.id} (${e.toString()})');
      return false; // App probably not installed
    }

    int? targetSDK =
        (await getInstalledInfo(app.id))?.applicationInfo?.targetSdkVersion;
    // The APK should target a new enough API
    // https://developer.android.com/reference/android/content/pm/PackageInstaller.SessionParams#setRequireUserAction(int)
    if (!(targetSDK != null && targetSDK >= (osInfo.version.sdkInt - 3))) {
      logs.add('Multiple APK URLs: ${app.id}');
      return false;
    }

    if (settingsProvider.useShizuku) {
      return true;
    }

    if (app.id == obtainiumId) {
      return false;
    }
    if (installerPackageName != obtainiumId) {
      // If we did not install the app, silent install is not possible
      return false;
    }
    if (osInfo.version.sdkInt < 31) {
      // The OS must also be new enough
      logs.add('Android SDK too old: ${osInfo.version.sdkInt}');
      return false;
    }
    return true;
  }

  Future<void> waitForUserToReturnToForeground(BuildContext context) async {
    NotificationsProvider notificationsProvider =
        context.read<NotificationsProvider>();
    if (!isForeground) {
      await notificationsProvider.notify(completeInstallationNotification,
          cancelExisting: true);
      while (await FGBGEvents.instance.stream.first != FGBGType.foreground) {}
      await notificationsProvider.cancel(completeInstallationNotification.id);
    }
  }

  Future<bool> canDowngradeApps() async =>
      (await getInstalledInfo('com.berdik.letmedowngrade')) != null;

  Future<void> unzipFile(String filePath, String destinationPath) async {
    await ZipFile.extractToDirectory(
        zipFile: File(filePath), destinationDir: Directory(destinationPath));
  }

  Future<bool> installXApkDir(
      DownloadedXApkDir dir, BuildContext? firstTimeWithContext,
      {bool needsBGWorkaround = false,
      bool shizukuPretendToBeGooglePlay = false}) async {
    // We don't know which APKs in an XAPK are supported by the user's device
    // So we try installing all of them and assume success if at least one installed
    // If 0 APKs installed, throw the first install error encountered
    var somethingInstalled = false;
    try {
      MultiAppMultiError errors = MultiAppMultiError();
      List<File> APKFiles = [];
      for (var file in dir.extracted
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()) {
        if (file.path.toLowerCase().endsWith('.apk')) {
          APKFiles.add(file);
        } else if (file.path.toLowerCase().endsWith('.obb')) {
          await moveObbFile(file, dir.appId);
        }
      }

      File? temp;
      APKFiles.removeWhere((element) {
        bool res = element.uri.pathSegments.last.startsWith(dir.appId);
        if (res) {
          temp = element;
        }
        return res;
      });
      if (temp != null) {
        APKFiles = [
          temp!,
          ...APKFiles,
        ];
      }

      try {
        await installApk(
            DownloadedApk(dir.appId, APKFiles[0]), firstTimeWithContext,
            needsBGWorkaround: needsBGWorkaround,
            shizukuPretendToBeGooglePlay: shizukuPretendToBeGooglePlay,
            additionalAPKs: APKFiles.sublist(1)
                .map((a) => DownloadedApk(dir.appId, a))
                .toList());
        somethingInstalled = true;
        dir.file.delete(recursive: true);
      } catch (e) {
        logs.add('Could not install APKs from XAPK: ${e.toString()}');
        errors.add(dir.appId, e, appName: apps[dir.appId]?.name);
      }
      if (errors.idsByErrorString.isNotEmpty) {
        throw errors;
      }
    } finally {
      dir.extracted.delete(recursive: true);
    }
    return somethingInstalled;
  }

  Future<bool> installApk(
      DownloadedApk file, BuildContext? firstTimeWithContext,
      {bool needsBGWorkaround = false,
      bool shizukuPretendToBeGooglePlay = false,
      List<DownloadedApk> additionalAPKs = const []}) async {
    if (firstTimeWithContext != null &&
        settingsProvider.beforeNewInstallsShareToAppVerifier &&
        (await getInstalledInfo('dev.soupslurpr.appverifier')) != null) {
      XFile f = XFile.fromData(file.file.readAsBytesSync(),
          mimeType: 'application/vnd.android.package-archive');
      Fluttertoast.showToast(
          msg: tr('appVerifierInstructionToast'),
          toastLength: Toast.LENGTH_LONG);
      await Share.shareXFiles([f]);
    }
    var newInfo =
        await pm.getPackageArchiveInfo(archiveFilePath: file.file.path);
    if (newInfo == null) {
      try {
        file.file.deleteSync(recursive: true);
        additionalAPKs.forEach((a) => a.file.deleteSync(recursive: true));
      } catch (e) {
        //
      } finally {
        throw ObtainiumError(tr('badDownload'));
      }
    }
    PackageInfo? appInfo = await getInstalledInfo(apps[file.appId]!.app.id);
    logs.add(
        'Installing "${newInfo.packageName}" version "${newInfo.versionName}" versionCode "${newInfo.versionCode}"${appInfo != null ? ' (from existing version "${appInfo.versionName}" versionCode "${appInfo.versionCode}")' : ''}');
    if (appInfo != null &&
        newInfo.versionCode! < appInfo.versionCode! &&
        !(await canDowngradeApps())) {
      throw DowngradeError();
    }
    if (needsBGWorkaround) {
      // The below 'await' will never return if we are in a background process
      // To work around this, we should assume the install will be successful
      // So we update the app's installed version first as we will never get to the later code
      // We can't conditionally get rid of the 'await' as this causes install fails (BG process times out) - see #896
      // TODO: When fixed, update this function and the calls to it accordingly
      apps[file.appId]!.app.installedVersion =
          apps[file.appId]!.app.latestVersion;
      await saveApps([apps[file.appId]!.app],
          attemptToCorrectInstallStatus: false);
    }
    int? code;
    if (!settingsProvider.useShizuku) {
      var allAPKs = [file.file.path];
      allAPKs.addAll(additionalAPKs.map((a) => a.file.path));
      code = await AndroidPackageInstaller.installApk(
          apkFilePath: allAPKs.join(','));
    } else {
      code = await ShizukuApkInstaller.installAPK(file.file.uri.toString(),
          shizukuPretendToBeGooglePlay ? "com.android.vending" : "");
    }
    bool installed = false;
    if (code != null && code != 0 && code != 3) {
      try {
        file.file.deleteSync(recursive: true);
      } catch (e) {
        //
      } finally {
        throw InstallError(code);
      }
    } else if (code == 0) {
      installed = true;
      apps[file.appId]!.app.installedVersion =
          apps[file.appId]!.app.latestVersion;
      file.file.delete(recursive: true);
    }
    await saveApps([apps[file.appId]!.app]);
    return installed;
  }

  Future<String> getStorageRootPath() async {
    return '/${(await getExternalStorageDirectory())!.uri.pathSegments.sublist(0, 3).join('/')}';
  }

  Future<void> moveObbFile(File file, String appId) async {
    if (!file.path.toLowerCase().endsWith('.obb')) return;

    // TODO: Does not support Android 11+
    if ((await DeviceInfoPlugin().androidInfo).version.sdkInt <= 29) {
      await Permission.storage.request();
    }

    String obbDirPath = "${await getStorageRootPath()}/Android/obb/$appId";
    Directory(obbDirPath).createSync(recursive: true);

    String obbFileName = file.path.split("/").last;
    await file.copy("$obbDirPath/$obbFileName");
  }

  void uninstallApp(String appId) async {
    var intent = AndroidIntent(
        action: 'android.intent.action.DELETE',
        data: 'package:$appId',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        package: 'vnd.android.package-archive');
    await intent.launch();
  }

  Future<MapEntry<String, String>?> confirmAppFileUrl(
      App app, BuildContext? context, bool pickAnyAsset,
      {bool evenIfSingleChoice = false}) async {
    var urlsToSelectFrom = app.apkUrls;
    if (pickAnyAsset) {
      urlsToSelectFrom = [...urlsToSelectFrom, ...app.otherAssetUrls];
    }
    // If the App has more than one APK, the user should pick one (if context provided)
    MapEntry<String, String>? appFileUrl = urlsToSelectFrom[
        app.preferredApkIndex >= 0 ? app.preferredApkIndex : 0];
    // get device supported architecture
    List<String> archs = (await DeviceInfoPlugin().androidInfo).supportedAbis;

    if ((urlsToSelectFrom.length > 1 || evenIfSingleChoice) &&
        context != null) {
      appFileUrl = await showDialog(
          // ignore: use_build_context_synchronously
          context: context,
          builder: (BuildContext ctx) {
            return AppFilePicker(
              app: app,
              initVal: appFileUrl,
              archs: archs,
              pickAnyAsset: pickAnyAsset,
            );
          });
    }
    getHost(String url) {
      var temp = Uri.parse(url).host.split('.');
      return temp.sublist(temp.length - 2).join('.');
    }

    // If the picked APK comes from an origin different from the source, get user confirmation (if context provided)
    if (appFileUrl != null &&
        getHost(appFileUrl.value) != getHost(app.url) &&
        context != null) {
      if (!(settingsProvider.hideAPKOriginWarning) &&
          await showDialog(
                  // ignore: use_build_context_synchronously
                  context: context,
                  builder: (BuildContext ctx) {
                    return APKOriginWarningDialog(
                        sourceUrl: app.url, apkUrl: appFileUrl!.value);
                  }) !=
              true) {
        appFileUrl = null;
      }
    }
    return appFileUrl;
  }

  // Given a list of AppIds, uses stored info about the apps to download APKs and install them
  // If the APKs can be installed silently, they are
  // If no BuildContext is provided, apps that require user interaction are ignored
  // If user input is needed and the App is in the background, a notification is sent to get the user's attention
  // Returns an array of Ids for Apps that were successfully downloaded, regardless of installation result
  Future<List<String>> downloadAndInstallLatestApps(
      List<String> appIds, BuildContext? context,
      {NotificationsProvider? notificationsProvider,
      bool forceParallelDownloads = false,
      bool useExisting = true}) async {
    notificationsProvider =
        notificationsProvider ?? context?.read<NotificationsProvider>();
    List<String> appsToInstall = [];
    List<String> trackOnlyAppsToUpdate = [];
    // For all specified Apps, filter out those for which:
    // 1. A URL cannot be picked
    // 2. That cannot be installed silently (IF no buildContext was given for interactive install)
    for (var id in appIds) {
      if (apps[id] == null) {
        throw ObtainiumError(tr('appNotFound'));
      }
      MapEntry<String, String>? apkUrl;
      var trackOnly = apps[id]!.app.additionalSettings['trackOnly'] == true;
      var refreshBeforeDownload =
          apps[id]!.app.additionalSettings['refreshBeforeDownload'] == true;
      if (refreshBeforeDownload) {
        await checkUpdate(apps[id]!.app.id);
      }
      if (!trackOnly) {
        // ignore: use_build_context_synchronously
        apkUrl = await confirmAppFileUrl(apps[id]!.app, context, false);
      }
      if (apkUrl != null) {
        int urlInd = apps[id]!
            .app
            .apkUrls
            .map((e) => e.value)
            .toList()
            .indexOf(apkUrl.value);
        if (urlInd >= 0 && urlInd != apps[id]!.app.preferredApkIndex) {
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

    // Prepare to download+install Apps
    MultiAppMultiError errors = MultiAppMultiError();
    List<String> installedIds = [];

    // Move Obtainium to the end of the line (let all other apps update first)
    appsToInstall =
        moveStrToEnd(appsToInstall, obtainiumId, strB: obtainiumTempId);

    Future<void> installFn(String id, bool willBeSilent,
        DownloadedApk? downloadedFile, DownloadedXApkDir? downloadedDir) async {
      apps[id]?.downloadProgress = -1;
      notifyListeners();
      try {
        bool sayInstalled = true;
        var contextIfNewInstall =
            apps[id]?.installedInfo == null ? context : null;
        bool needBGWorkaround =
            willBeSilent && context == null && !settingsProvider.useShizuku;
        bool shizukuPretendToBeGooglePlay = settingsProvider
                .shizukuPretendToBeGooglePlay ||
            apps[id]!.app.additionalSettings['shizukuPretendToBeGooglePlay'] ==
                true;
        if (downloadedFile != null) {
          if (needBGWorkaround) {
            // ignore: use_build_context_synchronously
            installApk(downloadedFile, contextIfNewInstall,
                needsBGWorkaround: true,
                shizukuPretendToBeGooglePlay: shizukuPretendToBeGooglePlay);
          } else {
            // ignore: use_build_context_synchronously
            sayInstalled = await installApk(downloadedFile, contextIfNewInstall,
                shizukuPretendToBeGooglePlay: shizukuPretendToBeGooglePlay);
          }
        } else {
          if (needBGWorkaround) {
            // ignore: use_build_context_synchronously
            installXApkDir(downloadedDir!, contextIfNewInstall,
                needsBGWorkaround: true);
          } else {
            // ignore: use_build_context_synchronously
            sayInstalled = await installXApkDir(
                downloadedDir!, contextIfNewInstall,
                shizukuPretendToBeGooglePlay: shizukuPretendToBeGooglePlay);
          }
        }
        if (willBeSilent && context == null) {
          if (!settingsProvider.useShizuku) {
            notificationsProvider?.notify(SilentUpdateAttemptNotification(
                [apps[id]!.app],
                id: id.hashCode));
          } else {
            notificationsProvider?.notify(SilentUpdateNotification(
                [apps[id]!.app], sayInstalled,
                id: id.hashCode));
          }
        }
        if (sayInstalled) {
          installedIds.add(id);
        }
      } finally {
        apps[id]?.downloadProgress = null;
        notifyListeners();
      }
    }

    Future<Map<Object?, Object?>> downloadFn(String id,
        {bool skipInstalls = false}) async {
      bool willBeSilent = false;
      DownloadedApk? downloadedFile;
      DownloadedXApkDir? downloadedDir;
      try {
        var downloadedArtifact =
            // ignore: use_build_context_synchronously
            await downloadApp(apps[id]!.app, context,
                notificationsProvider: notificationsProvider,
                useExisting: useExisting);
        if (downloadedArtifact is DownloadedApk) {
          downloadedFile = downloadedArtifact;
        } else {
          downloadedDir = downloadedArtifact as DownloadedXApkDir;
        }
        id = downloadedFile?.appId ?? downloadedDir!.appId;
        willBeSilent = await canInstallSilently(apps[id]!.app);
        if (!settingsProvider.useShizuku) {
          if (!(await settingsProvider.getInstallPermission(enforce: false))) {
            throw ObtainiumError(tr('cancelled'));
          }
        } else {
          switch ((await ShizukuApkInstaller.checkPermission())!) {
            case 'binder_not_found':
              throw ObtainiumError(tr('shizukuBinderNotFound'));
            case 'old_shizuku':
              throw ObtainiumError(tr('shizukuOld'));
            case 'old_android_with_adb':
              throw ObtainiumError(tr('shizukuOldAndroidWithADB'));
            case 'denied':
              throw ObtainiumError(tr('cancelled'));
          }
        }
        if (!willBeSilent && context != null && !settingsProvider.useShizuku) {
          // ignore: use_build_context_synchronously
          await waitForUserToReturnToForeground(context);
        }
      } catch (e) {
        errors.add(id, e, appName: apps[id]?.name);
      }
      return {
        'id': id,
        'willBeSilent': willBeSilent,
        'downloadedFile': downloadedFile,
        'downloadedDir': downloadedDir
      };
    }

    List<Map<Object?, Object?>> downloadResults = [];
    if (forceParallelDownloads || !settingsProvider.parallelDownloads) {
      for (var id in appsToInstall) {
        downloadResults.add(await downloadFn(id));
      }
    } else {
      downloadResults = await Future.wait(
          appsToInstall.map((id) => downloadFn(id, skipInstalls: true)));
    }
    for (var res in downloadResults) {
      if (!errors.appIdNames.containsKey(res['id'])) {
        try {
          await installFn(
              res['id'] as String,
              res['willBeSilent'] as bool,
              res['downloadedFile'] as DownloadedApk?,
              res['downloadedDir'] as DownloadedXApkDir?);
        } catch (e) {
          var id = res['id'] as String;
          errors.add(id, e, appName: apps[id]?.name);
        }
      }
    }

    if (errors.idsByErrorString.isNotEmpty) {
      throw errors;
    }

    return installedIds;
  }

  Future<List<String>> downloadAppAssets(
      List<String> appIds, BuildContext context,
      {bool forceParallelDownloads = false}) async {
    NotificationsProvider notificationsProvider =
        context.read<NotificationsProvider>();
    List<MapEntry<MapEntry<String, String>, App>> filesToDownload = [];
    for (var id in appIds) {
      if (apps[id] == null) {
        throw ObtainiumError(tr('appNotFound'));
      }
      MapEntry<String, String>? fileUrl;
      var refreshBeforeDownload =
          apps[id]!.app.additionalSettings['refreshBeforeDownload'] == true;
      if (refreshBeforeDownload) {
        await checkUpdate(apps[id]!.app.id);
      }
      if (apps[id]!.app.apkUrls.isNotEmpty ||
          apps[id]!.app.otherAssetUrls.isNotEmpty) {
        // ignore: use_build_context_synchronously
        MapEntry<String, String>? tempFileUrl = await confirmAppFileUrl(
            apps[id]!.app, context, true,
            evenIfSingleChoice: true);
        if (tempFileUrl != null) {
          fileUrl = MapEntry(
              tempFileUrl.key,
              await (SourceProvider().getSource(apps[id]!.app.url,
                      overrideSource: apps[id]!.app.overrideSource))
                  .apkUrlPrefetchModifier(tempFileUrl.value, apps[id]!.app.url,
                      apps[id]!.app.additionalSettings));
        }
      }
      if (fileUrl != null) {
        filesToDownload.add(MapEntry(fileUrl, apps[id]!.app));
      }
    }

    // Prepare to download+install Apps
    MultiAppMultiError errors = MultiAppMultiError();
    List<String> downloadedIds = [];

    Future<void> downloadFn(MapEntry<String, String> fileUrl, App app) async {
      try {
        String downloadPath = '${await getStorageRootPath()}/Download';
        await downloadFile(fileUrl.value, fileUrl.key, true,
            (double? progress) {
          notificationsProvider
              .notify(DownloadNotification(fileUrl.key, progress?.ceil() ?? 0));
        }, downloadPath,
            headers: await SourceProvider()
                .getSource(app.url, overrideSource: app.overrideSource)
                .getRequestHeaders(app.additionalSettings,
                    forAPKDownload:
                        fileUrl.key.endsWith('.apk') ? true : false),
            useExisting: false,
            allowInsecure: app.additionalSettings['allowInsecure'] == true,
            logs: logs);
        notificationsProvider
            .notify(DownloadedNotification(fileUrl.key, fileUrl.value));
      } catch (e) {
        errors.add(fileUrl.key, e);
      } finally {
        notificationsProvider.cancel(DownloadNotification(fileUrl.key, 0).id);
      }
    }

    if (forceParallelDownloads || !settingsProvider.parallelDownloads) {
      for (var urlWithApp in filesToDownload) {
        await downloadFn(urlWithApp.key, urlWithApp.value);
      }
    } else {
      await Future.wait(filesToDownload
          .map((urlWithApp) => downloadFn(urlWithApp.key, urlWithApp.value)));
    }
    if (errors.idsByErrorString.isNotEmpty) {
      throw errors;
    }
    return downloadedIds;
  }

  Future<Directory> getAppsDir() async {
    Directory appsDir =
        Directory('${(await getExternalStorageDirectory())!.path}/app_data');
    if (!appsDir.existsSync()) {
      appsDir.createSync();
    }
    return appsDir;
  }

  bool isVersionDetectionPossible(AppInMemory? app) {
    if (app?.app == null) {
      return false;
    }
    var source = SourceProvider()
        .getSource(app!.app.url, overrideSource: app.app.overrideSource);
    var naiveStandardVersionDetection =
        app.app.additionalSettings['naiveStandardVersionDetection'] == true ||
            source.naiveStandardVersionDetection;
    String? realInstalledVersion =
        app.app.additionalSettings['useVersionCodeAsOSVersion'] == true
            ? app.installedInfo?.versionCode.toString()
            : app.installedInfo?.versionName;
    bool isHTMLWithNoVersionDetection =
        (source.runtimeType == HTML().runtimeType &&
            (app.app.additionalSettings['versionExtractionRegEx'] as String?)
                    ?.isNotEmpty !=
                true);
    bool isDirectAPKLink = source.runtimeType == DirectAPKLink().runtimeType;
    return app.app.additionalSettings['trackOnly'] != true &&
        app.app.additionalSettings['releaseDateAsVersion'] != true &&
        !isHTMLWithNoVersionDetection &&
        !isDirectAPKLink &&
        realInstalledVersion != null &&
        app.app.installedVersion != null &&
        (reconcileVersionDifferences(
                    realInstalledVersion, app.app.installedVersion!) !=
                null ||
            naiveStandardVersionDetection);
  }

  // Given an App and it's on-device info...
  // Reconcile unexpected differences between its reported installed version, real installed version, and reported latest version
  App? getCorrectedInstallStatusAppIfPossible(
      App app, PackageInfo? installedInfo) {
    var modded = false;
    var trackOnly = app.additionalSettings['trackOnly'] == true;
    var versionDetectionIsStandard =
        app.additionalSettings['versionDetection'] == true;
    var naiveStandardVersionDetection =
        app.additionalSettings['naiveStandardVersionDetection'] == true ||
            SourceProvider()
                .getSource(app.url, overrideSource: app.overrideSource)
                .naiveStandardVersionDetection;
    String? realInstalledVersion =
        app.additionalSettings['useVersionCodeAsOSVersion'] == true
            ? installedInfo?.versionCode.toString()
            : installedInfo?.versionName;
    // FIRST, COMPARE THE APP'S REPORTED AND REAL INSTALLED VERSIONS, WHERE ONE IS NULL
    if (installedInfo == null && app.installedVersion != null && !trackOnly) {
      // App says it's installed but isn't really (and isn't track only) - set to not installed
      app.installedVersion = null;
      modded = true;
    } else if (realInstalledVersion != null && app.installedVersion == null) {
      // App says it's not installed but really is - set to installed and use real package versionName (or versionCode if chosen)
      app.installedVersion = realInstalledVersion;
      modded = true;
    }
    // SECOND, RECONCILE DIFFERENCES BETWEEN THE APP'S REPORTED AND REAL INSTALLED VERSIONS, WHERE NEITHER IS NULL
    if (realInstalledVersion != null &&
        realInstalledVersion != app.installedVersion &&
        versionDetectionIsStandard) {
      // App's reported version and real version don't match (and it uses standard version detection)
      // If they share a standard format (and are still different under it), update the reported version accordingly
      var correctedInstalledVersion = reconcileVersionDifferences(
          realInstalledVersion, app.installedVersion!);
      if (correctedInstalledVersion?.key == false) {
        app.installedVersion = correctedInstalledVersion!.value;
        modded = true;
      } else if (naiveStandardVersionDetection) {
        app.installedVersion = realInstalledVersion;
        modded = true;
      }
    }
    // THIRD, RECONCILE THE APP'S REPORTED INSTALLED AND LATEST VERSIONS
    if (app.installedVersion != null &&
        app.installedVersion != app.latestVersion &&
        versionDetectionIsStandard) {
      // App's reported installed and latest versions don't match (and it uses standard version detection)
      // If they share a standard format, make sure the App's reported installed version uses that format
      var correctedInstalledVersion =
          reconcileVersionDifferences(app.installedVersion!, app.latestVersion);
      if (correctedInstalledVersion?.key == true) {
        app.installedVersion = correctedInstalledVersion!.value;
        modded = true;
      }
    }
    // FOURTH, DISABLE VERSION DETECTION IF ENABLED AND THE REPORTED/REAL INSTALLED VERSIONS ARE NOT STANDARDIZED
    if (installedInfo != null &&
        versionDetectionIsStandard &&
        !isVersionDetectionPossible(
            AppInMemory(app, null, installedInfo, null))) {
      app.additionalSettings['versionDetection'] = false;
      app.installedVersion = app.latestVersion;
      logs.add('Could not reconcile version formats for: ${app.id}');
      modded = true;
    }

    return modded ? app : null;
  }

  MapEntry<bool, String>? reconcileVersionDifferences(
      String templateVersion, String comparisonVersion) {
    // Returns null if the versions don't share a common standard format
    // Returns <true, comparisonVersion> if they share a common format and are equal
    // Returns <false, templateVersion> if they share a common format but are not equal
    // templateVersion must fully match a standard format, while comparisonVersion can have a substring match
    var templateVersionFormats =
        findStandardFormatsForVersion(templateVersion, true);
    var comparisonVersionFormats =
        findStandardFormatsForVersion(comparisonVersion, false);
    var commonStandardFormats =
        templateVersionFormats.intersection(comparisonVersionFormats);
    if (commonStandardFormats.isEmpty) {
      return null;
    }
    for (String pattern in commonStandardFormats) {
      if (doStringsMatchUnderRegEx(
          pattern, comparisonVersion, templateVersion)) {
        return MapEntry(true, comparisonVersion);
      }
    }
    return MapEntry(false, templateVersion);
  }

  bool doStringsMatchUnderRegEx(String pattern, String value1, String value2) {
    var r = RegExp(pattern);
    var m1 = r.firstMatch(value1);
    var m2 = r.firstMatch(value2);
    return m1 != null && m2 != null
        ? value1.substring(m1.start, m1.end) ==
            value2.substring(m2.start, m2.end)
        : false;
  }

  Future<void> loadApps({String? singleId}) async {
    while (loadingApps) {
      await Future.delayed(const Duration(microseconds: 1));
    }
    loadingApps = true;
    notifyListeners();
    var sp = SourceProvider();
    List<List<String>> errors = [];
    var installedAppsData = await getAllInstalledInfo();
    List<String> removedAppIds = [];
    await Future.wait((await getAppsDir()) // Parse Apps from JSON
        .listSync()
        .map((item) async {
      App? app;
      if (item.path.toLowerCase().endsWith('.json') &&
          (singleId == null ||
              item.path.split('/').last.toLowerCase() ==
                  '${singleId.toLowerCase()}.json')) {
        try {
          app = App.fromJson(jsonDecode(File(item.path).readAsStringSync()));
        } catch (err) {
          if (err is FormatException) {
            logs.add('Corrupt JSON when loading App (will be ignored): $e');
            item.renameSync('${item.path}.corrupt');
          } else {
            rethrow;
          }
        }
      }
      if (app != null) {
        // Save the app to the in-memory list without grabbing any OS info first
        apps.update(
            app.id,
            (value) => AppInMemory(
                app!, value.downloadProgress, value.installedInfo, value.icon),
            ifAbsent: () => AppInMemory(app!, null, null, null));
        notifyListeners();
        try {
          // Try getting the app's source to ensure no invalid apps get loaded
          sp.getSource(app.url, overrideSource: app.overrideSource);
          // If the app is installed, grab its OS data and reconcile install statuses
          PackageInfo? installedInfo;
          try {
            installedInfo =
                installedAppsData.firstWhere((i) => i.packageName == app!.id);
          } catch (e) {
            // If the app isn't installed the above throws an error
          }
          // Reconcile differences between the installed and recorded install info
          var moddedApp =
              getCorrectedInstallStatusAppIfPossible(app, installedInfo);
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
              (value) => AppInMemory(
                  app!, value.downloadProgress, installedInfo, value.icon),
              ifAbsent: () => AppInMemory(app!, null, installedInfo, null));
          notifyListeners();
        } catch (e) {
          errors.add([app!.id, app.finalName, e.toString()]);
        }
      }
    }));
    if (errors.isNotEmpty) {
      removeApps(errors.map((e) => e[0]).toList());
      NotificationsProvider().notify(
          AppsRemovedNotification(errors.map((e) => [e[1], e[2]]).toList()));
    }
    // Delete externally uninstalled Apps if needed
    if (removedAppIds.isNotEmpty) {
      if (removedAppIds.isNotEmpty) {
        if (settingsProvider.removeOnExternalUninstall) {
          await removeApps(removedAppIds);
        }
      }
    }
    loadingApps = false;
    notifyListeners();
  }

  Future<void> updateAppIcon(String? appId, {bool ignoreCache = false}) async {
    if (apps[appId]?.icon == null) {
      var cachedIcon = File('${iconsCacheDir.path}/$appId.png');
      var alreadyCached = cachedIcon.existsSync() && !ignoreCache;
      var icon = alreadyCached
          ? (await cachedIcon.readAsBytes())
          : (await apps[appId]?.installedInfo?.applicationInfo?.getAppIcon());
      if (icon != null && !alreadyCached) {
        cachedIcon.writeAsBytes(icon.toList());
      }
      if (icon != null) {
        apps.update(
            apps[appId]!.app.id,
            (value) => AppInMemory(apps[appId]!.app, value.downloadProgress,
                value.installedInfo, icon),
            ifAbsent: () => AppInMemory(
                apps[appId]!.app, null, apps[appId]?.installedInfo, icon));
        notifyListeners();
      }
    }
  }

  Future<void> saveApps(List<App> apps,
      {bool attemptToCorrectInstallStatus = true,
      bool onlyIfExists = true}) async {
    attemptToCorrectInstallStatus = attemptToCorrectInstallStatus;
    await Future.wait(apps.map((a) async {
      var app = a.deepCopy();
      PackageInfo? info = await getInstalledInfo(app.id);
      var icon = await info?.applicationInfo?.getAppIcon();
      app.name = await (info?.applicationInfo?.getAppLabel()) ?? app.name;
      if (attemptToCorrectInstallStatus) {
        app = getCorrectedInstallStatusAppIfPossible(app, info) ?? app;
      }
      if (!onlyIfExists || this.apps.containsKey(app.id)) {
        String filePath = '${(await getAppsDir()).path}/${app.id}.json';
        File('$filePath.tmp')
            .writeAsStringSync(jsonEncode(app.toJson())); // #2089
        File('$filePath.tmp').renameSync(filePath);
      }
      try {
        this.apps.update(app.id,
            (value) => AppInMemory(app, value.downloadProgress, info, icon),
            ifAbsent:
                onlyIfExists ? null : () => AppInMemory(app, null, info, icon));
      } catch (e) {
        if (e is! ArgumentError || e.name != 'key') {
          rethrow;
        }
      }
    }));
    notifyListeners();
    export(isAuto: true);
  }

  Future<void> removeApps(List<String> appIds) async {
    var apkFiles = APKDir.listSync();
    await Future.wait(appIds.map((appId) async {
      File file = File('${(await getAppsDir()).path}/$appId.json');
      if (file.existsSync()) {
        file.deleteSync(recursive: true);
      }
      apkFiles
          .where(
              (element) => element.path.split('/').last.startsWith('$appId-'))
          .forEach((element) {
        element.delete(recursive: true);
      });
      if (apps.containsKey(appId)) {
        apps.remove(appId);
      }
    }));
    if (appIds.isNotEmpty) {
      notifyListeners();
      export(isAuto: true);
    }
  }

  Future<bool> removeAppsWithModal(BuildContext context, List<App> apps) async {
    var showUninstallOption = apps
        .where((a) =>
            a.installedVersion != null &&
            a.additionalSettings['trackOnly'] != true)
        .isNotEmpty;
    var values = await showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return GeneratedFormModal(
            primaryActionColour: Theme.of(context).colorScheme.error,
            title: plural('removeAppQuestion', apps.length),
            items: !showUninstallOption
                ? []
                : [
                    [
                      GeneratedFormSwitch('rmAppEntry',
                          label: tr('removeFromObtainium'), defaultValue: true)
                    ],
                    [
                      GeneratedFormSwitch('uninstallApp',
                          label: tr('uninstallFromDevice'))
                    ]
                  ],
            initValid: true,
          );
        });
    if (values != null) {
      bool uninstall = values['uninstallApp'] == true && showUninstallOption;
      bool remove = values['rmAppEntry'] == true || !showUninstallOption;
      if (uninstall) {
        for (var i = 0; i < apps.length; i++) {
          if (apps[i].installedVersion != null) {
            uninstallApp(apps[i].id);
            apps[i].installedVersion = null;
          }
        }
        await saveApps(apps, attemptToCorrectInstallStatus: false);
      }
      if (remove) {
        await removeApps(apps.map((e) => e.id).toList());
      }
      return uninstall || remove;
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

  addMissingCategories(SettingsProvider settingsProvider) {
    var cats = settingsProvider.categories;
    apps.forEach((key, value) {
      for (var c in value.app.categories) {
        if (!cats.containsKey(c)) {
          cats[c] = generateRandomLightColor().value;
        }
      }
    });
    settingsProvider.setCategories(cats, appsProvider: this);
  }

  Future<App?> checkUpdate(String appId) async {
    App? currentApp = apps[appId]!.app;
    SourceProvider sourceProvider = SourceProvider();
    App newApp = await sourceProvider.getApp(
        sourceProvider.getSource(currentApp.url,
            overrideSource: currentApp.overrideSource),
        currentApp.url,
        currentApp.additionalSettings,
        currentApp: currentApp);
    if (currentApp.preferredApkIndex < newApp.apkUrls.length) {
      newApp.preferredApkIndex = currentApp.preferredApkIndex;
    }
    await saveApps([newApp]);
    return newApp.latestVersion != currentApp.latestVersion ? newApp : null;
  }

  List<String> getAppsSortedByUpdateCheckTime(
      {DateTime? ignoreAppsCheckedAfter,
      bool onlyCheckInstalledOrTrackOnlyApps = false}) {
    List<String> appIds = apps.values
        .where((app) =>
            app.app.lastUpdateCheck == null ||
            ignoreAppsCheckedAfter == null ||
            app.app.lastUpdateCheck!.isBefore(ignoreAppsCheckedAfter))
        .where((app) {
          if (!onlyCheckInstalledOrTrackOnlyApps) {
            return true;
          } else {
            return app.app.installedVersion != null ||
                app.app.additionalSettings['trackOnly'] == true;
          }
        })
        .map((e) => e.app.id)
        .toList();
    appIds.sort((a, b) =>
        (apps[a]!.app.lastUpdateCheck ?? DateTime.fromMicrosecondsSinceEpoch(0))
            .compareTo(apps[b]!.app.lastUpdateCheck ??
                DateTime.fromMicrosecondsSinceEpoch(0)));
    return appIds;
  }

  Future<List<App>> checkUpdates(
      {DateTime? ignoreAppsCheckedAfter,
      bool throwErrorsForRetry = false,
      List<String>? specificIds,
      SettingsProvider? sp}) async {
    SettingsProvider settingsProvider = sp ?? this.settingsProvider;
    List<App> updates = [];
    MultiAppMultiError errors = MultiAppMultiError();
    if (!gettingUpdates) {
      gettingUpdates = true;
      try {
        List<String> appIds = getAppsSortedByUpdateCheckTime(
            ignoreAppsCheckedAfter: ignoreAppsCheckedAfter,
            onlyCheckInstalledOrTrackOnlyApps:
                settingsProvider.onlyCheckInstalledOrTrackOnlyApps);
        if (specificIds != null) {
          appIds = appIds.where((aId) => specificIds.contains(aId)).toList();
        }
        await Future.wait(appIds.map((appId) async {
          App? newApp;
          try {
            newApp = await checkUpdate(appId);
          } catch (e) {
            if ((e is RateLimitError || e is SocketException) &&
                throwErrorsForRetry) {
              rethrow;
            }
            errors.add(appId, e, appName: apps[appId]?.name);
          }
          if (newApp != null) {
            updates.add(newApp);
          }
        }), eagerError: true);
      } finally {
        gettingUpdates = false;
      }
    }
    if (errors.idsByErrorString.isNotEmpty) {
      var res = <String, dynamic>{};
      res['errors'] = errors;
      res['updates'] = updates;
      throw res;
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

  Map<String, dynamic> generateExportJSON(
      {List<String>? appIds, bool? overrideExportSettings}) {
    Map<String, dynamic> finalExport = {};
    finalExport['apps'] = apps.values
        .where((e) {
          if (appIds == null) {
            return true;
          } else {
            return appIds.contains(e.app.id);
          }
        })
        .map((e) => e.app.toJson())
        .toList();
    bool shouldExportSettings = settingsProvider.exportSettings;
    if (overrideExportSettings != null) {
      shouldExportSettings = overrideExportSettings;
    }
    if (shouldExportSettings) {
      finalExport['settings'] = Map<String, Object?>.fromEntries(
          (settingsProvider.prefs
                  ?.getKeys()
                  .map((key) => MapEntry(key, settingsProvider.prefs?.get(key)))
                  .toList()) ??
              []);
    }
    return finalExport;
  }

  Future<String?> export(
      {bool pickOnly = false, isAuto = false, SettingsProvider? sp}) async {
    SettingsProvider settingsProvider = sp ?? this.settingsProvider;
    var exportDir = await settingsProvider.getExportDir();
    if (isAuto) {
      if (settingsProvider.autoExportOnChanges != true) {
        return null;
      }
      if (exportDir == null) {
        return null;
      }
      var files = await saf
          .listFiles(exportDir, columns: [saf.DocumentFileColumn.id])
          .where((f) => f.uri.pathSegments.last.endsWith('-auto.json'))
          .toList();
      if (files.isNotEmpty) {
        for (var f in files) {
          saf.delete(f.uri);
        }
      }
    }
    if (exportDir == null || pickOnly) {
      await settingsProvider.pickExportDir();
      exportDir = await settingsProvider.getExportDir();
    }
    if (exportDir == null) {
      return null;
    }
    String? returnPath;
    if (!pickOnly) {
      var encoder = const JsonEncoder.withIndent("    ");
      Map<String, dynamic> finalExport = generateExportJSON();
      var result = await saf.createFile(exportDir,
          displayName:
              '${tr('obtainiumExportHyphenatedLowercase')}-${DateTime.now().toIso8601String().replaceAll(':', '-')}${isAuto ? '-auto' : ''}.json',
          mimeType: 'application/json',
          bytes: Uint8List.fromList(utf8.encode(encoder.convert(finalExport))));
      if (result == null) {
        throw ObtainiumError(tr('unexpectedError'));
      }
      returnPath =
          exportDir.pathSegments.join('/').replaceFirst('tree/primary:', '/');
    }
    return returnPath;
  }

  Future<MapEntry<List<App>, bool>> import(String appsJSON) async {
    var decodedJSON = jsonDecode(appsJSON);
    var newFormat = decodedJSON is! List;
    List<App> importedApps =
        ((newFormat ? decodedJSON['apps'] : decodedJSON) as List<dynamic>)
            .map((e) => App.fromJson(e))
            .toList();
    while (loadingApps) {
      await Future.delayed(const Duration(microseconds: 1));
    }
    for (App a in importedApps) {
      var installedInfo = await getInstalledInfo(a.id, printErr: false);
      a.installedVersion =
          a.additionalSettings['useVersionCodeAsOSVersion'] == true
              ? installedInfo?.versionCode.toString()
              : installedInfo?.versionName;
    }
    await saveApps(importedApps, onlyIfExists: false);
    notifyListeners();
    if (newFormat && decodedJSON['settings'] != null) {
      var settingsMap = decodedJSON['settings'] as Map<String, Object?>;
      settingsMap.forEach((key, value) {
        if (value is int) {
          settingsProvider.prefs?.setInt(key, value);
        } else if (value is double) {
          settingsProvider.prefs?.setDouble(key, value);
        } else if (value is bool) {
          settingsProvider.prefs?.setBool(key, value);
        } else if (value is List) {
          settingsProvider.prefs
              ?.setStringList(key, value.map((e) => e as String).toList());
        } else {
          settingsProvider.prefs?.setString(key, value as String);
        }
      });
    }
    return MapEntry<List<App>, bool>(
        importedApps, newFormat && decodedJSON['settings'] != null);
  }

  @override
  void dispose() {
    foregroundSubscription?.cancel();
    super.dispose();
  }

  Future<List<List<String>>> addAppsByURL(List<String> urls,
      {AppSource? sourceOverride}) async {
    List<dynamic> results = await SourceProvider().getAppsByURLNaive(urls,
        alreadyAddedUrls: apps.values.map((e) => e.app.url).toList(),
        sourceOverride: sourceOverride);
    List<App> pps = results[0];
    Map<String, dynamic> errorsMap = results[1];
    for (var app in pps) {
      if (apps.containsKey(app.id)) {
        errorsMap.addAll({app.id: tr('appAlreadyAdded')});
      } else {
        await saveApps([app], onlyIfExists: false);
      }
    }
    List<List<String>> errors =
        errorsMap.keys.map((e) => [e, errorsMap[e].toString()]).toList();
    return errors;
  }
}

class AppFilePicker extends StatefulWidget {
  const AppFilePicker(
      {super.key,
      required this.app,
      this.initVal,
      this.archs,
      this.pickAnyAsset = false});

  final App app;
  final MapEntry<String, String>? initVal;
  final List<String>? archs;
  final bool pickAnyAsset;

  @override
  State<AppFilePicker> createState() => _AppFilePickerState();
}

class _AppFilePickerState extends State<AppFilePicker> {
  MapEntry<String, String>? fileUrl;

  @override
  Widget build(BuildContext context) {
    fileUrl ??= widget.initVal;
    var urlsToSelectFrom = widget.app.apkUrls;
    if (widget.pickAnyAsset) {
      urlsToSelectFrom = [...urlsToSelectFrom, ...widget.app.otherAssetUrls];
    }
    return AlertDialog(
      scrollable: true,
      title: Text(widget.pickAnyAsset
          ? tr('selectX', args: [tr('releaseAsset').toLowerCase()])
          : tr('pickAnAPK')),
      content: Column(children: [
        urlsToSelectFrom.length > 1
            ? Text(tr('appHasMoreThanOnePackage', args: [widget.app.finalName]))
            : const SizedBox.shrink(),
        const SizedBox(height: 16),
        ...urlsToSelectFrom.map(
          (u) => RadioListTile<String>(
              title: Text(u.key),
              value: u.value,
              groupValue: fileUrl!.value,
              onChanged: (String? val) {
                setState(() {
                  fileUrl = urlsToSelectFrom.where((e) => e.value == val).first;
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
              Navigator.of(context).pop(fileUrl);
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

/// Background updater function
///
/// @param List<MapEntry<String, int>>? toCheck: The appIds to check for updates (with the number of previous attempts made per appid) (defaults to all apps)
///
/// @param List<String>? toInstall: The appIds to attempt to update (if empty - which is the default - all pending updates are taken)
///
/// When toCheck is empty, the function is in "install mode" (else it is in "update mode").
/// In update mode, all apps in toCheck are checked for updates (in parallel).
/// If an update is available and it cannot be installed silently, the user is notified of the available update.
/// If there are any errors, we recursively call the same function with retry count for the relevant apps decremented (if zero, the user is notified).
///
/// Once all update checks are complete, the task is run again in install mode.
/// In this mode, all pending silent updates are downloaded (in parallel) and installed in the background.
/// If there is an error, the user is notified.
///
Future<void> bgUpdateCheck(String taskId, Map<String, dynamic>? params) async {
  // ignore: avoid_print
  print('Started $taskId: ${params.toString()}');
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await loadTranslations();

  LogsProvider logs = LogsProvider();
  NotificationsProvider notificationsProvider = NotificationsProvider();
  AppsProvider appsProvider = AppsProvider(isBg: true);
  await appsProvider.loadApps();

  int maxAttempts = 4;
  int maxRetryWaitSeconds = 5;

  var netResult = await (Connectivity().checkConnectivity());
  if (netResult.contains(ConnectivityResult.none) ||
      netResult.isEmpty ||
      (netResult.contains(ConnectivityResult.vpn) && netResult.length == 1)) {
    logs.add('BG update task: No network.');
    return;
  }

  params ??= {};

  bool firstEverUpdateTask = DateTime.fromMillisecondsSinceEpoch(0)
          .compareTo(appsProvider.settingsProvider.lastCompletedBGCheckTime) ==
      0;

  List<MapEntry<String, int>> toCheck = <MapEntry<String, int>>[
    ...(params['toCheck']
            ?.map((entry) => MapEntry<String, int>(
                entry['key'] as String, entry['value'] as int))
            .toList() ??
        appsProvider
            .getAppsSortedByUpdateCheckTime(
                ignoreAppsCheckedAfter: params['toCheck'] == null
                    ? firstEverUpdateTask
                        ? null
                        : appsProvider.settingsProvider.lastCompletedBGCheckTime
                    : null,
                onlyCheckInstalledOrTrackOnlyApps: appsProvider
                    .settingsProvider.onlyCheckInstalledOrTrackOnlyApps)
            .map((e) => MapEntry(e, 0)))
  ];
  List<MapEntry<String, int>> toInstall = <MapEntry<String, int>>[
    ...(params['toInstall']
            ?.map((entry) => MapEntry<String, int>(
                entry['key'] as String, entry['value'] as int))
            .toList() ??
        (<List<MapEntry<String, int>>>[]))
  ];

  var networkRestricted = appsProvider.settingsProvider.bgUpdatesOnWiFiOnly &&
      !netResult.contains(ConnectivityResult.wifi) &&
      !netResult.contains(ConnectivityResult.ethernet);

  var chargingRestricted =
      appsProvider.settingsProvider.bgUpdatesWhileChargingOnly &&
          (await Battery().batteryState) != BatteryState.charging;

  if (networkRestricted) {
    logs.add('BG update task: Network restriction in effect.');
  }

  if (chargingRestricted) {
    logs.add('BG update task: Charging restriction in effect.');
  }

  if (toCheck.isNotEmpty) {
    // Task is either in update mode or install mode
    // If in update mode, we check for updates.
    // We divide the results into 4 groups:
    // - toNotify - Apps with updates that the user will be notified about (can't be silently installed)
    // - toThrow - Apps with update check errors that the user will be notified about (no retry)
    // After grouping the updates, we take care of toNotify and toThrow first
    // Then we run the function again in install mode (toCheck is empty)

    var enoughTimePassed = appsProvider.settingsProvider.updateInterval != 0 &&
        appsProvider.settingsProvider.lastCompletedBGCheckTime
            .add(
                Duration(minutes: appsProvider.settingsProvider.updateInterval))
            .isBefore(DateTime.now());
    if (!enoughTimePassed) {
      // ignore: avoid_print
      print(
          'BG update task: Too early for another check (last check was ${appsProvider.settingsProvider.lastCompletedBGCheckTime.toIso8601String()}, interval is ${appsProvider.settingsProvider.updateInterval}).');
      return;
    }

    logs.add('BG update task: Started (${toCheck.length}).');

    // Init. vars.
    List<App> updates = []; // All updates found (silent and non-silent)
    List<App> toNotify =
        []; // All non-silent updates that the user will be notified about
    List<MapEntry<String, int>> toRetry =
        []; // All apps that got errors while checking
    var retryAfterXSeconds = 0;
    MultiAppMultiError?
        errors; // All errors including those that will lead to a retry
    MultiAppMultiError toThrow =
        MultiAppMultiError(); // All errors that will not lead to a retry, just a notification
    CheckingUpdatesNotification notif = CheckingUpdatesNotification(
        plural('apps', toCheck.length)); // The notif. to show while checking

    try {
      // Check for updates
      notificationsProvider.notify(notif, cancelExisting: true);
      updates = await appsProvider.checkUpdates(
          specificIds: toCheck.map((e) => e.key).toList(),
          sp: appsProvider.settingsProvider);
    } catch (e) {
      if (e is Map) {
        updates = e['updates'];
        errors = e['errors'];
        errors!.rawErrors.forEach((key, err) {
          logs.add(
              'BG update task: Got error on checking for $key \'${err.toString()}\'.');

          var toCheckApp = toCheck.where((element) => element.key == key).first;
          if (toCheckApp.value < maxAttempts) {
            toRetry.add(MapEntry(toCheckApp.key, toCheckApp.value + 1));
            // Next task interval is based on the error with the longest retry time
            int minRetryIntervalForThisApp = err is RateLimitError
                ? (err.remainingMinutes * 60)
                : e is ClientException
                    ? (15 * 60)
                    : (toCheckApp.value + 1);
            if (minRetryIntervalForThisApp > maxRetryWaitSeconds) {
              minRetryIntervalForThisApp = maxRetryWaitSeconds;
            }
            if (minRetryIntervalForThisApp > retryAfterXSeconds) {
              retryAfterXSeconds = minRetryIntervalForThisApp;
            }
          } else {
            if (err is! RateLimitError) {
              toThrow.add(key, err, appName: errors?.appIdNames[key]);
            }
          }
        });
      } else {
        // We don't expect to ever get here in any situation so no need to catch (but log it in case)
        logs.add('Fatal error in BG update task: ${e.toString()}');
        rethrow;
      }
    } finally {
      notificationsProvider.cancel(notif.id);
    }

    // Filter out updates that will be installed silently (the rest go into toNotify)
    for (var i = 0; i < updates.length; i++) {
      if (networkRestricted ||
          chargingRestricted ||
          !(await appsProvider.canInstallSilently(updates[i]))) {
        if (updates[i].additionalSettings['skipUpdateNotifications'] != true) {
          toNotify.add(updates[i]);
        }
      }
    }

    // Send the update notification
    if (toNotify.isNotEmpty) {
      notificationsProvider.notify(UpdateNotification(toNotify));
    }

    // Send the error notifications (grouped by error string)
    if (toThrow.rawErrors.isNotEmpty) {
      for (var element in toThrow.idsByErrorString.entries) {
        notificationsProvider.notify(ErrorCheckingUpdatesNotification(
            errors!.errorsAppsString(element.key, element.value),
            id: Random().nextInt(10000)));
      }
    }
    // if there are update checks to retry, schedule a retry task
    logs.add('BG update task: Done checking for updates.');
    if (toRetry.isNotEmpty) {
      logs.add(
          'BG update task $taskId: Will retry in $retryAfterXSeconds seconds.');
      return await bgUpdateCheck(taskId, {
        'toCheck': toRetry
            .map((entry) => {'key': entry.key, 'value': entry.value})
            .toList(),
        'toInstall': toInstall
            .map((entry) => {'key': entry.key, 'value': entry.value})
            .toList(),
      });
    } else {
      // If there are no more update checks, call the function in install mode
      logs.add('BG update task: Done checking for updates.');
      return await bgUpdateCheck(taskId, {
        'toCheck': [],
        'toInstall': toInstall
            .map((entry) => {'key': entry.key, 'value': entry.value})
            .toList()
      });
    }
  } else {
    // In install mode...
    // If you haven't explicitly been given updates to install, grab all available silent updates
    if (toInstall.isEmpty && !networkRestricted && !chargingRestricted) {
      var temp = appsProvider.findExistingUpdates(installedOnly: true);
      for (var i = 0; i < temp.length; i++) {
        if (await appsProvider
            .canInstallSilently(appsProvider.apps[temp[i]]!.app)) {
          toInstall.add(MapEntry(temp[i], 0));
        }
      }
    }
    if (toInstall.isNotEmpty) {
      logs.add('BG install task: Started (${toInstall.length}).');
      var tempObtArr = toInstall.where((element) => element.key == obtainiumId);
      if (tempObtArr.isNotEmpty) {
        // Move obtainium to the end of the list as it must always install last
        var obt = tempObtArr.first;
        toInstall = moveStrToEndMapEntryWithCount(toInstall, obt);
      }
      // Loop through all updates and install each
      try {
        await appsProvider.downloadAndInstallLatestApps(
            toInstall.map((e) => e.key).toList(), null,
            notificationsProvider: notificationsProvider,
            forceParallelDownloads: true);
      } catch (e) {
        if (e is MultiAppMultiError) {
          e.idsByErrorString.forEach((key, value) {
            notificationsProvider.notify(ErrorCheckingUpdatesNotification(
                e.errorsAppsString(key, value)));
          });
        } else {
          // We don't expect to ever get here in any situation so no need to catch (but log it in case)
          logs.add('Fatal error in BG install task: ${e.toString()}');
          rethrow;
        }
      }
      logs.add('BG install task: Done installing updates.');
    }
  }
  appsProvider.settingsProvider.lastCompletedBGCheckTime = DateTime.now();
}
