import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

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
