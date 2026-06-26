// Manages state related to the list of Apps tracked by Obtainium,
// Exposes related functions such as those used to add, remove, download, and install Apps.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';

import 'package:android_intent_plus/flag.dart';
import 'package:android_package_installer/android_package_installer.dart';
import 'package:android_package_manager/android_package_manager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:http/io_client.dart';
import 'package:obtainium/app_sources/direct_apk_link.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/components/app_dialogs.dart';
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
import 'package:archive/archive.dart' as archive;
import 'package:share_plus/share_plus.dart';
import 'package:shared_storage/shared_storage.dart' as saf;
import 'package:shizuku_apk_installer/shizuku_apk_installer.dart';

part 'apps_provider_install.dart';
part 'apps_provider_lifecycle.dart';
part 'apps_provider_updates.dart';
part 'apps_provider_import_export.dart';

final pm = AndroidPackageManager();
final packageInfoFlags = PackageInfoFlags({PMFlag.getSigningCertificates});

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

  bool get hasMultipleSigners {
    return installedInfo?.signingInfo?.hasMultipleSigners ?? false;
  }

  List<String> get certificateHashes {
    // https://developer.android.com/reference/android/content/pm/SigningInfo#getApkContentsSigners()
    final signatures = hasMultipleSigners
        ? installedInfo?.signingInfo?.apkContentSigners
        : installedInfo?.signingInfo?.signingCertificateHistory;

    return signatures?.map((signature) {
          final digest = sha256.convert(signature);
          return digest.bytes
              .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
              .join(':');
        }).toList() ??
        [];
  }
}

class DownloadedApk {
  String appId;
  File file;
  DownloadedApk(this.appId, this.file);
}

enum DownloadedDirType { xapk, zip, tarball }

class DownloadedDir {
  String appId;
  File file;
  Directory extracted;
  DownloadedDirType type;
  DownloadedDir(this.appId, this.file, this.extracted, this.type);
}

List<String> generateStandardVersionRegExStrings() {
  var basics = [
    '[0-9]+',
    '[0-9]+\\.[0-9]+',
    '[0-9]+\\.[0-9]+\\.[0-9]+',
    '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+',
  ];
  var preSuffixes = ['-', '\\+'];
  var suffixes = ['alpha', 'beta', 'ose', '[0-9]+'];
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
    if (RegExp(
      '${strict ? '^' : ''}$pattern${strict ? '\$' : ''}',
    ).hasMatch(version)) {
      results.add(pattern);
    }
  }
  return results;
}

