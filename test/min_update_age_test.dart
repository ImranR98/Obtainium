import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/utils/min_update_age.dart';

App _app({
  required String latestVersion,
  DateTime? releaseDate,
  String? changeLog,
  List<MapEntry<String, String>> apkUrls = const [],
}) => App(
  id: 'com.example.app',
  url: 'https://example.com/app',
  author: 'Author',
  name: 'App',
  latestVersion: latestVersion,
  apkUrls: apkUrls,
  preferredApkIndex: 0,
  additionalSettings: const {},
  releaseDate: releaseDate,
  changeLog: changeLog,
);

void main() {
  group('isReleaseTooYoung', () {
    final now = DateTime(2026, 9, 12, 12);

    test('true when younger than the minimum age', () {
      expect(isReleaseTooYoung(DateTime(2026, 9, 7), 14, now: now), isTrue);
    });

    test('false when old enough', () {
      expect(isReleaseTooYoung(DateTime(2026, 8, 28), 14, now: now), isFalse);
    });

    test('false without a release date', () {
      expect(isReleaseTooYoung(null, 14, now: now), isFalse);
    });

    test('false when the minimum age is disabled', () {
      expect(isReleaseTooYoung(DateTime(2026, 9, 11), 0, now: now), isFalse);
    });
  });

  group('effectiveMinUpdateAgeDays', () {
    test('uses a per-app override', () async {
      expect(await effectiveMinUpdateAgeDays({'minimumUpdateAgeDays': '7'}), 7);
    });
  });

  group('applyMinAgeSuppression', () {
    test('keeps the current version, date, changelog and APK URLs', () {
      final current = _app(
        latestVersion: '0.12.6',
        releaseDate: DateTime(2026, 8, 28),
        changeLog: 'old',
        apkUrls: const [
          MapEntry('old.apk', 'https://example.com/0.12.6/old.apk'),
        ],
      );
      final fetched = _app(
        latestVersion: '0.12.8',
        releaseDate: DateTime(2026, 9, 7),
        changeLog: 'new',
        apkUrls: const [
          MapEntry('new.apk', 'https://example.com/0.12.8/new.apk'),
        ],
      );
      final result = applyMinAgeSuppression(current, fetched);
      expect(result.latestVersion, '0.12.6');
      expect(result.releaseDate, DateTime(2026, 8, 28));
      expect(result.changeLog, 'old');
      expect(result.apkUrls.single.key, 'old.apk');
      expect(result.apkUrls.single.value, 'https://example.com/0.12.6/old.apk');
      // Non-release metadata still comes from the fetch.
      expect(result.name, fetched.name);
    });
  });
}
