import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/components/app_list_tile.dart';
import 'package:obtainium/components/ui_widgets.dart';

import 'e2e_helpers.dart';

/// TV layout differences: icons are shown, no per-row checkboxes, selection
/// mode adds them, and the pinned footer's "Add app" button stays visible
/// without covering the end of the app list.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TV layout shows icons and keeps the add button visible', (
    tester,
  ) async {
    if (await skipUnlessTV()) return;

    await clearAppData();
    for (var i = 1; i <= 6; i++) {
      await seedAppJson(
        appJson(
          id: 'e2e.layout$i',
          name: 'E2E Layout App With A Fairly Long Name $i',
        ),
      );
    }
    await launchApp(tester);
    await pumpUntil(tester, find.textContaining('E2E Layout App'));

    // App icons are shown in the TV list (standard density).
    expect(find.byType(AppIcon), findsWidgets);

    // No per-row checkboxes outside selection mode.
    expect(find.byType(Checkbox), findsNothing);

    // The Add app button is pinned: visible without scrolling, and it stays
    // put while the list scrolls.
    expect(find.text('Add app'), findsOneWidget);
    final addRectBefore = tester.getRect(find.text('Add app'));

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await pumpFor(tester, const Duration(milliseconds: 500));

    final addRect = tester.getRect(find.text('Add app'));
    final lastTileRect = tester.getRect(find.byType(AppListTile).last);
    expect(
      addRect.top,
      greaterThanOrEqualTo(lastTileRect.bottom - 1),
      reason: 'Add app must not overlap the last app tile',
    );
    expect(
      (addRect.top - addRectBefore.top).abs(),
      lessThan(2),
      reason: 'the pinned footer must not move while scrolling',
    );

    // Selection mode shows checkboxes and the Actions button in the footer.
    await tester.tap(find.byIcon(Icons.checklist_rounded));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.byType(Checkbox), findsWidgets);
    expect(find.textContaining('Actions'), findsOneWidget);
    expect(find.text('Add app'), findsOneWidget);

    restoreErrorWidgetBuilder();
  });
}
