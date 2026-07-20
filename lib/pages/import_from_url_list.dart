import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/pages/import_export.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/theme/app_theme_accent.dart';
import 'package:provider/provider.dart';

/// Obtainium-style URL-list import page, kept as a dedicated route from Add App.
class ImportFromUrlListPage extends StatefulWidget {
  const ImportFromUrlListPage({
    super.key,
    this.embedded = false,
    this.onImportCompleted,
  });

  final bool embedded;
  final Future<void> Function()? onImportCompleted;

  @override
  State<ImportFromUrlListPage> createState() => _ImportFromUrlListPageState();
}

class _ImportFromUrlListPageState extends State<ImportFromUrlListPage> {
  final SourceProvider _sourceProvider = SourceProvider();
  final TextEditingController _urlController = TextEditingController();
  bool _isImporting = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String? _validateUrls(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final List<String> lines = value.trim().split('\n');
    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      try {
        _sourceProvider.getSource(lines[lineIndex]);
      } catch (error) {
        return '${tr('line')} ${lineIndex + 1}: $error';
      }
    }
    return null;
  }

  List<String> _urls() => _urlController.text
      .trim()
      .split('\n')
      .where((String line) => line.isNotEmpty)
      .toList();

  Future<void> _importFromFile() async {
    try {
      final FilePickerResult? result = await FilePicker.pickFiles();
      if (result == null || result.files.isEmpty) return;
      final String? path = result.files.single.path;
      if (path == null) return;
      final String fileContents = await File(path).readAsString();
      final String urls = RegExp(r'https?://[^\s"]+')
          .allMatches(fileContents)
          .map((RegExpMatch match) => match.group(0)!)
          .toSet()
          .where((String url) {
            try {
              _sourceProvider.getSource(url);
              return true;
            } catch (_) {
              return false;
            }
          })
          .join('\n');
      if (!mounted) return;
      setState(() {
        _urlController.text = urls;
      });
    } catch (error) {
      if (!mounted) return;
      showError(error);
    }
  }

  Future<void> _import() async {
    final List<String> urls = _urls();
    if (urls.isEmpty || _validateUrls(_urlController.text) != null) return;
    final AppsProvider appsProvider = context.read<AppsProvider>();
    final bool embedded = widget.embedded;
    final Future<void> Function()? onImportCompleted = widget.onImportCompleted;
    final NavigatorState navigator = Navigator.of(context);
    final ModalRoute<dynamic>? hostRoute = ModalRoute.of(context);
    setState(() {
      _isImporting = true;
    });
    try {
      final List<List<String>> errors = await appsProvider.addAppsByURL(urls);
      if (errors.isEmpty) {
        showMessage(
          tr('importedX', args: [plural('apps', urls.length).toLowerCase()]),
        );
        if (embedded) {
          await onImportCompleted?.call();
        } else if (navigator.mounted && hostRoute?.isCurrent == true) {
          navigator.pop();
        }
      } else {
        if (navigator.mounted) {
          unawaited(
            showDialog<void>(
              context: navigator.context,
              builder: (_) =>
                  ImportErrorDialog(urlsLength: urls.length, errors: errors),
            ),
          );
        }
      }
    } catch (error) {
      showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool useGradientBackground = context.select<SettingsProvider, bool>(
      (settingsProvider) => settingsProvider.useGradientBackground,
    );
    final double topContentInset = !widget.embedded && useGradientBackground
        ? MediaQuery.paddingOf(context).top + kToolbarHeight
        : 0;

    return Scaffold(
      extendBodyBehindAppBar: !widget.embedded && useGradientBackground,
      backgroundColor: widget.embedded && useGradientBackground
          ? Colors.transparent
          : colorScheme.surface,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(tr('importFromURLList')),
              backgroundColor: useGradientBackground
                  ? Colors.transparent
                  : colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              forceMaterialTransparency: useGradientBackground,
            ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (useGradientBackground)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: colorScheme.schemePageBackgroundGradient,
              ),
            ),
          Padding(
            padding: EdgeInsets.only(top: topContentInset),
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverSafeArea(
                  top: widget.embedded,
                  sliver: SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: 16,
                            children: [
                              TextFormField(
                                controller: _urlController,
                                maxLines: null,
                                minLines: 8,
                                enabled: !_isImporting,
                                decoration: InputDecoration(
                                  labelText: tr('appURLList'),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                                validator: _validateUrls,
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                              ),
                              OutlinedButton.icon(
                                onPressed: _isImporting
                                    ? null
                                    : _importFromFile,
                                icon: const Icon(Icons.upload_file_rounded),
                                label: Text(tr('importFromURLsInFile')),
                              ),
                              FilledButton(
                                onPressed: _isImporting ? null : _import,
                                child: _isImporting
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        spacing: 8,
                                        children: [
                                          const ExpressiveLoadingIndicator(
                                            constraints:
                                                BoxConstraints.tightFor(
                                                  width: 24,
                                                  height: 24,
                                                ),
                                          ),
                                          Text(tr('import')),
                                        ],
                                      )
                                    : Text(tr('import')),
                              ),
                              Card.filled(
                                margin: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    tr('importedAppsIdDisclaimer'),
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(fontStyle: FontStyle.italic),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
