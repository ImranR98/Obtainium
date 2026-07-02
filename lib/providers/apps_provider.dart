// Manages state related to the list of Apps tracked by Obtainium.
//
// Exposes related functions such as those used to add, remove, download, and install Apps.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:android_system_font/android_system_font.dart';
import 'package:android_package_manager/android_package_manager.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/io_client.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_fgbg/flutter_fgbg.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:http/http.dart';
import 'package:obtainium/main.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/easy_localization_controller.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports

import 'package:obtainium/providers/apps_provider_import_export.dart';
import 'package:obtainium/providers/apps_provider_install.dart';
import 'package:obtainium/providers/apps_provider_lifecycle.dart';
import 'package:obtainium/providers/apps_provider_updates.dart';

export 'apps_provider_import_export.dart';
export 'apps_provider_install.dart';
export 'apps_provider_lifecycle.dart';
export 'apps_provider_updates.dart';

// Named constants for magic numbers and hardcoded values
const int _defaultRetries = 3;
const int _retryDelaySeconds = 5;
const int _partialHashCheckStartingSize = 1024;
const int _partialHashCheckLowerLimit = 128;
const int _partialHashCheckDecrement = 256;
const int _maxDownloadPolls = 43;
const int _downloadPollIntervalSeconds = 7;
const int _progressUpdateIntervalMs = 500;
const int _downloadBufferSize = 32 * 1024;
const int _downloadProgressFallback = 30;
const int _bgUpdateMaxAttempts = 4;
const int _bgUpdateMaxRetryWaitSeconds = 5;
const int _bgClientExceptionRetryWaitSeconds = 15 * 60;

final packageManager = AndroidPackageManager();
final packageInfoFlags = PackageInfoFlags({PMFlag.getSigningCertificates});

/// Runtime wrapper for [App] holding download state and OS package info.
class AppInMemory {
  late App app;
  final ValueNotifier<double?> downloadProgressNotifier = ValueNotifier(null);
  PackageInfo? installedInfo;
  Uint8List? icon;
  String? sourceType;

  double? get downloadProgress => downloadProgressNotifier.value;
  set downloadProgress(double? value) => downloadProgressNotifier.value = value;

  AppInMemory(
    this.app,
    double? downloadProgress,
    this.installedInfo,
    this.icon, {
    this.sourceType,
  }) {
    downloadProgressNotifier.value = downloadProgress;
  }

  AppInMemory deepCopy() => AppInMemory(
    app.copyWith(),
    downloadProgress,
    installedInfo,
    icon,
    sourceType: sourceType,
  );

  AppInMemory copyWith({
    App? app,
    double? downloadProgress,
    PackageInfo? installedInfo,
    Uint8List? icon,
    String? sourceType,
  }) => AppInMemory(
    app ?? this.app,
    downloadProgress ?? this.downloadProgress,
    installedInfo ?? this.installedInfo,
    icon ?? this.icon,
    sourceType: sourceType ?? this.sourceType,
  );

  String get name => app.overrideName ?? app.finalName;
  String get author => app.overrideAuthor ?? app.finalAuthor;

