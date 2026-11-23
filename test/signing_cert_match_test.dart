import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/utils/signing_cert_utils.dart';

void main() {
  group('signingCertsMatch', () {
    test('matches identical certificates', () {
      expect(
        signingCertsMatch(
          installedHashes: const {'current'},
          apkHashes: const {'current'},
          apkHasPastSigningCertificates: false,
        ),
        isTrue,
      );
    });

    test('matches when the installed history is a superset', () {
      expect(
        signingCertsMatch(
          installedHashes: const {'old', 'current'},
          apkHashes: const {'current'},
          apkHasPastSigningCertificates: false,
        ),
        isTrue,
      );
    });

    test('accepts a rotated APK that carries the installed certificate', () {
      expect(
        signingCertsMatch(
          installedHashes: const {'current'},
          apkHashes: const {'old', 'current'},
          apkHasPastSigningCertificates: true,
        ),
        isTrue,
      );
    });

    test('does not trust an APK history without a lineage', () {
      expect(
        signingCertsMatch(
          installedHashes: const {'current'},
          apkHashes: const {'old', 'current'},
          apkHasPastSigningCertificates: false,
        ),
        isFalse,
      );
    });

    test('rejects an APK signed only with a past certificate', () {
      expect(
        signingCertsMatch(
          installedHashes: const {'current'},
          apkHashes: const {'old'},
          apkHasPastSigningCertificates: true,
        ),
        isFalse,
      );
    });

    test('rejects unrelated certificates', () {
      expect(
        signingCertsMatch(
          installedHashes: const {'current'},
          apkHashes: const {'attacker'},
          apkHasPastSigningCertificates: true,
        ),
        isFalse,
      );
    });

    test('rejects empty hash sets', () {
      expect(
        signingCertsMatch(
          installedHashes: const {},
          apkHashes: const {'current'},
          apkHasPastSigningCertificates: true,
        ),
        isFalse,
      );
      expect(
        signingCertsMatch(
          installedHashes: const {'current'},
          apkHashes: const {},
          apkHasPastSigningCertificates: true,
        ),
        isFalse,
      );
    });
  });
}
