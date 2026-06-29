// The import/export flows intentionally use the page's BuildContext across
// async gaps to show dialogs/snackbars; the page stays mounted for the whole
// operation (import/export progress is shown inline). These are pre-existing,
// deliberate uses (several already had inline ignores), so suppress file-wide.
// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

Widget _actionTile({
  required IconData icon,
  required String label,
  Widget? trailing,
  required VoidCallback? onTap,
}) {
  return ListTile(
    leading: Icon(icon),
    title: Text(label),
    trailing: trailing,
    onTap: onTap,
    enabled: onTap != null,
  );
}

class ImportFromURLListPage extends StatefulWidget {
  const ImportFromURLListPage({super.key});

  @override
  State<ImportFromURLListPage> createState() => _ImportFromURLListPageState();
}

class _ImportFromURLListPageState extends State<ImportFromURLListPage> {
  final _urlController = TextEditingController();
  bool _importing = false;
  final SourceProvider _sourceProvider = SourceProvider();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _importFromFile() {
    FilePicker.pickFiles().then((result) {
      if (result != null) {
        var path = result.files.single.path;
        if (path == null) return;
        var urls = RegExp('https?://[^"]+')
            .allMatches(File(path).readAsStringSync())
            .map((e) => e.input.substring(e.start, e.end))
            .toSet()
            .toList()
            .where((url) {
              try {
                _sourceProvider.getSource(url);
                return true;
              } catch (_) {
                return false;
              }
            })
            .join('\n');
        if (mounted) {
          setState(() {
            _urlController.text = urls;
          });
        }
      }
    }).catchError((e) {
      if (mounted) {
        if (e is PlatformException || e is MissingPluginException) {
          showError(ObtainiumError(tr('noFilePickerAvailable')), context);
        } else {
          showError(e, context);
        }
      }
    });
  }

  String? _validate(String? value) {
    if (value != null && value.isNotEmpty) {
      var lines = value.trim().split('\n');
      for (int i = 0; i < lines.length; i++) {
        try {
          _sourceProvider.getSource(lines[i]);
        } catch (e) {
          return '${tr('line')} ${i + 1}: $e';
        }
      }
    }
    return null;
  }

