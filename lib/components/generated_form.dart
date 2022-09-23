import 'package:flutter/material.dart';

enum FormItemType { string, bool }

typedef OnValueChanges = void Function(List<String> values, bool valid);

class GeneratedFormItem {
  late String label;
  late FormItemType type;
  late bool required;
  late int max;

  GeneratedFormItem(
      {this.label = "Input",
      this.type = FormItemType.string,
      this.required = true,
      this.max = 1});
}

class GeneratedForm extends StatefulWidget {
  const GeneratedForm(
      {super.key,
      required this.items,
      required this.onValueChanges,
      required this.defaultValues});

  final List<List<GeneratedFormItem>> items;
  final OnValueChanges onValueChanges;
  final List<String> defaultValues;

  @override
  State<GeneratedForm> createState() => _GeneratedFormState();
}

class _GeneratedFormState extends State<GeneratedForm> {
  final _formKey = GlobalKey<FormState>();
  late List<List<String>> values;
  late List<List<Widget>> formInputs;
  List<List<Widget>> rows = [];

  @override
  void initState() {
    super.initState();

    // Initialize form values as all empty
    int j = 0;
    values = widget.items
        .map((row) => row.map((e) {
              return j < widget.defaultValues.length
                  ? widget.defaultValues[j++]
                  : "";
            }).toList())
        .toList();

    // If any value changes, call this to update the parent with value and validity
    void someValueChanged() {
      List<String> returnValues = [];
      var valid = true;
      for (int r = 0; r < values.length; r++) {
        for (int i = 0; i < values[r].length; i++) {
          returnValues.add(values[r][i]);
          if (formInputs[r][i] is TextFormField) {
            valid = valid &&
                ((formInputs[r][i].key as GlobalKey<FormFieldState>)
                        .currentState
                        ?.isValid ??
                    false);
          }
        }
      }
      widget.onValueChanges(returnValues, valid);
    }

    // Dynamically create form inputs
    formInputs = widget.items.asMap().entries.map((row) {
      return row.value.asMap().entries.map((e) {
        if (e.value.type == FormItemType.string) {
          final formFieldKey = GlobalKey<FormFieldState>();
          return TextFormField(
            key: formFieldKey,
            initialValue: values[row.key][e.key],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (value) {
              setState(() {
                values[row.key][e.key] = value;
                someValueChanged();
              });
            },
            decoration: InputDecoration(
                helperText: e.value.label + (e.value.required ? " *" : "")),
            minLines: e.value.max <= 1 ? null : e.value.max,
            maxLines: e.value.max <= 1 ? 1 : e.value.max,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '${e.value.label} (required)';
              }
              return null;
            },
          );
        } else {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(e.value.label),
              Switch(
                  value: values[row.key][e.key] != "",
                  onChanged: (value) {
                    setState(() {
                      values[row.key][e.key] = value ? "true" : "";
                      someValueChanged();
                    });
                  })
            ],
          );
        }
      }).toList();
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    rows.clear();
    formInputs.asMap().entries.forEach((rowInputs) {
      if (rowInputs.key > 0) {
        rows.add([
          SizedBox(
            height: widget.items[rowInputs.key][0].type == FormItemType.bool
                ? 25
                : 4,
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
        rowItems.add(Expanded(child: rowInput.value));
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