List<String> moveStrToEnd(List<String> arr, String str, {String? strB}) {
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
  List<MapEntry<String, int>> arr,
  MapEntry<String, int> str, {
  MapEntry<String, int>? strB,
}) {
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
  String url,
  String fileName,
  bool fileNameHasExt,
  Function? onProgress,
  String destDir, {
  bool useExisting = true,
  Map<String, String>? headers,
  int retries = 3,
  bool allowInsecure = false,
  LogsProvider? logs,
}) async {
  try {
    return await downloadFile(
      url,
      fileName,
      fileNameHasExt,
      onProgress,
      destDir,
      useExisting: useExisting,
      headers: headers,
      allowInsecure: allowInsecure,
      logs: logs,
    );
  } catch (e) {
    if (retries > 0 && e is ClientException) {
      await Future.delayed(const Duration(seconds: 5));
      return await downloadFileWithRetry(
        url,
        fileName,
        fileNameHasExt,
        onProgress,
        destDir,
        useExisting: useExisting,
        headers: headers,
        retries: (retries - 1),
        allowInsecure: allowInsecure,
        logs: logs,
      );
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

Future<String> checkPartialDownloadHashDynamic(
  String url, {
  int startingSize = 1024,
  int lowerLimit = 128,
  Map<String, String>? headers,
  bool allowInsecure = false,
}) async {
  for (int i = startingSize; i >= lowerLimit; i -= 256) {
    List<String> ab = await Future.wait([
      checkPartialDownloadHash(
        url,
        i,
        headers: headers,
        allowInsecure: allowInsecure,
      ),
      checkPartialDownloadHash(
        url,
        i,
        headers: headers,
        allowInsecure: allowInsecure,
      ),
    ]);
    if (ab[0] == ab[1]) {
      return ab[0];
    }
  }
  throw NoVersionError();
}

Future<String> checkPartialDownloadHash(
  String url,
  int bytesToGrab, {
  Map<String, String>? headers,
  bool allowInsecure = false,
}) async {
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

Future<String?> checkETagHeader(
  String url, {
  Map<String, String>? headers,
  bool allowInsecure = false,
}) async {
  // Send the initial request but cancel it as soon as you have the headers
  var reqHeaders = headers ?? {};
  var req = Request('GET', Uri.parse(url));
  req.headers.addAll(reqHeaders);
  var client = IOClient(createHttpClient(allowInsecure));
  StreamedResponse response = await client.send(req);
  var resHeaders = response.headers;
  client.close();
  return resHeaders[HttpHeaders.etagHeader]
      ?.replaceAll('"', '')
      .hashCode
      .toString();
}

void deleteFile(File file) {
  try {
    file.deleteSync(recursive: true);
  } on PathAccessException catch (e) {
    throw ObtainiumError(
      tr('fileDeletionError', args: [e.path ?? tr('unknown')]),
    );
  }
}

Future<File> downloadFile(
  String url,
  String fileName,
  bool fileNameHasExt,
  Function? onProgress,
  String destDir, {
  bool useExisting = true,
  Map<String, String>? headers,
  bool allowInsecure = false,
  LogsProvider? logs,
}) async {
  // Send the initial request but cancel it as soon as you have the headers
  var reqHeaders = headers ?? {};
  var req = Request('GET', Uri.parse(url));
  req.headers.addAll(reqHeaders);
  var headersClient = IOClient(createHttpClient(allowInsecure));
  StreamedResponse headersResponse = await headersClient.send(req);
  var resHeaders = headersResponse.headers;

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
  headersClient.close();

  // If you have an existing file that is usable,
  // decide whether you can use it (either return full or resume partial)
  var fullContentLength = headersResponse.contentLength;
  if (useExisting && downloadedFile.existsSync()) {
    var length = downloadedFile.lengthSync();
    if (fullContentLength == null || !rangeFeatureEnabled) {
      // If there is no content length reported, assume it the existing file is fully downloaded
      // Also if the range feature is not supported, don't trust the content length if any (#1542)
      return downloadedFile;
    } else {
      // Check if resume needed/possible
      if (length == fullContentLength) {
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
      'Partial download exists - will wait: ${tempDownloadedFile.uri.pathSegments.last}',
    );
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
            'Existing partial download still in progress: ${tempDownloadedFile.uri.pathSegments.last}',
          );
        } else {
          logs?.add(
            'Ignoring existing partial download: ${tempDownloadedFile.uri.pathSegments.last}',
          );
          break;
        }
      } else {
        shouldReturn = downloadedFile.existsSync();
      }
    }
    if (shouldReturn) {
      logs?.add(
        'Existing partial download completed - not repeating: ${tempDownloadedFile.uri.pathSegments.last}',
      );
      return downloadedFile;
    } else {
      logs?.add(
        'Existing partial download not in progress: ${tempDownloadedFile.uri.pathSegments.last}',
      );
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
  req = Request('GET', Uri.parse(url));
  req.headers.addAll(reqHeaders);
  if (rangeFeatureEnabled && fullContentLength != null && rangeStart > 0) {
    reqHeaders.addAll({'range': 'bytes=$rangeStart-${fullContentLength - 1}'});
    sink = tempDownloadedFile.openWrite(mode: FileMode.writeOnlyAppend);
  } else if (tempDownloadedFile.existsSync()) {
    deleteFile(tempDownloadedFile);
  }
  var responseWithClient = await sourceRequestStreamResponse(
    'GET',
    url,
    reqHeaders,
    {},
  );
  HttpClient responseClient = responseWithClient.value.key;
  HttpClientResponse response = responseWithClient.value.value;
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
  await response
      .asBroadcastStream()
      .map((chunk) {
        received += chunk.length;
        final now = DateTime.now();
        if (onProgress != null &&
            (lastProgressUpdate == null ||
                now.difference(lastProgressUpdate!) >=
                    downloadUIUpdateInterval)) {
          progress = fullContentLength != null
              ? clampDouble((received / fullContentLength) * 100, 0, 100)
              : 30;
          onProgress(progress);
          lastProgressUpdate = now;
        }
        return chunk;
      })
      .transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
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
        ),
      )
      .pipe(sink);
  await sink.close();
  progress = null;
  if (onProgress != null) {
    onProgress(progress);
  }
  if (response.statusCode < 200 || response.statusCode > 299) {
    deleteFile(tempDownloadedFile);
    throw response.reasonPhrase;
  }
  if (tempDownloadedFile.existsSync()) {
    tempDownloadedFile.renameSync(downloadedFile.path);
  }
  responseClient.close();
  return downloadedFile;
}

Future<List<PackageInfo>> getAllInstalledInfo() async {
  return await pm.getInstalledPackages(flags: packageInfoFlags) ?? [];
}

Future<PackageInfo?> getInstalledInfo(
  String? packageName, {
  bool printErr = true,
}) async {
  if (packageName != null) {
    try {
      return await pm.getPackageInfo(
        packageName: packageName,
        flags: packageInfoFlags,
      );
    } catch (e) {
      if (printErr) {
        debugPrint(e.toString()); // OK
      }
    }
  }
  return null;
}

Future<Directory> getAppStorageDir() async =>
    await getExternalStorageDirectory() ??
    await getApplicationDocumentsDirectory();

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
  late Directory apkDir;
  late Directory iconsCacheDir;
  late SettingsProvider settingsProvider = SettingsProvider();

  Iterable<AppInMemory> getAppValues() => apps.values;

  /// Public wrapper around the protected [notifyListeners] so the provider's
  /// part-file extensions can request listeners to rebuild.
  void notify() => notifyListeners();

  AppsProvider({bool isBg = false}) {
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
        apkDir = cacheDirs!.first;
        iconsCacheDir = Directory('${cacheDirs.first.path}/icons');
        if (!iconsCacheDir.existsSync()) {
          iconsCacheDir.createSync();
        }
      } else {
        apkDir = Directory('${(await getAppStorageDir()).path}/apks');
        if (!apkDir.existsSync()) {
          apkDir.createSync();
        }
        iconsCacheDir = Directory('${(await getAppStorageDir()).path}/icons');
        if (!iconsCacheDir.existsSync()) {
          iconsCacheDir.createSync();
        }
      }
      if (!isBg) {
        // Load Apps into memory (in background processes, this is done later instead of in the constructor)
        await loadApps();
        // Delete any partial APKs (if safe to do so)
        var cutoff = DateTime.now().subtract(const Duration(days: 7));
        apkDir
            .listSync()
            .where((element) => element.statSync().modified.isBefore(cutoff))
            .forEach((partialApk) {
              if (!areDownloadsRunning()) {
                partialApk.delete(recursive: true);
              }
            });
      }
    }();
  }

  @override
  void dispose() {
    foregroundSubscription?.cancel();
    super.dispose();
  }

  Future<List<List<String>>> addAppsByURL(
    List<String> urls, {
    AppSource? sourceOverride,
  }) async {
    List<dynamic> results = await SourceProvider().getAppsByURLNaive(
      urls,
      alreadyAddedUrls: apps.values.map((e) => e.app.url).toList(),
      sourceOverride: sourceOverride,
    );
    List<App> pps = results[0];
    Map<String, dynamic> errorsMap = results[1];
    for (var app in pps) {
      if (apps.containsKey(app.id)) {
        errorsMap.addAll({app.id: tr('appAlreadyAdded')});
      } else {
        await saveApps([app], onlyIfExists: false);
      }
    }
    List<List<String>> errors = errorsMap.keys
        .map((e) => [e, errorsMap[e].toString()])
        .toList();
    return errors;
  }
}

