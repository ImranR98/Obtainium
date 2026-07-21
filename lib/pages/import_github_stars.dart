import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/app_sources/githubstars.dart';
import 'package:obtainium/components/app_bottom_sheet.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/pages/import_export.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:provider/provider.dart';

Future<void> showImportGitHubStarsSheet(
  BuildContext context, {
  Future<void> Function()? onImportCompleted,
}) async {
  await showAppModalSheet<void>(
    context: context,
    builder: (_) =>
        ImportGitHubStarsContent(onImportCompleted: onImportCompleted),
  );
}

class ImportGitHubStarsContent extends StatefulWidget {
  const ImportGitHubStarsContent({
    super.key,
    this.embedded = false,
    this.onImportCompleted,
  });

  final bool embedded;
  final Future<void> Function()? onImportCompleted;

  @override
  State<ImportGitHubStarsContent> createState() =>
      _ImportGitHubStarsContentState();
}

class _ImportGitHubStarsContentState extends State<ImportGitHubStarsContent> {
  final GitHubStars _source = GitHubStars();
  final TextEditingController _usernameController = TextEditingController();
  bool _isLoading = false;
  bool _showUsernameError = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _importStarredRepositories() async {
    final String username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() {
        _showUsernameError = true;
      });
      return;
    }

    final AppsProvider appsProvider = context.read<AppsProvider>();
    final bool embedded = widget.embedded;
    final Future<void> Function()? onImportCompleted = widget.onImportCompleted;
    final NavigatorState navigator = Navigator.of(context);
    final Route<dynamic>? usernameSheetRoute = embedded
        ? null
        : ModalRoute.of(context);
    setState(() {
      _isLoading = true;
      _showUsernameError = false;
    });
    try {
      final Map<String, List<String>> repositories = await _source
          .getUrlsWithDescriptions([username]);
      if (!mounted) return;
      if (repositories.isEmpty) {
        throw ObtainiumError(tr('noResults'));
      }
      setState(() {
        _isLoading = false;
      });
      await showAppModalSheet<List<String>>(
        context: navigator.context,
        builder: (_) => SelectionModal(
          entries: repositories,
          title: tr('selectAppsToImport'),
          presentAsBottomSheet: true,
          onSubmitSelection:
              (List<String> selectedUrls, VoidCallback stopLoading) async {
                try {
                  final List<List<String>> errors = await appsProvider
                      .addAppsByURL(selectedUrls);
                  stopLoading();
                  await WidgetsBinding.instance.endOfFrame;
                  if (errors.isEmpty) {
                    showMessage(
                      tr(
                        'importedX',
                        args: [
                          plural('apps', selectedUrls.length).toLowerCase(),
                        ],
                      ),
                    );
                  } else if (navigator.mounted) {
                    await showDialog<void>(
                      context: navigator.context,
                      builder: (_) => ImportErrorDialog(
                        urlsLength: selectedUrls.length,
                        errors: errors,
                      ),
                    );
                  }
                  if (onImportCompleted != null) {
                    await onImportCompleted();
                  }
                  if (usernameSheetRoute != null &&
                      usernameSheetRoute.isActive &&
                      navigator.mounted) {
                    navigator.removeRoute(usernameSheetRoute);
                  }
                  return true;
                } catch (error) {
                  stopLoading();
                  await WidgetsBinding.instance.endOfFrame;
                  showError(error);
                }
                return false;
              },
        ),
      );
    } catch (error) {
      showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = [
      if (!widget.embedded) ...[
        Row(
          children: [
            const Icon(Icons.star_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tr('importGitHubStarredRepositories'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
      TextField(
        controller: _usernameController,
        autofocus: !widget.embedded,
        enabled: !_isLoading,
        textInputAction: TextInputAction.done,
        onChanged: (_) {
          if (_showUsernameError) {
            setState(() {
              _showUsernameError = false;
            });
          }
        },
        onSubmitted: (_) {
          if (!_isLoading) {
            unawaited(_importStarredRepositories());
          }
        },
        decoration: InputDecoration(
          labelText: tr('uname'),
          errorText: _showUsernameError ? tr('invalidInput') : null,
          prefixIcon: const Icon(Icons.person_rounded),
        ),
      ),
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: 8,
        children: [
          if (!widget.embedded)
            TextButton(
              onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
              child: Text(tr('cancel')),
            ),
          FilledButton.icon(
            onPressed: _isLoading ? null : _importStarredRepositories,
            icon: _isLoading
                ? const ExpressiveLoadingIndicator(
                    constraints: BoxConstraints.tightFor(width: 24, height: 24),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(tr('import')),
          ),
        ],
      ),
    ];

    if (!widget.embedded) {
      return AppSheetContent(children: children);
    }

    return SafeArea(
      top: true,
      bottom: false,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
