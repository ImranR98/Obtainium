// Exposes functions used to save/load app settings

import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_storage/shared_storage.dart' as saf;

String obtainiumTempId = 'imranr98_obtainium_${GitHub().hosts[0]}';
String obtainiumId = 'dev.imranr.obtainium';
String obtainiumUrl = 'https://github.com/ImranR98/Obtainium';
Color obtainiumThemeColor = const Color(0xFF6438B5);

enum ThemeSettings { system, light, dark }

enum SortColumnSettings { added, nameAuthor, authorName, releaseDate }

enum SortOrderSettings { ascending, descending }

class SettingsProvider with ChangeNotifier {
  SharedPreferences? prefs;
  String? defaultAppDir;
  bool justStarted = true;

  String sourceUrl = 'https://github.com/ImranR98/Obtainium';

  // Not done in constructor as we want to be able to await it
  Future<void> initializeSettings() async {
    prefs = await SharedPreferences.getInstance();
    defaultAppDir = (await getExternalStorageDirectory())!.path;
    notifyListeners();
  }

  bool get useSystemFont {
    return prefs?.getBool('useSystemFont') ?? false;
  }

  set useSystemFont(bool useSystemFont) {
    prefs?.setBool('useSystemFont', useSystemFont);
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
    notifyListeners();
  }

  bool get useShizuku {
    return prefs?.getBool('useShizuku') ?? false;
  }

  set useShizuku(bool useShizuku) {
    prefs?.setBool('useShizuku', useShizuku);
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
    notifyListeners();
  }

  ThemeSettings get theme {
    return ThemeSettings
        .values[prefs?.getInt('theme') ?? ThemeSettings.system.index];
  }

