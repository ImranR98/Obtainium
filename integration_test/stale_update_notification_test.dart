import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/pages/apps.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';

import 'e2e_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('successful check clears a stale update notification', (
    tester,
  ) async {
    if (await skipIfTV()) return;

    await clearAppData();
    await seedAppJson(
      appJson(id: 'e2e.stale', name: 'E2E Stale', disabled: true),
    );
    await launchApp(tester);
    await pumpUntil(tester, find.text('E2E Stale'));

    final apps = readProvider<AppsProvider>();
    final notifications = readProvider<NotificationsProvider>();
    await notifications.cancel(updateNotificationId);
    await notifications.notify(
      UpdateNotification([apps.apps['e2e.stale']!.app]),
    );
    await pumpFor(tester, const Duration(seconds: 1));

    final before = await notifications.notifications.getActiveNotifications();
    expect(before.any((n) => n.id == updateNotificationId), isTrue);

    final state = tester.state<AppsPageState>(find.byType(AppsPage));
    await state.refresh();
    await pumpFor(tester, const Duration(seconds: 1));

    final after = await notifications.notifications.getActiveNotifications();
    expect(after.any((n) => n.id == updateNotificationId), isFalse);

    restoreErrorWidgetBuilder();
  });
}
