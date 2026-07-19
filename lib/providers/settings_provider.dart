// Exposes functions used to save/load app settings

import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';

import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_storage/shared_storage.dart' as saf;

const String obtainiumTempId = 'imranr98_obtainium_github.com';
const String obtainiumId = 'dev.imranr.obtainium';
const String obtainiumUrl = 'https://github.com/ImranR98/Obtainium';
const Color obtainiumThemeColor = Color(0xFF6438B5);

String lowerCaseUnlessLang(String str, String lang) =>
    currentLanguageCode == lang ? str : str.toLowerCase();

Locale? tryParseLocale(String? localeString) {
  if (localeString == null) return null;
  final split = localeString.split('-');
  if (split.length == 3) {
    return Locale.fromSubtags(
      languageCode: split[0],
      scriptCode: split[1],
      countryCode: split[2],
    );
  }
  if (split.length == 2) {
    return Locale(split[0], split[1]);
  }
  if (split.isNotEmpty) {
    return Locale(split[0]);
  }
  return null;
}

enum InstallerMode { system, shizuku, external }

enum GroupByMode { none, category, source }

enum ThemeSettings { system, light, dark }

enum SortColumnSettings { added, nameAuthor, authorName, releaseDate }

enum SortOrderSettings { ascending, descending }

enum ColourSchemeMode { standard, vibrant, expressive, materialYou }

enum ActionBannerMode { all, updatesOnly, none }

class SettingsProvider with ChangeNotifier {
  SharedPreferences? prefs;
  String? defaultAppDir;
  bool justStarted = true;
  bool isTV = false;

  T? _get<T>(String key) {
    final value = prefs?.get(key);
    if (value is T) return value;
    return null;
  }

  bool? _getBool(String key) => _get<bool>(key);
  int? _getInt(String key) => _get<int>(key);
  double? _getDouble(String key) => _get<double>(key);
  String? _getString(String key) => _get<String>(key);

  final String sourceUrl = obtainiumUrl;

  /// Platform properties that are stable for the process lifetime but expensive
  /// to fetch (platform channel round-trips). Cached across all provider instances.
  static String? _cachedDefaultAppDir;
  static bool? _cachedIsTV;

  Future<void> initializeSettings() async {
    prefs = await SharedPreferences.getInstance();
    prefsInstance ??= prefs;
    _cachedDefaultAppDir ??= (await getAppStorageDir()).path;
    if (_cachedIsTV == null) {
      final info = await DeviceInfoPlugin().androidInfo;
      _cachedIsTV =
          info.systemFeatures.contains('android.hardware.type.television') ||
          info.systemFeatures.contains('android.software.leanback');
    }
    defaultAppDir = _cachedDefaultAppDir;
    isTV = _cachedIsTV!;
    _migrateLegacyExportSetting();
    _normalizeInstallPreference();
    _migrateGroupBySetting();
    notifyListeners();
  }

  void _migrateLegacyExportSetting() {
    if (_getInt('exportSettings') != null) return;
    final legacyBool = _getBool('exportSettings');
    if (legacyBool != null) {
      prefs?.setInt('exportSettings', legacyBool ? 1 : 0);
    }
  }

  void _migrateGroupBySetting() {
    if (_getString('groupBy') != null) return;
    final legacy = _getBool('groupByCategory');
    if (legacy != null) {
      prefs?.setString(
        'groupBy',
        legacy ? GroupByMode.category.name : GroupByMode.none.name,
      );
      unawaited(prefs?.remove('groupByCategory') ?? Future.value());
    }
  }

  void _normalizeInstallPreference() {
    if (_getString('installMethod') != null) return;
    final shizukuFlag = _getBool('useShizuku');
    if (shizukuFlag != null) {
      prefs?.setString(
        'installMethod',
        shizukuFlag ? InstallerMode.shizuku.name : InstallerMode.system.name,
      );
      unawaited(prefs?.remove('useShizuku') ?? Future.value());
    }
  }

  static SharedPreferences? prefsInstance;

  bool get useSystemFont {
    return _getBool('useSystemFont') ?? false;
  }

  set useSystemFont(bool useSystemFont) {
    prefs?.setBool('useSystemFont', useSystemFont);
    notifyListeners();
  }

