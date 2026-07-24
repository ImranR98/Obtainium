import 'dart:async';
import 'dart:math';

import 'package:hsluv/hsluv.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/app_bottom_sheet.dart';
import 'package:obtainium/components/app_page_section_title.dart';
import 'package:obtainium/components/app_dropdown_field.dart';
import 'package:obtainium/components/category_action_chip.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/components/theme_accent_settings_section.dart';
import 'package:obtainium/theme/app_dialog_theme.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/theme/app_form_field_styles.dart';
import 'package:obtainium/theme/app_page_icon_colors.dart';
import 'package:obtainium/widgets/help_hint_icon.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

export 'generated_form_model.dart';

// Generates a color in the HSLuv (Pastel) color space
// https://pub.dev/documentation/hsluv/latest/hsluv/Hsluv/hpluvToRgb.html
Color generateRandomLightColor() {
  final randomSeed = Random().nextInt(120);
  // https://en.wikipedia.org/wiki/Golden_angle
  final goldenAngle = 180 * (3 - sqrt(5));
  // Generate next golden angle hue
  final double hue = randomSeed * goldenAngle;
  // Map from HPLuv color space to RGB, use constant saturation=100, lightness=55
  final List<double> rgbValuesDbl = Hsluv.hpluvToRgb([hue, 100, 55]);
  // Map RBG values from 0-1 to 0-255:
  final List<int> rgbValues = rgbValuesDbl
      .map((rgb) => (rgb * 255).clamp(0, 255).toInt())
      .toList();
  return Color.fromARGB(255, rgbValues[0], rgbValues[1], rgbValues[2]);
}

typedef OnValueChanges =
    void Function(Map<String, dynamic> values, bool valid, bool isBuilding);

/// Copy tag map so form state is not the same instance as [GeneratedFormTagInput.value].
Map<String, MapEntry<int, bool>> cloneCategoryTagInputValueMap(
  Map<String, MapEntry<int, bool>>? source,
) {
  if (source == null || source.isEmpty) {
    return <String, MapEntry<int, bool>>{};
  }
  return Map<String, MapEntry<int, bool>>.fromEntries(
    source.entries.map(
      (MapEntry<String, MapEntry<int, bool>> entry) =>
          MapEntry(entry.key, MapEntry(entry.value.key, entry.value.value)),
    ),
  );
}

/// Row indices of [items] grouped by [GeneratedFormSectionHeader] starts.
List<List<int>> generatedFormSectionRowIndices(
  List<List<GeneratedFormItem>> items,
) {
  final List<List<int>> sections = <List<int>>[];
  List<int> current = <int>[];
  for (int rowIndex = 0; rowIndex < items.length; rowIndex++) {
    final List<GeneratedFormItem> row = items[rowIndex];
    final bool headerRow =
        row.length == 1 && row.first is GeneratedFormSectionHeader;
    if (headerRow) {
      if (current.isNotEmpty) {
        sections.add(current);
      }
      current = <int>[rowIndex];
    } else {
      if (current.isEmpty) {
        current = <int>[rowIndex];
      } else {
        current.add(rowIndex);
      }
    }
  }
  if (current.isNotEmpty) {
    sections.add(current);
  }
  return sections;
}

class GeneratedForm extends StatefulWidget {
  const GeneratedForm({
    super.key,
    required this.items,
    required this.onValueChanges,
    this.outlinedInputFields = false,
    this.prominentSectionHeaders = false,
    this.outlinedFieldsExternalLabels = false,
    this.wrapFormSectionsInCards = false,
    this.outlinedFieldBorderRadius,
    this.tileMode = false,
  });

  final List<List<GeneratedFormItem>> items;
  final OnValueChanges onValueChanges;

  /// Rounded filled outline around text fields and dropdowns (e.g. full-screen editors).
  final bool outlinedInputFields;

  /// Corner radius for outlined fields; defaults to 12 when null.
  final double? outlinedFieldBorderRadius;

  /// Stronger section titles and a bar marker instead of a thin full-width divider.
  final bool prominentSectionHeaders;

  /// When [outlinedInputFields] is true, keep labels above the field instead of inside it.
  final bool outlinedFieldsExternalLabels;

  /// Group each [GeneratedFormSectionHeader] block in an app-page style card.
  final bool wrapFormSectionsInCards;

  /// Upstream compatibility flag (settings-tile styled forms). The fork renders
  /// its own styled fields, so this is accepted for API parity but does not
  /// change the visual layout here — the fork's outlined/section styling is the
  /// intended look (see cross-repo direction: "your visible layout stays yours").
  final bool tileMode;

  @override
  State<GeneratedForm> createState() => _GeneratedFormState();
}

InputDecoration _generatedFormTextFieldDecoration({
  required BuildContext context,
  required GeneratedFormTextField formItem,
  required bool outlined,
  required bool externalLabels,
  double borderRadius = 12,
}) {
  if (!outlined) {
    return InputDecoration(
      helperText: formItem.label + (formItem.required ? ' *' : ''),
      hintText: formItem.hint,
    );
  }
  if (externalLabels) {
    return appPageOutlinedInputDecoration(
      context,
      labelText: null,
      hintText: formItem.hint,
      borderRadius: borderRadius,
    );
  }
  return appPageOutlinedInputDecoration(
    context,
    labelText: formItem.label + (formItem.required ? ' *' : ''),
    hintText: formItem.hint,
    borderRadius: borderRadius,
  );
}

