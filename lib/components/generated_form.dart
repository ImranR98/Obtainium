import 'package:flutter/material.dart';

enum FormItemType { string, bool }

typedef OnValueChanges = void Function(List<List<String?>> values, bool valid);

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
      {super.key, required this.items, required this.onValueChanges});

  final List<List<GeneratedFormItem>> items;
  final OnValueChanges onValueChanges;

  @override
  State<GeneratedForm> createState() => _GeneratedFormState();
}

class _GeneratedFormState extends State<GeneratedForm> {
  final _formKey = GlobalKey<FormState>();
  late List<List<String?>> values;
  late List<List<Widget>> formInputs;
  List<List<Widget>> rows = [];

  @override
  void initState() {
    super.initState();

    // Initialize form values as all empty
    values = widget.items.map((row) => row.map((e) => "").toList()).toList();

    // If any value changes, call this to update the parent with value and validity
    void someValueChanged() {
      widget.onValueChanges(values, _formKey.currentState?.validate() ?? false);
    }

    // Dynamically create form inputs
    formInputs = widget.items.asMap().entries.map((row) {
      return row.value.asMap().entries.map((e) {
        if (e.value.type == FormItemType.string) {
          final controller =
              TextEditingController(text: values[row.key][e.key]);
          controller.addListener(() {
            // Each time an input value changes, update the results and send to parent
            values[row.key][e.key] = controller.value.text;
            someValueChanged();
          });
          return TextFormField(
              decoration: InputDecoration(
                  helperText: e.value.label + (e.value.required ? " *" : "")),
              controller: controller,
              minLines: e.value.max <= 1 ? null : e.value.max,
              maxLines: e.value.max <= 1 ? 1 : e.value.max,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '${e.value.label} (required)';
                }
                return null;
              }
              // : null,
              );
        } else {
          return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(e.value.label),
                Switch(
                    value: values[row.key][e.key]?.isEmpty ?? false,
                    onChanged: (value) {
                      values[row.key][e.key] = value ? "true" : "";
                      someValueChanged();
                    })
              ]);
        }
      }).toList();
    }).toList();

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
  }

  @override
  Widget build(BuildContext context) {
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
