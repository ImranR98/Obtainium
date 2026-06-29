import 'dart:math';

import 'package:hsluv/hsluv.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/ui_shapes.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

abstract class GeneratedFormItem {
  late String key;
  late String label;
  late List<Widget> belowWidgets;
  late dynamic defaultValue;
  List<dynamic> additionalValidators;
  dynamic ensureType(dynamic val);
  GeneratedFormItem clone();

  GeneratedFormItem(
    this.key, {
    this.label = 'Input',
    this.belowWidgets = const [],
    this.defaultValue,
    this.additionalValidators = const [],
  });
}

class GeneratedFormTextField extends GeneratedFormItem {
  late bool required;
  late int max;
  late String? hint;
  late bool password;
  late TextInputType? textInputType;
  late List<String>? autoCompleteOptions;
  late String? helpUrl;

  GeneratedFormTextField(
    super.key, {
    super.label,
    super.belowWidgets,
    String super.defaultValue = '',
    List<String? Function(String? value)> super.additionalValidators = const [],
    this.required = true,
    this.max = 1,
    this.hint,
    this.password = false,
    this.textInputType,
    this.autoCompleteOptions,
    this.helpUrl,
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
      defaultValue: defaultValue,
      additionalValidators: List.from(additionalValidators),
      required: required,
      max: max,
      hint: hint,
      password: password,
      textInputType: textInputType,
      autoCompleteOptions: autoCompleteOptions,
      helpUrl: helpUrl,
    );
  }
}

class GeneratedFormDropdown extends GeneratedFormItem {
  late List<MapEntry<String, String>>? opts;
  List<String>? disabledOptKeys;

  GeneratedFormDropdown(
    super.key,
    this.opts, {
    super.label,
    super.belowWidgets,
    String super.defaultValue = '',
    this.disabledOptKeys,
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
      defaultValue: defaultValue,
      disabledOptKeys: disabledOptKeys != null
          ? List.from(disabledOptKeys!)
          : null,
      additionalValidators: List.from(additionalValidators),
    );
  }
}

class GeneratedFormSwitch extends GeneratedFormItem {
  bool disabled;

  GeneratedFormSwitch(
    super.key, {
    super.label,
    super.belowWidgets,
    bool super.defaultValue = false,
    this.disabled = false,
    List<String? Function(bool value)> super.additionalValidators = const [],
  });

  @override
  bool ensureType(val) {
    return val == true || val == 'true';
  }

  @override
  GeneratedFormSwitch clone() {
    return GeneratedFormSwitch(
      key,
      label: label,
      belowWidgets: belowWidgets,
      defaultValue: defaultValue,
      disabled: disabled,
      additionalValidators: List.from(additionalValidators),
    );
  }
}

typedef OnValueChanges =
    void Function(Map<String, dynamic> values, bool valid, bool isBuilding);

class GeneratedForm extends StatefulWidget {
  const GeneratedForm({
    super.key,
    required this.items,
    required this.onValueChanges,
    this.tileMode = false,
  });

  final List<List<GeneratedFormItem>> items;
  final OnValueChanges onValueChanges;

  /// When true, switch rows are rendered as connected, rounded "setting tiles"
  /// (matching the settings page); other inputs render as their normal filled
  /// fields.
  final bool tileMode;

  @override
  State<GeneratedForm> createState() => _GeneratedFormState();
}

List<List<GeneratedFormItem>> cloneFormItems(
  List<List<GeneratedFormItem>> items,
) {
  List<List<GeneratedFormItem>> clonedItems = [];
  for (var row in items) {
    List<GeneratedFormItem> clonedRow = [];
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
    super.defaultValue = const [],
  });

  @override
  ensureType(val) {
    return val; // Not easy to validate List<Map<String, dynamic>>
  }

  @override
  GeneratedFormSubForm clone() {
    return GeneratedFormSubForm(
      key,
      cloneFormItems(items),
      label: label,
      belowWidgets: belowWidgets,
      defaultValue: defaultValue,
    );
  }
}

// Generates a color in the HSLuv (Pastel) color space
// https://pub.dev/documentation/hsluv/latest/hsluv/Hsluv/hpluvToRgb.html
Color generateRandomLightColor() {
  final randomSeed = Random().nextInt(120);
  // https://en.wikipedia.org/wiki/Golden_angle
  final goldenAngle = 180 * (3 - sqrt(5));
  // Generate next golden angle hue
  final double hue = randomSeed * goldenAngle;
  // Map from HPLuv color space to RGB, use constant saturation=100, lightness=70
  final List<double> rgbValuesDbl = Hsluv.hpluvToRgb([hue, 100, 70]);
  // Map RBG values from 0-1 to 0-255:
  final List<int> rgbValues = rgbValuesDbl
      .map((rgb) => (rgb * 255).toInt())
      .toList();
  return Color.fromARGB(255, rgbValues[0], rgbValues[1], rgbValues[2]);
}

