import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/services/apk_filter_service.dart';

void main() {
  group('splitMultiApkUrl', () {
    test('returns a single URL unchanged', () {
      expect(splitMultiApkUrl('https://example.com/app.apk'), [
        'https://example.com/app.apk',
      ]);
    });

    test('splits a joined base + splits value', () {
      expect(
        splitMultiApkUrl(
          'https://example.com/base.zip\n'
          'https://example.com/config.arm64_v8a.zip\n'
          'https://example.com/config.xxhdpi.zip',
        ),
        [
          'https://example.com/base.zip',
          'https://example.com/config.arm64_v8a.zip',
          'https://example.com/config.xxhdpi.zip',
        ],
      );
    });

    test('returns no URLs for an empty value', () {
      expect(splitMultiApkUrl(''), isEmpty);
    });

    test('drops empty segments', () {
      expect(splitMultiApkUrl('a\n\nb'), ['a', 'b']);
    });
  });

  group('joinMultiApkUrl', () {
    test('round-trips a split set', () {
      final urls = [
        'https://example.com/base.apk',
        'https://example.com/config.arm64_v8a.apk',
      ];
      expect(splitMultiApkUrl(joinMultiApkUrl(urls)), urls);
    });

    test('a joined value cannot be mistaken for a plain URL', () {
      final joined = joinMultiApkUrl([
        'https://example.com/a.apk',
        'https://example.com/b.apk',
      ]);
      expect(joined.contains(ApkFilterService.multiApkUrlSeparator), isTrue);
    });
  });
}
