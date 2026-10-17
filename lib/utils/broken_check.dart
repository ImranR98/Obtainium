import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/settings_provider.dart';

enum BrokenCheckReason {
  staleRelease,
  staleVersion,
  failedChecks,
  archived,
  filteredReleases,
}

class BrokenCheckConfig {
  final int? staleReleaseDays;
  final int? staleVersionDays;
  final int? failedChecksCount;
  final bool archivedEnabled;
  final int? filteredReleasesCount;

  const BrokenCheckConfig({
    this.staleReleaseDays,
    this.staleVersionDays,
    this.failedChecksCount,
    this.archivedEnabled = false,
    this.filteredReleasesCount,
  });
}

const List<int> brokenCheckDayOptions = [0, 30, 60, 90, 180, 365, 730];
const List<int> brokenCheckFailedChecksOptions = [0, 1, 2, 3, 5, 8, 10, 15, 20];
const List<int> brokenCheckFilteredReleasesOptions = [
  0,
  1,
  2,
  3,
  5,
  8,
  10,
  15,
  20,
];

int? _resolveThreshold(Object? override, int globalValue) {
  if (override is String && override.isNotEmpty) {
    if (override == 'off') return null;
    final parsed = int.tryParse(override);
    if (parsed != null) return parsed < 1 ? null : parsed;
  }
  return globalValue < 1 ? null : globalValue;
}

bool _resolveArchived(Object? override, bool globalEnabled) {
  if (override == 'off') return false;
  if (override == 'on') return true;
  return globalEnabled;
}

BrokenCheckConfig resolveBrokenCheckConfig(
  Map<String, dynamic> additionalSettings,
  SettingsProvider settingsProvider,
) {
  return BrokenCheckConfig(
    staleReleaseDays: _resolveThreshold(
      additionalSettings['brokenCheckStaleRelease'],
      settingsProvider.brokenCheckStaleReleaseDays,
    ),
    staleVersionDays: _resolveThreshold(
      additionalSettings['brokenCheckStaleVersion'],
      settingsProvider.brokenCheckStaleVersionDays,
    ),
    failedChecksCount: _resolveThreshold(
      additionalSettings['brokenCheckFailedChecks'],
      settingsProvider.brokenCheckFailedChecksCount,
    ),
    archivedEnabled: _resolveArchived(
      additionalSettings['brokenCheckArchived'],
      settingsProvider.brokenCheckArchivedEnabled,
    ),
    filteredReleasesCount: _resolveThreshold(
      additionalSettings['brokenCheckFilteredReleases'],
      settingsProvider.brokenCheckFilteredReleasesCount,
    ),
  );
}

bool isBrokenCheckIgnored(App app) =>
    !app.brokenCheckEnabled ||
    (app.brokenCheckDismissedVersion != null &&
        app.brokenCheckDismissedVersion == app.latestVersion);

List<BrokenCheckReason> evaluateBrokenCheckReasons(
  App app,
  BrokenCheckConfig config, {
  DateTime? now,
}) {
  final currentTime = now ?? DateTime.now();
  final reasons = <BrokenCheckReason>[];
  final staleReleaseDays = config.staleReleaseDays;
  final releaseDate = app.releaseDate;
  if (staleReleaseDays != null &&
      releaseDate != null &&
      currentTime.difference(releaseDate).inDays >= staleReleaseDays) {
    reasons.add(BrokenCheckReason.staleRelease);
  }
  final staleVersionDays = config.staleVersionDays;
  final versionChangedAt = app.latestVersionChangedAt;
  if (staleVersionDays != null &&
      versionChangedAt != null &&
      currentTime.difference(versionChangedAt).inDays >= staleVersionDays) {
    reasons.add(BrokenCheckReason.staleVersion);
  }
  final failedChecksCount = config.failedChecksCount;
  if (failedChecksCount != null &&
      app.consecutiveFailedChecks >= failedChecksCount) {
    reasons.add(BrokenCheckReason.failedChecks);
  }
  if (config.archivedEnabled && app.isArchived == true) {
    reasons.add(BrokenCheckReason.archived);
  }
  final filteredReleasesCount = config.filteredReleasesCount;
  final filteredOut = app.newerReleasesFilteredOut;
  if (filteredReleasesCount != null &&
      filteredOut != null &&
      filteredOut >= filteredReleasesCount) {
    reasons.add(BrokenCheckReason.filteredReleases);
  }
  return reasons;
}

