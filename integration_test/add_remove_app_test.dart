import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/providers/apps_provider.dart';

import 'e2e_helpers.dart';

/// Adds an app through the UI using the Direct APK Link source pointed at the
/// runner's local HTTP server, then removes it again. Covers source
/// detection, the "allow insecure" toggle, APK download/parsing and removal.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('add an app from a direct APK link and remove it', (
    tester,
  ) async {
    if (await skipIfTV()) return;

    await clearAppData();
    await launchApp(tester);

    // Nothing tracked yet.
    await pumpUntil(tester, find.text('No apps'));

    // Open Add App and enter the direct link.
    await tester.tap(find.text('Add'));
    await pumpUntil(tester, find.text('Add app'));
    await tester.enterText(
      find.byType(TextFormField).first,
      '$e2eBaseUrl/testapp-v2.apk',
    );
    await pumpUntil(
      tester,
      find.text('Allow insecure HTTP requests'),
      reason: 'source-specific options',
    );

    // Allow plain HTTP so the local server can be reached.
    final allowTile = find.widgetWithText(
      ListTile,
      'Allow insecure HTTP requests',
    );
    await tester.scrollUntilVisible(
      allowTile,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(
      find.descendant(of: allowTile, matching: find.byType(Switch)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Add the app (scroll back up to the URL row first).
    final addButton = find.widgetWithIcon(IconButton, Icons.add_rounded);
    await tester.scrollUntilVisible(
      addButton,
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(addButton);
    await pumpFor(tester, const Duration(seconds: 1));

    // The source can't infer the package id from a bare URL, so Obtainium
    // asks which file to download and then parses the APK for the real id.
    if (find.text('Pick an APK').evaluate().isNotEmpty) {
      await tester.tap(find.text('Continue'));
      await pumpFor(tester, const Duration(seconds: 1));
    }

    // Now on the app's detail page (id parsed from the downloaded APK).
    await pumpUntil(
      tester,
      find.textContaining(e2eTestPackageId),
      timeout: const Duration(seconds: 60),
      reason: 'app detail',
    );

    // The APK was downloaded and kept in the apk cache.
    final appsProvider = readProvider<AppsProvider>();
    await pumpUntilTrue(
      tester,
      () => appsProvider.apkDir.listSync().any(
        (e) => e.path.split('/').last.startsWith(e2eTestPackageId),
      ),
      timeout: const Duration(seconds: 30),
      reason: 'downloaded APK',
    );

    // Remove it from the list via the detail page's delete action.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await pumpUntil(tester, find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await pumpUntilTrue(
      tester,
      () => !appsProvider.apps.containsKey(e2eTestPackageId),
      reason: 'app removed',
    );
    await pumpUntil(tester, find.text('No apps'));

    restoreErrorWidgetBuilder();
  });
}
