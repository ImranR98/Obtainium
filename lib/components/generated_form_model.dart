import 'dart:math';

import 'package:flutter/material.dart';

enum GeneratedFormItemType { textField, dropdown, switch_, subForm }

class GeneratedFormFieldState {
  final FormFieldDefinition definition;
  dynamic value;
  String? error;
  bool touched;

  GeneratedFormFieldState({
    required this.definition,
    this.value,
    this.error,
    this.touched = false,
  });
}

class FormFieldDefinition {
  final String key;
  final String label;
  final GeneratedFormItemType type;
  final bool required;
  final dynamic defaultValue;
  final int max;
  final String? hint;
  final bool password;
  final TextInputType? textInputType;
  final List<String>? autoCompleteOptions;
  final String? helpUrl;
  final List<MapEntry<String, String>>? opts;
  final List<String>? disabledOptKeys;
  final bool disabledSwitch;
  final List<List<FormFieldDefinition>>? subItems;
  final List<dynamic> validators;
  final List<dynamic> belowWidgets;

  const FormFieldDefinition({
    required this.key,
    required this.label,
    required this.type,
    this.required = true,
    this.defaultValue,
    this.max = 1,
    this.hint,
    this.password = false,
    this.textInputType,
    this.autoCompleteOptions,
    this.helpUrl,
    this.opts,
    this.disabledOptKeys,
    this.disabledSwitch = false,
    this.subItems,
    this.validators = const [],
    this.belowWidgets = const [],
  });

  GeneratedFormItem toGeneratedFormItem() {
    switch (type) {
      case GeneratedFormItemType.textField:
        return GeneratedFormTextField(
          key,
          label: label,
          belowWidgets: belowWidgets,
          value: defaultValue,
          additionalValidators: List.from(validators),
          required: required,
          max: max,
          hint: hint,
          password: password,
          textInputType: textInputType,
          autoCompleteOptions: autoCompleteOptions,
          helpUrl: helpUrl,
        );
      case GeneratedFormItemType.dropdown:
        return GeneratedFormDropdown(
          key,
          opts,
          label: label,
          belowWidgets: belowWidgets,
          value: defaultValue,
          disabledOptKeys: disabledOptKeys,
          additionalValidators: List.from(validators),
        );
      case GeneratedFormItemType.switch_:
        return GeneratedFormSwitch(
          key,
          label: label,
          belowWidgets: belowWidgets,
          value: defaultValue ?? false,
          disabled: disabledSwitch,
          additionalValidators: List.from(validators),
        );
      case GeneratedFormItemType.subForm:
        return GeneratedFormSubForm(
          key,
          subItems
                  ?.map(
                    (row) => row.map((d) => d.toGeneratedFormItem()).toList(),
                  )
                  .toList() ??
              [],
          label: label,
          belowWidgets: belowWidgets,
          value: defaultValue,
        );
    }
  }
}

abstract class GeneratedFormItem {
  late String key;
  late String label;
  late List<dynamic> belowWidgets;
  late dynamic value;
  List<dynamic> additionalValidators;
  dynamic ensureType(dynamic val);
  GeneratedFormItem clone();

  GeneratedFormItem(
    this.key, {
    this.label = 'Input',
    this.belowWidgets = const [],
    this.value,
    this.additionalValidators = const [],
  });

  FormFieldDefinition toDefinition() {
    if (this is GeneratedFormTextField) {
      final self = this as GeneratedFormTextField;
      return FormFieldDefinition(
        key: key,
        label: label,
        type: GeneratedFormItemType.textField,
        required: self.required,
        defaultValue: value,
        max: self.max,
        hint: self.hint,
        password: self.password,
        textInputType: self.textInputType,
        autoCompleteOptions: self.autoCompleteOptions,
        helpUrl: self.helpUrl,
        validators: List.from(additionalValidators),
        belowWidgets: List.from(belowWidgets),
      );
    }
    if (this is GeneratedFormDropdown) {
      final self = this as GeneratedFormDropdown;
      return FormFieldDefinition(
        key: key,
        label: label,
        type: GeneratedFormItemType.dropdown,
        defaultValue: value,
        opts: self.opts,
        disabledOptKeys: self.disabledOptKeys,
        validators: List.from(additionalValidators),
        belowWidgets: List.from(belowWidgets),
      );
    }
    if (this is GeneratedFormSwitch) {
      final self = this as GeneratedFormSwitch;
      return FormFieldDefinition(
        key: key,
        label: label,
        type: GeneratedFormItemType.switch_,
        defaultValue: value ?? false,
        disabledSwitch: self.disabled,
        validators: List.from(additionalValidators),
        belowWidgets: List.from(belowWidgets),
      );
    }
    if (this is GeneratedFormSubForm) {
      final self = this as GeneratedFormSubForm;
      return FormFieldDefinition(
        key: key,
        label: label,
        type: GeneratedFormItemType.subForm,
        defaultValue: value,
        subItems: self.items
            .map((row) => row.map((item) => item.toDefinition()).toList())
            .toList(),
        validators: List.from(additionalValidators),
        belowWidgets: List.from(belowWidgets),
      );
    }
    throw Exception('Unknown GeneratedFormItem type: $runtimeType');
  }
}

