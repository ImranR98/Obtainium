import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/utils/broken_check.dart';
import 'package:shared_preferences/shared_preferences.dart';

App _app({
  String latestVersion = '1.0.0',
  DateTime? releaseDate,
  DateTime? latestVersionChangedAt,
  int consecutiveFailedChecks = 0,
  bool? isArchived,
  int? newerReleasesFilteredOut,
  bool brokenCheckEnabled = true,
  String? brokenCheckDismissedVersion,
  bool disabled = false,
  String? pendingRepoRenameUrl,
  Map<String, dynamic> additionalSettings = const {},
}) => App(
  id: 'com.example.app',
  url: 'https://example.com/app',
  author: 'Author',
  name: 'App',
  latestVersion: latestVersion,
  preferredApkIndex: 0,
  additionalSettings: additionalSettings,
  releaseDate: releaseDate,
  latestVersionChangedAt: latestVersionChangedAt,
  consecutiveFailedChecks: consecutiveFailedChecks,
  isArchived: isArchived,
  newerReleasesFilteredOut: newerReleasesFilteredOut,
  brokenCheckEnabled: brokenCheckEnabled,
  brokenCheckDismissedVersion: brokenCheckDismissedVersion,
  disabled: disabled,
  pendingRepoRenameUrl: pendingRepoRenameUrl,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 16, 12);

  group('defaults', () {
    late SettingsProvider settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsProvider();
      settings.prefs = await SharedPreferences.getInstance();
    });

    test('are all enabled with the compact thresholds', () {
      expect(settings.brokenCheckStaleReleaseDays, 180);
      expect(settings.brokenCheckStaleVersionDays, 180);
      expect(settings.brokenCheckFailedChecksCount, 3);
      expect(settings.brokenCheckArchivedEnabled, isTrue);
      expect(settings.brokenCheckFilteredReleasesCount, 5);
      expect(settings.showBrokenCheckIndicator, isTrue);
    });

    test('resolve to an enabled config', () {
      final config = resolveBrokenCheckConfig(const {}, settings);
      expect(config.staleReleaseDays, 180);
      expect(config.staleVersionDays, 180);
      expect(config.failedChecksCount, 3);
      expect(config.archivedEnabled, isTrue);
      expect(config.filteredReleasesCount, 5);
    });

    test('zero disables a heuristic globally', () {
      settings.brokenCheckStaleReleaseDays = 0;
      settings.brokenCheckFailedChecksCount = 0;
      final config = resolveBrokenCheckConfig(const {}, settings);
      expect(config.staleReleaseDays, isNull);
      expect(config.failedChecksCount, isNull);
    });
  });

  group('resolveBrokenCheckConfig per-app overrides', () {
    late SettingsProvider settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsProvider();
      settings.prefs = await SharedPreferences.getInstance();
    });

    test('numeric override wins over the global value', () {
      final config = resolveBrokenCheckConfig(const {
        'brokenCheckStaleRelease': '30',
        'brokenCheckFailedChecks': '10',
      }, settings);
      expect(config.staleReleaseDays, 30);
      expect(config.failedChecksCount, 10);
      expect(config.staleVersionDays, 180);
    });

    test('off disables even when the global value is enabled', () {
      final config = resolveBrokenCheckConfig(const {
        'brokenCheckStaleVersion': 'off',
      }, settings);
      expect(config.staleVersionDays, isNull);
    });

    test('numeric override re-enables a globally disabled heuristic', () {
      settings.brokenCheckFilteredReleasesCount = 0;
      final config = resolveBrokenCheckConfig(const {
        'brokenCheckFilteredReleases': '2',
      }, settings);
      expect(config.filteredReleasesCount, 2);
    });

    test('empty and invalid overrides fall back to the global value', () {
      final config = resolveBrokenCheckConfig(const {
        'brokenCheckStaleRelease': '',
        'brokenCheckStaleVersion': 'abc',
      }, settings);
      expect(config.staleReleaseDays, 180);
      expect(config.staleVersionDays, 180);
    });

    test('archived override turns it on and off', () {
      settings.brokenCheckArchivedEnabled = false;
      expect(
        resolveBrokenCheckConfig(const {
          'brokenCheckArchived': 'on',
        }, settings).archivedEnabled,
        isTrue,
      );
      expect(
        resolveBrokenCheckConfig(const {
          'brokenCheckArchived': 'off',
        }, settings).archivedEnabled,
        isFalse,
      );
    });
  });

  group('evaluateBrokenCheckReasons', () {
    const config = BrokenCheckConfig(
      staleReleaseDays: 180,
      staleVersionDays: 180,
      failedChecksCount: 3,
      archivedEnabled: true,
      filteredReleasesCount: 5,
    );

    test('stale release date fires at the threshold', () {
      expect(
        evaluateBrokenCheckReasons(
          _app(releaseDate: DateTime(2026, 4, 19)),
          config,
          now: now,
        ),
        contains(BrokenCheckReason.staleRelease),
      );
      expect(
        evaluateBrokenCheckReasons(
          _app(releaseDate: DateTime(2026, 4, 21)),
          config,
          now: now,
        ),
        isNot(contains(BrokenCheckReason.staleRelease)),
      );
    });

    test('stale release date is skipped without a date', () {
      expect(
        evaluateBrokenCheckReasons(_app(), config, now: now),
        isNot(contains(BrokenCheckReason.staleRelease)),
      );
    });

    test('stale version fires from latestVersionChangedAt', () {
      expect(
        evaluateBrokenCheckReasons(
          _app(latestVersionChangedAt: DateTime(2026, 4, 19)),
          config,
          now: now,
        ),
        contains(BrokenCheckReason.staleVersion),
      );
      expect(
        evaluateBrokenCheckReasons(
          _app(latestVersionChangedAt: now),
          config,
          now: now,
        ),
        isNot(contains(BrokenCheckReason.staleVersion)),
      );
    });

    test('failed checks fire at the count', () {
      expect(
        evaluateBrokenCheckReasons(
          _app(consecutiveFailedChecks: 3),
          config,
          now: now,
        ),
        contains(BrokenCheckReason.failedChecks),
      );
      expect(
        evaluateBrokenCheckReasons(
          _app(consecutiveFailedChecks: 2),
          config,
          now: now,
        ),
        isNot(contains(BrokenCheckReason.failedChecks)),
      );
    });

    test('archived fires only when known to be true', () {
      expect(
        evaluateBrokenCheckReasons(_app(isArchived: true), config, now: now),
        contains(BrokenCheckReason.archived),
      );
      expect(
        evaluateBrokenCheckReasons(_app(isArchived: false), config, now: now),
        isNot(contains(BrokenCheckReason.archived)),
      );
      expect(
        evaluateBrokenCheckReasons(_app(), config, now: now),
        isNot(contains(BrokenCheckReason.archived)),
      );
    });

    test('filtered releases fire at the count', () {
      expect(
        evaluateBrokenCheckReasons(
          _app(newerReleasesFilteredOut: 5),
          config,
          now: now,
        ),
        contains(BrokenCheckReason.filteredReleases),
      );
      expect(
        evaluateBrokenCheckReasons(
          _app(newerReleasesFilteredOut: 4),
          config,
          now: now,
        ),
        isNot(contains(BrokenCheckReason.filteredReleases)),
      );
      expect(
        evaluateBrokenCheckReasons(_app(), config, now: now),
        isNot(contains(BrokenCheckReason.filteredReleases)),
      );
    });

    test('disabled heuristics never fire', () {
      const disabled = BrokenCheckConfig();
      expect(
        evaluateBrokenCheckReasons(
          _app(
            releaseDate: DateTime(2020, 1, 1),
            latestVersionChangedAt: DateTime(2020, 1, 1),
            consecutiveFailedChecks: 100,
            isArchived: true,
            newerReleasesFilteredOut: 100,
          ),
          disabled,
          now: now,
        ),
        isEmpty,
      );
    });
  });

  group('isBrokenCheckIgnored', () {
    test('true when permanently disabled', () {
      expect(isBrokenCheckIgnored(_app(brokenCheckEnabled: false)), isTrue);
    });

    test('true while the dismissed version equals the latest version', () {
      expect(
        isBrokenCheckIgnored(
          _app(latestVersion: '2.0.0', brokenCheckDismissedVersion: '2.0.0'),
        ),
        isTrue,
      );
      expect(
        isBrokenCheckIgnored(
          _app(latestVersion: '2.0.1', brokenCheckDismissedVersion: '2.0.0'),
        ),
        isFalse,
      );
    });
  });

  group('isAppPossiblyBroken', () {
    late SettingsProvider settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsProvider();
      settings.prefs = await SharedPreferences.getInstance();
    });

    test('true with a reason and no exclusions', () {
      expect(isAppPossiblyBroken(_app(isArchived: true), settings), isTrue);
    });

    test('false for disabled apps', () {
      expect(
        isAppPossiblyBroken(_app(isArchived: true, disabled: true), settings),
        isFalse,
      );
    });

    test('false for apps pending a repo rename', () {
      expect(
        isAppPossiblyBroken(
          _app(isArchived: true, pendingRepoRenameUrl: 'https://example.com/x'),
          settings,
        ),
        isFalse,
      );
    });

    test('false for ignored apps', () {
      expect(
        isAppPossiblyBroken(
          _app(isArchived: true, brokenCheckEnabled: false),
          settings,
        ),
        isFalse,
      );
    });
  });

  group('shouldCountFailedCheck', () {
    test('excludes transient failures', () {
      expect(shouldCountFailedCheck(RateLimitError(5)), isFalse);
      expect(shouldCountFailedCheck(const SocketException('offline')), isFalse);
      expect(
        shouldCountFailedCheck(const HandshakeException('handshake')),
        isFalse,
      );
    });

    test('counts source-level failures', () {
      expect(shouldCountFailedCheck(NoReleasesError()), isTrue);
      expect(shouldCountFailedCheck(NoAPKError()), isTrue);
      expect(shouldCountFailedCheck(Exception('unexpected')), isTrue);
    });
  });

  group('App JSON', () {
    test('round-trips the detection fields', () {
      final app = _app(
        latestVersionChangedAt: DateTime.fromMicrosecondsSinceEpoch(1234567),
        consecutiveFailedChecks: 4,
        isArchived: true,
        newerReleasesFilteredOut: 7,
        brokenCheckEnabled: false,
        brokenCheckDismissedVersion: '1.0.0',
        additionalSettings: const {'brokenCheckStaleRelease': '30'},
      );
      final restored = App.fromJson(app.toJson());
      expect(
        restored.latestVersionChangedAt,
        DateTime.fromMicrosecondsSinceEpoch(1234567),
      );
      expect(restored.consecutiveFailedChecks, 4);
      expect(restored.isArchived, isTrue);
      expect(restored.newerReleasesFilteredOut, 7);
      expect(restored.brokenCheckEnabled, isFalse);
      expect(restored.brokenCheckDismissedVersion, '1.0.0');
      expect(restored.additionalSettings['brokenCheckStaleRelease'], '30');
    });

    test('defaults missing detection fields', () {
      final json = _app().toJson()
        ..remove('latestVersionChangedAt')
        ..remove('consecutiveFailedChecks')
        ..remove('isArchived')
        ..remove('newerReleasesFilteredOut')
        ..remove('brokenCheckEnabled')
        ..remove('brokenCheckDismissedVersion');
      final restored = App.fromJson(json);
      expect(restored.latestVersionChangedAt, isNull);
      expect(restored.consecutiveFailedChecks, 0);
      expect(restored.isArchived, isNull);
      expect(restored.newerReleasesFilteredOut, isNull);
      expect(restored.brokenCheckEnabled, isTrue);
      expect(restored.brokenCheckDismissedVersion, isNull);
    });
  });
}
