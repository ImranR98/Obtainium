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
    if (shouldExportSettings > 0) {
      final settingsValueKeys = settingsProvider.prefs?.getKeys().toSet();
      if (shouldExportSettings < 2) {
        settingsValueKeys?.removeWhere(isSecretSettingKey);
      }
      settingsMap = Map<String, Object?>.fromEntries(
        (settingsValueKeys
                ?.map((key) => MapEntry(key, settingsProvider.prefs?.get(key)))
                .toList()) ??
            [],
      );
    }
    final schema = ExportSchema(
      schemaVersion: currentExportSchemaVersion,
      exportedAt: DateTime.now().toIso8601String(),
      appVersion: kPackageVersion,
      apps: appList,
      settings: settingsMap,
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

  /// Imports apps (and optionally settings) from a JSON string, returning the parsed apps and a settings-present flag.
  Future<MapEntry<List<App>, bool>> import(String appsJSON) async {
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
    // Resolve the settings map (schema wrapper or legacy top-level 'settings').
    final Map<String, dynamic>? settingsMap = hasSchemaVersion
        ? schema!.settings
        : (decodedJSON is Map
              ? decodedJSON['settings'] as Map<String, dynamic>?
              : null);

    // Merge backed-up folders into existing ones (by name) and remap each app's
    // folder references to the resolved IDs before saving.
    importedApps = _reconcileImportedFolders(importedApps, settingsMap);

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
    if (settingsMap != null) {
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
    final Map<String, String> backupFolderIdToName = {};

    // Names from the backup's own folder list.
    final dynamic backupFoldersRaw = settingsMap?['appFolders'];
    if (backupFoldersRaw is String) {
      try {
        final list = jsonDecode(backupFoldersRaw) as List<dynamic>;
        for (final e in list) {
          final folder = AppFolder.fromJson(e as Map<String, dynamic>);
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
        foldersToCreate.add(AppFolder(id: backupId, name: name));
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

  ExportSchema({
    required this.schemaVersion,
    required this.exportedAt,
    required this.appVersion,
    required this.apps,
    this.settings,
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
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': currentExportSchemaVersion,
    'exportedAt': exportedAt,
    'appVersion': appVersion,
    'apps': apps,
    'settings': settings,
  };
}
