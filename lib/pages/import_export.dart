import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:obtainium/components/app_bottom_sheet.dart';
import 'package:obtainium/components/backup_import_sheet.dart';
import 'package:obtainium/components/app_dropdown_field.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/components/rippling_wavy_progress/linear.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart' show regExValidator;
import 'package:obtainium/theme/app_dialog_theme.dart';
import 'package:obtainium/theme/app_theme_accent.dart';
import 'package:obtainium/theme/m3e_expressive_list.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_storage/shared_storage.dart' as saf;
import 'package:url_launcher/url_launcher_string.dart';

/// Human-readable label for a SAF tree [Uri] (Android document tree).
String apkSaveTreeUriDisplayLabel(Uri uri) {
  final String path = uri.path;
  if (path.startsWith('/tree/')) {
    return Uri.decodeComponent(path.substring('/tree/'.length));
  }
  if (path.isNotEmpty) {
    final String withoutLeadingSlash = path.startsWith('/')
        ? path.substring(1)
        : path;
    return Uri.decodeComponent(withoutLeadingSlash);
  }
  return uri.toString();
}

/// Display path for SAF tree URIs, with `primary:` storage prefix removed.
String folderDisplayPathFromTreeUri(Uri uri) {
  final String label = apkSaveTreeUriDisplayLabel(uri);
  const String primaryPrefix = 'primary:';
  if (label.startsWith(primaryPrefix)) {
    return label.substring(primaryPrefix.length);
  }
  return label;
}

class ImportExportPage extends StatefulWidget {
  const ImportExportPage({super.key});

