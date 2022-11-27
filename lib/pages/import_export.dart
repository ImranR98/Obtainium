import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher_string.dart';

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

    return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: CustomScrollView(slivers: <Widget>[
          CustomAppBar(title: tr('importExport')),
          SliverFillRemaining(
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
                                            showError(
                                                tr('exportedTo', args: [path]),
                                                context);
                                          });
                                        },
                                  child: Text(tr('obtainiumExport')))),
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
                                                throw ObtainiumError(
                                                    tr('invalidInput'));
                                              }
                                              appsProvider
                                                  .importApps(data)
                                                  .then((value) {
                                                showError(
                                                    tr('importedX', args: [
                                                      plural('app', value)
                                                    ]),
                                                    context);
                                              });
                                            } else {
                                              // User canceled the picker
                                            }
                                          }).catchError((e) {
                                            showError(e, context);
                                          }).whenComplete(() {
                                            setState(() {
                                              importInProgress = false;
                                            });
                                          });
                                        },
                                  child: Text(tr('obtainiumImport'))))
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
                                          title: tr('importFromURLList'),
                                          items: [
                                            [
                                              GeneratedFormItem(
                                                  label: tr('appURLList'),
                                                  max: 7,
                                                  additionalValidators: [
                                                    (String? value) {
                                                      if (value != null &&
                                                          value.isNotEmpty) {
                                                        var lines = value
                                                            .trim()
                                                            .split('\n');
                                                        for (int i = 0;
                                                            i < lines.length;
                                                            i++) {
                                                          try {
                                                            sourceProvider
                                                                .getSource(
                                                                    lines[i]);
                                                          } catch (e) {
                                                            return '${tr('line')} ${i + 1}: $e';
                                                          }
                                                        }
                                                      }
                                                      return null;
                                                    }
                                                  ])
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
                                      appsProvider
                                          .addAppsByURL(urls)
                                          .then((errors) {
                                        if (errors.isEmpty) {
                                          showError(
                                              tr('importedX', args: [
                                                plural('app', urls.length)
                                              ]),
                                              context);
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
                                        showError(e, context);
                                      }).whenComplete(() {
                                        setState(() {
                                          importInProgress = false;
                                        });
                                      });
                                    }
                                  });
                                },
                          child: Text(
                            tr('importFromURLList'),
                          )),
                      ...sourceProvider.sources
                          .where((element) => element.canSearch)
                          .map((source) => Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 8),
                                    TextButton(
                                        onPressed: importInProgress
                                            ? null
                                            : () {
                                                () async {
                                                  var values = await showDialog<
                                                          List<String>>(
                                                      context: context,
                                                      builder:
                                                          (BuildContext ctx) {
                                                        return GeneratedFormModal(
                                                          title: tr('searchX',
                                                              args: [
                                                                source
                                                                    .runtimeType
                                                                    .toString()
                                                              ]),
                                                          items: [
                                                            [
                                                              GeneratedFormItem(
                                                                  label: tr(
                                                                      'searchQuery'))
                                                            ]
                                                          ],
                                                          defaultValues: const [],
                                                        );
                                                      });
                                                  if (values != null &&
                                                      values[0].isNotEmpty) {
                                                    setState(() {
                                                      importInProgress = true;
                                                    });
                                                    var urlsWithDescriptions =
                                                        await source
                                                            .search(values[0]);
                                                    if (urlsWithDescriptions
                                                        .isNotEmpty) {
                                                      var selectedUrls =
                                                          await showDialog<
                                                                  List<
                                                                      String>?>(
                                                              context: context,
                                                              builder:
                                                                  (BuildContext
                                                                      ctx) {
                                                                return UrlSelectionModal(
                                                                  urlsWithDescriptions:
                                                                      urlsWithDescriptions,
                                                                  selectedByDefault:
                                                                      false,
                                                                );
                                                              });
                                                      if (selectedUrls !=
                                                              null &&
                                                          selectedUrls
                                                              .isNotEmpty) {
                                                        var errors =
                                                            await appsProvider
                                                                .addAppsByURL(
                                                                    selectedUrls);
                                                        if (errors.isEmpty) {
                                                          // ignore: use_build_context_synchronously
                                                          showError(
                                                              tr('importedX',
                                                                  args: [
                                                                    plural(
                                                                        'app',
                                                                        selectedUrls
                                                                            .length)
                                                                  ]),
                                                              context);
                                                        } else {
                                                          showDialog(
                                                              context: context,
                                                              builder:
                                                                  (BuildContext
                                                                      ctx) {
                                                                return ImportErrorDialog(
                                                                    urlsLength:
                                                                        selectedUrls
                                                                            .length,
                                                                    errors:
                                                                        errors);
                                                              });
                                                        }
                                                      }
                                                    } else {
                                                      throw ObtainiumError(
                                                          tr('noResults'));
                                                    }
                                                  }
                                                }()
                                                    .catchError((e) {
                                                  showError(e, context);
                                                }).whenComplete(() {
                                                  setState(() {
                                                    importInProgress = false;
                                                  });
                                                });
                                              },
                                        child: Text(tr('searchX', args: [
                                          source.runtimeType.toString()
                                        ])))
                                  ]))
                          .toList(),
                      ...sourceProvider.massUrlSources
                          .map((source) => Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 8),
                                    TextButton(
                                        onPressed: importInProgress
                                            ? null
                                            : () {
                                                () async {
                                                  var values = await showDialog(
                                                      context: context,
                                                      builder:
                                                          (BuildContext ctx) {
                                                        return GeneratedFormModal(
                                                          title: tr('importX',
                                                              args: [
                                                                source.name
                                                              ]),
                                                          items:
                                                              source
                                                                  .requiredArgs
                                                                  .map(
                                                                      (e) => [
                                                                            GeneratedFormItem(label: e)
                                                                          ])
                                                                  .toList(),
                                                          defaultValues: const [],
                                                        );
                                                      });
                                                  if (values != null) {
                                                    setState(() {
                                                      importInProgress = true;
                                                    });
                                                    var urlsWithDescriptions =
                                                        await source
                                                            .getUrlsWithDescriptions(
                                                                values);
                                                    var selectedUrls =
                                                        await showDialog<
                                                                List<String>?>(
                                                            context: context,
                                                            builder:
                                                                (BuildContext
                                                                    ctx) {
                                                              return UrlSelectionModal(
                                                                  urlsWithDescriptions:
                                                                      urlsWithDescriptions);
                                                            });
                                                    if (selectedUrls != null) {
                                                      var errors =
                                                          await appsProvider
                                                              .addAppsByURL(
                                                                  selectedUrls);
                                                      if (errors.isEmpty) {
                                                        // ignore: use_build_context_synchronously
                                                        showError(
                                                            tr('importedX',
                                                                args: [
                                                                  plural(
                                                                      'app',
                                                                      selectedUrls
                                                                          .length)
                                                                ]),
                                                            context);
                                                      } else {
                                                        showDialog(
                                                            context: context,
                                                            builder:
                                                                (BuildContext
                                                                    ctx) {
                                                              return ImportErrorDialog(
                                                                  urlsLength:
                                                                      selectedUrls
                                                                          .length,
                                                                  errors:
                                                                      errors);
                                                            });
                                                      }
                                                    }
                                                  }
                                                }()
                                                    .catchError((e) {
                                                  showError(e, context);
                                                }).whenComplete(() {
                                                  setState(() {
                                                    importInProgress = false;
                                                  });
                                                });
                                              },
                                        child: Text(
                                            tr('importX', args: [source.name])))
                                  ]))
                          .toList(),
                      const Spacer(),
                      const Divider(
                        height: 32,
                      ),
                      Text(tr('importedAppsIdDisclaimer'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontStyle: FontStyle.italic, fontSize: 12)),
                      const SizedBox(
                        height: 8,
                      )
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
      title: Text(tr('importErrors')),
      content:
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          tr('importedXOfYApps', args: [
            (widget.urlsLength - widget.errors.length).toString(),
            widget.urlsLength.toString()
          ]),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Text(
          tr('followingURLsHadErrors'),
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
            child: Text(tr('okay')))
      ],
    );
  }
}

