import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsProvider> _settingsWithPrefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final SettingsProvider settings = SettingsProvider();
  settings.prefs = await SharedPreferences.getInstance();
  return settings;
}

void main() {
  test(
    'saved custom seed hexes fall back when all stored values are invalid',
    () async {
      final SettingsProvider settings = await _settingsWithPrefs(
        <String, Object>{
          'activeCustomSeedHex': '#123456',
          'savedCustomSeedHexList': jsonEncode(<String>[
            'not-a-color',
            '#GGGGGG',
          ]),
        },
      );

      expect(settings.savedCustomSeedHexes, <String>['#123456']);
    },
  );

  test('saved custom seed hexes keep valid stored values', () async {
    final SettingsProvider settings = await _settingsWithPrefs(<String, Object>{
      'activeCustomSeedHex': '#123456',
      'savedCustomSeedHexList': jsonEncode(<String>['#ABCDEF', 'not-a-color']),
    });

    expect(settings.savedCustomSeedHexes, <String>['#ABCDEF']);
  });

  test('shading intensity defaults to current theme boost', () async {
    final SettingsProvider settings = await _settingsWithPrefs(
      <String, Object>{},
    );

    expect(settings.shadingIntensity, 1.0);
  });

  test('shading intensity is stepped and clamped', () async {
    final SettingsProvider settings = await _settingsWithPrefs(
      <String, Object>{},
    );

    settings.shadingIntensity = 2.35;
    expect(settings.shadingIntensity, 2.0);

    settings.shadingIntensity = 0.46;
    expect(settings.shadingIntensity, 0.5);
  });

  test('black theme only applies to an effectively dark theme', () async {
    final SettingsProvider settings = await _settingsWithPrefs(<String, Object>{
      'theme': ThemeSettings.system.index,
      'useBlackTheme': true,
      'useGradientBackground': true,
      'shadingIntensity': 0.4,
    });

    settings.updatePlatformBrightness(Brightness.light);
    expect(settings.blackThemeActive, isFalse);
    expect(settings.useGradientBackground, isTrue);
    expect(settings.shadingIntensity, 0.4);

    settings.updatePlatformBrightness(Brightness.dark);
    expect(settings.blackThemeActive, isTrue);
    expect(settings.useGradientBackground, isFalse);
    expect(settings.shadingIntensity, 1.0);
    expect(settings.prefs?.getBool('useGradientBackground'), isTrue);
    expect(settings.prefs?.getDouble('shadingIntensity'), 0.4);

    settings.updatePlatformBrightness(Brightness.light);
    expect(settings.blackThemeActive, isFalse);
    expect(settings.useGradientBackground, isTrue);
    expect(settings.shadingIntensity, 0.4);

    settings.theme = ThemeSettings.light;
    expect(settings.blackThemeActive, isFalse);

    settings.theme = ThemeSettings.dark;
    expect(settings.blackThemeActive, isTrue);
  });

  test(
    'active black theme only overrides surface styling temporarily',
    () async {
      final SettingsProvider settings =
          await _settingsWithPrefs(<String, Object>{
            'theme': ThemeSettings.dark.index,
            'useBlackTheme': false,
            'useGradientBackground': true,
            'shadingIntensity': 0.4,
          });

      settings.useBlackTheme = true;

      expect(settings.useGradientBackground, isFalse);
      expect(settings.shadingIntensity, 1.0);
      expect(settings.prefs?.getBool('useGradientBackground'), isTrue);
      expect(settings.prefs?.getDouble('shadingIntensity'), 0.4);

      settings.useBlackTheme = false;
      expect(settings.useGradientBackground, isTrue);
      expect(settings.shadingIntensity, 0.4);
    },
  );

  test('card corner scale defaults, steps, and clamps', () async {
    final SettingsProvider settings = await _settingsWithPrefs(
      <String, Object>{},
    );

    expect(settings.cardCornerScale, 1.0);

    settings.cardCornerScale = 1.23;
    expect(settings.cardCornerScale, 1.2);

    settings.cardCornerScale = 2.0;
    expect(settings.cardCornerScale, SettingsProvider.cardCornerScaleMax);

    settings.cardCornerScale = 0.1;
    expect(settings.cardCornerScale, SettingsProvider.cardCornerScaleMin);
  });

  test('categories are returned alphabetically sorted by key', () async {
    final SettingsProvider settings = await _settingsWithPrefs(<String, Object>{
      'categories': jsonEncode(<String, int>{'Zulu': 1, 'Alpha': 2, 'beta': 3}),
    });

    expect(settings.categories.keys.toList(), <String>[
      'Alpha',
      'beta',
      'Zulu',
    ]);
  });

  test('setCategories sorts input categories alphabetically', () async {
    final SettingsProvider settings = await _settingsWithPrefs(
      <String, Object>{},
    );
    settings.setCategories(<String, int>{'zulu': 1, 'Alpha': 2, 'Beta': 3});

    expect(settings.categories.keys.toList(), <String>[
      'Alpha',
      'Beta',
      'zulu',
    ]);
  });
}
