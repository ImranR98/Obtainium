import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';

import 'package:obtainium/custom_errors.dart';

import 'package:obtainium/folders/app_folder.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/providers/virustotal_provider.dart';
import 'package:shared_storage/shared_storage.dart' as saf;

/// Secret settings excluded from the "settings without secrets" backup mode.
/// Source credentials conventionally end in `-creds`; VirusTotal predates that
/// convention, so its key and otherwise-useless validation fingerprint are
/// listed explicitly.
bool isSecretSettingKey(String key) {
  return key.endsWith('-creds') ||
      key == virusTotalApiKeyKey ||
      key == virusTotalValidatedApiKeyFingerprintKey;
}

bool hasSecretsInSettingsMap(Map<String, dynamic>? settingsMap) {
  if (settingsMap == null || settingsMap.isEmpty) return false;
  return settingsMap.entries.any(
    (e) =>
        isSecretSettingKey(e.key) &&
        e.value != null &&
        e.value.toString().isNotEmpty,
  );
}

class BackupContent {
  final List<App> apps;
  final Map<String, dynamic>? settingsMap;
  final ExportSchema? schema;

  const BackupContent({required this.apps, this.settingsMap, this.schema});
}

/// Import/export of app configurations for [AppsProvider].
extension AppsProviderImportExport on AppsProvider {
  /// Builds an exportable JSON map containing app data and optionally settings.
  Map<String, dynamic> generateExportJSON({
    List<String>? appIds,
    int? overrideExportSettings,
    SettingsProvider? sp,
  }) {
    // Build from the caller-provided provider (the UI's instance) rather than
    // the extension getter, so the export reflects the intended settings
    // (parity with fork main).
    final SettingsProvider settingsProvider = sp ?? this.settingsProvider;
    final appList = apps.values
        .where((e) => appIds == null || appIds.contains(e.app.id))
        .map((e) {
          // Inject a folderId→name map so folder membership can be restored
          // (by name) on a device with different folder IDs. Mirrors fork main.
          final appJson = e.app.toJson();
          final Map<String, dynamic> additionalSettings =
              Map<String, dynamic>.from(
                jsonDecode(appJson['additionalSettings'] as String),
              );
          final List<dynamic>? folderIds =
              additionalSettings['folderIds'] as List?;
          if (folderIds != null && folderIds.isNotEmpty) {
            final Map<String, String> folderNames = {};
            final existingFolders = settingsProvider.appFolders;
            for (final folderId in folderIds) {
              for (final f in existingFolders) {
                if (f.id == folderId) {
                  folderNames[folderId as String] = f.name;
                  break;
                }
              }
            }
            additionalSettings['folderNames'] = folderNames;
            appJson['additionalSettings'] = jsonEncode(additionalSettings);
          }
          return appJson;
        })
        .toList();
    int shouldExportSettings = settingsProvider.exportSettings;
    if (overrideExportSettings != null) {
      shouldExportSettings = overrideExportSettings;
    }
    Map<String, dynamic>? settingsMap;
    Map<String, dynamic>? settingsObtainXMap;
    if (shouldExportSettings > 0) {
      final settingsValueKeys = settingsProvider.prefs?.getKeys().toSet();
      if (shouldExportSettings < 2) {
        settingsValueKeys?.removeWhere(isSecretSettingKey);
      }
      final Map<String, dynamic> fullSettings =
          Map<String, dynamic>.fromEntries(
            (settingsValueKeys
                    ?.map(
                      (key) => MapEntry(key, settingsProvider.prefs?.get(key)),
                    )
                    .toList()) ??
                [],
          );
      final SplitExportSettings splitSettings = splitSettingsForExport(
        fullSettings,
      );
      settingsMap = splitSettings.settings;
      settingsObtainXMap = splitSettings.settingsObtainX;
    }
    final schema = ExportSchema(
      schemaVersion: currentExportSchemaVersion,
      exportedAt: DateTime.now().toIso8601String(),
      appVersion: kPackageVersion,
      apps: appList,
      settings: settingsMap,
      settingsObtainX: settingsObtainXMap,
    );
    return schema.toJson();
  }

