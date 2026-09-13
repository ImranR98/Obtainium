import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/components/app_list_tile.dart';
import 'package:obtainium/components/ui_widgets.dart';

import 'e2e_helpers.dart';

/// D-pad navigation of the two-pane TV layout: tile traversal, app bar
/// reachability, opening details and crossing between the panes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('remote navigates the two-pane TV layout', (tester) async {
    if (await skipUnlessTV()) return;

    await clearAppData();
    for (var i = 1; i <= 6; i++) {
      await seedAppJson(appJson(id: 'e2e.tv$i', name: 'E2E TV $i'));
    }
    await launchApp(tester);

    // The first tile is focused automatically.
    await pumpUntilTrue(
      tester,
      () => focusIsInside<AppListTile>(),
      reason: 'initial tile focus',
    );
    final firstFocus = FocusManager.instance.primaryFocus;

    // Down moves to another tile.
    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    await pumpUntilTrue(
      tester,
      () =>
          focusIsInside<AppListTile>() &&
          FocusManager.instance.primaryFocus != firstFocus,
      reason: 'tile traversal',
    );

    // Up repeatedly reaches the app bar buttons.
    var reachedBar = false;
    for (var i = 0; i < 12 && !reachedBar; i++) {
      await pressKey(tester, LogicalKeyboardKey.arrowUp);
      reachedBar =
          focusIsOnTooltip('Settings') ||
          focusIsOnTooltip('Refresh') ||
          focusIsOnTooltip('Actions');
    }
    expect(reachedBar, isTrue, reason: 'app bar reachable with the remote');

    // Back down to a tile and open its details.
    var onTile = false;
    for (var i = 0; i < 12 && !onTile; i++) {
      await pressKey(tester, LogicalKeyboardKey.arrowDown);
      onTile = focusIsInside<AppListTile>();
    }
    expect(onTile, isTrue, reason: 'back to the app list');
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.textContaining('Last update check'));
    expect(find.text('Select an app to see details'), findsNothing);

    // Right crosses into the detail pane (URL link is the first stop).
    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await pumpUntilTrue(
      tester,
      () => focusIsInside<LinkText>(),
      reason: 'detail pane focus',
    );

    // Left returns to the list.
    await pressKey(tester, LogicalKeyboardKey.arrowLeft);
    await pumpUntilTrue(
      tester,
      () => focusIsInside<AppListTile>(),
      reason: 'list focus restored',
    );

    restoreErrorWidgetBuilder();
  });
}