InputDecoration _generatedFormDropdownDecoration({
  required BuildContext context,
  required String labelText,
  required bool outlined,
  required bool externalLabels,
  double borderRadius = 12,
}) {
  if (!outlined) {
    return appPageDropdownInputDecoration(
      context,
      labelText: labelText,
      borderRadius: borderRadius,
    );
  }
  if (externalLabels) {
    return appPageDropdownInputDecoration(
      context,
      labelText: null,
      borderRadius: borderRadius,
    );
  }
  return appPageDropdownInputDecoration(
    context,
    labelText: labelText,
    borderRadius: borderRadius,
  );
}

/// Opens [helpUrl] in an external browser (used by source-config fields).
IconButton _helpUrlButton(String helpUrl) {
  return IconButton(
    icon: const Icon(Icons.open_in_new),
    tooltip: tr('about'),
    onPressed: () => unawaited(
      launchUrlString(helpUrl, mode: LaunchMode.externalApplication),
    ),
  );
}

/// Unified bottom-sheet for creating or editing a category.
/// Label field with live chip preview at top, shared color slider below,
/// and a single sheet-level "Save" button.
/// Returns ({Color color, String name}) or null if dismissed.
class _CategoryColorPickerSheet extends StatefulWidget {
  const _CategoryColorPickerSheet({
    required this.initialColor,
    required this.initialName,
  });
  final Color initialColor;
  final String initialName;

  @override
  State<_CategoryColorPickerSheet> createState() =>
      _CategoryColorPickerSheetState();
}

class _CategoryColorPickerSheetState extends State<_CategoryColorPickerSheet> {
  late Color _staged;
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _staged = widget.initialColor;
    _nameCtrl = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _stageHex(String hex) {
    final String clean = hex.replaceFirst('#', '');
    final int? value = int.tryParse(clean, radix: 16);
    if (value == null) return;
    setState(() {
      _staged = Color(0xFF000000 | value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameCtrl.text.trim();
    return AppSheetContent(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        CategoryEditorFields(
          nameController: _nameCtrl,
          color: _staged,
          autofocusName: widget.initialName.isEmpty,
          onNameChanged: (_) => setState(() {}),
          onColorHexChanged: _stageHex,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('cancel')),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: name.isEmpty
                  ? null
                  : () => Navigator.pop(context, (color: _staged, name: name)),
              child: Text(tr('save')),
            ),
          ],
        ),
      ],
    );
  }
}

/// Opens [_CategoryColorPickerSheet] for creating or editing a category.
/// Returns ({Color color, String name}) or null if dismissed.
Future<({Color color, String name})?> showCategorySheet(
  BuildContext context, {
  required Color initialColor,
  required String initialName,
}) {
  return showAppModalSheet<({Color color, String name})>(
    context: context,
    builder: (_) => _CategoryColorPickerSheet(
      initialColor: initialColor,
      initialName: initialName,
    ),
  );
}

String categoryColorToHex(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class CategoryEditorFields extends StatelessWidget {
  const CategoryEditorFields({
    super.key,
    required this.nameController,
    required this.color,
    required this.onNameChanged,
    required this.onColorHexChanged,
    this.autofocusName = false,
  });

  final TextEditingController nameController;
  final Color color;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onColorHexChanged;
  final bool autofocusName;
  static const int nameMaxLength = 20;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String hex = categoryColorToHex(color);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: nameController,
                autofocus: autofocusName,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(nameMaxLength),
                ],
                decoration:
                    appPageOutlinedInputDecoration(
                      context,
                      labelText: null,
                      hintText: tr('label'),
                      isDense: true,
                    ).copyWith(
                      suffixText:
                          '${nameController.text.length}/$nameMaxLength',
                    ),
                onChanged: onNameChanged,
              ),
            ),
            const SizedBox(width: 12),
            _CategoryHexChip(
              hex: hex,
              color: color,
              onHexChanged: onColorHexChanged,
            ),
          ],
        ),
        const SizedBox(height: 16),
        CustomHueColorSlider(
          seedHex: hex,
          onPreviewColor: onColorHexChanged,
          onSaveColor: onColorHexChanged,
          gapColor: scheme.surfaceContainerLow,
        ),
      ],
    );
  }
}

class _CategoryHexChip extends StatelessWidget {
  const _CategoryHexChip({
    required this.hex,
    required this.color,
    required this.onHexChanged,
  });

  final String hex;
  final Color color;
  final ValueChanged<String> onHexChanged;

  @override
  Widget build(BuildContext context) {
    return _EditableCategoryHexChip(
      hex: hex,
      color: color,
      onHexChanged: onHexChanged,
    );
  }
}

class _EditableCategoryHexChip extends StatefulWidget {
  const _EditableCategoryHexChip({
    required this.hex,
    required this.color,
    required this.onHexChanged,
  });

  final String hex;
  final Color color;
  final ValueChanged<String> onHexChanged;

  @override
  State<_EditableCategoryHexChip> createState() =>
      _EditableCategoryHexChipState();
}