  String get installerMode {
    final stored = _getString('installMethod');
    if (stored != null && InstallerMode.values.any((m) => m.name == stored)) {
      return stored;
    }
    return InstallerMode.system.name;
  }

  set installerMode(String mode) {
    final resolved = InstallerMode.values.any((m) => m.name == mode)
        ? mode
        : InstallerMode.system.name;
    prefs?.setString('installMethod', resolved);
    notifyListeners();
  }

  bool get useShizuku => installerMode == InstallerMode.shizuku.name;

  set useShizuku(bool useShizuku) {
    installerMode = useShizuku
        ? InstallerMode.shizuku.name
        : InstallerMode.system.name;
  }

  String? get externalInstallerPackage =>
      getSettingString('externalInstallerPackage');

  set externalInstallerPackage(String? val) {
    if (val == null || val.isEmpty) {
      prefs?.remove('externalInstallerPackage');
    } else {
      prefs?.setString('externalInstallerPackage', val);
    }
    notifyListeners();
  }

  String? get externalInstallerComponent =>
      getSettingString('externalInstallerComponent');

  set externalInstallerComponent(String? val) {
    if (val == null || val.isEmpty) {
      prefs?.remove('externalInstallerComponent');
    } else {
      prefs?.setString('externalInstallerComponent', val);
    }
    notifyListeners();
  }

  ThemeSettings get theme {
    return ThemeSettings.values[_getInt('theme') ?? ThemeSettings.system.index];
  }

  set theme(ThemeSettings t) {
    prefs?.setInt('theme', t.index);
    notifyListeners();
  }

  Color get themeColor {
    final int? colorCode = _getInt('themeColor');
    return (colorCode != null) ? Color(colorCode) : obtainiumThemeColor;
  }

  set themeColor(Color themeColor) {
    prefs?.setInt('themeColor', themeColor.toARGB32());
    notifyListeners();
  }

  ColourSchemeMode get colourSchemeMode {
    final stored = _getInt('colourSchemeMode');
    if (stored != null &&
        stored >= 0 &&
        stored < ColourSchemeMode.values.length) {
      return ColourSchemeMode.values[stored];
    }
    return (_getBool('useMaterialYou') ?? false)
        ? ColourSchemeMode.materialYou
        : ColourSchemeMode.standard;
  }

  set colourSchemeMode(ColourSchemeMode mode) {
    prefs?.setInt('colourSchemeMode', mode.index);
    prefs?.setBool('useMaterialYou', mode == ColourSchemeMode.materialYou);
    notifyListeners();
  }

  bool get useBlackTheme {
    return _getBool('useBlackTheme') ?? false;
  }

  set useBlackTheme(bool useBlackTheme) {
    prefs?.setBool('useBlackTheme', useBlackTheme);
    notifyListeners();
  }

  int get updateInterval {
    return _getInt('updateInterval') ?? 360;
  }

  set updateInterval(int min) {
    prefs?.setInt('updateInterval', min);
    notifyListeners();
  }

  double get updateIntervalSliderVal {
    return _getDouble('updateIntervalSliderVal') ?? 6.0;
  }

  set updateIntervalSliderVal(double val) {
    prefs?.setDouble('updateIntervalSliderVal', val);
    notifyListeners();
  }

  bool get checkOnStart {
    return _getBool('checkOnStart') ?? false;
  }

  set checkOnStart(bool checkOnStart) {
    prefs?.setBool('checkOnStart', checkOnStart);
    notifyListeners();
  }

  SortColumnSettings get sortColumn {
    return SortColumnSettings.values[_getInt('sortColumn') ??
        SortColumnSettings.nameAuthor.index];
  }

  set sortColumn(SortColumnSettings s) {
    prefs?.setInt('sortColumn', s.index);
    notifyListeners();
  }

  SortOrderSettings get sortOrder {
    return SortOrderSettings.values[_getInt('sortOrder') ??
        SortOrderSettings.ascending.index];
  }

  set sortOrder(SortOrderSettings s) {
    prefs?.setInt('sortOrder', s.index);
    notifyListeners();
  }

  bool checkAndFlipFirstRun() {
    final bool result = _getBool('firstRun') ?? true;
    if (result) {
      prefs?.setBool('firstRun', false);
    }
    return result;
  }

  bool get welcomeShown {
    return _getBool('welcomeShown') ?? false;
  }

  set welcomeShown(bool welcomeShown) {
    prefs?.setBool('welcomeShown', welcomeShown);
    notifyListeners();
  }

