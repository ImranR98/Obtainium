import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/components/app_list_tile.dart';

import 'e2e_helpers.dart';

/// TV layout differences: no per-row checkboxes, selection mode adds them,
/// and the bottom "Add app" button never covers the last app.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TV layout keeps the add button clear of the app list', (
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

    // No per-row checkboxes outside selection mode.
    expect(find.byType(Checkbox), findsNothing);

    // Scroll to the bottom; the Add app button sits below the last tile.
    await tester.scrollUntilVisible(
      find.text('Add app'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFor(tester, const Duration(milliseconds: 500));
    final addRect = tester.getRect(find.text('Add app'));
    final lastTileRect = tester.getRect(find.byType(AppListTile).last);
    expect(
      addRect.top,
      greaterThanOrEqualTo(lastTileRect.bottom),
      reason: 'Add app must not overlap the last app tile',
    );

    // Selection mode shows checkboxes without breaking the layout.
    await tester.tap(find.byIcon(Icons.checklist_rounded));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.byType(Checkbox), findsWidgets);

    restoreErrorWidgetBuilder();
  });
}
