import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';

import 'e2e_helpers.dart';

/// Walks the main screens that aren't covered by the smoke test: the update
/// banner dialog, the filter sheet, the category editor and the
/// import/export and logs pages.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('update banner, filter, categories, import/export and logs', (
    tester,
  ) async {
    if (await skipIfTV()) return;

    await clearAppData();
    for (var i = 1; i <= 3; i++) {
      await seedAppJson(
        appJson(
          id: 'e2e.app$i',
          name: 'E2E Pending $i',
          installedVersion: '0.9.$i',
          latestVersion: '1.0.$i',
          // Track-only apps keep their seeded installedVersion even when the
          // package is not actually installed, so the update banner shows.
          additionalSettings: const {'trackOnly': true},
        ),
      );
    }
    await launchApp(tester, prefs: const {'actionBannerMode': 'all'});
    await pumpUntil(tester, find.text('E2E Pending 1'));

    // Bulk update banner (visible with >= 2 pending apps).
    await pumpUntil(tester, find.text('Install/update apps'));
    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await pumpUntil(tester, find.textContaining('Change'));
    await tester.tap(find.text('Cancel'));
    await pumpUntil(tester, find.text('Install/update apps'));

    // Filter bottom sheet.
    await tester.tap(find.byIcon(Icons.filter_list_rounded));
    await pumpUntil(tester, find.text('Filter apps'));
    expect(find.text('App name'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await pumpUntil(tester, find.text('E2E Pending 1'));

    // Settings -> Appearance -> create a category.
    await tester.tap(find.byTooltip('Settings'));
    await pumpUntil(tester, find.text('Appearance'));
    await tester.tap(find.text('Appearance'));
    await pumpUntil(tester, find.text('App sort by'));
    final newCategoryChip = find.widgetWithText(ActionChip, '+');
    await tester.scrollUntilVisible(
      newCategoryChip,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(newCategoryChip);
    await pumpUntil(tester, find.text('New category'));
    final nameField = find.widgetWithText(TextField, 'Category name');
    await pumpUntil(tester, nameField);
    await tester.enterText(nameField, 'E2E Category');
    await pumpFor(tester, const Duration(milliseconds: 300));
    final continueButton = find.widgetWithText(FilledButton, 'Continue').last;
    await pumpUntilTrue(
      tester,
      () => tester.widget<FilledButton>(continueButton).onPressed != null,
      reason: 'category continue enabled',
    );
    await tester.tap(continueButton);
    await pumpUntil(tester, find.widgetWithText(ActionChip, 'E2E Category'));

    // Category editor exposes the update-check exclusion switch (#3375).
    await tester.tap(find.widgetWithText(ActionChip, 'E2E Category'));
    await pumpUntil(tester, find.text('Skip update checks'));
    final skipSwitch = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Skip update checks'),
      matching: find.byType(Switch),
    );
    await tester.scrollUntilVisible(
      skipSwitch,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(skipSwitch);
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Continue').last);
    await pumpUntil(tester, find.widgetWithText(ActionChip, 'E2E Category'));
    expect(
      readProvider<SettingsProvider>().categoriesExcludedFromChecks,
      contains('E2E Category'),
    );

    // An app in the excluded category is skipped by update checks.
    final appsProvider = readProvider<AppsProvider>();
    await appsProvider.saveApps([
      appsProvider.apps['e2e.app1']!.app.copyWith(categories: ['E2E Category']),
    ]);
    expect(
      appsProvider.getAppsSortedByUpdateCheckTime(forceAll: true),
      isNot(contains('e2e.app1')),
    );

    // Turning the switch back off removes the exclusion.
    await tester.tap(find.widgetWithText(ActionChip, 'E2E Category'));
    await pumpUntil(tester, find.text('Skip update checks'));
    final skipSwitch2 = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Skip update checks'),
      matching: find.byType(Switch),
    );
    await tester.scrollUntilVisible(
      skipSwitch2,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(skipSwitch2);
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Continue').last);
    await pumpUntil(tester, find.widgetWithText(ActionChip, 'E2E Category'));
    expect(
      readProvider<SettingsProvider>().categoriesExcludedFromChecks,
      isNot(contains('E2E Category')),
    );
    expect(
      appsProvider.getAppsSortedByUpdateCheckTime(forceAll: true),
      contains('e2e.app1'),
    );

    // Settings -> Import/export.
    await pressBack(tester);
    await pumpUntil(tester, find.text('Import/export'));
    await tester.tap(find.text('Import/export'));
    await pumpUntil(tester, find.text('Pick export directory'));
    expect(find.text('Obtainium import'), findsOneWidget);
    await pressBack(tester);

    // Settings -> App logs.
    await pumpUntil(tester, find.text('App logs'));
    await tester.tap(find.text('App logs'));
    await pumpUntil(tester, find.text('App logs'));
    expect(find.byIcon(Icons.share_rounded).evaluate(), isNotEmpty);
    await pressBack(tester);
    await pumpUntil(tester, find.text('Settings'));

    restoreErrorWidgetBuilder();
  });
}
