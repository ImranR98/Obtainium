import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';

class ImportExportPage extends StatefulWidget {
  const ImportExportPage({super.key});

  @override
  State<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends State<ImportExportPage> {
  bool gettingAppInfo = false;

  @override
  Widget build(BuildContext context) {
    SourceProvider sourceProvider = SourceProvider();
    var settingsProvider = context.read<SettingsProvider>();
    var appsProvider = context.read<AppsProvider>();

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

    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
                onPressed: appsProvider.apps.isEmpty || gettingAppInfo
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        appsProvider.exportApps().then((String path) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Exported to $path')),
                          );
                        });
                      },
                child: const Text('Obtainium Export')),
            const SizedBox(
              height: 8,
            ),
            ElevatedButton(
                onPressed: gettingAppInfo
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        showDialog(
                            context: context,
                            builder: (BuildContext ctx) {
                              return GeneratedFormModal(
                                  title: 'Obtainium Import',
                                  items: [
                                    GeneratedFormItem(
                                        'Obtainium Export JSON Data', true, 7)
                                  ]);
                            }).then((values) {
                          if (values != null) {
                            try {
                              jsonDecode(values[0]);
                            } catch (e) {
                              throw 'Invalid input';
                            }
                            appsProvider.importApps(values[0]).then((value) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        '$value App${value == 1 ? '' : 's'} Imported')),
                              );
                            });
                          }
                        }).catchError((e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString())),
                          );
                        });
                      },
                child: const Text('Obtainium Import')),
            if (gettingAppInfo)
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
                onPressed: gettingAppInfo
                    ? null
                    : () {
                        showDialog(
                            context: context,
                            builder: (BuildContext ctx) {
                              return GeneratedFormModal(
                                title: 'Import from URL List',
                                items: [
                                  GeneratedFormItem('App URL List', true, 7)
                                ],
                              );
                            }).then((values) {
                          if (values != null) {
                            var urls = (values[0] as String).split('\n');
                            setState(() {
                              gettingAppInfo = true;
                            });
                            addApps(urls).then((errors) {
                              if (errors.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('Imported ${urls.length} Apps')),
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }).whenComplete(() {
                              setState(() {
                                gettingAppInfo = false;
                              });
                            });
                          }
                        });
                      },
                child: const Text('Import from URL List')),
            ...sourceProvider.massSources
                .map((source) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          TextButton(
                              onPressed: gettingAppInfo
                                  ? null
                                  : () {
                                      showDialog(
                                          context: context,
                                          builder: (BuildContext ctx) {
                                            return GeneratedFormModal(
                                                title: 'Import ${source.name}',
                                                items: source.requiredArgs
                                                    .map((e) =>
                                                        GeneratedFormItem(
                                                            e, true, 1))
                                                    .toList());
                                          }).then((values) {
                                        if (values != null) {
                                          source.getUrls(values).then((urls) {
                                            setState(() {
                                              gettingAppInfo = true;
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
                                                    builder:
                                                        (BuildContext ctx) {
                                                      return ImportErrorDialog(
                                                          urlsLength:
                                                              urls.length,
                                                          errors: errors);
                                                    });
                                              }
                                            }).whenComplete(() {
                                              setState(() {
                                                gettingAppInfo = false;
                                              });
                                            });
                                          }).catchError((e) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                  content: Text(e.toString())),
                                            );
                                          });
                                        }
                                      });
                                    },
                              child: Text('Import ${source.name}'))
                        ]))
                .toList()
          ],
        ));
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
              HapticFeedback.lightImpact();
              Navigator.of(context).pop(null);
            },
            child: const Text('Okay'))
      ],
    );
  }
}
