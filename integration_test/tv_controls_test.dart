import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/components/app_list_tile.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/document_tree_bridge.dart';
import 'package:obtainium/providers/settings_provider.dart';

import 'e2e_helpers.dart';

/// TV-specific controls, driven exclusively through remote-control keys: no
/// pointer taps, which a remote cannot produce.
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

    // The first tile is focused automatically; no checkboxes until selection
    // mode is enabled.
    await pumpUntilTrue(tester, () => focusIsInside<AppListTile>());
    expect(find.byType(Checkbox), findsNothing);

    // Enter selection mode from the app bar with the remote.
    await focusAppBarButton(tester, 'Actions');
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.byType(Checkbox), findsWidgets);
    expect(find.textContaining('Actions ('), findsOneWidget);

    // Selecting a tile toggles its selection instead of opening it.
    await pressUntil(
      tester,
      LogicalKeyboardKey.arrowDown,
      () => focusIsInside<AppListTile>(),
      reason: 'tile reachable in selection mode',
    );
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.text('Actions (1)'));
    expect(find.text('Select an app to see details'), findsOneWidget);

    // Leave selection mode through the close button.
    await focusAppBarButton(tester, 'Close');
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.textContaining('Actions ('), findsNothing);

    // Settings -> Appearance -> open the "App sort by" dropdown with select.
    await focusAppBarButton(tester, 'Settings');
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.text('Appearance'));
    await pressUntil(
      tester,
      LogicalKeyboardKey.arrowDown,
      () => focusIsOnText('Appearance'),
      reason: 'Appearance row reachable',
    );
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.text('App sort by'));

    var onDropdown = false;
    for (var i = 0; i < 12 && !onDropdown; i++) {
      await pressKey(tester, LogicalKeyboardKey.arrowDown);
      onDropdown = focusIsWithin<DropdownMenu<SortColumnSettings>>();
    }
    expect(onDropdown, isTrue, reason: 'dropdown focusable with the remote');

    // Select opens the TV picker dialog; the current value is focused.
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.text('Release date'));
    // Move from the current value ("Name/author") to "As added" and pick it.
    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(
      readProvider<SettingsProvider>().sortColumn,
      SortColumnSettings.added,
      reason: 'picking an entry applies it',
    );
    expect(find.text('Release date'), findsNothing);

    // BACK dismisses the dialog without leaving the page.
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.text('Release date'));
    await pressBack(tester);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Release date'), findsNothing);
    expect(find.text('Appearance'), findsOneWidget);

    restoreErrorWidgetBuilder();
  });

  testWidgets('TV pages start focused and select-all is not a no-op', (
    tester,
  ) async {
    if (await skipUnlessTV()) return;

    await clearAppData();
    await seedAppJson(appJson(id: 'e2e.focus', name: 'E2E Focus'));
    await launchApp(tester);
    await pumpUntil(tester, find.text('E2E Focus'));

    // The select-all chip selects every app and enters selection mode, so
    // the checkboxes and the footer actions appear immediately.
    await pumpUntilTrue(tester, () => focusIsInside<AppListTile>());
    await pressUntil(
      tester,
      LogicalKeyboardKey.arrowUp,
      () => focusIsOnText('1'),
      reason: 'select-all chip reachable',
    );
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.textContaining('Actions (1)'));
    expect(find.byType(Checkbox), findsWidgets);
    await pressBack(tester);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.textContaining('Actions ('), findsNothing);

    // The Settings page opens with its first row focused, so select goes
    // straight to the Import/export page.
    await focusAppBarButton(tester, 'Settings');
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpFor(tester, const Duration(milliseconds: 800));
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.text('Pick export directory'));
    await pressBack(tester);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await pressBack(tester);
    await pumpFor(tester, const Duration(milliseconds: 500));

    // The Add app page opens with the URL field focused; reach it from the
    // home footer with the remote.
    await pressUntil(
      tester,
      LogicalKeyboardKey.arrowDown,
      () => focusIsOnText('Add app'),
      reason: 'Add app footer reachable',
    );
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(
      focusIsWithin<TvTextFieldFocus>(),
      isTrue,
      reason: 'Add app opens with the URL field focused',
    );
    // The add/search actions are rendered beside the field on TV so the
    // remote can reach them instead of being trapped inside the text field.
    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(
      focusIsWithin<IconButton>(),
      isTrue,
      reason: 'Add app field action reachable with the remote',
    );
    await pressBack(tester);
    await pumpFor(tester, const Duration(milliseconds: 500));

    // The colour picker is a focusable palette instead of the unusable
    // gesture-driven dialog: open it and confirm it with select.
    await focusAppBarButton(tester, 'Settings');
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.text('Appearance'));
    await pressUntil(
      tester,
      LogicalKeyboardKey.arrowDown,
      () => focusIsOnText('Appearance'),
      reason: 'Appearance row reachable',
    );
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.text('Select colour'));

    var onColourRow = false;
    for (var i = 0; i < 12 && !onColourRow; i++) {
      await pressKey(tester, LogicalKeyboardKey.arrowDown);
      onColourRow = focusIsWithin<ColorIndicator>();
    }
    expect(onColourRow, isTrue, reason: 'colour row focusable with the remote');
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.text('Continue'));
    // Walk down the palette to the dialog's actions and confirm.
    for (var i = 0; i < 12; i++) {
      await pressKey(tester, LogicalKeyboardKey.arrowDown);
    }
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Continue'), findsNothing, reason: 'dialog confirmed');

    restoreErrorWidgetBuilder();
  });

  testWidgets('TV exports and imports through Downloads without a picker', (
    tester,
  ) async {
    if (await skipUnlessTV()) return;

    await clearAppData();
    await seedAppJson(appJson(id: 'e2e.downloads', name: 'E2E Downloads'));
    await launchApp(tester);
    await pumpUntil(tester, find.text('E2E Downloads'));

    final settings = readProvider<SettingsProvider>();
    await settings.useDownloadsExportDir();
    await pumpFor(tester, const Duration(milliseconds: 300));

    // Import/export offers the Downloads destination on TV.
    await focusAppBarButton(tester, 'Settings');
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.text('Import/export'));
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.text('Pick export directory'));
    expect(find.text('Use the Downloads folder'), findsOneWidget);

    // Export with the remote; the file lands in Downloads/Obtainium.
    await pressUntil(
      tester,
      LogicalKeyboardKey.arrowDown,
      () => focusIsOnText('Obtainium export'),
      reason: 'export row reachable',
    );
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpFor(tester, const Duration(seconds: 2));
    final bridge = DocumentTreeBridge.instance;
    var exports = await bridge.downloadsExports();
    expect(exports, isNotEmpty, reason: 'export written to Downloads');

    // Auto-export replaces the previous -auto file on every change.
    settings.autoExportOnChanges = true;
    final apps = readProvider<AppsProvider>();
    final app = apps.apps['e2e.downloads']!.app;
    await apps.saveApps([app]);
    await pumpFor(tester, const Duration(seconds: 4));
    exports = await bridge.downloadsExports();
    expect(exports.where((e) => e.name.endsWith('-auto.json')), hasLength(1));
    await apps.saveApps([app]);
    await pumpFor(tester, const Duration(seconds: 4));
    exports = await bridge.downloadsExports();
    expect(
      exports.where((e) => e.name.endsWith('-auto.json')),
      hasLength(1),
      reason: 'the previous -auto export is pruned',
    );

    // Import the newest export through the Downloads list.
    await pressUntil(
      tester,
      LogicalKeyboardKey.arrowDown,
      () => focusIsOnText('Import from Downloads'),
      reason: 'import row reachable',
    );
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.textContaining('.json'));
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.text('Continue'));
    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await pressKey(tester, LogicalKeyboardKey.select);
    await pumpUntil(tester, find.textContaining('Imported'));

    restoreErrorWidgetBuilder();
  });
}
