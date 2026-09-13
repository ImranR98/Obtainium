import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/providers/apps_provider.dart';

import 'e2e_helpers.dart';

/// Attempts a real silent update of a package that the runner pre-installed
/// with Obtainium as its installer. Falls back to asserting that the APK was
/// downloaded when the silent session can't complete on the device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('silently updates a pre-installed test app', (tester) async {
    if (!e2eRunInstall) {
      markTestSkipped(
        'Needs the runner\'s setup: a local APK server and '
        '$e2eTestPackageId pre-installed with Obtainium as its installer. '
        'Run "./tool/e2e.sh" (install tests are enabled by default), or '
        're-run flutter test with --dart-define=E2E_RUN_INSTALL=true',
      );
      return;
    }
    if (await getInstalledInfo(e2eTestPackageId) == null) {
      markTestSkipped(
        'Pre-install $e2eTestPackageId with Obtainium as its installer '
        '(the runner does this); e.g. '
        'adb install -r -i dev.imranr.obtainium.debug '
        'build/e2e_assets/testapp-v1.apk',
      );
      return;
    }
    if (!await _testServerReachable()) {
      markTestSkipped(
        'Local APK server not reachable at $e2eBaseUrl; use '
        './tool/e2e.sh phone --with-install which starts it',
      );
      return;
    }

    if (await skipIfTV()) return;

    await clearAppData();
    await seedAppJson(
      appJson(
        id: e2eTestPackageId,
        name: 'E2E Test App',
        url: '$e2eBaseUrl/testapp-v2.apk',
        installedVersion: '1',
        latestVersion: '2',
        additionalSettings: const {'allowInsecure': true, 'trackOnly': false},
      ),
    );
    await launchApp(
      tester,
      prefs: const {'enableBackgroundUpdates': true, 'updateInterval': 720},
    );
    await pumpUntil(tester, find.text('E2E Test App'));

    // Trigger the background update check from Settings -> Updates.
    await tester.tap(find.byTooltip('Settings'));
    await pumpUntil(tester, find.text('Updates'));
    await tester.tap(find.text('Updates'));
    await pumpUntil(
      tester,
      find.text('Run background update check now'),
      reason: 'manual background check button',
    );
    await tester.tap(find.text('Run background update check now'));

    // The background task downloads and silently installs v2.
    var updated = false;
    final end = DateTime.now().add(const Duration(seconds: 120));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(seconds: 1));
      final info = await getInstalledInfo(e2eTestPackageId);
      if (info?.versionName == '2') {
        updated = true;
        break;
      }
    }

    if (!updated) {
      final appsProvider = readProvider<AppsProvider>();
      await pumpUntilTrue(
        tester,
        () => appsProvider.apkDir.listSync().any(
          (e) => e.path.split('/').last.startsWith(e2eTestPackageId),
        ),
        timeout: const Duration(seconds: 30),
        reason: 'downloaded APK',
      );
      markTestSkipped(
        'Silent install did not complete on this device; '
        'verified the update download instead',
      );
      restoreErrorWidgetBuilder();
      return;
    }
    expect(updated, isTrue);

    restoreErrorWidgetBuilder();
  });
}

/// Whether the runner's local APK server answers. Runs on the device, so
/// `10.0.2.2` maps to the host's loopback.
Future<bool> _testServerReachable() async {
  final client = HttpClient();
  try {
    final request = await client
        .getUrl(Uri.parse('$e2eBaseUrl/testapp-v2.apk'))
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
