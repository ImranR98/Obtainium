import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/theme.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
// AppsFilter and AppListBuilder are defined below in this file.
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

final RegExp _changelogUrlRegEx = RegExp(
  '(http|ftp|https)://([\\w_-]+(?:(?:\\.[\\w_-]+)+))([\\w.,@?^=%&:/~+#-]*[\\w@?^=%&/~+#-])?',
);

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
                      unawaited(
                        launchUrlString(
                          href.startsWith('http://') ||
                                  href.startsWith('https://')
                              ? href
                              : '${Uri.parse(app.url).origin}/$href',
                          mode: LaunchMode.externalApplication,
                        ),
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

VoidCallback? getChangeLogFn(BuildContext context, App app) {
  String? changesUrl;
  String? changeLog = app.changeLog;
  final trimmedChangeLog = changeLog?.trim() ?? '';
  final urlMatch = _changelogUrlRegEx.firstMatch(trimmedChangeLog);
  if (urlMatch != null &&
      urlMatch.start == 0 &&
      urlMatch.end == trimmedChangeLog.length) {
    changesUrl = trimmedChangeLog;
    changeLog = null;
  }
  if (changeLog == null && changesUrl == null) return null;
  return () {
    final appSource = SourceProvider().getSource(
      app.url,
      overrideSource: app.overrideSource,
    );
    changesUrl ??= appSource.changeLogPageFromStandardUrl(app.url);
    if (changeLog != null) {
      showChangeLogDialog(context, app, changesUrl, appSource, changeLog);
    } else if (changesUrl != null) {
      unawaited(
        launchUrlString(changesUrl!, mode: LaunchMode.externalApplication),
      );
    }
  };
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
  late Future<void> _iconFuture;
  String? _lastAppId;

  @override
  void initState() {
    super.initState();
    _lastAppId = widget.appId;
    _iconFuture = widget.appsProvider.updateAppIcon(widget.appId);
  }

  @override
  void didUpdateWidget(AppIconWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.appId != _lastAppId) {
      _lastAppId = widget.appId;
      _iconFuture = widget.appsProvider.updateAppIcon(widget.appId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.appsProvider.apps[widget.appId]?.name ?? '';
    return Semantics(
      label: name,
      button: true,
      onTap: widget.installed
          ? () => packageManager.openApp(widget.appId)
          : null,
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
          if (widget.installed) {
            packageManager.openApp(widget.appId);
          }
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

class AppListTile extends StatelessWidget {
  final AppInMemory appInMemory;
  final SettingsProvider settingsProvider;
  final AppsProvider appsProvider;

  final bool multiSelected;

  final bool detailSelected;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback onToggleSelected;

  /// Shape for the tile's selection/pinned highlight, so it matches the
  /// enclosing card's (or group segment's) corners. Falls back to the theme.
  final BorderRadius? borderRadius;

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
    this.borderRadius,
  });

  App get _app => appInMemory.app;

  Widget _updateButton(BuildContext context) {
    final trackOnly = _app.settings.getBool('trackOnly');
    final cs = Theme.of(context).colorScheme;
    final onPressed = appsProvider.areDownloadsRunning()
        ? null
        : () {
            settingsProvider.heavyImpact();
            appsProvider
                .downloadAndInstallLatestApps([
                  _app.id,
                ], appNavigatorKey.currentContext)
                .then((res) {
                  if (res.isNotEmpty && context.mounted) {
                    final np = context.read<NotificationsProvider>();
                    np.cancel(updateNotificationId);
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
          };
    return IconButton.filled(
      onPressed: onPressed,
      tooltip: trackOnly ? tr('markUpdated') : tr('update'),
      style: IconButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.12),
        disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
        visualDensity: VisualDensity.compact,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      icon: Icon(trackOnly ? Icons.check_rounded : Icons.download_rounded),
    );
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
              style:
                  Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: textColor) ??
                  TextStyle(color: textColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showChangesFn = getChangeLogFn(context, _app);
    final hasUpdate =
        _app.installedVersion != null &&
        _app.installedVersion != _app.latestVersion;
    final Widget trailingRow = LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (hasUpdate) ...[_updateButton(context), const SizedBox(width: 8)],
          _VersionLabel(
            appInMemory: appInMemory,
            settingsProvider: settingsProvider,
            maxWidth: math.min(constraints.maxWidth / 3, 200),
            showChangesFn: showChangesFn,
          ),
        ],
      ),
    );

    final disableSwipe = settingsProvider.disableSwipeActions;

    final transparent = Colors.transparent.toARGB32();
    final categories = _app.categories;
    final List<double> stops = [
      if (categories.isNotEmpty)
        ...List.generate(categories.length, (i) => i / categories.length),
      1.0,
    ];
    final appId = _app.id;
    final installed = _app.installedVersion;
    final latest = _app.latestVersion;
    final trackOnly = _app.settings.getBool('trackOnly');
    final canInstall = installed == null && !trackOnly;
    final canUpdate = installed != null && installed != latest && !trackOnly;
    final cs = Theme.of(context).colorScheme;

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

    return ValueListenableBuilder<double?>(
      valueListenable: appInMemory.downloadProgressNotifier,
      builder: (context, downloadProgress, child) {
        final tileChild = Semantics(
          customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
            if (canInstall || canUpdate)
              CustomSemanticsAction(
                label: canUpdate ? tr('update') : tr('install'),
              ): () {
                if (!appsProvider.areDownloadsRunning()) {
                  appsProvider.downloadAndInstallLatestApps([
                    appId,
                  ], appNavigatorKey.currentContext);
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
            child: () {
              final tile = ListTile(
                autofocus: autofocus,
                shape: borderRadius != null
                    ? RoundedSuperellipseBorder(borderRadius: borderRadius!)
                    : null,
                tileColor: _app.pinned
                    ? Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.06)
                    : Colors.transparent,
                selectedTileColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: _app.pinned ? 0.2 : 0.1),
                selected: multiSelected || detailSelected,
                leading: settingsProvider.isTV
                    ? null
                    : AppIconWidget(
                        appId: _app.id,
                        installed: appInMemory.installedInfo != null,
                        appsProvider: appsProvider,
                      ),
                onLongPress: onToggleSelected,
                title: Text(
                  maxLines: 1,
                  appInMemory.name,
                  style: TextStyle(
                    overflow: TextOverflow.ellipsis,
                    fontWeight: _app.pinned
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                subtitle: _app.hasPendingRepoRename
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _authorText(),
                          _repoMovedRow(context),
                        ],
                      )
                    : _authorText(),
                trailing: downloadProgress != null
                    ? DownloadProgressTrailing(
                        progress: downloadProgress,
                        receivedBytes: appInMemory.downloadReceivedBytes,
                        totalBytes: appInMemory.downloadTotalBytes,
                      )
                    : trailingRow,
                onTap: onTap,
              );
              if (settingsProvider.isTV) {
                return Row(
                  children: [
                    Checkbox(
                      value: multiSelected,
                      onChanged: (_) {
                        onToggleSelected();
                      },
                    ),
                    Expanded(child: tile),
                  ],
                );
              }
              return tile;
            }(),
          ),
        );

        return disableSwipe || downloadProgress != null
            ? tileChild
            : Dismissible(
                key: ValueKey(appId),
                direction: DismissDirection.horizontal,
                background: swipeBackground ?? const SizedBox.shrink(),
                secondaryBackground: Container(
                  color: cs.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: Icon(Icons.delete_outline,
                      color: cs.onErrorContainer),
                ),
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.startToEnd) {
                    if ((canInstall || canUpdate) &&
                        !appsProvider.areDownloadsRunning()) {
                      settingsProvider.heavyImpact();
                      unawaited(
                        appsProvider
                            .downloadAndInstallLatestApps([
                              appId,
                            ], appNavigatorKey.currentContext)
                            .catchError((e) {
                              if (context.mounted) showError(e, context);
                              return <String>[];
                            }),
                      );
                    }
                    return false;
                  } else {
                    settingsProvider.lightImpact();
                    return appsProvider.removeAppsWithModal(context, [_app]);
                  }
                },
                onDismissed: (direction) {},
                child: tileChild,
              );
      },
    );
  }
}

