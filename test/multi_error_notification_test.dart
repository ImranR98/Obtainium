import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/notifications_provider.dart';

void main() {
  test('notificationErrorString joins groups and caps surplus ones', () {
    final e = MultiAppMultiError();
    for (var i = 0; i < 50; i++) {
      e.add('com.example.app$i', Exception('error number $i'));
    }

    final full = e.notificationErrorString(maxChars: 100000);
    expect(full, contains('error number 0'));
    expect(full, contains('error number 49'));

    final capped = e.notificationErrorString(maxChars: 200);
    expect(capped, contains('error number 0'));
    expect(capped, isNot(contains('error number 49')));
    expect(capped.length, lessThan(400));
  });

  test('error notification uses an expandable big-text style', () {
    final n = ErrorCheckingUpdatesNotification('boom');
    expect(n.message, 'boom');
    expect(n.style, isA<BigTextStyleInformation>());
    expect((n.style! as BigTextStyleInformation).bigText, 'boom');
  });
}
