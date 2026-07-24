import 'package:flutter/material.dart';

/// Presents [builder] as a modal bottom sheet with the app's standard chrome:
/// the themed M3 Expressive shape, the framework drag handle, and (optionally)
/// full width on large
/// screens.
///
/// Pair the builder result with [AppSheetContent] or [AppSheetScaffold] so the
/// body caps just below the status bar, scrolls once it would exceed that, and
/// clears the keyboard and system nav bar. Call sites must **not**
/// re-implement handles, height caps, scroll views, padding, or inset math —
/// that all lives here so every sheet behaves identically.
Future<T?> showAppModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool fullWidth = false,
  Color? backgroundColor,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: enableDrag,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    backgroundColor: backgroundColor,
    // Full width overrides the M3 default that caps sheet width on wide screens.
    constraints: fullWidth
        ? const BoxConstraints(maxWidth: double.infinity)
        : null,
    builder: (BuildContext sheetContext) {
      final Widget sheet = builder(sheetContext);
      return Padding(
        // Keep the sheet itself above the keyboard. Putting this inset inside
        // the scroll view only adds hidden space below the focused field and
        // leaves the visible content behind the keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: fullWidth
            ? sheet
            : MediaQuery.removePadding(
                context: sheetContext,
                removeLeft: true,
                removeRight: true,
                child: sheet,
              ),
      );
    },
  );
}

double _appSheetMaxHeight(BuildContext context) {
  final MediaQueryData mediaQuery = MediaQuery.of(context);
  final double byFraction =
      mediaQuery.size.height * AppSheetContent.maxHeightFraction;
  final double byClearance =
      mediaQuery.size.height - mediaQuery.viewPadding.top - 56;
  return byFraction < byClearance ? byFraction : byClearance;
}

/// Shared structure for sheets that need a fixed header and action area around
/// a separately scrollable body.
///
/// This owns the height cap, safe-area handling, footer treatment, and system
/// navigation inset. Specialized sheets provide only their content and actions.
class AppSheetScaffold extends StatelessWidget {
  const AppSheetScaffold({
    super.key,
    required this.header,
    required this.body,
    this.footer,
    this.expand = false,
    this.headerPadding = const EdgeInsets.fromLTRB(20, 0, 20, 8),
    this.bodyPadding = EdgeInsets.zero,
    this.footerPadding = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  });

  final Widget header;
  final Widget body;
  final Widget? footer;

  /// Whether the sheet should fill its available height even when its body is
  /// short. Reading and large selection surfaces generally opt into this.
  final bool expand;

  final EdgeInsetsGeometry headerPadding;
  final EdgeInsetsGeometry bodyPadding;
  final EdgeInsets footerPadding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double maxHeight = _appSheetMaxHeight(context);
    final double bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return SafeArea(
      top: false,
      bottom: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SizedBox(
          height: expand ? maxHeight : null,
          child: Column(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: headerPadding, child: header),
              if (expand)
                Expanded(
                  child: Padding(padding: bodyPadding, child: body),
                )
              else
                Flexible(
                  child: Padding(padding: bodyPadding, child: body),
                ),
              if (footer != null)
                Material(
                  color: colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      footerPadding.left,
                      footerPadding.top,
                      footerPadding.right,
                      footerPadding.bottom + bottomInset,
                    ),
                    child: footer,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The standard body for [showAppModalSheet]: a min-sized [Column] of
/// [children] inside a height-capped, inset-aware scroll view.
///
/// * Height hugs the content up to ([MediaQuery] height − status bar − 12);
///   shorter content produces a shorter sheet (no dead space), taller content
///   scrolls.
/// * The sheet boundary tracks the keyboard while bottom padding clears the
///   system nav bar, so focused fields can scroll into the visible area.
/// * Horizontal padding plus a left/right [SafeArea] keep content clear of
///   landscape display cutouts.
class AppSheetContent extends StatelessWidget {
  const AppSheetContent({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 16),
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  /// Fraction of the screen height the sheet may occupy before its content
  /// starts to scroll. Kept below 1 so the drag handle and a sliver of scrim
  /// always sit clear of the status bar (otherwise dragging the handle catches
  /// the system notification panel instead of the sheet).
  static const double maxHeightFraction = 0.90;

  /// The sheet body, laid out as a vertical column.
  final List<Widget> children;

  /// Padding around the column. The bottom value is automatically extended by
  /// the system nav-bar inset.
  final EdgeInsets padding;

  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    // Cap at [maxHeightFraction] of the screen, but never so tall that the drag
    // handle would ride up behind the status bar. The fraction alone is not
    // enough in landscape, where the screen is short and 10% headroom is only a
    // few pixels — so also keep a fixed clearance below the top system inset and
    // use whichever limit is more restrictive.
    final double maxHeight = _appSheetMaxHeight(context);
    final double bottomInset = mq.viewPadding.bottom;
    return SafeArea(
      top: false,
      bottom: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            padding.top,
            padding.right,
            padding.bottom + bottomInset,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: crossAxisAlignment,
            children: children,
          ),
        ),
      ),
    );
  }
}
