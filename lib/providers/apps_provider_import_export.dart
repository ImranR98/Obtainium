import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';

import 'package:obtainium/custom_errors.dart';

import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/revanced/keystore_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:shared_storage/shared_storage.dart' as saf;

/// Import/export of app configurations for [AppsProvider].
extension AppsProviderImportExport on AppsProvider {
  /// Builds an exportable JSON map containing app data and optionally settings.
  ///
  /// Per-app patch configuration rides along automatically since it lives in
  /// [App.additionalSettings], which is already part of [App.toJson]. The
  /// keystore used to sign patched APKs is a separate, larger, binary secret,
  /// so it's only bundled when [keystoreProvider] is supplied AND the
  /// resolved settings level is exactly "all" (2) - not "none" or "exclude
  /// secrets" - matching how "-creds" settings are already gated.
  Future<Map<String, dynamic>> generateExportJSON({
    List<String>? appIds,
    int? overrideExportSettings,
    KeystoreProvider? keystoreProvider,
  }) async {
    final appList = apps.values
        .where((e) => appIds == null || appIds.contains(e.app.id))
        .map((e) => e.app.toJson())
        .toList();
    int shouldExportSettings = settingsProvider.exportSettings;
    if (overrideExportSettings != null) {
      shouldExportSettings = overrideExportSettings;
    }
    Map<String, dynamic>? settingsMap;
    if (shouldExportSettings > 0) {
      final settingsValueKeys = settingsProvider.prefs?.getKeys().toSet();
      if (shouldExportSettings < 2) {
        settingsValueKeys?.removeWhere((k) => k.endsWith('-creds'));
      }
      settingsMap = Map<String, Object?>.fromEntries(
        (settingsValueKeys
                ?.map((key) => MapEntry(key, settingsProvider.prefs?.get(key)))
                .toList()) ??
            [],
      );
    }
    String? keystoreBase64;
    if (shouldExportSettings == 2 && keystoreProvider != null) {
      final bytes = await keystoreProvider.exportToBytes();
      if (bytes != null) {
        keystoreBase64 = base64Encode(bytes);
      }
    }
    final schema = ExportSchema(
      schemaVersion: currentExportSchemaVersion,
      exportedAt: DateTime.now().toIso8601String(),
      appVersion: kPackageVersion,
      apps: appList,
      settings: settingsMap,
      keystoreBase64: keystoreBase64,
    );
    return schema.toJson();
  }

  /// Exports all app data (and optionally settings) as a JSON file to the configured export directory.
  Future<String?> export({
    bool pickOnly = false,
    isAuto = false,
    SettingsProvider? sp,
    KeystoreProvider? keystoreProvider,
  }) async {
    final SettingsProvider settingsProvider = sp ?? this.settingsProvider;
    var exportDir = await settingsProvider.getExportDir();
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
      exportDir = await settingsProvider.getExportDir();
    }
    if (exportDir == null) {
      return null;
    }
    String? returnPath;
    if (!pickOnly) {
      const encoder = JsonEncoder.withIndent('    ');
      final Map<String, dynamic> finalExport = await generateExportJSON(
        keystoreProvider: keystoreProvider,
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
  ///
  /// If the export contains a bundled keystore, [confirmKeystoreImport] is
  /// called to ask the user before it's imported (replacing any existing
  /// keystore) - it must not happen silently. If [confirmKeystoreImport] is
  /// omitted, any bundled keystore is ignored.
  Future<MapEntry<List<App>, bool>> import(
    String appsJSON, {
    KeystoreProvider? keystoreProvider,
    Future<bool> Function()? confirmKeystoreImport,
  }) async {
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
    if (hasSchemaVersion && schema != null) {
      if (schema.settings != null) {
        hasSettings = true;
        _applyImportedSettings(schema.settings!);
      }
    } else if (decodedJSON is! List && decodedJSON['settings'] != null) {
      hasSettings = true;
      _applyImportedSettings(decodedJSON['settings'] as Map<String, Object?>);
    }
    if (schema?.keystoreBase64 != null &&
        keystoreProvider != null &&
        confirmKeystoreImport != null &&
        await confirmKeystoreImport()) {
      final bytes = base64Decode(schema!.keystoreBase64!);
      await keystoreProvider.importFromBytes(
        Uint8List.fromList(bytes),
        alias: keystoreProvider.alias,
        password: keystoreProvider.password,
      );
    }
    return MapEntry<List<App>, bool>(importedApps, hasSettings);
  }

  void _applyImportedSettings(Map<String, dynamic> settingsMap) {
    settingsMap.forEach((key, value) {
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

// Bumped from 2 to 3 for the additive `keystoreBase64` field. Purely additive,
// but keeping the version bumped means the "newer schema than this Obtainium
// supports" guard below stays meaningful.
const int currentExportSchemaVersion = 3;
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
  // Only present when settings were exported at the "all" level - the
  // signing keystore used for ReVanced-patched apps, base64-encoded. Kept
  // inline in the JSON rather than as a companion file since the export is
  // already a single SAF-picked JSON document and a keystore is only a few KB.
  final String? keystoreBase64;

  ExportSchema({
    required this.schemaVersion,
    required this.exportedAt,
    required this.appVersion,
    required this.apps,
    this.settings,
    this.keystoreBase64,
  });

  factory ExportSchema.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'] as int? ?? 1;
    if (schemaVersion > currentExportSchemaVersion) {
      throw FormatException(
        'Export was created by a newer version of Obtainium '
        '(schema v$schemaVersion, current is v$currentExportSchemaVersion). '
        'Please update Obtainium to import this file.',
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
      keystoreBase64: json['keystoreBase64'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': currentExportSchemaVersion,
    'exportedAt': exportedAt,
    'appVersion': appVersion,
    'apps': apps,
    'settings': settings,
    if (keystoreBase64 != null) 'keystoreBase64': keystoreBase64,
  };
}
