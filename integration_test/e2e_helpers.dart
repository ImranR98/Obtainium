import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/main.dart' as app;
import 'package:obtainium/providers/settings_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Base URL the runner serves generated test APKs from. `10.0.2.2` is the
/// host loopback as seen from an Android emulator.
const e2eBaseUrl = String.fromEnvironment(
  'E2E_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

/// When false, the install/update suite is skipped (its preconditions are
/// provided by the runner: generated APKs and a pre-installed test package).
const e2eRunInstall = bool.fromEnvironment(
  'E2E_RUN_INSTALL',
  defaultValue: false,
);

const e2eTestPackageId = 'com.obtainium.e2etest';

/// Seeds SharedPreferences with deterministic defaults. Must run before
/// [launchApp].
Future<void> seedPrefs({Map<String, Object> overrides = const {}}) async {
  SharedPreferences.setMockInitialValues({
    'firstRun': false,
    'welcomeShown': true,
    'googleVerificationWarningShown': true,
    'checkOnStart': false,
    'updateInterval': 0,
    'enableBackgroundUpdates': false,
    'forcedLocale': 'en',
    ...overrides,
  });
}

ErrorWidgetBuilder? _errorWidgetBuilderBeforeApp;

/// Remembers the framework's [ErrorWidget.builder] before the app overrides
/// it; the test binding requires it to be restored after each test.
void saveErrorWidgetBuilder() {
  _errorWidgetBuilderBeforeApp = ErrorWidget.builder;
}

/// Restores the builder saved by [saveErrorWidgetBuilder].
void restoreErrorWidgetBuilder() {
  final builder = _errorWidgetBuilderBeforeApp;
  if (builder != null) {
    ErrorWidget.builder = builder;
  }
}

/// Seeds prefs and starts the real app on top of already-seeded storage.
Future<void> launchApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
}) async {
  saveErrorWidgetBuilder();
  await seedPrefs(overrides: prefs);
  app.main();
  await tester.pump();
  await pumpFor(tester, const Duration(seconds: 3));
}

/// The app's on-device `app_data` directory (where app JSONs live).
Future<Directory> externalAppDataDir() async {
  final ext = await getExternalStorageDirectory();
  if (ext == null) {
    throw StateError('External storage is unavailable');
  }
  return Directory('${ext.path}/app_data');
}

/// Deletes and recreates `app_data` so a suite starts from a clean slate.
Future<void> clearAppData() async {
  final dir = await externalAppDataDir();
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
  dir.createSync(recursive: true);
}

/// Writes a tracked-app JSON file straight into `app_data`, bypassing the UI.
Future<void> seedAppJson(Map<String, dynamic> app) async {
  final dir = await externalAppDataDir();
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  File('${dir.path}/${app['id']}.json').writeAsStringSync(jsonEncode(app));
}

/// Builds a valid app JSON payload as understood by `App.fromJson`.
Map<String, dynamic> appJson({
  required String id,
  required String name,
  String url = 'https://github.com/lichess-org/mobile',
  String author = 'E2E',
  String? installedVersion,
  String latestVersion = '1.0.0',
  List<List<String>> apkUrls = const [
    ['universal', 'https://example.com/app.apk'],
  ],
  Map<String, dynamic> additionalSettings = const {'versionDetection': true},
  bool pinned = false,
  List<String> categories = const [],
}) => {
  'id': id,
  'url': url,
  'author': author,
  'name': name,
  'installedVersion': installedVersion,
  'latestVersion': latestVersion,
  'apkUrls': jsonEncode(apkUrls),
  'otherAssetUrls': '[]',
  'preferredApkIndex': 0,
  'additionalSettings': jsonEncode(additionalSettings),
  'lastUpdateCheck': null,
  'pinned': pinned,
  'categories': categories,
  'releaseDate': null,
  'changeLog': null,
  'overrideSource': null,
  'allowIdChange': false,
  'pendingRepoRenameUrl': null,
};

/// Whether the runner's local HTTP server answers. Runs on the device, so
/// `10.0.2.2` maps to the host's loopback.
Future<bool> serverReachable([String path = 'testapp-v2.apk']) async {
  final client = HttpClient();
  try {
    final request = await client
        .getUrl(Uri.parse('$e2eBaseUrl/$path'))
        .timeout(const Duration(seconds: 5));
    final response = await request.close().timeout(const Duration(seconds: 5));
    await response.drain<void>();
    return response.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// Pumps frames until [finder] matches, failing with a clear message on
/// timeout. Prefer this over [WidgetTester.pumpAndSettle], which can hang when
/// the app shows an indefinite progress indicator.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail(
    'Timed out waiting for $finder'
    '${reason == null ? '' : ' ($reason)'}',
  );
}

/// Pumps frames until [condition] is true, failing with a clear message on
/// timeout.
Future<void> pumpUntilTrue(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for condition${reason == null ? '' : ' ($reason)'}');
}

/// Pumps frames for [duration] without requiring the tree to settle.
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Context of the running app, used to read providers from tests.
BuildContext get appContext {
  final ctx = app.appNavigatorKey.currentContext;
  if (ctx == null) {
    throw StateError('The app is not running yet');
  }
  return ctx;
}

T readProvider<T>() => Provider.of<T>(appContext, listen: false);

bool appIsTV() => readProvider<SettingsProvider>().isTV;

/// Whether the attached device reports itself as an Android TV, without
/// needing the app to be running.
Future<bool> deviceIsTV() async {
  final info = await DeviceInfoPlugin().androidInfo;
  return info.systemFeatures.contains('android.hardware.type.television') ||
      info.systemFeatures.contains('android.software.leanback');
}

/// Whether the currently focused node is [T] itself, contains a [T] in its
/// subtree, or sits inside a [T]. Covers wrappers that own focus for a child
/// control (e.g. `TvDropdownMenu`).
bool focusIsWithin<T extends Widget>() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  if (ctx.findAncestorWidgetOfExactType<T>() != null) return true;
  var found = false;
  void visit(Element element) {
    if (found) return;
    if (element.widget is T) {
      found = true;
      return;
    }
    element.visitChildren(visit);
  }

  (ctx as Element).visitChildren(visit);
  return found;
}

/// Sends a remote-control style key and lets the focus system react.
Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump(const Duration(milliseconds: 250));
}

/// Simulates the system/remote BACK button.
Future<void> pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Whether the current primary focus lives inside a widget of type [T].
bool focusIsInside<T extends Widget>() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  return ctx != null && ctx.findAncestorWidgetOfExactType<T>() != null;
}

/// Whether the current primary focus is inside a widget with [tooltip].
bool focusIsOnTooltip(String tooltip) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  final button = ctx.findAncestorWidgetOfExactType<IconButton>();
  return button?.tooltip == tooltip;
}

/// Marks a suite as skipped on the wrong device type. Returns true when the
/// caller should stop.
Future<bool> skipUnlessTV() async {
  if (!await deviceIsTV()) {
    markTestSkipped('TV-only suite (run on the Television AVD)');
    return true;
  }
  return false;
}

/// Marks a suite as skipped on the wrong device type. Returns true when the
/// caller should stop.
Future<bool> skipIfTV() async {
  if (await deviceIsTV()) {
    markTestSkipped('Phone-only suite (run on the phone AVD)');
    return true;
  }
  return false;
}
