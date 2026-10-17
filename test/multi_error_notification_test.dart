import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/notifications_provider.dart';

void main() {
  setUpAll(() {
    Localization.load(
      const Locale('en'),
      translations: Translations(
        jsonDecode(File('assets/translations/en.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
    );
  });

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
    expect(capped, contains('more errors'));
    expect(capped.length, lessThanOrEqualTo(200));
  });

  test('the default cap fits Android notification text limits', () {
    final e = MultiAppMultiError();
    for (var i = 0; i < 30; i++) {
      e.add(
        'com.example.app$i',
        Exception(
          'error number $i with a deliberately long explanation that mirrors '
          'an HTTP failure from a real source and pushes the list over the limit',
        ),
      );
    }

    final capped = e.notificationErrorString();
    expect(capped, contains('more error'));
    expect(capped.length, lessThanOrEqualTo(900));
  });

  test('a single oversized error is truncated without losing the list', () {
    final e = MultiAppMultiError();
    e.add('com.example.app0', Exception('x' * 2000));

    final capped = e.notificationErrorString();
    expect(capped.length, lessThanOrEqualTo(900));
    expect(capped, endsWith('…'));
    expect(capped, isNot(contains('and 0 more')));
  });

  test('error notification uses an expandable big-text style', () {
    final n = ErrorCheckingUpdatesNotification('boom');
    expect(n.message, 'boom');
    expect(n.style, isA<BigTextStyleInformation>());
    expect((n.style! as BigTextStyleInformation).bigText, 'boom');
  });
}
