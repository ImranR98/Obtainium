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
import 'package:obtainium/pages/bulk_add_apps.dart';
import 'package:obtainium/pages/home.dart';
import 'package:obtainium/pages/import_export.dart';
import 'package:obtainium/pages/import_from_url_list.dart';
import 'package:obtainium/pages/import_github_stars.dart';
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
import 'package:obtainium/theme/app_theme_accent.dart';
import 'package:obtainium/theme/m3e_expressive_list.dart';
import 'package:obtainium/widgets/help_hint_icon.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

const double _appVaultFabBottomGap = 8.0;
const double _fabHorizontalMargin = 16.0;
const double _fabMinimumSafeBottomPadding = 16.0;
InlineSpan _tooltipMessageWithBoldMarkdown(String message) {
  final List<String> messageParts = message.split('**');
  return TextSpan(
    children: [
      for (int partIndex = 0; partIndex < messageParts.length; partIndex++)
        TextSpan(
          text: messageParts[partIndex],
          style: partIndex.isOdd
              ? const TextStyle(fontWeight: FontWeight.bold)
              : null,
        ),
    ],
  );
}

enum _AddMode { launcher, byUrl, search }

enum _AddAppLauncherDestination {
  addByUrl,
  searchSources,
  batchSearch,
  bulkSearch,
  importUrlList,
  githubStars,
}

enum _PackageIdDetectionChoice { download, trackOnly }

class AddAppPage extends StatefulWidget {
  const AddAppPage({super.key, this.homeFabChromeTick, this.onStateChanged})
    : _initialMode = _AddMode.launcher,
      _initialUrl = null,
      _searchAddsMultipleApps = false,
      _onBatchSearchSaved = null,
      _onEmbeddedAddCompleted = null,
      _embeddedDetail = false;

  const AddAppPage._flow({
    super.key,
    required _AddMode initialMode,
    this._initialUrl,
    bool searchAddsMultipleApps = false,
    Future<void> Function()? onBatchSearchSaved,
    VoidCallback? onEmbeddedAddCompleted,
    bool embeddedDetail = false,
    this.homeFabChromeTick,
    this.onStateChanged,
  }) : assert(initialMode == _AddMode.byUrl || initialMode == _AddMode.search),
       assert(!searchAddsMultipleApps || initialMode == _AddMode.search),
       assert(onBatchSearchSaved == null || searchAddsMultipleApps),
       assert(onEmbeddedAddCompleted == null || embeddedDetail),
       _initialMode = initialMode,
       _searchAddsMultipleApps = searchAddsMultipleApps,
       _onBatchSearchSaved = onBatchSearchSaved,
       _onEmbeddedAddCompleted = onEmbeddedAddCompleted,
       _embeddedDetail = embeddedDetail;

  final _AddMode _initialMode;
  final String? _initialUrl;
  final bool _searchAddsMultipleApps;
  final Future<void> Function()? _onBatchSearchSaved;
  final VoidCallback? _onEmbeddedAddCompleted;
  final bool _embeddedDetail;
  final ValueNotifier<int>? homeFabChromeTick;
  final VoidCallback? onStateChanged;

  @override
  State<AddAppPage> createState() => AddAppPageState();
}

class AddAppPageState extends State<AddAppPage> {
  // ─── Mode ──────────────────────────────────────────────────────────────
  late _AddMode _mode;

  bool get isSubFlowActive => _mode != _AddMode.launcher;

