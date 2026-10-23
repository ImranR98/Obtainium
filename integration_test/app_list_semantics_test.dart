import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/components/app_list_tile.dart';

import 'e2e_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app row keeps details and changelog as separate semantics', (
    tester,
  ) async {
    if (await skipIfTV()) return;

    final handle = tester.ensureSemantics();
    await clearAppData();
    await seedAppJson(
      appJson(
        id: 'e2e.semantics',
        name: 'E2E Semantics',
        installedVersion: '1.0.0',
        latestVersion: '2.0.0',
        releaseUrl: 'https://example.com/changes',
        additionalSettings: const {'versionDetection': true, 'trackOnly': true},
      ),
    );
    await launchApp(tester);
    await pumpUntil(tester, find.text('E2E Semantics'));

    final row = tester
        .getSemantics(find.byType(AppListTile))
        .getSemanticsData();
    expect(row.label, contains('E2E Semantics'));
    expect(row.label, isNot(contains('1.0.0')));
    expect(row.label, isNot(contains('2.0.0')));
    expect(row.hasAction(SemanticsAction.tap), isTrue);

    final version = find.bySemanticsLabel(RegExp(r'1\.0\.0.*2\.0\.0'));
    expect(version, findsOneWidget);
    final versionData = tester.getSemantics(version).getSemanticsData();
    expect(versionData.label, contains('Changes'));
    expect(versionData.hasAction(SemanticsAction.tap), isTrue);

    handle.dispose();
    restoreErrorWidgetBuilder();
  });
}
