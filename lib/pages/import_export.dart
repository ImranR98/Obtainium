import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

class ImportFromURLListPage extends StatefulWidget {
  const ImportFromURLListPage({super.key});

  @override
  State<ImportFromURLListPage> createState() => _ImportFromURLListPageState();
}

class _ImportFromURLListPageState extends State<ImportFromURLListPage> {
  late ImportFromURLListController _controller;

  @override
  void initState() {
    super.initState();
    final sp = context.read<SourceProvider>();
    _controller = ImportFromURLListController(sourceProvider: sp);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _import() {
    final urls = _controller.getURLs();
    if (urls.isEmpty) return;
    final appsProvider = context.read<AppsProvider>();
    _controller.setImporting(true);
    appsProvider
        .addAppsByURL(urls)
        .then((errors) {
          if (!mounted) return;
          _controller.setImporting(false);
          if (errors.isEmpty) {
            showMessage(
              tr(
                'importedX',
                args: [plural('apps', urls.length).toLowerCase()],
              ),
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
          if (mounted) {
            _controller.setImporting(false);
            showError(e, context);
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Builder(
        builder: (context) {
          final controller = context.watch<ImportFromURLListController>();
          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  automaticallyImplyLeading: false,
                  title: Text(tr('importFromURLList')),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      MediaQuery.of(context).padding.bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 16,
                      children: [
                        ConnectedCard(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: TextFormField(
                            controller: controller.urlController,
                            maxLines: null,
                            minLines: 8,
                            decoration: InputDecoration(
                                labelText: tr('appURLList')),
                            validator: controller.validate,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: controller.isImporting
                              ? null
                              : () => controller.importFromFile(context),
                          icon: const Icon(Icons.upload_file_outlined),
                          label: Text(tr('importFromURLsInFile')),
                        ),
                        FilledButton(
                          onPressed: controller.isImporting ? null : _import,
                          child: controller.isImporting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(),
                                )
                              : Text(tr('import')),
                        ),
                        ConnectedCard(
                          isFirst: true,
                          isLast: true,
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            tr('importedAppsIdDisclaimer'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
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

  @override
  Widget build(BuildContext context) {
    final appsProvider = context.read<AppsProvider>();
    final settingsProvider = context.read<SettingsProvider>();

    void runObtainiumImport() {
      settingsProvider.selectionClick();
      FilePicker.pickFiles()
          .then((result) async {
            if (result == null) {
              if (!context.mounted) return;
              showMessage(tr('cancelled'), context);
              return;
            }
            if (result.files.isEmpty) {
              return;
            }
            if (mounted) {
              setState(() {
                importInProgress = true;
              });
            }
            final path = result.files.single.path;
            if (path == null) {
              throw ObtainiumError(tr('noFilePickerAvailable'));
            }
            final String data = await File(path).readAsString();
            try {
              jsonDecode(data);
            } catch (e) {
              throw ObtainiumError(tr('invalidInput'));
            }
            final value = await appsProvider.import(data);
            appsProvider.addMissingCategories(settingsProvider);
            if (!context.mounted) return;
            showMessage(
              '${tr('importedX', args: [plural('apps', value.key.length).toLowerCase()])}${value.value ? ' + ${tr('settings').toLowerCase()}' : ''}',
              context,
            );
          })
          .catchError((e) {
            if (!context.mounted) return;
            _showImportError(e, context);
          })
          .whenComplete(() {
            if (mounted) {
              setState(() {
                importInProgress = false;
              });
            }
          });
    }

    Future<void> runMassSourceImport(MassAppUrlSource source) async {
      try {
        final values = await showDialog<Map<String, dynamic>?>(
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
          if (mounted) {
            setState(() {
              importInProgress = true;
            });
          }
          final urlsWithDescriptions = await source.getUrlsWithDescriptions(
            values.values.map((e) => e.toString()).toList(),
          );
          if (!context.mounted) return;
          final selectedUrls = await showDialog<List<String>?>(
            context: context,
            builder: (BuildContext ctx) {
              return SelectionModal(entries: urlsWithDescriptions);
            },
          );
          if (selectedUrls != null) {
            final errors = await appsProvider.addAppsByURL(selectedUrls);
            if (!context.mounted) return;
            if (errors.isEmpty) {
              showMessage(
                tr(
                  'importedX',
                  args: [plural('apps', selectedUrls.length).toLowerCase()],
                ),
                context,
              );
            } else {
              unawaited(
                showDialog(
                  context: context,
                  builder: (BuildContext ctx) {
                    return ImportErrorDialog(
                      urlsLength: selectedUrls.length,
                      errors: errors,
                    );
                  },
                ),
              );
            }
          }
        }
      } catch (e) {
        if (!context.mounted) return;
        showError(e, context);
      } finally {
        if (mounted) {
          setState(() {
            importInProgress = false;
          });
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (importInProgress) const LinearProgressIndicator(),
        ConnectedCard(
          isFirst: true,
          isLast: true,
          child: ActionListTile(
            icon: Icons.download_outlined,
            label: tr('obtainiumImport'),
            onTap: importInProgress ? null : runObtainiumImport,
          ),
        ),
        Column(
          spacing: 2,
          children: () {
            final tiles = <Widget>[
              ActionListTile(
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
              ...context.read<SourceProvider>().massUrlSources.map(
                (source) => ActionListTile(
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
class ExportSection extends StatefulWidget {
  const ExportSection({super.key});

  @override
  State<ExportSection> createState() => _ExportSectionState();
}

class _ExportSectionState extends State<ExportSection> {
  Future<Uri?>? _exportDirFuture;
  String? _lastExportDirKey;

  @override
  Widget build(BuildContext context) {
    final appsProvider = context.read<AppsProvider>();
    final settingsProvider = context.watch<SettingsProvider>();

    final exportDirKey = settingsProvider.prefs?.getString('exportDir');
    if (_exportDirFuture == null || exportDirKey != _lastExportDirKey) {
      _lastExportDirKey = exportDirKey;
      _exportDirFuture = settingsProvider.getExportDir();
    }

    Future<void> runObtainiumExport({bool pickOnly = false}) async {
      settingsProvider.selectionClick();
      unawaited(
        appsProvider
            .export(
              pickOnly:
                  pickOnly || (await settingsProvider.getExportDir()) == null,
              sp: settingsProvider,
            )
            .then((String? result) {
              if (result != null) {
                if (!context.mounted) return;
                showMessage(tr('exportedTo', args: [result]), context);
              }
            })
            .catchError((e) {
              if (!context.mounted) return;
              showError(e, context);
            }),
      );
    }

    return FutureBuilder(
      future: _exportDirFuture,
      builder: (context, snapshot) {
        final items = <Widget>[
          ConnectedCard(
            isFirst: true,
            isLast: false,
            child: ActionListTile(
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
          ),
          ConnectedCard(
            isFirst: false,
            isLast: snapshot.data == null,
            child: ActionListTile(
              icon: Icons.upload_outlined,
              label: tr('obtainiumExport'),
              onTap: snapshot.data == null ? null : runObtainiumExport,
            ),
          ),
        ];
        if (snapshot.data != null) {
          items.addAll([
            ConnectedCard(
              isFirst: false,
              isLast: false,
              child: ToggleTile(
                label: tr('autoExportOnChanges'),
                value: settingsProvider.autoExportOnChanges,
                onChanged: (value) =>
                    settingsProvider.autoExportOnChanges = value,
              ),
            ),
            ConnectedCard(
              isFirst: false,
              isLast: true,
              child: DropdownMenu<String>(
                expandedInsets: EdgeInsets.zero,
                label: Text(tr('includeSettings')),
                initialSelection:
                    settingsProvider.exportSettings.toString(),
                dropdownMenuEntries: [
                  DropdownMenuEntry(
                      value: '0', label: tr('none')),
                  DropdownMenuEntry(
                      value: '1', label: tr('excludeSecrets')),
                  DropdownMenuEntry(
                      value: '2', label: tr('all')),
                ],
                onSelected: (value) {
                  if (value != null) {
                    settingsProvider.exportSettings =
                        int.tryParse(value) ?? 1;
                  }
                },
              ),
            ),
          ]);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 3,
          children: items,
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
          autofocus: context.read<SettingsProvider>().isTV,
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
      _resetEntrySelections();
    }
  }

  @override
  void initState() {
    super.initState();
    _resetEntrySelections();
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

  void _resetEntrySelections() {
    entrySelections.clear();
    for (var entry in widget.entries.entries) {
      entrySelections[entry] =
          widget.selectedByDefault &&
          !widget.onlyOneSelectionAllowed &&
          !widget.deselectThese.contains(entry.key);
    }
    if (widget.selectedByDefault &&
        widget.onlyOneSelectionAllowed &&
        widget.entries.entries.isNotEmpty) {
      selectOnlyOne(widget.entries.entries.first.key);
    }
  }

  Widget _buildSelectAllButton() {
    if (widget.onlyOneSelectionAllowed) {
      return const SizedBox.shrink();
    }
    final noneSelected = entrySelections.values.where((v) => v == true).isEmpty;
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

  void _selectThis(MapEntry<String, List<String>> entry, bool? value) {
    setState(() {
      value ??= false;
      if (value! && widget.onlyOneSelectionAllowed) {
        selectOnlyOne(entry.key);
      } else {
        entrySelections[entry] = value!;
      }
    });
  }

  Widget _buildUrlLink(MapEntry<String, List<String>> entry) {
    return Column(
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
  }

  Widget _buildDescriptionText(MapEntry<String, List<String>> entry) {
    return entry.value.length <= 1
        ? const SizedBox.shrink()
        : Text(
            entry.value[1].length > 128
                ? '${entry.value[1].substring(0, 128)}...'
                : entry.value[1],
            style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
          );
  }

  Widget _buildSingleSelectTile(MapEntry<String, List<String>> entry) {
    return ListTile(
      title: InkWell(
        onTap: widget.titlesAreLinks
            ? null
            : () {
                _selectThis(entry, !(entrySelections[entry] ?? false));
              },
        child: _buildUrlLink(entry),
      ),
      subtitle: entry.value.length <= 1
          ? null
          : InkWell(
              onTap: () {
                setState(() {
                  selectOnlyOne(entry.key);
                });
              },
              child: _buildDescriptionText(entry),
            ),
      leading: Radio<String>(value: entry.key),
    );
  }

  Widget _buildMultiSelectTile(MapEntry<String, List<String>> entry) {
    return Row(
      children: [
        Checkbox(
          value: entrySelections[entry],
          onChanged: (value) {
            _selectThis(entry, value);
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
                        _selectThis(entry, !(entrySelections[entry] ?? false));
                      },
                child: _buildUrlLink(entry),
              ),
              entry.value.length <= 1
                  ? const SizedBox.shrink()
                  : InkWell(
                      onTap: () {
                        _selectThis(entry, !(entrySelections[entry] ?? false));
                      },
                      child: _buildDescriptionText(entry),
                    ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildTVFooter() {
    if (!context.read<SettingsProvider>().isTV ||
        widget.onlyOneSelectionAllowed) {
      return [];
    }
    return [
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
                  entrySelections.values.where((b) => b).length.toString(),
                ],
              ),
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isTV = context.read<SettingsProvider>().isTV;
    final Map<MapEntry<String, List<String>>, bool> filteredEntrySelections =
        {};
    entrySelections.forEach((key, value) {
      final searchableText = key.value.isEmpty ? key.key : key.value[0];
      if (filterRegex.isEmpty || RegExp(filterRegex).hasMatch(searchableText)) {
        filteredEntrySelections.putIfAbsent(key, () => value);
      }
    });
    if (filterRegex.isNotEmpty && filteredEntrySelections.isEmpty) {
      entrySelections.forEach((key, value) {
        final searchableText = key.value.isEmpty ? key.key : key.value[0];
        if (filterRegex.isEmpty ||
            RegExp(
              filterRegex,
              caseSensitive: false,
            ).hasMatch(searchableText)) {
          filteredEntrySelections.putIfAbsent(key, () => value);
        }
      });
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
              tileMode: true,
              noTilePadding: true,
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
              return widget.onlyOneSelectionAllowed
                  ? _buildSingleSelectTile(entry)
                  : _buildMultiSelectTile(entry);
            }),
            ..._buildTVFooter(),
          ],
        ),
      ),
      actions: [
        _buildSelectAllButton(),
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

void _showImportError(dynamic e, BuildContext context) {
  if (e is PlatformException || e is MissingPluginException) {
    showError(ObtainiumError(tr('noFilePickerAvailable')), context);
  } else {
    showError(e, context);
  }
}

class ImportFromURLListController extends ChangeNotifier {
  final TextEditingController urlController = TextEditingController();
  bool isImporting = false;

  final SourceProvider sourceProvider;

  ImportFromURLListController({SourceProvider? sourceProvider})
    : sourceProvider = sourceProvider ?? SourceProvider();

  void showImportError(dynamic e, BuildContext context) =>
      _showImportError(e, context);

  Future<void> importFromFile(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles();
      if (result != null && result.files.isNotEmpty) {
        final path = result.files.single.path;
        if (path == null) return;
        final urls = RegExp(r'https?://[^\s"]+')
            .allMatches(await File(path).readAsString())
            .map((e) => e.input.substring(e.start, e.end))
            .toSet()
            .toList()
            .where((url) {
              try {
                sourceProvider.getSource(url);
                return true;
              } catch (e) {
                unawaited(
                  LogsProvider().add(
                    'URL parse error in filter: $e',
                    level: LogLevel.error,
                  ),
                );
                return false;
              }
            })
            .join('\n');
        urlController.text = urls;
        notifyListeners();
      }
    } catch (e) {
      if (context.mounted) {
        showImportError(e, context);
      }
    }
  }

  String? validate(String? value) {
    if (value != null && value.isNotEmpty) {
      final lines = value.trim().split('\n');
      for (int i = 0; i < lines.length; i++) {
        try {
          sourceProvider.getSource(lines[i]);
        } catch (e) {
          return '${tr('line')} ${i + 1}: $e';
        }
      }
    }
    return null;
  }

  List<String> getURLs() {
    return urlController.text
        .trim()
        .split('\n')
        .where((l) => l.isNotEmpty)
        .toList();
  }

  void setImporting(bool v) {
    isImporting = v;
    notifyListeners();
  }

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }
}
