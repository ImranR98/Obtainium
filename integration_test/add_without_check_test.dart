import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/providers/apps_provider.dart';

import 'e2e_helpers.dart';

/// #3345: with the "add without checking" setting enabled, an unexpected
/// failure while adding offers to save a placeholder entry; with it disabled
/// the normal error path is used instead.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const unreachableUrl = 'http://127.0.0.1:1/app.apk';

  final addFab = find.widgetWithText(FloatingActionButton, 'Add');

  Future<void> enterUnreachableUrl(WidgetTester tester) async {
    await tester.tap(addFab);
    final urlField = find.widgetWithText(TextField, 'App source URL');
    await pumpUntil(tester, urlField);
    await tester.enterText(urlField, unreachableUrl);
    await pumpFor(tester, const Duration(milliseconds: 1500));
    final addButton = find.widgetWithIcon(IconButton, Icons.add_rounded);
    await pumpUntilTrue(
      tester,
      () =>
          addButton.evaluate().isNotEmpty &&
          tester.widget<IconButton>(addButton).onPressed != null,
      reason: 'add button enabled',
    );
    await tester.tap(addButton);
  }

  testWidgets('offers the placeholder fallback when enabled', (tester) async {
    if (await skipIfTV()) return;

    await clearAppData();
    await launchApp(tester, prefs: const {'allowAddingAppsWithoutCheck': true});
    await pumpUntil(tester, addFab);
    await enterUnreachableUrl(tester);

    await pumpUntil(
      tester,
      find.text('Add app without checking?'),
      timeout: const Duration(seconds: 30),
    );
    expect(find.text('Add anyway'), findsOneWidget);
    await tester.tap(find.text('Add anyway'));
    await pumpFor(tester, const Duration(seconds: 2));

    final appsProvider = readProvider<AppsProvider>();
    final app = appsProvider.apps.values
        .where((a) => a.app.url == unreachableUrl)
        .firstOrNull;
    expect(app, isNotNull, reason: 'placeholder app saved');
    expect(RegExp(r'^[0-9a-f]{12}$').hasMatch(app!.app.id), isTrue);
    expect(app.app.apkUrls.single.value, 'placeholder');

    restoreErrorWidgetBuilder();
  });

  testWidgets('uses the normal error path when disabled', (tester) async {
    if (await skipIfTV()) return;

    await clearAppData();
    await launchApp(tester);
    await pumpUntil(tester, addFab);
    await enterUnreachableUrl(tester);

    await pumpUntil(
      tester,
      find.textContaining('127.0.0.1:1'),
      timeout: const Duration(seconds: 30),
      reason: 'error dialog shown',
    );
    expect(find.text('Add app without checking?'), findsNothing);
    final appsProvider = readProvider<AppsProvider>();
    expect(appsProvider.apps, isEmpty);

    restoreErrorWidgetBuilder();
  });
}
