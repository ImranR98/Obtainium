import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GeneratedFormItem {
  late String message;
  late bool required;

  GeneratedFormItem(this.message, this.required);
}

class GeneratedFormModal extends StatefulWidget {
  const GeneratedFormModal(
      {super.key, required this.title, required this.items});

  final String title;
  final List<GeneratedFormItem> items;

  @override
  State<GeneratedFormModal> createState() => _GeneratedFormModalState();
}

class _GeneratedFormModalState extends State<GeneratedFormModal> {
  final _formKey = GlobalKey<FormState>();

  final urlInputController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final formInputs = widget.items.map((e) {
      final controller = TextEditingController();
      return [
        controller,
        TextFormField(
          decoration: InputDecoration(helperText: e.message),
          controller: controller,
          validator: e.required
              ? (value) {
                  if (value == null || value.isEmpty) {
                    return '${e.message} (required)';
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
              HapticFeedback.lightImpact();
              Navigator.of(context).pop(null);
            },
            child: const Text('Cancel')),
        TextButton(
            onPressed: () {
              if (_formKey.currentState?.validate() == true) {
                HapticFeedback.heavyImpact();
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