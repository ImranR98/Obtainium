import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/category_editor.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/components/app_info_dialog.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:provider/provider.dart';

class AppPage extends StatefulWidget {
  const AppPage({
    super.key,
    required this.appId,
    this.showOppositeOfPreferredView = false,
    this.onClose,
  });

  final String appId;
  final bool showOppositeOfPreferredView;

  /// When provided, the page is being shown embedded in a detail pane (two-pane
  /// layout); "back" and post-action dismissals clear the pane via this instead
  /// of popping a route.
  final VoidCallback? onClose;

  @override
  State<AppPage> createState() => _AppPageState();
}

class _AppPageState extends State<AppPage> {
  WebViewController? _webViewController;
  bool _webViewLoaded = false;
  AppInMemory? prevApp;
  bool updating = false;

  @override
  void dispose() {
    _webViewController = null;
    super.dispose();
  }

  // Memoizes the per-build deepCopy of the app so it is only re-copied when the
  // underlying app actually changes (instead of on every rebuild, e.g. each
  // download-progress tick).
  int? _appCacheSig;
  AppInMemory? _appCache;

  /// Lazily builds (and loads, once) the WebView controller. The controller and
  /// its network load are deferred until the webpage view is actually shown, so
  /// opening the detail view alone never spins up a WebView engine.
  WebViewController _ensureWebViewController(String url) {
    var controller = _webViewController;
    if (controller == null) {
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onWebResourceError: (WebResourceError error) {
              if (error.isForMainFrame == true && mounted) {
                showError(
                  ObtainiumError(error.description, unexpected: true),
                  context,
                );
              }
            },
            onNavigationRequest: (NavigationRequest request) =>
                !(request.url.startsWith("http://") ||
                    request.url.startsWith("https://") ||
                    request.url.startsWith("ftp://") ||
                    request.url.startsWith("ftps://"))
                ? NavigationDecision.prevent
                : NavigationDecision.navigate,
          ),
        );
      _webViewController = controller;
    }
    if (!_webViewLoaded) {
      _webViewLoaded = true;
      controller.loadRequest(Uri.parse(url));
    }
    return controller;
  }

  /// A fingerprint of everything this page reads from an [AppInMemory]
  /// (including download progress, icon and installed info), used to decide when
  /// the cached [deepCopy] needs to be refreshed.
  int _appSignature(AppInMemory a) {
    final app = a.app;
    // Structured hash so a field value containing the old separator character
    // can't collide with a different combination of field values.
    return Object.hashAll([
      a.downloadProgress,
      identityHashCode(a.icon),
      identityHashCode(a.installedInfo),
      app.id,
      a.name,
      a.author,
      app.installedVersion,
      app.latestVersion,
      app.url,
      app.overrideSource,
      app.releaseDate?.microsecondsSinceEpoch,
      app.lastUpdateCheck?.microsecondsSinceEpoch,
      Object.hashAll(app.categories),
      app.pinned,
      app.hasPendingRepoRename,
      app.pendingRepoRenameUrl,
      app.apkUrls.length,
      app.otherAssetUrls.length,
      app.preferredApkIndex,
      app.additionalSettings.toString(),
    ]);
  }

  AppInMemory? _cachedApp(AppInMemory? source) {
    if (source == null) {
      _appCache = null;
      _appCacheSig = null;
      return null;
    }
    final sig = _appSignature(source);
    if (sig == _appCacheSig && _appCache != null) {
      return _appCache;
    }
    final copy = source.deepCopy();
    _appCache = copy;
    _appCacheSig = sig;
    return copy;
  }

  void _closePage() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      // Only pop when this page is still the top-most route. Without this,
      // the post-install auto-close can fire a second pop while the user has
      // already navigated back (the pop animation keeps the State mounted but
      // the route is no longer current), emptying the navigator -> black screen.
      Navigator.of(context).pop();
    }
  }

  Widget buildRepoRenameWarning({
    required AppInMemory? app,
    required AppsProvider appsProvider,
    required Future<void> Function(String id) onUpdate,
  }) {
    if (app?.app.hasPendingRepoRename != true) {
      return const SizedBox.shrink();
    }
    var appValue = app!;
    var pendingUrl = appValue.app.pendingRepoRenameUrl!;
    final colorScheme = ColorScheme.of(context);
    final textTheme = TextTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 2,
      children: [
        ConnectedCard(
          isFirst: true,
          isLast: false,
          color: colorScheme.surfaceContainer,
          padding: null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                spacing: 12,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 24,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr('repoRenamed'),
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          tr('repoRenamedExplanation'),
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ConnectedCard(
          isFirst: false,
          isLast: false,
          color: colorScheme.surfaceContainer,
          padding: null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                spacing: 12,
                children: [
                  Icon(
                    Icons.link_rounded,
                    size: 24,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr('newUrl'),
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          pendingUrl,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ConnectedCard(
          isFirst: false,
          isLast: true,
          color: colorScheme.surfaceContainer,
          padding: null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                // Min tap target has a height of 48dp
                vertical: 10 - 4,
              ),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await appsProvider.updatePendingRepoRename(
                          appValue.app.id,
                          null,
                        );
                      },
                      child: Text(tr('dismiss')),
                    ),
                  ),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () async {
                        await appsProvider.acceptRepoRename(
                          appValue.app.id,
                          pendingUrl,
                        );
                        if (mounted) {
                          onUpdate(appValue.app.id);
                        }
                      },
                      child: Text(tr('updateUrl')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _getUpdate(
    String id,
    BuildContext context,
    AppsProvider appsProvider, {
    bool resetVersion = false,
  }) async {
    try {
      setState(() {
        updating = true;
      });
      await appsProvider.checkUpdate(id);
      if (resetVersion) {
        appsProvider.apps[id]?.app.additionalSettings['versionDetection'] =
            true;
        if (appsProvider.apps[id]?.app.installedVersion != null) {
          appsProvider.apps[id]?.app.installedVersion =
              appsProvider.apps[id]?.app.latestVersion;
        }
        appsProvider.saveApps([appsProvider.apps[id]!.app]);
      }
    } catch (err) {
      if (err is RepositoryRenamedError && context.mounted) {
        await appsProvider.updatePendingRepoRename(id, err.newUrl);
      } else if (context.mounted) {
        showError(err, context);
      }
    } finally {
      if (mounted) {
        setState(() {
          updating = false;
        });
      }
    }
  }

  Widget _getAppWebView(BuildContext context, AppInMemory? app) {
    if (app == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final controller = _ensureWebViewController(app.app.url)
      ..setBackgroundColor(Theme.of(context).colorScheme.surface);
    return WebViewWidget(key: ObjectKey(controller), controller: controller);
  }

  Future<void> _showMarkUpdatedDialog(
    BuildContext context,
    SettingsProvider settingsProvider,
    AppInMemory? app,
    AppsProvider appsProvider,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: tr('alreadyUpToDateQuestion'),
      confirmText: tr('yesMarkUpdated'),
    );
    if (!confirmed) return;
    settingsProvider.selectionClick();
    var updatedApp = app?.app;
    if (updatedApp != null) {
      updatedApp.installedVersion = updatedApp.latestVersion;
      appsProvider.saveApps([updatedApp]);
    }
  }

  Future<Map<String, dynamic>?> _showAdditionalOptionsDialog(
    BuildContext context,
    AppSource? source,
    AppInMemory? app,
  ) async {
    var items = (source?.combinedAppSpecificSettingFormItems ?? []).map((row) {
      row = row.map((e) {
        if (app?.app.additionalSettings[e.key] != null) {
          e.defaultValue = app?.app.additionalSettings[e.key];
        }
        return e;
      }).toList();
      return row;
    }).toList();

    Map<String, dynamic> values = {};
    return Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: CustomScrollView(
            slivers: [
              SliverAppBar.large(
                pinned: true,
                title: Text(
                  tr('additionalOptsFor', args: [app?.name ?? tr('app')]),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: GeneratedForm(
                    tileMode: true,
                    items: items,
                    onValueChanges: (v, valid, isBuilding) {
                      values = v;
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    MediaQuery.of(context).padding.bottom + 24,
                  ),
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(values),
                    child: Text(tr('continue')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleAdditionalOptionChanges(
    Map<String, dynamic>? values,
    BuildContext context,
    AppInMemory? app,
    AppSource? source,
    AppsProvider appsProvider,
  ) {
    if (app != null && values != null) {
      Map<String, dynamic> originalSettings = app.app.additionalSettings;
      app.app.additionalSettings = values;
      if (source?.enforceTrackOnly == true) {
        app.app.additionalSettings['trackOnly'] = true;
        if (context.mounted) {
          showMessage(tr('appsFromSourceAreTrackOnly'), context);
        }
      }
      var versionDetectionEnabled =
          app.app.additionalSettings['versionDetection'] == true &&
          originalSettings['versionDetection'] != true;
      var releaseDateVersionEnabled =
          app.app.additionalSettings['releaseDateAsVersion'] == true &&
          originalSettings['releaseDateAsVersion'] != true;
      var releaseDateVersionDisabled =
          app.app.additionalSettings['releaseDateAsVersion'] != true &&
          originalSettings['releaseDateAsVersion'] == true;
      if (releaseDateVersionEnabled) {
        if (app.app.releaseDate != null) {
          bool isUpdated = app.app.installedVersion == app.app.latestVersion;
          app.app.latestVersion = app.app.releaseDate!.microsecondsSinceEpoch
              .toString();
          if (isUpdated) {
            app.app.installedVersion = app.app.latestVersion;
          }
        }
      } else if (releaseDateVersionDisabled) {
        app.app.installedVersion =
            app.installedInfo?.versionName ?? app.app.installedVersion;
      }
      if (versionDetectionEnabled) {
        app.app.additionalSettings['versionDetection'] = true;
        app.app.additionalSettings['releaseDateAsVersion'] = false;
      }
      appsProvider.saveApps([app.app]).then((value) {
        if (context.mounted) {
          _getUpdate(
            app.app.id,
            context,
            appsProvider,
            resetVersion: versionDetectionEnabled,
          );
        }
      });
    }
  }

  AppBar _appScreenAppBar() => AppBar(
    leading: IconButton(
      icon: Icon(
        widget.onClose != null ? Icons.close_rounded : Icons.arrow_back,
      ),
      onPressed: _closePage,
    ),
  );

  Widget _getPrimaryButton(
    BuildContext context,
    AppInMemory? app,
    AppsProvider appsProvider,
    SettingsProvider settingsProvider,
    bool areDownloadsRunning,
  ) {
    final installed = app?.app.installedVersion;
    final latest = app?.app.latestVersion;
    final hasAction =
        app != null &&
        !updating &&
        (installed == null || installed != latest) &&
        !areDownloadsRunning;
    final trackOnly = app?.app.additionalSettings['trackOnly'] == true;
    return FilledButton.icon(
      onPressed: hasAction
          ? () async {
              try {
                var successMessage = installed == null
                    ? tr('installed')
                    : tr('appsUpdated');
                var np = context.read<NotificationsProvider>();
                settingsProvider.heavyImpact();
                var res = await appsProvider.downloadAndInstallLatestApps([
                  app.app.id,
                ], globalNavigatorKey.currentContext);
                if (res.isNotEmpty && !trackOnly && context.mounted) {
                  showMessage(successMessage, context);
                }
                if (res.isNotEmpty && mounted) {
                  _closePage();
                }
                if (res.isNotEmpty) {
                  np.cancel(UpdateNotification([]).id);
                  np.cancel(
                    SilentUpdateAttemptNotification([], id: res[0].hashCode).id,
                  );
                }
              } catch (e) {
                if (context.mounted) showError(e, context);
              }
            }
          : null,
      icon: Icon(
        installed == null
            ? Icons.download_outlined
            : Icons.system_update_alt_rounded,
      ),
      label: Text(
        installed == null
            ? (!trackOnly ? tr('install') : tr('markInstalled'))
            : !trackOnly
            ? tr('update')
            : tr('markUpdated'),
      ),
    );
  }

  List<Widget> _getSecondaryActions(
    BuildContext context,
    AppInMemory? app,
    AppSource? source,
    AppsProvider appsProvider,
    SettingsProvider settingsProvider,
    bool showAppWebpageFinal,
    bool isVersionDetectionStandard,
    bool trackOnly,
  ) {
    return <Widget>[
      if (source != null && source.hasAppSpecificSettings)
        IconButton(
          onPressed: app?.downloadProgress != null || updating
              ? null
              : () async {
                  var values = await _showAdditionalOptionsDialog(
                    context,
                    source,
                    app,
                  );
                  if (context.mounted) {
                    _handleAdditionalOptionChanges(
                      values,
                      context,
                      app,
                      source,
                      appsProvider,
                    );
                  }
                },
          tooltip: tr('additionalOptions'),
          icon: const Icon(Icons.edit),
        ),
      if (app != null && app.installedInfo != null)
        IconButton(
          onPressed: () {
            appsProvider.openAppSettings(app.app.id);
          },
          icon: const Icon(Icons.settings),
          tooltip: tr('settings'),
        ),
      if (app != null && showAppWebpageFinal)
        IconButton(
          onPressed: () async {
            await appsProvider.updateAppIcon(app.app.id, ignoreCache: true);
            if (!context.mounted) return;
            showDialog(
              context: context,
              builder: (BuildContext ctx) =>
                  AppInfoDialog(app: app, appsProvider: appsProvider),
            );
          },
          icon: const Icon(Icons.more_horiz),
          tooltip: tr('more'),
        ),
      if (app?.app.installedVersion != null &&
          app?.app.installedVersion != app?.app.latestVersion &&
          !isVersionDetectionStandard &&
          !trackOnly)
        IconButton(
          onPressed: app?.downloadProgress != null || updating
              ? null
              : () => _showMarkUpdatedDialog(
                  context,
                  settingsProvider,
                  app,
                  appsProvider,
                ),
          tooltip: tr('markUpdated'),
          icon: const Icon(Icons.done),
        ),
      if ((!isVersionDetectionStandard || trackOnly) &&
          app?.app.installedVersion != null &&
          app?.app.installedVersion == app?.app.latestVersion)
        IconButton(
          onPressed: app?.app == null || updating
              ? null
              : () {
                  app!.app.installedVersion = null;
                  appsProvider.saveApps([app.app]);
                },
          icon: const Icon(Icons.restore_rounded),
          tooltip: tr('resetInstallStatus'),
        ),
      IconButton(
        onPressed: app?.downloadProgress != null || updating
            ? null
            : () {
                appsProvider
                    .removeAppsWithModal(context, app != null ? [app.app] : [])
                    .then((value) {
                      if (value == true) {
                        _closePage();
                      }
                    });
              },
        tooltip: tr('remove'),
        icon: const Icon(Icons.delete_outline),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    var appsProvider = context.read<AppsProvider>();
    var settingsProvider = context.watch<SettingsProvider>();
    var showAppWebpageFinal =
        (settingsProvider.showAppWebpage &&
            !widget.showOppositeOfPreferredView) ||
        (!settingsProvider.showAppWebpage &&
            widget.showOppositeOfPreferredView);
    bool areDownloadsRunning = context.select<AppsProvider, bool>(
      (p) => p.areDownloadsRunning(),
    );
    // AppInMemory objects are mutated in place during a download (only the
    // downloadProgress field changes), so selecting the app object alone never
    // detects progress ticks - its identity is unchanged, so context.select
    // treats it as equal and skips the rebuild, leaving the progress bar empty.
    // Subscribe to the progress value itself so this page rebuilds on each tick.
    context.select<AppsProvider, double?>(
      (p) => p.apps[widget.appId]?.downloadProgress,
    );

    // Builds a single positionally-rounded card sliver.
    Widget section(
      bool isFirst,
      bool isLast, {
      required List<Widget> children,
    }) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: ConnectedCard(
            isFirst: isFirst,
            isLast: isLast,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
      );
    }

    var sourceProvider = SourceProvider();
    AppInMemory? app = _cachedApp(
      context.select<AppsProvider, AppInMemory?>((p) => p.apps[widget.appId]),
    );
    var source = app != null
        ? sourceProvider.getSource(
            app.app.url,
            overrideSource: app.app.overrideSource,
          )
        : null;
    if (!areDownloadsRunning &&
        prevApp == null &&
        app != null &&
        settingsProvider.checkUpdateOnDetailPage) {
      prevApp = app;
      final idToCheck = app.app.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _getUpdate(idToCheck, context, appsProvider);
      });
    }
    var trackOnly = app?.app.additionalSettings['trackOnly'] == true;

    bool isVersionDetectionStandard =
        app?.app.additionalSettings['versionDetection'] == true;

    final certs = app != null && app.certificateHashes.isNotEmpty;
    final hasAssets =
        app?.app.apkUrls.isNotEmpty == true ||
        app?.app.otherAssetUrls.isNotEmpty == true;

    return Scaffold(
      appBar: showAppWebpageFinal ? _appScreenAppBar() : null,
      floatingActionButton: showAppWebpageFinal
          ? FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AppPage(
                      appId: widget.appId,
                      showOppositeOfPreferredView: true,
                      onClose: widget.onClose,
                    ),
                  ),
                );
              },
              tooltip: tr('more'),
              child: const Icon(Icons.info_outline),
            )
          : null,
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: () async {
          if (app != null) {
            await _getUpdate(app.app.id, context, appsProvider);
          }
        },
        child: showAppWebpageFinal
            ? _getAppWebView(context, app)
            : CustomScrollView(
                slivers: [
                  // Back button — top-left
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        8,
                        MediaQuery.of(context).padding.top + 8,
                        0,
                        0,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: _closePage,
                            icon: Icon(
                              widget.onClose != null
                                  ? Icons.close_rounded
                                  : Icons.arrow_back,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ===== Section 1 — Icon + name + author =====
                  section(
                    true,
                    true,
                    children: [
                      Row(
                        children: [
                          AppIcon(bytes: app?.icon, size: 56, radius: 14),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  app?.name ?? tr('app'),
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  tr(
                                    'byX',
                                    args: [app?.author ?? tr('unknown')],
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  // Section 2 — Version, last-check
                  section(
                    true,
                    false,
                    children: [
                      () {
                        String l = appInstalledVersionText(app?.app);
                        final upToDate =
                            app?.app.installedVersion == app?.app.latestVersion;
                        if (!upToDate) {
                          l += '\n${app?.app.latestVersion} ${tr('latest')}';
                        }
                        return Text(
                          l,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        );
                      }(),
                      if (app?.app.releaseDate != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            app!.app.releaseDate!
                                .toLocal()
                                .toString()
                                .split('.')
                                .first,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                    ],
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 2)),
                  section(
                    false,
                    true,
                    children: [
                      Text(
                        tr(
                          'lastUpdateCheckX',
                          args: [
                            app?.app.lastUpdateCheck
                                    ?.toLocal()
                                    .toString()
                                    .split('.')
                                    .first ??
                                tr('never'),
                          ],
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  // Section 3 — URL, certificate (opt), download asset
                  section(
                    true,
                    certs || hasAssets ? false : true,
                    children: [
                      Tooltip(
                        message: tr('copyToClipboard'),
                        child: GestureDetector(
                          onLongPress: () {
                            copyToClipboard(context, app?.app.url ?? '');
                          },
                          child: LinkText(
                            text: app?.app.url ?? '',
                            url: app?.app.url ?? '',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        app?.app.id ?? '',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (certs) ...[
                    const SliverToBoxAdapter(child: SizedBox(height: 2)),
                    section(
                      false,
                      !hasAssets,
                      children: [
                        Text(
                          '${plural('certificateHash', app.certificateHashes.length)}'
                          '${app.hasMultipleSigners ? " (${tr('multipleSigners')})" : ""}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        ...app.certificateHashes.map(
                          (h) => Tooltip(
                            message: tr('copyToClipboard'),
                            child: GestureDetector(
                              onLongPress: () {
                                copyToClipboard(context, h);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Text(
                                  h,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (hasAssets) ...[
                    const SliverToBoxAdapter(child: SizedBox(height: 2)),
                    section(
                      false,
                      true,
                      children: [
                        Center(
                          child: HighlightableButton(
                            highlight: settingsProvider.highlightTouchTargets,
                            onPressed: app?.app == null || updating
                                ? null
                                : () async {
                                    try {
                                      await appsProvider.downloadAppAssets([
                                        app!.app.id,
                                      ], context);
                                    } catch (e) {
                                      if (context.mounted) {
                                        showError(e, context);
                                      }
                                    }
                                  },
                            icon: const Icon(Icons.download_outlined, size: 18),
                            label: Text(
                              tr(
                                'downloadX',
                                args: [lowerCaseIfEnglish(tr('releaseAsset'))],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  // Section 4 — Categories
                  section(
                    true,
                    true,
                    children: [
                      CategorySelector(
                        alignment: WrapAlignment.start,
                        selected: app?.app.categories.toSet() ?? {},
                        onChanged: (categories) {
                          if (app != null) {
                            app.app.categories = categories.toList();
                            appsProvider.saveApps([app.app]);
                          }
                        },
                      ),
                    ],
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  // Section 5 — Actions
                  section(
                    true,
                    true,
                    children: [
                      Row(
                        children: [
                          ..._getSecondaryActions(
                            context,
                            app,
                            source,
                            appsProvider,
                            settingsProvider,
                            showAppWebpageFinal,
                            isVersionDetectionStandard,
                            trackOnly,
                          ),
                          const Spacer(),
                          _getPrimaryButton(
                            context,
                            app,
                            appsProvider,
                            settingsProvider,
                            areDownloadsRunning,
                          ),
                        ],
                      ),
                      if (app?.downloadProgress != null)
                        Semantics(
                          label: app!.downloadProgress! >= 0
                              ? tr(
                                  'percentProgress',
                                  args: [
                                    app.downloadProgress!.toInt().toString(),
                                  ],
                                )
                              : tr('installing'),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: LinearProgressIndicator(
                              value: app.downloadProgress! >= 0
                                  ? app.downloadProgress! / 100
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SliverPadding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 24,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

