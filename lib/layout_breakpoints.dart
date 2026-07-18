import 'package:flutter/widgets.dart';

/// Width (logical px) at/above which large-screen layouts (two-panel views,
/// navigation rail) are used in portrait. Shared so the breakpoint can't drift
/// between screens.
const double kLargeScreenWidthBreakpoint = 720;

/// In landscape, large-screen layouts kick in at this lower width.
const double kLargeScreenLandscapeWidthBreakpoint = 600;

/// Shortest-side boundary used when behavior must distinguish a phone from a
/// tablet independently of the current orientation.
const double kTabletShortestSideBreakpoint = 600;

/// Large-screen when wide enough in portrait, or somewhat narrower in landscape.
///
/// Used by the add-app and bulk-add pages, which intentionally opt into the
/// landscape breakpoint. Other pages use [kLargeScreenWidthBreakpoint] directly
/// (portrait threshold only) — that difference is deliberate, so don't unify
/// the two without checking each call site.
bool isLargeScreenLayout(
  double width,
  Orientation orientation, {
  bool alwaysUsePhoneLayout = false,
}) {
  if (alwaysUsePhoneLayout) return false;
  return width >= kLargeScreenWidthBreakpoint ||
      (width >= kLargeScreenLandscapeWidthBreakpoint &&
          orientation == Orientation.landscape);
}
