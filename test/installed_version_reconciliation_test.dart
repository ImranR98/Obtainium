import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/apps_provider.dart';

// `reconciledInstalledVersionFromLatest` and
// `reconciledInstalledVersionForDisabledVersionDetection` used to be top-level
// helpers in apps_provider.dart. They were inlined into
// AppsProvider.getCorrectedInstallStatusAppIfPossible (which drives App objects
// and is covered by version_order_test.dart) and removed from the public
// surface. They are reconstructed here verbatim from their original
// implementation so these focused unit tests keep exercising the still-public
// production reconciliation primitives (`reconcileVersionDifferences` and
// `versionsEffectivelyEqual`) that do the actual work.
String? reconciledInstalledVersionFromLatest(
  String installedVersion,
  String latestVersion,
) {
  if (installedVersion == latestVersion ||
      versionsEffectivelyEqual(installedVersion, latestVersion)) {
    return latestVersion;
  }
  final reconciled = reconcileVersionDifferences(
    installedVersion,
    latestVersion,
  );
  if (reconciled == null) {
    return null;
  }
  return reconciled.key ? reconciled.value : installedVersion;
}

String? reconciledInstalledVersionForDisabledVersionDetection(
  String realInstalledVersion,
  String reportedInstalledVersion,
  String latestVersion,
) {
  return reconciledInstalledVersionFromLatest(
        realInstalledVersion,
        latestVersion,
      ) ??
      (reconcileVersionDifferences(
                realInstalledVersion,
                reportedInstalledVersion,
              )?.key ==
              false
          ? realInstalledVersion
          : null);
}

void main() {
  test('installed version reconciliation keeps source latest when equal', () {
    expect(reconciledInstalledVersionFromLatest('1.1.0', '1.1.0'), '1.1.0');
  });

  test(
    'installed version reconciliation keeps source latest when equivalent',
    () {
      expect(reconciledInstalledVersionFromLatest('1.1.0', 'v1.1.0'), 'v1.1.0');
    },
  );

  test('installed version reconciliation accepts higher installed version', () {
    expect(reconciledInstalledVersionFromLatest('1.2.0', '1.1.0'), '1.2.0');
  });

  test('installed version reconciliation accepts lower installed version', () {
    expect(reconciledInstalledVersionFromLatest('1.0.0', '1.1.0'), '1.0.0');
  });

  test(
    'installed version reconciliation accepts long google release versions',
    () {
      const installed = '2026.04.27.917519149.2-release';
      const latest = '2026.04.27.917519149.2-release';
      const previousInstalled = '2026.03.12.885261117.2-release';

      expect(reconciledInstalledVersionFromLatest(installed, latest), latest);
      final reconciled = reconcileVersionDifferences(
        installed,
        previousInstalled,
      );
      expect(reconciled?.key, false);
      expect(reconciled?.value, installed);
    },
  );

  test(
    'installed version reconciliation accepts dotted release suffix versions',
    () {
      const installed = '1.0.915254043.release';
      const previousInstalled = '1.0.896819557.release';

      final reconciled = reconcileVersionDifferences(
        installed,
        previousInstalled,
      );
      expect(reconciled?.key, false);
      expect(reconciled?.value, installed);
    },
  );

  test('installed version reconciliation ignores unreconcilable version', () {
    expect(reconciledInstalledVersionFromLatest('9.18.50', '107'), isNull);
  });

  test(
    'disabled version detection accepts installed version when stored version reconciles',
    () {
      expect(
        reconciledInstalledVersionForDisabledVersionDetection(
          '1.2.0',
          '1.1.0',
          'release-2026-05-27',
        ),
        '1.2.0',
      );
    },
  );

  test(
    'disabled version detection accepts installed version when latest version reconciles',
    () {
      expect(
        reconciledInstalledVersionForDisabledVersionDetection(
          '1.2.0',
          'release-2026-04-01',
          '1.3.0',
        ),
        '1.2.0',
      );
    },
  );

  test(
    'disabled version detection reflects external upgrade even when latest is incompatible',
    () {
      // real upgraded from 1.1.0 → 1.2.0 externally; source uses a different format
      expect(
        reconciledInstalledVersionForDisabledVersionDetection(
          '1.2.0',
          '1.1.0',
          'build-abc123',
        ),
        '1.2.0',
      );
    },
  );

  test(
    'disabled version detection does not hide update when pseudo stored equals real',
    () {
      // pseudo stored == real (2.0), but source bumped to 2.1; reconciledInstalled
      // returns 2.0 (equal check), so installedVersion stays 2.0 and update stays visible
      expect(
        reconciledInstalledVersionForDisabledVersionDetection(
          '2.0',
          '2.0',
          '2.1',
        ),
        '2.0',
      );
    },
  );

  test(
    'disabled version detection ignores installed version when no version reconciles',
    () {
      expect(
        reconciledInstalledVersionForDisabledVersionDetection(
          '9.18.50',
          '106',
          '107',
        ),
        isNull,
      );
    },
  );
}
