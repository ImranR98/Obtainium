import 'package:obtainium/providers/settings_provider.dart';

/// The effect of the background guards on a background task, given the current
/// device conditions.
class BgGuardDecision {
  /// When true the background task should not check for updates at all.
  final bool skipChecks;

  /// When true updates found by this task may be silently installed.
  final bool allowInstalls;

  const BgGuardDecision({
    required this.skipChecks,
    required this.allowInstalls,
  });
}

/// Decides what a background task may do under the configured guard modes.
///
/// A guard only applies when its condition is unmet: "nothing" skips checks
/// (and therefore installs), "checksOnly" allows checks and notifications but
/// blocks installs, and "checksAndUpdates" allows everything.
BgGuardDecision evaluateBgGuards({
  required BgGuardMode wifiMode,
  required BgGuardMode chargingMode,
  required bool onUnmeteredNetwork,
  required bool charging,
}) {
  final skipChecks =
      (wifiMode == BgGuardMode.nothing && !onUnmeteredNetwork) ||
      (chargingMode == BgGuardMode.nothing && !charging);
  final allowInstalls =
      !skipChecks &&
      (onUnmeteredNetwork || wifiMode == BgGuardMode.checksAndUpdates) &&
      (charging || chargingMode == BgGuardMode.checksAndUpdates);
  return BgGuardDecision(skipChecks: skipChecks, allowInstalls: allowInstalls);
}

/// Whether a background task may silently install updates.
///
/// Manual runs (`forceAll`) only check, so the guards alone decide installs.
bool canInstallInBackground({
  required bool forceAll,
  required BgGuardDecision decision,
}) => !forceAll && decision.allowInstalls;
