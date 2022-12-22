import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/providers/settings_provider.dart';

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

  GeneratedFormTextField(String key,
      {String label = 'Input',
      List<Widget> belowWidgets = const [],
      String defaultValue = '',
      List<String? Function(String? value)> additionalValidators = const [],
      this.required = true,
      this.max = 1,
      this.hint})
      : super(key,
            label: label,
            belowWidgets: belowWidgets,
            defaultValue: defaultValue,
            additionalValidators: additionalValidators);

  @override
  String ensureType(val) {
    return val.toString();
  }
}

class GeneratedFormDropdown extends GeneratedFormItem {
  late List<MapEntry<String, String>>? opts;

  GeneratedFormDropdown(
    String key,
    this.opts, {
    String label = 'Input',
    List<Widget> belowWidgets = const [],
    String defaultValue = '',
    List<String? Function(String? value)> additionalValidators = const [],
  }) : super(key,
            label: label,
            belowWidgets: belowWidgets,
            defaultValue: defaultValue,
            additionalValidators: additionalValidators);

  @override
  String ensureType(val) {
    return val.toString();
  }
}

class GeneratedFormSwitch extends GeneratedFormItem {
  GeneratedFormSwitch(
    String key, {
    String label = 'Input',
    List<Widget> belowWidgets = const [],
    bool defaultValue = false,
    List<String? Function(bool value)> additionalValidators = const [],
  }) : super(key,
            label: label,
            belowWidgets: belowWidgets,
            defaultValue: defaultValue,
            additionalValidators: additionalValidators);

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
  GeneratedFormTagInput(String key,
      {String label = 'Input',
      List<Widget> belowWidgets = const [],
      Map<String, MapEntry<int, bool>> defaultValue = const {},
      List<String? Function(Map<String, MapEntry<int, bool>> value)>
          additionalValidators = const [],
      this.deleteConfirmationMessage,
      this.singleSelect = false,
      this.alignment = WrapAlignment.start,
      this.emptyMessage = 'Input'})
      : super(key,
            label: label,
            belowWidgets: belowWidgets,
            defaultValue: defaultValue,
            additionalValidators: additionalValidators);

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

class _GeneratedFormState extends State<GeneratedForm> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic> values = {};
  late List<List<Widget>> formInputs;
  List<List<Widget>> rows = [];

  // If any value changes, call this to update the parent with value and validity
  void someValueChanged({bool isBuilding = false}) {
    Map<String, dynamic> returnValues = values;
    var valid = true;
    for (int r = 0; r < widget.items.length; r++) {
      for (int i = 0; i < widget.items[r].length; i++) {
        if (formInputs[r][i] is TextFormField) {
          valid = valid &&
              ((formInputs[r][i].key as GlobalKey<FormFieldState>)
                      .currentState
                      ?.isValid ??
                  false);
        }
      }
    }
    widget.onValueChanges(returnValues, valid, isBuilding);
  }

  // Generates a random light color
// Courtesy of ChatGPT 😭 (with a bugfix 🥳)
  Color generateRandomLightColor() {
    // Create a random number generator
    final Random random = Random();

    // Generate random hue, saturation, and value values
    final double hue = random.nextDouble() * 360;
    final double saturation = 0.5 + random.nextDouble() * 0.5;
    final double value = 0.9 + random.nextDouble() * 0.1;

    // Create a HSV color with the random values
    return HSVColor.fromAHSV(1.0, hue, saturation, value).toColor();
  }

  @override
  void initState() {
    super.initState();

    // Initialize form values as all empty
    values.clear();
    int j = 0;
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
              items: formItem.opts!
                  .map((e2) =>
                      DropdownMenuItem(value: e2.key, child: Text(e2.value)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  values[formItem.key] = value ?? formItem.opts!.first.key;
                  someValueChanged();
                });
              });
        } else {
          return Container(); // Some input types added in build
        }
      }).toList();
    }).toList();
    someValueChanged(isBuilding: true);
  }

  @override
  Widget build(BuildContext context) {
    for (var r = 0; r < formInputs.length; r++) {
      for (var e = 0; e < formInputs[r].length; e++) {
        if (widget.items[r][e] is GeneratedFormSwitch) {
          formInputs[r][e] = Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.items[r][e].label),
              Switch(
                  value: values[widget.items[r][e].key],
                  onChanged: (value) {
                    setState(() {
                      values[widget.items[r][e].key] = value;
                      someValueChanged();
                    });
                  })
            ],
          );
        } else if (widget.items[r][e] is GeneratedFormTagInput) {
          formInputs[r][e] = Wrap(
            alignment: (widget.items[r][e] as GeneratedFormTagInput).alignment,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              (values[widget.items[r][e].key]
                              as Map<String, MapEntry<int, bool>>?)
                          ?.isEmpty ==
                      true
                  ? Text(
                      (widget.items[r][e] as GeneratedFormTagInput)
                          .emptyMessage,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )
                  : const SizedBox.shrink(),
              ...(values[widget.items[r][e].key]
                          as Map<String, MapEntry<int, bool>>?)
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
                              (values[widget.items[r][e].key] as Map<String,
                                      MapEntry<int, bool>>)[e2.key] =
                                  MapEntry(
                                      (values[widget.items[r][e].key] as Map<
                                              String,
                                              MapEntry<int, bool>>)[e2.key]!
                                          .key,
                                      value);
                              if ((widget.items[r][e] as GeneratedFormTagInput)
                                      .singleSelect &&
                                  value == true) {
                                for (var key in (values[widget.items[r][e].key]
                                        as Map<String, MapEntry<int, bool>>)
                                    .keys) {
                                  if (key != e2.key) {
                                    (values[widget.items[r][e].key] as Map<
                                        String,
                                        MapEntry<int,
                                            bool>>)[key] = MapEntry(
                                        (values[widget.items[r][e].key] as Map<
                                                String,
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
              (values[widget.items[r][e].key]
                              as Map<String, MapEntry<int, bool>>?)
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
                              var temp = values[widget.items[r][e].key]
                                  as Map<String, MapEntry<int, bool>>;
                              temp.removeWhere((key, value) => value.value);
                              values[widget.items[r][e].key] = temp;
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
                            var temp = values[widget.items[r][e].key]
                                as Map<String, MapEntry<int, bool>>?;
                            temp ??= {};
                            var singleSelect =
                                (widget.items[r][e] as GeneratedFormTagInput)
                                    .singleSelect;
                            var someSelected = temp.entries
                                .where((element) => element.value.value)
                                .isNotEmpty;
                            temp[label] = MapEntry(
                                generateRandomLightColor().value,
                                !(someSelected && singleSelect));
                            values[widget.items[r][e].key] = temp;
                            someValueChanged();
                          });
                        }
                      });
                    },
                    icon: const Icon(Icons.add),
                    visualDensity: VisualDensity.compact,
                    tooltip: tr('add'),
                  )),
            ],
          );
        }
      }
    }

    rows.clear();
    formInputs.asMap().entries.forEach((rowInputs) {
      if (rowInputs.key > 0) {
        rows.add([
          SizedBox(
            height: widget.items[rowInputs.key][0] is GeneratedFormSwitch &&
                    widget.items[rowInputs.key - 1][0] is! GeneratedFormSwitch
                ? 25
                : 8,
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
