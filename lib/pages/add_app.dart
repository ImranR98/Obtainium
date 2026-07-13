import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/layout_breakpoints.dart';
import 'package:obtainium/components/app_page_section_title.dart';
import 'package:obtainium/components/bulk_add_widget.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/components/version_regex_assist_dialog.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/pages/home.dart';
import 'package:obtainium/pages/page_route_slide_up.dart';
import 'package:obtainium/pages/settings.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/store_source_icons.dart';
import 'package:obtainium/theme/app_dialog_theme.dart';
import 'package:obtainium/theme/app_form_field_styles.dart';
import 'package:obtainium/theme/app_page_icon_colors.dart';
import 'package:obtainium/theme/app_segmented_button_theme.dart';
import 'package:obtainium/theme/app_theme_accent.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

const double _appVaultFabBottomGap = 8.0;
const double _fabHorizontalMargin = 16.0;
const double _fabMinimumSafeBottomPadding = 16.0;

enum _AddMode { byUrl, search, fromDevice }

enum _PackageIdDetectionChoice { download, trackOnly }

class AddAppPage extends StatefulWidget {
  const AddAppPage({super.key});

  @override
  State<AddAppPage> createState() => AddAppPageState();
}

class AddAppPageState extends State<AddAppPage> {
  // ─── Mode ──────────────────────────────────────────────────────────────
  _AddMode _mode = _AddMode.byUrl;

  // ─── URL mode state ────────────────────────────────────────────────────
  bool gettingAppInfo = false;
  String userInput = '';
  String? pickedSourceOverride;
  String? previousPickedSourceOverride;
  AppSource? pickedSource;
  Map<String, dynamic> additionalSettings = {};
  bool additionalSettingsValid = true;
  bool inferAppIdIfOptional = true;
  List<String> pickedCategories = [];
  SourceProvider sourceProvider = SourceProvider();
  late final TextEditingController _urlFieldController;

  // ─── Device mode state ────────────────────────────────────────────────
  final GlobalKey<BulkAddWidgetState> _bulkWidgetKey = GlobalKey();

  /// True while the Device tab's bulk-add is actively saving apps.
  /// Used by [HomePageState] to suppress auto-navigation during bulk add.
  bool get isBulkAdding =>
      _mode == _AddMode.fromDevice &&
      (_bulkWidgetKey.currentState?.isAdding ?? false);

  Future<bool> confirmCancelBulkScanForNavigation() async {
    if (_mode == _AddMode.fromDevice) {
      final bool canNavigate =
          await _bulkWidgetKey.currentState?.confirmCancelScanForNavigation(
            context,
          ) ??
          true;
      if (canNavigate) {
        _resetAllInputStates();
      }
      return canNavigate;
    }

    final bool isUrlDirty =
        _mode == _AddMode.byUrl && userInput.trim().isNotEmpty;
    final bool isSearchDirty =
        _mode == _AddMode.search &&
        (searchQuery.trim().isNotEmpty ||
            _searchHasSearched ||
            _searchResults.isNotEmpty);

    if (isUrlDirty || isSearchDirty) {
      final String titleKey = isUrlDirty
          ? 'discardUnsavedChangesQuestion'
          : 'resetSearchQuestion';
      final String explanationKey = isUrlDirty
          ? 'discardUnsavedChangesUrlExplanation'
          : 'discardUnsavedChangesSearchExplanation';

      final bool? discard = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text(tr(titleKey)),
            contentPadding: appDialogContentPadding,
            content: Text(tr(explanationKey)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(tr('cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                child: Text(tr('continue')),
              ),
            ],
          );
        },
      );

