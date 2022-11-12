// Exposes functions used to save/load app settings

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

String obtainiumTempId = 'imranr98_obtainium_${GitHub().host}';
String obtainiumId = 'dev.imranr.obtainium';

enum ThemeSettings { system, light, dark }

enum ColourSettings { basic, materialYou }

enum SortColumnSettings { added, nameAuthor, authorName }

enum SortOrderSettings { ascending, descending }

const maxAPIRateLimitMinutes = 30;
const minUpdateIntervalMinutes = maxAPIRateLimitMinutes + 30;
const maxUpdateIntervalMinutes = 4320;
List<int> updateIntervals = [15, 30, 60, 120, 180, 360, 720, 1440, 4320, 0]
    .where((element) =>
        (element >= minUpdateIntervalMinutes &&
            element <= maxUpdateIntervalMinutes) ||
        element == 0)
    .toList();

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

  int get updateInterval {
    var min = prefs?.getInt('updateInterval') ?? 360;
    if (!updateIntervals.contains(min)) {
      var temp = updateIntervals[0];
      for (var i in updateIntervals) {
        if (min > i && i != 0) {
          temp = i;
        }
      }
      min = temp;
    }
    return min;
  }

  set updateInterval(int min) {
    prefs?.setInt('updateInterval', (min < 15 && min != 0) ? 15 : min);
    notifyListeners();
  }

  SortColumnSettings get sortColumn {
    return SortColumnSettings.values[
        prefs?.getInt('sortColumn') ?? SortColumnSettings.nameAuthor.index];
  }

  set sortColumn(SortColumnSettings s) {
    prefs?.setInt('sortColumn', s.index);
    notifyListeners();
  }

  SortOrderSettings get sortOrder {
    return SortOrderSettings.values[
        prefs?.getInt('sortOrder') ?? SortOrderSettings.ascending.index];
  }

  set sortOrder(SortOrderSettings s) {
    prefs?.setInt('sortOrder', s.index);
    notifyListeners();
  }

  bool checkAndFlipFirstRun() {
    bool result = prefs?.getBool('firstRun') ?? true;
    if (result) {
      prefs?.setBool('firstRun', false);
    }
    return result;
  }

  Future<void> getInstallPermission() async {
    while (!(await Permission.requestInstallPackages.isGranted)) {
      // Explicit request as InstallPlugin request sometimes bugged
      Fluttertoast.showToast(
          msg: 'Please allow Obtainium to install Apps',
          toastLength: Toast.LENGTH_LONG);
      if ((await Permission.requestInstallPackages.request()) ==
          PermissionStatus.granted) {
        break;
      }
    }
  }

  bool get showAppWebpage {
    return prefs?.getBool('showAppWebpage') ?? false;
  }

  set showAppWebpage(bool show) {
    prefs?.setBool('showAppWebpage', show);
    notifyListeners();
  }

  bool get pinUpdates {
    return prefs?.getBool('pinUpdates') ?? true;
  }

  set pinUpdates(bool show) {
    prefs?.setBool('pinUpdates', show);
    notifyListeners();
  }

  String? getSettingString(String settingId) {
    return prefs?.getString(settingId);
  }

  void setSettingString(String settingId, String value) {
    prefs?.setString(settingId, value);
    notifyListeners();
  }
}
