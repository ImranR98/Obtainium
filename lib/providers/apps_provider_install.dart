import 'dart:async';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:android_package_manager/android_package_manager.dart';
import 'package:archive/archive.dart' as archive;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:flutter_fgbg/flutter_fgbg.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:obtainium/components/app_detail_widgets.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/installers/external_installer.dart';
import 'package:obtainium/installers/installer.dart';
import 'package:obtainium/installers/root_installer.dart';
import 'package:obtainium/installers/shizuku_installer.dart';
import 'package:obtainium/installers/stock_installer.dart';
import 'package:obtainium/installers/install_utils.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/utils/signing_cert_utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_storage/shared_storage.dart' as saf;

// NOTE: This provider extension is intentionally UX-coupled — it shows dialogs,
// toasts, and interacts with BuildContext for install operations that inherently
// require user interaction (APK file pickers, permission prompts, foreground
// detection, etc.). Decoupling these would add indirection without real benefit.

// Named constants for magic numbers and hardcoded values
const int _androidApiLevelR = 30;
const double _installingProgressSentinel = -1;
const int _downloadCompleteProgress = 100;
const int _remainingStepsProgress = 90;
// Package IDs of "Verified Apps" (formerly AppVerifier) and its known forks
// that accept a shared APK for verification before installation.
const List<String> _verifiedAppsPackageIds = [
  'dev.soupslurpr.appverifier', // AppVerifier (original)
  'com.roundsalmon4.appverifier', // AppVerifierBG fork
  'org.privacyguides.verifiedapps', // Privacy Guides "Verified Apps"
  'org.privacyguides.verifiedapps.play', // Privacy Guides "Verified Apps" (Play)
];

// A silent background install can't report completion synchronously — the
// platform install API's result never arrives while backgrounded (#896). The
// session still commits, so we poll (via waitForPackageInstall) for a short
// window to confirm the install actually landed.
const int _bgInstallConfirmAttempts = 20; // 20 × 500ms = 10 seconds

// Foreground stock-installer installs race the intent-based result against
// package polling (#3255): a lost result (e.g. the activity was recreated
// while the user was at a system prompt) must never stall the install chain.
const int _installConfirmPollAttempts = 300; // 300 × 1s ≈ 5 minutes
const Duration _installConfirmTimeout = Duration(minutes: 10);

class _InstallResult {
  final String id;
  final bool willBeSilent;
  final DownloadedApk? downloadedFile;
  final DownloadedDir? downloadedDir;
  const _InstallResult({
    required this.id,
    required this.willBeSilent,
    this.downloadedFile,
    this.downloadedDir,
  });
}

/// App download, install, and on-device package operations for [AppsProvider].
extension AppsProviderInstall on AppsProvider {
  /// Returns the [Installer] strategy for the current installer mode setting.
  Installer getInstaller() {
    switch (settingsProvider.installerMode) {
      case 'shizuku':
        return ShizukuInstaller(settingsProvider);
      case 'external':
        return ExternalInstaller(settingsProvider);
      case 'root':
        return RootInstaller(settingsProvider);
      default:
        return StockInstaller(settingsProvider);
    }
  }

  /// Returns the renamed file and the resolved app; callers must use the
  /// returned app's ID since [App] is immutable.
  Future<(File, App)> handleAPKIDChange(
    App app,
    PackageInfo newInfo,
    File downloadedFile,
    String downloadUrl,
  ) async {
    // If the APK package ID is different from the App ID, it is either new (using a placeholder ID) or the ID has changed
    // The former case should be handled (give the App its real ID), the latter is a security issue
    final isTempIdBool = isTempId(app);
    final actualPackageName = newInfo.packageName;
    if (app.id != actualPackageName) {
      if (actualPackageName == null) {
        throw ObtainiumError(tr('couldNotGetIdFromApk'))..url = app.url;
      }
      if (apps[app.id] != null && !isTempIdBool && !app.allowIdChange) {
        throw IDChangedError(actualPackageName)..url = app.url;
      }
      final idChangeWasAllowed = app.allowIdChange;
      final originalAppId = app.id;
      app = app.copyWith(id: actualPackageName, allowIdChange: false);
      downloadedFile = downloadedFile.renameSync(
        '${downloadedFile.parent.path}/${app.id}-${downloadUrl.hashCode}.${downloadedFile.path.split('.').last}',
      );
      if (apps[originalAppId] != null) {
        await removeApps([originalAppId]);
        await saveApps([
          app,
        ], onlyIfExists: !isTempIdBool && !idChangeWasAllowed);
      }
    }
    return (downloadedFile, app);
  }

  Future<void> updatePendingRepoRename(String appId, String? newUrl) async {
    if (apps.containsKey(appId)) {
      apps[appId]!.app = apps[appId]!.app.copyWith(
        pendingRepoRenameUrl: newUrl,
      );
      await saveApps([apps[appId]!.app]);
    }
  }

  /// Applies a detected repository rename: adopts [newUrl] and clears the
  /// pending-rename flag so update checks resume.
  Future<void> acceptRepoRename(String appId, String newUrl) async {
    if (apps.containsKey(appId)) {
      apps[appId]!.app = apps[appId]!.app.copyWith(
        url: newUrl,
        pendingRepoRenameUrl: null,
      );
      await saveApps([apps[appId]!.app]);
    }
  }

