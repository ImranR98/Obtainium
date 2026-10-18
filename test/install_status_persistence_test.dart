import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/apps_provider_lifecycle.dart';

void main() {
  group('resolveBulkOrLookup', () {
    test('uses the bulk entry when present', () async {
      var lookedUp = false;
      final result = await resolveBulkOrLookup<String>(
        'app',
        {'app': 'bulk'},
        lookup: (_) async {
          lookedUp = true;
          return 'lookup';
        },
      );

      expect(result, 'bulk');
      expect(lookedUp, isFalse);
    });

    test(
      'confirms with a per-app lookup when the bulk list misses it',
      () async {
        var lookupKey = '';
        final result = await resolveBulkOrLookup<String>(
          'app',
          const {},
          lookup: (key) async {
            lookupKey = key;
            return 'lookup';
          },
        );

        expect(result, 'lookup');
        expect(lookupKey, 'app');
      },
    );

    test('returns null when both sources miss', () async {
      final result = await resolveBulkOrLookup<String>(
        'app',
        const {},
        lookup: (_) async => null,
      );
      expect(result, isNull);
    });
  });

  group('shouldClearInstalledVersion', () {
    bool clear({
      bool installedInfoMissing = true,
      bool trackOnly = false,
      bool isBackground = false,
      bool versionDetectionIsStandard = false,
      String? installedVersion = 'v1.0',
      String latestVersion = 'v1.0',
    }) => shouldClearInstalledVersion(
      installedInfoMissing: installedInfoMissing,
      trackOnly: trackOnly,
      isBackground: isBackground,
      versionDetectionIsStandard: versionDetectionIsStandard,
      installedVersion: installedVersion,
      latestVersion: latestVersion,
    );

    test('background load preserves a marked-updated version', () {
      expect(clear(isBackground: true), isFalse);
    });

    test('background load still clears an up-to-date standard app', () {
      expect(
        clear(isBackground: true, versionDetectionIsStandard: true),
        isTrue,
      );
    });

    test('foreground load clears a genuinely missing install', () {
      expect(clear(), isTrue);
    });

    test('background load still clears an older installed version', () {
      expect(
        clear(
          isBackground: true,
          installedVersion: '0.9',
          latestVersion: '1.0',
        ),
        isTrue,
      );
    });

    test('track-only and missing recorded versions are left alone', () {
      expect(clear(trackOnly: true), isFalse);
      expect(clear(installedVersion: null), isFalse);
    });
  });
}
