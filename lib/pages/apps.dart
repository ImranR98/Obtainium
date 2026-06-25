import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:obtainium/components/app_list_builder.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/components/motion.dart';
import 'package:obtainium/components/ui_shapes.dart';
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
import 'package:url_launcher/url_launcher_string.dart';

class AppsPage extends StatefulWidget {
  const AppsPage({super.key, this.onAppSelected, this.selectedAppId});

  /// In a two-pane layout, called when the user taps an app (instead of pushing
  /// an [AppPage] route). In single-pane mode this is null and taps push a
  /// route as usual.
  final void Function(String appId)? onAppSelected;

  /// The app currently shown in the detail pane (two-pane), used to highlight
  /// the tile.
  final String? selectedAppId;

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
              ? InkWell(
                  child: Text(
                    changesUrl,
                    style: const TextStyle(
                      decoration: TextDecoration.underline,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  onTap: () {
                    launchUrlString(
                      changesUrl,
                      mode: LaunchMode.externalApplication,
                    );
                  },
                )
              : const SizedBox.shrink(),
          changesUrl != null
              ? const SizedBox(height: 16)
              : const SizedBox.shrink(),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width,
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: appSource.changeLogIfAnyIsMarkDown
                ? Markdown(
                    shrinkWrap: true,
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
                : SingleChildScrollView(child: Text(changeLog)),
          ),
        ],
        singleNullReturnButton: tr('ok'),
      );
    },
  );
}