bool isAppPossiblyBroken(App app, SettingsProvider settingsProvider) {
  if (app.disabled || app.hasPendingRepoRename || isBrokenCheckIgnored(app)) {
    return false;
  }
  return evaluateBrokenCheckReasons(
    app,
    resolveBrokenCheckConfig(app.additionalSettings, settingsProvider),
  ).isNotEmpty;
}

String brokenCheckReasonLabel(
  BrokenCheckReason reason,
  App app,
  BrokenCheckConfig config,
) {
  switch (reason) {
    case BrokenCheckReason.staleRelease:
      return tr(
        'possiblyBrokenReasonStaleRelease',
        args: ['${config.staleReleaseDays}'],
      );
    case BrokenCheckReason.staleVersion:
      return tr(
        'possiblyBrokenReasonStaleVersion',
        args: ['${config.staleVersionDays}'],
      );
    case BrokenCheckReason.failedChecks:
      return plural(
        'possiblyBrokenReasonFailedChecks',
        app.consecutiveFailedChecks,
      );
    case BrokenCheckReason.archived:
      return tr('possiblyBrokenReasonArchived');
    case BrokenCheckReason.filteredReleases:
      return plural(
        'possiblyBrokenReasonFilteredReleases',
        app.newerReleasesFilteredOut ?? 0,
      );
  }
}

bool shouldCountFailedCheck(Object error) =>
    error is! RateLimitError &&
    error is! SocketException &&
    error is! HandshakeException;

String brokenCheckDaysLabel(int days) =>
    days < 1 ? tr('disabled') : plural('day', days);
String brokenCheckFailedChecksLabel(int count) =>
    count < 1 ? tr('disabled') : plural('checks', count);
String brokenCheckFilteredReleasesLabel(int count) =>
    count < 1 ? tr('disabled') : plural('releases', count);

List<MapEntry<String, String>> _thresholdSliderOptions(List<int> values) {
  return [
    const MapEntry('', 'useGlobalDefault'),
    const MapEntry('off', 'disabled'),
    ...values
        .where((v) => v > 0)
        .map((v) => MapEntry(v.toString(), v.toString())),
  ];
}

List<List<GeneratedFormItem>> brokenCheckOverrideFormItems() {
  return [
    [
      GeneratedFormSlider(
        'brokenCheckStaleRelease',
        _thresholdSliderOptions(brokenCheckDayOptions),
        label: tr('possiblyBrokenOverrideStaleRelease'),
        value: '',
        required: false,
      ),
    ],
    [
      GeneratedFormSlider(
        'brokenCheckStaleVersion',
        _thresholdSliderOptions(brokenCheckDayOptions),
        label: tr('possiblyBrokenOverrideStaleVersion'),
        value: '',
        required: false,
      ),
    ],
    [
      GeneratedFormSlider(
        'brokenCheckFailedChecks',
        _thresholdSliderOptions(brokenCheckFailedChecksOptions),
        label: tr('possiblyBrokenOverrideFailedChecks'),
        value: '',
        required: false,
        numericLabelUnitKey: 'checks',
      ),
    ],
    [
      GeneratedFormDropdown(
        'brokenCheckArchived',
        [
          const MapEntry('', 'useGlobalDefault'),
          const MapEntry('off', 'disabled'),
          const MapEntry('on', 'enabled'),
        ],
        label: tr('possiblyBrokenOverrideArchived'),
        required: false,
      ),
    ],
    [
      GeneratedFormSlider(
        'brokenCheckFilteredReleases',
        _thresholdSliderOptions(brokenCheckFilteredReleasesOptions),
        label: tr('possiblyBrokenOverrideFilteredReleases'),
        value: '',
        required: false,
        numericLabelUnitKey: 'releases',
      ),
    ],
  ];
}
