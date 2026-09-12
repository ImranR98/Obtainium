// Minimum update age resolution and suppression helpers.
//
// Sources may skip releases younger than the configured minimum update age
// (supply-chain delay); sources that cannot look back rely on the fetch
// suppression below and on the add-time check in [SourceProvider.getApp].

import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/settings_provider.dart';

/// Resolves the effective minimum update age (in days) for an app: the
/// per-app override when set, otherwise the global setting.
Future<int> effectiveMinUpdateAgeDays(
  Map<String, dynamic> additionalSettings, {
  SettingsProvider? settingsProvider,
}) async {
  final raw = additionalSettings['minimumUpdateAgeDays'];
  if (raw is String && raw.isNotEmpty) {
    final parsed = int.tryParse(raw);
    if (parsed != null) {
      return parsed;
    }
  }
  final sp = settingsProvider ?? SettingsProvider();
  await sp.initializeSettings();
  return sp.minimumUpdateAgeDays;
}

/// Whether [releaseDate] is younger than [minAgeDays] as of [now].
bool isReleaseTooYoung(DateTime? releaseDate, int minAgeDays, {DateTime? now}) {
  if (releaseDate == null || minAgeDays <= 0) return false;
  return (now ?? DateTime.now()).difference(releaseDate) <
      Duration(days: minAgeDays);
}

/// Replaces the release-specific fields of [fetchedApp] with [currentApp]'s, so
/// the update stays suppressed until the fetched release is old enough. The
/// APK URLs must move with the version, otherwise an update made during the
/// suppression window would silently download the fresh release.
App applyMinAgeSuppression(App currentApp, App fetchedApp) {
  return fetchedApp.copyWith(
    latestVersion: currentApp.latestVersion,
    releaseDate: currentApp.releaseDate,
    changeLog: currentApp.changeLog,
    apkUrls: currentApp.apkUrls,
    otherAssetUrls: currentApp.otherAssetUrls,
  );
}
