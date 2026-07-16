// UI for selecting ReVanced universal patches and their options for a single
// app. A dedicated widget rather than reusing GeneratedFormSubForm, since that
// repeats one fixed field schema per row and can't express "different option
// fields depending on which patch this row selects."

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/providers/revanced/patch_bundle_provider.dart';
import 'package:obtainium/providers/revanced/patch_config.dart';

class PatchConfigForm extends StatefulWidget {
  const PatchConfigForm({
    super.key,
    required this.initialConfig,
    required this.bundleProvider,
    required this.onChanged,
  });

  final PatchConfig initialConfig;
  final PatchBundleProvider bundleProvider;
  final void Function(PatchConfig) onChanged;

  @override
  State<PatchConfigForm> createState() => _PatchConfigFormState();
}

class _PatchConfigFormState extends State<PatchConfigForm> {
  late PatchConfig _config;
  Future<List<PatchMetadata>>? _patchesFuture;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    _patchesFuture = widget.bundleProvider.listUniversalPatches();
  }

  Map<String, dynamic> _optionsFor(String patchName) =>
      _config.selectedPatches
          .firstWhere(
            (p) => p.patchName == patchName,
            orElse: () => SelectedPatch(patchName: patchName),
          )
          .options;

  bool _isSelected(String patchName) =>
      _config.selectedPatches.any((p) => p.patchName == patchName);

  void _setSelected(String patchName, bool selected) {
    setState(() {
      final patches = List<SelectedPatch>.from(_config.selectedPatches);
      patches.removeWhere((p) => p.patchName == patchName);
      if (selected) {
        patches.add(SelectedPatch(patchName: patchName));
      }
      _config = _config.copyWith(selectedPatches: patches);
    });
    widget.onChanged(_config);
  }

  void _setOption(String patchName, String key, dynamic value) {
    setState(() {
      final patches = List<SelectedPatch>.from(_config.selectedPatches);
      final index = patches.indexWhere((p) => p.patchName == patchName);
      if (index == -1) return;
      final options = Map<String, dynamic>.from(patches[index].options);
      options[key] = value;
      patches[index] = SelectedPatch(patchName: patchName, options: options);
      _config = _config.copyWith(selectedPatches: patches);
    });
    widget.onChanged(_config);
  }

  Future<void> _refreshBundle() async {
    setState(() => _refreshing = true);
    try {
      await widget.bundleProvider.updateBundle();
      setState(() {
        _patchesFuture = widget.bundleProvider.listUniversalPatches();
      });
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Widget _buildOptionField(String patchName, PatchOptionMetadata option) {
    final currentValue = _optionsFor(patchName)[option.key] ?? option.defaultValue;
    switch (option.type) {
      case 'boolean':
        return SwitchListTile(
          dense: true,
          title: Text(option.key),
          subtitle: option.description.isEmpty ? null : Text(option.description),
          value: currentValue == true,
          onChanged: (v) => _setOption(patchName, option.key, v),
        );
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: TextFormField(
            initialValue: currentValue?.toString() ?? '',
            decoration: InputDecoration(
              labelText: option.key,
              helperText: option.description.isEmpty ? null : option.description,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => _setOption(
              patchName,
              option.key,
              option.type == 'integer' ? int.tryParse(v) : v,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PatchMetadata>>(
      future: _patchesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final patches = snapshot.data ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (patches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(tr('noPatchBundleCached')),
              ),
            OutlinedButton.icon(
              onPressed: _refreshing ? null : _refreshBundle,
              icon: _refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(tr('updatePatchBundle')),
            ),
            ...patches.map((patch) {
              final selected = _isSelected(patch.name);
              return ExpansionTile(
                initiallyExpanded: selected,
                leading: Checkbox(
                  value: selected,
                  onChanged: (v) => _setSelected(patch.name, v ?? false),
                ),
                title: Text(patch.name),
                subtitle: patch.description.isEmpty ? null : Text(patch.description),
                children: !selected
                    ? []
                    : patch.options
                          .map((o) => _buildOptionField(patch.name, o))
                          .toList(),
              );
            }),
            if (_config.selectedPatches.isNotEmpty)
              SwitchListTile(
                dense: true,
                title: Text(tr('fallbackToSignOnlyOnPatchFailure')),
                subtitle: Text(tr('fallbackToSignOnlyOnPatchFailureExplanation')),
                value: _config.fallbackToSignOnlyOnPatchFailure,
                onChanged: (v) {
                  setState(() {
                    _config = _config.copyWith(fallbackToSignOnlyOnPatchFailure: v);
                  });
                  widget.onChanged(_config);
                },
              ),
          ],
        );
      },
    );
  }
}
