import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GeneratedFormModalItem {
  late String label;
  late bool required;
  late int max;

  GeneratedFormModalItem(this.label, this.required, this.max);
}

class GeneratedFormModal extends StatefulWidget {
  const GeneratedFormModal(
      {super.key, required this.title, required this.items});

  final String title;
  final List<GeneratedFormModalItem> items;

  @override
  State<GeneratedFormModal> createState() => _GeneratedFormModalState();
}

class _GeneratedFormModalState extends State<GeneratedFormModal> {
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final formInputs = widget.items.map((e) {
      final controller = TextEditingController();
      return [
        controller,
        TextFormField(
          decoration: InputDecoration(helperText: e.label),
          controller: controller,
          minLines: e.max <= 1 ? null : e.max,
          maxLines: e.max <= 1 ? 1 : e.max,
          validator: e.required
              ? (value) {
                  if (value == null || value.isEmpty) {
                    return '${e.label} (required)';
                  }
                  return null;
                }
              : null,
        )
      ];
    }).toList();
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [...formInputs.map((e) => e[1] as Widget)],
          )),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop(null);
            },
            child: const Text('Cancel')),
        TextButton(
            onPressed: () {
              if (_formKey.currentState?.validate() == true) {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop(formInputs
                    .map((e) => (e[0] as TextEditingController).value.text)
                    .toList());
              }
            },
            child: const Text('Continue'))
      ],
    );
  }
}

// TODO: Add support for larger textarea so this can be used for text/json imports