/// Background updater function
///
/// @param `List<MapEntry<String, int>>?` toCheck: The appIds to check for updates (with the number of previous attempts made per appid) (defaults to all apps)
///
/// @param `List<String>?` toInstall: The appIds to attempt to update (if empty - which is the default - all pending updates are taken)
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
  debugPrint('BG task started $taskId: ${params.toString()}');
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

  bool firstEverUpdateTask =
      DateTime.fromMillisecondsSinceEpoch(
        0,
      ).compareTo(appsProvider.settingsProvider.lastCompletedBGCheckTime) ==
      0;

  List<MapEntry<String, int>> toCheck = <MapEntry<String, int>>[
    ...(params['toCheck']
            ?.map(
              (entry) => MapEntry<String, int>(
                entry['key'] as String,
                entry['value'] as int,
              ),
            )
            .toList() ??
        appsProvider
            .getAppsSortedByUpdateCheckTime(
              ignoreAppsCheckedAfter: params['toCheck'] == null
                  ? firstEverUpdateTask
                        ? null
                        : appsProvider.settingsProvider.lastCompletedBGCheckTime
                  : null,
              onlyCheckInstalledOrTrackOnlyApps: appsProvider
                  .settingsProvider
                  .onlyCheckInstalledOrTrackOnlyApps,
            )
            .map((e) => MapEntry(e, 0))),
  ];
  List<MapEntry<String, int>> toInstall = <MapEntry<String, int>>[
    ...(params['toInstall']
            ?.map(
              (entry) => MapEntry<String, int>(
                entry['key'] as String,
                entry['value'] as int,
              ),
            )
            .toList() ??
        (<List<MapEntry<String, int>>>[])),
  ];

  var networkRestricted =
      appsProvider.settingsProvider.bgUpdatesOnWiFiOnly &&
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

    var enoughTimePassed =
        appsProvider.settingsProvider.updateInterval != 0 &&
        appsProvider.settingsProvider.lastCompletedBGCheckTime
            .add(
              Duration(minutes: appsProvider.settingsProvider.updateInterval),
            )
            .isBefore(DateTime.now());
    if (!enoughTimePassed) {
      debugPrint(
        'BG update task: Too early for another check (last check was ${appsProvider.settingsProvider.lastCompletedBGCheckTime.toIso8601String()}, interval is ${appsProvider.settingsProvider.updateInterval}).',
      );
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
      plural('apps', toCheck.length),
    ); // The notif. to show while checking

    try {
      // Check for updates
      notificationsProvider.notify(notif, cancelExisting: true);
      updates = await appsProvider.checkUpdates(
        specificIds: toCheck.map((e) => e.key).toList(),
        sp: appsProvider.settingsProvider,
      );
    } catch (e) {
      if (e is Map) {
        updates = e['updates'];
        errors = e['errors'];
        errors!.rawErrors.forEach((key, err) {
          logs.add(
            'BG update task: Got error on checking for $key \'${err.toString()}\'.',
          );

          var toCheckApp = toCheck.where((element) => element.key == key).first;
          if (toCheckApp.value < maxAttempts) {
            toRetry.add(MapEntry(toCheckApp.key, toCheckApp.value + 1));
            // Next task interval is based on the error with the longest retry time
            int minRetryIntervalForThisApp = err is RateLimitError
                ? (err.remainingMinutes * 60)
                : err is ClientException
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
    List<App> trackOnlyToNotify = [];
    List<App> exemptToNotify = [];
    for (var i = 0; i < updates.length; i++) {
      var canInstallSilently = await appsProvider.canInstallSilently(
        updates[i],
      );
      if (networkRestricted || chargingRestricted || !canInstallSilently) {
        if (updates[i].additionalSettings['skipUpdateNotifications'] != true) {
          logs.add(
            'BG update task notifying for ${updates[i].id} (networkRestricted $networkRestricted, chargingRestricted: $chargingRestricted, canInstallSilently: $canInstallSilently).',
          );
          if (updates[i].additionalSettings['trackOnly'] == true) {
            trackOnlyToNotify.add(updates[i]);
          } else if (updates[i]
                  .additionalSettings['exemptFromBackgroundUpdates'] ==
              true) {
            exemptToNotify.add(updates[i]);
          } else {
            toNotify.add(updates[i]);
          }
        }
      }
    }

    // Send separate notifications to avoid one being cancelled
    // when the other is processed
    if (toNotify.isNotEmpty) {
      notificationsProvider.notify(UpdateNotification(toNotify));
    }
    if (trackOnlyToNotify.isNotEmpty) {
      notificationsProvider.notify(
        TrackOnlyUpdateNotification(trackOnlyToNotify),
      );
    }
    if (exemptToNotify.isNotEmpty) {
      notificationsProvider.notify(TrackOnlyUpdateNotification(exemptToNotify));
    }

    // Send the error notifications (grouped by error string)
    if (toThrow.rawErrors.isNotEmpty) {
      for (var element in toThrow.idsByErrorString.entries) {
        notificationsProvider.notify(
          ErrorCheckingUpdatesNotification(
            errors!.errorsAppsString(element.key, element.value),
            id: Random().nextInt(10000),
          ),
        );
      }
    }
    // if there are update checks to retry, schedule a retry task
    logs.add('BG update task: Done checking for updates.');
    if (toRetry.isNotEmpty) {
      logs.add(
        'BG update task $taskId: Will retry in $retryAfterXSeconds seconds (${toRetry.length} to retry, ${toInstall.length} to install).',
      );
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
      logs.add(
        'BG update task: Done checking for updates (${toRetry.length} to retry, ${toInstall.length} to install).',
      );
      return await bgUpdateCheck(taskId, {
        'toCheck': [],
        'toInstall': toInstall
            .map((entry) => {'key': entry.key, 'value': entry.value})
            .toList(),
      });
    }
  } else {
    // In install mode...
    // If you haven't explicitly been given updates to install, grab all available silent updates
    logs.add('BG install task: Started (${toInstall.length}).');
    if (toInstall.isEmpty && !networkRestricted && !chargingRestricted) {
      var temp = appsProvider.findExistingUpdates(installedOnly: true);
      for (var i = 0; i < temp.length; i++) {
        if (await appsProvider.canInstallSilently(
          appsProvider.apps[temp[i]]!.app,
        )) {
          toInstall.add(MapEntry(temp[i], 0));
        }
      }
    }
    if (toInstall.isNotEmpty) {
      var tempObtArr = toInstall.where(
        (element) =>
            element.key == obtainiumId || element.key == '$obtainiumId.fdroid',
      );
      if (tempObtArr.isNotEmpty) {
        // Move obtainium to the end of the list as it must always install last
        var obt = tempObtArr.first;
        toInstall = moveStrToEndMapEntryWithCount(toInstall, obt);
      }
      // Loop through all updates and install each
      try {
        await appsProvider.downloadAndInstallLatestApps(
          toInstall.map((e) => e.key).toList(),
          null,
          notificationsProvider: notificationsProvider,
          forceParallelDownloads: true,
        );
      } catch (e) {
        if (e is MultiAppMultiError) {
          e.idsByErrorString.forEach((key, value) {
            notificationsProvider.notify(
              ErrorCheckingUpdatesNotification(e.errorsAppsString(key, value)),
            );
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
