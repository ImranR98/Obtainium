import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/pages/add_app.dart';

import 'e2e_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('paste button fills the URL field from the clipboard', (
    tester,
  ) async {
    if (await skipIfTV()) return;

    await clearAppData();
    await launchApp(tester);
    await pumpUntil(tester, find.text('No apps'));
    await tester.tap(find.text('Add'));
    await pumpUntil(tester, find.text('Add app'));

    await Clipboard.setData(
      const ClipboardData(text: '  https://github.com/example/repro  '),
    );
    await tester.tap(find.byTooltip('Paste'));

    final state = tester.state<AddAppPageState>(find.byType(AddAppPage));
    await pumpUntilTrue(
      tester,
      () => state.pickedSource?.sourceIdentifier == 'GitHub',
      reason: 'GitHub source picked from pasted URL',
    );
    await pumpFor(tester, const Duration(milliseconds: 500));

    expect(state.userInput, 'https://github.com/example/repro');
    expect(find.text('https://github.com/example/repro'), findsOneWidget);

    restoreErrorWidgetBuilder();
  });
}