  bool get needsRefreshBeforeDownload =>
      app.settings.getBool('refreshBeforeDownload') ||
      (app.apkUrls.isNotEmpty && app.apkUrls.first.value == 'placeholder');

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

/// Delegates to [VersionService.findStandardFormatsForVersion].
Set<String> findStandardFormatsForVersion(String version, bool strict) =>
    VersionService().findStandardFormatsForVersion(version, strict);

/// Removes all matching elements and appends the last match to the end.
/// This is intentionally deduplicating — only one instance is re-added.
List<T> _moveToEnd<T extends Object>(List<T> arr, bool Function(T) match) {
  T? temp;
  arr.removeWhere((element) {
    if (match(element)) {
      temp = element;
      return true;
    }
    return false;
  });
  if (temp != null) {
    arr.add(temp as T);
  }
  return arr;
}

List<String> moveStrToEnd(List<String> arr, String str, {String? strB}) =>
    _moveToEnd(arr, (e) => e == str || e == strB);

List<MapEntry<String, int>> moveStrToEndMapEntryWithCount(
  List<MapEntry<String, int>> arr,
  MapEntry<String, int> str, {
  MapEntry<String, int>? strB,
}) => _moveToEnd(arr, (e) => e.key == str.key || e.key == strB?.key);

Future<File> downloadFileWithRetry(
  String url,
  String fileName,
  bool fileNameHasExt,
  Function? onProgress,
  String destDir, {
  bool useExisting = true,
  Map<String, String>? headers,
  int retries = _defaultRetries,
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
      await Future.delayed(
        const Duration(seconds: _retryDelaySeconds),
      );
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
  final bytes = utf8.encode(jsonEncode(data));
  return sha256.convert(bytes).toString().substring(0, 8);
}

Future<String> checkPartialDownloadHashDynamic(
  String url, {
  int startingSize = _partialHashCheckStartingSize,
  int lowerLimit = _partialHashCheckLowerLimit,
  Map<String, String>? headers,
  bool allowInsecure = false,
}) async {
  for (
    int i = startingSize;
    i >= lowerLimit;
    i -= _partialHashCheckDecrement
  ) {
    // Both requests fetch the same byte range to confirm the hash is
    // stable. The loop decrements on mismatch; when two consecutive
    // requests agree, the hash is considered valid.
    final List<String> ab = await Future.wait([
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
  final req = Request('GET', Uri.parse(url));
  if (headers != null) {
    req.headers.addAll(headers);
  }
  req.headers[HttpHeaders.rangeHeader] = 'bytes=0-$bytesToGrab';
  final client = IOClient(createHttpClient(allowInsecure));
  try {
    final response = await client.send(req);
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw ObtainiumError(response.reasonPhrase ?? tr('unexpectedError'));
    }
    final List<List<int>> bytes = await response.stream
        .take(bytesToGrab)
        .toList();
    return hashListOfLists(bytes);
  } finally {
    client.close();
  }
}

Future<String?> checkETagHeader(
  String url, {
  Map<String, String>? headers,
  bool allowInsecure = false,
}) async {
  final reqHeaders = headers ?? {};
  final req = Request('GET', Uri.parse(url));
  req.headers.addAll(reqHeaders);
  final client = IOClient(createHttpClient(allowInsecure));
  final StreamedResponse response = await client.send(req);
  final resHeaders = response.headers;
  await response.stream.drain<void>().catchError((err) {
    LogsProvider().add(
      'Error draining response stream: $err',
      level: LogLevel.error,
    );
  });
  client.close();
  return resHeaders[HttpHeaders.etagHeader]
      ?.replaceAll('"', '')
      .hashCode
      .toString();
}

void deleteFile(File file) {
  try {
    file.deleteSync();
  } on PathAccessException catch (e) {
    throw ObtainiumError(
      tr('fileDeletionError', args: [e.path ?? tr('unknown')]),
    );
  }
}

/// Waits for a concurrent download to finish by polling the temp file size.
/// Returns the completed file if one is available, or null if a fresh download is needed.
Future<File?> _waitForConcurrentDownload(
  File tempDownloadedFile,
  File downloadedFile,
  LogsProvider? logs,
) async {
  unawaited(
    logs?.add(
      'Partial download exists - will wait: ${tempDownloadedFile.uri.pathSegments.last}',
    ),
  );
  int currentTempFileSize = await tempDownloadedFile.length();
  int pollCount = 0;
  while (pollCount < _maxDownloadPolls) {
    pollCount++;
    await Future.delayed(
      const Duration(seconds: _downloadPollIntervalSeconds),
    );
    if (tempDownloadedFile.existsSync()) {
      final int newTempFileSize = await tempDownloadedFile.length();
      if (newTempFileSize > currentTempFileSize) {
        currentTempFileSize = newTempFileSize;
        unawaited(
          logs?.add(
            'Existing partial download still in progress: ${tempDownloadedFile.uri.pathSegments.last}',
          ),
        );
      } else {
        unawaited(
          logs?.add(
            'Ignoring existing partial download: ${tempDownloadedFile.uri.pathSegments.last}',
          ),
        );
        break;
      }
    } else {
      return downloadedFile.existsSync() ? downloadedFile : null;
    }
  }
  if (downloadedFile.existsSync()) {
    unawaited(
      logs?.add(
        'Existing partial download completed - not repeating: ${tempDownloadedFile.uri.pathSegments.last}',
      ),
    );
    return downloadedFile;
  }
  unawaited(
    logs?.add(
      'Existing partial download not in progress: ${tempDownloadedFile.uri.pathSegments.last}',
    ),
  );
  return null;
}

/// Downloads a file to [destDir] with progress reporting, resuming partial downloads when supported.
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
  final reqHeaders = headers ?? {};
  final headersClient = IOClient(createHttpClient(allowInsecure));

  final headReq = Request('HEAD', Uri.parse(url));
  headReq.headers.addAll(reqHeaders);
  var headersResponse = await headersClient.send(headReq);

  final bool headSucceeded =
      headersResponse.statusCode >= 200 && headersResponse.statusCode < 300;
  if (!headSucceeded) {
    final getReq = Request('GET', Uri.parse(url));
    getReq.headers.addAll(reqHeaders);
    headersResponse = await headersClient.send(getReq);
  }

  final resHeaders = headersResponse.headers;

  // Use the headers to decide what the file extension is, and
  // whether it supports partial downloads (range request), and
  // what the total size of the file is (if provided)
  String ext = resHeaders['content-disposition']?.split('.').last ?? 'apk';
  if (ext.endsWith('"')) {
    ext = ext.substring(0, ext.length - 1);
  }
  if ((AppSource.isApkOrContainerFile(Uri.tryParse(url)?.path ?? url) ||
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
  final fullContentLength = headersResponse.contentLength;
  if (useExisting && downloadedFile.existsSync()) {
    final length = downloadedFile.lengthSync();
    if (fullContentLength == null || !rangeFeatureEnabled) {
      return downloadedFile;
    } else {
      if (length == fullContentLength) {
        return downloadedFile;
      }
      if (length > fullContentLength) {
        useExisting = false;
      }
    }
  }

  final File tempDownloadedFile = File('${downloadedFile.path}.part');

  // If there is already a temp file, a download may already be in progress - account for this (see #2073)
  final bool tempFileExists = tempDownloadedFile.existsSync();
  if (tempFileExists && useExisting) {
    final result = await _waitForConcurrentDownload(
      tempDownloadedFile,
      downloadedFile,
      logs,
    );
    if (result != null) return result;
  }

  // If the range feature is not available (or you need to start a ranged req from 0),
  // complete the already-started request, else cancel it and start a ranged request,
  // and open the file for writing in the appropriate mode
  final targetFileLength = useExisting && tempDownloadedFile.existsSync()
      ? tempDownloadedFile.lengthSync()
      : null;
  int rangeStart = targetFileLength ?? 0;
  IOSink? sink;
  bool sentRangeRequest = false;
  if (rangeFeatureEnabled && fullContentLength != null && rangeStart > 0) {
    reqHeaders.addAll({'range': 'bytes=$rangeStart-${fullContentLength - 1}'});
    sink = tempDownloadedFile.openWrite(mode: FileMode.writeOnlyAppend);
    sentRangeRequest = true;
  } else if (tempDownloadedFile.existsSync()) {
    deleteFile(tempDownloadedFile);
  }
  final responseWithClient = await sourceRequestStreamResponse(
    'GET',
    url,
    reqHeaders,
    {'allowInsecure': allowInsecure},
  );
  final HttpClient responseClient = responseWithClient.value.key;
  final HttpClientResponse response = responseWithClient.value.value;
  try {
    // If we requested a byte range to resume a partial download but the server
    // ignored it and returned the full file (200 instead of 206 Partial
    // Content), appending would corrupt the file - discard the partial data and
    // start the download over from the beginning.
    if (sentRangeRequest && response.statusCode == HttpStatus.ok) {
      await sink?.close();
      sink = null;
      rangeStart = 0;
      if (tempDownloadedFile.existsSync()) {
        deleteFile(tempDownloadedFile);
      }
    }
    sink ??= tempDownloadedFile.openWrite(mode: FileMode.writeOnly);

    var received = 0;
    double? progress;
    DateTime? lastProgressUpdate; // Track last progress update time
    if (rangeStart > 0 && fullContentLength != null) {
      received = rangeStart;
    }

    const downloadUIUpdateInterval = Duration(
      milliseconds: _progressUpdateIntervalMs,
    );
    const downloadBufferSizeLocal = _downloadBufferSize;

    // Check status code BEFORE finishing the download stream so we can
    // abort early on errors and avoid wasting bandwidth reading a body
    // the server already rejected.
    if (response.statusCode < 200 || response.statusCode > 299) {
      await sink.close();
      sink = null;
      await response.drain<void>().catchError((_) {});
      if (tempDownloadedFile.existsSync()) {
        deleteFile(tempDownloadedFile);
      }
      throw ObtainiumError(
        response.reasonPhrase.isNotEmpty
            ? response.reasonPhrase
            : tr(
                'errorWithHttpStatusCode',
                args: [response.statusCode.toString()],
              ),
      );
    }

    final downloadBuffer = BytesBuilder();
    await response
        .map((chunk) {
          received += chunk.length;
          final now = DateTime.now();
          if (onProgress != null &&
              (lastProgressUpdate == null ||
                  now.difference(lastProgressUpdate!) >=
                      downloadUIUpdateInterval)) {
            progress = fullContentLength != null
                ? (received / fullContentLength * 100).clamp(0, 100)
                : _downloadProgressFallback.toDouble();
            onProgress(progress);
            lastProgressUpdate = now;
          }
          return chunk;
        })
        .transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleData: (List<int> data, EventSink<List<int>> s) {
              downloadBuffer.add(data);
              if (downloadBuffer.length >= downloadBufferSizeLocal) {
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
    if (tempDownloadedFile.existsSync()) {
      if (downloadedFile.existsSync()) {
        downloadedFile.deleteSync();
      }
      tempDownloadedFile.renameSync(downloadedFile.path);
    }
    return downloadedFile;
  } finally {
    responseClient.close();
  }
}

Future<List<PackageInfo>> getAllInstalledInfo() async {
  return await packageManager.getInstalledPackages(flags: packageInfoFlags) ??
      [];
}

Future<PackageInfo?> getInstalledInfo(
  String? packageName, {
  bool printErr = true,
}) async {
  if (packageName != null) {
    try {
      return await packageManager.getPackageInfo(
        packageName: packageName,
        flags: packageInfoFlags,
      );
    } catch (e) {
      if (printErr) {
        unawaited(LogsProvider().add(e.toString(), level: LogLevel.error));
      }
    }
  }
  return null;
}

Future<Directory> getAppStorageDir() async =>
    await getExternalStorageDirectory() ??
    await getApplicationDocumentsDirectory();

class AppsProvider with ChangeNotifier {
  // Static, app-lifetime cross-instance save-notification bus; intentionally
  // never closed. The foreground instance subscribes so it can detect saves
  // made by background tasks and reload as needed.
  // ignore: close_sinks
  static final StreamController<void> _eventsController =
      StreamController<void>.broadcast();

  // In memory App state (should always be kept in sync with local storage versions)
  Map<String, AppInMemory> apps = {};
  bool loadingApps = false;
  bool gettingUpdates = false;
  Completer<List<App>>? updateCheckCompleter;
  LogsProvider logs = LogsProvider();

  // Serializes concurrent loadApps() calls without busy-waiting.
  Completer<void>? appsLoadingCompleter;

  // Coalesces bursts of saveApps()/removeApps() into a single auto-export.
  Timer? _autoExportDebounce;

  // Set in dispose() to guard against deferred callbacks running post-disposal.
  bool _disposed = false;

  // Tracks whether a background save occurred since the last load.
  bool _needsBgReload = false;
  StreamSubscription<void>? _eventSubscription;

  // Variables to keep track of the app foreground status (installs can't run in the background)
  bool isForeground = true;
  bool _isBg = false;
  late final Stream<FGBGType>? foregroundStream;
  late final StreamSubscription<FGBGType>? foregroundSubscription;
  late final Directory apkDir;
  late final Directory iconsCacheDir;
  late final SettingsProvider settingsProvider;

  Iterable<AppInMemory> getAppValues() {
    _reloadIfBgSaved();
    return apps.values;
  }

  void _reloadIfBgSaved() {
    if (!_needsBgReload) return;
    _needsBgReload = false;
    loadApps();
  }

  /// Public wrapper around the protected [notifyListeners] so the provider's
  /// part-file extensions can request listeners to rebuild.
  void notify() => notifyListeners();

  /// Waits for any in-flight [loadApps] to finish, so concurrent callers
  /// serialize instead of busy-waiting on a polling loop.
  Future<void> waitForAppsToLoad() async {
    final completer = appsLoadingCompleter;
    if (completer != null) {
      await completer.future;
      await waitForAppsToLoad();
    }
  }

  /// Schedules a debounced automatic export. Coalesces the many per-app
  /// save/remove operations that happen in bursts into a single export.
  /// No-op (cheaply returns) if auto-export is disabled inside [export].
  void scheduleAutoExport() {
    _autoExportDebounce?.cancel();
    _autoExportDebounce = Timer(const Duration(seconds: 2), () {
      if (!_disposed) {
        export(isAuto: true);
      }
    });
  }

  AppsProvider({
    bool isBg = false,
    SettingsProvider? settingsProvider,
    LogsProvider? logsProvider,
  }) {
    _isBg = isBg;
    this.settingsProvider = settingsProvider ?? SettingsProvider();
    logs = logsProvider ?? LogsProvider();
    // Subscribe to changes in the app foreground status
    foregroundStream = FGBGEvents.instance.stream.asBroadcastStream();
    foregroundSubscription = foregroundStream?.listen((event) async {
      isForeground = event == FGBGType.foreground;
      if (isForeground) {
        await loadApps();
      }
    });
    if (!_isBg) {
      _eventSubscription = _eventsController.stream.listen((_) {
        _needsBgReload = true;
      });
    }
    () async {
      await this.settingsProvider.initializeSettings();
      final cacheDirs = await getExternalCacheDirectories();
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
        await loadApps();
        final cutoff = DateTime.now().subtract(const Duration(days: 7));
        await for (var entity in apkDir.list()) {
          if (entity is File &&
              entity.path.endsWith('.part') &&
              (await entity.stat()).modified.isBefore(cutoff)) {
            if (!areDownloadsRunning()) {
              await entity.delete();
            }
          }
        }
      }
    }().catchError((e) {
      logs.add('AppsProvider async init error: $e', level: LogLevel.error);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    foregroundSubscription?.cancel();
    _autoExportDebounce?.cancel();
    _eventSubscription?.cancel();
    super.dispose();
  }

  Future<List<List<String>>> addAppsByURL(
    List<String> urls, {
    AppSource? sourceOverride,
  }) async {
    final List<dynamic> results = await SourceProvider().getAppsByURLNaive(
      urls,
      alreadyAddedUrls: apps.values.map((e) => e.app.url).toSet(),
      sourceOverride: sourceOverride,
    );
    final List<App> pps = results[0];
    final Map<String, dynamic> errorsMap = results[1];
    for (var app in pps) {
      if (apps.containsKey(app.id)) {
        errorsMap.addAll({app.id: tr('appAlreadyAdded')});
      } else {
        await saveApps([app], onlyIfExists: false);
      }
    }
    final List<List<String>> errors = errorsMap.keys
        .map((e) => [e, errorsMap[e].toString()])
        .toList();
    return errors;
  }
}

Future<void> _runBGInstallMode(
  List<MapEntry<String, int>> toInstall,
  bool networkRestricted,
  bool chargingRestricted,
  AppsProvider appsProvider,
  NotificationsProvider notificationsProvider,
  LogsProvider logs,
) async {
  unawaited(logs.add('BG install task: Started (${toInstall.length}).'));
  if (toInstall.isEmpty && !networkRestricted && !chargingRestricted) {
    final temp = appsProvider.findAppIdsWithPendingUpdates(installedOnly: true);
    for (var i = 0; i < temp.length; i++) {
      if (await appsProvider.canInstallSilently(
        appsProvider.apps[temp[i]]!.app,
      )) {
        toInstall.add(MapEntry(temp[i], 0));
      }
    }
  }
  if (toInstall.isNotEmpty) {
    final obtainiumEntries = toInstall.where(
      (element) =>
          element.key == obtainiumId || element.key == '$obtainiumId.fdroid',
    );
    if (obtainiumEntries.isNotEmpty) {
      final obt = obtainiumEntries.first;
      toInstall = moveStrToEndMapEntryWithCount(toInstall, obt);
    }
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
        unawaited(logs.add('Fatal error in BG install task: ${e.toString()}'));
        rethrow;
      }
    }
    unawaited(logs.add('BG install task: Done installing updates.'));
  }
}

/// Background update check and installation orchestrator.
///
/// In "update mode" (toCheck is non-empty): checks [toCheck] apps in parallel,
/// notifies the user of any non-silent updates, and retries failed checks.
///
/// In "install mode" (toCheck is empty): downloads and silently installs all
/// pending updates, placing Obtainium last in the install queue.
Future<void> bgUpdateCheck(
  String taskId,
  Map<String, dynamic>? params, {
  LogsProvider? logs,
  NotificationsProvider? notifs,
  SettingsProvider? settings,
}) async {
  final l = logs ?? LogsProvider();
  unawaited(l.add('BG task started $taskId: ${params.toString()}'));
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await TranslationLoader.load();

  final NotificationsProvider notificationsProvider =
      notifs ?? NotificationsProvider();
  final AppsProvider appsProvider = AppsProvider(
    isBg: true,
    settingsProvider: settings,
    logsProvider: l,
  );
  await appsProvider.loadApps();

  const int maxAttempts = _bgUpdateMaxAttempts;
  const int maxRetryWaitSeconds = _bgUpdateMaxRetryWaitSeconds;

  final netResult = await (Connectivity().checkConnectivity());
  if (netResult.contains(ConnectivityResult.none) ||
      netResult.isEmpty ||
      (netResult.contains(ConnectivityResult.vpn) && netResult.length == 1)) {
    unawaited(l.add('BG update task: No network.'));
    return;
  }

  params ??= {};

  final bool firstEverUpdateTask =
      DateTime.fromMillisecondsSinceEpoch(
        0,
      ).compareTo(appsProvider.settingsProvider.lastCompletedBGCheckTime) ==
      0;

  DateTime? ignoreAfter;
  if (params['toCheck'] == null) {
    ignoreAfter = firstEverUpdateTask
        ? null
        : appsProvider.settingsProvider.lastCompletedBGCheckTime;
  }

  final List<MapEntry<String, int>> toCheck = <MapEntry<String, int>>[
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
              ignoreAppsCheckedAfter: ignoreAfter,
              onlyCheckInstalledOrTrackOnlyApps: appsProvider
                  .settingsProvider
                  .onlyCheckInstalledOrTrackOnlyApps,
            )
            .map((e) => MapEntry(e, 0))),
  ];
  final List<MapEntry<String, int>> toInstall = <MapEntry<String, int>>[
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

  final networkRestricted =
      appsProvider.settingsProvider.bgUpdatesOnWiFiOnly &&
      !netResult.contains(ConnectivityResult.wifi) &&
      !netResult.contains(ConnectivityResult.ethernet);

  final chargingRestricted =
      appsProvider.settingsProvider.bgUpdatesWhileChargingOnly &&
      (await Battery().batteryState) != BatteryState.charging;

  if (networkRestricted) {
    unawaited(l.add('BG update task: Network restriction in effect.'));
  }

  if (chargingRestricted) {
    unawaited(l.add('BG update task: Charging restriction in effect.'));
  }

  if (toCheck.isNotEmpty) {
    await _bgRunUpdateCheck(
      taskId,
      toCheck,
      toInstall,
      networkRestricted,
      chargingRestricted,
      maxAttempts,
      maxRetryWaitSeconds,
      appsProvider,
      notificationsProvider,
      l,
    );
  } else {
    await _runBGInstallMode(
      toInstall,
      networkRestricted,
      chargingRestricted,
      appsProvider,
      notificationsProvider,
      l,
    );
  }
  appsProvider.settingsProvider.lastCompletedBGCheckTime = DateTime.now();
  AppsProvider._eventsController.add(null);
}

Future<void> _bgRunUpdateCheck(
  String taskId,
  List<MapEntry<String, int>> toCheck,
  List<MapEntry<String, int>> toInstall,
  bool networkRestricted,
  bool chargingRestricted,
  int maxAttempts,
  int maxRetryWaitSeconds,
  AppsProvider appsProvider,
  NotificationsProvider notificationsProvider,
  LogsProvider logs,
) async {
  final enoughTimePassed =
      appsProvider.settingsProvider.updateInterval != 0 &&
      appsProvider.settingsProvider.lastCompletedBGCheckTime
          .add(Duration(minutes: appsProvider.settingsProvider.updateInterval))
          .isBefore(DateTime.now());
  if (!enoughTimePassed) {
    unawaited(
      logs.add(
        'BG update task: Too early for another check (last check was ${appsProvider.settingsProvider.lastCompletedBGCheckTime.toIso8601String()}, interval is ${appsProvider.settingsProvider.updateInterval}).',
      ),
    );
    return;
  }

  unawaited(logs.add('BG update task: Started (${toCheck.length}).'));

  List<App> updates = [];
  final List<App> toNotify = [];
  final List<MapEntry<String, int>> toRetry = [];
  var retryAfterXSeconds = 0;
  MultiAppMultiError? errors;
  final MultiAppMultiError toThrow = MultiAppMultiError();
  final CheckingUpdatesNotification notif = CheckingUpdatesNotification(
    plural('apps', toCheck.length),
  );

  try {
    unawaited(notificationsProvider.notify(notif, cancelExisting: true));
    updates = await appsProvider.checkUpdates(
      specificIds: toCheck.map((e) => e.key).toList(),
      sp: appsProvider.settingsProvider,
    );
  } catch (e) {
    if (e is CheckUpdatesException) {
      updates = e.updates;
      errors = e.errors;
      errors.rawErrors.forEach((key, err) {
        logs.add(
          'BG update task: Got error on checking for $key \'${err.toString()}\'.',
        );

        final toCheckApp = toCheck.firstWhere(
          (element) => element.key == key,
          orElse: () => MapEntry(key, 0),
        );
        if (toCheckApp.value < maxAttempts) {
          toRetry.add(MapEntry(toCheckApp.key, toCheckApp.value + 1));
          int minRetryIntervalForThisApp = err is RateLimitError
              ? (err.remainingMinutes * 60)
              : err is ClientException
              ? (_bgClientExceptionRetryWaitSeconds)
              : (toCheckApp.value + 1);
          if (minRetryIntervalForThisApp > maxRetryWaitSeconds) {
            minRetryIntervalForThisApp = maxRetryWaitSeconds;
          }
          if (minRetryIntervalForThisApp > retryAfterXSeconds) {
            retryAfterXSeconds = minRetryIntervalForThisApp;
          }
        } else {
          if (err is! RateLimitError) {
            toThrow.add(key, err, appName: errors!.appIdNames[key]);
          }
        }
      });
    } else {
      unawaited(logs.add('Fatal error in BG update task: ${e.toString()}'));
      rethrow;
    }
  } finally {
    unawaited(notificationsProvider.cancel(notif.id));
  }

  final List<App> trackOnlyToNotify = [];
  final List<App> exemptToNotify = [];
  for (var i = 0; i < updates.length; i++) {
    final canInstallSilently = await appsProvider.canInstallSilently(
      updates[i],
    );
    if (networkRestricted || chargingRestricted || !canInstallSilently) {
      if (!updates[i].settings.getBool('skipUpdateNotifications')) {
        unawaited(
          logs.add(
            'BG update task notifying for ${updates[i].id} (networkRestricted $networkRestricted, chargingRestricted: $chargingRestricted, canInstallSilently: $canInstallSilently).',
          ),
        );
        if (updates[i].settings.getBool('trackOnly')) {
          trackOnlyToNotify.add(updates[i]);
        } else if (updates[i].settings.getBool('exemptFromBackgroundUpdates')) {
          exemptToNotify.add(updates[i]);
        } else {
          toNotify.add(updates[i]);
        }
      }
    }
  }

  if (toNotify.isNotEmpty) {
    unawaited(notificationsProvider.notify(UpdateNotification(toNotify)));
  }
  if (trackOnlyToNotify.isNotEmpty) {
    unawaited(
      notificationsProvider.notify(
        TrackOnlyUpdateNotification(trackOnlyToNotify),
      ),
    );
  }
  if (exemptToNotify.isNotEmpty) {
    unawaited(notificationsProvider.notify(UpdateNotification(exemptToNotify)));
  }

  if (toThrow.rawErrors.isNotEmpty) {
    for (var element in toThrow.idsByErrorString.entries) {
      unawaited(
        notificationsProvider.notify(
          ErrorCheckingUpdatesNotification(
            (errors ?? toThrow).errorsAppsString(element.key, element.value),
            id: Random().nextInt(10000),
          ),
        ),
      );
    }
  }

  unawaited(logs.add('BG update task: Done checking for updates.'));
  if (toRetry.isNotEmpty) {
    unawaited(
      logs.add(
        'BG update task $taskId: Will retry in $retryAfterXSeconds seconds (${toRetry.length} to retry, ${toInstall.length} to install).',
      ),
    );
    if (retryAfterXSeconds > 0) {
      await Future.delayed(Duration(seconds: retryAfterXSeconds));
    }
    return await bgUpdateCheck(taskId, {
      'toCheck': toRetry
          .map((entry) => {'key': entry.key, 'value': entry.value})
          .toList(),
      'toInstall': toInstall
          .map((entry) => {'key': entry.key, 'value': entry.value})
          .toList(),
    });
  } else {
    unawaited(
      logs.add(
        'BG update task: Done checking for updates (${toRetry.length} to retry, ${toInstall.length} to install).',
      ),
    );
    return await bgUpdateCheck(taskId, {
      'toCheck': [],
      'toInstall': toInstall
          .map((entry) => {'key': entry.key, 'value': entry.value})
          .toList(),
    });
  }
}

class CancellationException implements Exception {}

class CancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw CancellationException();
  }
}

/// Tracks device connectivity to support offline-aware behaviour.
///
/// Exposes the current [isOnline] state and an [onConnectivityChanged] stream
/// that emits only when the online/offline state actually flips.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  Stream<bool> get onConnectivityChanged => _controller.stream;
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  ConnectivityService() {
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      if (wasOnline != _isOnline) {
        _controller.add(_isOnline);
      }
    });
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}

class InstallContextService {
  Future<Directory> getApkDirectory() async {
    final cacheDirs = await getExternalCacheDirectories();
    if (cacheDirs?.isNotEmpty ?? false) {
      return cacheDirs!.first;
    }
    final storageDir = Directory('${(await getAppStorageDir()).path}/apks');
    if (!storageDir.existsSync()) {
      storageDir.createSync(recursive: true);
    }
    return storageDir;
  }

