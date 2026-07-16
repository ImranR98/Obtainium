// Downloads and caches the ReVanced universal-patches bundle, and exposes its
// available patches (name/description/options) for the per-app patch-config
// UI, via a native round-trip (bundle parsing needs patcher-android, which
// only exists in the "normal" flavor's Kotlin source set).

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';

const String _channelName = 'dev.imranr.obtainium/revanced';
const String kPatchBundleUrlKey = 'revanced-patch-bundle-url';

// ReVanced ships its universal-patches bundle as a release asset on
// revanced/revanced-patches; this points at the latest one by default.
// User-configurable in case the asset name/location changes or the user wants
// to point at a fork/mirror.
const String kDefaultPatchBundleUrl =
    'https://github.com/revanced/revanced-patches/releases/latest/download/patches.rvp';

class PatchMetadata {
  final String name;
  final String description;
  final List<PatchOptionMetadata> options;

  PatchMetadata({
    required this.name,
    required this.description,
    required this.options,
  });

  factory PatchMetadata.fromMap(Map<dynamic, dynamic> map) => PatchMetadata(
    name: map['name']?.toString() ?? '',
    description: map['description']?.toString() ?? '',
    options:
        (map['options'] as List<dynamic>?)
            ?.map((e) => PatchOptionMetadata.fromMap(e as Map<dynamic, dynamic>))
            .toList() ??
        const [],
  );
}

class PatchOptionMetadata {
  final String key;
  final String description;
  final bool required;
  final String type; // 'string' | 'boolean' | 'integer' | 'stringList'
  final dynamic defaultValue;

  PatchOptionMetadata({
    required this.key,
    required this.description,
    required this.required,
    required this.type,
    this.defaultValue,
  });

  factory PatchOptionMetadata.fromMap(Map<dynamic, dynamic> map) =>
      PatchOptionMetadata(
        key: map['key']?.toString() ?? '',
        description: map['description']?.toString() ?? '',
        required: map['required'] as bool? ?? false,
        type: map['type']?.toString() ?? 'string',
        defaultValue: map['default'],
      );
}

class PatchBundleProvider {
  PatchBundleProvider({SettingsProvider? settingsProvider, MethodChannel? channel})
    : _settingsProvider = settingsProvider,
      _channel = channel ?? const MethodChannel(_channelName);

  final SettingsProvider? _settingsProvider;
  final MethodChannel _channel;

  SettingsProvider get _settings => _settingsProvider ?? SettingsProvider();

  String get bundleUrl =>
      _settings.getSettingString(kPatchBundleUrlKey) ?? kDefaultPatchBundleUrl;

  set bundleUrl(String url) => _settings.setSettingString(kPatchBundleUrlKey, url);

  Future<Directory> _bundleDir() async {
    final dir = Directory('${(await getAppStorageDir()).path}/revanced');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> _bundleFile() async => File('${(await _bundleDir()).path}/patches.jar');

  Future<bool> hasCachedBundle() async => (await _bundleFile()).exists();

  /// Downloads (or re-downloads) the configured patch bundle. Manual action
  /// only - not implicitly refreshed on every update check, so an
  /// already-configured app's behavior doesn't change mid-flight.
  Future<void> updateBundle() async {
    final file = await _bundleFile();
    try {
      final response = await HttpClient().getUrl(Uri.parse(bundleUrl)).then((
        req,
      ) => req.close());
      if (response.statusCode != 200) {
        throw ObtainiumError('Failed to download patch bundle: HTTP ${response.statusCode}');
      }
      final sink = file.openWrite();
      await response.pipe(sink);
      await sink.close();
    } catch (e) {
      throw ObtainiumError('Failed to download patch bundle: $e');
    }
  }

  /// Lists the universal patches (and their options) available in the
  /// currently cached bundle. Returns an empty list if no bundle is cached
  /// yet - callers should prompt to run [updateBundle] first.
  Future<List<PatchMetadata>> listUniversalPatches() async {
    final file = await _bundleFile();
    if (!file.existsSync()) return [];
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('listPatches', {
        'bundlePath': file.path,
      });
      return (result ?? [])
          .map((e) => PatchMetadata.fromMap(e as Map<dynamic, dynamic>))
          .toList();
    } on MissingPluginException {
      return [];
    } on PlatformException catch (e) {
      throw ObtainiumError(e.message ?? 'Failed to list patches');
    }
  }

  Future<String> bundlePath() async => (await _bundleFile()).path;
}
