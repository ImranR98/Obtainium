import 'package:flutter/material.dart';

enum FormItemType { string, bool }

typedef OnValueChanges = void Function(
    List<String> values, bool valid, bool isBuilding);

class GeneratedFormItem {
  late String label;
  late FormItemType type;
  late bool required;
  late int max;
  late List<String? Function(String? value)> additionalValidators;
  late String id;
  late List<Widget> belowWidgets;
  late String? hint;
  late List<String>? opts;

  GeneratedFormItem(
      {this.label = 'Input',
      this.type = FormItemType.string,
      this.required = true,
      this.max = 1,
      this.additionalValidators = const [],
      this.id = 'input',
      this.belowWidgets = const [],
      this.hint,
      this.opts});
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

  // If any value changes, call this to update the parent with value and validity
  void someValueChanged({bool isBuilding = false}) {
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
    widget.onValueChanges(returnValues, valid, isBuilding);
  }

  @override
  void initState() {
    super.initState();

    // Initialize form values as all empty
    int j = 0;
    values = widget.items
        .map((row) => row.map((e) {
              return j < widget.defaultValues.length
                  ? widget.defaultValues[j++]
                  : e.opts != null
                      ? e.opts!.first
                      : '';
            }).toList())
        .toList();

    // Dynamically create form inputs
    formInputs = widget.items.asMap().entries.map((row) {
      return row.value.asMap().entries.map((e) {
        if (e.value.type == FormItemType.string && e.value.opts == null) {
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
                helperText: e.value.label + (e.value.required ? ' *' : ''),
                hintText: e.value.hint),
            minLines: e.value.max <= 1 ? null : e.value.max,
            maxLines: e.value.max <= 1 ? 1 : e.value.max,
            validator: (value) {
              if (e.value.required && (value == null || value.trim().isEmpty)) {
                return '${e.value.label} (required)';
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
            return const Text('ERROR: DROPDOWN MUST HAVE AT LEAST ONE OPT.');
          }
          return DropdownButtonFormField(
              decoration: const InputDecoration(labelText: 'Colour'),
              value: values[row.key][e.key],
              items: e.value.opts!
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  values[row.key][e.key] = value ?? e.value.opts!.first;
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
                  value: values[r][e] == 'true',
                  onChanged: (value) {
                    setState(() {
                      values[r][e] = value ? 'true' : '';
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
