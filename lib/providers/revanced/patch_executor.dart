// Runs a due patch job: download is already done by the time this is called
// (from _downloadAppForInstall) - this only patches + signs the already
// downloaded APK, in place of the stock file, before the normal install step
// runs. Only ever called with a non-null BuildContext (i.e. from a live
// foreground engine) - see patch_job_provider.dart for why.

import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/revanced/keystore_provider.dart';
import 'package:obtainium/providers/revanced/patch_bundle_provider.dart';
import 'package:obtainium/providers/revanced/patch_config.dart';
import 'package:obtainium/providers/revanced/patch_engine_channel.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';

class PatchAbortedException implements Exception {
  final String message;
  PatchAbortedException(this.message);
  @override
  String toString() => message;
}

extension AppsProviderPatchExecutor on AppsProvider {
  /// If [app] has no patch config, returns [downloadedApk] unchanged. Otherwise
  /// patches+signs it and returns the result, or throws [PatchAbortedException]
  /// / [ObtainiumError] if patching fails and the app isn't configured to fall
  /// back to a sign-only (unpatched) install.
  Future<File> patchDownloadedApkIfConfigured(
    App app,
    File downloadedApk,
    BuildContext context, {
    NotificationsProvider? notificationsProvider,
  }) async {
    final config = app.patchConfig;
    if (config.isEmpty) return downloadedApk;

    if (!context.mounted) return downloadedApk;
    final keystoreProvider = context.read<KeystoreProvider>();
    final patchBundleProvider = PatchBundleProvider(
      settingsProvider: settingsProvider,
    );
    final channel = PatchEngineChannel();

    // A signature conflict only matters the first time a patched build
    // replaces a previously stock-installed copy of this app - subsequent
    // patched updates are signed the same way as the last one and install
    // silently like normal.
    if (!config.firstPatchedInstallDone && app.installedVersion != null) {
      if (!context.mounted) {
        throw PatchAbortedException('Cannot confirm patch install: no UI context');
      }
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(tr('patchedInstallRequiresUninstall')),
          content: Text(
            tr('patchedInstallRequiresUninstallExplanation', args: [app.finalName]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(tr('proceed')),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        throw PatchAbortedException(tr('patchedInstallCancelledByUser'));
      }
    }

    if (!await keystoreProvider.hasKeystore()) {
      await keystoreProvider.regenerate();
    }

    final outputPath = '${downloadedApk.path}.revanced-patched.apk';
    final hasBundle = await patchBundleProvider.hasCachedBundle();

    unawaited(
      notificationsProvider?.notify(PatchingNotification(app.finalName)),
    );
    try {
      PatchApplyResult result;
      if (!hasBundle) {
        result = PatchApplyResult(
          success: false,
          error: 'No patch bundle downloaded yet',
        );
      } else {
        result = await channel.applyPatches(
          bundlePath: await patchBundleProvider.bundlePath(),
          inputApkPath: downloadedApk.path,
          outputApkPath: outputPath,
          packageName: app.id,
          patchConfig: config,
          keystoreProvider: keystoreProvider,
        );
      }

      if (!result.success && config.fallbackToSignOnlyOnPatchFailure) {
        result = await channel.applyPatches(
          bundlePath: await patchBundleProvider.bundlePath(),
          inputApkPath: downloadedApk.path,
          outputApkPath: outputPath,
          packageName: app.id,
          patchConfig: config,
          keystoreProvider: keystoreProvider,
          signOnly: true,
        );
      }

      if (!result.success) {
        unawaited(
          notificationsProvider?.notify(
            PatchingFailedNotification(app.finalName, result.error ?? ''),
          ),
        );
        throw ObtainiumError(
          '${tr('patchingFailed', args: [app.finalName])}: ${result.error ?? ''}',
        );
      }

      final patched = File(result.outputPath!);
      final updated = app.withPatchConfig(
        config.copyWith(firstPatchedInstallDone: true),
      );
      await saveApps([updated], onlyIfExists: true);
      return patched;
    } finally {
      unawaited(
        notificationsProvider?.cancel(PatchingNotification(app.finalName).id),
      );
    }
  }
}
