import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/app_list_tile.dart';
import 'package:obtainium/components/category_editor.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/theme.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/pages/settings.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class AppsPage extends StatefulWidget {
  const AppsPage({
    super.key,
    this.onAppSelected,
    this.selectedAppId,
    this.onSelectionChanged,
  });

  /// In a two-pane layout, called when the user taps an app (instead of pushing
  /// an [AppPage] route). In single-pane mode this is null and taps push a
  /// route as usual.
  final void Function(String appId)? onAppSelected;

  /// The app currently shown in the detail pane (two-pane), used to highlight
  /// the tile.
  final String? selectedAppId;

  /// Called whenever the set of selected app ids changes (e.g. when the user
  /// toggles a row or clears the selection), reporting whether any apps are now
  /// selected. The parent shell uses this to morph the FAB between "Add" and
  /// "Actions".
  final void Function(bool hasSelection)? onSelectionChanged;

  @override
  State<AppsPage> createState() => AppsPageState();
}

class AppsPageState extends State<AppsPage> {
  late final AppsProvider appsProvider;
  late final SettingsProvider settingsProvider;
  bool _providersInitialized = false;

  AppsFilter filter = AppsFilter();
  final AppsFilter neutralFilter = AppsFilter();
  Set<String> selectedAppIds = {};
  Set<String?> collapsedGroups = {};

