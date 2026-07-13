import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/theme/app_dialog_theme.dart';
import 'package:obtainium/theme/app_form_field_styles.dart';

typedef RegexAssistRawVersionResolver =
    Future<String?> Function(Map<String, dynamic> currentValues);

/// Removes segments that are alphabet-only (e.g. pixel, beta, release).
String stripLetterOnlySegmentsFromVersionRaw(String raw) {
  final List<String> parts = raw
      .split(RegExp(r'[.+_-]+'))
      .map((String segment) => segment.trim())
      .where((String segment) => segment.isNotEmpty)
      .toList();
  final List<String> kept = parts
      .where((String segment) => !RegExp(r'^[a-zA-Z]+$').hasMatch(segment))
      .toList();
  return kept.join('.');
}

/// Escapes [s] for regex, then wildcards digit runs that are NOT directly
/// adjacent to an ASCII letter — so version numbers like `19.35.34` become
/// `[0-9]+\.[0-9]+\.[0-9]+`, but identifier-embedded digits like the `64` in
/// `arm64` or the `8` in `v8a` stay literal.
String _regexEscapeWithVersionWildcards(String s) {
  return RegExp.escape(s).replaceAllMapped(
    RegExp(r'(?<![a-zA-Z])[0-9]+(?![a-zA-Z])'),
    (_) => '[0-9]+',
  );
}

/// One dot-separated segment: ASCII digit runs separated by hyphens (e.g. `12`, `8-27`).
bool _segmentIsDigitsAndHyphensOnly(String segment) {
  if (segment.isEmpty) {
    return false;
  }
  final List<String> hyphenParts = segment.split('-');
  for (final String part in hyphenParts) {
    if (part.isEmpty) {
      return false;
    }
    for (int i = 0; i < part.length; i++) {
      final int unit = part.codeUnitAt(i);
      if (unit < 0x30 || unit > 0x39) {
        return false;
      }
    }
  }
  return true;
}

bool _desiredUsesOnlyNumericHyphenSegments(String desired) {
  final List<String> parts = desired.trim().split('.');
  if (parts.isEmpty) {
    return false;
  }
  for (final String part in parts) {
    if (!_segmentIsDigitsAndHyphensOnly(part)) {
      return false;
    }
  }
  return true;
}

/// Wildcard fragment for one segment: same count of hyphen-separated digit runs as [segment].
String? _wildcardFragmentForSegment(String segment) {
  if (!_segmentIsDigitsAndHyphensOnly(segment)) {
    return null;
  }
  final List<String> hyphenParts = segment.split('-');
  if (hyphenParts.length == 1) {
    return '[0-9]+';
  }
  final StringBuffer buffer = StringBuffer('[0-9]+');
  for (int i = 1; i < hyphenParts.length; i++) {
    buffer.write('-[0-9]+');
  }
  return buffer.toString();
}

String? _digitWildcardCapturePattern(String desired) {
  final String trimmed = desired.trim();
  if (!_desiredUsesOnlyNumericHyphenSegments(trimmed)) {
    return null;
  }
  final List<String> parts = trimmed.split('.');
  if (parts.isEmpty) {
    return null;
  }
  final List<String> fragments = <String>[];
  for (final String part in parts) {
    final String? fragment = _wildcardFragmentForSegment(part);
    if (fragment == null) {
      return null;
    }
    fragments.add(fragment);
  }
  return '(${fragments.join(r'\.')})';
}

String? _hexWildcardCapturePattern(String desired) {
  final String trimmed = desired.trim();
  if (trimmed.length < 6 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(trimmed)) {
    return null;
  }
  return '([0-9a-fA-F]{${trimmed.length}})';
}

List<String> candidateVersionStringsFromRaw(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) return <String>[];
  final Set<String> seen = <String>{};
  final List<String> ordered = <String>[];

  void add(String value) {
    final String candidate = value.trim();
    if (candidate.isEmpty) return;
    if (seen.add(candidate)) {
      ordered.add(candidate);
    }
  }

  add(trimmed);
  if (trimmed.length > 1 &&
      (trimmed.startsWith('v') || trimmed.startsWith('V'))) {
    add(trimmed.substring(1));
  }
  final String strippedWords = stripLetterOnlySegmentsFromVersionRaw(trimmed);
  if (strippedWords.isNotEmpty && strippedWords != trimmed) {
    add(strippedWords);
  }
  final RegExp semverLike = RegExp(r'\d+\.\d+\.\d+(?:[.\w\-+/][\w\-+/]*)?');
  for (final Match match in semverLike.allMatches(trimmed)) {
    final String? group = match.group(0);
    if (group != null) {
      add(group);
    }
  }
  ordered.sort((String a, String b) => b.length.compareTo(a.length));
  return ordered;
}

