// Tracks which apps have a patch job "due" but not yet run. Deliberately
// separate from patch_executor.dart (which actually runs a job): the
// background WorkManager isolate has no native Flutter engine attached, so it
// can only ever mark a job pending here - never execute one. Only the
// foreground path (a live engine) calls into patch_executor.dart to run it.
// Keeping this split means a future background-capable executor can replace
// just the "run" side later without touching how jobs get marked due.

import 'package:flutter/material.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/revanced/patch_config.dart';
import 'package:obtainium/providers/source_provider.dart';

extension PatchJobApp on App {
  bool get hasPendingPatchJob => additionalSettings['patchJobPending'] == true;

  App withPatchJobPending(bool pending) => copyWith(
    additionalSettings: {...additionalSettings, 'patchJobPending': pending},
  );
}

bool appNeedsPatching(App app) => app.patchConfig.isNotEmpty;

extension AppsProviderPatchJobs on AppsProvider {
  /// Runs any patch jobs the background update check deferred (see
  /// patch_executor.dart) - meant to be called once from the foreground, e.g.
  /// shortly after app startup, where a live engine is available.
  Future<void> runPendingPatchJobs(
    BuildContext context, {
    NotificationsProvider? notificationsProvider,
  }) async {
    final pendingIds = getAppValues()
        .where((a) => a.app.hasPendingPatchJob)
        .map((a) => a.app.id)
        .toList();
    if (pendingIds.isEmpty) return;
    await downloadAndInstallLatestApps(
      pendingIds,
      context,
      notificationsProvider: notificationsProvider,
    );
  }
}