  /// Exports all app data (and optionally settings) as a JSON file to the configured export directory.
  Future<String?> export({
    bool pickOnly = false,
    isAuto = false,
    SettingsProvider? sp,
  }) async {
    final SettingsProvider settingsProvider = sp ?? this.settingsProvider;
    var exportDir = await settingsProvider.getExportDir(
      warnIfInaccessible: true,
    );
    if (isAuto) {
      if (!settingsProvider.autoExportOnChanges) {
        return null;
      }
      if (exportDir == null) {
        return null;
      }
      final files = await saf
          .listFiles(exportDir, columns: [saf.DocumentFileColumn.id])
          .where((f) => f.uri.pathSegments.last.endsWith('-auto.json'))
          .toList();
      if (files.isNotEmpty) {
        for (var f in files) {
          unawaited(saf.delete(f.uri));
        }
      }
    }
    if (exportDir == null || pickOnly) {
      await settingsProvider.pickExportDir();
      exportDir = await settingsProvider.getExportDir(warnIfInaccessible: true);
    }
    if (exportDir == null) {
      return null;
    }
    String? returnPath;
    if (!pickOnly) {
      const encoder = JsonEncoder.withIndent('    ');
      final Map<String, dynamic> finalExport = generateExportJSON(
        sp: settingsProvider,
      );
      final result = await saf.createFile(
        exportDir,
        displayName:
            '${tr('obtainiumExportHyphenatedLowercase')}-${DateTime.now().toIso8601String().replaceAll(':', '-')}${isAuto ? '-auto' : ''}.json',
        mimeType: 'application/json',
        bytes: Uint8List.fromList(utf8.encode(encoder.convert(finalExport))),
      );
      if (result == null) {
        throw ObtainiumError(tr('unexpectedError'));
      }
      returnPath = exportDir.pathSegments
          .join('/')
          .replaceFirst('tree/primary:', '/');
    }
    return returnPath;
  }

  /// Parses a backup JSON string into a [BackupContent] object.
  BackupContent parseBackupContent(String appsJSON) {
    dynamic decodedJSON;
    try {
      decodedJSON = jsonDecode(appsJSON);
    } catch (e) {
      throw ObtainiumError('${tr('failedToImport')}: ${e.toString()}');
    }
    final hasSchemaVersion =
        decodedJSON is Map && decodedJSON.containsKey('schemaVersion');
    List<App> importedApps;
    ExportSchema? schema;
    try {
      if (hasSchemaVersion) {
        schema = ExportSchema.fromJson(decodedJSON as Map<String, dynamic>);
        importedApps = schema.apps.map((e) => App.fromJson(e)).toList();
      } else {
        final newFormat = decodedJSON is! List;
        importedApps =
            ((newFormat ? decodedJSON['apps'] : decodedJSON) as List<dynamic>)
                .map((e) => App.fromJson(e))
                .toList();
      }
    } catch (e) {
      throw ObtainiumError('${tr('failedToImport')}: ${e.toString()}');
    }
    // Resolve settings: shared block plus optional ObtainX overlay.
    final Map<String, dynamic>? sharedSettings = hasSchemaVersion
        ? schema!.settings
        : (decodedJSON is Map
              ? decodedJSON['settings'] as Map<String, dynamic>?
              : null);
    final Map<String, dynamic>? settingsObtainXOverlay = hasSchemaVersion
        ? schema!.settingsObtainX
        : (decodedJSON is Map
              ? decodedJSON['settingsObtainX'] as Map<String, dynamic>?
              : null);
    final Map<String, dynamic>? settingsMap = mergeImportedSettingsMaps(
      sharedSettings,
      settingsObtainXOverlay,
    );
    return BackupContent(
      apps: importedApps,
      settingsMap: settingsMap,
      schema: schema,
    );
  }