int generateRandomNumber(
  int seed1, {
  int seed2 = 0,
  int seed3 = 0,
  max = 10000,
}) {
  int combinedSeed = seed1.hashCode ^ seed2.hashCode ^ seed3.hashCode;
  Random random = Random(combinedSeed);
  int randomNumber = random.nextInt(max);
  return randomNumber;
}

bool validateTextField(TextFormField tf) =>
    (tf.key as GlobalKey<FormFieldState>).currentState?.isValid == true;

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

  @override
  void didUpdateWidget(covariant _TVTextFieldFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.textFocusNode != oldWidget.textFocusNode) {
      oldWidget.textFocusNode.removeListener(_onTextFocusChange);
      widget.textFocusNode.addListener(_onTextFocusChange);
    }
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

class _FormSwitchRow extends StatelessWidget {
  const _FormSwitchRow({
    required this.item,
    required this.value,
    required this.onChanged,
  });

  final GeneratedFormSwitch item;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(item.label)),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: item.disabled ? null : onChanged,
        ),
      ],
    );
  }
}

class _GeneratedFormState extends State<GeneratedForm> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic> values = {};
  late List<List<Widget>> formInputs;
  String? initKey;
  int forceUpdateKeyCount = 0;
  // Text controllers created by initForm(); disposed in dispose() to avoid
  // leaking them when the form is removed.
  final List<TextEditingController> _textControllers = [];

  // If any value changes, call this to update the parent with value and validity
  void someValueChanged({bool isBuilding = false, bool forceInvalid = false}) {
    Map<String, dynamic> returnValues = values;
    var valid = true;
    for (int r = 0; r < formInputs.length; r++) {
      for (int i = 0; i < formInputs[r].length; i++) {
        if (formInputs[r][i] is TextFormField) {
          valid = valid && validateTextField(formInputs[r][i] as TextFormField);
        }
      }
    }
    if (forceInvalid) {
      valid = false;
    }
    widget.onValueChanges(returnValues, valid, isBuilding);
  }

  void initForm() {
    initKey = widget.key.toString();
    for (final c in _textControllers) {
      c.dispose();
    }
    _textControllers.clear();
    values.clear();
    for (var row in widget.items) {
      for (var e in row) {
        values[e.key] = e.defaultValue;
      }
    }

    // Dynamically create form inputs
    formInputs = widget.items.asMap().entries.map((row) {
      return row.value.asMap().entries.map((e) {
        var formItem = e.value;
        if (formItem is GeneratedFormTextField) {
          final formFieldKey = GlobalKey<FormFieldState>();
          var ctrl = TextEditingController(text: values[formItem.key]);
          _textControllers.add(ctrl);
          return TypeAheadField<String>(
            controller: ctrl,
            builder: (context, controller, focusNode) {
              final textField = TextFormField(
                controller: ctrl,
                focusNode: focusNode,
                keyboardType: formItem.textInputType,
                obscureText: formItem.password,
                autocorrect: !formItem.password,
                enableSuggestions: !formItem.password,
                key: formFieldKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (value) {
                  setState(() {
                    values[formItem.key] = value;
                    someValueChanged();
                  });
                },
                decoration: InputDecoration(
                  labelText: formItem.label + (formItem.required ? ' *' : ''),
                  hintText: formItem.hint,
                  filled: widget.tileMode ? false : null,
                  border: widget.tileMode ? InputBorder.none : null,
                  enabledBorder: widget.tileMode ? InputBorder.none : null,
                  focusedBorder: widget.tileMode ? InputBorder.none : null,
                  suffixIcon: formItem.helpUrl != null
                      ? IconButton(
                          icon: const Icon(Icons.open_in_new),
                          tooltip: tr('about'),
                          onPressed: () => launchUrlString(
                            formItem.helpUrl!,
                            mode: LaunchMode.externalApplication,
                          ).ignore(),
                        )
                      : formItem.belowWidgets.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.help_outline),
                          tooltip: tr('about'),
                          onPressed: () => showHelpDialog(
                            context,
                            title: formItem.label,
                            content: formItem.belowWidgets,
                          ),
                        )
                      : null,
                ),
                minLines: formItem.max <= 1 ? null : formItem.max,
                maxLines: formItem.max <= 1 ? 1 : formItem.max,
                validator: (value) {
                  if (formItem.required &&
                      (value == null || value.trim().isEmpty)) {
                    return '${formItem.label} ${tr('requiredInBrackets')}';
                  }
                  for (var validator in formItem.additionalValidators) {
                    String? result = validator(value);
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
        } else if (formItem is GeneratedFormDropdown) {
          if (formItem.opts!.isEmpty) {
            return Text(tr('dropdownNoOptsError'));
          }
          return DropdownButtonFormField(
            decoration: InputDecoration(
              labelText: formItem.label,
              filled: widget.tileMode ? false : null,
              border: widget.tileMode ? InputBorder.none : null,
              enabledBorder: widget.tileMode ? InputBorder.none : null,
              focusedBorder: widget.tileMode ? InputBorder.none : null,
            ),
            initialValue: values[formItem.key],
            items: formItem.opts!.map((e2) {
              var enabled = formItem.disabledOptKeys?.contains(e2.key) != true;
              return DropdownMenuItem(
                value: e2.key,
                enabled: enabled,
                child: Opacity(
                  opacity: enabled ? 1 : 0.5,
                  child: Text(e2.value),
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                values[formItem.key] = value ?? formItem.opts!.first.key;
                someValueChanged();
              });
            },
          );
        } else if (formItem is GeneratedFormSubForm) {
          values[formItem.key] = [];
          for (Map<String, dynamic> v
              in ((formItem.defaultValue ?? []) as List<dynamic>)) {
            var fullDefaults = getDefaultValuesFromFormItems(formItem.items);
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
  void dispose() {
    for (final c in _textControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.key.toString() != initKey) {
      initForm();
    }
    // Build a fresh render list each frame instead of mutating the
    // state-held [formInputs] (mutating state during build() is a Flutter
    // anti-pattern that can trigger rebuild loops). Persistent text/dropdown
    // field widgets are reused by reference; switch/subform slots are
    // (re)built here into the local copy only.
    final List<List<Widget>> renderedInputs = [
      for (final row in formInputs) [...row],
    ];
    for (var r = 0; r < renderedInputs.length; r++) {
      for (var e = 0; e < renderedInputs[r].length; e++) {
        final item = widget.items[r][e];
        String fieldKey = item.key;
        if (item is GeneratedFormSwitch) {
          renderedInputs[r][e] = _FormSwitchRow(
            item: item,
            value: values[fieldKey] as bool,
            onChanged: item.disabled
                ? null
                : (value) {
                    setState(() {
                      values[fieldKey] = value;
                      someValueChanged();
                    });
                  },
          );
        } else if (item is GeneratedFormSubForm) {
          List<Widget> subformColumn = [];
          var compact = item.items.length == 1 && item.items[0].length == 1;
          for (int i = 0; i < values[fieldKey].length; i++) {
            var internalFormKey = ValueKey(
              generateRandomNumber(
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
                      '${item.label} (${i + 1})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  GeneratedForm(
                    key: internalFormKey,
                    items: cloneFormItems(item.items)
                        .map(
                          (x) => x.map((y) {
                            y.defaultValue = values[fieldKey]?[i]?[y.key];
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
                                var temp = List.from(values[fieldKey]);
                                temp.removeAt(i);
                                values[fieldKey] = List.from(temp);
                                forceUpdateKeyCount++;
                                someValueChanged();
                              }
                            : null,
                        label: Text('${item.label} (${i + 1})'),
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
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        values[fieldKey].add(
                          getDefaultValuesFromFormItems(item.items),
                        );
                        forceUpdateKeyCount++;
                        someValueChanged();
                      },
                      icon: const Icon(Icons.add),
                      label: Text(item.label),
                    ),
                  ),
                ],
              ),
            ),
          );
          renderedInputs[r][e] = Column(children: subformColumn);
        }
      }
    }

    // Build one Row widget per input row.
    final List<Widget> inputRowWidgets = [];
    renderedInputs.asMap().entries.forEach((rowInputs) {
      List<Widget> rowItems = [];
      rowInputs.value.asMap().entries.forEach((rowInput) {
        if (rowInput.key > 0) {
          rowItems.add(const SizedBox(width: 20));
        }
        rowItems.add(Expanded(child: rowInput.value));
      });
      inputRowWidgets.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rowItems,
        ),
      );
    });

    if (widget.tileMode) {
      bool isFieldRow(int r) =>
          widget.items[r].isNotEmpty &&
          (widget.items[r][0] is GeneratedFormTextField ||
              widget.items[r][0] is GeneratedFormDropdown);
      bool isSwitchRow(int r) =>
          widget.items[r].isNotEmpty &&
          widget.items[r][0] is GeneratedFormSwitch;
      final colorScheme = Theme.of(context).colorScheme;
      final n = inputRowWidgets.length;
      final List<Widget> children = [];
      for (var r = 0; r < n; r++) {
        final EdgeInsets padding = isFieldRow(r)
            ? EdgeInsets.zero
            : isSwitchRow(r)
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 4)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
        children.add(
          Material(
            // Fields use a distinct, slightly more prominent tone so they
            // stand out from the surrounding control tiles while still
            // sharing the connected positional-radii system.
            color: isFieldRow(r)
                ? colorScheme.surfaceContainerHighest
                : colorScheme.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            shape: positionalTileShape(isFirst: r == 0, isLast: r == n - 1),
            child: Padding(padding: padding, child: inputRowWidgets[r]),
          ),
        );
      }
      return Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 3,
          children: children,
        ),
      );
    }

    final List<Widget> children = [];
    for (var r = 0; r < inputRowWidgets.length; r++) {
      if (r > 0) {
        children.add(
          SizedBox(
            height: widget.items[r - 1][0] is GeneratedFormSwitch ? 16 : 28,
          ),
        );
      }
      children.add(inputRowWidgets[r]);
    }

    return Form(
      key: _formKey,
      child: Column(children: children),
    );
  }
}
