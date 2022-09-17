import 'dart:convert';
import 'dart:ui';

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

  Future<List<List<String>>> addApps(
      MassAppSource source,
      List<String> args,
      SourceProvider sourceProvider,
      SettingsProvider settingsProvider,
      AppsProvider appsProvider) async {
    var urls = await source.getUrls(args);
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

  @override
  Widget build(BuildContext context) {
    SourceProvider sourceProvider = SourceProvider();
    var settingsProvider = context.read<SettingsProvider>();
    var appsProvider = context.read<AppsProvider>();
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
                onPressed: appsProvider.apps.isEmpty
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
                onPressed: () {
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
            const Divider(
              height: 32,
            ),
            ...sourceProvider.massSources
                .map((source) => TextButton(
                    onPressed: () {
                      showDialog(
                          context: context,
                          builder: (BuildContext ctx) {
                            return GeneratedFormModal(
                                title: 'Import ${source.name}',
                                items: source.requiredArgs
                                    .map((e) => GeneratedFormItem(e, true, 1))
                                    .toList());
                          }).then((values) {
                        if (values != null) {
                          source.getUrls(values).then((urls) {
                            addApps(source, values, sourceProvider,
                                    settingsProvider, appsProvider)
                                .then((errors) {
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
                                      return AlertDialog(
                                        scrollable: true,
                                        title: const Text('Import Errors'),
                                        content: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                '${urls.length - errors.length} of ${urls.length} Apps imported.',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge,
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                'The following Apps had errors:',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge,
                                              ),
                                              ...errors.map((e) {
                                                return Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      const SizedBox(
                                                        height: 16,
                                                      ),
                                                      Text(e[0]),
                                                      Text(
                                                        e[1],
                                                        style: const TextStyle(
                                                            fontStyle: FontStyle
                                                                .italic),
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
                                    });
                              }
                            });
                          }).catchError((e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())),
                            );
                          });
                        }
                      });
                    },
                    child: Text('Import ${source.name}')))
                .toList()
          ],
        ));
  }
}
