import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/theme/app_theme_accent.dart';
import 'package:provider/provider.dart';

class CustomAppBar extends StatefulWidget {
  const CustomAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.searchWidget,
    this.titleStyle,
    this.matchGradientBackground = false,
    this.progressiveBlurOverlayColor,
  });

  final String title;

  /// Toolbar leading widget (e.g. back). When null, no leading slot is shown.
  final Widget? leading;
  final List<Widget>? actions;

  /// Optional widget pinned below the flexible title (e.g. a search field).
  /// Pass a [PreferredSizeWidget] such as [PreferredSize].
  final PreferredSizeWidget? bottom;

  /// When provided, replaces the expanding-title layout with a compact inline
  /// row. The title and search field use the same bounded slot, with the caller
  /// showing one at a time, while [actions] remain fixed at the end.
  final Widget? searchWidget;

  /// Optional style override for the compact layout title.
  final TextStyle? titleStyle;

  /// Whether the non-blurred app bar should sample the page gradient behind it.
  final bool matchGradientBackground;

  /// Optional tint override for progressive blur.
  final Color? progressiveBlurOverlayColor;

  @override
  State<CustomAppBar> createState() => _CustomAppBarState();
}

class _CustomAppBarState extends State<CustomAppBar> {
  // Single BackdropFilter pass + colour tint gradient. See
  // [ProgressiveTopEdgeOverlay] for the rationale: the previous two-layer
  // implementation cost ~2x as much GPU per frame and produced 30 fps
  // drops on mid-range Android during apps-list scroll. The colour tint
  // gradient handles the "progressive" feel that the second blur used to
  // provide.
  // Kept gentle on purpose: the uniform single-pass blur is just a light
  // frost, and the progressive colour-tint gradient (opaque top → transparent
  // bottom) carries the "progressive" feel. See ProgressiveTopEdgeOverlay for
  // why graduated multi-pass blur is deliberately avoided (GPU cost).
  static const double _blurSigma = 3.0;

  Widget _buildBlur(Color overlayColor) {
    return ScrollLinkedProgressiveBlur(
      overlayColor: overlayColor,
      blurSigma: _blurSigma,
    );
  }

