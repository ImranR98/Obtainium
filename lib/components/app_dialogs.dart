import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';

/// Lets the user pick which APK/asset URL to use when an app exposes more than
/// one. Returns the selected `MapEntry<name, url>` (or null if cancelled).
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
    fileUrl ??= widget.initVal;
    var urlsToSelectFrom = widget.app.apkUrls;
    if (widget.pickAnyAsset) {
      urlsToSelectFrom = [...urlsToSelectFrom, ...widget.app.otherAssetUrls];
    }
    return AlertDialog(
      scrollable: true,
      title: Text(
        widget.pickAnyAsset
            ? tr('selectX', args: [lowerCaseIfEnglish(tr('releaseAsset'))])
            : tr('pickAnAPK'),
      ),
      content: RadioGroup<String>(
        groupValue: fileUrl!.value,
        onChanged: (String? val) {
          setState(() {
            fileUrl = urlsToSelectFrom.where((e) => e.value == val).first;
          });
        },
        child: Column(
          children: [
            urlsToSelectFrom.length > 1
                ? Text(
                    tr('appHasMoreThanOnePackage', args: [widget.app.finalName]),
                  )
                : const SizedBox.shrink(),
            const SizedBox(height: 16),
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
          onPressed: () {
            context.read<SettingsProvider>().selectionClick();
            Navigator.of(context).pop(fileUrl);
          },
          child: Text(tr('continue')),
        ),
      ],
    );
  }
}

/// Warns the user when an APK's host differs from the app's source host.
/// Returns true if the user chooses to continue.
class APKOriginWarningDialog extends StatefulWidget {
  const APKOriginWarningDialog({
    super.key,
    required this.sourceUrl,
    required this.apkUrl,
  });

  final String sourceUrl;
  final String apkUrl;

  @override
  State<APKOriginWarningDialog> createState() =>
      _APKOriginWarningDialogState();
}

class _APKOriginWarningDialogState extends State<APKOriginWarningDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(tr('warning')),
      content: Text(
        tr(
          'sourceIsXButPackageFromYPrompt',
          args: [
            Uri.parse(widget.sourceUrl).host,
            Uri.parse(widget.apkUrl).host,
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
          onPressed: () {
            context.read<SettingsProvider>().selectionClick();
            Navigator.of(context).pop(true);
          },
          child: Text(tr('continue')),
        ),
      ],
    );
  }
}
