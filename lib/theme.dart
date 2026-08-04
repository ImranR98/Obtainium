// Builds the Material 3 Expressive theme for the app.

import 'package:flutter/material.dart';

/// Builds the app-wide Material 3 Expressive [ThemeData] for a given
/// [colorScheme]. Expressive character lives here (large rounded shapes,
/// emphasized motion, updated M3 component looks) so it propagates to every
/// screen without per-widget styling.
ThemeData buildObtainiumTheme(ColorScheme colorScheme, String fontFamily) {
  final cardShape = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(24),
  );
  const buttonShape = StadiumBorder();
  final dialogShape = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(28),
  );
  final fieldShape = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(16),
  );

  const pillButtonStyle = ButtonStyle(
    shape: WidgetStatePropertyAll(buttonShape),
    minimumSize: WidgetStatePropertyAll(Size(0, 48)),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: fontFamily,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    cardTheme: CardThemeData(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: cardShape,
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(shape: dialogShape),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    appBarTheme: const AppBarThemeData(centerTitle: false),
    expansionTileTheme: ExpansionTileThemeData(
      shape: cardShape,
      collapsedShape: cardShape,
    ),
    listTileTheme: ListTileThemeData(shape: fieldShape),
    chipTheme: const ChipThemeData(shape: StadiumBorder()),
    searchBarTheme: const SearchBarThemeData(
      elevation: WidgetStatePropertyAll(0),
    ),
    filledButtonTheme: const FilledButtonThemeData(style: pillButtonStyle),
    elevatedButtonTheme: const ElevatedButtonThemeData(style: pillButtonStyle),
    outlinedButtonTheme: const OutlinedButtonThemeData(style: pillButtonStyle),
    textButtonTheme: const TextButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(buttonShape)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(20)),
      // FAB shadow depth. Tweak these to try different values (M3 default is 6).
      // `elevation` is the resting shadow; the others apply on interaction.
      elevation: 4,
      focusElevation: 6,
      hoverElevation: 8,
      highlightElevation: 6,
    ),
    inputDecorationTheme: const InputDecorationThemeData(
      filled: true,
      fillColor: null,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: const InputDecorationThemeData(
        filled: true,
        fillColor: null,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
      ),
      menuStyle: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ),
    sliderTheme: SliderThemeData(
      // `year2023: false` opts these components into the updated Material 3
      // appearance. The flag is deprecated by Flutter and will be removed once
      // the new look becomes the framework default, at which point these lines
      // (and the `ignore` directives) can simply be deleted with no visual
      // change. There is no replacement API to migrate to in the meantime.
      // Tracking: https://github.com/flutter/flutter/issues/162186
      // ignore: deprecated_member_use
      year2023: false,
      activeTrackColor: colorScheme.primary,
      inactiveTrackColor: colorScheme.surfaceContainerHighest,
      thumbColor: colorScheme.primary,
      overlayColor: colorScheme.primary.withValues(alpha: 0.12),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      // See the note on `sliderTheme.year2023` above; no replacement API exists
      // and this can be removed once the M3 look is the framework default.
      // Tracking: https://github.com/flutter/flutter/issues/162186
      // ignore: deprecated_member_use
      year2023: false,
    ),
  );
}

/// Corner radius for the outer corners of a connected tile run.
const double connectedTileBigRadius = 24;

/// Corner radius for the inner (joined) corners of a connected tile run.
const double connectedTileSmallRadius = 6;

BorderRadius positionalTileRadius({
  required bool isFirst,
  required bool isLast,
}) {
  return BorderRadius.vertical(
    top: Radius.circular(
      isFirst ? connectedTileBigRadius : connectedTileSmallRadius,
    ),
    bottom: Radius.circular(
      isLast ? connectedTileBigRadius : connectedTileSmallRadius,
    ),
  );
}

RoundedSuperellipseBorder positionalTileShape({
  required bool isFirst,
  required bool isLast,
}) => RoundedSuperellipseBorder(
  borderRadius: positionalTileRadius(isFirst: isFirst, isLast: isLast),
);

abstract final class ExpressiveMotion {
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  static const Duration short = Durations.short4;
  static const Duration medium = Durations.medium2;
}
