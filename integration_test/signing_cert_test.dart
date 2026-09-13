import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/utils/signing_cert_utils.dart';

import 'e2e_helpers.dart';

/// #2922: signing certificate verification.
///
/// Requires the runner's fixtures (`testapp-badkey-v2.apk` is the same package
/// and version as `testapp-v2.apk` but signed with a different keystore) and
/// `com.obtainium.e2etest` pre-installed at v1 with Obtainium as its installer.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signing certificate verification', (tester) async {
    if (!e2eRunInstall) {
      markTestSkipped('Needs the runner\'s install setup (./tool/e2e.sh)');
      return;
    }
    if (!await serverReachable('testapp-badkey-v2.apk')) {
      markTestSkipped(
        'Local e2e server not reachable at $e2eBaseUrl; run ./tool/e2e.sh',
      );
      return;
    }
    if (await getInstalledInfo(e2eTestPackageId) == null) {
      markTestSkipped('Pre-install $e2eTestPackageId via ./tool/e2e.sh');
      return;
    }
    if (await skipIfTV()) return;

    await clearAppData();
    await seedAppJson(
      appJson(
        id: e2eTestPackageId,
        name: 'E2E Sig',
        url: '$e2eBaseUrl/testapp-badkey-v2.apk',
        apkUrls: [
          ['universal', '$e2eBaseUrl/testapp-badkey-v2.apk'],
        ],
        installedVersion: '1',
        latestVersion: '2',
        additionalSettings: const {'allowInsecure': true},
      ),
    );
    await launchApp(tester, prefs: const {'enableBackgroundUpdates': true});
    await pumpUntil(tester, find.text('E2E Sig'));

    final appsProvider = readProvider<AppsProvider>();
    await pumpUntilTrue(
      tester,
      () => appsProvider.apps[e2eTestPackageId]?.installedInfo != null,
      reason: 'install status reconciled',
    );

    Set<String> cachedApks() => appsProvider.apkDir
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .toSet();

    Future<void> retarget({required String apk, String? expectedHashes}) async {
      final entry = appsProvider.apps[e2eTestPackageId]!;
      final settings = Map<String, dynamic>.from(entry.app.additionalSettings);
      if (expectedHashes == null) {
        settings.remove('allowedSigningCertHashes');
      } else {
        settings['allowedSigningCertHashes'] = expectedHashes;
      }
      entry.app = entry.app.copyWith(
        url: '$e2eBaseUrl/$apk',
        apkUrls: [MapEntry('universal', '$e2eBaseUrl/$apk')],
        latestVersion: '2',
        additionalSettings: settings,
      );
      await appsProvider.saveApps([entry.app]);
    }

    // 1. Archive signing info matches the installed app's certificate, and    //    the bad-key fixture is genuinely different.
    final installedHashes = appsProvider
        .apps[e2eTestPackageId]!
        .certificateHashes
        .toSet();
    final goodHashes = await _downloadAndHash('testapp-v2.apk');
    final badHashes = await _downloadAndHash('testapp-badkey-v2.apk');
    // ignore: avoid_print
    print(
      'SIG_CERTS installed=$installedHashes good=$goodHashes bad=$badHashes',
    );
    expect(installedHashes, isNotEmpty);
    expect(goodHashes, equals(installedHashes));
    expect(badHashes, isNotEmpty);
    expect(badHashes.intersection(installedHashes), isEmpty);

    // 2. Auto-compare warning: bad key vs installed cert. "Don't install"
    //    blocks and the blocked APK is deleted.
    final beforeWarn = cachedApks();
    Object? warnError;
    final warnFuture = appsProvider
        .downloadAndInstallLatestApps([e2eTestPackageId], appContext)
        .then<void>(
          (_) {},
          onError: (Object e) {
            warnError = e;
          },
        );
    await pumpUntil(tester, find.text('Signing certificate mismatch'));
    expect(find.text('Install anyway'), findsOneWidget);
    await tester.tap(find.text("Don't install"));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await warnFuture;
    expect(warnError, isA<MultiAppMultiError>());
    expect((await getInstalledInfo(e2eTestPackageId))?.versionName, '1');
    await pumpUntilTrue(
      tester,
      () => cachedApks().difference(beforeWarn).isEmpty,
      reason: 'blocked APK deleted',
    );

    // 3. A user-provided hash is a hard block: no "Install anyway".
    await retarget(
      apk: 'testapp-v2.apk',
      expectedHashes: List.filled(32, '00').join(':'),
    );
    Object? hardError;
    final hardFuture = appsProvider
        .downloadAndInstallLatestApps([e2eTestPackageId], appContext)
        .then<void>(
          (_) {},
          onError: (Object e) {
            hardError = e;
          },
        );
    await pumpUntil(tester, find.text('Signing certificate mismatch'));
    expect(find.text('Install anyway'), findsNothing);
    await tester.tap(find.text('Okay'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await hardFuture;
    expect(hardError, isA<MultiAppMultiError>());
    expect((await getInstalledInfo(e2eTestPackageId))?.versionName, '1');

    // 4. A matching user-provided hash allows the update.
    await retarget(
      apk: 'testapp-v2.apk',
      expectedHashes: installedHashes.join('\n'),
    );
    await appsProvider.downloadAndInstallLatestApps([
      e2eTestPackageId,
    ], appContext);
    expect((await getInstalledInfo(e2eTestPackageId))?.versionName, '2');

    // 5. Background (no context) mismatch is blocked without a prompt.
    await retarget(apk: 'testapp-badkey-v2.apk');
    Object? bgError;
    try {
      await appsProvider.downloadAndInstallLatestApps([e2eTestPackageId], null);
    } catch (e) {
      bgError = e;
    }
    expect(bgError, isA<MultiAppMultiError>());
    expect((await getInstalledInfo(e2eTestPackageId))?.versionName, '2');

    restoreErrorWidgetBuilder();
  });
}

/// Downloads a fixture APK from the runner's server and returns its signing
/// certificate hashes.
Future<Set<String>> _downloadAndHash(String name) async {
  final client = HttpClient();
  final dir = await Directory.systemTemp.createTemp('obtainium_sig');
  try {
    final file = File('${dir.path}/$name');
    final request = await client.getUrl(Uri.parse('$e2eBaseUrl/$name'));
    final response = await request.close();
    await response.pipe(file.openWrite());
    return await apkSigningCertHashes(file.path);
  } finally {
    client.close(force: true);
    await dir.delete(recursive: true);
  }
}
