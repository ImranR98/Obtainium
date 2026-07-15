import 'package:flutter/material.dart';

/// Mirrors FilePipe [AppColorSource] for accent / seed selection.
enum AppAccentColorSource {
  appDefault,
  materialYou,
  custom,
  presetSapphire,
  presetEmerald,
  presetAmber,
  presetViolet,
  presetCoral,
  presetTeal,
  presetLime,
  presetRose,
  presetSlate,
}

extension AppAccentColorSourceX on AppAccentColorSource {
  static AppAccentColorSource? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final AppAccentColorSource value in AppAccentColorSource.values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  /// Seed used with [ColorScheme.fromSeed]; null for [materialYou] (use dynamic).
  Color? get seedOrNull {
    switch (this) {
      case AppAccentColorSource.appDefault:
        return const Color(0xFF1B5EA8);
      case AppAccentColorSource.materialYou:
        return null;
      case AppAccentColorSource.custom:
        return null;
      case AppAccentColorSource.presetSapphire:
        return const Color(0xFF1565C0);
      case AppAccentColorSource.presetEmerald:
        return const Color(0xFF2E7D32);
      case AppAccentColorSource.presetAmber:
        return const Color(0xFFFF8F00);
      case AppAccentColorSource.presetViolet:
        return const Color(0xFF7B1FA2);
      case AppAccentColorSource.presetCoral:
        return const Color(0xFFE53935);
      case AppAccentColorSource.presetTeal:
        return const Color(0xFF00796B);
      case AppAccentColorSource.presetLime:
        return const Color(0xFFAFB42B);
      case AppAccentColorSource.presetRose:
        return const Color(0xFFE91E63);
      case AppAccentColorSource.presetSlate:
        return const Color(0xFF546E7A);
    }
  }

  bool get isSeedBased => this != AppAccentColorSource.materialYou;

  static const List<AppAccentColorSource> accentPickerOrder = [
    AppAccentColorSource.materialYou,
    AppAccentColorSource.appDefault,
    AppAccentColorSource.presetEmerald,
    AppAccentColorSource.presetAmber,
    AppAccentColorSource.presetViolet,
    AppAccentColorSource.presetCoral,
    AppAccentColorSource.presetTeal,
    AppAccentColorSource.presetLime,
    AppAccentColorSource.presetRose,
    AppAccentColorSource.presetSlate,
  ];
}

/// Maps to [DynamicSchemeVariant] for [ColorScheme.fromSeed].
enum AppThemePaletteStyle {
  tonalSpot,
  neutral,
  vibrant,
  expressive,
  rainbow,
  fruitSalad,
  monochrome,
  fidelity,
  content,
}

extension AppThemePaletteStyleX on AppThemePaletteStyle {
  DynamicSchemeVariant get dynamicVariant {
    switch (this) {
      case AppThemePaletteStyle.tonalSpot:
        return DynamicSchemeVariant.tonalSpot;
      case AppThemePaletteStyle.neutral:
        return DynamicSchemeVariant.neutral;
      case AppThemePaletteStyle.vibrant:
        return DynamicSchemeVariant.vibrant;
      case AppThemePaletteStyle.expressive:
        return DynamicSchemeVariant.expressive;
      case AppThemePaletteStyle.rainbow:
        return DynamicSchemeVariant.rainbow;
      case AppThemePaletteStyle.fruitSalad:
        return DynamicSchemeVariant.fruitSalad;
      case AppThemePaletteStyle.monochrome:
        return DynamicSchemeVariant.monochrome;
      case AppThemePaletteStyle.fidelity:
        return DynamicSchemeVariant.fidelity;
      case AppThemePaletteStyle.content:
        return DynamicSchemeVariant.content;
    }
  }

  static AppThemePaletteStyle? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final AppThemePaletteStyle value in AppThemePaletteStyle.values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  static List<AppThemePaletteStyle> get all => AppThemePaletteStyle.values;
}

String? normalizeCustomSeedHexOrNull(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  String hex = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  if (hex.length == 3) {
    hex = hex.split('').map((String c) => '$c$c').join();
  }
  if (hex.length != 6) return null;
  final int? parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return null;
  return '#${hex.toUpperCase()}';
}

