import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/pages/settings.dart';

import 'e2e_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches, lists apps and navigates the main screens', (
    tester,
  ) async {
    if (await skipIfTV()) return;

    await clearAppData();
    await seedAppJson(appJson(id: 'e2e.one', name: 'E2E App One'));
    await seedAppJson(
      appJson(
        id: 'e2e.two',
        name: 'E2E App Two',
        latestVersion: '2.0.0',
        pinned: true,
      ),
    );

    await launchApp(tester);

    // App list renders both seeded entries.
    await pumpUntil(tester, find.text('E2E App One'));
    expect(find.text('E2E App Two'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);

    // Open an app's detail page and come back via system back.
    await tester.tap(find.text('E2E App One'));
    await pumpUntil(
      tester,
      find.textContaining('Last update check'),
      reason: 'detail',
    );
    expect(find.textContaining('github.com/lichess-org/mobile'), findsWidgets);
    await pressBack(tester);
    await pumpUntil(tester, find.text('Search'));

    // Settings screen and one subpage.
    await tester.tap(find.byTooltip('Settings'));
    await pumpUntil(tester, find.byType(SettingsPage));
    expect(find.text('Import/export'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.text('Updates'));
    await pumpUntil(tester, find.text('Enable certificate pinning'));
    await pressBack(tester);
    await pumpUntil(tester, find.byType(SettingsPage));
    await pressBack(tester);
    await pumpUntil(tester, find.text('Search'));

    // Add App screen.
    await tester.tap(find.text('Add'));
    await pumpUntil(tester, find.text('Add app'));
    expect(find.text('App source URL'), findsOneWidget);
    await pressBack(tester);
    await pumpUntil(tester, find.text('Search'));

    restoreErrorWidgetBuilder();
  });
}
