import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/app_list_builder.dart';
import 'package:obtainium/components/app_list_tile.dart';
import 'package:obtainium/components/category_editor.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/components/motion.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/pages/app.dart';
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
  AppsFilter filter = AppsFilter();
  final AppsFilter neutralFilter = AppsFilter();
  Set<String> selectedAppIds = {};
  Set<String?> collapsedCategories = {};
  DateTime? refreshingSince;

  // Memoizes the (filter -> sort -> reorder) result so it is only recomputed
  // when an input that affects the list contents/order changes — not on every
  // unrelated rebuild (e.g. download-progress ticks, which mutate apps in
  // place and are reflected live by the cached AppInMemory references).
  int? _pipelineSig;
  List<AppInMemory>? _pipelineResult;

  // Debounces search-field input so rapid typing doesn't re-run the pipeline on
  // every keystroke.
  Timer? _searchDebounce;

  void clearSelected() {
    setState(() {
      selectedAppIds.clear();
    });
    widget.onSelectionChanged?.call(selectedAppIds.isNotEmpty);
  }

  void selectThese(List<App> apps) {
    if (selectedAppIds.isEmpty) {
      setState(() {
        for (var a in apps) {
          selectedAppIds.add(a.id);
        }
      });
      widget.onSelectionChanged?.call(selectedAppIds.isNotEmpty);
    }
  }

  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  final ScrollController scrollController = ScrollController();
  final TextEditingController searchController = TextEditingController();

  @override
  void dispose() {
    _searchDebounce?.cancel();
    scrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  int _pipelineSignature(List<AppInMemory> apps, SettingsProvider sp) {
    final parts = <Object?>[
      filter.nameFilter,
      filter.authorFilter,
      filter.idFilter,
      filter.includeUptodate,
      filter.includeNonInstalled,
      Object.hashAll(filter.categoryFilter),
      filter.sourceFilter,
      sp.sortColumn.index,
      sp.sortOrder.index,
      sp.pinUpdates,
      sp.buryNonInstalled,
      apps.length,
    ];
    for (final a in apps) {
      final app = a.app;
      parts.addAll(<Object?>[
        app.id,
        a.name,
        a.author,
        // installedVersion/latestVersion determine hasUpdate, the version text,
        // filtering (up-to-date / not-installed) and reorder (updates first), so
        // the cached pipeline result must invalidate when either changes -
        // otherwise an update check would leave stale tiles with no update
        // button or swipe-to-update.
        app.installedVersion,
        app.latestVersion,
        app.releaseDate,
        app.pinned,
        Object.hashAll(app.categories),
        app.hasPendingRepoRename,
        app.overrideSource,
        app.additionalSettings['trackOnly'] == true,
      ]);
    }
    return Object.hashAll(parts);
  }

  /// Builds the "install/update all" action callback (or null when there's
  /// nothing actionable / a download is in progress). Extracted from [build]
  /// to keep that method focused; behaviour is identical to the previous inline
  /// closure (the captured build-locals are now passed in as parameters).
  VoidCallback? _massObtainCallback(
    BuildContext context,
    AppsProvider appsProvider,
    SettingsProvider settingsProvider,
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
            List<GeneratedFormItem> formItems = [];
            if (existingUpdateIdsAllOrSelected.isNotEmpty) {
              formItems.add(
                GeneratedFormSwitch(
                  'updates',
                  label: tr(
                    'updateX',
                    args: [
                      plural(
                        'apps',
                        existingUpdateIdsAllOrSelected.length,
                      ).toLowerCase(),
                    ],
                  ),
                  defaultValue: true,
                ),
              );
            }
            if (newInstallIdsAllOrSelected.isNotEmpty) {
              formItems.add(
                GeneratedFormSwitch(
                  'installs',
                  label: tr(
                    'installX',
                    args: [
                      plural(
                        'apps',
                        newInstallIdsAllOrSelected.length,
                      ).toLowerCase(),
                    ],
                  ),
                  defaultValue: existingUpdateIdsAllOrSelected.isEmpty,
                ),
              );
            }
            if (trackOnlyUpdateIdsAllOrSelected.isNotEmpty) {
              formItems.add(
                GeneratedFormSwitch(
                  'trackonlies',
                  label: tr(
                    'markXTrackOnlyAsUpdated',
                    args: [
                      plural('apps', trackOnlyUpdateIdsAllOrSelected.length),
                    ],
                  ),
                  defaultValue:
                      existingUpdateIdsAllOrSelected.isEmpty &&
                      newInstallIdsAllOrSelected.isEmpty,
                ),
              );
            }
            showDialog<Map<String, dynamic>?>(
              context: context,
              builder: (BuildContext ctx) {
                var totalApps =
                    existingUpdateIdsAllOrSelected.length +
                    newInstallIdsAllOrSelected.length +
                    trackOnlyUpdateIdsAllOrSelected.length;
                return GeneratedFormModal(
                  title: tr(
                    'changeX',
                    args: [plural('apps', totalApps).toLowerCase()],
                  ),
                  items: formItems.map((e) => [e]).toList(),
                  initValid: true,
                );
              },
            ).then((values) async {
              if (values != null) {
                if (values.isEmpty) {
                  values = getDefaultValuesFromFormItems([formItems]);
                }
                bool shouldInstallUpdates = values['updates'] == true;
                bool shouldInstallNew = values['installs'] == true;
                bool shouldMarkTrackOnlies = values['trackonlies'] == true;
                List<String> toInstall = [];
                if (shouldInstallUpdates) {
                  toInstall.addAll(existingUpdateIdsAllOrSelected);
                }
                if (shouldInstallNew) {
                  toInstall.addAll(newInstallIdsAllOrSelected);
                }
                if (shouldMarkTrackOnlies) {
                  toInstall.addAll(trackOnlyUpdateIdsAllOrSelected);
                }
                appsProvider
                    .downloadAndInstallLatestApps(
                      toInstall,
                      globalNavigatorKey.currentContext,
                    )
                    .then((value) {
                      if (value.isNotEmpty) {
                        if (context.mounted) {
                          if (shouldInstallUpdates) {
                            showMessage(tr('appsUpdated'), context);
                          }
                          var np = context.read<NotificationsProvider>();
                          np.cancel(UpdateNotification([]).id);
                          np.cancel(SilentUpdateAttemptNotification([], id: value[0].hashCode).id);
                        }
                      }
                    })
                    .catchError((e) {
                      if (context.mounted) showError(e, context);
                    });
              }
            });
          };
  }

  List<AppInMemory> _getFilteredAndSortedApps(
    List<AppInMemory> listedApps,
    AppsFilter filter,
    SettingsProvider settingsProvider,
    Set<String> existingUpdates,
    int pipelineSig,
  ) {
    if (pipelineSig == _pipelineSig && _pipelineResult != null) {
      return _pipelineResult!;
    }
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
    _pipelineSig = pipelineSig;
    _pipelineResult = result;
    return result;
  }

  void _toggleAppSelected(App app) {
    setState(() {
      if (selectedAppIds.contains(app.id)) {
        selectedAppIds.remove(app.id);
      } else {
        selectedAppIds.add(app.id);
      }
    });
    widget.onSelectionChanged?.call(selectedAppIds.isNotEmpty);
  }

  Future<List<App>> _refresh(
    BuildContext context,
    AppsProvider appsProvider,
    SettingsProvider settingsProvider,
  ) {
    settingsProvider.lightImpact();
    setState(() {
      refreshingSince = DateTime.now();
    });
    return appsProvider
        .checkUpdates()
        .catchError((e) {
          if (context.mounted) showError(e is CheckUpdatesException ? e.errors : e, context);
          return <App>[];
        })
        .whenComplete(() {
          if (!mounted) return;
          setState(() {
            refreshingSince = null;
          });
        });
  }

  List<Widget> _getLoadingWidgets(
    BuildContext context,
    AppsProvider appsProvider,
    List<AppInMemory> listedApps,
  ) {
    return [
      if (listedApps.isEmpty)
        SliverFillRemaining(
          child: EmptyState(
            icon: appsProvider.apps.isEmpty
                ? (appsProvider.loadingApps
                      ? Icons.hourglass_empty_rounded
                      : Icons.apps_outlined)
                : Icons.search_off_rounded,
            message: appsProvider.apps.isEmpty
                ? appsProvider.loadingApps
                      ? tr('pleaseWait')
                      : tr('noApps')
                : tr('noAppsForFilter'),
          ),
        ),
      if (refreshingSince != null || appsProvider.loadingApps)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
            child: LinearProgressIndicator(
              value: appsProvider.loadingApps
                  ? null
                  : appsProvider.apps.values
                            .where(
                              (element) =>
                                  !(element.app.lastUpdateCheck?.isBefore(
                                        refreshingSince!,
                                      ) ??
                                      true),
                            )
                            .length /
                        (appsProvider.apps.isNotEmpty
                            ? appsProvider.apps.length
                            : 1),
            ),
          ),
        ),
    ];
  }

  Widget _buildTile(
    int index,
    BuildContext context,
    List<AppInMemory> listedApps,
    SettingsProvider settingsProvider,
    AppsProvider appsProvider,
  ) {
    final aim = listedApps[index];
    final app = aim.app;
    return AppListTile(
      appInMemory: aim,
      settingsProvider: settingsProvider,
      appsProvider: appsProvider,
      multiSelected: selectedAppIds.contains(app.id),
      detailSelected: widget.selectedAppId == app.id,
      autofocus: index == 0 && settingsProvider.isTV,
      onToggleSelected: () => _toggleAppSelected(app),
      onTap: () {
        if (selectedAppIds.isNotEmpty) {
          _toggleAppSelected(app);
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
        ),
      ),
    );
  }

  Widget _getCategoryCollapsibleTile(
    int index,
    BuildContext context,
    List<AppInMemory> listedApps,
    List<String?> listedCategories,
    Map<String?, List<int>> groupedByCategory,
    SettingsProvider settingsProvider,
    AppsProvider appsProvider,
  ) {
    final category = listedCategories[index];
    final appIndices = groupedByCategory[category] ?? [];
    final expanded = !collapsedCategories.contains(category);
    return AppListCategorySection(
      category: category,
      expanded: expanded,
      appCount: appIndices.length,
      onToggle: () {
        setState(() {
          if (expanded) {
            collapsedCategories.add(category);
          } else {
            collapsedCategories.remove(category);
          }
        });
      },
      buildTiles: () => [
        for (final i in appIndices)
          _buildTile(i, context, listedApps, settingsProvider, appsProvider),
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
    List<String?> listedCategories,
    Map<String?, List<int>> groupedByCategory,
    SettingsProvider settingsProvider,
    AppsProvider appsProvider,
  ) {
    return settingsProvider.groupByCategory &&
            !(listedCategories.isEmpty ||
                (listedCategories.length == 1 && listedCategories[0] == null))
        ? SliverList(
            delegate: SliverChildBuilderDelegate((
              BuildContext context,
              int index,
            ) {
              return _getCategoryCollapsibleTile(
                index,
                context,
                listedApps,
                listedCategories,
                groupedByCategory,
                settingsProvider,
                appsProvider,
              );
            }, childCount: listedCategories.length),
          )
        : SliverList(
            delegate: SliverChildBuilderDelegate((
              BuildContext context,
              int index,
            ) {
              return _appTileCard(
                index,
                context,
                listedApps,
                settingsProvider,
                appsProvider,
              );
            }, childCount: listedApps.length),
          );
  }

  Widget _getSearchBarSliver(
    BuildContext context,
    SettingsProvider settingsProvider,
    List<AppInMemory> listedApps,
  ) {
    var isFilterOff = filter.isIdenticalTo(neutralFilter, settingsProvider);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SearchBar(
          controller: searchController,
          hintText: tr('search'),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16),
          ),
          leading: const Icon(Icons.search_rounded),
          trailing: [
            _getSelectAllButton(context, listedApps),
            if (!isFilterOff)
              IconButton(
                tooltip: '${tr('filter')} - ${tr('remove')}',
                onPressed: () {
                  _searchDebounce?.cancel();
                  setState(() {
                    filter = AppsFilter();
                    searchController.clear();
                  });
                },
                icon: const Icon(Icons.filter_alt_off_outlined),
              ),
            IconButton(
              tooltip: tr('filterApps'),
              onPressed: () => _showFilterDialog(context),
              icon: const Icon(Icons.filter_list_rounded),
            ),
          ],
          onChanged: (value) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 300), () {
              if (mounted) {
                setState(() {
                  filter.nameFilter = value;
                });
              }
            });
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
    var onObtain = _massObtainCallback(
      context,
      appsProvider,
      settingsProvider,
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: ConnectedCard(
                  color: cs.primaryContainer,
                  padding: null,
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

  @override
  Widget build(BuildContext context) {
    final appsProvider = context.read<AppsProvider>();
    final settingsProvider = context.watch<SettingsProvider>();

    // Watch for changes that affect the pipeline result (app data changes,
    // loading state) without triggering rebuilds on every download tick.
    // Rebuild when loading state changes (the value itself is unused; the
    // subscription to loadingApps is what triggers builds on state transitions).
    context.select((AppsProvider p) => p.loadingApps);
    final pipelineSig = context.select(
      (AppsProvider p) =>
          _pipelineSignature(p.getAppValues().toList(), settingsProvider),
    );

    var listedApps = appsProvider.getAppValues().toList();

    if (!appsProvider.loadingApps &&
        appsProvider.apps.isNotEmpty &&
        settingsProvider.checkJustStarted() &&
        settingsProvider.checkOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshIndicatorKey.currentState?.show();
      });
    }

    var listedAppIdSet = listedApps.map((e) => e.app.id).toSet();
    final hadSelection = selectedAppIds.isNotEmpty;
    final localSelected = selectedAppIds.where(listedAppIdSet.contains).toSet();
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
          if (hadSelection != selectedAppIds.isNotEmpty) {
            widget.onSelectionChanged?.call(selectedAppIds.isNotEmpty);
          }
        }
      });
    }

    var existingUpdates = appsProvider.findAppIdsWithPendingUpdates(installedOnly: true);
    listedApps = _getFilteredAndSortedApps(
      listedApps,
      filter,
      settingsProvider,
      existingUpdates.toSet(),
      pipelineSig,
    );

    var existingUpdateIdsAllOrSelected = existingUpdates
        .where(
          (element) => selectedAppIds.isEmpty
              ? listedAppIdSet.contains(element)
              : selectedAppIds.contains(element),
        )
        .toList();
    var newInstallIdsAllOrSelected = appsProvider
        .findAppIdsWithPendingUpdates(nonInstalledOnly: true)
        .where(
          (element) => selectedAppIds.isEmpty
              ? listedAppIdSet.contains(element)
              : selectedAppIds.contains(element),
        )
        .toList();

    List<String> trackOnlyUpdateIdsAllOrSelected = [];
    for (var id in existingUpdateIdsAllOrSelected) {
      if (appsProvider.apps[id]!.app.additionalSettings['trackOnly'] == true) {
        trackOnlyUpdateIdsAllOrSelected.add(id);
      }
    }
    for (var id in newInstallIdsAllOrSelected) {
      if (appsProvider.apps[id]!.app.additionalSettings['trackOnly'] == true &&
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

    final groupedByCategory = <String?, List<int>>{};
    for (var i = 0; i < listedApps.length; i++) {
      final app = listedApps[i];
      if (app.app.categories.isEmpty) {
        groupedByCategory.putIfAbsent(null, () => []).add(i);
      } else {
        for (final cat in app.app.categories) {
          groupedByCategory.putIfAbsent(cat, () => []).add(i);
        }
      }
    }
    var listedCategories = groupedByCategory.keys.toList();
    listedCategories.sort((a, b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

    Set<App> selectedApps = listedApps
        .map((e) => e.app)
        .where((a) => selectedAppIds.contains(a.id))
        .toSet();

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
          // Tapping outside the search field (empty list area, background,
          // etc.) defocuses it / dismisses the keyboard. Taps on interactive
          // children (the search bar, list tiles) are handled by those
          // children, so they don't trigger this.
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: RefreshIndicator(
            key: _refreshIndicatorKey,
            onRefresh: () => _refresh(context, appsProvider, settingsProvider),
            child: Scrollbar(
              interactive: true,
              controller: scrollController,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                controller: scrollController,
                slivers: <Widget>[
                  CustomAppBar(title: tr('appsString')),
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
                  _getDisplayedList(
                    context,
                    listedApps,
                    listedCategories,
                    groupedByCategory,
                    settingsProvider,
                    appsProvider,
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 88)),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: selectedAppIds.isNotEmpty
            ? FloatingActionButton(
                onPressed: () => _showMoreOptionsBottomSheet(
                  context,
                  selectedApps,
                  appsProvider,
                  settingsProvider,
                ),
                tooltip: tr('more'),
                child: const Icon(Icons.more_vert),
              )
            : null,
      ),
    );
  }

  Future<void> _showFilterDialog(BuildContext context) async {
    var pendingCategories = {...filter.categoryFilter};
    var values = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (BuildContext ctx) {
        var vals = filter.toFormValuesMap();
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
                defaultValue: vals['appName'],
              ),
            ],
            [
              GeneratedFormTextField(
                'author',
                label: tr('author'),
                required: false,
                defaultValue: vals['author'],
              ),
            ],
            [
              GeneratedFormTextField(
                'appId',
                label: tr('appId'),
                required: false,
                defaultValue: vals['appId'],
              ),
            ],
            [
              GeneratedFormSwitch(
                'upToDateApps',
                label: tr('upToDateApps'),
                defaultValue: vals['upToDateApps'],
              ),
            ],
            [
              GeneratedFormSwitch(
                'nonInstalledApps',
                label: tr('nonInstalledApps'),
                defaultValue: vals['nonInstalledApps'],
              ),
            ],
            [
              GeneratedFormDropdown(
                'sourceFilter',
                label: tr('appSource'),
                defaultValue: filter.sourceFilter,
                [
                  MapEntry('', tr('none')),
                  ...SourceProvider().sources.map(
                    (e) => MapEntry(e.name, e.name),
                  ),
                ],
              ),
            ],
          ],
          additionalWidgets: [
            const SizedBox(height: 16),
            ConnectedCard(
              padding: null,
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
      setState(() {
        filter.setFormValuesFromMap(values);
        filter.categoryFilter = pendingCategories;
      });
    }
  }

  VoidCallback _launchCategorizeDialogCallback(
    BuildContext context,
    Set<App> selectedApps,
    AppsProvider appsProvider,
    SettingsProvider settingsProvider,
  ) {
    return () async {
      try {
        Set<String>? preselected;
        var showPrompt = false;
        for (var element in selectedApps) {
          var currentCats = element.categories.toSet();
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
            appsProvider.saveApps(
              selectedApps.map((e) {
                e.categories = pendingCategories.toList();
                return e;
              }).toList(),
            );
          }
        }
      } catch (err) {
        if (context.mounted) showError(err, context);
      }
    };
  }

  Future<void> _showMassMarkDialog(
    BuildContext context,
    Set<App> selectedApps,
    AppsProvider appsProvider,
    SettingsProvider settingsProvider,
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
      );
      if (!confirmed) return;
      settingsProvider.selectionClick();
      appsProvider.saveApps(
        selectedApps.map((a) {
          if (a.installedVersion != null &&
              !appsProvider.isVersionDetectionPossible(
                appsProvider.apps[a.id],
              )) {
            a.installedVersion = a.latestVersion;
          }
          return a;
        }).toList(),
      );
    } catch (e) {
      if (context.mounted) showError(e, context);
    }
  }

  void _pinSelectedApps(
    Set<App> selectedApps,
    AppsProvider appsProvider,
  ) {
    var pinStatus = selectedApps.where((element) => element.pinned).isEmpty;
    appsProvider.saveApps(
      selectedApps.map((e) {
        e.pinned = pinStatus;
        return e;
      }).toList(),
    );
  }

  void _showMoreOptionsBottomSheet(
    BuildContext context,
    Set<App> selectedApps,
    AppsProvider appsProvider,
    SettingsProvider settingsProvider,
  ) {
    final isPinned = selectedApps.where((e) => e.pinned).isNotEmpty;
    final hasSelection = selectedAppIds.isNotEmpty;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        Widget optionTile({
          required IconData icon,
          required String label,
          required VoidCallback? onTap,
        }) =>
            ActionListTile(
              icon: icon, label: label, onTap: onTap, autoPop: true,
            );

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                optionTile(
                  icon: Icons.delete_outline,
                  label: tr('removeSelectedApps'),
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
                      ? _launchCategorizeDialogCallback(
                          context,
                          selectedApps,
                          appsProvider,
                          settingsProvider,
                        )
                      : null,
                ),
                optionTile(
                  icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  label: isPinned ? tr('unpinFromTop') : tr('pinToTop'),
                  onTap: () => _pinSelectedApps(selectedApps, appsProvider),
                ),
                optionTile(
                  icon: Icons.share_outlined,
                  label: tr('shareSelectedAppURLs'),
                  onTap: () => _shareAppURLs(selectedApps),
                ),
                optionTile(
                  icon: Icons.link_outlined,
                  label: tr('shareAppConfigLinks'),
                  onTap: !hasSelection
                      ? null
                      : () => _shareConfigLinks(selectedApps),
                ),
                optionTile(
                  icon: Icons.file_download_outlined,
                  label: '${tr('share')} - ${tr('obtainiumExport')}',
                  onTap: !hasSelection
                      ? null
                      : () => _shareExport(appsProvider, selectedApps),
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
                          globalNavigatorKey.currentContext ?? context,
                        )
                        .catchError((e) {
                          showError(
                            e,
                            globalNavigatorKey.currentContext ?? context,
                          );
                          return <String>[];
                        });
                  },
                ),
                optionTile(
                  icon: Icons.done_all,
                  label: tr('markSelectedAppsUpdated'),
                  onTap: appsProvider.areDownloadsRunning()
                      ? null
                      : () => _showMassMarkDialog(
                          context,
                          selectedApps,
                          appsProvider,
                          settingsProvider,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _shareAppURLs(Set<App> selectedApps) {
    final buf = StringBuffer();
    for (var a in selectedApps) {
      buf.writeln(a.url);
    }
    final urls = buf.toString().trimRight();
    unawaited(SharePlus.instance
        .share(
          ShareParams(
            text: urls,
            subject: 'Obtainium - ${tr('appsString')}',
          ),
        ));
  }

  void _shareConfigLinks(Set<App> selectedApps) {
    final buf = StringBuffer();
    for (var a in selectedApps) {
      buf.writeln(
        'https://apps.obtainium.page/redirect?r=obtainium://app/${Uri.encodeComponent(jsonEncode({'id': a.id, 'url': a.url, 'author': a.author, 'name': a.name, 'preferredApkIndex': a.preferredApkIndex, 'additionalSettings': jsonEncode(a.additionalSettings), 'overrideSource': a.overrideSource}))}',
      );
    }
    unawaited(SharePlus.instance
        .share(
          ShareParams(
            text: buf.toString(),
            subject: 'Obtainium - ${tr('appsString')}',
          ),
        ));
  }

  void _shareExport(AppsProvider appsProvider, Set<App> selectedApps) {
    var encoder = const JsonEncoder.withIndent("    ");
    var exportJSON = encoder.convert(
      appsProvider.generateExportJSON(
        appIds: selectedApps.map((e) => e.id).toList(),
        overrideExportSettings: 0,
      ),
    );
    String fn =
        '${tr('obtainiumExportHyphenatedLowercase')}-${DateTime.now().toIso8601String().replaceAll(':', '-')}-count-${selectedApps.length}';
    XFile f = XFile.fromData(
      Uint8List.fromList(utf8.encode(exportJSON)),
      mimeType: 'application/json',
      name: fn,
    );
    unawaited(SharePlus.instance
        .share(
          ShareParams(
            files: [f],
            fileNameOverrides: ['$fn.json'],
          ),
        ));
  }

  void openAppById(String appId) {
    AppsProvider appsProvider = context.read<AppsProvider>();

    AppInMemory? app = appsProvider.apps[appId];

    // Should exist, since we just looked it up, but just in case...
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
}
