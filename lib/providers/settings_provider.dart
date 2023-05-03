// Exposes functions used to save/load app settings

import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

String obtainiumTempId = 'imranr98_obtainium_${GitHub().host}';
String obtainiumId = 'dev.imranr.obtainium';

enum ThemeSettings { system, light, dark }

enum ColourSettings { basic, materialYou }

enum SortColumnSettings { added, nameAuthor, authorName, releaseDate }

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

  bool get useBlackTheme {
    return prefs?.getBool('useBlackTheme') ?? false;
  }

  set useBlackTheme(bool useBlackTheme) {
    prefs?.setBool('useBlackTheme', useBlackTheme);
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

  Future<bool> getInstallPermission({bool enforce = false}) async {
    while (!(await Permission.requestInstallPackages.isGranted)) {
      // Explicit request as InstallPlugin request sometimes bugged
      Fluttertoast.showToast(
          msg: tr('pleaseAllowInstallPerm'), toastLength: Toast.LENGTH_LONG);
      if ((await Permission.requestInstallPackages.request()) ==
          PermissionStatus.granted) {
        return true;
      }
      if (!enforce) {
        return false;
      }
    }
    return true;
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

  bool get groupByCategory {
    return prefs?.getBool('groupByCategory') ?? false;
  }

  set groupByCategory(bool show) {
    prefs?.setBool('groupByCategory', show);
    notifyListeners();
  }

  bool get hideTrackOnlyWarning {
    return prefs?.getBool('hideTrackOnlyWarning') ?? false;
  }

  set hideTrackOnlyWarning(bool show) {
    prefs?.setBool('hideTrackOnlyWarning', show);
    notifyListeners();
  }

  bool get hideAPKOriginWarning {
    return prefs?.getBool('hideAPKOriginWarning') ?? false;
  }

  set hideAPKOriginWarning(bool show) {
    prefs?.setBool('hideAPKOriginWarning', show);
    notifyListeners();
  }

  String? getSettingString(String settingId) {
    return prefs?.getString(settingId);
  }

  void setSettingString(String settingId, String value) {
    prefs?.setString(settingId, value);
    notifyListeners();
  }

  Map<String, int> get categories =>
      Map<String, int>.from(jsonDecode(prefs?.getString('categories') ?? '{}'));

  void setCategories(Map<String, int> cats, {AppsProvider? appsProvider}) {
    if (appsProvider != null) {
      List<App> changedApps = appsProvider
          .getAppValues()
          .map((a) {
            var n1 = a.app.categories.length;
            a.app.categories.removeWhere((c) => !cats.keys.contains(c));
            return n1 > a.app.categories.length ? a.app : null;
          })
          .where((element) => element != null)
          .map((e) => e as App)
          .toList();
      if (changedApps.isNotEmpty) {
        appsProvider.saveApps(changedApps);
      }
    }
    prefs?.setString('categories', jsonEncode(cats));
    notifyListeners();
  }

  String? get forcedLocale {
    var fl = prefs?.getString('forcedLocale');
    return supportedLocales
            .where((element) => element.key.toLanguageTag() == fl)
            .isNotEmpty
        ? fl
        : null;
  }

  set forcedLocale(String? fl) {
    if (fl == null) {
      prefs?.remove('forcedLocale');
    } else if (supportedLocales
        .where((element) => element.key.toLanguageTag() == fl)
        .isNotEmpty) {
      prefs?.setString('forcedLocale', fl);
    }
    notifyListeners();
  }

  bool setEqual(Set<String> a, Set<String> b) =>
      a.length == b.length && a.union(b).length == a.length;

  void resetLocaleSafe(BuildContext context) {
    if (context.supportedLocales
        .map((e) => e.languageCode)
        .contains(context.deviceLocale.languageCode)) {
      context.resetLocale();
    } else {
      context.setLocale(context.fallbackLocale!);
      context.deleteSaveLocale();
    }
  }
}