  Future<Directory> getIconsCacheDir() async {
    final cacheDirs = await getExternalCacheDirectories();
    if (cacheDirs?.isNotEmpty ?? false) {
      final dir = Directory('${cacheDirs!.first.path}/icons');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    }
    final dir = Directory('${(await getAppStorageDir()).path}/icons');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }
}

class AppIdService {
  Future<String?> tryInferAppId(
    AppSource source,
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      return await source.tryInferringAppId(
        standardUrl,
        additionalSettings: additionalSettings,
      );
    } catch (_) {
      return null;
    }
  }

  String generateTempId(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) => (standardUrl + additionalSettings.toString()).hashCode.toString();
}

/// Isolates the implementation-level `easy_localization/src/` imports to a
/// single file so the rest of the codebase only depends on the public API.
class TranslationLoader {
  static Future<void> load() async {
    await EasyLocalizationController.initEasyLocation();
    final s = SettingsProvider();
    await s.initializeSettings();
    final forceLocale = s.forcedLocale;
    final controller = EasyLocalizationController(
      saveLocale: true,
      forceLocale: forceLocale,
      fallbackLocale: fallbackLocale,
      supportedLocales: supportedLocales.map((e) => e.key).toList(),
      assetLoader: const RootBundleAssetLoader(),
      useOnlyLangCode: false,
      useFallbackTranslations: true,
      path: localeDir,
      onLoadError: (FlutterError e) {
        throw e;
      },
    );
    await controller.loadTranslations();
    Localization.load(
      controller.locale,
      translations: controller.translations,
      fallbackTranslations: controller.fallbackTranslations,
    );
  }
}
// Platform channel helpers for native OS features (e.g. system font loading).

class NativeFeatures {
  static bool _systemFontLoaded = false;

  static Future<ByteData> _readFileBytes(String path) async {
    final bytes = await File(path).readAsBytes();
    return ByteData.view(bytes.buffer);
  }

  static Future<void> loadSystemFont() async {
    if (_systemFontLoaded) return;
    final fontLoader = FontLoader('SystemFont');
    final fontFilePath = await AndroidSystemFont().getFilePath();
    if (fontFilePath == null) return;
    fontLoader.addFont(_readFileBytes(fontFilePath));
    await fontLoader.load();
    _systemFontLoaded = true;
  }
}
