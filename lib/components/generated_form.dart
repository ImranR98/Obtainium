import 'dart:math';

import 'package:hsluv/hsluv.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/providers/source_provider.dart';

abstract class GeneratedFormItem {
  late String key;
  late String label;
  late List<Widget> belowWidgets;
  late dynamic defaultValue;
  List<dynamic> additionalValidators;
  dynamic ensureType(dynamic val);

  GeneratedFormItem(this.key,
      {this.label = 'Input',
      this.belowWidgets = const [],
      this.defaultValue,
      this.additionalValidators = const []});
}

class GeneratedFormTextField extends GeneratedFormItem {
  late bool required;
  late int max;
  late String? hint;
  late bool password;
  late TextInputType? textInputType;

  GeneratedFormTextField(super.key,
      {super.label,
      super.belowWidgets,
      String super.defaultValue = '',
      List<String? Function(String? value)> super.additionalValidators =
          const [],
      this.required = true,
      this.max = 1,
      this.hint,
      this.password = false,
      this.textInputType});

  @override
  String ensureType(val) {
    return val.toString();
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
}

class GeneratedFormSwitch extends GeneratedFormItem {
  GeneratedFormSwitch(
    super.key, {
    super.label,
    super.belowWidgets,
    bool super.defaultValue = false,
    List<String? Function(bool value)> super.additionalValidators = const [],
  });

  @override
  bool ensureType(val) {
    return val == true || val == 'true';
  }
}

class GeneratedFormTagInput extends GeneratedFormItem {
  late MapEntry<String, String>? deleteConfirmationMessage;
  late bool singleSelect;
  late WrapAlignment alignment;
  late String emptyMessage;
  late bool showLabelWhenNotEmpty;
  GeneratedFormTagInput(super.key,
      {super.label,
      super.belowWidgets,
      Map<String, MapEntry<int, bool>> super.defaultValue = const {},
      List<String? Function(Map<String, MapEntry<int, bool>> value)>
          super.additionalValidators = const [],
      this.deleteConfirmationMessage,
      this.singleSelect = false,
      this.alignment = WrapAlignment.start,
      this.emptyMessage = 'Input',
      this.showLabelWhenNotEmpty = true});

  @override
  Map<String, MapEntry<int, bool>> ensureType(val) {
    return val is Map<String, MapEntry<int, bool>> ? val : {};
  }
}

typedef OnValueChanges = void Function(
    Map<String, dynamic> values, bool valid, bool isBuilding);

class GeneratedForm extends StatefulWidget {
  const GeneratedForm(
      {super.key, required this.items, required this.onValueChanges});

  final List<List<GeneratedFormItem>> items;
  final OnValueChanges onValueChanges;

  @override
  State<GeneratedForm> createState() => _GeneratedFormState();
}

class GeneratedFormSubForm extends GeneratedFormItem {
  final List<List<GeneratedFormItem>> items;

  GeneratedFormSubForm(super.key, this.items,
      {super.label, super.belowWidgets, super.defaultValue});

  @override
  ensureType(val) {
    return val; // Not easy to validate List<Map<String, dynamic>>
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
  final List<int> rgbValues =
      rgbValuesDbl.map((rgb) => (rgb * 255).toInt()).toList();
  return Color.fromARGB(255, rgbValues[0], rgbValues[1], rgbValues[2]);
}

bool validateTextField(TextFormField tf) =>
    (tf.key as GlobalKey<FormFieldState>).currentState?.isValid == true;

class _GeneratedFormState extends State<GeneratedForm> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic> values = {};
  late List<List<Widget>> formInputs;
  List<List<Widget>> rows = [];
  String? initKey;

