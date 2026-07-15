import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:obtainium/providers/apps_provider.dart' show packageManager;
import 'package:obtainium/providers/logs_provider.dart';

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
      unawaited(
        LogsProvider().add(
          'Failed to list external installer targets: $e',
          level: LogLevel.error,
        ),
      );
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
      unawaited(
        LogsProvider().add(
          'Failed to get label for $package: $e',
          level: LogLevel.warning,
        ),
      );
      return null;
    }
  }

  Future<Uint8List?> _iconFor(String package) async {
    try {
      return await packageManager.getApplicationIcon(packageName: package);
    } catch (e) {
      unawaited(
        LogsProvider().add(
          'Failed to get icon for $package: $e',
          level: LogLevel.warning,
        ),
      );
      return null;
    }
  }

  /// Resolves a filesystem path to a content:// URI served by the FileProvider.
  Future<String?> contentUriForFile(String path) async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('contentUriForFile', {'path': path});
  }
}
