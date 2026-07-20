import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:android_package_manager/android_package_manager.dart';
import 'package:archive/archive.dart' as archive;
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:flutter_fgbg/flutter_fgbg.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/app_sources/fdroidrepo.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/app_sources/izzyondroid.dart';
import 'package:obtainium/components/app_detail_widgets.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/installers/installer.dart';
import 'package:obtainium/installers/shizuku_installer.dart';
import 'package:obtainium/installers/stock_installer.dart';
import 'package:obtainium/installers/external_installer.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/providers/virustotal_provider.dart';
import 'package:obtainium/theme/app_dialog_theme.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_storage/shared_storage.dart' as saf;

// NOTE: This provider extension is intentionally UX-coupled. Interactive calls
// use the app-level navigator for dialogs and receive an explicit interaction
// flag internally, so an async operation never retains a page BuildContext.

// Named constants for magic numbers and hardcoded values
const int _androidApiLevelR = 30;
// downloadProgress sentinels for the busy states the UI renders instead of a
// percentage: -1 "Installing", -2 "Scanning with VirusTotal", -3 "Flagged"
// (AppPage's download control reads all three; the list tile reads -1/-2).
const double _installingProgressSentinel = -1;
const double _scanningProgressSentinel = -2;
const double _flaggedProgressSentinel = -3;
const int _downloadCompleteProgress = 100;
const int _remainingStepsProgress = 90;

// A silent background install can't report completion synchronously — the
// platform install API's result never arrives while backgrounded (#896). The
// session still commits, so we poll (via waitForPackageInstall) for a short
// window to confirm the install actually landed.
const int _bgInstallConfirmAttempts = 20; // 20 × 500ms = 10 seconds

@visibleForTesting
bool isCleartextDownloadUrl(String url) {
  return Uri.tryParse(url)?.scheme.toLowerCase() == 'http';
}

/// Processes completed downloads one at a time, in the order they finish.
/// Entries selected by [deferUntilEnd] still download concurrently but are not
/// processed until every other entry has completed. This keeps app installs
/// serialized while avoiding a wait for the slowest download, and lets a
/// self-update remain last so it cannot terminate the rest of the batch.
@visibleForTesting
Future<void> processDownloadResultsAsReady<T>({
  required List<({String id, Future<T> result})> downloads,
  required bool Function(String id) deferUntilEnd,
  required Future<void> Function(T result) process,
}) async {
  Future<void> processChain = Future<void>.value();

  Future<void> processWhenReady(
    ({String id, Future<T> result}) download,
  ) async {
    final T result = await download.result;
    final Completer<void> processed = Completer<void>();
    processChain = processChain.then((_) async {
      try {
        await process(result);
        processed.complete();
      } catch (error, stackTrace) {
        processed.completeError(error, stackTrace);
      }
    });
    await processed.future;
  }

  final deferredDownloads = downloads.where(
    (download) => deferUntilEnd(download.id),
  );
  await Future.wait(
    downloads
        .where((download) => !deferUntilEnd(download.id))
        .map(processWhenReady),
  );
  for (final download in deferredDownloads) {
    await process(await download.result);
  }
}

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

/// MANUAL TEST HOOK - flip to `true` to force every VirusTotal scan to resolve
/// as `flagged` (fake detail/report URL, no network call), so the flagged
/// dialog/skip/notification paths can be exercised without a real API key or a
/// real flagged APK. Gated on [kDebugMode] as a safety net. Revert to `false`.
const bool debugForceFlaggedMalwareScan = false;

// ── Build-verification enforcement (reproducible builds + GitHub attestation) ──
// Pure predicates/messages that decide whether an install must be blocked
// because the source did not meet an enabled verification requirement. The
// status constants + reproducibleBuildStatusFromBool() live in source_provider.

bool reproducibleBuildVerificationApplies(AppSource source) {
  return source is FDroid || source is FDroidRepo || source is IzzyOnDroid;
}

bool reproducibleBuildEnforcementApplies(App app, AppSource source) {
  return app.additionalSettings['enforceReproducibleBuilds'] == true &&
      reproducibleBuildVerificationApplies(source);
}

String reproducibleBuildStatusForEnforcement(App app) {
  return app.latestReproducibleStatus ??
      reproducibleBuildStatusFromBool(app.latestIsReproducible);
}

bool reproducibleBuildEnforcementBlocksInstall(App app, AppSource source) {
  return reproducibleBuildEnforcementApplies(app, source) &&
      reproducibleBuildStatusForEnforcement(app) !=
          reproducibleBuildStatusVerified;
}

String reproducibleBuildEnforcedBlockedMessage() {
  return tr('reproducibleBuildEnforcedButBlocked');
}

bool githubAttestationEnforcementBlocksInstall(
  App app,
  AppSource source,
  SettingsProvider settingsProvider,
) {
  return source is GitHub &&
      source.shouldEnforceAttestations(
        app.additionalSettings,
        settingsProvider,
      ) &&
      app.latestAttestationStatus != githubAttestationStatusVerified;
}

String githubAttestationEnforcedBlockedMessage(String? attestationStatus) {
  return tr(
    attestationStatus == githubAttestationStatusUnsupported
        ? 'githubAttestationEnforcedButUnsupported'
        : 'githubAttestationEnforcedButFailed',
  );
}

bool buildVerificationEnforcementBlocksInstall(
  App app,
  AppSource source,
  SettingsProvider settingsProvider,
) {
  return reproducibleBuildEnforcementBlocksInstall(app, source) ||
      githubAttestationEnforcementBlocksInstall(app, source, settingsProvider);
}

String buildVerificationEnforcedBlockedMessage(
  App app,
  AppSource source,
  SettingsProvider settingsProvider,
) {
  if (reproducibleBuildEnforcementBlocksInstall(app, source)) {
    return reproducibleBuildEnforcedBlockedMessage();
  }
  return githubAttestationEnforcedBlockedMessage(app.latestAttestationStatus);
}

/// Sanitizes a proposed display name for a saved APK copy (SAF createFile).
String sanitizeApkSaveDisplayName(String raw) {
  final name = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  if (name.isEmpty) {
    return 'download.apk';
  }
  return name;
}

/// Same label as the release asset (e.g. GitHub attachment filename) when
/// possible, for the user-facing saved-APK copy.
String storeFacingDownloadDisplayNameForApp(App app) {
  if (app.apkUrls.isEmpty) {
    return 'download.apk';
  }
  final int preferredIdx =
      app.preferredApkIndex >= 0 && app.preferredApkIndex < app.apkUrls.length
      ? app.preferredApkIndex
      : 0;
  String key = app.apkUrls[preferredIdx].key.trim();
  if (key.isEmpty) {
    try {
      final Uri uri = Uri.parse(app.apkUrls[preferredIdx].value);
      if (uri.pathSegments.isNotEmpty) {
        key = uri.pathSegments.last;
      }
    } catch (_) {
      key = 'download.apk';
    }
  }
  if (key.isEmpty) {
    key = 'download.apk';
  }
  return sanitizeApkSaveDisplayName(key);
}

