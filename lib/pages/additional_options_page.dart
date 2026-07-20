import 'package:easy_localization/easy_localization.dart';
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/components/version_regex_assist_dialog.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/theme/app_dialog_theme.dart';
import 'package:obtainium/theme/app_page_icon_colors.dart';
import 'package:obtainium/theme/app_theme_accent.dart';
import 'package:provider/provider.dart';

import 'page_route_slide_up.dart';

enum _AdditionalOptionsUnsavedAction { keepEditing, discard, saveAndExit }

/// Prefer [slideUpPageRoute]; kept for call sites that still use this name.
PageRouteBuilder<T> additionalOptionsPageRoute<T>(WidgetBuilder builder) =>
    slideUpPageRoute<T>(builder);

/// Merges [formValues] into the app, applies version/release-date rules, saves.
/// Returns whether version detection was newly enabled (for follow-up refresh).
Future<bool> persistAdditionalOptionsForm({
  required AppsProvider appsProvider,
  required SettingsProvider settingsProvider,
  required String appId,
  required Map<String, dynamic> formValues,
}) async {
  final AppInMemory? appInMem = appsProvider.apps[appId];
  if (appInMem == null) return false;
  // App is immutable; work on a fresh copy and reassign via copyWith. The
  // copied additionalSettings map is safe to mutate in place below.
  App app = appInMem.app.copyWith();
  final AppSource source = SourceProvider().getSource(
    app.url,
    overrideSource: app.overrideSource,
  );
  final Map<String, dynamic> originalSettings = Map<String, dynamic>.from(
    app.additionalSettings,
  );
  syncVersionStringSourceSettings(originalSettings);
  if (originalSettings['versionDetection'] == 'versionCode' ||
      originalSettings['useVersionCodeAsOSVersion'] == true) {
    originalSettings['versionDetection'] = 'versionCode';
    originalSettings['useVersionCodeAsOSVersion'] = true;
  } else {
    originalSettings['useVersionCodeAsOSVersion'] = false;
  }
  app = app.copyWith(additionalSettings: {...originalSettings, ...formValues});
  syncVersionStringSourceSettings(app.additionalSettings);
  app.additionalSettings['useVersionCodeAsOSVersion'] =
      app.additionalSettings['versionDetection'] == 'versionCode';
  if (source is GitHub) {
    if (!source.canVerifyAttestations(
      app.additionalSettings,
      settingsProvider,
    )) {
      app.additionalSettings[GitHub.buildVerificationModeKey] =
          GitHub.buildVerificationOff;
    }
    app.additionalSettings[GitHub.enforceAttestationsKey] = false;
  }

  if (source.enforceTrackOnly) {
    app.additionalSettings['trackOnly'] = true;
    showMessage(tr('appsFromSourceAreTrackOnly'));
  }

  final bool versionDetectionPreviouslyActive =
      originalSettings['versionDetection'] == 'auto' ||
      originalSettings['versionDetection'] == 'standard' ||
      originalSettings['versionDetection'] == 'versionCode' ||
      originalSettings['versionDetection'] == true ||
      originalSettings['versionDetection'] == null;
  final bool versionDetectionCurrentlyActive =
      app.additionalSettings['versionDetection'] == 'auto' ||
      app.additionalSettings['versionDetection'] == 'standard' ||
      app.additionalSettings['versionDetection'] == 'versionCode' ||
      app.additionalSettings['versionDetection'] == true ||
      app.additionalSettings['versionDetection'] == null;

  final bool versionDetectionEnabled =
      versionDetectionCurrentlyActive && !versionDetectionPreviouslyActive;
  final bool versionDetectionDisabled =
      !versionDetectionCurrentlyActive && versionDetectionPreviouslyActive;

  final bool releaseDateVersionEnabled =
      app.additionalSettings['releaseDateAsVersion'] == true &&
      originalSettings['releaseDateAsVersion'] != true;
  final bool releaseDateVersionDisabled =
      app.additionalSettings['releaseDateAsVersion'] != true &&
      originalSettings['releaseDateAsVersion'] == true;

  if (releaseDateVersionEnabled && app.releaseDate != null) {
    final bool isUpdated =
        app.installedVersion == app.latestVersion ||
        (app.installedVersion != null &&
            versionsEffectivelyEqual(app.installedVersion!, app.latestVersion));
    app = app.copyWith(
      latestVersion: app.releaseDate!.toUtc().toIso8601String(),
    );
    if (isUpdated) app = app.copyWith(installedVersion: app.latestVersion);
  } else if (releaseDateVersionDisabled) {
    app = app.copyWith(
      installedVersion:
          appInMem.installedInfo?.versionName ?? app.installedVersion,
    );
  }

  if (versionDetectionEnabled) {
    if (app.additionalSettings['versionDetection'] != 'auto' &&
        app.additionalSettings['versionDetection'] != 'standard' &&
        app.additionalSettings['versionDetection'] != 'versionCode') {
      app.additionalSettings['versionDetection'] = 'auto';
    }
    if (app.additionalSettings['releaseDateAsVersion'] == true) {
      app.additionalSettings['versionStringSource'] =
          versionStringSourceDefault;
      syncVersionStringSourceSettings(app.additionalSettings);
    }
  } else if (versionDetectionDisabled && app.installedVersion != null) {
    final String? realInstalledVersion =
        app.additionalSettings['useVersionCodeAsOSVersion'] == true
        ? appInMem.installedInfo?.versionCode.toString()
        : appInMem.installedInfo?.versionName;
    if (realInstalledVersion != null) {
      if (reconcileVersionDifferences(
            realInstalledVersion,
            app.latestVersion,
          )?.key !=
          true) {
        app = app.copyWith(installedVersion: app.latestVersion);
      }
    }
  }

  bool versionSettingsChanged = versionDetectionEnabled;
  if (versionDetectionCurrentlyActive) {
    final List<String> versionKeys = [
      'useVersionCodeAsOSVersion',
      'versionStringSource',
      'versionExtractionRegEx',
      'matchGroupToUse',
      'releaseCommitShaAsVersion',
    ];
    for (final String key in versionKeys) {
      if (originalSettings[key] != app.additionalSettings[key]) {
        versionSettingsChanged = true;
        app = app.copyWith(installedVersion: null);
        break;
      }
    }
  }

  await appsProvider.saveApps([app], updateInstalledInfo: false);
  return versionSettingsChanged;
}

