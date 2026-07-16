// Per-app ReVanced patch selection + options, stored inside
// App.additionalSettings['patchConfig']. Rides through Obtainium's existing
// general import/export automatically since additionalSettings is already
// JSON-encoded as part of App.toJson()/App.fromJson().

import 'package:obtainium/providers/source_provider.dart';

class SelectedPatch {
  final String patchName;
  final Map<String, dynamic> options;

  SelectedPatch({required this.patchName, this.options = const {}});

  factory SelectedPatch.fromJson(Map<String, dynamic> json) => SelectedPatch(
    patchName: json['patchName'] as String? ?? '',
    options: (json['options'] as Map<String, dynamic>?) ?? const {},
  );

  Map<String, dynamic> toJson() => {
    'patchName': patchName,
    'options': options,
  };
}

class PatchConfig {
  final List<SelectedPatch> selectedPatches;

  /// If a configured patch fails to apply to a new app version (patches
  /// often lag behind app releases), block the update by default - a
  /// same-source APK that's merely re-signed (no patches) would still fail
  /// to install over a previously-patched install anyway unless the user
  /// opts into this fallback, which re-signs without applying any patches.
  final bool fallbackToSignOnlyOnPatchFailure;

  /// Set once the first patched install for this app has succeeded, so the
  /// one-time uninstall-required dialog isn't shown again on later updates.
  final bool firstPatchedInstallDone;

  const PatchConfig({
    this.selectedPatches = const [],
    this.fallbackToSignOnlyOnPatchFailure = false,
    this.firstPatchedInstallDone = false,
  });

  bool get isEmpty => selectedPatches.isEmpty;
  bool get isNotEmpty => selectedPatches.isNotEmpty;

  factory PatchConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PatchConfig();
    return PatchConfig(
      selectedPatches:
          (json['selectedPatches'] as List<dynamic>?)
              ?.map((e) => SelectedPatch.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      fallbackToSignOnlyOnPatchFailure:
          json['fallbackToSignOnlyOnPatchFailure'] as bool? ?? false,
      firstPatchedInstallDone: json['firstPatchedInstallDone'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'selectedPatches': selectedPatches.map((e) => e.toJson()).toList(),
    'fallbackToSignOnlyOnPatchFailure': fallbackToSignOnlyOnPatchFailure,
    'firstPatchedInstallDone': firstPatchedInstallDone,
  };

  PatchConfig copyWith({
    List<SelectedPatch>? selectedPatches,
    bool? fallbackToSignOnlyOnPatchFailure,
    bool? firstPatchedInstallDone,
  }) => PatchConfig(
    selectedPatches: selectedPatches ?? this.selectedPatches,
    fallbackToSignOnlyOnPatchFailure:
        fallbackToSignOnlyOnPatchFailure ?? this.fallbackToSignOnlyOnPatchFailure,
    firstPatchedInstallDone:
        firstPatchedInstallDone ?? this.firstPatchedInstallDone,
  );

  static PatchConfig fromApp(App app) =>
      PatchConfig.fromJson(app.additionalSettings['patchConfig'] as Map<String, dynamic>?);

  /// Maps to the shape revanced-library's Options.setOptions expects:
  /// { patchName: { optionKey: value } }.
  Map<String, Map<String, dynamic>> toNativeOptions() => {
    for (final p in selectedPatches) p.patchName: p.options,
  };

  List<String> get patchNames =>
      selectedPatches.map((p) => p.patchName).toList();
}

extension AppPatchConfig on App {
  PatchConfig get patchConfig => PatchConfig.fromApp(this);

  App withPatchConfig(PatchConfig config) => copyWith(
    additionalSettings: {
      ...additionalSettings,
      'patchConfig': config.toJson(),
    },
  );
}
