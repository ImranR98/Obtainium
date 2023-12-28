// Manages state related to the list of Apps tracked by Obtainium,
// Exposes related functions such as those used to add, remove, download, and install Apps.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import 'package:android_intent_plus/flag.dart';
import 'package:android_package_installer/android_package_installer.dart';
import 'package:android_package_manager/android_package_manager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:shared_storage/shared_storage.dart' as saf;
import 'installers_provider.dart';

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

Future<File> downloadFileWithRetry(
    String url, String fileNameNoExt, Function? onProgress, String destDir,
    {bool useExisting = true,
    Map<String, String>? headers,
    int retries = 3}) async {
  try {
    return await downloadFile(url, fileNameNoExt, onProgress, destDir,
        useExisting: useExisting, headers: headers);
  } catch (e) {
    if (retries > 0 && e is ClientException) {
      await Future.delayed(const Duration(seconds: 5));
      return await downloadFileWithRetry(
          url, fileNameNoExt, onProgress, destDir,
          useExisting: useExisting, headers: headers, retries: (retries - 1));
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

Future<String> checkDownloadHash(String url,
    {int bytesToGrab = 1024, Map<String, String>? headers}) async {
  var req = Request('GET', Uri.parse(url));
  if (headers != null) {
    req.headers.addAll(headers);
  }
  req.headers[HttpHeaders.rangeHeader] = 'bytes=0-$bytesToGrab';
  var client = http.Client();
  var response = await client.send(req);
  if (response.statusCode < 200 || response.statusCode > 299) {
    throw ObtainiumError(response.reasonPhrase ?? tr('unexpectedError'));
  }
  List<List<int>> bytes = await response.stream.take(bytesToGrab).toList();
  return hashListOfLists(bytes);
}

Future<File> downloadFile(
    String url, String fileNameNoExt, Function? onProgress, String destDir,
    {bool useExisting = true, Map<String, String>? headers}) async {
  var req = Request('GET', Uri.parse(url));
  if (headers != null) {
    req.headers.addAll(headers);
  }
  var client = http.Client();
  StreamedResponse response = await client.send(req);
  String ext =
      response.headers['content-disposition']?.split('.').last ?? 'apk';
  if (ext.endsWith('"') || ext.endsWith("other")) {
    ext = ext.substring(0, ext.length - 1);
  }
  if (url.toLowerCase().endsWith('.apk') && ext != 'apk') {
    ext = 'apk';
  }
  File downloadedFile = File('$destDir/$fileNameNoExt.$ext');
  if (!(downloadedFile.existsSync() && useExisting)) {
    File tempDownloadedFile = File('${downloadedFile.path}.part');
    if (tempDownloadedFile.existsSync()) {
      tempDownloadedFile.deleteSync(recursive: true);
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
      tempDownloadedFile.deleteSync(recursive: true);
      throw response.reasonPhrase ?? tr('unexpectedError');
    }
    tempDownloadedFile.renameSync(downloadedFile.path);
  } else {
    client.close();
  }
  return downloadedFile;
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
  late SettingsProvider settingsProvider = SettingsProvider();

  Iterable<AppInMemory> getAppValues() => apps.values.map((a) => a.deepCopy());

  AppsProvider({isBg = false}) {
    // Subscribe to changes in the app foreground status
    foregroundStream = FGBGEvents.stream.asBroadcastStream();
    foregroundSubscription = foregroundStream?.listen((event) async {
      isForeground = event == FGBGType.foreground;
      if (isForeground) await loadApps();
    });
    () async {
      await settingsProvider.initializeSettings();
      var cacheDirs = await getExternalCacheDirectories();
      if (cacheDirs?.isNotEmpty ?? false) {
        APKDir = cacheDirs!.first;
      } else {
        APKDir =
            Directory('${(await getExternalStorageDirectory())!.path}/apks');
        if (!APKDir.existsSync()) {
          APKDir.createSync();
        }
      }
      if (!isBg) {
        // Load Apps into memory (in background processes, this is done later instead of in the constructor)
        await loadApps();
        // Delete any partial APKs (if safe to do so)
        var cutoff = DateTime.now().subtract(const Duration(days: 7));
        APKDir.listSync()
            .where((element) =>
                element.path.endsWith('.part') ||
                element.statSync().modified.isBefore(cutoff))
            .forEach((partialApk) {
          if (!areDownloadsRunning()) {
            partialApk.delete(recursive: true);
          }
        });
      }
    }();
  }

  Future<File> handleAPKIDChange(App app, PackageInfo? newInfo,
      File downloadedFile, String downloadUrl) async {
    // If the APK package ID is different from the App ID, it is either new (using a placeholder ID) or the ID has changed
    // The former case should be handled (give the App its real ID), the latter is a security issue
    var isTempIdBool = isTempId(app);
    if (newInfo != null) {
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
    } else if (isTempIdBool) {
      throw ObtainiumError('Could not get ID from APK');
    }
    return downloadedFile;
  }

  Future<Object> downloadApp(App app, BuildContext? context,
      {NotificationsProvider? notificationsProvider}) async {
    var notifId = DownloadNotification(app.finalName, 0).id;
    if (apps[app.id] != null) {
      apps[app.id]!.downloadProgress = 0;
      notifyListeners();
    }
    try {
      AppSource source = SourceProvider()
          .getSource(app.url, overrideSource: app.overrideSource);
      String downloadUrl = await source.apkUrlPrefetchModifier(
          app.apkUrls[app.preferredApkIndex].value, app.url);
      var notif = DownloadNotification(app.finalName, 100);
      notificationsProvider?.cancel(notif.id);
      int? prevProg;
      var fileNameNoExt = '${app.id}-${downloadUrl.hashCode}';
      var headers = await source.getRequestHeaders(
          additionalSettings: app.additionalSettings, forAPKDownload: true);
      var downloadedFile = await downloadFileWithRetry(
          downloadUrl, fileNameNoExt,
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
      }, APKDir.path);
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
        newInfo =
            await pm.getPackageArchiveInfo(archiveFilePath: apks.first.path);
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
    if (app.id == obtainiumId) {
      return false;
    }
    if (!settingsProvider.enableBackgroundUpdates) {
      return false;
    }
    if (app.additionalSettings['exemptFromBackgroundUpdates'] == true) {
      return false;
    }
    if (app.apkUrls.length > 1) {
      // Manual API selection means silent install is not possible
      return false;
    }

    var osInfo = await DeviceInfoPlugin().androidInfo;
    String? installerPackageName;
    try {
      installerPackageName = osInfo.version.sdkInt >= 30
          ? (await pm.getInstallSourceInfo(packageName: app.id))
              ?.installingPackageName
          : (await pm.getInstallerPackageName(packageName: app.id));
    } catch (e) {
      // Probably not installed - ignore
    }
    if (installerPackageName != obtainiumId) {
      // If we did not install the app (or it isn't installed), silent install is not possible
      return false;
    }
    int? targetSDK =
        (await getInstalledInfo(app.id))?.applicationInfo?.targetSdkVersion;

    // The OS must also be new enough and the APK should target a new enough API
    return osInfo.version.sdkInt >= 31 &&
        targetSDK != null &&
        targetSDK >= // https://developer.android.com/reference/android/content/pm/PackageInstaller.SessionParams#setRequireUserAction(int)
            (osInfo.version.sdkInt - 3);
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

  Future<bool> canDowngradeApps() async =>
      (await getInstalledInfo('com.berdik.letmedowngrade')) != null;

  Future<void> unzipFile(String filePath, String destinationPath) async {
    await ZipFile.extractToDirectory(
        zipFile: File(filePath), destinationDir: Directory(destinationPath));
  }

  Future<void> installXApkDir(DownloadedXApkDir dir,
      {bool needsBGWorkaround = false}) async {
    // We don't know which APKs in an XAPK are supported by the user's device
    // So we try installing all of them and assume success if at least one installed
    // If 0 APKs installed, throw the first install error encountered
    try {
      var somethingInstalled = false;
      MultiAppMultiError errors = MultiAppMultiError();
      for (var file in dir.extracted
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()) {
        if (file.path.toLowerCase().endsWith('.apk')) {
          try {
            somethingInstalled = somethingInstalled ||
                await installApk(DownloadedApk(dir.appId, file),
                    needsBGWorkaround: needsBGWorkaround);
          } catch (e) {
            logs.add(
                'Could not install APK from XAPK \'${file.path}\': ${e.toString()}');
            errors.add(dir.appId, e, appName: apps[dir.appId]?.name);
          }
        } else if (file.path.toLowerCase().endsWith('.obb')) {
          await moveObbFile(file, dir.appId);
        }
      }
      if (somethingInstalled) {
        dir.file.delete(recursive: true);
      } else if (errors.idsByErrorString.isNotEmpty) {
        throw errors;
      }
    } finally {
      dir.extracted.delete(recursive: true);
    }
  }

  Future<bool> installApk(DownloadedApk file,
      {bool needsBGWorkaround = false}) async {
    var newInfo =
        await pm.getPackageArchiveInfo(archiveFilePath: file.file.path);
    PackageInfo? appInfo = await getInstalledInfo(apps[file.appId]!.app.id);
    if (appInfo != null &&
        newInfo!.versionCode! < appInfo.versionCode! &&
        !(await canDowngradeApps())) {
      throw DowngradeError();
    }
    if (needsBGWorkaround &&
        settingsProvider.installMethod == InstallMethodSettings.normal) {
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
    switch (settingsProvider.installMethod) {
      case InstallMethodSettings.normal:
        code = await AndroidPackageInstaller.installApk(
            apkFilePath: file.file.path);
      case InstallMethodSettings.shizuku:
        code = (await Installers.installWithShizuku(
                apkFileUri: file.file.uri.toString()))
            ? 0
            : 1;
      case InstallMethodSettings.root:
        code = (await Installers.installWithRoot(apkFilePath: file.file.path))
            ? 0
            : 1;
    }
    bool installed = false;
    if (code != null && code != 0 && code != 3) {
      throw InstallError(code);
    } else if (code == 0) {
      installed = true;
      apps[file.appId]!.app.installedVersion =
          apps[file.appId]!.app.latestVersion;
      file.file.delete(recursive: true);
    }
    await saveApps([apps[file.appId]!.app]);
    return installed;
  }

  Future<void> moveObbFile(File file, String appId) async {
    if (!file.path.toLowerCase().endsWith('.obb')) return;

    // TODO: Does not support Android 11+
    if ((await DeviceInfoPlugin().androidInfo).version.sdkInt <= 29) {
      await Permission.storage.request();
    }

    String obbDirPath = "/storage/emulated/0/Android/obb/$appId";
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

  Future<MapEntry<String, String>?> confirmApkUrl(
      App app, BuildContext? context) async {
    // If the App has more than one APK, the user should pick one (if context provided)
    MapEntry<String, String>? apkUrl =
        app.apkUrls[app.preferredApkIndex >= 0 ? app.preferredApkIndex : 0];
    // get device supported architecture
    List<String> archs = (await DeviceInfoPlugin().androidInfo).supportedAbis;

    if (app.apkUrls.length > 1 && context != null) {
      // ignore: use_build_context_synchronously
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
        getHost(apkUrl.value) != getHost(app.url) &&
        context != null) {
      // ignore: use_build_context_synchronously
      if (!(settingsProvider.hideAPKOriginWarning) &&
          // ignore: use_build_context_synchronously
          await showDialog(
                  context: context,
                  builder: (BuildContext ctx) {
                    return APKOriginWarningDialog(
                        sourceUrl: app.url, apkUrl: apkUrl!.value);
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
      List<String> appIds, BuildContext? context,
      {NotificationsProvider? notificationsProvider,
      bool forceParallelDownloads = false}) async {
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
      if (!trackOnly) {
        apkUrl = await confirmApkUrl(apps[id]!.app, context);
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

    Future<void> updateFn(String id, {bool skipInstalls = false}) async {
      try {
        var downloadedArtifact =
            // ignore: use_build_context_synchronously
            await downloadApp(apps[id]!.app, context,
                notificationsProvider: notificationsProvider);
        DownloadedApk? downloadedFile;
        DownloadedXApkDir? downloadedDir;
        if (downloadedArtifact is DownloadedApk) {
          downloadedFile = downloadedArtifact;
        } else {
          downloadedDir = downloadedArtifact as DownloadedXApkDir;
        }
        var appId = downloadedFile?.appId ?? downloadedDir!.appId;
        bool willBeSilent = await canInstallSilently(apps[appId]!.app);
        switch (settingsProvider.installMethod) {
          case InstallMethodSettings.normal:
            if (!(await settingsProvider.getInstallPermission(
                enforce: false))) {
              throw ObtainiumError(tr('cancelled'));
            }
          case InstallMethodSettings.shizuku:
            int code = await Installers.checkPermissionShizuku();
            if (code == -1) {
              throw ObtainiumError(tr('shizukuBinderNotFound'));
            } else if (code == 0) {
              throw ObtainiumError(tr('cancelled'));
            }
          case InstallMethodSettings.root:
            if (!(await Installers.checkPermissionRoot())) {
              throw ObtainiumError(tr('cancelled'));
            }
        }
        if (!willBeSilent && context != null) {
          // ignore: use_build_context_synchronously
          await waitForUserToReturnToForeground(context);
        }
        apps[id]?.downloadProgress = -1;
        notifyListeners();
        try {
          if (!skipInstalls) {
            if (downloadedFile != null) {
              if (willBeSilent && context == null) {
                installApk(downloadedFile, needsBGWorkaround: true);
              } else {
                await installApk(downloadedFile);
              }
            } else {
              if (willBeSilent && context == null) {
                installXApkDir(downloadedDir!, needsBGWorkaround: true);
              } else {
                await installXApkDir(downloadedDir!);
              }
            }
            if (willBeSilent && context == null) {
              notificationsProvider?.notify(SilentUpdateAttemptNotification(
                  [apps[appId]!.app],
                  id: appId.hashCode));
            }
          }
        } finally {
          apps[id]?.downloadProgress = null;
          notifyListeners();
        }
        installedIds.add(id);
      } catch (e) {
        errors.add(id, e, appName: apps[id]?.name);
      }
    }

    if (forceParallelDownloads || !settingsProvider.parallelDownloads) {
      for (var id in appsToInstall) {
        await updateFn(id);
      }
    } else {
      await Future.wait(
          appsToInstall.map((id) => updateFn(id, skipInstalls: true)));
      for (var id in appsToInstall) {
        if (!errors.appIdNames.containsKey(id)) {
          await updateFn(id);
        }
      }
    }

    if (errors.idsByErrorString.isNotEmpty) {
      throw errors;
    }

    return installedIds;
  }

  Future<Directory> getAppsDir() async {
    Directory appsDir =
        Directory('${(await getExternalStorageDirectory())!.path}/app_data');
    if (!appsDir.existsSync()) {
      appsDir.createSync();
    }
    return appsDir;
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

  bool isVersionDetectionPossible(AppInMemory? app) {
    if (app?.app == null) {
      return false;
    }
    var naiveStandardVersionDetection =
        app!.app.additionalSettings['naiveStandardVersionDetection'] == true ||
            SourceProvider()
                .getSource(app.app.url, overrideSource: app.app.overrideSource)
                .naiveStandardVersionDetection;
    return app.app.additionalSettings['trackOnly'] != true &&
        app.app.additionalSettings['versionDetection'] !=
            'releaseDateAsVersion' &&
        app.installedInfo?.versionName != null &&
        app.app.installedVersion != null &&
        (reconcileVersionDifferences(app.installedInfo!.versionName!,
                    app.app.installedVersion!) !=
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
        app.additionalSettings['versionDetection'] ==
            'standardVersionDetection';
    var naiveStandardVersionDetection =
        app.additionalSettings['naiveStandardVersionDetection'] == true ||
            SourceProvider()
                .getSource(app.url, overrideSource: app.overrideSource)
                .naiveStandardVersionDetection;
    // FIRST, COMPARE THE APP'S REPORTED AND REAL INSTALLED VERSIONS, WHERE ONE IS NULL
    if (installedInfo == null && app.installedVersion != null && !trackOnly) {
      // App says it's installed but isn't really (and isn't track only) - set to not installed
      app.installedVersion = null;
      modded = true;
    } else if (installedInfo?.versionName != null &&
        app.installedVersion == null) {
      // App says it's not installed but really is - set to installed and use real package versionName
      app.installedVersion = installedInfo!.versionName;
      modded = true;
    }
    // SECOND, RECONCILE DIFFERENCES BETWEEN THE APP'S REPORTED AND REAL INSTALLED VERSIONS, WHERE NEITHER IS NULL
    if (installedInfo?.versionName != null &&
        installedInfo!.versionName != app.installedVersion &&
        versionDetectionIsStandard) {
      // App's reported version and real version don't match (and it uses standard version detection)
      // If they share a standard format (and are still different under it), update the reported version accordingly
      var correctedInstalledVersion = reconcileVersionDifferences(
          installedInfo.versionName!, app.installedVersion!);
      if (correctedInstalledVersion?.key == false) {
        app.installedVersion = correctedInstalledVersion!.value;
        modded = true;
      } else if (naiveStandardVersionDetection) {
        app.installedVersion = installedInfo.versionName;
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
      app.additionalSettings['versionDetection'] = 'noVersionDetection';
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
    List<App?> newApps = (await getAppsDir()) // Parse Apps from JSON
        .listSync()
        .where((item) => item.path.toLowerCase().endsWith('.json'))
        .where((item) =>
            singleId == null ||
            item.path.split('/').last.toLowerCase() ==
                '${singleId.toLowerCase()}.json')
        .map((e) {
      try {
        return App.fromJson(jsonDecode(File(e.path).readAsStringSync()));
      } catch (err) {
        if (err is FormatException) {
          logs.add('Corrupt JSON when loading App (will be ignored): $e');
          e.renameSync('${e.path}.corrupt');
        } else {
          rethrow;
        }
      }
    }).toList();
    for (var app in newApps) {
      // Put Apps into memory to list them (fast)
      if (app != null) {
        try {
          sp.getSource(app.url, overrideSource: app.overrideSource);
          apps.update(
              app.id,
              (value) => AppInMemory(
                  app, value.downloadProgress, value.installedInfo, value.icon),
              ifAbsent: () => AppInMemory(app, null, null, null));
        } catch (e) {
          errors.add([app.id, app.finalName, e.toString()]);
        }
      }
    }
    notifyListeners();
    if (errors.isNotEmpty) {
      removeApps(errors.map((e) => e[0]).toList());
      NotificationsProvider().notify(
          AppsRemovedNotification(errors.map((e) => [e[1], e[2]]).toList()));
    }

    for (var app in apps.values) {
      // Get install status and other OS info for each App (slow)
      apps[app.app.id]?.installedInfo = await getInstalledInfo(app.app.id);
      apps[app.app.id]?.icon =
          await apps[app.app.id]?.installedInfo?.applicationInfo?.getAppIcon();
      apps[app.app.id]?.app.name = await (apps[app.app.id]
              ?.installedInfo
              ?.applicationInfo
              ?.getAppLabel()) ??
          app.name;
      notifyListeners();
    }
    // Reconcile version differences
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
      var removedAppIds = modifiedApps
          .where((a) => a.installedVersion == null)
          .map((e) => e.id)
          .toList();
      // After reconciliation, delete externally uninstalled Apps if needed
      if (removedAppIds.isNotEmpty) {
        if (settingsProvider.removeOnExternalUninstall) {
          await removeApps(removedAppIds);
        }
      }
    }

    loadingApps = false;
    notifyListeners();
  }

  Future<void> saveApps(List<App> apps,
      {bool attemptToCorrectInstallStatus = true,
      bool onlyIfExists = true}) async {
    attemptToCorrectInstallStatus = attemptToCorrectInstallStatus;
    for (var a in apps) {
      var app = a.deepCopy();
      PackageInfo? info = await getInstalledInfo(app.id);
      var icon = await info?.applicationInfo?.getAppIcon();
      app.name = await (info?.applicationInfo?.getAppLabel()) ?? app.name;
      if (attemptToCorrectInstallStatus) {
        app = getCorrectedInstallStatusAppIfPossible(app, info) ?? app;
      }
      if (!onlyIfExists || this.apps.containsKey(app.id)) {
        File('${(await getAppsDir()).path}/${app.id}.json')
            .writeAsStringSync(jsonEncode(app.toJson()));
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
    }
    notifyListeners();
    export(isAuto: true);
  }

  Future<void> removeApps(List<String> appIds) async {
    var apkFiles = APKDir.listSync();
    for (var appId in appIds) {
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
    }
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
      Map<String, dynamic> finalExport = {};
      finalExport['apps'] = apps.values.map((e) => e.app.toJson()).toList();
      if (settingsProvider.exportSettings) {
        finalExport['settings'] = Map<String, Object?>.fromEntries(
            (settingsProvider.prefs
                    ?.getKeys()
                    .map((key) =>
                        MapEntry(key, settingsProvider.prefs?.get(key)))
                    .toList()) ??
                []);
      }
      var result = await saf.createFile(exportDir,
          displayName:
              '${tr('obtainiumExportHyphenatedLowercase')}-${DateTime.now().toIso8601String().replaceAll(':', '-')}${isAuto ? '-auto' : ''}.json',
          mimeType: 'application/json',
          bytes: Uint8List.fromList(utf8.encode(jsonEncode(finalExport))));
      if (result == null) {
        throw ObtainiumError(tr('unexpectedError'));
      }
      returnPath =
          exportDir.pathSegments.join('/').replaceFirst('tree/primary:', '/');
    }
    return returnPath;
  }

  Future<MapEntry<int, bool>> import(String appsJSON) async {
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
      a.installedVersion =
          (await getInstalledInfo(a.id, printErr: false))?.versionName;
    }
    await saveApps(importedApps, onlyIfExists: false);
    notifyListeners();
    if (newFormat && decodedJSON['settings'] != null) {
      var settingsMap = decodedJSON['settings'] as Map<String, Object?>;
      settingsMap.forEach((key, value) {
        if (value is int) {
          settingsProvider.prefs?.setInt(key, value);
        } else if (value is bool) {
          settingsProvider.prefs?.setBool(key, value);
        } else {
          settingsProvider.prefs?.setString(key, value as String);
        }
      });
    }
    return MapEntry<int, bool>(
        importedApps.length, newFormat && decodedJSON['settings'] != null);
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

class APKPicker extends StatefulWidget {
  const APKPicker({super.key, required this.app, this.initVal, this.archs});

  final App app;
  final MapEntry<String, String>? initVal;
  final List<String>? archs;

  @override
  State<APKPicker> createState() => _APKPickerState();
}

class _APKPickerState extends State<APKPicker> {
  MapEntry<String, String>? apkUrl;

  @override
  Widget build(BuildContext context) {
    apkUrl ??= widget.initVal;
    return AlertDialog(
      scrollable: true,
      title: Text(tr('pickAnAPK')),
      content: Column(children: [
        Text(tr('appHasMoreThanOnePackage', args: [widget.app.finalName])),
        const SizedBox(height: 16),
        ...widget.app.apkUrls.map(
          (u) => RadioListTile<String>(
              title: Text(u.key),
              value: u.value,
              groupValue: apkUrl!.value,
              onChanged: (String? val) {
                setState(() {
                  apkUrl =
                      widget.app.apkUrls.where((e) => e.value == val).first;
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
  if (netResult == ConnectivityResult.none) {
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

  var networkRestricted = false;
  if (appsProvider.settingsProvider.bgUpdatesOnWiFiOnly) {
    networkRestricted = (netResult != ConnectivityResult.wifi) &&
        (netResult != ConnectivityResult.ethernet);
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

    // Set a bool for when we're no on wifi/wired and the user doesn't want to download apps in that state
    var networkRestricted = false;
    if (appsProvider.settingsProvider.bgUpdatesOnWiFiOnly) {
      var netResult = await (Connectivity().checkConnectivity());
      networkRestricted = (netResult != ConnectivityResult.wifi) &&
          (netResult != ConnectivityResult.ethernet);
    }

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
    if (toInstall.isEmpty && !networkRestricted) {
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
