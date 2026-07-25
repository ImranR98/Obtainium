import 'dart:async' show Timer, unawaited;
import 'dart:convert';
import 'dart:math' as math;

import 'package:animations/animations.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import 'package:expressive_refresh/expressive_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        PaintingContext,
        PipelineOwner,
        ScrollCacheExtent,
        RenderSliverMainAxisGroup,
        RenderProxySliver,
        SliverConstraints,
        SliverGeometry,
        LayerHandle,
        ClipRectLayer,
        SliverPhysicalParentData,
        RenderSliver;
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';
import 'package:obtainium/app_sources/apkmirror.dart';
import 'package:obtainium/components/app_bottom_sheet.dart';
import 'package:obtainium/components/app_dropdown_field.dart';
import 'package:obtainium/components/bulk_category_editor.dart';
import 'package:obtainium/components/bulk_update_sheet.dart';
import 'package:obtainium/components/category_action_chip.dart';
import 'package:obtainium/layout_breakpoints.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/empty_state_illustration.dart';
import 'package:obtainium/components/rippling_wavy_progress/circular.dart';
import 'package:obtainium/components/rippling_wavy_progress/linear.dart';
import 'package:obtainium/components/ui_widgets.dart' show ActionListTile;
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/date_time_format.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/pages/additional_options_page.dart';
import 'package:obtainium/pages/page_route_slide_up.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/pages/home.dart';
import 'package:obtainium/pages/settings.dart';
import 'package:obtainium/folders/app_folder.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/services/bulk_import_service.dart';
import 'package:obtainium/services/bulk_scan_cache.dart';
import 'package:obtainium/store_source_icons.dart';
import 'package:obtainium/theme/app_dialog_theme.dart';
import 'package:obtainium/theme/app_form_field_styles.dart';
import 'package:obtainium/theme/app_theme_accent.dart';
import 'package:obtainium/theme/app_segmented_button_theme.dart';
import 'package:obtainium/theme/m3e_expressive_list.dart';
import 'package:obtainium/widgets/help_hint_icon.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:markdown/markdown.dart' as md;

enum CategoryFilterIntent { neutral, include, exclude }

enum CategoryFilterMatchMode { any, all }

const int _maxFolderNameLength = 20;

CategoryFilterIntent nextCategoryFilterIntent(CategoryFilterIntent intent) =>
    switch (intent) {
      CategoryFilterIntent.neutral => CategoryFilterIntent.include,
      CategoryFilterIntent.include => CategoryFilterIntent.exclude,
      CategoryFilterIntent.exclude => CategoryFilterIntent.neutral,
    };

bool appCategoriesMatchFilter(
  Iterable<String> appCategories, {
  Set<String> includedCategories = const {},
  Set<String> excludedCategories = const {},
  CategoryFilterMatchMode matchMode = CategoryFilterMatchMode.any,
}) {
  final categorySet = appCategories.toSet();
  if (excludedCategories.intersection(categorySet).isNotEmpty) {
    return false;
  }
  if (includedCategories.isNotEmpty) {
    return switch (matchMode) {
      CategoryFilterMatchMode.any =>
        includedCategories.intersection(categorySet).isNotEmpty,
      CategoryFilterMatchMode.all => categorySet.containsAll(
        includedCategories,
      ),
    };
  }
  return true;
}

bool appIsTrackOnlyForFilter(App app) =>
    app.additionalSettings['trackOnly'] == true;

bool appIsUpToDateForFilter(App app) {
  return appIsUpToDateForFiltering(app);
}

bool appMatchesTriStateAttributeFilter({
  required bool attributeIsTrue,
  required CategoryFilterIntent intent,
}) {
  return switch (intent) {
    CategoryFilterIntent.neutral => true,
    CategoryFilterIntent.include => attributeIsTrue,
    CategoryFilterIntent.exclude => !attributeIsTrue,
  };
}

bool appMatchesUpToDateFilter(App app, CategoryFilterIntent intent) {
  return appMatchesTriStateAttributeFilter(
    attributeIsTrue: appIsUpToDateForFilter(app),
    intent: intent,
  );
}

bool appMatchesInstalledFilter(App app, CategoryFilterIntent intent) {
  return appMatchesTriStateAttributeFilter(
    attributeIsTrue: app.installedVersion != null,
    intent: intent,
  );
}

bool appMatchesTrackOnlyFilter(App app, CategoryFilterIntent intent) {
  return appMatchesTriStateAttributeFilter(
    attributeIsTrue: appIsTrackOnlyForFilter(app),
    intent: intent,
  );
}

String visibilityFilterChipLabel(String label, CategoryFilterIntent intent) {
  return switch (intent) {
    CategoryFilterIntent.neutral => label,
    CategoryFilterIntent.include => '+ $label',
    CategoryFilterIntent.exclude => '- $label',
  };
}

class _AppsGroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final int count;
  final bool isExpanded;
  final VoidCallback onTap;
  final double cardRadius;
  final double collapsedRadius;
  final ColorScheme colorScheme;

  _AppsGroupHeaderDelegate({
    required this.title,
    required this.count,
    required this.isExpanded,
    required this.onTap,
    required this.cardRadius,
    required this.collapsedRadius,
    required this.colorScheme,
  });

  @override
  double get minExtent =>
      SettingsProvider.collapsedHeaderHeight +
      SettingsProvider.collapsedHeaderGap;

  @override
  double get maxExtent =>
      SettingsProvider.collapsedHeaderHeight +
      SettingsProvider.collapsedHeaderGap;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        12,
        SettingsProvider.collapsedHeaderGap,
        12,
        0,
      ),
      child: M3eCollapsibleGroupHeader(
        title: title,
        count: count,
        isExpanded: isExpanded,
        onTap: onTap,
        collapsedRadius: collapsedRadius,
        colorScheme: colorScheme,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _AppsGroupHeaderDelegate oldDelegate) {
    return oldDelegate.title != title ||
        oldDelegate.count != count ||
        oldDelegate.isExpanded != isExpanded ||
        oldDelegate.cardRadius != cardRadius ||
        oldDelegate.collapsedRadius != collapsedRadius ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _ZOrderSliverMainAxisGroup extends SliverMainAxisGroup {
  /// Top-corner radius used to clip the scrolling content that tucks under the
  /// pinned group header. MUST equal the header's own top-corner radius
  /// ([_AppsGroupHeaderDelegate.collapsedRadius]); otherwise the content leaks
  /// through the crescent between the two mismatched corner arcs.
  final double headerTopRadius;

  const _ZOrderSliverMainAxisGroup({
    super.key,
    required super.slivers,
    required this.headerTopRadius,
  });

  @override
  RenderSliverMainAxisGroup createRenderObject(BuildContext context) {
    return _RenderZOrderSliverMainAxisGroup(headerTopRadius: headerTopRadius);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderZOrderSliverMainAxisGroup renderObject,
  ) {
    renderObject.headerTopRadius = headerTopRadius;
  }
}

class _RenderZOrderSliverMainAxisGroup extends RenderSliverMainAxisGroup {
  double headerTopRadius;

  _RenderZOrderSliverMainAxisGroup({required this.headerTopRadius});

  @override
  void paint(PaintingContext context, Offset offset) {
    if (childCount == 0) {
      return;
    }
    final List<RenderSliver> children = [];
    RenderSliver? child = firstChild;
    while (child != null) {
      children.add(child);
      child = childAfter(child);
    }

    double headerTop = 0.0;
    if (children.isNotEmpty) {
      final RenderSliver first = children[0];
      final SliverPhysicalParentData firstParentData =
          first.parentData! as SliverPhysicalParentData;
      // Visual top of the header card within the group's coordinate space.
      headerTop =
          firstParentData.paintOffset.dy + SettingsProvider.collapsedHeaderGap;
    }

    // Paint all content slivers first (from index 1 to N-1)
    for (int i = 1; i < children.length; i++) {
      final RenderSliver child = children[i];
      if (child.geometry?.visible == true) {
        final SliverPhysicalParentData childParentData =
            child.parentData! as SliverPhysicalParentData;

        final Rect bounds = Rect.fromLTRB(
          12.0,
          headerTop,
          constraints.crossAxisExtent - 12.0,
          headerTop + constraints.remainingPaintExtent + 2000.0,
        );

        final RRect clipRRect = RRect.fromRectAndCorners(
          bounds,
          topLeft: Radius.circular(headerTopRadius),
          topRight: Radius.circular(headerTopRadius),
        );

        context.pushClipRRect(needsCompositing, offset, bounds, clipRRect, (
          PaintingContext context,
          Offset offset,
        ) {
          context.paintChild(child, offset + childParentData.paintOffset);
        });
      }
    }

    // Paint the pinned header (index 0) last so it renders on top of the scrolling content
    if (children.isNotEmpty) {
      final RenderSliver first = children[0];
      if (first.geometry?.visible == true) {
        final SliverPhysicalParentData childParentData =
            first.parentData! as SliverPhysicalParentData;
        context.paintChild(first, offset + childParentData.paintOffset);
      }
    }
  }
}

typedef _AnimatedAppsGroupItemBuilder =
    Widget Function(BuildContext context, int index);

class _AnimatedAppsGroupBody extends StatefulWidget {
  const _AnimatedAppsGroupBody({
    super.key,
    required this.expanded,
    required this.itemCount,
    required this.itemBuilder,
  });

  final bool expanded;
  final int itemCount;
  final _AnimatedAppsGroupItemBuilder itemBuilder;

  @override
  State<_AnimatedAppsGroupBody> createState() => _AnimatedAppsGroupBodyState();
}

class _AnimatedAppsGroupBodyState extends State<_AnimatedAppsGroupBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _factor;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: kM3eGroupExpandDuration,
      reverseDuration: kM3eGroupCollapseDuration,
      value: widget.expanded ? 1.0 : 0.0,
    );
    // A single, idempotent 0..1 reveal factor drives the whole group body as
    // one unit (see [_SliverCollapseReveal]). Re-toggling mid-flight just
    // redirects THIS controller from its current value — it can never stack
    // overlapping per-item insert/remove transitions the way the old
    // SliverAnimatedList did, which is what let rapid header taps fan the tiles
    // out into "helicopter blade" ghost rows.
    _factor = CurvedAnimation(
      parent: _controller,
      curve: kM3eGroupTransitionCurve,
      reverseCurve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant _AnimatedAppsGroupBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != oldWidget.expanded) {
      if (widget.expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _factor.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SliverCollapseReveal(
      factor: _factor,
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          widget.itemBuilder,
          childCount: widget.itemCount,
        ),
      ),
    );
  }
}

/// Reveals/collapses a lazy child sliver as ONE unit by scaling its reported
/// extents (and clipping its paint) by a single [factor] animation — a
/// sliver-level equivalent of [SizeTransition], but for a `SliverList` instead
/// of a box.
///
/// Why not animate each tile in/out individually: a per-item approach uses
/// imperative, non-cancellable insert/remove animations, so interrupting a
/// collapse with an expand (rapid header taps) leaves both sets of transitions
/// in flight at once and their half-sized rows show through as ghosts. A single
/// re-targetable factor has no such state to desync.
///
/// Laziness is preserved: when fully collapsed the child is laid out with zero
/// remaining extent so a `SliverList` builds no tiles (important when many
/// groups are collapsed simultaneously); only the group actually
/// expanding/animating builds the tiles the viewport needs.
class _SliverCollapseReveal extends SingleChildRenderObjectWidget {
  const _SliverCollapseReveal({required this.factor, required Widget sliver})
    : super(child: sliver);

  final Animation<double> factor;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSliverCollapseReveal(factor: factor);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSliverCollapseReveal renderObject,
  ) {
    renderObject.factor = factor;
  }
}

class _RenderSliverCollapseReveal extends RenderProxySliver {
  _RenderSliverCollapseReveal({required this._factor});

  // Plain field + explicit setter (not `final`): the setter re-wires the
  // relayout listener when the widget hands us a new animation instance.
  Animation<double> _factor;
  Animation<double> get factor => _factor;
  set factor(Animation<double> value) {
    if (identical(_factor, value)) return;
    if (attached) _factor.removeListener(markNeedsLayout);
    _factor = value;
    if (attached) _factor.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  final LayerHandle<ClipRectLayer> _clipHandle = LayerHandle<ClipRectLayer>();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _factor.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _factor.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void dispose() {
    _clipHandle.layer = null;
    super.dispose();
  }

  @override
  void performLayout() {
    final SliverConstraints constraints = this.constraints;
    final double f = _factor.value.clamp(0.0, 1.0).toDouble();

    if (f <= 0.0) {
      // Fully collapsed: starve the child of room so a lazy SliverList builds
      // no tiles, and occupy no space in the scroll.
      child!.layout(
        constraints.copyWith(
          remainingPaintExtent: 0.0,
          remainingCacheExtent: 0.0,
          overlap: 0.0,
        ),
        parentUsesSize: true,
      );
      geometry = SliverGeometry.zero;
      return;
    }

    child!.layout(constraints, parentUsesSize: true);
    final SliverGeometry childGeometry = child!.geometry!;

    if (f >= 1.0) {
      geometry = childGeometry;
      return;
    }

    // Uniformly shrink the child's extents by the reveal factor. Because
    // layoutExtent scales too, the slivers below slide up/down smoothly as the
    // group grows/collapses.
    final double paintExtent = math.min(
      childGeometry.paintExtent * f,
      constraints.remainingPaintExtent,
    );
    final double layoutExtent = math.min(
      childGeometry.layoutExtent * f,
      paintExtent,
    );
    geometry = SliverGeometry(
      scrollExtent: childGeometry.scrollExtent * f,
      paintExtent: paintExtent,
      layoutExtent: layoutExtent,
      maxPaintExtent: childGeometry.maxPaintExtent * f,
      hasVisualOverflow: true,
      cacheExtent: childGeometry.cacheExtent,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || geometry == null || !geometry!.visible) {
      _clipHandle.layer = null;
      return;
    }
    final double f = _factor.value.clamp(0.0, 1.0).toDouble();
    if (f >= 1.0) {
      _clipHandle.layer = null;
      context.paintChild(child!, offset);
      return;
    }
    // The child paints its tiles top-anchored from the sliver origin; clip to
    // the revealed extent so tiles are hidden from the bottom up (matching a
    // top-aligned SizeTransition).
    final double paintExtent = geometry!.paintExtent;
    final Rect clipRect;
    switch (constraints.axis) {
      case Axis.vertical:
        clipRect = Rect.fromLTWH(
          0,
          0,
          constraints.crossAxisExtent,
          paintExtent,
        );
      case Axis.horizontal:
        clipRect = Rect.fromLTWH(
          0,
          0,
          paintExtent,
          constraints.crossAxisExtent,
        );
    }
    _clipHandle.layer = context.pushClipRect(
      needsCompositing,
      offset,
      clipRect,
      (PaintingContext context, Offset offset) =>
          context.paintChild(child!, offset),
      clipBehavior: Clip.hardEdge,
      oldLayer: _clipHandle.layer,
    );
  }
}

// Android ApplicationInfo flag constants used for app type classification.
const int _androidFlagSystem = 1; // ApplicationInfo.FLAG_SYSTEM
const int _androidFlagUpdatedSystemApp =
    128; // ApplicationInfo.FLAG_UPDATED_SYSTEM_APP

/// App type groups for the "Group by App Type" feature.
enum AppTypeGroup { user, system, privileged }

/// Returns the [AppTypeGroup] for a given [AppInMemory] based on Android package flags.
/// Non-installed apps (no [AppInMemory.installedInfo]) are treated as user apps.
AppTypeGroup classifyAppType(AppInMemory app) {
  final info = app.installedInfo;
  if (info == null) return AppTypeGroup.user;
  final flags = info.applicationInfo?.flags ?? 0;
  final isSystem =
      (flags & _androidFlagSystem) != 0 ||
      (flags & _androidFlagUpdatedSystemApp) != 0;
  if (!isSystem) return AppTypeGroup.user;
  // Privileged: system app NOT updated by the user that lives in a privileged partition.
  final isUpdatedByUser = (flags & _androidFlagUpdatedSystemApp) != 0;
  if (!isUpdatedByUser) {
    final sourceDir = info.applicationInfo?.sourceDir ?? '';
    if (sourceDir.contains('/priv-app/') ||
        sourceDir.contains('/framework/') ||
        sourceDir.startsWith('/vendor/') ||
        sourceDir.startsWith('/odm/') ||
        sourceDir.startsWith('/oem/')) {
      return AppTypeGroup.privileged;
    }
  }
  return AppTypeGroup.system;
}

/// A labeled row with an info tooltip and a [Switch], used in the view-options sheet.
// `_GroupToggleRow` was here. Removed in favour of [SwitchListTile] at
// the call sites for consistency with the other rows in
// [showAppsViewOptionsSheet] (whole-row tap target, built-in InkWell,
// matching font and padding).

/// Fingerprint so [AppsPage] rebuilds only when app-list data changes,
/// not on every [AppsProvider.notifyListeners] (e.g. download-progress ticks
/// or icon-load completions — icons are watched per-row by [_AppIconWidget]).
/// [AppsProvider.appsListRevision] avoids hashing every app for each of those
/// notifications, which is important while new rows lazily load their icons.
int _appsPageAppsRebuildToken(AppsProvider provider) {
  return Object.hash(
    provider.loadingApps,
    provider.areDownloadsRunning(),
    provider.appsListRevision,
    provider.apps.length,
    provider.pendingUpdateCount,
  );
}

/// Progress bar shown during pull-to-refresh and initial app-load.
///
/// Subscribes to [AppsProvider] via a narrow [context.select] that returns
/// only `(loadingApps, refreshProgressNotifier)`. The notifier updates this
/// widget without notifying the provider, so the surrounding [AppsPage]
/// (filter / sort / sliver list) does not rescan the whole app collection.
///
/// App metadata changes advance [AppsProvider.appsListRevision] once after the
/// batched save, while intermediate progress stays isolated here.
class _RefreshProgressBar extends StatelessWidget {
  const _RefreshProgressBar({required this.refreshingSince});

  final DateTime? refreshingSince;

  @override
  Widget build(BuildContext context) {
    final (bool loadingApps, ValueNotifier<double?> progressNotifier) = context
        .select<AppsProvider, (bool, ValueNotifier<double?>)>(
          (p) => (p.loadingApps, p.refreshProgressNotifier),
        );
    // M3 Expressive linear progress indicator. Wavy active track with a
    // stop-dot at the end (per the M3E spec). The widget draws two
    // separate lanes (active above, track below) with a fixed gap so the
    // active and inactive segments never overlap.
    return ValueListenableBuilder<double?>(
      valueListenable: progressNotifier,
      builder: (context, refreshProgress, _) =>
          LinearRipplingWavyProgressIndicator(
            value: loadingApps
                ? null
                : (refreshProgress ?? (refreshingSince != null ? 1.0 : 0.0)),
          ),
    );
  }
}

/// An isolated icon widget that subscribes only to its own app's icon bytes.
/// When an icon finishes loading, only this widget rebuilds — not [AppsPage].
class _AppIconWidget extends StatelessWidget {
  const _AppIconWidget({required this.appId});

  final String appId;