  void _import() {
    var urls = _urlController.text.trim().split('\n').where((l) => l.isNotEmpty).toList();
    if (urls.isEmpty) return;
    final appsProvider = context.read<AppsProvider>();
    setState(() => _importing = true);
    appsProvider
        .addAppsByURL(urls)
        .then((errors) {
          if (!mounted) return;
          if (errors.isEmpty) {
            showMessage(
              tr('importedX', args: [plural('apps', urls.length).toLowerCase()]),
              context,
            );
            Navigator.of(context).pop();
          } else {
            showDialog(
              context: context,
              builder: (BuildContext ctx) {
                return ImportErrorDialog(
                  urlsLength: urls.length,
                  errors: errors,
                );
              },
            );
          }
        })
        .catchError((e) {
          if (mounted) showError(e, context);
        })
        .whenComplete(() {
          if (mounted) setState(() => _importing = false);
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(tr('importFromURLList'))),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  TextFormField(
                    controller: _urlController,
                    maxLines: null,
                    minLines: 8,
                    decoration: InputDecoration(
                      labelText: tr('appURLList'),
                      alignLabelWithText: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    validator: _validate,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                  OutlinedButton.icon(
                    onPressed: _importing ? null : _importFromFile,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(tr('importFromURLsInFile')),
                  ),
                  FilledButton(
                    onPressed: _importing ? null : _import,
                    child: _importing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(tr('import')),
                  ),
                  ConnectedCard(
                    isFirst: true,
                    isLast: true,
                    child: Text(
                      tr('importedAppsIdDisclaimer'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The app-import controls (file import, source search, URL-list import, mass
/// sources). Embedded in the Add App page (shown while no URL is entered).
class ImportSection extends StatefulWidget {
  const ImportSection({super.key});

  @override
  State<ImportSection> createState() => _ImportSectionState();
}

class _ImportSectionState extends State<ImportSection> {
  bool importInProgress = false;
  // SourceProvider is stateless and its source list is statically cached, so
  // hold one instance rather than allocating a new one on every build().
  final SourceProvider sourceProvider = SourceProvider();

  @override
  Widget build(BuildContext context) {
    var appsProvider = context.read<AppsProvider>();
    var settingsProvider = context.read<SettingsProvider>();

    runObtainiumImport() {
      settingsProvider.selectionClick();
      FilePicker.pickFiles()
          .then((result) {
            if (result == null) {
              // User canceled the picker.
              showMessage(tr('cancelled'), context);
              return;
            }
            setState(() {
              importInProgress = true;
            });
            var path = result.files.single.path;
            if (path == null) {
              throw ObtainiumError(tr('noFilePickerAvailable'));
            }
            String data = File(path).readAsStringSync();
            try {
              jsonDecode(data);
            } catch (e) {
              throw ObtainiumError(tr('invalidInput'));
            }
            appsProvider.import(data).then((value) {
              appsProvider.addMissingCategories(settingsProvider);
              showMessage(
                '${tr('importedX', args: [plural('apps', value.key.length).toLowerCase()])}${value.value ? ' + ${tr('settings').toLowerCase()}' : ''}',
                context,
              );
            });
          })
          .catchError((e) {
            if (e is PlatformException || e is MissingPluginException) {
              showError(ObtainiumError(tr('noFilePickerAvailable')), context);
            } else {
              showError(e, context);
            }
          })
          .whenComplete(() {
            setState(() {
              importInProgress = false;
            });
          });
    }

    runMassSourceImport(MassAppUrlSource source) {
      () async {
            var values = await showDialog<Map<String, dynamic>?>(
              context: context,
              builder: (BuildContext ctx) {
                return GeneratedFormModal(
                  title: tr('importX', args: [source.name]),
                  items: source.requiredArgs
                      .map((e) => [GeneratedFormTextField(e, label: e)])
                      .toList(),
                );
              },
            );
            if (values != null) {
              setState(() {
                importInProgress = true;
              });
              var urlsWithDescriptions = await source.getUrlsWithDescriptions(
                values.values.map((e) => e.toString()).toList(),
              );
              var selectedUrls = await showDialog<List<String>?>(
                context: context,
                builder: (BuildContext ctx) {
                  return SelectionModal(entries: urlsWithDescriptions);
                },
              );
              if (selectedUrls != null) {
                var errors = await appsProvider.addAppsByURL(selectedUrls);
                if (errors.isEmpty) {
                  showMessage(
                    tr(
                      'importedX',
                      args: [plural('apps', selectedUrls.length).toLowerCase()],
                    ),
                    context,
                  );
                } else {
                  showDialog(
                    context: context,
                    builder: (BuildContext ctx) {
                      return ImportErrorDialog(
                        urlsLength: selectedUrls.length,
                        errors: errors,
                      );
                    },
                  );
                }
              }
            }
          }()
          .catchError((e) {
            showError(e, context);
          })
          .whenComplete(() {
            setState(() {
              importInProgress = false;
            });
          });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (importInProgress) const LinearProgressIndicator(),
        ConnectedCard(
          isFirst: true,
          isLast: true,
          padding: null,
          child: _actionTile(
            icon: Icons.download_outlined,
            label: tr('obtainiumImport'),
            onTap: importInProgress ? null : runObtainiumImport,
          ),
        ),
        Column(
          spacing: 2,
          children: () {
            final tiles = <Widget>[
              _actionTile(
                icon: Icons.format_list_bulleted_outlined,
                label: tr('importFromURLList'),
                onTap: importInProgress
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ImportFromURLListPage(),
                          ),
                        ),
              ),
              ...sourceProvider.massUrlSources.map(
                (source) => _actionTile(
                  icon: Icons.cloud_download_outlined,
                  label: tr('importX', args: [source.name]),
                  onTap: importInProgress
                      ? null
                      : () => runMassSourceImport(source),
                ),
              ),
            ];
            return <Widget>[
              for (var i = 0; i < tiles.length; i++)
                ConnectedCard(
                  isFirst: i == 0,
                  isLast: i == tiles.length - 1,
                  padding: null,
                  child: tiles[i],
                ),
            ];
          }(),
        ),
      ],
    );
  }
}

/// The app-export controls (export dir picker, export action, auto-export and
/// settings-inclusion options). Embedded in the Settings page.
class ExportSection extends StatelessWidget {
  const ExportSection({super.key});

  @override
  Widget build(BuildContext context) {
    var appsProvider = context.read<AppsProvider>();
    var settingsProvider = context.watch<SettingsProvider>();

    runObtainiumExport({bool pickOnly = false}) async {
      settingsProvider.selectionClick();
      appsProvider
          .export(
            pickOnly:
                pickOnly || (await settingsProvider.getExportDir()) == null,
            sp: settingsProvider,
          )
          .then((String? result) {
            if (result != null) {
              showMessage(tr('exportedTo', args: [result]), context);
            }
          })
          .catchError((e) {
            showError(e, context);
          });
    }

    return FutureBuilder(
      future: settingsProvider.getExportDir(),
      builder: (context, snapshot) {
        return Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _actionTile(
                icon: Icons.folder_open_outlined,
                label: tr('pickExportDir'),
                trailing: snapshot.data != null
                    ? Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () => runObtainiumExport(pickOnly: true),
              ),
              _actionTile(
                icon: Icons.upload_outlined,
                label: tr('obtainiumExport'),
                onTap: snapshot.data == null ? null : runObtainiumExport,
              ),
              if (snapshot.data != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: GeneratedForm(
                    items: [
                      [
                        GeneratedFormSwitch(
                          'autoExportOnChanges',
                          label: tr('autoExportOnChanges'),
                          defaultValue: settingsProvider.autoExportOnChanges,
                        ),
                      ],
                      [
                        GeneratedFormDropdown(
                          'exportSettings',
                          [
                            MapEntry('0', tr('none')),
                            MapEntry('1', tr('excludeSecrets')),
                            MapEntry('2', tr('all')),
                          ],
                          label: tr('includeSettings'),
                          defaultValue: settingsProvider.exportSettings
                              .toString(),
                        ),
                      ],
                    ],
                    onValueChanges: (value, valid, isBuilding) {
                      if (valid && !isBuilding) {
                        if (value['autoExportOnChanges'] != null) {
                          settingsProvider.autoExportOnChanges =
                              value['autoExportOnChanges'] == true;
                        }
                        if (value['exportSettings'] != null) {
                          settingsProvider.exportSettings = int.parse(
                            value['exportSettings'],
                          );
                        }
                      }
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class ImportErrorDialog extends StatefulWidget {
  const ImportErrorDialog({
    super.key,
    required this.urlsLength,
    required this.errors,
  });

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
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              'importedXOfYApps',
              args: [
                (widget.urlsLength - widget.errors.length).toString(),
                widget.urlsLength.toString(),
              ],
            ),
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
                const SizedBox(height: 16),
                Text(e[0]),
                Text(e[1], style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
            );
          }),
        ],
      ),
      actions: [
        FilledButton.tonal(
          onPressed: () {
            Navigator.of(context).pop(null);
          },
          child: Text(tr('ok')),
        ),
      ],
    );
  }
}

class SelectionModal extends StatefulWidget {
  const SelectionModal({
    super.key,
    required this.entries,
    this.selectedByDefault = true,
    this.onlyOneSelectionAllowed = false,
    this.titlesAreLinks = true,
    this.title,
    this.deselectThese = const [],
  });

  final String? title;
  final Map<String, List<String>> entries;
  final bool selectedByDefault;
  final List<String> deselectThese;
  final bool onlyOneSelectionAllowed;
  final bool titlesAreLinks;

  @override
  State<SelectionModal> createState() => _SelectionModalState();
}

class _SelectionModalState extends State<SelectionModal> {
  Map<MapEntry<String, List<String>>, bool> entrySelections = {};
  String filterRegex = '';
  @override
  void didUpdateWidget(SelectionModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entries != oldWidget.entries ||
        widget.selectedByDefault != oldWidget.selectedByDefault ||
        widget.deselectThese != oldWidget.deselectThese) {
      entrySelections.clear();
      for (var entry in widget.entries.entries) {
        entrySelections.putIfAbsent(
          entry,
          () =>
              widget.selectedByDefault &&
              !widget.onlyOneSelectionAllowed &&
              !widget.deselectThese.contains(entry.key),
        );
      }
      if (widget.selectedByDefault && widget.onlyOneSelectionAllowed) {
        selectOnlyOne(widget.entries.entries.first.key);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    for (var entry in widget.entries.entries) {
      entrySelections.putIfAbsent(
        entry,
        () =>
            widget.selectedByDefault &&
            !widget.onlyOneSelectionAllowed &&
            !widget.deselectThese.contains(entry.key),
      );
    }
    if (widget.selectedByDefault && widget.onlyOneSelectionAllowed) {
      selectOnlyOne(widget.entries.entries.first.key);
    }
  }

  void selectOnlyOne(String url) {
    for (var e in entrySelections.keys) {
      entrySelections[e] = e.key == url;
    }
  }

  void selectAll({bool deselect = false}) {
    for (var e in entrySelections.keys) {
      entrySelections[e] = !deselect;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTV = context.read<SettingsProvider>().isTV;
    Map<MapEntry<String, List<String>>, bool> filteredEntrySelections = {};
    entrySelections.forEach((key, value) {
      var searchableText = key.value.isEmpty ? key.key : key.value[0];
      if (filterRegex.isEmpty || RegExp(filterRegex).hasMatch(searchableText)) {
        filteredEntrySelections.putIfAbsent(key, () => value);
      }
    });
    if (filterRegex.isNotEmpty && filteredEntrySelections.isEmpty) {
      entrySelections.forEach((key, value) {
        var searchableText = key.value.isEmpty ? key.key : key.value[0];
        if (filterRegex.isEmpty ||
            RegExp(
              filterRegex,
              caseSensitive: false,
            ).hasMatch(searchableText)) {
          filteredEntrySelections.putIfAbsent(key, () => value);
        }
      });
    }
    getSelectAllButton() {
      if (widget.onlyOneSelectionAllowed) {
        return SizedBox.shrink();
      }
      var noneSelected = entrySelections.values.where((v) => v == true).isEmpty;
      return noneSelected
          ? TextButton(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onPressed: () {
                setState(() {
                  selectAll();
                });
              },
              child: Text(tr('selectAll')),
            )
          : TextButton(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onPressed: () {
                setState(() {
                  selectAll(deselect: true);
                });
              },
              child: Text(tr('deselectX', args: [''])),
            );
    }

    final selectedRadioKey = entrySelections.entries
        .where((e) => e.value)
        .map((e) => e.key.key)
        .firstOrNull;
    void onRadioChanged(String? value) {
      if (value == null) return;
      if (isTV) {
        Navigator.of(context).pop([value]);
      } else {
        setState(() {
          selectOnlyOne(value);
        });
      }
    }

    return AlertDialog(
      scrollable: true,
      title: Text(widget.title ?? tr('pick')),
      content: RadioGroup<String>(
        groupValue: selectedRadioKey,
        onChanged: onRadioChanged,
        child: Column(
          children: [
            GeneratedForm(
              items: [
                [
                  GeneratedFormTextField(
                    'filter',
                    label: tr('filter'),
                    required: false,
                    additionalValidators: [
                      (value) {
                        return regExValidator(value);
                      },
                    ],
                  ),
                ],
              ],
              onValueChanges: (value, valid, isBuilding) {
                if (valid && !isBuilding) {
                  if (value['filter'] != null) {
                    setState(() {
                      filterRegex = value['filter'];
                    });
                  }
                }
              },
            ),
            ...filteredEntrySelections.keys.map((entry) {
              selectThis(bool? value) {
                setState(() {
                  value ??= false;
                  if (value! && widget.onlyOneSelectionAllowed) {
                    selectOnlyOne(entry.key);
                  } else {
                    entrySelections[entry] = value!;
                  }
                });
              }

              var urlLink = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.titlesAreLinks)
                    LinkText(
                      text: entry.value.isEmpty ? entry.key : entry.value[0],
                      url: entry.key,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )
                  else
                    Text(
                      entry.value.isEmpty ? entry.key : entry.value[0],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.start,
                    ),
                  if (widget.titlesAreLinks)
                    Text(
                      Uri.parse(entry.key).host,
                      style: const TextStyle(
                        decoration: TextDecoration.underline,
                        fontSize: 12,
                      ),
                    ),
                ],
              );

              var descriptionText = entry.value.length <= 1
                  ? const SizedBox.shrink()
                  : Text(
                      entry.value[1].length > 128
                          ? '${entry.value[1].substring(0, 128)}...'
                          : entry.value[1],
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                      ),
                    );

              var singleSelectTile = ListTile(
                title: InkWell(
                  onTap: widget.titlesAreLinks
                      ? null
                      : () {
                          selectThis(!(entrySelections[entry] ?? false));
                        },
                  child: urlLink,
                ),
                subtitle: entry.value.length <= 1
                    ? null
                    : InkWell(
                        onTap: () {
                          setState(() {
                            selectOnlyOne(entry.key);
                          });
                        },
                        child: descriptionText,
                      ),
                leading: Radio<String>(value: entry.key),
              );

              var multiSelectTile = Row(
                children: [
                  Checkbox(
                    value: entrySelections[entry],
                    onChanged: (value) {
                      selectThis(value);
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: widget.titlesAreLinks
                              ? null
                              : () {
                                  selectThis(
                                    !(entrySelections[entry] ?? false),
                                  );
                                },
                          child: urlLink,
                        ),
                        entry.value.length <= 1
                            ? const SizedBox.shrink()
                            : InkWell(
                                onTap: () {
                                  selectThis(
                                    !(entrySelections[entry] ?? false),
                                  );
                                },
                                child: descriptionText,
                              ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              );

              return widget.onlyOneSelectionAllowed
                  ? singleSelectTile
                  : multiSelectTile;
            }),
            if (isTV && !widget.onlyOneSelectionAllowed) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(tr('cancel')),
                  ),
                  TextButton(
                    onPressed: entrySelections.values.where((b) => b).isEmpty
                        ? null
                        : () => Navigator.of(context).pop(
                            entrySelections.entries
                                .where((entry) => entry.value)
                                .map((e) => e.key.key)
                                .toList(),
                          ),
                    child: Text(
                      tr(
                        'selectX',
                        args: [
                          entrySelections.values
                              .where((b) => b)
                              .length
                              .toString(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        getSelectAllButton(),
        TextButton(
          autofocus: isTV,
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(tr('cancel')),
        ),
        FilledButton(
          onPressed: entrySelections.values.where((b) => b).isEmpty
              ? null
              : () {
                  Navigator.of(context).pop(
                    entrySelections.entries
                        .where((entry) => entry.value)
                        .map((e) => e.key.key)
                        .toList(),
                  );
                },
          child: Text(
            widget.onlyOneSelectionAllowed
                ? tr('pick')
                : tr(
                    'selectX',
                    args: [
                      entrySelections.values.where((b) => b).length.toString(),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