  /// Imports apps (and optionally settings) from a JSON string, returning the parsed apps and a settings-present flag.
  Future<MapEntry<List<App>, bool>> import(
    String appsJSON, {
    Set<String>? selectedAppIds,
    bool importSettings = true,
  }) async {
    final backupContent = parseBackupContent(appsJSON);
    List<App> importedApps = backupContent.apps;
    final settingsMap = backupContent.settingsMap;

    if (selectedAppIds != null) {
      importedApps = importedApps
          .where((a) => selectedAppIds.contains(a.id))
          .toList();
    }

    // Merge backed-up folders into existing ones (by name) and remap each app's
    // folder references to the resolved IDs before saving.
    importedApps = _reconcileImportedFolders(
      importedApps,
      importSettings ? settingsMap : null,
    );

    await waitForAppsToLoad();
    for (var i = 0; i < importedApps.length; i++) {
      final a = importedApps[i];
      final installedInfo = await getInstalledInfo(a.id);
      importedApps[i] = a.copyWith(
        installedVersion: a.settings.getBool('useVersionCodeAsOSVersion')
            ? installedInfo?.versionCode.toString()
            : installedInfo?.versionName,
      );
    }
    await saveApps(importedApps, onlyIfExists: false);
    bool hasSettings = false;
    if (importSettings && settingsMap != null) {
      hasSettings = true;
      // 'appFolders' is skipped: already merged/persisted by
      // _reconcileImportedFolders. Reload settings so the merged folder list
      // (and everything else) is reflected in memory immediately.
      _applyImportedSettings(settingsMap, skipKeys: const {'appFolders'});
      await settingsProvider.initializeSettings();
    }
    return MapEntry<List<App>, bool>(importedApps, hasSettings);
  }

