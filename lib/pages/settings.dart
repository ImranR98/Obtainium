import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data' show ByteData, Endian, Uint8List;

import 'package:android_package_manager/android_package_manager.dart'
    show PackageInfo;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:obtainium/app_distribution.dart';
import 'package:obtainium/layout_breakpoints.dart';
import 'package:obtainium/widgets/help_hint_icon.dart';
import 'package:obtainium/components/app_bottom_sheet.dart';
import 'package:obtainium/components/app_dropdown_field.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/themes_settings_section.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/components/tv_slider_wrapper.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/app_sources/gitlab.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/external_install_bridge.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/providers/virustotal_provider.dart';
import 'package:obtainium/theme.dart';
import 'package:obtainium/theme/app_dialog_theme.dart';
import 'package:obtainium/theme/app_form_field_styles.dart';
import 'package:obtainium/theme/app_theme_accent.dart';
import 'package:obtainium/theme/app_segmented_button_theme.dart';
import 'package:obtainium/theme/m3e_expressive_list.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shizuku_apk_installer/shizuku_apk_installer.dart';
import 'package:url_launcher/url_launcher_string.dart';

IconData _swipeActionIcon(SwipeAction action) => switch (action) {
  SwipeAction.update => Icons.system_update_alt_rounded,
  SwipeAction.pin => Icons.push_pin_rounded,
  SwipeAction.appOptions => Icons.tune_rounded,
  SwipeAction.delete => Icons.delete_rounded,
  SwipeAction.open => Icons.open_in_new_rounded,
  SwipeAction.appInfo => Icons.info_rounded,
  SwipeAction.edit => Icons.edit_rounded,
  SwipeAction.none => Icons.block_rounded,
};

String get _aboutObtainXWebsiteUrl => tr('aboutObtainXWebsiteUrl');
String get _aboutObtainXPrivacyUrl => tr('aboutObtainXPrivacyUrl');
String get _aboutObtainXTermsUrl => tr('aboutObtainXTermsUrl');
String get _aboutRememberUrl => tr('aboutRememberUrl');
String get _aboutFilePipeUrl => tr('aboutFilePipeUrl');
const String _aboutAuthorUrl = 'https://github.com/bikram-agarwal';
const String _aboutWikiUrl = 'https://wiki.obtainium.imranr.dev/';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => SettingsPageState();
}

/// One entry in the large-screen settings master list (and its detail pane).
class _SettingsCategory {
  const _SettingsCategory({
    required this.key,
    required this.title,
    required this.icon,
    required this.widget,
  });

  final String key;
  final String title;
  final IconData icon;
  final Widget widget;
}

class SettingsPageState extends State<SettingsPage> {
  final GlobalKey<_SourceSpecificSectionState> _sourceSpecificKey =
      GlobalKey<_SourceSpecificSectionState>();
  final GlobalKey<_IntegrationsSectionState> _integrationsKey =
      GlobalKey<_IntegrationsSectionState>();
  late final Future<AndroidDeviceInfo> _androidInfo =
      DeviceInfoPlugin().androidInfo;
  final ValueNotifier<Map<String, bool>> _expandedSettingsSections =
      ValueNotifier<Map<String, bool>>(<String, bool>{});
  bool _expandedSettingsSectionsLoaded = false;

  String? _selectedCategory;

  // ── Scaffold-level subscriptions ────────────────────────────────────
  // We deliberately avoid `context.watch<SettingsProvider>()`: that would
  // rebuild this whole widget tree on every single setter change. Instead
  // we subscribe only to the values needed for the Scaffold chrome, and
  // let each section widget subscribe to its own narrow set.
  static int _scaffoldSettingsHash(SettingsProvider sp) => Object.hash(
    sp.prefs,
    sp.useGradientBackground,
    sp.progressiveBlurEnabled,
    sp.cardCornerScale,
    sp.alwaysUsePhoneLayout,
  );

  static const List<String> _settingsSectionKeys = [
    'updates',
    'integrations',
    'warnings',
    'sourceSpecific',
    'themes',
    'appearance',
    'interaction',
    'categories',
  ];

  static const List<int> updateIntervalNodes = [
    15,
    30,
    60,
    120,
    180,
    360,
    720,
    1440,
    4320,
    10080,
    20160,
    43200,
  ];

  @override
  void dispose() {
    _expandedSettingsSections.dispose();
    super.dispose();
  }