  set theme(ThemeSettings t) {
    prefs?.setInt('theme', t.index);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  Color get themeColor {
    int? colorCode = prefs?.getInt('themeColor');
    return (colorCode != null) ? Color(colorCode) : obtainiumThemeColor;
  }

  set themeColor(Color themeColor) {
    prefs?.setInt('themeColor', themeColor.value);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get useMaterialYou {
    return prefs?.getBool('useMaterialYou') ?? false;
  }

  set useMaterialYou(bool useMaterialYou) {
    prefs?.setBool('useMaterialYou', useMaterialYou);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get useBlackTheme {
    return prefs?.getBool('useBlackTheme') ?? false;
  }

  set useBlackTheme(bool useBlackTheme) {
    prefs?.setBool('useBlackTheme', useBlackTheme);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  int get updateInterval {
    return prefs?.getInt('updateInterval') ?? 360;
  }

  set updateInterval(int min) {
    prefs?.setInt('updateInterval', min);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  double get updateIntervalSliderVal {
    return prefs?.getDouble('updateIntervalSliderVal') ?? 6.0;
  }

  set updateIntervalSliderVal(double val) {
    prefs?.setDouble('updateIntervalSliderVal', val);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get sxncdEnabled {
    return prefs?.getBool('sxncdEnabled') ?? false;
  }

  set sxncdEnabled(bool sxncdEnabled) {
    prefs?.setBool('sxncdEnabled', sxncdEnabled);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  String get sxncdSavedTs {
    return prefs?.getString('sxncdSavedTs') ?? '1900-01-01T00:00:00.000';
  }

  set sxncdSavedTs(String sxncdSavedTs) {
    prefs?.setString('sxncdSavedTs', sxncdSavedTs);
    notifyListeners();
  }

  String get sxncdUrl {
    return prefs?.getString('sxncdUrl') ?? '';
  }

  set sxncdUrl(String sxncdUrl) {
    prefs?.setString('sxncdUrl', sxncdUrl);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  String get sxncdApiKey {
    return prefs?.getString('sxncdApiKey') ?? '';
  }

  set sxncdApiKey(String sxncdApiKey) {
    prefs?.setString('sxncdApiKey', sxncdApiKey);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  String get sxncdDeviceName {
    return prefs?.getString('sxncdDeviceName') ?? '';
  }

  set sxncdDeviceName(String sxncdDeviceName) {
    prefs?.setString('sxncdDeviceName', sxncdDeviceName);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  String get sxncdEncryptionPassword {
    return prefs?.getString('sxncdEncryptionPassword') ?? '';
  }

  set sxncdEncryptionPassword(String sxncdEncryptionPassword) {
    prefs?.setString('sxncdEncryptionPassword', sxncdEncryptionPassword);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get checkOnStart {
    return prefs?.getBool('checkOnStart') ?? false;
  }

  set checkOnStart(bool checkOnStart) {
    prefs?.setBool('checkOnStart', checkOnStart);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  SortColumnSettings get sortColumn {
    return SortColumnSettings.values[
        prefs?.getInt('sortColumn') ?? SortColumnSettings.nameAuthor.index];
  }

  set sortColumn(SortColumnSettings s) {
    prefs?.setInt('sortColumn', s.index);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  SortOrderSettings get sortOrder {
    return SortOrderSettings.values[
        prefs?.getInt('sortOrder') ?? SortOrderSettings.ascending.index];
  }

  set sortOrder(SortOrderSettings s) {
    prefs?.setInt('sortOrder', s.index);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool checkAndFlipFirstRun() {
    bool result = prefs?.getBool('firstRun') ?? true;
    if (result) {
      prefs?.setBool('firstRun', false);
    }
    return result;
  }

  bool checkJustStarted() {
    if (justStarted) {
      justStarted = false;
      return true;
    }
    return false;
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
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get pinUpdates {
    return prefs?.getBool('pinUpdates') ?? true;
  }

  set pinUpdates(bool show) {
    prefs?.setBool('pinUpdates', show);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get buryNonInstalled {
    return prefs?.getBool('buryNonInstalled') ?? false;
  }

  set buryNonInstalled(bool show) {
    prefs?.setBool('buryNonInstalled', show);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get groupByCategory {
    return prefs?.getBool('groupByCategory') ?? false;
  }

  set groupByCategory(bool show) {
    prefs?.setBool('groupByCategory', show);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get hideTrackOnlyWarning {
    return prefs?.getBool('hideTrackOnlyWarning') ?? false;
  }

  set hideTrackOnlyWarning(bool show) {
    prefs?.setBool('hideTrackOnlyWarning', show);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get hideAPKOriginWarning {
    return prefs?.getBool('hideAPKOriginWarning') ?? false;
  }

  set hideAPKOriginWarning(bool show) {
    prefs?.setBool('hideAPKOriginWarning', show);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  String? getSettingString(String settingId) {
    String? str = prefs?.getString(settingId);
    return str?.isNotEmpty == true ? str : null;
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

  Locale? get forcedLocale {
    var flSegs = prefs?.getString('forcedLocale')?.split('-');
    var fl = flSegs != null && flSegs.isNotEmpty
        ? Locale(flSegs[0], flSegs.length > 1 ? flSegs[1] : null)
        : null;
    var set = supportedLocales.where((element) => element.key == fl).isNotEmpty
        ? fl
        : null;
    return set;
  }

  set forcedLocale(Locale? fl) {
    if (fl == null) {
      prefs?.remove('forcedLocale');
    } else if (supportedLocales
        .where((element) => element.key == fl)
        .isNotEmpty) {
      prefs?.setString('forcedLocale', fl.toLanguageTag());
    }
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool setEqual(Set<String> a, Set<String> b) =>
      a.length == b.length && a.union(b).length == a.length;

  void resetLocaleSafe(BuildContext context) {
    if (context.supportedLocales.contains(context.deviceLocale)) {
      context.resetLocale();
    } else {
      context.setLocale(context.fallbackLocale!);
      context.deleteSaveLocale();
    }
  }

  bool get removeOnExternalUninstall {
    return prefs?.getBool('removeOnExternalUninstall') ?? false;
  }

  set removeOnExternalUninstall(bool show) {
    prefs?.setBool('removeOnExternalUninstall', show);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get checkUpdateOnDetailPage {
    return prefs?.getBool('checkUpdateOnDetailPage') ?? true;
  }

  set checkUpdateOnDetailPage(bool show) {
    prefs?.setBool('checkUpdateOnDetailPage', show);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get disablePageTransitions {
    return prefs?.getBool('disablePageTransitions') ?? false;
  }

  set disablePageTransitions(bool show) {
    prefs?.setBool('disablePageTransitions', show);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get reversePageTransitions {
    return prefs?.getBool('reversePageTransitions') ?? false;
  }

  set reversePageTransitions(bool show) {
    prefs?.setBool('reversePageTransitions', show);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get enableBackgroundUpdates {
    return prefs?.getBool('enableBackgroundUpdates') ?? true;
  }

  set enableBackgroundUpdates(bool val) {
    prefs?.setBool('enableBackgroundUpdates', val);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get bgUpdatesOnWiFiOnly {
    return prefs?.getBool('bgUpdatesOnWiFiOnly') ?? false;
  }

  set bgUpdatesOnWiFiOnly(bool val) {
    prefs?.setBool('bgUpdatesOnWiFiOnly', val);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get bgUpdatesWhileChargingOnly {
    return prefs?.getBool('bgUpdatesWhileChargingOnly') ?? false;
  }

  set bgUpdatesWhileChargingOnly(bool val) {
    prefs?.setBool('bgUpdatesWhileChargingOnly', val);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  DateTime get lastCompletedBGCheckTime {
    int? temp = prefs?.getInt('lastCompletedBGCheckTime');
    return temp != null
        ? DateTime.fromMillisecondsSinceEpoch(temp)
        : DateTime.fromMillisecondsSinceEpoch(0);
  }

  set lastCompletedBGCheckTime(DateTime val) {
    prefs?.setInt('lastCompletedBGCheckTime', val.millisecondsSinceEpoch);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get showDebugOpts {
    return prefs?.getBool('showDebugOpts') ?? false;
  }

  set showDebugOpts(bool val) {
    prefs?.setBool('showDebugOpts', val);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get highlightTouchTargets {
    return prefs?.getBool('highlightTouchTargets') ?? false;
  }

  set highlightTouchTargets(bool val) {
    prefs?.setBool('highlightTouchTargets', val);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  Future<Uri?> getExportDir() async {
    var uriString = prefs?.getString('exportDir');
    if (uriString != null) {
      Uri? uri = Uri.parse(uriString);
      if (!(await saf.canRead(uri) ?? false) ||
          !(await saf.canWrite(uri) ?? false)) {
        uri = null;
        prefs?.remove('exportDir');
        notifyListeners();
      }
      return uri;
    } else {
      return null;
    }
  }

  Future<void> pickExportDir({bool remove = false}) async {
    var existingSAFPerms = (await saf.persistedUriPermissions()) ?? [];
    var currentOneWayDataSyncDir = await getExportDir();
    Uri? newOneWayDataSyncDir;
    if (!remove) {
      newOneWayDataSyncDir = (await saf.openDocumentTree());
    }
    if (currentOneWayDataSyncDir?.path != newOneWayDataSyncDir?.path) {
      if (newOneWayDataSyncDir == null) {
        prefs?.remove('exportDir');
      } else {
        prefs?.setString('exportDir', newOneWayDataSyncDir.toString());
      }
      notifyListeners();
    }
    for (var e in existingSAFPerms) {
      await saf.releasePersistableUriPermission(e.uri);
    }
  }

  bool get autoExportOnChanges {
    return prefs?.getBool('autoExportOnChanges') ?? false;
  }

  set autoExportOnChanges(bool val) {
    prefs?.setBool('autoExportOnChanges', val);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get onlyCheckInstalledOrTrackOnlyApps {
    return prefs?.getBool('onlyCheckInstalledOrTrackOnlyApps') ?? false;
  }

  set onlyCheckInstalledOrTrackOnlyApps(bool val) {
    prefs?.setBool('onlyCheckInstalledOrTrackOnlyApps', val);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get exportSettings {
    return prefs?.getBool('exportSettings') ?? false;
  }

  set exportSettings(bool val) {
    prefs?.setBool('exportSettings', val);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get parallelDownloads {
    return prefs?.getBool('parallelDownloads') ?? false;
  }

  set parallelDownloads(bool val) {
    prefs?.setBool('parallelDownloads', val);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  List<String> get searchDeselected {
    return prefs?.getStringList('searchDeselected') ?? [];
  }

  set searchDeselected(List<String> list) {
    prefs?.setStringList('searchDeselected', list);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get beforeNewInstallsShareToAppVerifier {
    return prefs?.getBool('beforeNewInstallsShareToAppVerifier') ?? true;
  }

  set beforeNewInstallsShareToAppVerifier(bool val) {
    prefs?.setBool('beforeNewInstallsShareToAppVerifier', val);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }

  bool get shizukuPretendToBeGooglePlay {
    return prefs?.getBool('shizukuPretendToBeGooglePlay') ?? false;
  }

  set shizukuPretendToBeGooglePlay(bool val) {
    prefs?.setBool('shizukuPretendToBeGooglePlay', val);
    notifyListeners();
    prefs?.setString('sxncdSavedTs', DateTime.now().toIso8601String());
  }
}
