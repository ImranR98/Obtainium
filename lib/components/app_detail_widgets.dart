import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';

String appInstalledVersionText(App? app) {
  final installed = app?.installedVersion;
  if (installed == null) return tr('notInstalled');
  final upToDate = installed == app?.latestVersion;
  return '$installed ${tr('installed')}${upToDate ? ' / ${tr('latest')}' : ''}';
}

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
    final isTV = context.read<SettingsProvider>().isTV;
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
          autofocus: isTV,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('continue')),
        ),
      ],
    );
  }
}

class AppFilePicker extends StatefulWidget {
  const AppFilePicker({
    super.key,
    required this.app,
    this.initVal,
    this.archs,
    this.pickAnyAsset = false,
  });

  final App app;
  final MapEntry<String, String>? initVal;
  final List<String>? archs;
  final bool pickAnyAsset;

  @override
  State<AppFilePicker> createState() => _AppFilePickerState();
}

class _AppFilePickerState extends State<AppFilePicker> {
  MapEntry<String, String>? fileUrl;

  @override
  Widget build(BuildContext context) {
    final isTV = context.read<SettingsProvider>().isTV;
    var urlsToSelectFrom = widget.app.apkUrls;
    if (widget.pickAnyAsset) {
      urlsToSelectFrom = [...urlsToSelectFrom, ...widget.app.otherAssetUrls];
    }
    fileUrl ??=
        widget.initVal ??
        (urlsToSelectFrom.isNotEmpty ? urlsToSelectFrom.first : null);
    return AlertDialog(
      scrollable: true,
      title: Text(
        widget.pickAnyAsset
            ? tr('selectX', args: [lowerCaseIfEnglish(tr('releaseAsset'))])
            : tr('pickAnAPK'),
      ),
      content: fileUrl == null
          ? const SizedBox.shrink()
          : RadioGroup<String>(
              groupValue: fileUrl!.value,
              onChanged: (String? val) {
                setState(() {
                  fileUrl = urlsToSelectFrom.firstWhere(
                    (e) => e.value == val,
                    orElse: () => urlsToSelectFrom.first,
                  );
                });
              },
              child: Column(
                children: [
                  urlsToSelectFrom.length > 1
                      ? Text(
                          tr(
                            'appHasMoreThanOnePackage',
                            args: [widget.app.finalName],
                          ),
                        )
                      : const SizedBox.shrink(),
                  const SizedBox(height: 16),
                  if (isTV)
                    ...urlsToSelectFrom.asMap().entries.map(
                      (entry) => ListTile(
                        autofocus: entry.key == 0,
                        leading: Radio<String>(value: entry.value.value),
                        title: Text(entry.value.key),
                        selected: fileUrl?.value == entry.value.value,
                        onTap: () {
                          setState(() {
                            fileUrl = entry.value;
                          });
                        },
                      ),
                    )
                  else
                    ...urlsToSelectFrom.map(
                      (u) => RadioListTile<String>(
                        title: Text(u.key),
                        value: u.value,
                      ),
                    ),
                  if (widget.archs != null) const SizedBox(height: 16),
                  if (widget.archs != null)
                    Text(
                      widget.archs!.length == 1
                          ? tr('deviceSupportsXArch', args: [widget.archs![0]])
                          : tr('deviceSupportsFollowingArchs') +
                                list2FriendlyString(
                                  widget.archs!.map((e) => '\'$e\'').toList(),
                                ),
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(null);
          },
          child: Text(tr('cancel')),
        ),
        FilledButton(
          autofocus: isTV && urlsToSelectFrom.isEmpty,
          onPressed: fileUrl != null
              ? () {
                  context.read<SettingsProvider>().selectionClick();
                  Navigator.of(context).pop(fileUrl);
                }
              : null,
          child: Text(tr('continue')),
        ),
      ],
    );
  }
}

class APKOriginWarningDialog extends StatefulWidget {
  const APKOriginWarningDialog({
    super.key,
    required this.sourceUrl,
    required this.apkUrl,
  });

  final String sourceUrl;
  final String apkUrl;

  @override
  State<APKOriginWarningDialog> createState() => _APKOriginWarningDialogState();
}

class _APKOriginWarningDialogState extends State<APKOriginWarningDialog> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final isTV = context.read<SettingsProvider>().isTV;
    return AlertDialog(
      scrollable: true,
      title: Text(tr('warning')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'sourceIsXButPackageFromYPrompt',
              args: [
                Uri.parse(widget.sourceUrl).host,
                Uri.parse(widget.apkUrl).host,
              ],
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            autofocus: isTV,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _dontShowAgain,
            onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
            title: Text(tr('dontShowAgain')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(null);
          },
          child: Text(tr('cancel')),
        ),
        FilledButton(
          autofocus: !isTV,
          onPressed: () {
            final sp = context.read<SettingsProvider>();
            sp.selectionClick();
            if (_dontShowAgain) {
              sp.hideAPKOriginWarning = true;
            }
            Navigator.of(context).pop(true);
          },
          child: Text(tr('continue')),
        ),
      ],
    );
  }
}
