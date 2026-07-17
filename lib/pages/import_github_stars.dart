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
    builder: (_) => _ImportGitHubStarsSheet(
      onImportCompleted: onImportCompleted,
    ),
  );
}

class _ImportGitHubStarsSheet extends StatefulWidget {
  const _ImportGitHubStarsSheet({this.onImportCompleted});

  final Future<void> Function()? onImportCompleted;

  @override
  State<_ImportGitHubStarsSheet> createState() =>
      _ImportGitHubStarsSheetState();
}

class _ImportGitHubStarsSheetState extends State<_ImportGitHubStarsSheet> {
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
      final NavigatorState navigator = Navigator.of(context);
      final Route<dynamic>? usernameSheetRoute = ModalRoute.of(context);
      await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: false,
        builder: (_) => SelectionModal(
          entries: repositories,
          title: tr('selectAppsToImport'),
          presentAsBottomSheet: true,
          onSubmitSelection:
              (List<String> selectedUrls, VoidCallback stopLoading) async {
            try {
              final List<List<String>> errors = await context
                  .read<AppsProvider>()
                  .addAppsByURL(selectedUrls);
              if (!mounted) return false;
              stopLoading();
              await WidgetsBinding.instance.endOfFrame;
              if (!mounted) return false;
              if (errors.isEmpty) {
                showMessage(
                  tr(
                    'importedX',
                    args: [
                      plural('apps', selectedUrls.length).toLowerCase(),
                    ],
                  ),
                  context,
                );
              } else {
                await showDialog<void>(
                  context: context,
                  builder: (_) => ImportErrorDialog(
                    urlsLength: selectedUrls.length,
                    errors: errors,
                  ),
                );
                if (!mounted) return false;
              }
              final Future<void> Function()? onImportCompleted =
                  widget.onImportCompleted;
              if (onImportCompleted != null) {
                await onImportCompleted();
              }
              if (usernameSheetRoute != null &&
                  usernameSheetRoute.isActive) {
                navigator.removeRoute(usernameSheetRoute);
              }
              return true;
            } catch (error) {
              stopLoading();
              await WidgetsBinding.instance.endOfFrame;
              if (mounted) showError(error, context);
            }
            return false;
          },
        ),
      );
    } catch (error) {
      if (mounted) showError(error, context);
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
    return AppSheetContent(
      children: [
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
        TextField(
          controller: _usernameController,
          autofocus: true,
          enabled: !_isLoading,
          textInputAction: TextInputAction.search,
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
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () => Navigator.of(context).pop(),
              child: Text(tr('cancel')),
            ),
            FilledButton.icon(
              onPressed: _isLoading ? null : _importStarredRepositories,
              icon: _isLoading
                  ? const ExpressiveLoadingIndicator(
                      constraints: BoxConstraints.tightFor(
                        width: 24,
                        height: 24,
                      ),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(tr('import')),
            ),
          ],
        ),
      ],
    );
  }
}
