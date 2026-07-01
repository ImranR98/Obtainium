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

  final pillButtonStyle = ButtonStyle(
    shape: const WidgetStatePropertyAll(buttonShape),
    minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
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
    filledButtonTheme: FilledButtonThemeData(style: pillButtonStyle),
    elevatedButtonTheme: ElevatedButtonThemeData(style: pillButtonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: pillButtonStyle),
    textButtonTheme: TextButtonThemeData(
      style: const ButtonStyle(shape: WidgetStatePropertyAll(buttonShape)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
      ),
      menuStyle: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ),
    sliderTheme: SliderThemeData(
      // ignore: deprecated_member_use
      year2023: false, // TODO: remove when deprecated_member_use is resolved upstream
      activeTrackColor: colorScheme.primary,
      inactiveTrackColor: colorScheme.surfaceContainerHighest,
      thumbColor: colorScheme.primary,
      overlayColor: colorScheme.primary.withValues(alpha: 0.12),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      // ignore: deprecated_member_use
      year2023: false, // TODO: remove when deprecated_member_use is resolved upstream
    ),
  );
}