  // If any value changes, call this to update the parent with value and validity
  void someValueChanged({bool isBuilding = false, bool forceInvalid = false}) {
    Map<String, dynamic> returnValues = values;
    var valid = true;
    for (int r = 0; r < widget.items.length; r++) {
      for (int i = 0; i < widget.items[r].length; i++) {
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

  initForm() {
    initKey = widget.key.toString();
    // Initialize form values as all empty
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
          return TextFormField(
            keyboardType: formItem.textInputType,
            obscureText: formItem.password,
            autocorrect: !formItem.password,
            enableSuggestions: !formItem.password,
            key: formFieldKey,
            initialValue: values[formItem.key],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (value) {
              setState(() {
                values[formItem.key] = value;
                someValueChanged();
              });
            },
            decoration: InputDecoration(
                helperText: formItem.label + (formItem.required ? ' *' : ''),
                hintText: formItem.hint),
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
        } else if (formItem is GeneratedFormDropdown) {
          if (formItem.opts!.isEmpty) {
            return Text(tr('dropdownNoOptsError'));
          }
          return DropdownButtonFormField(
              decoration: InputDecoration(labelText: formItem.label),
              value: values[formItem.key],
              items: formItem.opts!.map((e2) {
                var enabled =
                    formItem.disabledOptKeys?.contains(e2.key) != true;
                return DropdownMenuItem(
                    value: e2.key,
                    enabled: enabled,
                    child: Opacity(
                        opacity: enabled ? 1 : 0.5, child: Text(e2.value)));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  values[formItem.key] = value ?? formItem.opts!.first.key;
                  someValueChanged();
                });
              });
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
  Widget build(BuildContext context) {
    if (widget.key.toString() != initKey) {
      initForm();
    }
    for (var r = 0; r < formInputs.length; r++) {
      for (var e = 0; e < formInputs[r].length; e++) {
        String fieldKey = widget.items[r][e].key;
        if (widget.items[r][e] is GeneratedFormSwitch) {
          formInputs[r][e] = Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(widget.items[r][e].label)),
              const SizedBox(
                width: 8,
              ),
              Switch(
                  value: values[fieldKey],
                  onChanged: (value) {
                    setState(() {
                      values[fieldKey] = value;
                      someValueChanged();
                    });
                  })
            ],
          );
        } else if (widget.items[r][e] is GeneratedFormTagInput) {
          formInputs[r][e] =
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                  const SizedBox(
                    height: 8,
                  ),
                ],
              ),
            Wrap(
              alignment:
                  (widget.items[r][e] as GeneratedFormTagInput).alignment,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                (values[fieldKey] as Map<String, MapEntry<int, bool>>?)
                            ?.isEmpty ==
                        true
                    ? Text(
                        (widget.items[r][e] as GeneratedFormTagInput)
                            .emptyMessage,
                      )
                    : const SizedBox.shrink(),
                ...(values[fieldKey] as Map<String, MapEntry<int, bool>>?)
                        ?.entries
                        .map((e2) {
                      return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(e2.key),
                            backgroundColor: Color(e2.value.key).withAlpha(50),
                            selectedColor: Color(e2.value.key),
                            visualDensity: VisualDensity.compact,
                            selected: e2.value.value,
                            onSelected: (value) {
                              setState(() {
                                (values[fieldKey] as Map<String,
                                        MapEntry<int, bool>>)[e2.key] =
                                    MapEntry(
                                        (values[fieldKey] as Map<String,
                                                MapEntry<int, bool>>)[e2.key]!
                                            .key,
                                        value);
                                if ((widget.items[r][e]
                                            as GeneratedFormTagInput)
                                        .singleSelect &&
                                    value == true) {
                                  for (var key in (values[fieldKey]
                                          as Map<String, MapEntry<int, bool>>)
                                      .keys) {
                                    if (key != e2.key) {
                                      (values[fieldKey] as Map<
                                          String,
                                          MapEntry<int,
                                              bool>>)[key] = MapEntry(
                                          (values[fieldKey] as Map<String,
                                                  MapEntry<int, bool>>)[key]!
                                              .key,
                                          false);
                                    }
                                  }
                                }
                                someValueChanged();
                              });
                            },
                          ));
                    }) ??
                    [const SizedBox.shrink()],
                (values[fieldKey] as Map<String, MapEntry<int, bool>>?)
                            ?.values
                            .where((e) => e.value)
                            .length ==
                        1
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: IconButton(
                          onPressed: () {
                            setState(() {
                              var temp = values[fieldKey]
                                  as Map<String, MapEntry<int, bool>>;
                              // get selected category str where bool is true
                              final oldEntry = temp.entries
                                  .firstWhere((entry) => entry.value.value);
                              // generate new color, ensure it is not the same
                              int newColor = oldEntry.value.key;
                              while (oldEntry.value.key == newColor) {
                                newColor = generateRandomLightColor().value;
                              }
                              // Update entry with new color, remain selected
                              temp.update(oldEntry.key,
                                  (old) => MapEntry(newColor, old.value));
                              values[fieldKey] = temp;
                              someValueChanged();
                            });
                          },
                          icon: const Icon(Icons.format_color_fill_rounded),
                          visualDensity: VisualDensity.compact,
                          tooltip: tr('colour'),
                        ))
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
                            fn() {
                              setState(() {
                                var temp = values[fieldKey]
                                    as Map<String, MapEntry<int, bool>>;
                                temp.removeWhere((key, value) => value.value);
                                values[fieldKey] = temp;
                                someValueChanged();
                              });
                            }

                            if ((widget.items[r][e] as GeneratedFormTagInput)
                                    .deleteConfirmationMessage !=
                                null) {
                              var message =
                                  (widget.items[r][e] as GeneratedFormTagInput)
                                      .deleteConfirmationMessage!;
                              showDialog<Map<String, dynamic>?>(
                                  context: context,
                                  builder: (BuildContext ctx) {
                                    return GeneratedFormModal(
                                        title: message.key,
                                        message: message.value,
                                        items: const []);
                                  }).then((value) {
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
                        ))
                    : const SizedBox.shrink(),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: IconButton(
                      onPressed: () {
                        showDialog<Map<String, dynamic>?>(
                            context: context,
                            builder: (BuildContext ctx) {
                              return GeneratedFormModal(
                                  title: widget.items[r][e].label,
                                  items: [
                                    [
                                      GeneratedFormTextField('label',
                                          label: tr('label'))
                                    ]
                                  ]);
                            }).then((value) {
                          String? label = value?['label'];
                          if (label != null) {
                            setState(() {
                              var temp = values[fieldKey]
                                  as Map<String, MapEntry<int, bool>>?;
                              temp ??= {};
                              if (temp[label] == null) {
                                var singleSelect = (widget.items[r][e]
                                        as GeneratedFormTagInput)
                                    .singleSelect;
                                var someSelected = temp.entries
                                    .where((element) => element.value.value)
                                    .isNotEmpty;
                                temp[label] = MapEntry(
                                    generateRandomLightColor().value,
                                    !(someSelected && singleSelect));
                                values[fieldKey] = temp;
                                someValueChanged();
                              }
                            });
                          }
                        });
                      },
                      icon: const Icon(Icons.add),
                      visualDensity: VisualDensity.compact,
                      tooltip: tr('add'),
                    )),
              ],
            )
          ]);
        } else if (widget.items[r][e] is GeneratedFormSubForm) {
          List<Widget> subformColumn = [];
          for (int i = 0; i < values[fieldKey].length; i++) {
            subformColumn.add(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(
                  height: 16,
                ),
                Text(
                  '${(widget.items[r][e] as GeneratedFormSubForm).label} (${i + 1})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                GeneratedForm(
                  items: (widget.items[r][e] as GeneratedFormSubForm)
                      .items
                      .map((x) => x.map((y) {
                            y.defaultValue = values[fieldKey]?[i]?[y.key];
                            return y;
                          }).toList())
                      .toList(),
                  onValueChanges: (values, valid, isBuilding) {
                    if (valid) {
                      this.values[fieldKey]?[i] = values;
                    }
                    someValueChanged(
                        isBuilding: isBuilding, forceInvalid: !valid);
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                        style: TextButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error),
                        onPressed: (values[fieldKey].length > 0)
                            ? () {
                                var temp = List.from(values[fieldKey]);
                                temp.removeAt(i);
                                values[fieldKey] = List.from(temp);
                                someValueChanged();
                              }
                            : null,
                        label: Text(
                          '${(widget.items[r][e] as GeneratedFormSubForm).label} (${i + 1})',
                        ),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                        ))
                  ],
                ),
              ],
            ));
          }
          subformColumn.add(Padding(
            padding: EdgeInsets.only(
                bottom: values[fieldKey].length > 0 ? 24 : 0, top: 8),
            child: Row(
              children: [
                Expanded(
                    child: ElevatedButton.icon(
                        onPressed: () {
                          values[fieldKey].add(getDefaultValuesFromFormItems(
                              (widget.items[r][e] as GeneratedFormSubForm)
                                  .items));
                          someValueChanged();
                        },
                        icon: const Icon(Icons.add),
                        label: Text((widget.items[r][e] as GeneratedFormSubForm)
                            .label))),
              ],
            ),
          ));
          if (values[fieldKey].length > 0) {
            subformColumn.add(const Divider());
          }
          formInputs[r][e] = Column(children: subformColumn);
        }
      }
    }

    rows.clear();
    formInputs.asMap().entries.forEach((rowInputs) {
      if (rowInputs.key > 0) {
        rows.add([
          SizedBox(
            height: widget.items[rowInputs.key - 1][0] is GeneratedFormSwitch
                ? 8
                : 25,
          )
        ]);
      }
      List<Widget> rowItems = [];
      rowInputs.value.asMap().entries.forEach((rowInput) {
        if (rowInput.key > 0) {
          rowItems.add(const SizedBox(
            width: 20,
          ));
        }
        rowItems.add(Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
              rowInput.value,
              ...widget.items[rowInputs.key][rowInput.key].belowWidgets
            ])));
      });
      rows.add(rowItems);
    });

    return Form(
        key: _formKey,
        child: Column(
          children: [
            ...rows.map((row) => Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [...row.map((e) => e)],
                ))
          ],
        ));
  }
}
