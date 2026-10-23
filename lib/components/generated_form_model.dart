import 'package:flutter/widgets.dart';

abstract class GeneratedFormItem {
  late String key;
  late String label;
  late dynamic value;
  List<dynamic> additionalValidators;
  dynamic ensureType(dynamic val);
  GeneratedFormItem clone();

  GeneratedFormItem(
    this.key, {
    this.label = 'Input',
    this.value,
    this.additionalValidators = const [],
  });
}

class GeneratedFormTextField extends GeneratedFormItem {
  late bool required;
  final int max;
  final String? hint;
  final bool password;
  final List<String>? autoCompleteOptions;
  final String? helpUrl;
  final Widget? suffixIcon;

  GeneratedFormTextField(
    super.key, {
    super.label,
    String super.value = '',
    List<String? Function(String? value)> super.additionalValidators = const [],
    this.required = true,
    this.max = 1,
    this.hint,
    this.password = false,
    this.autoCompleteOptions,
    this.helpUrl,
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
      value: value,
      additionalValidators: List.from(additionalValidators),
      required: required,
      max: max,
      hint: hint,
      password: password,
      autoCompleteOptions: autoCompleteOptions,
      helpUrl: helpUrl,
      suffixIcon: suffixIcon,
    );
  }
}

class GeneratedFormDropdown extends GeneratedFormItem {
  final List<MapEntry<String, String>>? opts;
  late bool required;
  final String? helpUrl;

  GeneratedFormDropdown(
    super.key,
    this.opts, {
    super.label,
    String super.value = '',
    this.required = true,
    this.helpUrl,
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
      value: value,
      required: required,
      helpUrl: helpUrl,
      additionalValidators: List.from(additionalValidators),
    );
  }
}

class GeneratedFormSwitch extends GeneratedFormItem {
  bool disabled;
  final List<String> mutuallyExclusiveWith;

  GeneratedFormSwitch(
    super.key, {
    super.label,
    bool super.value = false,
    this.disabled = false,
    this.mutuallyExclusiveWith = const [],
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
      value: value,
      disabled: disabled,
      mutuallyExclusiveWith: List.from(mutuallyExclusiveWith),
      additionalValidators: List.from(additionalValidators),
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

class GeneratedFormSlider extends GeneratedFormItem {
  /// Maps each slider stop's value to a label. Labels are either translation
  /// keys or plain numeric counts (resolved by the renderer with the
  /// pluralized [numericLabelUnitKey] string).
  final List<MapEntry<String, String>>? opts;
  final String numericLabelUnitKey;
  late bool required;

  GeneratedFormSlider(
    super.key,
    this.opts, {
    super.label,
    String super.value = '',
    this.required = true,
    this.numericLabelUnitKey = 'day',
    List<String? Function(String? value)> super.additionalValidators = const [],
  });

  @override
  String ensureType(val) {
    return val.toString();
  }

  @override
  GeneratedFormSlider clone() {
    return GeneratedFormSlider(
      key,
      opts?.map((e) => MapEntry(e.key, e.value)).toList(),
      label: label,
      value: value,
      required: required,
      numericLabelUnitKey: numericLabelUnitKey,
      additionalValidators: List.from(additionalValidators),
    );
  }
}

class GeneratedFormSubForm extends GeneratedFormItem {
  final List<List<GeneratedFormItem>> items;

  GeneratedFormSubForm(
    super.key,
    this.items, {
    super.label,
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
      value: value,
    );
  }
}

/// A non-input section label rendered between form rows. [id] can be used to
/// scroll a form to the section (via [GlobalObjectKey]).
class GeneratedFormHeader extends GeneratedFormItem {
  final String? id;

  GeneratedFormHeader({this.id, required super.label}) : super('');

  @override
  dynamic ensureType(val) => val;

  @override
  GeneratedFormHeader clone() => GeneratedFormHeader(id: id, label: label);
}

Map<String, dynamic> getDefaultValuesFromFormItems(
  List<List<GeneratedFormItem>> items,
) {
  final entries = <MapEntry<String, dynamic>>[];
  for (final row in items) {
    for (final el in row) {
      if (el is GeneratedFormHeader) continue;
      if (el is GeneratedFormSwitch) {
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
