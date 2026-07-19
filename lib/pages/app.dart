import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:obtainium/components/app_list_tile.dart';
import 'package:obtainium/components/category_editor.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/components/app_detail_widgets.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

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
  late final AppsProvider appsProvider;
  late final SettingsProvider settingsProvider;
  late final String appId;
  bool _initialized = false;

  late final SourceProvider _sourceProvider;
  WebViewController? webViewController;
  bool webViewLoaded = false;
  bool _webViewReady = false;
  bool get webViewReady => _webViewReady;
  String? _webViewError;
  bool _pendingAppIdChange = false;
  AppInMemory? prevApp;
  bool updating = false;

  int? _appCacheSig;
  AppInMemory? _appCache;

  // Best-effort download-size probe for the currently-selected APK URL.
  String? _sizeProbeKey;
  int? _probedDownloadSize;

  void _maybeProbeDownloadSize(AppInMemory app) {
    if (app.app.apkUrls.isEmpty) return;
    final idx =
        (app.app.preferredApkIndex >= 0 &&
            app.app.preferredApkIndex < app.app.apkUrls.length)
        ? app.app.preferredApkIndex
        : 0;
    final url = app.app.apkUrls[idx].value;
    if (url.isEmpty || url == 'placeholder') return;
    final key = '${app.app.id}|$url';
    if (key == _sizeProbeKey) return;
    _sizeProbeKey = key;
    _probedDownloadSize = null;
    () async {
      try {
        final source = _sourceProvider.getSource(
          app.app.url,
          overrideSource: app.app.overrideSource,
        );
        final resolvedUrl = await source.assetUrlPrefetchModifier(
          url,
          app.app.url,
          app.app.additionalSettings,
        );
        final headers = await source.getRequestHeaders(
          app.app.additionalSettings,
          resolvedUrl,
          forAPKDownload: true,
        );
        final size = await getDownloadSize(
          resolvedUrl,
          headers: headers,
          allowInsecure: app.app.settings.getBool('allowInsecure'),
        );
        if (mounted && _sizeProbeKey == key && size != null) {
          setState(() => _probedDownloadSize = size);
        }
      } catch (e) {
        // Best-effort only: leave the size unknown when it can't be resolved.
        unawaited(LogsProvider().add('Size probe failed for $url: $e'));
      }
    }();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      appId = widget.appId;
      appsProvider = context.read<AppsProvider>();
      settingsProvider = context.read<SettingsProvider>();
      _sourceProvider = context.read<SourceProvider>();
      _initialized = true;
    }
  }

  @override
  void didUpdateWidget(covariant AppPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // React to appId changes even before the WebView is ready, but defer
    // UI updates until the WebView has finished loading to avoid
    // predictive-back crashes.
    if (_initialized && oldWidget.appId != widget.appId) {
      _pendingAppIdChange = true;
      if (webViewReady) {
        _pendingAppIdChange = false;
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    webViewController = null;
    super.dispose();
  }

  void onWebViewLoaded() {
    _webViewReady = true;
    if (_pendingAppIdChange) {
      _pendingAppIdChange = false;
      setState(() {});
    }
  }

  AppSource? get source {
    final aim = appsProvider.apps[appId];
    if (aim == null) return null;
    return _sourceProvider.getSource(
      aim.app.url,
      overrideSource: aim.app.overrideSource,
    );
  }

  WebViewController ensureWebViewController(String url) {
    var wvc = webViewController;
    if (wvc == null) {
      wvc = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) {
              onWebViewLoaded();
            },
            onWebResourceError: (WebResourceError error) {
              if (error.isForMainFrame == true) {
                setState(() {
                  _webViewError = error.description;
                });
              }
            },
            onNavigationRequest: (NavigationRequest request) =>
                !(request.url.startsWith('http://') ||
                    request.url.startsWith('https://') ||
                    request.url.startsWith('ftp://') ||
                    request.url.startsWith('ftps://'))
                ? NavigationDecision.prevent
                : NavigationDecision.navigate,
          ),
        );
      webViewController = wvc;
    }
    if (!webViewLoaded) {
      webViewLoaded = true;
      wvc.loadRequest(Uri.parse(url));
    }
    return wvc;
  }

  int appSignature(AppInMemory a) {
    final app = a.app;
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
      jsonEncode(app.additionalSettings),
    ]);
  }

  AppInMemory? cachedApp(AppInMemory? source) {
    if (source == null) {
      _appCache = null;
      _appCacheSig = null;
      return null;
    }
    final sig = appSignature(source);
    if (sig == _appCacheSig && _appCache != null) {
      return _appCache;
    }
    final copy = source.deepCopy();
    _appCache = copy;
    _appCacheSig = sig;
    return copy;
  }

  Future<void> getUpdate(
    BuildContext context, {
    bool resetVersion = false,
  }) async {
    try {
      updating = true;
      if (mounted) setState(() {});
      await appsProvider.checkUpdate(appId);
      if (resetVersion) {
        final currentAim = appsProvider.apps[appId];
        if (currentAim != null) {
          var updatedApp = currentAim.app.copyWith(
            additionalSettings: Map<String, dynamic>.from(
              currentAim.app.additionalSettings,
            )..['versionDetection'] = true,
          );
          if (updatedApp.installedVersion != null) {
            updatedApp = updatedApp.copyWith(
              installedVersion: updatedApp.latestVersion,
            );
          }
          await appsProvider.saveApps([updatedApp]);
        }
      }
    } catch (err) {
      if (err is RepositoryRenamedError && context.mounted) {
        await appsProvider.updatePendingRepoRename(appId, err.newUrl);
      } else if (context.mounted) {
        showError(err, context);
      }
    } finally {
      updating = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> showMarkUpdatedDialog(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: tr('alreadyUpToDateQuestion'),
      confirmText: tr('yesMarkUpdated'),
      autofocusConfirm: settingsProvider.isTV,
    );
    if (!confirmed) return;
    settingsProvider.selectionClick();
    final aim = appsProvider.apps[appId];
    var updatedApp = aim?.app;
    if (updatedApp != null) {
      updatedApp = updatedApp.copyWith(
        installedVersion: updatedApp.latestVersion,
      );
      unawaited(appsProvider.saveApps([updatedApp]));
    }
  }

  Future<Map<String, dynamic>?> showAdditionalOptionsDialog(
    BuildContext context,
    AppInMemory? app,
  ) async {
    final s = source;
    final items = (s?.combinedAppSpecificSettingFormItems ?? []).map((row) {
      row = row.map((e) {
        if (app?.app.additionalSettings[e.key] != null) {
          e.value = app?.app.additionalSettings[e.key];
        }
        return e;
      }).toList();
      return row;
    }).toList();

    Map<String, dynamic> values = {};
    return Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (ctx) => PopScope<Map<String, dynamic>>(
          // Leaving the page saves the settings, so there is no Continue button.
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            Navigator.of(ctx).pop(values);
          },
          child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  automaticallyImplyLeading: false,
                  title: Text(
                    tr('additionalOptsFor', args: [app?.name ?? tr('app')]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      MediaQuery.of(context).padding.bottom,
                    ),
                    child: GeneratedForm(
                      tileMode: true,
                      items: items,
                      onValueChanges: (v, valid, isBuilding) {
                        values = v;
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void handleAdditionalOptionChanges(
    Map<String, dynamic>? values,
    BuildContext context,
    AppInMemory? app,
  ) {
    if (app != null && values != null) {
      final s = source;
      final Map<String, dynamic> originalSettings = app.app.additionalSettings;
      app.app = app.app.copyWith(additionalSettings: values);
      if (s?.enforceTrackOnly == true) {
        app.app = app.app.copyWith(
          additionalSettings: Map<String, dynamic>.from(
            app.app.additionalSettings,
          )..['trackOnly'] = true,
        );
        if (context.mounted) {
          showMessage(tr('appsFromSourceAreTrackOnly'), context);
        }
      }
      final versionDetectionEnabled =
          app.app.settings.getBool('versionDetection') &&
          originalSettings['versionDetection'] != true;
      final releaseDateVersionEnabled =
          app.app.settings.getBool('releaseDateAsVersion') &&
          originalSettings['releaseDateAsVersion'] != true;
      final releaseDateVersionDisabled =
          !app.app.settings.getBool('releaseDateAsVersion') &&
          originalSettings['releaseDateAsVersion'] == true;
      if (releaseDateVersionEnabled) {
        if (app.app.releaseDate != null) {
          final bool isUpdated =
              app.app.installedVersion == app.app.latestVersion;
          app.app = app.app.copyWith(
            latestVersion: app.app.releaseDate!.microsecondsSinceEpoch
                .toString(),
          );
          if (isUpdated) {
            app.app = app.app.copyWith(installedVersion: app.app.latestVersion);
          }
        }
      } else if (releaseDateVersionDisabled) {
        app.app = app.app.copyWith(
          installedVersion:
              app.installedInfo?.versionName ?? app.app.installedVersion,
        );
      }
      if (versionDetectionEnabled) {
        app.app = app.app.copyWith(
          additionalSettings:
              Map<String, dynamic>.from(app.app.additionalSettings)
                ..['versionDetection'] = true
                ..['releaseDateAsVersion'] = false,
        );
      }
      appsProvider.saveApps([app.app]).then((_) {
        if (context.mounted) {
          getUpdate(context, resetVersion: versionDetectionEnabled);
        }
      });
    }
  }

  Future<List<String>> installOrUpdate(
    BuildContext context,
    AppInMemory? app,
  ) async {
    try {
      final trackOnly = app?.app.settings.getBool('trackOnly') == true;
      final successMessage = app?.app.installedVersion == null
          ? tr('installed')
          : tr('appsUpdated');
      final np = Provider.of<NotificationsProvider>(context, listen: false);
      settingsProvider.heavyImpact();
      final res = await appsProvider.downloadAndInstallLatestApps([
        appId,
      ], appNavigatorKey.currentContext);
      if (res.isNotEmpty && !trackOnly && context.mounted) {
        showMessage(successMessage, context);
      }
      if (res.isNotEmpty) {
        unawaited(np.cancel(updateNotificationId));
        unawaited(
          np.cancel(
            SilentUpdateAttemptNotification([], id: res[0].hashCode).id,
          ),
        );
      }
      return res;
    } catch (e) {
      if (context.mounted) showError(e, context);
      return <String>[];
    }
  }

  void resetInstallStatus(AppInMemory? app) {
    if (app == null) return;
    app.app = app.app.copyWith(installedVersion: null);
    unawaited(appsProvider.saveApps([app.app]));
  }

  Future<bool> removeApp(BuildContext context, AppInMemory? app) async {
    if (app == null) return false;
    return await appsProvider.removeAppsWithModal(context, [app.app]) == true;
  }

  void openAppSettings(AppInMemory? app) {
    if (app == null) return;
    appsProvider.openAppSettings(app.app.id);
  }

  void updateAppIcon() {
    appsProvider.updateAppIcon(appId, ignoreCache: true);
  }

  void _closePage() {
    if (!mounted) return;
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (ModalRoute.of(context)?.isCurrent ?? false) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleInstallOrUpdate(
    BuildContext context,
    AppInMemory? app,
  ) async {
    final res = await installOrUpdate(context, app);
    if (res.isNotEmpty && mounted) {
      _closePage();
    }
  }

  Widget _getAppWebView(BuildContext context, AppInMemory? app) {
    if (app == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_webViewError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(tr('webviewLoadError')),
              Text(
                _webViewError!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _webViewError = null;
                    webViewLoaded = false;
                  });
                },
                child: Text(tr('retry')),
              ),
            ],
          ),
        ),
      );
    }
    final webController = ensureWebViewController(app.app.url)
      ..setBackgroundColor(Theme.of(context).colorScheme.surface);
    return WebViewWidget(
      key: ObjectKey(webController),
      controller: webController,
    );
  }

  AppBar _appScreenAppBar() => AppBar(
    automaticallyImplyLeading: false,
    leading: widget.onClose != null
        ? IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _closePage,
          )
        : null,
  );

  Widget _getPrimaryButton(
    BuildContext context,
    AppInMemory? app,
    AppsProvider appsProvider,
    bool areDownloadsRunning,
  ) {
    final installed = app?.app.installedVersion;
    final latest = app?.app.latestVersion;
    final hasAction =
        app != null &&
        !updating &&
        (installed == null || installed != latest) &&
        !areDownloadsRunning;
    final trackOnly = app?.app.settings.getBool('trackOnly') == true;
    return FilledButton.icon(
      onPressed: hasAction ? () => _handleInstallOrUpdate(context, app) : null,
      icon: Icon(
        installed == null
            ? Icons.download_outlined
            : Icons.system_update_alt_rounded,
      ),
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            installed == null
                ? (!trackOnly ? tr('install') : tr('markInstalled'))
                : !trackOnly
                ? tr('update')
                : tr('markUpdated'),
          ),
          if (_probedDownloadSize != null)
            Text(
              formatBytes(_probedDownloadSize!),
              style: const TextStyle(fontSize: 12),
            ),
        ],
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
                  final values = await showAdditionalOptionsDialog(
                    context,
                    app,
                  );
                  if (context.mounted) {
                    handleAdditionalOptionChanges(values, context, app);
                  }
                },
          tooltip: tr('additionalOptions'),
          icon: const Icon(Icons.edit),
        ),
      if (app != null && app.installedInfo != null)
        IconButton(
          onPressed: () {
            openAppSettings(app);
          },
          icon: const Icon(Icons.settings),
          tooltip: tr('settings'),
        ),
      if (app != null && showAppWebpageFinal)
        IconButton(
          onPressed: () async {
            updateAppIcon();
            if (!context.mounted) return;
            unawaited(
              showDialog(
                context: context,
                builder: (BuildContext ctx) =>
                    AppInfoDialog(app: app, appsProvider: appsProvider),
              ),
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
              : () => showMarkUpdatedDialog(context),
          tooltip: tr('markUpdated'),
          icon: const Icon(Icons.done),
        ),
      if ((!isVersionDetectionStandard || trackOnly) &&
          app?.app.installedVersion != null &&
          app?.app.installedVersion == app?.app.latestVersion)
        IconButton(
          onPressed: updating
              ? null
              : () {
                  resetInstallStatus(app);
                },
          icon: const Icon(Icons.restore_rounded),
          tooltip: tr('resetInstallStatus'),
        ),
      IconButton(
        onPressed: app == null || app.downloadProgress != null || updating
            ? null
            : () {
                removeApp(context, app).then((removed) {
                  if (removed) {
                    _closePage();
                  }
                });
              },
        tooltip: tr('remove'),
        icon: const Icon(Icons.delete_outline),
      ),
    ];
  }

  Widget _buildSection(
    bool isFirst,
    bool isLast, {
    required List<Widget> children,
    EdgeInsetsGeometry? padding,
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: ConnectedCard(
          isFirst: isFirst,
          isLast: isLast,
          padding: padding ?? const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _repoRenameInfoRow(IconData icon, String title, String subtitle) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      spacing: 12,
      children: [
        Icon(icon, size: 24, color: cs.onSurfaceVariant),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: tt.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Banner shown when a repository rename was detected, letting the user adopt
  /// the new URL (which resumes update checks) or dismiss it. Returns no slivers
  /// when there is no pending rename.
  List<Widget> _buildRepoRenameSection(
    AppInMemory? app,
    AppsProvider appsProvider,
  ) {
    if (app?.app.hasPendingRepoRename != true) return const [];
    final appId = app!.app.id;
    final pendingUrl = app.app.pendingRepoRenameUrl!;
    return [
      const SliverToBoxAdapter(child: SizedBox(height: 20)),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 3,
            children: [
              ConnectedCard(
                isFirst: true,
                isLast: false,
                child: _repoRenameInfoRow(
                  Icons.info_outline_rounded,
                  tr('repoRenamed'),
                  tr('repoRenamedExplanation'),
                ),
              ),
              ConnectedCard(
                isFirst: false,
                isLast: false,
                child: _repoRenameInfoRow(
                  Icons.link_rounded,
                  tr('newUrl'),
                  pendingUrl,
                ),
              ),
              ConnectedCard(
                isFirst: false,
                isLast: true,
                child: Row(
                  spacing: 12,
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            appsProvider.updatePendingRepoRename(appId, null),
                        child: Text(tr('dismiss')),
                      ),
                    ),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () async {
                          await appsProvider.acceptRepoRename(
                            appId,
                            pendingUrl,
                          );
                          if (mounted) unawaited(getUpdate(context));
                        },
                        child: Text(tr('updateUrl')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildAppIcon(AppInMemory? app) {
    final icon = AppIcon(bytes: app?.icon, size: 56, radius: 14);
    if (app == null || app.installedInfo == null) return icon;
    return Semantics(
      button: true,
      label: app.name,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          settingsProvider.lightImpact();
          packageManager.openApp(app.app.id);
        },
        child: icon,
      ),
    );
  }

  Widget _buildHeaderSection(AppInMemory? app) {
    return _buildSection(
      true,
      true,
      children: [
        Row(
          children: [
            _buildAppIcon(app),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app?.name ?? tr('app'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr('byX', args: [app?.author ?? tr('unknown')]),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildVersionInfoSections(AppInMemory? app) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final trackOnly = app?.app.settings.getBool('trackOnly') == true;
    final pseudo = app?.app != null && isVersionPseudo(app!.app);
    final realVersion = app?.installedInfo?.versionName;
    final apkCount = app?.app.apkUrls.length ?? 0;
    final changeLogFn = app != null ? getChangeLogFn(context, app.app) : null;
    return [
      _buildSection(
        true,
        false,
        children: [
          if (trackOnly) _detailNote(tr('xIsTrackOnly', args: [tr('app')])),
          if (pseudo)
            _detailNote(
              realVersion != null
                  ? '${tr('pseudoVersionInUse')} (OS installed $realVersion)'
                  : tr('pseudoVersionInUse'),
            ),
          () {
            String l = appInstalledVersionText(app?.app);
            final upToDate =
                app?.app.installedVersion == app?.app.latestVersion;
            if (!upToDate) {
              l += '\n${app?.app.latestVersion} ${tr('latest')}';
            }
            return Text(
              l,
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            );
          }(),
          if (apkCount > 0)
            _detailNote(
              apkCount == 1 ? app!.app.apkUrls[0].key : plural('apk', apkCount),
            ),
          if (changeLogFn != null || app?.app.releaseDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: changeLogFn,
                borderRadius: BorderRadius.circular(4),
                child: Text(
                  app?.app.releaseDate == null
                      ? tr('changes')
                      : app!.app.releaseDate!
                            .toLocal()
                            .toString()
                            .split('.')
                            .first,
                  style: tt.bodyMedium?.copyWith(
                    color: changeLogFn != null
                        ? cs.primary
                        : cs.onSurfaceVariant,
                    fontStyle: changeLogFn != null ? FontStyle.italic : null,
                    decoration: changeLogFn != null
                        ? TextDecoration.underline
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 2)),
      _buildSection(
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
            style: tt.bodyMedium,
          ),
        ],
      ),
    ];
  }

  Widget _detailNote(String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }

  /// Renders the source-provided "about" markdown, when present, as its own
  /// section so it fits the sectioned detail layout.
  List<Widget> _buildAboutSection(AppInMemory? app) {
    final about = app?.app.additionalSettings['about'];
    if (about is! String || about.isEmpty) return const [];
    return [
      const SliverToBoxAdapter(child: SizedBox(height: 20)),
      _buildSection(
        true,
        true,
        children: [
          MarkdownBody(
            data: about,
            styleSheet: MarkdownStyleSheet(
              blockquoteDecoration: BoxDecoration(
                color: Theme.of(context).cardColor,
              ),
            ),
            onTapLink: (text, href, title) {
              if (href != null) {
                unawaited(
                  launchUrlString(href, mode: LaunchMode.externalApplication),
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
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildSourceInfoSections(
    AppInMemory? app,
    AppsProvider appsProvider,
    SettingsProvider settingsProvider,
    bool certs,
    bool hasAssets,
  ) {
    final widgets = <Widget>[
      _buildSection(
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
    ];
    if (certs) {
      final a = app!;
      widgets.addAll([
        const SliverToBoxAdapter(child: SizedBox(height: 2)),
        _buildSection(
          false,
          !hasAssets,
          children: [
            Text(
              '${plural('certificateHash', a.certificateHashes.length)}'
              '${a.hasMultipleSigners ? " (${tr('multipleSigners')})" : ""}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            ...a.certificateHashes.map(
              (h) => Tooltip(
                message: tr('copyToClipboard'),
                child: GestureDetector(
                  onLongPress: () {
                    copyToClipboard(context, h);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
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
      ]);
    }
    if (hasAssets) {
      widgets.addAll([
        const SliverToBoxAdapter(child: SizedBox(height: 2)),
        _buildSection(
          false,
          true,
          padding: const EdgeInsets.all(0),
          children: [
            Center(
              child: TextButton.icon(
                onPressed: app?.app == null || updating
                    ? null
                    : () async {
                        try {
                          await appsProvider.downloadAppAssets([
                            app!.app.id,
                          ], context);
                        } catch (e) {
                          if (mounted) {
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
      ]);
    }
    return widgets;
  }

  Widget _buildCategorySection(AppInMemory? app, AppsProvider appsProvider) {
    return _buildSection(
      true,
      true,
      children: [
        CategorySelector(
          alignment: WrapAlignment.start,
          selected: app?.app.categories.toSet() ?? {},
          onChanged: (categories) {
            if (app != null) {
              app.app = app.app.copyWith(categories: categories.toList());
              unawaited(appsProvider.saveApps([app.app]));
            }
          },
        ),
      ],
    );
  }

  Widget _buildActionsContent(
    AppInMemory? app,
    AppsProvider appsProvider,
    SettingsProvider settingsProvider,
    AppSource? source,
    bool showAppWebpageFinal,
    bool isVersionDetectionStandard,
    bool trackOnly,
    bool areDownloadsRunning,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (app?.downloadProgress != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: app!.downloadProgress! >= 0
                        ? tr(
                            'percentProgress',
                            args: [app.downloadProgress!.toInt().toString()],
                          )
                        : tr('installing'),
                    child: LinearProgressIndicator(
                      value: app.downloadProgress! >= 0
                          ? app.downloadProgress! / 100
                          : null,
                    ),
                  ),
                ),
                if (app.downloadProgress! >= 0) ...[
                  const SizedBox(width: 8),
                  DownloadCancelButton(
                    onPressed: () => appsProvider.cancelDownload(widget.appId),
                  ),
                ],
              ],
            ),
          ),
        if (app?.downloadProgress != null &&
            app!.downloadProgress! >= 0 &&
            app.downloadReceivedBytes != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              formatDownloadSize(
                app.downloadReceivedBytes,
                app.downloadTotalBytes,
              )!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
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
                areDownloadsRunning,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appsProvider = context.read<AppsProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final showAppWebpageFinal =
        (settingsProvider.showAppWebpage &&
            !widget.showOppositeOfPreferredView) ||
        (!settingsProvider.showAppWebpage &&
            widget.showOppositeOfPreferredView);
    final bool areDownloadsRunning = context.select<AppsProvider, bool>(
      (p) => p.areDownloadsRunning(),
    );
    context.select<AppsProvider, double?>(
      (p) => p.apps[widget.appId]?.downloadProgress,
    );

    final AppInMemory? app = cachedApp(
      context.select<AppsProvider, AppInMemory?>((p) => p.apps[widget.appId]),
    );
    final installed = app?.app.installedVersion;
    final latest = app?.app.latestVersion;
    if (app != null &&
        app.downloadProgress == null &&
        !updating &&
        !areDownloadsRunning &&
        (installed == null || installed != latest)) {
      _maybeProbeDownloadSize(app);
    }
    final source = this.source;

    if (!areDownloadsRunning &&
        prevApp == null &&
        app != null &&
        settingsProvider.checkUpdateOnDetailPage) {
      prevApp = app;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) getUpdate(context);
      });
    }
    final trackOnly = app?.app.settings.getBool('trackOnly') == true;

    final bool isVersionDetectionStandard =
        app?.app.settings.getBool('versionDetection') == true;

    final certs = app != null && app.certificateHashes.isNotEmpty;
    final hasAssets =
        app?.app.apkUrls.isNotEmpty == true ||
        app?.app.otherAssetUrls.isNotEmpty == true;

    return Scaffold(
      appBar: showAppWebpageFinal ? _appScreenAppBar() : null,
      floatingActionButton: showAppWebpageFinal
          ? FloatingActionButton(
              onPressed: () {
                settingsProvider.selectionClick();
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
      body: showAppWebpageFinal
          ? _getAppWebView(context, app)
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      if (app != null) {
                        await getUpdate(context);
                      }
                    },
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: MediaQuery.of(context).padding.top + 8,
                          ),
                        ),
                        _buildHeaderSection(app),
                        ..._buildRepoRenameSection(app, appsProvider),
                        const SliverToBoxAdapter(child: SizedBox(height: 20)),
                        ..._buildVersionInfoSections(app),
                        const SliverToBoxAdapter(child: SizedBox(height: 20)),
                        ..._buildSourceInfoSections(
                          app,
                          appsProvider,
                          settingsProvider,
                          certs,
                          hasAssets,
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 20)),
                        _buildCategorySection(app, appsProvider),
                        ..._buildAboutSection(app),
                        const SliverToBoxAdapter(child: SizedBox(height: 32)),
                      ],
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: SafeArea(
                    top: false,
                    child: _buildActionsContent(
                      app,
                      appsProvider,
                      settingsProvider,
                      source,
                      showAppWebpageFinal,
                      isVersionDetectionStandard,
                      trackOnly,
                      areDownloadsRunning,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