Map<String, String>? tryBuildRegexForExtractedVersion({
  required String raw,
  required String desired,
}) {
  final String trimmedDesired = desired.trim();
  if (raw.isEmpty || trimmedDesired.isEmpty) return null;
  if (!raw.contains(trimmedDesired)) return null;

  final String? wildcardPattern = _digitWildcardCapturePattern(trimmedDesired);
  if (wildcardPattern != null) {
    for (final String pattern in <String>[
      wildcardPattern,
      '.*$wildcardPattern',
    ]) {
      try {
        final String? out = extractVersion(pattern, r'$1', raw);
        if (out == trimmedDesired) {
          return <String, String>{
            'versionExtractionRegEx': pattern,
            'matchGroupToUse': r'$1',
          };
        }
      } catch (_) {}
    }
  }

  final String? hexWildcardPattern = _hexWildcardCapturePattern(trimmedDesired);
  if (hexWildcardPattern != null) {
    final int desiredStart = raw.indexOf(trimmedDesired);
    final List<String> hexPatterns = <String>[];
    if (desiredStart == 0) {
      hexPatterns.add('^$hexWildcardPattern.*');
    }
    if (desiredStart + trimmedDesired.length == raw.length) {
      hexPatterns.add('.*$hexWildcardPattern\$');
    }
    hexPatterns.add('.*?$hexWildcardPattern.*');
    for (final String pattern in hexPatterns) {
      try {
        final String? out = extractVersion(pattern, r'$1', raw);
        if (out == trimmedDesired) {
          return <String, String>{
            'versionExtractionRegEx': pattern,
            'matchGroupToUse': r'$1',
          };
        }
      } catch (_) {}
    }
  }

  final String escaped = _regexEscapeWithVersionWildcards(trimmedDesired);
  final List<String> patterns = <String>['($escaped)', '.*($escaped)'];
  for (final String pattern in patterns) {
    try {
      final String? out = extractVersion(pattern, r'$1', raw);
      if (out == trimmedDesired) {
        return <String, String>{
          'versionExtractionRegEx': pattern,
          'matchGroupToUse': r'$1',
        };
      }
    } catch (_) {}
  }
  return null;
}

/// Builds a filter RegEx so [RegExp] matches [raw] and the chosen substring is covered.
String? tryBuildFilterRegExFromSelection({
  required String raw,
  required String desired,
}) {
  final String trimmedDesired = desired.trim();
  if (raw.isEmpty || trimmedDesired.isEmpty) {
    return null;
  }
  if (!raw.contains(trimmedDesired)) {
    return null;
  }

  bool matchesRaw(String pattern) {
    try {
      return RegExp(pattern).hasMatch(raw);
    } catch (_) {
      return false;
    }
  }

  final String? wildcardPattern = _digitWildcardCapturePattern(trimmedDesired);
  if (wildcardPattern != null) {
    for (final String pattern in <String>[
      wildcardPattern,
      '.*$wildcardPattern',
      '$wildcardPattern.*',
      '.*$wildcardPattern.*',
    ]) {
      if (matchesRaw(pattern)) {
        return pattern;
      }
    }
  }

  final String escaped = _regexEscapeWithVersionWildcards(trimmedDesired);
  for (final String pattern in <String>[
    escaped,
    '.*$escaped',
    '$escaped.*',
    '.*$escaped.*',
  ]) {
    if (matchesRaw(pattern)) {
      return pattern;
    }
  }
  return null;
}

enum RegexAssistKind {
  versionExtraction,
  apkFilter,
  releaseTitleFilter,
  versionFilter,
}

List<String> regexAssistLinesFromSnapshot(String? snapshot) {
  if (snapshot == null || snapshot.trim().isEmpty) {
    return <String>[];
  }
  return snapshot
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .toList();
}

