import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'e2e_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('update health link wording depends on the reason', (
    tester,
  ) async {
    if (await skipIfTV()) return;

    await clearAppData();
    final stale =
        appJson(
            id: 'e2e.stale',
            name: 'E2E Stale',
            additionalSettings: const {
              'versionDetection': true,
              'updateHealthStaleRelease': '30',
            },
          )
          ..['releaseDate'] = DateTime.now()
              .subtract(const Duration(days: 90))
              .microsecondsSinceEpoch;
    final config = appJson(
      id: 'e2e.config',
      name: 'E2E Config',
      additionalSettings: const {'versionDetection': true},
    )..['consecutiveFailedChecks'] = 5;
    await seedAppJson(stale);
    await seedAppJson(config);
    await launchApp(tester);
    addTearDown(restoreErrorWidgetBuilder);

    await pumpUntil(tester, find.text('E2E Stale'));
    await tester.tap(find.text('E2E Stale'));
    await pumpUntil(tester, find.text('No update detected recently'));

    await tester.pageBack();
    await pumpUntil(tester, find.text('E2E Config'));
    await tester.tap(find.text('E2E Config'));
    await pumpUntil(tester, find.text('This app config may prevent updates'));
  });
}
