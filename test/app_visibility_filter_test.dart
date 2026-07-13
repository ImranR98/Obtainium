import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/pages/apps.dart';
import 'package:obtainium/providers/source_provider.dart';

App _buildFilterApp({
  String? installedVersion,
  String latestVersion = '2.0',
  bool trackOnly = false,
}) {
  return App(
    id: 'com.example.app',
    url: 'https://example.com/app',
    author: 'Author',
    name: 'Example App',
    installedVersion: installedVersion,
    latestVersion: latestVersion,
    apkUrls: const <MapEntry<String, String>>[],
    preferredApkIndex: 0,
    additionalSettings: trackOnly ? const {'trackOnly': true} : const {},
    lastUpdateCheck: DateTime.now(),
    pinned: false,
  );
}

void main() {
  test('neutral visibility intents match any app', () {
    expect(
      appMatchesUpToDateFilter(
        _buildFilterApp(installedVersion: '2.0'),
        CategoryFilterIntent.neutral,
      ),
      true,
    );
    expect(
      appMatchesInstalledFilter(
        _buildFilterApp(installedVersion: null),
        CategoryFilterIntent.neutral,
      ),
      true,
    );
    expect(
      appMatchesTrackOnlyFilter(
        _buildFilterApp(trackOnly: true),
        CategoryFilterIntent.neutral,
      ),
      true,
    );
  });

  test('up to date include requires an up to date app', () {
    expect(
      appMatchesUpToDateFilter(
        _buildFilterApp(installedVersion: '2.0'),
        CategoryFilterIntent.include,
      ),
      true,
    );
    expect(
      appMatchesUpToDateFilter(
        _buildFilterApp(installedVersion: '1.0'),
        CategoryFilterIntent.include,
      ),
      false,
    );
    expect(
      appMatchesUpToDateFilter(
        _buildFilterApp(installedVersion: null),
        CategoryFilterIntent.include,
      ),
      false,
    );
  });

  test('up to date exclude hides up to date apps', () {
    expect(
      appMatchesUpToDateFilter(
        _buildFilterApp(installedVersion: '2.0'),
        CategoryFilterIntent.exclude,
      ),
      false,
    );
    expect(
      appMatchesUpToDateFilter(
        _buildFilterApp(installedVersion: '1.0'),
        CategoryFilterIntent.exclude,
      ),
      true,
    );
  });

  test('installed include requires an installed app', () {
    expect(
      appMatchesInstalledFilter(
        _buildFilterApp(installedVersion: '1.0'),
        CategoryFilterIntent.include,
      ),
      true,
    );
    expect(
      appMatchesInstalledFilter(
        _buildFilterApp(installedVersion: null),
        CategoryFilterIntent.include,
      ),
      false,
    );
  });

  test('installed exclude hides installed apps', () {
    expect(
      appMatchesInstalledFilter(
        _buildFilterApp(installedVersion: null),
        CategoryFilterIntent.exclude,
      ),
      true,
    );
    expect(
      appMatchesInstalledFilter(
        _buildFilterApp(installedVersion: '1.0'),
        CategoryFilterIntent.exclude,
      ),
      false,
    );
  });

  test('track only include requires a track only app', () {
    expect(
      appMatchesTrackOnlyFilter(
        _buildFilterApp(trackOnly: true),
        CategoryFilterIntent.include,
      ),
      true,
    );
    expect(
      appMatchesTrackOnlyFilter(
        _buildFilterApp(trackOnly: false),
        CategoryFilterIntent.include,
      ),
      false,
    );
  });

  test('track only exclude hides track only apps', () {
    expect(
      appMatchesTrackOnlyFilter(
        _buildFilterApp(trackOnly: false),
        CategoryFilterIntent.exclude,
      ),
      true,
    );
    expect(
      appMatchesTrackOnlyFilter(
        _buildFilterApp(trackOnly: true),
        CategoryFilterIntent.exclude,
      ),
      false,
    );
  });

  test('visibilityFilterChipLabel prefixes include and exclude states', () {
    expect(
      visibilityFilterChipLabel('Up-to-date', CategoryFilterIntent.include),
      '+ Up-to-date',
    );
    expect(
      visibilityFilterChipLabel('Up-to-date', CategoryFilterIntent.exclude),
      '- Up-to-date',
    );
  });

  test('AppsFilter setFormValuesFromMap migrates legacy boolean keys', () {
    final filter = AppsFilter();
    filter.setFormValuesFromMap({
      'appName': '',
      'author': '',
      'appId': '',
      'upToDateApps': false,
      'nonInstalledApps': false,
      'sourceFilter': '',
    });
    expect(filter.upToDateFilterIntent, CategoryFilterIntent.exclude);
    expect(filter.installedFilterIntent, CategoryFilterIntent.include);
    expect(filter.trackOnlyFilterIntent, CategoryFilterIntent.neutral);
  });

  test('AppsFilter setFormValuesFromMap migrates segmented enum keys', () {
    final filter = AppsFilter();
    filter.setFormValuesFromMap({
      'appName': '',
      'author': '',
      'appId': '',
      'updateStatusFilter': 'upToDateOnly',
      'installStatusFilter': 'notInstalledOnly',
      'trackModeFilter': 'installable',
      'sourceFilter': '',
    });
    expect(filter.upToDateFilterIntent, CategoryFilterIntent.include);
    expect(filter.installedFilterIntent, CategoryFilterIntent.exclude);
    expect(filter.trackOnlyFilterIntent, CategoryFilterIntent.exclude);
  });
}
