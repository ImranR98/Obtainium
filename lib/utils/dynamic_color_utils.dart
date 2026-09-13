// Builds full Material 3 color schemes from the Android OS core palette.

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

/// Converts the OS-provided core palette into a [ColorScheme] where every
/// role is resolved from the OS tonal palettes.
///
/// `dynamic_color`'s own conversion seeds the newer surface roles from the
/// primary color, which drifts their hue and chroma away from Android's
/// neutral palette and makes surfaces clash with the rest of the scheme.
ColorScheme corePaletteToColorScheme(
  // ignore: deprecated_member_use
  CorePalette palette, {
  Brightness brightness = Brightness.light,
}) {
  final scheme = DynamicScheme(
    // Only consulted by the fidelity/content variants; all palettes below are
    // provided directly by the OS.
    sourceColorHct: palette.primary.keyColor,
    variant: Variant.tonalSpot,
    isDark: brightness == Brightness.dark,
    primaryPalette: palette.primary,
    secondaryPalette: palette.secondary,
    tertiaryPalette: palette.tertiary,
    neutralPalette: palette.neutral,
    neutralVariantPalette: palette.neutralVariant,
  );

  // Start from a seed so roles added to ColorScheme in the future stay defined,
  // then override every current role with the OS-derived value.
  return ColorScheme.fromSeed(
    seedColor: Color(scheme.primary),
    brightness: brightness,
  ).copyWith(
    primary: Color(scheme.primary),
    onPrimary: Color(scheme.onPrimary),
    primaryContainer: Color(scheme.primaryContainer),
    onPrimaryContainer: Color(scheme.onPrimaryContainer),
    primaryFixed: Color(scheme.primaryFixed),
    primaryFixedDim: Color(scheme.primaryFixedDim),
    onPrimaryFixed: Color(scheme.onPrimaryFixed),
    onPrimaryFixedVariant: Color(scheme.onPrimaryFixedVariant),
    secondary: Color(scheme.secondary),
    onSecondary: Color(scheme.onSecondary),
    secondaryContainer: Color(scheme.secondaryContainer),
    onSecondaryContainer: Color(scheme.onSecondaryContainer),
    secondaryFixed: Color(scheme.secondaryFixed),
    secondaryFixedDim: Color(scheme.secondaryFixedDim),
    onSecondaryFixed: Color(scheme.onSecondaryFixed),
    onSecondaryFixedVariant: Color(scheme.onSecondaryFixedVariant),
    tertiary: Color(scheme.tertiary),
    onTertiary: Color(scheme.onTertiary),
    tertiaryContainer: Color(scheme.tertiaryContainer),
    onTertiaryContainer: Color(scheme.onTertiaryContainer),
    tertiaryFixed: Color(scheme.tertiaryFixed),
    tertiaryFixedDim: Color(scheme.tertiaryFixedDim),
    onTertiaryFixed: Color(scheme.onTertiaryFixed),
    onTertiaryFixedVariant: Color(scheme.onTertiaryFixedVariant),
    error: Color(scheme.error),
    onError: Color(scheme.onError),
    errorContainer: Color(scheme.errorContainer),
    onErrorContainer: Color(scheme.onErrorContainer),
    surface: Color(scheme.surface),
    onSurface: Color(scheme.onSurface),
    surfaceDim: Color(scheme.surfaceDim),
    surfaceBright: Color(scheme.surfaceBright),
    surfaceContainerLowest: Color(scheme.surfaceContainerLowest),
    surfaceContainerLow: Color(scheme.surfaceContainerLow),
    surfaceContainer: Color(scheme.surfaceContainer),
    surfaceContainerHigh: Color(scheme.surfaceContainerHigh),
    surfaceContainerHighest: Color(scheme.surfaceContainerHighest),
    onSurfaceVariant: Color(scheme.onSurfaceVariant),
    outline: Color(scheme.outline),
    outlineVariant: Color(scheme.outlineVariant),
    shadow: Color(scheme.shadow),
    scrim: Color(scheme.scrim),
    inverseSurface: Color(scheme.inverseSurface),
    onInverseSurface: Color(scheme.inverseOnSurface),
    inversePrimary: Color(scheme.inversePrimary),
    surfaceTint: Color(scheme.surfaceTint),
    // ignore: deprecated_member_use
    surfaceVariant: Color(scheme.surfaceVariant),
  );
}

/// Provides light and dark [ColorScheme]s from the OS core palette.
///
/// Mirrors `dynamic_color`'s [DynamicColorBuilder] but uses
/// [corePaletteToColorScheme] instead of the package's conversion, which
/// drifts surface roles away from Android's neutral palette.
class ObtainiumDynamicColorBuilder extends StatefulWidget {
  const ObtainiumDynamicColorBuilder({super.key, required this.builder});

  final Widget Function(ColorScheme? light, ColorScheme? dark) builder;

  @override
  State<ObtainiumDynamicColorBuilder> createState() =>
      _ObtainiumDynamicColorBuilderState();
}

class _ObtainiumDynamicColorBuilderState
    extends State<ObtainiumDynamicColorBuilder> {
  ColorScheme? _light;
  ColorScheme? _dark;

  @override
  void initState() {
    super.initState();
    _loadDynamicColors();
  }

  Future<void> _loadDynamicColors() async {
    try {
      // ignore: deprecated_member_use
      final corePalette = await DynamicColorPlugin.getCorePalette();
      if (!mounted) return;
      if (corePalette != null) {
        setState(() {
          _light = corePaletteToColorScheme(corePalette);
          _dark = corePaletteToColorScheme(
            corePalette,
            brightness: Brightness.dark,
          );
        });
        return;
      }
    } on PlatformException {
      // Dynamic color is unavailable; the caller falls back to a seeded scheme.
    }

    try {
      final accentColor = await DynamicColorPlugin.getAccentColor();
      if (!mounted) return;
      if (accentColor != null) {
        setState(() {
          _light = ColorScheme.fromSeed(
            seedColor: accentColor,
            brightness: Brightness.light,
          );
          _dark = ColorScheme.fromSeed(
            seedColor: accentColor,
            brightness: Brightness.dark,
          );
        });
      }
    } on PlatformException {
      // Dynamic color is unavailable; the caller falls back to a seeded scheme.
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(_light, _dark);
  }
}
