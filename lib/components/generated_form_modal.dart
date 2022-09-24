import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/generated_form.dart';

class GeneratedFormModal extends StatefulWidget {
  const GeneratedFormModal(
      {super.key,
      required this.title,
      required this.items,
      required this.defaultValues});

  final String title;
  final List<List<GeneratedFormItem>> items;
  final List<String> defaultValues;

  @override
  State<GeneratedFormModal> createState() => _GeneratedFormModalState();
}

class _GeneratedFormModalState extends State<GeneratedFormModal> {
  List<String> values = [];
  bool valid = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: GeneratedForm(
          items: widget.items,
          onValueChanges: (values, valid) {
            setState(() {
              this.values = values;
              this.valid = valid;
            });
          },
          defaultValues: widget.defaultValues),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop(null);
            },
            child: const Text('Cancel')),
        TextButton(
            onPressed: !valid
                ? null
                : () {
                    if (valid) {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop(values);
                    }
                  },
            child: const Text('Continue'))
      ],
    );
  }
}
