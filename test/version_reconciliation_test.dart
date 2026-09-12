import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/services/version_service.dart';

/// The tracked version after reconciliation, falling back to the original when
/// nothing changes.
String trackedAfter({
  required String? tracked,
  required String? real,
  required String latest,
  bool standard = true,
  bool naive = false,
}) {
  return reconcileTrackedVersion(
        trackedVersion: tracked,
        realInstalledVersion: real,
        latestVersion: latest,
        versionDetectionIsStandard: standard,
        naiveStandardVersionDetection: naive,
      ) ??
      tracked!;
}

/// Whether the UI would show an update badge for the given app state.
bool updateShown(String installed, String latest) {
  final app = App(
    id: 'com.example.app',
    url: 'https://github.com/example/app',
    author: 'example',
    name: 'App',
    installedVersion: installed,
    latestVersion: latest,
    preferredApkIndex: 0,
    additionalSettings: const {'versionDetection': true},
  );
  return isAppUpdateable(app, SettingsProvider());
}

void main() {
  group('reconcileVersionDifferences', () {
    test('equal versions share a format and match', () {
      final result = reconcileVersionDifferences('1.2.3', '1.2.3');
      expect(result, isNotNull);
      expect(result!.areEqual, isTrue);
      expect(result.version, '1.2.3');
    });

    test('different versions sharing a format are reported as different', () {
      final result = reconcileVersionDifferences('1.2.3', '1.2.4');
      expect(result, isNotNull);
      expect(result!.areEqual, isFalse);
      expect(result.version, '1.2.3');
    });

    test('a leading v on the comparison side matches under a loose format', () {
      final result = reconcileVersionDifferences('1.2.3', 'v1.2.3');
      expect(result, isNotNull);
      expect(result!.areEqual, isTrue);
      expect(result.version, 'v1.2.3');
    });

    test('a leading v on the template side cannot be reconciled', () {
      expect(reconcileVersionDifferences('v1.2.3', '1.2.3'), isNull);
    });

    test('unknown packaging suffixes are not standard formats', () {
      expect(reconcileVersionDifferences('1.6.15-debug', '1.6.15'), isNull);
      expect(reconcileVersionDifferences('1.6.15', '1.6.15-debug'), isNotNull);
    });

    test('pre-release qualifiers reconcile only when they match', () {
      // Punctuation differences inside a qualifier are normalized by
      // version_normalization (not by the regex-format reconciler).
      expect(
        reconcileVersionDifferences('1.2.3-beta1', '1.2.3-beta.1'),
        isNull,
      );
      expect(reconcileVersionDifferences('61.0', '61.0-beta1'), isNull);
      expect(reconcileVersionDifferences('61.0-beta1', '61.0'), isNull);
    });

    test('Debian-style versions reconcile', () {
      final result = reconcileVersionDifferences('1.2.3-1', '1.2.3-1');
      expect(result, isNotNull);
      expect(result!.areEqual, isTrue);
    });

    test('numeric-only versions with different values are different', () {
      final result = reconcileVersionDifferences('2412', '622797097');
      expect(result, isNotNull);
      expect(result!.areEqual, isFalse);
    });
  });

  group('versionDetectionPossible', () {
    bool possible({
      bool trackOnly = false,
      bool releaseDateAsVersion = false,
      bool isHtmlWithNoVersionDetection = false,
      bool versionDetectionDisallowed = false,
      String? real = '1.2.3',
      String? tracked = '1.2.3',
      String latest = '1.2.4',
      bool naive = false,
    }) {
      return versionDetectionPossible(
        trackOnly: trackOnly,
        releaseDateAsVersion: releaseDateAsVersion,
        isHtmlWithNoVersionDetection: isHtmlWithNoVersionDetection,
        versionDetectionDisallowed: versionDetectionDisallowed,
        realInstalledVersion: real,
        trackedVersion: tracked,
        latestVersion: latest,
        naiveStandardVersionDetection: naive,
      );
    }

    test('keeps detection on for cosmetic differences', () {
      expect(
        possible(real: 'v2026.03', tracked: 'v2026.03', latest: 'v2026.07'),
        isTrue,
      );
      expect(
        possible(
          real: '1.6.15-debug',
          tracked: '1.6.15-debug',
          latest: '1.6.15',
        ),
        isTrue,
      );
      expect(
        possible(real: '1.0.5基本版', tracked: '1.0.5基本版', latest: '1.0.5正式版'),
        isTrue,
      );
    });

    test('keeps detection on when the real version matches latest', () {
      expect(
        possible(
          real: '1.6.15-debug',
          tracked: '1.6.15-debug',
          latest: '1.6.15',
        ),
        isTrue,
      );
      expect(
        possible(
          real: 'v151_beta',
          tracked: 'v151_beta',
          latest: '151.0.7922.47',
        ),
        isTrue,
      );
    });

    test('turns detection off for a major-only rolling tag', () {
      expect(
        possible(
          real: '151.0.7922.47',
          tracked: '151.0.7922.47',
          latest: 'v151_beta',
        ),
        isFalse,
      );
      expect(
        possible(
          real: '151.0.7922.47',
          tracked: 'v151_beta',
          latest: 'v151_beta',
        ),
        isFalse,
      );
    });

    test('a naive source keeps detection on for a rolling tag', () {
      expect(
        possible(
          real: '151.0.7922.47',
          tracked: '151.0.7922.47',
          latest: 'v151_beta',
          naive: true,
        ),
        isTrue,
      );
    });

    test('turns detection off for unrelated non-standard versions', () {
      expect(possible(real: 'foo', tracked: 'bar', latest: 'baz'), isFalse);
    });

    test('a naive source accepts unrelated non-standard versions', () {
      expect(
        possible(real: 'foo', tracked: 'bar', latest: 'baz', naive: true),
        isTrue,
      );
    });

    test(
      'track-only, release-date, HTML-without-regex and disallowed sources opt out',
      () {
        expect(possible(trackOnly: true), isFalse);
        expect(possible(releaseDateAsVersion: true), isFalse);
        expect(possible(isHtmlWithNoVersionDetection: true), isFalse);
        expect(possible(versionDetectionDisallowed: true), isFalse);
      },
    );

    test('missing real or tracked versions opt out', () {
      expect(possible(real: null), isFalse);
      expect(possible(tracked: null), isFalse);
    });

    test('standard versions are always possible', () {
      expect(
        possible(real: '1.2.3', tracked: '1.2.3', latest: '1.2.4'),
        isTrue,
      );
      expect(
        possible(real: '1.2.3-1', tracked: '1.2.3-1', latest: '1.2.3-2'),
        isTrue,
      );
    });
  });

  group('reconcileTrackedVersion', () {
    test('collapses packaging suffixes on the installed side', () {
      expect(
        trackedAfter(
          tracked: '1.6.15-debug',
          real: '1.6.15-debug',
          latest: '1.6.15',
        ),
        '1.6.15',
      );
      expect(
        trackedAfter(
          tracked: '0.9.108 strip',
          real: '0.9.108 strip',
          latest: '0.9.108',
        ),
        '0.9.108',
      );
      expect(
        trackedAfter(
          tracked: '1.0.5-release+26090410',
          real: '1.0.5-release+26090410',
          latest: '1.0.5',
        ),
        '1.0.5',
      );
    });

    test('collapses a leading v in both directions', () {
      expect(
        trackedAfter(tracked: 'v2026.03', real: 'v2026.03', latest: '2026.03'),
        '2026.03',
      );
      expect(
        trackedAfter(tracked: '2026.03', real: '2026.03', latest: 'v2026.03'),
        'v2026.03',
      );
    });

    test('does not collapse a rolling major-only pre-release tag', () {
      expect(
        reconcileTrackedVersion(
          trackedVersion: '151.0.7922.47',
          realInstalledVersion: '151.0.7922.47',
          latestVersion: 'v151_beta',
          versionDetectionIsStandard: true,
          naiveStandardVersionDetection: false,
        ),
        isNull,
      );
      // A previously collapsed tag is not restored to the device version, so
      // it stays equal to the remote until the tag changes.
      expect(
        reconcileTrackedVersion(
          trackedVersion: 'v151_beta',
          realInstalledVersion: '151.0.7922.47',
          latestVersion: 'v151_beta',
          versionDetectionIsStandard: true,
          naiveStandardVersionDetection: false,
        ),
        isNull,
      );
    });

    test('does not hide conflicting packaging variants', () {
      expect(
        reconcileTrackedVersion(
          trackedVersion: '1.6.15-debug',
          realInstalledVersion: '1.6.15-debug',
          latestVersion: '1.6.15-release',
          versionDetectionIsStandard: true,
          naiveStandardVersionDetection: false,
        ),
        isNull,
      );
      expect(
        reconcileTrackedVersion(
          trackedVersion: '1.6.15',
          realInstalledVersion: '1.6.15',
          latestVersion: '1.6.15-debug',
          versionDetectionIsStandard: true,
          naiveStandardVersionDetection: false,
        ),
        isNull,
      );
      expect(
        reconcileTrackedVersion(
          trackedVersion: '1.6.15-release',
          realInstalledVersion: '1.6.15-release',
          latestVersion: '1.6.15-debug',
          versionDetectionIsStandard: true,
          naiveStandardVersionDetection: false,
        ),
        isNull,
      );
    });

    test('keeps pre-release qualifiers significant', () {
      expect(
        reconcileTrackedVersion(
          trackedVersion: '61.0-beta1',
          realInstalledVersion: '61.0-beta1',
          latestVersion: '61.0',
          versionDetectionIsStandard: true,
          naiveStandardVersionDetection: false,
        ),
        isNull,
      );
    });

    test('adopts latest when the device version is the same release', () {
      // The #2324 scenario: F-Droid installed the stable build behind
      // Obtainium's back, so the tracked pre-release value must catch up.
      expect(
        trackedAfter(tracked: '61.0-beta1', real: '61.0', latest: '61.0'),
        '61.0',
      );
      expect(
        trackedAfter(tracked: '1.6.14', real: '1.6.15', latest: '1.6.15'),
        '1.6.15',
      );
      expect(
        trackedAfter(tracked: '1.6.14', real: '1.6.15-debug', latest: '1.6.15'),
        '1.6.15',
      );
      expect(
        trackedAfter(
          tracked: 'v151_beta',
          real: '151.0.7922.47',
          latest: '151.0.7922.47',
        ),
        '151.0.7922.47',
      );
    });

    test('tracks a device downgrade', () {
      expect(
        trackedAfter(tracked: '1.6.15', real: '1.6.14', latest: '1.6.15'),
        '1.6.14',
      );
    });

    test('keeps build metadata significant when the remote carries it', () {
      expect(
        reconcileTrackedVersion(
          trackedVersion: '1.0.5+1',
          realInstalledVersion: '1.0.5+1',
          latestVersion: '1.0.5+2',
          versionDetectionIsStandard: true,
          naiveStandardVersionDetection: false,
        ),
        isNull,
      );
      expect(
        reconcileTrackedVersion(
          trackedVersion: '1.0.5',
          realInstalledVersion: '1.0.5',
          latestVersion: '1.0.5+1',
          versionDetectionIsStandard: true,
          naiveStandardVersionDetection: false,
        ),
        isNull,
      );
      expect(
        trackedAfter(tracked: '1.0.5+1', real: '1.0.5+1', latest: '1.0.5'),
        '1.0.5',
      );
    });

    test('does not swallow non-ASCII qualifiers', () {
      expect(
        reconcileTrackedVersion(
          trackedVersion: '1.2.3稳定版',
          realInstalledVersion: '1.2.3稳定版',
          latestVersion: '1.2.3',
          versionDetectionIsStandard: true,
          naiveStandardVersionDetection: false,
        ),
        isNull,
      );
      expect(
        reconcileTrackedVersion(
          trackedVersion: '1.2.3稳定版',
          realInstalledVersion: '1.2.3稳定版',
          latestVersion: '1.2.3正式版',
          versionDetectionIsStandard: true,
          naiveStandardVersionDetection: false,
        ),
        isNull,
      );
    });

    test('normalizes letter/digit punctuation in qualifiers', () {
      expect(
        trackedAfter(
          tracked: '1.2.3-beta1',
          real: '1.2.3-beta1',
          latest: '1.2.3-beta.1',
        ),
        '1.2.3-beta.1',
      );
    });

    test('naive sources adopt the real version when possible', () {
      expect(
        trackedAfter(tracked: 'v2', real: '2.0', latest: '2.0', naive: true),
        '2.0',
      );
    });

    test('does not reconcile when standard detection is off', () {
      // Cosmetic collapsing is independent of the detection toggle, but the
      // reported-vs-real reconciliation steps are not.
      expect(
        reconcileTrackedVersion(
          trackedVersion: '1.6.14',
          realInstalledVersion: '1.6.15',
          latestVersion: '1.7.0',
          versionDetectionIsStandard: false,
          naiveStandardVersionDetection: false,
        ),
        isNull,
      );
    });

    test('a null tracked version is left to the caller', () {
      expect(
        reconcileTrackedVersion(
          trackedVersion: null,
          realInstalledVersion: '1.2.3',
          latestVersion: '1.2.4',
          versionDetectionIsStandard: true,
          naiveStandardVersionDetection: false,
        ),
        isNull,
      );
    });
  });

  group('update badge outcomes after correction', () {
    String effectiveInstalled({
      required String tracked,
      required String real,
      required String latest,
    }) => trackedAfter(tracked: tracked, real: real, latest: latest);

    test('no badge for cosmetic differences', () {
      expect(
        updateShown(
          effectiveInstalled(
            tracked: '1.6.15-debug',
            real: '1.6.15-debug',
            latest: '1.6.15',
          ),
          '1.6.15',
        ),
        isFalse,
      );
      expect(
        updateShown(
          effectiveInstalled(
            tracked: 'v2026.03',
            real: 'v2026.03',
            latest: '2026.03',
          ),
          '2026.03',
        ),
        isFalse,
      );
    });

    test('badge for a rolling major-only tag', () {
      expect(
        updateShown(
          effectiveInstalled(
            tracked: '151.0.7922.47',
            real: '151.0.7922.47',
            latest: 'v151_beta',
          ),
          'v151_beta',
        ),
        isTrue,
      );
    });

    test('badge for real updates', () {
      expect(
        updateShown(
          effectiveInstalled(
            tracked: '1.6.14',
            real: '1.6.14',
            latest: '1.6.15',
          ),
          '1.6.15',
        ),
        isTrue,
      );
      expect(
        updateShown(
          effectiveInstalled(
            tracked: '1.6.15-debug',
            real: '1.6.15-debug',
            latest: '1.7.0',
          ),
          '1.7.0',
        ),
        isTrue,
      );
      expect(
        updateShown(
          effectiveInstalled(
            tracked: '1.0.5+1',
            real: '1.0.5+1',
            latest: '1.0.5+2',
          ),
          '1.0.5+2',
        ),
        isTrue,
      );
    });

    test('badge for conflicting packaging variants', () {
      expect(
        updateShown(
          effectiveInstalled(
            tracked: '1.6.15-debug',
            real: '1.6.15-debug',
            latest: '1.6.15-release',
          ),
          '1.6.15-release',
        ),
        isTrue,
      );
      expect(
        updateShown(
          effectiveInstalled(
            tracked: '1.6.15',
            real: '1.6.15',
            latest: '1.6.15-debug',
          ),
          '1.6.15-debug',
        ),
        isTrue,
      );
    });

    test('badge for a genuine pre-release-to-final difference', () {
      expect(
        updateShown(
          effectiveInstalled(
            tracked: '61.0-beta1',
            real: '61.0-beta1',
            latest: '61.0',
          ),
          '61.0',
        ),
        isTrue,
      );
    });

    test('no badge when the device already has the latest release', () {
      expect(
        updateShown(
          effectiveInstalled(
            tracked: '61.0-beta1',
            real: '61.0',
            latest: '61.0',
          ),
          '61.0',
        ),
        isFalse,
      );
    });
  });
}