  /// Merges backed-up folders into the existing folder list (matching by name,
  /// creating only the missing ones), then returns [importedApps] with each
  /// app's folderIds / excludedFolderIds / folderNames remapped from backup IDs
  /// to the resolved target IDs. Mirrors fork main, adapted for the immutable
  /// [App] (copyWith instead of in-place mutation).
  List<App> _reconcileImportedFolders(
    List<App> importedApps,
    Map<String, dynamic>? settingsMap,
  ) {
    final List<AppFolder> existingFolders = List<AppFolder>.from(
      settingsProvider.appFolders,
    );
    final Map<String, String> backupIdToTargetId = {};
    final List<AppFolder> foldersToCreate = [];
    final Map<String, AppFolder> backupFolders = {};
    final Map<String, String> backupFolderIdToName = {};

    // Folders from the backup's own folder list.
    final dynamic backupFoldersRaw = settingsMap?['appFolders'];
    if (backupFoldersRaw is String) {
      try {
        final list = jsonDecode(backupFoldersRaw) as List<dynamic>;
        for (final e in list) {
          final folder = AppFolder.fromJson(e as Map<String, dynamic>);
          backupFolders[folder.id] = folder;
          backupFolderIdToName[folder.id] = folder.name;
        }
      } catch (_) {}
    }
    // Names carried on the apps themselves.
    for (final app in importedApps) {
      final Map<dynamic, dynamic>? appFolderNames =
          app.additionalSettings['folderNames'] as Map?;
      if (appFolderNames != null) {
        appFolderNames.forEach((key, val) {
          if (key is String && val is String) {
            backupFolderIdToName.putIfAbsent(key, () => val);
          }
        });
      }
    }

    // Match each backup folder to an existing one by name, else schedule it.
    backupFolderIdToName.forEach((backupId, name) {
      AppFolder? match;
      for (final f in existingFolders) {
        if (f.name.trim().toLowerCase() == name.trim().toLowerCase()) {
          match = f;
          break;
        }
      }
      if (match != null) {
        backupIdToTargetId[backupId] = match.id;
      } else {
        final AppFolder targetFolder =
            backupFolders[backupId] ?? AppFolder(id: backupId, name: name);
        foldersToCreate.add(targetFolder);
        backupIdToTargetId[backupId] = backupId;
      }
    });
    if (foldersToCreate.isNotEmpty) {
      existingFolders.addAll(foldersToCreate);
      settingsProvider.appFolders = existingFolders;
    }

    // Resolve a backup folder ID to its target ID, or null if it maps to no
    // known folder (drop the reference in that case).
    String? resolveId(String id) {
      final targetId = backupIdToTargetId[id];
      if (targetId != null) return targetId;
      if (existingFolders.any((f) => f.id == id)) return id;
      return null;
    }

    // Remap each app's folder references onto a fresh additionalSettings map.
    return importedApps.map((app) {
      final folderIds = folderIdsForApp(app);
      // Read the legacy exclusion list raw (not the merged view) so remapping
      // doesn't duplicate override-derived excludes into it — overrides are
      // remapped separately below.
      final rawExcluded = app.additionalSettings['excludedFolderIds'];
      final excludedIds = rawExcluded is List
          ? List<String>.from(rawExcluded)
          : const <String>[];
      final overridesRaw = app.additionalSettings['folderOverrides'];
      final hasOverrides = overridesRaw is Map && overridesRaw.isNotEmpty;
      if (folderIds.isEmpty && excludedIds.isEmpty && !hasOverrides) {
        return app;
      }
      final Map<String, dynamic> updated = Map<String, dynamic>.from(
        app.additionalSettings,
      );
      final Map<String, dynamic> updatedFolderNames = {};
      if (folderIds.isNotEmpty) {
        final List<String> updatedFolderIds = [];
        for (final id in folderIds) {
          final String? targetId = resolveId(id);
          if (targetId == null) continue;
          updatedFolderIds.add(targetId);
          final String folderName =
              backupFolderIdToName[id] ??
              existingFolders.firstWhere((f) => f.id == targetId).name;
          updatedFolderNames[targetId] = folderName;
        }
        updated['folderIds'] = updatedFolderIds;
      }
      if (excludedIds.isNotEmpty) {
        final List<String> updatedExcludedIds = [];
        for (final id in excludedIds) {
          final String? targetId = resolveId(id);
          if (targetId != null) updatedExcludedIds.add(targetId);
        }
        updated['excludedFolderIds'] = updatedExcludedIds;
      }
      // Remap the membership overrides (Always include / Always exclude) so
      // they survive folder-ID remapping instead of being silently lost.
      if (hasOverrides) {
        final Map<String, dynamic> updatedOverrides = {};
        overridesRaw.forEach((key, value) {
          final String? targetId = resolveId(key.toString());
          if (targetId != null) updatedOverrides[targetId] = value;
        });
        updated['folderOverrides'] = updatedOverrides;
      }
      updated['folderNames'] = updatedFolderNames;
      return app.copyWith(additionalSettings: updated);
    }).toList();
  }

  void _applyImportedSettings(
    Map<String, dynamic> settingsMap, {
    Set<String> skipKeys = const {},
  }) {
    settingsMap.forEach((key, value) {
      if (skipKeys.contains(key)) return;
      if (value is int) {
        settingsProvider.prefs?.setInt(key, value);
      } else if (value is double) {
        settingsProvider.prefs?.setDouble(key, value);
      } else if (value is bool) {
        settingsProvider.prefs?.setBool(key, value);
      } else if (value is List) {
        settingsProvider.prefs?.setStringList(
          key,
          value.whereType<String>().toList(),
        );
      } else if (value is String) {
        settingsProvider.setSettingString(key, value);
      }
    });
  }
}

