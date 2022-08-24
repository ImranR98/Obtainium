import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeSettings { system, light, dark }

enum ColourSettings { basic, materialYou }

class SettingsProvider with ChangeNotifier {
  SharedPreferences? prefs;

  String sourceUrl = 'https://github.com/ImranR98/Obtainium';

  // Not done in constructor as we want to be able to await it
  Future<void> initializeSettings() async {
    prefs = await SharedPreferences.getInstance();
    notifyListeners();
  }

  ThemeSettings get theme {
    return ThemeSettings
        .values[prefs?.getInt('theme') ?? ThemeSettings.system.index];
  }

  set theme(ThemeSettings t) {
    print(t);
    prefs?.setInt('theme', t.index);
    notifyListeners();
  }

  ColourSettings get colour {
    return ColourSettings
        .values[prefs?.getInt('colour') ?? ColourSettings.basic.index];
  }

  set colour(ColourSettings t) {
    prefs?.setInt('colour', t.index);
    notifyListeners();
  }

  checkAndFlipFirstRun() {
    bool result = prefs?.getBool('firstRun') ?? true;
    if (result) {
      prefs?.setBool('firstRun', false);
    }
    return result;
  }
}
