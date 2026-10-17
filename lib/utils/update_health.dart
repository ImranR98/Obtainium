import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/settings_provider.dart';

enum UpdateHealthReason {
  staleRelease,
  staleVersion,
  failedChecks,
  archived,
  filteredReleases,
}

class UpdateHealthConfig {
  final int? staleReleaseDays;
  final int? staleVersionDays;
  final int? failedChecksCount;
  final bool archivedEnabled;
  final int? filteredReleasesCount;

  const UpdateHealthConfig({
    this.staleReleaseDays,
    this.staleVersionDays,
    this.failedChecksCount,
    this.archivedEnabled = false,
    this.filteredReleasesCount,
  });
}

const List<int> updateHealthDayOptions = [0, 30, 60, 90, 180, 365, 730];
const List<int> updateHealthFailedChecksOptions = [
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
const List<int> updateHealthFilteredReleasesOptions = [
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

UpdateHealthConfig resolveUpdateHealthConfig(
  Map<String, dynamic> additionalSettings,
  SettingsProvider settingsProvider,
) {
  return UpdateHealthConfig(
    staleReleaseDays: _resolveThreshold(
      additionalSettings['updateHealthStaleRelease'],
      settingsProvider.updateHealthStaleReleaseDays,
    ),
    staleVersionDays: _resolveThreshold(
      additionalSettings['updateHealthStaleVersion'],
      settingsProvider.updateHealthStaleVersionDays,
    ),
    failedChecksCount: _resolveThreshold(
      additionalSettings['updateHealthFailedChecks'],
      settingsProvider.updateHealthFailedChecksCount,
    ),
    archivedEnabled: _resolveArchived(
      additionalSettings['updateHealthArchived'],
      settingsProvider.updateHealthArchivedEnabled,
    ),
    filteredReleasesCount: _resolveThreshold(
      additionalSettings['updateHealthFilteredReleases'],
      settingsProvider.updateHealthFilteredReleasesCount,
    ),
  );
}

bool isUpdateHealthIgnored(App app) =>
    !app.updateHealthEnabled ||
    (app.updateHealthDismissedVersion != null &&
        app.updateHealthDismissedVersion == app.latestVersion);

List<UpdateHealthReason> evaluateUpdateHealthReasons(
  App app,
  UpdateHealthConfig config, {
  DateTime? now,
}) {
  final currentTime = now ?? DateTime.now();
  final reasons = <UpdateHealthReason>[];
  final staleReleaseDays = config.staleReleaseDays;
  final releaseDate = app.releaseDate;
  if (staleReleaseDays != null &&
      releaseDate != null &&
      currentTime.difference(releaseDate).inDays >= staleReleaseDays) {
    reasons.add(UpdateHealthReason.staleRelease);
  }
  final staleVersionDays = config.staleVersionDays;
  final versionChangedAt = app.latestVersionChangedAt;
  if (staleVersionDays != null &&
      versionChangedAt != null &&
      currentTime.difference(versionChangedAt).inDays >= staleVersionDays) {
    reasons.add(UpdateHealthReason.staleVersion);
  }
  final failedChecksCount = config.failedChecksCount;
  if (failedChecksCount != null &&
      app.consecutiveFailedChecks >= failedChecksCount) {
    reasons.add(UpdateHealthReason.failedChecks);
  }
  if (config.archivedEnabled && app.isArchived == true) {
    reasons.add(UpdateHealthReason.archived);
  }
  final filteredReleasesCount = config.filteredReleasesCount;
  final filteredOut = app.newerReleasesFilteredOut;
  if (filteredReleasesCount != null &&
      filteredOut != null &&
      filteredOut >= filteredReleasesCount) {
    reasons.add(UpdateHealthReason.filteredReleases);
  }
  return reasons;
}

bool hasUpdateHealthIssues(App app, SettingsProvider settingsProvider) {
  if (app.disabled || app.hasPendingRepoRename || isUpdateHealthIgnored(app)) {
    return false;
  }
  return evaluateUpdateHealthReasons(
    app,
    resolveUpdateHealthConfig(app.additionalSettings, settingsProvider),
  ).isNotEmpty;
}

String updateHealthReasonLabel(
  UpdateHealthReason reason,
  App app,
  UpdateHealthConfig config,
) {
  switch (reason) {
    case UpdateHealthReason.staleRelease:
      return tr(
        'updateHealthReasonStaleRelease',
        args: ['${config.staleReleaseDays}'],
      );
    case UpdateHealthReason.staleVersion:
      return tr(
        'updateHealthReasonStaleVersion',
        args: ['${config.staleVersionDays}'],
      );
    case UpdateHealthReason.failedChecks:
      return plural(
        'updateHealthReasonFailedChecks',
        app.consecutiveFailedChecks,
      );
    case UpdateHealthReason.archived:
      return tr('updateHealthReasonArchived');
    case UpdateHealthReason.filteredReleases:
      return plural(
        'updateHealthReasonFilteredReleases',
        app.newerReleasesFilteredOut ?? 0,
      );
  }
}

bool shouldCountFailedCheck(Object error) =>
    error is! RateLimitError &&
    error is! SocketException &&
    error is! HandshakeException;

String updateHealthDaysLabel(int days) =>
    days < 1 ? tr('disabled') : plural('day', days);
String updateHealthFailedChecksLabel(int count) =>
    count < 1 ? tr('disabled') : plural('checks', count);
String updateHealthFilteredReleasesLabel(int count) =>
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

const String updateHealthSectionId = 'updateHealthSection';

List<List<GeneratedFormItem>> updateHealthOverrideFormItems() {
  return [
    [
      GeneratedFormSlider(
        'updateHealthStaleRelease',
        _thresholdSliderOptions(updateHealthDayOptions),
        label: tr('updateHealthOverrideStaleRelease'),
        value: '',
        required: false,
      ),
    ],
    [
      GeneratedFormSlider(
        'updateHealthStaleVersion',
        _thresholdSliderOptions(updateHealthDayOptions),
        label: tr('updateHealthOverrideStaleVersion'),
        value: '',
        required: false,
      ),
    ],
    [
      GeneratedFormSlider(
        'updateHealthFailedChecks',
        _thresholdSliderOptions(updateHealthFailedChecksOptions),
        label: tr('updateHealthOverrideFailedChecks'),
        value: '',
        required: false,
        numericLabelUnitKey: 'checks',
      ),
    ],
    [
      GeneratedFormDropdown(
        'updateHealthArchived',
        [
          const MapEntry('', 'useGlobalDefault'),
          const MapEntry('off', 'disabled'),
          const MapEntry('on', 'enabled'),
        ],
        label: tr('updateHealthOverrideArchived'),
        required: false,
      ),
    ],
    [
      GeneratedFormSlider(
        'updateHealthFilteredReleases',
        _thresholdSliderOptions(updateHealthFilteredReleasesOptions),
        label: tr('updateHealthOverrideFilteredReleases'),
        value: '',
        required: false,
        numericLabelUnitKey: 'releases',
      ),
    ],
  ];
}