Color? colorFromNormalizedHex(String? normalizedHex) {
  if (normalizedHex == null || normalizedHex.length != 7) return null;
  final int? rgb = int.tryParse(normalizedHex.substring(1), radix: 16);
  if (rgb == null) return null;
  return Color(0xFF000000 | rgb);
}

String colorToCanonicalHex(Color color) {
  final int rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

extension ColorSchemeBoost on ColorScheme {
  ColorScheme boostSurfaceContainersTowardPrimary({
    required bool darkTheme,
    required bool useGradient,
    required double shadingIntensity,
  }) {
    final double intensity = shadingIntensity.clamp(0.0, 2.0);
    if (intensity <= 0.0) return this;

    final Color accent;
    final double containerAmount;
    final double surfaceAmount;

    if (useGradient) {
      accent = primary;
      containerAmount = darkTheme ? 0.20 : 0.12;
      surfaceAmount = 0.0;
    } else if (darkTheme) {
      // Dark mode: boost toward `inversePrimary` (dark, saturated version of the
      // hue) so containers gain vivid colour without being lifted toward white.
      // Surface gets a small boost only — preserves the luminance gap between
      // page background and cards (critical for Material You neutral palettes
      // where all tones share the same hue).
      accent = inversePrimary;
      containerAmount = 0.42;
      surfaceAmount = 0.12;
    } else {
      accent = Color.lerp(primary, primaryContainer, 0.12)!;
      containerAmount = 0.26;
      surfaceAmount = 0.26;
    }

    Color tintC(Color base) {
      return Color.lerp(base, accent, containerAmount * intensity)!;
    }

    Color tintS(Color base) {
      return Color.lerp(base, accent, surfaceAmount * intensity)!;
    }

    ColorScheme result = copyWith(
      surface: useGradient ? surface : tintS(surface),
      surfaceContainerLowest: tintC(surfaceContainerLowest),
      surfaceContainerLow: tintC(surfaceContainerLow),
      surfaceContainer: tintC(surfaceContainer),
      surfaceContainerHigh: tintC(surfaceContainerHigh),
      surfaceContainerHighest: tintC(surfaceContainerHighest),
    );

    // In dark mode, neutral palettes can collapse the tonal spread so cards match
    // the page background. Prefer darkening the background toward black (keeps card
    // chroma); if the surface is already near black (OLED), nudge cards toward a
    // primary-tinted highlight instead of bleaching toward white.
    if (darkTheme) {
      const double minDelta = 0.06;
      double backgroundLum = result.surface.computeLuminance();
      double cardHighLum = result.surfaceContainerHighest.computeLuminance();
      double deficit = minDelta - (cardHighLum - backgroundLum);
      if (deficit > 0) {
        final double darkenSurfaceMix = (deficit * 2.0).clamp(0.0, 0.14);
        result = result.copyWith(
          surface: Color.lerp(result.surface, Colors.black, darkenSurfaceMix)!,
          surfaceContainerLowest: Color.lerp(
            result.surfaceContainerLowest,
            Colors.black,
            darkenSurfaceMix * 0.9,
          )!,
        );
        backgroundLum = result.surface.computeLuminance();
        cardHighLum = result.surfaceContainerHighest.computeLuminance();
        deficit = minDelta - (cardHighLum - backgroundLum);
        if (deficit > 0) {
          final Color chromaticLift = Color.lerp(
            result.surfaceBright,
            result.primary,
            0.12,
          )!;
          final double liftMix = (deficit * 1.2).clamp(0.0, 0.22);
          result = result.copyWith(
            surfaceContainerHigh: Color.lerp(
              result.surfaceContainerHigh,
              chromaticLift,
              liftMix * 0.85,
            )!,
            surfaceContainerHighest: Color.lerp(
              result.surfaceContainerHighest,
              chromaticLift,
              liftMix,
            )!,
          );
        }
      }
    }

    return result;
  }

  ColorScheme boostContainersForSeedThemes({required bool darkTheme}) {
    final double primaryBlend = darkTheme ? 0.30 : 0.24;
    final double secondaryBlend = darkTheme ? 0.26 : 0.20;
    final double tertiaryBlend = darkTheme ? 0.28 : 0.22;

    return copyWith(
      primaryContainer: Color.lerp(primaryContainer, primary, primaryBlend),
      secondaryContainer: Color.lerp(
        secondaryContainer,
        secondary,
        secondaryBlend,
      ),
      tertiaryContainer: Color.lerp(tertiaryContainer, tertiary, tertiaryBlend),
    );
  }
}

extension ColorSchemeBlackTheme on ColorScheme {
  bool get usesPureBlackBackgrounds {
    return surface.toARGB32() == Colors.black.toARGB32() &&
        surfaceContainer.toARGB32() == Colors.black.toARGB32() &&
        surfaceContainerHighest.toARGB32() == Colors.black.toARGB32();
  }

  ColorScheme withPureBlackBackgrounds() {
    const Color blackBackground = Colors.black;
    return copyWith(
      surface: blackBackground,
      surfaceDim: blackBackground,
      surfaceBright: blackBackground,
      surfaceContainerLowest: blackBackground,
      surfaceContainerLow: blackBackground,
      surfaceContainer: blackBackground,
      surfaceContainerHigh: blackBackground,
      surfaceContainerHighest: blackBackground,
      surfaceTint: Colors.transparent,
      shadow: blackBackground,
      scrim: blackBackground,
    );
  }
}

/// Page gradients and toolbar scrims: blend [primary] (not [primaryContainer]) at
/// modest alpha so backgrounds keep hue without chalky pastels.
extension ColorSchemePageScrims on ColorScheme {
  Color get schemePageGradientTopColor {
    if (usesPureBlackBackgrounds) return Colors.black;
    final double topAlpha = brightness == Brightness.dark ? 0.22 : 0.16;
    return Color.alphaBlend(primary.withValues(alpha: topAlpha), surface);
  }

  Color get schemePageGradientMidColor {
    if (usesPureBlackBackgrounds) return Colors.black;
    final double midAlpha = brightness == Brightness.dark ? 0.12 : 0.08;
    return Color.alphaBlend(primary.withValues(alpha: midAlpha), surface);
  }

  Color get schemeToolbarScrimBase {
    if (usesPureBlackBackgrounds) return Colors.black;
    final double primaryAlpha = brightness == Brightness.dark ? 0.26 : 0.18;
    return Color.alphaBlend(primary.withValues(alpha: primaryAlpha), surface);
  }

  /// Translucent tint for progressive edge blur: low-alpha [surface] so chrome
  /// (app bar, nav bar) reads like the page background, not elevated cards.
  Color get schemeProgressiveBlurOverlayTint {
    final double alpha = brightness == Brightness.dark ? 0.34 : 0.30;
    return surface.withValues(alpha: alpha);
  }

  /// The standard full-page background gradient (top tint → mid tint → surface).
  /// Single source of truth for the ~dozen page/pane backgrounds that used to
  /// inline this identical gradient, so they can't drift apart.
  LinearGradient get schemePageBackgroundGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: const [0, 0.38, 0.72, 1],
    colors: [
      schemePageGradientTopColor,
      schemePageGradientMidColor,
      surface,
      surface,
    ],
  );
}

