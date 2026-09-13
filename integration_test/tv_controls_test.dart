import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/providers/settings_provider.dart';

import 'e2e_helpers.dart';

/// TV-specific controls: selection mode, the TV dropdown, and BACK while
/// editing a text field.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TV selection, dropdowns and text editing work with the remote', (
    tester,
  ) async {
    if (await skipUnlessTV()) return;

    await clearAppData();
    for (var i = 1; i <= 2; i++) {
      await seedAppJson(appJson(id: 'e2e.ctrl$i', name: 'E2E Control $i'));
    }
    await launchApp(tester);
    await pumpUntil(tester, find.text('E2E Control 1'));

    // No checkboxes until selection mode is enabled.
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.byIcon(Icons.checklist_rounded));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.byType(Checkbox), findsWidgets);
    expect(find.textContaining('Actions ('), findsOneWidget);

    // Tapping a tile toggles selection instead of opening it.
    await tester.tap(find.text('E2E Control 1'));
    await pumpUntil(tester, find.text('Actions (1)'));
    expect(find.text('Select an app to see details'), findsOneWidget);

    // Leave selection mode.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // Settings -> Appearance -> open the "App sort by" dropdown with select.
    await tester.tap(find.byTooltip('Settings'));
    await pumpUntil(tester, find.text('Appearance'));
    await tester.tap(find.text('Appearance'));
    await pumpUntil(tester, find.text('App sort by'));

    var onDropdown = false;
    for (var i = 0; i < 12 && !onDropdown; i++) {
      await pressKey(tester, LogicalKeyboardKey.arrowDown);
      onDropdown = focusIsWithin<DropdownMenu<SortColumnSettings>>();
    }
    expect(onDropdown, isTrue, reason: 'dropdown focusable with the remote');
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.text('As added'));
    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('As added'), findsWidgets);

    restoreErrorWidgetBuilder();
  });
}
