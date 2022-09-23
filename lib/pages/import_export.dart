import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

class ImportExportPage extends StatefulWidget {
  const ImportExportPage({super.key});

  @override
  State<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends State<ImportExportPage> {
  bool importInProgress = false;

  @override
  Widget build(BuildContext context) {
    SourceProvider sourceProvider = SourceProvider();
    var settingsProvider = context.read<SettingsProvider>();
    var appsProvider = context.read<AppsProvider>();
    var outlineButtonStyle = ButtonStyle(
      shape: MaterialStateProperty.all(
        StadiumBorder(
          side: BorderSide(
            width: 1,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );

    Future<List<List<String>>> addApps(List<String> urls) async {
      await settingsProvider.getInstallPermission();
      List<dynamic> results = await sourceProvider.getApps(urls);
      List<App> apps = results[0];
      Map<String, dynamic> errorsMap = results[1];
      for (var app in apps) {
        if (appsProvider.apps.containsKey(app.id)) {
          errorsMap.addAll({app.id: 'App already added'});
        } else {
          await appsProvider.saveApp(app);
        }
      }
      List<List<String>> errors =
          errorsMap.keys.map((e) => [e, errorsMap[e].toString()]).toList();
      return errors;
    }

    return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: CustomScrollView(slivers: <Widget>[
          const CustomAppBar(title: 'Import/Export'),
          SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: TextButton(
                                  style: outlineButtonStyle,
                                  onPressed: appsProvider.apps.isEmpty ||
                                          importInProgress
                                      ? null
                                      : () {
                                          HapticFeedback.selectionClick();
                                          appsProvider
                                              .exportApps()
                                              .then((String path) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                  content: Text(
                                                      'Exported to $path')),
                                            );
                                          });
                                        },
                                  child: const Text('Obtainium Export'))),
                          const SizedBox(
                            width: 16,
                          ),
                          Expanded(
                              child: TextButton(
                                  style: outlineButtonStyle,
                                  onPressed: importInProgress
                                      ? null
                                      : () {
                                          HapticFeedback.selectionClick();
                                          FilePicker.platform
                                              .pickFiles()
                                              .then((result) {
                                            setState(() {
                                              importInProgress = true;
                                            });
                                            if (result != null) {
                                              String data = File(
                                                      result.files.single.path!)
                                                  .readAsStringSync();
                                              try {
                                                jsonDecode(data);
                                              } catch (e) {
                                                throw 'Invalid input';
                                              }
                                              appsProvider
                                                  .importApps(data)
                                                  .then((value) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                      content: Text(
                                                          '$value App${value == 1 ? '' : 's'} Imported')),
                                                );
                                              });
                                            } else {
                                              // User canceled the picker
                                            }
                                          }).catchError((e) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                  content: Text(e.toString())),
                                            );
                                          }).whenComplete(() {
                                            setState(() {
                                              importInProgress = false;
                                            });
                                          });
                                        },
                                  child: const Text('Obtainium Import')))
                        ],
                      ),
                      if (importInProgress)
                        Column(
                          children: const [
                            SizedBox(
                              height: 14,
                            ),
                            LinearProgressIndicator(),
                            SizedBox(
                              height: 14,
                            ),
                          ],
                        )
                      else
                        const Divider(
                          height: 32,
                        ),
                      TextButton(
                          onPressed: importInProgress
                              ? null
                              : () {
                                  showDialog(
                                      context: context,
                                      builder: (BuildContext ctx) {
                                        return GeneratedFormModal(
                                          title: 'Import from URL List',
                                          items: [
                                            [
                                              GeneratedFormItem(
                                                  label: 'App URL List', max: 7)
                                            ]
                                          ],
                                          defaultValues: const [],
                                        );
                                      }).then((values) {
                                    if (values != null) {
                                      var urls =
                                          (values[0] as String).split('\n');
                                      setState(() {
                                        importInProgress = true;
                                      });
                                      addApps(urls).then((errors) {
                                        if (errors.isEmpty) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    'Imported ${urls.length} Apps')),
                                          );
                                        } else {
                                          showDialog(
                                              context: context,
                                              builder: (BuildContext ctx) {
                                                return ImportErrorDialog(
                                                    urlsLength: urls.length,
                                                    errors: errors);
                                              });
                                        }
                                      }).catchError((e) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(content: Text(e.toString())),
                                        );
                                      }).whenComplete(() {
                                        setState(() {
                                          importInProgress = false;
                                        });
                                      });
                                    }
                                  });
                                },
                          child: const Text(
                            'Import from URL List',
                          )),
                      ...sourceProvider.massSources
                          .map((source) => Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 8),
                                    TextButton(
                                        onPressed: importInProgress
                                            ? null
                                            : () {
                                                showDialog(
                                                    context: context,
                                                    builder:
                                                        (BuildContext ctx) {
                                                      return GeneratedFormModal(
                                                        title:
                                                            'Import ${source.name}',
                                                        items: source
                                                            .requiredArgs
                                                            .map((e) => [
                                                                  GeneratedFormItem(
                                                                      label: e)
                                                                ])
                                                            .toList(),
                                                        defaultValues: const [],
                                                      );
                                                    }).then((values) {
                                                  if (values != null) {
                                                    source
                                                        .getUrls(values)
                                                        .then((urls) {
                                                      setState(() {
                                                        importInProgress = true;
                                                      });
                                                      addApps(urls)
                                                          .then((errors) {
                                                        if (errors.isEmpty) {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                            SnackBar(
                                                                content: Text(
                                                                    'Imported ${urls.length} Apps')),
                                                          );
                                                        } else {
                                                          showDialog(
                                                              context: context,
                                                              builder:
                                                                  (BuildContext
                                                                      ctx) {
                                                                return ImportErrorDialog(
                                                                    urlsLength: urls
                                                                        .length,
                                                                    errors:
                                                                        errors);
                                                              });
                                                        }
                                                      }).whenComplete(() {
                                                        setState(() {
                                                          importInProgress =
                                                              false;
                                                        });
                                                      });
                                                    }).catchError((e) {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        SnackBar(
                                                            content: Text(
                                                                e.toString())),
                                                      );
                                                    });
                                                  }
                                                });
                                              },
                                        child: Text('Import ${source.name}'))
                                  ]))
                          .toList()
                    ],
                  )))
        ]));
  }
}

class ImportErrorDialog extends StatefulWidget {
  const ImportErrorDialog(
      {super.key, required this.urlsLength, required this.errors});

  final int urlsLength;
  final List<List<String>> errors;

  @override
  State<ImportErrorDialog> createState() => _ImportErrorDialogState();
}

class _ImportErrorDialogState extends State<ImportErrorDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Import Errors'),
      content:
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          '${widget.urlsLength - widget.errors.length} of ${widget.urlsLength} Apps imported.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Text(
          'The following URLs had errors:',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        ...widget.errors.map((e) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(
                  height: 16,
                ),
                Text(e[0]),
                Text(
                  e[1],
                  style: const TextStyle(fontStyle: FontStyle.italic),
                )
              ]);
        }).toList()
      ]),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop(null);
            },
            child: const Text('Okay'))
      ],
    );
  }
}
