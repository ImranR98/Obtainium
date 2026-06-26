part of 'apps_provider.dart';

/// App download, install, and on-device package operations for [AppsProvider].
extension AppsProviderInstall on AppsProvider {
  Future<File> handleAPKIDChange(
    App app,
    PackageInfo newInfo,
    File downloadedFile,
    String downloadUrl,
  ) async {
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
        '${downloadedFile.parent.path}/${app.id}-${downloadUrl.hashCode}.${downloadedFile.path.split('.').last}',
      );
      if (apps[originalAppId] != null) {
        await removeApps([originalAppId]);
        await saveApps([
          app,
        ], onlyIfExists: !isTempIdBool && !idChangeWasAllowed);
      }
    }
    return downloadedFile;
  }

  Future<void> updatePendingRepoRename(String appId, String? newUrl) async {
    if (apps.containsKey(appId)) {
      apps[appId]!.app.pendingRepoRenameUrl = newUrl;
      await saveApps([apps[appId]!.app]);
    }
  }

  Future<void> acceptRepoRename(String appId, String newUrl) async {
    if (apps.containsKey(appId)) {
      apps[appId]!.app.url = newUrl;
      apps[appId]!.app.pendingRepoRenameUrl = null;
      await saveApps([apps[appId]!.app]);
    }
  }

  Future<Object> downloadApp(
    App app,
    BuildContext? context, {
    NotificationsProvider? notificationsProvider,
    bool useExisting = true,
  }) async {
    var notifId = DownloadNotification(app.finalName, 0).id;
    if (apps[app.id] != null) {
      apps[app.id]!.downloadProgress = 0;
      notify();
    }
    try {
      if (app.apkUrls.isEmpty) throw NoAPKError();
      if (app.preferredApkIndex >= app.apkUrls.length) {
        app.preferredApkIndex = app.apkUrls.length - 1;
      }
      if (app.preferredApkIndex < 0) app.preferredApkIndex = 0;
      AppSource source = SourceProvider().getSource(
        app.url,
        overrideSource: app.overrideSource,
      );
      var additionalSettingsPlusSourceConfig = {
        ...app.additionalSettings,
        ...(await source.getSourceConfigValues(
          app.additionalSettings,
          settingsProvider,
        )),
      };
      String downloadUrl = await source.assetUrlPrefetchModifier(
        await source.generalReqPrefetchModifier(
          app.apkUrls[app.preferredApkIndex].value,
          additionalSettingsPlusSourceConfig,
        ),
        app.url,
        additionalSettingsPlusSourceConfig,
      );
      var notif = DownloadNotification(app.finalName, 100);
      notificationsProvider?.cancel(notif.id);
      int? prevProg;
      var fileNameNoExt = '${app.id}-${downloadUrl.hashCode}';
      if (source.urlsAlwaysHaveExtension) {
        fileNameNoExt =
            '$fileNameNoExt.${app.apkUrls[app.preferredApkIndex].key.split('.').last}';
      }
      var headers = await source.getRequestHeaders(
        app.additionalSettings,
        downloadUrl,
        forAPKDownload: true,
      );
      var downloadedFile = await downloadFileWithRetry(
        downloadUrl,
        fileNameNoExt,
        source.urlsAlwaysHaveExtension,
        headers: headers,
        (double? progress) {
          int? prog = progress?.ceil();
          if (apps[app.id] != null) {
            apps[app.id]!.downloadProgress = progress;
            notify();
          }
          notif = DownloadNotification(app.finalName, prog ?? 100);
          if (prog != null && prevProg != prog) {
            notificationsProvider?.notify(notif);
          }
          prevProg = prog;
        },
        this.apkDir.path,
        useExisting: useExisting,
        allowInsecure: app.additionalSettings['allowInsecure'] == true,
        logs: logs,
      );
      // Set to 90 for remaining steps, will make null in 'finally'
      if (apps[app.id] != null) {
        apps[app.id]!.downloadProgress = -1;
        notify();
        notif = DownloadNotification(app.finalName, -1);
        notificationsProvider?.notify(notif);
      }
      PackageInfo? newInfo;
      var originalAssetName = app.apkUrls[app.preferredApkIndex].key
          .toLowerCase();
      var isAPK = downloadedFile.path.toLowerCase().endsWith('.apk');
      var isXAPK = downloadedFile.path.toLowerCase().endsWith('.xapk');
      var isTarball =
          originalAssetName.endsWith('.tar.gz') ||
          originalAssetName.endsWith('.tgz') ||
          originalAssetName.endsWith('.tar.bz2') ||
          originalAssetName.endsWith('.tar.xz');
      Directory? apkDir;
      if (isAPK) {
        newInfo = await pm.getPackageArchiveInfo(
          archiveFilePath: downloadedFile.path,
        );
      } else {
        // Assume XAPK, ZIP, or tarball
        String apkDirPath = '${downloadedFile.path}-dir';
        if (isTarball) {
          await extractTarballFile(downloadedFile.path, apkDirPath);
        } else {
          await unzipFile(downloadedFile.path, apkDirPath);
        }
        apkDir = Directory(apkDirPath);
        var apks = apkDir
            .listSync(recursive: true)
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
          apks = [temp!, ...apks];
        }

        String? filterRegEx;
        if (isTarball &&
            app.additionalSettings['tarballedApkFilterRegEx']?.isNotEmpty ==
                true) {
          filterRegEx = app.additionalSettings['tarballedApkFilterRegEx'];
        } else if (!isTarball &&
            app.additionalSettings['zippedApkFilterRegEx']?.isNotEmpty ==
                true) {
          filterRegEx = app.additionalSettings['zippedApkFilterRegEx'];
        }
        if (filterRegEx != null) {
          var reg = RegExp(filterRegEx);
          apks.removeWhere((apk) {
            var relativePath = apk.path.substring(apkDir!.path.length + 1);
            var shouldDelete = !reg.hasMatch(relativePath);
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
            newInfo = await pm.getPackageArchiveInfo(
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
        downloadedFile.delete();
        throw ObtainiumError('Could not get ID from APK');
      }
      downloadedFile = await handleAPKIDChange(
        app,
        newInfo,
        downloadedFile,
        downloadUrl,
      );
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
        DownloadedDirType dirType;
        if (isXAPK) {
          dirType = DownloadedDirType.xapk;
        } else if (isTarball) {
          dirType = DownloadedDirType.tarball;
        } else {
          dirType = DownloadedDirType.zip;
        }
        return DownloadedDir(app.id, downloadedFile, apkDir!, dirType);
      }
    } finally {
      notificationsProvider?.cancel(notifId);
      if (apps[app.id] != null) {
        apps[app.id]!.downloadProgress = null;
        notify();
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
          ? (await pm.getInstallSourceInfo(
              packageName: app.id,
            ))?.installingPackageName
          : (await pm.getInstallerPackageName(packageName: app.id));
    } catch (e) {
      logs.add(
        'Failed to get installed package details: ${app.id} (${e.toString()})',
      );
      return false; // App probably not installed
    }

    int? targetSDK = (await getInstalledInfo(
      app.id,
    ))?.applicationInfo?.targetSdkVersion;
    int requiredSDK = osInfo.version.sdkInt - 3;
    // The APK should target a new enough API
    // https://developer.android.com/reference/android/content/pm/PackageInstaller.SessionParams#setRequireUserAction(int)
    if (!(targetSDK != null && targetSDK >= requiredSDK)) {
      logs.add(
        'App currently targets API $targetSDK which is too low for background updates (requires API $requiredSDK): ${app.id}',
      );
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
    NotificationsProvider notificationsProvider = context
        .read<NotificationsProvider>();
    if (!isForeground) {
      await notificationsProvider.notify(
        completeInstallationNotification,
        cancelExisting: true,
      );
      while (await FGBGEvents.instance.stream.first != FGBGType.foreground) {}
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
    final bytes = await File(filePath).readAsBytes();
    List<int> decompressed;

    // Detect compression by magic bytes (file extension may be wrong after download)
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      // gzip
      decompressed = archive.GZipDecoder().decodeBytes(bytes);
    } else if (bytes.length >= 3 &&
        bytes[0] == 0x42 &&
        bytes[1] == 0x5a &&
        bytes[2] == 0x68) {
      // bzip2 ('BZh')
      decompressed = archive.BZip2Decoder().decodeBytes(bytes);
    } else if (bytes.length >= 6 &&
        bytes[0] == 0xfd &&
        bytes[1] == 0x37 &&
        bytes[2] == 0x7a &&
        bytes[3] == 0x58 &&
        bytes[4] == 0x5a &&
        bytes[5] == 0x00) {
      // xz
      decompressed = archive.XZDecoder().decodeBytes(bytes);
    } else {
      // Assume uncompressed tar
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
    BuildContext? firstTimeWithContext, {
    bool needsBGWorkaround = false,
    bool shizukuPretendToBeGooglePlay = false,
  }) async {
    // We don't know which APKs in an XAPK or ZIP are supported by the user's device
    // So we try installing all of them and assume success if at least one installed
    // If 0 APKs installed, throw the first install error encountered
    // Obviously this approach is naive and is undesirable in many cases, needs to be improved
    var somethingInstalled = false;
    try {
      MultiAppMultiError errors = MultiAppMultiError();
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

      File? temp;
      apkFiles.removeWhere((element) {
        bool res = element.uri.pathSegments.last.startsWith(dir.appId);
        if (res) {
          temp = element;
        }
        return res;
      });
      if (temp != null) {
        apkFiles = [temp!, ...apkFiles];
      }

      try {
        var wasInstalled = await installApk(
          DownloadedApk(dir.appId, apkFiles[0]),
          // ignore: use_build_context_synchronously
          firstTimeWithContext,
          needsBGWorkaround: needsBGWorkaround,
          shizukuPretendToBeGooglePlay: shizukuPretendToBeGooglePlay,
          additionalAPKs: apkFiles.sublist(
            1,
          ).map((a) => DownloadedApk(dir.appId, a)).toList(),
        );
        somethingInstalled = somethingInstalled || wasInstalled;
        dir.file.delete(recursive: true);
      } catch (e) {
        logs.add('Could not install APKs from ${dir.type}: ${e.toString()}');
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
    DownloadedApk file,
    BuildContext? firstTimeWithContext, {
    bool needsBGWorkaround = false,
    bool shizukuPretendToBeGooglePlay = false,
    List<DownloadedApk> additionalAPKs = const [],
  }) async {
    if (firstTimeWithContext != null) {
      await _shareToAppVerifier(file, firstTimeWithContext);
    }
    var newInfo = await pm.getPackageArchiveInfo(
      archiveFilePath: file.file.path,
    );
    if (newInfo == null) {
      try {
        deleteFile(file.file);
        for (var a in additionalAPKs) {
          deleteFile(a.file);
        }
      } catch (e) {
        //
      } finally {
        throw ObtainiumError(tr('badDownload'));
      }
    }
    PackageInfo? appInfo = await getInstalledInfo(apps[file.appId]!.app.id);
    logs.add(
      'Installing "${newInfo.packageName}" version "${newInfo.versionName}" versionCode "${newInfo.versionCode}"${appInfo != null ? ' (from existing version "${appInfo.versionName}" versionCode "${appInfo.versionCode}")' : ''}',
    );
    if (appInfo != null &&
        newInfo.versionCode! < appInfo.versionCode! &&
        !(await canDowngradeApps())) {
      if (settingsProvider.showAppDowngradeError) {
        throw DowngradeError(appInfo.versionCode!, newInfo.versionCode!);
      }
    }
    if (needsBGWorkaround) {
      // The below 'await' will never return if we are in a background process
      // To work around this, we should assume the install will be successful
      // So we update the app's installed version first as we will never get to the later code
      // We can't conditionally get rid of the 'await' as this causes install fails (BG process times out) - see #896
      // TODO: When fixed, update this function and the calls to it accordingly
      apps[file.appId]!.app.installedVersion =
          apps[file.appId]!.app.latestVersion;
      await saveApps([
        apps[file.appId]!.app,
      ], attemptToCorrectInstallStatus: false);
    }
    int? code;
    if (!settingsProvider.useShizuku) {
      var allAPKs = [file.file.path];
      allAPKs.addAll(additionalAPKs.map((a) => a.file.path));
      code = await AndroidPackageInstaller.installApk(
        apkFilePath: allAPKs.join(','),
      );
    } else {
      code = await ShizukuApkInstaller().installAPK(
        file.file.uri.toString(),
        shizukuPretendToBeGooglePlay ? "com.android.vending" : "",
      );
    }
    bool installed = false;
    if (code != null && code != 0 && code != 3) {
      try {
        deleteFile(file.file);
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

  Future<void> _shareToAppVerifier(
    DownloadedApk file,
    BuildContext context,
  ) async {
    if (!settingsProvider.beforeNewInstallsShareToAppVerifier) return;
    if (await getInstalledInfo('dev.soupslurpr.appverifier') == null) return;
    XFile f = XFile.fromData(
      file.file.readAsBytesSync(),
      mimeType: 'application/vnd.android.package-archive',
    );
    Fluttertoast.showToast(
      msg: tr('appVerifierInstructionToast'),
      toastLength: Toast.LENGTH_LONG,
    );
    await SharePlus.instance.share(ShareParams(files: [f]));
  }

  Future<String> getStorageRootPath() async {
    return '/${(await getAppStorageDir()).uri.pathSegments.sublist(0, 3).join('/')}';
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
    // If the App has more than one APK, the user should pick one (if context provided)
    MapEntry<String, String>? appFileUrl =
        urlsToSelectFrom[app.preferredApkIndex >= 0
            ? app.preferredApkIndex
            : 0];
    // When picking any asset, use the APK filter regex to pre-select the best matching
    // asset by default, without hiding other assets from the user.
    if (pickAnyAsset &&
        app.additionalSettings['apkFilterRegEx'] is String &&
        (app.additionalSettings['apkFilterRegEx'] as String).isNotEmpty) {
      var matching = filterApks(
        urlsToSelectFrom,
        app.additionalSettings['apkFilterRegEx'],
        app.additionalSettings['invertAPKFilter'] == true,
      );
      if (matching.isNotEmpty) {
        appFileUrl = matching.first;
      }
    }
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
        },
      );
    }
    getHost(String url) {
      if (url == 'placeholder') {
        return null;
      }
      var temp = Uri.parse(url).host.split('.');
      return temp.sublist(temp.length - 2).join('.');
    }

    // If the picked APK comes from an origin different from the source, get user confirmation (if context provided)
    if (appFileUrl != null &&
        ![
          getHost(app.url),
          'placeholder',
        ].contains(getHost(appFileUrl.value)) &&
        context != null) {
      if (!(settingsProvider.hideAPKOriginWarning) &&
          await showDialog(
                // ignore: use_build_context_synchronously
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
  ) async {
    List<String> appsToInstall = [];
    List<String> trackOnlyAppsToUpdate = [];
    for (var id in appIds) {
      if (apps[id] == null) {
        throw ObtainiumError(tr('appNotFound'));
      }
      MapEntry<String, String>? apkUrl;
      var trackOnly = apps[id]!.app.additionalSettings['trackOnly'] == true;
      var refreshBeforeDownload =
          apps[id]!.app.additionalSettings['refreshBeforeDownload'] == true ||
          apps[id]!.app.apkUrls.isNotEmpty &&
              apps[id]!.app.apkUrls.first.value == 'placeholder';
      if (refreshBeforeDownload) {
        await checkUpdate(apps[id]!.app.id);
      }
      if (!trackOnly) {
        // ignore: use_build_context_synchronously
        apkUrl = await confirmAppFileUrl(apps[id]!.app, context, false);
      }
      if (apkUrl != null) {
        var url = apkUrl.value;
        int urlInd = apps[id]!.app.apkUrls.indexWhere((e) => e.value == url);
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
    return (appsToInstall, trackOnlyAppsToUpdate);
  }

  // Given a list of AppIds, uses stored info about the apps to download APKs and install them
  // If the APKs can be installed silently, they are
  // If no BuildContext is provided, apps that require user interaction are ignored
  // If user input is needed and the App is in the background, a notification is sent to get the user's attention
  // Returns an array of Ids for Apps that were successfully downloaded, regardless of installation result
  Future<List<String>> downloadAndInstallLatestApps(
    List<String> appIds,
    BuildContext? context, {
    NotificationsProvider? notificationsProvider,
    bool forceParallelDownloads = false,
    bool useExisting = true,
  }) async {
    notificationsProvider =
        notificationsProvider ?? context?.read<NotificationsProvider>();

    var (appsToInstall, trackOnlyAppsToUpdate) = await _resolveAppsToInstall(
      appIds,
      context,
    );

    // Mark all specified track-only apps as latest
    saveApps(
      trackOnlyAppsToUpdate.map((e) {
        var a = apps[e]!.app;
        a.installedVersion = a.latestVersion;
        return a;
      }).toList(),
    );

    // Prepare to download+install Apps
    MultiAppMultiError errors = MultiAppMultiError();
    List<String> installedIds = [];

    // Move Obtainium to the end of the line (let all other apps update first)
    appsToInstall = moveStrToEnd(
      appsToInstall,
      obtainiumId,
      strB: obtainiumTempId,
    );
    appsToInstall = moveStrToEnd(appsToInstall, '$obtainiumId.fdroid');

    Future<void> installFn(
      String id,
      bool willBeSilent,
      DownloadedApk? downloadedFile,
      DownloadedDir? downloadedDir,
    ) async {
      apps[id]?.downloadProgress = -1;
      notify();
      try {
        bool sayInstalled = true;
        var contextIfNewInstall = apps[id]?.installedInfo == null
            ? context
            : null;
        bool needBGWorkaround =
            willBeSilent && context == null && !settingsProvider.useShizuku;
        bool shizukuPretendToBeGooglePlay =
            settingsProvider.shizukuPretendToBeGooglePlay ||
            apps[id]!.app.additionalSettings['shizukuPretendToBeGooglePlay'] ==
                true;
        if (downloadedFile != null) {
          if (needBGWorkaround) {
            // ignore: use_build_context_synchronously
            installApk(
              downloadedFile,
              contextIfNewInstall,
              needsBGWorkaround: true,
              shizukuPretendToBeGooglePlay: shizukuPretendToBeGooglePlay,
            );
          } else {
            // ignore: use_build_context_synchronously
            sayInstalled = await installApk(
              downloadedFile,
              contextIfNewInstall,
              shizukuPretendToBeGooglePlay: shizukuPretendToBeGooglePlay,
            );
          }
        } else {
          if (needBGWorkaround) {
            // ignore: use_build_context_synchronously
            installApkDir(
              downloadedDir!,
              contextIfNewInstall,
              needsBGWorkaround: true,
            );
          } else {
            // ignore: use_build_context_synchronously
            sayInstalled = await installApkDir(
              downloadedDir!,
              contextIfNewInstall,
              shizukuPretendToBeGooglePlay: shizukuPretendToBeGooglePlay,
            );
          }
        }
        if (willBeSilent && context == null) {
          if (!settingsProvider.useShizuku) {
            notificationsProvider?.notify(
              SilentUpdateAttemptNotification([apps[id]!.app], id: id.hashCode),
            );
          } else {
            notificationsProvider?.notify(
              SilentUpdateNotification(
                [apps[id]!.app],
                sayInstalled,
                id: id.hashCode,
              ),
            );
          }
        }
        if (sayInstalled) {
          installedIds.add(id);
          // Dismiss the update notification since the app was successfully installed
          notificationsProvider?.cancel(UpdateNotification([]).id);
        }
      } finally {
        apps[id]?.downloadProgress = null;
        notify();
      }
    }

    Future<Map<Object?, Object?>> downloadFn(
      String id, {
      bool skipInstalls = false,
    }) async {
      bool willBeSilent = false;
      DownloadedApk? downloadedFile;
      DownloadedDir? downloadedDir;
      try {
        var downloadedArtifact =
            // ignore: use_build_context_synchronously
            await downloadApp(
              apps[id]!.app,
              context,
              notificationsProvider: notificationsProvider,
              useExisting: useExisting,
            );
        if (downloadedArtifact is DownloadedApk) {
          downloadedFile = downloadedArtifact;
        } else {
          downloadedDir = downloadedArtifact as DownloadedDir;
        }
        id = downloadedFile?.appId ?? downloadedDir!.appId;
        // Bridge the gap between download completion and install start so the
        // Dismissible stays disabled (see AppListTile).
        apps[id]?.downloadProgress = -1;
        notify();
        willBeSilent = await canInstallSilently(apps[id]!.app);
        if (!settingsProvider.useShizuku) {
          if (!(await settingsProvider.getInstallPermission(enforce: false))) {
            throw ObtainiumError(tr('cancelled'));
          }
        } else {
          switch ((await ShizukuApkInstaller().checkPermission())!) {
            case 'services_not_found':
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
        if (apps[id] != null) { apps[id]!.downloadProgress = null; notify(); }
      }
      return {
        'id': id,
        'willBeSilent': willBeSilent,
        'downloadedFile': downloadedFile,
        'downloadedDir': downloadedDir,
      };
    }

    List<Map<Object?, Object?>> downloadResults = [];
    if (forceParallelDownloads || !settingsProvider.parallelDownloads) {
      for (var id in appsToInstall) {
        downloadResults.add(await downloadFn(id));
      }
    } else {
      downloadResults = await Future.wait(
        appsToInstall.map((id) => downloadFn(id, skipInstalls: true)),
      );
    }
    for (var res in downloadResults) {
      if (!errors.appIdNames.containsKey(res['id'])) {
        try {
          await installFn(
            res['id'] as String,
            res['willBeSilent'] as bool,
            res['downloadedFile'] as DownloadedApk?,
            res['downloadedDir'] as DownloadedDir?,
          );
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
    List<String> appIds,
    BuildContext context, {
    bool forceParallelDownloads = false,
  }) async {
    NotificationsProvider notificationsProvider = context
        .read<NotificationsProvider>();
    List<MapEntry<MapEntry<String, String>, App>> filesToDownload = [];
    for (var id in appIds) {
      if (apps[id] == null) {
        throw ObtainiumError(tr('appNotFound'));
      }
      MapEntry<String, String>? fileUrl;
      var refreshBeforeDownload =
          apps[id]!.app.additionalSettings['refreshBeforeDownload'] == true ||
          apps[id]!.app.apkUrls.isNotEmpty &&
              apps[id]!.app.apkUrls.first.value == 'placeholder';
      if (refreshBeforeDownload) {
        await checkUpdate(apps[id]!.app.id);
      }
      if (apps[id]!.app.apkUrls.isNotEmpty ||
          apps[id]!.app.otherAssetUrls.isNotEmpty) {
        // ignore: use_build_context_synchronously
        MapEntry<String, String>? tempFileUrl = await confirmAppFileUrl(
          apps[id]!.app,
          // ignore: use_build_context_synchronously
          context,
          true,
          evenIfSingleChoice: true,
        );
        if (tempFileUrl != null) {
          var s = SourceProvider().getSource(
            apps[id]!.app.url,
            overrideSource: apps[id]!.app.overrideSource,
          );
          var additionalSettingsPlusSourceConfig = {
            ...apps[id]!.app.additionalSettings,
            ...(await s.getSourceConfigValues(
              apps[id]!.app.additionalSettings,
              settingsProvider,
            )),
          };
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
    MultiAppMultiError errors = MultiAppMultiError();
    List<String> downloadedIds = [];

    Future<void> downloadFn(MapEntry<String, String> fileUrl, App app) async {
      try {
        String downloadPath = '${await getStorageRootPath()}/Download';
        await downloadFile(
          fileUrl.value,
          fileUrl.key,
          true,
          (double? progress) {
            notificationsProvider.notify(
              DownloadNotification(fileUrl.key, progress?.ceil() ?? 0),
            );
          },
          downloadPath,
          headers: await SourceProvider()
              .getSource(app.url, overrideSource: app.overrideSource)
              .getRequestHeaders(
                app.additionalSettings,
                fileUrl.value,
                forAPKDownload: fileUrl.key.endsWith('.apk') ? true : false,
              ),
          useExisting: false,
          allowInsecure: app.additionalSettings['allowInsecure'] == true,
          logs: logs,
        );
        notificationsProvider.notify(
          DownloadedNotification(fileUrl.key, fileUrl.value),
        );
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
      await Future.wait(
        filesToDownload.map(
          (urlWithApp) => downloadFn(urlWithApp.key, urlWithApp.value),
        ),
      );
    }
    if (errors.idsByErrorString.isNotEmpty) {
      throw errors;
    }
    return downloadedIds;
  }
}
