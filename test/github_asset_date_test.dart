import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/app_sources/github.dart';

void main() {
  test('falls back to all assets when the APK filter leaves none', () {
    final release = {
      'assets': [
        {'created_at': '2026-01-02T04:00:00Z', 'updated_at': null},
        {'created_at': '2026-01-02T05:00:00Z', 'updated_at': null},
      ],
      'filteredAssets': <dynamic>[],
    };

    expect(newestAssetDateFromRelease(release), DateTime.utc(2026, 1, 2, 5));
  });

  test('prefers a non-empty filtered asset list', () {
    final release = {
      'assets': [
        {'created_at': '2026-01-02T04:00:00Z', 'updated_at': null},
        {'created_at': '2026-01-02T05:00:00Z', 'updated_at': null},
      ],
      'filteredAssets': [
        {'created_at': '2026-01-02T03:00:00Z', 'updated_at': null},
      ],
    };

    expect(newestAssetDateFromRelease(release), DateTime.utc(2026, 1, 2, 3));
  });

  test('prefers updated_at and accepts created_at when it is absent', () {
    final release = {
      'assets': [
        {
          'created_at': '2026-01-02T04:00:00Z',
          'updated_at': '2026-01-02T06:00:00Z',
        },
        {'created_at': '2026-01-02T05:00:00Z', 'updated_at': null},
      ],
    };

    expect(newestAssetDateFromRelease(release), DateTime.utc(2026, 1, 2, 6));
  });

  test('returns null without parseable asset dates', () {
    expect(newestAssetDateFromRelease({'assets': <dynamic>[]}), isNull);
    expect(newestAssetDateFromRelease({}), isNull);
  });
}