/// Full-screen editor for per-app additional options (keyboard-friendly).
class AdditionalOptionsPage extends StatefulWidget {
  const AdditionalOptionsPage({super.key, required this.appId});

  final String appId;

  @override
  State<AdditionalOptionsPage> createState() => _AdditionalOptionsPageState();
}

class _AdditionalOptionsPageState extends State<AdditionalOptionsPage> {
  late List<List<GeneratedFormItem>> _items;
  Map<String, dynamic> _values = {};
  Map<String, dynamic> _baselineValues = {};
  bool _baselineReady = false;
  bool _valid = false;
  bool _saving = false;

  ColorScheme? _iconDerivedColorScheme;
  String? _iconSchemeCacheKey;
  String? _iconSchemeLoadingForKey;
  String? _iconSchemeFailedCacheKey;
  ThemeData? _cachedPageTheme;
  String? _cachedPageThemeKey;
  bool _requestedMissingIconLoad = false;

  @override
  void initState() {
    super.initState();
    final AppsProvider appsProvider = context.read<AppsProvider>();
    final AppInMemory? appInMem = appsProvider.apps[widget.appId];
    if (appInMem == null) {
      _items = [];
      _valid = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    final App app = appInMem.app;
    final Map<String, dynamic> appAdditionalSettings =
        Map<String, dynamic>.from(app.additionalSettings);
    syncVersionStringSourceSettings(appAdditionalSettings);
    // Defensively normalize versionDetection to the string enum the dropdown
    // expects. App.fromJson normally migrates legacy bool values, but it falls
    // back to raw JSON if that migration throws — a bool here would crash the
    // DropdownButton ("no item with value: false"). false→pseudo / true→auto
    // preserves the app's actual behavior; anything unrecognized → auto.
    final dynamic vd = appAdditionalSettings['versionDetection'];
    if (vd == false) {
      appAdditionalSettings['versionDetection'] = 'pseudo';
    } else if (vd == true) {
      appAdditionalSettings['versionDetection'] = 'auto';
    } else if (vd != 'auto' &&
        vd != 'standard' &&
        vd != 'pseudo' &&
        vd != 'versionCode') {
      appAdditionalSettings['versionDetection'] = 'auto';
    }
    if (appAdditionalSettings['versionDetection'] == 'versionCode' ||
        appAdditionalSettings['useVersionCodeAsOSVersion'] == true) {
      appAdditionalSettings['versionDetection'] = 'versionCode';
      appAdditionalSettings['useVersionCodeAsOSVersion'] = true;
    } else {
      appAdditionalSettings['useVersionCodeAsOSVersion'] = false;
    }
    final SettingsProvider settingsProvider = context.read<SettingsProvider>();
    final AppSource source = SourceProvider().getSource(
      app.url,
      overrideSource: app.overrideSource,
    );
    _items = cloneFormItems(source.combinedAppSpecificSettingFormItems);
    for (final List<GeneratedFormItem> row in _items) {
      for (final GeneratedFormItem element in row) {
        if (appAdditionalSettings[element.key] != null) {
          final dynamic stored = appAdditionalSettings[element.key];
          // For a dropdown, never assign a stored value that isn't one of the
          // current options — DropdownButton asserts ("no item with value X")
          // and crashes the page. This happens when the source's offered
          // options change (e.g. versionStringSource after an overrideSource /
          // URL edit, or a legacy value). Keep the item's default instead.
          if (element is GeneratedFormDropdown &&
              element.opts?.any((o) => o.key == stored.toString()) != true) {
            // leave element.value at its constructor default
          } else {
            element.value = stored;
          }
        }
        if (source is GitHub &&
            element is GeneratedFormDropdown &&
            element.key == GitHub.buildVerificationModeKey) {
          final bool canVerifyGitHubBuild = source.canVerifyAttestations(
            appAdditionalSettings,
            settingsProvider,
          );
          if (!canVerifyGitHubBuild) {
            element.disabledOptKeys = [
              GitHub.buildVerificationAudit,
              GitHub.buildVerificationEnforce,
            ];
            element.value = GitHub.buildVerificationOff;
          } else if (appAdditionalSettings[GitHub.buildVerificationModeKey] ==
                  null &&
              appAdditionalSettings[GitHub.enforceAttestationsKey] == true) {
            element.value = GitHub.buildVerificationEnforce;
          }
        }
      }
    }
    _baselineValues = Map<String, dynamic>.from(
      getDefaultValuesFromFormItems(_items),
    );
    _baselineReady = _items.isNotEmpty;
    attachRegexAssistToItems(
      _items,
      rawLatestVersionFromSource: app.rawLatestVersionFromSource,
      rawApkNamesFromSource: app.rawApkNamesFromSource,
      rawReleaseTitlesFromSource: app.rawReleaseTitlesFromSource,
      resolveRawLatestVersionFromValues:
          (Map<String, dynamic> currentValues) async {
            final Map<String, dynamic> settings = <String, dynamic>{
              ...appAdditionalSettings,
              ...currentValues,
            };
            syncVersionStringSourceSettings(settings);
            settings['versionExtractionRegEx'] = '';
            settings['matchGroupToUse'] = '';
            try {
              final App resolvedApp = await SourceProvider().getApp(
                source,
                app.url,
                settings,
                currentApp: app,
              );
              return resolvedApp.rawLatestVersionFromSource;
            } catch (_) {
              return null;
            }
          },
    );
    _valid = _items.isEmpty;
  }

  void _startIconSchemeLoadIfNeeded(Uint8List iconBytes, String cacheKey) {
    if (!mounted) return;
    if (_iconSchemeCacheKey == cacheKey) return;
    if (_iconSchemeLoadingForKey == cacheKey) return;
    _iconSchemeLoadingForKey = cacheKey;
    _extractColorSchemeFromIcon(iconBytes, cacheKey);
  }

  Future<void> _extractColorSchemeFromIcon(
    Uint8List iconBytes,
    String cacheKey,
  ) async {
    if (!context.mounted) return;
    final Brightness brightness = Theme.of(context).brightness;
    final AppsProvider apps = context.read<AppsProvider>();
    final SettingsProvider settings = context.read<SettingsProvider>();
    final ColorScheme? scheme = await loadColorSchemeFromAppIcon(
      iconBytes: iconBytes,
      brightness: brightness,
    );
    if (!mounted) return;
    if (!identical(apps.apps[widget.appId]?.icon, iconBytes)) return;
    if (!settings.matchAppPageToIconColors) return;
    if (scheme != null) {
      setState(() {
        if (_iconSchemeLoadingForKey == cacheKey) {
          _iconDerivedColorScheme = scheme;
          _iconSchemeCacheKey = cacheKey;
          _iconSchemeLoadingForKey = null;
          _iconSchemeFailedCacheKey = null;
        }
      });
    } else {
      setState(() {
        if (_iconSchemeLoadingForKey == cacheKey) {
          _iconSchemeLoadingForKey = null;
          _iconSchemeFailedCacheKey = cacheKey;
        }
      });
    }
  }

  Future<void> _onSave() async {
    if (!_valid || _saving || !_isDirty()) return;
    setState(() {
      _saving = true;
    });
    try {
      final AppsProvider appsProvider = context.read<AppsProvider>();
      final SettingsProvider settingsProvider = context
          .read<SettingsProvider>();
      final NavigatorState navigator = Navigator.of(context);
      final bool versionDetectionEnabled = await persistAdditionalOptionsForm(
        appsProvider: appsProvider,
        settingsProvider: settingsProvider,
        appId: widget.appId,
        formValues: _values,
      );
      if (!mounted || !navigator.mounted) return;
      navigator.pop(versionDetectionEnabled);
    } catch (err) {
      showError(err);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  bool _formValuesEqual(
    Map<String, dynamic> current,
    Map<String, dynamic> baseline,
  ) {
    if (current.length != baseline.length) {
      return false;
    }
    for (final MapEntry<String, dynamic> entry in current.entries) {
      if (!_formValueEquals(baseline[entry.key], entry.value)) {
        return false;
      }
    }
    return true;
  }

  bool _formValueEquals(dynamic left, dynamic right) {
    if (identical(left, right)) return true;
    if (left is MapEntry && right is MapEntry) {
      return _formValueEquals(left.key, right.key) &&
          _formValueEquals(left.value, right.value);
    }
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final dynamic key in left.keys) {
        if (!right.containsKey(key)) return false;
        if (!_formValueEquals(left[key], right[key])) return false;
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (int index = 0; index < left.length; index++) {
        if (!_formValueEquals(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }

  bool _isDirty() {
    return _baselineReady && !_formValuesEqual(_values, _baselineValues);
  }

  Future<_AdditionalOptionsUnsavedAction?> _showUnsavedChangesDialog(
    BuildContext dialogHostContext,
    ThemeData dialogTheme,
  ) {
    return showDialog<_AdditionalOptionsUnsavedAction>(
      context: dialogHostContext,
      builder: (BuildContext dialogContext) {
        return Theme(
          data: dialogTheme,
          child: AlertDialog(
            title: Text(tr('appEditsUnsavedTitle')),
            contentPadding: appDialogContentPadding,
            content: Text(tr('appEditsUnsavedBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _AdditionalOptionsUnsavedAction.discard,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                child: Text(tr('discard')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _AdditionalOptionsUnsavedAction.keepEditing,
                ),
                child: Text(tr('keepEditing')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _AdditionalOptionsUnsavedAction.saveAndExit,
                ),
                child: Text(tr('saveAndExit')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleLeaveRequest(
    BuildContext actionContext,
    ThemeData pageTheme,
  ) async {
    if (_saving) {
      return;
    }
    if (!_isDirty()) {
      if (mounted) {
        Navigator.of(actionContext).pop();
      }
      return;
    }
    final _AdditionalOptionsUnsavedAction? action =
        await _showUnsavedChangesDialog(actionContext, pageTheme);
    if (!actionContext.mounted) {
      return;
    }
    switch (action) {
      case _AdditionalOptionsUnsavedAction.discard:
        Navigator.of(actionContext).pop();
        break;
      case _AdditionalOptionsUnsavedAction.saveAndExit:
        await _onSave();
        break;
      case _AdditionalOptionsUnsavedAction.keepEditing:
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.select<SettingsProvider, int>(
      (SettingsProvider settings) => Object.hash(
        settings.matchAppPageToIconColors,
        settings.blackThemeActive,
      ),
    );
    context.select<AppsProvider, int>((AppsProvider provider) {
      final AppInMemory? inMemory = provider.apps[widget.appId];
      return Object.hash(
        identityHashCode(inMemory?.icon),
        inMemory?.icon?.length,
      );
    });

    final ThemeData parentTheme = Theme.of(context);
    final Brightness themeBrightness = parentTheme.brightness;
    final AppsProvider appsProvider = context.read<AppsProvider>();
    final SettingsProvider settingsProvider = context.read<SettingsProvider>();
    final AppInMemory? appInMem = appsProvider.apps[widget.appId];

    if (appInMem != null &&
        appInMem.icon == null &&
        !_requestedMissingIconLoad) {
      _requestedMissingIconLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        appsProvider.updateAppIcon(widget.appId, ignoreCache: false);
      });
    }

    final Uint8List? iconBytes = appInMem?.icon;
    final bool useIconPageColors = settingsProvider.matchAppPageToIconColors;

    if (useIconPageColors && iconBytes != null) {
      final String iconSchemeCacheKey =
          '${identityHashCode(iconBytes)}_${themeBrightness.name}';
      final ColorScheme? cachedScheme = getCachedColorScheme(
        iconBytes,
        themeBrightness,
      );
      if (cachedScheme != null) {
        _iconDerivedColorScheme = cachedScheme;
        _iconSchemeCacheKey = iconSchemeCacheKey;
      } else if (_iconSchemeCacheKey != iconSchemeCacheKey &&
          _iconSchemeLoadingForKey != iconSchemeCacheKey &&
          _iconSchemeFailedCacheKey != iconSchemeCacheKey) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startIconSchemeLoadIfNeeded(iconBytes, iconSchemeCacheKey);
        });
      }
    } else {
      if (_iconDerivedColorScheme != null ||
          _iconSchemeCacheKey != null ||
          _iconSchemeLoadingForKey != null ||
          _iconSchemeFailedCacheKey != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _iconDerivedColorScheme = null;
            _iconSchemeCacheKey = null;
            _iconSchemeLoadingForKey = null;
            _iconSchemeFailedCacheKey = null;
          });
        });
      }
    }

    final bool applyIconDerivedPageTheming =
        useIconPageColors && _iconDerivedColorScheme != null;
    final ColorScheme themedPageColorScheme = !applyIconDerivedPageTheming
        ? parentTheme.colorScheme
        : darkenIconPageSchemeInDarkMode(
            appPageSurfacesWithVisibleAccent(_iconDerivedColorScheme!),
          );
    final bool applyBlackPageTheme = settingsProvider.blackThemeActive;
    final ColorScheme pageColorSchemeForPage = applyBlackPageTheme
        ? themedPageColorScheme.withPureBlackBackgrounds()
        : themedPageColorScheme;
    final Brightness pageBrightness = pageColorSchemeForPage.brightness;

    final String pageThemeKey =
        '${_iconSchemeCacheKey ?? "none"}_${themeBrightness.name}_${applyBlackPageTheme ? "black" : "standard"}';
    if (_cachedPageThemeKey != pageThemeKey || _cachedPageTheme == null) {
      _cachedPageThemeKey = pageThemeKey;
      _cachedPageTheme = buildAppPageThemedData(
        parentTheme,
        pageColorSchemeForPage,
      );
    }
    final ThemeData pageThemeForPage = _cachedPageTheme!;

    final Color scaffoldBackground = appPageDeeperSurfaceColor(
      pageColorSchemeForPage.surface,
      pageBrightness,
    );

    if (_items.isEmpty) {
      return Theme(
        data: pageThemeForPage,
        child: Scaffold(
          backgroundColor: scaffoldBackground,
          appBar: AppBar(title: Text(tr('additionalOptions'))),
          body: const Center(child: SizedBox.shrink()),
        ),
      );
    }

    final double fabBottomPadding = MediaQuery.of(context).padding.bottom + 16;
    final bool canSave = _valid && !_saving && _isDirty();
    final ColorScheme colorScheme = pageThemeForPage.colorScheme;
    final Color disabledSaveFabColor =
        Color.lerp(
          colorScheme.surfaceContainerHighest,
          colorScheme.onSurface,
          Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.08,
        ) ??
        colorScheme.surfaceContainerHighest;

    return Theme(
      data: pageThemeForPage,
      child: PopScope(
        canPop: !_saving && !_isDirty(),
        onPopInvokedWithResult: (bool didPop, dynamic result) async {
          if (didPop) {
            return;
          }
          if (_saving) {
            return;
          }
          await _handleLeaveRequest(context, pageThemeForPage);
        },
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: scaffoldBackground,
          floatingActionButton: Padding(
            padding: EdgeInsets.only(bottom: fabBottomPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'additional_options_cancel',
                  tooltip: tr('cancel'),
                  onPressed: _saving
                      ? null
                      : () => _handleLeaveRequest(context, pageThemeForPage),
                  child: const Icon(Icons.close),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'additional_options_save',
                  tooltip: tr('continue'),
                  backgroundColor: canSave ? null : disabledSaveFabColor,
                  foregroundColor: canSave
                      ? null
                      : colorScheme.onSurface.withValues(alpha: 0.48),
                  elevation: canSave ? null : 0,
                  onPressed: canSave ? _onSave : null,
                  child: _saving
                      ? Builder(
                          builder: (indicatorContext) {
                            return ExpressiveLoadingIndicator(
                              color: IconTheme.of(indicatorContext).color,
                              constraints: const BoxConstraints.tightFor(
                                width: 26,
                                height: 26,
                              ),
                            );
                          },
                        )
                      : const Icon(Icons.check),
                ),
              ],
            ),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          body: CustomScrollView(
            scrollCacheExtent: const ScrollCacheExtent.pixels(1600),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              CustomAppBar(
                title: tr('additionalOptions'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, fabBottomPadding + 124),
                sliver: SliverToBoxAdapter(
                  child: GeneratedForm(
                    items: _items,
                    outlinedInputFields: true,
                    prominentSectionHeaders: true,
                    wrapFormSectionsInCards: true,
                    onValueChanges: (values, valid, isBuilding) {
                      if (isBuilding) {
                        _values = values;
                        _valid = valid;
                      } else {
                        setState(() {
                          _values = values;
                          _valid = valid;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
