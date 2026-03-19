import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/pages/apps.dart';
import 'package:obtainium/pages/settings.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:provider/provider.dart';
import 'package:markdown/markdown.dart' as md;

class AppPage extends StatefulWidget {
  const AppPage({
    super.key,
    required this.appId,
    this.showOppositeOfPreferredView = false,
  });

  final String appId;
  final bool showOppositeOfPreferredView;

  @override
  State<AppPage> createState() => _AppPageState();
}

class _AppPageState extends State<AppPage> {
  static const double _versionRowLabelWidth = 120;

  late final WebViewController _webViewController;
  bool _wasWebViewOpened = false;
  AppInMemory? prevApp;
  bool updating = false;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == true) {
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
  }

  @override
  Widget build(BuildContext context) {
    var appsProvider = context.watch<AppsProvider>();
    var settingsProvider = context.watch<SettingsProvider>();
    var showAppWebpageFinal =
        (settingsProvider.showAppWebpage &&
            !widget.showOppositeOfPreferredView) ||
        (!settingsProvider.showAppWebpage &&
            widget.showOppositeOfPreferredView);
    getUpdate(String id, {bool resetVersion = false}) async {
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
        // ignore: use_build_context_synchronously
        showError(err, context);
      } finally {
        setState(() {
          updating = false;
        });
      }
    }

    bool areDownloadsRunning = appsProvider.areDownloadsRunning();

    var sourceProvider = SourceProvider();
    AppInMemory? app = appsProvider.apps[widget.appId]?.deepCopy();
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
      getUpdate(app.app.id);
    }
    var trackOnly = app?.app.additionalSettings['trackOnly'] == true;

    bool isVersionDetectionStandard =
        app?.app.additionalSettings['versionDetection'] == true;

    bool installedVersionIsEstimate = app?.app != null
        ? isVersionPseudo(app!.app)
        : false;

    if (app != null && !_wasWebViewOpened) {
      _wasWebViewOpened = true;
      _webViewController.loadRequest(Uri.parse(app.app.url));
    }

    Widget _sectionCard(
      BuildContext ctx,
      String sectionTitle,
      List<Widget> children,
    ) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final colorScheme = Theme.of(ctx).colorScheme;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? colorScheme.surfaceContainerHighest
              : colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
          boxShadow: [
            if (isDark)
              BoxShadow(
                color: colorScheme.shadow.withAlpha(180),
                blurRadius: 16,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              )
            else
              BoxShadow(
                color: colorScheme.shadow.withAlpha(40),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                sectionTitle,
                style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );
    }

    String _formatDateTimeToMinute(DateTime dateTime) {
      final local = dateTime.toLocal();
      final year = local.year.toString();
      final month = local.month.toString().padLeft(2, '0');
      final day = local.day.toString().padLeft(2, '0');
      final hour = local.hour.toString().padLeft(2, '0');
      final minute = local.minute.toString().padLeft(2, '0');
      return '$year-$month-$day $hour:$minute';
    }

    Widget _detailRow(BuildContext ctx, String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
              ),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    Widget _detailRowWithLink(
      BuildContext ctx,
      String label,
      String value,
      VoidCallback? onTap,
    ) {
      final linkStyle = Theme.of(ctx).textTheme.bodySmall?.copyWith(
            color: onTap != null
                ? Theme.of(ctx).colorScheme.primary
                : null,
            decoration: onTap != null ? TextDecoration.underline : null,
          );
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: Text(
                  value,
                  style: linkStyle,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget _versionVerdictRow(BuildContext ctx, Widget chip) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _versionRowLabelWidth,
              child: Text(
                tr('verdict'),
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
            ),
            const SizedBox(width: 8),
            chip,
          ],
        ),
      );
    }

    Widget _versionRow(BuildContext ctx, String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: _versionRowLabelWidth,
              child: Text(
                label,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                value,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    Widget _versionRowWithLink(
      BuildContext ctx,
      String label,
      String value,
      VoidCallback? onTap,
    ) {
      final linkStyle = Theme.of(ctx).textTheme.bodySmall?.copyWith(
            color: Theme.of(ctx).colorScheme.primary,
            decoration: onTap != null ? TextDecoration.underline : null,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          );
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: _versionRowLabelWidth,
              child: Text(
                label,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: Text(
                  value,
                  style: linkStyle,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget _buildDownloadLink() {
      if (app?.app.apkUrls.isEmpty != false &&
          app?.app.otherAssetUrls.isEmpty != false) return const SizedBox.shrink();
      return GestureDetector(
        onTap: app?.app == null || updating
            ? null
            : () async {
                try {
                  await appsProvider.downloadAppAssets(
                      [app!.app.id], context);
                } catch (e) {
                  showError(e, context);
                }
              },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: settingsProvider.highlightTouchTargets
                    ? (Theme.of(context).brightness == Brightness.light
                          ? Theme.of(context).primaryColor
                          : Theme.of(context).primaryColorLight)
                        .withAlpha(
                            Theme.of(context).brightness == Brightness.light
                                ? 20
                                : 40)
                    : null,
              ),
              padding: settingsProvider.highlightTouchTargets
                  ? const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 6)
                  : const EdgeInsetsDirectional.fromSTEB(0, 2, 0, 2),
              margin: const EdgeInsetsDirectional.fromSTEB(0, 2, 0, 0),
              child: Text(
                tr('downloadX',
                    args: [lowerCaseIfEnglish(tr('releaseAsset'))]),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      decoration: TextDecoration.underline,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    Widget _buildCertBlock() {
      if (app == null || app!.certificateHashes.isEmpty) return const SizedBox.shrink();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: app!.certificateHashes.map((hash) {
          return GestureDetector(
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: hash));
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('copiedToClipboard'))));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              child: SelectableText(
                hash,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          );
        }).toList(),
      );
    }

    Widget _buildAboutBlock() {
      if (app?.app.additionalSettings['about'] is! String ||
          (app?.app.additionalSettings['about'] as String).isEmpty)
        return const SizedBox.shrink();
      return GestureDetector(
        onLongPress: () {
          Clipboard.setData(
              ClipboardData(
                  text: app?.app.additionalSettings['about'] ?? ''));
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr('copiedToClipboard'))));
        },
        child: Markdown(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          styleSheet: MarkdownStyleSheet(
            blockquoteDecoration: BoxDecoration(
              color: Theme.of(context).cardColor,
            ),
            textAlign: WrapAlignment.center,
          ),
          data: app?.app.additionalSettings['about'] as String,
          onTapLink: (text, href, title) {
            if (href != null) {
              launchUrlString(href, mode: LaunchMode.externalApplication);
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
      );
    }

    getInfoColumn({bool small = false}) {
      final undeterminedTrackOnlyInstalled =
          trackOnly &&
              app?.app.additionalSettings['trackOnlyUndeterminedInstalledVersion'] ==
                  true &&
              app?.app.installedVersion == null;
      bool installed = app?.app.installedVersion != null;
      bool upToDate = app?.app.installedVersion == app?.app.latestVersion ||
          (app?.app.installedVersion != null &&
              (versionsEffectivelyEqual(
                  app!.app.installedVersion!, app.app.latestVersion) ||
                  installedVersionIsNewerOrEqual(
                      app!.app.installedVersion!, app.app.latestVersion)));
      final effectivelyEqual = installed &&
          app!.app.installedVersion != null &&
          app.app.installedVersion != app.app.latestVersion &&
          versionsEffectivelyEqual(
              app.app.installedVersion!, app.app.latestVersion);
      if (undeterminedTrackOnlyInstalled) {
        upToDate = false;
      }
      var changeLogFn = app != null ? getChangeLogFn(context, app.app) : null;

      final lastUpdateCheckLabel =
          tr('lastUpdateCheckX', args: [tr('never')]).split(':').first.trim();
      final lastUpdateCheckValue = app?.app.lastUpdateCheck == null
          ? tr('never')
          : _formatDateTimeToMinute(app!.app.lastUpdateCheck!);

      final versionCardChildren = <Widget>[];
      if (undeterminedTrackOnlyInstalled) {
        final installedLabel = app?.app.additionalSettings['trackOnlyTemporaryPackageId'] == true
            ? tr('trackOnlyTempPackageIdInstalledVersion')
            : tr('trackOnlyUndeterminedInstalledVersion');
        versionCardChildren.add(
          _versionRow(context, tr('installed'), installedLabel),
        );
        versionCardChildren.add(
          _versionRow(context, tr('latest'), app?.app.latestVersion ?? '-'),
        );
        versionCardChildren.add(
          _versionRow(context, lastUpdateCheckLabel, lastUpdateCheckValue),
        );
        if (changeLogFn != null || app?.app.releaseDate != null) {
          versionCardChildren.add(
            _versionRowWithLink(
              context,
              tr('changelog'),
              app?.app.releaseDate == null
                  ? tr('changes')
                  : _formatDateTimeToMinute(app!.app.releaseDate!),
              changeLogFn,
            ),
          );
        }
        if ((app?.app.apkUrls.length ?? 0) > 0) {
          versionCardChildren.add(
            _versionRowWithLink(
              context,
              tr('assets'),
              app!.app.apkUrls.length == 1
                  ? app!.app.apkUrls[0].key
                  : plural('apk', app!.app.apkUrls.length),
              app?.app == null || updating
                  ? null
                  : () async {
                      try {
                        await appsProvider.downloadAppAssets(
                            [app!.app.id], context);
                      } catch (e) {
                        showError(e, context);
                      }
                    },
            ),
          );
        }
      } else {
        if (installed) {
          versionCardChildren.add(
            _versionRow(context, tr('installed'), app?.app.installedVersion ?? ''),
          );
        } else {
          versionCardChildren.add(
            _versionRow(context, tr('installed'), tr('notInstalled')),
          );
        }
        versionCardChildren.add(
          _versionRow(context, tr('latest'), app?.app.latestVersion ?? '-'),
        );
        if (effectivelyEqual) {
          versionCardChildren.add(_versionVerdictRow(
            context,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                tr('effectivelyEqual'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ));
        } else if (upToDate) {
          versionCardChildren.add(_versionVerdictRow(
            context,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF2E7D32).withAlpha(60)
                    : const Color(0xFFC8E6C9),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                tr('sameVersion'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFFA5D6A7)
                          : const Color(0xFF1B5E20),
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ));
        } else if (installed) {
          versionCardChildren.add(_versionVerdictRow(
            context,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                tr('updateAvailable'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ));
        }
        versionCardChildren.add(
          _versionRow(context, lastUpdateCheckLabel, lastUpdateCheckValue),
        );
        if (changeLogFn != null || app?.app.releaseDate != null) {
          versionCardChildren.add(
            _versionRowWithLink(
              context,
              tr('changelog'),
              app?.app.releaseDate == null
                  ? tr('changes')
                  : _formatDateTimeToMinute(app!.app.releaseDate!),
              changeLogFn,
            ),
          );
        }
        if ((app?.app.apkUrls.length ?? 0) > 0) {
          versionCardChildren.add(
            _versionRowWithLink(
              context,
              tr('assets'),
              app!.app.apkUrls.length == 1
                  ? app!.app.apkUrls[0].key
                  : plural('apk', app!.app.apkUrls.length),
              app?.app == null || updating
                  ? null
                  : () async {
                      try {
                        await appsProvider.downloadAppAssets(
                            [app!.app.id], context);
                      } catch (e) {
                        showError(e, context);
                      }
                    },
            ),
          );
        }
      }
      final versionCard = _sectionCard(
        context,
        tr('version').toUpperCase(),
        versionCardChildren,
      );

      final detailsChildren = <Widget>[
        if (app?.app.id != null && app!.app.id!.isNotEmpty)
          _detailRow(context, tr('package'), app!.app.id!),
        if (app?.app.url != null && app!.app.url!.isNotEmpty)
          _detailRowWithLink(
            context,
            tr('trackedSource'),
            app!.app.url!,
            () => launchUrlString(
              app!.app.url!,
              mode: LaunchMode.externalApplication,
            ),
          ),
        if (app?.app.id != null && app!.app.id!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    tr('otherSources'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ActionChip(
                        label: Text(tr('playStore')),
                        onPressed: () => launchUrlString(
                          'https://play.google.com/store/apps/details?id=${app!.app.id}',
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      ActionChip(
                        label: Text(tr('apkmirror')),
                        onPressed: () => launchUrlString(
                          'https://www.apkmirror.com/?post_type=app_release&searchtype=apk&s=${Uri.encodeComponent(app!.app.id!)}',
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      ActionChip(
                        label: Text(tr('fdroidStore')),
                        onPressed: () => launchUrlString(
                          'https://f-droid.org/packages/${app!.app.id}/',
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  tr('categories'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                ),
              ),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.start,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ...(app?.app.categories ?? []).map(
                      (categoryName) => Chip(
                        label: Text(
                          categoryName,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (sheetContext) => Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CategoryEditorSelector(
                            alignment: WrapAlignment.center,
                            preselected: app?.app.categories != null
                                ? app!.app.categories.toSet()
                                : {},
                            showLabelWhenNotEmpty: false,
                            onSelected: (categories) {
                              if (app != null) {
                                app!.app.categories = categories;
                                appsProvider.saveApps([app!.app]);
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () =>
                                Navigator.pop(sheetContext),
                            child: Text(tr('continue')),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Text(tr('edit')),
              ),
            ],
          ),
        ),
      ];
      final detailsCard = _sectionCard(
        context,
        tr('details').toUpperCase(),
        detailsChildren,
      );

      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          versionCard,
          detailsCard,
          if (app?.app.additionalSettings['about'] is String &&
              app?.app.additionalSettings['about'].isNotEmpty)
            _sectionCard(
              context,
              tr('about').toUpperCase(),
              [_buildAboutBlock()],
            ),
        ],
      );
    }

    Widget _buildDetailHeroContent() {
      const double heroScale = 1.2;
      const heroIconSize = 58.0;
      final scaledIconSize = heroIconSize * heroScale;
      final titleStyle = Theme.of(context).textTheme.titleLarge;
      final bylineStyle = Theme.of(context).textTheme.bodySmall;
      final iconWidget = FutureBuilder(
        future: appsProvider.updateAppIcon(app?.app.id, ignoreCache: true),
        builder: (ctx, val) {
          if (app?.icon != null) {
            return GestureDetector(
              onTap: app == null ? null : () => pm.openApp(app.app.id),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  app!.icon!,
                  height: scaledIconSize,
                  width: scaledIconSize,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            );
          }
          return Container(
            height: scaledIconSize,
            width: scaledIconSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withAlpha(200),
                ],
              ),
            ),
          );
        },
      );
      return Padding(
        padding: const EdgeInsets.only(right: 16, bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            iconWidget,
            SizedBox(width: 12 * heroScale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    app?.name ?? tr('app'),
                    style: titleStyle?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: (titleStyle?.fontSize ?? 22) * heroScale,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2 * heroScale),
                  Text(
                    tr('byX', args: [app?.author ?? tr('unknown')]),
                    style: bylineStyle?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: (bylineStyle?.fontSize ?? 12) * heroScale,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    getFullInfoColumn({bool small = false}) {
      const heroIconSize = 48.0;
      final iconWidget = FutureBuilder(
        future: appsProvider.updateAppIcon(app?.app.id, ignoreCache: true),
        builder: (ctx, val) {
          if (app?.icon != null) {
            return GestureDetector(
              onTap: app == null ? null : () => pm.openApp(app.app.id),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(small ? 12 : 16),
                child: Image.memory(
                  app!.icon!,
                  height: small ? 70 : heroIconSize,
                  width: small ? 70 : heroIconSize,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            );
          }
          if (small) {
            return SizedBox(height: 70, width: 70);
          }
          return Container(
            height: heroIconSize,
            width: heroIconSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withAlpha(200),
                ],
              ),
            ),
          );
        },
      );

      if (small) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 0),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [iconWidget],
            ),
            const SizedBox(height: 10),
            Text(
              app?.name ?? tr('app'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall,
            ),
            Text(
              tr('byX', args: [app?.author ?? tr('unknown')]),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: settingsProvider.highlightTouchTargets ? 2 : 8),
            GestureDetector(
              onTap: () {
                if (app?.app.url != null) {
                  launchUrlString(
                    app?.app.url ?? '',
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: app?.app.url ?? ''));
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(tr('copiedToClipboard'))));
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: settingsProvider.highlightTouchTargets
                          ? (Theme.of(context).brightness == Brightness.light
                                    ? Theme.of(context).primaryColor
                                    : Theme.of(context).primaryColorLight)
                              .withAlpha(
                                  Theme.of(context).brightness == Brightness.light
                                      ? 20
                                      : 40)
                          : null,
                    ),
                    padding: settingsProvider.highlightTouchTargets
                        ? const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 6)
                        : EdgeInsetsDirectional.zero,
                    child: Text(
                      app?.app.url ?? '',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                            decoration: TextDecoration.underline,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              app?.app.id ?? '',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            getInfoColumn(small: true),
            const SizedBox(height: 24),
          ],
        );
      }

      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                iconWidget,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        app?.name ?? tr('app'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
          ),
          getInfoColumn(small: false),
          const SizedBox(height: 24),
        ],
      );
    }

    getAppWebView() => app != null
        ? WebViewWidget(
            key: ObjectKey(_webViewController),
            controller: _webViewController
              ..setBackgroundColor(Theme.of(context).colorScheme.surface),
          )
        : Container();

    showMarkUpdatedDialog() {
      return showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: Text(tr('alreadyUpToDateQuestion')),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(tr('no')),
              ),
              TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  var updatedApp = app?.app;
                  if (updatedApp != null) {
                    updatedApp.installedVersion = updatedApp.latestVersion;
                    appsProvider.saveApps([updatedApp]);
                  }
                  Navigator.of(context).pop();
                },
                child: Text(tr('yesMarkUpdated')),
              ),
            ],
          );
        },
      );
    }

    showAdditionalOptionsDialog() async {
      return await showDialog<Map<String, dynamic>?>(
        context: context,
        builder: (BuildContext ctx) {
          var items = (source?.combinedAppSpecificSettingFormItems ?? []).map((
            row,
          ) {
            row = row.map((e) {
              if (app?.app.additionalSettings[e.key] != null) {
                e.defaultValue = app?.app.additionalSettings[e.key];
              }
              return e;
            }).toList();
            return row;
          }).toList();

          return GeneratedFormModal(
            title: tr('additionalOptions'),
            items: items,
          );
        },
      );
    }

    handleAdditionalOptionChanges(Map<String, dynamic>? values) {
      if (app != null && values != null) {
        Map<String, dynamic> originalSettings = app.app.additionalSettings;
        app.app.additionalSettings = values;
        if (source?.enforceTrackOnly == true) {
          app.app.additionalSettings['trackOnly'] = true;
          // ignore: use_build_context_synchronously
          showMessage(tr('appsFromSourceAreTrackOnly'), context);
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
            bool isUpdated = app.app.installedVersion == app.app.latestVersion ||
                (app.app.installedVersion != null &&
                    versionsEffectivelyEqual(
                        app.app.installedVersion!, app.app.latestVersion));
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
          getUpdate(app.app.id, resetVersion: versionDetectionEnabled);
        });
      }
    }

    getBottomCenterActions() {
      const double expressiveRadius = 26;
      const EdgeInsets expressivePadding =
          EdgeInsets.symmetric(horizontal: 16, vertical: 14);
      const Size expressiveMinimumSize = Size(48, 52);
      final RoundedRectangleBorder expressiveShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(expressiveRadius),
      );
      const Size expressiveMaximumSize = Size(double.infinity, 52);
      final ButtonStyle expressiveFilled = FilledButton.styleFrom(
        minimumSize: expressiveMinimumSize,
        maximumSize: expressiveMaximumSize,
        padding: expressivePadding,
        shape: expressiveShape,
        elevation: 1,
        shadowColor: Theme.of(context).colorScheme.shadow,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
      final ButtonStyle expressiveTonal = FilledButton.styleFrom(
        minimumSize: expressiveMinimumSize,
        maximumSize: expressiveMaximumSize,
        padding: expressivePadding,
        shape: expressiveShape,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

      final bool actionBlocked = updating || areDownloadsRunning;
      final installedVersion = app?.app.installedVersion;
      final bool installedVersionIsNull = installedVersion == null;
      final bool versionBehind = installedVersion != null &&
          installedVersion != app!.app.latestVersion &&
          !versionsEffectivelyEqual(installedVersion, app.app.latestVersion) &&
          !installedVersionIsNewerOrEqual(installedVersion, app.app.latestVersion);
      final bool trackOnlyHasVersionUpdate = trackOnly && versionBehind;
      final bool primaryActionEnabled =
          !actionBlocked && (installedVersionIsNull || versionBehind);

      Future<void> runInstallOrMarkUpdated() async {
        try {
          final successMessage = installedVersionIsNull
              ? tr('installed')
              : tr('appsUpdated');
          HapticFeedback.heavyImpact();
          final res = await appsProvider.downloadAndInstallLatestApps(
            app?.app.id != null ? [app!.app.id] : [],
            globalNavigatorKey.currentContext,
          );
          if (res.isNotEmpty && !trackOnly && mounted) {
            showMessage(successMessage, context);
          }
          if (res.isNotEmpty && mounted) {
            Navigator.of(context).pop();
          }
        } catch (e) {
          if (mounted) {
            showError(e, context);
          }
        }
      }

      void openTrackOnlyReleasePage() {
        if (app == null) return;
        launchUrlString(
          trackOnlyDownloadPageUrl(app.app),
          mode: LaunchMode.externalApplication,
        );
      }

      if (trackOnlyHasVersionUpdate) {
        // Outer Row is in a Column with unbounded max height. A nested Row of
        // two horizontal Expanded children + stretch can get infinite cross-axis
        // extent and break layout (blank page). Fixed height bounds the inner Row.
        const double dualButtonBarHeight = 52;
        return SizedBox(
          height: dualButtonBarHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: FilledButton(
                  style: expressiveFilled,
                  onPressed: actionBlocked ? null : openTrackOnlyReleasePage,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      tr('update'),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonal(
                  style: expressiveTonal,
                  onPressed: actionBlocked ? null : runInstallOrMarkUpdated,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      tr('markUpdated'),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return FilledButton(
        style: expressiveFilled,
        onPressed: primaryActionEnabled ? runInstallOrMarkUpdated : null,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            installedVersionIsNull
                ? (!trackOnly ? tr('install') : tr('markInstalled'))
                : (!trackOnly ? tr('update') : tr('markUpdated')),
            maxLines: 1,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    getBottomSheetMenu() => Padding(
      padding: EdgeInsets.fromLTRB(
        0,
        0,
        0,
        MediaQuery.of(context).padding.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).colorScheme.surfaceContainerHigh
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).colorScheme.outlineVariant.withAlpha(140)
                  : Theme.of(context).colorScheme.outlineVariant.withAlpha(70),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow.withAlpha(
                    Theme.of(context).brightness == Brightness.dark ? 130 : 40,
                  ),
              blurRadius: Theme.of(context).brightness == Brightness.dark
                  ? 18
                  : 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                if (source != null &&
                    source.combinedAppSpecificSettingFormItems.isNotEmpty)
                  IconButton(
                    onPressed: app?.downloadProgress != null || updating
                        ? null
                        : () async {
                            var values = await showAdditionalOptionsDialog();
                            handleAdditionalOptionChanges(values);
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
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext ctx) {
                          return AlertDialog(
                            scrollable: true,
                            content: getFullInfoColumn(small: true),
                            title: Text(app.name),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                                child: Text(tr('continue')),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    icon: const Icon(Icons.more_horiz),
                    tooltip: tr('more'),
                  ),
                if (app?.app.installedVersion != null &&
                    app?.app.installedVersion != app?.app.latestVersion &&
                    !versionsEffectivelyEqual(
                        app!.app.installedVersion!, app.app.latestVersion) &&
                    !installedVersionIsNewerOrEqual(
                        app!.app.installedVersion!, app.app.latestVersion) &&
                    !isVersionDetectionStandard &&
                    !trackOnly)
                  IconButton(
                    onPressed: app?.downloadProgress != null || updating
                        ? null
                        : showMarkUpdatedDialog,
                    tooltip: tr('markUpdated'),
                    icon: const Icon(Icons.done),
                  ),
                if ((!isVersionDetectionStandard || trackOnly) &&
                    app?.app.installedVersion != null &&
                    (app?.app.installedVersion == app?.app.latestVersion ||
                        versionsEffectivelyEqual(
                            app!.app.installedVersion!, app.app.latestVersion) ||
                        installedVersionIsNewerOrEqual(
                            app!.app.installedVersion!, app.app.latestVersion)))
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
                              .removeAppsWithModal(
                                context,
                                app != null ? [app.app] : [],
                              )
                              .then((value) {
                                if (value == true) {
                                  Navigator.of(context).pop();
                                }
                              });
                        },
                  tooltip: tr('remove'),
                  icon: const Icon(Icons.delete_outline),
                ),
                  ],
                ),
                if (app?.downloadProgress != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
              child: LinearProgressIndicator(
                value: app!.downloadProgress! >= 0
                    ? app.downloadProgress! / 100
                    : null,
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: showAppWebpageFinal ? AppBar() : null,
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
        child: showAppWebpageFinal
            ? getAppWebView()
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: SafeArea(
                      top: true,
                      bottom: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () => Navigator.pop(context),
                                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                              ),
                              Expanded(child: _buildDetailHeroContent()),
                            ],
                          ),
                          getInfoColumn(small: false),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Row(
                              children: [
                                Expanded(child: getBottomCenterActions()),
                              ],
                            ),
                          ),
                          SizedBox(
                              height: MediaQuery.of(context).padding.bottom),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
        onRefresh: () async {
          if (app != null) {
            getUpdate(app.app.id);
          }
        },
      ),
      bottomSheet: getBottomSheetMenu(),
    );
  }
}