class DownloadProgressTrailing extends StatelessWidget {
  final double progress;
  final int? receivedBytes;
  final int? totalBytes;
  final VoidCallback? onCancel;
  const DownloadProgressTrailing({
    super.key,
    required this.progress,
    this.receivedBytes,
    this.totalBytes,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final installing = progress < 0;
    final label = installing ? tr('installing') : '${progress.toInt()}%';
    final sizeLabel = installing
        ? null
        : formatDownloadSize(receivedBytes, totalBytes);
    final labelStyle =
        Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11) ??
        const TextStyle(fontSize: 11);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 112,
          child: Semantics(
            label: sizeLabel == null ? label : '$label $sizeLabel',
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: installing ? null : progress / 100,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
                if (sizeLabel != null)
                  Text(
                    sizeLabel,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
              ],
            ),
          ),
        ),
        if (!installing && onCancel != null)
          DownloadCancelButton(onPressed: onCancel!),
      ],
    );
  }
}

String capitalizeFirst(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// A collapsible section header + its app tiles, used when the list is grouped
/// (by category or source). [title] is the already-resolved display label.
class AppListGroupSection extends StatelessWidget {
  final String title;
  final bool expanded;
  final int appCount;
  final VoidCallback onToggle;
  final List<Widget> Function() buildTiles;

  const AppListGroupSection({
    super.key,
    required this.title,
    required this.expanded,
    required this.appCount,
    required this.onToggle,
    required this.buildTiles,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showItems = expanded && appCount > 0;
    final tiles = showItems ? buildTiles() : const <Widget>[];
    final segmentCount = 1 + tiles.length;

    Widget segment(int i, Color color, Widget child) => ConnectedCard(
      isFirst: i == 0,
      isLast: i == segmentCount - 1,
      color: color,
      child: child,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        // Small gaps so entries read as distinct positional tiles, matching the
        // connected-tile look used for settings.
        spacing: 3,
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
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(appCount.toString()),
                  ],
                ),
              ),
            ),
          ),
          ...tiles.asMap().entries.map(
            (e) => segment(e.key + 1, colorScheme.surfaceContainerLow, e.value),
          ),
        ],
      ),
    );
  }
}