  bool get googleVerificationWarningShown {
    return _getBool('googleVerificationWarningShown') ?? false;
  }

  set googleVerificationWarningShown(bool googleVerificationWarningShown) {
    prefs?.setBool(
      'googleVerificationWarningShown',
      googleVerificationWarningShown,
    );
    notifyListeners();
  }

  bool checkJustStarted() {
    if (justStarted) {
      justStarted = false;
      return true;
    }
    return false;
  }

  /// Prompts the user for the Android install-permission grant. Loops until
  /// granted (if [enforce] is true) or cancelled. Has a maximum iteration limit
  /// to prevent infinite loops on systems where the permission dialog never
  /// appears.
  Future<bool> getInstallPermission({bool enforce = false}) async {
    var attempts = 0;
    const maxAttempts = 10;
    while (!(await Permission.requestInstallPackages.isGranted)) {
      unawaited(
        Fluttertoast.showToast(
          msg: tr('pleaseAllowInstallPerm'),
          toastLength: Toast.LENGTH_LONG,
        ),
      );
      if ((await Permission.requestInstallPackages.request()) ==
          PermissionStatus.granted) {
        return true;
      }
      if (!enforce || ++attempts >= maxAttempts) {
        return false;
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    return true;
  }

  bool get showAppWebpage {
    return _getBool('showAppWebpage') ?? false;
  }

  set showAppWebpage(bool show) {
    prefs?.setBool('showAppWebpage', show);
    notifyListeners();
  }

  bool get pinUpdates {
    return _getBool('pinUpdates') ?? true;
  }

  set pinUpdates(bool value) {
    prefs?.setBool('pinUpdates', value);
    notifyListeners();
  }

  bool get buryNonInstalled {
    return _getBool('buryNonInstalled') ?? false;
  }

  set buryNonInstalled(bool value) {
    prefs?.setBool('buryNonInstalled', value);
    notifyListeners();
  }

  String get groupBy {
    final stored = _getString('groupBy');
    if (stored != null && GroupByMode.values.any((m) => m.name == stored)) {
      return stored;
    }
    return GroupByMode.none.name;
  }

  set groupBy(String mode) {
    final resolved = GroupByMode.values.any((m) => m.name == mode)
        ? mode
        : GroupByMode.none.name;
    prefs?.setString('groupBy', resolved);
    notifyListeners();
  }

  bool get hideTrackOnlyWarning {
    return _getBool('hideTrackOnlyWarning') ?? false;
  }

  set hideTrackOnlyWarning(bool show) {
    prefs?.setBool('hideTrackOnlyWarning', show);
    notifyListeners();
  }

  bool get hideAPKOriginWarning {
    return _getBool('hideAPKOriginWarning') ?? false;
  }

  set hideAPKOriginWarning(bool show) {
    prefs?.setBool('hideAPKOriginWarning', show);
    notifyListeners();
  }

  String? getSettingString(String settingId) {
    final String? str = _getString(settingId);
    return str?.isNotEmpty == true ? str : null;
  }

  void setSettingString(String settingId, String value) {
    prefs?.setString(settingId, value);
    notifyListeners();
  }

  bool getSettingBool(String settingId) {
    return _getBool(settingId) ?? false;
  }

  void setSettingBool(String settingId, bool value) {
    prefs?.setBool(settingId, value);
    notifyListeners();
  }

  String? _categoriesRaw;
  Map<String, int>? _categoriesCache;

  Map<String, int> get categories {
    final raw = _getString('categories') ?? '{}';
    if (raw != _categoriesRaw || _categoriesCache == null) {
      _categoriesRaw = raw;
      try {
        _categoriesCache = Map<String, int>.from(jsonDecode(raw));
      } catch (e) {
        unawaited(
          LogsProvider().add(
            'Corrupted categories data, resetting: $e',
            level: LogLevel.error,
          ),
        );
        _categoriesCache = <String, int>{};
      }
    }
    return _categoriesCache!;
  }

  void setCategories(Map<String, int> cats, {AppsProvider? appsProvider}) {
    if (appsProvider != null) {
      final List<App> changedApps = appsProvider
          .getAppValues()
          .map((a) {
            if (!a.app.categories.any((c) => !cats.keys.contains(c))) {
              return null;
            }
            final app = a.app.copyWith(
              categories: List<String>.from(a.app.categories)
                ..removeWhere((c) => !cats.keys.contains(c)),
            );
            return app;
          })
          .where((element) => element != null)
          .map((e) => e as App)
          .toList();
      if (changedApps.isNotEmpty) {
        appsProvider.saveApps(changedApps).catchError((e) {
          unawaited(
            LogsProvider().add(
              'Failed to save apps during category update: $e',
              level: LogLevel.error,
            ),
          );
        });
      }
    }
    prefs?.setString('categories', jsonEncode(cats));
    notifyListeners();
  }

  Locale? get forcedLocale {
    final fl = tryParseLocale(_getString('forcedLocale'));
    final set =
        supportedLocales.where((element) => element.key == fl).isNotEmpty
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
  }

  bool setEqual(Set<String> a, Set<String> b) =>
      a.length == b.length && a.union(b).length == a.length;

  void resetLocaleSafe(BuildContext context) {
    if (context.supportedLocales.any(
      (l) => l.languageCode == context.deviceLocale.languageCode,
    )) {
      context.resetLocale();
    } else {
      context.setLocale(context.fallbackLocale!);
      context.deleteSaveLocale();
    }
  }

  bool get showAppDowngradeError {
    return _getBool('showAppDowngradeError') ?? true;
  }

  set showAppDowngradeError(bool show) {
    prefs?.setBool('showAppDowngradeError', show);
    notifyListeners();
  }

  bool get tactileFeedbackEnabled {
    return _getBool('tactileFeedbackEnabled') ?? true;
  }

  set tactileFeedbackEnabled(bool val) {
    prefs?.setBool('tactileFeedbackEnabled', val);
    notifyListeners();
  }

  void lightImpact() {
    if (tactileFeedbackEnabled) HapticFeedback.lightImpact();
  }

  void heavyImpact() {
    if (tactileFeedbackEnabled) HapticFeedback.heavyImpact();
  }

  void selectionClick() {
    if (tactileFeedbackEnabled) HapticFeedback.selectionClick();
  }

  bool get includePrereleasesByDefault {
    return _getBool('includePrereleasesByDefault') ?? false;
  }

  set includePrereleasesByDefault(bool val) {
    prefs?.setBool('includePrereleasesByDefault', val);
    notifyListeners();
  }

  bool get removeOnExternalUninstall {
    return _getBool('removeOnExternalUninstall') ?? false;
  }

  set removeOnExternalUninstall(bool value) {
    prefs?.setBool('removeOnExternalUninstall', value);
    notifyListeners();
  }

  bool get checkUpdateOnDetailPage {
    return _getBool('checkUpdateOnDetailPage') ?? false;
  }

  set checkUpdateOnDetailPage(bool value) {
    prefs?.setBool('checkUpdateOnDetailPage', value);
    notifyListeners();
  }

  bool get enableBackgroundUpdates {
    return _getBool('enableBackgroundUpdates') ?? true;
  }

  set enableBackgroundUpdates(bool val) {
    prefs?.setBool('enableBackgroundUpdates', val);
    notifyListeners();
  }

  bool get bgUpdatesOnWiFiOnly {
    return _getBool('bgUpdatesOnWiFiOnly') ?? false;
  }

  set bgUpdatesOnWiFiOnly(bool val) {
    prefs?.setBool('bgUpdatesOnWiFiOnly', val);
    notifyListeners();
  }

  bool get bgUpdatesWhileChargingOnly {
    return _getBool('bgUpdatesWhileChargingOnly') ?? false;
  }

  set bgUpdatesWhileChargingOnly(bool val) {
    prefs?.setBool('bgUpdatesWhileChargingOnly', val);
    notifyListeners();
  }

  bool get highlightTouchTargets {
    return _getBool('highlightTouchTargets') ?? false;
  }

  set highlightTouchTargets(bool val) {
    prefs?.setBool('highlightTouchTargets', val);
    notifyListeners();
  }

  bool get disableSwipeActions {
    return _getBool('disableSwipeActions') ?? false;
  }

  set disableSwipeActions(bool val) {
    prefs?.setBool('disableSwipeActions', val);
    notifyListeners();
  }

  bool get alwaysUsePhoneLayout {
    return _getBool('alwaysUsePhoneLayout') ?? false;
  }

  set alwaysUsePhoneLayout(bool val) {
    prefs?.setBool('alwaysUsePhoneLayout', val);
    notifyListeners();
  }

  Future<Uri?> getExportDir() async {
    final uriString = _getString('exportDir');
    if (uriString != null) {
      Uri? uri = Uri.parse(uriString);
      if (!(await saf.canRead(uri) ?? false) ||
          !(await saf.canWrite(uri) ?? false)) {
        uri = null;
        await prefs?.remove('exportDir');
        notifyListeners();
      }
      return uri;
    } else {
      return null;
    }
  }

  Future<void> pickExportDir({bool remove = false}) async {
    final existingSAFPerms = (await saf.persistedUriPermissions()) ?? [];
    final currentOneWayDataSyncDir = await getExportDir();
    Uri? newOneWayDataSyncDir;
    if (!remove) {
      try {
        newOneWayDataSyncDir = (await saf.openDocumentTree());
      } catch (e) {
        unawaited(
          LogsProvider().add(
            'Failed to open document tree: $e',
            level: LogLevel.error,
          ),
        );
        throw ObtainiumError(tr('noFilePickerAvailable'));
      }
    }
    if (currentOneWayDataSyncDir?.path != newOneWayDataSyncDir?.path) {
      if (newOneWayDataSyncDir == null) {
        await prefs?.remove('exportDir');
      } else {
        unawaited(
          prefs?.setString('exportDir', newOneWayDataSyncDir.toString()),
        );
      }
      notifyListeners();
    }
    for (var e in existingSAFPerms) {
      if (e.uri != newOneWayDataSyncDir) {
        await saf.releasePersistableUriPermission(e.uri);
      }
    }
  }

  bool get autoExportOnChanges {
    return _getBool('autoExportOnChanges') ?? false;
  }

  set autoExportOnChanges(bool val) {
    prefs?.setBool('autoExportOnChanges', val);
    notifyListeners();
  }

  bool get onlyCheckInstalledOrTrackOnlyApps {
    return _getBool('onlyCheckInstalledOrTrackOnlyApps') ?? false;
  }

  set onlyCheckInstalledOrTrackOnlyApps(bool val) {
    prefs?.setBool('onlyCheckInstalledOrTrackOnlyApps', val);
    notifyListeners();
  }

  int get exportSettings {
    return _getInt('exportSettings') ?? 1;
  }

  set exportSettings(int val) {
    prefs?.setInt('exportSettings', val > 2 || val < 0 ? 1 : val);
    notifyListeners();
  }

  bool get parallelDownloads {
    return _getBool('parallelDownloads') ?? false;
  }

  set parallelDownloads(bool val) {
    prefs?.setBool('parallelDownloads', val);
    notifyListeners();
  }

  List<String> get searchDeselected {
    return prefs?.getStringList('searchDeselected') ??
        SourceProvider().sources.map((s) => s.name).toList();
  }

  set searchDeselected(List<String> list) {
    prefs?.setStringList('searchDeselected', list);
    notifyListeners();
  }

  ActionBannerMode get actionBannerMode {
    final stored = prefs?.getString('actionBannerMode');
    if (stored != null &&
        ActionBannerMode.values.any((m) => m.name == stored)) {
      return ActionBannerMode.values.byName(stored);
    }
    final legacyBool = _getBool('showActionBannerForUpdateOnly');
    if (legacyBool != null) {
      return legacyBool
          ? ActionBannerMode.updatesOnly
          : ActionBannerMode.all;
    }
    return ActionBannerMode.updatesOnly;
  }

  set actionBannerMode(ActionBannerMode mode) {
    prefs?.setString('actionBannerMode', mode.name);
    notifyListeners();
  }

  bool get beforeNewInstallsShareToAppVerifier {
    return _getBool('beforeNewInstallsShareToAppVerifier') ?? true;
  }

  set beforeNewInstallsShareToAppVerifier(bool val) {
    prefs?.setBool('beforeNewInstallsShareToAppVerifier', val);
    notifyListeners();
  }

  bool get shizukuPretendToBeGooglePlay {
    return _getBool('shizukuPretendToBeGooglePlay') ?? false;
  }

  set shizukuPretendToBeGooglePlay(bool val) {
    prefs?.setBool('shizukuPretendToBeGooglePlay', val);
    notifyListeners();
  }
}
