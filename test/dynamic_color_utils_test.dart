// ignore_for_file: deprecated_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/utils/dynamic_color_utils.dart';

void main() {
  // Accent and neutral hues intentionally differ, like the wallpaper themes
  // where seeding surface roles from the primary color drifts them away from
  // the OS neutral palette (issue #3322).
  final palette = CorePalette.fromList([
    ...TonalPalette.of(340, 48).asList,
    ...TonalPalette.of(340, 16).asList,
    ...TonalPalette.of(40, 24).asList,
    ...TonalPalette.of(200, 16).asList,
    ...TonalPalette.of(200, 20).asList,
  ]);

  group('corePaletteToColorScheme light', () {
    final scheme = corePaletteToColorScheme(palette);

    test('resolves accent roles from the OS palettes', () {
      expect(scheme.primary, Color(palette.primary.get(40)));
      expect(scheme.onPrimary, Color(palette.primary.get(100)));
      expect(scheme.primaryContainer, Color(palette.primary.get(90)));
      expect(scheme.onPrimaryContainer, Color(palette.primary.get(30)));
      expect(scheme.secondary, Color(palette.secondary.get(40)));
      expect(scheme.onSecondary, Color(palette.secondary.get(100)));
      expect(scheme.tertiary, Color(palette.tertiary.get(40)));
      expect(scheme.error, Color(palette.error.get(40)));
    });

    test('resolves fixed roles from the OS palettes', () {
      expect(scheme.primaryFixed, Color(palette.primary.get(90)));
      expect(scheme.primaryFixedDim, Color(palette.primary.get(80)));
      expect(scheme.onPrimaryFixed, Color(palette.primary.get(10)));
      expect(scheme.onPrimaryFixedVariant, Color(palette.primary.get(30)));
      expect(scheme.secondaryFixed, Color(palette.secondary.get(90)));
      expect(scheme.tertiaryFixed, Color(palette.tertiary.get(90)));
    });

    test('resolves surface roles from the OS neutral palette', () {
      expect(scheme.surface, Color(palette.neutral.get(98)));
      expect(scheme.onSurface, Color(palette.neutral.get(10)));
      expect(scheme.surfaceDim, Color(palette.neutral.get(87)));
      expect(scheme.surfaceBright, Color(palette.neutral.get(98)));
      expect(scheme.surfaceContainerLowest, Color(palette.neutral.get(100)));
      expect(scheme.surfaceContainerLow, Color(palette.neutral.get(96)));
      expect(scheme.surfaceContainer, Color(palette.neutral.get(94)));
      expect(scheme.surfaceContainerHigh, Color(palette.neutral.get(92)));
      expect(scheme.surfaceContainerHighest, Color(palette.neutral.get(90)));
      expect(scheme.onSurfaceVariant, Color(palette.neutralVariant.get(30)));
    });

    test('does not seed surface roles from the primary color', () {
      final seeded = ColorScheme.fromSeed(
        seedColor: Color(palette.primary.get(40)),
      );
      expect(scheme.surfaceContainerLow, isNot(seeded.surfaceContainerLow));
      expect(scheme.surface, isNot(seeded.surface));
      final hue = Hct.fromInt(scheme.surfaceContainerLow.toARGB32()).hue;
      expect((hue - 200).abs(), lessThan(5));
    });
  });

  group('corePaletteToColorScheme dark', () {
    final scheme = corePaletteToColorScheme(
      palette,
      brightness: Brightness.dark,
    );

    test('resolves accent roles from the OS palettes', () {
      expect(scheme.primary, Color(palette.primary.get(80)));
      expect(scheme.onPrimary, Color(palette.primary.get(20)));
      expect(scheme.primaryContainer, Color(palette.primary.get(30)));
      expect(scheme.onPrimaryContainer, Color(palette.primary.get(90)));
      expect(scheme.secondary, Color(palette.secondary.get(80)));
      expect(scheme.onSecondary, Color(palette.secondary.get(20)));
      expect(scheme.tertiary, Color(palette.tertiary.get(80)));
      expect(scheme.error, Color(palette.error.get(80)));
    });

    test('resolves fixed roles from the OS palettes', () {
      expect(scheme.primaryFixed, Color(palette.primary.get(90)));
      expect(scheme.primaryFixedDim, Color(palette.primary.get(80)));
      expect(scheme.onPrimaryFixed, Color(palette.primary.get(10)));
      expect(scheme.onPrimaryFixedVariant, Color(palette.primary.get(30)));
      expect(scheme.secondaryFixed, Color(palette.secondary.get(90)));
      expect(scheme.tertiaryFixed, Color(palette.tertiary.get(90)));
    });

    test('resolves surface roles from the OS neutral palette', () {
      expect(scheme.surface, Color(palette.neutral.get(6)));
      expect(scheme.onSurface, Color(palette.neutral.get(90)));
      expect(scheme.surfaceDim, Color(palette.neutral.get(6)));
      expect(scheme.surfaceBright, Color(palette.neutral.get(24)));
      expect(scheme.surfaceContainerLowest, Color(palette.neutral.get(4)));
      expect(scheme.surfaceContainerLow, Color(palette.neutral.get(10)));
      expect(scheme.surfaceContainer, Color(palette.neutral.get(12)));
      expect(scheme.surfaceContainerHigh, Color(palette.neutral.get(17)));
      expect(scheme.surfaceContainerHighest, Color(palette.neutral.get(22)));
      expect(scheme.onSurfaceVariant, Color(palette.neutralVariant.get(80)));
    });

    test('does not seed surface roles from the primary color', () {
      final seeded = ColorScheme.fromSeed(
        seedColor: Color(palette.primary.get(80)),
        brightness: Brightness.dark,
      );
      expect(scheme.surfaceContainerLow, isNot(seeded.surfaceContainerLow));
      expect(scheme.surface, isNot(seeded.surface));
      final hue = Hct.fromInt(scheme.surfaceContainerLow.toARGB32()).hue;
      expect((hue - 200).abs(), lessThan(5));
    });
  });
}
