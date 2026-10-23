import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/apps_provider_lifecycle.dart';

void main() {
  group('isIconCacheUsable', () {
    final cacheTime = DateTime.fromMillisecondsSinceEpoch(2000);

    test('false when the cache file does not exist', () {
      expect(
        isIconCacheUsable(
          cacheExists: false,
          cacheModified: null,
          packageLastUpdateTime: 1000,
        ),
        isFalse,
      );
    });

    test('false when ignoreCache is set even if the cache is current', () {
      expect(
        isIconCacheUsable(
          ignoreCache: true,
          cacheExists: true,
          cacheModified: cacheTime,
          packageLastUpdateTime: 1000,
        ),
        isFalse,
      );
    });

    test('true when the cache is newer than the last package update', () {
      expect(
        isIconCacheUsable(
          cacheExists: true,
          cacheModified: cacheTime,
          packageLastUpdateTime: 1000,
        ),
        isTrue,
      );
    });

    test('true when the cache matches the last package update', () {
      expect(
        isIconCacheUsable(
          cacheExists: true,
          cacheModified: cacheTime,
          packageLastUpdateTime: cacheTime.millisecondsSinceEpoch,
        ),
        isTrue,
      );
    });

    test('false when the package was updated after the cache was written', () {
      expect(
        isIconCacheUsable(
          cacheExists: true,
          cacheModified: cacheTime,
          packageLastUpdateTime: cacheTime.millisecondsSinceEpoch + 1,
        ),
        isFalse,
      );
    });

    test('true when the package update time is unknown', () {
      expect(
        isIconCacheUsable(
          cacheExists: true,
          cacheModified: cacheTime,
          packageLastUpdateTime: null,
        ),
        isTrue,
      );
    });

    test('true when the cache modification time is unknown', () {
      expect(
        isIconCacheUsable(
          cacheExists: true,
          cacheModified: null,
          packageLastUpdateTime: 1000,
        ),
        isTrue,
      );
    });
  });

  group('loadAppIconSafely', () {
    test('returns the loaded icon bytes', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(await loadAppIconSafely(() async => bytes), same(bytes));
    });

    test('returns the fallback when loading throws', () async {
      final fallback = Uint8List.fromList([4, 5]);
      final result = await loadAppIconSafely(
        () async => throw PlatformException(
          code: 'error',
          message: 'width and height must be > 0',
        ),
        fallback: fallback,
      );
      expect(result, same(fallback));
    });

    test('returns the fallback when no loader is available', () async {
      final fallback = Uint8List.fromList([6]);
      expect(await loadAppIconSafely(null, fallback: fallback), same(fallback));
    });

    test('returns null when loading fails without a fallback', () async {
      expect(
        await loadAppIconSafely(
          () async => throw PlatformException(code: 'error'),
        ),
        isNull,
      );
    });
  });
}