/// Optional inline "assist" action for a text field (e.g. the RegEx builder).
/// Given the current form values, it may push text patches back into the form.
typedef FormValuesTextPatch = void Function(Map<String, String> patches);

typedef GeneratedFormTextFieldAssist =
    Future<void> Function(
      BuildContext context,
      FormValuesTextPatch patch,
      Map<String, dynamic> values,
    );

class GeneratedFormTextField extends GeneratedFormItem {
  late bool required;
  final int max;
  final String? hint;
  final bool password;
  final TextInputType? textInputType;
  final List<String>? autoCompleteOptions;
  final String? helpUrl;
  // Fork-only: inline assist action + custom suffix (RegEx assist, etc.).
  GeneratedFormTextFieldAssist? assistAction;
  IconData assistIcon;
  String? assistTooltip;
  Widget? suffixIcon;

  GeneratedFormTextField(
    super.key, {
    super.label,
    super.belowWidgets,
    String super.value = '',
    List<String? Function(String? value)> super.additionalValidators = const [],
    this.required = true,
    this.max = 1,
    this.hint,
    this.password = false,
    this.textInputType,
    this.autoCompleteOptions,
    this.helpUrl,
    this.assistAction,
    this.assistIcon = Icons.auto_fix_high_outlined,
    this.assistTooltip,
    this.suffixIcon,
  });

  @override
  String ensureType(val) {
    return val.toString();
  }

  @override
  GeneratedFormTextField clone() {
    return GeneratedFormTextField(
      key,
      label: label,
      belowWidgets: belowWidgets,
      value: value,
      additionalValidators: List.from(additionalValidators),
      required: required,
      max: max,
      hint: hint,
      password: password,
      textInputType: textInputType,
      autoCompleteOptions: autoCompleteOptions,
      helpUrl: helpUrl,
      assistAction: assistAction,
      assistIcon: assistIcon,
      assistTooltip: assistTooltip,
      suffixIcon: suffixIcon,
    );
  }
}

class GeneratedFormDropdown extends GeneratedFormItem {
  final List<MapEntry<String, String>>? opts;
  List<String>? disabledOptKeys;
  late bool required;
  final String? helpUrl;
  // Fork-only: help icon rendered next to the dropdown label.
  String? labelTooltip;

  GeneratedFormDropdown(
    super.key,
    this.opts, {
    super.label,
    super.belowWidgets,
    String super.value = '',
    this.disabledOptKeys,
    this.required = true,
    this.helpUrl,
    this.labelTooltip,
    List<String? Function(String? value)> super.additionalValidators = const [],
  });

  @override
  String ensureType(val) {
    return val.toString();
  }

  @override
  GeneratedFormDropdown clone() {
    return GeneratedFormDropdown(
      key,
      opts?.map((e) => MapEntry(e.key, e.value)).toList(),
      label: label,
      belowWidgets: belowWidgets,
      value: value,
      disabledOptKeys: disabledOptKeys != null
          ? List.from(disabledOptKeys!)
          : null,
      required: required,
      helpUrl: helpUrl,
      labelTooltip: labelTooltip,
      additionalValidators: List.from(additionalValidators),
    );
  }
}

class GeneratedFormSwitch extends GeneratedFormItem {
  bool disabled;
  // Fork-only: help icon next to the switch label + keys this switch turns off.
  String? labelTooltip;
  List<String> turnsOffKeys;

  GeneratedFormSwitch(
    super.key, {
    super.label,
    super.belowWidgets,
    bool super.value = false,
    this.disabled = false,
    this.labelTooltip,
    this.turnsOffKeys = const [],
    List<String? Function(bool value)> super.additionalValidators = const [],
  });

  @override
  bool ensureType(val) {
    if (val is bool) return val;
    if (val is String) return val.toLowerCase() == 'true';
    return false;
  }

