import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/app_sources/rustore.dart';
import 'package:obtainium/services/apk_filter_service.dart';

void main() {
  group('apkUrlsFromDownloadUrls', () {
    test('uses a single .apk URL as-is', () {
      const url = 'https://static-m.rustore.ru/version/4/accubattery.apk';
      final result = apkUrlsFromDownloadUrls([url]);
      expect(result, hasLength(1));
      expect(result.first.key, 'accubattery.apk');
      expect(result.first.value, url);
    });

    test('converts a single .zip URL to its .apk sibling', () {
      final result = apkUrlsFromDownloadUrls([
        'https://static-m.rustore.ru/version/4/app.zip',
      ]);
      expect(
        result.single.value,
        'https://static-m.rustore.ru/version/4/app.apk',
      );
    });

    test('joins multiple URLs into one base + splits entry', () {
      final urls = [
        'https://static-m.rustore.ru/2026/9/12/base.zip',
        'https://static-m.rustore.ru/2026/9/12/config.arm64_v8a.zip',
        'https://static-m.rustore.ru/2026/9/12/config.xxhdpi.zip',
      ];
      final result = apkUrlsFromDownloadUrls(urls);
      expect(result, hasLength(1));
      expect(result.single.key, 'base.zip');
      expect(splitMultiApkUrl(result.single.value), urls);
    });
  });
}
