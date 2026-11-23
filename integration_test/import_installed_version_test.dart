import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/custom_errors.dart';
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
      Map<String, dynamic> additionalSettings, {
      bool allowIdChange = false,
    }) => App(
      id: id,
      url: 'https://example.com/$id',
      author: 'Author',
      name: id,
      installedVersion: installedVersion,
      latestVersion: '9.9.9',
      preferredApkIndex: 0,
      additionalSettings: additionalSettings,
      allowIdChange: allowIdChange,
    );

    final tracked = app('com.example.tracked', '1.2.3', {
      'trackOnly': true,
      'versionDetection': true,
    }, allowIdChange: true);
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
    expect(imported['com.example.tracked']?.allowIdChange, isFalse);
    expect(imported['com.example.pinned']?.installedVersion, '2.3.4');
    expect(imported['com.example.regular']?.installedVersion, isNull);

    final savedFile = File(
      '${(await externalAppDataDir()).path}/com.example.tracked.json',
    );
    expect(savedFile.existsSync(), isTrue);
    expect(jsonDecode(await savedFile.readAsString()), isA<Map>());

    await provider.removeApps(result.key.map((app) => app.id).toList());
  });

  testWidgets('import rejects IDs that escape the app data directory', (
    tester,
  ) async {
    if (await skipIfTV()) return;

    await clearAppData();
    await launchApp(tester);
    addTearDown(restoreErrorWidgetBuilder);

    final provider = readProvider<AppsProvider>();
    const escapedId = '../obtainium_path_traversal_poc';
    final appDataDir = await externalAppDataDir();
    final escapedFile = File(
      '${appDataDir.parent.path}/obtainium_path_traversal_poc.json',
    );
    if (escapedFile.existsSync()) escapedFile.deleteSync();

    const malicious = App(
      id: escapedId,
      url: 'https://example.com/malicious',
      author: 'Author',
      name: 'Malicious',
      latestVersion: '1.0.0',
      preferredApkIndex: 0,
      additionalSettings: {'versionDetection': true},
    );

    await expectLater(
      provider.import(jsonEncode([malicious.toJson()])),
      throwsA(isA<ObtainiumError>()),
    );

    expect(escapedFile.existsSync(), isFalse);
    expect(provider.apps.containsKey(escapedId), isFalse);
  });
}