// ignore: must_be_immutable
class UrlSelectionModal extends StatefulWidget {
  UrlSelectionModal(
      {super.key,
      required this.urlsWithDescriptions,
      this.selectedByDefault = true,
      this.onlyOneSelectionAllowed = false});

  Map<String, String> urlsWithDescriptions;
  bool selectedByDefault;
  bool onlyOneSelectionAllowed;

  @override
  State<UrlSelectionModal> createState() => _UrlSelectionModalState();
}

class _UrlSelectionModalState extends State<UrlSelectionModal> {
  Map<MapEntry<String, String>, bool> urlWithDescriptionSelections = {};
  @override
  void initState() {
    super.initState();
    for (var url in widget.urlsWithDescriptions.entries) {
      urlWithDescriptionSelections.putIfAbsent(url,
          () => widget.selectedByDefault && !widget.onlyOneSelectionAllowed);
    }
    if (widget.selectedByDefault && widget.onlyOneSelectionAllowed) {
      selectOnlyOne(widget.urlsWithDescriptions.entries.first.key);
    }
  }

  selectOnlyOne(String url) {
    for (var uwd in urlWithDescriptionSelections.keys) {
      urlWithDescriptionSelections[uwd] = uwd.key == url;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(
          widget.onlyOneSelectionAllowed ? tr('selectURL') : tr('selectURLs')),
      content: Column(children: [
        ...urlWithDescriptionSelections.keys.map((urlWithD) {
          return Row(children: [
            Checkbox(
                value: urlWithDescriptionSelections[urlWithD],
                onChanged: (value) {
                  setState(() {
                    value ??= false;
                    if (value! && widget.onlyOneSelectionAllowed) {
                      selectOnlyOne(urlWithD.key);
                    } else {
                      urlWithDescriptionSelections[urlWithD] = value!;
                    }
                  });
                }),
            const SizedBox(
              width: 8,
            ),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  height: 8,
                ),
                GestureDetector(
                    onTap: () {
                      launchUrlString(urlWithD.key,
                          mode: LaunchMode.externalApplication);
                    },
                    child: Text(
                      Uri.parse(urlWithD.key).path.substring(1),
                      style:
                          const TextStyle(decoration: TextDecoration.underline),
                      textAlign: TextAlign.start,
                    )),
                Text(
                  urlWithD.value.length > 128
                      ? '${urlWithD.value.substring(0, 128)}...'
                      : urlWithD.value,
                  style: const TextStyle(
                      fontStyle: FontStyle.italic, fontSize: 12),
                ),
                const SizedBox(
                  height: 8,
                )
              ],
            ))
          ]);
        })
      ]),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text(tr('cancel'))),
        TextButton(
            onPressed:
                urlWithDescriptionSelections.values.where((b) => b).isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pop(urlWithDescriptionSelections
                            .entries
                            .where((entry) => entry.value)
                            .map((e) => e.key.key)
                            .toList());
                      },
            child: Text(widget.onlyOneSelectionAllowed
                ? tr('pick')
                : tr('importX', args: [
                    plural(
                        'url',
                        urlWithDescriptionSelections.values
                            .where((b) => b)
                            .length)
                  ])))
      ],
    );
  }
}
