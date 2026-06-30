import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/components/motion.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

final RegExp _changeLogUrlRegExp = RegExp(
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
                      launchUrlString(
                        href.startsWith('http://') ||
                                href.startsWith('https://')
                            ? href
                            : '${Uri.parse(app.url).origin}/$href',
                        mode: LaunchMode.externalApplication,
                      ).ignore();
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
      launchUrlString(
        changesUrl!,
        mode: LaunchMode.externalApplication,
      ).ignore();
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
      // Expose the InkWell's double-tap "open app" action to accessibility
      // services (screen readers can't perform a double-tap gesture).
      onTap: widget.installed ? () => pm.openApp(widget.appId) : null,
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
/// info, swipe-to-install/update/remove, and multi-select handling.
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
    // AppInMemory objects are mutated in place during a download (only the
    // downloadProgress field changes), so the apps-list page does not rebuild
    // on each tick (its pipeline signature ignores progress). Subscribe to this
    // app's live progress value directly so only this tile rebuilds per tick,
    // and so the bar clears when progress is reset to null after install.
    final downloadProgress = context.select<AppsProvider, double?>(
      (p) => p.apps[_app.id]?.downloadProgress,
    );
    var showChangesFn = getChangeLogFn(context, _app);
    var hasUpdate =
        _app.installedVersion != null &&
        _app.installedVersion != _app.latestVersion;
    final updateColor = hasUpdate
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    Widget trailingRow = LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          hasUpdate ? _updateButton(context) : const SizedBox.shrink(),
          hasUpdate ? const SizedBox(width: 5) : const SizedBox.shrink(),
          HighlightableButton(
            highlight: settingsProvider.highlightTouchTargets,
            onPressed: showChangesFn,
            label: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      constraints: BoxConstraints(
                        maxWidth: math.min(constraints.maxWidth / 4, 160),
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
                      _changesButtonString(showChangesFn != null),
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: updateColor,
                        decoration: showChangesFn == null
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
      ),
    );

    var transparent = Colors.transparent.toARGB32();
    var categories = _app.categories;
    List<double> stops = [
      if (categories.length > 1)
        ...categories.asMap().entries.map(
          (e) => ((e.key / (categories.length - 1)) - 0.0001),
        )
      else if (categories.length == 1)
        0.9999,
      1,
    ];
    final appId = _app.id;
    final installed = _app.installedVersion;
    final latest = _app.latestVersion;
    final trackOnly = _app.additionalSettings['trackOnly'] == true;
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

    return Dismissible(
      key: ValueKey(appId),
      direction: downloadProgress == null
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
          if ((canInstall || canUpdate) &&
              !appsProvider.areDownloadsRunning()) {
            appsProvider
                .downloadAndInstallLatestApps([
                  appId,
                ], globalNavigatorKey.currentContext)
                .catchError((e) {
                  var ctx = globalNavigatorKey.currentContext;
                  if (ctx != null && ctx.mounted) showError(e, ctx);
                  return <String>[];
                });
          }
          return false;
        } else {
          return appsProvider.removeAppsWithModal(context, [_app]);
        }
      },
      onDismissed: (direction) {},
      child: Semantics(
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
            trailing: downloadProgress != null
                ? DownloadProgressTrailing(progress: downloadProgress)
                : trailingRow,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

/// Compact download-progress indicator shown in an app list tile's trailing
/// slot (a small bar plus the integer percentage).
class DownloadProgressTrailing extends StatelessWidget {
  final double progress;
  const DownloadProgressTrailing({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final installing = progress < 0;
    final label = installing
        ? tr('installing')
        : tr('percentProgress', args: [progress.toInt().toString()]);
    return SizedBox(
      width: 64,
      child: Semantics(
        label: label,
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
              style:
                  Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(fontSize: 11) ??
                  const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// A collapsible category header plus (when expanded) its app rows, shaped as a
/// single connected, positionally-rounded block.
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
                        (() {
                          final s = category ?? tr('noCategory');
                          return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
                        })(),
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
