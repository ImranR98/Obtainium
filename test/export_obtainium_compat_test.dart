import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/apps_provider_import_export.dart';
import 'package:obtainium/providers/settings_provider.dart';

void main() {
  // ── sortColumn is the one shared key ObtainX can set out of Obtainium's
  // range (its 5th value, lastUpdateCheck = index 4). It must be sanitized in
  // the shared block and preserved in the overlay for an ObtainX self-import.
  test(
    'sortColumn 4 is sanitized in settings and preserved in settingsObtainX',
    () {
      final SplitExportSettings split =
          splitSettingsForExport(<String, dynamic>{
            'sortColumn': SortColumnSettings.lastUpdateCheck.index,
            'theme': ThemeSettings.dark.index,
          });

      expect(
        split.settings['sortColumn'],
        SortColumnSettings.releaseDate.index,
      );
      expect(
        split.settingsObtainX?['sortColumn'],
        SortColumnSettings.lastUpdateCheck.index,
      );
      expect(split.settings['theme'], ThemeSettings.dark.index);
      expect(split.settingsObtainX?.containsKey('theme'), isFalse);
    },
  );

  test('safe sortColumn stays only in settings', () {
    final SplitExportSettings split = splitSettingsForExport(<String, dynamic>{
      'sortColumn': SortColumnSettings.nameAuthor.index,
    });

    expect(split.settings['sortColumn'], SortColumnSettings.nameAuthor.index);
    expect(split.settingsObtainX?.containsKey('sortColumn'), isNot(true));
  });

  // ── Convergence: grouping and installer are now stored under upstream's own
  // keys/values, so they pass through to the shared block verbatim — no mapping,
  // no overlay. Obtainium reads them directly.
  test('groupBy passes through to shared settings unchanged', () {
    final SplitExportSettings split = splitSettingsForExport(<String, dynamic>{
      'groupBy': AppsListGroupBy.source.name,
    });

    expect(split.settings['groupBy'], AppsListGroupBy.source.name);
    expect(split.settingsObtainX?.containsKey('groupBy'), isNot(true));
  });

  test('installMethod passes through to shared settings unchanged', () {
    final SplitExportSettings split = splitSettingsForExport(<String, dynamic>{
      'installMethod': InstallerMode.external.name,
    });

    expect(split.settings['installMethod'], InstallerMode.external.name);
    expect(split.settingsObtainX?.containsKey('installMethod'), isNot(true));
  });

  test(
    'groupBy appType stays verbatim in shared settings (Obtainium tolerates it)',
    () {
      // ObtainX's extra grouping value has no Obtainium equivalent, but Obtainium's
      // groupBy getter falls back to none for unknown values, so it need not be
      // stripped — and keeping it lets an ObtainX self-import restore it exactly.
      final SplitExportSettings split = splitSettingsForExport(
        <String, dynamic>{'groupBy': AppsListGroupBy.appType.name},
      );

      expect(split.settings['groupBy'], AppsListGroupBy.appType.name);
      expect(split.settingsObtainX?.containsKey('groupBy'), isNot(true));
    },
  );

  test('ObtainX-only keys stay out of shared settings', () {
    final SplitExportSettings split = splitSettingsForExport(<String, dynamic>{
      'appFolders': '[]',
      'appAccentColorSource': 'custom',
      'folderView_abc': jsonEncode(<String, dynamic>{'sortColumn': 4}),
      'collapsedGroups': <String>['src:GitHub'],
      'settingsSection_themes': true,
      'groupNonInstalledSeparately': true,
      'enableVirusTotalScanning': true,
      'hideBatteryOptimizationWarning': true,
      // Converged shared keys — must NOT be treated as ObtainX-only.
      'installMethod': InstallerMode.external.name,
      'groupBy': AppsListGroupBy.category.name,
      'buryNonInstalled': true,
      'checkUpdateOnDetailPage': false,
      'theme': ThemeSettings.light.index,
    });

    expect(split.settings.containsKey('appFolders'), isFalse);
    expect(split.settings.containsKey('collapsedGroups'), isFalse);
    expect(split.settings.containsKey('settingsSection_themes'), isFalse);
    expect(split.settings.containsKey('groupNonInstalledSeparately'), isFalse);
    expect(split.settings.containsKey('enableVirusTotalScanning'), isFalse);
    expect(
      split.settings.containsKey('hideBatteryOptimizationWarning'),
      isFalse,
    );
    expect(split.settingsObtainX?['hideBatteryOptimizationWarning'], isTrue);
    expect(split.settings['installMethod'], InstallerMode.external.name);
    expect(split.settings['groupBy'], AppsListGroupBy.category.name);
    expect(split.settings['buryNonInstalled'], isTrue);
    expect(split.settings['checkUpdateOnDetailPage'], isFalse);
    expect(split.settingsObtainX?['appFolders'], '[]');
    expect(split.settingsObtainX?['collapsedGroups'], <String>['src:GitHub']);
    expect(split.settings['theme'], ThemeSettings.light.index);
  });

  test('shared (non-ObtainX-only) keys stay in settings, not the overlay', () {
    // Keys without an ObtainX-only classification go to the shared block so
    // Obtainium restores the ones it recognizes; none leak into the overlay.
    final SplitExportSettings split = splitSettingsForExport(<String, dynamic>{
      'checkUpdateOnDetailPage': true,
      'buryNonInstalled': true,
    });

    expect(split.settings['checkUpdateOnDetailPage'], isTrue);
    expect(split.settings['buryNonInstalled'], isTrue);
    expect(
      split.settingsObtainX?.containsKey('checkUpdateOnDetailPage'),
      isNot(true),
    );
    expect(split.settingsObtainX?.containsKey('buryNonInstalled'), isNot(true));
  });

  test('settings includes most prefs like Obtainium export', () {
    final Map<String, dynamic> fullSettings = <String, dynamic>{
      for (int index = 0; index < 80; index++) 'pref_$index': index,
      'theme': ThemeSettings.dark.index,
      'groupBy': AppsListGroupBy.source.name,
      'appFolders': '[]',
    };
    final SplitExportSettings split = splitSettingsForExport(fullSettings);

    expect(split.settings.length, greaterThan(70));
    expect(split.settings['groupBy'], AppsListGroupBy.source.name);
    expect(split.settingsObtainX?['appFolders'], '[]');
  });

  test('mergeImportedSettingsMaps overlays ObtainX settings on import', () {
    final Map<String, dynamic>? merged = mergeImportedSettingsMaps(
      <String, dynamic>{
        'sortColumn': SortColumnSettings.releaseDate.index,
        'installMethod': InstallerMode.system.name,
        'theme': ThemeSettings.system.index,
      },
      <String, dynamic>{
        'sortColumn': SortColumnSettings.lastUpdateCheck.index,
        'appFolders': '[]',
      },
    );

    // Overlay wins on conflict (real sortColumn over the sanitized one).
    expect(merged?['sortColumn'], SortColumnSettings.lastUpdateCheck.index);
    expect(merged?['theme'], ThemeSettings.system.index);
    expect(merged?['installMethod'], InstallerMode.system.name);
    expect(merged?['appFolders'], '[]');
  });

  test('imported groupBy / installMethod survive the merge unchanged', () {
    // No translation on import: an Obtainium backup's shared keys are read
    // directly by ObtainX, so the merge is a plain pass-through.
    final Map<String, dynamic>? merged =
        mergeImportedSettingsMaps(<String, dynamic>{
          'groupBy': AppsListGroupBy.source.name,
          'installMethod': InstallerMode.shizuku.name,
        }, null);

    expect(merged?['groupBy'], AppsListGroupBy.source.name);
    expect(merged?['installMethod'], InstallerMode.shizuku.name);
  });

  test(
    'ObtainX self-import round-trips groupBy=appType via the shared block',
    () {
      final SplitExportSettings split = splitSettingsForExport(
        <String, dynamic>{'groupBy': AppsListGroupBy.appType.name},
      );
      final Map<String, dynamic>? merged = mergeImportedSettingsMaps(
        split.settings,
        split.settingsObtainX,
      );

      expect(merged?['groupBy'], AppsListGroupBy.appType.name);
    },
  );

  test('mergeImportedSettingsMaps falls back to shared settings only', () {
    final Map<String, dynamic>? merged = mergeImportedSettingsMaps(
      <String, dynamic>{'sortColumn': SortColumnSettings.added.index},
      null,
    );

    expect(merged?['sortColumn'], SortColumnSettings.added.index);
  });

  test('ExportSchema emits settingsObtainX when present', () {
    final ExportSchema schema = ExportSchema(
      schemaVersion: currentExportSchemaVersion,
      exportedAt: '2026-01-01T00:00:00.000',
      appVersion: '1.0.0',
      apps: <Map<String, dynamic>>[],
      settings: <String, dynamic>{'sortColumn': 3},
      settingsObtainX: <String, dynamic>{'sortColumn': 4},
    );

    final Map<String, dynamic> json = schema.toJson();
    expect(json['settings'], <String, dynamic>{'sortColumn': 3});
    expect(json['settingsObtainX'], <String, dynamic>{'sortColumn': 4});
  });

  test('Obtainium-facing settings never contain sortColumn >= 4', () {
    final SplitExportSettings split = splitSettingsForExport(<String, dynamic>{
      'sortColumn': 4,
      'groupBy': AppsListGroupBy.appType.name,
      'collapsedGroups': <String>[],
    });

    final int sortColumn = split.settings['sortColumn'] as int;
    expect(sortColumn >= obtainiumSortColumnCount, isFalse);
    expect(split.settings.containsKey('collapsedGroups'), isFalse);
  });
}
