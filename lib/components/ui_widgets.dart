import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Renders an app's icon as a Material 3 Expressive squircle, falling back to
/// the Obtainium glyph on a tonal surface when no icon is available. Centralizes
/// the icon/placeholder rendering shared by the app list and the app detail page.
class AppIcon extends StatelessWidget {
  final Uint8List? bytes;
  final double size;
  final double radius;

  /// Size of the fallback glyph shown when [bytes] is null.
  final double glyphSize;

  /// Dims the icon (e.g. to mark an app as not installed).
  final bool dimmed;

  const AppIcon({
    super.key,
    required this.bytes,
    required this.size,
    this.radius = 12,
    this.glyphSize = 24,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: bytes != null
            ? Image.memory(
                bytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                opacity: dimmed ? const AlwaysStoppedAnimation(0.6) : null,
              )
            : ColoredBox(
                color: colorScheme.surfaceContainerHighest,
                child: Center(
                  child: Image(
                    image: const AssetImage('assets/graphics/icon_small.png'),
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.4),
                    colorBlendMode: BlendMode.modulate,
                    gaplessPlayback: true,
                    width: glyphSize,
                    height: glyphSize,
                  ),
                ),
              ),
      ),
    );
  }
}

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