Null Function()? getChangeLogFn(BuildContext context, App app) {
  String? changesUrl;
  String? changeLog = app.changeLog;
  if (changeLog?.split('\n').length == 1 &&
      RegExp(
        '(http|ftp|https)://([\\w_-]+(?:(?:\\.[\\w_-]+)+))([\\w.,@?^=%&:/~+#-]*[\\w@?^=%&/~+#-])?',
      ).hasMatch(changeLog!)) {
    changesUrl = changeLog;
    changeLog = null;
  }
  if (changeLog == null && changesUrl == null) return null;
  return () {
    var appSource = SourceProvider().getSource(
      app.url,
      overrideSource: app.overrideSource,
    );
    if (changesUrl == null) {
      changesUrl = appSource.changeLogPageFromStandardUrl(app.url);
    }
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
  var updatesOnlyFilter = AppsFilter(
    includeUptodate: false,
    includeNonInstalled: false,
  );
  Set<String> selectedAppIds = {};
  Set<String?> collapsedCategories = {};
  DateTime? refreshingSince;

  void clearSelected() {
    setState(() {
      selectedAppIds.clear();
    });
  }

  void selectThese(List<App> apps) {
    if (selectedAppIds.isEmpty) {
      setState(() {
        for (var a in apps) {
          selectedAppIds.add(a.id);
        }
      });
    }
  }

  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  late final ScrollController scrollController = ScrollController();
  final TextEditingController searchController = TextEditingController();

  var sourceProvider = SourceProvider();

  @override
  void dispose() {
    scrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var appsProvider = context.watch<AppsProvider>();
    var settingsProvider = context.watch<SettingsProvider>();
    var listedApps = appsProvider.getAppValues().toList();

    refresh() {
      settingsProvider.lightImpact();
      setState(() {
        refreshingSince = DateTime.now();
      });
      return appsProvider
          .checkUpdates()
          .catchError((e) {
            showError(e is Map ? e['errors'] : e, context);
            return <App>[];
          })
          .whenComplete(() {
            setState(() {
              refreshingSince = null;
            });
          });
    }

    if (!appsProvider.loadingApps &&
        appsProvider.apps.isNotEmpty &&
        settingsProvider.checkJustStarted() &&
        settingsProvider.checkOnStart) {
      _refreshIndicatorKey.currentState?.show();
    }

    var listedAppIdSet = listedApps.map((e) => e.app.id).toSet();
    selectedAppIds = selectedAppIds.where(listedAppIdSet.contains).toSet();

    toggleAppSelected(App app) {
      setState(() {
        if (selectedAppIds.contains(app.id)) {
          selectedAppIds.remove(app.id);
        } else {
          selectedAppIds.add(app.id);
        }
      });
    }

    var existingUpdates = appsProvider.findExistingUpdates(installedOnly: true);

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
      var temp = listedApps.map(
        (e) => e.app.categories.isNotEmpty ? e.app.categories : [null],
      );
      return temp.isNotEmpty
          ? {
              ...temp.reduce((v, e) => [...v, ...e]),
            }.toList()
          : [];
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

    getLoadingWidgets() {
      return [
        if (listedApps.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      appsProvider.apps.isEmpty
                          ? (appsProvider.loadingApps
                                ? Icons.hourglass_empty_rounded
                                : Icons.apps_outlined)
                          : Icons.search_off_rounded,
                      size: 56,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      appsProvider.apps.isEmpty
                          ? appsProvider.loadingApps
                                ? tr('pleaseWait')
                                : tr('noApps')
                          : tr('noAppsForFilter'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (refreshingSince != null || appsProvider.loadingApps)
          SliverToBoxAdapter(
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
      ];
    }

    getUpdateButton(int appIndex) {
      return IconButton(
        visualDensity: VisualDensity.compact,
        color: Theme.of(context).colorScheme.primary,
        tooltip:
            listedApps[appIndex].app.additionalSettings['trackOnly'] == true
            ? tr('markUpdated')
            : tr('update'),
        onPressed: appsProvider.areDownloadsRunning()
            ? null
            : () {
                appsProvider
                    .downloadAndInstallLatestApps([
                      listedApps[appIndex].app.id,
                    ], globalNavigatorKey.currentContext)
                    .then((res) {
                      if (res.isNotEmpty) {
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
                      showError(e, context);
                      return <String>[];
                    });
              },
        icon: Icon(
          listedApps[appIndex].app.additionalSettings['trackOnly'] == true
              ? Icons.check_circle_outline
              : Icons.install_mobile,
        ),
      );
    }

    getVersionText(int appIndex) {
      var installed = listedApps[appIndex].app.installedVersion;
      var latest = listedApps[appIndex].app.latestVersion;
      if (installed != null && installed != latest) {
        return '$installed → $latest';
      }
      return installed ?? tr('notInstalled');
    }

    getChangesButtonString(int appIndex, bool hasChangeLogFn) {
      return listedApps[appIndex].app.releaseDate == null
          ? hasChangeLogFn
                ? tr('changes')
                : ''
          : DateFormat(
              'yyyy-MM-dd',
            ).format(listedApps[appIndex].app.releaseDate!.toLocal());
    }

    Widget buildAuthorText(int appIndex) {
      return Text(
        tr('byX', args: [listedApps[appIndex].author]),
        maxLines: 1,
        style: TextStyle(
          overflow: TextOverflow.ellipsis,
          fontWeight: listedApps[appIndex].app.pinned
              ? FontWeight.bold
              : FontWeight.normal,
        ),
      );
    }

    Widget buildRepoMovedRow() {
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
                style: TextStyle(color: textColor, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    getSingleAppHorizTile(int index) {
      var showChangesFn = getChangeLogFn(context, listedApps[index].app);
      var hasUpdate =
          listedApps[index].app.installedVersion != null &&
          listedApps[index].app.installedVersion !=
              listedApps[index].app.latestVersion;
      Widget trailingRow = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          hasUpdate ? getUpdateButton(index) : const SizedBox.shrink(),
          hasUpdate ? const SizedBox(width: 5) : const SizedBox.shrink(),
          InkWell(
            onTap: showChangesFn,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color:
                    settingsProvider.highlightTouchTargets &&
                        showChangesFn != null
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1)
                    : null,
              ),
              padding: settingsProvider.highlightTouchTargets
                  ? const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 0)
                  : const EdgeInsetsDirectional.fromSTEB(24, 0, 0, 0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width / 4,
                        ),
                        child: Text(
                          getVersionText(index),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: isVersionPseudo(listedApps[index].app)
                              ? TextStyle(fontStyle: FontStyle.italic)
                              : null,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        getChangesButtonString(index, showChangesFn != null),
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          decoration: showChangesFn != null
                              ? TextDecoration.underline
                              : TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );

      var transparent = Colors.transparent.toARGB32();
      var categories = listedApps[index].app.categories;
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
      // Capture the app id before wrapping in Dismissible so the swipe
      // callbacks don't see a stale list index during the animation.
      final appId = listedApps[index].app.id;
      final installed = listedApps[index].app.installedVersion;
      final latest = listedApps[index].app.latestVersion;
      final trackOnly =
          listedApps[index].app.additionalSettings['trackOnly'] == true;
      final canInstall = installed == null && !trackOnly;
      final canUpdate =
          installed != null && installed != latest && !trackOnly;
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
        direction: DismissDirection.horizontal,
        background: swipeBackground ?? const SizedBox.shrink(),
        secondaryBackground: Container(
          color: cs.errorContainer,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            // Swipe right — install or update (snap back, action is async).
            if (canInstall || canUpdate) {
              appsProvider.downloadAndInstallLatestApps(
                [appId],
                globalNavigatorKey.currentContext,
              );
            }
            return false;
          } else {
            // Swipe left — remove (delegates to the standard confirm dialog).
            return appsProvider.removeAppsWithModal(
              context,
              [listedApps[index].app],
            );
          }
        },
        onDismissed: (direction) {
          // Removal is already handled inside confirmDismiss via
          // removeAppsWithModal; nothing to do here.
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
            autofocus: index == 0 && settingsProvider.isTV,
            tileColor: listedApps[index].app.pinned
                ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06)
                : Colors.transparent,
            selectedTileColor: Theme.of(context).colorScheme.primary.withValues(
              alpha: listedApps[index].app.pinned ? 0.2 : 0.1,
            ),
            selected: selectedAppIds.contains(
              listedApps[index].app.id,
            ) ||
                widget.selectedAppId == listedApps[index].app.id,
            onLongPress: () {
              toggleAppSelected(listedApps[index].app);
            },
            leading: (settingsProvider.isTV)
                ? Checkbox(
                    value: selectedAppIds.contains(listedApps[index].app.id),
                    onChanged: (_) {
                      toggleAppSelected(listedApps[index].app);
                    },
                  )
                : AppIconWidget(
                    appId: listedApps[index].app.id,
                    installed: listedApps[index].installedInfo != null,
                    appsProvider: appsProvider,
                  ),
            title: Text(
              maxLines: 1,
              listedApps[index].name,
              style: TextStyle(
                overflow: TextOverflow.ellipsis,
                fontWeight: listedApps[index].app.pinned
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            subtitle: listedApps[index].app.hasPendingRepoRename
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [buildAuthorText(index), buildRepoMovedRow()],
                  )
                : buildAuthorText(index),
            trailing: listedApps[index].downloadProgress != null
                ? SizedBox(
                    child: Text(
                      listedApps[index].downloadProgress! >= 0
                          ? tr(
                              'percentProgress',
                              args: [
                                listedApps[index].downloadProgress!
                                    .toInt()
                                    .toString(),
                              ],
                            )
                          : tr('installing'),
                      textAlign: (listedApps[index].downloadProgress! >= 0)
                          ? TextAlign.start
                          : TextAlign.end,
                    ),
                  )
                : trailingRow,
             onTap: () {
               if (selectedAppIds.isNotEmpty) {
                 toggleAppSelected(listedApps[index].app);
               } else if (widget.onAppSelected != null) {
                 widget.onAppSelected!(listedApps[index].app.id);
               } else {
                 Navigator.push(
                   context,
                   MaterialPageRoute(
                     builder: (context) =>
                         AppPage(appId: listedApps[index].app.id),
                   ),
                 );
               }
             },
          ),
        ),
      );
    }

    appTileCard(int index) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: getSingleAppHorizTile(index),
        ),
      );
    }

    getCategoryCollapsibleTile(int index) {
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

      capFirstChar(String str) => str[0].toUpperCase() + str.substring(1);
      final colorScheme = Theme.of(context).colorScheme;
      final expanded = !collapsedCategories.contains(category);
      final showItems = expanded && appEntries.isNotEmpty;
      // The header and (when expanded) its app items form one connected,
      // positionally-rounded block.
      final segmentCount = 1 + (showItems ? appEntries.length : 0);

      segment(int i, Color color, Widget child) => Material(
        color: color,
        clipBehavior: Clip.antiAlias,
        shape: positionalTileShape(
          isFirst: i == 0,
          isLast: i == segmentCount - 1,
        ),
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
                onTap: () {
                  setState(() {
                    if (expanded) {
                      collapsedCategories.add(category);
                    } else {
                      collapsedCategories.remove(category);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: expanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.chevron_right_rounded),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          capFirstChar(category ?? tr('noCategory')),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(appEntries.length.toString()),
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
                        for (var i = 0; i < appEntries.length; i++) ...[
                          const SizedBox(height: 3),
                          segment(
                            i + 1,
                            colorScheme.surfaceContainerLow,
                            getSingleAppHorizTile(appEntries[i].key),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      );
    }

    getSelectAllButton() {
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
                selectedAppIds.isEmpty
                    ? selectThese(listedApps.map((e) => e.app).toList())
                    : clearSelected();
              },
              icon: Icon(
                selectedAppIds.isEmpty
                    ? Icons.select_all_outlined
                    : Icons.deselect_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              label: Text(selectedAppIds.length.toString()),
            );
    }

    getMassObtainFunction() {
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
                        showError(e, context);
                        return <String>[];
                      })
                      .then((value) {
                        if (value.isNotEmpty) {
                          if (shouldInstallUpdates) {
                            showMessage(tr('appsUpdated'), context);
                          }
                          var np = context.read<NotificationsProvider>();
                          np.cancel(UpdateNotification([]).id);
                        }
                      });
                }
              });
            };
    }

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
          if (cont) {
            // ignore: use_build_context_synchronously
            await showDialog<Map<String, dynamic>?>(
              context: context,
              builder: (BuildContext ctx) {
                return GeneratedFormModal(
                  title: tr('categorize'),
                  items: const [],
                  initValid: true,
                  singleNullReturnButton: tr('continue'),
                  additionalWidgets: [
                    CategoryEditorSelector(
                      preselected: !showPrompt ? preselected ?? {} : {},
                      showLabelWhenNotEmpty: false,
                      onSelected: (categories) {
                        appsProvider.saveApps(
                          selectedApps.map((e) {
                            e.categories = categories;
                            return e;
                          }).toList(),
                        );
                      },
                    ),
                  ],
                );
              },
            );
          }
        } catch (err) {
          showError(err, context);
        }
      };
    }

    showMassMarkDialog() {
      return showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: Text(
              tr(
                'markXSelectedAppsAsUpdated',
                args: [selectedAppIds.length.toString()],
              ),
            ),
            content: Text(
              tr('onlyWorksWithNonVersionDetectApps'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(tr('no')),
              ),
              FilledButton(
                onPressed: () {
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

                  Navigator.of(context).pop();
                },
                child: Text(tr('yes')),
              ),
            ],
          );
        },
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
          );
        },
      );
    }

    getMainBottomButtons() {
      return [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: selectedAppIds.isEmpty ? null : showMoreOptionsDialog,
          tooltip: tr('more'),
          icon: const Icon(Icons.more_vert),
        ),
      ];
    }

    showFilterDialog() async {
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: CategoryEditorSelector(
                      preselected: filter.categoryFilter,
                      onSelected: (categories) {
                        filter.categoryFilter = categories.toSet();
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
      if (values != null) {
        setState(() {
          filter.setFormValuesFromMap(values);
        });
      }
    }

    getDisplayedList() {
      return settingsProvider.groupByCategory &&
              !(listedCategories.isEmpty ||
                  (listedCategories.length == 1 && listedCategories[0] == null))
          ? SliverList(
              delegate: SliverChildBuilderDelegate((
                BuildContext context,
                int index,
              ) {
                return getCategoryCollapsibleTile(index);
              }, childCount: listedCategories.length),
            )
          : SliverList(
              delegate: SliverChildBuilderDelegate((
                BuildContext context,
                int index,
              ) {
                return appTileCard(index);
              }, childCount: listedApps.length),
            );
    }

    getSearchBarSliver() {
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
              getSelectAllButton(),
              if (selectedAppIds.isNotEmpty)
                ...getMainBottomButtons(),
              if (!isFilterOff)
                IconButton(
                  tooltip: '${tr('filter')} - ${tr('remove')}',
                  onPressed: () {
                    setState(() {
                      filter = AppsFilter();
                      searchController.clear();
                    });
                  },
                  icon: const Icon(Icons.filter_alt_off_outlined),
                ),
              IconButton(
                tooltip: tr('filterApps'),
                onPressed: showFilterDialog,
                icon: const Icon(Icons.filter_list_rounded),
              ),
            ],
            onChanged: (value) {
              setState(() {
                filter.nameFilter = value;
              });
            },
          ),
        ),
      );
    }

    getUpdateBannerSliver() {
      var onObtain = getMassObtainFunction();
      final cs = Theme.of(context).colorScheme;
      return SliverToBoxAdapter(
        child: onObtain == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Material(
                  color: cs.primaryContainer,
                  clipBehavior: Clip.antiAlias,
                  shape: squircleBorder(BorderRadius.circular(24)),
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
      );
    }

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
          onRefresh: refresh,
          child: Scrollbar(
            interactive: true,
            controller: scrollController,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              controller: scrollController,
              slivers: <Widget>[
                CustomAppBar(title: tr('appsString')),
                if (appsProvider.apps.isNotEmpty) getSearchBarSliver(),
                if (appsProvider.apps.isNotEmpty) getUpdateBannerSliver(),
                ...getLoadingWidgets(),
                getDisplayedList(),
                const SliverToBoxAdapter(child: SizedBox(height: 88)),
              ],
            ),
          ),
        ),
      ),
    );
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
    return InkWell(
      child: SizedBox(
        width: 44,
        height: 44,
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(12),
          child: FutureBuilder(
            future: _iconFuture,
            builder: (ctx, val) {
              var icon = widget.appsProvider.apps[widget.appId]?.icon;
              return icon != null
                  ? Image.memory(
                      icon,
                      gaplessPlayback: true,
                      fit: BoxFit.cover,
                      opacity: AlwaysStoppedAnimation(
                        widget.installed ? 1 : 0.6,
                      ),
                    )
                  : ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: Image(
                          image: const AssetImage(
                            'assets/graphics/icon_small.png',
                          ),
                          color: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? Colors.white.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.4),
                          colorBlendMode: BlendMode.modulate,
                          gaplessPlayback: true,
                          width: 24,
                          height: 24,
                        ),
                      ),
                    );
            },
          ),
        ),
      ),
      onDoubleTap: () {
        pm.openApp(widget.appId);
      },
      onLongPress: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                AppPage(appId: widget.appId, showOppositeOfPreferredView: true),
          ),
        );
      },
    );
  }
}
