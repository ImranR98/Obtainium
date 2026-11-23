import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/apps_provider.dart';

import 'e2e_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('import preserves tracked versions for pseudo-versioned apps', (
    tester,
  ) async {
    if (await skipIfTV()) return;

    await clearAppData();
    await launchApp(tester);
    addTearDown(restoreErrorWidgetBuilder);

    final provider = readProvider<AppsProvider>();

    App app(
      String id,
      String? installedVersion,
      Map<String, dynamic> additionalSettings,
    ) => App(
      id: id,
      url: 'https://example.com/$id',
      author: 'Author',
      name: id,
      installedVersion: installedVersion,
      latestVersion: '9.9.9',
      preferredApkIndex: 0,
      additionalSettings: additionalSettings,
    );

    final tracked = app('com.example.tracked', '1.2.3', {
      'trackOnly': true,
      'versionDetection': true,
    });
    final pinned = app('com.example.pinned', '2.3.4', {
      'versionDetection': false,
    });
    final regular = app('com.example.regular', '3.4.5', {
      'versionDetection': true,
    });

    final result = await provider.import(
      jsonEncode([tracked.toJson(), pinned.toJson(), regular.toJson()]),
    );
    final imported = {for (final app in result.key) app.id: app};

    expect(imported['com.example.tracked']?.installedVersion, '1.2.3');
    expect(imported['com.example.pinned']?.installedVersion, '2.3.4');
    expect(imported['com.example.regular']?.installedVersion, isNull);

    await provider.removeApps(result.key.map((app) => app.id).toList());
  });
}