class AppsFilter {
  String nameFilter;
  String authorFilter;
  String idFilter;
  bool includeUptodate;
  bool includeNonInstalled;
  Set<String> categoryFilter;
  String sourceFilter;

  AppsFilter({
    this.nameFilter = '',
    this.authorFilter = '',
    this.idFilter = '',
    this.includeUptodate = true,
    this.includeNonInstalled = true,
    this.categoryFilter = const {},
    this.sourceFilter = '',
  });

  Map<String, dynamic> toFormValuesMap() {
    return {
      'appName': nameFilter,
      'author': authorFilter,
      'appId': idFilter,
      'upToDateApps': includeUptodate,
      'nonInstalledApps': includeNonInstalled,
      'sourceFilter': sourceFilter,
    };
  }

  void setFormValuesFromMap(Map<String, dynamic> values) {
    nameFilter = values['appName'] as String? ?? '';
    authorFilter = values['author'] as String? ?? '';
    idFilter = values['appId'] as String? ?? '';
    includeUptodate = values['upToDateApps'] as bool? ?? false;
    includeNonInstalled = values['nonInstalledApps'] as bool? ?? false;
    sourceFilter = values['sourceFilter'] as String? ?? '';
  }

  bool isIdenticalTo(AppsFilter other, SettingsProvider settingsProvider) =>
      authorFilter.trim() == other.authorFilter.trim() &&
      nameFilter.trim() == other.nameFilter.trim() &&
      idFilter.trim() == other.idFilter.trim() &&
      includeUptodate == other.includeUptodate &&
      includeNonInstalled == other.includeNonInstalled &&
      settingsProvider.setEqual(categoryFilter, other.categoryFilter) &&
      sourceFilter.trim() == other.sourceFilter.trim();
}

