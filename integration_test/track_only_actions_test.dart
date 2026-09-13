import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/providers/apps_provider.dart';

import 'e2e_helpers.dart';

/// Track-only apps (e.g. APKMirror) keep their pseudo-version control on the
/// detail page: the primary button marks the app installed/updated and the
/// reset action clears it, even when a release page URL is available.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('track-only detail page keeps pseudo-version controls', (
    tester,
  ) async {
    if (await skipIfTV()) return;

    await clearAppData();
    await seedAppJson(
      appJson(
        id: 'e2e.trackonly',
        name: 'E2E Track Only',
        installedVersion: '0.9.0',
        latestVersion: '1.0.0',
        apkUrls: const [],
        additionalSettings: const {'trackOnly': true, 'versionDetection': true},
        releaseUrl: 'https://example.com/release',
      ),
    );
    await launchApp(tester);
    await pumpUntil(tester, find.text('E2E Track Only'));

    await tester.tap(find.text('E2E Track Only'));
    await pumpUntil(
      tester,
      find.textContaining('Last update check'),
      reason: 'detail',
    );

    // The primary action is the pseudo-version control, not a browser link.
    expect(find.text('Mark updated'), findsOneWidget);
    expect(find.text('Update'), findsNothing);
    expect(find.byTooltip('Open release page'), findsOneWidget);

    await tester.tap(find.text('Mark updated'));
    final appsProvider = readProvider<AppsProvider>();
    await pumpUntilTrue(
      tester,
      () => appsProvider.apps['e2e.trackonly']?.app.installedVersion == '1.0.0',
      reason: 'track-only app marked updated',
    );

    // Once up to date, the reset action is available again.
    await pumpUntil(tester, find.byTooltip('Reset install status'));
    await tester.tap(find.byTooltip('Reset install status'));
    await pumpUntilTrue(
      tester,
      () => appsProvider.apps['e2e.trackonly']?.app.installedVersion == null,
      reason: 'install status reset',
    );

    restoreErrorWidgetBuilder();
  });
}