      if (discard == true) {
        _resetAllInputStates();
        return true;
      }
      return false;
    }

    return true;
  }

  /// Called by [HomePageState] when the user presses back while this tab is
  /// active. Returns true if the bulk flow consumed the event (moved one step
  /// back). Returns false so the caller falls through to normal tab navigation.
  bool handleBack() {
    if (_mode == _AddMode.fromDevice) {
      return _bulkWidgetKey.currentState?.handleBack() ?? false;
    }
    if (_mode == _AddMode.byUrl && _byUrlOpenedFromSearchPick) {
      setState(() {
        _byUrlOpenedFromSearchPick = false;
        _mode = _AddMode.search;
      });
      return true;
    }
    return false;
  }

  // ─── Search mode state ─────────────────────────────────────────────────
  bool searching = false;
  String searchQuery = '';
  // Cache of past inline-search results. Instance-scoped (so it's discarded
  // when leaving the page, rather than serving stale results across sessions)
  // and size-bounded so it can't grow unbounded. The key includes the selected
  // sources, and searches that prompt for per-source options are never cached
  // (their results depend on that dialog input — see runInlineSearch).
  final Map<String, Map<String, MapEntry<String, List<String>>>> _searchCache =
      {};
  static const int _searchCacheMaxEntries = 50;
  // Searchable-source names the user has selected (null = not yet initialised)
  Set<String>? _searchSelectedStores;
  // Interleaved search results: key=URL/identifier, value=(sourceName, subtitleLines)
  Map<String, MapEntry<String, List<String>>> _searchResults = {};
  bool _searchHasSearched = false;
  String _searchResultFilter = '';
  bool _byUrlOpenedFromSearchPick = false;
  late final TextEditingController _searchSomeSourcesController;
  late final TextEditingController _searchResultFilterController;
  late final FocusNode _searchSomeSourcesFocusNode;

  void linkFn(String input) {
    try {
      if (input.isEmpty) {
        throw UnsupportedURLError();
      }
      sourceProvider.getSource(input);
      if (_mode != _AddMode.byUrl || _byUrlOpenedFromSearchPick) {
        setState(() {
          _mode = _AddMode.byUrl;
          _byUrlOpenedFromSearchPick = false;
        });
      }
      changeUserInput(input, true, false, updateUrlInput: true);
    } catch (e) {
      showError(e, context);
    }
  }

  @override
  void initState() {
    super.initState();
    _urlFieldController = TextEditingController();
    _searchSomeSourcesController = TextEditingController();
    _searchResultFilterController = TextEditingController();
    _searchSomeSourcesFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _urlFieldController.dispose();
    _searchSomeSourcesController.dispose();
    _searchResultFilterController.dispose();
    _searchSomeSourcesFocusNode.dispose();
    super.dispose();
  }

  /// Lazily initialise [_searchSelectedStores] using persisted deselections.
  Set<String> _getSearchSelectedStores(SettingsProvider settingsProvider) {
    if (_searchSelectedStores == null) {
      final deselected = settingsProvider.searchDeselected.toSet();
      _searchSelectedStores = sourceProvider.sources
          .where((e) => e.canSearch && !deselected.contains(e.name))
          .map((e) => e.name)
          .toSet();
    }
    return _searchSelectedStores!;
  }

  bool _isUrlInputValid(String value) {
    if (value.trim().isEmpty) {
      return false;
    }
    try {
      sourceProvider
          .getSource(value, overrideSource: pickedSourceOverride)
          .standardizeUrl(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  void changeUserInput(
    String input,
    bool valid,
    bool isBuilding, {
    bool updateUrlInput = false,
    String? overrideSource,
  }) {
    userInput = input;
    if (!isBuilding) {
      setState(() {
        if (overrideSource != null) {
          pickedSourceOverride = overrideSource;
        }
        final bool overrideChanged =
            pickedSourceOverride != previousPickedSourceOverride;
        previousPickedSourceOverride = pickedSourceOverride;
        if (updateUrlInput) {
          _urlFieldController.text = input;
        }
        final prevHost = pickedSource?.hosts.isNotEmpty == true
            ? pickedSource?.hosts[0]
            : null;
        final source = valid
            ? sourceProvider.getSource(
                userInput,
                overrideSource: pickedSourceOverride,
              )
            : null;
        if (pickedSource.runtimeType != source.runtimeType ||
            overrideChanged ||
            (prevHost != null && prevHost != source?.hosts[0])) {
          pickedSource = source;
          pickedSource?.runOnAddAppInputChange(userInput);
          final dynamic preservedOnDemandOnly =
              additionalSettings['onDemandOnly'];
          additionalSettings = source != null
              ? getDefaultValuesFromFormItems(
                  source.combinedAppSpecificSettingFormItems,
                )
              : {};
          if (preservedOnDemandOnly == true) {
            additionalSettings['onDemandOnly'] = true;
          }
          additionalSettingsValid = source != null
              ? !sourceProvider.ifRequiredAppSpecificSettingsExist(source)
              : true;
          inferAppIdIfOptional = true;
        }
      });
    }
  }

  void _resetUrlModeInput() {
    userInput = '';
    pickedSourceOverride = null;
    previousPickedSourceOverride = null;
    pickedSource = null;
    additionalSettings = {};
    additionalSettingsValid = true;
    inferAppIdIfOptional = true;
    pickedCategories = [];
    _urlFieldController.clear();
  }

  void _resetAllInputStates() {
    setState(() {
      _resetUrlModeInput();
      searching = false;
      searchQuery = '';
      _searchResults = {};
      _searchHasSearched = false;
      _searchResultFilter = '';
      _byUrlOpenedFromSearchPick = false;
      _searchSomeSourcesController.clear();
      _searchResultFilterController.clear();
      _mode = _AddMode.byUrl;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppsProvider appsProvider = context.read<AppsProvider>();
    // Narrow subscription to only the settings this page actually reads
    // in build. The previous broad watch rebuilt the (long, expensive)
    // add-app form on every settings notify, including ones unrelated to
    // this page (categories, sort, swipe actions, etc.).
    context.select<SettingsProvider, int>(
      (s) => Object.hash(
        // [searchDeselected] is a List<String>; hash its contents,
        // because the getter returns a fresh list every call so reference
        // hashing would either always re-trigger or never trigger.
        Object.hashAll(s.searchDeselected),
        s.hideTrackOnlyWarning,
        s.useGradientBackground,
        s.progressiveBlurEnabled,
        s.cardCornerScale,
        s.getSettingString(GitHub.githubCredsKey),
        s.getSettingString(GitHub.validatedPATFingerprintKey),
      ),
    );
    final SettingsProvider settingsProvider = context.read<SettingsProvider>();
    final NotificationsProvider notificationsProvider = context
        .read<NotificationsProvider>();

    final bool doingSomething = gettingAppInfo || searching;
    // The nested Scaffold inherits bottom padding from the home Scaffold when
    // the blurred bottom nav extends underneath it. Place this FAB from the
    // actual screen bottom chrome instead of letting the default endFloat
    // location stack its own 16 dp margin on top of that inherited padding.
    final double coveredBottomInset = MediaQuery.paddingOf(context).bottom;
    final double bottomChromeClearance = settingsProvider.progressiveBlurEnabled
        ? coveredBottomInset
        : 0.0;
    final double appVaultFabBottomPadding =
        (bottomChromeClearance > _fabMinimumSafeBottomPadding
            ? bottomChromeClearance
            : _fabMinimumSafeBottomPadding) +
        _appVaultFabBottomGap;
    final bool urlHasInput =
        _mode == _AddMode.byUrl && userInput.trim().isNotEmpty;
    final bool showAppVaultFab =
        (_mode == _AddMode.byUrl && userInput.trim().isEmpty) ||
        (_mode == _AddMode.search && !_searchHasSearched && !searching);
    final bool showBottomActionFab = showAppVaultFab || urlHasInput;

    // ── Track-only / release-date confirmations (URL mode) ─────────────

    Future<bool> getTrackOnlyConfirmationIfNeeded(
      bool userPickedTrackOnly, {
      bool ignoreHideSetting = false,
    }) async {
      final useTrackOnly =
          userPickedTrackOnly || pickedSource!.enforceTrackOnly;
      if (useTrackOnly &&
          (!settingsProvider.hideTrackOnlyWarning || ignoreHideSetting)) {
        // ignore: use_build_context_synchronously
        final values = await showDialog(
          context: context,
          builder: (BuildContext ctx) {
            return GeneratedFormModal(
              initValid: true,
              title: tr(
                'xIsTrackOnly',
                args: [
                  pickedSource!.enforceTrackOnly ? tr('source') : tr('app'),
                ],
              ),
              items: [
                [GeneratedFormSwitch('hide', label: tr('dontShowAgain'))],
              ],
              message:
                  '${pickedSource!.enforceTrackOnly ? tr('appsFromSourceAreTrackOnly') : tr('youPickedTrackOnly')}\n\n${tr('trackOnlyAppDescription')}',
            );
          },
        );
        if (values != null) {
          settingsProvider.hideTrackOnlyWarning = values['hide'] == true;
        }
        return useTrackOnly && values != null;
      } else {
        return true;
      }
    }

    Future<bool> getReleaseDateAsVersionConfirmationIfNeeded(
      bool userPickedTrackOnly,
    ) async {
      return (!(getVersionStringSource(additionalSettings) ==
              versionStringSourceReleaseDate &&
          // ignore: use_build_context_synchronously
          await showDialog(
                context: context,
                builder: (BuildContext ctx) {
                  return GeneratedFormModal(
                    title: tr('releaseDateAsVersion'),
                    items: const [],
                    message: tr('releaseDateAsVersionExplanation'),
                  );
                },
              ) ==
              null));
    }

    Future<_PackageIdDetectionChoice?>
    getPackageIdDetectionConfirmation() async {
      if (!context.mounted) return null;
      return showDialog<_PackageIdDetectionChoice>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text(tr('downloadAPKToIdentifyAppQuestion')),
            contentPadding: appDialogContentPadding,
            content: Text(tr('downloadAPKToIdentifyAppExplanation')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(tr('cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(_PackageIdDetectionChoice.trackOnly),
                child: Text(tr('trackOnly')),
              ),
              TextButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(_PackageIdDetectionChoice.download),
                child: Text(tr('downloadX', args: [tr('app')])),
              ),
            ],
          );
        },
      );
    }

    // ── Add app (URL mode) ─────────────────────────────────────────────

    Future<void> addApp({bool resetUserInputAfter = false}) async {
      bool appWasAdded = false;
      setState(() {
        gettingAppInfo = true;
      });
      try {
        if (userInput.trim().toLowerCase().startsWith('http://')) {
          bool proceed = false;
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) {
              return AlertDialog(
                title: Text(tr('insecureConnection')),
                contentPadding: appDialogContentPadding,
                content: Text(tr('cleartextWarningExplanation')),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                    child: Text(tr('cancel')),
                  ),
                  TextButton(
                    onPressed: () {
                      proceed = true;
                      Navigator.of(dialogContext).pop();
                    },
                    child: Text(tr('continue')),
                  ),
                ],
              );
            },
          );
          if (!proceed) {
            throw ObtainiumError(tr('cancelled'));
          }
        }
        final userPickedTrackOnly = additionalSettings['trackOnly'] == true;
        App? app;
        if ((await getTrackOnlyConfirmationIfNeeded(userPickedTrackOnly)) &&
            (await getReleaseDateAsVersionConfirmationIfNeeded(
              userPickedTrackOnly,
            ))) {
          if (pickedSource is GitHub) {
            if (!(pickedSource as GitHub).canVerifyAttestations(
              additionalSettings,
              settingsProvider,
            )) {
              additionalSettings[GitHub.buildVerificationModeKey] =
                  GitHub.buildVerificationOff;
            }
            additionalSettings[GitHub.enforceAttestationsKey] = false;
          }
          final trackOnly =
              pickedSource!.enforceTrackOnly || userPickedTrackOnly;
          app = await sourceProvider.getApp(
            pickedSource!,
            userInput.trim(),
            additionalSettings,
            trackOnlyOverride: trackOnly,
            sourceIsOverriden: pickedSourceOverride != null,
            inferAppIdIfOptional: inferAppIdIfOptional,
          );
          // Only download the APK here if you need to for the package ID
          if (isTempId(app) && app.additionalSettings['trackOnly'] != true) {
            final packageIdDetectionChoice =
                await getPackageIdDetectionConfirmation();
            if (packageIdDetectionChoice == null) {
              throw ObtainiumError(tr('cancelled'));
            }
            if (packageIdDetectionChoice ==
                _PackageIdDetectionChoice.trackOnly) {
              app.additionalSettings['trackOnly'] = true;
            } else {
              if (!context.mounted) return;
              final apkUrl = await appsProvider.confirmAppFileUrl(
                app,
                context,
                false,
              );
              if (apkUrl == null) {
                throw ObtainiumError(tr('cancelled'));
              }
              app = app.copyWith(
                preferredApkIndex: app.apkUrls
                    .map((e) => e.value)
                    .toList()
                    .indexOf(apkUrl.value),
              );
              // ignore: use_build_context_synchronously
              final downloadedArtifact = await appsProvider.downloadApp(
                app,
                globalNavigatorKey.currentContext,
                notificationsProvider: notificationsProvider,
              );
              DownloadedApk? downloadedFile;
              DownloadedDir? downloadedDir;
              if (downloadedArtifact is DownloadedApk) {
                downloadedFile = downloadedArtifact;
              } else {
                downloadedDir = downloadedArtifact as DownloadedDir;
              }
              app = app.copyWith(
                id: downloadedFile?.appId ?? downloadedDir!.appId,
              );
            }
          }
          if (appsProvider.apps.containsKey(app.id)) {
            throw ObtainiumError(tr('appAlreadyAdded'));
          }
          app.additionalSettings['useVersionCodeAsOSVersion'] =
              app.additionalSettings['versionDetection'] == 'versionCode';
          if (app.additionalSettings['trackOnly'] == true) {
            app = app.copyWith(installedVersion: null);
            if (isTempId(app)) {
              app.additionalSettings['trackOnlyTemporaryPackageId'] = true;
              app.additionalSettings['trackOnlyUndeterminedInstalledVersion'] =
                  true;
            } else {
              app.additionalSettings['trackOnlyTemporaryPackageId'] = false;
              final installedInfo = await getInstalledInfo(
                app.id,
                printErr: false,
              );
              if (installedInfo != null) {
                app = app.copyWith(
                  installedVersion:
                      app.additionalSettings['useVersionCodeAsOSVersion'] ==
                          true
                      ? installedInfo.versionCode.toString()
                      : installedInfo.versionName,
                );
                app.additionalSettings['trackOnlyUndeterminedInstalledVersion'] =
                    false;
              } else {
                app.additionalSettings['trackOnlyUndeterminedInstalledVersion'] =
                    true;
              }
            }
          } else if (app.additionalSettings['versionDetection'] == 'pseudo' ||
              app.additionalSettings['versionDetection'] == false) {
            app = app.copyWith(installedVersion: app.latestVersion);
          }
          app = app.copyWith(categories: pickedCategories);
          await appsProvider.saveApps([app], onlyIfExists: false);
          final liveApp = appsProvider.apps[app.id]?.app;
          if (liveApp != null) {
            await appsProvider.assignMatchingFoldersToAppIfNeeded(liveApp);
          }
          appWasAdded = true;
        }
        if (app != null) {
          if (!context.mounted) return;
          final double screenWidth = MediaQuery.sizeOf(context).width;
          final bool isLargeScreen = screenWidth >= kLargeScreenWidthBreakpoint;
          final homeState = context.findAncestorStateOfType<HomePageState>();
          if (isLargeScreen && homeState != null) {
            _resetUrlModeInput();
            unawaited(homeState.switchToAppsTabAndOpenApp(app.id));
          } else {
            unawaited(
              Navigator.push(
                globalNavigatorKey.currentContext ?? context,
                heroFriendlyAppPageRoute((_) => AppPage(appId: app!.id)),
              ),
            );
          }
        }
      } catch (e) {
        if (!context.mounted) return;
        showError(e, context);
      } finally {
        if (mounted) {
          setState(() {
            gettingAppInfo = false;
            if (appWasAdded || resetUserInputAfter) {
              _resetUrlModeInput();
            }
          });
        }
      }
    }

    bool urlAddDisabled() =>
        doingSomething ||
        pickedSource == null ||
        (pickedSource!.combinedAppSpecificSettingFormItems.isNotEmpty &&
            !additionalSettingsValid);

    VoidCallback? urlAddAction() {
      if (urlAddDisabled()) return null;
      return () {
        hapticSelection();
        addApp();
      };
    }

    List<List<GeneratedFormItem>> buildAdditionalSettingsItems() {
      final List<List<GeneratedFormItem>> items = cloneFormItems([
        ...pickedSource!.combinedAppSpecificSettingFormItems,
        ...(pickedSourceOverride != null
            ? pickedSource!.sourceConfigSettingFormItems.map((e) => [e])
            : []),
      ]);
      // Pre-check the per-app "Include prereleases" switch for newly-added apps
      // when the global default is on. Only affects defaults at add-time; saved
      // values for existing apps still take precedence in GeneratedForm.
      if (settingsProvider.includePrereleasesByDefault) {
        for (final GeneratedFormItem item in items.expand((row) => row)) {
          if (item is GeneratedFormSwitch && item.key == 'includePrereleases') {
            item.value = true;
          }
        }
      }
      if (pickedSource is GitHub) {
        final bool canVerifyGitHubBuild = (pickedSource as GitHub)
            .canVerifyAttestations(additionalSettings, settingsProvider);
        for (final GeneratedFormItem item in items.expand((row) => row)) {
          if (item is GeneratedFormDropdown &&
              item.key == GitHub.buildVerificationModeKey) {
            if (!canVerifyGitHubBuild) {
              item.disabledOptKeys = [
                GitHub.buildVerificationAudit,
                GitHub.buildVerificationEnforce,
              ];
              item.value = GitHub.buildVerificationOff;
            }
            final String? legacyMode =
                additionalSettings[GitHub.buildVerificationModeKey]?.toString();
            if (legacyMode == null &&
                additionalSettings[GitHub.enforceAttestationsKey] == true &&
                canVerifyGitHubBuild) {
              item.value = GitHub.buildVerificationEnforce;
            }
          }
        }
      }
      return attachRegexAssistToItems(
        items,
        rawLatestVersionFromSource: null,
        rawApkNamesFromSource: null,
        rawReleaseTitlesFromSource: null,
      );
    }

    Widget buildBottomActionFab() {
      if (urlHasInput) {
        return FloatingActionButton.extended(
          key: const ValueKey<String>('add-app-save-fab'),
          heroTag: 'add-app-save-fab',
          onPressed: urlAddAction(),
          icon: gettingAppInfo
              ? ExpressiveLoadingIndicator(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                )
              : const Icon(Icons.save_rounded),
          label: Text(tr('save')),
        );
      }
      return FloatingActionButton.extended(
        key: const ValueKey<String>('add-app-app-vault-fab'),
        heroTag: 'add-app-app-vault-fab',
        onPressed: () {
          launchUrlString(
            'https://apps.obtainium.imranr.dev/',
            mode: LaunchMode.externalApplication,
          );
        },
        icon: const Icon(Icons.apps_rounded),
        label: Text(tr('aboutAppVault')),
      );
    }

    // ── URL mode widgets ───────────────────────────────────────────────

    void showSupportedSourcesDialog() {
      showDialog(
        context: context,
        builder: (context) {
          return GeneratedFormModal(
            singleNullReturnButton: tr('ok'),
            title: tr('supportedSources'),
            items: const [],
            additionalWidgets: [
              ...sourceProvider.sources
                  .where((e) => e.name != 'RockMods')
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: InkWell(
                        onTap: e.hosts.isNotEmpty
                            ? () {
                                launchUrlString(
                                  'https://${e.hosts[0]}',
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            : null,
                        child: Text(
                          '${e.name}${e.enforceTrackOnly ? ' ${tr('trackOnlyInBrackets')}' : ''}${e.canSearch ? ' ${tr('searchableInBrackets')}' : ''}',
                          style: TextStyle(
                            decoration: e.hosts.isNotEmpty
                                ? TextDecoration.underline
                                : TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
              const SizedBox(height: 16),
              Text(
                '${tr('note')}:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(tr('selfHostedNote', args: [tr('overrideSource')])),
            ],
          );
        },
      );
    }

    // Bottom-right action FAB overlay (App Vault / submit), shared by the
    // large-screen and narrow layouts which previously inlined it identically.
    Widget buildBottomActionFabOverlay() {
      return Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _fabHorizontalMargin,
            0,
            _fabHorizontalMargin,
            appVaultFabBottomPadding,
          ),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: showBottomActionFab ? 1 : 0),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubicEmphasized,
            builder: (context, animationValue, child) {
              return IgnorePointer(
                ignoring: !showBottomActionFab,
                child: Opacity(opacity: animationValue, child: child),
              );
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: buildBottomActionFab(),
            ),
          ),
        ),
      );
    }

    Widget getUrlInputRow() {
      final bool showSupportedSourcesButton = userInput.trim().isEmpty;
      final bool addDisabled = urlAddDisabled();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _urlFieldController,
              onChanged: (String text) {
                changeUserInput(text, _isUrlInputValid(text), false);
              },
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) {
                if (!addDisabled) {
                  hapticSelection();
                  addApp();
                }
              },
              decoration:
                  appPageOutlinedInputDecoration(
                    context,
                    labelText: tr('appSourceURL'),
                  ).copyWith(
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                    suffixIcon: TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        end: showSupportedSourcesButton ? 1 : 0,
                      ),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubicEmphasized,
                      builder: (context, animationValue, child) {
                        return SizedBox(
                          width: 48,
                          height: 48,
                          child: Opacity(
                            opacity: animationValue,
                            child: IgnorePointer(
                              ignoring: !showSupportedSourcesButton,
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: IconButton(
                        tooltip: tr('supportedSources'),
                        icon: const Icon(Icons.info_outline_rounded),
                        onPressed: showSupportedSourcesDialog,
                      ),
                    ),
                  ),
            ),
          ),
        ],
      );
    }

    Widget getHTMLSourceOverrideDropdown() => Column(
      children: [
        Row(
          children: [
            Expanded(
              child: GeneratedForm(
                outlinedInputFields: true,
                items: [
                  [
                    GeneratedFormDropdown(
                      'overrideSource',
                      value: pickedSourceOverride ?? '',
                      [
                        MapEntry('', tr('none')),
                        ...sourceProvider.sources
                            .where(
                              (s) =>
                                  s.allowOverride ||
                                  (pickedSource != null &&
                                      pickedSource.runtimeType ==
                                          s.runtimeType),
                            )
                            .map(
                              (s) => MapEntry(s.runtimeType.toString(), s.name),
                            ),
                      ],
                      label: tr('overrideSource'),
                    ),
                  ],
                ],
                onValueChanges: (values, valid, isBuilding) {
                  void fn() {
                    pickedSourceOverride =
                        (values['overrideSource'] == null ||
                            values['overrideSource'] == '')
                        ? null
                        : values['overrideSource'];
                  }

                  if (!isBuilding) {
                    setState(() {
                      fn();
                    });
                  } else {
                    fn();
                  }
                  changeUserInput(userInput, valid, isBuilding);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );

    Widget getAdditionalOptsCol() {
      final ColorScheme colorScheme = Theme.of(context).colorScheme;
      final TextStyle? sectionIntroStyle = Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.primary);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pickedSource != null && pickedSource!.appIdInferIsOptional)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GeneratedForm(
                key: const Key('inferAppIdIfOptional'),
                outlinedInputFields: true,
                prominentSectionHeaders: true,
                wrapFormSectionsInCards: true,
                items: [
                  [
                    GeneratedFormSwitch(
                      'inferAppIdIfOptional',
                      label: tr('tryInferAppIdFromCode'),
                      value: inferAppIdIfOptional,
                    ),
                  ],
                ],
                onValueChanges: (values, valid, isBuilding) {
                  if (!isBuilding) {
                    setState(() {
                      inferAppIdIfOptional = values['inferAppIdIfOptional'];
                    });
                  }
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              tr(
                'additionalOptsFor',
                args: [pickedSource?.name ?? tr('source')],
              ),
              style: sectionIntroStyle,
            ),
          ),
          GeneratedForm(
            key: Key(
              '${pickedSource.runtimeType.toString()}-${pickedSource?.hostChanged.toString()}-${pickedSource?.hostIdenticalDespiteAnyChange.toString()}',
            ),
            outlinedInputFields: true,
            prominentSectionHeaders: true,
            wrapFormSectionsInCards: true,
            items: buildAdditionalSettingsItems(),
            onValueChanges: (values, valid, isBuilding) {
              if (!isBuilding) {
                setState(() {
                  additionalSettings = values;
                  additionalSettingsValid = valid;
                });
              }
            },
          ),
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            decoration: appPageSectionCardDecoration(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: appPageCardSectionHeaderLabel(
                      context,
                      tr('categories'),
                    ),
                  ),
                  CategoryEditorSelector(
                    alignment: WrapAlignment.start,
                    showLabelWhenNotEmpty: false,
                    onSelected: (categories) {
                      pickedCategories = categories;
                    },
                  ),
                ],
              ),
            ),
          ),
          if (pickedSource != null && pickedSource!.enforceTrackOnly)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: GeneratedForm(
                key: Key(
                  '${pickedSource.runtimeType.toString()}-${pickedSource?.hostChanged.toString()}-${pickedSource?.hostIdenticalDespiteAnyChange.toString()}-appId',
                ),
                outlinedInputFields: true,
                prominentSectionHeaders: true,
                wrapFormSectionsInCards: true,
                items: [
                  [
                    GeneratedFormTextField(
                      'appId',
                      label: '${tr('appId')} - ${tr('custom')}',
                      required: false,
                      additionalValidators: [
                        (value) {
                          if (value == null || value.isEmpty) {
                            return null;
                          }
                          final isValid = RegExp(
                            r'^([A-Za-z]{1}[A-Za-z\d_]*\.)+[A-Za-z][A-Za-z\d_]*$',
                          ).hasMatch(value);
                          if (!isValid) {
                            return tr('invalidInput');
                          }
                          return null;
                        },
                      ],
                    ),
                  ],
                ],
                onValueChanges: (values, valid, isBuilding) {
                  if (!isBuilding) {
                    setState(() {
                      additionalSettings['appId'] = values['appId'];
                    });
                  }
                },
              ),
            ),
        ],
      );
    }

    // ── Search mode widgets ────────────────────────────────────────────

    final Set<String> searchSelectedStores = _getSearchSelectedStores(
      settingsProvider,
    );

    // ── Inline search runner ───────────────────────────────────────────

    Future<void> runInlineSearch({
      required AppsProvider appsProvider,
      required SettingsProvider settingsProvider,
    }) async {
      _searchSomeSourcesFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
      _searchResultFilterController.clear();

      final List<AppSource> selectedSources = sourceProvider.sources
          .where((e) => searchSelectedStores.contains(e.name))
          .toList();
      // Results from sources that prompt for per-search options depend on that
      // dialog input, so such searches must not be served from / written to the
      // cache (doing so would skip the prompt and reuse stale option values).
      final bool cacheable = !selectedSources.any(
        (e) => e.includeAdditionalOptsInMainSearch,
      );
      // Key on the query *and* the selected sources, so changing the source
      // selection doesn't return the previous selection's results.
      final String cacheKey =
          '${searchQuery.trim().toLowerCase()} '
          '${(searchSelectedStores.toList()..sort()).join(',')}';

      if (cacheable && _searchCache.containsKey(cacheKey)) {
        setState(() {
          _searchResults = Map.of(_searchCache[cacheKey]!);
          _searchHasSearched = true;
          _byUrlOpenedFromSearchPick = false;
          _searchResultFilter = '';
          searching = false;
        });
        return;
      }

      setState(() {
        searching = true;
        _byUrlOpenedFromSearchPick = false;
        _searchHasSearched = false;
        _searchResults = {};
        _searchResultFilter = '';
      });

      try {
        final List<String> selectedSourceNames = searchSelectedStores.toList();
        if (selectedSourceNames.isEmpty) {
          throw ObtainiumError(tr('noResults'));
        }

        final List<MapEntry<String, Map<String, List<String>>>?>
        results = (await Future.wait(
          sourceProvider.sources
              .where((e) => selectedSourceNames.contains(e.name))
              .map((e) async {
                try {
                  Map<String, dynamic>? querySettings = {};
                  if (e.includeAdditionalOptsInMainSearch) {
                    querySettings = await showDialog<Map<String, dynamic>?>(
                      context: context,
                      builder: (BuildContext ctx) {
                        return GeneratedFormModal(
                          title: tr('searchX', args: [e.name]),
                          items: [
                            ...e.searchQuerySettingFormItems.map((e) => [e]),
                            [
                              GeneratedFormTextField(
                                'url',
                                label: e.hosts.isNotEmpty
                                    ? tr('overrideSource')
                                    : plural('url', 1).substring(2),
                                autoCompleteOptions: [
                                  ...(e.hosts.isNotEmpty ? [e.hosts[0]] : []),
                                  ...appsProvider.apps.values
                                      .where(
                                        (a) =>
                                            sourceProvider
                                                .getSource(
                                                  a.app.url,
                                                  overrideSource:
                                                      a.app.overrideSource,
                                                )
                                                .runtimeType ==
                                            e.runtimeType,
                                      )
                                      .map((a) {
                                        final uri = Uri.parse(a.app.url);
                                        return '${uri.origin}${uri.path}';
                                      }),
                                ],
                                value: e.hosts.isNotEmpty ? e.hosts[0] : '',
                                required: true,
                              ),
                            ],
                          ],
                        );
                      },
                    );
                    if (querySettings == null) {
                      return null;
                    }
                  }
                  return MapEntry(
                    e.runtimeType.toString(),
                    await e.search(searchQuery, querySettings: querySettings),
                  );
                } catch (err) {
                  if (err is! CredsNeededError) {
                    rethrow;
                  } else {
                    err.unexpected = true;
                    if (!context.mounted) return null;
                    showError(err, context);
                    return null;
                  }
                }
              }),
        )).where((a) => a != null).toList();

        // Interleave results from multiple sources
        final Map<String, MapEntry<String, List<String>>> res = {};
        var si = 0;
        var done = false;
        while (!done) {
          done = true;
          for (var r in results) {
            final sourceName = r!.key;
            if (r.value.length > si) {
              done = false;
              final singleRes = r.value.entries.elementAt(si);
              res[singleRes.key] = MapEntry(sourceName, singleRes.value);
            }
          }
          si++;
        }

        if (!context.mounted) return;
        setState(() {
          _searchResults = res;
          _searchHasSearched = true;
          if (cacheable) {
            // Evict the oldest entry once the cache is full (insertion order).
            if (_searchCache.length >= _searchCacheMaxEntries &&
                !_searchCache.containsKey(cacheKey)) {
              _searchCache.remove(_searchCache.keys.first);
            }
            _searchCache[cacheKey] = res;
          }
        });
      } catch (e) {
        if (!context.mounted) return;
        showError(e, context);
      } finally {
        if (mounted) {
          setState(() {
            searching = false;
          });
        }
      }
    }

    // ── Search mode widgets ────────────────────────────────────────────

    Widget getSearchBarRow() {
      final ColorScheme colorScheme = Theme.of(context).colorScheme;
      final bool searchDisabled = searchQuery.isEmpty || doingSomething;
      final Widget trailingSearch = searching
          ? SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: ExpressiveLoadingIndicator(
                  color: colorScheme.primary,
                  constraints: const BoxConstraints.tightFor(
                    width: 22,
                    height: 22,
                  ),
                ),
              ),
            )
          : Material(
              color: searchDisabled
                  ? colorScheme.primary.withValues(alpha: 0.38)
                  : colorScheme.primary,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: searchDisabled
                    ? null
                    : () {
                        _searchSomeSourcesFocusNode.unfocus();
                        FocusManager.instance.primaryFocus?.unfocus();
                        hapticSelection();
                        runInlineSearch(
                          appsProvider: appsProvider,
                          settingsProvider: settingsProvider,
                        );
                      },
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    Icons.search,
                    color: colorScheme.onPrimary,
                    size: 22,
                  ),
                ),
              ),
            );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              focusNode: _searchSomeSourcesFocusNode,
              controller: _searchSomeSourcesController,
              onChanged: (String text) {
                setState(() {
                  searchQuery = text.trim();
                });
              },
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                if (!(searchQuery.isEmpty || doingSomething)) {
                  _searchSomeSourcesFocusNode.unfocus();
                  hapticSelection();
                  runInlineSearch(
                    appsProvider: appsProvider,
                    settingsProvider: settingsProvider,
                  );
                }
              },
              decoration: appPageOutlinedInputDecoration(
                context,
                labelText: null,
                hintText: tr('searchSomeSourcesLabel'),
                isDense: true,
                borderRadius: 30,
              ),
            ),
          ),
          const SizedBox(width: 10),
          trailingSearch,
        ],
      );
    }

    Widget getSearchStoreChips() {
      final searchableSources = sourceProvider.sources
          .where((e) => e.canSearch)
          .toList();
      if (searchableSources.isEmpty) return const SizedBox.shrink();

      searchableSources.sort((a, b) {
        if (a.regionalStore && !b.regionalStore) {
          return 1;
        } else if (!a.regionalStore && b.regionalStore) {
          return -1;
        }
        return a.name.compareTo(b.name);
      });

      return Wrap(
        spacing: 8,
        runSpacing: 4,
        children: searchableSources.map((source) {
          final selected = searchSelectedStores.contains(source.name);
          return FilterChip(
            avatar: source.hosts.isNotEmpty
                ? StoreSourceChipAvatar(host: source.hosts.first, size: 16)
                : null,
            showCheckmark: false,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(source.name),
                if (selected) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.check_rounded, size: 14),
                ],
              ],
            ),
            selected: selected,
            onSelected: (value) {
              setState(() {
                if (value) {
                  searchSelectedStores.add(source.name);
                } else {
                  searchSelectedStores.remove(source.name);
                }
                settingsProvider.searchDeselected = searchableSources
                    .map((s) => s.name)
                    .where((n) => !searchSelectedStores.contains(n))
                    .toList();
              });
            },
          );
        }).toList(),
      );
    }

    Widget getSearchResultsList() {
      if (!_searchHasSearched && _searchResults.isEmpty) {
        return const SizedBox.shrink();
      }
      if (_searchResults.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Center(child: Text(tr('noResults'))),
        );
      }
      // Apply filter if the user typed one.
      final String filterQ = _searchResultFilter.trim().toLowerCase();
      final entries = _searchResults.entries.where((e) {
        if (filterQ.isEmpty) return true;
        final title = e.key.toLowerCase();
        final subtitle = e.value.value.join(' ').toLowerCase();
        return title.contains(filterQ) || subtitle.contains(filterQ);
      }).toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              tr('addAppSearchResultsTitle'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextField(
            controller: _searchResultFilterController,
            onChanged: (v) => setState(() => _searchResultFilter = v),
            decoration:
                appPageOutlinedInputDecoration(
                  context,
                  labelText: null,
                  hintText: tr('filter'),
                  isDense: true,
                  borderRadius: 30,
                ).copyWith(
                  prefixIcon: const Icon(Icons.filter_list_rounded, size: 20),
                  suffixIcon: _searchResultFilter.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchResultFilterController.clear();
                            setState(() => _searchResultFilter = '');
                          },
                        )
                      : null,
                ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Center(child: Text(tr('noResults'))),
            ),
          const SizedBox(height: 8),
          ...entries.map((entry) {
            final displayTitle = entry.key;
            final sourceName = entry.value.key;
            final subtitleLines = entry.value.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: SizedBox(
                  width: 32,
                  child: Center(child: _searchSourceIcon(sourceName)),
                ),
                title: subtitleLines.isNotEmpty
                    ? Text(
                        subtitleLines.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Text(
                        displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                subtitle: subtitleLines.isNotEmpty
                    ? Text(
                        displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    : null,
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () {
                  // Fill URL mode with selected result and switch to it
                  changeUserInput(
                    displayTitle,
                    true,
                    false,
                    updateUrlInput: true,
                    overrideSource: sourceName,
                  );
                  setState(() {
                    _byUrlOpenedFromSearchPick = true;
                    _mode = _AddMode.byUrl;
                  });
                },
              ),
            );
          }),
        ],
      );
    }

    // ── Mode selector ──────────────────────────────────────────────────

    Widget buildModeSelector() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: AppSegmentedButton<_AddMode>(
          segments: [
            ButtonSegment(
              value: _AddMode.byUrl,
              label: AppSegmentedButtonLabel(tr('addByUrl')),
              icon: const Icon(Icons.link_rounded),
            ),
            ButtonSegment(
              value: _AddMode.search,
              label: AppSegmentedButtonLabel(tr('addBySearch')),
              icon: const Icon(Icons.search_rounded),
            ),
            ButtonSegment(
              value: _AddMode.fromDevice,
              label: AppSegmentedButtonLabel(tr('addFromDevice')),
              icon: const Icon(Icons.phone_android_rounded),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (Set<_AddMode> selection) async {
            final _AddMode nextMode = selection.first;
            if (nextMode == _mode) return;
            if (!await confirmCancelBulkScanForNavigation()) {
              return;
            }
            if (!mounted) return;
            setState(() {
              _byUrlOpenedFromSearchPick = false;
              _mode = nextMode;
            });
          },
        ),
      );
    }

    // ── Layout ─────────────────────────────────────────────────────────

    final ColorScheme addScheme = Theme.of(context).colorScheme;

    BoxDecoration buildAddAppGradientDecoration() {
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.38, 0.72, 1],
          colors: [
            addScheme.schemePageGradientTopColor,
            addScheme.schemePageGradientMidColor,
            addScheme.surface,
            addScheme.surface,
          ],
        ),
      );
    }

    Widget buildGradientBackground() {
      return Positioned.fill(
        child: DecoratedBox(decoration: buildAddAppGradientDecoration()),
      );
    }

    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool isLargeScreen = isLargeScreenLayout(
      screenWidth,
      MediaQuery.orientationOf(context),
    );

    Widget buildModeTile(_AddMode modeObj, String title, IconData icon) {
      final ColorScheme cs = Theme.of(context).colorScheme;
      final bool selected = _mode == modeObj;

      final Color containerColor = selected
          ? cs.secondaryContainer
          : cs.surfaceContainerHigh;
      final Color contentColor = selected
          ? cs.onSecondaryContainer
          : cs.onSurface;

      final Color iconBoxColor = selected
          ? cs.primary.withValues(alpha: 0.16)
          : cs.primaryContainer.withValues(alpha: 0.48);

      final Color iconColor = selected ? cs.primary : cs.onSurfaceVariant;
      final Color chevronColor = cs.onSurfaceVariant;

      final double modeTileRadius = settingsProvider.cardCornerRadiusFor(
        SettingsProvider.baseCollapsedHeaderRadius,
      );

      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Container(
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(modeTileRadius),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () async {
                if (modeObj == _mode) return;
                if (!await confirmCancelBulkScanForNavigation()) {
                  return;
                }
                setState(() {
                  _byUrlOpenedFromSearchPick = false;
                  _mode = modeObj;
                });
              },
              borderRadius: BorderRadius.circular(modeTileRadius),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: iconBoxColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: iconColor, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: contentColor,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: chevronColor,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (isLargeScreen) {
      return Scaffold(
        backgroundColor: addScheme.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (settingsProvider.useGradientBackground)
              buildGradientBackground(),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Scaffold(
                    backgroundColor: settingsProvider.useGradientBackground
                        ? Colors.transparent
                        : addScheme.surface,
                    body: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height:
                              MediaQuery.paddingOf(context).top +
                              kToolbarHeight,
                          child: Padding(
                            padding: EdgeInsetsDirectional.only(
                              start: 20,
                              top: MediaQuery.paddingOf(context).top,
                              end: 20,
                            ),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                tr('addApp'),
                                style: Theme.of(context).textTheme.titleLarge!
                                    .copyWith(color: addScheme.onSurface),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              buildModeTile(
                                _AddMode.byUrl,
                                tr('addByUrl'),
                                Icons.link_rounded,
                              ),
                              buildModeTile(
                                _AddMode.search,
                                tr('addBySearch'),
                                Icons.search_rounded,
                              ),
                              buildModeTile(
                                _AddMode.fromDevice,
                                tr('addFromDevice'),
                                Icons.phone_android_rounded,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: addScheme.outlineVariant.withAlpha(50),
                ),
                Expanded(
                  flex: 4,
                  child: Scaffold(
                    backgroundColor: settingsProvider.useGradientBackground
                        ? Colors.transparent
                        : addScheme.surface,
                    body: Builder(
                      builder: (context) {
                        if (_mode == _AddMode.fromDevice) {
                          return BulkAddWidget(
                            key: _bulkWidgetKey,
                            isLargeScreen: isLargeScreen,
                            bottomActionBottomPadding: appVaultFabBottomPadding,
                            onComplete: () => setState(() {
                              _byUrlOpenedFromSearchPick = false;
                              _mode = _AddMode.byUrl;
                            }),
                          );
                        }

                        return CustomScrollView(
                          key: PageStorageKey<String>(
                            'add-app-detail-${_mode.name}-scroll',
                          ),
                          slivers: [
                            SliverSafeArea(
                              top: true,
                              bottom: false,
                              sliver: SliverPadding(
                                padding: const EdgeInsets.all(16),
                                sliver: SliverToBoxAdapter(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (_mode == _AddMode.byUrl) ...[
                                        const SizedBox(height: 8),
                                        getUrlInputRow(),
                                        const SizedBox(height: 16),
                                        if (pickedSource != null)
                                          getHTMLSourceOverrideDropdown(),
                                        if (pickedSource != null)
                                          FutureBuilder(
                                            builder: (ctx, val) {
                                              return val.data != null &&
                                                      val.data!.isNotEmpty
                                                  ? Text(
                                                      val.data!,
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.bodySmall,
                                                    )
                                                  : const SizedBox();
                                            },
                                            future: pickedSource
                                                ?.getSourceNote(),
                                          ),
                                        if (pickedSource != null)
                                          getAdditionalOptsCol(),
                                      ],
                                      if (_mode == _AddMode.search) ...[
                                        const SizedBox(height: 8),
                                        getSearchBarRow(),
                                        const SizedBox(height: 12),
                                        Text(
                                          tr('storesToSearch'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        getSearchStoreChips(),
                                        getSearchResultsList(),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (settingsProvider.progressiveBlurEnabled)
                              SliverToBoxAdapter(
                                child: SizedBox(height: bottomChromeClearance),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            buildBottomActionFabOverlay(),
          ],
        ),
      );
    }

    // Device mode uses a plain Column so the BulkAddWidget always gets a clean
    // bounded height via Expanded, with no outer CustomScrollView that could
    // steal scroll gestures or push content off-screen.
    if (_mode == _AddMode.fromDevice) {
      return Scaffold(
        backgroundColor: addScheme.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (settingsProvider.useGradientBackground)
              buildGradientBackground(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: MediaQuery.paddingOf(context).top + kToolbarHeight,
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: 20,
                      top: MediaQuery.paddingOf(context).top,
                      end: 20,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        tr('addApp'),
                        style: Theme.of(context).textTheme.titleLarge!.copyWith(
                          color: addScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
                buildModeSelector(),
                Expanded(
                  child: BulkAddWidget(
                    key: _bulkWidgetKey,
                    isLargeScreen: isLargeScreen,
                    bottomActionBottomPadding: appVaultFabBottomPadding,
                    onComplete: () => setState(() {
                      _byUrlOpenedFromSearchPick = false;
                      _mode = _AddMode.byUrl;
                    }),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Scaffold(
      // Don't let the keyboard resize the body (see the apps-list Scaffold): the
      // per-frame resize repaint forces the app bar's progressive-blur
      // BackdropFilter to re-rasterize every frame and stutters the keyboard
      // slide. The URL / search field is at the top, so it stays visible.
      resizeToAvoidBottomInset: false,
      backgroundColor: addScheme.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (settingsProvider.useGradientBackground) buildGradientBackground(),
          CustomScrollView(
            scrollCacheExtent: const ScrollCacheExtent.pixels(1600),
            key: const PageStorageKey<String>('add-app-tab-scroll'),
            slivers: <Widget>[
              CustomAppBar(
                title: tr('addApp'),
                matchGradientBackground: settingsProvider.useGradientBackground,
              ),
              // Mode selector pinned just below the app bar
              SliverPersistentHeader(
                pinned: false,
                delegate: _PaddedWidgetDelegate(
                  child: buildModeSelector(),
                  height: 60,
                  backgroundColor: settingsProvider.useGradientBackground
                      ? Colors.transparent
                      : addScheme.surface,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.topCenter,
                        children: <Widget>[...previousChildren, ?currentChild],
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(_mode),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── By URL ─────────────────────────────────────
                          if (_mode == _AddMode.byUrl) ...[
                            const SizedBox(height: 8),
                            getUrlInputRow(),
                            const SizedBox(height: 16),
                            if (pickedSource != null)
                              getHTMLSourceOverrideDropdown(),
                            if (pickedSource != null)
                              FutureBuilder(
                                builder: (ctx, val) {
                                  return val.data != null &&
                                          val.data!.isNotEmpty
                                      ? Text(
                                          val.data!,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        )
                                      : const SizedBox();
                                },
                                future: pickedSource?.getSourceNote(),
                              ),
                            if (pickedSource != null) getAdditionalOptsCol(),
                          ],

                          // ── Search ─────────────────────────────────────
                          if (_mode == _AddMode.search) ...[
                            const SizedBox(height: 8),
                            getSearchBarRow(),
                            const SizedBox(height: 12),
                            Text(
                              tr('storesToSearch'),
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            getSearchStoreChips(),
                            getSearchResultsList(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (settingsProvider.progressiveBlurEnabled)
                SliverToBoxAdapter(
                  child: SizedBox(height: bottomChromeClearance),
                ),
            ],
          ),
          buildBottomActionFabOverlay(),
        ],
      ),
    );
  }

  /// Small icon to indicate which source a search result came from.
  Widget _searchSourceIcon(String sourceName) {
    final String? assetPath = storeSourceAssetPathForClassName(sourceName);
    if (assetPath == null) return const Icon(Icons.store_rounded, size: 20);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    Widget img = StoreSourceIconImage(assetPath: assetPath, size: 20);
    if (iconNeedsInversion(assetPath, isDark)) {
      img = ColorFiltered(colorFilter: invertColorFilter, child: img);
    }
    return img;
  }
}

/// Minimal [SliverPersistentHeaderDelegate] for a fixed-height widget.
class _PaddedWidgetDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  final Color backgroundColor;

  const _PaddedWidgetDelegate({
    required this.child,
    required this.height,
    required this.backgroundColor,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(color: backgroundColor, child: child);
  }

  @override
  bool shouldRebuild(_PaddedWidgetDelegate oldDelegate) =>
      oldDelegate.child != child ||
      oldDelegate.height != height ||
      oldDelegate.backgroundColor != backgroundColor;
}
