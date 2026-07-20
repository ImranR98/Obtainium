import 'package:flutter/material.dart';

/// Inline tappable help-icon that pops a tooltip with [message] or
/// [richMessage].
///
/// Used inline next to a settings-row title (or any other label) when a
/// long subtitle would crowd the row but a contextual explanation is still
/// useful. Tap to show; tooltip auto-dismisses after [showDuration].
///
/// Visual styling (background colour, text style, padding, radius) comes
/// from the [TooltipTheme] set globally in [main.dart] - so all
/// help-tooltips look consistent and on-brand without per-call-site fuss.
///
/// **Implementation note on tap propagation.** The icon is rendered as an
/// [IconButton] with manual tooltip triggering, NOT a bare [Icon] wrapped
/// in a tap-trigger [Tooltip]. The reason: when this widget lives inside
/// a [SwitchListTile] (or any row wrapped in an [InkWell]), a tap on a
/// bare-icon-with-tap-tooltip ALSO triggers the parent row's ink response
/// because the bare [Tooltip]'s [GestureRecognizer] doesn't claim the
/// pointer hit at the same level as the [InkWell] does - both fire. With
/// the M3 [InkSparkle] splash factory the parent's reaction shows as a
/// distracting full-row flash whenever the user taps the help icon.
/// [IconButton]'s own internal [InkResponse] *does* claim the pointer
/// hit, contains the ripple to a small circle around the icon, AND
/// prevents the ancestor row from receiving the same tap. We trigger the
/// tooltip explicitly from `onPressed` via a [GlobalKey] since
/// [TooltipTriggerMode.tap] would now compete with [IconButton]'s own
/// gesture handling.
class HelpHintIcon extends StatefulWidget {
  const HelpHintIcon({
    super.key,
    this.message,
    this.richMessage,
    this.icon = Icons.help_outline_rounded,
    this.size = 20,
    this.padding = const EdgeInsets.only(left: 6),
    this.showDuration = const Duration(seconds: 8),
  }) : assert((message == null) != (richMessage == null));

  final String? message;
  final InlineSpan? richMessage;
  final IconData icon;
  final double size;
  final EdgeInsetsGeometry padding;
  final Duration showDuration;

  @override
  State<HelpHintIcon> createState() => _HelpHintIconState();
}

class _HelpHintIconState extends State<HelpHintIcon> {
  final GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final double buttonSize = widget.size + 12;
    return Padding(
      padding: widget.padding,
      child: Tooltip(
        key: _tooltipKey,
        message: widget.message,
        richMessage: widget.richMessage,
        triggerMode: TooltipTriggerMode.manual,
        waitDuration: Duration.zero,
        showDuration: widget.showDuration,
        child: IconButton(
          // Compact sizing keeps the IconButton hit target close to the
          // size of the previous bare icon. Default IconButton has a
          // 48dp tap target which would otherwise push other row items
          // around.
          iconSize: widget.size,
          style: IconButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
            padding: const EdgeInsets.all(4),
            minimumSize: Size(buttonSize, buttonSize),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          icon: Icon(widget.icon, size: widget.size),
          onPressed: () {
            _tooltipKey.currentState?.ensureTooltipVisible();
          },
        ),
      ),
    );
  }
}
