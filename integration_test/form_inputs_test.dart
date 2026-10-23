import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/providers/settings_provider.dart';

import 'e2e_helpers.dart';

/// Confirms real settings controls write through to the provider. The
/// generated-form input types themselves are sampled in
/// test/generated_form_inputs_test.dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('settings toggle and text field write through', (tester) async {
    if (await skipIfTV()) return;

    await clearAppData();
    await launchApp(tester);
    await pumpUntil(tester, find.text('No apps'));

    await tester.tap(find.byTooltip('Settings'));
    await pumpUntil(tester, find.text('Updates'));
    await tester.tap(find.text('Updates').first);
    await pumpFor(tester, const Duration(seconds: 1));

    final settings = readProvider<SettingsProvider>();
    expect(settings.checkOnStart, isFalse);

    final toggle = find.widgetWithText(
      ListTile,
      'Check for updates on startup',
    );
    for (var i = 0; i < 10 && toggle.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await pumpFor(tester, const Duration(milliseconds: 200));
    }
    await tester.tap(
      find.descendant(of: toggle, matching: find.byType(Switch)),
    );
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(settings.checkOnStart, isTrue);

    final field = find.widgetWithText(TextFormField, 'Global APK filter regex');
    for (var i = 0; i < 10 && field.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await pumpFor(tester, const Duration(milliseconds: 200));
    }
    await tester.enterText(field, 'e2e-input-sample');
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(settings.globalApkFilterRegEx, 'e2e-input-sample');

    final versionField = find.widgetWithText(
      TextFormField,
      'Global version trimming regex',
    );
    await tester.enterText(versionField, r'\d+(\.\d+)+');
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(settings.globalVersionExtractionRegEx, r'\d+(\.\d+)+');

    final groupField = find.widgetWithText(
      TextFormField,
      'Match group to use for "Global version trimming regex"',
    );
    await tester.enterText(groupField, '0');
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(settings.globalMatchGroupToUse, '0');

    restoreErrorWidgetBuilder();
  });
}
