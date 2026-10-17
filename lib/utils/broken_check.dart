import 'dart:io';

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

bool shouldCountFailedCheck(Object error) =>
    error is! RateLimitError &&
    error is! SocketException &&
    error is! HandshakeException;
