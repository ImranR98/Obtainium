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
    [GeneratedFormItem('Test Item', FormItemType.string, true, 1)]
  ];

  void onSourceSpecificDataChanges(
      List<List<String?>> valuesFromForm, bool formValid) {
    setState(() {
      sourceSpecificData = valuesFromForm;
      valid = formValid;
      print(sourceSpecificData?[0][0]);
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