  void _notifyModeChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.homeFabChromeTick != null) {
        widget.homeFabChromeTick!.value = widget.homeFabChromeTick!.value + 1;
      }
      widget.onStateChanged?.call();
    });
  }

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
  final GlobalKey _urlFieldKey = GlobalKey();
  late final TextEditingController _urlFieldController;
  late final FocusNode _urlFieldFocusNode;
  _AddAppLauncherDestination _selectedLauncherDestination =
      _AddAppLauncherDestination.addByUrl;
  String? _launcherDetailUrl;
  final GlobalKey<AddAppPageState> _launcherUrlDetailKey = GlobalKey();
  final GlobalKey<AddAppPageState> _launcherSearchDetailKey = GlobalKey();
  final GlobalKey<AddAppPageState> _launcherBatchSearchDetailKey = GlobalKey();
  final GlobalKey<BulkAddWidgetState> _launcherBulkDetailKey = GlobalKey();

  bool get isBulkAdding =>
      (_launcherUrlDetailKey.currentState?.gettingAppInfo ?? false) ||
      (_launcherSearchDetailKey.currentState?.gettingAppInfo ?? false) ||
      (_launcherBatchSearchDetailKey.currentState?.gettingAppInfo ?? false) ||
      (_launcherBulkDetailKey.currentState?.isAdding ?? false);

  AddAppPageState? get _selectedLauncherFlowState =>
      switch (_selectedLauncherDestination) {
        _AddAppLauncherDestination.addByUrl =>
          _launcherUrlDetailKey.currentState,
        _AddAppLauncherDestination.searchSources =>
          _launcherSearchDetailKey.currentState,
        _AddAppLauncherDestination.batchSearch =>
          _launcherBatchSearchDetailKey.currentState,
        _ => null,
      };

  bool get hasInlineLauncherFlow =>
      widget._initialMode == _AddMode.launcher && _mode != _AddMode.launcher;

  void clearInputFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  bool get _hasUnsavedFlowInput {
    if (_mode == _AddMode.byUrl) {
      return userInput.trim().isNotEmpty;
    }
    return _mode == _AddMode.search && _searchResults.isNotEmpty;
  }

  Future<bool> confirmCancelBulkScanForNavigation() async {
    if (_mode == _AddMode.launcher) {
      final AddAppPageState? selectedFlowState = _selectedLauncherFlowState;
      if (selectedFlowState != null) {
        return selectedFlowState.confirmCancelBulkScanForNavigation();
      }
      if (_selectedLauncherDestination ==
          _AddAppLauncherDestination.bulkSearch) {
        final BulkAddWidgetState? bulkState =
            _launcherBulkDetailKey.currentState;
        if (bulkState != null) {
          return bulkState.confirmCancelScanForNavigation(context);
        }
      }
    }

    final bool isUrlDirty = _mode == _AddMode.byUrl && _hasUnsavedFlowInput;
    final bool isSearchDirty = _mode == _AddMode.search && _hasUnsavedFlowInput;

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

  Future<void> _requestFlowPop() async {
    if (handleBack()) return;
    clearInputFocus();
    final bool hadUnsavedInput = _hasUnsavedFlowInput;
    final NavigatorState navigator = Navigator.of(context);
    if (!await confirmCancelBulkScanForNavigation()) return;
    if (!mounted || !navigator.mounted) return;
    if (widget._initialMode == _AddMode.launcher) {
      if (_mode != _AddMode.launcher) {
        _resetAllInputStates();
      }
      return;
    }
    if (hadUnsavedInput) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && navigator.mounted) navigator.pop();
      });
    } else {
      navigator.pop();
    }
  }

  /// Handles Search-result drill-in before the routed flow itself is closed.
  /// The launcher returns false so [HomePageState] can use normal tab back.
  bool handleBack() {
    if (_mode == _AddMode.launcher) {
      if (_selectedLauncherFlowState?.handleBack() ?? false) {
        return true;
      }
      if (_selectedLauncherDestination ==
              _AddAppLauncherDestination.bulkSearch &&
          (_launcherBulkDetailKey.currentState?.handleBack() ?? false)) {
        return true;
      }
    }
    if (_mode == _AddMode.byUrl && _byUrlOpenedFromSearchPick) {
      clearInputFocus();
      setState(() {
        _byUrlOpenedFromSearchPick = false;
        _mode = _AddMode.search;
      });
      _notifyModeChanged();
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
  final Set<String> _searchSelectedResultUrls = {};
  bool _searchHasSearched = false;
  String _searchResultFilter = '';
  bool _byUrlOpenedFromSearchPick = false;
  late final TextEditingController _searchSomeSourcesController;
  late final TextEditingController _searchResultFilterController;
  late final FocusNode _searchSomeSourcesFocusNode;
  final GlobalKey _searchResultFilterKey = GlobalKey();

  void linkFn(String input) {
    try {
      if (input.isEmpty) {
        throw UnsupportedURLError();
      }
      sourceProvider.getSource(input);
      bool modeChanged = false;
      if (_mode == _AddMode.launcher) {
        setState(() {
          _mode = _AddMode.byUrl;
        });
        modeChanged = true;
      }
      if (_mode != _AddMode.byUrl || _byUrlOpenedFromSearchPick) {
        setState(() {
          _mode = _AddMode.byUrl;
          _byUrlOpenedFromSearchPick = false;
        });
        modeChanged = true;
      }
      if (modeChanged) {
        _notifyModeChanged();
      }
      changeUserInput(input, true, false, updateUrlInput: true);
    } catch (e) {
      showError(e);
    }
  }

  @override
  void initState() {
    super.initState();
    _mode = widget._initialMode;
    _urlFieldController = TextEditingController();
    _urlFieldFocusNode = FocusNode();
    _searchSomeSourcesController = TextEditingController();
    _searchResultFilterController = TextEditingController();
    _searchSomeSourcesFocusNode = FocusNode();
    if (widget._initialUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) linkFn(widget._initialUrl!);
      });
    }
  }

  @override
  void dispose() {
    _urlFieldController.dispose();
    _urlFieldFocusNode.dispose();
    _searchSomeSourcesController.dispose();
    _searchResultFilterController.dispose();
    _searchSomeSourcesFocusNode.dispose();
    super.dispose();
  }

  /// Lazily initialise the store selection for the active search workflow.
  Set<String> _getSearchSelectedStores() {
    _searchSelectedStores ??= {};
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
          final bool preserveUrlFocus = _urlFieldFocusNode.hasFocus;
          _urlFieldController.value = TextEditingValue(
            text: input,
            selection: TextSelection.collapsed(offset: input.length),
          );
          if (preserveUrlFocus) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _urlFieldController.selection = TextSelection.collapsed(
                offset: _urlFieldController.text.length,
              );
              _urlFieldFocusNode.requestFocus();
            });
          }
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
    final bool modeChanged = _mode != widget._initialMode;
    setState(() {
      _resetUrlModeInput();
      searching = false;
      searchQuery = '';
      _searchResults = {};
      _searchSelectedResultUrls.clear();
      _searchHasSearched = false;
      _searchResultFilter = '';
      _byUrlOpenedFromSearchPick = false;
      _searchSomeSourcesController.clear();
      _searchResultFilterController.clear();
      _mode = widget._initialMode;
    });
    if (modeChanged) {
      _notifyModeChanged();
    }
  }

  void _scrollEmbeddedSearchResultsToFilter() {
    if (!widget._embeddedDetail || _searchResults.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final BuildContext? filterContext = _searchResultFilterKey.currentContext;
      if (filterContext == null) return;
      Scrollable.ensureVisible(
        filterContext,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubicEmphasized,
        alignment: 0,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  void _showSupportedSourcesDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return GeneratedFormModal(
          singleNullReturnButton: tr('ok'),
          title: tr('supportedSources'),
          items: const [],
          additionalWidgets: [
            ...sourceProvider.sourceTemplates
                .where((source) => source.name != 'RockMods')
                .map(
                  (source) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: InkWell(
                      onTap: source.hosts.isNotEmpty
                          ? () {
                              launchUrlString(
                                'https://${source.hosts[0]}',
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          : null,
                      child: Text(
                        '${source.name}${source.enforceTrackOnly ? ' ${tr('trackOnlyInBrackets')}' : ''}${source.canSearch ? ' ${tr('searchableInBrackets')}' : ''}',
                        style: TextStyle(
                          decoration: source.hosts.isNotEmpty
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

  Widget _buildAppSourceUrlField({
    required BuildContext context,
    required bool submitDisabled,
    required VoidCallback onSubmit,
    bool matchLauncherButton = false,
    bool selected = false,
    ValueChanged<String>? onValidLauncherInput,
    VoidCallback? onTap,
  }) {
    final bool showSupportedSourcesButton = userInput.trim().isEmpty;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextStyle? launcherTextStyle = matchLauncherButton
        ? Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colorScheme.onSecondaryContainer,
          )
        : null;
    final Widget supportedSourcesButton = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: showSupportedSourcesButton ? 1 : 0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubicEmphasized,
      builder: (context, animationValue, child) {
        return ClipRect(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            widthFactor: animationValue,
            child: SizedBox(
              width: 56,
              height: 48,
              child: Opacity(
                opacity: animationValue,
                child: IgnorePointer(
                  ignoring: !showSupportedSourcesButton,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: IconButton(
        tooltip: tr('supportedSources'),
        padding: EdgeInsets.zero,
        icon: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: matchLauncherButton
                ? colorScheme.surfaceContainerHighest
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: matchLauncherButton ? colorScheme.onSurfaceVariant : null,
          ),
        ),
        onPressed: () => _showSupportedSourcesDialog(context),
      ),
    );
    final InputDecoration decoration =
        appPageOutlinedInputDecoration(
          context,
          labelText: tr('appSourceURL'),
          borderRadius: SettingsProvider.collapsedHeaderHeight / 2,
        ).copyWith(
          fillColor: matchLauncherButton
              ? selected
                    ? colorScheme.secondaryContainer
                    : m3eCollapsedGroupHeaderFill(colorScheme)
              : null,
          labelStyle: launcherTextStyle,
          floatingLabelStyle: matchLauncherButton
              ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                )
              : null,
          contentPadding: matchLauncherButton
              ? const EdgeInsetsDirectional.fromSTEB(50, 16, 14, 16)
              : null,
          prefixIconConstraints: matchLauncherButton
              ? const BoxConstraints.tightFor(width: 50, height: 48)
              : null,
          prefixIcon: matchLauncherButton
              ? Padding(
                  padding: const EdgeInsetsDirectional.only(start: 14, end: 6),
                  child: Center(
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.link_rounded,
                        color: colorScheme.onSecondaryContainer,
                        size: 17,
                      ),
                    ),
                  ),
                )
              : null,
          constraints: matchLauncherButton
              ? const BoxConstraints.tightFor(
                  height: SettingsProvider.collapsedHeaderHeight,
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          suffixIcon: supportedSourcesButton,
        );

    final Widget textField = TextField(
      key: _urlFieldKey,
      controller: _urlFieldController,
      focusNode: _urlFieldFocusNode,
      style: launcherTextStyle,
      textAlignVertical: TextAlignVertical.center,
      onTap: onTap,
      onChanged: (String text) {
        final bool valid = _isUrlInputValid(text);
        changeUserInput(text, valid, false);
        if (_mode == _AddMode.launcher && valid) {
          if (onValidLauncherInput != null) {
            onValidLauncherInput(text);
          } else {
            linkFn(text);
          }
        }
      },
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.go,
      onSubmitted: (_) {
        if (!submitDisabled) {
          hapticSelection();
          onSubmit();
        }
      },
      decoration: decoration,
    );

    return SizedBox(
      height: SettingsProvider.collapsedHeaderHeight,
      child: textField,
    );
  }

  Widget _buildLauncher(BuildContext context) {
    context.select<SettingsProvider, int>(
      (SettingsProvider settings) => Object.hash(
        settings.useGradientBackground,
        settings.progressiveBlurEnabled,
      ),
    );
    final SettingsProvider settingsProvider = context.read<SettingsProvider>();
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final HomePageState? homeState = context
        .findAncestorStateOfType<HomePageState>();
    final double coveredBottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final double bottomChromeClearance = settingsProvider.progressiveBlurEnabled
        ? coveredBottomInset
        : 0.0;

    final bool useTwoPaneLayout =
        MediaQuery.sizeOf(context).width >= kLargeScreenWidthBreakpoint &&
        !settingsProvider.alwaysUsePhoneLayout;
    final double embeddedBottomActionPadding =
        (bottomChromeClearance > _fabMinimumSafeBottomPadding
            ? bottomChromeClearance
            : _fabMinimumSafeBottomPadding) +
        _appVaultFabBottomGap;

    Future<void> switchToAppsPage() async {
      if (homeState != null) {
        await homeState.switchToPage(0);
      }
    }

    void resetLauncherAfterSuccessfulAdd() {
      if (!mounted) return;
      clearInputFocus();
      setState(() {
        _selectedLauncherDestination = _AddAppLauncherDestination.addByUrl;
        _launcherDetailUrl = null;
        _resetUrlModeInput();
      });
    }

    Future<void> resetLauncherAndSwitchToAppsPage() async {
      resetLauncherAfterSuccessfulAdd();
      await switchToAppsPage();
    }

    void openPage(WidgetBuilder builder) {
      clearInputFocus();
      hapticSelection();
      unawaited(
        Navigator.of(context).push(MaterialPageRoute(builder: builder)),
      );
    }

    Future<void> selectLauncherDestination(
      _AddAppLauncherDestination destination,
    ) async {
      if (_selectedLauncherDestination == destination) return;
      if (!await confirmCancelBulkScanForNavigation()) return;
      if (!mounted) return;
      clearInputFocus();
      hapticSelection();
      setState(() {
        _selectedLauncherDestination = destination;
      });
    }

    Widget launcherButton({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      IconData trailingIcon = Icons.chevron_right_rounded,
      double trailingIconSize = 20,
      bool selected = false,
    }) {
      return SizedBox(
        height: SettingsProvider.collapsedHeaderHeight,
        child: FilledButton.tonal(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: selected
                ? colorScheme.secondaryContainer
                : m3eCollapsedGroupHeaderFill(colorScheme),
            foregroundColor: colorScheme.onSecondaryContainer,
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 12, 0),
            shape: const StadiumBorder(),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: colorScheme.onSecondaryContainer,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(label)),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  trailingIcon,
                  color: colorScheme.onSurfaceVariant,
                  size: trailingIconSize,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final List<Widget> actions = [
      if (useTwoPaneLayout)
        launcherButton(
          icon: Icons.link_rounded,
          label: tr('appSourceURL'),
          selected:
              _selectedLauncherDestination ==
              _AddAppLauncherDestination.addByUrl,
          onPressed: () => unawaited(
            selectLauncherDestination(_AddAppLauncherDestination.addByUrl),
          ),
        )
      else
        _buildAppSourceUrlField(
          context: context,
          submitDisabled: !_isUrlInputValid(userInput),
          onSubmit: () => linkFn(userInput),
          matchLauncherButton: true,
        ),
      // Stable mapping: multi-source search uses manage-search; the
      // single-source batch workflow uses the plain search glyph.
      launcherButton(
        icon: Icons.manage_search_rounded,
        label: tr('searchSourcesAddApp'),
        selected:
            useTwoPaneLayout &&
            _selectedLauncherDestination ==
                _AddAppLauncherDestination.searchSources,
        onPressed: () {
          if (useTwoPaneLayout) {
            unawaited(
              selectLauncherDestination(
                _AddAppLauncherDestination.searchSources,
              ),
            );
          } else {
            openPage(
              (_) => const AddAppPage._flow(initialMode: _AddMode.search),
            );
          }
        },
      ),
      launcherButton(
        icon: Icons.search_rounded,
        label: tr('searchSourceAddApps'),
        selected:
            useTwoPaneLayout &&
            _selectedLauncherDestination ==
                _AddAppLauncherDestination.batchSearch,
        onPressed: () {
          if (useTwoPaneLayout) {
            unawaited(
              selectLauncherDestination(_AddAppLauncherDestination.batchSearch),
            );
          } else {
            openPage(
              (_) => AddAppPage._flow(
                initialMode: _AddMode.search,
                searchAddsMultipleApps: true,
                onBatchSearchSaved: switchToAppsPage,
              ),
            );
          }
        },
      ),
      launcherButton(
        icon: Icons.phone_android_rounded,
        label: tr('bulkSearchDeviceApps'),
        selected:
            useTwoPaneLayout &&
            _selectedLauncherDestination ==
                _AddAppLauncherDestination.bulkSearch,
        onPressed: () {
          if (useTwoPaneLayout) {
            unawaited(
              selectLauncherDestination(_AddAppLauncherDestination.bulkSearch),
            );
          } else {
            openPage((_) => const BulkAddAppsPage());
          }
        },
      ),
      launcherButton(
        icon: Icons.playlist_add_rounded,
        label: tr('importFromURLList'),
        selected:
            useTwoPaneLayout &&
            _selectedLauncherDestination ==
                _AddAppLauncherDestination.importUrlList,
        onPressed: () {
          if (useTwoPaneLayout) {
            unawaited(
              selectLauncherDestination(
                _AddAppLauncherDestination.importUrlList,
              ),
            );
          } else {
            openPage((_) => const ImportFromUrlListPage());
          }
        },
      ),
      launcherButton(
        icon: Icons.star_rounded,
        label: tr('importGitHubStarredRepositories'),
        selected:
            useTwoPaneLayout &&
            _selectedLauncherDestination ==
                _AddAppLauncherDestination.githubStars,
        onPressed: () {
          if (useTwoPaneLayout) {
            unawaited(
              selectLauncherDestination(_AddAppLauncherDestination.githubStars),
            );
          } else {
            clearInputFocus();
            hapticSelection();
            unawaited(
              showImportGitHubStarsSheet(
                context,
                onImportCompleted: switchToAppsPage,
              ),
            );
          }
        },
      ),
      launcherButton(
        icon: Icons.apps_rounded,
        label: tr('crowdsourcedConfigsShort'),
        trailingIcon: Icons.open_in_new_rounded,
        trailingIconSize: 18,
        onPressed: () {
          clearInputFocus();
          hapticSelection();
          unawaited(
            launchUrlString(
              'https://apps.obtainium.imranr.dev/',
              mode: LaunchMode.externalApplication,
            ),
          );
        },
      ),
    ];

    Widget actionColumn(List<Widget> paneActions) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SettingsProvider.collapsedHeaderGap,
        children: paneActions,
      );
    }

    if (useTwoPaneLayout) {
      final Widget selectedDetail = switch (_selectedLauncherDestination) {
        _AddAppLauncherDestination.addByUrl => AddAppPage._flow(
          key: _launcherUrlDetailKey,
          initialMode: _AddMode.byUrl,
          initialUrl: _launcherDetailUrl,
          onEmbeddedAddCompleted: resetLauncherAfterSuccessfulAdd,
          embeddedDetail: true,
          homeFabChromeTick: widget.homeFabChromeTick,
          onStateChanged: widget.onStateChanged,
        ),
        _AddAppLauncherDestination.searchSources => AddAppPage._flow(
          key: _launcherSearchDetailKey,
          initialMode: _AddMode.search,
          onEmbeddedAddCompleted: resetLauncherAfterSuccessfulAdd,
          embeddedDetail: true,
          homeFabChromeTick: widget.homeFabChromeTick,
          onStateChanged: widget.onStateChanged,
        ),
        _AddAppLauncherDestination.batchSearch => AddAppPage._flow(
          key: _launcherBatchSearchDetailKey,
          initialMode: _AddMode.search,
          searchAddsMultipleApps: true,
          onBatchSearchSaved: resetLauncherAndSwitchToAppsPage,
          embeddedDetail: true,
          homeFabChromeTick: widget.homeFabChromeTick,
          onStateChanged: widget.onStateChanged,
        ),
        _AddAppLauncherDestination.bulkSearch => BulkAddWidget(
          key: _launcherBulkDetailKey,
          standalone: false,
          isLargeScreen: true,
          bottomActionBottomPadding: embeddedBottomActionPadding,
          onComplete: () => unawaited(resetLauncherAndSwitchToAppsPage()),
        ),
        _AddAppLauncherDestination.importUrlList => ImportFromUrlListPage(
          embedded: true,
          onImportCompleted: resetLauncherAndSwitchToAppsPage,
        ),
        _AddAppLauncherDestination.githubStars => ImportGitHubStarsContent(
          embedded: true,
          onImportCompleted: resetLauncherAndSwitchToAppsPage,
        ),
      };
      return Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: colorScheme.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: settingsProvider.useGradientBackground
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: colorScheme.schemePageBackgroundGradient,
                      ),
                    )
                  : ColoredBox(color: colorScheme.surface),
            ),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Scaffold(
                    resizeToAvoidBottomInset: false,
                    backgroundColor: settingsProvider.useGradientBackground
                        ? Colors.transparent
                        : colorScheme.surface,
                    body: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (settingsProvider.useGradientBackground)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient:
                                  colorScheme.schemePageBackgroundGradient,
                            ),
                          ),
                        CustomScrollView(
                          key: const PageStorageKey<String>(
                            'add-app-launcher-master-scroll',
                          ),
                          slivers: [
                            CustomAppBar(
                              title: tr('addApp'),
                              matchGradientBackground:
                                  settingsProvider.useGradientBackground,
                              progressiveBlurOverlayColor: colorScheme.surface
                                  .withValues(alpha: 0.72),
                            ),
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                8,
                                16,
                                112 + bottomChromeClearance,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: actionColumn(actions),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: colorScheme.outlineVariant.withAlpha(50),
                ),
                Expanded(
                  flex: 4,
                  child: Scaffold(
                    resizeToAvoidBottomInset: false,
                    backgroundColor: settingsProvider.useGradientBackground
                        ? Colors.transparent
                        : colorScheme.surface,
                    body: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (settingsProvider.useGradientBackground)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient:
                                    colorScheme.schemePageBackgroundGradient,
                              ),
                            ),
                          ),
                        KeyedSubtree(
                          key: ValueKey<_AddAppLauncherDestination>(
                            _selectedLauncherDestination,
                          ),
                          child: selectedDetail,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: colorScheme.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (settingsProvider.useGradientBackground)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: colorScheme.schemePageBackgroundGradient,
              ),
            ),
          CustomScrollView(
            key: const PageStorageKey<String>('add-app-launcher-scroll'),
            slivers: [
              CustomAppBar(
                title: tr('addApp'),
                matchGradientBackground: settingsProvider.useGradientBackground,
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  112 + bottomChromeClearance,
                ),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: actionColumn(actions),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == _AddMode.launcher) {
      return _buildLauncher(context);
    }
    final bool isInlineLauncherFlow = widget._initialMode == _AddMode.launcher;
    final AppsProvider appsProvider = context.read<AppsProvider>();
    // Narrow subscription to only the settings this page actually reads
    // in build. The previous broad watch rebuilt the (long, expensive)
    // add-app form on every settings notify, including ones unrelated to
    // this page (categories, sort, swipe actions, etc.).
    context.select<SettingsProvider, int>(
      (s) => Object.hash(
        s.hideTrackOnlyWarning,
        s.useGradientBackground,
        s.progressiveBlurEnabled,
        s.cardCornerScale,
        s.alwaysUsePhoneLayout,
        s.getSettingString(GitHub.githubCredsKey),
        s.getSettingString(GitHub.validatedPATFingerprintKey),
      ),
    );
    final SettingsProvider settingsProvider = context.read<SettingsProvider>();
    final NotificationsProvider notificationsProvider = context
        .read<NotificationsProvider>();
    final bool useLargeScreenLayout =
        MediaQuery.sizeOf(context).width >= kLargeScreenWidthBreakpoint &&
        !settingsProvider.alwaysUsePhoneLayout;
    final HomePageState? homeState = context
        .findAncestorStateOfType<HomePageState>();

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
    final bool batchSearchHasSelection =
        widget._searchAddsMultipleApps &&
        _mode == _AddMode.search &&
        _searchSelectedResultUrls.isNotEmpty;
    final bool showBottomActionFab = urlHasInput || batchSearchHasSelection;

    // ── Track-only / release-date confirmations (URL mode) ─────────────

    Future<bool> getTrackOnlyConfirmationIfNeeded(
      bool userPickedTrackOnly, {
      bool ignoreHideSetting = false,
    }) async {
      final useTrackOnly =
          userPickedTrackOnly || pickedSource!.enforceTrackOnly;
      if (useTrackOnly &&
          (!settingsProvider.hideTrackOnlyWarning || ignoreHideSetting)) {
        final NavigatorState? navigator = globalNavigatorKey.currentState;
        if (navigator == null || !navigator.mounted) return false;
        final values = await showDialog(
          context: navigator.context,
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
      // No confirmation needed unless the version comes from the release date;
      // return true (proceed) without touching the navigator in the common case.
      if (getVersionStringSource(additionalSettings) !=
          versionStringSourceReleaseDate) {
        return true;
      }
      final NavigatorState? navigator = globalNavigatorKey.currentState;
      if (navigator == null || !navigator.mounted) return false;
      return await showDialog(
            context: navigator.context,
            builder: (BuildContext ctx) {
              return GeneratedFormModal(
                title: tr('releaseDateAsVersion'),
                items: const [],
                message: tr('releaseDateAsVersionExplanation'),
              );
            },
          ) !=
          null;
    }

    Future<_PackageIdDetectionChoice?>
    getPackageIdDetectionConfirmation() async {
      final NavigatorState? navigator = globalNavigatorKey.currentState;
      if (navigator == null || !navigator.mounted) return null;
      return showDialog<_PackageIdDetectionChoice>(
        context: navigator.context,
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
              FilledButton(
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
                  // Tonal (medium emphasis), not a full FilledButton: this
                  // proceeds over an insecure http:// connection, so it gets a
                  // clear hierarchy without strongly pushing the risky action.
                  FilledButton.tonal(
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
                false,
                allowUserInteraction: true,
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
              final downloadedArtifact = await appsProvider.downloadApp(
                app,
                allowUserInteraction: true,
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
          if (!mounted) return;
          if (useLargeScreenLayout && homeState != null && homeState.mounted) {
            final VoidCallback? onEmbeddedAddCompleted =
                widget._onEmbeddedAddCompleted;
            _resetUrlModeInput();
            onEmbeddedAddCompleted?.call();
            unawaited(homeState.switchToAppsTabAndOpenApp(app.id));
          } else {
            final NavigatorState? navigator = globalNavigatorKey.currentState;
            if (navigator != null && navigator.mounted) {
              unawaited(
                navigator.push(
                  heroFriendlyAppPageRoute((_) => AppPage(appId: app!.id)),
                ),
              );
            }
          }
        }
      } catch (e) {
        showError(e);
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

    Future<void> addSelectedSearchResults() async {
      final List<String> selectedUrls = _searchResults.keys
          .where(_searchSelectedResultUrls.contains)
          .toList();
      if (selectedUrls.isEmpty) return;

      bool saveCompleted = false;
      final bool embeddedDetail = widget._embeddedDetail;
      final Future<void> Function()? onBatchSearchSaved =
          widget._onBatchSearchSaved;
      final NavigatorState navigator = Navigator.of(context);
      final ModalRoute<dynamic>? hostRoute = ModalRoute.of(context);
      setState(() {
        gettingAppInfo = true;
      });
      try {
        final String? sourceIdentifier =
            _searchResults[selectedUrls.first]?.key;
        final AppSource? sourceOverride = sourceIdentifier == null
            ? null
            : sourceProvider.getSource(
                selectedUrls.first,
                overrideSource: sourceIdentifier,
              );
        final List<List<String>> errors = await appsProvider.addAppsByURL(
          selectedUrls,
          sourceOverride: sourceOverride,
        );
        if (!context.mounted) return;
        saveCompleted = true;
        setState(() {
          _searchSelectedResultUrls.clear();
        });
        if (errors.isEmpty) {
          showMessage(
            tr(
              'importedX',
              args: [plural('apps', selectedUrls.length).toLowerCase()],
            ),
          );
        } else {
          // Show the error dialog if a navigator is available, but don't abort
          // the function if it isn't — the save already completed, so the
          // post-save cleanup (pop + onBatchSearchSaved) must still run.
          final NavigatorState? navigator = globalNavigatorKey.currentState;
          if (navigator != null && navigator.mounted) {
            await showDialog<void>(
              context: navigator.context,
              builder: (BuildContext dialogContext) {
                return ImportErrorDialog(
                  urlsLength: selectedUrls.length,
                  errors: errors,
                );
              },
            );
          }
        }
      } catch (error) {
        showError(error);
      } finally {
        if (mounted) {
          setState(() {
            gettingAppInfo = false;
          });
        }
      }
      if (saveCompleted) {
        if (!embeddedDetail &&
            navigator.mounted &&
            hostRoute?.isCurrent == true) {
          navigator.pop();
        }
        if (onBatchSearchSaved != null) {
          await onBatchSearchSaved();
        }
      }
    }

    VoidCallback? batchSearchAddAction() {
      if (doingSomething || _searchSelectedResultUrls.isEmpty) return null;
      return () {
        hapticSelection();
        unawaited(addSelectedSearchResults());
      };
    }

    Widget buildBottomActionFab() {
      final bool addsSearchResults =
          widget._searchAddsMultipleApps && _mode == _AddMode.search;
      return FloatingActionButton.extended(
        key: ValueKey<String>(
          addsSearchResults
              ? 'add-search-results-save-fab'
              : 'add-app-save-fab',
        ),
        heroTag: 'add-app-save-fab',
        onPressed: addsSearchResults ? batchSearchAddAction() : urlAddAction(),
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

    // ── URL mode widgets ───────────────────────────────────────────────

    // Bottom-right submit FAB for URL and batch-search flows.
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
                        ...sourceProvider.sourceTemplates
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

    final Set<String> searchSelectedStores = _getSearchSelectedStores();

    // ── Inline search runner ───────────────────────────────────────────

    Future<void> runInlineSearch({required AppsProvider appsProvider}) async {
      _searchSomeSourcesFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
      _searchResultFilterController.clear();

      final List<AppSource> selectedSources = sourceProvider.sourceTemplates
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
          _searchSelectedResultUrls.clear();
          _searchHasSearched = true;
          _byUrlOpenedFromSearchPick = false;
          _searchResultFilter = '';
          searching = false;
        });
        _scrollEmbeddedSearchResultsToFilter();
        return;
      }

      setState(() {
        searching = true;
        _byUrlOpenedFromSearchPick = false;
        _searchHasSearched = false;
        _searchResults = {};
        _searchSelectedResultUrls.clear();
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
                    showError(err);
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
        _scrollEmbeddedSearchResultsToFilter();
      } catch (e) {
        showError(e);
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
      final bool hasValidStoreSelection = widget._searchAddsMultipleApps
          ? searchSelectedStores.length == 1
          : searchSelectedStores.isNotEmpty;
      final bool searchDisabled =
          doingSomething ||
          searchQuery.trim().isEmpty ||
          !hasValidStoreSelection;
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
                        runInlineSearch(appsProvider: appsProvider);
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
                if (!searchDisabled) {
                  _searchSomeSourcesFocusNode.unfocus();
                  hapticSelection();
                  runInlineSearch(appsProvider: appsProvider);
                }
              },
              decoration:
                  appPageOutlinedInputDecoration(
                    context,
                    labelText: null,
                    hintText: tr('search'),
                    isDense: true,
                    borderRadius: 30,
                  ).copyWith(
                    suffixIcon: HelpHintIcon(
                      richMessage: _tooltipMessageWithBoldMarkdown(
                        tr(
                          widget._searchAddsMultipleApps
                              ? 'searchSourceAddAppsTooltip'
                              : 'searchSourcesAddAppTooltip',
                        ),
                      ),
                      icon: Icons.info_outline_rounded,
                      padding: EdgeInsets.zero,
                      showDuration: const Duration(seconds: 10),
                    ),
                  ),
            ),
          ),
          const SizedBox(width: 10),
          trailingSearch,
        ],
      );
    }

    Widget getSearchStoreChips() {
      final searchableSources = sourceProvider.sourceTemplates
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
          final Widget? avatar = source.hosts.isNotEmpty
              ? StoreSourceChipAvatar(host: source.hosts.first, size: 16)
              : null;
          final Widget label = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(source.name),
              if (selected) ...[
                const SizedBox(width: 4),
                const Icon(Icons.check_rounded, size: 14),
              ],
            ],
          );
          void updateSelection(bool value) {
            setState(() {
              if (widget._searchAddsMultipleApps) {
                searchSelectedStores.clear();
                if (value) {
                  searchSelectedStores.add(source.name);
                }
                _searchResults = {};
                _searchSelectedResultUrls.clear();
                _searchHasSearched = false;
                _searchResultFilter = '';
                _searchResultFilterController.clear();
              } else {
                if (value) {
                  searchSelectedStores.add(source.name);
                } else {
                  searchSelectedStores.remove(source.name);
                }
              }
            });
          }

          if (widget._searchAddsMultipleApps) {
            return ChoiceChip(
              avatar: avatar,
              showCheckmark: false,
              label: label,
              selected: selected,
              onSelected: updateSelection,
            );
          }
          return FilterChip(
            avatar: avatar,
            showCheckmark: false,
            label: label,
            selected: selected,
            onSelected: updateSelection,
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
            key: _searchResultFilterKey,
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
            final bool selected = _searchSelectedResultUrls.contains(
              displayTitle,
            );

            void updateResultSelection(bool value) {
              setState(() {
                if (value) {
                  _searchSelectedResultUrls.add(displayTitle);
                } else {
                  _searchSelectedResultUrls.remove(displayTitle);
                }
              });
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                selected: widget._searchAddsMultipleApps && selected,
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
                trailing: widget._searchAddsMultipleApps
                    ? SizedBox.square(
                        dimension: 28,
                        child: Checkbox(
                          value: selected,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: const VisualDensity(
                            horizontal: -4,
                            vertical: -4,
                          ),
                          onChanged: (value) {
                            updateResultSelection(value ?? false);
                          },
                        ),
                      )
                    : const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () {
                  if (widget._searchAddsMultipleApps) {
                    updateResultSelection(!selected);
                    return;
                  }
                  // Fill URL mode with selected result and switch to it
                  clearInputFocus();
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

    final Widget flowScaffold = Scaffold(
      // Don't let the keyboard resize the body (see the apps-list Scaffold): the
      // per-frame resize repaint forces the app bar's progressive-blur
      // BackdropFilter to re-rasterize every frame and stutters the keyboard
      // slide. The URL / search field is at the top, so it stays visible.
      resizeToAvoidBottomInset: false,
      backgroundColor:
          widget._embeddedDetail && settingsProvider.useGradientBackground
          ? Colors.transparent
          : addScheme.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (settingsProvider.useGradientBackground) buildGradientBackground(),
          CustomScrollView(
            scrollCacheExtent: const ScrollCacheExtent.pixels(1600),
            key: PageStorageKey<String>(
              'add-app-flow-${widget._initialMode.name}-'
              '${widget._searchAddsMultipleApps}-scroll',
            ),
            slivers: <Widget>[
              if (!widget._embeddedDetail)
                CustomAppBar(
                  title: isInlineLauncherFlow
                      ? tr('addApp')
                      : _mode == _AddMode.byUrl
                      ? tr('addAppUrl')
                      : tr(
                          widget._searchAddsMultipleApps
                              ? 'searchSourceAddApps'
                              : 'searchSourcesAddApp',
                        ),
                  searchWidget: isInlineLauncherFlow
                      ? null
                      : const SizedBox.shrink(),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () {
                      unawaited(_requestFlowPop());
                    },
                  ),
                  matchGradientBackground:
                      settingsProvider.useGradientBackground,
                ),
              SliverSafeArea(
                top: widget._embeddedDetail,
                bottom: false,
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      isInlineLauncherFlow ? 16 : 12,
                      8,
                      isInlineLauncherFlow ? 16 : 12,
                      16,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isInlineLauncherFlow ? 720 : 840,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          layoutBuilder: (currentChild, previousChildren) {
                            return Stack(
                              alignment: Alignment.topCenter,
                              children: <Widget>[
                                ...previousChildren,
                                ?currentChild,
                              ],
                            );
                          },
                          child: KeyedSubtree(
                            key: ValueKey(_mode),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_mode == _AddMode.byUrl) ...[
                                  const SizedBox(height: 8),
                                  _buildAppSourceUrlField(
                                    context: context,
                                    submitDisabled: urlAddDisabled(),
                                    matchLauncherButton: isInlineLauncherFlow,
                                    onSubmit: () {
                                      unawaited(addApp());
                                    },
                                  ),
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
                                  if (pickedSource != null)
                                    getAdditionalOptsCol(),
                                ],
                                if (_mode == _AddMode.search) ...[
                                  const SizedBox(height: 8),
                                  getSearchBarRow(),
                                  const SizedBox(height: 12),
                                  Text(
                                    widget._searchAddsMultipleApps
                                        ? tr(
                                            'selectX',
                                            args: [tr('source').toLowerCase()],
                                          )
                                        : tr('storesToSearch'),
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

    if (widget._embeddedDetail) {
      return flowScaffold;
    }

    return PopScope(
      canPop:
          widget._initialMode != _AddMode.launcher &&
          !_byUrlOpenedFromSearchPick &&
          !_hasUnsavedFlowInput,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) unawaited(_requestFlowPop());
      },
      child: flowScaffold,
    );
  }

  /// Small icon to indicate which source a search result came from.
  Widget _searchSourceIcon(String sourceName) {
    final String? assetPath = storeSourceAssetPathForClassName(sourceName);
    if (assetPath == null) return const Icon(Icons.store_rounded, size: 20);
    return StoreSourceIconImage(assetPath: assetPath, size: 20);
  }
}