  final TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final GlobalKey<RefreshIndicatorState> refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  Timer? _searchDebounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_providersInitialized) {
      appsProvider = context.read<AppsProvider>();
      settingsProvider = context.read<SettingsProvider>();
      _providersInitialized = true;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    scrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void clearSelected() {
    selectedAppIds.clear();
    setState(() {});
    widget.onSelectionChanged?.call(selectedAppIds.isNotEmpty);
  }

  void selectThese(List<App> apps) {
    if (selectedAppIds.isEmpty) {
      for (var a in apps) {
        selectedAppIds.add(a.id);
      }
      setState(() {});
      widget.onSelectionChanged?.call(selectedAppIds.isNotEmpty);
    }
  }

  void toggleAppSelected(App app) {
    if (selectedAppIds.contains(app.id)) {
      selectedAppIds.remove(app.id);
    } else {
      selectedAppIds.add(app.id);
    }
    setState(() {});
    widget.onSelectionChanged?.call(selectedAppIds.isNotEmpty);
  }

  List<AppInMemory> getFilteredAndSortedApps(
    List<AppInMemory> listedApps,
    Set<String> existingUpdates,
  ) {
    var result = AppListBuilder.filter(listedApps, filter);
    result = AppListBuilder.sort(
      result,
      settingsProvider.sortColumn,
      settingsProvider.sortOrder,
    );
    result = AppListBuilder.reorder(
      result,
      settingsProvider.pinUpdates,
      settingsProvider.buryNonInstalled,
      existingUpdates,
    );
    return result;
  }

  Future<List<App>> refresh() {
    settingsProvider.lightImpact();
    setState(() {});
    final ctx = context;
    return appsProvider
        .checkUpdates(forceAll: true)
        .catchError((e) {
          if (ctx.mounted) {
            showError(e is CheckUpdatesException ? e.errors : e, ctx);
          }
          return <App>[];
        })
        .whenComplete(() {
          setState(() {});
        });
  }

  VoidCallback? massObtainCallback(
    BuildContext context,
    List<String> existingUpdateIdsAllOrSelected,
    List<String> newInstallIdsAllOrSelected,
    List<String> trackOnlyUpdateIdsAllOrSelected,
  ) {
    return appsProvider.areDownloadsRunning() ||
            (existingUpdateIdsAllOrSelected.isEmpty &&
                newInstallIdsAllOrSelected.isEmpty &&
                trackOnlyUpdateIdsAllOrSelected.isEmpty)
        ? null
        : () {
            settingsProvider.heavyImpact();
            _showObtainDialog(
              context,
              existingUpdateIdsAllOrSelected,
              newInstallIdsAllOrSelected,
              trackOnlyUpdateIdsAllOrSelected,
            );
          };
  }

  void _showObtainDialog(
    BuildContext context,
    List<String> existingUpdateIds,
    List<String> newInstallIds,
    List<String> trackOnlyUpdateIds,
  ) {
    final totalApps =
        existingUpdateIds.length +
        newInstallIds.length +
        trackOnlyUpdateIds.length;
    showDialog<Set<String>>(
      context: context,
      builder: (BuildContext ctx) {
        return _BulkUpdateDialog(
          existingUpdateIds: existingUpdateIds,
          newInstallIds: newInstallIds,
          trackOnlyUpdateIds: trackOnlyUpdateIds,
          totalApps: totalApps,
          apps: appsProvider.apps,
        );
      },
    ).then((selectedIds) async {
      if (selectedIds != null && selectedIds.isNotEmpty) {
        if (!context.mounted) return;
        unawaited(
          appsProvider
              .downloadAndInstallLatestApps(
                selectedIds.toList(),
                appNavigatorKey.currentContext,
              )
              .then((value) {
                if (value.isNotEmpty) {
                  if (context.mounted) {
                    showMessage(tr('appsUpdated'), context);
                    final np = context.read<NotificationsProvider>();
                    np.cancel(updateNotificationId);
                    np.cancel(
                      SilentUpdateAttemptNotification(
                        [],
                        id: value[0].hashCode,
                      ).id,
                    );
                  }
                }
              })
              .catchError((e) {
                if (context.mounted) showError(e, context);
              }),
        );
      }
    });
  }

  Future<void> showFilterDialog(BuildContext context) async {
    var pendingCategories = {...filter.categoryFilter};
    final values = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (BuildContext ctx) {
        final vals = filter.toFormValuesMap();
        return GeneratedFormModal(
          tileMode: true,
          initValid: true,
          title: tr('filterApps'),
          items: [
            [
              GeneratedFormTextField(
                'appName',
                label: tr('appName'),
                required: false,
                value: vals['appName'],
              ),
            ],
            [
              GeneratedFormTextField(
                'author',
                label: tr('author'),
                required: false,
                value: vals['author'],
              ),
            ],
            [
              GeneratedFormTextField(
                'appId',
                label: tr('appId'),
                required: false,
                value: vals['appId'],
              ),
            ],
            [
              GeneratedFormSwitch(
                'upToDateApps',
                label: tr('upToDateApps'),
                value: vals['upToDateApps'],
              ),
            ],
            [
              GeneratedFormSwitch(
                'nonInstalledApps',
                label: tr('nonInstalledApps'),
                value: vals['nonInstalledApps'],
              ),
            ],
            [
              GeneratedFormDropdown(
                'sourceFilter',
                label: tr('appSource'),
                value: filter.sourceFilter,
                [
                  MapEntry('', tr('none')),
                  ...ctx.read<SourceProvider>().sources.map(
                    (e) => MapEntry(e.sourceIdentifier, e.name),
                  ),
                ],
              ),
            ],
          ],
          additionalWidgets: [
            const SizedBox(height: 16),
            ConnectedCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CategorySelector(
                  selected: filter.categoryFilter,
                  allowCreate: false,
                  onChanged: (categories) {
                    pendingCategories = categories;
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
    if (values != null) {
      _searchDebounce?.cancel();
      filter.setFormValuesFromMap(values);
      filter.categoryFilter = pendingCategories;
      // Keep the search bar in sync with the name filter the dialog just set,
      // otherwise it shows stale text and the next keystroke overwrites it.
      if (searchController.text != filter.nameFilter) {
        searchController.text = filter.nameFilter;
      }
      if (mounted) setState(() {});
    }
  }

  void onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      filter.nameFilter = value;
      if (mounted) setState(() {});
    });
  }

  void clearSearchAndFilter() {
    _searchDebounce?.cancel();
    filter = AppsFilter();
    searchController.clear();
    setState(() {});
  }

  Future<void> Function() launchCategorizeDialogCallback(
    BuildContext context,
    Set<App> selectedApps,
  ) {
    return () async {
      try {
        Set<String>? preselected;
        var showPrompt = false;
        for (var element in selectedApps) {
          final currentCats = element.categories.toSet();
          if (preselected == null) {
            preselected = currentCats;
          } else {
            if (!settingsProvider.setEqual(currentCats, preselected)) {
              showPrompt = true;
              break;
            }
          }
        }
        var cont = true;
        if (showPrompt) {
          cont =
              await showDialog<Map<String, dynamic>?>(
                context: context,
                builder: (BuildContext ctx) {
                  return GeneratedFormModal(
                    title: tr('categorize'),
                    items: const [],
                    initValid: true,
                    message: tr('selectedCategorizeWarning'),
                  );
                },
              ) !=
              null;
        }
        if (cont && context.mounted) {
          var pendingCategories = !showPrompt
              ? (preselected ?? <String>{})
              : <String>{};
          var categoriesChanged = false;
          await showDialog<Map<String, dynamic>?>(
            context: context,
            builder: (BuildContext ctx) {
              return GeneratedFormModal(
                title: tr('categorize'),
                items: const [],
                initValid: true,
                singleNullReturnButton: tr('continue'),
                additionalWidgets: [
                  CategorySelector(
                    selected: !showPrompt ? (preselected ?? {}) : {},
                    onChanged: (categories) {
                      pendingCategories = categories;
                      categoriesChanged = true;
                    },
                  ),
                ],
              );
            },
          );
          if (categoriesChanged) {
            unawaited(
              appsProvider.saveApps(
                selectedApps.map((e) {
                  e = e.copyWith(categories: pendingCategories.toList());
                  return e;
                }).toList(),
              ),
            );
          }
        }
      } catch (err) {
        if (context.mounted) showError(err, context);
      }
    };
  }

  Future<void> showMassMarkDialog(
    BuildContext context,
    Set<App> selectedApps,
  ) async {
    try {
      final confirmed = await showConfirmDialog(
        context,
        title: tr(
          'markXSelectedAppsAsUpdated',
          args: [selectedAppIds.length.toString()],
        ),
        content: Text(
          tr('onlyWorksWithNonVersionDetectApps'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
          ),
        ),
        autofocusConfirm: context.read<SettingsProvider>().isTV,
      );
      if (!confirmed) return;
      settingsProvider.selectionClick();
      unawaited(
        appsProvider.saveApps(
          selectedApps.map((a) {
            if (a.installedVersion != null &&
                !appsProvider.isVersionDetectionPossible(
                  appsProvider.apps[a.id],
                )) {
              a = a.copyWith(installedVersion: a.latestVersion);
            }
            return a;
          }).toList(),
        ),
      );
    } catch (e) {
      if (context.mounted) showError(e, context);
    }
  }

  void pinSelectedApps(Set<App> selectedApps) {
    final pinStatus = selectedApps.where((element) => element.pinned).isEmpty;
    unawaited(
      appsProvider.saveApps(
        selectedApps.map((e) {
          e = e.copyWith(pinned: pinStatus);
          return e;
        }).toList(),
      ),
    );
  }

  void showMoreOptionsBottomSheet(BuildContext context, Set<App> selectedApps) {
    final isPinned = selectedApps.where((e) => e.pinned).isNotEmpty;
    final hasSelection = selectedAppIds.isNotEmpty;

    final existingUpdateIds = selectedApps
        .where(
          (a) =>
              a.installedVersion != null &&
              a.installedVersion != a.latestVersion &&
              a.settings.getBool('trackOnly') != true,
        )
        .map((a) => a.id)
        .toList();
    final newInstallIds = selectedApps
        .where(
          (a) =>
              a.installedVersion == null &&
              a.settings.getBool('trackOnly') != true,
        )
        .map((a) => a.id)
        .toList();
    final trackOnlyUpdateIds = selectedApps
        .where(
          (a) =>
              a.installedVersion != null &&
              a.installedVersion != a.latestVersion &&
              a.settings.getBool('trackOnly') == true,
        )
        .map((a) => a.id)
        .toList();
    final hasObtainActions =
        existingUpdateIds.isNotEmpty ||
        newInstallIds.isNotEmpty ||
        trackOnlyUpdateIds.isNotEmpty;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        Widget optionTile({
          required IconData icon,
          required String label,
          required VoidCallback? onTap,
        }) => ActionListTile(
          icon: icon,
          label: label,
          onTap: onTap,
          autoPop: true,
        );

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                optionTile(
                  icon: Icons.delete_outline,
                  label: tr('remove'),
                  onTap: hasSelection
                      ? () {
                          appsProvider.removeAppsWithModal(
                            context,
                            selectedApps.toList(),
                          );
                        }
                      : null,
                ),
                optionTile(
                  icon: Icons.category_outlined,
                  label: tr('categorize'),
                  onTap: hasSelection
                      ? launchCategorizeDialogCallback(context, selectedApps)
                      : null,
                ),
                optionTile(
                  icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  label: isPinned ? tr('unpinFromTop') : tr('pinToTop'),
                  onTap: () => pinSelectedApps(selectedApps),
                ),
                if (hasObtainActions && !appsProvider.areDownloadsRunning())
                  optionTile(
                    icon: Icons.download_rounded,
                    label: tr('installUpdateSelectedApps'),
                    onTap: () {
                      settingsProvider.heavyImpact();
                      _showObtainDialog(
                        context,
                        existingUpdateIds,
                        newInstallIds,
                        trackOnlyUpdateIds,
                      );
                    },
                  ),
                optionTile(
                  icon: Icons.share_outlined,
                  label: tr('shareSelectedAppURLs'),
                  onTap: () => shareAppURLs(selectedApps),
                ),
                optionTile(
                  icon: Icons.link_outlined,
                  label: tr('shareAppConfigLinks'),
                  onTap: !hasSelection
                      ? null
                      : () => shareConfigLinks(selectedApps),
                ),
                optionTile(
                  icon: Icons.file_download_outlined,
                  label: '${tr('share')} - ${tr('obtainiumExport')}',
                  onTap: !hasSelection ? null : () => shareExport(selectedApps),
                ),
                optionTile(
                  icon: Icons.download_outlined,
                  label: tr(
                    'downloadX',
                    args: [lowerCaseIfEnglish(tr('releaseAsset'))],
                  ),
                  onTap: () {
                    appsProvider
                        .downloadAppAssets(
                          selectedApps.map((e) => e.id).toList(),
                          context,
                        )
                        .catchError((e) {
                          if (context.mounted) showError(e, context);
                          return <String>[];
                        });
                  },
                ),
                optionTile(
                  icon: Icons.done_all,
                  label: tr('markSelectedAppsUpdated'),
                  onTap: appsProvider.areDownloadsRunning()
                      ? null
                      : () => showMassMarkDialog(context, selectedApps),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void shareAppURLs(Set<App> selectedApps) {
    final buf = StringBuffer();
    for (var a in selectedApps) {
      buf.writeln(a.url);
    }
    final urls = buf.toString().trimRight();
    unawaited(
      SharePlus.instance.share(
        ShareParams(text: urls, subject: 'Obtainium - ${tr('appsString')}'),
      ),
    );
  }

  void shareConfigLinks(Set<App> selectedApps) {
    final buf = StringBuffer();
    for (var a in selectedApps) {
      buf.writeln(
        'https://apps.obtainium.imranr.dev/redirect?r=obtainium://app/${Uri.encodeComponent(jsonEncode({'id': a.id, 'url': a.url, 'author': a.author, 'name': a.name, 'preferredApkIndex': a.preferredApkIndex, 'additionalSettings': jsonEncode(a.additionalSettings), 'overrideSource': a.overrideSource}))}',
      );
    }
    unawaited(
      SharePlus.instance.share(
        ShareParams(
          text: buf.toString(),
          subject: 'Obtainium - ${tr('appsString')}',
        ),
      ),
    );
  }

  void shareExport(Set<App> selectedApps) {
    const encoder = JsonEncoder.withIndent('    ');
    final exportJSON = encoder.convert(
      appsProvider.generateExportJSON(
        appIds: selectedApps.map((e) => e.id).toList(),
        overrideExportSettings: 0,
      ),
    );
    final String fn =
        '${tr('obtainiumExportHyphenatedLowercase')}-${DateTime.now().toIso8601String().replaceAll(':', '-')}-count-${selectedApps.length}';
    final XFile f = XFile.fromData(
      Uint8List.fromList(utf8.encode(exportJSON)),
      mimeType: 'application/json',
      name: fn,
    );
    unawaited(
      SharePlus.instance.share(
        ShareParams(files: [f], fileNameOverrides: ['$fn.json']),
      ),
    );
  }

  void toggleGroupCollapse(String? group) {
    if (collapsedGroups.contains(group)) {
      collapsedGroups.remove(group);
    } else {
      collapsedGroups.add(group);
    }
    setState(() {});
  }

  Widget _buildTile(
    int index,
    BuildContext context,
    List<AppInMemory> listedApps,
    SettingsProvider settingsProvider,
    AppsProvider appsProvider, {
    BorderRadius? borderRadius,
  }) {
    final aim = listedApps[index];
    final app = aim.app;
    return AppListTile(
      appInMemory: aim,
      settingsProvider: settingsProvider,
      appsProvider: appsProvider,
      borderRadius: borderRadius,
      multiSelected: selectedAppIds.contains(app.id),
      detailSelected: widget.selectedAppId == app.id,
      autofocus: index == 0 && settingsProvider.isTV,
      onToggleSelected: () => toggleAppSelected(app),
      onTap: () {
        if (selectedAppIds.isNotEmpty) {
          toggleAppSelected(app);
        } else if (widget.onAppSelected != null) {
          widget.onAppSelected!(app.id);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AppPage(appId: app.id)),
          );
        }
      },
    );
  }

  Widget _appTileCard(
    int index,
    BuildContext context,
    List<AppInMemory> listedApps,
    SettingsProvider settingsProvider,
    AppsProvider appsProvider,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: _buildTile(
          index,
          context,
          listedApps,
          settingsProvider,
          appsProvider,
          borderRadius: BorderRadius.circular(connectedTileBigRadius),
        ),
      ),
    );
  }

  Widget _getGroupCollapsibleTile(
    int index,
    BuildContext context,
    List<AppInMemory> listedApps,
    String groupBy,
    List<String?> listedGroups,
    Map<String?, List<int>> grouped,
    SettingsProvider settingsProvider,
    AppsProvider appsProvider,
  ) {
    final group = listedGroups[index];
    final appIndices = grouped[group] ?? [];
    final expanded = !collapsedGroups.contains(group);
    final title = groupBy == GroupByMode.source.name
        ? (group ?? tr('noSource'))
        : capitalizeFirst(group ?? tr('noCategory'));
    return AppListGroupSection(
      title: title,
      expanded: expanded,
      appCount: appIndices.length,
      onToggle: () => toggleGroupCollapse(group),
      buildTiles: () => [
        for (var j = 0; j < appIndices.length; j++)
          _buildTile(
            appIndices[j],
            context,
            listedApps,
            settingsProvider,
            appsProvider,
            // Header occupies the top slot, so tiles are never first; the last
            // tile gets the group's rounded bottom.
            borderRadius: positionalTileRadius(
              isFirst: false,
              isLast: j == appIndices.length - 1,
            ),
          ),
      ],
    );
  }

  Widget _getSelectAllButton(
    BuildContext context,
    List<AppInMemory> listedApps,
  ) {
    return selectedAppIds.isEmpty
        ? TextButton.icon(
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onPressed: () {
              selectThese(listedApps.map((e) => e.app).toList());
            },
            icon: Icon(
              Icons.select_all_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            label: Text(listedApps.length.toString()),
          )
        : TextButton.icon(
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onPressed: () {
              clearSelected();
            },
            icon: Icon(
              Icons.deselect_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            label: Text(selectedAppIds.length.toString()),
          );
  }

  Widget _getDisplayedList(
    BuildContext context,
    List<AppInMemory> listedApps,
    String groupBy,
    List<String?> listedGroups,
    Map<String?, List<int>> grouped,
    SettingsProvider settingsProvider,
    AppsProvider appsProvider,
  ) {
    return groupBy != GroupByMode.none.name &&
            !(listedGroups.isEmpty ||
                (listedGroups.length == 1 && listedGroups[0] == null))
        ? SliverList(
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                return _getGroupCollapsibleTile(
                  index,
                  context,
                  listedApps,
                  groupBy,
                  listedGroups,
                  grouped,
                  settingsProvider,
                  appsProvider,
                );
              },
              childCount: listedGroups.length,
              addAutomaticKeepAlives: false,
            ),
          )
        : SliverList(
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                return _appTileCard(
                  index,
                  context,
                  listedApps,
                  settingsProvider,
                  appsProvider,
                );
              },
              childCount: listedApps.length,
              addAutomaticKeepAlives: false,
            ),
          );
  }

  Widget _getSearchBarSliver(
    BuildContext context,
    SettingsProvider settingsProvider,
    List<AppInMemory> listedApps,
  ) {
    final isFilterOff = filter.isIdenticalTo(neutralFilter, settingsProvider);
    final trailing = <Widget>[
      _getSelectAllButton(context, listedApps),
      if (!isFilterOff)
        IconButton(
          tooltip: '${tr('filter')} - ${tr('remove')}',
          onPressed: () => clearSearchAndFilter(),
          icon: const Icon(Icons.filter_alt_off_outlined),
        ),
      IconButton(
        tooltip: tr('filterApps'),
        onPressed: () => showFilterDialog(context),
        icon: const Icon(Icons.filter_list_rounded),
      ),
    ];
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: settingsProvider.isTV
            ? _TVSearchBar(
                controller: searchController,
                onChanged: onSearchChanged,
                trailing: trailing,
                hintText: tr('search'),
              )
            : SearchBar(
                controller: searchController,
                hintText: tr('search'),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 16),
                ),
                leading: const Icon(Icons.search_rounded),
                trailing: trailing,
                onChanged: (value) {
                  onSearchChanged(value);
                },
              ),
      ),
    );
  }

  Widget _getUpdateBannerSliver(
    BuildContext context,
    AppsProvider appsProvider,
    SettingsProvider settingsProvider,
    List<String> existingUpdateIdsAllOrSelected,
    List<String> newInstallIdsAllOrSelected,
    List<String> trackOnlyUpdateIdsAllOrSelected,
  ) {
    final mode = settingsProvider.actionBannerMode;
    if (mode == ActionBannerMode.none) {
      return const SliverToBoxAdapter(child: SizedBox(width: double.infinity));
    }
    final onObtain =
        mode == ActionBannerMode.updatesOnly &&
            existingUpdateIdsAllOrSelected.isEmpty
        ? null
        : massObtainCallback(
            context,
            existingUpdateIdsAllOrSelected,
            newInstallIdsAllOrSelected,
            trackOnlyUpdateIdsAllOrSelected,
          );
    final cs = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: AnimatedSize(
        duration: ExpressiveMotion.medium,
        curve: ExpressiveMotion.emphasized,
        alignment: Alignment.topCenter,
        child: onObtain == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ConnectedCard(
                  color: cs.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.system_update_alt_rounded,
                          color: cs.onPrimaryContainer,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            selectedAppIds.isEmpty
                                ? tr('installUpdateApps')
                                : tr('installUpdateSelectedApps'),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: cs.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: onObtain,
                          child: Text(tr('update')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _getLoadingWidgets(
    BuildContext context,
    AppsProvider appsProvider,
    List<AppInMemory> listedApps,
  ) {
    if (appsProvider.loadingApps && appsProvider.apps.isEmpty) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: CircularProgressIndicator(
              strokeCap: StrokeCap.round,
              strokeWidth: 6,
            ),
          ),
        ),
      ];
    }
    return [
      if (appsProvider.loadingApps && listedApps.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(32, 0, 32, 8),
            child: LinearProgressIndicator(),
          ),
        ),
      if (listedApps.isEmpty)
        SliverFillRemaining(
          child: EmptyState(
            icon: appsProvider.apps.isEmpty
                ? Icons.apps_outlined
                : Icons.search_off_rounded,
            message: appsProvider.apps.isEmpty
                ? tr('noApps')
                : tr('noAppsForFilter'),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final appsProvider = context.watch<AppsProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final sourceProvider = context.read<SourceProvider>();

    if (!appsProvider.loadingApps &&
        appsProvider.apps.isNotEmpty &&
        settingsProvider.checkJustStarted() &&
        settingsProvider.checkOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        refreshIndicatorKey.currentState?.show();
      });
    }

    final apps = appsProvider.getAppValues().toList();
    final allAppIds = apps.map((e) => e.app.id).toSet();
    final localSelected = selectedAppIds.where(allAppIds.contains).toSet();
    if (localSelected.length != selectedAppIds.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final freshListedIds = appsProvider
              .getAppValues()
              .map((e) => e.app.id)
              .toSet();
          setState(() {
            selectedAppIds = selectedAppIds
                .where(freshListedIds.contains)
                .toSet();
          });
          widget.onSelectionChanged?.call(selectedAppIds.isNotEmpty);
        }
      });
    }

    final existingUpdates = appsProvider
        .findAppIdsWithPendingUpdates(installedOnly: true)
        .toSet();
    final listedApps = getFilteredAndSortedApps(
      List<AppInMemory>.from(apps),
      existingUpdates,
    );

    final listedAppIdSet2 = listedApps.map((e) => e.app.id).toSet();

    var existingUpdateIdsAllOrSelected = existingUpdates
        .where(
          (element) => selectedAppIds.isEmpty
              ? listedAppIdSet2.contains(element)
              : selectedAppIds.contains(element),
        )
        .toList();
    var newInstallIdsAllOrSelected = appsProvider
        .findAppIdsWithPendingUpdates(nonInstalledOnly: true)
        .where(
          (element) => selectedAppIds.isEmpty
              ? listedAppIdSet2.contains(element)
              : selectedAppIds.contains(element),
        )
        .toList();

    final List<String> trackOnlyUpdateIdsAllOrSelected = [];
    for (var id in existingUpdateIdsAllOrSelected) {
      if (appsProvider.apps[id]!.app.settings.getBool('trackOnly')) {
        trackOnlyUpdateIdsAllOrSelected.add(id);
      }
    }
    for (var id in newInstallIdsAllOrSelected) {
      if (appsProvider.apps[id]!.app.settings.getBool('trackOnly') &&
          !trackOnlyUpdateIdsAllOrSelected.contains(id)) {
        trackOnlyUpdateIdsAllOrSelected.add(id);
      }
    }
    existingUpdateIdsAllOrSelected = existingUpdateIdsAllOrSelected
        .where((id) => !trackOnlyUpdateIdsAllOrSelected.contains(id))
        .toList();
    newInstallIdsAllOrSelected = newInstallIdsAllOrSelected
        .where((id) => !trackOnlyUpdateIdsAllOrSelected.contains(id))
        .toList();

    final groupBy = settingsProvider.groupBy;
    final grouped = <String?, List<int>>{};
    if (groupBy == GroupByMode.category.name) {
      for (var i = 0; i < listedApps.length; i++) {
        final app = listedApps[i];
        if (app.app.categories.isEmpty) {
          grouped.putIfAbsent(null, () => []).add(i);
        } else {
          for (final cat in app.app.categories) {
            grouped.putIfAbsent(cat, () => []).add(i);
          }
        }
      }
    } else if (groupBy == GroupByMode.source.name) {
      final sourceNames = {
        for (final s in sourceProvider.sources) s.sourceIdentifier: s.name,
      };
      for (var i = 0; i < listedApps.length; i++) {
        final label =
            sourceNames[listedApps[i].sourceType] ??
            listedApps[i].sourceType ??
            tr('noSource');
        grouped.putIfAbsent(label, () => []).add(i);
      }
    }
    final listedGroups = grouped.keys.toList();
    listedGroups.sort((a, b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

    return PopScope(
      canPop: selectedAppIds.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          clearSelected();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: RefreshIndicator(
            key: refreshIndicatorKey,
            onRefresh: refresh,
            child: Scrollbar(
              interactive: true,
              controller: scrollController,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                controller: scrollController,
                slivers: <Widget>[
                  CustomAppBar(
                    title: tr('appsString'),
                    actions: [
                      IconButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SettingsPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.settings_outlined),
                        tooltip: tr('settings'),
                      ),
                    ],
                  ),
                  if (appsProvider.apps.isNotEmpty)
                    _getSearchBarSliver(context, settingsProvider, listedApps),
                  if (appsProvider.apps.isNotEmpty)
                    _getUpdateBannerSliver(
                      context,
                      appsProvider,
                      settingsProvider,
                      existingUpdateIdsAllOrSelected,
                      newInstallIdsAllOrSelected,
                      trackOnlyUpdateIdsAllOrSelected,
                    ),
                  ..._getLoadingWidgets(context, appsProvider, listedApps),
                  const _RefreshProgressBar(),
                  _getDisplayedList(
                    context,
                    listedApps,
                    groupBy,
                    listedGroups,
                    grouped,
                    settingsProvider,
                    appsProvider,
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 96,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void openAppById(String appId) {
    final AppInMemory? app = context.read<AppsProvider>().apps[appId];

    if (app == null) {
      return;
    }

    if (widget.onAppSelected != null) {
      widget.onAppSelected!(app.app.id);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (BuildContext context) => AppPage(appId: app.app.id),
        ),
      );
    }
  }

  void showSelectedAppActions() {
    if (!mounted) return;
    final listedApps = context.read<AppsProvider>().getAppValues().toList();
    final selectedApps = listedApps
        .map((e) => e.app)
        .where((a) => selectedAppIds.contains(a.id))
        .toSet();
    if (selectedApps.isNotEmpty) {
      showMoreOptionsBottomSheet(context, selectedApps);
    }
  }
}

class _RefreshProgressBar extends StatelessWidget {
  const _RefreshProgressBar();

  @override
  Widget build(BuildContext context) {
    final progressNotifier = context.read<AppsProvider>().refreshProgress;
    return ValueListenableBuilder<double?>(
      valueListenable: progressNotifier,
      builder: (context, refreshProgress, _) {
        if (refreshProgress == null) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
            child: LinearProgressIndicator(value: refreshProgress),
          ),
        );
      },
    );
  }
}