/// True when the stock Android installer is being asked to install a lower
/// version code. Shizuku and third-party installers handle their own downgrade
/// capabilities and must not be blocked by the stock-installer warning.
bool isStockInstallerDowngrade({
  required int? installedVersionCode,
  required int? newVersionCode,
  required String installerModeKey,
}) {
  return installerModeKey == 'system' &&
      installedVersionCode != null &&
      newVersionCode != null &&
      newVersionCode < installedVersionCode;
}

/// App download, install, and on-device package operations for [AppsProvider].
extension AppsProviderInstall on AppsProvider {
  /// Returns the [Installer] strategy for the current installer mode setting.
  Installer getInstaller() {
    switch (settingsProvider.installerMode) {
      case 'shizuku':
        return ShizukuInstaller(settingsProvider);
      // Third-party installer. Value matches upstream Obtainium's
      // InstallerMode.external.name.
      case 'external':
        return ExternalInstaller(settingsProvider);
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
    App app, {
    bool allowUserInteraction = false,
    NotificationsProvider? notificationsProvider,
    bool useExisting = true,
  }) async {
    final initialNotification = DownloadNotification(
      app.finalName,
      0,
      appId: app.id,
    );
    final notifId = initialNotification.id;
    var nativeDownloadServiceStarted = false;
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
      final String downloadUrl = await source.assetUrlPrefetchModifier(
        await source.generalReqPrefetchModifier(
          app.apkUrls[app.preferredApkIndex].value,
          additionalSettingsPlusSourceConfig,
        ),
        app.url,
        additionalSettingsPlusSourceConfig,
      );
      if (allowUserInteraction && isCleartextDownloadUrl(downloadUrl)) {
        final NavigatorState? navigator = globalNavigatorKey.currentState;
        if (navigator == null || !navigator.mounted) {
          throw ObtainiumError(tr('cancelled'));
        }
        final bool? proceed = await showDialog<bool>(
          context: navigator.context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(tr('insecureDownloadUrl')),
            contentPadding: appDialogContentPadding,
            content: Text(tr('cleartextDownloadWarningExplanation')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(tr('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(tr('continue')),
              ),
            ],
          ),
        );
        if (proceed != true) {
          throw ObtainiumError(tr('cancelled'));
        }
      }
      if (notificationsProvider != null) {
        await notificationsProvider.cancel(notifId);
      }
      nativeDownloadServiceStarted =
          await NativeFeatures.startDownloadForegroundService(
            id: initialNotification.id,
            appId: app.id,
            title: initialNotification.title,
            message: initialNotification.message,
            channelCode: initialNotification.channelCode,
            channelName: initialNotification.channelName,
            channelDescription: initialNotification.channelDescription,
            cancelLabel: tr('cancel'),
          );
      var notif = initialNotification;
      if (!nativeDownloadServiceStarted) {
        unawaited(notificationsProvider?.notify(notif));
      }
      int? prevProg;
      var fileNameNoExt = '${app.id}-${downloadUrl.hashCode}';
      if (source.urlsAlwaysHaveExtension) {
        fileNameNoExt =
            '$fileNameNoExt.${app.apkUrls[app.preferredApkIndex].key.split('.').last}';
      }
      final headers = await source.getRequestHeaders(
        app.additionalSettings,
        downloadUrl,
        forAPKDownload: true,
      );
      var downloadedFile = await downloadFileWithRetry(
        downloadUrl,
        fileNameNoExt,
        source.urlsAlwaysHaveExtension,
        headers: headers,
        (double? progress, [int? received, int? total]) {
          final int? prog = progress?.ceil();
          if (apps[app.id] != null) {
            apps[app.id]!.downloadReceivedBytes = received;
            apps[app.id]!.downloadTotalBytes = total;
            apps[app.id]!.downloadProgress = progress;
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
            receivedBytes: received,
            totalBytes: total,
          );
          if (prog != null && prevProg != prog) {
            if (nativeDownloadServiceStarted) {
              unawaited(
                NativeFeatures.showDownloadProgressNotification(
                  id: notif.id,
                  appId: app.id,
                  title: notif.title,
                  message: notif.message,
                  channelCode: notif.channelCode,
                  progressPercent: prog,
                  indeterminate: false,
                  cancelLabel: tr('cancel'),
                  shortCriticalText: '$prog%',
                ),
              );
            } else {
              unawaited(notificationsProvider?.notify(notif));
            }
          }
          prevProg = prog;
        },
        this.apkDir.path,
        useExisting: useExisting,
        allowInsecure: app.settings.getBool('allowInsecure'),
        logs: logs,
        cancellationToken: cancellationToken,
      );
      if (apps[app.id] != null) {
        apps[app.id]!.downloadProgress = _remainingStepsProgress.toDouble();
        notify();
        notif = DownloadNotification(app.finalName, _remainingStepsProgress);
        if (nativeDownloadServiceStarted) {
          unawaited(
            NativeFeatures.showDownloadProgressNotification(
              id: notif.id,
              appId: app.id,
              title: notif.title,
              message: notif.message,
              channelCode: notif.channelCode,
              progressPercent: _remainingStepsProgress,
              indeterminate: true,
              cancelLabel: tr('cancel'),
            ),
          );
        } else {
          unawaited(notificationsProvider?.notify(notif));
        }
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
      if (isAPK) {
        newInfo = await packageManager.getPackageArchiveInfo(
          archiveFilePath: downloadedFile.path,
        );
      } else {
        final String apkDirPath = '${downloadedFile.path}-dir';
        if (isTarball) {
          await extractTarballFile(downloadedFile.path, apkDirPath);
        } else {
          await unzipFile(downloadedFile.path, apkDirPath);
        }
        apkDir = Directory(apkDirPath);
        var apks = apkDir
            .listSync(recursive: true)
            .where((e) => AppSource.isApkOrContainerFile(e.path))
            .toList();

        apks = _preferMatchingApk(apks, app.id);

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
      if (isAPK) {
        return DownloadedApk(resolvedAppId, downloadedFile);
      } else {
        DownloadedDirType dirType;
        if (isXAPK) {
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
      if (nativeDownloadServiceStarted) {
        await NativeFeatures.stopDownloadForegroundService();
      }
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
      unawaited(
        logs.add(
          'App will not be installed silently: multiple APK URLs require manual selection: ${app.id}',
        ),
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
      unawaited(
        logs.add(
          'App will not be installed in the background: background updates are disabled: ${app.id}',
        ),
      );
      return false;
    }
    if (app.settings.getBool('exemptFromBackgroundUpdates')) {
      unawaited(
        logs.add(
          'App will not be installed in the background: exempted from background updates: ${app.id}',
        ),
      );
      return false;
    }
    return canInstallSilently(app);
  }

  Future<void> waitForUserToReturnToForeground(
    NotificationsProvider notificationsProvider,
  ) async {
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
    for (final file in tarArchive.files) {
      if (file.isFile) {
        final content = file.content;
        final outPath = '${destDir.path}/${file.name}';
        final outFile = File(outPath);
        outFile.createSync(recursive: true);
        outFile.writeAsBytesSync(content);
      }
    }
  }

  Future<bool> installApkDir(
    DownloadedDir dir,
    NotificationsProvider? firstInstallNotificationsProvider, {
    bool needsBGWorkaround = false,
    Map<String, dynamic> installOptions = const {},
    bool skipPreInstallVerification = false,

    /// See [installApk]'s param of the same name. Verification/scanning runs
    /// once here against the container before any split part is installed.
    bool showMalwareScanDialog = false,
  }) async {
    // Verify + scan the container once up front; the split-APK installApk calls
    // below pass skipMalwareScan so it is not repeated per part.
    if (!skipPreInstallVerification) {
      final bool proceedAfterVerification = await _runPreInstallVerification(
        appId: dir.appId,
        primaryFile: dir.file,
        showMalwareScanDialog: showMalwareScanDialog,
        cleanupOnSkip: () {
          try {
            if (dir.file.existsSync()) dir.file.deleteSync();
            if (dir.extracted.existsSync()) {
              dir.extracted.deleteSync(recursive: true);
            }
          } catch (_) {}
        },
      );
      if (!proceedAfterVerification) return false;
    }
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
          unawaited(_disposeDownloadedBundle(dir, somethingInstalled));
        } catch (e) {
          unawaited(
            logs.add(
              'Could not install container from ${dir.type}: ${e.toString()}',
            ),
          );
          errors.add(dir.appId, e, appName: apps[dir.appId]?.name);
        }
        if (errors.idsByErrorString.isNotEmpty) {
          throw errors;
        }
        return somethingInstalled;
      }

      apkFiles = _preferMatchingApk(apkFiles, dir.appId).cast<File>().toList();

      if (apkFiles.isEmpty) {
        throw NoAPKError();
      }

      try {
        final wasInstalled = await installApk(
          DownloadedApk(dir.appId, apkFiles[0]),
          firstInstallNotificationsProvider,
          needsBGWorkaround: needsBGWorkaround,
          installOptions: installOptions,
          additionalAPKs: apkFiles
              .sublist(1)
              .map((a) => DownloadedApk(dir.appId, a))
              .toList(),
          // Container already verified/scanned above.
          skipMalwareScan: true,
          // The bundle itself is what gets saved (below); don't also persist
          // the extracted primary APK under the same release asset name.
          skipApkSaveFolderPersistForPrimaryApk: true,
        );
        somethingInstalled = somethingInstalled || wasInstalled;
        unawaited(_disposeDownloadedBundle(dir, somethingInstalled));
      } catch (e) {
        unawaited(
          logs.add(
            'Could not install APKs for ${dir.appId} from ${dir.type}: ${e.toString()}',
          ),
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
    NotificationsProvider? firstInstallNotificationsProvider, {
    bool needsBGWorkaround = false,
    Map<String, dynamic> installOptions = const {},
    List<DownloadedApk> additionalAPKs = const [],

    /// Whether a build-verification/VirusTotal result can be shown as a dialog
    /// (someone's watching) or must skip the app and notify (background/silent).
    bool showMalwareScanDialog = false,

    /// Set by [installApkDir] for a split APK — the container was already
    /// verified/scanned once, so re-running per part would waste effort and the
    /// VirusTotal rate limit.
    bool skipMalwareScan = false,

    /// Set by [installApkDir] for the extracted primary split APK: the outer
    /// bundle ([DownloadedDir.file]) is what gets persisted to the save folder,
    /// so the extracted APK must not be copied again under the same asset name.
    bool skipApkSaveFolderPersistForPrimaryApk = false,
  }) async {
    // Resolve the "Save downloaded APK copies" target once, up front (matches
    // main). Only touched when the feature is on and this isn't the extracted
    // primary of a bundle install; feature-off leaves this null (no behavior
    // change, no extra SAF access).
    final bool saveApkCopiesRequested =
        settingsProvider.saveDownloadedApkCopies &&
        !skipApkSaveFolderPersistForPrimaryApk;
    final Uri? apkSaveTreeUri = (Platform.isAndroid && saveApkCopiesRequested)
        ? await settingsProvider.getApkSaveDir(warnIfInaccessible: true)
        : null;
    if (!skipMalwareScan) {
      final bool proceed = await _runPreInstallVerification(
        appId: file.appId,
        primaryFile: file.file,
        showMalwareScanDialog: showMalwareScanDialog,
        cleanupOnSkip: () {
          try {
            if (file.file.existsSync()) file.file.deleteSync();
            for (final a in additionalAPKs) {
              if (a.file.existsSync()) a.file.deleteSync();
            }
          } catch (_) {}
        },
      );
      if (!proceed) return false;
    }
    if (firstInstallNotificationsProvider != null) {
      await _shareWithVerifiedApps(file, firstInstallNotificationsProvider);
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
        unawaited(
          logs.add(
            'Failed to delete bad download files for ${file.appId}: ${e.toString()}',
          ),
        );
      }
      throw ObtainiumError(tr('badDownload'))..url = apps[file.appId]?.app.url;
    }
    final PackageInfo? appInfo = await getInstalledInfo(
      apps[file.appId]!.app.id,
    );
    unawaited(
      logs.add(
        'Installing "${newInfo.packageName}" version "${newInfo.versionName}" versionCode "${newInfo.versionCode}"${appInfo != null ? ' (from existing version "${appInfo.versionName}" versionCode "${appInfo.versionCode}")' : ''}',
      ),
    );
    final newVersionCode = newInfo.versionCode;
    final oldVersionCode = appInfo?.versionCode;
    if (isStockInstallerDowngrade(
          installedVersionCode: oldVersionCode,
          newVersionCode: newVersionCode,
          installerModeKey: getInstaller().modeKey,
        ) &&
        !(await canDowngradeApps()) &&
        settingsProvider.showAppDowngradeError) {
      try {
        file.file.deleteSync();
      } catch (e) {
        unawaited(
          logs.add(
            'Failed to delete downgraded APK file: $e',
            level: LogLevel.error,
          ),
        );
      }
      throw DowngradeError(oldVersionCode!, newVersionCode!);
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
    final InstallResult result = await getInstaller().installApk(
      allAPKs,
      appId: file.appId,
      installOptions: installOptions,
    );
    final bool installed = result.isSuccess;
    if (installed) {
      apps[file.appId]!.app = apps[file.appId]!.app.copyWith(
        installedVersion: apps[file.appId]!.app.latestVersion,
      );
    }
    // Dispose the downloaded APK for EVERY outcome (parity with main's
    // _disposeInstalledApkFilesAfterSession): copy it into the save folder if
    // that feature is on (regardless of success — so a cancelled/pending
    // install still yields a saved copy), then delete only when the install
    // succeeded or the version was skipped. A failed/cancelled/pending install
    // with no skip keeps the file so a retry can reuse it without re-download.
    if (saveApkCopiesRequested && apkSaveTreeUri != null) {
      await _saveInstalledApkCopyThenMaybeDelete(
        appId: file.appId,
        primaryFile: file.file,
        installReportedOk: installed,
        apkSaveTreeUri: apkSaveTreeUri,
      );
    } else {
      final App? appRef = apps[file.appId]?.app;
      final bool skipLatest =
          appRef != null && isSkipActiveForCurrentLatest(appRef);
      if (installed || skipLatest) {
        try {
          await file.file.delete(recursive: true);
        } catch (e) {
          unawaited(
            logs.add('Failed to delete APK after install: ${e.toString()}'),
          );
        }
      }
    }
    if (result.isError) {
      throw InstallError(result.errorCode!);
    }
    await saveApps([apps[file.appId]!.app]);
    return installed;
  }

  Future<void> _shareWithVerifiedApps(
    DownloadedApk file,
    NotificationsProvider notificationsProvider,
  ) async {
    if (!settingsProvider.beforeNewInstallsShareToAppVerifier) return;
    // Intentionally does NOT gate on whether a known verifier app is installed.
    // Package-visibility rules (Android 11+) hide those packages from
    // getInstalledInfo unless each is declared in a <queries> block, so an
    // installed-check silently suppresses the share sheet for everyone (the
    // regression this restores). The user already opted in via the setting; the
    // share sheet itself lets them pick the verifier. Do not reintroduce a
    // getInstalledInfo()-based gate here.
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
    try {
      await SharePlus.instance.share(ShareParams(files: [f]));
      // The share sheet pulls the user out to the verifier app; wait for them to
      // return before continuing to the actual install prompt.
      await waitForUserToReturnToForeground(notificationsProvider);
    } catch (e) {
      unawaited(logs.add('Share to App Verifier failed: ${e.toString()}'));
    }
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
        unawaited(
          logs.add(
            'Copied OBB file $obbFileName for $appId via direct file access',
          ),
        );
      } catch (e) {
        unawaited(
          logs.add('Failed to place OBB file for $appId: ${e.toString()}'),
        );
      }
    } else {
      await Permission.storage.request();
      final String obbDirPath =
          '${await getStorageRootPath()}/Android/obb/$appId';
      Directory(obbDirPath).createSync(recursive: true);
      final String obbFileName = file.path.split('/').last;
      await file.copy('$obbDirPath/$obbFileName');
      unawaited(
        logs.add(
          'Copied OBB file $obbFileName for $appId via direct file access',
        ),
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
    bool pickAnyAsset, {
    bool allowUserInteraction = false,
    bool evenIfSingleChoice = false,
    ThemeData? dialogTheme,
  }) async {
    var urlsToSelectFrom = app.apkUrls;
    if (pickAnyAsset) {
      urlsToSelectFrom = [...urlsToSelectFrom, ...app.otherAssetUrls];
    }
    // If the App has more than one APK, the user should pick one (if context provided)
    MapEntry<String, String>? appFileUrl;
    if (urlsToSelectFrom.isNotEmpty) {
      final int selectedApkIndex =
          app.preferredApkIndex >= 0 &&
              app.preferredApkIndex < urlsToSelectFrom.length
          ? app.preferredApkIndex
          : 0;
      appFileUrl = urlsToSelectFrom[selectedApkIndex];
    }
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

    final NavigatorState? navigator = allowUserInteraction
        ? globalNavigatorKey.currentState
        : null;
    if ((urlsToSelectFrom.length > 1 || evenIfSingleChoice) &&
        navigator != null &&
        navigator.mounted) {
      appFileUrl = await showDialog(
        context: navigator.context,
        builder: (BuildContext ctx) {
          final Widget picker = AppFilePicker(
            app: app,
            initVal: appFileUrl,
            archs: archs,
            pickAnyAsset: pickAnyAsset,
          );
          return dialogTheme == null
              ? picker
              : Theme(data: dialogTheme, child: picker);
        },
      );
    }
    String? getHost(String url) {
      if (url == 'placeholder') {
        return null;
      }
      final temp = Uri.parse(url).host.split('.');
      if (temp.length < 2) return temp.first;
      return temp.sublist(temp.length - 2).join('.');
    }

    // If the picked APK comes from an origin different from the source, get user confirmation (if context provided)
    if (appFileUrl != null &&
        ![
          getHost(app.url),
          'placeholder',
        ].contains(getHost(appFileUrl.value)) &&
        navigator != null &&
        navigator.mounted) {
      if (!(settingsProvider.hideAPKOriginWarning) &&
          await showDialog(
                context: navigator.context,
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
    bool allowUserInteraction, {
    ThemeData? dialogTheme,
  }) async {
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
        await checkUpdate(apps[id]!.app.id);
      }
      if (!trackOnly) {
        apkUrl = await confirmAppFileUrl(
          apps[id]!.app,
          false,
          allowUserInteraction: allowUserInteraction,
          dialogTheme: dialogTheme,
        );
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
        if (allowUserInteraction ||
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

  /// Downloads APKs for [appIds] and installs them, silently when possible.
  /// Without a BuildContext, apps requiring user interaction are skipped
  /// and a notification is sent instead. Returns IDs of successfully downloaded apps.
  Future<List<String>> downloadAndInstallLatestApps(
    List<String> appIds,
    BuildContext? context, {
    NotificationsProvider? notificationsProvider,
    bool forceParallelDownloads = false,
    bool useExisting = true,
    ThemeData? dialogTheme,
  }) async {
    final bool allowUserInteraction = context != null;
    if (notificationsProvider == null && allowUserInteraction) {
      final BuildContext? appContext = globalNavigatorKey.currentContext;
      if (appContext != null) {
        notificationsProvider = appContext.read<NotificationsProvider>();
      }
    }

    var (appsToInstall, trackOnlyAppsToUpdate) = await _resolveAppsToInstall(
      appIds,
      allowUserInteraction,
      dialogTheme: dialogTheme,
    );

    // Mark all specified track-only apps as latest
    await saveApps(
      trackOnlyAppsToUpdate.map((e) {
        var a = apps[e]!.app;
        a = a.copyWith(installedVersion: a.latestVersion);
        return a;
      }).toList(),
    );

    final MultiAppMultiError errors = MultiAppMultiError();
    final List<String> installedIds = [];
    final List<({String appName, String status, String? detail})>
    malwareScanSkips = [];

    // Move Obtainium to the end of the line (let all other apps update first)
    appsToInstall = moveStrToEnd(
      appsToInstall,
      obtainiumId,
      strB: obtainiumTempId,
    );
    appsToInstall = moveStrToEnd(appsToInstall, '$obtainiumId.fdroid');
    appsToInstall = moveStrToEnd(appsToInstall, '$obtainiumId.debug');

    Future<void> installDownloadResult(_InstallResult result) async {
      if ((result.downloadedFile == null && result.downloadedDir == null) ||
          errors.appIdNames.containsKey(result.id)) {
        return;
      }
      try {
        await _installDownloadedApp(
          result.id,
          result.willBeSilent,
          result.downloadedFile,
          result.downloadedDir,
          installedIds,
          errors,
          allowUserInteraction,
          notificationsProvider,
        );
      } on MalwareScanBlockedError catch (error) {
        malwareScanSkips.add((
          appName: apps[result.id]?.name ?? result.id,
          status: error.status,
          detail: error.detail,
        ));
      } catch (error) {
        errors.add(result.id, error, appName: apps[result.id]?.name);
      }
    }

    try {
      if (!forceParallelDownloads && !settingsProvider.parallelDownloads) {
        for (final id in appsToInstall) {
          await installDownloadResult(
            await _downloadAppForInstall(
              id,
              allowUserInteraction,
              notificationsProvider,
              useExisting,
              errors,
            ),
          );
        }
      } else {
        final downloads = <({String id, Future<_InstallResult> result})>[
          for (final id in appsToInstall)
            (
              id: id,
              result: _downloadAppForInstall(
                id,
                allowUserInteraction,
                notificationsProvider,
                useExisting,
                errors,
              ),
            ),
        ];
        final selfUpdateIds = <String>{
          obtainiumId,
          obtainiumTempId,
          '$obtainiumId.fdroid',
          '$obtainiumId.debug',
        };
        await processDownloadResultsAsReady(
          downloads: downloads,
          deferUntilEnd: selfUpdateIds.contains,
          process: installDownloadResult,
        );
      }
    } finally {
      // Clear any remaining progress in case the flow was interrupted
      // (e.g. unhandled error in a download, app backgrounded/killed, etc.)
      for (var id in appsToInstall) {
        apps[id]?.downloadProgress = null;
      }
      notify();
    }

    if (malwareScanSkips.isNotEmpty && notificationsProvider != null) {
      unawaited(
        notificationsProvider.notify(
          MalwareScanSkippedNotification(malwareScanSkips),
        ),
      );
    }

    if (errors.idsByErrorString.isNotEmpty) {
      throw errors;
    }

    return installedIds;
  }

  Future<List<String>> downloadAppAssets(
    List<String> appIds, {
    bool forceParallelDownloads = false,
    ThemeData? dialogTheme,
  }) async {
    final BuildContext? appContext = globalNavigatorKey.currentContext;
    if (appContext == null) {
      throw ObtainiumError(tr('unknown'));
    }
    final NotificationsProvider notificationsProvider = appContext
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
          true,
          allowUserInteraction: true,
          evenIfSingleChoice: true,
          dialogTheme: dialogTheme,
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

  Future<void> _installDownloadedApp(
    String id,
    bool willBeSilent,
    DownloadedApk? downloadedFile,
    DownloadedDir? downloadedDir,
    List<String> installedIds,
    MultiAppMultiError errors,
    bool allowUserInteraction,
    NotificationsProvider? notificationsProvider,
  ) async {
    final appEntry = apps[id];
    if (appEntry == null) return;
    // Nothing to install (e.g. the download was cancelled): skip silently.
    if (downloadedFile == null && downloadedDir == null) return;
    // Installation has actually begun: show an indeterminate busy indicator
    // rather than a frozen percentage. If a VirusTotal scan will run first, lead
    // with "Scanning" so the indicator doesn't flash "Installing" before the scan
    // (the scan step later flips this to "Flagged"/"Installing" as appropriate).
    appEntry.downloadProgress = willScanApkWithVirusTotal()
        ? _scanningProgressSentinel
        : _installingProgressSentinel;
    notify();
    try {
      bool sayInstalled = true;
      final NotificationsProvider? firstInstallNotificationsProvider =
          appEntry.installedInfo == null && allowUserInteraction
          ? notificationsProvider
          : null;
      final String installerModeKey = getInstaller().modeKey;
      // Only the stock session-based installer needs the background-completion
      // workaround (its install await never returns in the background).
      final bool needBGWorkaround =
          willBeSilent && !allowUserInteraction && installerModeKey == 'system';
      final bool shizukuPretendToBeGooglePlay =
          settingsProvider.shizukuPretendToBeGooglePlay ||
          appEntry.app.settings.getBool('shizukuPretendToBeGooglePlay');
      if (downloadedFile != null) {
        if (needBGWorkaround) {
          final bool proceedAfterVerification =
              await _runPreInstallVerification(
                appId: id,
                primaryFile: downloadedFile.file,
                showMalwareScanDialog: false,
                cleanupOnSkip: () {
                  try {
                    if (downloadedFile.file.existsSync()) {
                      downloadedFile.file.deleteSync();
                    }
                  } catch (_) {}
                },
              );
          if (!proceedAfterVerification) return;
          final baseline = await captureInstallBaseline(id);
          unawaited(
            installApk(
              downloadedFile,
              null,
              needsBGWorkaround: true,
              installOptions: {
                'shizukuPretendToBeGooglePlay': shizukuPretendToBeGooglePlay,
              },
              skipMalwareScan: true,
            ),
          );
          sayInstalled = await waitForPackageInstall(
            id,
            baseline,
            attempts: _bgInstallConfirmAttempts,
          );
          unawaited(
            logs.add(
              sayInstalled
                  ? 'BG install confirmed for $id via polling'
                  : 'BG install poll timed out for $id after $_bgInstallConfirmAttempts attempts',
              level: sayInstalled ? LogLevel.info : LogLevel.warning,
            ),
          );
          if (!sayInstalled) {
            final latestInfo = await getInstalledInfo(id);
            unawaited(
              logs.add(
                'BG install final state for $id: wasInstalled=${baseline.wasInstalled}, '
                'baselineUpdateTime=${baseline.updateTime}, '
                'currentUpdateTime=${latestInfo?.lastUpdateTime}, '
                'latestVersion=${appEntry.app.latestVersion}',
                level: LogLevel.warning,
              ),
            );
          }
        } else {
          sayInstalled = await installApk(
            downloadedFile,
            firstInstallNotificationsProvider,
            installOptions: {
              'shizukuPretendToBeGooglePlay': shizukuPretendToBeGooglePlay,
            },
            showMalwareScanDialog: allowUserInteraction,
          );
        }
      } else {
        if (needBGWorkaround) {
          final bool proceedAfterVerification =
              await _runPreInstallVerification(
                appId: id,
                primaryFile: downloadedDir!.file,
                showMalwareScanDialog: false,
                cleanupOnSkip: () {
                  try {
                    if (downloadedDir.file.existsSync()) {
                      downloadedDir.file.deleteSync();
                    }
                    if (downloadedDir.extracted.existsSync()) {
                      downloadedDir.extracted.deleteSync(recursive: true);
                    }
                  } catch (_) {}
                },
              );
          if (!proceedAfterVerification) return;
          final baseline = await captureInstallBaseline(id);
          unawaited(
            installApkDir(
              downloadedDir,
              null,
              needsBGWorkaround: true,
              skipPreInstallVerification: true,
            ),
          );
          sayInstalled = await waitForPackageInstall(
            id,
            baseline,
            attempts: _bgInstallConfirmAttempts,
          );
          unawaited(
            logs.add(
              sayInstalled
                  ? 'BG install confirmed for $id via polling'
                  : 'BG install poll timed out for $id after $_bgInstallConfirmAttempts attempts',
              level: sayInstalled ? LogLevel.info : LogLevel.warning,
            ),
          );
          if (!sayInstalled) {
            final latestInfo = await getInstalledInfo(id);
            unawaited(
              logs.add(
                'BG install final state for $id: wasInstalled=${baseline.wasInstalled}, '
                'baselineUpdateTime=${baseline.updateTime}, '
                'currentUpdateTime=${latestInfo?.lastUpdateTime}, '
                'latestVersion=${appEntry.app.latestVersion}',
                level: LogLevel.warning,
              ),
            );
          }
        } else {
          sayInstalled = await installApkDir(
            downloadedDir!,
            firstInstallNotificationsProvider,
            installOptions: {
              'shizukuPretendToBeGooglePlay': shizukuPretendToBeGooglePlay,
            },
            showMalwareScanDialog: allowUserInteraction,
          );
        }
      }
      if (willBeSilent && !allowUserInteraction) {
        if (installerModeKey == 'system' && !sayInstalled) {
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
    bool allowUserInteraction,
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
        allowUserInteraction: allowUserInteraction,
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
      willBeSilent = await canInstallSilently(apps[id]!.app);
      final installer = getInstaller();
      await installer.ensurePermission();
      // Only the stock installer surfaces a system install prompt that pulls the
      // user away; wait for them to return before proceeding.
      if (!willBeSilent &&
          allowUserInteraction &&
          notificationsProvider != null &&
          installer.modeKey == 'system') {
        await waitForUserToReturnToForeground(notificationsProvider);
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
  ) async {
    try {
      final String downloadPath = '${await getStorageRootPath()}/Download';
      await downloadFile(
        fileUrl.value,
        fileUrl.key,
        true,
        (double? progress, [int? received, int? total]) {
          unawaited(
            notificationsProvider.notify(
              DownloadNotification(
                fileUrl.key,
                progress?.ceil() ?? 0,
                receivedBytes: received,
                totalBytes: total,
              ),
            ),
          );
        },
        downloadPath,
        headers: await SourceProvider()
            .getSource(app.url, overrideSource: app.overrideSource)
            .getRequestHeaders(
              app.additionalSettings,
              fileUrl.value,
              forAPKDownload: AppSource.isApkOrContainerFile(fileUrl.key),
            ),
        useExisting: false,
        allowInsecure: app.settings.getBool('allowInsecure'),
        logs: logs,
      );
      unawaited(
        notificationsProvider.notify(
          DownloadedNotification(fileUrl.key, fileUrl.value),
        ),
      );
      downloadedIds.add(fileUrl.key);
    } catch (e) {
      if (e is! CancellationException) {
        errors.add(fileUrl.key, e);
      }
    } finally {
      unawaited(
        notificationsProvider.cancel(DownloadNotification(fileUrl.key, 0).id),
      );
    }
  }

  /// Verifies a downloaded GitHub artifact's SHA-256 against its build
  /// attestation. Returns a [githubAttestationStatus*] value, or null when the
  /// app's source is not GitHub.
  Future<String?> verifyGitHubAttestation(App app, File file) async {
    final AppSource source = SourceProvider().getSource(
      app.url,
      overrideSource: app.overrideSource,
    );
    if (source is! GitHub) {
      return null;
    }
    try {
      final String standardizedUrl = source.standardizeUrl(app.url);
      final hash = await sha256.bind(file.openRead()).first;
      final String sha256Digest = hash.toString();
      return await source.getAttestationStatusForSha256Digest(
        standardizedUrl,
        sha256Digest,
        app.additionalSettings,
      );
    } catch (e) {
      unawaited(
        logs.add('Error verifying GitHub attestation: ${e.toString()}'),
      );
    }
    return githubAttestationStatusError;
  }

  /// Whether a VirusTotal scan will actually run for the next install (feature
  /// toggle on and a validated API key present).
  bool willScanApkWithVirusTotal() {
    if (kDebugMode && debugForceFlaggedMalwareScan) {
      return true;
    }
    if (!settingsProvider.enableVirusTotalScanning) {
      return false;
    }
    final String? apiKey = settingsProvider.getSettingString(
      virusTotalApiKeyKey,
    );
    return apiKey != null &&
        apiKey.isNotEmpty &&
        hasValidatedApiKey(apiKey, settingsProvider);
  }

  /// Scans a downloaded APK with VirusTotal, when scanning is enabled and an API
  /// key is configured. A null `status` means no scan was attempted (feature off
  /// or unconfigured) — callers must treat that as a no-op, distinct from a real
  /// [malwareScanStatusError]. Unlike the pre-immutability fork version this no
  /// longer mutates [app]; the caller applies the returned detail/reportUrl via
  /// copyWith.
  Future<({String? status, String? detail, String? reportUrl})>
  scanApkWithVirusTotal(App app, File file) async {
    if (kDebugMode && debugForceFlaggedMalwareScan) {
      final hash = await sha256.bind(file.openRead()).first;
      return (
        status: malwareScanStatusFlagged,
        detail:
            '3/70 security vendors flagged this file (TEST result - '
            'debugForceFlaggedMalwareScan is on)',
        reportUrl: 'https://www.virustotal.com/gui/file/$hash',
      );
    }
    if (!willScanApkWithVirusTotal()) {
      return (status: null, detail: null, reportUrl: null);
    }
    final String apiKey = settingsProvider.getSettingString(
      virusTotalApiKeyKey,
    )!;
    try {
      final hash = await sha256.bind(file.openRead()).first;
      final result = await VirusTotalScanner().scan(
        file,
        hash.toString(),
        apiKey,
      );
      return (
        status: result.status,
        detail: result.detail,
        reportUrl: result.reportUrl,
      );
    } catch (e) {
      unawaited(
        logs.add('Error scanning APK with VirusTotal: ${e.toString()}'),
      );
      return (
        status: malwareScanStatusError,
        detail: tr('virusTotalErrorGeneric', args: [e.toString()]),
        reportUrl: null,
      );
    }
  }

  /// Acts on a [scanApkWithVirusTotal] result: `clean` never interrupts;
  /// `flagged`/`error` pause with a decision dialog when someone is watching
  /// ([showMalwareScanDialog]), or skip the app (throwing
  /// [MalwareScanBlockedError]) when there is no one to ask. [cleanupOnSkip]
  /// deletes whatever was downloaded. Returns true to proceed, false when the
  /// watching user declined (a deliberate choice, not a failure — callers must
  /// return quietly rather than throw).
  Future<bool> _handleMalwareScanResult({
    required App app,
    required String status,
    String? detail,
    String? reportUrl,
    required bool showMalwareScanDialog,
    required void Function() cleanupOnSkip,
  }) async {
    if (status == malwareScanStatusClean) {
      if (showMalwareScanDialog) {
        unawaited(
          Fluttertoast.showToast(
            msg: tr('malwareScanCleanToast', args: [app.finalName]),
          ),
        );
      }
      return true;
    }
    if (showMalwareScanDialog) {
      final NavigatorState? navigator = globalNavigatorKey.currentState;
      if (navigator == null || !navigator.mounted) return true;
      final ThemeData dialogTheme = Theme.of(navigator.context);
      final bool? proceed = await showDialog<bool>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (BuildContext ctx) => Theme(
          data: dialogTheme,
          child: MalwareScanWarningDialog(
            appName: app.finalName,
            status: status,
            detail: detail,
            reportUrl: reportUrl,
          ),
        ),
      );
      if (proceed == true) {
        return true;
      }
      cleanupOnSkip();
      return false;
    }
    cleanupOnSkip();
    throw MalwareScanBlockedError(status, detail, appName: app.finalName);
  }

  Uri? _documentUriFromSafPluginResult(dynamic pluginResult) {
    if (pluginResult == null) return null;
    if (pluginResult is Map) {
      return Uri.parse(
        Map<String, dynamic>.from(pluginResult)['uri'] as String,
      );
    }
    return (pluginResult as dynamic).uri as Uri?;
  }

  /// Writes [source] into the SAF tree as [displayName] without loading the
  /// whole file into memory. Replaces an existing document with the same name.
  Future<bool> _chunkedCopyApkToSafTree(
    File source,
    Uri treeUri,
    String displayName, {
    String? mimeType,
  }) async {
    final String resolvedMime =
        mimeType ??
        (displayName.toLowerCase().endsWith('.apk')
            ? 'application/vnd.android.package-archive'
            : (displayName.toLowerCase().endsWith('.zip')
                  ? 'application/zip'
                  : (displayName.toLowerCase().endsWith('.json')
                        ? 'application/json'
                        : '*/*')));
    final dynamic existing = await saf.findFile(treeUri, displayName);
    if (existing != null) {
      final Uri? existingUri = existing is Map
          ? Uri.parse(Map<String, dynamic>.from(existing)['uri'] as String)
          : (existing as dynamic).uri as Uri?;
      if (existingUri != null) {
        await saf.delete(existingUri);
      }
    }
    Uri? documentUri;
    var isFirstChunk = true;
    await for (final List<int> chunk in source.openRead()) {
      final Uint8List bytes = Uint8List.fromList(chunk);
      if (isFirstChunk) {
        final dynamic created = await saf.createFile(
          treeUri,
          mimeType: resolvedMime,
          displayName: displayName,
          bytes: bytes,
        );
        isFirstChunk = false;
        documentUri = _documentUriFromSafPluginResult(created);
        if (documentUri == null) {
          return false;
        }
      } else {
        await saf.writeToFile(
          documentUri!,
          bytes: bytes,
          mode: FileMode.append,
        );
      }
    }
    if (isFirstChunk) {
      final dynamic created = await saf.createFile(
        treeUri,
        mimeType: resolvedMime,
        displayName: displayName,
        bytes: Uint8List(0),
      );
      return _documentUriFromSafPluginResult(created) != null;
    }
    return true;
  }

  /// Bundle SAF copy + delete for XAPK/ZIP/tarball installs (off the critical
  /// path). Ports main's `_finalizeDownloadedDirDisposition` bundle handling to
  /// this branch's split-file [installApkDir]: when "Save downloaded APK copies"
  /// is on and a folder resolves, [DownloadedDir.file] is copied to the save
  /// folder BEFORE it is deleted, and the delete is gated on a successful copy.
  /// When the feature is off, the bundle is deleted exactly as before.
  /// ([DownloadedDir.extracted] is disposed separately by [installApkDir]'s
  /// finally.)
  Future<void> _disposeDownloadedBundle(
    DownloadedDir dir,
    bool somethingInstalled,
  ) async {
    // Feature OFF (or non-Android): keep the bundle after a failed install so a
    // retry can reuse it — delete only when something installed or the version
    // was skipped (parity with main's !saveApkCopies branch).
    if (!Platform.isAndroid || !settingsProvider.saveDownloadedApkCopies) {
      final App? appForSave = apps[dir.appId]?.app;
      final bool skipLatest =
          appForSave != null && isSkipActiveForCurrentLatest(appForSave);
      if (somethingInstalled || skipLatest) {
        unawaited(dir.file.delete());
      }
      return;
    }
    try {
      final App? appForSave = apps[dir.appId]?.app;
      final Uri? resolvedApkSaveUri = await settingsProvider.getApkSaveDir(
        warnIfInaccessible: true,
      );
      var bundleCopiedOk = false;
      if (appForSave != null &&
          resolvedApkSaveUri != null &&
          dir.file.existsSync()) {
        try {
          bundleCopiedOk = await _chunkedCopyApkToSafTree(
            dir.file,
            resolvedApkSaveUri,
            storeFacingDownloadDisplayNameForApp(appForSave),
          );
        } catch (exception, stackTrace) {
          unawaited(
            logs.add(
              'APK save folder copy failed: ${exception.toString()}\n$stackTrace',
              level: LogLevel.error,
            ),
          );
          unawaited(Fluttertoast.showToast(msg: tr('apkSaveFolderCopyFailed')));
        }
      }
      final bool skipLatest =
          appForSave != null && isSkipActiveForCurrentLatest(appForSave);
      final bool hasSaveFolder = resolvedApkSaveUri != null;
      final bool shouldDeleteBundle;
      if (hasSaveFolder && appForSave != null && dir.file.existsSync()) {
        // A configured, reachable save folder: only delete once the copy landed.
        shouldDeleteBundle =
            bundleCopiedOk && (somethingInstalled || skipLatest);
      } else if (resolvedApkSaveUri == null) {
        // Feature on but folder unreachable: keep the bundle after a successful
        // install (so the user can still recover it), delete only when skipped.
        shouldDeleteBundle = somethingInstalled ? false : skipLatest;
      } else {
        shouldDeleteBundle = somethingInstalled || skipLatest;
      }
      if (shouldDeleteBundle && dir.file.existsSync()) {
        try {
          dir.file.deleteSync();
        } catch (_) {}
      }
    } catch (exception, stackTrace) {
      unawaited(
        logs.add(
          'Post-install bundle disposition failed: ${exception.toString()}\n$stackTrace',
          level: LogLevel.error,
        ),
      );
    }
  }

  /// Per-APK SAF copy + delete after a successful single-APK install (off the
  /// critical path). Ports main's `_disposeInstalledApkFilesAfterSession`
  /// primary-file handling: the installed APK is copied to the save folder
  /// BEFORE it is deleted, and the delete is gated on a successful copy. Only
  /// invoked when the save-copies feature is on and a folder resolved; the
  /// feature-off delete happens inline at the call site, unchanged.
  Future<void> _saveInstalledApkCopyThenMaybeDelete({
    required String appId,
    required File primaryFile,
    required bool installReportedOk,
    required Uri apkSaveTreeUri,
  }) async {
    try {
      final App? appRef = apps[appId]?.app;
      final bool skipLatest =
          appRef != null && isSkipActiveForCurrentLatest(appRef);
      var copiedOk = false;
      if (appRef != null && primaryFile.existsSync()) {
        try {
          copiedOk = await _chunkedCopyApkToSafTree(
            primaryFile,
            apkSaveTreeUri,
            storeFacingDownloadDisplayNameForApp(appRef),
          );
        } catch (exception, stackTrace) {
          unawaited(
            logs.add(
              'APK save folder copy failed: ${exception.toString()}\n$stackTrace',
              level: LogLevel.error,
            ),
          );
          unawaited(Fluttertoast.showToast(msg: tr('apkSaveFolderCopyFailed')));
        }
      }
      // hasSaveFolder is always true here (caller only invokes with a resolved
      // save URI), so mirror main's hasSaveFolder branch directly.
      final bool deletePrimary = copiedOk && (installReportedOk || skipLatest);
      if (deletePrimary && primaryFile.existsSync()) {
        try {
          primaryFile.deleteSync();
        } catch (_) {}
      }
    } catch (exception, stackTrace) {
      unawaited(
        logs.add(
          'Post-install APK disposition failed: ${exception.toString()}\n$stackTrace',
          level: LogLevel.error,
        ),
      );
    }
  }

  /// Runs the pre-install verification gauntlet for [appId]: reproducible-build
  /// enforcement, GitHub attestation verify/enforce, and VirusTotal scanning.
  /// Persists attestation/malware status via copyWith + saveApps. Returns true
  /// to proceed, false when a watching user declined a flagged/errored scan;
  /// throws [ObtainiumError] for an enforcement block and
  /// [MalwareScanBlockedError] for a silent (background) skip.
  Future<bool> _runPreInstallVerification({
    required String appId,
    required File primaryFile,
    required bool showMalwareScanDialog,
    required void Function() cleanupOnSkip,
  }) async {
    final AppInMemory? appInMemory = apps[appId];
    if (appInMemory == null) return true;
    App app = appInMemory.app;
    final AppSource source = SourceProvider().getSource(
      app.url,
      overrideSource: app.overrideSource,
    );

    // Reproducible-build enforcement.
    if (reproducibleBuildEnforcementBlocksInstall(app, source)) {
      cleanupOnSkip();
      throw ObtainiumError(reproducibleBuildEnforcedBlockedMessage());
    }

    // GitHub attestation verification (+ optional enforcement).
    if (source is GitHub &&
        source.shouldVerifyAttestations(
          app.additionalSettings,
          settingsProvider,
        )) {
      final String? attestationStatus = await verifyGitHubAttestation(
        app,
        primaryFile,
      );
      app = app.copyWith(latestAttestationStatus: attestationStatus);
      if (apps[appId] != null) {
        apps[appId]!.app = app;
      }
      await saveApps([app]);
      if (source.shouldEnforceAttestations(
            app.additionalSettings,
            settingsProvider,
          ) &&
          attestationStatus != githubAttestationStatusVerified) {
        cleanupOnSkip();
        throw ObtainiumError(
          githubAttestationEnforcedBlockedMessage(attestationStatus),
        );
      }
    }

    // VirusTotal malware scan. Surface "Scanning with VirusTotal" while it runs
    // (the caller set "Installing"/"Scanning" up front, but the scan is the part
    // that actually takes time), then reflect a flagged/errored result as
    // "Flagged" before prompting the user to decide.
    if (willScanApkWithVirusTotal()) {
      apps[appId]?.downloadProgress = _scanningProgressSentinel;
      notify();
    }
    final scan = await scanApkWithVirusTotal(app, primaryFile);
    if (scan.status != null) {
      app = app.copyWith(
        latestMalwareScanStatus: scan.status,
        latestMalwareScanDetail: scan.detail,
        latestMalwareScanReportUrl: scan.reportUrl,
      );
      if (apps[appId] != null) {
        apps[appId]!.app = app;
      }
      await saveApps([app]);
      apps[appId]?.downloadProgress = scan.status != malwareScanStatusClean
          ? _flaggedProgressSentinel
          : _installingProgressSentinel;
      notify();
      final bool proceed = await _handleMalwareScanResult(
        app: app,
        status: scan.status!,
        detail: scan.detail,
        reportUrl: scan.reportUrl,
        showMalwareScanDialog: showMalwareScanDialog,
        cleanupOnSkip: cleanupOnSkip,
      );
      if (!proceed) return false;
      if (showMalwareScanDialog && scan.status != malwareScanStatusClean) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    // Scan cleared (or was skipped) and we're proceeding — hand back to the
    // installer as "Installing" so a lingering "Scanning"/"Flagged" state clears.
    apps[appId]?.downloadProgress = _installingProgressSentinel;
    notify();
    return true;
  }
}
