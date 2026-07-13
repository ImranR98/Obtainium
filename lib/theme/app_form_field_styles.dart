import 'package:flutter/material.dart';

const EdgeInsetsGeometry appDropdownFieldContentPadding = EdgeInsets.symmetric(
  horizontal: 12,
  vertical: 10,
);

/// Rounded filled field style used on additional options and app edit screens.
InputDecoration appPageOutlinedInputDecoration(
  BuildContext context, {
  required String? labelText,
  String? hintText,
  bool isDense = false,
  double borderRadius = 12,
  bool showOutline = false,
}) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  final BorderRadius radius = BorderRadius.circular(borderRadius);
  final Color fieldFillColor = scheme.brightness == Brightness.light
      ? Color.alphaBlend(
          scheme.onSurface.withValues(alpha: 0.075),
          scheme.surfaceContainerHighest,
        )
      : Color.alphaBlend(
          scheme.primary.withValues(alpha: 0.045),
          scheme.surfaceContainerHighest,
        );
  final BorderSide enabledSide = showOutline
      ? BorderSide(color: scheme.outline.withValues(alpha: 0.55))
      : BorderSide.none;
  final BorderSide focusedSide = showOutline
      ? BorderSide(color: scheme.primary, width: 2)
      : BorderSide.none;
  final BorderSide errorSide = showOutline
      ? BorderSide(color: scheme.error)
      : BorderSide.none;
  final BorderSide focusedErrorSide = showOutline
      ? BorderSide(color: scheme.error, width: 2)
      : BorderSide.none;
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    floatingLabelBehavior: labelText == null
        ? FloatingLabelBehavior.never
        : FloatingLabelBehavior.auto,
    filled: true,
    fillColor: fieldFillColor,
    isDense: isDense,
    contentPadding: isDense
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: radius, borderSide: enabledSide),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: enabledSide,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: focusedSide,
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: errorSide,
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: focusedErrorSide,
    ),
  );
}

InputDecoration appPageDropdownInputDecoration(
  BuildContext context, {
  required String? labelText,
  double borderRadius = 12,
  bool showOutline = false,
}) {
  return appPageOutlinedInputDecoration(
    context,
    labelText: labelText,
    isDense: true,
    borderRadius: borderRadius,
    showOutline: showOutline,
  ).copyWith(contentPadding: appDropdownFieldContentPadding);
}