  @override
  Widget build(BuildContext context) {
    final (Uint8List? icon, bool notInstalled) = context
        .select<AppsProvider, (Uint8List?, bool)>((p) {
          final a = p.apps[appId];
          return (a?.icon, a?.installedInfo == null);
        });
    if (icon != null) {
      final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      final int iconCachePx = (40 * devicePixelRatio).round();
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          icon,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: iconCachePx,
          cacheHeight: iconCachePx,
          filterQuality: FilterQuality.low,
          opacity: AlwaysStoppedAnimation(notInstalled ? 0.6 : 1.0),
        ),
      );
    }
    // Placeholder shown while the icon is still loading.
    return SizedBox(
      width: 40,
      height: 40,
      child: Center(
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.rotationZ(0.31),
          child: Image(
            image: const AssetImage('assets/graphics/icon_small.png'),
            width: 28,
            height: 28,
            fit: BoxFit.contain,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.3),
            colorBlendMode: BlendMode.modulate,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}

/// A single row in the apps list.
///
/// Pushes [AppPage] with a bottom sheet style slide-up so it reads as opening
/// from the bottom bar / actions.

/// Subscribes directly to [AppsProvider] for [AppInMemory.downloadProgress]
/// so download-progress ticks only rebuild the one row that is downloading,
/// not the entire page.  All other per-row data is received from the parent
/// (already gated behind the page-level list-build token).
class _AppListItem extends StatelessWidget {
  const _AppListItem({
    required this.appId,
    required this.isSelected,
    required this.areDownloadsRunning,
    required this.iconWidget,
    required this.onTap,
    required this.onLongPress,
    required this.highlightTouchTargets,
    required this.categoryColors,
    required this.showAppTypeBadge,
    required this.showTrackedStoreBadge,
    required this.showCategoriesBadge,
    required this.showCheckmark,
    this.sourceHost,
    this.itemBorderRadius,
    this.isSplitPaneActive = false,
  });

  final String appId;
  final bool isSelected;
  final bool areDownloadsRunning;
  final Widget iconWidget;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool highlightTouchTargets;
  final Map<String?, int> categoryColors;
  final bool showAppTypeBadge;
  final bool showTrackedStoreBadge;
  final bool showCategoriesBadge;
  final String? sourceHost;
  final BorderRadius? itemBorderRadius;
  final bool showCheckmark;

  /// The current app in the landscape two-pane layout (its detail is shown in
  /// the side pane). Communicated with a tinted fill + deeper shadow rather
  /// than the multi-select outline, so it doesn't look like a selected row.
  final bool isSplitPaneActive;

  @override
  Widget build(BuildContext context) {
    // Full app data — rebuilds when any field changes (gated by page token).
    final AppInMemory? app = context.select<AppsProvider, AppInMemory?>(
      (p) => p.apps[appId],
    );
    if (app == null) return const SizedBox.shrink();

    // Download progress watched independently so only this row rebuilds on ticks.
    final double? downloadProgress = context.select<AppsProvider, double?>(
      (p) => p.apps[appId]?.downloadProgress,
    );

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final Size screenSize = MediaQuery.sizeOf(context);
    final double screenWidth = screenSize.width;
    final bool isLargeScreen =
        screenWidth >= kLargeScreenWidthBreakpoint &&
        !context.read<SettingsProvider>().isTV &&
        !context.read<SettingsProvider>().alwaysUsePhoneLayout;
    final bool hideVersionAndChangelog =
        MediaQuery.orientationOf(context) == Orientation.landscape &&
        screenSize.shortestSide < kTabletShortestSideBreakpoint;

    final showChangesFn = getChangeLogFn(context, app.app);
    final installed = app.app.installedVersion;
    final skipActive = isSkipActiveForCurrentLatest(app.app);
    final hasUpdate = installed != null && appHasActionableUpdate(app.app);
    final hasUncertainUpdate =
        installed != null && versionOrderUncertainUpdate(app.app);
    final settingsProvider = context.read<SettingsProvider>();
    final source = SourceProvider().getSourceTemplate(
      app.app.url,
      overrideSource: app.app.overrideSource,
    );
    final buildVerificationBlocked = buildVerificationEnforcementBlocksInstall(
      app.app,
      source,
      settingsProvider,
    );
    final String buildVerificationBlockedMessage =
        buildVerificationEnforcedBlockedMessage(
          app.app,
          source,
          settingsProvider,
        );

    void onUpdateOrOpenReleasePressed() {
      if (buildVerificationBlocked) {
        showError(ObtainiumError(buildVerificationBlockedMessage));
        return;
      }
      final trackOnly = app.app.additionalSettings['trackOnly'] == true;
      if (trackOnly) {
        launchUrlString(
          trackOnlyDownloadPageUrl(app.app),
          mode: LaunchMode.externalApplication,
        );
      } else {
        context
            .read<AppsProvider>()
            .downloadAndInstallLatestApps([
              app.app.id,
            ], globalNavigatorKey.currentContext)
            .catchError((e) {
              if (!context.mounted) return <String>[];
              showError(e);
              return <String>[];
            });
      }
    }

    Widget buildUpdateButton() {
      final trackOnly = app.app.additionalSettings['trackOnly'] == true;
      return IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        color: colorScheme.primary,
        tooltip: buildVerificationBlocked
            ? buildVerificationBlockedMessage
            : trackOnly
            ? tr('openDownloadPage')
            : tr('update'),
        onPressed: areDownloadsRunning || buildVerificationBlocked
            ? null
            : onUpdateOrOpenReleasePressed,
        icon: const Icon(Icons.install_mobile),
      );
    }

    Widget buildUncertainUpdateButton() {
      return IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        color: colorScheme.primary,
        tooltip: buildVerificationBlocked
            ? buildVerificationBlockedMessage
            : tr('uncertainUpdateTooltip'),
        onPressed: areDownloadsRunning || buildVerificationBlocked
            ? null
            : onUpdateOrOpenReleasePressed,
        icon: const Icon(Icons.help_outline),
      );
    }

    Widget buildSkippedVersionIcon() {
      return Tooltip(
        message: tr('latestVersionSkipped'),
        child: SizedBox.square(
          dimension: 32,
          child: Center(
            child: Icon(
              Icons.skip_next_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final String versionText = app.app.installedVersion ?? tr('none');
    final String changesButtonString = app.app.releaseDate == null
        ? (showChangesFn != null ? tr('changes') : '')
        : formatDeviceOrderedNumericDate(context, app.app.releaseDate!);

    final bool hasTrailingWidgets =
        skipActive ||
        (!skipActive && hasUpdate) ||
        (!skipActive && !hasUpdate && hasUncertainUpdate);

    final Widget? trailingRow = (hideVersionAndChangelog && !hasTrailingWidgets)
        ? null
        : ConstrainedBox(
            // ListTile measures trailing before title/subtitle. Bound the
            // secondary version/date column so app and developer names keep
            // the larger share of the row and truncate last.
            constraints: BoxConstraints(maxWidth: screenWidth * 0.32),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!hideVersionAndChangelog)
                  Flexible(
                    child: GestureDetector(
                      onTap: showChangesFn,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: highlightTouchTargets && showChangesFn != null
                              ? (theme.brightness == Brightness.light
                                        ? theme.primaryColor
                                        : theme.primaryColorLight)
                                    .withAlpha(
                                      theme.brightness == Brightness.light
                                          ? 20
                                          : 40,
                                    )
                              : null,
                        ),
                        padding: highlightTouchTargets
                            ? const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 0)
                            : EdgeInsets.zero,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              versionText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: isVersionPseudo(app.app)
                                  ? const TextStyle(fontStyle: FontStyle.italic)
                                  : null,
                            ),
                            Text(
                              changesButtonString,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                decoration: showChangesFn != null
                                    ? TextDecoration.underline
                                    : TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!hideVersionAndChangelog && hasTrailingWidgets)
                  const SizedBox(width: 5),
                if (skipActive) buildSkippedVersionIcon(),
                if (!skipActive && hasUpdate) buildUpdateButton(),
                if (!skipActive && !hasUpdate && hasUncertainUpdate)
                  buildUncertainUpdateButton(),
              ],
            ),
          );

    Widget buildDownloadProgressControl() {
      final double activeDownloadProgress = downloadProgress ?? 0;
      final bool isScanning =
          downloadProgress != null && activeDownloadProgress == -2;
      final bool isInstalling =
          downloadProgress != null && activeDownloadProgress == -1;
      final bool isBusy = isScanning || isInstalling;
      final double? progressValue = isBusy
          ? null
          : (activeDownloadProgress / 100).clamp(0.0, 1.0);
      return Semantics(
        label: isScanning
            ? tr('scanningWithVirusTotal')
            : isInstalling
            ? tr('installing')
            : tr(
                'percentProgress',
                args: [activeDownloadProgress.toInt().toString()],
              ),
        button: !isBusy,
        child: SizedBox.square(
          dimension: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.square(
                dimension: 48,
                child: CircularRipplingWavyProgressIndicator(
                  value: progressValue,
                  size: CircularProgressM3ESize.s,
                  activeColor: isBusy
                      ? colorScheme.secondary
                      : colorScheme.primary,
                ),
              ),
              if (!isBusy)
                IconButton.filledTonal(
                  tooltip: tr('cancel'),
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(32),
                    minimumSize: const Size.square(32),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: colorScheme.errorContainer,
                    foregroundColor: colorScheme.onErrorContainer,
                  ),
                  icon: const Icon(Icons.stop_rounded, size: 19),
                  onPressed: () =>
                      context.read<AppsProvider>().cancelDownload(app.app.id),
                ),
            ],
          ),
        ),
      );
    }

    final int transparent = colorScheme.surface.withValues(alpha: 0).toARGB32();

    final bool pinned = app.app.pinned;
    // Pinned rows get a tonal fill (constant, persistent — pinning is a
    // set-and-forget intent). Selected rows get an outline + a subtle
    // 1dp lift + a checkmark on the leading icon (transient, action-mode
    // affordance). The two states are on completely orthogonal axes —
    // fill vs. stroke vs. icon-replacement — so a row that is BOTH
    // pinned and selected reads as "filled, framed, and check-marked"
    // with no visual collision.
    //
    // Alpha tuned per brightness: M3 secondaryContainer-ish saturation in
    // light mode is naturally stronger than dark, so dark gets a touch
    // more alpha to match perceptual contrast.
    final bool showBlackThemeOutline = colorScheme.usesPureBlackBackgrounds;
    final Color rowFillColor = pinned && !showBlackThemeOutline
        ? Color.alphaBlend(
            colorScheme.primary.withValues(
              alpha: colorScheme.brightness == Brightness.light ? 0.10 : 0.14,
            ),
            m3eGroupedListRowFill(colorScheme),
          )
        : m3eGroupedListRowFill(colorScheme);

    // App-type badge at bottom-right of icon — icon only, no background.
    final appType = classifyAppType(app);
    final (IconData appTypeIcon, Color appTypeColor) = switch (appType) {
      AppTypeGroup.user => (Icons.person_rounded, Colors.green),
      AppTypeGroup.system => (Icons.android_rounded, Colors.grey),
      AppTypeGroup.privileged => (Icons.security_rounded, Colors.grey.shade600),
    };
    // App type badge on icon (gated by showAppTypeBadge).
    final Widget iconWithBadge = showAppTypeBadge
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              iconWidget,
              Positioned(
                right: -3,
                bottom: -3,
                child: Icon(appTypeIcon, size: 14, color: appTypeColor),
              ),
            ],
          )
        : iconWidget;

    // When the row is selected, the app icon is replaced with a primary
    // circle + checkmark — Material's standard "selected list item" lead
    // affordance, the same vocabulary M3 uses for selected contacts.
    // This is the third orthogonal selection cue (alongside the row
    // outline and 1dp lift) and is what makes selection unmistakable in
    // multi-select mode without leaning on a fill that would collide
    // with the pinned-row tonal fill.
    final Widget leadingIconForSlot = showCheckmark
        ? Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.check_rounded,
              color: colorScheme.onPrimary,
              size: 24,
            ),
          )
        : iconWithBadge;

    // Leading = [icon+type-badge or check] + [store column] inside ListTile.leading.
    // Store column keeps title position stable when showTrackedStoreBadge is true;
    // collapses when showTrackedStoreBadge is false so content on the right can expand.
    final Widget leadingWidget = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        leadingIconForSlot,
        if (showTrackedStoreBadge) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: 20,
            child: Center(
              child: sourceHost != null
                  ? Transform.scale(
                      scale: 1.25,
                      child: StoreSourceListBadge(host: sourceHost!),
                    )
                  : null,
            ),
          ),
        ],
      ],
    );

    // The landscape two-pane active card is shown WITHOUT an outline (that
    // reads as a multi-select row). Instead it gets a primary-tinted fill and a
    // deeper shadow so it stands out as "the one open in the side pane".
    final Color effectiveFillColor = isSplitPaneActive
        ? Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.18),
            rowFillColor,
          )
        : rowFillColor;

    final Widget tile = Container(
      decoration: BoxDecoration(
        color: effectiveFillColor,
        // Match the per-row corner radius the parent grouped-list ClipRRect
        // applies. Without this, the outline below paints to the
        // rectangular bounds and gets clipped at the rounded edge.
        borderRadius: itemBorderRadius,
        // Outline-only treatment for multi-SELECTED rows. [Border.all] paints
        // inside the box bounds so the outline doesn't push neighbours
        // around. ~0.7 alpha so the line reads as "framed" without
        // looking as loud as a button. Pinned uses fill, so the two
        // signals never collide — a selected pinned card cleanly shows
        // tonal fill (pinned) plus outline (selected). The two-pane active
        // card intentionally has no outline (see [effectiveFillColor]).
        border: isSelected
            ? Border.all(
                color: colorScheme.primary.withValues(alpha: 0.7),
                width: 1.5,
              )
            : showBlackThemeOutline
            ? Border.fromBorderSide(m3ePureBlackOutlineSide(colorScheme))
            : null,
        // Subtle lift on selected rows and a deeper lift on the two-pane
        // active card. M3 elevation as a "this row is the current target" cue.
        boxShadow: (isSelected || isSplitPaneActive)
            ? [
                BoxShadow(
                  color: colorScheme.shadow.withValues(
                    alpha: isSplitPaneActive ? 0.12 : 0.06,
                  ),
                  offset: Offset(0, isSplitPaneActive ? 2 : 1),
                  blurRadius: isSplitPaneActive ? 5 : 2,
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          if (!showCategoriesBadge && app.app.categories.isNotEmpty)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 5,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: app.app.categories.map((category) {
                    return Expanded(
                      child: Container(
                        color: Color(
                          categoryColors[category] ?? transparent,
                        ).withAlpha(255),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: Colors.transparent,
                child: ListTile(
                  shape: itemBorderRadius == null
                      ? null
                      : RoundedRectangleBorder(borderRadius: itemBorderRadius!),
                  tileColor: Colors.transparent,
                  // Selection no longer uses [selectedTileColor]; the visual
                  // treatment lives in the parent [Container] (outline + 1dp
                  // shadow) and on the leading icon (replaced with a checkmark
                  // when selected). Keeping the ListTile fill transparent on
                  // both states preserves the pinned-fill underneath.
                  selectedTileColor: Colors.transparent,
                  selected: isSelected,
                  onLongPress: onLongPress,
                  contentPadding: EdgeInsetsDirectional.only(
                    start: isLargeScreen ? 12 : 16,
                    end: hasTrailingWidgets ? 4 : (isLargeScreen ? 12 : 16),
                  ),
                  horizontalTitleGap: 8,
                  leading: leadingWidget,
                  title: Row(
                    children: [
                      if (pinned)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: Icon(
                            Icons.push_pin_rounded,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          app.name,
                          maxLines: 1,
                          style: TextStyle(
                            overflow: TextOverflow.ellipsis,
                            fontWeight: pinned
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    tr('byX', args: [app.author]),
                    maxLines: 1,
                    style: TextStyle(
                      overflow: TextOverflow.ellipsis,
                      fontWeight: pinned ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: downloadProgress != null
                      ? buildDownloadProgressControl()
                      : trailingRow,
                  onTap: onTap,
                ),
              ),
              if (showCategoriesBadge && app.app.categories.isNotEmpty)
                GestureDetector(
                  // Opaque so the whole row (padding and gaps between chips)
                  // is tappable, not just the pixels covering a chip — the
                  // default deferToChild left most of this row dead to taps.
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  onLongPress: onLongPress,
                  // Full-width child: the parent Column is start-aligned, so a
                  // content-sized child would leave the space to the right of
                  // the last chip a dead zone. Stretch to the card edge so the
                  // entire row is tappable, left to right.
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: isLargeScreen ? 12 : 16,
                        right: isLargeScreen ? 12 : 16,
                        bottom: 8,
                      ),
                      child: _CategoryChipsRow(
                        categories: app.app.categories,
                        categoryColors: categoryColors,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    if (itemBorderRadius != null) {
      return RepaintBoundary(
        child: Material(
          color: effectiveFillColor,
          shape: RoundedRectangleBorder(borderRadius: itemBorderRadius!),
          clipBehavior: Clip.antiAlias,
          child: tile,
        ),
      );
    }
    return RepaintBoundary(child: tile);
  }
}

/// Opens the full-screen Additional Options page (same transition as [AppPage]) or in split-pane second panel.
Future<void> _openAdditionalOptionsModal(
  String appId,
  BuildContext context,
) async {
  final appsProvider = context.read<AppsProvider>();
  if (appsProvider.apps[appId] == null) return;
  if (!context.mounted) return;

  final double screenWidth = MediaQuery.sizeOf(context).width;
  final bool isLargeScreen =
      screenWidth >= kLargeScreenWidthBreakpoint &&
      !context.read<SettingsProvider>().isTV &&
      !context.read<SettingsProvider>().alwaysUsePhoneLayout;

  if (isLargeScreen) {
    final appsPageState = context.findAncestorStateOfType<AppsPageState>();
    if (appsPageState != null) {
      appsPageState.openAppById(appId, autoScroll: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appsPageState.detailsNavKey?.currentState?.push(
          slideUpPageRoute((_) => AdditionalOptionsPage(appId: appId)),
        );
      });
    }
  } else {
    await Navigator.push<void>(
      context,
      slideUpPageRoute((_) => AdditionalOptionsPage(appId: appId)),
    );
  }
}

/// Wraps a list row with horizontal-swipe action hints.
/// The left/right actions are configurable via [SettingsProvider].
class _SwipeableListItem extends StatefulWidget {
  const _SwipeableListItem({
    super.key,
    required this.appId,
    required this.hasUpdate,
    required this.isPinned,
    required this.isInstalled,
    required this.areDownloadsRunning,
    required this.keepAlive,
    required this.rightAction,
    required this.leftAction,
    required this.child,
    this.appsListHeroFolderId,
  });

  final String appId;
  final String? appsListHeroFolderId;
  final bool hasUpdate;
  final bool isPinned;
  final bool isInstalled;
  final bool areDownloadsRunning;
  final bool keepAlive;
  final SwipeAction rightAction;
  final SwipeAction leftAction;
  final Widget child;

  @override
  State<_SwipeableListItem> createState() => _SwipeableListItemState();
}

class _SwipeableListItemState extends State<_SwipeableListItem>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  double _dragOffset = 0;

  // Eases [_dragOffset] back to 0 on release so the revealed action (icon +
  // label) slides and fades out smoothly instead of snapping — mirroring
  // Remember's swipe-reveal behaviour.
  //
  // Created eagerly in initState (not a `late final` inline initializer): a
  // lazy initializer would run on first access, and for rows that are never
  // swiped the first access is dispose(), which would construct the ticker
  // during an ancestor lookup on an already-deactivated element.
  late final AnimationController _settleController;
  Animation<double>? _settleAnimation;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _settleController.dispose();
    super.dispose();
  }

  void _settleToZero() {
    _settleController.stop();
    _settleAnimation =
        Tween<double>(begin: _dragOffset, end: 0.0).animate(
          CurvedAnimation(parent: _settleController, curve: Curves.easeOut),
        )..addListener(() {
          setState(() => _dragOffset = _settleAnimation!.value);
        });
    _settleController
      ..reset()
      ..forward();
  }

  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void didUpdateWidget(_SwipeableListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepAlive != widget.keepAlive) updateKeepAlive();
  }

  bool _canExecute(SwipeAction action) {
    switch (action) {
      case SwipeAction.update:
        return (widget.hasUpdate || !widget.isInstalled) &&
            !widget.areDownloadsRunning;
      case SwipeAction.open:
        return widget.isInstalled;
      case SwipeAction.none:
        return false;
      default:
        return true;
    }
  }

  /// Swipe-reveal label reflecting the card's current state: "Update" vs
  /// "Install" depending on whether the app is installed, and "Pin" vs "Unpin"
  /// depending on whether it's already pinned. Other actions use their generic
  /// [SwipeAction] label.
  String _actionLabel(SwipeAction action) {
    switch (action) {
      case SwipeAction.update:
        return widget.isInstalled ? tr('update') : tr('install');
      case SwipeAction.pin:
        return widget.isPinned ? tr('unpin') : tr('pin');
      default:
        return tr('swipeAction_${action.name}');
    }
  }

  (IconData, Color) _actionVisuals(SwipeAction action, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (action) {
      case SwipeAction.update:
        return (Icons.install_mobile, Colors.green);
      case SwipeAction.pin:
        return (
          widget.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
          cs.primary,
        );
      case SwipeAction.appOptions:
        return (Icons.tune, cs.primary);
      case SwipeAction.edit:
        return (Icons.edit_outlined, Colors.blue);
      case SwipeAction.delete:
        return (Icons.delete_outline, Colors.red);
      case SwipeAction.open:
        return (Icons.open_in_new, Colors.orange);
      case SwipeAction.appInfo:
        return (Icons.info_outline, Colors.teal);
      case SwipeAction.none:
        return (Icons.circle, Colors.transparent);
    }
  }

  Future<void> _executeAction(SwipeAction action, BuildContext context) async {
    final provider = context.read<AppsProvider>();
    final app = provider.apps[widget.appId]?.app;
    switch (action) {
      case SwipeAction.update:
        final isTrackOnly = app?.additionalSettings['trackOnly'] == true;
        if (isTrackOnly && app != null) {
          unawaited(
            launchUrlString(
              trackOnlyDownloadPageUrl(app),
              mode: LaunchMode.externalApplication,
            ),
          );
        } else {
          unawaited(
            provider
                .downloadAndInstallLatestApps([
                  widget.appId,
                ], globalNavigatorKey.currentContext)
                .catchError((Object e, StackTrace stackTrace) {
                  unawaited(
                    provider.logs.add(
                      'Swipe update failed for ${widget.appId}: $e\n$stackTrace',
                      level: LogLevel.error,
                    ),
                  );
                  showError(e);
                  return <String>[];
                }),
          );
        }
      case SwipeAction.pin:
        if (app != null) {
          unawaited(
            provider.saveApps([
              app.copyWith(pinned: !widget.isPinned),
            ], updateInstalledInfo: false),
          );
        }
      case SwipeAction.appOptions:
        await _openAdditionalOptionsModal(widget.appId, context);
      case SwipeAction.edit:
        if (context.mounted) {
          final double screenWidth = MediaQuery.sizeOf(context).width;
          final bool isLargeScreen =
              screenWidth >= kLargeScreenWidthBreakpoint &&
              !context.read<SettingsProvider>().isTV &&
              !context.read<SettingsProvider>().alwaysUsePhoneLayout;

          if (isLargeScreen) {
            final appsPageState = context
                .findAncestorStateOfType<AppsPageState>();
            if (appsPageState != null) {
              appsPageState.openAppInEditMode(widget.appId, autoScroll: false);
            }
          } else {
            await Navigator.push(
              context,
              heroFriendlyAppPageRoute(
                (_) => AppPage(
                  appId: widget.appId,
                  openInEditMode: true,
                  appsListHeroFolderId: widget.appsListHeroFolderId,
                ),
              ),
            );
          }
        }
      case SwipeAction.delete:
        if (app != null) {
          // Capture messenger before the await – the widget may be disposed after removal
          final messenger = scaffoldMessengerKey.currentState;
          final RemoveAppsWithModalResult removeResult = await provider
              .removeAppsWithModal(context, [app]);
          if (removeResult.shouldShowSnackBar) {
            final Set<String> undoAppIds = removeResult.deferredUndoAppIds;
            messenger
              ?..clearSnackBars()
              ..showSnackBar(
                SnackBar(
                  content: Text(tr('xAppsRemoved', args: ['1'])),
                  persist: false,
                  duration: const Duration(seconds: 5),
                  behavior: SnackBarBehavior.floating,
                  action: undoAppIds.isNotEmpty
                      ? SnackBarAction(
                          label: tr('undo'),
                          onPressed: () => provider
                              .undoDeferredObtainiumRemovals(undoAppIds),
                        )
                      : null,
                ),
              );
          }
        }
      case SwipeAction.open:
        unawaited(packageManager.openApp(widget.appId));
      case SwipeAction.appInfo:
        unawaited(provider.openAppSettings(widget.appId));
      case SwipeAction.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    const swipeThreshold = 80.0;
    const maxDrag = 120.0;

    final canSwipeRight = _canExecute(widget.rightAction);
    final canSwipeLeft = _canExecute(widget.leftAction);

    Color bgColor;
    IconData bgIcon;
    Alignment bgAlign;
    Color iconColor;
    String bgLabel = '';
    // Icon leads the label when swiping right (aligned to the leading edge);
    // the label leads when swiping left (aligned to the trailing edge).
    bool bgIconLeading = true;

    if (_dragOffset > 0 && canSwipeRight) {
      final (icon, color) = _actionVisuals(widget.rightAction, context);
      bgColor = color.withValues(alpha: 0.25);
      bgIcon = icon;
      bgAlign = Alignment.centerLeft;
      iconColor = color;
      bgLabel = _actionLabel(widget.rightAction);
      bgIconLeading = true;
    } else if (_dragOffset < 0 && canSwipeLeft) {
      final (icon, color) = _actionVisuals(widget.leftAction, context);
      bgColor = color.withValues(alpha: 0.20);
      bgIcon = icon;
      bgAlign = Alignment.centerRight;
      iconColor = color;
      bgLabel = _actionLabel(widget.leftAction);
      bgIconLeading = false;
    } else {
      bgColor = Colors.transparent;
      bgIcon = Icons.circle;
      bgAlign = Alignment.center;
      iconColor = Colors.transparent;
    }

    // Fade + subtle scale-in of the revealed action, tracking swipe progress
    // up to the commit threshold — matches Remember's fade in / out.
    final double revealProgress = (_dragOffset.abs() / swipeThreshold).clamp(
      0.0,
      1.0,
    );
    final TextStyle? labelStyle = Theme.of(context).textTheme.labelLarge
        ?.copyWith(color: iconColor, fontWeight: FontWeight.w600);

    return GestureDetector(
      onHorizontalDragStart: (_) => _settleController.stop(),
      onHorizontalDragUpdate: (details) {
        _settleController.stop();
        setState(() {
          _dragOffset += details.delta.dx;
          _dragOffset = _dragOffset.clamp(
            canSwipeLeft ? -maxDrag : 0.0,
            canSwipeRight ? maxDrag : 0.0,
          );
        });
      },
      onHorizontalDragEnd: (_) {
        if (_dragOffset > swipeThreshold && canSwipeRight) {
          _executeAction(widget.rightAction, context);
          setState(() => _dragOffset = 0);
        } else if (_dragOffset < -swipeThreshold && canSwipeLeft) {
          _executeAction(widget.leftAction, context);
          setState(() => _dragOffset = 0);
        } else {
          _settleToZero();
        }
      },
      onHorizontalDragCancel: _settleToZero,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: bgColor,
                alignment: bgAlign,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Opacity(
                  opacity: revealProgress,
                  child: Transform.scale(
                    scale: 0.88 + 0.12 * revealProgress,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: bgIconLeading
                          ? [
                              Icon(bgIcon, color: iconColor),
                              const SizedBox(width: 8),
                              Text(bgLabel, style: labelStyle),
                            ]
                          : [
                              Text(bgLabel, style: labelStyle),
                              const SizedBox(width: 8),
                              Icon(bgIcon, color: iconColor),
                            ],
                    ),
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}

class AppsPage extends StatefulWidget {
  const AppsPage({
    super.key,
    this.onDemandOnlyList = false,
    this.folderId,
    this.homeFabChromeTick,
    this.onStateChanged,
  });

  /// When true, only apps with [App.additionalSettings] `onDemandOnly` are listed
  /// and pull-to-refresh checks only those IDs. When [folderId] is set,
  /// pull-to-refresh checks only apps in that folder. Otherwise (main list),
  /// pull-to-refresh checks all apps except on-demand-only (see
  /// [AppsProvider.getAppsSortedByUpdateCheckTime]).
  final bool onDemandOnlyList;

  /// When non-null, only apps belonging to this folder ID are shown.
  final String? folderId;

  /// Notifies [HomePage] FAB overlay to rebuild when badge/selection changes.
  final ValueNotifier<int>? homeFabChromeTick;

  /// Post-frame [HomePage] rebuild when shell FAB chrome changes (phone layout).
  final VoidCallback? onStateChanged;

  @override
  State<AppsPage> createState() => AppsPageState();
}

String? _githubReleaseApiUrlFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.host.toLowerCase().endsWith('github.com')) {
    return null;
  }
  final segments = uri.pathSegments;
  if (segments.length < 3 || segments[2] != 'releases') {
    return null;
  }
  final repoApiBase =
      'https://api.github.com/repos/${segments[0]}/${segments[1]}/releases';
  if (segments.length == 3 || segments[3] == 'latest') {
    return '$repoApiBase/latest';
  }
  if (segments[3] == 'tag' && segments.length >= 5) {
    final tagName = segments.sublist(4).join('/');
    return '$repoApiBase/tags/${Uri.encodeComponent(tagName)}';
  }
  return null;
}

String? _rawFileUrlFromRepositoryPageUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  final segments = uri.pathSegments;
  if (host.endsWith('github.com') &&
      segments.length >= 5 &&
      segments[2] == 'blob') {
    return Uri(
      scheme: 'https',
      host: 'raw.githubusercontent.com',
      pathSegments: [
        segments[0],
        segments[1],
        segments[3],
        ...segments.sublist(4),
      ],
    ).toString();
  }
  final gitLabBlobIndex = segments.indexOf('blob');
  if (host.endsWith('gitlab.com') &&
      gitLabBlobIndex > 1 &&
      segments[gitLabBlobIndex - 1] == '-' &&
      segments.length > gitLabBlobIndex + 2) {
    final rawSegments = List<String>.from(segments);
    rawSegments[gitLabBlobIndex] = 'raw';
    return uri.replace(pathSegments: rawSegments).toString();
  }
  return null;
}

Future<String?> _loadLinkedChangeLog(
  AppSource appSource,
  App app,
  String changesUrl,
) async {
  final githubReleaseApiUrl = _githubReleaseApiUrlFromUrl(changesUrl);
  final requestUrl =
      githubReleaseApiUrl ??
      _rawFileUrlFromRepositoryPageUrl(changesUrl) ??
      changesUrl;
  final response = await appSource.sourceRequest(
    requestUrl,
    app.additionalSettings,
  );
  if (response.statusCode != 200) {
    throw getObtainiumHttpError(response);
  }
  if (githubReleaseApiUrl != null) {
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return (decoded['body'] ?? '').toString();
    }
  }
  if (appSource is APKMirror) {
    // APKMirror URLs can point at an app listing with no "What's new"
    // section (for example Markup). Never fall through to the generic raw-body
    // path for this HTML source, or the entire document is shown as a changelog.
    return apkMirrorChangeLogFromReleasePageHtml(response.body);
  }
  return response.body;
}

void showChangeLogDialog(
  BuildContext context,
  App app,
  String? changesUrl,
  AppSource appSource,
  String? changeLog,
) {
  String? processedChangeLog = changeLog;
  if (changeLog != null && appSource.changeLogIfAnyIsMarkDown) {
    // Release notes from some stores (APKMirror, Google apps) separate lines
    // with literal <br> tags on a single line. flutter_markdown ignores raw
    // HTML, so those render as visible "<br>" text — convert them to Markdown
    // hard line breaks first.
    processedChangeLog = processedChangeLog!.replaceAll(
      RegExp(r'<br\s*/?>', caseSensitive: false),
      '  \n',
    );
    final htmlImgRegex = RegExp(r'<img\s+([^>]+)\/?>', caseSensitive: false);
    final srcRegex = RegExp("src=[\"']([^\"']+)[\"']", caseSensitive: false);
    final altRegex = RegExp("alt=[\"']([^\"']+)[\"']", caseSensitive: false);

    String resolveUrl(String src) {
      if (src.startsWith('http://') || src.startsWith('https://')) {
        return src;
      }
      try {
        final uri = Uri.parse(app.url);
        final segments = uri.pathSegments;
        var cleanPath = src;
        if (cleanPath.startsWith('./')) {
          cleanPath = cleanPath.substring(2);
        } else if (cleanPath.startsWith('/')) {
          cleanPath = cleanPath.substring(1);
        }

        if (uri.host.contains('github.com') && segments.length >= 2) {
          return 'https://raw.githubusercontent.com/${segments[0]}/${segments[1]}/HEAD/$cleanPath';
        } else if (uri.host.contains('gitlab.com') && segments.length >= 2) {
          return 'https://gitlab.com/${segments[0]}/${segments[1]}/-/raw/HEAD/$cleanPath';
        } else if (uri.host.contains('codeberg.org') && segments.length >= 2) {
          return 'https://codeberg.org/${segments[0]}/${segments[1]}/raw/branch/HEAD/$cleanPath';
        } else {
          return '${uri.origin}/$cleanPath';
        }
      } catch (_) {
        return src;
      }
    }

    processedChangeLog = processedChangeLog.replaceAllMapped(htmlImgRegex, (
      match,
    ) {
      final attrs = match.group(1) ?? '';
      final srcMatch = srcRegex.firstMatch(attrs);
      final altMatch = altRegex.firstMatch(attrs);
      if (srcMatch != null) {
        final src = resolveUrl(srcMatch.group(1)!);
        final alt = altMatch?.group(1) ?? '';
        return '![$alt]($src)';
      }
      return match.group(0)!;
    });

    final mdImgRegex = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)');
    processedChangeLog = processedChangeLog.replaceAllMapped(mdImgRegex, (
      match,
    ) {
      final alt = match.group(1) ?? '';
      final src = match.group(2)!;
      final absoluteSrc = resolveUrl(src);
      return '![$alt]($absoluteSrc)';
    });

    // GitHub/GitLab release notes routinely wrap screenshots in HTML layout
    // tags (<table>/<tr>/<td>, <picture>, <div align="center">, …). CommonMark
    // treats everything inside such an HTML block as raw HTML, so the images
    // just converted to Markdown above would never be parsed or shown. Strip
    // the structural wrapper tags (the images survive) so each screenshot
    // renders — stacked vertically rather than in columns, since
    // flutter_markdown can't lay out HTML tables.
    processedChangeLog = processedChangeLog.replaceAll(
      RegExp(
        r'</?(?:table|thead|tbody|tfoot|tr|td|th|picture|source|div|center|p)\b[^>]*>',
        caseSensitive: false,
      ),
      '\n\n',
    );
  }
  final Future<String?>? linkedChangeLogFuture =
      changeLog == null && changesUrl != null
      ? _loadLinkedChangeLog(appSource, app, changesUrl)
      : null;

  showAppModalSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) {
      final ColorScheme colorScheme = Theme.of(sheetContext).colorScheme;
      final TextTheme textTheme = Theme.of(sheetContext).textTheme;

      // Non-scrolling content — the shared sheet provides the scroll view, so
      // short changelogs hug their height and long ones scroll within the cap.
      Widget buildChangeLogContent(String? displayChangeLog) {
        if (displayChangeLog == null || displayChangeLog.trim().isEmpty) {
          return Text(tr('notFound'), style: textTheme.bodyMedium);
        }
        return appSource.changeLogIfAnyIsMarkDown
            ? MarkdownBody(
                styleSheet: MarkdownStyleSheet(
                  blockquoteDecoration: BoxDecoration(
                    color: Theme.of(sheetContext).cardColor,
                  ),
                ),
                data: displayChangeLog,
                onTapLink: (text, href, title) {
                  if (href != null) {
                    launchUrlString(
                      href.startsWith('http://') || href.startsWith('https://')
                          ? href
                          : '${Uri.parse(app.url).origin}/$href',
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                extensionSet: md.ExtensionSet(
                  md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                  [
                    md.EmojiSyntax(),
                    ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                  ],
                ),
              )
            : SelectableText(displayChangeLog, style: textTheme.bodyMedium);
      }

      final Widget changeLogContent = linkedChangeLogFuture == null
          ? buildChangeLogContent(processedChangeLog)
          : FutureBuilder<String?>(
              future: linkedChangeLogFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return SizedBox(
                    height: 120,
                    child: Center(
                      child: ExpressiveLoadingIndicator(
                        color: colorScheme.primary,
                        constraints: const BoxConstraints.tightFor(
                          width: 64,
                          height: 64,
                        ),
                      ),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return SelectableText(
                    snapshot.error.toString(),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.error,
                    ),
                  );
                }
                return buildChangeLogContent(snapshot.data);
              },
            );

      return AppSheetContent(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        app.name,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        app.latestVersion,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  tooltip: tr('close'),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          if (changesUrl != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: InkWell(
                onTap: () {
                  launchUrlString(
                    changesUrl,
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: Text(
                  changesUrl,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    decoration: TextDecoration.underline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: changeLogContent,
          ),
        ],
      );
    },
  );
}

/// Compiled once at load time. Previously this was rebuilt on every call to
/// [getChangeLogFn], which runs per visible row on every apps-list rebuild —
/// compiling a RegExp per row per frame is pure main-thread waste.
final RegExp _changeLogUrlRegExp = RegExp(
  '(http|ftp|https)://([\\w_-]+(?:(?:\\.[\\w_-]+)+))([\\w.,@?^=%&:/~+#-]*[\\w@?^=%&/~+#-])?',
);

Null Function()? getChangeLogFn(BuildContext context, App app) {
  final AppSource appSource = SourceProvider().getSourceTemplate(
    app.url,
    overrideSource: app.overrideSource,
  );
  String? changesUrl = appSource.changeLogPageFromStandardUrl(app.url);
  String? changeLog = app.changeLog;
  // Only treat the changelog as a link when the *entire* trimmed text is a
  // single URL. The previous "one line + contains a URL" check misfired on
  // release notes that pack everything onto one line with literal <br>
  // separators (APKMirror/Google apps) and embed a link: it shoved the whole
  // changelog into Uri.parse as if it were a URL, throwing a FormatException
  // ("Scheme not starting with alphabetic character"). Require a full match.
  final String trimmedChangeLog = changeLog?.trim() ?? '';
  if (trimmedChangeLog.isNotEmpty) {
    final Match? urlMatch = _changeLogUrlRegExp.firstMatch(trimmedChangeLog);
    if (urlMatch != null &&
        urlMatch.start == 0 &&
        urlMatch.end == trimmedChangeLog.length) {
      changesUrl = appSource is APKMirror
          ? trimmedChangeLog
          : (changesUrl ?? trimmedChangeLog);
      changeLog = null;
    }
  }
  return (changeLog == null && changesUrl == null)
      ? null
      : () {
          showChangeLogDialog(context, app, changesUrl, appSource, changeLog);
        };
}

void showAppsViewOptionsSheet(BuildContext context, {String? folderId}) {
  showAppModalSheet<void>(
    context: context,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final settingsProvider = ctx.watch<SettingsProvider>();

          // Effective view-setting accessors — use per-folder overrides when
          // viewing a folder, otherwise fall back to global settings.
          final effectiveSortColumn = folderId != null
              ? settingsProvider.folderSortColumn(folderId)
              : settingsProvider.sortColumn;
          void setEffectiveSortColumn(SortColumnSettings v) => folderId != null
              ? settingsProvider.setFolderSortColumn(folderId, v)
              : (settingsProvider.sortColumn = v);

          final effectiveSortOrder = folderId != null
              ? settingsProvider.folderSortOrder(folderId)
              : settingsProvider.sortOrder;
          void setEffectiveSortOrder(SortOrderSettings v) => folderId != null
              ? settingsProvider.setFolderSortOrder(folderId, v)
              : (settingsProvider.sortOrder = v);

          final effectiveGroupBy = folderId != null
              ? settingsProvider.folderGroupBy(folderId)
              : settingsProvider.appsListGroupBy;
          void setEffectiveGroupBy(AppsListGroupBy v) => folderId != null
              ? settingsProvider.setFolderGroupBy(folderId, v)
              : (settingsProvider.appsListGroupBy = v);

          final effectivePinUpdates = folderId != null
              ? settingsProvider.folderPinUpdates(folderId)
              : settingsProvider.pinUpdates;
          void setEffectivePinUpdates(bool v) => folderId != null
              ? settingsProvider.setFolderPinUpdates(folderId, v)
              : (settingsProvider.pinUpdates = v);

          final effectiveBuryNonInstalled = folderId != null
              ? settingsProvider.folderBuryNonInstalled(folderId)
              : settingsProvider.buryNonInstalled;
          void setEffectiveBuryNonInstalled(bool v) => folderId != null
              ? settingsProvider.setFolderBuryNonInstalled(folderId, v)
              : (settingsProvider.buryNonInstalled = v);

          final effectiveGroupNonInstalledSeparately = folderId != null
              ? settingsProvider.folderGroupNonInstalledSeparately(folderId)
              : settingsProvider.groupNonInstalledSeparately;
          void setEffectiveGroupNonInstalledSeparately(bool v) =>
              folderId != null
              ? settingsProvider.setFolderGroupNonInstalledSeparately(
                  folderId,
                  v,
                )
              : (settingsProvider.groupNonInstalledSeparately = v);

          final effectiveGroupTrackOnlySeparately = folderId != null
              ? settingsProvider.folderGroupTrackOnlySeparately(folderId)
              : settingsProvider.groupTrackOnlySeparately;
          void setEffectiveGroupTrackOnlySeparately(bool v) => folderId != null
              ? settingsProvider.setFolderGroupTrackOnlySeparately(folderId, v)
              : (settingsProvider.groupTrackOnlySeparately = v);

          final effectiveGroupUpdatesSeparately = folderId != null
              ? settingsProvider.folderGroupUpdatesSeparately(folderId)
              : settingsProvider.groupUpdatesSeparately;
          void setEffectiveGroupUpdatesSeparately(bool v) => folderId != null
              ? settingsProvider.setFolderGroupUpdatesSeparately(folderId, v)
              : (settingsProvider.groupUpdatesSeparately = v);

          final colorScheme = Theme.of(ctx).colorScheme;
          final textTheme = Theme.of(ctx).textTheme;

          Widget sectionLabel(String text) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text(
                text,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            );
          }

          return AppSheetContent(
            children: [
              Text(
                tr('appsViewOptions'),
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sectionLabel(tr('showBadges')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        avatar: const Icon(Icons.person_rounded, size: 16),
                        showCheckmark: false,
                        label: Text(tr('showAppTypeBadge')),
                        selected: settingsProvider.showAppTypeBadge,
                        onSelected: (value) {
                          settingsProvider.showAppTypeBadge = value;
                          setSheetState(() {});
                        },
                      ),
                      FilterChip(
                        avatar: const Icon(Icons.store_rounded, size: 16),
                        showCheckmark: false,
                        label: Text(tr('showTrackedStoreBadge')),
                        selected: settingsProvider.showTrackedStoreBadge,
                        onSelected: (value) {
                          settingsProvider.showTrackedStoreBadge = value;
                          setSheetState(() {});
                        },
                      ),
                      FilterChip(
                        avatar: const Icon(Icons.category_rounded, size: 16),
                        showCheckmark: false,
                        label: Text(tr('showCategoriesBadge')),
                        selected: settingsProvider.showCategoriesBadge,
                        onSelected: (value) {
                          settingsProvider.showCategoriesBadge = value;
                          setSheetState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
              Divider(color: colorScheme.outlineVariant),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: appDropdownField<SortColumnSettings>(
                      context: ctx,
                      labelText: tr('sortBy'),
                      value: effectiveSortColumn,
                      menuWidth: appDropdownMenuWidth(ctx, [
                        tr('authorName'),
                        tr('nameAuthor'),
                        tr('asAdded'),
                        tr('releaseDate'),
                        tr('sortByLastUpdateCheck'),
                      ]),
                      items: [
                        DropdownMenuItem(
                          value: SortColumnSettings.authorName,
                          child: Text(tr('authorName')),
                        ),
                        DropdownMenuItem(
                          value: SortColumnSettings.nameAuthor,
                          child: Text(tr('nameAuthor')),
                        ),
                        DropdownMenuItem(
                          value: SortColumnSettings.added,
                          child: Text(tr('asAdded')),
                        ),
                        DropdownMenuItem(
                          value: SortColumnSettings.releaseDate,
                          child: Text(tr('releaseDate')),
                        ),
                        DropdownMenuItem(
                          value: SortColumnSettings.lastUpdateCheck,
                          child: Text(tr('sortByLastUpdateCheck')),
                        ),
                      ],
                      onChanged: (newValue) {
                        if (newValue != null) {
                          setEffectiveSortColumn(newValue);
                          setSheetState(() {});
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    icon: Icon(
                      effectiveSortOrder == SortOrderSettings.ascending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                    ),
                    tooltip: effectiveSortOrder == SortOrderSettings.ascending
                        ? tr('ascending')
                        : tr('descending'),
                    onPressed: () {
                      setEffectiveSortOrder(
                        effectiveSortOrder == SortOrderSettings.ascending
                            ? SortOrderSettings.descending
                            : SortOrderSettings.ascending,
                      );
                      setSheetState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              appDropdownField<AppsListGroupBy>(
                context: ctx,
                labelText: tr('groupBy'),
                value: effectiveGroupBy,
                menuWidth: appDropdownMenuWidth(ctx, [
                  tr('groupByNone'),
                  tr('category'),
                  tr('groupByTrackedSource'),
                  tr('groupByAppType'),
                ]),
                items: [
                  DropdownMenuItem(
                    value: AppsListGroupBy.none,
                    child: Text(tr('groupByNone')),
                  ),
                  DropdownMenuItem(
                    value: AppsListGroupBy.category,
                    child: Text(tr('category')),
                  ),
                  DropdownMenuItem(
                    value: AppsListGroupBy.source,
                    child: Text(tr('groupByTrackedSource')),
                  ),
                  DropdownMenuItem(
                    value: AppsListGroupBy.appType,
                    child: Text(tr('groupByAppType')),
                  ),
                ],
                onChanged: (newValue) {
                  if (newValue != null) {
                    setEffectiveGroupBy(newValue);
                    setSheetState(() {});
                  }
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  sectionLabel(tr('groupSeparately')),
                  const SizedBox(width: 8),
                  HelpHintIcon(
                    message: tr('groupSeparatelyDescription'),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    showCheckmark: false,
                    label: Text(tr('updates')),
                    selected: effectiveGroupUpdatesSeparately,
                    onSelected: (value) {
                      setEffectiveGroupUpdatesSeparately(value);
                      setSheetState(() {});
                    },
                  ),
                  if (effectiveGroupBy != AppsListGroupBy.none) ...[
                    FilterChip(
                      showCheckmark: false,
                      label: Text(tr('nonInstalledApps')),
                      selected: effectiveGroupNonInstalledSeparately,
                      onSelected: (value) {
                        setEffectiveGroupNonInstalledSeparately(value);
                        setSheetState(() {});
                      },
                    ),
                    FilterChip(
                      showCheckmark: false,
                      label: Text(tr('trackOnly')),
                      selected: effectiveGroupTrackOnlySeparately,
                      onSelected: (value) {
                        setEffectiveGroupTrackOnlySeparately(value);
                        setSheetState(() {});
                      },
                    ),
                  ],
                ],
              ),
              Divider(color: colorScheme.outlineVariant),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('pinUpdates')),
                value: effectivePinUpdates,
                onChanged: (value) {
                  setEffectivePinUpdates(value);
                  setSheetState(() {});
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('moveNonInstalledAppsToBottom')),
                value: effectiveBuryNonInstalled,
                onChanged: (value) {
                  setEffectiveBuryNonInstalled(value);
                  setSheetState(() {});
                },
              ),
              // Main-tab-only toggle: shows / hides foldered apps on
              // this view AND scopes pull-to-refresh accordingly.
              // Hidden when this sheet is opened from inside a folder
              // view because the toggle has no meaning there - a
              // folder always shows its own apps.
              if (folderId == null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('showFolderedAppsOnMainPage')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HelpHintIcon(
                        message: tr('showFolderedAppsOnMainPageTooltip'),
                        padding: EdgeInsets.zero,
                      ),
                      Switch(
                        value: settingsProvider.showFolderedAppsOnMainPage,
                        onChanged: (value) {
                          settingsProvider.showFolderedAppsOnMainPage = value;
                          setSheetState(() {});
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    settingsProvider.showFolderedAppsOnMainPage =
                        !settingsProvider.showFolderedAppsOnMainPage;
                    setSheetState(() {});
                  },
                ),
            ],
          );
        },
      );
    },
  );
}

/// Keeps auto-hide/show of the apps footer local to this state so scrolling
/// does not call [setState] on [AppsPageState] and rebuild the whole list.
class _ScrollLinkedAppFooter extends StatefulWidget {
  const _ScrollLinkedAppFooter({
    required this.scrollController,
    required this.selectionActive,
    required this.footer,
  });

  final ScrollController scrollController;
  final bool selectionActive;
  final Widget footer;

  @override
  State<_ScrollLinkedAppFooter> createState() => _ScrollLinkedAppFooterState();
}

class _ScrollLinkedAppFooterState extends State<_ScrollLinkedAppFooter> {
  bool _footerExpanded = true;
  double _previousOffset = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant _ScrollLinkedAppFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
    if (oldWidget.selectionActive != widget.selectionActive) {
      if (widget.scrollController.hasClients) {
        _previousOffset = widget.scrollController.offset;
      }
      if (!_footerExpanded) {
        setState(() {
          _footerExpanded = true;
        });
      }
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final ScrollController controller = widget.scrollController;
    if (!controller.hasClients) {
      return;
    }
    if (widget.selectionActive) {
      _previousOffset = controller.offset;
      if (!_footerExpanded) {
        setState(() {
          _footerExpanded = true;
        });
      }
      return;
    }
    final double currentOffset = controller.offset;
    final double delta = currentOffset - _previousOffset;
    _previousOffset = currentOffset;
    if (currentOffset <= 24) {
      if (!_footerExpanded) {
        setState(() {
          _footerExpanded = true;
        });
      }
      return;
    }
    const double scrollSensitivity = 10;
    if (delta > scrollSensitivity) {
      if (_footerExpanded) {
        setState(() {
          _footerExpanded = false;
        });
      }
    } else if (delta < -scrollSensitivity) {
      if (!_footerExpanded) {
        setState(() {
          _footerExpanded = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubicEmphasized,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: _footerExpanded || widget.selectionActive
          ? widget.footer
          : const SizedBox(width: double.infinity),
    );
  }
}

// Reserved settings key for the On-Demand Only page's per-view options.
const String _onDemandViewSettingsId = '__on_demand_only__';

class AppsPageState extends State<AppsPage> {
  GlobalKey<NavigatorState>? detailsNavKey;
  String? _detailsNavKeyAppId;
  bool _openSelectedInEditMode = false;

  void openAppInEditMode(String appId, {bool autoScroll = true}) {
    setState(() {
      _openSelectedInEditMode = true;
      selectedAppId = appId;
      detailsNavKey = null;
      _detailsNavKeyAppId = null;
    });
    if (autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToApp(appId);
      });
    }
  }

  GlobalKey<NavigatorState> _getDetailsNavKey(String appId) {
    if (_detailsNavKeyAppId != appId || detailsNavKey == null) {
      detailsNavKey = GlobalKey<NavigatorState>();
      _detailsNavKeyAppId = appId;
    }
    return detailsNavKey!;
  }

  AppsFilter filter = AppsFilter();
  final AppsFilter neutralFilter = AppsFilter();
  var updatesOnlyFilter = AppsFilter(
    upToDateFilterIntent: CategoryFilterIntent.exclude,
    installedFilterIntent: CategoryFilterIntent.include,
  );
  Set<String> selectedAppIds = {};
  DateTime? refreshingSince;

  VoidCallback? openSelectionActionsSheetHandler;
  VoidCallback? runMassObtainHandler;
  int pageUpdateCount = 0;

  bool get hasMassObtainOperations => runMassObtainHandler != null;

  void runMassObtain() {
    runMassObtainHandler?.call();
  }

  bool get isSelectionActive => selectedAppIds.isNotEmpty;

  void openViewOptionsSheet() {
    showAppsViewOptionsSheet(context, folderId: _viewSettingsId);
  }

  void openSelectionActionsSheet() {
    openSelectionActionsSheetHandler?.call();
  }

  /// Update-all + actions/view-options FABs overlaid on the apps list.
  Widget _buildAppsPageSideFabOverlay(
    BuildContext context, {
    required String heroScope,
  }) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOutCubicEmphasized,
        offset: MediaQuery.of(context).viewInsets.bottom > 0
            ? const Offset(0, 1.5)
            : Offset.zero,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: MediaQuery.of(context).viewInsets.bottom > 0 ? 0.0 : 1.0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (hasMassObtainOperations)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    FloatingActionButton.small(
                      heroTag: '${heroScope}_update_all_fab',
                      elevation: 6,
                      highlightElevation: 8,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onPrimaryContainer,
                      onPressed: () {
                        hapticSelection();
                        runMassObtain();
                      },
                      tooltip: null,
                      child: const Icon(Icons.file_download_outlined, size: 20),
                    ),
                    if (pageUpdateCount > 0)
                      Positioned(
                        left: -4,
                        bottom: -4,
                        child: Badge(
                          label: Text(pageUpdateCount.toString()),
                          backgroundColor: Theme.of(context).colorScheme.error,
                          textColor: Theme.of(context).colorScheme.onError,
                        ),
                      ),
                  ],
                )
              else
                const SizedBox.shrink(),
              if (isSelectionActive)
                FloatingActionButton.small(
                  heroTag: '${heroScope}_actions_fab',
                  elevation: 6,
                  highlightElevation: 8,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  onPressed: () {
                    hapticSelection();
                    openSelectionActionsSheet();
                  },
                  tooltip: null,
                  child: const Icon(Icons.checklist, size: 20),
                )
              else
                FloatingActionButton.small(
                  heroTag: '${heroScope}_view_options_fab',
                  elevation: 6,
                  highlightElevation: 8,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  foregroundColor: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant,
                  onPressed: () {
                    hapticSelection();
                    openViewOptionsSheet();
                  },
                  tooltip: null,
                  child: const Icon(Icons.tune, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool clearSelected() {
    if (selectedAppIds.isNotEmpty) {
      setState(() {
        selectedAppIds.clear();
      });
      _notifyHomeFabChromeIfChanged();
      return true;
    }
    return false;
  }

  /// Called by [_HomePageState] when the system back button is pressed while
  /// this tab is active. Returns true if the back event was consumed.
  bool handleBack() {
    if (clearSelected()) return true;
    final navKey = detailsNavKey;
    if (navKey != null &&
        navKey.currentState != null &&
        navKey.currentState!.canPop()) {
      navKey.currentState!.pop();
      return true;
    }
    if (_searchExpanded) {
      setState(() {
        _searchExpanded = false;
        _searchController.clear();
        _searchFocusNode.unfocus();
      });
      return true;
    }
    final sp = context.read<SettingsProvider>();
    final isFilterActive = !filter.isIdenticalTo(neutralFilter, sp);
    if (isFilterActive) {
      setState(() {
        filter = AppsFilter();
        _searchController.clear();
      });
      return true;
    }
    return false;
  }

  // Typed for [ExpressiveRefreshIndicatorState] (from expressive_refresh) so
  // we can call .show() to programmatically trigger the refresh from the
  // checkOnStart auto-refresh path. The state class mirrors Flutter's
  // [RefreshIndicatorState.show] API ({bool atTop = true}).
  final GlobalKey<ExpressiveRefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<ExpressiveRefreshIndicatorState>();

  // ── Deferred background store-availability scan ───────────────────────────
  // The post-refresh APKMirror/F-Droid availability scan does ~50 HTTP fetches
  // and HTML parses (now off the UI isolate per [parseHtmlOffIsolate], but
  // still consumes radio + battery and can stutter network-dependent widgets).
  // We delay it by a few seconds after refresh completes so the user has
  // unimpeded scrolling during the immediate post-refresh window. Cancelled
  // on dispose and reset on each refresh.
  Timer? _deferredStoreScanTimer;
  static const Duration _deferredStoreScanDelay = Duration(seconds: 3);

  late final ScrollController scrollController;

  /// One [Future] per app id so icon loading is not restarted on every rebuild.
  final Map<String, Future<void>> _appListIconWarmFutures = {};

  var sourceProvider = SourceProvider();

  // ── List-computation cache ────────────────────────────────────────────────
  // The filter → sort → pin/bury pass is O(n log n) and runs inside build().
  // We skip it entirely when the inputs haven't changed (e.g. a setState() for
  // row selection or the refresh-indicator doesn't need a new sort).
  int? _lastListBuildToken;
  List<AppInMemory> _listedAppsCache = const [];
  // Search matches that live inside folders, surfaced under a divider on the
  // main page so a search isn't dead-ended by folder membership (mirrors how
  // Remember's search reveals archived/trashed notes). One entry per folder
  // that has at least one match, in folder-settings order. Stays empty unless
  // a text search is active on the main page with foldered apps hidden.
  // A null folderId marks the "On-Demand Only" bucket rather than a folder.
  List<({String? folderId, String folderName, List<AppInMemory> apps})>
  _crossFolderMatchesCache = const [];
  List<String> _existingUpdatesCache = const [];
  List<String> _newInstallsCache = const [];
  List<String> _listedSourcesCache = const [];
  List<String?> _listedCategoriesCache = const [];
  List<AppTypeGroup> _listedAppTypesCache = const [];

  /// Maps category key (`__null__` for uncategorized) → indices into [_listedAppsCache].
  Map<String, List<int>> _categoryGroupListedIndices = const {};

  /// Maps source runtime type string → indices into [_listedAppsCache].
  Map<String, List<int>> _sourceGroupListedIndices = const {};

  /// Maps [AppTypeGroup] → indices into [_listedAppsCache].
  Map<AppTypeGroup, List<int>> _appTypeGroupListedIndices = const {};
  List<int> _nonInstalledListedIndices = const [];
  List<int> _trackOnlyListedIndices = const [];

  /// Indices of apps shown in the "Updates" group (groupUpdatesSeparately).
  List<int> _updatesGroupListedIndices = const [];
  int? _lastGroupIndexCacheToken;

  // Folder/on-demand counts shown as sidebar/badge numbers. These are a pure
  // function of app state + the folder set, so they're cached behind their own
  // token instead of being recomputed (O(apps × folders)) on every build —
  // selection toggles, swipe gestures, and the refresh indicator all rebuild
  // [AppsPage] without changing any of these counts.
  int? _lastFolderCountsToken;
  int _onDemandOnlyAppCountCache = 0;
  Map<String, int> _folderAppCountsCache = const {};
  Map<String, int> _folderUpdateCountsCache = const {};

  /// Pushes FAB badge / mass-obtain / selection state to [HomePage] without
  /// calling [setState] on the home shell.
  int? _lastNotifiedPageUpdateCount;
  bool? _lastNotifiedMassObtainAvailable;
  bool? _lastNotifiedSelectionActive;
  bool _homeFabBadgeSyncScheduled = false;

  void _notifyHomeFabChromeIfChanged({bool force = false}) {
    final bool massObtainAvailable = runMassObtainHandler != null;
    final bool selectionActive = isSelectionActive;
    if (!force &&
        pageUpdateCount == _lastNotifiedPageUpdateCount &&
        massObtainAvailable == _lastNotifiedMassObtainAvailable &&
        selectionActive == _lastNotifiedSelectionActive) {
      return;
    }
    _lastNotifiedPageUpdateCount = pageUpdateCount;
    _lastNotifiedMassObtainAvailable = massObtainAvailable;
    _lastNotifiedSelectionActive = selectionActive;

    final ValueNotifier<int>? tick = widget.homeFabChromeTick;
    if (tick != null) {
      tick.value = tick.value + 1;
    }

    final VoidCallback? notifyHome = widget.onStateChanged;
    if (notifyHome == null) return;
    if (_homeFabBadgeSyncScheduled) return;
    _homeFabBadgeSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _homeFabBadgeSyncScheduled = false;
      if (mounted) notifyHome();
    });
  }

  // ── Group expansion state ─────────────────────────────────────────────────
  // Groups start expanded. When the user collapses one its key goes here and
  // its child tiles are no longer built, saving widget-tree work on rebuilds.
  final Set<String> _collapsedGroups = {};

  // ── Hero keep-alive ───────────────────────────────────────────────────────
  // Removed: previously held the appId of the row whose AppPage was open so
  // the row would stay mounted (via [_SwipeableListItem.keepAlive]) for the
  // back-pop Hero flight. With the [OpenContainer] (Container Transform)
  // migration in [getSingleAppHorizTile], the morph manages the source-row
  // lifecycle for the duration of the open animation, so manual keep-alive
  // is no longer required.

  // ── Inline search ─────────────────────────────────────────────────────────
  late final TextEditingController _searchController;

  /// Whether the search bar is currently expanded.
  bool _searchExpanded = false;

  /// The currently selected app's ID for split-pane layout.
  String? selectedAppId;
  final FocusNode _searchFocusNode = FocusNode();

  // ── Effective view-setting helpers ─────────────────────────────────────────
  // When in a folder view, these return the folder's stored override or fall
  // back to the global setting. On the main page they just return the global.

  /// Returns the per-view settings key for this page, or null for the main page.
  String? get _viewSettingsId =>
      widget.folderId ??
      (widget.onDemandOnlyList ? _onDemandViewSettingsId : null);

  SortColumnSettings _effectiveSortColumn(SettingsProvider sp) {
    final id = _viewSettingsId;
    return id != null ? sp.folderSortColumn(id) : sp.sortColumn;
  }

  SortOrderSettings _effectiveSortOrder(SettingsProvider sp) {
    final id = _viewSettingsId;
    return id != null ? sp.folderSortOrder(id) : sp.sortOrder;
  }

  AppsListGroupBy _effectiveGroupBy(SettingsProvider sp) {
    final id = _viewSettingsId;
    return id != null ? sp.folderGroupBy(id) : sp.appsListGroupBy;
  }

  bool _effectivePinUpdates(SettingsProvider sp) {
    final id = _viewSettingsId;
    return id != null ? sp.folderPinUpdates(id) : sp.pinUpdates;
  }

  bool _effectiveBuryNonInstalled(SettingsProvider sp) {
    final id = _viewSettingsId;
    return id != null ? sp.folderBuryNonInstalled(id) : sp.buryNonInstalled;
  }

  bool _effectiveGroupNonInstalledSeparately(SettingsProvider sp) {
    final id = _viewSettingsId;
    return id != null
        ? sp.folderGroupNonInstalledSeparately(id)
        : sp.groupNonInstalledSeparately;
  }

  bool _effectiveGroupTrackOnlySeparately(SettingsProvider sp) {
    final id = _viewSettingsId;
    return id != null
        ? sp.folderGroupTrackOnlySeparately(id)
        : sp.groupTrackOnlySeparately;
  }

  bool _effectiveGroupUpdatesSeparately(SettingsProvider sp) {
    final id = _viewSettingsId;
    return id != null
        ? sp.folderGroupUpdatesSeparately(id)
        : sp.groupUpdatesSeparately;
  }

  void _saveCollapsedGroups(List<String> keys, {required bool add}) {
    final sp = context.read<SettingsProvider>();
    final current = sp.prefs?.getStringList('collapsedGroups')?.toSet() ?? {};
    if (add) {
      current.addAll(keys);
    } else {
      current.removeAll(keys);
    }
    sp.prefs?.setStringList('collapsedGroups', current.toList());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifyHomeFabChromeIfChanged(force: true);
    });
    final sp = context.read<SettingsProvider>();
    _collapsedGroups.addAll(
      sp.prefs?.getStringList('collapsedGroups') ?? const <String>[],
    );
    scrollController = ScrollController();
    _searchController = TextEditingController();
    _searchController.addListener(() {
      final text = _searchController.text;
      if (text != filter.nameFilter) {
        setState(() => filter.nameFilter = text);
      }
    });
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus &&
          _searchController.text.isEmpty &&
          _searchExpanded) {
        setState(() {
          _searchExpanded = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _deferredStoreScanTimer?.cancel();
    scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Builds the compact search bar that lives inline with the "Apps" title.
  ///
  /// The search bar filters by app name. Its right-hand chip opens the full
  /// filter sheet and uses a primary-container colour when any filter is active.
  Widget _buildSearchBar({
    required ColorScheme colorScheme,
    required VoidCallback showFilterSheet,
    required AppsFilter neutralFilter,
    required SettingsProvider settingsProvider,
    required FocusNode focusNode,
  }) {
    final bool anyFilterActive = !filter.isIdenticalTo(
      neutralFilter,
      settingsProvider,
    );

    return TextField(
      controller: _searchController,
      focusNode: focusNode,
      autofocus: true,
      // Any tap outside the field drops focus (the default on touch platforms
      // keeps it, so the field held focus and the keyboard kept popping back up
      // after tapping a result, header, or anywhere else). onTapOutside fires on
      // raw pointer-down regardless of whether a child consumes the tap, so it
      // covers list rows, folder headers, filter chips — every interaction.
      onTapOutside: (_) {
        if (focusNode.hasFocus) focusNode.unfocus();
      },
      decoration:
          appPageOutlinedInputDecoration(
            context,
            labelText: null,
            hintText: tr('search'),
            isDense: true,
            borderRadius: 30,
          ).copyWith(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            suffixIcon: Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: Align(
                alignment: Alignment.center,
                widthFactor: 1,
                child: GestureDetector(
                  onTap: showFilterSheet,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: anyFilterActive
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tr('appName'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: anyFilterActive
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 14,
                          color: anyFilterActive
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
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

  /// Returns the human-readable display name for a source identifier (the
  /// stable value stored in [AppsFilter.sourceFilter]).
  String _getSourceName(String sourceKey) {
    for (final s in sourceProvider.sourceTemplates) {
      if (s.sourceIdentifier == sourceKey) return s.name;
    }
    return sourceKey;
  }

  /// Builds a single dismissible [InputChip] for the filter chips row.
  Widget _filterChip(String label, VoidCallback onDelete) {
    return InputChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onDeleted: onDelete,
      deleteIcon: const Icon(Icons.close, size: 16),
      // The default delete-icon box reserves a large tap target that reads as
      // oversized horizontal padding around the ✕. Shrink the box to the icon
      // and drop the label→icon gap so the ✕ sits snug against the text.
      deleteIconBoxConstraints: const BoxConstraints.tightFor(
        width: 18,
        height: 18,
      ),
      labelPadding: const EdgeInsets.only(left: 6, right: 2),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    );
  }

  /// Builds a pinned row of dismissible filter chips for every active
  /// non-text filter. Returns [null] when no non-text filters are active
  /// (which causes [CustomAppBar] to omit the bottom bar entirely).
  PreferredSizeWidget? _buildFilterChipsRow(VoidCallback onOpenFilterSheet) {
    final chips = <Widget>[];

    // ── Text filters ────────────────────────────────────────────────────────
    // Author and app-ID have no other on-page indicator (they can only be set
    // from the filter sheet), so always surface them as chips. The name filter
    // normally lives in the search bar, but it can also be set from the sheet —
    // in which case the search bar stays collapsed and shows nothing — so add a
    // name chip only while the search bar is collapsed, to avoid duplicating the
    // visible search field.
    if (filter.nameFilter.trim().isNotEmpty && !_searchExpanded) {
      chips.add(
        _filterChip('${tr('appName')}: ${filter.nameFilter.trim()}', () {
          setState(() {
            filter.nameFilter = '';
            _searchController.clear();
          });
        }),
      );
    }
    if (filter.authorFilter.trim().isNotEmpty) {
      chips.add(
        _filterChip(
          '${tr('author')}: ${filter.authorFilter.trim()}',
          () => setState(() => filter.authorFilter = ''),
        ),
      );
    }

    void addVisibilityFilterChip(
      String label,
      CategoryFilterIntent intent,
      ValueChanged<CategoryFilterIntent> onClear,
    ) {
      if (intent == CategoryFilterIntent.neutral) {
        return;
      }
      chips.add(
        _filterChip(
          visibilityFilterChipLabel(label, intent),
          () => setState(() => onClear(CategoryFilterIntent.neutral)),
        ),
      );
    }

    addVisibilityFilterChip(
      tr('visibilityFilterUpToDate'),
      filter.upToDateFilterIntent,
      (intent) => filter.upToDateFilterIntent = intent,
    );
    addVisibilityFilterChip(
      tr('visibilityFilterInstalled'),
      filter.installedFilterIntent,
      (intent) => filter.installedFilterIntent = intent,
    );
    addVisibilityFilterChip(
      tr('trackOnly'),
      filter.trackOnlyFilterIntent,
      (intent) => filter.trackOnlyFilterIntent = intent,
    );

    if (filter.sourceFilter.isNotEmpty) {
      chips.add(
        _filterChip(
          '${tr('source')}: ${_getSourceName(filter.sourceFilter)}',
          () => setState(() => filter.sourceFilter = ''),
        ),
      );
    }

    for (final cat in filter.includedCategoryFilter) {
      chips.add(
        _filterChip(
          cat,
          () => setState(
            () => filter.includedCategoryFilter = Set.from(
              filter.includedCategoryFilter,
            )..remove(cat),
          ),
        ),
      );
    }

    if (filter.includedCategoryFilter.length > 1 &&
        filter.categoryMatchMode == CategoryFilterMatchMode.all) {
      chips.add(
        _filterChip(
          tr('categoryMatchAllActive'),
          () => setState(
            () => filter.categoryMatchMode = CategoryFilterMatchMode.any,
          ),
        ),
      );
    }

    for (final cat in filter.excludedCategoryFilter) {
      chips.add(
        _filterChip(
          '-$cat',
          () => setState(
            () => filter.excludedCategoryFilter = Set.from(
              filter.excludedCategoryFilter,
            )..remove(cat),
          ),
        ),
      );
    }

    if (chips.isEmpty) return null;

    // A leading filter icon that reopens the filter sheet, shown whenever the
    // row is present (i.e. whenever a filter is active). Fixed 32-px slot with
    // a 20-px glyph, so it centers with a 6-px trailing gap to the first chip —
    // matching the 6-px inter-chip gap. (No visualDensity: it would shrink the
    // slot below 32 px and throw off both the gap and the centering balance.)
    const double iconSlot = 32;
    final Widget filterIcon = IconButton(
      icon: const Icon(Icons.filter_alt_rounded),
      iconSize: 20,
      onPressed: onOpenFilterSheet,
      tooltip: tr('filterApps'),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: iconSlot,
        minHeight: iconSlot,
      ),
    );

    return PreferredSize(
      preferredSize: const Size.fromHeight(44),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            filterIcon,
            ...chips.expand((c) => [c, const SizedBox(width: 6)]).toList()
              ..removeLast(),
            // The app bar centers this row's content when it fits. A leading
            // icon would drag that centering right, off-centering the chips; a
            // trailing spacer equal to the icon's slot re-balances it so the
            // CHIPS (not the icon+chips group) are what's centered, with the
            // icon hanging in the left gap next to the first chip. Harmless
            // extra scroll space once the row overflows.
            const SizedBox(width: iconSlot),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // select() prevents rebuilds for notifications that don't affect list data
    // (download-progress ticks, icon-load completions). The returned token is
    // also used as part of the list-computation cache key below.
    final int appsToken = context.select<AppsProvider, int>(
      _appsPageAppsRebuildToken,
    );
    final appsProvider = context.read<AppsProvider>();
    // Narrow the SettingsProvider dependency to a hash of just the settings
    // that actually affect this page's build. The previous
    // `context.watch<SettingsProvider>()` subscribed to EVERY notification
    // - including ones for settings the apps page doesn't read (e.g.
    // useFGService, enableBackgroundUpdates, install-permission flags).
    // Each of those rebuilt the entire 4000+-line apps tree, which on
    // devices with many apps blocked the frame and made unrelated toggles
    // (in the view options sheet AND elsewhere) feel laggy.
    //
    // [context.select] only rebuilds the page when the returned hash
    // changes - so toggling foreground service in main settings, for
    // example, no longer triggers an apps-page rebuild at all.
    //
    // We still call [context.read] below for non-reactive access to
    // every other setting the page references (folder rule lookups,
    // setter calls, etc.).
    final String? watchedViewSettingsId = _viewSettingsId;
    context.select<SettingsProvider, int>(
      (s) => Object.hashAll([
        s.showFolderedAppsOnMainPage,
        s.pinUpdates,
        s.buryNonInstalled,
        s.sortColumn,
        s.sortOrder,
        s.appsListGroupBy,
        s.groupNonInstalledSeparately,
        s.groupTrackOnlySeparately,
        s.groupUpdatesSeparately,
        // categories is a Map<String?, int>; hash by length + sorted entries.
        Object.hashAll(s.categories.entries.map((e) => '${e.key}=${e.value}')),
        s.showAppTypeBadge,
        s.showTrackedStoreBadge,
        s.showCategoriesBadge,
        s.highlightTouchTargets,
        s.progressiveBlurEnabled,
        s.reduceVisualEffects,
        s.useGradientBackground,
        s.cardCornerScale,
        s.leftSwipeAction,
        s.rightSwipeAction,
        s.alwaysUsePhoneLayout,
        s.appFolders.length,
        // Per-view overrides: relevant for real folders and the synthetic
        // On-Demand Only view; a hash-as-zero collapse for the main page.
        watchedViewSettingsId == null
            ? 0
            : Object.hash(
                s.folderPinUpdates(watchedViewSettingsId),
                s.folderBuryNonInstalled(watchedViewSettingsId),
                s.folderSortColumn(watchedViewSettingsId).index,
                s.folderSortOrder(watchedViewSettingsId).index,
                s.folderGroupBy(watchedViewSettingsId).index,
                s.folderGroupNonInstalledSeparately(watchedViewSettingsId),
                s.folderGroupTrackOnlySeparately(watchedViewSettingsId),
                s.folderGroupUpdatesSeparately(watchedViewSettingsId),
              ),
      ]),
    );
    final SettingsProvider settingsProvider = context.read<SettingsProvider>();
    final existingFolderIds = settingsProvider.appFolders
        .map((f) => f.id)
        .toSet();
    final double appsListGroupCardRadius = settingsProvider.cardCornerRadiusFor(
      kM3eGroupCardRadius,
    );
    final double appsListCollapsedHeaderRadius = settingsProvider
        .cardCornerRadiusFor(SettingsProvider.baseCollapsedHeaderRadius);
    final double appsListItemOuterRadius = settingsProvider.cardCornerRadiusFor(
      kM3eOuterRadius,
    );
    final double appsListItemInnerRadius = settingsProvider.cardCornerRadiusFor(
      kM3eInnerRadius,
    );
    Future<void> backgroundScanStoreAvailability() async {
      late final List<String> idsForStoreHintScan;
      if (widget.onDemandOnlyList) {
        idsForStoreHintScan = appsProvider.apps.values
            .where((a) => a.app.additionalSettings['onDemandOnly'] == true)
            .map((a) => a.app.id)
            .toList();
      } else if (widget.folderId != null) {
        final String folderId = widget.folderId!;
        idsForStoreHintScan = appsProvider.apps.values
            .where((a) => folderIdsForApp(a.app).contains(folderId))
            .map((a) => a.app.id)
            .toList();
      } else {
        idsForStoreHintScan = appsProvider.apps.values
            .where((a) => a.app.additionalSettings['onDemandOnly'] != true)
            .map((a) => a.app.id)
            .toList();
      }
      if (idsForStoreHintScan.isEmpty) return;
      final cache = await BulkScanCache.load();
      final needsApkMirror = idsForStoreHintScan
          .where((id) => !(cache[id]?.containsKey('APKMirror') ?? false))
          .toList();
      final needsFDroid = idsForStoreHintScan
          .where((id) => !(cache[id]?.containsKey('F-Droid') ?? false))
          .toList();
      if (needsApkMirror.isEmpty && needsFDroid.isEmpty) return;
      await Future.wait([
        if (needsApkMirror.isNotEmpty)
          BulkImportService.checkApkMirror(
            needsApkMirror,
          ).then((r) => BulkScanCache.mergeStoreAndSave(cache, 'APKMirror', r)),
        if (needsFDroid.isNotEmpty)
          BulkImportService.checkFDroid(
            needsFDroid,
          ).then((r) => BulkScanCache.mergeStoreAndSave(cache, 'F-Droid', r)),
      ]);
    }

    Future<List<App>> refresh() {
      hapticLightImpact();
      setState(() {
        refreshingSince = DateTime.now();
        // Note: [_appListIconWarmFutures] is intentionally NOT cleared here.
        // Clearing it caused every visible row to re-enter [updateAppIcon] on
        // every pull-to-refresh, which on 50+ apps means 50 disk reads of the
        // user-icon override file plus 50 platform-channel calls back to the
        // OS - all on the UI isolate, all while the user is trying to scroll.
        // Icons are keyed by [App.id] and don't change just because we ran
        // an update check, so the warm map stays valid across refreshes.
        // Forced re-decode of a specific app's icon already goes through
        // [AppsProvider.updateAppIcon] with `ignoreCache: true` from the
        // app-detail page, which bypasses this map.
      });
      // Manual refresh checks exactly the apps currently visible on this
      // surface — the filtered/listed set, not every app in the folder/main
      // list. [_listedAppsCache] already has all active filters (search,
      // category, source, state) plus the folder / on-demand boundary applied
      // by the last build. An explicit ID list bypasses the background
      // freshness interval while [checkUpdates] still applies the
      // installed/track-only preference.
      final Future<List<App>> refreshFuture = appsProvider.checkUpdates(
        specificIds: _listedAppsCache.map((a) => a.app.id).toList(),
      );
      return refreshFuture
          .catchError((e) {
            if (!context.mounted) return <App>[];
            showError(e is Map ? e['errors'] : e);
            return <App>[];
          })
          .whenComplete(() {
            // Allow the progress bar to reach 100% before dismissing.
            return Future.delayed(
              LinearRipplingWavyProgressIndicator.defaultDragDuration,
            );
          })
          .whenComplete(() {
            setState(() {
              refreshingSince = null;
            });
            // Defer the background store-availability scan so the user gets
            // a few seconds of unimpeded UI right after the refresh
            // completes. Reset the timer if another refresh fires before the
            // delay elapses (debounce-ish behaviour: only the most recent
            // refresh's scan is queued at any time).
            _deferredStoreScanTimer?.cancel();
            _deferredStoreScanTimer = Timer(_deferredStoreScanDelay, () {
              _deferredStoreScanTimer = null;
              if (!mounted) return;
              unawaited(backgroundScanStoreAvailability());
            });
          });
    }

    if (!widget.onDemandOnlyList &&
        !appsProvider.loadingApps &&
        appsProvider.apps.isNotEmpty &&
        settingsProvider.checkJustStarted() &&
        settingsProvider.checkOnStart) {
      _refreshIndicatorKey.currentState?.show();
    }

    // Keep only IDs that still exist in the provider (e.g. after a delete).
    selectedAppIds = selectedAppIds
        .where((element) => appsProvider.apps.containsKey(element))
        .toSet();

    void toggleAppSelected(App app) {
      setState(() {
        if (selectedAppIds.contains(app.id)) {
          selectedAppIds.removeWhere((a) => a == app.id);
        } else {
          selectedAppIds.add(app.id);
        }
      });
      _notifyHomeFabChromeIfChanged();
    }

    // ── Cached filter / sort / reorder ─────────────────────────────────────
    // filter+sort is O(n log n). We skip the entire pass when nothing that
    // affects list ordering has changed — e.g. tapping to select a row or
    // toggling the refresh indicator doesn't need a new sort.
    final int listBuildToken = Object.hashAll([
      appsToken,
      widget.onDemandOnlyList,
      widget.folderId,
      settingsProvider.showFolderedAppsOnMainPage,
      filter.nameFilter,
      filter.authorFilter,
      filter.upToDateFilterIntent.index,
      filter.installedFilterIntent.index,
      filter.trackOnlyFilterIntent.index,
      Object.hashAll(filter.includedCategoryFilter.toList()..sort()),
      Object.hashAll(filter.excludedCategoryFilter.toList()..sort()),
      filter.categoryMatchMode.index,
      filter.sourceFilter,
      _effectiveSortColumn(settingsProvider).index,
      _effectiveSortOrder(settingsProvider).index,
      _effectiveGroupBy(settingsProvider).index,
      _effectivePinUpdates(settingsProvider),
      _effectiveBuryNonInstalled(settingsProvider),
      _effectiveGroupNonInstalledSeparately(settingsProvider),
      _effectiveGroupTrackOnlySeparately(settingsProvider),
      _effectiveGroupUpdatesSeparately(settingsProvider),
    ]);
    if (listBuildToken != _lastListBuildToken) {
      _lastListBuildToken = listBuildToken;
      var workingList = appsProvider.apps.values.toList();

      if (widget.onDemandOnlyList) {
        workingList = workingList
            .where(
              (appInMem) =>
                  appInMem.app.additionalSettings['onDemandOnly'] == true,
            )
            .toList();
      } else {
        workingList = workingList
            .where(
              (appInMem) =>
                  appInMem.app.additionalSettings['onDemandOnly'] != true,
            )
            .toList();
      }

      // ── Folder filter ───────────────────────────────────────────────────
      if (widget.folderId != null) {
        workingList = workingList
            .where(
              (appInMem) =>
                  folderIdsForApp(appInMem.app).contains(widget.folderId),
            )
            .toList();
      } else if (!widget.onDemandOnlyList &&
          !settingsProvider.showFolderedAppsOnMainPage) {
        // On the main page only: hide apps that belong to any folder.
        // The on-demand page shows all on-demand apps regardless of folder membership.
        workingList = workingList
            .where(
              (appInMem) => folderIdsForApp(
                appInMem.app,
              ).where((id) => existingFolderIds.contains(id)).isEmpty,
            )
            .toList();
      }

      // Single source of truth for "does this app pass the active filters".
      // Reused below to compute cross-folder search matches so the two lists
      // never drift apart.
      bool appMatchesFilters(AppInMemory app) {
        if (!appMatchesUpToDateFilter(app.app, filter.upToDateFilterIntent)) {
          return false;
        }
        if (!appMatchesInstalledFilter(app.app, filter.installedFilterIntent)) {
          return false;
        }
        if (!appMatchesTrackOnlyFilter(app.app, filter.trackOnlyFilterIntent)) {
          return false;
        }
        if (filter.nameFilter.isNotEmpty || filter.authorFilter.isNotEmpty) {
          final nameTokens = filter.nameFilter
              .split(' ')
              .where((element) => element.trim().isNotEmpty)
              .toList();
          final authorTokens = filter.authorFilter
              .split(' ')
              .where((element) => element.trim().isNotEmpty)
              .toList();
          for (final t in nameTokens) {
            if (!app.name.toLowerCase().contains(t.toLowerCase())) {
              return false;
            }
          }
          for (final t in authorTokens) {
            if (!app.author.toLowerCase().contains(t.toLowerCase())) {
              return false;
            }
          }
        }
        if (!appCategoriesMatchFilter(
          app.app.categories,
          includedCategories: filter.includedCategoryFilter,
          excludedCategories: filter.excludedCategoryFilter,
          matchMode: filter.categoryMatchMode,
        )) {
          return false;
        }
        if (filter.sourceFilter.isNotEmpty &&
            sourceProvider
                    .getSourceTemplate(
                      app.app.url,
                      overrideSource: app.app.overrideSource,
                    )
                    .sourceIdentifier !=
                filter.sourceFilter) {
          return false;
        }
        return true;
      }

      workingList = workingList.where(appMatchesFilters).toList();

      final sortCol = _effectiveSortColumn(settingsProvider);
      final sortOrd = _effectiveSortOrder(settingsProvider);
      workingList.sort((a, b) {
        int result = 0;
        if (sortCol == SortColumnSettings.authorName) {
          result = ((a.author + a.name).toLowerCase()).compareTo(
            (b.author + b.name).toLowerCase(),
          );
        } else if (sortCol == SortColumnSettings.nameAuthor) {
          result = ((a.name + a.author).toLowerCase()).compareTo(
            (b.name + b.author).toLowerCase(),
          );
        } else if (sortCol == SortColumnSettings.releaseDate) {
          // Handle null dates: apps with unknown release dates go to end.
          final aDate = a.app.releaseDate;
          final bDate = b.app.releaseDate;
          final isDescending = sortOrd == SortOrderSettings.descending;
          if (aDate == null && bDate == null) {
            result = ((a.name + a.author).toLowerCase()).compareTo(
              (b.name + b.author).toLowerCase(),
            );
          } else if (aDate == null) {
            result = isDescending ? -1 : 1;
          } else if (bDate == null) {
            result = isDescending ? 1 : -1;
          } else {
            result = aDate.compareTo(bDate);
          }
        } else if (sortCol == SortColumnSettings.lastUpdateCheck) {
          final aDate = a.app.lastUpdateCheck;
          final bDate = b.app.lastUpdateCheck;
          final isDescending = sortOrd == SortOrderSettings.descending;
          if (aDate == null && bDate == null) {
            result = ((a.name + a.author).toLowerCase()).compareTo(
              (b.name + b.author).toLowerCase(),
            );
          } else if (aDate == null) {
            result = isDescending ? -1 : 1;
          } else if (bDate == null) {
            result = isDescending ? 1 : -1;
          } else {
            result = aDate.compareTo(bDate);
          }
        } else if (sortCol == SortColumnSettings.added) {
          result = 0;
        }
        return result;
      });

      if (sortOrd == SortOrderSettings.descending) {
        workingList = workingList.reversed.toList();
      }

      // Cache existingUpdates together with the list: pinUpdates ordering
      // depends on it and it's a pure function of app state (in the token).
      _existingUpdatesCache = appsProvider
          .findExistingUpdates(
            installedOnly: true,
            includeVersionOrderUncertain: true,
          )
          .toList();
      _newInstallsCache = appsProvider
          .findExistingUpdates(nonInstalledOnly: true)
          .toList();

      if (_effectivePinUpdates(settingsProvider)) {
        final temp = <AppInMemory>[];
        workingList = workingList.where((sa) {
          if (_existingUpdatesCache.contains(sa.app.id)) {
            temp.add(sa);
            return false;
          }
          return true;
        }).toList();
        workingList = [...temp, ...workingList];
      }

      if (_effectiveBuryNonInstalled(settingsProvider)) {
        final temp = <AppInMemory>[];
        workingList = workingList.where((sa) {
          if (sa.app.installedVersion == null) {
            temp.add(sa);
            return false;
          }
          return true;
        }).toList();
        workingList = [...workingList, ...temp];
      }

      final tempPinned = <AppInMemory>[];
      final tempNotPinned = <AppInMemory>[];
      for (final a in workingList) {
        if (a.app.pinned) {
          tempPinned.add(a);
        } else {
          tempNotPinned.add(a);
        }
      }
      _listedAppsCache = [...tempPinned, ...tempNotPinned];

      // ── Cross-folder search matches ─────────────────────────────────────
      // On the main page, apps that live inside a folder — or in the On-Demand
      // Only bucket — are hidden from the list, so a plain search would
      // dead-end on them. When a text search is active we gather those hidden
      // matches here and render them below the results under per-bucket
      // headers. In a folder / on-demand view the user deliberately narrowed
      // scope, so search stays scoped there and this stays empty.
      _crossFolderMatchesCache = const [];
      final bool crossFolderSearchActive =
          !widget.onDemandOnlyList &&
          widget.folderId == null &&
          (filter.nameFilter.trim().isNotEmpty ||
              filter.authorFilter.trim().isNotEmpty);
      if (crossFolderSearchActive) {
        final Set<String> mainListedIds = {
          for (final a in _listedAppsCache) a.app.id,
        };
        // Folder id → its position in settings order, for picking a single
        // home folder when an app belongs to several (avoids listing — and
        // Hero-tagging — the same app more than once in this section).
        final Map<String, int> folderOrder = {
          for (int i = 0; i < settingsProvider.appFolders.length; i++)
            settingsProvider.appFolders[i].id: i,
        };
        final Map<String, List<AppInMemory>> matchesByFolder = {};
        final List<AppInMemory> onDemandMatches = [];
        for (final appInMem in appsProvider.apps.values) {
          if (mainListedIds.contains(appInMem.app.id)) {
            continue; // already shown in the main results — no duplicate
          }
          if (!appMatchesFilters(appInMem)) continue;
          // On-demand apps are their own exclusive bucket (never in folders on
          // the main page), so route them there and don't also fold-group them.
          if (appInMem.app.additionalSettings['onDemandOnly'] == true) {
            onDemandMatches.add(appInMem);
            continue;
          }
          final List<String> folderIds = folderIdsForApp(
            appInMem.app,
          ).where(existingFolderIds.contains).toList();
          if (folderIds.isEmpty) continue; // not filed into any live folder
          // Home folder = the earliest one in settings order.
          folderIds.sort(
            (a, b) => (folderOrder[a] ?? 1 << 30).compareTo(
              folderOrder[b] ?? 1 << 30,
            ),
          );
          (matchesByFolder[folderIds.first] ??= <AppInMemory>[]).add(appInMem);
        }
        int byName(AppInMemory a, AppInMemory b) => (a.name + a.author)
            .toLowerCase()
            .compareTo((b.name + b.author).toLowerCase());
        final matches =
            <({String? folderId, String folderName, List<AppInMemory> apps})>[];
        // Folders first, in their configured order, for a stable listing.
        for (final folder in settingsProvider.appFolders) {
          final List<AppInMemory>? apps = matchesByFolder[folder.id];
          if (apps == null || apps.isEmpty) continue;
          apps.sort(byName);
          matches.add((
            folderId: folder.id,
            folderName: folder.name,
            apps: apps,
          ));
        }
        // On-Demand Only last, mirroring its position in the folder-button
        // list. A null folderId marks it as the on-demand bucket.
        if (onDemandMatches.isNotEmpty) {
          onDemandMatches.sort(byName);
          matches.add((folderId: null, folderName: '', apps: onDemandMatches));
        }
        if (matches.isNotEmpty) {
          _crossFolderMatchesCache = matches;
        }
      }
    }
    // ── Use cached results ──────────────────────────────────────────────────
    var listedApps = _listedAppsCache;

    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool isLargeScreen =
        screenWidth >= kLargeScreenWidthBreakpoint &&
        !context.read<SettingsProvider>().isTV &&
        !settingsProvider.alwaysUsePhoneLayout;
    // Row-invariant for this frame: compute once here instead of in the
    // per-row builder ([getSingleAppHorizTile]), which otherwise re-ran this
    // O(n) scan for every materialized row during a fling.
    final bool downloadsRunning = appsProvider.areDownloadsRunning();

    // The two-panel layout needs an effective selection, but mutating
    // [selectedAppId] during build is a Flutter anti-pattern. Derive it locally
    // for this frame, then reconcile the persisted field after the frame so
    // taps and later reads stay consistent.
    // A cross-folder search result is a valid two-pane selection too, even
    // though it isn't in [listedApps] — otherwise tapping one would be reset
    // to the first main-list app on the next frame.
    bool isSelectableAppId(String id) =>
        listedApps.any((sa) => sa.app.id == id) ||
        _crossFolderMatchesCache.any((g) => g.apps.any((a) => a.app.id == id));
    String? effectiveSelectedAppId = selectedAppId;
    if (isLargeScreen) {
      if (effectiveSelectedAppId == null && listedApps.isNotEmpty) {
        effectiveSelectedAppId = listedApps.first.app.id;
      } else if (effectiveSelectedAppId != null &&
          !isSelectableAppId(effectiveSelectedAppId)) {
        effectiveSelectedAppId = listedApps.isNotEmpty
            ? listedApps.first.app.id
            : null;
      }
      if (effectiveSelectedAppId != selectedAppId) {
        final String? reconciled = effectiveSelectedAppId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && selectedAppId != reconciled) {
            setState(() => selectedAppId = reconciled);
          }
        });
      }
    }

    // Multi-select puts batch actions in pane 2; hide duplicate list FABs then.
    final bool showSplitPaneListFabs =
        isLargeScreen &&
        widget.folderId == null &&
        !widget.onDemandOnlyList &&
        selectedAppIds.isEmpty;
    final bool showFolderListFabs =
        isLargeScreen &&
        (widget.folderId != null || widget.onDemandOnlyList) &&
        selectedAppIds.isEmpty;

    // On-demand and per-folder app/update counts. Recomputed only when app
    // state ([appsToken]) or the folder set changes — not on every rebuild.
    // A single pass over the apps fills all three maps (previously this was
    // three separate full scans, each O(apps × folders)).
    final appFolders = settingsProvider.appFolders;
    final int folderCountsToken = Object.hash(
      appsToken,
      Object.hashAll(appFolders.map((f) => f.id)),
    );
    if (folderCountsToken != _lastFolderCountsToken) {
      _lastFolderCountsToken = folderCountsToken;
      int onDemand = 0;
      final Map<String, int> appCounts = {for (final f in appFolders) f.id: 0};
      final Map<String, int> updateCounts = {
        for (final f in appFolders) f.id: 0,
      };
      for (final a in appsProvider.apps.values) {
        if (a.app.additionalSettings['onDemandOnly'] == true) {
          onDemand++;
          continue;
        }
        final bool hasUpdate =
            appHasActionableUpdate(a.app) || versionOrderUncertainUpdate(a.app);
        for (final fid in folderIdsForApp(a.app)) {
          final int? current = appCounts[fid];
          if (current == null) continue; // folder no longer exists
          appCounts[fid] = current + 1;
          if (hasUpdate) updateCounts[fid] = updateCounts[fid]! + 1;
        }
      }
      _onDemandOnlyAppCountCache = onDemand;
      _folderAppCountsCache = appCounts;
      _folderUpdateCountsCache = updateCounts;
    }
    final int onDemandOnlyAppCount = _onDemandOnlyAppCountCache;
    final Map<String, int> folderAppCounts = _folderAppCountsCache;
    final Map<String, int> folderUpdateCounts = _folderUpdateCountsCache;
    final String? currentFolderName = widget.folderId != null
        ? appFolders
              .where((f) => f.id == widget.folderId)
              .map((f) => f.name)
              .firstOrNull
        : null;

    // Membership set so the filters below are O(updates) instead of
    // O(updates × apps) from a `listedApps.any(...)` scan per id.
    final separateUpdates = _effectiveGroupUpdatesSeparately(settingsProvider);
    bool isInUpdatesGroup(AppInMemory entry) =>
        separateUpdates &&
        _existingUpdatesCache.contains(entry.app.id) &&
        (widget.onDemandOnlyList ||
            entry.app.additionalSettings['onDemandOnly'] != true);

    final Set<String> listedAppIdSet = {
      for (final AppInMemory listed in listedApps) listed.app.id,
    };

    List<String> filterListedMassObtainIds(Iterable<String> ids) =>
        ids.where((id) => listedAppIdSet.contains(id)).toList();

    // Mass-obtain / bulk sheet: listed pending updates (not gated on a
    // separate Updates group — default [groupUpdatesSeparately] is false).
    var existingUpdateIdsAllOrSelected = filterListedMassObtainIds(
      _existingUpdatesCache,
    );
    var newInstallIdsAllOrSelected = filterListedMassObtainIds(
      _newInstallsCache,
    );

    final List<String> trackOnlyUpdateIdsAllOrSelected = [];
    for (final String id in [
      ...existingUpdateIdsAllOrSelected,
      ...newInstallIdsAllOrSelected,
    ]) {
      if (appsProvider.apps[id]?.app.additionalSettings['trackOnly'] == true) {
        trackOnlyUpdateIdsAllOrSelected.add(id);
      }
    }
    existingUpdateIdsAllOrSelected = existingUpdateIdsAllOrSelected
        .where((id) => !trackOnlyUpdateIdsAllOrSelected.contains(id))
        .toList();
    newInstallIdsAllOrSelected = newInstallIdsAllOrSelected
        .where((id) => !trackOnlyUpdateIdsAllOrSelected.contains(id))
        .toList();

    // FAB badge: grouped Updates section only when that section exists.
    final Set<String> pageUpdateBadgeIds = separateUpdates
        ? {
            for (final AppInMemory listed in listedApps)
              if (isInUpdatesGroup(listed)) listed.app.id,
          }
        : existingUpdateIdsAllOrSelected.toSet();
    if (selectedAppIds.isEmpty) {
      pageUpdateCount = pageUpdateBadgeIds.length;
    } else {
      int count = 0;
      for (final id in selectedAppIds) {
        if (pageUpdateBadgeIds.contains(id)) {
          count++;
        }
      }
      pageUpdateCount = count;
    }

    final effectiveGroupBy = _effectiveGroupBy(settingsProvider);
    final segregateNonInstalled =
        _effectiveGroupNonInstalledSeparately(settingsProvider) &&
        (effectiveGroupBy == AppsListGroupBy.category ||
            effectiveGroupBy == AppsListGroupBy.source ||
            effectiveGroupBy == AppsListGroupBy.appType);
    final segregateTrackOnly =
        _effectiveGroupTrackOnlySeparately(settingsProvider) &&
        (effectiveGroupBy == AppsListGroupBy.category ||
            effectiveGroupBy == AppsListGroupBy.source ||
            effectiveGroupBy == AppsListGroupBy.appType);

    final tempRenamed = <AppInMemory>[];
    final tempPinned = <AppInMemory>[];
    final tempNotPinned = <AppInMemory>[];
    for (final AppInMemory listedApp in listedApps) {
      if (listedApp.app.hasPendingRepoRename) {
        tempRenamed.add(listedApp);
      } else if (listedApp.app.pinned) {
        tempPinned.add(listedApp);
      } else {
        tempNotPinned.add(listedApp);
      }
    }
    listedApps = [...tempRenamed, ...tempPinned, ...tempNotPinned];

    // Apps that go into normal category/source/appType groups (excluding
    // segregated non-installed, segregated track-only, and the updates group when those features are on).
    List<AppInMemory> appsForGroups(List<AppInMemory> source) => source
        .where(
          (e) =>
              !(segregateNonInstalled && e.app.installedVersion == null) &&
              !(segregateTrackOnly &&
                  e.app.additionalSettings['trackOnly'] == true) &&
              !isInUpdatesGroup(e),
        )
        .toList();

    final appsListedForCategoryKeys = appsForGroups(listedApps);
    final appsListedForSourceKeys = appsListedForCategoryKeys;
    final appsListedForAppTypeKeys = appsListedForCategoryKeys;

    if (listBuildToken != _lastGroupIndexCacheToken) {
      _lastGroupIndexCacheToken = listBuildToken;

      // 1. Categories
      if (effectiveGroupBy == AppsListGroupBy.category) {
        List<String?> getListedCategories(List<AppInMemory> appsSource) {
          final temp = appsSource.map(
            (e) => e.app.categories.isNotEmpty ? e.app.categories : [null],
          );
          return temp.isNotEmpty
              ? {
                  ...temp.reduce((v, e) => [...v, ...e]),
                }.toList()
              : [];
        }

        final cats = getListedCategories(appsListedForCategoryKeys);
        cats.sort((a, b) {
          return a != null && b != null
              ? a.toLowerCase().compareTo(b.toLowerCase())
              : a == null
              ? 1
              : -1;
        });
        _listedCategoriesCache = cats;

        final nextCategoryMap = <String, List<int>>{};
        for (
          int categoryIndex = 0;
          categoryIndex < _listedCategoriesCache.length;
          categoryIndex++
        ) {
          final String? categoryNullable =
              _listedCategoriesCache[categoryIndex];
          final String mapKey = categoryNullable ?? '__null__';
          final indices = <int>[];
          for (
            int listingIndex = 0;
            listingIndex < listedApps.length;
            listingIndex++
          ) {
            final AppInMemory row = listedApps[listingIndex];
            if (segregateNonInstalled && row.app.installedVersion == null) {
              continue;
            }
            if (segregateTrackOnly &&
                row.app.additionalSettings['trackOnly'] == true) {
              continue;
            }
            if (isInUpdatesGroup(row)) continue;
            if (row.app.categories.contains(categoryNullable) ||
                (row.app.categories.isEmpty && categoryNullable == null)) {
              indices.add(listingIndex);
            }
          }
          nextCategoryMap[mapKey] = indices;
        }
        _categoryGroupListedIndices = nextCategoryMap;
      } else {
        _listedCategoriesCache = const [];
        _categoryGroupListedIndices = const {};
      }

      // 2. Sources
      if (effectiveGroupBy == AppsListGroupBy.source) {
        List<String> getListedSourceKeys(List<AppInMemory> appsSource) {
          if (appsSource.isEmpty) return [];
          final keys = appsSource
              .map(
                (e) => sourceProvider
                    .getSourceTemplate(
                      e.app.url,
                      overrideSource: e.app.overrideSource,
                    )
                    .sourceIdentifier,
              )
              .toSet()
              .toList();
          keys.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return keys;
        }

        _listedSourcesCache = getListedSourceKeys(appsListedForSourceKeys);

        final nextSourceMap = <String, List<int>>{};
        for (
          int sourceIndex = 0;
          sourceIndex < _listedSourcesCache.length;
          sourceIndex++
        ) {
          final String sourceKey = _listedSourcesCache[sourceIndex];
          final indices = <int>[];
          for (
            int listingIndex = 0;
            listingIndex < listedApps.length;
            listingIndex++
          ) {
            final AppInMemory row = listedApps[listingIndex];
            if (segregateNonInstalled && row.app.installedVersion == null) {
              continue;
            }
            if (segregateTrackOnly &&
                row.app.additionalSettings['trackOnly'] == true) {
              continue;
            }
            if (isInUpdatesGroup(row)) continue;
            if (sourceProvider
                    .getSourceTemplate(
                      row.app.url,
                      overrideSource: row.app.overrideSource,
                    )
                    .sourceIdentifier ==
                sourceKey) {
              indices.add(listingIndex);
            }
          }
          nextSourceMap[sourceKey] = indices;
        }
        _sourceGroupListedIndices = nextSourceMap;
      } else {
        _listedSourcesCache = const [];
        _sourceGroupListedIndices = const {};
      }

      // 3. App Types
      if (effectiveGroupBy == AppsListGroupBy.appType) {
        _listedAppTypesCache = AppTypeGroup.values
            .where(
              (t) =>
                  appsListedForAppTypeKeys.any((e) => classifyAppType(e) == t),
            )
            .toList();

        final nextAppTypeMap = <AppTypeGroup, List<int>>{};
        for (final type in _listedAppTypesCache) {
          final indices = <int>[];
          for (
            int listingIndex = 0;
            listingIndex < listedApps.length;
            listingIndex++
          ) {
            final AppInMemory row = listedApps[listingIndex];
            if (segregateNonInstalled && row.app.installedVersion == null) {
              continue;
            }
            if (segregateTrackOnly &&
                row.app.additionalSettings['trackOnly'] == true) {
              continue;
            }
            if (isInUpdatesGroup(row)) continue;
            if (classifyAppType(row) == type) {
              indices.add(listingIndex);
            }
          }
          if (indices.isNotEmpty) nextAppTypeMap[type] = indices;
        }
        _appTypeGroupListedIndices = nextAppTypeMap;
      } else {
        _listedAppTypesCache = const [];
        _appTypeGroupListedIndices = const {};
      }

      // Group membership is a strict hierarchy — each app lands in at most one
      // of these groups: Updates > Track-only > Not-installed. An app with an
      // actionable update therefore never also shows under Track-only or
      // Not-installed, and a track-only app never doubles as Not-installed.
      final nonInstalled = <int>[];
      final trackOnlyList = <int>[];
      for (
        int listingIndex = 0;
        listingIndex < listedApps.length;
        listingIndex++
      ) {
        final AppInMemory row = listedApps[listingIndex];
        // Updates has the highest priority (isInUpdatesGroup already accounts
        // for whether updates grouping is enabled).
        if (isInUpdatesGroup(row)) continue;
        final isTrackOnly = row.app.additionalSettings['trackOnly'] == true;
        if (isTrackOnly) {
          if (segregateTrackOnly) {
            trackOnlyList.add(listingIndex);
          } else if (row.app.installedVersion == null) {
            nonInstalled.add(listingIndex);
          }
        } else {
          if (row.app.installedVersion == null) {
            nonInstalled.add(listingIndex);
          }
        }
      }
      _nonInstalledListedIndices = nonInstalled;
      _trackOnlyListedIndices = trackOnlyList;

      final updatesIndices = <int>[];
      for (
        int listingIndex = 0;
        listingIndex < listedApps.length;
        listingIndex++
      ) {
        if (isInUpdatesGroup(listedApps[listingIndex])) {
          updatesIndices.add(listingIndex);
        }
      }
      _updatesGroupListedIndices = updatesIndices;
    }

    final showNonInstalledGroupSection =
        segregateNonInstalled && _nonInstalledListedIndices.isNotEmpty;
    final showTrackOnlyGroupSection =
        segregateTrackOnly && _trackOnlyListedIndices.isNotEmpty;
    final showUpdatesGroupSection =
        separateUpdates && listedApps.any(isInUpdatesGroup);

    final listedCategories = _listedCategoriesCache;
    final listedSources = _listedSourcesCache;
    final listedAppTypes = _listedAppTypesCache;

    List<String> getActiveGroupKeys() {
      final folderPrefix = widget.folderId != null
          ? 'folder_${widget.folderId}_'
          : '';
      final List<String> keys = [];
      if (effectiveGroupBy == AppsListGroupBy.category) {
        for (final category in listedCategories) {
          keys.add('${folderPrefix}cat:${category ?? '__null__'}');
        }
      } else if (effectiveGroupBy == AppsListGroupBy.source) {
        for (final source in listedSources) {
          keys.add('${folderPrefix}src:$source');
        }
      } else if (effectiveGroupBy == AppsListGroupBy.appType) {
        for (final type in listedAppTypes) {
          keys.add('${folderPrefix}appType:${type.name}');
        }
      }
      if (showNonInstalledGroupSection) {
        keys.add('${folderPrefix}__nonInstalled__');
      }
      if (showTrackOnlyGroupSection) {
        keys.add('${folderPrefix}__trackOnly__');
      }
      if (showUpdatesGroupSection) {
        keys.add('${folderPrefix}__updates__');
      }
      return keys;
    }

    final activeGroupKeys = getActiveGroupKeys();
    final bool allGroupsExpanded =
        activeGroupKeys.isNotEmpty &&
        activeGroupKeys.every((key) => !_collapsedGroups.contains(key));

    // Resolve selected apps from the authoritative app map, not [listedApps]:
    // cross-folder / on-demand search results are selectable but are NOT in
    // [listedApps], so scoping to it would yield an empty set for those (which
    // made bulk actions no-op and made `apps.every(...)` checks vacuously true
    // — e.g. every folder pre-checked in the add-to-folder dialog).
    Set<App> getSelectedApps() => {
      for (final id in selectedAppIds)
        if (appsProvider.apps[id] != null) appsProvider.apps[id]!.app,
    };
    final Set<App> selectedApps = getSelectedApps();

    List<Widget> getLoadingWidgets() {
      if (appsProvider.loadingApps && appsProvider.apps.isEmpty) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Semantics(
                label: tr('pleaseWait'),
                child: const CircularRipplingWavyProgressIndicator(),
              ),
            ),
          ),
        ];
      }
      final bool isMainAppsPage =
          !widget.onDemandOnlyList && widget.folderId == null;
      final bool filterActive = !filter.isIdenticalTo(
        neutralFilter,
        settingsProvider,
      );
      final Widget emptyStateContent;
      if (filterActive && appsProvider.apps.isNotEmpty) {
        // A filter / search matched nothing — anywhere it's applied (main
        // page, a folder, or the on-demand list). Offer an escape hatch.
        emptyStateContent = AppEmptyState(
          illustration: const AppFilterEmptyIllustration(),
          title: tr('noAppsForFilter'),
          subtitle: tr('noAppsForFilterSubtitle'),
          action: FilledButton.tonalIcon(
            onPressed: () => setState(() {
              filter = AppsFilter();
              _searchController.clear();
            }),
            icon: const Icon(Icons.filter_alt_off_rounded),
            label: Text(tr('clearFilters')),
          ),
        );
      } else if (widget.onDemandOnlyList && onDemandOnlyAppCount == 0) {
        emptyStateContent = AppEmptyState(
          illustration: const AppArchiveEmptyIllustration(),
          title: tr('onDemandOnlyEmptyTitle'),
          subtitle: tr('onDemandOnlyEmpty'),
        );
      } else {
        // Pristine library, or an emptied folder (no active filter): nudge the
        // user toward adding an app. Folders use this same state — not the
        // "clear filters" one — when they simply have no apps.
        emptyStateContent = AppEmptyState(
          illustration: const AppLibraryEmptyIllustration(),
          title: tr('noApps'),
          subtitle: tr('noAppsSubtitle'),
          action: FilledButton.icon(
            onPressed: () async {
              // A folder list is a route pushed on top of the shell (HomePage
              // is a sibling route under the root navigator, not an ancestor),
              // so reach the shell via its global key rather than
              // findAncestorState — which returns null from a pushed route.
              // Pop the folder first so the tab switch isn't hidden behind it.
              if (widget.folderId != null) {
                await Navigator.of(context).maybePop();
              }
              final HomePageState? home = homePageKey.currentState;
              if (home != null) {
                unawaited(home.switchToPage(1));
              }
            },
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('addApp')),
          ),
        );
      }
      return [
        // Don't show the empty-state message when the only matches live in
        // folders — the "Found in your folders" section below carries them.
        if (listedApps.isEmpty && _crossFolderMatchesCache.isEmpty)
          isMainAppsPage
              ? SliverLayoutBuilder(
                  builder: (context, constraints) {
                    // Centre the empty state in the space *above* the
                    // bottom-pinned "Manage folders" footer (a trailing
                    // SliverFillRemaining) + the nav pill. Reserving that room
                    // here keeps the taller illustration from shoving the
                    // footer down behind the pill.
                    final double available =
                        constraints.viewportMainAxisExtent -
                        constraints.precedingScrollExtent;
                    // Reserve room for whatever the bottom footer will actually
                    // render (Manage folders + one button per folder + the
                    // On-Demand entry, each shown conditionally) plus the nav
                    // pill, so centring the illustration never pushes those
                    // buttons behind the pill. Scales with folder count and the
                    // user's font size.
                    final double btn =
                        48 * MediaQuery.textScalerOf(context).scale(1.0);
                    final bool showManage =
                        appsProvider.apps.isNotEmpty || appFolders.isNotEmpty;
                    double footer = 0;
                    if (showManage) footer += btn;
                    if (appFolders.isNotEmpty) {
                      footer += 8 + appFolders.length * (btn + 8);
                    }
                    if (onDemandOnlyAppCount > 0) footer += btn + 8;
                    if (footer > 0) footer += 20; // footer's own top padding
                    final double navClear = isLargeScreen ? 52.0 : 80.0;
                    final double footerReserve =
                        MediaQuery.paddingOf(context).bottom +
                        navClear +
                        footer;
                    final double boxHeight = math.max(
                      0.0,
                      available - footerReserve,
                    );
                    return SliverToBoxAdapter(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: boxHeight),
                        child: Center(child: emptyStateContent),
                      ),
                    );
                  },
                )
              : SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    // Exclude the floating nav pill from the centring region so
                    // the whole block sits at the visible optical centre, not
                    // biased low toward the screen edge.
                    padding: EdgeInsets.only(
                      bottom:
                          MediaQuery.paddingOf(context).bottom +
                          (isLargeScreen ? 52.0 : 80.0),
                    ),
                    child: Center(child: emptyStateContent),
                  ),
                ),
        // Initial empty-library loading uses the centered M3E indicator above.
        // Keep this compact bar for explicit user-initiated refreshes only.
        if (refreshingSince != null)
          SliverToBoxAdapter(
            // Top padding pushes the bar clear of the [CustomAppBar] blur
            // overlay's bottom edge - sitting flush against it produced a
            // visible half-blurred line through the indicator.
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _RefreshProgressBar(refreshingSince: refreshingSince),
            ),
          ),
      ];
    }

    GestureDetector getAppIcon(int appIndex, {AppInMemory? appOverride}) {
      final String rowAppId = (appOverride ?? listedApps[appIndex]).app.id;
      // Kick off icon loading once; putIfAbsent prevents duplicate loads.
      // _AppIconWidget independently watches the icon bytes via context.select,
      // so only that widget rebuilds when the icon arrives — not the full page.
      if (appsProvider.apps[rowAppId]?.icon == null) {
        _appListIconWarmFutures.putIfAbsent(
          rowAppId,
          () => appsProvider.updateAppIcon(rowAppId),
        );
      }
      return GestureDetector(
        child: Hero(
          tag: widget.folderId != null
              ? 'folder-${widget.folderId}-icon-$rowAppId'
              : 'app-icon-$rowAppId',
          // Preserve the ClipRRect/shape during the flight.
          flightShuttleBuilder: (_, animation, _, _, _) =>
              _AppIconWidget(appId: rowAppId),
          child: _AppIconWidget(appId: rowAppId),
        ),
        onDoubleTap: () => packageManager.openApp(rowAppId),
        onLongPress: () {
          Navigator.push(
            context,
            heroFriendlyAppPageRoute(
              (_) => AppPage(
                appId: rowAppId,
                showOppositeOfPreferredView: true,
                appsListHeroFolderId: widget.folderId,
              ),
            ),
          );
        },
      );
    }

    Widget getSingleAppHorizTile(
      int index, {
      M3eListGroupPosition? groupPosition,
      bool flatListBody = false,
      AppInMemory? appOverride,
    }) {
      final app = appOverride ?? listedApps[index];
      final appId = app.app.id;
      final installed = app.app.installedVersion;
      final hasUpdate = installed != null && appHasActionableUpdate(app.app);
      final hasUncertainUpdate =
          installed != null && versionOrderUncertainUpdate(app.app);
      final sourceHost = sourceProvider
          .getSourceTemplate(
            app.app.url,
            overrideSource: app.app.overrideSource,
          )
          .hosts
          .firstOrNull;
      // M3 Container Transform: tapping the row morphs the row's container
      // into the AppPage's container. Replaces the previous
      // `Navigator.push(heroFriendlyAppPageRoute(...))` flow plus the
      // `_heroKeepaliveAppId` keep-alive state machine - OpenContainer
      // owns the widget lifecycle during the morph, so we no longer
      // need to keep the source row alive manually.
      //
      // Selection mode (`selectedAppIds.isNotEmpty`) still routes the tap
      // to [toggleAppSelected]; it never triggers the morph in that mode.
      // Long-press still toggles selection. Swipe actions on the row are
      // unaffected because they're handled inside [_SwipeableListItem].
      // The icon's own onLongPress (which opens AppPage with the opposite
      // view) still uses the standard Navigator.push - that's a secondary
      // path and doesn't benefit from container transform.
      final BorderRadius? itemRadius = groupPosition != null
          ? m3eListGroupItemRadius(
              groupPosition,
              flatListBody: flatListBody,
              outerRadius: appsListItemOuterRadius,
              innerRadius: appsListItemInnerRadius,
            )
          : null;

      // [isLargeScreen] is computed once per frame in the enclosing build
      // scope; the per-row recomputation (and its MediaQuery.sizeOf dependency,
      // which made every row rebuild on any metrics change) was redundant.

      // Builds the row visual given the callback that should fire when the
      // user taps a non-selected row. Used by both the OpenContainer path
      // (callback = openContainer) and the [reduceVisualEffects] fallback
      // path (callback = direct Navigator.push).
      Widget buildRowWith(VoidCallback navigateToAppPage) => _SwipeableListItem(
        key: ValueKey(appId),
        appId: appId,
        hasUpdate: hasUpdate || hasUncertainUpdate,
        isPinned: app.app.pinned,
        isInstalled: installed != null,
        areDownloadsRunning: downloadsRunning,
        keepAlive: false,
        rightAction: settingsProvider.rightSwipeAction,
        leftAction: settingsProvider.leftSwipeAction,
        appsListHeroFolderId: widget.folderId,
        child: _AppListItem(
          appId: appId,
          isSelected: selectedAppIds.contains(appId),
          isSplitPaneActive:
              isLargeScreen &&
              effectiveSelectedAppId == appId &&
              selectedAppIds.isEmpty,
          showCheckmark: selectedAppIds.contains(appId),
          areDownloadsRunning: downloadsRunning,
          iconWidget: getAppIcon(index, appOverride: appOverride),
          sourceHost: sourceHost,
          showAppTypeBadge: settingsProvider.showAppTypeBadge,
          showTrackedStoreBadge: settingsProvider.showTrackedStoreBadge,
          showCategoriesBadge: settingsProvider.showCategoriesBadge,
          onTap: selectedAppIds.isNotEmpty
              ? () => toggleAppSelected(app.app)
              : navigateToAppPage,
          onLongPress: () => toggleAppSelected(app.app),
          highlightTouchTargets: settingsProvider.highlightTouchTargets,
          categoryColors: settingsProvider.categories,
          itemBorderRadius: itemRadius,
        ),
      );

      // M3 Container Transform: tapping the row morphs the row's container
      // into the AppPage's container. Replaces the previous
      // `Navigator.push(heroFriendlyAppPageRoute(...))` flow plus the
      // `_heroKeepaliveAppId` keep-alive state machine - OpenContainer
      // owns the widget lifecycle during the morph, so we no longer
      // need to keep the source row alive manually.
      //
      // When [SettingsProvider.reduceVisualEffects] is on, we skip the
      // morph entirely and use a plain page-route push. The morph
      // rasterizes the source AND target during the transition (both
      // expensive) and is one of the heavier paint costs in the app -
      // dropping it gives users on weaker hardware their frame budget
      // back during navigation.
      //
      // Selection mode (`selectedAppIds.isNotEmpty`) still routes the tap
      // to [toggleAppSelected]; it never triggers navigation in that mode.
      // Long-press still toggles selection. Swipe actions on the row are
      // unaffected because they're handled inside [_SwipeableListItem].
      // The icon's own onLongPress (which opens AppPage with the opposite
      // view) still uses the standard Navigator.push - that's a secondary
      // path and doesn't benefit from container transform.
      final Widget swipeItem = isLargeScreen
          ? buildRowWith(() => setState(() => selectedAppId = appId))
          : settingsProvider.reduceVisualEffects
          ? buildRowWith(
              () => Navigator.push(
                context,
                heroFriendlyAppPageRoute(
                  (_) => AppPage(
                    appId: appId,
                    appsListHeroFolderId: widget.folderId,
                  ),
                ),
              ),
            )
          : OpenContainer(
              key: ValueKey('open-$appId'),
              closedColor: Colors.transparent,
              openColor: Theme.of(context).scaffoldBackgroundColor,
              closedElevation: 0,
              openElevation: 0,
              transitionType: ContainerTransitionType.fadeThrough,
              transitionDuration: const Duration(milliseconds: 320),
              closedShape: itemRadius != null
                  ? RoundedRectangleBorder(borderRadius: itemRadius)
                  : const RoundedRectangleBorder(),
              // We drive the open trigger from [_AppListItem.onTap] ourselves
              // so selection-mode taps stay routed to [toggleAppSelected].
              tappable: false,
              openBuilder: (BuildContext _, VoidCallback _) =>
                  AppPage(appId: appId, appsListHeroFolderId: widget.folderId),
              closedBuilder: (BuildContext _, VoidCallback openContainer) =>
                  buildRowWith(openContainer),
            );
      if (groupPosition != null) {
        return ClipRRect(
          borderRadius: m3eListGroupItemRadius(
            groupPosition,
            flatListBody: flatListBody,
            outerRadius: appsListItemOuterRadius,
            innerRadius: appsListItemInnerRadius,
          ),
          child: swipeItem,
        );
      }
      return swipeItem;
    }

    /// Ungrouped list: each app as its own M3E card; corners follow [flatListBody]
    /// rules with [first]/[middle]/[last]/[only] by index in the run.
    Widget flatListAppRow(
      int listedAppIndex,
      int indexInRun,
      int runLength, {
      bool spacerBeforeFirstRow = false,
      bool spacerAfterLastRow = false,
    }) {
      final bool gapBeforeTile = indexInRun > 0 || spacerBeforeFirstRow;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (gapBeforeTile) const SizedBox(height: kM3eItemGap),
            if (indexInRun == 0 && !spacerBeforeFirstRow)
              const SizedBox(height: 6),
            getSingleAppHorizTile(
              listedAppIndex,
              groupPosition: runLength == 1
                  ? M3eListGroupPosition.only
                  : indexInRun == 0
                  ? M3eListGroupPosition.first
                  : indexInRun == runLength - 1
                  ? M3eListGroupPosition.last
                  : M3eListGroupPosition.middle,
              flatListBody: true,
            ),
            if (indexInRun == runLength - 1) ...[
              const SizedBox(height: 6),
              if (spacerAfterLastRow) const SizedBox(height: kM3eItemGap),
            ],
          ],
        ),
      );
    }

    Widget buildCollapsibleTile({
      required String groupKey,
      required String title,
      required List<int> matchingIndices,
    }) {
      final bool isExpanded = !_collapsedGroups.contains(groupKey);
      final theme = Theme.of(context);
      return _ZOrderSliverMainAxisGroup(
        key: ValueKey(groupKey),
        // Clip the scrolling content to the pinned header's top radius, not
        // the group card radius — the header sits on top, so its corners are
        // what the content must tuck under (see field doc).
        headerTopRadius: appsListCollapsedHeaderRadius,
        slivers: [
          SliverPersistentHeader(
            key: ValueKey('${groupKey}_header'),
            pinned: true,
            delegate: _AppsGroupHeaderDelegate(
              title: title,
              count: matchingIndices.length,
              isExpanded: isExpanded,
              cardRadius: appsListGroupCardRadius,
              collapsedRadius: appsListCollapsedHeaderRadius,
              colorScheme: theme.colorScheme,
              onTap: () {
                // Expansion state lives solely in [_collapsedGroups] and is read
                // fresh on every build; toggle it via the page's own setState.
                // A per-group StatefulBuilder used to hold local isExpanded/
                // showExpandedBody state that desynced when the whole list
                // rebuilt (e.g. after a search), leaving headers stuck.
                final bool wasExpanded = !_collapsedGroups.contains(groupKey);
                setState(() {
                  if (wasExpanded) {
                    _collapsedGroups.add(groupKey);
                  } else {
                    _collapsedGroups.remove(groupKey);
                  }
                });
                _saveCollapsedGroups([groupKey], add: wasExpanded);
              },
            ),
          ),
          if (matchingIndices.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: DecoratedSliver(
                decoration: BoxDecoration(
                  color: settingsProvider.useGradientBackground
                      ? Colors.transparent
                      : m3eGroupedListBackdropFill(theme.colorScheme),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(appsListGroupCardRadius),
                  ),
                  // No group-frame border: each card already draws its own
                  // outline, and a frame at the same edge doubled it into a
                  // thick continuous rail down both sides that made the cards
                  // look connected. Dropping the frame leaves each card's own
                  // (thinner) outline, so they read as independent cards.
                ),
                sliver: _AnimatedAppsGroupBody(
                  key: ValueKey('${groupKey}_body'),
                  expanded: isExpanded,
                  itemCount: matchingIndices.length,
                  itemBuilder: (context, tileIndex) {
                    return Padding(
                      padding: EdgeInsets.only(
                        top: tileIndex == 0
                            ? kM3eHeaderToFirstCardGap
                            : kM3eItemGap,
                      ),
                      child: getSingleAppHorizTile(
                        matchingIndices[tileIndex],
                        groupPosition: matchingIndices.length == 1
                            ? M3eListGroupPosition.only
                            : tileIndex == 0
                            ? M3eListGroupPosition.first
                            : tileIndex == matchingIndices.length - 1
                            ? M3eListGroupPosition.last
                            : M3eListGroupPosition.middle,
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      );
    }

    Widget getCategoryCollapsibleTile(int index) {
      final folderPrefix = widget.folderId != null
          ? 'folder_${widget.folderId}_'
          : '';
      final catKey =
          '${folderPrefix}cat:${listedCategories[index] ?? '__null__'}';
      final String categoryMapKey = listedCategories[index] ?? '__null__';
      final matchingIndices =
          _categoryGroupListedIndices[categoryMapKey] ?? const <int>[];
      String capFirstChar(String str) =>
          str[0].toUpperCase() + str.substring(1);
      final title = capFirstChar(listedCategories[index] ?? tr('noCategory'));
      return buildCollapsibleTile(
        groupKey: catKey,
        title: title,
        matchingIndices: matchingIndices,
      );
    }

    Widget getNonInstalledCollapsibleTile() {
      final folderPrefix = widget.folderId != null
          ? 'folder_${widget.folderId}_'
          : '';
      return buildCollapsibleTile(
        groupKey: '${folderPrefix}__nonInstalled__',
        title: tr('notInstalled'),
        matchingIndices: _nonInstalledListedIndices,
      );
    }

    Widget getTrackOnlyCollapsibleTile() {
      final folderPrefix = widget.folderId != null
          ? 'folder_${widget.folderId}_'
          : '';
      return buildCollapsibleTile(
        groupKey: '${folderPrefix}__trackOnly__',
        title: tr('trackOnly'),
        matchingIndices: _trackOnlyListedIndices,
      );
    }

    Widget getSourceCollapsibleTile(int index) {
      final sourceKey = listedSources[index];
      final folderPrefix = widget.folderId != null
          ? 'folder_${widget.folderId}_'
          : '';
      final groupKey = '${folderPrefix}src:$sourceKey';
      final matchingIndices =
          _sourceGroupListedIndices[sourceKey] ?? const <int>[];

      final AppInMemory firstForTitle = matchingIndices.isEmpty
          ? listedApps.firstWhere(
              (appInMem) =>
                  sourceProvider
                      .getSourceTemplate(
                        appInMem.app.url,
                        overrideSource: appInMem.app.overrideSource,
                      )
                      .sourceIdentifier ==
                  sourceKey,
            )
          : listedApps[matchingIndices.first];
      final sourceTitle = sourceProvider
          .getSourceTemplate(
            firstForTitle.app.url,
            overrideSource: firstForTitle.app.overrideSource,
          )
          .name;

      return buildCollapsibleTile(
        groupKey: groupKey,
        title: sourceTitle,
        matchingIndices: matchingIndices,
      );
    }

    Widget getAppTypeCollapsibleTile(AppTypeGroup type) {
      final folderPrefix = widget.folderId != null
          ? 'folder_${widget.folderId}_'
          : '';
      final String groupKey = '${folderPrefix}appType:${type.name}';
      final matchingIndices = _appTypeGroupListedIndices[type] ?? const <int>[];
      final String title = switch (type) {
        AppTypeGroup.user => tr('appTypeUser'),
        AppTypeGroup.system => tr('appTypeSystem'),
        AppTypeGroup.privileged => tr('appTypePrivileged'),
      };
      return buildCollapsibleTile(
        groupKey: groupKey,
        title: title,
        matchingIndices: matchingIndices,
      );
    }

    Widget getUpdatesCollapsibleTile() {
      final folderPrefix = widget.folderId != null
          ? 'folder_${widget.folderId}_'
          : '';
      return buildCollapsibleTile(
        groupKey: '${folderPrefix}__updates__',
        title: tr('updatesGroup'),
        matchingIndices: _updatesGroupListedIndices,
      );
    }

    Null Function()? getMassObtainFunction() {
      return appsProvider.areDownloadsRunning() ||
              (existingUpdateIdsAllOrSelected.isEmpty &&
                  newInstallIdsAllOrSelected.isEmpty &&
                  trackOnlyUpdateIdsAllOrSelected.isEmpty)
          ? null
          : () {
              hapticHeavyImpact();
              showBulkUpdatePickerSheet(
                context: context,
                apps: appsProvider.apps,
                existingUpdateIds: existingUpdateIdsAllOrSelected,
                newInstallIds: newInstallIdsAllOrSelected,
                trackOnlyUpdateIds: trackOnlyUpdateIdsAllOrSelected,
                initialSelectedIds: selectedAppIds.isNotEmpty
                    ? selectedAppIds
                    : null,
              ).then((Set<String>? selectedIds) {
                if (selectedIds == null || selectedIds.isEmpty) return;
                unawaited(
                  appsProvider
                      .downloadAndInstallLatestApps(
                        selectedIds.toList(),
                        globalNavigatorKey.currentContext,
                      )
                      .catchError((e) {
                        if (!context.mounted) return <String>[];
                        showError(e);
                        return <String>[];
                      })
                      .then((value) {
                        if (value.isNotEmpty) {
                          if (!context.mounted) return;
                          showMessage(tr('appsUpdated'));
                        }
                      }),
                );
              });
            };
    }

    Future<Null> Function() launchCategorizeDialog([
      Iterable<App>? targetApps,
    ]) {
      return () async {
        try {
          final appsToCategorize = (targetApps ?? getSelectedApps()).toList();
          await showAppModalSheet<void>(
            context: context,
            builder: (BuildContext sheetContext) {
              return BulkCategoryEditorSheet(
                availableCategoryColors: settingsProvider.categories,
                selectedAppCategories: appsToCategorize
                    .map((app) => app.categories.toList())
                    .toList(),
                onApply: (actions) {
                  final nextCategoryColors = Map<String, int>.from(
                    settingsProvider.categories,
                  )..addAll(actions.newCategoryColors);
                  if (actions.newCategoryColors.isNotEmpty) {
                    settingsProvider.setCategories(nextCategoryColors);
                  }
                  final updatedCategoryLists =
                      applyBulkCategoryActionsToCategoryLists(
                        appsToCategorize.map((app) => app.categories),
                        actions,
                      );
                  var index = 0;
                  appsProvider.saveApps(
                    appsToCategorize
                        .map(
                          (app) => app.copyWith(
                            categories: updatedCategoryLists[index++],
                          ),
                        )
                        .toList(),
                    updateInstalledInfo: false,
                  );
                },
              );
            },
          );
        } catch (err) {
          if (!context.mounted) return;
          showError(err);
        }
      };
    }

    Future<dynamic> showMassMarkDialog([Iterable<App>? targetApps]) {
      final appsToMark = (targetApps ?? getSelectedApps()).toList();
      return showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: Text(
              tr(
                'markXSelectedAppsAsUpdated',
                args: [appsToMark.length.toString()],
              ),
            ),
            contentPadding: appDialogContentPadding,
            content: Text(
              tr('onlyWorksWithNonVersionDetectApps'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(tr('no')),
              ),
              TextButton(
                onPressed: () {
                  hapticSelection();
                  appsProvider.saveApps(
                    appsToMark.map((a) {
                      if (a.installedVersion != null &&
                          !appsProvider.isVersionDetectionPossible(
                            appsProvider.apps[a.id],
                          )) {
                        return a.copyWith(installedVersion: a.latestVersion);
                      }
                      return a;
                    }).toList(),
                    attemptToCorrectInstallStatus: false,
                    updateInstalledInfo: false,
                  );

                  Navigator.of(context).pop();
                },
                child: Text(tr('yes')),
              ),
            ],
          );
        },
      );
    }

    void pinSelectedApps([Iterable<App>? targetApps]) {
      final appsToPin = targetApps ?? getSelectedApps();
      final pinStatus = appsToPin.where((element) => element.pinned).isEmpty;
      appsProvider.saveApps(
        appsToPin.map((e) => e.copyWith(pinned: pinStatus)).toList(),
        updateInstalledInfo: false,
      );
    }

    // Shared bulk-action bodies, used by both the phone "more options" sheet
    // and the large-screen action pane. They intentionally do not dismiss any
    // surface - the phone sheet pops at its own call sites; the pane stays.
    void downloadSelectedAppAssets([Iterable<App>? targetApps]) {
      final appsToDownload = targetApps ?? getSelectedApps();
      appsProvider
          .downloadAppAssets(appsToDownload.map((e) => e.id).toList())
          .catchError((e) {
            showError(e);
            return <String>[];
          });
    }

    void shareSelectedAppUrls([Iterable<App>? targetApps]) {
      final appsToShare = targetApps ?? getSelectedApps();
      String urls = '';
      for (var a in appsToShare) {
        urls += '${a.url}\n';
      }
      if (urls.isNotEmpty) {
        urls = urls.substring(0, urls.length - 1);
      }
      SharePlus.instance.share(
        ShareParams(text: urls, subject: 'ObtainX - ${tr('appsString')}'),
      );
    }

    void shareSelectedAppConfigLinks([Iterable<App>? targetApps]) {
      final appsToShare = targetApps ?? getSelectedApps();
      String urls = '';
      for (var a in appsToShare) {
        urls +=
            'https://apps.obtainium.imranr.dev/redirect?r=obtainium://app/${Uri.encodeComponent(jsonEncode({'id': a.id, 'url': a.url, 'author': a.author, 'name': a.name, 'preferredApkIndex': a.preferredApkIndex, 'additionalSettings': jsonEncode(a.additionalSettings), 'overrideSource': a.overrideSource}))}\n\n';
      }
      SharePlus.instance.share(
        ShareParams(text: urls, subject: 'ObtainX - ${tr('appsString')}'),
      );
    }

    void exportSelectedApps([Iterable<App>? targetApps]) {
      final appsToExport = (targetApps ?? getSelectedApps()).toList();
      const encoder = JsonEncoder.withIndent('    ');
      final exportJSON = encoder.convert(
        appsProvider.generateExportJSON(
          appIds: appsToExport.map((e) => e.id).toList(),
          overrideExportSettings: 0,
        ),
      );
      final String fn =
          '${tr('obtainiumExportHyphenatedLowercase')}-${DateTime.now().toIso8601String().replaceAll(':', '-')}-count-${appsToExport.length}';
      final XFile f = XFile.fromData(
        Uint8List.fromList(utf8.encode(exportJSON)),
        mimeType: 'application/json',
        name: fn,
      );
      SharePlus.instance.share(
        ShareParams(files: [f], fileNameOverrides: ['$fn.json']),
      );
    }

    void showCombinedSelectionActionsSheet() {
      final ColorScheme scheme = Theme.of(context).colorScheme;

      showAppModalSheet<void>(
        context: context,
        builder: (sheetCtx) {
          return StatefulBuilder(
            builder: (sheetCtx, setSheetState) {
              final Set<App> currentSelectedApps = getSelectedApps();
              final bool selectedAppsArePinned = currentSelectedApps.any(
                (selectedApp) => selectedApp.pinned,
              );

              return AppSheetContent(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  // Header: Selection count & Select All / Deselect All
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr(
                              'selectedX',
                              args: [selectedAppIds.length.toString()],
                            ),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: listedApps.isEmpty
                              ? null
                              : () {
                                  setState(() {
                                    for (final appInMem in listedApps) {
                                      selectedAppIds.add(appInMem.app.id);
                                    }
                                  });
                                  _notifyHomeFabChromeIfChanged();
                                  setSheetState(() {});
                                },
                          icon: const Icon(Icons.select_all_outlined, size: 18),
                          label: Text(tr('selectAll')),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              selectedAppIds.clear();
                            });
                            _notifyHomeFabChromeIfChanged();
                            Navigator.of(sheetCtx).pop();
                          },
                          tooltip: tr('deselectAll'),
                          icon: const Icon(Icons.deselect, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 8),

                  // Install / Update Selected
                  if (getMassObtainFunction() != null)
                    ActionListTile(
                      icon: Icons.file_download_outlined,
                      label: tr('installUpdateSelectedApps'),
                      onTap: () {
                        getMassObtainFunction()?.call();
                      },
                      autoPop: true,
                    ),
                  // Categorize
                  ActionListTile(
                    icon: Icons.category_outlined,
                    label: tr('categorize'),
                    onTap: launchCategorizeDialog(currentSelectedApps),
                    autoPop: true,
                  ),
                  // Add to Folder
                  ActionListTile(
                    icon: Icons.folder_copy_outlined,
                    label: tr('addToFolder'),
                    onTap: () =>
                        _showFolderAssignDialog(context, currentSelectedApps),
                    autoPop: true,
                  ),
                  // Pin / Unpin
                  ActionListTile(
                    icon: selectedAppsArePinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    label: selectedAppsArePinned
                        ? tr('unpinFromTop')
                        : tr('pinToTop'),
                    onTap: () => pinSelectedApps(currentSelectedApps),
                    autoPop: true,
                  ),
                  // Share URLs
                  ActionListTile(
                    icon: Icons.share_outlined,
                    label: tr('shareSelectedAppURLs'),
                    onTap: () => shareSelectedAppUrls(currentSelectedApps),
                    autoPop: true,
                  ),
                  // Share Config Links
                  ActionListTile(
                    icon: Icons.link_outlined,
                    label: tr('shareAppConfigLinks'),
                    onTap: selectedAppIds.isEmpty
                        ? null
                        : () =>
                              shareSelectedAppConfigLinks(currentSelectedApps),
                    autoPop: true,
                  ),
                  // Export JSON
                  ActionListTile(
                    icon: Icons.file_download_outlined,
                    label: '${tr('share')} - ${tr('obtainiumExport')}',
                    onTap: selectedAppIds.isEmpty
                        ? null
                        : () => exportSelectedApps(currentSelectedApps),
                    autoPop: true,
                  ),
                  // Download Release Assets
                  ActionListTile(
                    icon: Icons.download_outlined,
                    label: tr(
                      'downloadX',
                      args: [lowerCaseIfEnglish(tr('releaseAsset'))],
                    ),
                    onTap: () => downloadSelectedAppAssets(currentSelectedApps),
                    autoPop: true,
                  ),
                  // Mark as Updated
                  ActionListTile(
                    icon: Icons.done_all,
                    label: tr('markSelectedAppsUpdated'),
                    onTap: appsProvider.areDownloadsRunning()
                        ? null
                        : () => showMassMarkDialog(currentSelectedApps),
                    autoPop: true,
                  ),
                  const Divider(height: 16),
                  // Remove Selected Apps
                  ActionListTile(
                    icon: Icons.delete_outline_outlined,
                    label: tr('removeSelectedApps'),
                    iconColor: scheme.error,
                    textColor: scheme.error,
                    onTap: () async {
                      final appsProviderRef = appsProvider;
                      final messenger = scaffoldMessengerKey.currentState;
                      final RemoveAppsWithModalResult removeResult =
                          await appsProviderRef.removeAppsWithModal(
                            context,
                            currentSelectedApps.toList(),
                          );
                      if (removeResult.shouldShowSnackBar) {
                        final Set<String> undoAppIds =
                            removeResult.deferredUndoAppIds;
                        final int removedCount =
                            removeResult.deferredUndoAppIds.isNotEmpty
                            ? removeResult.deferredUndoAppIds.length
                            : currentSelectedApps.length;
                        messenger
                          ?..clearSnackBars()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                tr('xAppsRemoved', args: ['$removedCount']),
                              ),
                              persist: false,
                              duration: const Duration(seconds: 5),
                              behavior: SnackBarBehavior.floating,
                              action: undoAppIds.isNotEmpty
                                  ? SnackBarAction(
                                      label: tr('undo'),
                                      onPressed: () => appsProviderRef
                                          .undoDeferredObtainiumRemovals(
                                            undoAppIds,
                                          ),
                                    )
                                  : null,
                            ),
                          );
                      }
                    },
                    autoPop: true,
                  ),
                ],
              );
            },
          );
        },
      );
    }

    runMassObtainHandler = getMassObtainFunction();
    openSelectionActionsSheetHandler = showCombinedSelectionActionsSheet;

    _notifyHomeFabChromeIfChanged();

    // ── Filter bottom sheet ──────────────────────────────────────────────────
    // Shows all filter/search options in a modal bottom sheet.
    // Changes to text fields, toggles, and the dropdown are applied live; the
    // sheet is dismissed by dragging down or tapping outside.
    void showFilterSheet() {
      showAppModalSheet<void>(
        context: context,
        builder: (sheetCtx) {
          return StatefulBuilder(
            builder: (sheetCtx, setSheetState) {
              // Call both parent and sheet setState when the filter changes.
              void update(VoidCallback fn) {
                fn();
                setState(() {});
                setSheetState(() {});
              }

              // ── Source items ──────────────────────────────────────────────
              final sourceItems = [
                MapEntry('', tr('sourceAny')),
                ...sourceProvider.sourceTemplates.map(
                  (e) => MapEntry(e.sourceIdentifier, e.name),
                ),
              ];

              return AppSheetContent(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                children: [
                  // Title row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr('filterApps'),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            update(() {
                              filter = AppsFilter();
                              _searchController.clear();
                            });
                            Navigator.of(sheetCtx).pop();
                          },
                          child: Text(tr('remove')),
                        ),
                      ],
                    ),
                  ),

                  // ── Text filters ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Column(
                      children: [
                        TextFormField(
                          initialValue: filter.nameFilter,
                          textInputAction: TextInputAction.next,
                          decoration:
                              appPageOutlinedInputDecoration(
                                sheetCtx,
                                labelText: tr('appName'),
                                isDense: true,
                              ).copyWith(
                                prefixIcon: const Icon(Icons.search_rounded),
                              ),
                          onChanged: (value) {
                            update(() {
                              filter.nameFilter = value;
                              if (_searchController.text != value) {
                                _searchController.text = value;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: filter.authorFilter,
                          textInputAction: TextInputAction.done,
                          decoration:
                              appPageOutlinedInputDecoration(
                                sheetCtx,
                                labelText: tr('author'),
                                isDense: true,
                              ).copyWith(
                                prefixIcon: const Icon(Icons.search_rounded),
                              ),
                          onChanged: (value) {
                            update(() => filter.authorFilter = value);
                          },
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),
                  const SizedBox(height: 8),

                  // ── Source dropdown ───────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: appDropdownField<String>(
                      key: ValueKey(filter.sourceFilter),
                      context: context,
                      value: filter.sourceFilter,
                      labelText: tr('appSource'),
                      menuWidth: appDropdownMenuWidth(
                        context,
                        sourceItems.map((sourceItem) => sourceItem.value),
                      ),
                      items: sourceItems
                          .map(
                            (sourceItem) => DropdownMenuItem(
                              value: sourceItem.key,
                              child: Text(sourceItem.value),
                            ),
                          )
                          .toList(),
                      onChanged: (newValue) {
                        update(() => filter.sourceFilter = newValue ?? '');
                      },
                    ),
                  ),

                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),

                  // ── Visibility filters ──────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr('visibilityFilterCycleHint'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 8),
                        CategoryActionChipGroup(
                          children: [
                            _TriStateCategoryFilterChip(
                              category: tr('visibilityFilterUpToDate'),
                              color: Theme.of(context).colorScheme.primary,
                              intent: filter.upToDateFilterIntent,
                              onCycle: () => update(
                                () => filter.upToDateFilterIntent =
                                    nextCategoryFilterIntent(
                                      filter.upToDateFilterIntent,
                                    ),
                              ),
                              onClear:
                                  filter.upToDateFilterIntent ==
                                      CategoryFilterIntent.neutral
                                  ? null
                                  : () => update(
                                      () => filter.upToDateFilterIntent =
                                          CategoryFilterIntent.neutral,
                                    ),
                            ),
                            _TriStateCategoryFilterChip(
                              category: tr('visibilityFilterInstalled'),
                              color: Theme.of(context).colorScheme.primary,
                              intent: filter.installedFilterIntent,
                              onCycle: () => update(
                                () => filter.installedFilterIntent =
                                    nextCategoryFilterIntent(
                                      filter.installedFilterIntent,
                                    ),
                              ),
                              onClear:
                                  filter.installedFilterIntent ==
                                      CategoryFilterIntent.neutral
                                  ? null
                                  : () => update(
                                      () => filter.installedFilterIntent =
                                          CategoryFilterIntent.neutral,
                                    ),
                            ),
                            _TriStateCategoryFilterChip(
                              category: tr('trackOnly'),
                              color: Theme.of(context).colorScheme.primary,
                              intent: filter.trackOnlyFilterIntent,
                              onCycle: () => update(
                                () => filter.trackOnlyFilterIntent =
                                    nextCategoryFilterIntent(
                                      filter.trackOnlyFilterIntent,
                                    ),
                              ),
                              onClear:
                                  filter.trackOnlyFilterIntent ==
                                      CategoryFilterIntent.neutral
                                  ? null
                                  : () => update(
                                      () => filter.trackOnlyFilterIntent =
                                          CategoryFilterIntent.neutral,
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ── Category selector ─────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: _TriStateCategoryFilterSelector(
                      categoryColors: settingsProvider.categories,
                      includedCategories: filter.includedCategoryFilter,
                      excludedCategories: filter.excludedCategoryFilter,
                      matchMode: filter.categoryMatchMode,
                      onChanged: (included, excluded) {
                        update(() {
                          filter.includedCategoryFilter = included;
                          filter.excludedCategoryFilter = excluded;
                        });
                      },
                      onMatchModeChanged: (matchMode) {
                        update(() {
                          filter.categoryMatchMode = matchMode;
                        });
                      },
                    ),
                  ),

                  // ── Save as Folder ────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: _SaveAsFolderRow(
                      onSave: (name) {
                        Navigator.of(sheetCtx).pop();
                        // Defer creation until the sheet is fully torn down so
                        // the provider mutations don't race its disposal.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          unawaited(
                            _createFolderFromCurrentFilter(filter, name),
                          );
                        });
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    List<Widget> getDisplayedList() {
      final groupBy = effectiveGroupBy;
      final pinUpdatesEnabled = _effectivePinUpdates(settingsProvider);

      // Builds a list of slivers where the optional updates group is prepended
      // (pinUpdatesEnabled=true) or appended (false) to the list of main groups.
      List<Widget> buildGroupedSliverList({
        required int mainChildCount,
        required Widget Function(int index) mainBuilder,
      }) {
        final List<Widget> list = [];
        // Updates group pinned to top.
        if (showUpdatesGroupSection && pinUpdatesEnabled) {
          list.add(getUpdatesCollapsibleTile());
        }
        // Main groups.
        for (int i = 0; i < mainChildCount; i++) {
          list.add(mainBuilder(i));
        }
        // Non-installed group.
        if (showNonInstalledGroupSection) {
          list.add(getNonInstalledCollapsibleTile());
        }
        // Track-only group.
        if (showTrackOnlyGroupSection) {
          list.add(getTrackOnlyCollapsibleTile());
        }
        // Updates group at bottom (when not pinned).
        if (showUpdatesGroupSection && !pinUpdatesEnabled) {
          list.add(getUpdatesCollapsibleTile());
        }
        return list;
      }

      final useCategoryGroups =
          groupBy == AppsListGroupBy.category &&
          ((segregateNonInstalled || segregateTrackOnly)
              ? (listedCategories.isNotEmpty ||
                    showNonInstalledGroupSection ||
                    showTrackOnlyGroupSection)
              : !(listedCategories.isEmpty ||
                    (listedCategories.length == 1 &&
                        listedCategories[0] == null)));
      if (useCategoryGroups) {
        return buildGroupedSliverList(
          mainChildCount: listedCategories.length,
          mainBuilder: (i) => getCategoryCollapsibleTile(i),
        );
      }

      final useSourceGroups =
          groupBy == AppsListGroupBy.source &&
          (listedSources.isNotEmpty ||
              showNonInstalledGroupSection ||
              showTrackOnlyGroupSection);
      if (useSourceGroups) {
        return buildGroupedSliverList(
          mainChildCount: listedSources.length,
          mainBuilder: (i) => getSourceCollapsibleTile(i),
        );
      }

      final useAppTypeGroups =
          groupBy == AppsListGroupBy.appType &&
          (listedAppTypes.isNotEmpty ||
              showNonInstalledGroupSection ||
              showTrackOnlyGroupSection);
      if (useAppTypeGroups) {
        return buildGroupedSliverList(
          mainChildCount: listedAppTypes.length,
          mainBuilder: (i) => getAppTypeCollapsibleTile(listedAppTypes[i]),
        );
      }

      // Flat list — still supports the updates group.
      if (showUpdatesGroupSection) {
        // Non-updates app indices (already in _listedAppsCache order, minus those in updates).
        final nonUpdatesIndices = [
          for (int i = 0; i < listedApps.length; i++)
            if (!isInUpdatesGroup(listedApps[i])) i,
        ];
        final flatSliverList = SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            return flatListAppRow(
              nonUpdatesIndices[index],
              index,
              nonUpdatesIndices.length,
              spacerBeforeFirstRow: pinUpdatesEnabled && index == 0,
              spacerAfterLastRow:
                  !pinUpdatesEnabled && index == nonUpdatesIndices.length - 1,
            );
          }, childCount: nonUpdatesIndices.length),
        );

        if (pinUpdatesEnabled) {
          return [getUpdatesCollapsibleTile(), flatSliverList];
        } else {
          return [flatSliverList, getUpdatesCollapsibleTile()];
        }
      }

      return [
        SliverList(
          delegate: SliverChildBuilderDelegate((
            BuildContext context,
            int index,
          ) {
            return flatListAppRow(index, index, listedApps.length);
          }, childCount: listedApps.length),
        ),
      ];
    }

    // One cross-folder search result, styled as a flat-list M3E card (same
    // look as [flatListAppRow]) but driven by an explicit app rather than an
    // index into [listedApps].
    Widget crossFolderAppRow(AppInMemory app, int indexInRun, int runLength) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (indexInRun > 0) const SizedBox(height: kM3eItemGap),
            if (indexInRun == 0) const SizedBox(height: 6),
            getSingleAppHorizTile(
              -1,
              appOverride: app,
              flatListBody: true,
              groupPosition: runLength == 1
                  ? M3eListGroupPosition.only
                  : indexInRun == 0
                  ? M3eListGroupPosition.first
                  : indexInRun == runLength - 1
                  ? M3eListGroupPosition.last
                  : M3eListGroupPosition.middle,
            ),
            if (indexInRun == runLength - 1) const SizedBox(height: 6),
          ],
        ),
      );
    }

    // The "Found in your folders" section: a labelled divider, then one
    // tappable folder sub-header + its matching rows per folder. Empty unless
    // [_crossFolderMatchesCache] was populated (main page + active text search).
    List<Widget> getCrossFolderMatchesSlivers() {
      final matches = _crossFolderMatchesCache;
      if (matches.isEmpty) return const [];
      final ThemeData theme = Theme.of(context);
      final slivers = <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Divider(color: theme.colorScheme.outlineVariant),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    tr('appsInFoldersHeader'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(color: theme.colorScheme.outlineVariant),
                ),
              ],
            ),
          ),
        ),
      ];
      for (final group in matches) {
        // A null folderId is the On-Demand Only bucket; anything else is a
        // real folder. Each opens its own page.
        final bool isOnDemand = group.folderId == null;
        final String label = isOnDemand ? tr('onDemandOnly') : group.folderName;
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.push(
                    context,
                    slideUpPageRoute(
                      (_) => isOnDemand
                          ? const AppsPage(onDemandOnlyList: true)
                          : AppsPage(folderId: group.folderId),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOnDemand
                            ? Icons.folder_special_outlined
                            : Icons.folder_outlined,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$label (${group.apps.length})',
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final apps = group.apps;
        slivers.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => crossFolderAppRow(apps[i], i, apps.length),
              childCount: apps.length,
            ),
          ),
        );
      }
      return slivers;
    }

    // Back intercept priority:
    // 1. Multi-select active → deselect all
    // 2. Search expanded → collapse search bar
    // 3. Filter active → reset filter
    // 4. Otherwise → normal pop (exit / go up)
    final bool isFilterActive = !filter.isIdenticalTo(
      neutralFilter,
      settingsProvider,
    );
    final bool shouldInterceptBack =
        selectedAppIds.isNotEmpty || _searchExpanded || isFilterActive;

    final PreferredSizeWidget? filterChipsBar = _buildFilterChipsRow(
      showFilterSheet,
    );

    return PopScope(
      canPop: !shouldInterceptBack,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (selectedAppIds.isNotEmpty) {
          clearSelected();
        } else if (_searchExpanded) {
          setState(() {
            _searchExpanded = false;
            _searchController.clear();
            _searchFocusNode.unfocus();
          });
        } else if (isFilterActive) {
          setState(() {
            filter = AppsFilter();
            _searchController.clear();
          });
        }
      },
      child: () {
        final Widget listScaffold = Scaffold(
          // Don't let the keyboard resize the body. A resize repaints the scene
          // on every frame of the keyboard's slide animation, which forces the
          // app bar's progressive blur (a BackdropFilter) to re-rasterize each
          // frame — the keyboard-slide stutter. The search field is in the app
          // bar, so it stays visible; the list just sits under the keyboard.
          resizeToAvoidBottomInset: false,
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                // [ExpressiveRefreshIndicator] is a drop-in replacement for the
                // stock [RefreshIndicator] - same API surface (child, onRefresh,
                // displacement, color, etc.) - but renders the M3 Expressive
                // morphing-polygon loading shape instead of the legacy circular
                // spinner. From package: expressive_refresh.
                child: ExpressiveRefreshIndicator(
                  key: _refreshIndicatorKey,
                  onRefresh: refresh,
                  child: _ConditionalScrollbar(
                    condition: !isLargeScreen,
                    controller: scrollController,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (settingsProvider.useGradientBackground)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: Theme.of(
                                  context,
                                ).colorScheme.schemePageBackgroundGradient,
                              ),
                            ),
                          ),
                        CustomScrollView(
                          scrollCacheExtent: const ScrollCacheExtent.pixels(
                            1800,
                          ),
                          key: PageStorageKey<String>(
                            'apps-scroll-${widget.folderId ?? (widget.onDemandOnlyList ? 'on-demand' : 'main')}',
                          ),
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: ClampingScrollPhysics(),
                          ),
                          controller: scrollController,
                          slivers: <Widget>[
                            CustomAppBar(
                              leading:
                                  (widget.onDemandOnlyList ||
                                      widget.folderId != null)
                                  ? IconButton(
                                      icon: const Icon(Icons.arrow_back),
                                      onPressed: () =>
                                          Navigator.of(context).maybePop(),
                                      tooltip: MaterialLocalizations.of(
                                        context,
                                      ).backButtonTooltip,
                                    )
                                  : null,
                              title: _searchExpanded
                                  ? ''
                                  : (widget.onDemandOnlyList
                                        ? tr('onDemandOnlyAppsTitle')
                                        : currentFolderName ??
                                              tr('appsString')),
                              matchGradientBackground:
                                  settingsProvider.useGradientBackground,
                              progressiveBlurOverlayColor: isLargeScreen
                                  ? Theme.of(context).colorScheme.surface
                                        .withValues(alpha: 0.72)
                                  : null,
                              actions: [
                                if (!_searchExpanded)
                                  IconButton(
                                    icon: const Icon(Icons.search),
                                    onPressed: () {
                                      setState(() => _searchExpanded = true);
                                      _searchFocusNode.requestFocus();
                                    },
                                  ),
                                if (effectiveGroupBy != AppsListGroupBy.none ||
                                    showUpdatesGroupSection) ...[
                                  IconButton(
                                    icon: Icon(
                                      allGroupsExpanded
                                          ? Icons.unfold_less_rounded
                                          : Icons.unfold_more_rounded,
                                    ),
                                    tooltip: allGroupsExpanded
                                        ? tr('collapseAll')
                                        : tr('expandAll'),
                                    onPressed: () {
                                      setState(() {
                                        if (allGroupsExpanded) {
                                          _collapsedGroups.addAll(
                                            activeGroupKeys,
                                          );
                                        } else {
                                          _collapsedGroups.removeAll(
                                            activeGroupKeys,
                                          );
                                        }
                                      });
                                      // Persist the bulk toggle so it survives a
                                      // restart, matching the per-group header tap.
                                      _saveCollapsedGroups(
                                        activeGroupKeys,
                                        add: allGroupsExpanded,
                                      );
                                    },
                                  ),
                                ],
                              ],
                              // Always use the compact layout so the action icon
                              // and "Apps" title are always on the same toolbar row.
                              searchWidget: _searchExpanded
                                  ? _buildSearchBar(
                                      colorScheme: Theme.of(
                                        context,
                                      ).colorScheme,
                                      showFilterSheet: showFilterSheet,
                                      neutralFilter: neutralFilter,
                                      settingsProvider: settingsProvider,
                                      focusNode: _searchFocusNode,
                                    )
                                  : const SizedBox.shrink(),
                              bottom: filterChipsBar,
                            ),
                            ...getLoadingWidgets(),
                            ...getDisplayedList(),
                            ...getCrossFolderMatchesSlivers(),
                            if (!widget.onDemandOnlyList &&
                                widget.folderId == null)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    bottom:
                                        MediaQuery.paddingOf(context).bottom +
                                        (!isLargeScreen
                                            ? 80.0
                                            : ((showSplitPaneListFabs ||
                                                      showFolderListFabs)
                                                  ? 52.0
                                                  : 0.0)),
                                  ),
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        20,
                                        16,
                                        0,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          // Manage Folders button — hidden on the
                                          // empty first-run page; nothing to
                                          // organize into folders yet.
                                          if (appsProvider.apps.isNotEmpty ||
                                              appFolders.isNotEmpty)
                                            TextButton.icon(
                                              onPressed: () {
                                                unawaited(
                                                  _showFolderManageSheet(
                                                    context,
                                                  ),
                                                );
                                              },
                                              icon: const Icon(
                                                Icons.folder_copy_outlined,
                                                size: 18,
                                              ),
                                              label: Text(tr('manageFolders')),
                                            ),
                                          // User-defined folder buttons
                                          if (appFolders.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            ...appFolders.map(
                                              (folder) => Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 8,
                                                ),
                                                child: FilledButton.icon(
                                                  onPressed: () {
                                                    Navigator.push(
                                                      context,
                                                      slideUpPageRoute(
                                                        (_) => AppsPage(
                                                          folderId: folder.id,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  icon: () {
                                                    final int upd =
                                                        folderUpdateCounts[folder
                                                            .id] ??
                                                        0;
                                                    if (upd > 0) {
                                                      return Stack(
                                                        clipBehavior: Clip.none,
                                                        alignment:
                                                            AlignmentDirectional
                                                                .centerStart,
                                                        children: [
                                                          const Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              SizedBox(
                                                                width: 4,
                                                                height: 16,
                                                              ),
                                                              SizedBox(
                                                                width: 6,
                                                              ),
                                                              Icon(
                                                                Icons
                                                                    .folder_outlined,
                                                              ),
                                                            ],
                                                          ),
                                                          Badge(
                                                            label: Text('$upd'),
                                                            child:
                                                                const SizedBox(
                                                                  width: 4,
                                                                  height: 16,
                                                                ),
                                                          ),
                                                        ],
                                                      );
                                                    }
                                                    return const Icon(
                                                      Icons.folder_outlined,
                                                    );
                                                  }(),
                                                  label: Text(
                                                    '${folder.name} '
                                                    '(${folderAppCounts[folder.id] ?? 0})',
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                          ],
                                          // On-Demand Only button (always last) —
                                          // only when it actually holds apps.
                                          if (onDemandOnlyAppCount > 0)
                                            FilledButton.icon(
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  slideUpPageRoute(
                                                    (_) => const AppsPage(
                                                      onDemandOnlyList: true,
                                                    ),
                                                  ),
                                                );
                                              },
                                              icon: const Icon(
                                                Icons.folder_special_outlined,
                                              ),
                                              label: Text(
                                                '${tr('onDemandOnly')} '
                                                '($onDemandOnlyAppCount)',
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (widget.onDemandOnlyList ||
                                widget.folderId != null)
                              SliverToBoxAdapter(
                                child: SizedBox(
                                  height:
                                      MediaQuery.paddingOf(context).bottom +
                                      (!isLargeScreen
                                          ? 80.0
                                          : ((showSplitPaneListFabs ||
                                                    showFolderListFabs)
                                                ? 52.0
                                                : 0.0)),
                                ),
                              ),
                          ],
                        ),
                        if (!isLargeScreen &&
                            (widget.folderId != null ||
                                widget.onDemandOnlyList))
                          _buildAppsPageSideFabOverlay(
                            context,
                            heroScope: widget.folderId ?? 'ondemand',
                          ),
                        if (showSplitPaneListFabs)
                          _buildAppsPageSideFabOverlay(
                            context,
                            heroScope: 'main_split',
                          ),
                        if (showFolderListFabs)
                          _buildAppsPageSideFabOverlay(
                            context,
                            heroScope: widget.folderId ?? 'ondemand',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        if (isLargeScreen) {
          // Full-bleed page background behind both panes - prevents the master
          // pane's app-bar progressive-blur BackdropFilter from sampling
          // transparent-black at the seam (the detail pane paints after the
          // master in this Row, so that strip is empty when the blur
          // rasterizes), which produced the two-panel "dark smudge" at the
          // right end of the master title bar. See settings.dart and
          // custom_app_bar.dart's _buildBlur.
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: settingsProvider.useGradientBackground
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: Theme.of(
                            context,
                          ).colorScheme.schemePageBackgroundGradient,
                        ),
                      )
                    : ColoredBox(color: Theme.of(context).colorScheme.surface),
              ),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        scrollbarTheme: const ScrollbarThemeData(
                          thumbColor: WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                          trackColor: WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                          trackBorderColor: WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                          minThumbLength: 0,
                        ),
                      ),
                      child: listScaffold,
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withAlpha(50),
                  ),
                  Expanded(
                    flex: 4,
                    child: selectedAppIds.isNotEmpty
                        ? Builder(
                            builder: (BuildContext context) {
                              final ColorScheme scheme = Theme.of(
                                context,
                              ).colorScheme;
                              final destructiveButtonStyle =
                                  FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(56),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    backgroundColor: scheme.errorContainer,
                                    foregroundColor: scheme.onErrorContainer,
                                    elevation: 0,
                                    // Match the ActionListTile rows above:
                                    // bodyLarge (16sp) label + 24dp icon, so the
                                    // Remove action isn't visually smaller.
                                    textStyle: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                    alignment: Alignment.centerLeft,
                                  );
                              return Scaffold(
                                backgroundColor:
                                    settingsProvider.useGradientBackground
                                    ? Colors.transparent
                                    : scheme.surface,
                                body: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (settingsProvider.useGradientBackground)
                                      Positioned.fill(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: scheme
                                                .schemePageBackgroundGradient,
                                          ),
                                        ),
                                      ),
                                    CustomScrollView(
                                      slivers: [
                                        CustomAppBar(
                                          title: tr(
                                            'selectedX',
                                            args: [
                                              selectedAppIds.length.toString(),
                                            ],
                                          ),
                                          matchGradientBackground:
                                              settingsProvider
                                                  .useGradientBackground,
                                        ),
                                        SliverSafeArea(
                                          top: false,
                                          bottom: true,
                                          sliver: SliverPadding(
                                            padding: const EdgeInsets.all(24),
                                            sliver: SliverToBoxAdapter(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  // Select-all / deselect-all as
                                                  // a connected M3E segmented
                                                  // control, driven in action
                                                  // mode: the selection is never
                                                  // persisted (always empty), so
                                                  // each tap simply fires its
                                                  // action.
                                                  AppSegmentedButton<bool>(
                                                    selected: const <bool>{},
                                                    emptySelectionAllowed: true,
                                                    onSelectionChanged:
                                                        (Set<bool> values) {
                                                          final bool selectAll =
                                                              values.contains(
                                                                true,
                                                              );
                                                          setState(() {
                                                            if (selectAll) {
                                                              for (final appInMem
                                                                  in listedApps) {
                                                                selectedAppIds
                                                                    .add(
                                                                      appInMem
                                                                          .app
                                                                          .id,
                                                                    );
                                                              }
                                                            } else {
                                                              selectedAppIds
                                                                  .clear();
                                                            }
                                                          });
                                                        },
                                                    segments: [
                                                      ButtonSegment<bool>(
                                                        value: true,
                                                        enabled: listedApps
                                                            .isNotEmpty,
                                                        icon: const Icon(
                                                          Icons
                                                              .select_all_outlined,
                                                        ),
                                                        label: Text(
                                                          tr('selectAll'),
                                                        ),
                                                      ),
                                                      ButtonSegment<bool>(
                                                        value: false,
                                                        icon: const Icon(
                                                          Icons.deselect,
                                                        ),
                                                        label: Text(
                                                          tr('deselectAll'),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  FilledButton.icon(
                                                    style: FilledButton.styleFrom(
                                                      minimumSize:
                                                          const Size.fromHeight(
                                                            56,
                                                          ),
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 24,
                                                            vertical: 16,
                                                          ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              16,
                                                            ),
                                                      ),
                                                      alignment:
                                                          Alignment.centerLeft,
                                                    ),
                                                    onPressed:
                                                        getMassObtainFunction(),
                                                    icon: const Icon(
                                                      Icons
                                                          .file_download_outlined,
                                                    ),
                                                    label: Text(
                                                      tr(
                                                        'installUpdateSelectedApps',
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  M3eExpressiveSettingsCard(
                                                    colorScheme: scheme,
                                                    items: [
                                                      ActionListTile(
                                                        iconColor:
                                                            appsProvider
                                                                .areDownloadsRunning()
                                                            ? null
                                                            : scheme.primary,
                                                        textColor:
                                                            appsProvider
                                                                .areDownloadsRunning()
                                                            ? null
                                                            : scheme.primary,
                                                        icon: Icons
                                                            .check_circle_outline_rounded,
                                                        label: tr(
                                                          'markSelectedAppsUpdated',
                                                        ),
                                                        onTap:
                                                            appsProvider
                                                                .areDownloadsRunning()
                                                            ? null
                                                            : showMassMarkDialog,
                                                      ),
                                                      ActionListTile(
                                                        iconColor:
                                                            scheme.primary,
                                                        textColor:
                                                            scheme.primary,
                                                        icon: Icons
                                                            .download_for_offline_outlined,
                                                        label: tr(
                                                          'downloadX',
                                                          args: [
                                                            lowerCaseIfEnglish(
                                                              tr(
                                                                'releaseAsset',
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        onTap:
                                                            downloadSelectedAppAssets,
                                                      ),
                                                      ActionListTile(
                                                        iconColor:
                                                            scheme.primary,
                                                        textColor:
                                                            scheme.primary,
                                                        icon: Icons
                                                            .category_outlined,
                                                        label: tr('categorize'),
                                                        onTap:
                                                            launchCategorizeDialog(),
                                                      ),
                                                      ActionListTile(
                                                        iconColor:
                                                            scheme.primary,
                                                        textColor:
                                                            scheme.primary,
                                                        icon: Icons
                                                            .push_pin_outlined,
                                                        label:
                                                            selectedApps
                                                                .where(
                                                                  (
                                                                    element,
                                                                  ) => element
                                                                      .pinned,
                                                                )
                                                                .isEmpty
                                                            ? tr('pinToTop')
                                                            : tr(
                                                                'unpinFromTop',
                                                              ),
                                                        onTap: pinSelectedApps,
                                                      ),
                                                      ActionListTile(
                                                        iconColor:
                                                            scheme.primary,
                                                        textColor:
                                                            scheme.primary,
                                                        icon: Icons
                                                            .folder_copy_outlined,
                                                        label: tr(
                                                          'addToFolder',
                                                        ),
                                                        onTap: () =>
                                                            _showFolderAssignDialog(
                                                              context,
                                                              selectedApps,
                                                            ),
                                                      ),
                                                      ActionListTile(
                                                        iconColor:
                                                            scheme.primary,
                                                        textColor:
                                                            scheme.primary,
                                                        icon: Icons
                                                            .share_outlined,
                                                        label: tr(
                                                          'shareSelectedAppURLs',
                                                        ),
                                                        onTap:
                                                            shareSelectedAppUrls,
                                                      ),
                                                      ActionListTile(
                                                        iconColor:
                                                            scheme.primary,
                                                        textColor:
                                                            scheme.primary,
                                                        icon: Icons
                                                            .settings_suggest_outlined,
                                                        label: tr(
                                                          'shareAppConfigLinks',
                                                        ),
                                                        onTap:
                                                            shareSelectedAppConfigLinks,
                                                      ),
                                                      ActionListTile(
                                                        iconColor:
                                                            scheme.primary,
                                                        textColor:
                                                            scheme.primary,
                                                        icon: Icons
                                                            .import_export_outlined,
                                                        label:
                                                            '${tr('share')} - ${tr('obtainiumExport')}',
                                                        onTap:
                                                            exportSelectedApps,
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 24),
                                                  FilledButton.icon(
                                                    style:
                                                        destructiveButtonStyle,
                                                    onPressed: () async {
                                                      final appsProviderRef =
                                                          appsProvider;
                                                      final messenger =
                                                          scaffoldMessengerKey
                                                              .currentState;
                                                      final RemoveAppsWithModalResult
                                                      removeResult =
                                                          await appsProviderRef
                                                              .removeAppsWithModal(
                                                                context,
                                                                selectedApps
                                                                    .toList(),
                                                              );
                                                      if (removeResult
                                                          .shouldShowSnackBar) {
                                                        final Set<String>
                                                        undoAppIds = removeResult
                                                            .deferredUndoAppIds;
                                                        final int removedCount =
                                                            removeResult
                                                                .deferredUndoAppIds
                                                                .isNotEmpty
                                                            ? removeResult
                                                                  .deferredUndoAppIds
                                                                  .length
                                                            : selectedApps
                                                                  .length;
                                                        messenger
                                                          ?..clearSnackBars()
                                                          ..showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                tr(
                                                                  'xAppsRemoved',
                                                                  args: [
                                                                    '$removedCount',
                                                                  ],
                                                                ),
                                                              ),
                                                              persist: false,
                                                              duration:
                                                                  const Duration(
                                                                    seconds: 5,
                                                                  ),
                                                              behavior:
                                                                  SnackBarBehavior
                                                                      .floating,
                                                              action:
                                                                  undoAppIds
                                                                      .isNotEmpty
                                                                  ? SnackBarAction(
                                                                      label: tr(
                                                                        'undo',
                                                                      ),
                                                                      onPressed: () =>
                                                                          appsProviderRef.undoDeferredObtainiumRemovals(
                                                                            undoAppIds,
                                                                          ),
                                                                    )
                                                                  : null,
                                                            ),
                                                          );
                                                      }
                                                    },
                                                    icon: const Icon(
                                                      Icons
                                                          .delete_outline_outlined,
                                                      size: 24,
                                                    ),
                                                    label: Text(
                                                      tr('removeSelectedApps'),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                        : (effectiveSelectedAppId == null
                              ? Scaffold(
                                  backgroundColor:
                                      settingsProvider.useGradientBackground
                                      ? Colors.transparent
                                      : Theme.of(context).colorScheme.surface,
                                  body: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (settingsProvider
                                          .useGradientBackground)
                                        Positioned.fill(
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: Theme.of(context)
                                                  .colorScheme
                                                  .schemePageBackgroundGradient,
                                            ),
                                          ),
                                        ),
                                      Center(
                                        child: SingleChildScrollView(
                                          padding: const EdgeInsets.all(24),
                                          child: M3eExpressiveSettingsCard(
                                            colorScheme: Theme.of(
                                              context,
                                            ).colorScheme,
                                            items: [
                                              AboutSectionContent(
                                                colorScheme: Theme.of(
                                                  context,
                                                ).colorScheme,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Navigator(
                                  key: _getDetailsNavKey(
                                    effectiveSelectedAppId,
                                  ),
                                  onGenerateRoute: (RouteSettings settings) {
                                    final bool openEdit =
                                        _openSelectedInEditMode;
                                    if (_openSelectedInEditMode) {
                                      _openSelectedInEditMode = false;
                                    }
                                    return MaterialPageRoute(
                                      builder: (context) => AppPage(
                                        appId: effectiveSelectedAppId!,
                                        isEmbedded: true,
                                        openInEditMode: openEdit,
                                      ),
                                    );
                                  },
                                )),
                  ),
                ],
              ),
            ],
          );
        }
        return listScaffold;
      }(),
    );
  }

  void openAppById(String appId, {bool autoScroll = true}) {
    final AppsProvider appsProvider = context.read<AppsProvider>();

    final AppInMemory? app = appsProvider.apps[appId];

    // Should exist, since we just looked it up, but just in case...
    if (app == null) {
      return;
    }

    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool isLargeScreen =
        screenWidth >= kLargeScreenWidthBreakpoint &&
        !context.read<SettingsProvider>().isTV &&
        !context.read<SettingsProvider>().alwaysUsePhoneLayout;

    if (isLargeScreen) {
      setState(() {
        selectedAppId = app.app.id;
      });
      if (autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          scrollToApp(appId);
        });
      }
    } else {
      Navigator.push(
        context,
        heroFriendlyAppPageRoute(
          (_) =>
              AppPage(appId: app.app.id, appsListHeroFolderId: widget.folderId),
        ),
      );
    }
  }

  void scrollToApp(String appId) {
    if (!scrollController.hasClients) return;

    final sp = context.read<SettingsProvider>();
    final groupBy = _effectiveGroupBy(sp);

    final int index = _listedAppsCache.indexWhere((sa) => sa.app.id == appId);
    if (index == -1) return;

    double offset = 120.0; // Base header height approximation
    const double itemHeight = 84.0;
    const double headerHeight = 48.0;

    if (groupBy == AppsListGroupBy.none) {
      // Flat list
      final showUpdatesGroupSection =
          _effectiveGroupUpdatesSeparately(sp) &&
          _updatesGroupListedIndices.isNotEmpty;
      final pinUpdatesEnabled = _effectivePinUpdates(sp);
      if (showUpdatesGroupSection) {
        if (pinUpdatesEnabled) {
          final isUpdatesCollapsed = _collapsedGroups.contains(
            '${widget.folderId != null ? 'folder_${widget.folderId}_' : ''}__updates__',
          );
          offset += headerHeight;
          if (!isUpdatesCollapsed) {
            offset += _updatesGroupListedIndices.length * itemHeight;
          }
        }
        final nonUpdatesIndices = [
          for (int i = 0; i < _listedAppsCache.length; i++)
            if (!_updatesGroupListedIndices.contains(i)) i,
        ];
        final flatIndex = nonUpdatesIndices.indexOf(index);
        if (flatIndex != -1) {
          offset += flatIndex * itemHeight;
        }
      } else {
        offset += index * itemHeight;
      }
    } else if (groupBy == AppsListGroupBy.category) {
      // Category group
      for (final cat in _listedCategoriesCache) {
        final categoryMapKey = cat ?? '__null__';
        final indices = _categoryGroupListedIndices[categoryMapKey] ?? [];
        if (indices.isEmpty) continue;
        offset += headerHeight; // Group header
        final catAppIndex = indices.indexOf(index);
        if (catAppIndex != -1) {
          offset += catAppIndex * itemHeight;
          break;
        } else {
          final folderPrefix = widget.folderId != null
              ? 'folder_${widget.folderId}_'
              : '';
          final isCollapsed = _collapsedGroups.contains(
            '${folderPrefix}cat:$categoryMapKey',
          );
          if (!isCollapsed) {
            offset += indices.length * itemHeight;
          }
        }
      }
    } else if (groupBy == AppsListGroupBy.source) {
      // Source group
      for (final src in _listedSourcesCache) {
        final indices = _sourceGroupListedIndices[src] ?? [];
        if (indices.isEmpty) continue;
        offset += headerHeight; // Group header
        final srcAppIndex = indices.indexOf(index);
        if (srcAppIndex != -1) {
          offset += srcAppIndex * itemHeight;
          break;
        } else {
          final folderPrefix = widget.folderId != null
              ? 'folder_${widget.folderId}_'
              : '';
          final isCollapsed = _collapsedGroups.contains(
            '${folderPrefix}src:$src',
          );
          if (!isCollapsed) {
            offset += indices.length * itemHeight;
          }
        }
      }
    } else if (groupBy == AppsListGroupBy.appType) {
      // AppType group
      for (final type in _listedAppTypesCache) {
        final indices = _appTypeGroupListedIndices[type] ?? [];
        if (indices.isEmpty) continue;
        offset += headerHeight; // Group header
        final typeAppIndex = indices.indexOf(index);
        if (typeAppIndex != -1) {
          offset += typeAppIndex * itemHeight;
          break;
        } else {
          final folderPrefix = widget.folderId != null
              ? 'folder_${widget.folderId}_'
              : '';
          final isCollapsed = _collapsedGroups.contains(
            '${folderPrefix}appType:${type.name}',
          );
          if (!isCollapsed) {
            offset += indices.length * itemHeight;
          }
        }
      }
    }

    scrollController.animateTo(
      offset.clamp(0.0, scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
    );
  }

  // ── Folder helpers ──────────────────────────────────────────────────────────

  /// Reconciles [folder]'s criteria against every app, including removals.
  ///
  /// When [preserveExistingMembers] is set (a manual folder that just gained
  /// criteria), any app that was hand-added to the folder and has no explicit
  /// override is promoted to an Always-include override first, so it isn't
  /// silently dropped just because it doesn't match the brand-new criteria.
  Future<void> _applyFolderCriteriaToAllApps(
    AppFolder folder, {
    bool preserveExistingMembers = false,
  }) async {
    if (!folder.isSmart) return;
    final appsProvider = context.read<AppsProvider>();
    final folders = context.read<SettingsProvider>().appFolders;
    final sourceProvider = SourceProvider();
    final changed = <App>[];
    for (final appInMem in appsProvider.apps.values) {
      final app = appInMem.app;
      var mutated = false;
      if (preserveExistingMembers &&
          folderIdsForApp(app).contains(folder.id) &&
          folderOverrideForApp(app, folder.id) ==
              FolderMembershipOverride.automatic) {
        setFolderMembershipOverride(
          app,
          folder.id,
          FolderMembershipOverride.include,
          folder.name,
        );
        mutated = true;
      }
      final sourceIdentifier = sourceProvider
          .getSourceTemplate(app.url, overrideSource: app.overrideSource)
          .sourceIdentifier;
      final reconciled = reconcileAppFolderMemberships(
        app,
        folders,
        sourceIdentifier: sourceIdentifier,
        isUpToDate: appIsUpToDateForFiltering(app),
      );
      // reconcile() snapshots state after our promotion, so flag the app
      // explicitly when we mutated it — otherwise the override wouldn't persist.
      if (reconciled || mutated) {
        changed.add(app);
      }
    }
    if (changed.isNotEmpty) {
      await appsProvider.saveApps(changed, updateInstalledInfo: false);
    }
  }

  /// Removes all traces of [folderId] from every app.
  Future<void> _removeFolderFromAllApps(String folderId) async {
    final appsProvider = context.read<AppsProvider>();
    final changed = <App>[];
    for (final appInMem in appsProvider.apps.values) {
      final app = appInMem.app;
      final hadId =
          folderIdsForApp(app).contains(folderId) ||
          excludedFolderIdsForApp(app).contains(folderId);
      if (hadId) {
        clearFolderFromApp(app, folderId);
        changed.add(app);
      }
    }
    if (changed.isNotEmpty) {
      await appsProvider.saveApps(changed, updateInstalledInfo: false);
    }
  }

  String _folderRuleMatchLabel(FolderRuleMatchType match) {
    switch (match) {
      case FolderRuleMatchType.contains:
        return tr('folderRuleMatchContains');
      case FolderRuleMatchType.equals:
        return tr('folderRuleMatchEquals');
      case FolderRuleMatchType.startsWith:
        return tr('folderRuleMatchStartsWith');
    }
  }

  /// Compact list of the concrete values an active [FolderCriteria] filters on,
  /// e.g. ["firefox", "GitHub", "System", "Not Up-to-date"]. Rendered as the
  /// single-line folder subtitle in the Manage Folders sheet.
  List<String> _folderCriteriaValues(
    FolderCriteria criteria,
    Map<String, String> sourceNames,
  ) {
    final values = <String>[];
    String not(String label) =>
        tr('folderConditionNot', namedArgs: {'label': label});
    void addText(FolderTextCriterion? text) {
      if (text != null && !text.isEmpty) values.add(text.query);
    }

    void addState(FolderConditionIntent intent, String label) {
      if (intent == FolderConditionIntent.include) values.add(label);
      if (intent == FolderConditionIntent.exclude) values.add(not(label));
    }

    addText(criteria.name);
    addText(criteria.author);
    if (criteria.source != null && !criteria.source!.isEmpty) {
      final id = criteria.source!.query;
      values.add(sourceNames[id] ?? id);
    }
    values.addAll(criteria.includedCategories);
    values.addAll(criteria.excludedCategories.map(not));
    addState(criteria.installedIntent, tr('visibilityFilterInstalled'));
    addState(criteria.upToDateIntent, tr('visibilityFilterUpToDate'));
    addState(criteria.trackOnlyIntent, tr('trackOnly'));
    return values;
  }

  // ── Save filter as folder ───────────────────────────────────────────────────

  /// Captures every condition configured in the Apps filter sheet as a
  /// [FolderCriteria] and creates a folder with the given [name], then
  /// reconciles matching apps. An empty filter yields a manual folder. The
  /// active filter is left untouched. Called after the filter sheet is popped
  /// (see the inline save-as-folder row), so provider mutations don't race the
  /// sheet's teardown.
  Future<void> _createFolderFromCurrentFilter(
    AppsFilter currentFilter,
    String name,
  ) async {
    if (name.isEmpty) return;
    final criteria = currentFilter.toFolderCriteria();
    final settingsProvider = context.read<SettingsProvider>();
    final folder = AppFolder(
      id: AppFolder.generateId(),
      name: name,
      criteria: criteria.isEmpty ? null : criteria,
    );
    settingsProvider.appFolders = [...settingsProvider.appFolders, folder];
    hapticSelection();
    await _applyFolderCriteriaToAllApps(folder);
  }

  // ── Folder assign dialog ────────────────────────────────────────────────────

  void _showFolderAssignDialog(BuildContext context, Set<App> apps) {
    final settingsProvider = context.read<SettingsProvider>();
    // Mutable so newly created folders can be reflected without re-opening.
    var folders = settingsProvider.appFolders;

    // Determine which folders all selected apps already belong to.
    final commonFolderIds = folders
        .map((f) => f.id)
        .where((id) => apps.every((a) => folderIdsForApp(a).contains(id)))
        .toSet();
    final selected = Set<String>.from(commonFolderIds);

    // On-Demand Only: checked if ALL selected apps have onDemandOnly == true.
    const String onDemandKey = '__onDemandOnly__';
    final bool allOnDemand = apps.every(
      (a) => a.additionalSettings['onDemandOnly'] == true,
    );
    if (allOnDemand) selected.add(onDemandKey);

    showDialog<void>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDState) {
          Future<void> createNewFolder() async {
            final nameCtrl = TextEditingController();
            final name = await showDialog<String>(
              context: dCtx,
              builder: (ctx) => AlertDialog(
                scrollable: true,
                title: Text(tr('newFolder')),
                contentPadding: appDialogContentPadding,
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      maxLength: _maxFolderNameLength,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: appPageOutlinedInputDecoration(
                        ctx,
                        labelText: tr('folderName'),
                      ),
                      onSubmitted: (_) =>
                          Navigator.of(ctx).pop(nameCtrl.text.trim()),
                    ),
                    const SizedBox(height: 8),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(tr('cancel')),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(ctx).pop(nameCtrl.text.trim()),
                          child: Text(tr('ok')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
            nameCtrl.dispose();
            if (name == null || name.isEmpty) return;
            final newFolder = AppFolder(id: AppFolder.generateId(), name: name);
            final updatedFolders = [...settingsProvider.appFolders, newFolder];
            settingsProvider.appFolders = updatedFolders;
            setDState(() {
              folders = updatedFolders;
              selected.remove(onDemandKey);
              selected.add(newFolder.id);
            });
          }

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            title: Text(tr('addToFolder')),
            contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...folders.map(
                      (f) => CheckboxListTile(
                        title: Text(f.name),
                        secondary: const Icon(Icons.folder_outlined),
                        value: selected.contains(f.id),
                        onChanged: (v) => setDState(() {
                          if (v == true) {
                            selected.add(f.id);
                            // Regular folder and On-Demand are mutually exclusive.
                            selected.remove(onDemandKey);
                          } else {
                            selected.remove(f.id);
                          }
                        }),
                      ),
                    ),
                    CheckboxListTile(
                      title: Text(tr('onDemandOnly')),
                      secondary: const Icon(Icons.folder_special_outlined),
                      value: selected.contains(onDemandKey),
                      onChanged: (v) => setDState(() {
                        if (v == true) {
                          // On-Demand is mutually exclusive with all regular folders.
                          selected
                            ..removeWhere((id) => id != onDemandKey)
                            ..add(onDemandKey);
                        } else {
                          selected.remove(onDemandKey);
                        }
                      }),
                    ),
                    const Divider(height: 8),
                    ListTile(
                      leading: const Icon(Icons.create_new_folder_outlined),
                      title: Text(tr('newFolder')),
                      onTap: createNewFolder,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dCtx).pop(),
                child: Text(tr('cancel')),
              ),
              FilledButton(
                onPressed: () async {
                  final appsProvider = context.read<AppsProvider>();
                  final bool setOnDemand = selected.contains(onDemandKey);
                  for (final app in apps) {
                    // Apply only checkbox states the user actually toggled, so
                    // untouched automatic smart-folder memberships stay
                    // automatic. For smart folders a manual toggle becomes an
                    // Always include / Always exclude override so it survives
                    // reconciliation; manual folders use plain membership.
                    for (final f in folders) {
                      final wasMember = commonFolderIds.contains(f.id);
                      final nowMember = selected.contains(f.id);
                      if (wasMember == nowMember) continue;
                      if (nowMember) {
                        if (f.isSmart) {
                          setFolderMembershipOverride(
                            app,
                            f.id,
                            FolderMembershipOverride.include,
                            f.name,
                          );
                        } else {
                          addAppToFolder(app, f.id, f.name);
                        }
                      } else {
                        if (f.isSmart) {
                          setFolderMembershipOverride(
                            app,
                            f.id,
                            FolderMembershipOverride.exclude,
                            f.name,
                          );
                        } else {
                          removeAppFromFolder(app, f.id);
                        }
                      }
                    }
                    // On-Demand Only: toggle setting when state changed.
                    if (setOnDemand) {
                      app.additionalSettings['onDemandOnly'] = true;
                      // On-demand and folders are mutually exclusive — drop any
                      // folder association so the app can't carry stale, hidden
                      // memberships (the checkbox UI already clears folder
                      // selections; this enforces it at the data layer).
                      clearAllFoldersFromApp(app);
                    } else if (allOnDemand) {
                      // Was checked for all, now unchecked — clear it.
                      app.additionalSettings['onDemandOnly'] = false;
                    }
                  }
                  await appsProvider.saveApps(
                    apps.toList(),
                    updateInstalledInfo: false,
                  );
                  if (!mounted || !dCtx.mounted) return;
                  clearSelected();
                  Navigator.of(dCtx).pop();
                },
                child: Text(tr('save')),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Folder management sheet ─────────────────────────────────────────────────

  Future<void> _showFolderManageSheet(
    BuildContext context, {
    bool createNewFolder = false,
    FolderCriteria? prefillCriteria,
  }) async {
    var creatingFolder = createNewFolder;
    var newFolderInitialCriteria = prefillCriteria;
    AppFolder? editingFolder;
    AppFolder? folderPendingDelete;
    final appsProvider = context.read<AppsProvider>();
    final sourceProvider = SourceProvider();
    final sourceItems = [
      MapEntry('', tr('sourceAny')),
      ...sourceProvider.sourceTemplates.map(
        (e) => MapEntry(e.sourceIdentifier, e.name),
      ),
    ];
    final sourceNames = {for (final item in sourceItems) item.key: item.value};

    int countCriteriaMatches(FolderCriteria criteria) {
      if (criteria.isEmpty) return 0;
      return appsProvider.apps.values
          .where((app) => app.app.additionalSettings['onDemandOnly'] != true)
          .where((app) {
            final sourceIdentifier = sourceProvider
                .getSourceTemplate(
                  app.app.url,
                  overrideSource: app.app.overrideSource,
                )
                .sourceIdentifier;
            return criteria.matches(
              app.app,
              sourceIdentifier: sourceIdentifier,
              isUpToDate: appIsUpToDateForFiltering(app.app),
            );
          })
          .length;
    }

    await showAppModalSheet<void>(
      context: context,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final settingsProvider = sheetCtx.watch<SettingsProvider>();
          final folders = settingsProvider.appFolders;

          Future<void> saveFolder(
            AppFolder? existing,
            String name,
            FolderCriteria? criteria,
          ) async {
            hapticSelection();
            final updatedFolders = List<AppFolder>.from(
              settingsProvider.appFolders,
            );
            final AppFolder savedFolder;
            if (existing == null) {
              savedFolder = AppFolder(
                id: AppFolder.generateId(),
                name: name,
                criteria: criteria,
              );
              updatedFolders.add(savedFolder);
            } else {
              savedFolder = existing.copyWith(
                name: name,
                criteria: criteria,
                clearCriteria: criteria == null,
              );
              final folderIndex = updatedFolders.indexWhere(
                (folder) => folder.id == existing.id,
              );
              if (folderIndex >= 0) {
                updatedFolders[folderIndex] = savedFolder;
              }
            }
            // Manual folder gaining criteria: keep its hand-added members
            // instead of dropping those that don't match the new criteria.
            final becameSmart =
                existing != null && !existing.isSmart && savedFolder.isSmart;
            settingsProvider.appFolders = updatedFolders;
            FocusScope.of(sheetCtx).unfocus();
            setSheetState(() {
              creatingFolder = false;
              newFolderInitialCriteria = null;
              editingFolder = null;
            });
            await _applyFolderCriteriaToAllApps(
              savedFolder,
              preserveExistingMembers: becameSmart,
            );
          }

          Future<void> deleteFolder(AppFolder folder) async {
            hapticSelection();
            settingsProvider.appFolders = settingsProvider.appFolders
                .where((candidate) => candidate.id != folder.id)
                .toList();
            settingsProvider.clearFolderViewSettings(folder.id);
            setSheetState(() {
              folderPendingDelete = null;
              if (editingFolder?.id == folder.id) {
                editingFolder = null;
              }
            });
            await _removeFolderFromAllApps(folder.id);
          }

          return AppSheetContent(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  tr('folders'),
                  style: Theme.of(sheetCtx).textTheme.titleMedium,
                ),
              ),
              if (folders.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: Text(tr('noFolders'))),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: folders.length,
                  itemBuilder: (_, index) {
                    final folder = folders[index];
                    final isEditing = editingFolder?.id == folder.id;
                    final isPendingDelete =
                        folderPendingDelete?.id == folder.id;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 16,
                            right: 4,
                          ),
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(folder.name),
                          subtitle: folder.isSmart
                              ? _FolderSummaryLine(
                                  values: _folderCriteriaValues(
                                    folder.criteria!,
                                    sourceNames,
                                  ),
                                )
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                iconSize: 22,
                                icon: Icon(
                                  isEditing
                                      ? Icons.expand_less
                                      : Icons.edit_outlined,
                                ),
                                tooltip: tr('editFolder'),
                                onPressed: () {
                                  hapticSelection();
                                  FocusScope.of(sheetCtx).unfocus();
                                  setSheetState(() {
                                    editingFolder = isEditing ? null : folder;
                                    creatingFolder = false;
                                    newFolderInitialCriteria = null;
                                    folderPendingDelete = null;
                                  });
                                },
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                iconSize: 22,
                                icon: const Icon(Icons.delete_outlined),
                                tooltip: tr('deleteFolder'),
                                onPressed: () {
                                  hapticSelection();
                                  FocusScope.of(sheetCtx).unfocus();
                                  setSheetState(() {
                                    folderPendingDelete = isPendingDelete
                                        ? null
                                        : folder;
                                    editingFolder = null;
                                    creatingFolder = false;
                                    newFolderInitialCriteria = null;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeInOutCubicEmphasized,
                            alignment: Alignment.topCenter,
                            child: isEditing
                                ? Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      4,
                                      16,
                                      16,
                                    ),
                                    child: _InlineFolderEditor(
                                      key: ValueKey('edit-${folder.id}'),
                                      existing: folder,
                                      categoryColors:
                                          settingsProvider.categories,
                                      sourceItems: sourceItems,
                                      countCriteriaMatches:
                                          countCriteriaMatches,
                                      folderRuleMatchLabel:
                                          _folderRuleMatchLabel,
                                      onCancel: () {
                                        FocusScope.of(sheetCtx).unfocus();
                                        setSheetState(() {
                                          editingFolder = null;
                                        });
                                      },
                                      onSave: (name, criteria) =>
                                          saveFolder(folder, name, criteria),
                                    ),
                                  )
                                : isPendingDelete
                                ? Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      4,
                                      16,
                                      16,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          tr(
                                            'deleteFolderConfirm',
                                            namedArgs: {'name': folder.name},
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        OverflowBar(
                                          alignment: MainAxisAlignment.end,
                                          spacing: 8,
                                          children: [
                                            TextButton(
                                              onPressed: () {
                                                setSheetState(() {
                                                  folderPendingDelete = null;
                                                });
                                              },
                                              child: Text(tr('cancel')),
                                            ),
                                            FilledButton(
                                              onPressed: () {
                                                unawaited(deleteFolder(folder));
                                              },
                                              style: FilledButton.styleFrom(
                                                backgroundColor: Theme.of(
                                                  sheetCtx,
                                                ).colorScheme.error,
                                                foregroundColor: Theme.of(
                                                  sheetCtx,
                                                ).colorScheme.onError,
                                              ),
                                              child: Text(tr('delete')),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    hapticSelection();
                    final shouldExpand = !creatingFolder;
                    FocusScope.of(sheetCtx).unfocus();
                    setSheetState(() {
                      creatingFolder = shouldExpand;
                      newFolderInitialCriteria = null;
                      editingFolder = null;
                      folderPendingDelete = null;
                    });
                  },
                  icon: Icon(
                    creatingFolder
                        ? Icons.expand_less
                        : Icons.create_new_folder_outlined,
                  ),
                  label: Text(tr('newFolder')),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOutCubicEmphasized,
                  alignment: Alignment.topCenter,
                  child: creatingFolder
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _InlineFolderEditor(
                            key: const ValueKey('new-folder'),
                            initialCriteria: newFolderInitialCriteria,
                            categoryColors: settingsProvider.categories,
                            sourceItems: sourceItems,
                            countCriteriaMatches: countCriteriaMatches,
                            folderRuleMatchLabel: _folderRuleMatchLabel,
                            onCancel: () {
                              FocusScope.of(sheetCtx).unfocus();
                              setSheetState(() {
                                creatingFolder = false;
                                newFolderInitialCriteria = null;
                              });
                            },
                            onSave: (name, criteria) =>
                                saveFolder(null, name, criteria),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Inline "save as folder" control for the Apps filter sheet: a folder-name
/// field with a Save button on the same row. Save is enabled only once a name
/// is entered. Manages its own controller so it survives sheet rebuilds.
class _SaveAsFolderRow extends StatefulWidget {
  const _SaveAsFolderRow({required this.onSave});

  final ValueChanged<String> onSave;

  @override
  State<_SaveAsFolderRow> createState() => _SaveAsFolderRowState();
}

class _SaveAsFolderRowState extends State<_SaveAsFolderRow> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    widget.onSave(name);
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _controller.text.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            maxLength: _maxFolderNameLength,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration:
                appPageOutlinedInputDecoration(
                  context,
                  labelText: tr('saveAsFolder'),
                  isDense: true,
                ).copyWith(
                  prefixIcon: const Icon(Icons.create_new_folder_outlined),
                  counterText: '',
                ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: canSave ? _submit : null,
          child: Text(tr('save')),
        ),
      ],
    );
  }
}

/// Renders [values] as a single line of comma-separated text, showing as many
/// as fit and collapsing the remainder into a trailing "+n". Used as the smart
/// folder subtitle in the Manage Folders sheet.
class _FolderSummaryLine extends StatelessWidget {
  const _FolderSummaryLine({required this.values});

  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final style =
        theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ) ??
        const TextStyle();
    final direction = Directionality.of(context);

    double textWidth(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        maxLines: 1,
      )..layout();
      return painter.width;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        var fit = 0;
        for (var i = 0; i < values.length; i++) {
          final shown = values.take(i + 1).join(', ');
          final remaining = values.length - i - 1;
          final reserve = remaining > 0 ? textWidth('  +$remaining') : 0.0;
          if (textWidth(shown) + reserve <= maxWidth) {
            fit = i + 1;
          } else {
            break;
          }
        }
        // Always show at least one value (ellipsized if it can't fully fit).
        final shownCount = fit == 0 ? 1 : fit;
        final overflow = values.length - shownCount;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                values.take(shownCount).join(', '),
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
            if (overflow > 0) Text('  +$overflow', style: style, maxLines: 1),
          ],
        );
      },
    );
  }
}

/// Full filter-style editor for a smart folder's [FolderCriteria]. Mirrors the
/// Apps filter sheet: text fields with match-type operators, source, tri-state
/// visibility conditions, and the shared category selector. Leaving every
/// condition empty produces a manual folder (criteria == null).
class _InlineFolderEditor extends StatefulWidget {
  const _InlineFolderEditor({
    super.key,
    required this.categoryColors,
    required this.sourceItems,
    required this.countCriteriaMatches,
    required this.folderRuleMatchLabel,
    required this.onCancel,
    required this.onSave,
    this.existing,
    this.initialCriteria,
  });

  final AppFolder? existing;
  final FolderCriteria? initialCriteria;
  final Map<String, int> categoryColors;
  final List<MapEntry<String, String>> sourceItems;
  final int Function(FolderCriteria criteria) countCriteriaMatches;
  final String Function(FolderRuleMatchType match) folderRuleMatchLabel;
  final VoidCallback onCancel;
  final Future<void> Function(String name, FolderCriteria? criteria) onSave;

  @override
  State<_InlineFolderEditor> createState() => _InlineFolderEditorState();
}

class _InlineFolderEditorState extends State<_InlineFolderEditor> {
  late final TextEditingController _nameController;
  late final TextEditingController _nameQuery;
  late final TextEditingController _authorQuery;
  late FolderRuleMatchType _nameOp;
  late FolderRuleMatchType _authorOp;
  late Set<String> _includedCategories;
  late Set<String> _excludedCategories;
  late FolderCategoryMatchMode _categoryMatchMode;
  late String _sourceId;
  late FolderConditionIntent _installedIntent;
  late FolderConditionIntent _upToDateIntent;
  late FolderConditionIntent _trackOnlyIntent;

  late final String _initialName;
  late final FolderCriteria? _initialCriteria;

  @override
  void initState() {
    super.initState();
    final c = widget.existing?.criteria ?? widget.initialCriteria;
    _initialName = (widget.existing?.name ?? '').trim();
    _initialCriteria = (c == null || c.isEmpty) ? null : c;
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _nameQuery = TextEditingController(text: c?.name?.query ?? '');
    _authorQuery = TextEditingController(text: c?.author?.query ?? '');
    _nameOp = c?.name?.matchType ?? FolderRuleMatchType.contains;
    _authorOp = c?.author?.matchType ?? FolderRuleMatchType.contains;
    _includedCategories = {...?c?.includedCategories};
    _excludedCategories = {...?c?.excludedCategories};
    _categoryMatchMode = c?.categoryMatchMode ?? FolderCategoryMatchMode.any;
    _sourceId = c?.source?.query ?? '';
    _installedIntent = c?.installedIntent ?? FolderConditionIntent.neutral;
    _upToDateIntent = c?.upToDateIntent ?? FolderConditionIntent.neutral;
    _trackOnlyIntent = c?.trackOnlyIntent ?? FolderConditionIntent.neutral;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameQuery.dispose();
    _authorQuery.dispose();
    super.dispose();
  }

  FolderTextCriterion? _text(
    TextEditingController controller,
    FolderRuleMatchType op, {
    required bool tokenize,
    required bool caseSensitive,
  }) {
    final query = controller.text.trim();
    if (query.isEmpty) return null;
    return FolderTextCriterion(
      query: query,
      matchType: op,
      // Whitespace-tokenized "contains" mirrors the Apps filter search fields.
      tokenizeContains: tokenize,
      caseSensitive: caseSensitive,
    );
  }

  FolderCriteria _buildCriteria() => FolderCriteria(
    name: _text(_nameQuery, _nameOp, tokenize: true, caseSensitive: false),
    author: _text(
      _authorQuery,
      _authorOp,
      tokenize: true,
      caseSensitive: false,
    ),
    includedCategories: _includedCategories,
    excludedCategories: _excludedCategories,
    categoryMatchMode: _categoryMatchMode,
    source: _sourceId.trim().isEmpty
        ? null
        : FolderTextCriterion(
            query: _sourceId.trim(),
            matchType: FolderRuleMatchType.equals,
            caseSensitive: true,
          ),
    installedIntent: _installedIntent,
    upToDateIntent: _upToDateIntent,
    trackOnlyIntent: _trackOnlyIntent,
  );

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final criteria = _buildCriteria();
    await widget.onSave(name, criteria.isEmpty ? null : criteria);
  }

  /// Whether the current form differs from the folder it was opened with.
  /// Enables Save only when there is something to persist.
  bool get _isDirty {
    if (_nameController.text.trim() != _initialName) return true;
    final current = _buildCriteria();
    return !_criteriaEquals(current.isEmpty ? null : current, _initialCriteria);
  }

  bool _setEq(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  bool _textEq(FolderTextCriterion? a, FolderTextCriterion? b) {
    final aEmpty = a == null || a.isEmpty;
    final bEmpty = b == null || b.isEmpty;
    if (aEmpty && bEmpty) return true;
    if (aEmpty || bEmpty) return false;
    return a.query.trim() == b.query.trim() && a.matchType == b.matchType;
  }

  bool _criteriaEquals(FolderCriteria? a, FolderCriteria? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return _textEq(a.name, b.name) &&
        _textEq(a.author, b.author) &&
        _setEq(a.includedCategories, b.includedCategories) &&
        _setEq(a.excludedCategories, b.excludedCategories) &&
        a.categoryMatchMode == b.categoryMatchMode &&
        _textEq(a.source, b.source) &&
        a.installedIntent == b.installedIntent &&
        a.upToDateIntent == b.upToDateIntent &&
        a.trackOnlyIntent == b.trackOnlyIntent;
  }

  CategoryFilterIntent _toCat(FolderConditionIntent intent) => switch (intent) {
    FolderConditionIntent.neutral => CategoryFilterIntent.neutral,
    FolderConditionIntent.include => CategoryFilterIntent.include,
    FolderConditionIntent.exclude => CategoryFilterIntent.exclude,
  };

  FolderConditionIntent _fromCat(CategoryFilterIntent intent) =>
      switch (intent) {
        CategoryFilterIntent.neutral => FolderConditionIntent.neutral,
        CategoryFilterIntent.include => FolderConditionIntent.include,
        CategoryFilterIntent.exclude => FolderConditionIntent.exclude,
      };

  Widget _opSelector(
    FolderRuleMatchType value,
    ValueChanged<FolderRuleMatchType> onChanged,
  ) {
    return PopupMenuButton<FolderRuleMatchType>(
      initialValue: value,
      onSelected: (selected) => setState(() => onChanged(selected)),
      itemBuilder: (_) => FolderRuleMatchType.values
          .map(
            (match) => PopupMenuItem(
              value: match,
              child: Text(widget.folderRuleMatchLabel(match)),
            ),
          )
          .toList(),
      child: InputDecorator(
        decoration:
            appPageOutlinedInputDecoration(
              context,
              labelText: tr('folderRuleMatch'),
              isDense: true,
            ).copyWith(
              suffixIcon: const Icon(Icons.arrow_drop_down),
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
            ),
        child: Text(
          widget.folderRuleMatchLabel(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _textCriterion({
    required TextEditingController controller,
    required String label,
    required FolderRuleMatchType op,
    required ValueChanged<FolderRuleMatchType> onOp,
    bool caseSensitive = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            autocorrect: !caseSensitive,
            enableSuggestions: !caseSensitive,
            decoration: appPageOutlinedInputDecoration(
              context,
              labelText: label,
              isDense: true,
            ).copyWith(prefixIcon: const Icon(Icons.search_rounded)),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 132, child: _opSelector(op, onOp)),
      ],
    );
  }

  Widget _stateChip(
    String label,
    FolderConditionIntent intent,
    ValueChanged<FolderConditionIntent> onChanged,
  ) {
    return _TriStateCategoryFilterChip(
      category: label,
      color: Theme.of(context).colorScheme.primary,
      intent: _toCat(intent),
      onCycle: () => setState(
        () => onChanged(_fromCat(nextCategoryFilterIntent(_toCat(intent)))),
      ),
      onClear: intent == FolderConditionIntent.neutral
          ? null
          : () => setState(() => onChanged(FolderConditionIntent.neutral)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final criteria = _buildCriteria();
    final matchCount = criteria.isEmpty
        ? null
        : widget.countCriteriaMatches(criteria);
    final canSave = _nameController.text.trim().isNotEmpty && _isDirty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameController,
          maxLength: _maxFolderNameLength,
          textCapitalization: TextCapitalization.words,
          decoration: appPageOutlinedInputDecoration(
            context,
            labelText: tr('folderName'),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(tr('folderConditions'), style: theme.textTheme.titleSmall),
            HelpHintIcon(message: tr('folderConditionsHint')),
          ],
        ),
        const SizedBox(height: 12),
        _textCriterion(
          controller: _nameQuery,
          label: tr('appName'),
          op: _nameOp,
          onOp: (v) => _nameOp = v,
        ),
        const SizedBox(height: 12),
        _textCriterion(
          controller: _authorQuery,
          label: tr('author'),
          op: _authorOp,
          onOp: (v) => _authorOp = v,
        ),
        const SizedBox(height: 16),
        appDropdownField<String>(
          key: ValueKey(_sourceId),
          context: context,
          value: _sourceId,
          labelText: tr('appSource'),
          menuWidth: appDropdownMenuWidth(
            context,
            widget.sourceItems.map((sourceItem) => sourceItem.value),
          ),
          items: widget.sourceItems
              .map(
                (sourceItem) => DropdownMenuItem(
                  value: sourceItem.key,
                  child: Text(sourceItem.value),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _sourceId = value ?? ''),
        ),
        const SizedBox(height: 16),
        Text(
          tr('visibilityFilterCycleHint'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        CategoryActionChipGroup(
          children: [
            _stateChip(
              tr('visibilityFilterInstalled'),
              _installedIntent,
              (v) => _installedIntent = v,
            ),
            _stateChip(
              tr('visibilityFilterUpToDate'),
              _upToDateIntent,
              (v) => _upToDateIntent = v,
            ),
            _stateChip(
              tr('trackOnly'),
              _trackOnlyIntent,
              (v) => _trackOnlyIntent = v,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _TriStateCategoryFilterSelector(
          categoryColors: widget.categoryColors,
          includedCategories: _includedCategories,
          excludedCategories: _excludedCategories,
          matchMode: switch (_categoryMatchMode) {
            FolderCategoryMatchMode.any => CategoryFilterMatchMode.any,
            FolderCategoryMatchMode.all => CategoryFilterMatchMode.all,
          },
          onChanged: (included, excluded) => setState(() {
            _includedCategories = included;
            _excludedCategories = excluded;
          }),
          onMatchModeChanged: (mode) => setState(() {
            _categoryMatchMode = switch (mode) {
              CategoryFilterMatchMode.any => FolderCategoryMatchMode.any,
              CategoryFilterMatchMode.all => FolderCategoryMatchMode.all,
            };
          }),
        ),
        const SizedBox(height: 12),
        if (matchCount != null)
          Text(
            tr('ruleMatchesXApps', namedArgs: {'count': '$matchCount'}),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 12),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          children: [
            TextButton(onPressed: widget.onCancel, child: Text(tr('cancel'))),
            FilledButton.icon(
              onPressed: canSave ? () => unawaited(_save()) : null,
              icon: const Icon(Icons.save_outlined),
              label: Text(tr('save')),
            ),
          ],
        ),
      ],
    );
  }
}

class _TriStateCategoryFilterSelector extends StatelessWidget {
  const _TriStateCategoryFilterSelector({
    required this.categoryColors,
    required this.includedCategories,
    required this.excludedCategories,
    required this.matchMode,
    required this.onChanged,
    required this.onMatchModeChanged,
  });

  final Map<String, int> categoryColors;
  final Set<String> includedCategories;
  final Set<String> excludedCategories;
  final CategoryFilterMatchMode matchMode;
  final void Function(Set<String> included, Set<String> excluded) onChanged;
  final ValueChanged<CategoryFilterMatchMode> onMatchModeChanged;

  @override
  Widget build(BuildContext context) {
    final categories = <String>{
      ...categoryColors.keys,
      ...includedCategories,
      ...excludedCategories,
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (categories.isEmpty) {
      return Text(
        tr('noCategories'),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    void cycleCategory(String category) {
      final included = Set<String>.from(includedCategories);
      final excluded = Set<String>.from(excludedCategories);
      final currentIntent = included.contains(category)
          ? CategoryFilterIntent.include
          : excluded.contains(category)
          ? CategoryFilterIntent.exclude
          : CategoryFilterIntent.neutral;
      switch (nextCategoryFilterIntent(currentIntent)) {
        case CategoryFilterIntent.neutral:
          included.remove(category);
          excluded.remove(category);
          break;
        case CategoryFilterIntent.include:
          included.add(category);
          excluded.remove(category);
          break;
        case CategoryFilterIntent.exclude:
          included.remove(category);
          excluded.add(category);
          break;
      }
      onChanged(included, excluded);
    }

    void clearCategory(String category) {
      onChanged(
        Set<String>.from(includedCategories)..remove(category),
        Set<String>.from(excludedCategories)..remove(category),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr('categories'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 112,
              child: AppSegmentedButton<CategoryFilterMatchMode>(
                segments: [
                  ButtonSegment(
                    value: CategoryFilterMatchMode.any,
                    label: AppSegmentedButtonLabel(tr('categoryMatchAny')),
                  ),
                  ButtonSegment(
                    value: CategoryFilterMatchMode.all,
                    label: AppSegmentedButtonLabel(tr('categoryMatchAll')),
                  ),
                ],
                selected: {matchMode},
                onSelectionChanged: (selection) {
                  onMatchModeChanged(selection.first);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          tr('categoryFilterCycleHint'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        CategoryActionChipGroup(
          children: categories.map((category) {
            final intent = includedCategories.contains(category)
                ? CategoryFilterIntent.include
                : excludedCategories.contains(category)
                ? CategoryFilterIntent.exclude
                : CategoryFilterIntent.neutral;
            return _TriStateCategoryFilterChip(
              category: category,
              color: Color(
                categoryColors[category] ?? Colors.grey.shade500.toARGB32(),
              ),
              intent: intent,
              onCycle: () => cycleCategory(category),
              onClear: intent == CategoryFilterIntent.neutral
                  ? null
                  : () => clearCategory(category),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _TriStateCategoryFilterChip extends StatelessWidget {
  const _TriStateCategoryFilterChip({
    required this.category,
    required this.color,
    required this.intent,
    required this.onCycle,
    this.onClear,
  });

  final String category;
  final Color color;
  final CategoryFilterIntent intent;
  final VoidCallback onCycle;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final maxChipWidth = MediaQuery.sizeOf(context).width - 40;
    final CategoryActionChipState chipState = switch (intent) {
      CategoryFilterIntent.neutral => CategoryActionChipState.muted,
      CategoryFilterIntent.include => CategoryActionChipState.add,
      CategoryFilterIntent.exclude => CategoryActionChipState.remove,
    };

    return Tooltip(
      message: switch (intent) {
        CategoryFilterIntent.neutral => category,
        CategoryFilterIntent.include => '+ $category',
        CategoryFilterIntent.exclude => '- $category',
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxChipWidth),
        child: GestureDetector(
          onLongPress: onClear,
          child: CategoryActionChip(
            label: category,
            color: color,
            state: chipState,
            onPressed: onCycle,
          ),
        ),
      ),
    );
  }
}

class AppsFilter {
  String nameFilter;
  String authorFilter;
  CategoryFilterIntent upToDateFilterIntent;
  CategoryFilterIntent installedFilterIntent;
  CategoryFilterIntent trackOnlyFilterIntent;
  Set<String> includedCategoryFilter;
  Set<String> excludedCategoryFilter;
  CategoryFilterMatchMode categoryMatchMode;
  String sourceFilter;

  AppsFilter({
    this.nameFilter = '',
    this.authorFilter = '',
    this.upToDateFilterIntent = CategoryFilterIntent.neutral,
    this.installedFilterIntent = CategoryFilterIntent.neutral,
    this.trackOnlyFilterIntent = CategoryFilterIntent.neutral,
    Set<String> categoryFilter = const {},
    Set<String>? includedCategoryFilter,
    Set<String>? excludedCategoryFilter,
    this.categoryMatchMode = CategoryFilterMatchMode.any,
    this.sourceFilter = '',
  }) : includedCategoryFilter = includedCategoryFilter ?? categoryFilter,
       excludedCategoryFilter = excludedCategoryFilter ?? const {};

  Map<String, dynamic> toFormValuesMap() {
    return {
      'appName': nameFilter,
      'author': authorFilter,
      'upToDateFilterIntent': upToDateFilterIntent.name,
      'installedFilterIntent': installedFilterIntent.name,
      'trackOnlyFilterIntent': trackOnlyFilterIntent.name,
      'sourceFilter': sourceFilter,
    };
  }

  FolderCriteria toFolderCriteria() {
    FolderConditionIntent folderIntent(CategoryFilterIntent intent) {
      return switch (intent) {
        CategoryFilterIntent.neutral => FolderConditionIntent.neutral,
        CategoryFilterIntent.include => FolderConditionIntent.include,
        CategoryFilterIntent.exclude => FolderConditionIntent.exclude,
      };
    }

    FolderTextCriterion? textCriterion(
      String query, {
      required bool tokenizeContains,
      required bool caseSensitive,
    }) {
      final trimmed = query.trim();
      if (trimmed.isEmpty) return null;
      return FolderTextCriterion(
        query: trimmed,
        tokenizeContains: tokenizeContains,
        caseSensitive: caseSensitive,
      );
    }

    return FolderCriteria(
      name: textCriterion(
        nameFilter,
        tokenizeContains: true,
        caseSensitive: false,
      ),
      author: textCriterion(
        authorFilter,
        tokenizeContains: true,
        caseSensitive: false,
      ),
      includedCategories: includedCategoryFilter,
      excludedCategories: excludedCategoryFilter,
      categoryMatchMode: switch (categoryMatchMode) {
        CategoryFilterMatchMode.any => FolderCategoryMatchMode.any,
        CategoryFilterMatchMode.all => FolderCategoryMatchMode.all,
      },
      source: sourceFilter.trim().isEmpty
          ? null
          : FolderTextCriterion(
              query: sourceFilter.trim(),
              matchType: FolderRuleMatchType.equals,
              caseSensitive: true,
            ),
      installedIntent: folderIntent(installedFilterIntent),
      upToDateIntent: folderIntent(upToDateFilterIntent),
      trackOnlyIntent: folderIntent(trackOnlyFilterIntent),
    );
  }

  CategoryFilterIntent _intentFromLegacyUpdateStatus(String name) {
    return switch (name) {
      'needsUpdateOnly' => CategoryFilterIntent.exclude,
      'upToDateOnly' => CategoryFilterIntent.include,
      _ => CategoryFilterIntent.neutral,
    };
  }

  CategoryFilterIntent _intentFromLegacyInstallStatus(String name) {
    return switch (name) {
      'installedOnly' => CategoryFilterIntent.include,
      'notInstalledOnly' => CategoryFilterIntent.exclude,
      _ => CategoryFilterIntent.neutral,
    };
  }

  CategoryFilterIntent _intentFromLegacyTrackMode(String name) {
    return switch (name) {
      'trackOnly' => CategoryFilterIntent.include,
      'installable' => CategoryFilterIntent.exclude,
      _ => CategoryFilterIntent.neutral,
    };
  }

  void setFormValuesFromMap(Map<String, dynamic> values) {
    nameFilter = values['appName']!;
    authorFilter = values['author']!;
    if (values.containsKey('upToDateFilterIntent')) {
      upToDateFilterIntent = CategoryFilterIntent.values.byName(
        values['upToDateFilterIntent'] as String,
      );
    } else if (values.containsKey('updateStatusFilter')) {
      upToDateFilterIntent = _intentFromLegacyUpdateStatus(
        values['updateStatusFilter'] as String,
      );
    } else if (values['upToDateApps'] == false) {
      upToDateFilterIntent = CategoryFilterIntent.exclude;
    } else {
      upToDateFilterIntent = CategoryFilterIntent.neutral;
    }
    if (values.containsKey('installedFilterIntent')) {
      installedFilterIntent = CategoryFilterIntent.values.byName(
        values['installedFilterIntent'] as String,
      );
    } else if (values.containsKey('installStatusFilter')) {
      installedFilterIntent = _intentFromLegacyInstallStatus(
        values['installStatusFilter'] as String,
      );
    } else if (values['nonInstalledApps'] == false) {
      installedFilterIntent = CategoryFilterIntent.include;
    } else {
      installedFilterIntent = CategoryFilterIntent.neutral;
    }
    if (values.containsKey('trackOnlyFilterIntent')) {
      trackOnlyFilterIntent = CategoryFilterIntent.values.byName(
        values['trackOnlyFilterIntent'] as String,
      );
    } else if (values.containsKey('trackModeFilter')) {
      trackOnlyFilterIntent = _intentFromLegacyTrackMode(
        values['trackModeFilter'] as String,
      );
    } else {
      trackOnlyFilterIntent = CategoryFilterIntent.neutral;
    }
    sourceFilter = values['sourceFilter'];
  }

  bool isIdenticalTo(AppsFilter other, SettingsProvider settingsProvider) =>
      authorFilter.trim() == other.authorFilter.trim() &&
      nameFilter.trim() == other.nameFilter.trim() &&
      upToDateFilterIntent == other.upToDateFilterIntent &&
      installedFilterIntent == other.installedFilterIntent &&
      trackOnlyFilterIntent == other.trackOnlyFilterIntent &&
      settingsProvider.setEqual(
        includedCategoryFilter,
        other.includedCategoryFilter,
      ) &&
      settingsProvider.setEqual(
        excludedCategoryFilter,
        other.excludedCategoryFilter,
      ) &&
      categoryMatchMode == other.categoryMatchMode &&
      sourceFilter.trim() == other.sourceFilter.trim();
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

class _ConditionalScrollbar extends StatelessWidget {
  const _ConditionalScrollbar({
    required this.condition,
    required this.controller,
    required this.child,
  });

  final bool condition;
  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!condition) {
      return ScrollConfiguration(
        behavior: const _NoScrollbarBehavior(),
        child: child,
      );
    }
    return Scrollbar(interactive: true, controller: controller, child: child);
  }
}

class _CategoryChipsRow extends StatelessWidget {
  const _CategoryChipsRow({
    required this.categories,
    required this.categoryColors,
  });

  final List<String> categories;
  final Map<String?, int> categoryColors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final int transparent = colorScheme.surface.withValues(alpha: 0).toARGB32();

    final TextStyle? labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w500,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth;

        double calculateTextWidth(String text) {
          final TextPainter textPainter = TextPainter(
            text: TextSpan(text: text, style: labelStyle),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          );
          try {
            textPainter.textScaler = MediaQuery.textScalerOf(context);
          } catch (_) {
            try {
              // ignore: deprecated_member_use
              textPainter.textScaleFactor = MediaQuery.textScaleFactorOf(
                context,
              );
            } catch (_) {}
          }
          textPainter.layout();
          return textPainter.width;
        }

        const double chipPaddingFootprint = 46.0;

        double totalWidthOfAll = 0.0;
        final List<double> chipWidths = [];
        for (final category in categories) {
          final double textW = calculateTextWidth(category);
          final double chipW = textW + chipPaddingFootprint;
          chipWidths.add(chipW);
          totalWidthOfAll += chipW;
        }

        if (totalWidthOfAll <= maxWidth) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: categories.map((category) {
              final color = Color(
                categoryColors[category] ?? transparent,
              ).withAlpha(255);
              return CategoryActionChip(
                label: category,
                color: color,
                state: CategoryActionChipState.plain,
              );
            }).toList(),
          );
        }

        int bestK = 0;
        for (int k = categories.length - 1; k >= 0; k--) {
          double prefixWidth = 0.0;
          for (int i = 0; i < k; i++) {
            prefixWidth += chipWidths[i];
          }
          final int remaining = categories.length - k;
          final String plusMoreText = tr(
            'plusMore',
            args: [remaining.toString()],
          );
          final double plusMoreChipW =
              calculateTextWidth(plusMoreText) + chipPaddingFootprint;

          if (prefixWidth + plusMoreChipW <= maxWidth) {
            bestK = k;
            break;
          }
        }

        final List<Widget> children = [];
        for (int i = 0; i < bestK; i++) {
          final category = categories[i];
          final color = Color(
            categoryColors[category] ?? transparent,
          ).withAlpha(255);
          children.add(
            CategoryActionChip(
              label: category,
              color: color,
              state: CategoryActionChipState.plain,
            ),
          );
        }

        final int remainingCount = categories.length - bestK;
        if (remainingCount > 0) {
          final String plusMoreText = tr(
            'plusMore',
            args: [remainingCount.toString()],
          );
          children.add(
            CategoryActionChip(
              label: plusMoreText,
              color: colorScheme.surfaceContainerHighest,
              state: CategoryActionChipState.muted,
            ),
          );
        }

        return Row(mainAxisSize: MainAxisSize.min, children: children);
      },
    );
  }
}