class _EditableCategoryHexChipState extends State<_EditableCategoryHexChip> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final Object _tapRegionGroup = Object();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.hex);
  }

  @override
  void didUpdateWidget(covariant _EditableCategoryHexChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.hex != widget.hex) {
      _controller.text = widget.hex;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _editing = true;
      _controller.text = widget.hex;
      _controller.selection = TextSelection(
        baseOffset: 1,
        extentOffset: _controller.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _commitEditing() {
    final normalized = _normalizeCategoryHexInput(_controller.text);
    if (normalized != null) {
      widget.onHexChanged(normalized);
      _controller.text = normalized;
    } else {
      _controller.text = widget.hex;
    }
    setState(() {
      _editing = false;
    });
  }

  void _handleHexChanged(String value) {
    final normalized = _normalizeCategoryHexInput(value);
    if (normalized != null) {
      widget.onHexChanged(normalized);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool colorIsLight = widget.color.computeLuminance() > 0.35;
    final Color foreground = colorIsLight ? Colors.black87 : Colors.white;
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: foreground,
      fontFamily: 'monospace',
      fontWeight: FontWeight.w800,
    );
    return TapRegion(
      groupId: _tapRegionGroup,
      onTapOutside: (_) {
        if (_editing) _commitEditing();
      },
      child: SizedBox(
        width: 118,
        height: 48,
        child: Material(
          color: widget.color,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _editing ? null : _startEditing,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.center,
                child: _editing
                    ? SizedBox(
                        height: (textStyle?.fontSize ?? 14) * 1.25,
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          inputFormatters: [_CategoryHexInputFormatter()],
                          maxLines: 1,
                          autofocus: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          textCapitalization: TextCapitalization.characters,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.done,
                          textAlign: TextAlign.center,
                          textAlignVertical: TextAlignVertical.center,
                          cursorColor: foreground,
                          style: textStyle?.copyWith(height: 1.0),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            counterText: '',
                            isCollapsed: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: _handleHexChanged,
                          onEditingComplete: _commitEditing,
                        ),
                      )
                    : Text(widget.hex, maxLines: 1, style: textStyle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _normalizeCategoryHexInput(String raw) {
  final clean = raw.startsWith('#') ? raw.substring(1) : raw;
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(clean)) return null;
  return '#${clean.toUpperCase()}';
}

class _CategoryHexInputFormatter extends TextInputFormatter {
  static final RegExp _validHex = RegExp(r'^[0-9a-fA-F]*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String nextText = newValue.text.toUpperCase();
    if (nextText.isNotEmpty && !nextText.startsWith('#')) {
      nextText = '#$nextText';
    }
    final cleanText = nextText.startsWith('#')
        ? nextText.substring(1)
        : nextText;
    if (cleanText.length > 6 || !_validHex.hasMatch(cleanText)) {
      hapticVibrate();
      SystemSound.play(SystemSoundType.alert);
      return oldValue;
    }

    int clampOffset(int offset) {
      final prefixOffset =
          newValue.text.isNotEmpty && !newValue.text.startsWith('#') ? 1 : 0;
      return (offset + prefixOffset).clamp(0, nextText.length).toInt();
    }

    return TextEditingValue(
      text: nextText,
      selection: TextSelection(
        baseOffset: clampOffset(newValue.selection.baseOffset),
        extentOffset: clampOffset(newValue.selection.extentOffset),
        affinity: newValue.selection.affinity,
        isDirectional: newValue.selection.isDirectional,
      ),
      composing: TextRange.empty,
    );
  }
}

bool validateTextField(TextFormField tf) =>
    (tf.key as GlobalKey<FormFieldState>).currentState?.isValid == true;

/// Reads [Theme] on each rebuild so colors follow async icon-derived themes.
///
/// [GeneratedForm.initForm] runs once from [State.initState]; widgets created
/// there would otherwise keep the first frame's colors (e.g. MaterialApp)
/// after [AdditionalOptionsPage] applies icon [Theme].
class _ThemePinnedDropdownFormField extends StatelessWidget {
  const _ThemePinnedDropdownFormField({
    required this.formItem,
    required this.outlinedInputFields,
    required this.outlinedFieldsExternalLabels,
    required this.outlinedFieldBorderRadius,
    required this.value,
    required this.onChanged,
  });

  final GeneratedFormDropdown formItem;
  final bool outlinedInputFields;
  final bool outlinedFieldsExternalLabels;
  final double outlinedFieldBorderRadius;
  final dynamic value;
  final void Function(dynamic newValue) onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool showExternalFieldLabels =
        outlinedInputFields && outlinedFieldsExternalLabels;
    final Widget? helpIcon =
        formItem.labelTooltip != null && formItem.labelTooltip!.isNotEmpty
        ? HelpHintIcon(
            message: formItem.labelTooltip!,
            size: 18,
            padding: EdgeInsets.zero,
          )
        : (formItem.helpUrl != null ? _helpUrlButton(formItem.helpUrl!) : null);
    final TextStyle? dropdownTextStyle = theme.textTheme.bodyLarge?.copyWith(
      color: scheme.onSurface,
    );
    final Widget field = appDropdownField<dynamic>(
      context: context,
      value: value,
      labelText: formItem.label,
      menuWidth: appDropdownMenuWidth(
        context,
        (formItem.opts ?? const []).map(
          (MapEntry<String, String> option) => option.value,
        ),
        style: dropdownTextStyle,
      ),
      borderRadius: outlinedFieldBorderRadius,
      decoration: _generatedFormDropdownDecoration(
        context: context,
        labelText: formItem.label,
        outlined: outlinedInputFields,
        externalLabels: showExternalFieldLabels,
        borderRadius: outlinedFieldBorderRadius,
      ),
      items: formItem.opts!.map((MapEntry<String, String> option) {
        final bool enabled =
            formItem.disabledOptKeys?.contains(option.key) != true;
        return DropdownMenuItem<dynamic>(
          value: option.key,
          enabled: enabled,
          child: Opacity(opacity: enabled ? 1 : 0.5, child: Text(option.value)),
        );
      }).toList(),
      onChanged: onChanged,
    );
    if (showExternalFieldLabels) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    formItem.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (helpIcon != null) ...[const SizedBox(width: 6), helpIcon],
              ],
            ),
          ),
          field,
        ],
      );
    }
    if (helpIcon != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          field,
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: helpIcon,
            ),
          ),
        ],
      );
    }
    return field;
  }
}