  /// Downloads the preferred APK for [app], returning a [DownloadedApk] or [DownloadedDir].
  Future<Object> downloadApp(
    App app,
    BuildContext? context, {
    NotificationsProvider? notificationsProvider,
    bool useExisting = true,
  }) async {
    final notifId = DownloadNotification(app.finalName, 0, idKey: app.id).id;
    final cancellationToken = registerDownloadCancellation(app.id);
    try {
      if (apps[app.id] != null) {
        apps[app.id]!.downloadProgress = 0;
        apps[app.id]!.downloadReceivedBytes = null;
        apps[app.id]!.downloadTotalBytes = null;
        notify();
      }
      if (app.apkUrls.isEmpty) throw NoAPKError();
      if (app.preferredApkIndex >= app.apkUrls.length) {
        app = app.copyWith(preferredApkIndex: app.apkUrls.length - 1);
      }
      if (app.preferredApkIndex < 0) app = app.copyWith(preferredApkIndex: 0);
      if (apps[app.id] != null) apps[app.id]!.app = app;
      final AppSource source = SourceProvider().getSource(
        app.url,
        overrideSource: app.overrideSource,
      );
      final additionalSettingsPlusSourceConfig = await source
          .buildMergedSettings(app.additionalSettings, settingsProvider);
      final List<String> apkUrlValues = splitMultiApkUrl(
        app.apkUrls[app.preferredApkIndex].value,
      );
      final List<String> downloadUrls = [];
      for (final apkUrlValue in apkUrlValues) {
        downloadUrls.add(
          await source.assetUrlPrefetchModifier(
            await source.generalReqPrefetchModifier(
              apkUrlValue,
              additionalSettingsPlusSourceConfig,
            ),
            app.url,
            additionalSettingsPlusSourceConfig,
          ),
        );
      }
      final String downloadUrl = downloadUrls.first;
      final bool multipleApks = downloadUrls.length > 1;
      var notif = DownloadNotification(
        app.finalName,
        _downloadCompleteProgress,
        idKey: app.id,
      );
      unawaited(notificationsProvider?.cancel(notifId));
      int? prevProg;
      var fileNameNoExt = '${app.id}-${downloadUrl.hashCode}';
      if (source.urlsAlwaysHaveExtension) {
        fileNameNoExt =
            '$fileNameNoExt.${app.apkUrls[app.preferredApkIndex].key.split('.').last}';
      }
      additionalSettingsPlusSourceConfig['allowInsecure'] = app.settings
          .getBool('allowInsecure');
      additionalSettingsPlusSourceConfig['allowInsecureRedirects'] =
          source.allowInsecureRedirects;
      additionalSettingsPlusSourceConfig['enableCertificatePinning'] =
          settingsProvider.enableCertificatePinning;
      // Multiple URLs (a base APK plus splits) are downloaded sequentially, so
      // each file's 0-100 progress is scaled into the overall progress.
      int completedDownloads = 0;
      void reportProgress(double? progress, [int? received, int? total]) {
        final double? overallProgress = progress == null
            ? null
            : (completedDownloads * 100 + progress) / downloadUrls.length;
        final int? prog = overallProgress?.ceil();
        if (apps[app.id] != null) {
          apps[app.id]!.downloadReceivedBytes = received;
          apps[app.id]!.downloadTotalBytes = total;
          apps[app.id]!.downloadProgress = overallProgress;
          // Only rebuild listeners when the displayed (integer) percent
          // actually changes, to avoid redundant whole-page rebuilds on
          // every sub-percent download tick.
          if (prevProg != prog) {
            notify();
          }
        }
        notif = DownloadNotification(
          app.finalName,
          prog ?? _downloadCompleteProgress,
          // Only foreground downloads are cancellable from the notification;
          // the background isolate's token isn't reachable from the main
          // isolate that handles the action tap.
          appId: isBg ? null : app.id,
          idKey: app.id,
          receivedBytes: received,
          totalBytes: total,
        );
        if (prog != null && prevProg != prog) {
          unawaited(notificationsProvider?.notify(notif));
        }
        prevProg = prog;
      }

      final headers = await source.getRequestHeaders(
        app.additionalSettings,
        downloadUrl,
        forAPKDownload: true,
      );
      additionalSettingsPlusSourceConfig['url'] = downloadUrl;
      var downloadedFile = await downloadFileWithRetry(
        fileNameNoExt,
        source.urlsAlwaysHaveExtension,
        headers: headers,
        reportProgress,
        this.apkDir.path,
        additionalSettingsPlusSourceConfig,
        useExisting: useExisting,
        cancellationToken: cancellationToken,
      );
      completedDownloads = 1;
      if (apps[app.id] != null) {
        apps[app.id]!.downloadProgress = _remainingStepsProgress.toDouble();
        notify();
        notif = DownloadNotification(
          app.finalName,
          _remainingStepsProgress,
          idKey: app.id,
        );
        unawaited(notificationsProvider?.notify(notif));
      }
      PackageInfo? newInfo;
      final originalAssetName = app.apkUrls[app.preferredApkIndex].key
          .toLowerCase();
      final isAPK = downloadedFile.path.toLowerCase().endsWith('.apk');
      final isXAPK = downloadedFile.path.toLowerCase().endsWith('.xapk');
      final isTarball =
          originalAssetName.endsWith('.tar.gz') ||
          originalAssetName.endsWith('.tgz') ||
          originalAssetName.endsWith('.tar.bz2') ||
          originalAssetName.endsWith('.tar.xz');
      Directory? apkDir;
      if (isAPK && !multipleApks) {
        newInfo = await packageManager.getPackageArchiveInfo(
          archiveFilePath: downloadedFile.path,
        );
      } else {
        final String apkDirPath = '${downloadedFile.path}-dir';
        if (isTarball) {
          await extractTarballFile(downloadedFile.path, apkDirPath);
        } else if (isAPK) {
          // A base APK plus split URLs: move the base into the bundle dir so
          // everything is installed together.
          downloadedFile = downloadedFile.renameSync(
            '$apkDirPath/${downloadedFile.path.split('/').last}',
          );
        } else {
          await unzipFile(downloadedFile.path, apkDirPath);
        }
        if (multipleApks) {
          // Download the remaining split URLs into the same directory.
          for (var i = 1; i < downloadUrls.length; i++) {
            final splitUrl = downloadUrls[i];
            final splitHeaders = await source.getRequestHeaders(
              app.additionalSettings,
              splitUrl,
              forAPKDownload: true,
            );
            additionalSettingsPlusSourceConfig['url'] = splitUrl;
            completedDownloads = i;
            final splitFile = await downloadFileWithRetry(
              '$fileNameNoExt-$i',
              false,
              reportProgress,
              this.apkDir.path,
              additionalSettingsPlusSourceConfig,
              useExisting: useExisting,
              headers: splitHeaders,
              cancellationToken: cancellationToken,
            );
            if (splitFile.path.toLowerCase().endsWith('.apk')) {
              splitFile.renameSync(
                '$apkDirPath/${splitFile.path.split('/').last}',
              );
            } else {
              await unzipFile(splitFile.path, apkDirPath);
              unawaited(splitFile.delete());
            }
          }
          completedDownloads = downloadUrls.length;
        }
        apkDir = Directory(apkDirPath);
        var apks = apkDir
            .listSync(recursive: true)
            .where((e) => AppSource.isApkOrContainerFile(e.path))
            .toList();

        apks = _preferMatchingApk(apks, app.id);
        if (multipleApks) {
          apks = _moveSplitBaseFirst(apks);
        }

        String? filterRegEx;
        if (isTarball &&
            app.settings
                    .getStringOrNull('tarballedApkFilterRegEx')
                    ?.isNotEmpty ==
                true) {
          filterRegEx = app.settings.getStringOrNull('tarballedApkFilterRegEx');
        } else if (!isTarball &&
            app.settings.getStringOrNull('zippedApkFilterRegEx')?.isNotEmpty ==
                true) {
          filterRegEx = app.settings.getStringOrNull('zippedApkFilterRegEx');
        }
        if (filterRegEx != null) {
          final reg = RegExp(filterRegEx);
          apks.removeWhere((apk) {
            final relativePath = apk.path.substring(apkDir!.path.length + 1);
            final shouldDelete = !reg.hasMatch(relativePath);
            if (shouldDelete) {
              apk.delete();
            }
            return shouldDelete;
          });
        }

        if (apks.isEmpty) {
          throw NoAPKError();
        }

        for (var i = 0; i < apks.length; i++) {
          try {
            newInfo = await packageManager.getPackageArchiveInfo(
              archiveFilePath: apks[i].path,
            );
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
        unawaited(downloadedFile.delete());
        if (apkDir != null && apkDir.existsSync()) {
          apkDir.deleteSync(recursive: true);
        }
        throw ObtainiumError(tr('couldNotGetIdFromApk'))..url = app.url;
      }
      final (renamedFile, resolvedApp) = await handleAPKIDChange(
        app,
        newInfo,
        downloadedFile,
        downloadUrl,
      );
      downloadedFile = renamedFile;
      final String resolvedAppId = resolvedApp.id;
      // Delete older versions of the file if any (keyed to the resolved id,
      // since the id may have changed from a placeholder to the real package).
      for (var file in downloadedFile.parent.listSync()) {
        final fn = file.path.split('/').last;
        if (fn.startsWith('$resolvedAppId-') &&
            FileSystemEntity.isFileSync(file.path) &&
            file.path != downloadedFile.path) {
          unawaited(file.delete(recursive: true));
        }
      }
      if (isAPK && !multipleApks) {
        return DownloadedApk(resolvedAppId, downloadedFile);
      } else {
        DownloadedDirType dirType;
        if (multipleApks) {
          dirType = DownloadedDirType.splitApks;
        } else if (isXAPK) {
          dirType = DownloadedDirType.xapk;
        } else if (isTarball) {
          dirType = DownloadedDirType.tarball;
        } else {
          dirType = DownloadedDirType.zip;
        }
        return DownloadedDir(resolvedAppId, downloadedFile, apkDir!, dirType);
      }
    } finally {
      clearDownloadCancellation(app.id);
      unawaited(notificationsProvider?.cancel(notifId));
      if (apps[app.id] != null) {
        apps[app.id]!.downloadProgress = null;
        apps[app.id]!.downloadReceivedBytes = null;
        apps[app.id]!.downloadTotalBytes = null;
        notify();
      }
    }
  }

  bool areDownloadsRunning() => apps.values
      .where((element) => element.downloadProgress != null)
      .isNotEmpty;

  /// Whether [app] can be installed without a user prompt, based only on
  /// device/app capability (single APK plus the active installer's own rules).
  /// Independent of the background-update setting.
  Future<bool> canInstallSilently(App app) async {
    if (app.apkUrls.length > 1) {
      AppLogger.info(
        'App will not be installed silently: multiple APK URLs require manual selection: ${app.id}',
      );
      return false; // Manual API selection means silent install is not possible
    }
    // Installer-specific eligibility (target SDK, installer of record, OS
    // version, Shizuku, etc.) is delegated to the active installer strategy.
    return getInstaller().canInstallSilently(app);
  }

  /// Whether [app] should be installed silently in the background: the
  /// background-update policy (global toggle + per-app exemption) on top of
  /// [canInstallSilently]. Foreground installs must not use this.
  Future<bool> canInstallSilentlyInBackground(App app) async {
    if (!settingsProvider.enableBackgroundUpdates) {
      AppLogger.info(
        'App will not be installed in the background: background updates are disabled: ${app.id}',
      );
      return false;
    }
    if (app.settings.getBool('exemptFromBackgroundUpdates')) {
      AppLogger.info(
        'App will not be installed in the background: exempted from background updates: ${app.id}',
      );
      return false;
    }
    return canInstallSilently(app);
  }

  Future<void> waitForUserToReturnToForeground(BuildContext context) async {
    final NotificationsProvider notificationsProvider = context
        .read<NotificationsProvider>();
    if (!isForeground) {
      await notificationsProvider.notify(
        completeInstallationNotification,
        cancelExisting: true,
      );
      await FGBGEvents.instance.stream
          .firstWhere((t) => t == FGBGType.foreground)
          .timeout(
            const Duration(minutes: 5),
            onTimeout: () => FGBGType.foreground,
          );
      await notificationsProvider.cancel(completeInstallationNotification.id);
    }
  }

  Future<bool> canDowngradeApps() async =>
      (await getInstalledInfo('com.berdik.letmedowngrade')) != null;

  Future<void> unzipFile(String filePath, String destinationPath) async {
    await ZipFile.extractToDirectory(
      zipFile: File(filePath),
      destinationDir: Directory(destinationPath),
    );
  }

  Future<void> extractTarballFile(
    String filePath,
    String destinationPath,
  ) async {
    final File tarballFile = File(filePath);
    final bytes = await tarballFile.readAsBytes();
    List<int> decompressed;

    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      decompressed = const archive.GZipDecoder().decodeBytes(bytes);
    } else if (bytes.length >= 3 &&
        bytes[0] == 0x42 &&
        bytes[1] == 0x5a &&
        bytes[2] == 0x68) {
      decompressed = archive.BZip2Decoder().decodeBytes(bytes);
    } else if (bytes.length >= 6 &&
        bytes[0] == 0xfd &&
        bytes[1] == 0x37 &&
        bytes[2] == 0x7a &&
        bytes[3] == 0x58 &&
        bytes[4] == 0x5a &&
        bytes[5] == 0x00) {
      decompressed = archive.XZDecoder().decodeBytes(bytes);
    } else {
      decompressed = bytes;
    }

    final tarArchive = archive.TarDecoder().decodeBytes(decompressed);
    final destDir = Directory(destinationPath);
    if (!destDir.existsSync()) {
      destDir.createSync(recursive: true);
    }
    final destRoot = Uri.file(
      destDir.absolute.path,
    ).normalizePath().toFilePath();
    for (final file in tarArchive.files) {
      if (!file.isFile) continue;
      // Reject entries whose path would escape the destination directory.
      final outPath = Uri.file(
        '$destRoot/${file.name}',
      ).normalizePath().toFilePath();
      if (outPath != destRoot && !outPath.startsWith('$destRoot/')) {
        throw ObtainiumError(tr('invalidArchive'));
      }
      final outFile = File(outPath);
      outFile.createSync(recursive: true);
      outFile.writeAsBytesSync(file.content);
    }
  }

  Future<bool> installApkDir(
    DownloadedDir dir,
    BuildContext? firstTimeWithContext, {
    bool needsBGWorkaround = false,
    Map<String, dynamic> installOptions = const {},
  }) async {
    // Try installing all APKs; succeed if at least one installed.
    var somethingInstalled = false;
    final installer = getInstaller();
    try {
      final MultiAppMultiError errors = MultiAppMultiError();
      List<File> apkFiles = [];
      for (var file
          in dir.extracted
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()) {
        if (file.path.toLowerCase().endsWith('.apk')) {
          apkFiles.add(file);
        } else if (file.path.toLowerCase().endsWith('.obb')) {
          await moveObbFile(file, dir.appId);
        }
      }

      if (installer.wantsContainerHandoff) {
        if (dir.type == DownloadedDirType.splitApks) {
          // The external installer opens one file per intent, so it can't run
          // an install session for base + split APKs from separate downloads.
          throw ObtainiumError(tr('splitApksUnsupportedByExternalInstaller'));
        }
        // Hand off the original bundle file (XAPK/ZIP/tarball) to the
        // third-party installer rather than the extracted split APKs.
        try {
          final result = await installer.installApk(
            [dir.file.path],
            appId: dir.appId,
            installOptions: installOptions,
          );
          if (result.isError) {
            throw InstallError(result.errorCode ?? -1);
          }
          if (result.isSuccess) {
            somethingInstalled = true;
            apps[dir.appId]!.app = apps[dir.appId]!.app.copyWith(
              installedVersion: apps[dir.appId]!.app.latestVersion,
            );
            await saveApps([apps[dir.appId]!.app]);
          }
          unawaited(dir.file.delete());
        } catch (e) {
          AppLogger.info(
            'Could not install container from ${dir.type}: ${e.toString()}',
          );
          errors.add(dir.appId, e, appName: apps[dir.appId]?.name);
        }
        if (errors.idsByErrorString.isNotEmpty) {
          throw errors;
        }
        return somethingInstalled;
      }

      apkFiles = _preferMatchingApk(apkFiles, dir.appId).cast<File>().toList();
      if (dir.type == DownloadedDirType.splitApks) {
        apkFiles = _moveSplitBaseFirst(apkFiles);
      }

      if (apkFiles.isEmpty) {
        throw NoAPKError();
      }

      try {
        final wasInstalled = await installApk(
          DownloadedApk(dir.appId, apkFiles[0]),
          // ignore: use_build_context_synchronously
          firstTimeWithContext,
          needsBGWorkaround: needsBGWorkaround,
          installOptions: installOptions,
          additionalAPKs: apkFiles
              .sublist(1)
              .map((a) => DownloadedApk(dir.appId, a))
              .toList(),
        );
        somethingInstalled = somethingInstalled || wasInstalled;
        unawaited(dir.file.delete());
      } catch (e) {
        AppLogger.info(
          'Could not install APKs for ${dir.appId} from ${dir.type}: ${e.toString()}',
        );
        errors.add(dir.appId, e, appName: apps[dir.appId]?.name);
      }
      if (errors.idsByErrorString.isNotEmpty) {
        throw errors;
      }
    } finally {
      unawaited(dir.extracted.delete(recursive: true));
    }
    return somethingInstalled;
  }

  /// Installs a downloaded APK file, with optional auxiliary split APKs and Shizuku support.
  Future<bool> installApk(
    DownloadedApk file,
    BuildContext? firstTimeWithContext, {
    bool needsBGWorkaround = false,
    Map<String, dynamic> installOptions = const {},
    List<DownloadedApk> additionalAPKs = const [],
  }) async {
    if (firstTimeWithContext != null) {
      await _shareWithVerifiedApps(file, firstTimeWithContext);
    }
    final newInfo = await packageManager.getPackageArchiveInfo(
      archiveFilePath: file.file.path,
    );
    if (newInfo == null) {
      try {
        deleteFile(file.file);
        for (var a in additionalAPKs) {
          deleteFile(a.file);
        }
      } catch (e) {
        AppLogger.info(
          'Failed to delete bad download files for ${file.appId}: ${e.toString()}',
        );
      }
      throw ObtainiumError(tr('badDownload'))..url = apps[file.appId]?.app.url;
    }
    final PackageInfo? appInfo = await getInstalledInfo(
      apps[file.appId]!.app.id,
    );
    AppLogger.info(
      'Installing "${newInfo.packageName}" version "${newInfo.versionName}" versionCode "${newInfo.versionCode}"${appInfo != null ? ' (from existing version "${appInfo.versionName}" versionCode "${appInfo.versionCode}")' : ''}',
    );
    final newVersionCode = newInfo.versionCode;
    final oldVersionCode = appInfo?.versionCode;
    if (appInfo != null &&
        newVersionCode != null &&
        oldVersionCode != null &&
        newVersionCode < oldVersionCode &&
        !(await canDowngradeApps())) {
      if (settingsProvider.showAppDowngradeError) {
        try {
          file.file.deleteSync();
        } catch (e) {
          AppLogger.error(e, message: 'Failed to delete downgraded APK file');
        }
        throw DowngradeError(oldVersionCode, newVersionCode);
      }
    }
    if (needsBGWorkaround) {
      // Background process workaround (#896): the `await installApk` below
      // will never return in BG, so pre-update the installed version.
      // TODO(#896): Remove this when platform install API supports BG completion.
      apps[file.appId]!.app = apps[file.appId]!.app.copyWith(
        installedVersion: apps[file.appId]!.app.latestVersion,
      );
      await saveApps([
        apps[file.appId]!.app,
      ], attemptToCorrectInstallStatus: false);
    }
    final allAPKs = [file.file.path];
    allAPKs.addAll(additionalAPKs.map((a) => a.file.path));
    final installer = getInstaller();
    final InstallResult result =
        needsBGWorkaround || installer.modeKey != 'stock'
        ? await installer.installApk(
            allAPKs,
            appId: file.appId,
            installOptions: installOptions,
          )
        : await _installWithPollConfirmation(
            installer,
            allAPKs,
            file.appId,
            installOptions,
          );
    bool installed = false;
    if (result.isError) {
      try {
        deleteFile(file.file);
      } catch (e) {
        AppLogger.info(
          'Failed to delete APK after failed install: ${e.toString()}',
        );
      }
      throw InstallError(result.errorCode!);
    } else if (result.isSuccess) {
      installed = true;
      apps[file.appId]!.app = apps[file.appId]!.app.copyWith(
        installedVersion: apps[file.appId]!.app.latestVersion,
      );
      unawaited(file.file.delete(recursive: true));
      if (!isBg) settingsProvider.heavyImpact();
    }
    // Cancelled or already-installed/pending: keep the file so a retry can
    // reuse it without re-downloading (matches main).
    await saveApps([apps[file.appId]!.app]);
    return installed;
  }

  /// Installs via the stock installer while racing the intent-based result
  /// against polling for the package to land; the first conclusive outcome
  /// wins, and the overall wait is capped, so a lost install result can never
  /// stall the install chain (#3255).
  Future<InstallResult> _installWithPollConfirmation(
    Installer installer,
    List<String> apkPaths,
    String appId,
    Map<String, dynamic> installOptions,
  ) async {
    final baseline = await captureInstallBaseline(appId);
    final intentCompleter = Completer<InstallResult>();
    final pollCompleter = Completer<InstallResult>();
    unawaited(
      installer
          .installApk(apkPaths, appId: appId, installOptions: installOptions)
          .then(
            (result) {
              if (!intentCompleter.isCompleted) {
                intentCompleter.complete(result);
              }
            },
            onError: (Object e, StackTrace st) {
              if (!intentCompleter.isCompleted) {
                intentCompleter.completeError(e, st);
              }
            },
          ),
    );
    unawaited(
      waitForPackageInstall(
        appId,
        baseline,
        attempts: _installConfirmPollAttempts,
        interval: const Duration(seconds: 1),
      ).then((confirmed) {
        if (confirmed) {
          if (!pollCompleter.isCompleted) {
            pollCompleter.complete(InstallResult.success());
          }
        } else if (isForeground) {
          // Nothing landed while the app was in the foreground — the install
          // result was lost (or the session stalled); fail rather than wait.
          if (!pollCompleter.isCompleted) {
            pollCompleter.completeError(
              ObtainiumError(tr('installConfirmationError')),
            );
          }
        }
        // Backgrounded and unconfirmed: the user may still be at a system
        // prompt, so keep awaiting the intent result until the overall cap.
      }),
    );
    try {
      return await Future.any([
        intentCompleter.future,
        pollCompleter.future,
      ]).timeout(_installConfirmTimeout);
    } on TimeoutException {
      AppLogger.warn(
        'Install confirmation timed out for $appId after $_installConfirmTimeout.',
      );
      throw ObtainiumError(tr('installConfirmationError'))
        ..url = apps[appId]?.app.url;
    }
  }

  Future<void> _shareWithVerifiedApps(
    DownloadedApk file,
    BuildContext context,
  ) async {
    if (!settingsProvider.beforeNewInstallsShareToAppVerifier) return;
    var anyInstalled = false;
    for (final id in _verifiedAppsPackageIds) {
      if (await getInstalledInfo(id) != null) {
        anyInstalled = true;
        break;
      }
    }
    if (!anyInstalled) return;
    final XFile f = XFile(
      file.file.path,
      mimeType: 'application/vnd.android.package-archive',
    );
    unawaited(
      Fluttertoast.showToast(
        msg: tr('appVerifierInstructionToast'),
        toastLength: Toast.LENGTH_LONG,
      ),
    );
    await SharePlus.instance.share(ShareParams(files: [f]));
  }

  Future<String> getStorageRootPath() async {
    try {
      return '/${(await getAppStorageDir()).uri.pathSegments.sublist(0, 3).join('/')}';
    } catch (_) {
      return '/storage/emulated/0';
    }
  }

  Future<void> moveObbFile(File file, String appId) async {
    if (!file.path.toLowerCase().endsWith('.obb')) return;

    final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    if (sdkInt >= _androidApiLevelR) {
      try {
        final obbDir = await saf.openDocumentTree(
          initialUri: Uri.parse('${await getStorageRootPath()}/Android/obb'),
        );
        if (obbDir == null) return;
        final appSpecificObbDoc = await saf.child(obbDir, appId);
        if (appSpecificObbDoc == null) return;
        final obbFileName = file.path.split('/').last;
        final obbDestPath =
            '${await getStorageRootPath()}/Android/obb/$appId/$obbFileName';
        await Directory(
          '${await getStorageRootPath()}/Android/obb/$appId',
        ).create(recursive: true);
        await file.copy(obbDestPath);
        AppLogger.info(
          'Copied OBB file $obbFileName for $appId via direct file access',
        );
      } catch (e) {
        AppLogger.info('Failed to place OBB file for $appId: ${e.toString()}');
      }
    } else {
      await Permission.storage.request();
      final String obbDirPath =
          '${await getStorageRootPath()}/Android/obb/$appId';
      Directory(obbDirPath).createSync(recursive: true);
      final String obbFileName = file.path.split('/').last;
      await file.copy('$obbDirPath/$obbFileName');
      AppLogger.info(
        'Copied OBB file $obbFileName for $appId via direct file access',
      );
    }
  }

  Future<void> uninstallApp(String appId) async {
    final intent = AndroidIntent(
      action: 'android.intent.action.DELETE',
      data: 'package:$appId',
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      package: 'vnd.android.package-archive',
    );
    await intent.launch();
  }

  Future<MapEntry<String, String>?> confirmAppFileUrl(
    App app,
    BuildContext? context,
    bool pickAnyAsset, {
    bool evenIfSingleChoice = false,
  }) async {
    var urlsToSelectFrom = app.apkUrls;
    if (pickAnyAsset) {
      urlsToSelectFrom = [...urlsToSelectFrom, ...app.otherAssetUrls];
    }
    if (urlsToSelectFrom.isEmpty) {
      throw NoAPKError();
    }
    // If the App has more than one APK, the user should pick one (if context provided)
    final int preferredIndex =
        app.preferredApkIndex >= 0 &&
            app.preferredApkIndex < urlsToSelectFrom.length
        ? app.preferredApkIndex
        : 0;
    MapEntry<String, String>? appFileUrl = urlsToSelectFrom[preferredIndex];
    // When picking any asset, use the APK filter regex to pre-select the best matching
    // asset by default, without hiding other assets from the user.
    if (pickAnyAsset &&
        app.settings.getStringOrNull('apkFilterRegEx')?.isNotEmpty == true) {
      final matching = filterApks(
        urlsToSelectFrom,
        app.settings.getStringOrNull('apkFilterRegEx'),
        app.settings.getBool('invertAPKFilter'),
      );
      if (matching.isNotEmpty) {
        appFileUrl = matching.first;
      }
    }
    final List<String> archs =
        (await DeviceInfoPlugin().androidInfo).supportedAbis;

    if ((urlsToSelectFrom.length > 1 || evenIfSingleChoice) &&
        context != null &&
        context.mounted) {
      appFileUrl = await showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AppFilePicker(
            app: app,
            initVal: appFileUrl,
            archs: archs,
            pickAnyAsset: pickAnyAsset,
          );
        },
      );
    }
    String? getHost(String url) {
      if (url == 'placeholder') {
        return null;
      }
      return HttpService.extractRootHost(Uri.parse(url).host);
    }