  Widget _buildGradientBackground(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    final double pageHeight = MediaQuery.sizeOf(context).height;

    return IgnorePointer(
      child: ClipRect(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return OverflowBox(
              alignment: Alignment.topCenter,
              minWidth: constraints.maxWidth,
              maxWidth: constraints.maxWidth,
              minHeight: pageHeight,
              maxHeight: pageHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: colorScheme.schemePageBackgroundGradient,
                ),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: pageHeight,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextStyle titleBaseLarge = Theme.of(context).textTheme.titleLarge!;
    final TextStyle resolvedCompactTitle =
        (widget.titleStyle ??
                Theme.of(context).appBarTheme.titleTextStyle ??
                titleBaseLarge)
            .copyWith(color: colorScheme.onSurface);

    // [Selector] instead of [context.watch] so that the persistent app
    // bar - which sits on every page - only rebuilds when these specific
    // settings flip, not on every unrelated SettingsProvider notify
    // (categories, swipe actions, sort changes, etc.).
    final bool blurEnabled = context.select<SettingsProvider, bool>(
      (settings) => settings.progressiveBlurEnabled,
    );
    final Widget headerBackground;
    if (blurEnabled) {
      headerBackground = _buildBlur(
        widget.progressiveBlurOverlayColor ??
            colorScheme.schemeProgressiveBlurOverlayTint,
      );
    } else if (widget.matchGradientBackground) {
      headerBackground = _buildGradientBackground(context, colorScheme);
    } else {
      headerBackground = ColoredBox(color: colorScheme.surface);
    }
    final bool transparentAppBar =
        blurEnabled || widget.matchGradientBackground;

    if (widget.searchWidget != null) {
      // Compact layout - draw the header background as flexibleSpace so the
      // toolbar title/actions render on top of it, not behind it.
      return SliverAppBar(
        pinned: true,
        automaticallyImplyLeading: false,
        leading: widget.leading,
        actions: widget.actions,
        titleSpacing: 0,
        bottom: widget.bottom,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        backgroundColor: transparentAppBar
            ? Colors.transparent
            : colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        forceMaterialTransparency: transparentAppBar,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        actionsIconTheme: IconThemeData(color: colorScheme.onSurface),
        flexibleSpace: headerBackground,
        title: Padding(
          padding: EdgeInsets.only(
            left: widget.leading != null ? 0 : 20,
            right: 4,
          ),
          child: Row(
            children: [
              if (widget.title.isNotEmpty) ...[
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.fastEaseInToSlowEaseOut,
                    style: resolvedCompactTitle,
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ] else
                Expanded(child: widget.searchWidget!),
            ],
          ),
        ),
      );
    }

    // Default (large expanding title) - header background is the bottom layer
    // of a Stack used as flexibleSpace. FlexibleSpaceBar sits on top and handles title
    // animation. This avoids FlexibleSpaceBar.background's fade-out, which
    // would make the blur invisible as soon as the user starts scrolling.
    //
    // When [leading] is set, inset the collapsed title past the toolbar
    // leading slot so it does not draw under the back button.
    final EdgeInsetsDirectional expandingTitlePadding =
        EdgeInsetsDirectional.only(
          start: widget.leading != null ? kToolbarHeight + 8 : 20,
          end: 20,
          top: 16,
          bottom: 16,
        );
    final Widget flexibleSpace = widget.title.isEmpty
        ? headerBackground
        : Stack(
            fit: StackFit.expand,
            children: [
              headerBackground,
              FlexibleSpaceBar(
                titlePadding: expandingTitlePadding,
                title: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge!.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          );

    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      leading: widget.leading,
      leadingWidth: widget.leading != null ? kToolbarHeight : null,
      actions: widget.actions,
      expandedHeight: widget.title.isEmpty ? null : 100,
      bottom: widget.bottom,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      backgroundColor: transparentAppBar
          ? Colors.transparent
          : colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      forceMaterialTransparency: transparentAppBar,
      iconTheme: IconThemeData(color: colorScheme.onSurface),
      actionsIconTheme: IconThemeData(color: colorScheme.onSurface),
      flexibleSpace: flexibleSpace,
    );
  }
}

class ScrollLinkedProgressiveBlur extends StatefulWidget {
  final Color overlayColor;
  final double blurSigma;

  const ScrollLinkedProgressiveBlur({
    super.key,
    required this.overlayColor,
    required this.blurSigma,
  });

  @override
  State<ScrollLinkedProgressiveBlur> createState() =>
      _ScrollLinkedProgressiveBlurState();
}

class _ScrollLinkedProgressiveBlurState
    extends State<ScrollLinkedProgressiveBlur> {
  // Last quantized ramp value we built a subtree for, and that subtree.
  double _lastT = -1;
  Widget _cached = const SizedBox.shrink();

  @override
  void didUpdateWidget(ScrollLinkedProgressiveBlur oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A theme change (tint) or a blur-strength change invalidates the cache.
    if (oldWidget.overlayColor != widget.overlayColor ||
        oldWidget.blurSigma != widget.blurSigma) {
      _lastT = -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scrollPosition = Scrollable.maybeOf(context)?.position;
    if (scrollPosition == null) {
      return _contentFor(1.0);
    }

    return AnimatedBuilder(
      animation: scrollPosition,
      builder: (context, child) {
        double opacity = 0.0;
        if (scrollPosition.hasPixels) {
          // Fades in over 36 pixels of scroll
          opacity = (scrollPosition.pixels / 36.0).clamp(0.0, 1.0);
        }
        return _contentFor(opacity);
      },
    );
  }

  /// Returns the blur subtree for ramp value [t], reusing the cached instance
  /// when [t] is unchanged. Past the 36px fade-in ramp `t` is pinned at 1.0, so
  /// without this the [AnimatedBuilder] rebuilt an identical BackdropFilter +
  /// ImageFilter + LinearGradient on the UI thread every single scroll frame.
  /// Returning the *identical* widget instance lets Flutter skip the subtree
  /// rebuild entirely. (The backdrop blur still re-rasterizes over the moving
  /// content on the raster thread — that is inherent to a live blur.)
  Widget _contentFor(double t) {
    // Quantize to 1% so sub-pixel scroll deltas don't defeat the cache.
    final double q = (t * 100).roundToDouble() / 100;
    if (q == _lastT) return _cached;
    _lastT = q;
    _cached = _buildBlurContent(q);
    return _cached;
  }

  Widget _buildBlurContent(double opacity) {
    if (opacity <= 0.0) return const SizedBox.shrink();

    // Ramp the fade-in via the blur sigma and the tint's alpha rather than
    // wrapping the whole thing in an Opacity. Opacity forces an offscreen
    // saveLayer every scroll frame, and a BackdropFilter inside that layer
    // samples the (empty) layer instead of the screen behind it — so the old
    // approach was both costly per-frame and didn't blur the content correctly.
    // Same end state at full scroll; just a cleaner, cheaper ramp in between.
    final double t = opacity.clamp(0.0, 1.0);
    return IgnorePointer(
      child: RepaintBoundary(
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: widget.blurSigma * t,
                  sigmaY: widget.blurSigma * t,
                ),
                child: const SizedBox.expand(),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      widget.overlayColor.withValues(
                        alpha: widget.overlayColor.a * t,
                      ),
                      widget.overlayColor.withValues(alpha: 0),
                    ],
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