ColorScheme colorSchemeForAccentSettings({
  required Brightness brightness,
  required AppAccentColorSource accentSource,
  required AppThemePaletteStyle paletteStyle,
  required ColorScheme? lightDynamic,
  required ColorScheme? darkDynamic,
  required String activeCustomSeedHex,
}) {
  final ColorScheme? dynamicScheme = brightness == Brightness.light
      ? lightDynamic
      : darkDynamic;
  final bool dynamicAvailable = dynamicScheme != null;
  if (accentSource == AppAccentColorSource.materialYou && dynamicAvailable) {
    return dynamicScheme;
  }

  const Color fallbackSeed = Color(0xFF1B5EA8);
  Color seed =
      accentSource.seedOrNull ??
      colorFromNormalizedHex(
        normalizeCustomSeedHexOrNull(activeCustomSeedHex),
      ) ??
      fallbackSeed;
  if (accentSource == AppAccentColorSource.custom) {
    seed =
        colorFromNormalizedHex(
          normalizeCustomSeedHexOrNull(activeCustomSeedHex),
        ) ??
        fallbackSeed;
  }
  if (accentSource == AppAccentColorSource.materialYou && !dynamicAvailable) {
    seed = fallbackSeed;
  }

  return ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: paletteStyle.dynamicVariant,
  );
}
