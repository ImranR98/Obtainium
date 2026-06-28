import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:obtainium/components/app_list_builder.dart';
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
import 'package:url_launcher/url_launcher_string.dart';

/// Matches a single bare URL, used to detect change logs that are really just a
/// link. Compiled once rather than per app tile per build.
final RegExp _changeLogUrlRegExp = RegExp(
  '(http|ftp|https)://([\\w_-]+(?:(?:\\.[\\w_-]+)+))([\\w.,@?^=%&:/~+#-]*[\\w@?^=%&/~+#-])?',
);

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

void showChangeLogDialog(
  BuildContext context,
  App app,
  String? changesUrl,
  AppSource appSource,
  String changeLog,
) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return GeneratedFormModal(
        title: tr('changes'),
        items: const [],
        message: app.latestVersion,
        additionalWidgets: [
          changesUrl != null
              ? LinkText(
                  text: changesUrl,
                  url: changesUrl,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                )
              : const SizedBox.shrink(),
          changesUrl != null
              ? const SizedBox(height: 16)
              : const SizedBox.shrink(),
          // Rendered inline (non-scrolling) so the AlertDialog's own
          // `scrollable: true` handles overflow. Nesting a scrolling Markdown
          // (a ListView viewport) here caused a layout failure ("RenderBox was
          // not laid out" on the dialog's shape).
          appSource.changeLogIfAnyIsMarkDown
              ? MarkdownBody(
                  styleSheet: MarkdownStyleSheet(
                    blockquoteDecoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                    ),
                  ),
                  data: changeLog,
                  onTapLink: (text, href, title) {
                    if (href != null) {
                      launchUrlString(
                        href.startsWith('http://') ||
                                href.startsWith('https://')
                            ? href
                            : '${Uri.parse(app.url).origin}/$href',
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  extensionSet: md.ExtensionSet(
                    md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                    [
                      md.EmojiSyntax(),
                      ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                    ],
                  ),
                )
              : Text(changeLog),
        ],
        singleNullReturnButton: tr('ok'),
      );
    },
  );
}

