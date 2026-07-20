import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/app_sources/fdroidrepo.dart';
import 'package:obtainium/app_sources/izzyondroid.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/layout_breakpoints.dart';
import 'package:obtainium/providers/apps_provider_import_export.dart';
import 'package:obtainium/providers/apps_provider_install.dart';
import 'package:obtainium/providers/apps_provider_updates.dart';
import 'package:obtainium/providers/source_provider.dart';

App _buildTestApp({
  required String id,
  String url = 'https://example.com/app',
  String author = 'Author',
  String name = 'Example App',
  String? installedVersion,
  String latestVersion = '1.0',
  List<MapEntry<String, String>> apkUrls = const [],
  int preferredApkIndex = 0,
  Map<String, dynamic> additionalSettings = const {},
  DateTime? lastUpdateCheck,
  bool pinned = false,
  List<String> categories = const [],
  DateTime? releaseDate,
  String? changeLog,
  String? overrideSource,
  String? iconUrl,
  int? apkSizeBytes,
  String? rawLatestVersionFromSource,
  String? latestReproducibleStatus,
  int? latestReproducibleVersionCode,
  String? latestAttestationStatus,
  String? latestMalwareScanStatus,
  String? latestMalwareScanDetail,
  String? latestMalwareScanReportUrl,
}) {
  return App(
    id: id,
    url: url,
    author: author,
    name: name,
    installedVersion: installedVersion,
    latestVersion: latestVersion,
    apkUrls: apkUrls,
    preferredApkIndex: preferredApkIndex,
    additionalSettings: additionalSettings,
    lastUpdateCheck: lastUpdateCheck,
    pinned: pinned,
    categories: categories,
    releaseDate: releaseDate,
    changeLog: changeLog,
    overrideSource: overrideSource,
    iconUrl: iconUrl,
    apkSizeBytes: apkSizeBytes,
    rawLatestVersionFromSource: rawLatestVersionFromSource,
    latestReproducibleStatus: latestReproducibleStatus,
    latestReproducibleVersionCode: latestReproducibleVersionCode,
    latestAttestationStatus: latestAttestationStatus,
    latestMalwareScanStatus: latestMalwareScanStatus,
    latestMalwareScanDetail: latestMalwareScanDetail,
    latestMalwareScanReportUrl: latestMalwareScanReportUrl,
  );
}