  Future<bool> confirmDiscardUnsavedChanges() async {
    final sourceSpecificState = _sourceSpecificKey.currentState;
    final integrationsState = _integrationsKey.currentState;
    final bool hasUnsavedChanges =
        (sourceSpecificState != null &&
            (sourceSpecificState.isGithubDirty ||
                sourceSpecificState.isGitlabDirty)) ||
        (integrationsState?.isVirusTotalApiKeyDirty ?? false);
    if (hasUnsavedChanges) {
      final bool? discard = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text(tr('discardUnsavedChangesQuestion')),
            contentPadding: appDialogContentPadding,
            content: Text(tr('discardUnsavedPATChangesExplanation')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                child: Text(tr('discard')),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(tr('stayHere')),
              ),
            ],
          );
        },
      );
      if (discard == true) {
        sourceSpecificState?.discardChanges();
        integrationsState?.discardChanges();
        return true;
      }
      return false;
    }
    return true;
  }

  void _loadExpandedSettingsSections(SettingsProvider sp) {
    if (_expandedSettingsSectionsLoaded || sp.prefs == null) return;
    _expandedSettingsSections.value = <String, bool>{
      for (final key in _settingsSectionKeys)
        key: sp.prefs?.getBool('settingsSection_$key') ?? true,
    };
    _expandedSettingsSectionsLoaded = true;
  }

  static bool _sectionExpanded(Map<String, bool> expandedState, String key) {
    return expandedState[key] ?? true;
  }

  @override
  Widget build(BuildContext context) {
    // Narrow watch: register a dependency only on the values needed for the
    // Scaffold chrome (via context.select) so this page rebuilds when those
    // change, without rebuilding on every unrelated settings change. The hash
    // value itself is unused — the select call's dependency is the point.
    context.select<SettingsProvider, int>(_scaffoldSettingsHash);
    final SettingsProvider sp = context.read<SettingsProvider>();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final SourceProvider sourceProvider = SourceProvider();

    // One-time initialization guard.
    if (sp.prefs == null) sp.initializeSettings();
    _loadExpandedSettingsSections(sp);

    void setSectionExpanded(String key, bool value) {
      sp.prefs?.setBool('settingsSection_$key', value);
      _expandedSettingsSections.value = <String, bool>{
        ..._expandedSettingsSections.value,
        key: value,
      };
    }

    void setAllSettingsSectionsExpanded(bool value) {
      for (final sectionKey in _settingsSectionKeys) {
        sp.prefs?.setBool('settingsSection_$sectionKey', value);
      }
      _expandedSettingsSections.value = <String, bool>{
        for (final sectionKey in _settingsSectionKeys) sectionKey: value,
      };
    }

    final List<String> visibleSettingsSectionKeys = [
      'updates',
      'integrations',
      'warnings',
      if (sourceProvider.sourceTemplates.any(
        (source) => source.sourceConfigSettingFormItems.isNotEmpty,
      ))
        'sourceSpecific',
      'themes',
      'appearance',
      'interaction',
      'categories',
    ];
    // Each section is wrapped in a RepaintBoundary so it composites to its own
    // cached layer. The settings body is one eager Column inside a single
    // SliverToBoxAdapter (unlike the apps list, which is a lazy ListView.builder
    // that gets per-row RepaintBoundaries for free). Without boundaries the whole
    // visible tree re-rasterizes every scroll frame — and because the scroll
    // offset lands on sub-pixels, text/border anti-aliasing differs frame to
    // frame, which reads as a shimmer/shiver while scrolling (made worse by the
    // app bar's BackdropFilter, which forces the content beneath it to re-raster
    // every frame). Cached layers just translate rigidly instead.
    Widget settingsCard(List<Widget> children) {
      return RepaintBoundary(
        child: M3eExpressiveSettingsCard(colorScheme: cs, items: children),
      );
    }

    Widget collapsibleCard(String key, Widget child) {
      // RepaintBoundary: see settingsCard above for why each section is its own
      // cached layer.
      return RepaintBoundary(
        child: ValueListenableBuilder<Map<String, bool>>(
          valueListenable: _expandedSettingsSections,
          child: child,
          builder: (context, expandedState, child) {
            final bool expanded = _sectionExpanded(expandedState, key);
            return AnimatedPadding(
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeInOutCubicEmphasized,
              padding: EdgeInsets.only(
                bottom: expanded ? SettingsProvider.collapsedHeaderGap : 0,
              ),
              child: ClipRect(
                clipper: _SettingsSectionShadowClipper(expanded: expanded),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeInOutCubicEmphasized,
                  alignment: Alignment.topCenter,
                  heightFactor: expanded ? 1.0 : 0.0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOutCubicEmphasized,
                    opacity: expanded ? 1.0 : 0.0,
                    child: child!,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    Widget sectionHeader(String title, IconData icon, String key) {
      const Duration headerTransitionDuration = Duration(milliseconds: 300);
      const Curve headerTransitionCurve = Curves.easeInOutCubicEmphasized;
      final Color collapsedHeaderColor = m3eCollapsedGroupHeaderFill(cs);
      final Color collapsedHeaderContentColor = cs.onSecondaryContainer;

      // RepaintBoundary: see settingsCard above for why each section is its own
      // cached layer.
      return RepaintBoundary(
        child: ValueListenableBuilder<Map<String, bool>>(
          valueListenable: _expandedSettingsSections,
          builder: (context, expandedState, _) {
            final bool expanded = _sectionExpanded(expandedState, key);
            final Color headerContentColor = expanded
                ? cs.primary
                : collapsedHeaderContentColor;
            final BorderSide outlineSide = expanded
                ? BorderSide.none
                : m3ePureBlackOutlineSide(cs, alpha: 0.16);

            final double collapsedRadius =
                SettingsProvider.cardCornerRadiusForScale(
                  SettingsProvider.baseCollapsedHeaderRadius,
                  context.select<SettingsProvider, double>(
                    (s) => s.cardCornerScale,
                  ),
                );

            return Padding(
              padding: const EdgeInsets.only(
                top: SettingsProvider.collapsedHeaderGap,
              ),
              child: AnimatedContainer(
                duration: headerTransitionDuration,
                curve: headerTransitionCurve,
                decoration: BoxDecoration(
                  color: expanded ? Colors.transparent : collapsedHeaderColor,
                  borderRadius: BorderRadius.circular(
                    expanded ? 8 : collapsedRadius,
                  ),
                  border: outlineSide == BorderSide.none
                      ? null
                      : Border.fromBorderSide(outlineSide),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => setSectionExpanded(key, !expanded),
                    borderRadius: BorderRadius.circular(
                      expanded ? 8 : collapsedRadius,
                    ),
                    splashFactory: NoSplash.splashFactory,
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    child: SizedBox(
                      height: SettingsProvider.collapsedHeaderHeight,
                      child: AnimatedPadding(
                        duration: headerTransitionDuration,
                        curve: headerTransitionCurve,
                        padding: EdgeInsets.symmetric(
                          horizontal: expanded ? 4 : 12,
                          vertical: expanded ? 4 : 8,
                        ),
                        child: Center(
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: headerTransitionDuration,
                                curve: headerTransitionCurve,
                                width: expanded ? 20 : 30,
                                height: expanded ? 20 : 30,
                                decoration: BoxDecoration(
                                  color: expanded
                                      ? Colors.transparent
                                      : cs.primary.withValues(alpha: 0.16),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  icon,
                                  color: headerContentColor,
                                  size: expanded ? 16 : 17,
                                ),
                              ),
                              SizedBox(width: expanded ? 8 : 10),
                              Expanded(
                                child: AnimatedDefaultTextStyle(
                                  duration: headerTransitionDuration,
                                  curve: headerTransitionCurve,
                                  style: TextStyle(
                                    fontFamily: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge?.fontFamily,
                                    fontWeight: expanded
                                        ? FontWeight.w600
                                        : FontWeight.w700,
                                    color: headerContentColor,
                                    fontSize: 13,
                                    letterSpacing: expanded ? 0 : 0.1,
                                    decoration: TextDecoration.none,
                                  ),
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              AnimatedContainer(
                                duration: headerTransitionDuration,
                                curve: headerTransitionCurve,
                                width: expanded ? 20 : 32,
                                height: expanded ? 20 : 32,
                                decoration: BoxDecoration(
                                  color: expanded
                                      ? Colors.transparent
                                      : cs.surfaceContainerHighest,
                                  shape: BoxShape.circle,
                                ),
                                child: AnimatedRotation(
                                  turns: expanded ? 0.25 : 0,
                                  duration: headerTransitionDuration,
                                  curve: headerTransitionCurve,
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    color: expanded
                                        ? cs.primary
                                        : cs.onSurfaceVariant,
                                    size: expanded ? 18 : 20,
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
              ),
            );
          },
        ),
      );
    }

    Widget aboutSectionHeader() {
      // RepaintBoundary: see settingsCard above for why each section is its own
      // cached layer.
      return RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
            child: Row(
              children: [
                Icon(Icons.info_rounded, color: cs.primary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('about'),
                    style: TextStyle(
                      fontFamily: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.fontFamily,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                      fontSize: 13,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _openLogsDialog(context),
                  icon: const Icon(Icons.bug_report_outlined),
                  tooltip: tr('appLogs'),
                  color: cs.primary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool isLargeScreen =
        screenWidth >= kLargeScreenWidthBreakpoint && !sp.alwaysUsePhoneLayout;

    final List<_SettingsCategory> categoriesList = [
      _SettingsCategory(
        key: 'updates',
        title: tr('updates'),
        icon: Icons.update_rounded,
        widget: _UpdatesSection(cs: cs, androidInfo: _androidInfo),
      ),
      _SettingsCategory(
        key: 'integrations',
        title: tr('integrations'),
        icon: Icons.extension_rounded,
        widget: _IntegrationsSection(key: _integrationsKey),
      ),
      _SettingsCategory(
        key: 'warnings',
        title: tr('warnings'),
        icon: Icons.warning_rounded,
        widget: const _WarningsSection(),
      ),
      if (sourceProvider.sourceTemplates.any(
        (s) => s.sourceConfigSettingFormItems.isNotEmpty,
      ))
        _SettingsCategory(
          key: 'sourceSpecific',
          title: tr('sourceSpecific'),
          icon: Icons.dns_rounded,
          widget: _SourceSpecificSection(key: _sourceSpecificKey),
        ),
      _SettingsCategory(
        key: 'themes',
        title: tr('settingsThemesSection'),
        icon: Icons.palette_rounded,
        widget: _ThemesSettingsSection(androidInfoFuture: _androidInfo),
      ),
      _SettingsCategory(
        key: 'appearance',
        title: tr('appearance'),
        icon: Icons.tune_rounded,
        widget: const _AppearanceSection(),
      ),
      _SettingsCategory(
        key: 'interaction',
        title: tr('interaction'),
        icon: Icons.touch_app_rounded,
        widget: const _InteractionSection(),
      ),
      _SettingsCategory(
        key: 'categories',
        title: tr('categories'),
        icon: Icons.label_rounded,
        widget: const _CategoriesSection(),
      ),
      _SettingsCategory(
        key: 'about',
        title: tr('about'),
        icon: Icons.info_rounded,
        widget: settingsCard([AboutSectionContent(colorScheme: cs)]),
      ),
    ];

    Widget buildCategoryTile(_SettingsCategory categoryObj) {
      final String key = categoryObj.key;
      final String title = categoryObj.title;
      final IconData icon = categoryObj.icon;
      final bool selected = _selectedCategory == key;

      final Color containerColor = selected
          ? cs.secondaryContainer
          : m3eCollapsedGroupHeaderFill(cs);
      final Color contentColor = cs.onSecondaryContainer;

      final Color iconBoxColor = cs.primary.withValues(alpha: 0.16);

      final Color iconColor = cs.onSecondaryContainer;

      final Color chevronColor = cs.onSurfaceVariant;

      final double categoryTileRadius = sp.cardCornerRadiusFor(
        SettingsProvider.baseCollapsedHeaderRadius,
      );

      return Padding(
        padding: const EdgeInsets.only(
          bottom: SettingsProvider.collapsedHeaderGap,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(categoryTileRadius),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () async {
                if (await confirmDiscardUnsavedChanges()) {
                  setState(() {
                    _selectedCategory = key;
                  });
                }
              },
              borderRadius: BorderRadius.circular(categoryTileRadius),
              child: SizedBox(
                height: SettingsProvider.collapsedHeaderHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
                            fontFamily: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.fontFamily,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: contentColor,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: chevronColor,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (isLargeScreen) {
      _selectedCategory ??= categoriesList.first.key;
      if (!categoriesList.any((c) => c.key == _selectedCategory)) {
        _selectedCategory = categoriesList.first.key;
      }
      final selectedCategoryObj = categoriesList.firstWhere(
        (c) => c.key == _selectedCategory,
        orElse: () => categoriesList.first,
      );

      // Full-bleed page background painted *behind* both panes. The master
      // pane's app-bar progressive-blur BackdropFilter samples its layer's
      // backdrop, and in this Row the detail pane is painted after the master
      // - so without a background here, the strip just past the master's right
      // edge is transparent-black when the blur rasterizes, and the blur pulls
      // that darkness into the right end of the master title bar (the two-panel
      // "dark smudge"). Painting an opaque page background first gives the blur
      // real pixels to sample at the seam. See custom_app_bar.dart's _buildBlur.
      return Theme(
        data: Theme.of(context).copyWith(
          listTileTheme: const ListTileThemeData(
            contentPadding: kM3eSettingsListTileContentPadding,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: sp.useGradientBackground
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: cs.schemePageBackgroundGradient,
                      ),
                    )
                  : ColoredBox(color: cs.surface),
            ),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      scrollbarTheme: const ScrollbarThemeData(
                        thumbColor: WidgetStatePropertyAll(Colors.transparent),
                        trackColor: WidgetStatePropertyAll(Colors.transparent),
                        trackBorderColor: WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                        minThumbLength: 0,
                      ),
                    ),
                    child: Scaffold(
                      backgroundColor: sp.useGradientBackground
                          ? Colors.transparent
                          : cs.surface,
                      body: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (sp.useGradientBackground)
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: cs.schemePageBackgroundGradient,
                                ),
                              ),
                            ),
                          ScrollConfiguration(
                            behavior: const _NoScrollbarBehavior(),
                            child: CustomScrollView(
                              key: const PageStorageKey<String>(
                                'settings-master-scroll',
                              ),
                              slivers: [
                                CustomAppBar(
                                  title: tr('settings'),
                                  matchGradientBackground:
                                      sp.useGradientBackground,
                                  progressiveBlurOverlayColor: isLargeScreen
                                      ? cs.surface.withValues(alpha: 0.72)
                                      : null,
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.all(16),
                                  sliver: SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) => buildCategoryTile(
                                        categoriesList[index],
                                      ),
                                      childCount: categoriesList.length,
                                    ),
                                  ),
                                ),
                                SliverToBoxAdapter(
                                  child: SizedBox(
                                    height:
                                        MediaQuery.paddingOf(context).bottom +
                                        24.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: cs.outlineVariant.withAlpha(50),
                ),
                Expanded(
                  flex: 4,
                  child: Scaffold(
                    backgroundColor: sp.useGradientBackground
                        ? Colors.transparent
                        : cs.surface,
                    body: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (sp.useGradientBackground)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: cs.schemePageBackgroundGradient,
                              ),
                            ),
                          ),
                        CustomScrollView(
                          key: ValueKey(
                            'settings-detail-${selectedCategoryObj.key}',
                          ),
                          slivers: [
                            // No top app bar in the detail pane: it carried no
                            // title, so it only added a blank frosted strip. The
                            // status-bar inset is preserved with SliverSafeArea so
                            // the content doesn't slide under the system bar.
                            SliverSafeArea(
                              top: true,
                              bottom: false,
                              sliver: SliverPadding(
                                padding: const EdgeInsets.all(16),
                                sliver: SliverToBoxAdapter(
                                  child: selectedCategoryObj.widget,
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height:
                                    MediaQuery.paddingOf(context).bottom +
                                    (!isLargeScreen ? 88.0 : 24.0),
                              ),
                            ),
                          ],
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

    return Theme(
      data: Theme.of(context).copyWith(
        listTileTheme: const ListTileThemeData(
          contentPadding: kM3eSettingsListTileContentPadding,
        ),
      ),
      child: Scaffold(
        backgroundColor: cs.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (sp.useGradientBackground)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: cs.schemePageBackgroundGradient,
                  ),
                ),
              ),
            CustomScrollView(
              scrollCacheExtent: const ScrollCacheExtent.pixels(1600),
              key: const PageStorageKey<String>('settings-tab-scroll'),
              slivers: <Widget>[
                CustomAppBar(
                  title: tr('settings'),
                  matchGradientBackground: sp.useGradientBackground,
                  actions: [
                    ValueListenableBuilder<Map<String, bool>>(
                      valueListenable: _expandedSettingsSections,
                      builder: (context, expandedState, _) {
                        final bool allSettingsSectionsExpanded =
                            visibleSettingsSectionKeys.every(
                              (key) => _sectionExpanded(expandedState, key),
                            );
                        return IconButton(
                          tooltip: allSettingsSectionsExpanded
                              ? tr('collapseAll')
                              : tr('expandAll'),
                          icon: Icon(
                            allSettingsSectionsExpanded
                                ? Icons.unfold_less_rounded
                                : Icons.unfold_more_rounded,
                          ),
                          onPressed: () {
                            setAllSettingsSectionsExpanded(
                              !allSettingsSectionsExpanded,
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: sp.prefs == null
                        ? const SizedBox()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Updates ───────────────────────────────────
                              sectionHeader(
                                tr('updates'),
                                Icons.update_rounded,
                                'updates',
                              ),
                              collapsibleCard(
                                'updates',
                                _UpdatesSection(
                                  cs: cs,
                                  androidInfo: _androidInfo,
                                ),
                              ),
                              // ── Integrations ─────────────────────────────
                              sectionHeader(
                                tr('integrations'),
                                Icons.extension_rounded,
                                'integrations',
                              ),
                              collapsibleCard(
                                'integrations',
                                _IntegrationsSection(key: _integrationsKey),
                              ),
                              // ── Warnings ─────────────────────────────────
                              sectionHeader(
                                tr('warnings'),
                                Icons.warning_rounded,
                                'warnings',
                              ),
                              collapsibleCard(
                                'warnings',
                                const _WarningsSection(),
                              ),
                              // ── Source-specific ───────────────────────────
                              if (sourceProvider.sourceTemplates.any(
                                (s) =>
                                    s.sourceConfigSettingFormItems.isNotEmpty,
                              )) ...[
                                sectionHeader(
                                  tr('sourceSpecific'),
                                  Icons.dns_rounded,
                                  'sourceSpecific',
                                ),
                                collapsibleCard(
                                  'sourceSpecific',
                                  _SourceSpecificSection(
                                    key: _sourceSpecificKey,
                                  ),
                                ),
                              ],
                              // ── Themes ───────────────────────────────────
                              sectionHeader(
                                tr('settingsThemesSection'),
                                Icons.palette_rounded,
                                'themes',
                              ),
                              collapsibleCard(
                                'themes',
                                _ThemesSettingsSection(
                                  androidInfoFuture: _androidInfo,
                                ),
                              ),
                              // ── Appearance ────────────────────────────────
                              sectionHeader(
                                tr('appearance'),
                                Icons.tune_rounded,
                                'appearance',
                              ),
                              collapsibleCard(
                                'appearance',
                                const _AppearanceSection(),
                              ),
                              // ── Interaction ──────────────────────────────
                              sectionHeader(
                                tr('interaction'),
                                Icons.touch_app_rounded,
                                'interaction',
                              ),
                              collapsibleCard(
                                'interaction',
                                const _InteractionSection(),
                              ),
                              // ── Categories ───────────────────────────────
                              sectionHeader(
                                tr('categories'),
                                Icons.label_rounded,
                                'categories',
                              ),
                              collapsibleCard(
                                'categories',
                                const _CategoriesSection(),
                              ),
                              aboutSectionHeader(),
                              settingsCard([
                                AboutSectionContent(colorScheme: cs),
                              ]),
                            ],
                          ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height:
                        MediaQuery.paddingOf(context).bottom +
                        (!isLargeScreen ? 88.0 : 24.0),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _SettingsSectionShadowClipper extends CustomClipper<Rect> {
  const _SettingsSectionShadowClipper({required this.expanded});

  final bool expanded;

  static const double shadowPaintAllowance = 32;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(
      -shadowPaintAllowance,
      -shadowPaintAllowance,
      size.width + shadowPaintAllowance,
      size.height + (expanded ? shadowPaintAllowance : 0),
    );
  }

  @override
  bool shouldReclip(_SettingsSectionShadowClipper oldClipper) {
    return oldClipper.expanded != expanded;
  }
}

// ── Section widgets ─────────────────────────────────────────────────────

/// Updates section with its own narrow provider subscription.
/// Only rebuilds when update-related settings change.
class _UpdatesSection extends StatelessWidget {
  const _UpdatesSection({required this.cs, required this.androidInfo});

  final ColorScheme cs;
  final Future<AndroidDeviceInfo> androidInfo;

  static int _updateSettingsHash(SettingsProvider sp) => Object.hash(
    sp.updateInterval,
    sp.updateIntervalSliderVal,
    sp.useFGService,
    sp.enableBackgroundUpdates,
    sp.bgUpdatesOnWiFiOnly,
    sp.bgUpdatesWhileChargingOnly,
    sp.checkOnStart,
    sp.checkUpdateOnDetailPage,
    sp.onlyCheckInstalledOrTrackOnlyApps,
    sp.removeOnExternalUninstall,
    sp.parallelDownloads,
    sp.includePrereleasesByDefault,
  );

  @override
  Widget build(BuildContext context) {
    // Narrow watch — only rebuild when update-related settings change.
    context.select<SettingsProvider, int>(_updateSettingsHash);
    final SettingsProvider sp = context.read<SettingsProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // First item in the Updates section, deliberately NOT inside the
        // settings card: a manual trigger for the full background update
        // worker (check → download → install-if-enabled → notify, across all
        // eligible apps), as opposed to pull-to-refresh's foreground check of
        // only the currently visible list.
        const _RunBgUpdateCheckNowButton(),
        FutureBuilder<AndroidDeviceInfo>(
          future: androidInfo,
          builder: (context, snapshot) {
            return _buildSettingsCardContent(context, sp, cs, snapshot);
          },
        ),
      ],
    );
  }

  Widget _buildSettingsCardContent(
    BuildContext context,
    SettingsProvider sp,
    ColorScheme cs,
    AsyncSnapshot<AndroidDeviceInfo> snapshot,
  ) {
    final List<Widget> rows = <Widget>[_UpdateIntervalSlider(cs: cs)];
    final bool showBgControls =
        (sp.updateInterval > 0) &&
        (((snapshot.data?.version.sdkInt ?? 0) >= 30) || sp.useShizuku);
    if (showBgControls) {
      rows
        ..add(
          ListTile(
            title: Text(tr('foregroundServiceForUpdateChecking')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HelpHintIcon(
                  message: tr('foregroundServiceReliabilityNote'),
                  padding: EdgeInsets.zero,
                ),
                Switch(
                  value: sp.useFGService,
                  onChanged: (bool value) => sp.useFGService = value,
                ),
              ],
            ),
            onTap: () => sp.useFGService = !sp.useFGService,
          ),
        )
        ..add(
          ListTile(
            title: Text(tr('enableBackgroundUpdates')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HelpHintIcon(
                  message:
                      '${tr('backgroundUpdateReqsExplanation')}\n\n${tr('backgroundUpdateLimitsExplanation')}',
                  padding: EdgeInsets.zero,
                ),
                Switch(
                  value: sp.enableBackgroundUpdates,
                  onChanged: (bool value) => sp.enableBackgroundUpdates = value,
                ),
              ],
            ),
            onTap: () =>
                sp.enableBackgroundUpdates = !sp.enableBackgroundUpdates,
          ),
        );
      if (sp.enableBackgroundUpdates) {
        rows
          ..add(
            SwitchListTile(
              title: Text(tr('bgUpdatesOnWiFiOnly')),
              value: sp.bgUpdatesOnWiFiOnly,
              onChanged: (bool value) => sp.bgUpdatesOnWiFiOnly = value,
            ),
          )
          ..add(
            SwitchListTile(
              title: Text(tr('bgUpdatesWhileChargingOnly')),
              value: sp.bgUpdatesWhileChargingOnly,
              onChanged: (bool value) => sp.bgUpdatesWhileChargingOnly = value,
            ),
          );
      }
    }
    rows.addAll(<Widget>[
      SwitchListTile(
        title: Text(tr('checkOnStart')),
        value: sp.checkOnStart,
        onChanged: (bool value) => sp.checkOnStart = value,
      ),
      SwitchListTile(
        title: Text(tr('checkUpdateOnDetailPage')),
        value: sp.checkUpdateOnDetailPage,
        onChanged: (bool value) => sp.checkUpdateOnDetailPage = value,
      ),
      SwitchListTile(
        title: Text(tr('includePrereleasesByDefault')),
        value: sp.includePrereleasesByDefault,
        onChanged: (bool value) => sp.includePrereleasesByDefault = value,
      ),
      SwitchListTile(
        title: Text(tr('onlyCheckInstalledOrTrackOnlyApps')),
        value: sp.onlyCheckInstalledOrTrackOnlyApps,
        onChanged: (bool value) => sp.onlyCheckInstalledOrTrackOnlyApps = value,
      ),
      SwitchListTile(
        title: Text(tr('removeOnExternalUninstall')),
        value: sp.removeOnExternalUninstall,
        onChanged: (bool value) => sp.removeOnExternalUninstall = value,
      ),
      SwitchListTile(
        title: Text(tr('parallelDownloads')),
        value: sp.parallelDownloads,
        onChanged: (bool value) => sp.parallelDownloads = value,
      ),
    ]);
    return M3eExpressiveSettingsCard(colorScheme: cs, items: rows);
  }
}

/// Manual trigger for the background update check, shown as the first item in
/// the Updates section (intentionally outside the settings card). Unlike
/// pull-to-refresh — a foreground check of the currently visible list — this
/// runs the actual background worker: check → download → install (when
/// enabled) → notifications, across all eligible apps ([forceAll]).
class _RunBgUpdateCheckNowButton extends StatefulWidget {
  const _RunBgUpdateCheckNowButton();

  @override
  State<_RunBgUpdateCheckNowButton> createState() =>
      _RunBgUpdateCheckNowButtonState();
}

class _RunBgUpdateCheckNowButtonState
    extends State<_RunBgUpdateCheckNowButton> {
  bool _isRunning = false;

  Future<void> _trigger() async {
    if (_isRunning) return;
    setState(() => _isRunning = true);
    // Read the provider before the async gap so we don't touch context after.
    final LogsProvider logs = context.read<LogsProvider>();
    await logs.add(
      'Manual background update check triggered from settings',
      level: LogLevel.info,
    );
    try {
      final String taskId = 'manual_${DateTime.now().millisecondsSinceEpoch}';
      await bgUpdateCheck(taskId, null, forceAll: true);
      await logs.add(
        'Manual background update check completed',
        level: LogLevel.info,
      );
    } catch (e) {
      unawaited(
        logs.add(
          'Manual background update check failed: $e',
          level: LogLevel.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // No horizontal inset: match the full width of the settings-card rows
      // below (they stretch edge-to-edge in the same Column). Only a small
      // bottom gap separates this action from the toggle group.
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.tonal(
          onPressed: _isRunning ? null : _trigger,
          // Match the row titles below (ListTile default = bodyLarge, ~16sp),
          // which are larger than the button's default labelLarge (~14sp).
          // Only textStyle is overridden; pill shape and tonal colors still
          // come from the theme's filledButtonTheme.
          style: FilledButton.styleFrom(
            textStyle: Theme.of(context).textTheme.bodyLarge,
          ),
          child: _isRunning
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: ExpressiveLoadingIndicator(),
                )
              : Text(tr('runBgCheckNow')),
        ),
      ),
    );
  }
}

/// Update-interval slider — a StatefulWidget so drag updates use local state.
/// The SettingsProvider is only written to when the user lifts their finger
/// (onChangeEnd), avoiding a notifyListeners → full-page rebuild on every
/// slider tick during drag.
class _UpdateIntervalSlider extends StatefulWidget {
  const _UpdateIntervalSlider({required this.cs});

  final ColorScheme cs;

  @override
  State<_UpdateIntervalSlider> createState() => _UpdateIntervalSliderState();
}

class _UpdateIntervalSliderState extends State<_UpdateIntervalSlider> {
  double? _dragValue;
  late final FocusNode _sliderFocusNode;

  @override
  void initState() {
    super.initState();
    _sliderFocusNode = FocusNode(canRequestFocus: false, skipTraversal: true);
  }

  @override
  void dispose() {
    _sliderFocusNode.dispose();
    super.dispose();
  }

  int _intervalForVal(double val) {
    final int index = val.round().clamp(
      0,
      SettingsPageState.updateIntervalNodes.length,
    );
    if (index == 0) {
      return 0;
    }
    return SettingsPageState.updateIntervalNodes[index - 1];
  }

  String _labelForVal(double val) {
    final int minutes = _intervalForVal(val);
    if (minutes == 0) {
      return tr('neverManualOnly');
    }
    if (minutes < 60) {
      return plural('minute', minutes);
    } else if (minutes < 24 * 60) {
      return plural('hour', minutes ~/ 60);
    } else {
      return plural('day', minutes ~/ (24 * 60));
    }
  }

  @override
  Widget build(BuildContext context) {
    final double sliderVal =
        _dragValue ??
        context.select<SettingsProvider, double>(
          (s) => s.updateIntervalSliderVal,
        );
    final String label = _labelForVal(sliderVal);
    final isTV = context.read<SettingsProvider>().isTV;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kM3eSettingsCardHorizontalInset,
        8,
        kM3eSettingsCardHorizontalInset,
        8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.update_rounded, color: widget.cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(tr('bgUpdateCheckInterval'))),
                      Text(label),
                    ],
                  ),
                ),
                TVSliderWrapper(
                  value: sliderVal,
                  min: 0,
                  max: SettingsPageState.updateIntervalNodes.length.toDouble(),
                  divisions: SettingsPageState.updateIntervalNodes.length,
                  onChanged: (double value) {
                    setState(() => _dragValue = value);
                  },
                  onChangeEnd: (double value) {
                    final SettingsProvider sp = context
                        .read<SettingsProvider>();
                    sp.updateIntervalSliderVal = value;
                    sp.updateInterval = _intervalForVal(value);
                    setState(() => _dragValue = null);
                  },
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 16,
                      trackShape: const _GappedTrackShape(),
                      thumbShape: const _VerticalBarThumbShape(),
                      activeTickMarkColor: Theme.of(
                        context,
                      ).colorScheme.onPrimary,
                      inactiveTickMarkColor: Theme.of(
                        context,
                      ).colorScheme.primary,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      focusNode: isTV ? _sliderFocusNode : null,
                      value: sliderVal.clamp(
                        0,
                        SettingsPageState.updateIntervalNodes.length.toDouble(),
                      ),
                      max: SettingsPageState.updateIntervalNodes.length
                          .toDouble(),
                      divisions: SettingsPageState.updateIntervalNodes.length,
                      label: label,
                      onChanged: (double value) {
                        setState(() => _dragValue = value);
                      },
                      onChangeEnd: (double value) {
                        final SettingsProvider sp = context
                            .read<SettingsProvider>();
                        sp.updateIntervalSliderVal = value;
                        sp.updateInterval = _intervalForVal(value);
                        setState(() => _dragValue = null);
                      },
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

/// Source-specific settings section — reads/writes generic source config.
class _SourceSpecificSection extends StatefulWidget {
  const _SourceSpecificSection({super.key});

  @override
  State<_SourceSpecificSection> createState() => _SourceSpecificSectionState();
}

class _SourceSpecificSectionState extends State<_SourceSpecificSection> {
  late final TextEditingController _githubPatController;
  late final TextEditingController _hubProxyController;
  late final TextEditingController _gitlabPatController;
  bool _githubChecking = false;
  bool _gitlabChecking = false;

  bool get isGithubDirty {
    final String currentText = _githubPatController.text.trim();
    final SettingsProvider sp = context.read<SettingsProvider>();
    final String savedText = sp.getSettingString(GitHub.githubCredsKey) ?? '';
    return currentText != savedText;
  }

  bool get isGitlabDirty {
    final String currentText = _gitlabPatController.text.trim();
    final SettingsProvider sp = context.read<SettingsProvider>();
    final String savedText = sp.getSettingString('gitlab-creds') ?? '';
    return currentText != savedText;
  }

  void discardChanges() {
    final SettingsProvider sp = context.read<SettingsProvider>();
    _githubPatController.text =
        sp.getSettingString(GitHub.githubCredsKey) ?? '';
    _gitlabPatController.text = sp.getSettingString('gitlab-creds') ?? '';
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final SettingsProvider sp = context.read<SettingsProvider>();
    _githubPatController = TextEditingController(
      text: sp.getSettingString(GitHub.githubCredsKey) ?? '',
    );
    _hubProxyController = TextEditingController(
      text: sp.getSettingString(GitHub.githubReqPrefixKey) ?? '',
    );
    _gitlabPatController = TextEditingController(
      text: sp.getSettingString('gitlab-creds') ?? '',
    );
  }

  @override
  void dispose() {
    _githubPatController.dispose();
    _hubProxyController.dispose();
    _gitlabPatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SettingsProvider sp = context.watch<SettingsProvider>();
    final ColorScheme cs = Theme.of(context).colorScheme;

    return M3eExpressiveSettingsCard(
      colorScheme: cs,
      items: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kM3eSettingsCardHorizontalInset,
            12,
            kM3eSettingsCardTrailingInset,
            12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    tr('personalAccessTokenPAT'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  HelpHintIcon(
                    message: tr('patExplanationTooltip'),
                    size: 18,
                    padding: const EdgeInsets.only(left: 8),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _githubPatController,
                      obscureText: true,
                      decoration:
                          appPageOutlinedInputDecoration(
                            context,
                            labelText: tr('githubPATLabel'),
                            isDense: true,
                          ).copyWith(
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.open_in_new_rounded),
                              onPressed: () => launchUrlString(
                                'https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens',
                                mode: LaunchMode.externalApplication,
                              ),
                              tooltip: tr('about'),
                            ),
                          ),
                      onChanged: (val) {
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Builder(
                    builder: (context) {
                      final String enteredText = _githubPatController.text
                          .trim();
                      final String savedText =
                          sp.getSettingString(GitHub.githubCredsKey) ?? '';
                      final bool isDirty = enteredText != savedText;
                      final bool isValidated = GitHub.hasValidatedPAT(
                        enteredText,
                        sp,
                      );
                      final bool buttonIsEnabled =
                          isDirty || (enteredText.isNotEmpty && !isValidated);

                      return SizedBox(
                        width: 48,
                        height: 56,
                        child: Center(
                          child: _githubChecking
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: ExpressiveLoadingIndicator(
                                    color: cs.primary,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 20,
                                      height: 20,
                                    ),
                                  ),
                                )
                              // Show the validated shield only when the PAT is
                              // BOTH validated AND actually saved (!isDirty).
                              // Keying the shield on the stored fingerprint
                              // alone hid the save button when a matching
                              // fingerprint existed without saved creds (e.g.
                              // validated via the add-app form), stranding the
                              // field dirty with no way to persist it.
                              : (GitHub.hasValidatedPAT(enteredText, sp) &&
                                        !isDirty
                                    ? Tooltip(
                                        message: tr('githubPATValidated'),
                                        child: Icon(
                                          Icons.verified_user,
                                          color: cs.primary,
                                        ),
                                      )
                                    : IconButton.filledTonal(
                                        icon: const Icon(Icons.save_rounded),
                                        onPressed: buttonIsEnabled
                                            ? () async {
                                                FocusManager
                                                    .instance
                                                    .primaryFocus
                                                    ?.unfocus();
                                                if (enteredText.isEmpty) {
                                                  sp.setSettingString(
                                                    GitHub.githubCredsKey,
                                                    '',
                                                  );
                                                  GitHub.clearPATValidation(sp);
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        tr('dismiss'),
                                                      ),
                                                    ),
                                                  );
                                                  setState(() {});
                                                  return;
                                                }
                                                setState(() {
                                                  _githubChecking = true;
                                                });
                                                final String? error =
                                                    await GitHub.validatePAT(
                                                      enteredText,
                                                    );
                                                if (!context.mounted) return;
                                                setState(() {
                                                  _githubChecking = false;
                                                });
                                                if (error == null) {
                                                  sp.setSettingString(
                                                    GitHub.githubCredsKey,
                                                    enteredText,
                                                  );
                                                  GitHub.storePATValidation(
                                                    enteredText,
                                                    sp,
                                                  );
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        tr(
                                                          'githubPATValidated',
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                } else {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(error),
                                                    ),
                                                  );
                                                }
                                              }
                                            : null,
                                      )),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kM3eSettingsCardHorizontalInset,
            12,
            kM3eSettingsCardHorizontalInset,
            12,
          ),
          child: TextField(
            controller: _hubProxyController,
            decoration:
                appPageOutlinedInputDecoration(
                  context,
                  labelText: tr('GHReqPrefix'),
                  hintText: 'gh-proxy.org',
                  isDense: true,
                ).copyWith(
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.open_in_new_rounded),
                    onPressed: () => launchUrlString(
                      'https://github.com/sky22333/hubproxy',
                      mode: LaunchMode.externalApplication,
                    ),
                    tooltip: tr('about'),
                  ),
                ),
            onChanged: (val) {
              sp.setSettingString(GitHub.githubReqPrefixKey, val.trim());
            },
          ),
        ),
        SwitchListTile(
          title: Text(tr('GHReqPrefixUseToken')),
          value: sp.getSettingBool(GitHub.githubReqPrefixUseTokenKey) ?? false,
          onChanged: (val) {
            sp.setSettingBool(GitHub.githubReqPrefixUseTokenKey, val);
          },
        ),
        SwitchListTile(
          title: Text(tr('repoRenamedCheck')),
          value: sp.getSettingBool('checkRepoRename') ?? false,
          onChanged: (val) {
            sp.setSettingBool('checkRepoRename', val);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kM3eSettingsCardHorizontalInset,
            12,
            kM3eSettingsCardTrailingInset,
            12,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _gitlabPatController,
                  obscureText: true,
                  decoration:
                      appPageOutlinedInputDecoration(
                        context,
                        labelText: tr('gitlabPATLabel'),
                        isDense: true,
                      ).copyWith(
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.open_in_new_rounded),
                          onPressed: () => launchUrlString(
                            'https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html#create-a-personal-access-token',
                            mode: LaunchMode.externalApplication,
                          ),
                          tooltip: tr('about'),
                        ),
                      ),
                  onChanged: (val) {
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (context) {
                  final String enteredText = _gitlabPatController.text.trim();
                  final String savedText =
                      sp.getSettingString('gitlab-creds') ?? '';
                  final bool isDirty = enteredText != savedText;
                  final bool isValidated = GitLab.hasValidatedPAT(
                    enteredText,
                    sp,
                  );
                  final bool buttonIsEnabled =
                      isDirty || (enteredText.isNotEmpty && !isValidated);

                  return SizedBox(
                    width: 48,
                    height: 56,
                    child: Center(
                      child: _gitlabChecking
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: ExpressiveLoadingIndicator(
                                color: cs.primary,
                                constraints: const BoxConstraints.tightFor(
                                  width: 20,
                                  height: 20,
                                ),
                              ),
                            )
                          // Shield only when validated AND saved (see the GitHub
                          // field above for why fingerprint-alone is wrong).
                          : (GitLab.hasValidatedPAT(enteredText, sp) && !isDirty
                                ? Tooltip(
                                    message: tr('gitlabPATValidated'),
                                    child: Icon(
                                      Icons.verified_user,
                                      color: cs.primary,
                                    ),
                                  )
                                : IconButton.filledTonal(
                                    icon: const Icon(Icons.save_rounded),
                                    onPressed: buttonIsEnabled
                                        ? () async {
                                            FocusManager.instance.primaryFocus
                                                ?.unfocus();
                                            if (enteredText.isEmpty) {
                                              sp.setSettingString(
                                                'gitlab-creds',
                                                '',
                                              );
                                              GitLab.clearPATValidation(sp);
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(tr('dismiss')),
                                                ),
                                              );
                                              setState(() {});
                                              return;
                                            }
                                            setState(() {
                                              _gitlabChecking = true;
                                            });
                                            final String? error =
                                                await GitLab.validatePAT(
                                                  enteredText,
                                                );
                                            if (!context.mounted) return;
                                            setState(() {
                                              _gitlabChecking = false;
                                            });
                                            if (error == null) {
                                              sp.setSettingString(
                                                'gitlab-creds',
                                                enteredText,
                                              );
                                              GitLab.storePATValidation(
                                                enteredText,
                                                sp,
                                              );
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    tr('gitlabPATValidated'),
                                                  ),
                                                ),
                                              );
                                            } else {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(content: Text(error)),
                                              );
                                            }
                                          }
                                        : null,
                                  )),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Themes section — delegates to external themes settings widget,
/// using the existing optimized context.select pattern.
class _ThemesSettingsSection extends StatelessWidget {
  const _ThemesSettingsSection({required this.androidInfoFuture});

  final Future<AndroidDeviceInfo> androidInfoFuture;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return M3eExpressiveSettingsCard(
      colorScheme: cs,
      items: buildThemesSettingsCardItems(context, androidInfoFuture),
    );
  }
}

/// Appearance section — locale, UI scale slider, card-corner slider, toggles.
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  static int _appearanceSettingsHash(SettingsProvider sp) => Object.hash(
    sp.forcedLocale?.toLanguageTag(),
    sp.appUiScale,
    sp.cardCornerScale,
    sp.showAppWebpage,
    sp.highlightTouchTargets,
    sp.alwaysUsePhoneLayout,
    sp.customFontPath,
  );

  @override
  Widget build(BuildContext context) {
    context.select<SettingsProvider, int>(_appearanceSettingsHash);
    final SettingsProvider sp = context.read<SettingsProvider>();
    final ColorScheme cs = Theme.of(context).colorScheme;

    return M3eExpressiveSettingsCard(
      colorScheme: cs,
      items: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kM3eSettingsCardHorizontalInset,
            12,
            kM3eSettingsCardHorizontalInset,
            4,
          ),
          child: _LocaleMenu(sp: sp),
        ),
        _CustomFontTile(sp: sp),
        const _UiScaleSlider(),
        const _CardCornerScaleSlider(),
        SwitchListTile(
          title: Text(tr('alwaysUsePhoneLayout')),
          value: sp.alwaysUsePhoneLayout,
          onChanged: (value) => sp.alwaysUsePhoneLayout = value,
        ),
        SwitchListTile(
          title: Text(tr('showWebInAppView')),
          value: sp.showAppWebpage,
          onChanged: (value) => sp.showAppWebpage = value,
        ),
        SwitchListTile(
          title: Text(tr('highlightTouchTargets')),
          value: sp.highlightTouchTargets,
          onChanged: (value) => sp.highlightTouchTargets = value,
        ),
      ],
    );
  }
}

class _CustomFontTile extends StatelessWidget {
  const _CustomFontTile({required this.sp});

  final SettingsProvider sp;

  String? _readFontName(Uint8List bytes) {
    try {
      final ByteData data = ByteData.view(bytes.buffer);
      if (data.lengthInBytes < 12) return null;

      final int numTables = data.getUint16(4, Endian.big);
      if (data.lengthInBytes < 12 + (numTables * 16)) return null;

      int? nameTableOffset;
      for (int i = 0; i < numTables; i++) {
        final int recordOffset = 12 + (i * 16);
        final int tag1 = data.getUint8(recordOffset);
        final int tag2 = data.getUint8(recordOffset + 1);
        final int tag3 = data.getUint8(recordOffset + 2);
        final int tag4 = data.getUint8(recordOffset + 3);
        if (tag1 == 110 && tag2 == 97 && tag3 == 109 && tag4 == 101) {
          // "name"
          nameTableOffset = data.getUint32(recordOffset + 8, Endian.big);
          break;
        }
      }

      if (nameTableOffset == null || nameTableOffset >= data.lengthInBytes) {
        return null;
      }

      final int count = data.getUint16(nameTableOffset + 2, Endian.big);
      final int stringOffset = data.getUint16(nameTableOffset + 4, Endian.big);

      final int stringStorageStart = nameTableOffset + stringOffset;
      if (stringStorageStart >= data.lengthInBytes) return null;

      String? fontFamilyName;
      String? fullFontName;

      for (int i = 0; i < count; i++) {
        final int recordPos = nameTableOffset + 6 + (i * 12);
        if (recordPos + 12 > data.lengthInBytes) break;

        final int platformID = data.getUint16(recordPos, Endian.big);
        final int nameID = data.getUint16(recordPos + 6, Endian.big);
        final int length = data.getUint16(recordPos + 8, Endian.big);
        final int offset = data.getUint16(recordPos + 10, Endian.big);

        if (nameID == 4 || nameID == 1) {
          final int start = stringStorageStart + offset;
          if (start + length > data.lengthInBytes) continue;

          final Uint8List nameBytes = bytes.sublist(start, start + length);
          String nameStr = '';

          if (platformID == 3 || platformID == 0) {
            final buffer = StringBuffer();
            for (int j = 0; j < nameBytes.length; j += 2) {
              if (j + 1 < nameBytes.length) {
                final int charCode = (nameBytes[j] << 8) | nameBytes[j + 1];
                if (charCode != 0) {
                  buffer.writeCharCode(charCode);
                }
              }
            }
            nameStr = buffer.toString().trim();
          } else {
            nameStr = utf8.decode(nameBytes, allowMalformed: true).trim();
          }

          if (nameStr.isNotEmpty) {
            if (nameID == 4) {
              fullFontName = nameStr;
            } else {
              fontFamilyName = nameStr;
            }
          }
        }
      }

      return fullFontName ?? fontFamilyName;
    } catch (_) {}
    return null;
  }

  Future<void> _pickFont(BuildContext context) async {
    try {
      final bool? proceed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text(tr('settingsCustomFontChoose')),
            contentPadding: appDialogContentPadding,
            content: Text(tr('settingsCustomFontChooseExplanation')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(tr('cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(tr('pick')),
              ),
            ],
          );
        },
      );
      if (proceed != true) return;

      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
      );
      if (result == null || result.files.single.path == null) return;
      final String pickedPath = result.files.single.path!;

      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final Directory fontsDir = Directory('${appDocDir.path}/fonts');
      await fontsDir.create(recursive: true);
      final String ext = pickedPath.split('.').last.toLowerCase();
      final String targetPath = '${fontsDir.path}/custom_font.$ext';

      final File sourceFile = File(pickedPath);
      final Uint8List bytes = await sourceFile.readAsBytes();

      // Read font name from metadata
      final String? parsedName = _readFontName(bytes);
      final String displayName =
          parsedName ?? pickedPath.split(Platform.pathSeparator).last;

      // Verify the font by temporarily loading it
      final FontLoader fontLoader = FontLoader('TempCustomFontTest');
      fontLoader.addFont(Future.value(bytes.buffer.asByteData()));
      await fontLoader.load();

      // Write font to destination
      final File targetFile = File(targetPath);
      await targetFile.writeAsBytes(bytes);

      sp.customFontName = displayName;
      sp.customFontPath = targetPath;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('settingsCustomFontSuccess')),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('settingsCustomFontErrorInvalid')),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? currentPath = sp.customFontPath;
    final String subtitleText = currentPath != null
        ? (sp.customFontName ?? currentPath.split(Platform.pathSeparator).last)
        : tr('settingsCustomFontDefault');

    return ListTile(
      title: Text(tr('settingsCustomFontTitle')),
      subtitle: Text(subtitleText),
      leading: const Icon(Icons.font_download_outlined),
      trailing: currentPath != null
          ? IconButton.filledTonal(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                sp.customFontName = null;
                sp.customFontPath = null;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(tr('settingsCustomFontResetSuccess')),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            )
          : null,
      onTap: () => _pickFont(context),
    );
  }
}

class _LocaleMenu extends StatelessWidget {
  const _LocaleMenu({required this.sp});

  final SettingsProvider sp;

  @override
  Widget build(BuildContext context) {
    return appDropdownField<String>(
      key: ValueKey(sp.forcedLocale?.toLanguageTag() ?? '_system'),
      context: context,
      value: sp.forcedLocale?.toLanguageTag() ?? '_system',
      labelText: tr('language'),
      menuWidth: appDropdownMenuWidth(
        context,
        [
          tr('followSystem'),
          ...supportedLocales.map(
            (MapEntry<Locale, String> localeEntry) => localeEntry.value,
          ),
        ],
        style: Theme.of(context).textTheme.bodyLarge,
        horizontalPadding: 96,
        minWidth: 150,
      ),
      items: [
        DropdownMenuItem<String>(
          value: '_system',
          child: Text(tr('followSystem')),
        ),
        ...supportedLocales.map(
          (MapEntry<Locale, String> localeEntry) => DropdownMenuItem<String>(
            value: localeEntry.key.toLanguageTag(),
            child: Text(localeEntry.value),
          ),
        ),
      ],
      onChanged: (String? value) {
        final Locale? selectedLocale = value == null || value == '_system'
            ? null
            : supportedLocales
                  .firstWhere(
                    (MapEntry<Locale, String> localeEntry) =>
                        localeEntry.key.toLanguageTag() == value,
                  )
                  .key;
        sp.forcedLocale = selectedLocale;
        if (selectedLocale != null) {
          unawaited(context.setLocale(selectedLocale));
        } else {
          unawaited(sp.resetLocaleSafe(context));
        }
      },
    );
  }
}

class _UiScaleSlider extends StatefulWidget {
  const _UiScaleSlider();

  @override
  State<_UiScaleSlider> createState() => _UiScaleSliderState();
}

class _UiScaleSliderState extends State<_UiScaleSlider> {
  double? _dragValue;
  late final FocusNode _sliderFocusNode;

  @override
  void initState() {
    super.initState();
    _sliderFocusNode = FocusNode(canRequestFocus: false, skipTraversal: true);
  }

  @override
  void dispose() {
    _sliderFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final double value =
        _dragValue ??
        context.select<SettingsProvider, double>((s) => s.appUiScale);
    final isTV = context.read<SettingsProvider>().isTV;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kM3eSettingsCardHorizontalInset,
        8,
        kM3eSettingsCardHorizontalInset,
        8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.format_size_rounded, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(tr('uiScale'))),
                      Text('${(value * 100).round()}%'),
                    ],
                  ),
                ),
                TVSliderWrapper(
                  value: value,
                  min: SettingsProvider.appUiScaleMin,
                  max: SettingsProvider.appUiScaleMax,
                  divisions:
                      ((SettingsProvider.appUiScaleMax -
                                  SettingsProvider.appUiScaleMin) /
                              0.05)
                          .round(),
                  onChanged: (double v) {
                    setState(() => _dragValue = v);
                  },
                  onChangeEnd: (double v) {
                    context.read<SettingsProvider>().appUiScale = v;
                    setState(() => _dragValue = null);
                  },
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 16,
                      trackShape: const _GappedTrackShape(),
                      thumbShape: const _VerticalBarThumbShape(),
                      activeTickMarkColor: cs.onPrimary,
                      inactiveTickMarkColor: cs.primary,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      focusNode: isTV ? _sliderFocusNode : null,
                      min: SettingsProvider.appUiScaleMin,
                      max: SettingsProvider.appUiScaleMax,
                      divisions:
                          ((SettingsProvider.appUiScaleMax -
                                      SettingsProvider.appUiScaleMin) /
                                  0.05)
                              .round(),
                      label: '${(value * 100).round()}%',
                      value: value.clamp(
                        SettingsProvider.appUiScaleMin,
                        SettingsProvider.appUiScaleMax,
                      ),
                      onChanged: (double v) {
                        setState(() => _dragValue = v);
                      },
                      onChangeEnd: (double v) {
                        context.read<SettingsProvider>().appUiScale = v;
                        setState(() => _dragValue = null);
                      },
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

class _CardCornerScaleSlider extends StatefulWidget {
  const _CardCornerScaleSlider();

  @override
  State<_CardCornerScaleSlider> createState() => _CardCornerScaleSliderState();
}

class _CardCornerScaleSliderState extends State<_CardCornerScaleSlider> {
  double? _dragValue;
  late final FocusNode _sliderFocusNode;

  @override
  void initState() {
    super.initState();
    _sliderFocusNode = FocusNode(canRequestFocus: false, skipTraversal: true);
  }

  @override
  void dispose() {
    _sliderFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final double value =
        _dragValue ??
        context.select<SettingsProvider, double>((s) => s.cardCornerScale);
    final isTV = context.read<SettingsProvider>().isTV;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kM3eSettingsCardHorizontalInset,
        8,
        kM3eSettingsCardHorizontalInset,
        8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.rounded_corner_rounded, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(tr('cardCorners'))),
                      Text('${(value * 100).round()}%'),
                    ],
                  ),
                ),
                TVSliderWrapper(
                  value: value,
                  min: SettingsProvider.cardCornerScaleMin,
                  max: SettingsProvider.cardCornerScaleMax,
                  divisions:
                      ((SettingsProvider.cardCornerScaleMax -
                                  SettingsProvider.cardCornerScaleMin) /
                              0.10)
                          .round(),
                  onChanged: (double v) {
                    setState(() => _dragValue = v);
                  },
                  onChangeEnd: (double v) {
                    context.read<SettingsProvider>().cardCornerScale = v;
                    setState(() => _dragValue = null);
                  },
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 16,
                      trackShape: const _GappedTrackShape(),
                      thumbShape: const _VerticalBarThumbShape(),
                      activeTickMarkColor: cs.onPrimary,
                      inactiveTickMarkColor: cs.primary,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      focusNode: isTV ? _sliderFocusNode : null,
                      min: SettingsProvider.cardCornerScaleMin,
                      max: SettingsProvider.cardCornerScaleMax,
                      divisions:
                          ((SettingsProvider.cardCornerScaleMax -
                                      SettingsProvider.cardCornerScaleMin) /
                                  0.10)
                              .round(),
                      label: '${(value * 100).round()}%',
                      value: value.clamp(
                        SettingsProvider.cardCornerScaleMin,
                        SettingsProvider.cardCornerScaleMax,
                      ),
                      onChanged: (double v) {
                        setState(() => _dragValue = v);
                      },
                      onChangeEnd: (double v) {
                        context.read<SettingsProvider>().cardCornerScale = v;
                        setState(() => _dragValue = null);
                      },
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

/// Gestures section — swipe action dropdowns.
/// Warnings section — visibility of operation warnings/prompts. All toggles are
/// positive ("Show …", ON = visible). Track-only/APK-origin/battery wrap inverted
/// hideX prefs; downgrade uses showAppDowngradeError directly.
class _WarningsSection extends StatelessWidget {
  const _WarningsSection();

  static int _warningsSettingsHash(SettingsProvider sp) => Object.hash(
    sp.hideBatteryOptimizationWarning,
    sp.hideTrackOnlyWarning,
    sp.hideAPKOriginWarning,
    sp.showAppDowngradeError,
  );

  @override
  Widget build(BuildContext context) {
    context.select<SettingsProvider, int>(_warningsSettingsHash);
    final SettingsProvider sp = context.read<SettingsProvider>();
    final ColorScheme cs = Theme.of(context).colorScheme;
    return M3eExpressiveSettingsCard(
      colorScheme: cs,
      items: [
        SwitchListTile(
          title: Text(tr('showBatteryOptimizationPrompt')),
          // Bound to the existing hideBatteryOptimizationWarning (inverted) so the
          // launch dialog's "don't show again" and this toggle stay in sync.
          value: !sp.hideBatteryOptimizationWarning,
          onChanged: (value) => sp.hideBatteryOptimizationWarning = !value,
        ),
        SwitchListTile(
          title: Text(tr('showTrackOnlyWarnings')),
          value: !sp.hideTrackOnlyWarning,
          onChanged: (value) => sp.hideTrackOnlyWarning = !value,
        ),
        SwitchListTile(
          title: Text(tr('showAPKOriginWarnings')),
          value: !sp.hideAPKOriginWarning,
          onChanged: (value) => sp.hideAPKOriginWarning = !value,
        ),
        SwitchListTile(
          title: Text(tr('showAppDowngradeError')),
          value: sp.showAppDowngradeError,
          onChanged: (value) => sp.showAppDowngradeError = value,
        ),
      ],
    );
  }
}

class _InteractionSection extends StatelessWidget {
  const _InteractionSection();

  static int _interactionSettingsHash(SettingsProvider sp) => Object.hash(
    sp.rightSwipeAction,
    sp.leftSwipeAction,
    sp.tactileFeedbackEnabled,
  );

  @override
  Widget build(BuildContext context) {
    context.select<SettingsProvider, int>(_interactionSettingsHash);
    final SettingsProvider sp = context.read<SettingsProvider>();
    final ColorScheme cs = Theme.of(context).colorScheme;

    final List<SwipeAction> actions = swipeActionsSortedByLocalizedLabel();
    final double swipeMenuWidth = appDropdownMenuWidth(
      context,
      actions.map((SwipeAction action) => tr('swipeAction_${action.name}')),
      style: Theme.of(context).textTheme.bodyLarge,
      horizontalPadding: 120,
      minWidth: 180,
      maxWidthInset: 80,
    );

    List<DropdownMenuItem<SwipeAction>> actionItems() {
      return actions.map((SwipeAction action) {
        return DropdownMenuItem<SwipeAction>(
          value: action,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_swipeActionIcon(action), size: 18, color: cs.primary),
              const SizedBox(width: 12),
              Text(tr('swipeAction_${action.name}')),
            ],
          ),
        );
      }).toList();
    }

    return M3eExpressiveSettingsCard(
      colorScheme: cs,
      items: [
        SwitchListTile(
          title: Text(tr('tactileFeedbackEnabled')),
          value: sp.tactileFeedbackEnabled,
          onChanged: (value) => sp.tactileFeedbackEnabled = value,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kM3eSettingsCardHorizontalInset,
            12,
            kM3eSettingsCardHorizontalInset,
            12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              appDropdownField<SwipeAction>(
                key: ValueKey('rightSwipeAction_${sp.rightSwipeAction}'),
                context: context,
                value: sp.rightSwipeAction,
                labelText: tr('rightSwipeAction'),
                menuWidth: swipeMenuWidth,
                items: actionItems(),
                onChanged: (SwipeAction? value) {
                  if (value != null) sp.rightSwipeAction = value;
                },
              ),
              const SizedBox(height: 16),
              appDropdownField<SwipeAction>(
                key: ValueKey('leftSwipeAction_${sp.leftSwipeAction}'),
                context: context,
                value: sp.leftSwipeAction,
                labelText: tr('leftSwipeAction'),
                menuWidth: swipeMenuWidth,
                items: actionItems(),
                onChanged: (SwipeAction? value) {
                  if (value != null) sp.leftSwipeAction = value;
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IntegrationsSection extends StatefulWidget {
  const _IntegrationsSection({super.key});

  @override
  State<_IntegrationsSection> createState() => _IntegrationsSectionState();
}

class _IntegrationsSectionState extends State<_IntegrationsSection>
    with WidgetsBindingObserver {
  bool _appManagerInstalled = false;
  bool _letMeDowngradeInstalled = false;
  bool _loading = true;
  late final TextEditingController _virusTotalApiKeyController;
  bool _virusTotalChecking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInstalledApps();
    _virusTotalApiKeyController = TextEditingController(
      text:
          context.read<SettingsProvider>().getSettingString(
            virusTotalApiKeyKey,
          ) ??
          '',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _virusTotalApiKeyController.dispose();
    super.dispose();
  }

  bool get isVirusTotalApiKeyDirty {
    final String currentText = _virusTotalApiKeyController.text.trim();
    final SettingsProvider sp = context.read<SettingsProvider>();
    final String savedText = sp.getSettingString(virusTotalApiKeyKey) ?? '';
    return currentText != savedText;
  }

  void discardChanges() {
    final SettingsProvider sp = context.read<SettingsProvider>();
    _virusTotalApiKeyController.text =
        sp.getSettingString(virusTotalApiKeyKey) ?? '';
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkInstalledApps();
    }
  }

  Future<void> _checkInstalledApps() async {
    final results = await Future.wait([
      getInstalledInfo('io.github.muntashirakon.AppManager'),
      getInstalledInfo('com.berdik.letmedowngrade'),
    ]);
    if (mounted) {
      setState(() {
        _appManagerInstalled = results[0] != null;
        _letMeDowngradeInstalled = results[1] != null;
        _loading = false;
      });
    }
  }

  static int _integrationsSettingsHash(SettingsProvider sp) => Object.hash(
    sp.openAppInfoInAppManager,
    sp.beforeNewInstallsShareToAppVerifier,
    sp.enableVirusTotalScanning,
    sp.enableLetMeDowngrade,
    sp.installerMode,
    sp.shizukuPretendToBeGooglePlay,
  );

  @override
  Widget build(BuildContext context) {
    context.select<SettingsProvider, int>(_integrationsSettingsHash);
    final SettingsProvider sp = context.read<SettingsProvider>();
    final ColorScheme cs = Theme.of(context).colorScheme;

    return M3eExpressiveSettingsCard(
      colorScheme: cs,
      items: [
        ListTile(
          title: Text(
            tr('openAppInfoInAppManager'),
            style: TextStyle(
              color: _loading
                  ? cs.onSurface.withValues(alpha: 0.38)
                  : _appManagerInstalled
                  ? null
                  : cs.onSurface.withValues(alpha: 0.38),
            ),
          ),
          onTap: !_loading && !_appManagerInstalled
              ? () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('appManagerNotInstalledSnackbar'))),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: tr('about'),
                onPressed: () {
                  launchUrlString(
                    tr('aboutAppManagerUrl'),
                    mode: LaunchMode.externalApplication,
                  );
                },
                style: IconButton.styleFrom(
                  foregroundColor: cs.onSurfaceVariant,
                  iconSize: 20,
                  padding: const EdgeInsets.all(4),
                  minimumSize: const Size(32, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.open_in_new_rounded),
              ),
              Switch(
                value:
                    !_loading &&
                    _appManagerInstalled &&
                    sp.openAppInfoInAppManager,
                onChanged: !_loading && _appManagerInstalled
                    ? (bool value) => sp.openAppInfoInAppManager = value
                    : null,
              ),
            ],
          ),
        ),
        ListTile(
          title: Text(
            tr('beforeNewInstallsShareToAppVerifier'),
            style: TextStyle(
              color: _loading ? cs.onSurface.withValues(alpha: 0.38) : null,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HelpHintIcon(
                message: tr('shareToAppVerifierTooltip'),
                size: 20,
                padding: EdgeInsets.zero,
              ),
              Switch(
                value: !_loading && sp.beforeNewInstallsShareToAppVerifier,
                onChanged: !_loading
                    ? (bool value) =>
                          sp.beforeNewInstallsShareToAppVerifier = value
                    : null,
              ),
            ],
          ),
        ),
        ListTile(
          title: Text(
            tr('enableLetMeDowngrade'),
            style: TextStyle(
              color: _loading
                  ? cs.onSurface.withValues(alpha: 0.38)
                  : _letMeDowngradeInstalled
                  ? null
                  : cs.onSurface.withValues(alpha: 0.38),
            ),
          ),
          onTap: !_loading && !_letMeDowngradeInstalled
              ? () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(tr('letMeDowngradeNotInstalledSnackbar')),
                  ),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: tr('about'),
                onPressed: () {
                  launchUrlString(
                    tr('aboutLetMeDowngradeUrl'),
                    mode: LaunchMode.externalApplication,
                  );
                },
                style: IconButton.styleFrom(
                  foregroundColor: cs.onSurfaceVariant,
                  iconSize: 20,
                  padding: const EdgeInsets.all(4),
                  minimumSize: const Size(32, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.open_in_new_rounded),
              ),
              Switch(
                value:
                    !_loading &&
                    _letMeDowngradeInstalled &&
                    sp.enableLetMeDowngrade,
                onChanged: !_loading && _letMeDowngradeInstalled
                    ? (bool value) => sp.enableLetMeDowngrade = value
                    : null,
              ),
            ],
          ),
        ),
        Builder(
          builder: (context) {
            final String savedApiKey =
                sp.getSettingString(virusTotalApiKeyKey) ?? '';
            final bool hasValidatedKey =
                savedApiKey.isNotEmpty && hasValidatedApiKey(savedApiKey, sp);
            return ListTile(
              title: Text(tr('enableVirusTotalScanning')),
              onTap: !hasValidatedKey
                  ? () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(tr('virusTotalNotValidatedSnackbar')),
                      ),
                    )
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HelpHintIcon(
                    message: tr('virusTotalScanningTooltip'),
                    size: 20,
                    padding: EdgeInsets.zero,
                  ),
                  Switch(
                    value: hasValidatedKey && sp.enableVirusTotalScanning,
                    onChanged: hasValidatedKey
                        ? (bool value) => sp.enableVirusTotalScanning = value
                        : null,
                  ),
                ],
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kM3eSettingsCardHorizontalInset,
            8,
            kM3eSettingsCardTrailingInset,
            12,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _virusTotalApiKeyController,
                  obscureText: true,
                  decoration:
                      appPageOutlinedInputDecoration(
                        context,
                        labelText: tr('virusTotalApiKeyLabel'),
                        isDense: true,
                      ).copyWith(
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.open_in_new_rounded),
                          onPressed: () => launchUrlString(
                            'https://www.virustotal.com/gui/my-apikey',
                            mode: LaunchMode.externalApplication,
                          ),
                          tooltip: tr('about'),
                        ),
                      ),
                  onChanged: (val) {
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (context) {
                  final String enteredText = _virusTotalApiKeyController.text
                      .trim();
                  final String savedText =
                      sp.getSettingString(virusTotalApiKeyKey) ?? '';
                  final bool isDirty = enteredText != savedText;
                  final bool isValidated = hasValidatedApiKey(enteredText, sp);
                  final bool buttonIsEnabled =
                      isDirty || (enteredText.isNotEmpty && !isValidated);
                  return SizedBox(
                    width: 48,
                    height: 56,
                    child: Center(
                      child: _virusTotalChecking
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: ExpressiveLoadingIndicator(
                                color: cs.primary,
                                constraints: const BoxConstraints.tightFor(
                                  width: 20,
                                  height: 20,
                                ),
                              ),
                            )
                          // Shield only when validated AND saved (see GitHub PAT).
                          : (isValidated && !isDirty
                                ? Tooltip(
                                    message: tr('virusTotalKeyValidated'),
                                    child: Icon(
                                      Icons.verified_user,
                                      color: cs.primary,
                                    ),
                                  )
                                : IconButton.filledTonal(
                                    icon: const Icon(Icons.save_rounded),
                                    onPressed: buttonIsEnabled
                                        ? () async {
                                            FocusManager.instance.primaryFocus
                                                ?.unfocus();
                                            if (enteredText.isEmpty) {
                                              sp.setSettingString(
                                                virusTotalApiKeyKey,
                                                '',
                                              );
                                              clearApiKeyValidation(sp);
                                              sp.enableVirusTotalScanning =
                                                  false;
                                              setState(() {});
                                              return;
                                            }
                                            setState(() {
                                              _virusTotalChecking = true;
                                            });
                                            final String? error =
                                                await VirusTotalScanner()
                                                    .validateApiKey(
                                                      enteredText,
                                                    );
                                            if (!context.mounted) return;
                                            setState(() {
                                              _virusTotalChecking = false;
                                            });
                                            if (error == null) {
                                              sp.setSettingString(
                                                virusTotalApiKeyKey,
                                                enteredText,
                                              );
                                              storeApiKeyValidation(
                                                enteredText,
                                                sp,
                                              );
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    tr(
                                                      'virusTotalKeyValidated',
                                                    ),
                                                  ),
                                                ),
                                              );
                                              setState(() {});
                                            } else {
                                              clearApiKeyValidation(sp);
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(content: Text(error)),
                                              );
                                            }
                                          }
                                        : null,
                                  )),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kM3eSettingsCardHorizontalInset,
            8,
            kM3eSettingsCardHorizontalInset,
            4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('installerMode')),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: AppSegmentedButton<String>(
                  segments: [
                    ButtonSegment<String>(
                      value: 'system',
                      label: AppSegmentedButtonLabel(tr('installerModeStock')),
                    ),
                    ButtonSegment<String>(
                      value: 'shizuku',
                      label: AppSegmentedButtonLabel(
                        tr('installerModeShizuku'),
                      ),
                    ),
                    ButtonSegment<String>(
                      value: 'external',
                      label: AppSegmentedButtonLabel(
                        tr('installerModeThirdParty'),
                      ),
                    ),
                  ],
                  selected: {sp.installerMode},
                  onSelectionChanged: (Set<String> selected) {
                    final String mode = selected.first;
                    if (mode == 'shizuku') {
                      ShizukuApkInstaller().checkPermission().then((
                        String? resCode,
                      ) {
                        if (!context.mounted) return;
                        if (resCode!.startsWith('granted')) {
                          sp.installerMode = 'shizuku';
                        } else {
                          switch (resCode) {
                            case 'services_not_found':
                              showError(
                                ObtainiumError(tr('shizukuBinderNotFound')),
                              );
                            case 'old_shizuku':
                              showError(ObtainiumError(tr('shizukuOld')));
                            case 'old_android_with_adb':
                              showError(
                                ObtainiumError(tr('shizukuOldAndroidWithADB')),
                              );
                            case 'denied':
                              showError(ObtainiumError(tr('cancelled')));
                          }
                        }
                      });
                    } else {
                      sp.installerMode = mode;
                    }
                  },
                ),
              ),
              if (sp.installerMode == 'shizuku')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('shizukuPretendToBeGooglePlay')),
                  value: sp.shizukuPretendToBeGooglePlay,
                  onChanged: (bool value) =>
                      sp.shizukuPretendToBeGooglePlay = value,
                ),
              if (sp.installerMode == 'external')
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: _ExternalInstallerTile(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Categories section — delegates to CategoryEditorSelector.
class _CategoriesSection extends StatelessWidget {
  const _CategoriesSection();

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return M3eExpressiveSettingsCard(
      colorScheme: cs,
      items: const [
        Padding(
          padding: EdgeInsets.all(16),
          child: CategoryEditorSelector(
            showLabelWhenNotEmpty: false,
            showSelectedCheckmark: true,
            showChangeIntentIcons: false,
          ),
        ),
      ],
    );
  }
}

class AboutSectionContent extends StatelessWidget {
  const AboutSectionContent({super.key, required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final SettingsProvider sp = context.read<SettingsProvider>();
    final TextTheme textTheme = Theme.of(context).textTheme;
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool isLargeScreen =
        screenWidth >= kLargeScreenWidthBreakpoint && !sp.alwaysUsePhoneLayout;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FutureBuilder<PackageInfo?>(
                future: getInstalledInfo(
                  obtainiumId,
                  printErr: false,
                  includeOwnDebugBuild: true,
                ),
                builder: (context, snapshot) {
                  final String versionName =
                      snapshot.data?.versionName ?? tr('unknown');
                  return Text(
                    tr('aboutAppVersion', args: [versionName]),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              Text(
                tr('aboutTagline'),
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _AboutImageTile(
                    assetPath: 'assets/graphics/icon_small.png',
                    borderRadius: 24,
                    semanticLabel: tr('about'),
                    fit: BoxFit.contain,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                  const SizedBox(width: 14),
                  _AboutImageTile(
                    assetPath: 'assets/graphics/me_600.webp',
                    borderRadius: 18,
                    semanticLabel: tr('aboutAuthorProfile'),
                    onTap: () => _openAboutUrl(_aboutAuthorUrl),
                    onLongPress: () => _copyAboutUrl(_aboutAuthorUrl),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                tr('aboutByline'),
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openAboutUrl(sp.sourceUrl),
                    onLongPress: () => _copyAboutUrl(sp.sourceUrl),
                    icon: _GitHubMarkIcon(color: colorScheme.onPrimary),
                    label: Text(tr('aboutStarOnGithub')),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: _aboutSecondaryButtonStyle(colorScheme),
                        onPressed: () => _openAboutUrl(_aboutWikiUrl),
                        onLongPress: () => _copyAboutUrl(_aboutWikiUrl),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: Text(tr('aboutOpenWiki')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: _aboutSecondaryButtonStyle(colorScheme),
                        onPressed: () =>
                            _shareAboutUrl(_aboutObtainXWebsiteUrl, 'ObtainX'),
                        onLongPress: () =>
                            _copyAboutUrl(_aboutObtainXWebsiteUrl),
                        icon: const Icon(Icons.share_rounded),
                        label: Text(tr('share')),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tr('aboutOtherApps'),
                        style: textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _AboutAppPromo(
                      colorScheme: colorScheme,
                      assetPath: 'assets/graphics/logo_remember.png',
                      accentColor: const Color(0xFF74B84A),
                      name: tr('aboutRememberName'),
                      tagline: tr('aboutRememberTagline'),
                      url: _aboutRememberUrl,
                      appId: tr('aboutRememberPackageId'),
                    ),
                    const SizedBox(height: 10),
                    _AboutAppPromo(
                      colorScheme: colorScheme,
                      assetPath: 'assets/graphics/logo_filepipe.png',
                      accentColor: const Color(0xFF5967D8),
                      name: tr('aboutFilePipeName'),
                      tagline: tr('aboutFilePipeTagline'),
                      url: _aboutFilePipeUrl,
                      appId: tr('aboutFilePipePackageId'),
                    ),
                    const SizedBox(height: 8),
                    _AboutLegalLinks(colorScheme: colorScheme),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (isLargeScreen)
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              onPressed: () => _openLogsDialog(context),
              icon: Icon(Icons.bug_report_outlined, color: colorScheme.primary),
              tooltip: tr('appLogs'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
      ],
    );
  }
}

ButtonStyle _aboutSecondaryButtonStyle(ColorScheme colorScheme) {
  return FilledButton.styleFrom(
    backgroundColor: Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.16),
      colorScheme.surfaceContainerHighest,
    ),
    foregroundColor: colorScheme.primary,
    side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.36)),
  );
}

class _GitHubMarkIcon extends StatelessWidget {
  const _GitHubMarkIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(20),
      painter: _GitHubMarkPainter(color),
    );
  }
}

class _GitHubMarkPainter extends CustomPainter {
  const _GitHubMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final Path path = Path()
      ..moveTo(12, 2)
      ..arcToPoint(
        const Offset(2, 12),
        radius: const Radius.circular(10),
        clockwise: false,
      )
      ..relativeCubicTo(0, 4.42, 2.87, 8.17, 6.84, 9.5)
      ..relativeCubicTo(0.5, 0.08, 0.66, -0.23, 0.66, -0.5)
      ..relativeLineTo(0, -1.69)
      ..relativeCubicTo(-2.77, 0.6, -3.36, -1.34, -3.36, -1.34)
      ..relativeCubicTo(-0.46, -1.16, -1.11, -1.47, -1.11, -1.47)
      ..relativeCubicTo(-0.91, -0.62, 0.07, -0.6, 0.07, -0.6)
      ..relativeCubicTo(1, 0.07, 1.53, 1.03, 1.53, 1.03)
      ..relativeCubicTo(0.89, 1.52, 2.34, 1.08, 2.91, 0.83)
      ..relativeCubicTo(0.09, -0.65, 0.35, -1.09, 0.63, -1.34)
      ..relativeCubicTo(-2.22, -0.25, -4.55, -1.11, -4.55, -4.94)
      ..relativeCubicTo(0, -1.09, 0.39, -1.98, 1.03, -2.68)
      ..relativeCubicTo(-0.1, -0.25, -0.45, -1.27, 0.1, -2.65)
      ..relativeCubicTo(0, 0, 0.84, -0.27, 2.75, 1.02)
      ..relativeCubicTo(0.8, -0.22, 1.65, -0.33, 2.5, -0.33)
      ..relativeCubicTo(0.85, 0, 1.7, 0.11, 2.5, 0.33)
      ..relativeCubicTo(1.91, -1.29, 2.75, -1.02, 2.75, -1.02)
      ..relativeCubicTo(0.55, 1.38, 0.2, 2.4, 0.1, 2.65)
      ..relativeCubicTo(0.64, 0.7, 1.03, 1.59, 1.03, 2.68)
      ..relativeCubicTo(0, 3.85, -2.34, 4.68, -4.57, 4.93)
      ..relativeCubicTo(0.36, 0.31, 0.68, 0.92, 0.68, 1.85)
      ..relativeLineTo(0, 2.74)
      ..relativeCubicTo(0, 0.27, 0.16, 0.59, 0.67, 0.5)
      ..cubicTo(19.14, 20.17, 22, 16.42, 22, 12)
      ..arcToPoint(
        const Offset(12, 2),
        radius: const Radius.circular(10),
        clockwise: false,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GitHubMarkPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _AboutImageTile extends StatelessWidget {
  const _AboutImageTile({
    required this.assetPath,
    required this.borderRadius,
    required this.semanticLabel,
    this.backgroundColor,
    this.fit = BoxFit.cover,
    this.onTap,
    this.onLongPress,
  });

  final String assetPath;
  final double borderRadius;
  final String semanticLabel;
  final Color? backgroundColor;
  final BoxFit fit;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor ?? Colors.transparent,
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink.image(
          image: AssetImage(assetPath),
          width: 84,
          height: 84,
          fit: fit,
          child: Semantics(
            label: semanticLabel,
            image: true,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _AboutAppPromo extends StatelessWidget {
  const _AboutAppPromo({
    required this.colorScheme,
    required this.assetPath,
    required this.accentColor,
    required this.name,
    required this.tagline,
    required this.url,
    this.appId,
  });

  final ColorScheme colorScheme;
  final String assetPath;
  final Color accentColor;
  final String name;
  final String tagline;
  final String url;
  final String? appId;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Color containerColor = Color.alphaBlend(
      accentColor.withValues(alpha: 0.24),
      colorScheme.surfaceContainerHighest,
    );
    final RoundedRectangleBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: accentColor.withValues(alpha: 0.34)),
    );
    return Material(
      color: containerColor,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            appId != null ? _openPromoApp(appId!, url) : _openAboutUrl(url),
        onLongPress: () => _copyAboutUrl(url),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  assetPath,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: accentColor.withValues(alpha: 0.86),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutLegalLinks extends StatelessWidget {
  const _AboutLegalLinks({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AboutTextLink(
              label: tr('aboutWebsite'),
              url: _aboutObtainXWebsiteUrl,
              colorScheme: colorScheme,
            ),
            _AboutLinkSeparator(colorScheme: colorScheme),
            _AboutTextLink(
              label: tr('aboutPrivacyPolicy'),
              url: _aboutObtainXPrivacyUrl,
              colorScheme: colorScheme,
            ),
            _AboutLinkSeparator(colorScheme: colorScheme),
            _AboutTextLink(
              label: tr('aboutTerms'),
              url: _aboutObtainXTermsUrl,
              colorScheme: colorScheme,
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutTextLink extends StatelessWidget {
  const _AboutTextLink({
    required this.label,
    required this.url,
    required this.colorScheme,
  });

  final String label;
  final String url;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => _openAboutUrl(url),
      onLongPress: () => _copyAboutUrl(url),
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, maxLines: 1),
    );
  }
}

class _AboutLinkSeparator extends StatelessWidget {
  const _AboutLinkSeparator({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Text('•', style: TextStyle(color: colorScheme.onSurfaceVariant));
  }
}

Future<void> _openAboutUrl(String url) async {
  await launchUrlString(url, mode: LaunchMode.externalApplication);
}

Future<void> _openPromoApp(String appId, String webUrl) async {
  if (AppDistribution.fdroid) {
    try {
      final String deepLink = 'fdroid.app:$appId';
      final bool launched = await launchUrlString(
        deepLink,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      if (!launched) {
        await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
    }
  } else {
    await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
  }
}

Future<void> _copyAboutUrl(String url) async {
  await Clipboard.setData(ClipboardData(text: url));
  showMessage(tr('aboutLinkCopied'));
}

Future<void> _shareAboutUrl(String url, String subject) async {
  await SharePlus.instance.share(
    ShareParams(
      text: tr('aboutShareText', args: [url]),
      subject: subject,
    ),
  );
}

void _openLogsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext dialogContext) {
      return const LogsDialog(initialDays: 7);
    },
  );
}

class LogsDialog extends StatefulWidget {
  final int initialDays;
  const LogsDialog({super.key, required this.initialDays});

  @override
  State<LogsDialog> createState() => _LogsDialogState();
}

class _LogsDialogState extends State<LogsDialog> {
  String? logString;
  bool isLoading = true;
  late int selectedDays;
  List<int> days = [7, 5, 4, 3, 2, 1];

  @override
  void initState() {
    super.initState();
    selectedDays = widget.initialDays;
    fetchLogs(selectedDays);
  }

  void fetchLogs(int daysLimit) {
    setState(() {
      isLoading = true;
    });
    context
        .read<LogsProvider>()
        .get(
          after: DateTime.now().subtract(Duration(days: daysLimit)),
          limit: 500,
          orderBy: 'timestamp DESC',
        )
        .then((logsList) {
          if (!mounted) return;
          setState(() {
            final chronologicalLogs = logsList.reversed.toList();
            final String joinedLogs = chronologicalLogs
                .map((logEntry) => logEntry.toString())
                .join('\n\n');
            logString = joinedLogs.isNotEmpty ? joinedLogs : tr('noLogs');
            isLoading = false;
          });
        })
        .catchError((error) {
          if (!mounted) return;
          setState(() {
            logString = tr('noLogs');
            isLoading = false;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    final logsProvider = context.read<LogsProvider>();

    Future<String> getDiagnosticsText() async {
      final buffer = StringBuffer();
      buffer.writeln('=== ObtainX Diagnostic Log ===');
      // Captured before the first async gap below so context isn't used across
      // an await.
      final settingsProvider = context.read<SettingsProvider>();
      final appsProvider = context.read<AppsProvider>();

      try {
        final packageInfo = await getInstalledInfo(
          obtainiumId,
          printErr: false,
          includeOwnDebugBuild: true,
        );
        buffer.writeln(
          'App Version: ${packageInfo?.versionName ?? 'Unknown'} (code ${packageInfo?.versionCode ?? 'unknown'})',
        );
        buffer.writeln(
          'Package ID: ${packageInfo?.packageName ?? obtainiumId}',
        );
      } catch (exception) {
        buffer.writeln('App Version: Unknown (Error fetching package info)');
      }

      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        buffer.writeln(
          'Device: ${androidInfo.manufacturer} ${androidInfo.model} (${androidInfo.device})',
        );
        buffer.writeln(
          'Android Version: ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})',
        );
        buffer.writeln(
          'Supported ABIs: ${androidInfo.supportedAbis.join(', ')}',
        );
      } catch (exception) {
        buffer.writeln('Device Info: Unknown (Error fetching device info)');
      }

      buffer.writeln('Installer Mode: ${settingsProvider.installerMode}');
      buffer.writeln('Use Shizuku: ${settingsProvider.useShizuku}');
      buffer.writeln(
        'Background Updates: ${settingsProvider.enableBackgroundUpdates}',
      );
      buffer.writeln(
        'Parallel Downloads: ${settingsProvider.parallelDownloads}',
      );
      buffer.writeln('Tracked Apps: ${appsProvider.apps.length}');

      try {
        final notificationGranted = await Permission.notification.isGranted;
        buffer.writeln('Notifications Enabled: $notificationGranted');
      } catch (exception) {
        buffer.writeln(
          'Notifications Enabled: Unknown (Error checking permission)',
        );
      }

      final autoExportEnabled = settingsProvider.autoExportOnChanges;
      buffer.writeln('Auto-Export on Changes: $autoExportEnabled');
      if (autoExportEnabled) {
        try {
          final exportDir = await settingsProvider.getExportDir(
            requireAccess: false,
          );
          if (exportDir == null) {
            buffer.writeln('Export Directory: Not configured');
          } else {
            final accessGranted =
                await settingsProvider.getExportDir(
                  warnIfInaccessible: false,
                ) !=
                null;
            buffer.writeln(
              'Export Directory Configured: true (Access Present: $accessGranted)',
            );
          }
        } catch (exception) {
          buffer.writeln('Export Directory: Unknown (Error checking path)');
        }
      }

      final saveApkCopies = settingsProvider.saveDownloadedApkCopies;
      buffer.writeln('Save APK Copies: $saveApkCopies');
      if (saveApkCopies) {
        try {
          final apkSaveDir = await settingsProvider.getApkSaveDir(
            requireAccess: false,
          );
          if (apkSaveDir == null) {
            buffer.writeln('APK Save Directory: Not configured');
          } else {
            final accessGranted =
                await settingsProvider.getApkSaveDir(
                  warnIfInaccessible: false,
                ) !=
                null;
            buffer.writeln(
              'APK Save Directory Configured: true (Access Present: $accessGranted)',
            );
          }
        } catch (exception) {
          buffer.writeln('APK Save Directory: Unknown (Error checking path)');
        }
      }

      final githubPat = settingsProvider.getSettingString(
        GitHub.githubCredsKey,
      );
      final hasGithubPat = githubPat != null && githubPat.isNotEmpty;
      final githubPatValid =
          hasGithubPat && GitHub.hasValidatedPAT(githubPat, settingsProvider);
      buffer.writeln(
        'GitHub PAT: ${hasGithubPat ? "Saved" : "Not Saved"}${hasGithubPat ? " (Validated: $githubPatValid)" : ""}',
      );

      final gitlabPat = settingsProvider.getSettingString('gitlab-creds');
      final hasGitlabPat = gitlabPat != null && gitlabPat.isNotEmpty;
      final gitlabPatValid =
          hasGitlabPat && GitLab.hasValidatedPAT(gitlabPat, settingsProvider);
      buffer.writeln(
        'GitLab PAT: ${hasGitlabPat ? "Saved" : "Not Saved"}${hasGitlabPat ? " (Validated: $gitlabPatValid)" : ""}',
      );

      final vtApiKey = settingsProvider.getSettingString(virusTotalApiKeyKey);
      final hasVtApiKey = vtApiKey != null && vtApiKey.isNotEmpty;
      final vtApiKeyValid =
          hasVtApiKey && hasValidatedApiKey(vtApiKey, settingsProvider);
      buffer.writeln(
        'VirusTotal API Key: ${hasVtApiKey ? "Saved" : "Not Saved"}${hasVtApiKey ? " (Validated: $vtApiKeyValid)" : ""}',
      );

      buffer.writeln('===============================\n');

      return buffer.toString();
    }

    return AlertDialog(
      title: Text(tr('appLogs')),
      contentPadding: appDialogContentPadding,
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            appDropdownField<int>(
              key: ValueKey(selectedDays),
              context: context,
              value: selectedDays,
              enabled: !isLoading,
              menuWidth: appDropdownMenuWidth(
                context,
                days.map((int dayValue) => plural('day', dayValue)),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              items: days
                  .map(
                    (int dayValue) => DropdownMenuItem<int>(
                      value: dayValue,
                      child: Text(plural('day', dayValue)),
                    ),
                  )
                  .toList(),
              onChanged: (int? selectedValue) {
                if (selectedValue != null) {
                  selectedDays = selectedValue;
                  fetchLogs(selectedValue);
                }
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: isLoading
                  ? const Center(child: ExpressiveLoadingIndicator())
                  : Scrollbar(
                      child: SingleChildScrollView(
                        child: SelectableText(logString ?? ''),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: double.maxFinite,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () async {
                      final cont =
                          (await showDialog<Map<String, dynamic>?>(
                            context: context,
                            builder: (BuildContext modalContext) {
                              return GeneratedFormModal(
                                title: tr('appLogs'),
                                items: const [],
                                initValid: true,
                                message: tr('removeFromObtainX'),
                                primaryActionColour: Theme.of(
                                  modalContext,
                                ).colorScheme.error,
                              );
                            },
                          )) !=
                          null;
                      if (cont) {
                        unawaited(logsProvider.clear());
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    child: Text(tr('remove')),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(tr('close')),
                  ),
                  TextButton(
                    onPressed: () async {
                      final diagnostics = await getDiagnosticsText();
                      final logs = logString ?? '';
                      const int maxLogChars = 100000;
                      final String safeLogs = logs.length > maxLogChars
                          ? '[... Truncated ${logs.length - maxLogChars} characters. Use "Share as file" for full logs ...]\n\n${logs.substring(logs.length - maxLogChars)}'
                          : logs;
                      unawaited(
                        SharePlus.instance.share(
                          ShareParams(
                            text: '$diagnostics$safeLogs',
                            subject: tr('appLogs'),
                          ),
                        ),
                      );
                    },
                    child: Text(tr('share')),
                  ),
                  TextButton(
                    onPressed: () async {
                      final diagnostics = await getDiagnosticsText();
                      final timestampForFilename = DateTime.now()
                          .toIso8601String()
                          .replaceAll(':', '-');
                      final logFileName =
                          'obtainx-logs-$timestampForFilename.txt';
                      final logFile = XFile.fromData(
                        Uint8List.fromList(
                          utf8.encode('$diagnostics${logString ?? ''}'),
                        ),
                        mimeType: 'text/plain',
                        name: logFileName,
                      );
                      await SharePlus.instance.share(
                        ShareParams(
                          files: [logFile],
                          fileNameOverrides: [logFileName],
                          subject: tr('appLogs'),
                        ),
                      );
                    },
                    child: Text(tr('shareAsFile')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Canonical JSON for [GeneratedForm] key (prefs key order can vary).
String _stableCategoriesMapJson(Map<String, int> categories) {
  final List<MapEntry<String, int>> sorted =
      List<MapEntry<String, int>>.from(categories.entries)..sort(
        (MapEntry<String, int> left, MapEntry<String, int> right) =>
            left.key.compareTo(right.key),
      );
  return jsonEncode(Map<String, int>.fromEntries(sorted));
}

Map<String, MapEntry<int, bool>> _mergeCategoryEditorMaps(
  Map<String, int> fromPrefs,
  Map<String, MapEntry<int, bool>> previousSelections,
  Set<String> preselected,
) {
  final Map<String, MapEntry<int, bool>> merged =
      <String, MapEntry<int, bool>>{};
  for (final MapEntry<String, int> entry in fromPrefs.entries) {
    merged[entry.key] = MapEntry(
      entry.value,
      previousSelections[entry.key]?.value ?? preselected.contains(entry.key),
    );
  }
  for (final MapEntry<String, MapEntry<int, bool>> entry
      in previousSelections.entries) {
    if (!merged.containsKey(entry.key)) {
      merged[entry.key] = entry.value;
    }
  }
  final List<MapEntry<String, MapEntry<int, bool>>> sortedEntries =
      merged.entries.toList()..sort((a, b) {
        final int cmp = a.key.toLowerCase().compareTo(b.key.toLowerCase());
        if (cmp != 0) return cmp;
        return a.key.compareTo(b.key);
      });
  return Map<String, MapEntry<int, bool>>.fromEntries(sortedEntries);
}

class CategoryEditorSelector extends StatefulWidget {
  final void Function(List<String> categories)? onSelected;
  final bool singleSelect;
  final Set<String> preselected;
  final WrapAlignment alignment;
  final bool showLabelWhenNotEmpty;
  final bool showSelectedCheckmark;
  final bool showChangeIntentIcons;

  /// When false, only chips are shown (toggle selection). Add / edit / remove
  /// controls for the global category list are hidden.
  final bool allowCategoryManagement;
  const CategoryEditorSelector({
    super.key,
    this.onSelected,
    this.singleSelect = false,
    this.preselected = const {},
    this.alignment = WrapAlignment.start,
    this.showLabelWhenNotEmpty = true,
    this.showSelectedCheckmark = false,
    this.showChangeIntentIcons = true,
    this.allowCategoryManagement = true,
  });

  @override
  State<CategoryEditorSelector> createState() => _CategoryEditorSelectorState();
}

class _CategoryEditorSelectorState extends State<CategoryEditorSelector> {
  Map<String, MapEntry<int, bool>> storedValues = {};

  @override
  Widget build(BuildContext context) {
    // Select only categories so this widget doesn't rebuild on unrelated
    // settings changes (every SettingsProvider setter calls notifyListeners).
    final Map<String, int> fromPrefs = context
        .select<SettingsProvider, Map<String, int>>((s) => s.categories);
    final appsProvider = context
        .read<AppsProvider>(); // not watch: saveApps would rebuild form
    final Map<String, MapEntry<int, bool>> merged = _mergeCategoryEditorMaps(
      fromPrefs,
      storedValues,
      widget.preselected,
    );
    return GeneratedForm(
      key: ValueKey<String>(
        'categories_${_stableCategoriesMapJson(fromPrefs)}',
      ),
      items: [
        [
          GeneratedFormTagInput(
            'categories',
            label: tr('categories'),
            emptyMessage: tr('noCategories'),
            value: merged,
            alignment: widget.alignment,
            deleteConfirmationMessage: MapEntry(
              tr('deleteCategoriesQuestion'),
              tr('categoryDeleteWarning'),
            ),
            singleSelect: widget.singleSelect,
            showLabelWhenNotEmpty: widget.showLabelWhenNotEmpty,
            allowTagManagement: widget.allowCategoryManagement,
            showSelectedCheckmark: widget.showSelectedCheckmark,
            showChangeIntentIcons: widget.showChangeIntentIcons,
          ),
        ],
      ],
      onValueChanges: ((values, valid, isBuilding) {
        if (!isBuilding) {
          final Map<String, MapEntry<int, bool>> catMap =
              values['categories'] as Map<String, MapEntry<int, bool>>;
          storedValues = cloneCategoryTagInputValueMap(catMap);
          final Map<String, int> colorsByName = catMap.map(
            (key, value) => MapEntry(key, value.key),
          );
          final List<String> selected = catMap.keys
              .where((k) => catMap[k]!.value)
              .toList();
          widget.onSelected?.call(selected);
          context.read<SettingsProvider>().setCategories(
            colorsByName,
            appsProvider: appsProvider,
          );
        }
      }),
    );
  }
}

class _ExternalInstallerTile extends StatefulWidget {
  const _ExternalInstallerTile();

  @override
  State<_ExternalInstallerTile> createState() => _ExternalInstallerTileState();
}

class _ExternalInstallerTileState extends State<_ExternalInstallerTile> {
  Future<List<InstallerTarget>>? _targetsFuture;

  @override
  void initState() {
    super.initState();
    _targetsFuture = ExternalInstallerBridge.instance.listTargets();
  }

  InstallerTarget? _current(
    List<InstallerTarget> targets,
    SettingsProvider settingsProvider,
  ) {
    final String? package = settingsProvider.externalInstallerPackage;
    final String? activity = settingsProvider.externalInstallerComponent;
    if (package == null || activity == null) return null;
    for (final InstallerTarget target in targets) {
      if (target.package == package && target.activity == activity) {
        return target;
      }
    }
    return null;
  }

  Widget _targetIcon(InstallerTarget? target, {double size = 40}) {
    final Uint8List? icon = target?.icon;
    if (icon == null || icon.isEmpty) {
      return Icon(Icons.extension_outlined, size: size);
    }
    final int cacheSize = (size * MediaQuery.devicePixelRatioOf(context))
        .round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        icon,
        width: size,
        height: size,
        fit: BoxFit.contain,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        errorBuilder: (_, _, _) => Icon(Icons.extension_outlined, size: size),
      ),
    );
  }

  Future<void> _choose(
    List<InstallerTarget> targets,
    SettingsProvider settingsProvider,
  ) async {
    if (targets.isEmpty) return;
    final Map<String, List<InstallerTarget>> grouped = {};
    for (final InstallerTarget target in targets) {
      grouped.putIfAbsent(target.package, () => []).add(target);
    }
    for (final MapEntry<String, List<InstallerTarget>> entry
        in grouped.entries) {
      final Set<String> seenActivities = {};
      entry.value.removeWhere(
        (InstallerTarget target) => !seenActivities.add(target.activity),
      );
      entry.value.sort((InstallerTarget first, InstallerTarget second) {
        final String firstLabel =
            (first.activityLabel ?? first.activity.split('.').last)
                .toLowerCase();
        final String secondLabel =
            (second.activityLabel ?? second.activity.split('.').last)
                .toLowerCase();
        final bool firstIsInstaller = firstLabel.contains('install');
        final bool secondIsInstaller = secondLabel.contains('install');
        if (firstIsInstaller != secondIsInstaller) {
          return firstIsInstaller ? -1 : 1;
        }
        final int labelComparison = firstLabel.compareTo(secondLabel);
        if (labelComparison != 0) return labelComparison;
        return first.activity.toLowerCase().compareTo(
          second.activity.toLowerCase(),
        );
      });
    }
    grouped.removeWhere((_, List<InstallerTarget> targets) => targets.isEmpty);
    final List<MapEntry<String, List<InstallerTarget>>> entries = grouped
        .entries
        .toList();
    int expandedIndex = -1;
    final InstallerTarget? picked = await showAppModalSheet<InstallerTarget>(
      context: context,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext builderContext, StateSetter setSheetState) =>
            AppSheetContent(
              children: [
                Text(
                  tr('chooseExternalInstaller'),
                  style: Theme.of(builderContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                M3eExpressiveSettingsCard(
                  items: [
                    for (int index = 0; index < entries.length; index++)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            onTap: () {
                              final entry = entries[index];
                              if (entry.value.length == 1) {
                                Navigator.of(
                                  sheetContext,
                                ).pop(entry.value.first);
                              } else {
                                setSheetState(() {
                                  expandedIndex = expandedIndex == index
                                      ? -1
                                      : index;
                                });
                              }
                            },
                            leading: _targetIcon(
                              entries[index].value.first,
                              size: 36,
                            ),
                            title: Text(
                              entries[index].value.first.label,
                              style: Theme.of(
                                builderContext,
                              ).textTheme.titleSmall,
                            ),
                            subtitle: Text(
                              entries[index].key,
                              style: Theme.of(
                                builderContext,
                              ).textTheme.bodySmall,
                            ),
                            trailing: entries[index].value.length > 1
                                ? AnimatedRotation(
                                    turns: expandedIndex == index ? 0.5 : 0,
                                    duration: ExpressiveMotion.short,
                                    curve: ExpressiveMotion.emphasized,
                                    child: const Icon(Icons.expand_more),
                                  )
                                : null,
                          ),
                          AnimatedSize(
                            duration: ExpressiveMotion.medium,
                            curve: ExpressiveMotion.emphasized,
                            child: expandedIndex == index
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: entries[index].value
                                        .map(
                                          (InstallerTarget target) =>
                                              _activityChoiceRow(
                                                context: builderContext,
                                                target: target,
                                                siblings: entries[index].value,
                                                onTap: () => Navigator.of(
                                                  sheetContext,
                                                ).pop(target),
                                              ),
                                        )
                                        .toList(),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
      ),
    );
    if (picked == null) return;
    settingsProvider.externalInstallerPackage = picked.package;
    settingsProvider.externalInstallerComponent = picked.activity;
    if (mounted) setState(() {});
  }

  String _shortActivityName(
    InstallerTarget target,
    List<InstallerTarget> siblings,
  ) {
    final String shortName = target.activity.split('.').last;
    final bool hasDuplicate = siblings.any(
      (InstallerTarget sibling) =>
          sibling != target && sibling.activity.split('.').last == shortName,
    );
    return hasDuplicate ? target.activity : shortName;
  }

  String _activityDisplayLabel(
    InstallerTarget target,
    List<InstallerTarget> siblings,
  ) {
    return target.activityLabel ?? _shortActivityName(target, siblings);
  }

  String? _activityDisambiguator(
    InstallerTarget target,
    List<InstallerTarget> siblings,
  ) {
    final String? activityLabel = target.activityLabel;
    if (activityLabel == null) return null;
    final String normalizedLabel = activityLabel.toLowerCase();
    final int matchingLabelCount = siblings
        .where(
          (InstallerTarget sibling) =>
              sibling.activityLabel?.toLowerCase() == normalizedLabel,
        )
        .length;
    return matchingLabelCount > 1 ? _shortActivityName(target, siblings) : null;
  }

  Widget _activityChoiceRow({
    required BuildContext context,
    required InstallerTarget target,
    required List<InstallerTarget> siblings,
    required VoidCallback onTap,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String? disambiguator = _activityDisambiguator(target, siblings);
    final double cornerRadius = SettingsProvider.cardCornerRadiusForScale(
      14,
      context.read<SettingsProvider>().cardCornerScale,
    );
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(52, 3, 12, 3),
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsetsDirectional.fromSTEB(14, 2, 8, 2),
          minTileHeight: 48,
          title: Text(
            _activityDisplayLabel(target, siblings),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          subtitle: disambiguator == null
              ? null
              : Text(
                  disambiguator,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
          trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settingsProvider = context.watch<SettingsProvider>();
    return FutureBuilder<List<InstallerTarget>>(
      future: _targetsFuture,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<List<InstallerTarget>> snapshot,
          ) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
                leading: SizedBox.square(
                  dimension: 24,
                  child: ExpressiveLoadingIndicator(),
                ),
              );
            }
            final List<InstallerTarget> targets =
                snapshot.data ?? const <InstallerTarget>[];
            final InstallerTarget? current = _current(
              targets,
              settingsProvider,
            );
            final List<InstallerTarget> currentPackageTargets = targets
                .where(
                  (InstallerTarget target) =>
                      target.package == current?.package,
                )
                .toList();
            final int intentCount = currentPackageTargets
                .map((InstallerTarget target) => target.activity)
                .toSet()
                .length;
            final String subtitle = current != null
                ? intentCount > 1
                      ? '${current.label} · '
                            '${_activityDisplayLabel(current, currentPackageTargets)}'
                      : current.label
                : settingsProvider.externalInstallerPackage ??
                      tr('externalInstallerUnset');
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: _targetIcon(current),
              title: Text(tr('chooseExternalInstaller')),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.expand_more_rounded),
              onTap: () => _choose(targets, settingsProvider),
            );
          },
    );
  }
}

class _VerticalBarThumbShape extends SliderComponentShape {
  const _VerticalBarThumbShape();

  static const double _width = 4;
  static const double _height = 28;
  static const double _radius = 2;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(_width, _height);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    // Flutter's slider computes the framework-provided [center.dx] using
    // the FULL trackRect width:
    //   thumbX = trackRect.left + value * trackRect.width
    // ...but tick marks are inset on each side by trackHeight/2:
    //   tickX  = trackRect.left + value * (trackRect.width - trackHeight)
    //                           + trackHeight/2
    // The two only coincide at value == 0.5. Everywhere else the thumb
    // drifts off the tick proportionally to (value - 0.5) * trackHeight.
    // For a default 4dp track this drift is sub-pixel and unnoticeable;
    // for our M3E 16dp track it's a visible 8dp at the endpoints.
    //
    // Re-project the framework-provided center onto the tick-aligned
    // x-axis so the vertical bar thumb lands exactly on each dot.
    final Rect trackRect = sliderTheme.trackShape!.getPreferredRect(
      parentBox: parentBox,
      offset: Offset.zero,
      sliderTheme: sliderTheme,
      isEnabled: enableAnimation.value > 0,
      isDiscrete: isDiscrete,
    );
    final double trackHeight = trackRect.height;
    final double trackWidth = trackRect.width;
    Offset alignedCenter = center;
    if (trackWidth > trackHeight) {
      final double valueRatio = textDirection == TextDirection.rtl
          ? 1.0 - value
          : value;
      final double alignedX =
          trackRect.left +
          valueRatio * (trackWidth - trackHeight) +
          trackHeight / 2;
      alignedCenter = Offset(alignedX, center.dy);
    }
    final canvas = context.canvas;
    final paint = Paint()
      ..color = sliderTheme.thumbColor ?? Colors.white
      ..style = PaintingStyle.fill;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: alignedCenter, width: _width, height: _height),
      const Radius.circular(_radius),
    );
    canvas.drawRRect(rrect, paint);
  }
}

class _GappedTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const _GappedTrackShape();

  static const double _gap = 4;
  static const double _radius = 8;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final canvas = context.canvas;
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    // Re-project thumbCenter.dx onto the tick-aligned axis so the split
    // between active and inactive lanes coincides with the rendered
    // thumb position. See the long comment in [_VerticalBarThumbShape]
    // for why this re-projection is needed (Flutter's tick range is
    // inset by trackHeight/2 on each side; the framework-provided
    // thumbCenter is on the un-inset full-track axis).
    double thumbX = thumbCenter.dx;
    final double trackHeight = trackRect.height;
    final double trackWidth = trackRect.width;
    if (trackWidth > trackHeight) {
      final double valueRatio = ((thumbCenter.dx - trackRect.left) / trackWidth)
          .clamp(0.0, 1.0);
      thumbX =
          trackRect.left +
          valueRatio * (trackWidth - trackHeight) +
          trackHeight / 2;
    }

    final activePaint = Paint()
      ..color = (sliderTheme.activeTrackColor ?? Colors.blue);
    final inactivePaint = Paint()
      ..color = (sliderTheme.inactiveTrackColor ?? Colors.grey);

    // Active (left) track — up to thumb minus gap
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(
          trackRect.left,
          trackRect.top,
          thumbX - _gap,
          trackRect.bottom,
        ),
        topLeft: const Radius.circular(_radius),
        bottomLeft: const Radius.circular(_radius),
      ),
      activePaint,
    );

    // Inactive (right) track — from thumb plus gap
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(
          thumbX + _gap,
          trackRect.top,
          trackRect.right,
          trackRect.bottom,
        ),
        topRight: const Radius.circular(_radius),
        bottomRight: const Radius.circular(_radius),
      ),
      inactivePaint,
    );
  }
}