/// Wires RegEx assist onto version and filter fields (mutates items in place).
List<List<GeneratedFormItem>> attachRegexAssistToItems(
  List<List<GeneratedFormItem>> items, {
  required String? rawLatestVersionFromSource,
  required String? rawApkNamesFromSource,
  required String? rawReleaseTitlesFromSource,
  RegexAssistRawVersionResolver? resolveRawLatestVersionFromValues,
}) {
  final List<String> apkRawLines = regexAssistLinesFromSnapshot(
    rawApkNamesFromSource,
  );
  final List<String> titleRawLines = regexAssistLinesFromSnapshot(
    rawReleaseTitlesFromSource,
  );
  for (final List<GeneratedFormItem> row in items) {
    for (final GeneratedFormItem element in row) {
      if (element is! GeneratedFormTextField) {
        continue;
      }
      if (element.key == 'versionExtractionRegEx') {
        element.assistAction =
            (
              BuildContext context,
              FormValuesTextPatch patch,
              Map<String, dynamic> currentValues,
            ) async {
              final String versionStringSource = getVersionStringSource(
                currentValues,
              );
              final List<String> versionRawLines =
                  versionStringSource == versionStringSourceAssetName
                  ? apkRawLines
                  : versionStringSource == versionStringSourceReleaseTitle
                  ? titleRawLines
                  : const <String>[];
              final String? versionInitialRaw = versionRawLines.isNotEmpty
                  ? versionRawLines.first
                  : rawLatestVersionFromSource;
              String? resolvedInitialRaw = versionInitialRaw;
              if (resolveRawLatestVersionFromValues != null) {
                final String? liveRaw = await resolveRawLatestVersionFromValues(
                  currentValues,
                );
                if (liveRaw?.trim().isNotEmpty == true) {
                  resolvedInitialRaw = liveRaw;
                }
              }
              String? initialDesired;
              if (resolvedInitialRaw?.trim().isNotEmpty == true) {
                try {
                  initialDesired = extractVersion(
                    currentValues['versionExtractionRegEx'] as String?,
                    currentValues['matchGroupToUse'] as String?,
                    resolvedInitialRaw!,
                  );
                } catch (_) {
                  initialDesired = null;
                }
              }
              if (!context.mounted) {
                return;
              }
              return showRegexAssistDialog(
                context: context,
                kind: RegexAssistKind.versionExtraction,
                initialRaw: resolvedInitialRaw,
                initialDesired: initialDesired,
                rawLineSuggestions: versionRawLines,
                filterFieldKey: null,
                patch: patch,
              );
            };
      } else if (element.key == 'apkFilterRegEx') {
        element.assistAction =
            (
              BuildContext context,
              FormValuesTextPatch patch,
              Map<String, dynamic> currentValues,
            ) {
              return showRegexAssistDialog(
                context: context,
                kind: RegexAssistKind.apkFilter,
                initialRaw: apkRawLines.isNotEmpty ? apkRawLines.first : null,
                rawLineSuggestions: apkRawLines,
                filterFieldKey: 'apkFilterRegEx',
                patch: patch,
              );
            };
      } else if (element.key == 'filterReleaseTitlesByRegEx') {
        element.assistAction =
            (
              BuildContext context,
              FormValuesTextPatch patch,
              Map<String, dynamic> currentValues,
            ) {
              return showRegexAssistDialog(
                context: context,
                kind: RegexAssistKind.releaseTitleFilter,
                initialRaw: titleRawLines.isNotEmpty
                    ? titleRawLines.first
                    : null,
                rawLineSuggestions: titleRawLines,
                filterFieldKey: 'filterReleaseTitlesByRegEx',
                patch: patch,
              );
            };
      } else if (element.key == 'filterVersionsByRegEx') {
        element.assistAction =
            (
              BuildContext context,
              FormValuesTextPatch patch,
              Map<String, dynamic> currentValues,
            ) {
              return showRegexAssistDialog(
                context: context,
                kind: RegexAssistKind.versionFilter,
                initialRaw: titleRawLines.isNotEmpty
                    ? titleRawLines.first
                    : rawLatestVersionFromSource,
                rawLineSuggestions: titleRawLines,
                filterFieldKey: 'filterVersionsByRegEx',
                patch: patch,
              );
            };
      }
    }
  }
  return items;
}

/// Prefer [attachRegexAssistToItems]; kept for older call sites.
List<List<GeneratedFormItem>> attachLatestVersionRegexAssistToItems(
  List<List<GeneratedFormItem>> items, {
  required String? rawLatestVersionFromSource,
}) {
  return attachRegexAssistToItems(
    items,
    rawLatestVersionFromSource: rawLatestVersionFromSource,
    rawApkNamesFromSource: null,
    rawReleaseTitlesFromSource: null,
    resolveRawLatestVersionFromValues: null,
  );
}

