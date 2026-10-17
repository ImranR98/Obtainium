import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/utils/update_health.dart';
import 'package:shared_preferences/shared_preferences.dart';

App _app({
  String latestVersion = '1.0.0',
  DateTime? releaseDate,
  DateTime? latestVersionChangedAt,
  int consecutiveFailedChecks = 0,
  bool? isArchived,
  int? newerReleasesFilteredOut,
  bool updateHealthEnabled = true,
  String? updateHealthDismissedVersion,
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
  updateHealthEnabled: updateHealthEnabled,
  updateHealthDismissedVersion: updateHealthDismissedVersion,
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
      expect(settings.updateHealthStaleReleaseDays, 180);
      expect(settings.updateHealthStaleVersionDays, 180);
      expect(settings.updateHealthFailedChecksCount, 5);
      expect(settings.updateHealthArchivedEnabled, isTrue);
      expect(settings.updateHealthFilteredReleasesCount, 5);
      expect(settings.showUpdateHealthIndicator, isTrue);
    });

    test('resolve to an enabled config', () {
      final config = resolveUpdateHealthConfig(const {}, settings);
      expect(config.staleReleaseDays, 180);
      expect(config.staleVersionDays, 180);
      expect(config.failedChecksCount, 5);
      expect(config.archivedEnabled, isTrue);
      expect(config.filteredReleasesCount, 5);
    });

    test('zero disables a heuristic globally', () {
      settings.updateHealthStaleReleaseDays = 0;
      settings.updateHealthFailedChecksCount = 0;
      final config = resolveUpdateHealthConfig(const {}, settings);
      expect(config.staleReleaseDays, isNull);
      expect(config.failedChecksCount, isNull);
    });
  });

  group('resolveUpdateHealthConfig per-app overrides', () {
    late SettingsProvider settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsProvider();
      settings.prefs = await SharedPreferences.getInstance();
    });

    test('numeric override wins over the global value', () {
      final config = resolveUpdateHealthConfig(const {
        'updateHealthStaleRelease': '30',
        'updateHealthFailedChecks': '10',
      }, settings);
      expect(config.staleReleaseDays, 30);
      expect(config.failedChecksCount, 10);
      expect(config.staleVersionDays, 180);
    });

    test('off disables even when the global value is enabled', () {
      final config = resolveUpdateHealthConfig(const {
        'updateHealthStaleVersion': 'off',
      }, settings);
      expect(config.staleVersionDays, isNull);
    });

    test('numeric override re-enables a globally disabled heuristic', () {
      settings.updateHealthFilteredReleasesCount = 0;
      final config = resolveUpdateHealthConfig(const {
        'updateHealthFilteredReleases': '2',
      }, settings);
      expect(config.filteredReleasesCount, 2);
    });

    test('empty and invalid overrides fall back to the global value', () {
      final config = resolveUpdateHealthConfig(const {
        'updateHealthStaleRelease': '',
        'updateHealthStaleVersion': 'abc',
      }, settings);
      expect(config.staleReleaseDays, 180);
      expect(config.staleVersionDays, 180);
    });

    test('archived override turns it on and off', () {
      settings.updateHealthArchivedEnabled = false;
      expect(
        resolveUpdateHealthConfig(const {
          'updateHealthArchived': 'on',
        }, settings).archivedEnabled,
        isTrue,
      );
      expect(
        resolveUpdateHealthConfig(const {
          'updateHealthArchived': 'off',
        }, settings).archivedEnabled,
        isFalse,
      );
    });
  });

  group('evaluateUpdateHealthReasons', () {
    const config = UpdateHealthConfig(
      staleReleaseDays: 180,
      staleVersionDays: 180,
      failedChecksCount: 3,
      archivedEnabled: true,
      filteredReleasesCount: 5,
    );

    test('stale release date fires at the threshold', () {
      expect(
        evaluateUpdateHealthReasons(
          _app(releaseDate: DateTime(2026, 4, 19)),
          config,
          now: now,
        ),
        contains(UpdateHealthReason.staleRelease),
      );
      expect(
        evaluateUpdateHealthReasons(
          _app(releaseDate: DateTime(2026, 4, 21)),
          config,
          now: now,
        ),
        isNot(contains(UpdateHealthReason.staleRelease)),
      );
    });

    test('stale release date is skipped without a date', () {
      expect(
        evaluateUpdateHealthReasons(_app(), config, now: now),
        isNot(contains(UpdateHealthReason.staleRelease)),
      );
    });

    test('stale version fires from latestVersionChangedAt', () {
      expect(
        evaluateUpdateHealthReasons(
          _app(latestVersionChangedAt: DateTime(2026, 4, 19)),
          config,
          now: now,
        ),
        contains(UpdateHealthReason.staleVersion),
      );
      expect(
        evaluateUpdateHealthReasons(
          _app(latestVersionChangedAt: now),
          config,
          now: now,
        ),
        isNot(contains(UpdateHealthReason.staleVersion)),
      );
    });

    test('failed checks fire at the count', () {
      expect(
        evaluateUpdateHealthReasons(
          _app(consecutiveFailedChecks: 3),
          config,
          now: now,
        ),
        contains(UpdateHealthReason.failedChecks),
      );
      expect(
        evaluateUpdateHealthReasons(
          _app(consecutiveFailedChecks: 2),
          config,
          now: now,
        ),
        isNot(contains(UpdateHealthReason.failedChecks)),
      );
    });

    test('archived fires only when known to be true', () {
      expect(
        evaluateUpdateHealthReasons(_app(isArchived: true), config, now: now),
        contains(UpdateHealthReason.archived),
      );
      expect(
        evaluateUpdateHealthReasons(_app(isArchived: false), config, now: now),
        isNot(contains(UpdateHealthReason.archived)),
      );
      expect(
        evaluateUpdateHealthReasons(_app(), config, now: now),
        isNot(contains(UpdateHealthReason.archived)),
      );
    });

    test('filtered releases fire at the count', () {
      expect(
        evaluateUpdateHealthReasons(
          _app(newerReleasesFilteredOut: 5),
          config,
          now: now,
        ),
        contains(UpdateHealthReason.filteredReleases),
      );
      expect(
        evaluateUpdateHealthReasons(
          _app(newerReleasesFilteredOut: 4),
          config,
          now: now,
        ),
        isNot(contains(UpdateHealthReason.filteredReleases)),
      );
      expect(
        evaluateUpdateHealthReasons(_app(), config, now: now),
        isNot(contains(UpdateHealthReason.filteredReleases)),
      );
    });

    test('disabled heuristics never fire', () {
      const disabled = UpdateHealthConfig();
      expect(
        evaluateUpdateHealthReasons(
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

  group('isUpdateHealthIgnored', () {
    test('true when permanently disabled', () {
      expect(isUpdateHealthIgnored(_app(updateHealthEnabled: false)), isTrue);
    });

    test('true while the dismissed version equals the latest version', () {
      expect(
        isUpdateHealthIgnored(
          _app(latestVersion: '2.0.0', updateHealthDismissedVersion: '2.0.0'),
        ),
        isTrue,
      );
      expect(
        isUpdateHealthIgnored(
          _app(latestVersion: '2.0.1', updateHealthDismissedVersion: '2.0.0'),
        ),
        isFalse,
      );
    });
  });

  group('hasUpdateHealthIssues', () {
    late SettingsProvider settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsProvider();
      settings.prefs = await SharedPreferences.getInstance();
    });

    test('true with a reason and no exclusions', () {
      expect(hasUpdateHealthIssues(_app(isArchived: true), settings), isTrue);
    });

    test('false for disabled apps', () {
      expect(
        hasUpdateHealthIssues(_app(isArchived: true, disabled: true), settings),
        isFalse,
      );
    });

    test('false for apps pending a repo rename', () {
      expect(
        hasUpdateHealthIssues(
          _app(isArchived: true, pendingRepoRenameUrl: 'https://example.com/x'),
          settings,
        ),
        isFalse,
      );
    });

    test('false for ignored apps', () {
      expect(
        hasUpdateHealthIssues(
          _app(isArchived: true, updateHealthEnabled: false),
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
        updateHealthEnabled: false,
        updateHealthDismissedVersion: '1.0.0',
        additionalSettings: const {'updateHealthStaleRelease': '30'},
      );
      final restored = App.fromJson(app.toJson());
      expect(
        restored.latestVersionChangedAt,
        DateTime.fromMicrosecondsSinceEpoch(1234567),
      );
      expect(restored.consecutiveFailedChecks, 4);
      expect(restored.isArchived, isTrue);
      expect(restored.newerReleasesFilteredOut, 7);
      expect(restored.updateHealthEnabled, isFalse);
      expect(restored.updateHealthDismissedVersion, '1.0.0');
      expect(restored.additionalSettings['updateHealthStaleRelease'], '30');
    });

    test('defaults missing detection fields', () {
      final json = _app().toJson()
        ..remove('latestVersionChangedAt')
        ..remove('consecutiveFailedChecks')
        ..remove('isArchived')
        ..remove('newerReleasesFilteredOut')
        ..remove('updateHealthEnabled')
        ..remove('updateHealthDismissedVersion');
      final restored = App.fromJson(json);
      expect(restored.latestVersionChangedAt, isNull);
      expect(restored.consecutiveFailedChecks, 0);
      expect(restored.isArchived, isNull);
      expect(restored.newerReleasesFilteredOut, isNull);
      expect(restored.updateHealthEnabled, isTrue);
      expect(restored.updateHealthDismissedVersion, isNull);
    });
  });
}
