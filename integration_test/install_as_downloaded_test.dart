import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/providers/apps_provider.dart';

import 'e2e_helpers.dart';

/// #2611: installs must begin as soon as each app has downloaded, even while
/// other apps in the queue are still downloading (installs stay serialized).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('installs an app while another is still downloading', (
    tester,
  ) async {
    if (!e2eRunInstall) {
      markTestSkipped(
        'Needs the runner\'s setup (./tool/e2e.sh): generated APKs, the '
        '/slow/ server route and both test packages pre-installed with '
        'Obtainium as their installer',
      );
      return;
    }
    if (!await serverReachable('testapp-v2.apk')) {
      markTestSkipped(
        'Local e2e server not reachable at $e2eBaseUrl; run ./tool/e2e.sh',
      );
      return;
    }
    if (await getInstalledInfo(e2eTestPackageId) == null ||
        await getInstalledInfo(e2eSecondTestPackageId) == null) {
      markTestSkipped(
        'Pre-install both test packages with Obtainium as their installer '
        '(the runner does this); e.g. adb install -r -i '
        'dev.imranr.obtainium.debug build/e2e_assets/testapp-v1.apk',
      );
      return;
    }
    if (await skipIfTV()) return;

    await clearAppData();
    await seedAppJson(
      appJson(
        id: e2eTestPackageId,
        name: 'E2E Fast',
        // Same host as the APK so no origin-warning dialog blocks the queue.
        url: '$e2eBaseUrl/testapp-v2.apk',
        apkUrls: [
          ['universal', '$e2eBaseUrl/testapp-v2.apk'],
        ],
        installedVersion: '1',
        latestVersion: '2',
        additionalSettings: const {'allowInsecure': true},
      ),
    );
    await seedAppJson(
      appJson(
        id: e2eSecondTestPackageId,
        name: 'E2E Slow',
        url: '$e2eBaseUrl/slow/testapp2-v2.apk',
        apkUrls: [
          ['universal', '$e2eBaseUrl/slow/testapp2-v2.apk'],
        ],
        installedVersion: '1',
        latestVersion: '2',
        additionalSettings: const {'allowInsecure': true},
      ),
    );
    await launchApp(tester);
    await pumpUntil(tester, find.text('E2E Fast'));

    final appsProvider = readProvider<AppsProvider>();
    // Wait for install-status reconciliation so both apps are eligible for a
    // silent update before the queue starts.
    await pumpUntilTrue(
      tester,
      () =>
          appsProvider.apps[e2eTestPackageId]?.installedInfo != null &&
          appsProvider.apps[e2eSecondTestPackageId]?.installedInfo != null,
      reason: 'installed info reconciled',
    );

    final installFuture = appsProvider.downloadAndInstallLatestApps([
      e2eTestPackageId,
      e2eSecondTestPackageId,
    ], appContext);

    // The fast app's install must complete while the slow app's download is
    // still running.
    var fastInstalledWhileSlowDownloaded = false;
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(seconds: 1));
      final fast = await getInstalledInfo(e2eTestPackageId);
      final slow = await getInstalledInfo(e2eSecondTestPackageId);
      final slowDownloading =
          appsProvider.apps[e2eSecondTestPackageId]?.downloadProgress != null;
      if (fast?.versionName == '2' &&
          slowDownloading &&
          slow?.versionName != '2') {
        fastInstalledWhileSlowDownloaded = true;
        break;
      }
      if (slow?.versionName == '2') break;
    }

    expect(
      fastInstalledWhileSlowDownloaded,
      isTrue,
      reason:
          'the fast app must install while the slow app is still downloading',
    );

    // Let the whole queue finish (the slow app still installs one at a time).
    await installFuture;
    expect((await getInstalledInfo(e2eSecondTestPackageId))?.versionName, '2');

    restoreErrorWidgetBuilder();
  });
}
