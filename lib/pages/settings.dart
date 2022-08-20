import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Center(
        child: Text(
      'No Configurable Settings Yet.',
      style: Theme.of(context).textTheme.bodyLarge,
      textAlign: TextAlign.center,
    ));
  }
}
