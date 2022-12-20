import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

enum FormItemType { string, bool }

typedef OnValueChanges = void Function(
    Map<String, String> values, bool valid, bool isBuilding);

class GeneratedFormItem {
  late String key;
  late String label;
  late FormItemType type;
  late bool required;
  late int max;
  late List<String? Function(String? value)> additionalValidators;
  late List<Widget> belowWidgets;
  late String? hint;
  late List<MapEntry<String, String>>? opts;

  GeneratedFormItem(this.key,
      {this.label = 'Input',
      this.type = FormItemType.string,
      this.required = true,
      this.max = 1,
      this.additionalValidators = const [],
      this.belowWidgets = const [],
      this.hint,
      this.opts}) {
    if (type != FormItemType.string) {
      required = false;
    }
  }
}

class GeneratedForm extends StatefulWidget {
  const GeneratedForm(
      {super.key,
      required this.items,
      required this.onValueChanges,
      required this.defaultValues});

  final List<List<GeneratedFormItem>> items;
  final OnValueChanges onValueChanges;
  final Map<String, String> defaultValues;

  @override
  State<GeneratedForm> createState() => _GeneratedFormState();
}

class _GeneratedFormState extends State<GeneratedForm> {
  final _formKey = GlobalKey<FormState>();
  Map<String, String> values = {};
  late List<List<Widget>> formInputs;
  List<List<Widget>> rows = [];

  // If any value changes, call this to update the parent with value and validity
  void someValueChanged({bool isBuilding = false}) {
    Map<String, String> returnValues = {};
    var valid = true;
    for (int r = 0; r < widget.items.length; r++) {
      for (int i = 0; i < widget.items[r].length; i++) {
        returnValues[widget.items[r][i].key] =
            values[widget.items[r][i].key] ?? '';
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
        values[e.key] = widget.defaultValues[e.key] ?? e.opts?.first.key ?? '';
      }
    }

    // Dynamically create form inputs
    formInputs = widget.items.asMap().entries.map((row) {
      return row.value.asMap().entries.map((e) {
        if (e.value.type == FormItemType.string && e.value.opts == null) {
          final formFieldKey = GlobalKey<FormFieldState>();
          return TextFormField(
            key: formFieldKey,
            initialValue: values[e.value.key],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (value) {
              setState(() {
                values[e.value.key] = value;
                someValueChanged();
              });
            },
            decoration: InputDecoration(
                helperText: e.value.label + (e.value.required ? ' *' : ''),
                hintText: e.value.hint),
            minLines: e.value.max <= 1 ? null : e.value.max,
            maxLines: e.value.max <= 1 ? 1 : e.value.max,
            validator: (value) {
              if (e.value.required && (value == null || value.trim().isEmpty)) {
                return '${e.value.label} ${tr('requiredInBrackets')}';
              }
              for (var validator in e.value.additionalValidators) {
                String? result = validator(value);
                if (result != null) {
                  return result;
                }
              }
              return null;
            },
          );
        } else if (e.value.type == FormItemType.string &&
            e.value.opts != null) {
          if (e.value.opts!.isEmpty) {
            return Text(tr('dropdownNoOptsError'));
          }
          return DropdownButtonFormField(
              decoration: InputDecoration(labelText: e.value.label),
              value: values[e.value.key],
              items: e.value.opts!
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  values[e.value.key] = value ?? e.value.opts!.first.key;
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
        if (widget.items[r][e].type == FormItemType.bool) {
          formInputs[r][e] = Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.items[r][e].label),
              Switch(
                  value: values[widget.items[r][e].key] == 'true',
                  onChanged: (value) {
                    setState(() {
                      values[widget.items[r][e].key] = value ? 'true' : '';
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
            height: widget.items[rowInputs.key][0].type == FormItemType.bool &&
                    widget.items[rowInputs.key - 1][0].type ==
                        FormItemType.string
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
