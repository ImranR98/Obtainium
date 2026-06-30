import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

String appInstalledVersionText(App? app) {
  final installed = app?.installedVersion;
  if (installed == null) return tr('notInstalled');
  final upToDate = installed == app?.latestVersion;
  return '$installed ${tr('installed')}${upToDate ? ' / ${tr('latest')}' : ''}';
}

/// A read-only summary of an app (icon, name, author, URL/ID, version status,
/// last update check), shown from the in-app webpage view's "more" button.
class AppInfoDialog extends StatelessWidget {
  final AppInMemory app;
  final AppsProvider appsProvider;

  const AppInfoDialog({
    super.key,
    required this.app,
    required this.appsProvider,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      scrollable: true,
      title: Text(app.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (app.icon != null)
            Center(child: AppIcon(bytes: app.icon, size: 56, radius: 14))
          else
            const SizedBox.shrink(),
          const SizedBox(height: 12),
          Text(
            app.name,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            tr('byX', args: [app.author]),
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            app.app.url,
            style: textTheme.labelSmall?.copyWith(
              decoration: TextDecoration.underline,
            ),
          ),
          Text(app.app.id, style: textTheme.labelSmall),
          const SizedBox(height: 8),
          Text(appInstalledVersionText(app.app), style: textTheme.bodyMedium),
          Text(
            tr(
              'lastUpdateCheckX',
              args: [
                app.app.lastUpdateCheck
                        ?.toLocal()
                        .toString()
                        .split('.')
                        .first ??
                    tr('never'),
              ],
            ),
            style: textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('continue')),
        ),
      ],
    );
  }
}