class _BulkUpdateDialog extends StatefulWidget {
  final List<String> existingUpdateIds;
  final List<String> newInstallIds;
  final List<String> trackOnlyUpdateIds;
  final int totalApps;
  final Map<String, AppInMemory> apps;

  const _BulkUpdateDialog({
    required this.existingUpdateIds,
    required this.newInstallIds,
    required this.trackOnlyUpdateIds,
    required this.totalApps,
    required this.apps,
  });

  @override
  State<_BulkUpdateDialog> createState() => _BulkUpdateDialogState();
}

class _BulkUpdateDialogState extends State<_BulkUpdateDialog> {
  late Set<String> selectedIds;

  @override
  void initState() {
    super.initState();
    selectedIds = {...widget.existingUpdateIds, ...widget.trackOnlyUpdateIds};
    if (widget.existingUpdateIds.isEmpty) {
      selectedIds.addAll(widget.newInstallIds);
    }
  }

  bool get allSelected => selectedIds.length == widget.totalApps;

  void _toggleAll() {
    setState(() {
      if (allSelected) {
        selectedIds.clear();
      } else {
        selectedIds = {
          ...widget.existingUpdateIds,
          ...widget.newInstallIds,
          ...widget.trackOnlyUpdateIds,
        };
      }
    });
  }