void main() {
  test('App.copyWith can explicitly clear nullable source metadata', () {
    final App app = _buildTestApp(
      id: 'copy',
      iconUrl: 'https://example.com/icon.png',
      apkSizeBytes: 123,
      latestReproducibleStatus: reproducibleBuildStatusVerified,
      latestReproducibleVersionCode: 31,
      latestAttestationStatus: githubAttestationStatusVerified,
      latestMalwareScanStatus: malwareScanStatusFlagged,
      latestMalwareScanDetail: 'Detected',
      latestMalwareScanReportUrl: 'https://example.com/report',
    );

    final App cleared = app.copyWith(
      iconUrl: null,
      apkSizeBytes: null,
      latestReproducibleStatus: null,
      latestReproducibleVersionCode: null,
      latestAttestationStatus: null,
      latestMalwareScanStatus: null,
      latestMalwareScanDetail: null,
      latestMalwareScanReportUrl: null,
    );

    expect(cleared.iconUrl, isNull);
    expect(cleared.apkSizeBytes, isNull);
    expect(cleared.latestReproducibleStatus, isNull);
    expect(cleared.latestReproducibleVersionCode, isNull);
    expect(cleared.latestAttestationStatus, isNull);
    expect(cleared.latestMalwareScanStatus, isNull);
    expect(cleared.latestMalwareScanDetail, isNull);
    expect(cleared.latestMalwareScanReportUrl, isNull);
  });

  test('fetched updates preserve concurrent live app state', () {
    final App requestedApp = _buildTestApp(
      id: 'merge',
      installedVersion: '1.0',
      apkUrls: const [MapEntry('old.apk', 'https://example.com/old.apk')],
      additionalSettings: const {'trackOnly': false},
      apkSizeBytes: 123,
    );
    final App liveApp = requestedApp.copyWith(
      installedVersion: '1.1',
      latestVersion: '2.0',
      pinned: true,
      categories: const ['Live category'],
      additionalSettings: const {
        'trackOnly': false,
        'skippedLatestVersion': '2.0',
      },
      latestMalwareScanStatus: malwareScanStatusFlagged,
      latestMalwareScanDetail: 'Detected while refresh was running',
      latestMalwareScanReportUrl: 'https://example.com/live-report',
    );
    final DateTime fetchedAt = DateTime.utc(2026, 7, 14);
    final App fetchedApp = _buildTestApp(
      id: 'merge',
      author: 'Updated author',
      name: 'Updated name',
      latestVersion: '2.0',
      apkUrls: const [MapEntry('new.apk', 'https://example.com/new.apk')],
      additionalSettings: requestedApp.additionalSettings,
      lastUpdateCheck: fetchedAt,
      changeLog: 'Changes',
      rawLatestVersionFromSource: 'v2.0',
      latestReproducibleStatus: reproducibleBuildStatusVerified,
      latestReproducibleVersionCode: 31,
      latestAttestationStatus: githubAttestationStatusVerified,
    );

    final App? merged = mergeFetchedUpdateWithLiveState(
      requestedApp: requestedApp,
      liveApp: liveApp,
      fetchedApp: fetchedApp,
    );

    expect(merged, isNotNull);
    expect(merged!.latestVersion, '2.0');
    expect(merged.author, 'Updated author');
    expect(merged.name, 'Updated name');
    expect(merged.apkUrls.single.key, 'new.apk');
    expect(merged.lastUpdateCheck, fetchedAt);
    expect(merged.apkSizeBytes, isNull);
    expect(merged.latestReproducibleVersionCode, 31);
    expect(merged.installedVersion, '1.1');
    expect(merged.pinned, isTrue);
    expect(merged.categories, const ['Live category']);
    expect(merged.additionalSettings['skippedLatestVersion'], '2.0');
    expect(merged.latestMalwareScanStatus, malwareScanStatusFlagged);
    expect(
      merged.latestMalwareScanDetail,
      'Detected while refresh was running',
    );
    expect(
      merged.latestMalwareScanReportUrl,
      'https://example.com/live-report',
    );
  });

  test('a newly discovered release clears stale malware scan metadata', () {
    final App requestedApp = _buildTestApp(
      id: 'new-release',
      latestMalwareScanStatus: malwareScanStatusFlagged,
      latestMalwareScanDetail: 'Old release detection',
      latestMalwareScanReportUrl: 'https://example.com/old-report',
    );
    final App fetchedApp = requestedApp.copyWith(latestVersion: '2.0');

    final App? merged = mergeFetchedUpdateWithLiveState(
      requestedApp: requestedApp,
      liveApp: requestedApp,
      fetchedApp: fetchedApp,
    );

    expect(merged, isNotNull);
    expect(merged!.latestMalwareScanStatus, isNull);
    expect(merged.latestMalwareScanDetail, isNull);
    expect(merged.latestMalwareScanReportUrl, isNull);
  });

  test('fetched update is discarded after URL or source changes', () {
    final App requestedApp = _buildTestApp(id: 'stale');
    final App fetchedApp = requestedApp.copyWith(latestVersion: '2.0');

    expect(
      mergeFetchedUpdateWithLiveState(
        requestedApp: requestedApp,
        liveApp: requestedApp.copyWith(url: 'https://example.com/moved'),
        fetchedApp: fetchedApp,
      ),
      isNull,
    );
    expect(
      mergeFetchedUpdateWithLiveState(
        requestedApp: requestedApp,
        liveApp: requestedApp.copyWith(overrideSource: 'HTML'),
        fetchedApp: fetchedApp,
      ),
      isNull,
    );
  });

  test('manual refresh IDs match the visible list surface', () {
    final List<App> apps = [
      _buildTestApp(id: 'main'),
      _buildTestApp(
        id: 'foldered',
        additionalSettings: const {
          'folderIds': ['folder'],
        },
      ),
      _buildTestApp(
        id: 'on-demand',
        additionalSettings: const {
          'onDemandOnly': true,
          'folderIds': ['folder'],
        },
      ),
    ];

    expect(
      appIdsForManualRefresh(
        apps: apps,
        onDemandOnlyList: false,
        folderId: null,
        showFolderedAppsOnMainPage: false,
        existingFolderIds: const {'folder'},
      ),
      const ['main'],
    );
    expect(
      appIdsForManualRefresh(
        apps: apps,
        onDemandOnlyList: false,
        folderId: null,
        showFolderedAppsOnMainPage: true,
        existingFolderIds: const {'folder'},
      ),
      const ['main', 'foldered'],
    );
    expect(
      appIdsForManualRefresh(
        apps: apps,
        onDemandOnlyList: false,
        folderId: 'folder',
        showFolderedAppsOnMainPage: false,
        existingFolderIds: const {'folder'},
      ),
      const ['foldered'],
    );
    expect(
      appIdsForManualRefresh(
        apps: apps,
        onDemandOnlyList: true,
        folderId: null,
        showFolderedAppsOnMainPage: false,
        existingFolderIds: const {'folder'},
      ),
      const ['on-demand'],
    );
  });

  test('only the stock installer is blocked for a downgrade', () {
    expect(
      isStockInstallerDowngrade(
        installedVersionCode: 10,
        newVersionCode: 9,
        installerModeKey: 'system',
      ),
      isTrue,
    );
    for (final String installerMode in ['shizuku', 'external']) {
      expect(
        isStockInstallerDowngrade(
          installedVersionCode: 10,
          newVersionCode: 9,
          installerModeKey: installerMode,
        ),
        isFalse,
      );
    }
    expect(
      isStockInstallerDowngrade(
        installedVersionCode: 10,
        newVersionCode: 10,
        installerModeKey: 'system',
      ),
      isFalse,
    );
    expect(
      isStockInstallerDowngrade(
        installedVersionCode: null,
        newVersionCode: 9,
        installerModeKey: 'system',
      ),
      isFalse,
    );
  });

  test('only HTTP download URLs require a cleartext warning', () {
    expect(isCleartextDownloadUrl('http://example.com/app.apk'), isTrue);
    expect(isCleartextDownloadUrl('HTTP://example.com/app.apk'), isTrue);
    expect(isCleartextDownloadUrl('https://example.com/app.apk'), isFalse);
    expect(
      isCleartextDownloadUrl('https://example.com/?next=http://insecure.test'),
      isFalse,
    );
  });

  test(
    'parallel downloads install as ready, serialize installs, and defer self-update',
    () async {
      final Completer<String> slowDownload = Completer<String>();
      final Completer<String> fastDownload = Completer<String>();
      final Completer<String> selfUpdateDownload = Completer<String>();
      final Completer<void> fastInstallStarted = Completer<void>();
      final Completer<void> releaseFastInstall = Completer<void>();
      final List<String> installOrder = [];
      var activeInstalls = 0;
      var maxActiveInstalls = 0;

      final Future<void> processing = processDownloadResultsAsReady<String>(
        downloads: [
          (id: 'slow', result: slowDownload.future),
          (id: 'fast', result: fastDownload.future),
          (id: 'self', result: selfUpdateDownload.future),
        ],
        deferUntilEnd: (String id) => id == 'self',
        process: (String result) async {
          activeInstalls++;
          if (activeInstalls > maxActiveInstalls) {
            maxActiveInstalls = activeInstalls;
          }
          installOrder.add(result);
          if (result == 'fast') {
            fastInstallStarted.complete();
            await releaseFastInstall.future;
          }
          activeInstalls--;
        },
      );

      selfUpdateDownload.complete('self');
      fastDownload.complete('fast');
      await fastInstallStarted.future;
      slowDownload.complete('slow');
      await Future<void>.delayed(Duration.zero);

      expect(installOrder, const ['fast']);
      expect(maxActiveInstalls, 1);

      releaseFastInstall.complete();
      await processing;

      expect(installOrder, const ['fast', 'slow', 'self']);
      expect(maxActiveInstalls, 1);
    },
  );

  test('F-Droid-style verification controls retain their help tooltip', () {
    for (final AppSource source in [FDroid(), FDroidRepo(), IzzyOnDroid()]) {
      final GeneratedFormSwitch verificationSwitch = source
          .additionalSourceAppSpecificSettingFormItems
          .expand((row) => row)
          .whereType<GeneratedFormSwitch>()
          .singleWhere((item) => item.key == 'enforceReproducibleBuilds');

      expect(
        verificationSwitch.labelTooltip,
        isNotEmpty,
        reason: '${source.name} must explain build verification enforcement',
      );
    }
  });

  test('settings-without-secrets excludes all known credential keys', () {
    expect(isSecretSettingKey('github-creds'), isTrue);
    expect(isSecretSettingKey('gitlab-creds'), isTrue);
    expect(isSecretSettingKey('virustotal-api-key'), isTrue);
    expect(
      isSecretSettingKey('virustotal-api-key-validated-fingerprint'),
      isTrue,
    );
    expect(isSecretSettingKey('updateInterval'), isFalse);
  });

  test('always-use-phone-layout overrides every breakpoint', () {
    expect(isLargeScreenLayout(800, Orientation.portrait), isTrue);
    expect(
      isLargeScreenLayout(
        800,
        Orientation.portrait,
        alwaysUsePhoneLayout: true,
      ),
      isFalse,
    );
    expect(
      isLargeScreenLayout(
        650,
        Orientation.landscape,
        alwaysUsePhoneLayout: true,
      ),
      isFalse,
    );
  });
}