class AppListBuilder {
  static List<AppInMemory> filter(List<AppInMemory> apps, AppsFilter filter) {
    final nameTokens = filter.nameFilter.isNotEmpty
        ? filter.nameFilter
              .split(' ')
              .where((element) => element.trim().isNotEmpty)
              .toList()
        : const <String>[];
    final authorTokens = filter.authorFilter.isNotEmpty
        ? filter.authorFilter
              .split(' ')
              .where((element) => element.trim().isNotEmpty)
              .toList()
        : const <String>[];

    return apps.where((app) {
      if (app.app.installedVersion == app.app.latestVersion &&
          !(filter.includeUptodate)) {
        return false;
      }
      if (app.app.installedVersion == null && !(filter.includeNonInstalled)) {
        return false;
      }
      for (var t in nameTokens) {
        if (!app.name.toLowerCase().contains(t.toLowerCase())) {
          return false;
        }
      }
      for (var t in authorTokens) {
        if (!app.author.toLowerCase().contains(t.toLowerCase())) {
          return false;
        }
      }
      if (filter.idFilter.isNotEmpty) {
        if (!app.app.id.contains(filter.idFilter)) {
          return false;
        }
      }
      if (filter.categoryFilter.isNotEmpty &&
          filter.categoryFilter
              .intersection(app.app.categories.toSet())
              .isEmpty) {
        return false;
      }
      if (filter.sourceFilter.isNotEmpty &&
          app.sourceType != filter.sourceFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  static List<AppInMemory> sort(
    List<AppInMemory> apps,
    SortColumnSettings sortColumn,
    SortOrderSettings sortOrder,
  ) {
    if (sortColumn == SortColumnSettings.added) {
      final list = List<AppInMemory>.from(apps);
      if (sortOrder == SortOrderSettings.descending) {
        return list.reversed.toList();
      }
      return list;
    }

    final isDesc = sortOrder == SortOrderSettings.descending;
    if (sortColumn == SortColumnSettings.releaseDate) {
      final entries = apps.map((a) => MapEntry(a.app.releaseDate, a)).toList()
        ..sort((a, b) {
          final aDate = a.key;
          final bDate = b.key;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return isDesc ? bDate.compareTo(aDate) : aDate.compareTo(bDate);
        });
      apps = entries.map((e) => e.value).toList();
    } else {
      String keyFn(AppInMemory a) => switch (sortColumn) {
        SortColumnSettings.authorName => (a.author + a.name).toLowerCase(),
        SortColumnSettings.nameAuthor => (a.name + a.author).toLowerCase(),
        _ => '',
      };
      final entries = apps.map((a) => MapEntry(keyFn(a), a)).toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      apps = entries.map((e) => e.value).toList();
      if (isDesc) {
        apps = apps.reversed.toList();
      }
    }
    return apps;
  }

  static List<AppInMemory> reorder(
    List<AppInMemory> apps,
    bool pinUpdates,
    bool buryNonInstalled,
    Set<String> existingUpdates,
  ) {
    if (pinUpdates) {
      final temp = <AppInMemory>[];
      apps = apps.where((sa) {
        if (existingUpdates.contains(sa.app.id)) {
          temp.add(sa);
          return false;
        }
        return true;
      }).toList();
      apps = [...temp, ...apps];
    }

    if (buryNonInstalled) {
      final temp = <AppInMemory>[];
      apps = apps.where((sa) {
        if (sa.app.installedVersion == null) {
          temp.add(sa);
          return false;
        }
        return true;
      }).toList();
      apps = [...apps, ...temp];
    }

    final tempRenamed = <AppInMemory>[];
    final tempPinned = <AppInMemory>[];
    final tempNotPinned = <AppInMemory>[];
    for (var a in apps) {
      if (a.app.hasPendingRepoRename) {
        tempRenamed.add(a);
      } else if (a.app.pinned) {
        tempPinned.add(a);
      } else {
        tempNotPinned.add(a);
      }
    }
    apps = [...tempRenamed, ...tempPinned, ...tempNotPinned];

    return apps;
  }
}

class _VersionLabel extends StatelessWidget {
  final AppInMemory appInMemory;
  final SettingsProvider settingsProvider;
  final double maxWidth;
  final VoidCallback? showChangesFn;

  const _VersionLabel({
    required this.appInMemory,
    required this.settingsProvider,
    required this.maxWidth,
    required this.showChangesFn,
  });

  @override
  Widget build(BuildContext context) {
    final app = appInMemory.app;
    final hasUpdate =
        app.installedVersion != null &&
        app.installedVersion != app.latestVersion;
    final updateColor = hasUpdate
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final highlight = settingsProvider.highlightTouchTargets;

    Widget content = Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 14),
              child: Text(
                installedVersionText(app),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontStyle:
                      isVersionPseudo(app) ? FontStyle.italic : null,
                  color: updateColor,
                ),
              ),
            ),
          ),
          Text(
            changesLabel(app, showChangesFn != null),
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: updateColor,
              fontSize: 13,
              decoration: showChangesFn == null
                  ? TextDecoration.none
                  : TextDecoration.underline,
            ),
          ),
        ],
      ),
    );

    if (showChangesFn == null) return content;

    if (highlight) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: content,
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: showChangesFn,
      child: content,
    );
  }

  String installedVersionText(App app) {
    final installed = app.installedVersion;
    final latest = app.latestVersion;
    if (installed != null && installed != latest) {
      return '$installed → $latest';
    }
    return installed ?? tr('notInstalled');
  }

  String changesLabel(App app, bool hasChangeLogFn) {
    return app.releaseDate == null
        ? hasChangeLogFn
            ? tr('changes')
            : ''
        : DateFormat('yyyy-MM-dd').format(app.releaseDate!.toLocal());
  }
}