  Widget _sectionHeader(String label, List<String> ids, ColorScheme cs) {
    if (ids.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
          ),
          Text(
            ' (${ids.length})',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _appCheckRow(String id, ColorScheme cs) {
    final aim = widget.apps[id];
    if (aim == null) return const SizedBox.shrink();
    final isNewInstall = aim.app.installedVersion == null;
    final isUpdate =
        aim.app.installedVersion != null &&
        aim.app.installedVersion != aim.app.latestVersion;
    final versionLabel = isUpdate
        ? '${aim.app.installedVersion} → ${aim.app.latestVersion}'
        : aim.app.latestVersion;
    return CheckboxListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 4, right: 4),
      visualDensity: VisualDensity.compact,
      value: selectedIds.contains(id),
      onChanged: (checked) {
        setState(() {
          if (checked == true) {
            selectedIds.add(id);
          } else {
            selectedIds.remove(id);
          }
        });
      },
      secondary: AppIcon(
        bytes: aim.icon,
        size: 36,
        radius: 8,
        dimmed: isNewInstall,
      ),
      title: Text(
        aim.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (aim.author.isNotEmpty)
            Text(
              tr('byX', args: [aim.author]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          if (versionLabel.isNotEmpty)
            Text(
              versionLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
        ],
      ),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      scrollable: true,
      title: Text(
        tr('changeX', args: [plural('apps', widget.totalApps).toLowerCase()]),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: allSelected,
                  tristate: selectedIds.isNotEmpty && !allSelected,
                  onChanged: (_) => _toggleAll(),
                  visualDensity: VisualDensity.compact,
                ),
                TextButton(
                  onPressed: _toggleAll,
                  child: Text(
                    allSelected
                        ? tr('deselectX', args: [widget.totalApps.toString()])
                        : tr('selectAll'),
                  ),
                ),
              ],
            ),
            _sectionHeader(tr('updates'), widget.existingUpdateIds, cs),
            ...widget.existingUpdateIds.map((id) => _appCheckRow(id, cs)),
            _sectionHeader(tr('nonInstalledApps'), widget.newInstallIds, cs),
            ...widget.newInstallIds.map((id) => _appCheckRow(id, cs)),
            if (widget.trackOnlyUpdateIds.isNotEmpty) ...[
              _sectionHeader(tr('trackOnly'), widget.trackOnlyUpdateIds, cs),
              ...widget.trackOnlyUpdateIds.map((id) => _appCheckRow(id, cs)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: context.read<SettingsProvider>().isTV,
          onPressed: () {
            Navigator.of(context).pop(null);
          },
          child: Text(tr('cancel')),
        ),
        FilledButton(
          onPressed: selectedIds.isEmpty
              ? null
              : () {
                  context.read<SettingsProvider>().selectionClick();
                  Navigator.of(context).pop(selectedIds);
                },
          child: Text(tr('continue')),
        ),
      ],
    );
  }
}

class _TVSearchBar extends StatefulWidget {
  const _TVSearchBar({
    required this.controller,
    required this.onChanged,
    required this.trailing,
    required this.hintText,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final List<Widget> trailing;
  final String hintText;

  @override
  State<_TVSearchBar> createState() => _TVSearchBarState();
}

class _TVSearchBarState extends State<_TVSearchBar> {
  final FocusNode _textFocus = FocusNode();

  @override
  void dispose() {
    _textFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TvTextFieldFocus(
          textFocusNode: _textFocus,
          borderRadius: 28,
          child: TextField(
            focusNode: _textFocus,
            controller: widget.controller,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              hintText: widget.hintText,
              prefixIcon: const Icon(Icons.search_rounded),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(28)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: widget.trailing,
        ),
      ],
    );
  }
}