class _TVTextFieldFocus extends StatefulWidget {
  final Widget child;
  final FocusNode textFocusNode;

  const _TVTextFieldFocus({required this.child, required this.textFocusNode});

  @override
  State<_TVTextFieldFocus> createState() => _TVTextFieldFocusState();
}

class _TVTextFieldFocusState extends State<_TVTextFieldFocus> {
  final FocusNode _outerFocus = FocusNode();
  bool _activated = false;

  @override
  void initState() {
    super.initState();
    widget.textFocusNode.addListener(_onTextFocusChange);
  }

  void _onTextFocusChange() {
    if (!widget.textFocusNode.hasFocus && _activated) {
      setState(() => _activated = false);
      _outerFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    widget.textFocusNode.removeListener(_onTextFocusChange);
    _outerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _outerFocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          setState(() => _activated = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.textFocusNode.requestFocus();
          });
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: _outerFocus,
        builder: (context, child) => Container(
          decoration: _outerFocus.hasFocus && !_activated
              ? BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                )
              : null,
          child: ExcludeFocus(excluding: !_activated, child: widget.child),
        ),
      ),
    );
  }
}

class _GeneratedFormState extends State<GeneratedForm> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic> values = {};
  late List<List<Widget>> formInputs;
  List<List<Widget>> rows = [];
  int forceUpdateKeyCount = 0;
  final Map<String, TextEditingController> _textFieldControllers = {};
  final Map<String, Map<String, MapEntry<int, bool>>> _initialTagValues = {};

  void _disposeTextFieldControllers() {
    for (final TextEditingController controller
        in _textFieldControllers.values) {
      controller.dispose();
    }
    _textFieldControllers.clear();
  }

  void applyTextFieldPatches(Map<String, String> patches) {
    setState(() {
      patches.forEach((String key, String value) {
        values[key] = value;
        final TextEditingController? controller = _textFieldControllers[key];
        if (controller != null) {
          controller.text = value;
        }
      });
    });
    someValueChanged();
  }

  // If any value changes, call this to update the parent with value and validity
  void someValueChanged({bool isBuilding = false, bool forceInvalid = false}) {
    final Map<String, dynamic> returnValues = values;
    var valid = true;
    if (!isBuilding) {
      valid = _formKey.currentState?.validate() ?? true;
      for (int r = 0; r < formInputs.length; r++) {
        for (int i = 0; i < formInputs[r].length; i++) {
          if (formInputs[r][i] is TextFormField) {
            valid =
                valid && validateTextField(formInputs[r][i] as TextFormField);
          }
        }
      }
    }
    if (forceInvalid) {
      valid = false;
    }
    widget.onValueChanges(returnValues, valid, isBuilding);
  }

  void initForm() {
    _disposeTextFieldControllers();
    _initialTagValues.clear();
    // Initialize form values as all empty
    values.clear();
    for (var row in widget.items) {
      for (var e in row) {
        if (e is GeneratedFormSectionHeader) continue;
        if (e is GeneratedFormTagInput) {
          final initialValue = cloneCategoryTagInputValueMap(
            e.value as Map<String, MapEntry<int, bool>>?,
          );
          values[e.key] = initialValue;
          _initialTagValues[e.key] = cloneCategoryTagInputValueMap(
            initialValue,
          );
        } else {
          values[e.key] = e.value;
        }
      }
    }

    // Dynamically create form inputs
    formInputs = widget.items.asMap().entries.map((row) {
      return row.value.asMap().entries.map((e) {
        final formItem = e.value;
        if (formItem is GeneratedFormSectionHeader) {
          return const SizedBox.shrink();
        } else if (formItem is GeneratedFormTextField) {
          final formFieldKey = GlobalKey<FormFieldState>();
          final String initialText = values[formItem.key]?.toString() ?? '';
          final TextEditingController ctrl = _textFieldControllers.putIfAbsent(
            formItem.key,
            () => TextEditingController(text: initialText),
          );
          if (ctrl.text != initialText) {
            ctrl.text = initialText;
          }
          final bool showExternalFieldLabels =
              widget.outlinedInputFields && widget.outlinedFieldsExternalLabels;
          final double outlinedRadius = widget.outlinedFieldBorderRadius ?? 12;
          final _GeneratedFormState formState = this;
          final Widget typeAhead = TypeAheadField<String>(
            controller: ctrl,
            builder: (context, controller, focusNode) {
              final InputDecoration baseDecoration =
                  _generatedFormTextFieldDecoration(
                    context: context,
                    formItem: formItem,
                    outlined: widget.outlinedInputFields,
                    externalLabels: showExternalFieldLabels,
                    borderRadius: outlinedRadius,
                  );
              final Widget textField = TextFormField(
                controller: ctrl,
                focusNode: focusNode,
                keyboardType: formItem.textInputType,
                obscureText: formItem.password,
                autocorrect: !formItem.password,
                enableSuggestions: !formItem.password,
                key: formFieldKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (value) {
                  // No setState here: the field already shows the new text via
                  // its own controller, and nothing else in this form renders
                  // from a text field's value (switches/tag-inputs/subforms key
                  // off their own values). someValueChanged() still runs the
                  // form validator and notifies the parent of value+validity —
                  // including per-field error display via _formKey.validate().
                  // Previously every keystroke called setState, rebuilding the
                  // entire form-input tree (all switches, tag inputs, subforms,
                  // dropdowns) on each character.
                  values[formItem.key] = value;
                  someValueChanged();
                },
                decoration: baseDecoration.copyWith(
                  suffixIcon:
                      formItem.suffixIcon ??
                      (formItem.assistAction != null
                          ? IconButton(
                              tooltip:
                                  formItem.assistTooltip ??
                                  tr('regexAssistTooltip'),
                              icon: Icon(formItem.assistIcon),
                              onPressed: () async {
                                await formItem.assistAction!(
                                  context,
                                  formState.applyTextFieldPatches,
                                  formState.values,
                                );
                              },
                            )
                          : (formItem.helpUrl != null
                                ? _helpUrlButton(formItem.helpUrl!)
                                : null)),
                ),
                minLines: formItem.max <= 1 ? null : formItem.max,
                maxLines: formItem.max <= 1 ? 1 : formItem.max,
                validator: (value) {
                  if (formItem.required &&
                      (value == null || value.trim().isEmpty)) {
                    return '${formItem.label} ${tr('requiredInBrackets')}';
                  }
                  for (var validator in formItem.additionalValidators) {
                    final String? result = validator(value);
                    if (result != null) {
                      return result;
                    }
                  }
                  return null;
                },
              );
              if (context.read<SettingsProvider>().isTV) {
                return _TVTextFieldFocus(
                  textFocusNode: focusNode,
                  child: textField,
                );
              }
              return textField;
            },
            itemBuilder: (context, value) {
              return ListTile(title: Text(value));
            },
            onSelected: (value) {
              ctrl.text = value;
              setState(() {
                values[formItem.key] = value;
                someValueChanged();
              });
            },
            suggestionsCallback: (search) {
              return formItem.autoCompleteOptions
                  ?.where((t) => t.toLowerCase().contains(search.toLowerCase()))
                  .toList();
            },
            hideOnEmpty: true,
          );
          if (showExternalFieldLabels) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 6),
                  child: Text(
                    formItem.label + (formItem.required ? ' *' : ''),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                typeAhead,
              ],
            );
          }
          return typeAhead;
        } else if (formItem is GeneratedFormDropdown) {
          if (formItem.opts!.isEmpty) {
            return Text(tr('dropdownNoOptsError'));
          }
          return _ThemePinnedDropdownFormField(
            formItem: formItem,
            outlinedInputFields: widget.outlinedInputFields,
            outlinedFieldsExternalLabels: widget.outlinedFieldsExternalLabels,
            outlinedFieldBorderRadius: widget.outlinedFieldBorderRadius ?? 12,
            value: values[formItem.key],
            onChanged: (dynamic newValue) {
              setState(() {
                values[formItem.key] = newValue ?? formItem.opts!.first.key;
                someValueChanged();
              });
            },
          );
        } else if (formItem is GeneratedFormSubForm) {
          values[formItem.key] = [];
          for (Map<String, dynamic> v
              in ((formItem.value ?? []) as List<dynamic>)) {
            final fullDefaults = getDefaultValuesFromFormItems(formItem.items);
            for (var element in v.entries) {
              fullDefaults[element.key] = element.value;
            }
            values[formItem.key].add(fullDefaults);
          }
          return Container();
        } else {
          return Container(); // Some input types added in build
        }
      }).toList();
    }).toList();
    someValueChanged(isBuilding: true);
  }

  @override
  void initState() {
    super.initState();
    initForm();
  }

  @override
  void didUpdateWidget(covariant GeneratedForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.key != widget.key) {
      initForm();
    }
  }

  @override
  void dispose() {
    _disposeTextFieldControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (var r = 0; r < formInputs.length; r++) {
      for (var e = 0; e < formInputs[r].length; e++) {
        final String fieldKey = widget.items[r][e].key;
        if (widget.items[r][e] is GeneratedFormSectionHeader) {
          final GeneratedFormSectionHeader header =
              widget.items[r][e] as GeneratedFormSectionHeader;
          final bool showDivider = r > 0;
          final ThemeData theme = Theme.of(context);
          final ColorScheme scheme = theme.colorScheme;
          final bool prominent = widget.prominentSectionHeaders;
          final bool inSectionCard =
              prominent && widget.wrapFormSectionsInCards;
          formInputs[r][e] = Padding(
            padding: EdgeInsets.only(
              top: showDivider
                  ? (prominent ? (inSectionCard ? 2 : 20) : 16)
                  : (prominent ? (inSectionCard ? 0 : 8) : 4),
              bottom: prominent ? (inSectionCard ? 6 : 10) : 6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showDivider && !prominent) ...[
                  Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                  const SizedBox(height: 12),
                ],
                if (showDivider && prominent && !inSectionCard)
                  const SizedBox(height: 4),
                if (prominent)
                  appPageCardSectionHeaderLabel(context, header.label)
                else
                  Text(
                    header.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
              ],
            ),
          );
          continue;
        }
        if (widget.items[r][e] is GeneratedFormSwitch) {
          final GeneratedFormSwitch switchItem =
              widget.items[r][e] as GeneratedFormSwitch;
          final Widget? switchHelpIcon =
              switchItem.labelTooltip != null &&
                  switchItem.labelTooltip!.isNotEmpty
              ? HelpHintIcon(
                  message: switchItem.labelTooltip!,
                  padding: EdgeInsets.zero,
                )
              : null;
          formInputs[r][e] = FormField<bool>(
            initialValue: values[fieldKey],
            validator: (value) {
              for (var validator in switchItem.additionalValidators) {
                final String? result = validator(value == true);
                if (result != null) {
                  return result;
                }
              }
              return null;
            },
            builder: (field) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          switchItem.label,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      if (switchHelpIcon != null)
                        switchHelpIcon
                      else
                        const SizedBox(width: 8),
                      Switch(
                        value: values[fieldKey],
                        onChanged: switchItem.disabled
                            ? null
                            : (value) {
                                setState(() {
                                  values[fieldKey] = value;
                                  field.didChange(value);
                                  if (value) {
                                    for (final String targetKey
                                        in switchItem.turnsOffKeys) {
                                      values[targetKey] = false;
                                    }
                                  }
                                  someValueChanged();
                                });
                              },
                      ),
                    ],
                  ),
                  if (field.hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        field.errorText!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        } else if (widget.items[r][e] is GeneratedFormTagInput) {
          // Capture the form item here so that closures defined below don't
          // close over the for-loop variables r and e, which have stale
          // (final-iteration) values by the time the closures are invoked.
          final tagInput = widget.items[r][e] as GeneratedFormTagInput;
          Future<void> onAddPressed() async {
            final NavigatorState navigator = Navigator.of(context);
            final result = await showCategorySheet(
              navigator.context,
              initialColor: generateRandomLightColor(),
              initialName: '',
            );
            if (!mounted || result == null) return;
            var temp = values[fieldKey] as Map<String, MapEntry<int, bool>>?;
            temp ??= {};
            if (temp.containsKey(result.name)) return;
            final singleSelect = tagInput.singleSelect;
            final someSelected = temp.values.any((v) => v.value);
            setState(() {
              temp![result.name] = MapEntry(
                result.color.toARGB32(),
                !(someSelected && singleSelect),
              );
              values[fieldKey] = temp;
            });
            someValueChanged();
          }

          formInputs[r][e] = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((values[fieldKey] as Map<String, MapEntry<int, bool>>?)
                          ?.isNotEmpty ==
                      true &&
                  (widget.items[r][e] as GeneratedFormTagInput)
                      .showLabelWhenNotEmpty)
                Column(
                  crossAxisAlignment:
                      (widget.items[r][e] as GeneratedFormTagInput).alignment ==
                          WrapAlignment.center
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.items[r][e].label),
                    const SizedBox(height: 8),
                  ],
                ),
              CategoryActionChipGroup(
                alignment:
                    (widget.items[r][e] as GeneratedFormTagInput).alignment,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ...(values[fieldKey] as Map<String, MapEntry<int, bool>>?)
                          ?.entries
                          .map((e2) {
                            final bool originallySelected =
                                _initialTagValues[fieldKey]?[e2.key]?.value ??
                                false;
                            final bool currentlySelected = e2.value.value;
                            final CategoryActionChipState selectedState =
                                tagInput.showSelectedCheckmark
                                ? CategoryActionChipState.checked
                                : CategoryActionChipState.plain;
                            final CategoryActionChipState chipState =
                                tagInput.showChangeIntentIcons
                                ? (originallySelected
                                      ? (currentlySelected
                                            ? selectedState
                                            : CategoryActionChipState.remove)
                                      : (currentlySelected
                                            ? CategoryActionChipState.add
                                            : CategoryActionChipState.muted))
                                : (currentlySelected
                                      ? selectedState
                                      : CategoryActionChipState.muted);

                            void onCategoryChipSelected(bool newValue) {
                              setState(() {
                                final Map<String, MapEntry<int, bool>> map =
                                    values[fieldKey]
                                        as Map<String, MapEntry<int, bool>>;
                                map[e2.key] = MapEntry(
                                  map[e2.key]!.key,
                                  newValue,
                                );
                                if (tagInput.singleSelect && newValue) {
                                  for (final String key in map.keys) {
                                    if (key != e2.key) {
                                      map[key] = MapEntry(map[key]!.key, false);
                                    }
                                  }
                                }
                              });
                              someValueChanged();
                            }

                            return KeyedSubtree(
                              key: ValueKey<String>('category_chip_${e2.key}'),
                              child: CategoryActionChip(
                                label: e2.key,
                                color: Color(e2.value.key),
                                state: chipState,
                                onPressed: () {
                                  onCategoryChipSelected(!currentlySelected);
                                },
                              ),
                            );
                          }) ??
                      [const SizedBox.shrink()],
                  if (tagInput.allowTagManagement) ...[
                    (values[fieldKey] as Map<String, MapEntry<int, bool>>?)
                                ?.values
                                .where((e) => e.value)
                                .length ==
                            1
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: IconButton(
                              onPressed: () async {
                                final temp =
                                    values[fieldKey]
                                        as Map<String, MapEntry<int, bool>>;
                                final oldEntry = temp.entries.firstWhere(
                                  (e) => e.value.value,
                                );
                                final NavigatorState navigator = Navigator.of(
                                  context,
                                );
                                final result = await showCategorySheet(
                                  navigator.context,
                                  initialColor: Color(oldEntry.value.key),
                                  initialName: oldEntry.key,
                                );
                                if (!mounted || result == null) return;
                                setState(() {
                                  if (result.name != oldEntry.key) {
                                    temp.remove(oldEntry.key);
                                  }
                                  temp[result.name] = MapEntry(
                                    result.color.toARGB32(),
                                    oldEntry.value.value,
                                  );
                                  values[fieldKey] = temp;
                                });
                                someValueChanged();
                              },
                              icon: const Icon(Icons.edit_outlined),
                              visualDensity: VisualDensity.compact,
                              tooltip: tr('edit'),
                            ),
                          )
                        : const SizedBox.shrink(),
                    (values[fieldKey] as Map<String, MapEntry<int, bool>>?)
                                ?.values
                                .where((e) => e.value)
                                .isNotEmpty ==
                            true
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: IconButton(
                              onPressed: () {
                                void fn() {
                                  setState(() {
                                    final temp =
                                        values[fieldKey]
                                            as Map<String, MapEntry<int, bool>>;
                                    temp.removeWhere(
                                      (key, value) => value.value,
                                    );
                                    values[fieldKey] = temp;
                                  });
                                  someValueChanged();
                                }

                                if (tagInput.deleteConfirmationMessage !=
                                    null) {
                                  final message =
                                      tagInput.deleteConfirmationMessage!;
                                  showDialog<Map<String, dynamic>?>(
                                    context: context,
                                    builder: (BuildContext ctx) {
                                      return GeneratedFormModal(
                                        title: message.key,
                                        message: message.value,
                                        items: const [],
                                        primaryActionColour: Theme.of(
                                          ctx,
                                        ).colorScheme.error,
                                      );
                                    },
                                  ).then((value) {
                                    if (value != null) {
                                      fn();
                                    }
                                  });
                                } else {
                                  fn();
                                }
                              },
                              icon: const Icon(Icons.remove),
                              visualDensity: VisualDensity.compact,
                              tooltip: tr('remove'),
                            ),
                          )
                        : const SizedBox.shrink(),
                    (values[fieldKey] as Map<String, MapEntry<int, bool>>?)
                                ?.isEmpty ==
                            true
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: TextButton.icon(
                              onPressed: onAddPressed,
                              icon: const Icon(Icons.add),
                              label: Text(
                                (widget.items[r][e] as GeneratedFormTagInput)
                                    .label,
                              ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: IconButton(
                              onPressed: onAddPressed,
                              icon: const Icon(Icons.add),
                              visualDensity: VisualDensity.compact,
                              tooltip: tr('add'),
                            ),
                          ),
                  ],
                ],
              ),
            ],
          );
        } else if (widget.items[r][e] is GeneratedFormSubForm) {
          final List<Widget> subformColumn = [];
          final compact =
              (widget.items[r][e] as GeneratedFormSubForm).items.length == 1 &&
              (widget.items[r][e] as GeneratedFormSubForm).items[0].length == 1;
          for (int i = 0; i < values[fieldKey].length; i++) {
            final internalFormKey = ValueKey(
              generateDeterministicId(
                values[fieldKey].length,
                seed2: i,
                seed3: forceUpdateKeyCount,
              ),
            );
            subformColumn.add(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!compact) const SizedBox(height: 16),
                  if (!compact)
                    Text(
                      '${(widget.items[r][e] as GeneratedFormSubForm).label} (${i + 1})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  GeneratedForm(
                    key: internalFormKey,
                    outlinedInputFields: widget.outlinedInputFields,
                    outlinedFieldBorderRadius: widget.outlinedFieldBorderRadius,
                    prominentSectionHeaders: widget.prominentSectionHeaders,
                    outlinedFieldsExternalLabels:
                        widget.outlinedFieldsExternalLabels,
                    wrapFormSectionsInCards: widget.wrapFormSectionsInCards,
                    items:
                        cloneFormItems(
                              (widget.items[r][e] as GeneratedFormSubForm)
                                  .items,
                            )
                            .map(
                              (x) => x.map((y) {
                                y.value = values[fieldKey]?[i]?[y.key];
                                y.key = '${y.key.toString()},$internalFormKey';
                                return y;
                              }).toList(),
                            )
                            .toList(),
                    onValueChanges: (values, valid, isBuilding) {
                      values = values.map(
                        (key, value) => MapEntry(key.split(',')[0], value),
                      );
                      if (valid) {
                        this.values[fieldKey]?[i] = values;
                      }
                      someValueChanged(
                        isBuilding: isBuilding,
                        forceInvalid: !valid,
                      );
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: (values[fieldKey].length > 0)
                            ? () {
                                final temp = List.from(values[fieldKey]);
                                temp.removeAt(i);
                                values[fieldKey] = List.from(temp);
                                forceUpdateKeyCount++;
                                someValueChanged();
                              }
                            : null,
                        label: Text(
                          '${(widget.items[r][e] as GeneratedFormSubForm).label} (${i + 1})',
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }
          subformColumn.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 0, top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        values[fieldKey].add(
                          getDefaultValuesFromFormItems(
                            (widget.items[r][e] as GeneratedFormSubForm).items,
                          ),
                        );
                        forceUpdateKeyCount++;
                        someValueChanged();
                      },
                      icon: const Icon(Icons.add),
                      label: Text(
                        (widget.items[r][e] as GeneratedFormSubForm).label,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          formInputs[r][e] = Column(children: subformColumn);
        }
      }
    }

    rows.clear();
    formInputs.asMap().entries.forEach((rowInputs) {
      if (rowInputs.key > 0) {
        final bool previousRowIsSwitch =
            widget.items[rowInputs.key - 1][0] is GeneratedFormSwitch;
        final double gapAfterPreviousRow = previousRowIsSwitch
            ? 8
            : (widget.outlinedInputFields ? 12 : 25);
        rows.add([SizedBox(height: gapAfterPreviousRow)]);
      }
      final List<Widget> rowItems = [];
      rowInputs.value.asMap().entries.forEach((rowInput) {
        if (rowInput.key > 0) {
          rowItems.add(const SizedBox(width: 20));
        }
        rowItems.add(
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                rowInput.value,
                ...widget.items[rowInputs.key][rowInput.key].belowWidgets
                    .cast<Widget>(),
              ],
            ),
          ),
        );
      });
      rows.add(rowItems);
    });

    final List<Widget> rowBars = rows.map((List<Widget> row) {
      if (row.length == 1 && row.single is SizedBox) {
        final SizedBox spacer = row.single as SizedBox;
        return SizedBox(width: double.infinity, height: spacer.height);
      }
      return Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: row,
      );
    }).toList();

    Widget formBody;
    if (widget.wrapFormSectionsInCards) {
      final List<List<int>> sections = generatedFormSectionRowIndices(
        widget.items,
      );
      final List<Widget> sectionCards = <Widget>[];
      for (final List<int> sectionRows in sections) {
        final List<Widget> sectionChildren = <Widget>[];
        for (int index = 0; index < sectionRows.length; index++) {
          final int rowIndex = sectionRows[index];
          if (rowIndex > 0) {
            sectionChildren.add(rowBars[2 * rowIndex - 1]);
          }
          sectionChildren.add(rowBars[2 * rowIndex]);
        }
        sectionCards.add(
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            decoration: appPageSectionCardDecoration(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: sectionChildren,
              ),
            ),
          ),
        );
      }
      formBody = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: sectionCards,
      );
    } else {
      formBody = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rowBars,
      );
    }

    return Form(key: _formKey, child: formBody);
  }
}

