import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:obtainium/providers/apps_provider.dart' show packageManager;
import 'package:obtainium/core/logging/app_logger.dart';

/// A device app that can receive an APK install handoff.
class InstallerTarget {
  final String package;
  final String activity;
  final String label;
  final Uint8List? icon;

  const InstallerTarget({
    required this.package,
    required this.activity,
    required this.label,
    this.icon,
  });
}

/// Outcome of a tracked external-installer handoff.
class ExternalInstallResult {
  /// Whether the installer (or a package-change broadcast) reported the
  /// install as completed. Callers should still verify against the package
  /// manager before trusting it.
  final bool installed;

  /// Installer-reported failure code (a PackageManager INSTALL_FAILED_* value)
  /// when the installer supports reporting one.
  final int? errorCode;

  const ExternalInstallResult({required this.installed, this.errorCode});
}

/// Parses a native `launchInstallIntent` payload into an
/// [ExternalInstallResult]. Returns null when no result was reported.
ExternalInstallResult? externalInstallResultFromNative(Object? raw) {
  if (raw is! Map) return null;
  final errorCode = raw['errorCode'];
  return ExternalInstallResult(
    installed: raw['installed'] == true,
    errorCode: errorCode is int ? errorCode : null,
  );
}

/// Bridge to the two native helpers that have no Flutter-plugin equivalent:
/// enumerating APK-install-capable activities and turning a downloaded file
/// into a shareable content:// URI. All handoff orchestration stays in Dart.
class ExternalInstallerBridge {
  ExternalInstallerBridge._();

  static final ExternalInstallerBridge instance = ExternalInstallerBridge._();

  static const MethodChannel _channel = MethodChannel(
    'dev.imranr.obtainium/external_install',
  );

  /// Lists installer apps, enriching each native package/activity pair with a
  /// human-readable label and launcher icon fetched via the package manager.
  Future<List<InstallerTarget>> listTargets() async {
    if (!Platform.isAndroid) return const [];
    List<dynamic>? raw;
    try {
      raw = await _channel.invokeMethod<List<dynamic>>('listInstallTargets');
    } catch (e) {
      AppLogger.error(e, message: 'Failed to list external installer targets');
      return const [];
    }
    if (raw == null) return const [];

    final targets = <InstallerTarget>[];
    for (final entry in raw) {
      final map = Map<String, dynamic>.from(entry as Map);
      final package = map['package']?.toString();
      final activity = map['activity']?.toString();
      if (package == null || activity == null) continue;
      final label = await _labelFor(package);
      final icon = await _iconFor(package);
      targets.add(
        InstallerTarget(
          package: package,
          activity: activity,
          label: label ?? package,
          icon: icon,
        ),
      );
    }
    targets.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    return targets;
  }

  Future<String?> _labelFor(String package) async {
    try {
      return await packageManager.getApplicationLabel(packageName: package);
    } catch (e) {
      AppLogger.warn('Failed to get label for $package: $e');
      return null;
    }
  }

  Future<Uint8List?> _iconFor(String package) async {
    try {
      return await packageManager.getApplicationIcon(packageName: package);
    } catch (e) {
      AppLogger.warn('Failed to get icon for $package: $e');
      return null;
    }
  }

  /// Resolves a filesystem path to a content:// URI served by the FileProvider.
  Future<String?> contentUriForFile(String path) async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('contentUriForFile', {'path': path});
  }

  /// Hands [uri] to the chosen external installer and waits for the tracked
  /// result. Returns null when result tracking is unavailable (non-Android or
  /// an older native side), in which case the caller should fall back to
  /// polling the package state.
  Future<ExternalInstallResult?> launchInstallIntent({
    required String uri,
    required String type,
    required String expectedPackageName,
    String? package,
    String? activity,
  }) async {
    if (!Platform.isAndroid) return null;
    final raw = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('launchInstallIntent', {
          'uri': uri,
          'type': type,
          'package': package,
          'activity': activity,
          'expectedPackageName': expectedPackageName,
        });
    return externalInstallResultFromNative(raw);
  }
}
