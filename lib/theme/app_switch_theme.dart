import 'package:flutter/material.dart';

SwitchThemeData appSwitchTheme(ColorScheme colorScheme) {
  final Color enabledOffAccent = Color.lerp(
    colorScheme.onSurfaceVariant,
    colorScheme.primary,
    colorScheme.brightness == Brightness.dark ? 0.42 : 0.50,
  )!;
  final Color enabledOffTrack = Color.alphaBlend(
    enabledOffAccent.withValues(
      alpha: colorScheme.brightness == Brightness.dark ? 0.22 : 0.16,
    ),
    colorScheme.surfaceContainerHighest,
  );

  return SwitchThemeData(
    thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
      if (states.contains(WidgetState.selected)) {
        return Icon(Icons.check_rounded, color: colorScheme.primary, size: 16);
      }
      return null;
    }),
    thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled) ||
          states.contains(WidgetState.selected)) {
        return null;
      }
      return enabledOffAccent;
    }),
    trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled) ||
          states.contains(WidgetState.selected)) {
        return null;
      }
      return enabledOffTrack;
    }),
    trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) {
        return null;
      }
      return Colors.transparent;
    }),
    trackOutlineWidth: WidgetStateProperty.resolveWith<double?>((states) {
      if (states.contains(WidgetState.disabled)) {
        return null;
      }
      return 0;
    }),
  );
}
