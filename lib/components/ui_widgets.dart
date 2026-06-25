import 'package:flutter/material.dart';

/// A text-style action that becomes a visible tonal button when the user has
/// enabled the "highlight touch targets" accessibility option, and a subtle
/// text button otherwise. Replaces the app's hand-built `InkWell` + tinted
/// `Container` link pattern with standard Material 3 buttons.
class HighlightableButton extends StatelessWidget {
  final bool highlight;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final Widget? icon;
  final Widget label;

  const HighlightableButton({
    super.key,
    required this.highlight,
    required this.onPressed,
    this.onLongPress,
    this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (icon != null) {
      return highlight
          ? FilledButton.tonalIcon(
              onPressed: onPressed,
              onLongPress: onLongPress,
              icon: icon!,
              label: label,
            )
          : TextButton.icon(
              onPressed: onPressed,
              onLongPress: onLongPress,
              icon: icon!,
              label: label,
            );
    }
    return highlight
        ? FilledButton.tonal(
            onPressed: onPressed,
            onLongPress: onLongPress,
            child: label,
          )
        : TextButton(
            onPressed: onPressed,
            onLongPress: onLongPress,
            child: label,
          );
  }
}