class GeneratedFormModal extends StatefulWidget {
  const GeneratedFormModal({
    super.key,
    required this.title,
    required this.items,
    this.initValid = false,
    this.message = '',
    this.additionalWidgets = const [],
    this.singleNullReturnButton,
    this.primaryActionColour,
    this.tileMode = false,
  });

  final String title;
  final String message;
  final List<List<GeneratedFormItem>> items;
  final bool initValid;
  final List<Widget> additionalWidgets;
  final String? singleNullReturnButton;
  final Color? primaryActionColour;
  final bool tileMode;

  @override
  State<GeneratedFormModal> createState() => _GeneratedFormModalState();
}

class _GeneratedFormModalState extends State<GeneratedFormModal> {
  Map<String, dynamic> values = {};
  bool valid = false;

  @override
  void initState() {
    super.initState();
    valid = widget.initValid || widget.items.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      contentPadding: appDialogContentPadding,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.message.isNotEmpty) Text(widget.message),
          if (widget.message.isNotEmpty) const SizedBox(height: 16),
          GeneratedForm(
            tileMode: widget.tileMode,
            items: widget.items,
            onValueChanges: (nextValues, nextValid, isBuilding) {
              if (isBuilding) {
                values = nextValues;
                valid = nextValid;
              } else {
                setState(() {
                  values = nextValues;
                  valid = nextValid;
                });
              }
            },
          ),
          if (widget.additionalWidgets.isNotEmpty) ...widget.additionalWidgets,
        ],
      ),
      actions: [
        TextButton(
          autofocus: context.read<SettingsProvider>().isTV,
          onPressed: () {
            Navigator.of(context).pop(null);
          },
          child: Text(
            widget.singleNullReturnButton == null
                ? tr('cancel')
                : widget.singleNullReturnButton!,
          ),
        ),
        widget.singleNullReturnButton == null
            ? FilledButton(
                // Emphasized primary. A non-null primaryActionColour marks a
                // destructive confirm (e.g. colorScheme.error) → filled in that
                // colour with a contrast-safe foreground; otherwise the default
                // primary fill.
                style: widget.primaryActionColour == null
                    ? null
                    : FilledButton.styleFrom(
                        backgroundColor: widget.primaryActionColour,
                        foregroundColor:
                            ThemeData.estimateBrightnessForColor(
                                  widget.primaryActionColour!,
                                ) ==
                                Brightness.dark
                            ? Colors.white
                            : Colors.black,
                      ),
                onPressed: !valid
                    ? null
                    : () {
                        if (valid) {
                          hapticSelection();
                          Navigator.of(context).pop(values);
                        }
                      },
                child: Text(tr('continue')),
              )
            : const SizedBox.shrink(),
      ],
    );
  }
}