const int obtainiumSortColumnCount = 4;
const String obtainXFolderViewSettingPrefix = 'folderView_';
const String obtainXSettingsSectionPrefix = 'settingsSection_';

/// Pref keys with no counterpart in upstream Obtainium. They're kept out of
/// [SplitExportSettings.settings] (so an Obtainium import isn't polluted by keys
/// it can never use) and carried in [SplitExportSettings.settingsObtainX]
/// instead. Every other pref goes in [settings], matching Obtainium's own backup
/// format so Obtainium restores it directly.
///
/// Notably absent: grouping (`groupBy`) and the installer (`installMethod`).
/// ObtainX now persists both under upstream's own keys/values, so they are plain
/// shared settings — no translation, no overlay.
const Set<String> obtainXOnlySettingKeys = {
  'appFolders',
  'appAccentColorSource',
  'activeCustomSeedHex',
  'savedCustomSeedHexList',
  'appThemePaletteStyle',
  'progressiveBlurEnabled',
  'progressiveBlurDefaultMigrated',
  'reduceVisualEffects',
  'useGradientBackground',
  'shadingIntensity',
  'appUiScale',
  'cardCornerScale',
  'matchAppPageToIconColors',
  'showAppTypeBadge',
  'showTrackedStoreBadge',
  'showCategoriesBadge',
  'saveDownloadedApkCopies',
  'apkSaveDir',
  'rightSwipeAction',
  'leftSwipeAction',
  'rightSwipeActionName',
  'leftSwipeActionName',
  'swipeActionEnumVersion',
  'enableVirusTotalScanning',
  'githubValidatedPATFingerprint',
  'openAppInfoInAppManager',
  'folderCriteriaMigrationVersion',
  'collapsedGroups',
  'showFolderedAppsOnMainPage',
  'groupNonInstalledSeparately',
  'groupTrackOnlySeparately',
  'groupUpdatesSeparately',
  'enableLetMeDowngrade',
  'lastCompletedBGCheckTime',
  'showDebugOpts',
  'useFGService',
  'hideBatteryOptimizationWarning',
};

bool isObtainXOnlySettingKey(String key) {
  return obtainXOnlySettingKeys.contains(key) ||
      key.startsWith(obtainXFolderViewSettingPrefix) ||
      key.startsWith(obtainXSettingsSectionPrefix);
}

class SplitExportSettings {
  const SplitExportSettings({required this.settings, this.settingsObtainX});

  final Map<String, dynamic> settings;
  final Map<String, dynamic>? settingsObtainX;
}

/// Builds the Obtainium-facing [settings] block: every pref except ObtainX-only
/// keys, with the one value ObtainX can encode out of Obtainium's range
/// (`sortColumn`) sanitized. Shared keys (`groupBy`, `installMethod`, …) are
/// already Obtainium-compatible thanks to the settings convergence, so they pass
/// through verbatim.
Map<String, dynamic> buildObtainiumSettingsMap(
  Map<String, dynamic> fullSettings,
) {
  final Map<String, dynamic> settings = <String, dynamic>{};

  fullSettings.forEach((String key, dynamic value) {
    if (!isObtainXOnlySettingKey(key)) {
      settings[key] = value;
    }
  });

  sanitizeExportedSettingsForObtainium(settings);
  return settings;
}

/// Builds the ObtainX-only overlay: keys Obtainium can't use, plus the original
/// value of any setting [buildObtainiumSettingsMap] had to sanitize (so an
/// ObtainX self-import restores it exactly).
Map<String, dynamic> buildObtainXSettingsMap(
  Map<String, dynamic> fullSettings,
  Map<String, dynamic> obtainiumSettings,
) {
  final Map<String, dynamic> settingsObtainX = <String, dynamic>{};

  fullSettings.forEach((String key, dynamic value) {
    if (isObtainXOnlySettingKey(key)) {
      settingsObtainX[key] = value;
    }
  });

  // `sortColumn` is the only shared key ObtainX can set out of Obtainium's range
  // (its lastUpdateCheck = index 4). The shared block sanitized it; keep the real
  // value here so ObtainX's own import overrides the sanitized one.
  final dynamic fullSortColumn = fullSettings['sortColumn'];
  if (fullSortColumn != null &&
      fullSortColumn != obtainiumSettings['sortColumn']) {
    settingsObtainX['sortColumn'] = fullSortColumn;
  }

  return settingsObtainX;
}

