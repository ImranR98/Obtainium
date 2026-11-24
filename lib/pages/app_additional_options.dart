import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/components/github_actions_picker.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/utils/nav_helper.dart';
import 'package:provider/provider.dart';

/// Opens the additional-options page for an app, optionally scrolled to the
/// section with the given [GeneratedFormHeader.id], and applies the changes.
Future<void> showAppAdditionalOptions(
  BuildContext context,
  String appId, {
  String? scrollToSection,
}) async {
  final appsProvider = context.read<AppsProvider>();
  final app = appsProvider.apps[appId];
  if (app == null) return;
  AppSource? source;
  try {
    source = SourceProvider().getSource(
      app.app.url,
      overrideSource: app.app.overrideSource,
    );
  } catch (_) {
    source = null;
  }
  final values = await showAdditionalOptionsPage(
    context,
    source,
    app,
    scrollToSection: scrollToSection,
  );
  if (values == null || !context.mounted) return;
  await applyAdditionalOptionChanges(context, source, app, values);
}

Future<Map<String, dynamic>?> showAdditionalOptionsPage(
  BuildContext context,
  AppSource? source,
  AppInMemory? app, {
  String? scrollToSection,
}) {
  final items =
      <List<GeneratedFormItem>>[
        ...(source?.combinedAppSpecificSettingFormItems ?? []),
      ].map((row) {
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
      traversalEdgeBehavior: traversalEdgeBehaviorFor(context),
      builder: (ctx) => PopScope<Map<String, dynamic>>(
        // Leaving the page saves the settings, so there is no Continue button.
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          // While a text field is being edited, the first BACK only dismisses
          // the keyboard; it must not also save and leave.
          if (isEditingTextField()) {
            FocusManager.instance.primaryFocus?.unfocus();
            return;
          }
          Navigator.of(ctx).pop(values);
        },
        child: _AdditionalOptionsPage(
          title: tr('additionalOptions'),
          source: source,
          url: app?.app.url,
          initialSettings: app?.app.additionalSettings ?? const {},
          items: items,
          scrollToSection: scrollToSection,
          onValuesChanged: (v) => values = v,
        ),
      ),
    ),
  );
}

Future<void> applyAdditionalOptionChanges(
  BuildContext context,
  AppSource? source,
  AppInMemory app,
  Map<String, dynamic> values, {
  ValueChanged<bool>? onBusyChanged,
}) async {
  final appsProvider = context.read<AppsProvider>();
  final Map<String, dynamic> originalSettings = app.app.additionalSettings;
  final savedValues = Map<String, dynamic>.from(values);
  // The additional-options form does not include every stored setting
  // (e.g. the add-time package ID field and source-config overrides such as
  // credentials), so carry those over instead of dropping them.
  originalSettings.forEach((key, value) {
    savedValues.putIfAbsent(key, () => value);
  });
  app.app = app.app.copyWith(additionalSettings: savedValues);
  if (source?.enforceTrackOnly == true) {
    app.app = app.app.copyWith(
      additionalSettings: Map<String, dynamic>.from(app.app.additionalSettings)
        ..['trackOnly'] = true,
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
      final bool isUpdated = app.app.installedVersion == app.app.latestVersion;
      app.app = app.app.copyWith(
        latestVersion: app.app.releaseDate!.microsecondsSinceEpoch.toString(),
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
      additionalSettings: Map<String, dynamic>.from(app.app.additionalSettings)
        ..['versionDetection'] = true
        ..['releaseDateAsVersion'] = false,
    );
  }
  await appsProvider.saveApps([app.app]);
  if (!context.mounted) return;
  await refreshAppMetadata(
    context,
    appId: app.app.id,
    resetVersion: versionDetectionEnabled,
    onBusyChanged: onBusyChanged,
  );
}

/// Re-fetches an app's metadata, optionally resetting its version-detection
/// state, and reports transient busy state through [onBusyChanged].
Future<void> refreshAppMetadata(
  BuildContext context, {
  required String appId,
  bool resetVersion = false,
  ValueChanged<bool>? onBusyChanged,
}) async {
  final appsProvider = context.read<AppsProvider>();
  onBusyChanged?.call(true);
  try {
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
    onBusyChanged?.call(false);
  }
}

class _AdditionalOptionsPage extends StatefulWidget {
  const _AdditionalOptionsPage({
    required this.title,
    required this.items,
    required this.source,
    required this.url,
    required this.initialSettings,
    required this.onValuesChanged,
    this.scrollToSection,
  });

  final String title;
  final AppSource? source;
  final String? url;
  final Map<String, dynamic> initialSettings;
  final List<List<GeneratedFormItem>> items;
  final ValueChanged<Map<String, dynamic>> onValuesChanged;
  final String? scrollToSection;

  @override
  State<_AdditionalOptionsPage> createState() => _AdditionalOptionsPageState();
}

class _AdditionalOptionsPageState extends State<_AdditionalOptionsPage> {
  Map<String, dynamic> _currentValues = {};
  int _formGeneration = 0;
  @override
  void initState() {
    super.initState();
    _currentValues = {
      ...getDefaultValuesFromFormItems(widget.items),
      ...widget.initialSettings,
    };
    final target = widget.scrollToSection;
    if (target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(target));
    }
  }

  Future<void> _scrollTo(String sectionId) async {
    BuildContext? targetContext;
    for (var attempt = 0; attempt < 4; attempt++) {
      targetContext = GlobalObjectKey(sectionId).currentContext;
      if (targetContext != null) break;
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
    }
    if (targetContext == null || !targetContext.mounted) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          CustomAppBar(title: widget.title),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                MediaQuery.of(context).padding.bottom,
              ),
              child: TvInitialFocus(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.source is GitHub &&
                        !(widget.source! as GitHub).hostChanged &&
                        widget.url != null &&
                        _currentValues['githubActionsEnabled'] == true) ...[
                      const SizedBox(height: 12),
                      GitHubActionsPickerButton(
                        source: widget.source! as GitHub,
                        url: widget.url!,
                        settings: _currentValues,
                        onSelected: (selection) {
                          setState(() {
                            _currentValues.addAll(selection);
                            _formGeneration++;
                          });
                          widget.onValuesChanged(_currentValues);
                        },
                      ),
                    ],
                    GeneratedForm(
                      key: ValueKey(_formGeneration),
                      tileMode: true,
                      items: GitHub.visibleActionsFormItems(
                          widget.items, widget.source, _currentValues)
                          .map((row) => row.map((item) {
                        final cloned = item.clone();
                        if (_currentValues.containsKey(cloned.key)) {
                          cloned.value = _currentValues[cloned.key];
                        }
                        return cloned;
                      }).toList()).toList(),
                      onValueChanges: (v, valid, isBuilding) {
                        final wasEnabled = GitHub.actionsEnabledFor(
                            widget.source, _currentValues);
                        final merged = GitHub.mergeActionsFormValues(
                            widget.source, _currentValues, v);
                        _currentValues = merged;
                        widget.onValuesChanged(_currentValues);
                        if (wasEnabled != GitHub.actionsEnabledFor(
                            widget.source, _currentValues)) {
                          setState(() => _formGeneration++);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
