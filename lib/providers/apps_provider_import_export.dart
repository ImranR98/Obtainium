import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';

import 'package:obtainium/custom_errors.dart';

import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:shared_storage/shared_storage.dart' as saf;

/// Settings keys that may be applied from an imported backup. Anything else
/// is ignored, so a crafted backup cannot hijack behavior: credentials
/// (`-creds`), the external installer identity (`externalInstallerPackage` /
/// `externalInstallerComponent`), device-specific state (`exportDir`) and
/// onboarding flags are deliberately excluded.
const Set<String> importableSettingsKeys = {
  'actionBannerMode',
  'alwaysUsePhoneLayout',
  'autoExportOnChanges',
  'beforeNewInstallsShareToAppVerifier',
  'bgUpdatesOnWiFiOnly',
  'bgUpdatesWhileChargingOnly',
  'buryNonInstalled',
  'categories',
  'checkOnStart',
  'checkUpdateOnDetailPage',
  'colourSchemeMode',
  'disableSwipeActions',
  'enableBackgroundUpdates',
  'exportInstalledOnly',
  'exportSettings',
  'forcedLocale',
  'groupBy',
  'groupByCategory',
  'hideAPKOriginWarning',
  'hideDowngrades',
  'hideTrackOnlyWarning',
  'highlightTouchTargets',
  'includePrereleasesByDefault',
  'installMethod',
  'onlyCheckInstalledOrTrackOnlyApps',
  'parallelDownloads',
  'pinUpdates',
  'removeOnExternalUninstall',
  'searchDeselected',
  'shizukuPretendToBeGooglePlay',
  'showActionBannerForUpdateOnly',
  'showAppDowngradeError',
  'showAppWebpage',
  'sortColumn',
  'sortOrder',
  'tactileFeedbackEnabled',
  'theme',
  'themeColor',
  'updateInterval',
  'updateIntervalSliderVal',
  'useBlackTheme',
  'useMaterialYou',
  'useShizuku',
  'useSystemFont',
};

/// additionalSettings keys (per app) that hold regular expressions.
const List<String> regexSettingKeys = [
  'versionExtractionRegEx',
  'apkFilterRegEx',
  'customLinkFilterRegex',
];

/// Best-effort ReDoS guard: compiles the pattern and times it against short
/// adversarial probes. Catastrophic-backtracking patterns blow their time
/// budget even on tiny inputs, while safe patterns answer in microseconds.
bool isRegExSafe(String pattern) {
  final RegExp re;
  try {
    re = RegExp(pattern);
  } catch (_) {
    return false;
  }
  const probes = [
    'aaaaaaaaaaaaaaaaaaaaaa!',
    'ababababababababababab!',
    'https://example.com/releases/download/v1.2.3/app-release.apk',
  ];
  final sw = Stopwatch()..start();
  for (final probe in probes) {
    re.hasMatch(probe);
    if (sw.elapsedMilliseconds > 250) {
      return false;
    }
  }
  return true;
}

/// Returns a copy of [additionalSettings] with unsafe regex values removed,
/// or null if nothing needed changing.
Map<String, dynamic>? withoutUnsafeRegexes(
  Map<String, dynamic> additionalSettings,
) {
  var changed = false;
  final cleaned = Map<String, dynamic>.from(additionalSettings);
  for (final key in regexSettingKeys) {
    final value = cleaned[key];
    if (value is String && value.isNotEmpty && !isRegExSafe(value)) {
      cleaned.remove(key);
      changed = true;
    }
  }
  final intermediate = cleaned['intermediateLink'];
  if (intermediate is List) {
    for (final item in intermediate) {
      if (item is Map) {
        final value = item['customLinkFilterRegex'];
        if (value is String && value.isNotEmpty && !isRegExSafe(value)) {
          item['customLinkFilterRegex'] = '';
          changed = true;
        }
      }
    }
  }
  return changed ? cleaned : null;
}

/// Whether [additionalSettings] contains at least one unsafe regex.
bool hasUnsafeRegex(Map<String, dynamic> additionalSettings) =>
    withoutUnsafeRegexes(additionalSettings) != null;

/// Import/export of app configurations for [AppsProvider].
extension AppsProviderImportExport on AppsProvider {
  /// Builds an exportable JSON map containing app data and optionally settings.
  Map<String, dynamic> generateExportJSON({
    List<String>? appIds,
    int? overrideExportSettings,
  }) {
    final appList = apps.values
        .where((e) => appIds == null || appIds.contains(e.app.id))
        .where((e) => !settingsProvider.exportInstalledOnly ||
            e.app.installedVersion != null)
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
      final Map<String, dynamic> finalExport = generateExportJSON();
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
    // Strip potentially unsafe (ReDoS-prone) regexes from imported configs —
    // they would otherwise run on every update check.
    var strippedUnsafe = false;
    for (var i = 0; i < importedApps.length; i++) {
      final cleaned = withoutUnsafeRegexes(importedApps[i].additionalSettings);
      if (cleaned != null) {
        importedApps[i] = importedApps[i].copyWith(
          additionalSettings: cleaned,
        );
        strippedUnsafe = true;
      }
    }
    if (strippedUnsafe) {
      unawaited(
        LogsProvider().add(
          'Stripped potentially unsafe regular expressions from imported apps',
          level: LogLevel.warning,
        ),
      );
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
    return MapEntry<List<App>, bool>(importedApps, hasSettings);
  }

  /// Returns human-readable warnings about an import payload: existing apps
  /// that would be overwritten (with URL changes) and security-relevant
  /// content (cleartext HTTP URLs, insecure per-app settings, unsafe
  /// regexes). Best-effort: unparseable entries are skipped.
  Future<List<String>> getImportWarnings(String appsJSON) async {
    final warnings = <String>[];
    dynamic decoded;
    try {
      decoded = jsonDecode(appsJSON);
    } catch (_) {
      return warnings;
    }
    final appsList = decoded is List
        ? decoded
        : (decoded is Map ? decoded['apps'] : null);
    if (appsList is! List) return warnings;
    for (final e in appsList) {
      if (e is! Map) continue;
      final entry = Map<String, dynamic>.from(e);
      // Tolerate both additionalSettings shapes (string or map).
      if (entry['additionalSettings'] is Map) {
        entry['additionalSettings'] = jsonEncode(entry['additionalSettings']);
      }
      final App app;
      try {
        app = App.fromJson(entry);
      } catch (_) {
        continue;
      }
      final existing = apps[app.id];
      if (existing != null) {
        warnings.add(
          existing.app.url != app.url
              ? tr(
                  'importWarningOverwriteUrl',
                  args: [app.id, existing.app.url, app.url],
                )
              : tr('importWarningOverwrite', args: [app.id]),
        );
      }
      if (app.url.toLowerCase().startsWith('http://')) {
        warnings.add(tr('importWarningHttp', args: [app.id]));
      }
      if (app.settings.getBool('allowInsecure')) {
        warnings.add(tr('importWarningAllowInsecure', args: [app.id]));
      }
      if (hasUnsafeRegex(app.additionalSettings)) {
        warnings.add(tr('importWarningUnsafeRegex', args: [app.id]));
      }
    }
    return warnings;
  }

  void _applyImportedSettings(Map<String, dynamic> settingsMap) {
    settingsMap.forEach((key, value) {
      if (!importableSettingsKeys.contains(key)) {
        unawaited(
          LogsProvider().add(
            'Ignored setting on import (not allowlisted): $key',
            level: LogLevel.warning,
          ),
        );
        return;
      }
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