Future<void> showLatestVersionRegexAssistDialog({
  required BuildContext context,
  required String? rawLatestVersionFromSource,
  required FormValuesTextPatch patch,
}) async {
  await showRegexAssistDialog(
    context: context,
    kind: RegexAssistKind.versionExtraction,
    initialRaw: rawLatestVersionFromSource,
    rawLineSuggestions: const <String>[],
    filterFieldKey: null,
    patch: patch,
  );
}

Future<void> showRegexAssistDialog({
  required BuildContext context,
  required RegexAssistKind kind,
  required String? initialRaw,
  String? initialDesired,
  required List<String> rawLineSuggestions,
  required String? filterFieldKey,
  required FormValuesTextPatch patch,
}) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return _RegexAssistDialogBody(
        kind: kind,
        initialRaw: initialRaw,
        initialDesired: initialDesired,
        rawLineSuggestions: rawLineSuggestions,
        filterFieldKey: filterFieldKey,
        patch: patch,
      );
    },
  );
}

class _RegexAssistDialogBody extends StatefulWidget {
  const _RegexAssistDialogBody({
    required this.kind,
    required this.initialRaw,
    required this.initialDesired,
    required this.rawLineSuggestions,
    required this.filterFieldKey,
    required this.patch,
  });

  final RegexAssistKind kind;
  final String? initialRaw;
  final String? initialDesired;
  final List<String> rawLineSuggestions;
  final String? filterFieldKey;
  final FormValuesTextPatch patch;

  @override
  State<_RegexAssistDialogBody> createState() => _RegexAssistDialogBodyState();
}

class _RegexAssistDialogBodyState extends State<_RegexAssistDialogBody> {
  late final TextEditingController _rawController;
  late List<String> _candidates;
  String? _selectedCandidate;
  late final TextEditingController _customController;
  late final FocusNode _customFocusNode;
  String? _selectedRawLineSuggestion;

  @override
  void initState() {
    super.initState();
    _rawController = TextEditingController(text: widget.initialRaw ?? '');
    _customController = TextEditingController();
    _customFocusNode = FocusNode();
    _customFocusNode.addListener(_onCustomFocusChange);
    if (widget.rawLineSuggestions.isNotEmpty) {
      _selectedRawLineSuggestion = widget.rawLineSuggestions.first;
      if (_rawController.text.trim().isEmpty) {
        _rawController.text = _selectedRawLineSuggestion!;
      }
    }
    _rebuildCandidates();
    final String desired = widget.initialDesired?.trim() ?? '';
    if (desired.isNotEmpty && _rawController.text.contains(desired)) {
      final bool matchesSuggestion = _candidates.contains(desired);
      if (matchesSuggestion) {
        _selectedCandidate = desired;
      } else {
        _selectedCandidate = null;
        _customController.text = desired;
      }
    }
  }

  void _onCustomFocusChange() {
    if (!_customFocusNode.hasFocus) {
      return;
    }
    if (_customController.text.isEmpty &&
        _rawController.text.trim().isNotEmpty) {
      setState(() {
        _customController.text = _rawController.text;
        _selectedCandidate = null;
      });
    }
  }

  void _rebuildCandidates() {
    _candidates = candidateVersionStringsFromRaw(_rawController.text);
    _selectedCandidate = _candidates.isNotEmpty ? _candidates.first : null;
    _customController.clear();
  }

  void _selectCustomSubstring() {
    if (_customController.text.isEmpty &&
        _rawController.text.trim().isNotEmpty) {
      _customController.text = _rawController.text.trim();
    }
    _selectedCandidate = null;
    _customFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _customFocusNode.removeListener(_onCustomFocusChange);
    _customFocusNode.dispose();
    _rawController.dispose();
    _customController.dispose();
    super.dispose();
  }

  String _dialogTitle() {
    switch (widget.kind) {
      case RegexAssistKind.versionExtraction:
        return tr('versionRegexAssistTitle');
      case RegexAssistKind.apkFilter:
        return tr('filterRegexAssistTitleApk');
      case RegexAssistKind.releaseTitleFilter:
        return tr('filterRegexAssistTitleRelease');
      case RegexAssistKind.versionFilter:
        return tr('filterRegexAssistTitleVersion');
    }
  }