/// Splits live prefs into a shared Obtainium-safe block and an ObtainX overlay.
SplitExportSettings splitSettingsForExport(Map<String, dynamic> fullSettings) {
  final Map<String, dynamic> settings = buildObtainiumSettingsMap(fullSettings);
  final Map<String, dynamic> settingsObtainX = buildObtainXSettingsMap(
    fullSettings,
    settings,
  );

  return SplitExportSettings(
    settings: settings,
    settingsObtainX: settingsObtainX.isEmpty ? null : settingsObtainX,
  );
}

/// Merges the shared settings block with the ObtainX overlay on import. The
/// overlay wins on conflicts (e.g. the real `sortColumn` over the sanitized one).
Map<String, dynamic>? mergeImportedSettingsMaps(
  Map<String, dynamic>? sharedSettings,
  Map<String, dynamic>? settingsObtainX,
) {
  if (sharedSettings == null) {
    return null;
  }
  if (settingsObtainX == null || settingsObtainX.isEmpty) {
    return Map<String, dynamic>.from(sharedSettings);
  }
  return <String, dynamic>{...sharedSettings, ...settingsObtainX};
}

/// Obtainium reads `sortColumn` as an unchecked index into its 4-value
/// [SortColumnSettings]. ObtainX adds a 5th value
/// ([SortColumnSettings.lastUpdateCheck], index 4), which would crash
/// Obtainium's home screen on import — so clamp any out-of-range index to a safe
/// default in the shared block. (`groupBy` needs no such handling: Obtainium
/// tolerates unknown group values, falling back to none.)
void sanitizeExportedSettingsForObtainium(Map<String, dynamic> settings) {
  final dynamic sortColumn = settings['sortColumn'];
  if (sortColumn is int &&
      (sortColumn < 0 || sortColumn >= obtainiumSortColumnCount)) {
    settings['sortColumn'] = SortColumnSettings.releaseDate.index;
  }
}

const int currentExportSchemaVersion = 2;
const String kPackageVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.0.0',
);

class ExportSchema {
  final int schemaVersion;
  final String exportedAt;
  final String appVersion;
  final List<Map<String, dynamic>> apps;
  final Map<String, dynamic>? settings;
  final Map<String, dynamic>? settingsObtainX;

  ExportSchema({
    required this.schemaVersion,
    required this.exportedAt,
    required this.appVersion,
    required this.apps,
    this.settings,
    this.settingsObtainX,
  });

  factory ExportSchema.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'] as int? ?? 1;
    if (schemaVersion > currentExportSchemaVersion) {
      throw FormatException(
        tr(
          'backupCreatedByNewerVersion',
          args: [
            schemaVersion.toString(),
            currentExportSchemaVersion.toString(),
          ],
        ),
      );
    }
    return ExportSchema(
      schemaVersion: schemaVersion,
      exportedAt: json['exportedAt'] as String? ?? '',
      appVersion: json['appVersion'] as String? ?? '',
      apps:
          (json['apps'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      settings: json['settings'] as Map<String, dynamic>?,
      settingsObtainX: json['settingsObtainX'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'schemaVersion': currentExportSchemaVersion,
      'exportedAt': exportedAt,
      'appVersion': appVersion,
      'apps': apps,
      'settings': settings,
    };
    if (settingsObtainX != null && settingsObtainX!.isNotEmpty) {
      json['settingsObtainX'] = settingsObtainX;
    }
    return json;
  }
}
