import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/generated_form.dart';

class GeneratedFormModal extends StatefulWidget {
  const GeneratedFormModal(
      {super.key,
      required this.title,
      required this.items,
      required this.defaultValues,
      this.initValid = false,
      this.message = ''});

  final String title;
  final String message;
  final List<List<GeneratedFormItem>> items;
  final Map<String, String> defaultValues;
  final bool initValid;

  @override
  State<GeneratedFormModal> createState() => _GeneratedFormModalState();
}

class _GeneratedFormModalState extends State<GeneratedFormModal> {
  Map<String, String> values = {};
  bool valid = false;

  @override
  void initState() {
    super.initState();
    widget.defaultValues.forEach((key, value) {
      values[key] = value;
    });
    valid = widget.initValid || widget.items.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content:
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.message.isNotEmpty) Text(widget.message),
        if (widget.message.isNotEmpty)
          const SizedBox(
            height: 16,
          ),
        GeneratedForm(
            items: widget.items,
            onValueChanges: (values, valid, isBuilding) {
              if (isBuilding) {
                this.values = values;
                this.valid = valid;
              } else {
                setState(() {
                  this.values = values;
                  this.valid = valid;
                });
              }
            },
            defaultValues: widget.defaultValues)
      ]),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop(null);
            },
            child: Text(tr('cancel'))),
        TextButton(
            onPressed: !valid
                ? null
                : () {
                    if (valid) {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop(values);
                    }
                  },
            child: Text(tr('continue')))
      ],
    );
  }
}
