import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/pages/add_app.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/components/ui_widgets.dart';

import 'e2e_helpers.dart';

/// Global add-app defaults (Settings > Updates > Include pre-releases by
/// default, Shizuku pretend to be Google Play) must land in the new app's
/// additionalSettings even when the user never touches the form (#3377).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('global add-app defaults are captured without form edits', (
    tester,
  ) async {
    if (await skipIfTV()) return;

    await clearAppData();
    await launchApp(
      tester,
      prefs: {
        'includePrereleasesByDefault': true,
        'shizukuPretendToBeGooglePlay': true,
      },
    );

    final settings = readProvider<SettingsProvider>();
    expect(settings.includePrereleasesByDefault, isTrue);
    expect(settings.shizukuPretendToBeGooglePlay, isTrue);

    await pumpUntil(tester, find.text('No apps'));
    await tester.tap(find.text('Add'));
    await pumpUntil(tester, find.text('Add app'));
    await tester.enterText(
      find.byType(TextFormField).first,
      'https://github.com/example/repro',
    );

    final state = tester.state<AddAppPageState>(find.byType(AddAppPage));
    await pumpUntilTrue(
      tester,
      () => state.pickedSource?.sourceIdentifier == 'GitHub',
      reason: 'GitHub source picked',
    );
    await pumpFor(tester, const Duration(milliseconds: 500));

    expect(state.additionalSettings['includePrereleases'], isTrue);
    expect(state.additionalSettings['shizukuPretendToBeGooglePlay'], isTrue);

    state.changeUserInput(
      'https://galaxystore.samsung.com/detail/com.example.app',
      true,
      false,
    );
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(state.additionalSettings['shizukuPretendToBeGooglePlay'], isTrue);
    expect(state.additionalSettings['shizukuPretendToBeGalaxyStore'], isFalse);
    final galaxySwitch = find.descendant(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is ToggleTile &&
            widget.label.contains('Set Samsung Galaxy Store'),
      ),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(galaxySwitch);
    await tester.pumpAndSettle();
    await tester.tap(galaxySwitch);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(state.additionalSettings['shizukuPretendToBeGalaxyStore'], isTrue);
    expect(state.additionalSettings['shizukuPretendToBeGooglePlay'], isFalse);
    expect(settings.shizukuPretendToBeGooglePlay, isTrue);
    await tester.tap(galaxySwitch);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(state.additionalSettings['shizukuPretendToBeGalaxyStore'], isFalse);
    expect(state.additionalSettings['shizukuPretendToBeGooglePlay'], isTrue);

    for (final profile in state.pickedSource!.searchProfiles) {
      state.changeUserInput(
        state.userInput,
        true,
        false,
        overrideSource: state.pickedSource!.sourceIdentifier,
        appSettings: profile.appSettings,
      );
      await pumpFor(tester, const Duration(milliseconds: 500));
      for (final setting in profile.appSettings.entries) {
        expect(state.additionalSettings[setting.key], setting.value);
      }
    }

    restoreErrorWidgetBuilder();
  });
}
