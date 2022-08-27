import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    AppsProvider appsProvider = context.read<AppsProvider>();
    SettingsProvider settingsProvider = context.watch<SettingsProvider>();
    if (settingsProvider.prefs == null) {
      settingsProvider.initializeSettings();
    }
    return Padding(
        padding: const EdgeInsets.all(16),
        child: settingsProvider.prefs == null
            ? Container()
            : Column(
                children: [
                  DropdownButtonFormField(
                      decoration: const InputDecoration(labelText: 'Theme'),
                      value: settingsProvider.theme,
                      items: const [
                        DropdownMenuItem(
                          value: ThemeSettings.dark,
                          child: Text('Dark'),
                        ),
                        DropdownMenuItem(
                          value: ThemeSettings.light,
                          child: Text('Light'),
                        ),
                        DropdownMenuItem(
                          value: ThemeSettings.system,
                          child: Text('Follow System'),
                        )
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          settingsProvider.theme = value;
                        }
                      }),
                  const SizedBox(
                    height: 16,
                  ),
                  DropdownButtonFormField(
                      decoration: const InputDecoration(labelText: 'Colour'),
                      value: settingsProvider.colour,
                      items: const [
                        DropdownMenuItem(
                          value: ColourSettings.basic,
                          child: Text('Obtainium'),
                        ),
                        DropdownMenuItem(
                          value: ColourSettings.materialYou,
                          child: Text('Material You'),
                        )
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          settingsProvider.colour = value;
                        }
                      }),
                  const SizedBox(
                    height: 16,
                  ),
                  DropdownButtonFormField(
                      decoration: const InputDecoration(
                          labelText: 'Background Update Checking Interval'),
                      value: settingsProvider.updateInterval,
                      items: const [
                        DropdownMenuItem(
                          value: 15,
                          child: Text('15 Minutes'),
                        ),
                        DropdownMenuItem(
                          value: 30,
                          child: Text('30 Minutes'),
                        ),
                        DropdownMenuItem(
                          value: 60,
                          child: Text('1 Hour'),
                        ),
                        DropdownMenuItem(
                          value: 360,
                          child: Text('6 Hours'),
                        ),
                        DropdownMenuItem(
                          value: 720,
                          child: Text('12 Hours'),
                        ),
                        DropdownMenuItem(
                          value: 1440,
                          child: Text('1 Day'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          settingsProvider.updateInterval = value;
                        }
                      }),
                  const SizedBox(
                    height: 32,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      ElevatedButton(
                          onPressed: appsProvider.apps.isEmpty
                              ? null
                              : () {
                                  HapticFeedback.lightImpact();
                                  appsProvider.exportApps().then((String path) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text('Exported to $path')),
                                    );
                                  });
                                },
                          child: const Text('Export Apps')),
                      ElevatedButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            showDialog(
                                context: context,
                                builder: (BuildContext ctx) {
                                  final formKey = GlobalKey<FormState>();
                                  final jsonInputController =
                                      TextEditingController();

                                  return AlertDialog(
                                    scrollable: true,
                                    title: const Text('Import Apps'),
                                    content: Column(children: [
                                      const Text(
                                          'Copy the contents of the Obtainium export file and paste them into the field below:'),
                                      Form(
                                        key: formKey,
                                        child: TextFormField(
                                          minLines: 7,
                                          maxLines: 7,
                                          decoration: const InputDecoration(
                                              helperText:
                                                  'Obtainium export data'),
                                          controller: jsonInputController,
                                          validator: (value) {
                                            if (value == null ||
                                                value.isEmpty) {
                                              return 'Please enter your Obtainium export data';
                                            }
                                            bool isJSON = true;
                                            try {
                                              jsonDecode(value);
                                            } catch (e) {
                                              isJSON = false;
                                            }
                                            if (!isJSON) {
                                              return 'Invalid input';
                                            }
                                            return null;
                                          },
                                        ),
                                      )
                                    ]),
                                    actions: [
                                      TextButton(
                                          onPressed: () {
                                            HapticFeedback.lightImpact();
                                            Navigator.of(context).pop();
                                          },
                                          child: const Text('Cancel')),
                                      TextButton(
                                          onPressed: () {
                                            HapticFeedback.heavyImpact();
                                            if (formKey.currentState!
                                                .validate()) {
                                              appsProvider
                                                  .importApps(
                                                      jsonInputController
                                                          .value.text)
                                                  .then((value) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                      content: Text(
                                                          '$value Apps Imported')),
                                                );
                                              }).catchError((e) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                      content:
                                                          Text(e.toString())),
                                                );
                                              }).whenComplete(() {
                                                Navigator.of(context).pop();
                                              });
                                            }
                                          },
                                          child: const Text('Import')),
                                    ],
                                  );
                                });
                          },
                          child: const Text('Import Apps'))
                    ],
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        style: ButtonStyle(
                          foregroundColor:
                              MaterialStateProperty.resolveWith<Color>(
                                  (Set<MaterialState> states) {
                            return Colors.grey;
                          }),
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          launchUrlString(settingsProvider.sourceUrl,
                              mode: LaunchMode.externalApplication);
                        },
                        icon: const Icon(Icons.code),
                        label: Text(
                          'Source',
                          style: Theme.of(context).textTheme.caption,
                        ),
                      )
                    ],
                  ),
                ],
              ));
  }
}