  @override
  GeneratedFormSwitch clone() {
    return GeneratedFormSwitch(
      key,
      label: label,
      belowWidgets: belowWidgets,
      value: value,
      disabled: disabled,
      labelTooltip: labelTooltip,
      turnsOffKeys: List.from(turnsOffKeys),
      additionalValidators: List.from(additionalValidators),
    );
  }
}

/// Fork-only: visual group title for long forms; not written to [values] or
/// app settings (rendered as a section header by the form renderer).
class GeneratedFormSectionHeader extends GeneratedFormItem {
  GeneratedFormSectionHeader(super.key, {required super.label})
    : super(value: null, belowWidgets: const []);

  @override
  dynamic ensureType(dynamic val) => null;

  @override
  GeneratedFormSectionHeader clone() {
    return GeneratedFormSectionHeader(key, label: label);
  }
}

/// Fork-only: category chip input. Value is a map of tag name -> (color, selected).
class GeneratedFormTagInput extends GeneratedFormItem {
  late MapEntry<String, String>? deleteConfirmationMessage;
  late bool singleSelect;
  late WrapAlignment alignment;
  late String emptyMessage;
  late bool showLabelWhenNotEmpty;

  /// When false, only category chips are shown (toggle selection). Add / edit /
  /// remove list controls are hidden.
  late bool allowTagManagement;
  late bool showSelectedCheckmark;
  late bool showChangeIntentIcons;
  GeneratedFormTagInput(
    super.key, {
    super.label,
    super.belowWidgets,
    Map<String, MapEntry<int, bool>> super.value = const {},
    List<String? Function(Map<String, MapEntry<int, bool>> value)>
        super.additionalValidators =
        const [],
    this.deleteConfirmationMessage,
    this.singleSelect = false,
    this.alignment = WrapAlignment.start,
    this.emptyMessage = 'Input',
    this.showLabelWhenNotEmpty = true,
    this.allowTagManagement = true,
    this.showSelectedCheckmark = false,
    this.showChangeIntentIcons = true,
  });

  @override
  Map<String, MapEntry<int, bool>> ensureType(val) {
    return val is Map<String, MapEntry<int, bool>> ? val : {};
  }

  @override
  GeneratedFormTagInput clone() {
    return GeneratedFormTagInput(
      key,
      label: label,
      belowWidgets: belowWidgets,
      value: value,
      additionalValidators: List.from(additionalValidators),
      deleteConfirmationMessage: deleteConfirmationMessage,
      singleSelect: singleSelect,
      alignment: alignment,
      emptyMessage: emptyMessage,
      showLabelWhenNotEmpty: showLabelWhenNotEmpty,
      allowTagManagement: allowTagManagement,
      showSelectedCheckmark: showSelectedCheckmark,
      showChangeIntentIcons: showChangeIntentIcons,
    );
  }
}

List<List<GeneratedFormItem>> cloneFormItems(
  List<List<GeneratedFormItem>> items,
) {
  final List<List<GeneratedFormItem>> clonedItems = [];
  for (var row in items) {
    final List<GeneratedFormItem> clonedRow = [];
    for (var it in row) {
      clonedRow.add(it.clone());
    }
    clonedItems.add(clonedRow);
  }
  return clonedItems;
}

class GeneratedFormSubForm extends GeneratedFormItem {
  final List<List<GeneratedFormItem>> items;

  GeneratedFormSubForm(
    super.key,
    this.items, {
    super.label,
    super.belowWidgets,
    super.value = const [],
  });

  @override
  dynamic ensureType(val) {
    if (val is List) return val;
    return [];
  }

  @override
  GeneratedFormSubForm clone() {
    return GeneratedFormSubForm(
      key,
      cloneFormItems(items),
      label: label,
      belowWidgets: belowWidgets,
      value: value,
    );
  }
}

int generateDeterministicId(
  int seed1, {
  int seed2 = 0,
  int seed3 = 0,
  int max = 10000,
}) {
  final int combinedSeed = seed1.hashCode ^ seed2.hashCode ^ seed3.hashCode;
  final Random random = Random(combinedSeed);
  return random.nextInt(max);
}

Map<String, dynamic> getDefaultValuesFromFormItems(
  List<List<GeneratedFormItem>> items,
) {
  final entries = <MapEntry<String, dynamic>>[];
  for (final row in items) {
    for (final el in row) {
      if (el is GeneratedFormSectionHeader) {
        continue;
      } else if (el is GeneratedFormSwitch) {
        entries.add(MapEntry(el.key, el.value ?? false));
      } else if (el is GeneratedFormSubForm) {
        entries.add(MapEntry(el.key, el.value ?? []));
      } else {
        entries.add(MapEntry(el.key, el.value ?? ''));
      }
    }
  }
  return Map.fromEntries(entries);
}
