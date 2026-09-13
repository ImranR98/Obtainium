import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/components/app_list_tile.dart';
import 'package:obtainium/providers/settings_provider.dart';

import 'e2e_helpers.dart';

/// The app list density setting must shrink rows step by step and be reachable
/// from Settings -> Appearance (#2620).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app list density reduces row height', (tester) async {
    if (await skipIfTV()) return;

    await clearAppData();
    for (var i = 1; i <= 5; i++) {
      await seedAppJson(appJson(id: 'e2e.app$i', name: 'E2E App $i'));
    }
    await launchApp(tester);
    await pumpUntil(tester, find.text('E2E App 1'));

    final settings = readProvider<SettingsProvider>();
    double tileHeight() =>
        tester.getSize(find.byType(AppListTile).first).height;

    expect(settings.appListDensity, AppListDensity.standard);
    final standardHeight = tileHeight();

    settings.appListDensity = AppListDensity.compact;
    await pumpFor(tester, const Duration(milliseconds: 300));
    final compactHeight = tileHeight();

    settings.appListDensity = AppListDensity.dense;
    await pumpFor(tester, const Duration(milliseconds: 300));
    final denseHeight = tileHeight();

    expect(compactHeight, lessThan(standardHeight));
    expect(denseHeight, lessThan(compactHeight));

    // The control is reachable from Settings -> Appearance.
    await tester.tap(find.byTooltip('Settings'));
    await pumpUntil(tester, find.text('Appearance'));
    await tester.tap(find.text('Appearance'));
    await pumpUntil(tester, find.text('App sort by'));
    final densityLabel = find.text('App list density');
    await tester.scrollUntilVisible(
      densityLabel,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(densityLabel, findsOneWidget);

    // ignore: avoid_print
    print(
      'DENSITY_RESULT standard=$standardHeight '
      'compact=$compactHeight dense=$denseHeight',
    );
    restoreErrorWidgetBuilder();
  });
}
