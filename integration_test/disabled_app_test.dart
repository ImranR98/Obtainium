import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/components/app_list_tile.dart';
import 'package:obtainium/providers/apps_provider.dart';

import 'e2e_helpers.dart';

/// Disabled apps (#3375): dimmed, no update affordance, and toggleable from
/// the app page.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('disabled apps are dimmed and can be re-enabled', (tester) async {
    if (await skipIfTV()) return;

    await clearAppData();
    // Track-only apps keep their seeded installedVersion even though the
    // package is not actually installed, so the pending-update UI shows.
    await seedAppJson(
      appJson(
        id: 'e2e.enabled',
        name: 'E2E Enabled App',
        installedVersion: '1.0.0',
        latestVersion: '2.0.0',
        additionalSettings: const {'trackOnly': true},
      ),
    );
    await seedAppJson(
      appJson(
        id: 'e2e.disabled',
        name: 'E2E Disabled App',
        installedVersion: '1.0.0',
        latestVersion: '2.0.0',
        additionalSettings: const {'trackOnly': true},
        disabled: true,
      ),
    );
    await launchApp(tester);
    await pumpUntil(tester, find.textContaining('E2E Disabled App'));

    final disabledTile = find.widgetWithText(AppListTile, 'E2E Disabled App');
    final enabledTile = find.widgetWithText(AppListTile, 'E2E Enabled App');
    expect(disabledTile, findsOneWidget);
    expect(
      tester.getTopLeft(disabledTile).dy,
      greaterThan(tester.getTopLeft(enabledTile).dy),
      reason: 'disabled apps sort to the bottom of the list',
    );

    // Disabled apps are excluded from automatic and manual update checks.
    final appsProvider = readProvider<AppsProvider>();
    final checkIds = appsProvider.getAppsSortedByUpdateCheckTime(
      forceAll: true,
    );
    expect(checkIds, contains('e2e.enabled'));
    expect(checkIds, isNot(contains('e2e.disabled')));
    expect(
      appsProvider.findAppIdsWithPendingUpdates(),
      isNot(contains('e2e.disabled')),
    );
    await expectLater(
      appsProvider.checkUpdate('e2e.disabled'),
      completion(isNull),
    );

    expect(
      find.descendant(of: disabledTile, matching: find.text('Disabled')),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<Opacity>(
            find.descendant(of: disabledTile, matching: find.byType(Opacity)),
          )
          .any((o) => o.opacity < 1.0),
      isTrue,
      reason: 'disabled rows are dimmed',
    );

    expect(
      find.descendant(
        of: enabledTile,
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
      reason: 'the enabled track-only row keeps its mark-updated action',
    );
    expect(
      find.descendant(
        of: disabledTile,
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsNothing,
      reason: 'disabled rows show no update action',
    );

    // Re-enable from the app page.
    await tester.tap(disabledTile);
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Enable app'));
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Disable app'));
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Enable app'));
    await pumpFor(tester, const Duration(seconds: 1));

    await pressBack(tester);
    await pumpFor(tester, const Duration(seconds: 1));
    expect(
      find.descendant(
        of: find.widgetWithText(AppListTile, 'E2E Disabled App'),
        matching: find.text('Disabled'),
      ),
      findsNothing,
      reason: 'the app is no longer disabled after re-enabling',
    );

    restoreErrorWidgetBuilder();
  });
}