  @override
  State<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends State<ImportExportPage> {
  bool importInProgress = false;

  @override
  Widget build(BuildContext context) {
    // [appsProvider] is intentionally a broad watch — this page lists
    // every tracked app to drive the export selection, and any add /
    // remove / rename should refresh the list. The expensive cost is
    // [settingsProvider] which used to broad-watch and rebuild this
    // long page on every unrelated settings change. Narrow it to only
    // the four fields actually read in build.
    final appsProvider = context.watch<AppsProvider>();
    context.select<SettingsProvider, int>(
      (s) => Object.hash(
        s.useGradientBackground,
        s.saveDownloadedApkCopies,
        s.exportSettings,
        s.autoExportOnChanges,
      ),
    );
    final settingsProvider = context.read<SettingsProvider>();

    final outlineButtonStyle = ButtonStyle(
      foregroundColor: WidgetStateProperty.all(
        Theme.of(context).colorScheme.onSurface,
      ),
      shape: WidgetStateProperty.all(
        StadiumBorder(
          side: BorderSide(
            width: 1,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );

    Future<void> runObtainiumExport({bool pickOnly = false}) async {
      hapticSelection();
      try {
        final String? result = await appsProvider.export(
          pickOnly: pickOnly || (await settingsProvider.getExportDir()) == null,
          sp: settingsProvider,
        );
        if (result != null) {
          showMessage(tr('exportedTo', args: [result]));
        }
        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        showError(e);
      }
    }

    Future<void> importObtainiumBackupData(String backupData) async {
      final BackupContent backupContent;
      try {
        backupContent = appsProvider.parseBackupContent(backupData);
      } catch (err) {
        throw ObtainiumError(tr('invalidInput'));
      }

      final hasSettings =
          backupContent.settingsMap != null &&
          backupContent.settingsMap!.isNotEmpty;
      final hasSecrets = hasSecretsInSettingsMap(backupContent.settingsMap);

      if (backupContent.apps.isEmpty && !hasSettings) {
        throw ObtainiumError(tr('noResults'));
      }

      final BackupImportSelection? selection =
          await showBackupImportPickerSheet(
            context: context,
            backupApps: backupContent.apps,
            hasSettings: hasSettings,
            hasSecrets: hasSecrets,
            existingApps: appsProvider.apps,
          );

      if (selection == null) {
        return;
      }

      final importResult = await appsProvider.import(
        backupData,
        selectedAppIds: selection.selectedAppIds,
        importSettings: selection.importSettings,
      );
      final cats = settingsProvider.categories;
      appsProvider.apps.forEach((key, appInMemory) {
        for (var category in appInMemory.app.categories) {
          if (!cats.containsKey(category)) {
            cats[category] = generateRandomLightColor().toARGB32();
          }
        }
      });
      appsProvider.addMissingCategories(settingsProvider);
      showMessage(
        '${tr('importedX', args: [plural('apps', importResult.key.length).toLowerCase()])}${importResult.value ? ' + ${tr('settings').toLowerCase()}' : ''}',
      );
    }

    Future<String?> pickBackupDataFromSystemPicker() async {
      final Uri? exportDir = Platform.isAndroid
          ? await settingsProvider.getExportDir(requireAccess: false)
          : null;
      if (Platform.isAndroid) {
        final List<Uri>? selectedUris;
        try {
          selectedUris = await saf.openDocument(
            initialUri: exportDir,
            grantWritePermission: false,
            persistablePermission: false,
            mimeType: '*/*',
          );
        } catch (e) {
          throw ObtainiumError(tr('noFilePickerAvailable'));
        }
        if (selectedUris == null || selectedUris.isEmpty) {
          return null;
        }
        final String? selectedBackupData = await saf.getDocumentContentAsString(
          selectedUris.single,
        );
        if (selectedBackupData == null) {
          throw ObtainiumError(tr('unexpectedError'));
        }
        return selectedBackupData;
      }

      final FilePickerResult? result;
      try {
        result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
      } catch (e) {
        throw ObtainiumError(tr('noFilePickerAvailable'));
      }
      if (result == null) {
        return null;
      }
      return File(result.files.single.path!).readAsString();
    }

    Future<void> runObtainiumImport() async {
      hapticSelection();
      var importStarted = false;
      try {
        final String? backupData = await pickBackupDataFromSystemPicker();
        if (backupData != null) {
          if (!context.mounted) return;
          setState(() {
            importInProgress = true;
          });
          importStarted = true;
          await importObtainiumBackupData(backupData);
        }
      } catch (err) {
        showError(err);
      } finally {
        if (context.mounted && importStarted) {
          setState(() {
            importInProgress = false;
          });
        }
      }
    }

    final ColorScheme impScheme = Theme.of(context).colorScheme;

    /// Folder picker rows with a title + subtitle (more vertical air).
    const EdgeInsets importPageCardFolderRowPadding = EdgeInsets.fromLTRB(
      16,
      12,
      16,
      12,
    );

    /// Other padded rows inside [importPageCard] (dropdowns and buttons).
    const EdgeInsets importPageCardRowPadding = EdgeInsets.fromLTRB(
      16,
      8,
      16,
      8,
    );
    const EdgeInsets importPageCardSwitchTilePadding = EdgeInsets.fromLTRB(
      16,
      0,
      16,
      4,
    );
    const double importPageCardRowItemGap = 12;

    Widget importPageCard(List<Widget> cardItems) {
      return M3eExpressiveSettingsCard(
        colorScheme: impScheme,
        items: cardItems,
      );
    }

    Widget importPageSectionTitle(
      String title,
      IconData icon, {
      double topPadding = 20,
      double bottomPadding = 8,
    }) {
      return Padding(
        padding: EdgeInsets.fromLTRB(4, topPadding, 4, bottomPadding),
        child: Row(
          children: [
            Icon(icon, color: impScheme.primary, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: impScheme.primary,
                  fontSize: 13,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget resettableImportPageRow({
      required Widget child,
      required VoidCallback? onReset,
    }) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onReset == null
            ? null
            : () {
                hapticMediumImpact();
                onReset();
              },
        child: child,
      );
    }

    final ButtonStyle folderPickOutlineStyle = outlineButtonStyle.merge(
      ButtonStyle(
        padding: WidgetStateProperty.all(const EdgeInsets.all(10)),
        minimumSize: WidgetStateProperty.all(Size.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

    Widget folderOutlineIconButton({
      required String tooltipMessage,
      required VoidCallback? onPressed,
    }) {
      return Tooltip(
        message: tooltipMessage,
        child: TextButton(
          style: folderPickOutlineStyle,
          onPressed: onPressed,
          child: Icon(Icons.folder_open_rounded, color: impScheme.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: impScheme.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (settingsProvider.useGradientBackground)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: impScheme.schemePageBackgroundGradient,
                ),
              ),
            ),
          CustomScrollView(
            scrollCacheExtent: const ScrollCacheExtent.pixels(1600),
            key: const PageStorageKey<String>('import-export-tab-scroll'),
            slivers: <Widget>[
              CustomAppBar(
                title: tr('importExport'),
                matchGradientBackground: settingsProvider.useGradientBackground,
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  8 + MediaQuery.paddingOf(context).bottom,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (Platform.isAndroid) ...[
                        importPageSectionTitle(
                          tr('importExportCardUpdateAssets'),
                          Icons.system_update_rounded,
                        ),
                        FutureBuilder<List<Uri?>>(
                          future: Future.wait<Uri?>([
                            settingsProvider.getApkSaveDir(
                              requireAccess: false,
                            ),
                            settingsProvider.getApkSaveDir(),
                          ]),
                          builder: (context, apkSaveSnapshot) {
                            final Uri? savedApkSaveUri =
                                apkSaveSnapshot.data?[0];
                            final Uri? accessibleApkSaveUri =
                                apkSaveSnapshot.data?[1];
                            final bool apkSaveDirInaccessible =
                                savedApkSaveUri != null &&
                                accessibleApkSaveUri == null;
                            final String apkFolderTitle =
                                savedApkSaveUri == null
                                ? tr('pickApkSaveDir')
                                : folderDisplayPathFromTreeUri(savedApkSaveUri);
                            final Color apkFolderDescriptionColor =
                                apkSaveDirInaccessible
                                ? impScheme.error
                                : impScheme.onSurfaceVariant;
                            return importPageCard([
                              resettableImportPageRow(
                                onReset:
                                    importInProgress || savedApkSaveUri == null
                                    ? null
                                    : () async {
                                        await settingsProvider.pickApkSaveDir(
                                          remove: true,
                                        );
                                        if (context.mounted) {
                                          setState(() {});
                                        }
                                      },
                                child: Padding(
                                  padding: importPageCardFolderRowPadding,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              apkFolderTitle,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    color:
                                                        apkSaveDirInaccessible
                                                        ? impScheme.error
                                                        : null,
                                                  ),
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              tr(
                                                apkSaveDirInaccessible
                                                    ? 'storagePermissionDenied'
                                                    : 'apkSaveFolderDescription',
                                              ),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        apkFolderDescriptionColor,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      folderOutlineIconButton(
                                        tooltipMessage: tr('pickApkSaveDir'),
                                        onPressed: importInProgress
                                            ? null
                                            : () async {
                                                await settingsProvider
                                                    .pickApkSaveDir();
                                                if (context.mounted) {
                                                  setState(() {});
                                                }
                                              },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SwitchListTile(
                                visualDensity: VisualDensity.compact,
                                contentPadding: importPageCardSwitchTilePadding,
                                title: Text(tr('saveDownloadedApkCopies')),
                                value: settingsProvider.saveDownloadedApkCopies,
                                onChanged: importInProgress
                                    ? null
                                    : (bool enabled) {
                                        settingsProvider
                                                .saveDownloadedApkCopies =
                                            enabled;
                                      },
                              ),
                            ]);
                          },
                        ),
                      ],
                      importPageSectionTitle(
                        tr('importExportCardObtainxBackup'),
                        Icons.save_as_rounded,
                      ),
                      FutureBuilder<List<Uri?>>(
                        future: Future.wait<Uri?>([
                          settingsProvider.getExportDir(requireAccess: false),
                          settingsProvider.getExportDir(),
                        ]),
                        builder: (context, exportSnapshot) {
                          final Uri? savedExportUri = exportSnapshot.data?[0];
                          final Uri? accessibleExportUri =
                              exportSnapshot.data?[1];
                          final bool exportDirInaccessible =
                              savedExportUri != null &&
                              accessibleExportUri == null;
                          final Color exportFolderDescriptionColor =
                              exportDirInaccessible
                              ? impScheme.error
                              : impScheme.onSurfaceVariant;
                          return importPageCard([
                            resettableImportPageRow(
                              onReset:
                                  importInProgress || savedExportUri == null
                                  ? null
                                  : () async {
                                      await settingsProvider.pickExportDir(
                                        remove: true,
                                      );
                                      if (context.mounted) {
                                        setState(() {});
                                      }
                                    },
                              child: Padding(
                                padding: importPageCardFolderRowPadding,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            savedExportUri == null
                                                ? tr('pickConfigExportFolder')
                                                : folderDisplayPathFromTreeUri(
                                                    savedExportUri,
                                                  ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  color: exportDirInaccessible
                                                      ? impScheme.error
                                                      : null,
                                                ),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            tr(
                                              exportDirInaccessible
                                                  ? 'storagePermissionDenied'
                                                  : 'configExportFolderDescription',
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      exportFolderDescriptionColor,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    folderOutlineIconButton(
                                      tooltipMessage: tr('pickExportDir'),
                                      onPressed: importInProgress
                                          ? null
                                          : () {
                                              runObtainiumExport(
                                                pickOnly: true,
                                              );
                                            },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: importPageCardRowPadding,
                              child: (() {
                                final List<String> labels = [
                                  tr('importExportBackupScopeOnlyApps'),
                                  tr(
                                    'importExportBackupScopeAppsSettingsNoSecrets',
                                  ),
                                  tr(
                                    'importExportBackupScopeAllAppsAndSettings',
                                  ),
                                ];
                                return appDropdownField<int>(
                                  key: ValueKey(
                                    settingsProvider.exportSettings,
                                  ),
                                  context: context,
                                  value: settingsProvider.exportSettings,
                                  labelText: tr('importExportIncludeInBackup'),
                                  menuWidth: appDropdownMenuWidth(
                                    context,
                                    labels,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                    horizontalPadding: 96,
                                    minWidth: 150,
                                    maxWidthInset: 120,
                                  ),
                                  items: [
                                    DropdownMenuItem<int>(
                                      value: 0,
                                      child: Text(
                                        tr('importExportBackupScopeOnlyApps'),
                                      ),
                                    ),
                                    DropdownMenuItem<int>(
                                      value: 1,
                                      child: Text(
                                        tr(
                                          'importExportBackupScopeAppsSettingsNoSecrets',
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem<int>(
                                      value: 2,
                                      child: Text(
                                        tr(
                                          'importExportBackupScopeAllAppsAndSettings',
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (int? selected) {
                                    if (selected != null) {
                                      settingsProvider.exportSettings =
                                          selected;
                                    }
                                  },
                                );
                              })(),
                            ),
                            SwitchListTile(
                              visualDensity: VisualDensity.compact,
                              contentPadding: importPageCardSwitchTilePadding,
                              title: Text(tr('autoExportOnChanges')),
                              value: settingsProvider.autoExportOnChanges,
                              onChanged: importInProgress
                                  ? null
                                  : (bool value) {
                                      settingsProvider.autoExportOnChanges =
                                          value;
                                    },
                            ),
                            Padding(
                              padding: importPageCardRowPadding,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      style: outlineButtonStyle,
                                      onPressed: importInProgress
                                          ? null
                                          : runObtainiumImport,
                                      child: Text(tr('obtainiumImport')),
                                    ),
                                  ),
                                  const SizedBox(
                                    width: importPageCardRowItemGap,
                                  ),
                                  Expanded(
                                    child: TextButton(
                                      style: outlineButtonStyle,
                                      onPressed:
                                          importInProgress ||
                                              exportSnapshot.data == null
                                          ? null
                                          : runObtainiumExport,
                                      child: Text(tr('obtainiumExport')),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ]);
                        },
                      ),
                      if (importInProgress) ...[
                        const SizedBox(height: 14),
                        const LinearRipplingWavyProgressIndicator(),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
      contentPadding: appDialogContentPadding,
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
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(null);
          },
          child: Text(tr('ok')),
        ),
      ],
    );
  }
}

// ignore: must_be_immutable
class SelectionModal extends StatefulWidget {
  SelectionModal({
    super.key,
    required this.entries,
    this.selectedByDefault = true,
    this.onlyOneSelectionAllowed = false,
    this.titlesAreLinks = true,
    this.title,
    this.deselectThese = const [],
    this.presentAsBottomSheet = false,
    this.showFilterField = true,
    this.onSubmitSelection,
  });

  String? title;
  Map<String, List<String>> entries;
  bool selectedByDefault;
  List<String> deselectThese;
  bool onlyOneSelectionAllowed;
  bool titlesAreLinks;

  /// When true, [build] returns content for the shared app sheet scaffold.
  bool presentAsBottomSheet;

  /// When false, the regex filter field is hidden (for short lists such as searchable sources).
  bool showFilterField;

  /// Runs before a bottom-sheet selection is dismissed. Returning true closes
  /// the sheet; returning false keeps the results visible for another attempt.
  Future<bool> Function(List<String>, VoidCallback)? onSubmitSelection;

  @override
  State<SelectionModal> createState() => _SelectionModalState();
}

class _SelectionModalState extends State<SelectionModal> {
  Map<MapEntry<String, List<String>>, bool> entrySelections = {};
  String filterRegex = '';
  bool _isSubmitting = false;
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
    if (widget.presentAsBottomSheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        FocusManager.instance.primaryFocus?.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            FocusManager.instance.primaryFocus?.unfocus();
          }
        });
      });
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
    // Filter once with a single compiled RegExp. Previously a RegExp was
    // compiled per entry — and twice over when the case-sensitive pass found
    // nothing — i.e. O(entries) compilations on every keystroke over what can
    // be a large mass-import list.
    final List<MapEntry<String, List<String>>> filteredEntryKeys;
    if (filterRegex.isEmpty) {
      filteredEntryKeys = entrySelections.keys.toList();
    } else {
      String searchableFor(MapEntry<String, List<String>> key) =>
          key.value.isEmpty ? key.key : key.value[0];
      final RegExp rx = RegExp(filterRegex);
      var matches = entrySelections.keys
          .where((key) => rx.hasMatch(searchableFor(key)))
          .toList();
      if (matches.isEmpty) {
        final RegExp rxInsensitive = RegExp(filterRegex, caseSensitive: false);
        matches = entrySelections.keys
            .where((key) => rxInsensitive.hasMatch(searchableFor(key)))
            .toList();
      }
      filteredEntryKeys = matches;
    }
    Widget getSelectAllButton() {
      if (widget.onlyOneSelectionAllowed) {
        return const SizedBox.shrink();
      }
      final noneSelected = entrySelections.values
          .where((v) => v == true)
          .isEmpty;
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

    final Widget? filterFormWidget = widget.showFilterField
        ? GeneratedForm(
            outlinedInputFields: true,
            prominentSectionHeaders: false,
            wrapFormSectionsInCards: false,
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
          )
        : null;

    Widget buildEntryTile(MapEntry<String, List<String>> entry) {
      void selectThis(bool? value) {
        setState(() {
          value ??= false;
          if (value! && widget.onlyOneSelectionAllowed) {
            selectOnlyOne(entry.key);
          } else {
            entrySelections[entry] = value!;
          }
        });
      }

      final urlLink = GestureDetector(
        onTap: !widget.titlesAreLinks
            ? null
            : () {
                launchUrlString(
                  entry.key,
                  mode: LaunchMode.externalApplication,
                );
              },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.value.isEmpty ? entry.key : entry.value[0],
              style: TextStyle(
                decoration: widget.titlesAreLinks
                    ? TextDecoration.underline
                    : null,
                fontWeight: FontWeight.bold,
              ),
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
        ),
      );

      final descriptionText = entry.value.length <= 1
          ? const SizedBox.shrink()
          : Text(
              entry.value[1].length > 128
                  ? '${entry.value[1].substring(0, 128)}...'
                  : entry.value[1],
              style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            );

      final selectedEntries = entrySelections.entries
          .where((e) => e.value)
          .toList();

      final singleSelectTile = RadioGroup<String>(
        groupValue: selectedEntries.isEmpty
            ? null
            : selectedEntries.first.key.key,
        onChanged: (String? value) {
          if (value != null) {
            setState(() {
              selectOnlyOne(value);
            });
          }
        },
        child: ListTile(
          title: GestureDetector(
            onTap: widget.titlesAreLinks
                ? null
                : () {
                    selectThis(!(entrySelections[entry] ?? false));
                  },
            child: urlLink,
          ),
          subtitle: entry.value.length <= 1
              ? null
              : GestureDetector(
                  onTap: () {
                    setState(() {
                      selectOnlyOne(entry.key);
                    });
                  },
                  child: descriptionText,
                ),
          leading: Radio<String>(value: entry.key),
        ),
      );

      final bool isSelected = entrySelections[entry] ?? false;
      final multiSelectTile = ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        dense: true,
        minVerticalPadding: 4,
        visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
        title: GestureDetector(
          onTap: widget.titlesAreLinks || _isSubmitting
              ? null
              : () {
                  selectThis(!isSelected);
                },
          child: urlLink,
        ),
        subtitle: entry.value.length <= 1
            ? null
            : GestureDetector(
                onTap: _isSubmitting
                    ? null
                    : () {
                        selectThis(!isSelected);
                      },
                child: descriptionText,
              ),
        trailing: SizedBox.square(
          dimension: 28,
          child: Checkbox(
            value: isSelected,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            onChanged: _isSubmitting ? null : selectThis,
          ),
        ),
        onTap: _isSubmitting ? null : () => selectThis(!isSelected),
      );

      return widget.onlyOneSelectionAllowed
          ? singleSelectTile
          : multiSelectTile;
    }

    final List<Widget> sheetColumnChildren = [
      ?filterFormWidget,
      for (final key in filteredEntryKeys) buildEntryTile(key),
    ];

    final List<Widget> selectionActions = [
      getSelectAllButton(),
      TextButton(
        onPressed: () {
          Navigator.of(context).pop();
        },
        child: Text(tr('cancel')),
      ),
      TextButton(
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
    ];

    if (widget.presentAsBottomSheet) {
      final ColorScheme colorScheme = Theme.of(context).colorScheme;

      void popWithSelectedKeys() {
        Navigator.of(context).pop(
          entrySelections.entries
              .where(
                (MapEntry<MapEntry<String, List<String>>, bool> e) => e.value,
              )
              .map(
                (MapEntry<MapEntry<String, List<String>>, bool> e) => e.key.key,
              )
              .toList(),
        );
      }

      Future<void> submitSelectedKeys() async {
        final List<String> selectedKeys = entrySelections.entries
            .where(
              (MapEntry<MapEntry<String, List<String>>, bool> entry) =>
                  entry.value,
            )
            .map(
              (MapEntry<MapEntry<String, List<String>>, bool> entry) =>
                  entry.key.key,
            )
            .toList();
        final Future<bool> Function(List<String>, VoidCallback)?
        onSubmitSelection = widget.onSubmitSelection;
        if (onSubmitSelection == null) {
          Navigator.of(context).pop(selectedKeys);
          return;
        }

        setState(() {
          _isSubmitting = true;
        });
        void stopSubmitting() {
          if (mounted && _isSubmitting) {
            setState(() {
              _isSubmitting = false;
            });
          }
        }

        final bool closeSheet = await onSubmitSelection(
          selectedKeys,
          stopSubmitting,
        );
        if (!context.mounted) return;
        if (closeSheet) {
          Navigator.of(context).pop(selectedKeys);
        } else {
          setState(() {
            _isSubmitting = false;
          });
        }
      }

      final bool hasSelection = entrySelections.values.any(
        (bool selected) => selected,
      );
      final int selectionCount = entrySelections.values
          .where((bool selected) => selected)
          .length;

      Widget sheetIconBar() {
        Widget slot({
          required String tooltip,
          required Widget icon,
          required VoidCallback? onPressed,
          bool primary = false,
        }) {
          return Expanded(
            child: Center(
              child: primary
                  ? IconButton.filled(
                      tooltip: tooltip,
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      icon: icon,
                      onPressed: onPressed,
                    )
                  : IconButton.filledTonal(
                      tooltip: tooltip,
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      icon: icon,
                      onPressed: onPressed,
                    ),
            ),
          );
        }

        if (widget.onlyOneSelectionAllowed) {
          return Row(
            children: [
              slot(
                tooltip: tr('cancel'),
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              slot(
                tooltip: tr('continue'),
                icon: const Icon(Icons.check_rounded),
                onPressed: hasSelection ? popWithSelectedKeys : null,
                primary: true,
              ),
            ],
          );
        }
        return Row(
          children: [
            slot(
              tooltip: tr('selectAll'),
              icon: const Icon(Icons.select_all_rounded),
              onPressed: _isSubmitting
                  ? null
                  : () {
                      setState(() {
                        selectAll();
                      });
                    },
            ),
            slot(
              tooltip: tr('deselectAll'),
              icon: const Icon(Icons.deselect_rounded),
              onPressed: _isSubmitting
                  ? null
                  : () {
                      setState(() {
                        selectAll(deselect: true);
                      });
                    },
            ),
            slot(
              tooltip: tr('cancel'),
              icon: const Icon(Icons.close_rounded),
              onPressed: _isSubmitting
                  ? null
                  : () {
                      Navigator.of(context).pop();
                    },
            ),
            slot(
              tooltip: widget.onSubmitSelection == null
                  ? tr('selectX', args: [selectionCount.toString()])
                  : tr('save'),
              icon: _isSubmitting
                  ? ExpressiveLoadingIndicator(
                      color: colorScheme.onSurfaceVariant,
                      constraints: const BoxConstraints.tightFor(
                        width: 24,
                        height: 24,
                      ),
                    )
                  : Icon(
                      widget.onSubmitSelection == null
                          ? Icons.check_rounded
                          : Icons.save_rounded,
                    ),
              onPressed: hasSelection && !_isSubmitting
                  ? () => unawaited(submitSelectedKeys())
                  : null,
              primary: true,
            ),
          ],
        );
      }

      return AppSheetScaffold(
        expand: true,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title ?? tr('pick'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (filterFormWidget != null) ...[
              const SizedBox(height: 12),
              filterFormWidget,
            ],
          ],
        ),
        body: ListView.builder(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          itemCount: filteredEntryKeys.length,
          itemBuilder: (BuildContext context, int index) {
            return buildEntryTile(filteredEntryKeys[index]);
          },
        ),
        footer: sheetIconBar(),
      );
    }

    return AlertDialog(
      scrollable: true,
      title: Text(widget.title ?? tr('pick')),
      contentPadding: appDialogContentPadding,
      content: Column(children: sheetColumnChildren),
      actions: selectionActions,
    );
  }
}