    // If the picked APK comes from an origin different from the source, get user confirmation (if context provided)
    if (appFileUrl != null &&
        ![
          getHost(app.url),
          'placeholder',
        ].contains(getHost(appFileUrl.value)) &&
        context != null &&
        context.mounted) {
      final trustedHosts = SourceProvider()
          .getSource(app.url, overrideSource: app.overrideSource)
          .trustedApkHosts;
      if (!trustedHosts.contains(getHost(appFileUrl.value)) &&
          !(settingsProvider.hideAPKOriginWarning) &&
          await showDialog(
                context: context,
                builder: (BuildContext ctx) {
                  return APKOriginWarningDialog(
                    sourceUrl: app.url,
                    apkUrl: appFileUrl!.value,
                  );
                },
              ) !=
              true) {
        appFileUrl = null;
      }
    }
    return appFileUrl;
  }

  // Filters app IDs into those that can be installed and those that are track-only,
  // refreshing stale data and confirming file URLs before returning.
  Future<(List<String>, List<String>)> _resolveAppsToInstall(
    List<String> appIds,
    BuildContext? context,
    MultiAppMultiError errors,
  ) async {
    final List<String> appsToInstall = [];
    final List<String> trackOnlyAppsToUpdate = [];
    for (var id in appIds) {
      if (apps[id] == null) {
        throw ObtainiumError(tr('appNotFound'));
      }
      MapEntry<String, String>? apkUrl;
      final trackOnly = apps[id]!.app.settings.getBool('trackOnly');
      final refreshBeforeDownload = apps[id]!.needsRefreshBeforeDownload;
      if (refreshBeforeDownload) {
        try {
          await checkUpdate(apps[id]!.app.id);
        } catch (e) {
          // A single app failing to refresh must not abort the whole batch;
          // record it and let the remaining apps proceed.
          errors.add(id, e, appName: apps[id]?.name);
          continue;
        }
      }
      if (!trackOnly) {
        // ignore: use_build_context_synchronously
        apkUrl = await confirmAppFileUrl(apps[id]!.app, context, false);
      }
      if (apkUrl != null) {
        final url = apkUrl.value;
        final int urlInd = apps[id]!.app.apkUrls.indexWhere(
          (e) => e.value == url,
        );
        if (urlInd >= 0 && urlInd != apps[id]!.app.preferredApkIndex) {
          apps[id]!.app = apps[id]!.app.copyWith(preferredApkIndex: urlInd);
          await saveApps([apps[id]!.app]);
        }
        if (context != null ||
            await canInstallSilentlyInBackground(apps[id]!.app)) {
          appsToInstall.add(id);
        }
      }
      if (trackOnly) {
        trackOnlyAppsToUpdate.add(id);
      }
    }
    return (appsToInstall, trackOnlyAppsToUpdate);
  }

  /// Installs a previously downloaded app, recording any failure in [errors]
  /// instead of aborting the remaining installs.
  Future<void> _installQueuedApp(
    _InstallResult res,
    List<String> installedIds,
    MultiAppMultiError errors,
    BuildContext? context,
    NotificationsProvider? notificationsProvider,
  ) async {
    try {
      await _installDownloadedApp(
        res.id,
        res.willBeSilent,
        res.downloadedFile,
        res.downloadedDir,
        installedIds,
        errors,
        context,
        notificationsProvider,
      );
    } catch (e) {
      errors.add(res.id, e, appName: apps[res.id]?.name);
    }
  }

  bool _isObtainiumId(String id) =>
      id == obtainiumId ||
      id == obtainiumTempId ||
      id == '$obtainiumId.fdroid' ||
      id == '$obtainiumId.debug';

  /// Downloads APKs for [appIds] and installs them, silently when possible.
  /// Without a BuildContext, apps requiring user interaction are skipped
  /// and a notification is sent instead. Returns IDs of successfully downloaded apps.
  Future<List<String>> downloadAndInstallLatestApps(
    List<String> appIds,
    BuildContext? context, {
    NotificationsProvider? notificationsProvider,
    bool forceParallelDownloads = false,
    bool useExisting = true,
  }) async {
    notificationsProvider =
        notificationsProvider ?? context?.read<NotificationsProvider>();

    final MultiAppMultiError errors = MultiAppMultiError();
    var (appsToInstall, trackOnlyAppsToUpdate) = await _resolveAppsToInstall(
      appIds,
      context,
      errors,
    );

    // Mark all specified track-only apps as latest
    await saveApps(
      trackOnlyAppsToUpdate.map((e) {
        var a = apps[e]!.app;
        a = a.copyWith(installedVersion: a.latestVersion);
        return a;
      }).toList(),
    );

    final List<String> installedIds = [];

    // Move Obtainium to the end of the line (let all other apps update first)
    appsToInstall = moveStrToEnd(
      appsToInstall,
      obtainiumId,
      strB: obtainiumTempId,
    );
    appsToInstall = moveStrToEnd(appsToInstall, '$obtainiumId.fdroid');
    appsToInstall = moveStrToEnd(appsToInstall, '$obtainiumId.debug');

    final List<_InstallResult> obtainiumResults = [];
    Future<void> installChain = Future.value();

    Future<void> handleAppDownloadAndQueueInstall(String id) async {
      final res = await _downloadAppForInstall(
        id,
        // ignore: use_build_context_synchronously
        context,
        notificationsProvider,
        useExisting,
        errors,
      );
      if (!errors.appIdNames.containsKey(res.id)) {
        if (_isObtainiumId(res.id)) {
          obtainiumResults.add(res);
        } else {
          installChain = installChain.then(
            (_) => _installQueuedApp(
              res,
              installedIds,
              errors,
              // ignore: use_build_context_synchronously
              context,
              notificationsProvider,
            ),
          );
        }
      }
    }

    try {
      // Background tasks (forceParallelDownloads) run serially like main,
      // otherwise the parallelDownloads setting controls concurrency.
      if (forceParallelDownloads || !settingsProvider.parallelDownloads) {
        for (var id in appsToInstall) {
          await handleAppDownloadAndQueueInstall(id);
        }
      } else {
        await Future.wait(
          appsToInstall.map((id) => handleAppDownloadAndQueueInstall(id)),
        );
      }
      await installChain;

      for (var res in obtainiumResults) {
        if (!errors.appIdNames.containsKey(res.id)) {
          await _installQueuedApp(
            res,
            installedIds,
            errors,
            // ignore: use_build_context_synchronously
            context,
            notificationsProvider,
          );
        }
      }
    } finally {
      // Clear any remaining progress in case the flow was interrupted
      // (e.g. unhandled error in a download, app backgrounded/killed, etc.)
      for (var id in appsToInstall) {
        apps[id]?.downloadProgress = null;
      }
      notify();
    }

    if (errors.idsByErrorString.isNotEmpty) {
      throw errors;
    }

    return installedIds;
  }

  Future<List<String>> downloadAppAssets(
    List<String> appIds,
    BuildContext context, {
    bool forceParallelDownloads = false,
  }) async {
    final NotificationsProvider notificationsProvider = context
        .read<NotificationsProvider>();
    final List<MapEntry<MapEntry<String, String>, App>> filesToDownload = [];
    for (var id in appIds) {
      if (apps[id] == null) {
        throw ObtainiumError(tr('appNotFound'));
      }
      MapEntry<String, String>? fileUrl;
      final refreshBeforeDownload = apps[id]!.needsRefreshBeforeDownload;
      if (refreshBeforeDownload) {
        await checkUpdate(apps[id]!.app.id);
      }
      if (apps[id]!.app.apkUrls.isNotEmpty ||
          apps[id]!.app.otherAssetUrls.isNotEmpty) {
        final MapEntry<String, String>? tempFileUrl = await confirmAppFileUrl(
          apps[id]!.app,
          // ignore: use_build_context_synchronously
          context,
          true,
          evenIfSingleChoice: true,
        );
        if (tempFileUrl != null) {
          final s = SourceProvider().getSource(
            apps[id]!.app.url,
            overrideSource: apps[id]!.app.overrideSource,
          );
          final additionalSettingsPlusSourceConfig = await s
              .buildMergedSettings(
                apps[id]!.app.additionalSettings,
                settingsProvider,
              );
          fileUrl = MapEntry(
            tempFileUrl.key,
            await s.assetUrlPrefetchModifier(
              await s.generalReqPrefetchModifier(
                tempFileUrl.value,
                additionalSettingsPlusSourceConfig,
              ),
              apps[id]!.app.url,
              additionalSettingsPlusSourceConfig,
            ),
          );
        }
      }
      if (fileUrl != null) {
        filesToDownload.add(MapEntry(fileUrl, apps[id]!.app));
      }
    }

    // Prepare to download+install Apps
    final MultiAppMultiError errors = MultiAppMultiError();
    final List<String> downloadedIds = [];

    if (forceParallelDownloads || !settingsProvider.parallelDownloads) {
      for (var urlWithApp in filesToDownload) {
        await _downloadAssetFile(
          urlWithApp.key,
          urlWithApp.value,
          errors,
          downloadedIds,
          notificationsProvider,
          settingsProvider.enableCertificatePinning,
        );
      }
    } else {
      await Future.wait(
        filesToDownload.map(
          (urlWithApp) => _downloadAssetFile(
            urlWithApp.key,
            urlWithApp.value,
            errors,
            downloadedIds,
            notificationsProvider,
            settingsProvider.enableCertificatePinning,
          ),
        ),
      );
    }
    if (errors.idsByErrorString.isNotEmpty) {
      throw errors;
    }
    return downloadedIds;
  }

  List<FileSystemEntity> _preferMatchingApk(
    List<FileSystemEntity> apks,
    String appId,
  ) {
    FileSystemEntity? temp;
    apks.removeWhere((element) {
      final bool res = element.uri.pathSegments.last.startsWith(appId);
      if (res) {
        temp = element;
      }
      return res;
    });
    if (temp != null) {
      apks = [temp!, ...apks];
    }
    return apks;
  }

  /// Moves a `base.apk` to the front of a split APK set, so package info and
  /// the install session start from the base.
  List<T> _moveSplitBaseFirst<T extends FileSystemEntity>(List<T> apks) {
    final int baseIndex = apks.indexWhere(
      (e) => e.uri.pathSegments.last.toLowerCase() == 'base.apk',
    );
    if (baseIndex > 0) {
      apks.insert(0, apks.removeAt(baseIndex));
    }
    return apks;
  }

  /// Applies the per-app expected signing certificate hashes and, unless
  /// disabled, the installed app's certificate to [apkHashes]. Throws
  /// [SigningCertMismatchError] when the install must not proceed.
  ///
  /// A user-provided hash list is a hard block (no override); a mismatch
  /// against the installed app warns in the foreground (with an install-anyway
  /// option) and is treated as blocked when there is no context (background).
  Future<void> _verifyDownloadedApkSignatures(
    AppInMemory appEntry,
    Set<String> apkHashes,
    BuildContext? context,
  ) async {
    final userHashes = parseAllowedSigningCertHashes(
      appEntry.app.settings.getStringOrNull('allowedSigningCertHashes'),
    );
    final installedHashes = appEntry.certificateHashes.toSet();
    final name = appEntry.name;

    Future<void> showMismatch({
      required Set<String> expected,
      required bool hardBlock,
    }) async {
      if (context == null || !context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => SigningCertMismatchDialog(
          appName: name,
          expectedHashes: expected.toList(),
          actualHashes: apkHashes.toList(),
          hardBlock: hardBlock,
        ),
      );
    }

    // Signing info unavailable (pre-API 28 or unreadable archive). A
    // user-provided hash cannot be checked, so refuse to install unverified.
    if (apkHashes.isEmpty) {
      if (userHashes.isNotEmpty) {
        AppLogger.warn(
          'Signing certificate unreadable for ${appEntry.app.id}; '
          'blocking because expected hashes are configured',
        );
        await showMismatch(expected: userHashes, hardBlock: true);
        throw SigningCertMismatchError(
          hardBlock: true,
          expected: userHashes,
          actual: apkHashes,
        );
      }
      return;
    }

    if (userHashes.isNotEmpty && !apkHashes.every(userHashes.contains)) {
      await showMismatch(expected: userHashes, hardBlock: true);
      throw SigningCertMismatchError(
        hardBlock: true,
        expected: userHashes,
        actual: apkHashes,
      );
    }

    if (!settingsProvider.verifySigningCertHashes ||
        installedHashes.isEmpty ||
        apkHashes.every(installedHashes.contains)) {
      return;
    }

    var proceed = false;
    if (context != null && context.mounted) {
      proceed =
          await showDialog<bool>(
            context: context,
            builder: (_) => SigningCertMismatchDialog(
              appName: name,
              expectedHashes: installedHashes.toList(),
              actualHashes: apkHashes.toList(),
              hardBlock: false,
            ),
          ) ==
          true;
    }
    if (!proceed) {
      throw SigningCertMismatchError(
        hardBlock: false,
        expected: installedHashes,
        actual: apkHashes,
      );
    }
  }

  /// Fires a background install and confirms it by polling the installed
  /// package. The stock installer's install await never returns while the app
  /// is in the background, so the call is intentionally not awaited and
  /// completion is detected via [waitForPackageInstall].
  Future<bool> _awaitBackgroundInstall(
    String id,
    AppInMemory appEntry,
    Future<bool> Function() install, {
    required String failureLogPrefix,
  }) async {
    final baseline = await captureInstallBaseline(id);
    unawaited(
      install().catchError((Object e) {
        // The await is intentionally not observed (the stock installer never
        // returns in the background), but a thrown error must not escape as an
        // unhandled async error.
        AppLogger.warn('$failureLogPrefix: $e');
        return false;
      }),
    );
    final sayInstalled = await waitForPackageInstall(
      id,
      baseline,
      attempts: _bgInstallConfirmAttempts,
    );
    if (sayInstalled) {
      AppLogger.info('BG install confirmed for $id via polling');
    } else {
      AppLogger.warn(
        'BG install poll timed out for $id after $_bgInstallConfirmAttempts attempts',
      );
      final latestInfo = await getInstalledInfo(id);
      AppLogger.warn(
        'BG install final state for $id: wasInstalled=${baseline.wasInstalled}, '
        'baselineUpdateTime=${baseline.updateTime}, '
        'currentUpdateTime=${latestInfo?.lastUpdateTime}, '
        'latestVersion=${appEntry.app.latestVersion}',
      );
    }
    return sayInstalled;
  }

  Future<void> _installDownloadedApp(
    String id,
    bool willBeSilent,
    DownloadedApk? downloadedFile,
    DownloadedDir? downloadedDir,
    List<String> installedIds,
    MultiAppMultiError errors,
    BuildContext? context,
    NotificationsProvider? notificationsProvider,
  ) async {
    final appEntry = apps[id];
    if (appEntry == null) return;
    // Nothing to install (e.g. the download was cancelled): skip silently.
    if (downloadedFile == null && downloadedDir == null) return;
    // Verify the signing certificate(s) before any install attempt so a
    // mismatched or unverifiable APK never reaches the installer (#2922).
    final apkHashes = downloadedFile != null
        ? await apkSigningCertHashes(downloadedFile.file.path)
        : await apkFilesSigningCertHashes(
            downloadedDir!.extracted
                .listSync(recursive: true, followLinks: false)
                .whereType<File>()
                .where((f) => f.path.toLowerCase().endsWith('.apk'))
                .map((f) => f.path),
          );
    try {
      final verificationContext = context != null && context.mounted
          ? context
          : null;
      await _verifyDownloadedApkSignatures(
        appEntry,
        apkHashes,
        // ignore: use_build_context_synchronously
        verificationContext,
      );
    } on SigningCertMismatchError {
      // A blocked APK is useless; remove it so it isn't retried or reused.
      try {
        if (downloadedFile != null) {
          downloadedFile.file.deleteSync();
        } else {
          downloadedDir!.extracted.deleteSync(recursive: true);
          downloadedDir.file.deleteSync();
        }
      } catch (e) {
        AppLogger.warn('Failed to delete blocked APK for $id: ${e.toString()}');
      }
      rethrow;
    }
    // Installation has actually begun: use -1 (installing) so the UI shows an
    // indeterminate "Installing" indicator rather than a frozen percentage.
    appEntry.downloadProgress = _installingProgressSentinel;
    notify();
    try {
      bool sayInstalled = true;
      final contextIfNewInstall = appEntry.installedInfo == null
          ? context
          : null;
      final String installerModeKey = getInstaller().modeKey;
      // Only the stock session-based installer needs the background-completion
      // workaround (its install await never returns in the background).
      final bool needBGWorkaround =
          willBeSilent && context == null && installerModeKey == 'stock';
      final bool shizukuPretendToBeGooglePlay =
          settingsProvider.shizukuPretendToBeGooglePlay ||
          appEntry.app.settings.getBool('shizukuPretendToBeGooglePlay');
      if (downloadedFile != null) {
        if (needBGWorkaround) {
          sayInstalled = await _awaitBackgroundInstall(
            id,
            appEntry,
            () => installApk(
              downloadedFile,
              null,
              needsBGWorkaround: true,
              installOptions: {
                'shizukuPretendToBeGooglePlay': shizukuPretendToBeGooglePlay,
              },
            ),
            failureLogPrefix: 'Background install threw for $id',
          );
        } else {
          final installContext =
              contextIfNewInstall != null && contextIfNewInstall.mounted
              ? contextIfNewInstall
              : null;
          sayInstalled = await installApk(
            downloadedFile,
            // ignore: use_build_context_synchronously
            installContext,
            installOptions: {
              'shizukuPretendToBeGooglePlay': shizukuPretendToBeGooglePlay,
            },
          );
        }
      } else {
        if (needBGWorkaround) {
          sayInstalled = await _awaitBackgroundInstall(
            id,
            appEntry,
            () => installApkDir(downloadedDir!, null, needsBGWorkaround: true),
            failureLogPrefix: 'Background install directory threw for $id',
          );
        } else {
          final installContext =
              contextIfNewInstall != null && contextIfNewInstall.mounted
              ? contextIfNewInstall
              : null;
          sayInstalled = await installApkDir(
            downloadedDir!,
            // ignore: use_build_context_synchronously
            installContext,
            installOptions: {
              'shizukuPretendToBeGooglePlay': shizukuPretendToBeGooglePlay,
            },
          );
        }
      }
      if (willBeSilent && context == null) {
        if (installerModeKey == 'stock' && !sayInstalled) {
          // Stock background install couldn't be confirmed within the polling
          // window, so report it as a best-effort attempt rather than a result.
          unawaited(
            notificationsProvider?.notify(
              SilentUpdateAttemptNotification([appEntry.app], id: id.hashCode),
            ),
          );
        } else {
          unawaited(
            notificationsProvider?.notify(
              SilentUpdateNotification(
                [appEntry.app],
                sayInstalled,
                id: id.hashCode,
              ),
            ),
          );
        }
      }
      if (sayInstalled) {
        installedIds.add(id);
        // Dismiss the update notification since the app was successfully installed
        unawaited(notificationsProvider?.cancel(updateNotificationId));
      }
    } finally {
      appEntry.downloadProgress = null;
      notify();
    }
  }

  Future<_InstallResult> _downloadAppForInstall(
    String id,
    BuildContext? context,
    NotificationsProvider? notificationsProvider,
    bool useExisting,
    MultiAppMultiError errors,
  ) async {
    bool willBeSilent = false;
    DownloadedApk? downloadedFile;
    DownloadedDir? downloadedDir;
    try {
      final downloadedArtifact = await downloadApp(
        apps[id]!.app,
        context,
        notificationsProvider: notificationsProvider,
        useExisting: useExisting,
      );
      if (downloadedArtifact is DownloadedApk) {
        downloadedFile = downloadedArtifact;
      } else if (downloadedArtifact is DownloadedDir) {
        downloadedDir = downloadedArtifact;
      } else {
        throw ObtainiumError(tr('downloadFailed'))..url = apps[id]?.app.url;
      }
      id = downloadedFile?.appId ?? downloadedDir?.appId ?? id;
      // Bridge download-to-install gap so the Dismissible stays disabled.
      // Use 100 (download complete) rather than -1 (installing) so the UI
      // doesn't report "Installing" before installation actually begins.
      apps[id]?.downloadProgress = _downloadCompleteProgress.toDouble();
      notify();
      if (!isBg) settingsProvider.lightImpact();
      willBeSilent = await canInstallSilently(apps[id]!.app);
      final installer = getInstaller();
      await installer.ensurePermission();
      // Only the stock installer surfaces a system install prompt that pulls the
      // user away; wait for them to return before proceeding.
      if (!willBeSilent &&
          context != null &&
          context.mounted &&
          installer.modeKey == 'stock') {
        await waitForUserToReturnToForeground(context);
      }
    } catch (e) {
      // A user-cancelled download is not an error; skip it silently.
      if (e is! CancellationException) {
        errors.add(id, e, appName: apps[id]?.name);
      }
      downloadedFile = null;
      downloadedDir = null;
      if (apps[id] != null) {
        apps[id]!.downloadProgress = null;
        notify();
      }
    }
    return _InstallResult(
      id: id,
      willBeSilent: willBeSilent,
      downloadedFile: downloadedFile,
      downloadedDir: downloadedDir,
    );
  }

  Future<void> _downloadAssetFile(
    MapEntry<String, String> fileUrl,
    App app,
    MultiAppMultiError errors,
    List<String> downloadedIds,
    NotificationsProvider notificationsProvider,
    bool enableCertificatePinning,
  ) async {
    // A single entry can hold a split APK set (base first, then splits), so
    // each URL is downloaded as its own file.
    final List<String> urls = splitMultiApkUrl(fileUrl.value);
    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      final String fileName = i == 0
          ? fileUrl.key
          : (Uri.tryParse(url)?.pathSegments.lastOrNull ??
                '${fileUrl.key}-split$i');
      app.additionalSettings['url'] = url;
      app.additionalSettings['enableCertificatePinning'] =
          enableCertificatePinning;
      final notifId = DownloadNotification(
        fileName,
        0,
        idKey: '${app.id}|$url',
      ).id;
      try {
        final String downloadPath = '${await getStorageRootPath()}/Download';
        await downloadFileWithRetry(
          fileName,
          true,
          (double? progress, [int? received, int? total]) {
            unawaited(
              notificationsProvider.notify(
                DownloadNotification(
                  fileName,
                  progress?.ceil() ?? 0,
                  idKey: '${app.id}|$url',
                  receivedBytes: received,
                  totalBytes: total,
                ),
              ),
            );
          },
          downloadPath,
          app.additionalSettings,
          headers: await SourceProvider()
              .getSource(app.url, overrideSource: app.overrideSource)
              .getRequestHeaders(
                app.additionalSettings,
                url,
                forAPKDownload: AppSource.isApkOrContainerFile(fileName),
              ),
          useExisting: false,
        );
        unawaited(
          notificationsProvider.notify(
            DownloadedNotification(fileName, url, appId: app.id),
          ),
        );
        downloadedIds.add(fileName);
      } catch (e) {
        if (e is! CancellationException) {
          errors.add(fileName, e);
        }
      } finally {
        unawaited(notificationsProvider.cancel(notifId));
      }
    }
  }
}
