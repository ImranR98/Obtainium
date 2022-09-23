import 'package:flutter/material.dart';
import 'package:obtainium/components/generated_form.dart';

class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  List<List<String?>>? sourceSpecificData;
  bool valid = false;

  List<List<GeneratedFormItem>> sourceSpecificInputs = [
    [GeneratedFormItem(label: 'Test Item 1')],
    [
      GeneratedFormItem(label: 'Test Item 2', required: false),
      GeneratedFormItem(label: 'Test Item 3')
    ],
    [GeneratedFormItem(label: 'Test Item 4', type: FormItemType.bool)]
  ];

  void onSourceSpecificDataChanges(
      List<List<String?>> valuesFromForm, bool formValid) {
    setState(() {
      sourceSpecificData = valuesFromForm;
      valid = formValid;
      sourceSpecificData?.forEach((row) {
        for (var element in row) {
          print(element);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Test Page')),
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GeneratedForm(
            items: sourceSpecificInputs,
            onValueChanges: onSourceSpecificDataChanges,
          ),
        ));
  }
}