Null Function()? getChangeLogFn(BuildContext context, App app) {
  String? changesUrl;
  String? changeLog = app.changeLog;
  // Treat the changelog as a launchable link only when it is *only* a URL —
  // not free-text that merely contains one (e.g. APKPure changelogs), which
  // would otherwise be passed wholesale to the URL launcher and fail with
  // ACTIVITY_NOT_FOUND.
  final trimmedChangeLog = changeLog?.trim() ?? '';
  final urlMatch = _changeLogUrlRegExp.firstMatch(trimmedChangeLog);
  if (urlMatch != null &&
      urlMatch.start == 0 &&
      urlMatch.end == trimmedChangeLog.length) {
    changesUrl = trimmedChangeLog;
    changeLog = null;
  }
  if (changeLog == null && changesUrl == null) return null;
  return () {
    var appSource = SourceProvider().getSource(
      app.url,
      overrideSource: app.overrideSource,
    );
    changesUrl ??= appSource.changeLogPageFromStandardUrl(app.url);
    if (changeLog != null) {
      showChangeLogDialog(context, app, changesUrl, appSource, changeLog);
    } else if (changesUrl != null) {
      launchUrlString(changesUrl!, mode: LaunchMode.externalApplication);
    }
  };
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

  // Detects when downloads begin or end so the pipeline cache is invalidated
  // on state transitions (showing/hiding progress UI) without flushing on
  // every per-tick progress update.
  bool _downloadsWereActive = false;

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

  late final ScrollController scrollController = ScrollController();
  final TextEditingController searchController = TextEditingController();

  var sourceProvider = SourceProvider();

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
                    .catchError((e) {
                      if (context.mounted) showError(e, context);
                      return <String>[];
                    })
                    .then((value) {
                      if (value.isNotEmpty) {
                        if (context.mounted) {
                          if (shouldInstallUpdates) {
                            showMessage(tr('appsUpdated'), context);
                          }
                          var np = context.read<NotificationsProvider>();
                          np.cancel(UpdateNotification([]).id);
                        }
                      }
                    });
              }
            });
          };
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
          if (context.mounted) showError(e is Map ? e['errors'] : e, context);
          return <App>[];
        })
        .whenComplete(() {
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
    SettingsProvider settingsProvider,
    AppsProvider appsProvider,
  ) {
    final category = listedCategories[index];
    final appEntries = listedApps
        .asMap()
        .entries
        .where(
          (e) =>
              e.value.app.categories.contains(category) ||
              e.value.app.categories.isEmpty && category == null,
        )
        .toList();
    final expanded = !collapsedCategories.contains(category);
    return AppListCategorySection(
      category: category,
      expanded: expanded,
      appCount: appEntries.length,
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
        for (final e in appEntries)
          _buildTile(
            e.key,
            context,
            listedApps,
            settingsProvider,
            appsProvider,
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
    List<String?> listedCategories,
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
    var appsProvider = context.watch<AppsProvider>();
    var settingsProvider = context.watch<SettingsProvider>();
    var listedApps = appsProvider.getAppValues().toList();

    if (!appsProvider.loadingApps &&
        appsProvider.apps.isNotEmpty &&
        settingsProvider.checkJustStarted() &&
        settingsProvider.checkOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshIndicatorKey.currentState?.show();
      });
    }

    var listedAppIdSet = listedApps.map((e) => e.app.id).toSet();
    selectedAppIds = selectedAppIds.where(listedAppIdSet.contains).toSet();

    var existingUpdates = appsProvider.findExistingUpdates(installedOnly: true);

    // Invalidate the pipeline cache when downloads start or stop so the
    // UI reflects progress changes without recomputing on every tick.
    final downloadsActive = appsProvider.areDownloadsRunning();
    if (downloadsActive != _downloadsWereActive) {
      _pipelineResult = null;
      _downloadsWereActive = downloadsActive;
    }

    final pipelineSig = _pipelineSignature(listedApps, settingsProvider);
    if (pipelineSig == _pipelineSig && _pipelineResult != null) {
      listedApps = _pipelineResult!;
    } else {
      listedApps = AppListBuilder.filter(listedApps, filter, sourceProvider);
      listedApps = AppListBuilder.sort(
        listedApps,
        settingsProvider.sortColumn,
        settingsProvider.sortOrder,
      );
      listedApps = AppListBuilder.reorder(
        listedApps,
        settingsProvider.pinUpdates,
        settingsProvider.buryNonInstalled,
        existingUpdates.map((e) => e).toSet(),
      );
      _pipelineSig = pipelineSig;
      _pipelineResult = listedApps;
    }

    var existingUpdateIdsAllOrSelected = existingUpdates
        .where(
          (element) => selectedAppIds.isEmpty
              ? listedAppIdSet.contains(element)
              : selectedAppIds.contains(element),
        )
        .toList();
    var newInstallIdsAllOrSelected = appsProvider
        .findExistingUpdates(nonInstalledOnly: true)
        .where(
          (element) => selectedAppIds.isEmpty
              ? listedAppIdSet.contains(element)
              : selectedAppIds.contains(element),
        )
        .toList();

    List<String> trackOnlyUpdateIdsAllOrSelected = [];
    bool isNotTrackOnly(String id) {
      if (appsProvider.apps[id]!.app.additionalSettings['trackOnly'] == true) {
        trackOnlyUpdateIdsAllOrSelected.add(id);
        return false;
      }
      return true;
    }

    existingUpdateIdsAllOrSelected = existingUpdateIdsAllOrSelected
        .where(isNotTrackOnly)
        .toList();
    newInstallIdsAllOrSelected = newInstallIdsAllOrSelected
        .where(isNotTrackOnly)
        .toList();

    List<String?> getListedCategories() {
      final cats = <String?>{};
      for (final e in listedApps) {
        if (e.app.categories.isEmpty) {
          cats.add(null);
        } else {
          cats.addAll(e.app.categories);
        }
      }
      return cats.toList();
    }

    var listedCategories = getListedCategories();
    listedCategories.sort((a, b) {
      return a != null && b != null
          ? a.toLowerCase().compareTo(b.toLowerCase())
          : a == null
          ? 1
          : -1;
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
        body: RefreshIndicator(
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
                  settingsProvider,
                  appsProvider,
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 88)),
              ],
            ),
          ),
        ),
        floatingActionButton: selectedAppIds.isNotEmpty
            ? FloatingActionButton(
                onPressed: () => _showMoreOptions(
                  context,
                  appsProvider,
                  settingsProvider,
                  selectedApps,
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
                  ...sourceProvider.sources.map(
                    (e) => MapEntry(e.runtimeType.toString(), e.name),
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

  void _showMoreOptions(
    BuildContext context,
    AppsProvider appsProvider,
    SettingsProvider settingsProvider,
    Set<App> selectedApps,
  ) {
    launchCategorizeDialog() {
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

    showMassMarkDialog() async {
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
    }

    pinSelectedApps() {
      var pinStatus = selectedApps.where((element) => element.pinned).isEmpty;
      appsProvider.saveApps(
        selectedApps.map((e) {
          e.pinned = pinStatus;
          return e;
        }).toList(),
      );
    }

    showMoreOptionsDialog() {
      final isPinned = selectedApps.where((e) => e.pinned).isNotEmpty;
      final hasSelection = selectedAppIds.isNotEmpty;
      return showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (BuildContext ctx) {
          Widget optionTile({
            required IconData icon,
            required String label,
            required VoidCallback? onTap,
          }) {
            return ListTile(
              leading: Icon(icon),
              title: Text(label),
              enabled: onTap != null,
              onTap: onTap == null
                  ? null
                  : () {
                      Navigator.of(ctx).pop();
                      onTap();
                    },
            );
          }

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
                    onTap: hasSelection ? launchCategorizeDialog() : null,
                  ),
                  optionTile(
                    icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    label: isPinned ? tr('unpinFromTop') : tr('pinToTop'),
                    onTap: pinSelectedApps,
                  ),
                  optionTile(
                    icon: Icons.share_outlined,
                    label: tr('shareSelectedAppURLs'),
                    onTap: () {
                      String urls = '';
                      for (var a in selectedApps) {
                        urls += '${a.url}\n';
                      }
                      urls = urls.substring(0, urls.length - 1);
                      SharePlus.instance.share(
                        ShareParams(
                          text: urls,
                          subject: 'Obtainium - ${tr('appsString')}',
                        ),
                      );
                    },
                  ),
                  optionTile(
                    icon: Icons.link_outlined,
                    label: tr('shareAppConfigLinks'),
                    onTap: !hasSelection
                        ? null
                        : () {
                            String urls = '';
                            for (var a in selectedApps) {
                              urls +=
                                  'https://apps.obtainium.page/redirect?r=obtainium://app/${Uri.encodeComponent(jsonEncode({'id': a.id, 'url': a.url, 'author': a.author, 'name': a.name, 'preferredApkIndex': a.preferredApkIndex, 'additionalSettings': jsonEncode(a.additionalSettings), 'overrideSource': a.overrideSource}))}\n\n';
                            }
                            SharePlus.instance.share(
                              ShareParams(
                                text: urls,
                                subject: 'Obtainium - ${tr('appsString')}',
                              ),
                            );
                          },
                  ),
                  optionTile(
                    icon: Icons.file_download_outlined,
                    label: '${tr('share')} - ${tr('obtainiumExport')}',
                    onTap: !hasSelection
                        ? null
                        : () {
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
                            SharePlus.instance.share(
                              ShareParams(
                                files: [f],
                                fileNameOverrides: ['$fn.json'],
                              ),
                            );
                          },
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
                          .catchError(
                            // ignore: invalid_return_type_for_catch_error
                            (e) => showError(
                              e,
                              globalNavigatorKey.currentContext ?? context,
                            ),
                          );
                    },
                  ),
                  optionTile(
                    icon: Icons.done_all,
                    label: tr('markSelectedAppsUpdated'),
                    onTap: appsProvider.areDownloadsRunning()
                        ? null
                        : showMassMarkDialog,
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    showMoreOptionsDialog();
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

class AppIconWidget extends StatefulWidget {
  final String appId;
  final bool installed;
  final AppsProvider appsProvider;

  const AppIconWidget({
    super.key,
    required this.appId,
    required this.installed,
    required this.appsProvider,
  });

  @override
  State<AppIconWidget> createState() => _AppIconWidgetState();
}

class _AppIconWidgetState extends State<AppIconWidget> {
  late final Future<void> _iconFuture;

  @override
  void initState() {
    super.initState();
    _iconFuture = widget.appsProvider.updateAppIcon(widget.appId);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.appsProvider.apps[widget.appId]?.name ?? '';
    return Semantics(
      label: name,
      button: true,
      // Mirror the icon's long-press gesture (open the app's detail/web view)
      // so assistive technologies can reach it; the InkWell gesture itself is
      // invisible to screen readers.
      onLongPress: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                AppPage(appId: widget.appId, showOppositeOfPreferredView: true),
          ),
        );
      },
      child: InkWell(
        child: FutureBuilder(
          future: _iconFuture,
          builder: (ctx, val) => AppIcon(
            bytes: widget.appsProvider.apps[widget.appId]?.icon,
            size: 44,
            dimmed: !widget.installed,
          ),
        ),
        onDoubleTap: () {
          pm.openApp(widget.appId);
        },
        onLongPress: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AppPage(
                appId: widget.appId,
                showOppositeOfPreferredView: true,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A single row in the apps list: the app's icon, name/author, version + change
/// info, swipe-to-install/update/remove, and multi-select handling. Extracted
/// from the apps page so the per-row markup lives in one focused widget rather
/// than a large closure rebuilt inside the page's build method.
class AppListTile extends StatelessWidget {
  final AppInMemory appInMemory;
  final SettingsProvider settingsProvider;
  final AppsProvider appsProvider;

  /// Whether this app is part of the current multi-selection.
  final bool multiSelected;

  /// Whether this app is the one open in the detail pane (two-pane layout).
  final bool detailSelected;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback onToggleSelected;

  const AppListTile({
    super.key,
    required this.appInMemory,
    required this.settingsProvider,
    required this.appsProvider,
    required this.multiSelected,
    required this.detailSelected,
    required this.autofocus,
    required this.onTap,
    required this.onToggleSelected,
  });

  App get _app => appInMemory.app;

  Widget _updateButton(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      color: Theme.of(context).colorScheme.primary,
      tooltip: _app.additionalSettings['trackOnly'] == true
          ? tr('markUpdated')
          : tr('update'),
      onPressed: appsProvider.areDownloadsRunning()
          ? null
          : () {
              appsProvider
                  .downloadAndInstallLatestApps([
                    _app.id,
                  ], globalNavigatorKey.currentContext)
                  .then((res) {
                    if (res.isNotEmpty && context.mounted) {
                      var np = context.read<NotificationsProvider>();
                      np.cancel(UpdateNotification([]).id);
                      np.cancel(
                        SilentUpdateAttemptNotification(
                          [],
                          id: res[0].hashCode,
                        ).id,
                      );
                    }
                  })
                  .catchError((e) {
                    if (context.mounted) showError(e, context);
                  });
            },
      icon: Icon(
        _app.additionalSettings['trackOnly'] == true
            ? Icons.check_circle_outline
            : Icons.install_mobile,
      ),
    );
  }

  String _versionText() {
    var installed = _app.installedVersion;
    var latest = _app.latestVersion;
    if (installed != null && installed != latest) {
      return '$installed → $latest';
    }
    return installed ?? tr('notInstalled');
  }

  String _changesButtonString(bool hasChangeLogFn) {
    return _app.releaseDate == null
        ? hasChangeLogFn
              ? tr('changes')
              : ''
        : DateFormat('yyyy-MM-dd').format(_app.releaseDate!.toLocal());
  }

  Widget _authorText() {
    return Text(
      tr('byX', args: [appInMemory.author]),
      maxLines: 1,
      style: TextStyle(
        overflow: TextOverflow.ellipsis,
        fontWeight: _app.pinned ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _repoMovedRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final infoColor = colorScheme.primary.withValues(alpha: 0.7);
    final textColor = colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, color: infoColor, size: 14),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              tr('repoRenamed'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: textColor) ?? TextStyle(color: textColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var showChangesFn = getChangeLogFn(context, _app);
    var hasUpdate =
        _app.installedVersion != null &&
        _app.installedVersion != _app.latestVersion;
    var isInstalling = appInMemory.downloadProgress == -1;
    final updateColor = hasUpdate
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    Widget trailingRow = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        hasUpdate ? _updateButton(context) : const SizedBox.shrink(),
        hasUpdate ? const SizedBox(width: 5) : const SizedBox.shrink(),
        HighlightableButton(
          highlight: settingsProvider.highlightTouchTargets,
          onPressed: isInstalling ? null : showChangesFn,
          label: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: math.min(
                        MediaQuery.of(context).size.width / 4,
                        160,
                      ),
                    ),
                    child: Text(
                      _versionText(),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: isVersionPseudo(_app)
                          ? TextStyle(
                              fontStyle: FontStyle.italic,
                              color: updateColor,
                            )
                          : TextStyle(color: updateColor),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isInstalling
                        ? tr('installing')
                        : _changesButtonString(showChangesFn != null),
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: updateColor,
                      decoration: isInstalling || showChangesFn == null
                          ? TextDecoration.none
                          : TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    var transparent = Colors.transparent.toARGB32();
    var categories = _app.categories;
    List<double> stops = [
      if (categories.isNotEmpty)
        ...categories.asMap().entries.map(
          (e) => ((e.key / (categories.length - 1)) - 0.0001),
        ),
      1,
    ];
    if (stops.length == 2) {
      stops[0] = 0.9999;
    }
    final appId = _app.id;
    final installed = _app.installedVersion;
    final latest = _app.latestVersion;
    final trackOnly = _app.additionalSettings['trackOnly'] == true;
    final canInstall = installed == null && !trackOnly;
    final canUpdate = installed != null && installed != latest && !trackOnly;
    final cs = Theme.of(context).colorScheme;

    // Swipe-right background: Install or Update, depending on state.
    final swipeBackground = canInstall
        ? Container(
            color: cs.primaryContainer,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.install_mobile, color: cs.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  tr('install'),
                  style: TextStyle(color: cs.onPrimaryContainer),
                ),
              ],
            ),
          )
        : canUpdate
        ? Container(
            color: cs.primaryContainer,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.system_update_alt_rounded,
                  color: cs.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  tr('update'),
                  style: TextStyle(color: cs.onPrimaryContainer),
                ),
              ],
            ),
          )
        : null;

    return Dismissible(
      key: ValueKey(appId),
      direction: appInMemory.downloadProgress == null
          ? DismissDirection.horizontal
          : DismissDirection.none,
      background: swipeBackground ?? const SizedBox.shrink(),
      secondaryBackground: Container(
        color: cs.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Swipe right — install or update (disabled if any download is running).
          if ((canInstall || canUpdate) &&
              !appsProvider.areDownloadsRunning()) {
            appsProvider.downloadAndInstallLatestApps([
              appId,
            ], globalNavigatorKey.currentContext);
          }
          return false;
        } else {
          // Swipe left — remove (delegates to the standard confirm dialog).
          return appsProvider.removeAppsWithModal(context, [_app]);
        }
      },
      onDismissed: (direction) {
        // Removal is already handled inside confirmDismiss via
        // removeAppsWithModal; nothing to do here.
      },
      child: Semantics(
        // Expose the swipe gestures (install/update and remove) to assistive
        // technologies, which can neither discover nor perform a Dismissible
        // swipe on their own.
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          if (canInstall || canUpdate)
            CustomSemanticsAction(
              label: canUpdate ? tr('update') : tr('install'),
            ): () {
              if (!appsProvider.areDownloadsRunning()) {
                appsProvider.downloadAndInstallLatestApps([
                  appId,
                ], globalNavigatorKey.currentContext);
              }
            },
          CustomSemanticsAction(label: tr('remove')): () {
            appsProvider.removeAppsWithModal(context, [_app]);
          },
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: categories.isEmpty
                ? null
                : LinearGradient(
                    stops: stops,
                    begin: const Alignment(-1, 0),
                    end: const Alignment(-0.97, 0),
                    colors: [
                      ...categories.map(
                        (e) => Color(
                          settingsProvider.categories[e] ?? transparent,
                        ).withAlpha(255),
                      ),
                      Color(transparent),
                    ],
                  ),
          ),
          child: ListTile(
            autofocus: autofocus,
            tileColor: _app.pinned
                ? Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.06)
                : Colors.transparent,
            selectedTileColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: _app.pinned ? 0.2 : 0.1),
            selected: multiSelected || detailSelected,
            onLongPress: onToggleSelected,
            leading: (settingsProvider.isTV)
                ? Checkbox(
                    value: multiSelected,
                    onChanged: (_) {
                      onToggleSelected();
                    },
                  )
                : AppIconWidget(
                    appId: _app.id,
                    installed: appInMemory.installedInfo != null,
                    appsProvider: appsProvider,
                  ),
            title: Text(
              maxLines: 1,
              appInMemory.name,
              style: TextStyle(
                overflow: TextOverflow.ellipsis,
                fontWeight: _app.pinned ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: _app.hasPendingRepoRename
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [_authorText(), _repoMovedRow(context)],
                  )
                : _authorText(),
            trailing:
                appInMemory.downloadProgress != null &&
                    appInMemory.downloadProgress! >= 0
                ? _DownloadProgressTrailing(
                    progress: appInMemory.downloadProgress!,
                  )
                : trailingRow,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

/// Compact download-progress indicator shown in an app list tile's trailing
/// slot (a small bar plus the integer percentage), kept consistent with the
/// detail page's progress UI. Extracted into its own widget so the per-row
/// markup stays focused and the percentage label is computed once.
class _DownloadProgressTrailing extends StatelessWidget {
  final double progress;
  const _DownloadProgressTrailing({required this.progress});

  @override
  Widget build(BuildContext context) {
    final label = tr('percentProgress', args: [progress.toInt().toString()]);
    return SizedBox(
      width: 56,
      child: Semantics(
        label: label,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: progress / 100),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11) ?? const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// A collapsible category header plus (when expanded) its app rows, shaped as a
/// single connected, positionally-rounded block. Tiles are built lazily via
/// [buildTiles] so collapsed categories don't construct their rows.
class AppListCategorySection extends StatelessWidget {
  final String? category;
  final bool expanded;
  final int appCount;
  final VoidCallback onToggle;
  final List<Widget> Function() buildTiles;

  const AppListCategorySection({
    super.key,
    required this.category,
    required this.expanded,
    required this.appCount,
    required this.onToggle,
    required this.buildTiles,
  });

  @override
  Widget build(BuildContext context) {
    String capFirstChar(String str) => str[0].toUpperCase() + str.substring(1);
    final colorScheme = Theme.of(context).colorScheme;
    final showItems = expanded && appCount > 0;
    final tiles = showItems ? buildTiles() : const <Widget>[];
    final segmentCount = 1 + tiles.length;

    Widget segment(int i, Color color, Widget child) => ConnectedCard(
      isFirst: i == 0,
      isLast: i == segmentCount - 1,
      color: color,
      padding: null,
      child: child,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          segment(
            0,
            colorScheme.surfaceContainerHigh,
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: expanded ? 0.25 : 0,
                      duration: ExpressiveMotion.short,
                      child: const Icon(Icons.chevron_right_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        capFirstChar(category ?? tr('noCategory')),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(appCount.toString()),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: ExpressiveMotion.medium,
            curve: ExpressiveMotion.emphasized,
            alignment: Alignment.topCenter,
            child: !showItems
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < tiles.length; i++) ...[
                        const SizedBox(height: 3),
                        segment(
                          i + 1,
                          colorScheme.surfaceContainerLow,
                          tiles[i],
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
