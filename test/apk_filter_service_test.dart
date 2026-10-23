import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/services/apk_filter_service.dart';

void main() {
  final service = ApkFilterService();

  MapEntry<String, String> apk(String name) =>
      MapEntry(name, 'https://example.com/$name');

  test('keeps universal APKs alongside the ABI-specific match', () async {
    final filtered = await service.filterApksByArch(
      [
        apk('app-arm64-v8a.apk'),
        apk('app-armeabi-v7a.apk'),
        apk('app-universal.apk'),
      ],
      ['arm64-v8a'],
    );

    expect(filtered.map((e) => e.key), [
      'app-universal.apk',
      'app-arm64-v8a.apk',
    ]);
  });

  test('puts universal first so the ABI match stays the default', () async {
    final filtered = await service.filterApksByArch(
      [apk('app-universal.apk'), apk('app-arm64-v8a.apk')],
      ['arm64-v8a'],
    );

    expect(filtered.last.key, 'app-arm64-v8a.apk');
  });

  test('does not duplicate universal entries', () async {
    final filtered = await service.filterApksByArch(
      [apk('app-universal-arm64-v8a.apk'), apk('app-universal.apk')],
      ['arm64-v8a'],
    );

    expect(filtered.map((e) => e.key).toSet(), {
      'app-universal-arm64-v8a.apk',
      'app-universal.apk',
    });
    expect(filtered.length, 2);
  });

  test('leaves the list alone when no ABI matches', () async {
    final urls = [apk('app-universal.apk'), apk('app-x86.apk')];
    final filtered = await service.filterApksByArch(urls, ['arm64-v8a']);
    expect(filtered, urls);
  });
}