  String _rawHint() {
    switch (widget.kind) {
      case RegexAssistKind.versionExtraction:
        return tr('versionRegexAssistRawHint');
      case RegexAssistKind.apkFilter:
        return tr('filterRegexAssistRawHintApk');
      case RegexAssistKind.releaseTitleFilter:
        return tr('filterRegexAssistRawHintRelease');
      case RegexAssistKind.versionFilter:
        return tr('filterRegexAssistRawHintVersion');
    }
  }

  String _pickSubstringLabel() {
    switch (widget.kind) {
      case RegexAssistKind.versionExtraction:
        return tr('versionRegexAssistPickLabel');
      case RegexAssistKind.apkFilter:
        return tr('filterRegexAssistPickLabelApk');
      case RegexAssistKind.releaseTitleFilter:
        return tr('filterRegexAssistPickLabelRelease');
      case RegexAssistKind.versionFilter:
        return tr('filterRegexAssistPickLabelVersion');
    }
  }

  void _applySelection() {
    final String raw = _rawController.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('versionRegexAssistNeedRaw'))));
      return;
    }
    final String desired = _customController.text.trim().isNotEmpty
        ? _customController.text.trim()
        : (_selectedCandidate ?? '').trim();
    if (desired.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('versionRegexAssistPickOrType'))),
      );
      return;
    }
    if (widget.kind == RegexAssistKind.versionExtraction) {
      final Map<String, String>? built = tryBuildRegexForExtractedVersion(
        raw: raw,
        desired: desired,
      );
      if (built == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('versionRegexAssistCouldNotBuild'))),
        );
        return;
      }
      widget.patch(built);
    } else {
      final String? pattern = tryBuildFilterRegExFromSelection(
        raw: raw,
        desired: desired,
      );
      if (pattern == null || widget.filterFieldKey == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('versionRegexAssistCouldNotBuild'))),
        );
        return;
      }
      widget.patch(<String, String>{widget.filterFieldKey!: pattern});
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: Text(_dialogTitle()),
      contentPadding: appDialogContentPadding,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _rawHint(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.rawLineSuggestions.length > 1) ...<Widget>[
              Text(
                tr('filterRegexAssistPickRawLineLabel'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _selectedRawLineSuggestion,
                onChanged: (String? newLine) {
                  if (newLine == null) return;
                  setState(() {
                    _selectedRawLineSuggestion = newLine;
                    _rawController.text = newLine;
                    _rebuildCandidates();
                  });
                },
                child: Column(
                  children: widget.rawLineSuggestions
                      .map(
                        (String line) => RadioListTile<String>(
                          value: line,
                          title: Text(line, style: theme.textTheme.bodyMedium),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _rawController,
              minLines: 1,
              maxLines: 4,
              decoration: appPageOutlinedInputDecoration(
                context,
                labelText: null,
                hintText: tr('versionRegexAssistRawPlaceholder'),
              ),
              onChanged: (_) => setState(_rebuildCandidates),
            ),
            if (_candidates.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                _pickSubstringLabel(),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _customController.text.trim().isNotEmpty
                    ? null
                    : _selectedCandidate,
                onChanged: (String? newCandidate) {
                  if (newCandidate == null) return;
                  setState(() {
                    _selectedCandidate = newCandidate;
                    _customController.clear();
                  });
                },
                child: Column(
                  children: _candidates
                      .map(
                        (String candidate) => RadioListTile<String>(
                          value: candidate,
                          title: Text(
                            candidate,
                            style: theme.textTheme.bodyMedium,
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            RadioGroup<String>(
              groupValue: _customController.text.trim().isNotEmpty
                  ? 'custom'
                  : null,
              onChanged: (String? value) {
                if (value == null) return;
                setState(_selectCustomSubstring);
              },
              child: RadioListTile<String>(
                value: 'custom',
                title: Text(
                  tr('versionRegexAssistCustomLabel'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _customController,
              focusNode: _customFocusNode,
              decoration: appPageOutlinedInputDecoration(
                context,
                labelText: null,
                hintText: tr('versionRegexAssistCustomHint'),
              ),
              onChanged: (_) {
                setState(() {
                  _selectedCandidate = null;
                });
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('cancel')),
        ),
        FilledButton(
          onPressed: _applySelection,
          child: Text(tr('versionRegexAssistApply')),
        ),
      ],
    );
  }
}
