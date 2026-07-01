// Exposes functions used to save/load app settings

import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

Locale? tryParseLocale(String? localeString) {
  if (localeString == null) return null;
  final split = localeString.split('-');
  if (split.length == 3) {
    return Locale.fromSubtags(languageCode: split[0], countryCode: split[2]);
  }
  if (split.length == 2) {
    return Locale(split[0], split[1]);
  }
  if (split.isNotEmpty) {
    return Locale(split[0]);
  }
  return null;
}

enum ThemeSettings { system, light, dark }

enum SortColumnSettings { added, nameAuthor, authorName, releaseDate }

enum SortOrderSettings { ascending, descending }

enum ColourSchemeMode { standard, vibrant, expressive, materialYou }

class SettingsProvider with ChangeNotifier {
  SharedPreferences? prefs;
  final ConfigProvider? _configProvider;
  String? defaultAppDir;
  bool justStarted = true;
  bool isTV = false;

  SettingsProvider({ConfigProvider? configProvider})
    : _configProvider = configProvider;

  /// Reads a value preferring the injected [ConfigProvider] (unified config
  /// layer). Falls back to direct [SharedPreferences] access for backward
  /// compatibility when no [ConfigProvider] is injected.
  T? _get<T>(String key) {
    if (_configProvider != null) {
      return _configProvider.get<T>(key);
    }
    return prefs?.get(key) as T?;
  }

  bool? _getBool(String key) => _get<bool>(key);
  int? _getInt(String key) => _get<int>(key);
  double? _getDouble(String key) => _get<double>(key);
  String? _getString(String key) => _get<String>(key);

  String sourceUrl = 'https://github.com/ImranR98/Obtainium';

  /// Platform properties that are stable for the process lifetime but expensive
  /// to fetch (platform channel round-trips). Cached across all provider instances.
  static String? _cachedDefaultAppDir;
  static bool? _cachedIsTV;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static final Map<String, String?> _secureCache = {};

  Future<void> initializeSettings() async {
    prefs = await SharedPreferences.getInstance();
    prefsInstance ??= prefs;
    await _loadSecureCache();
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
    notifyListeners();
  }

  void _migrateLegacyExportSetting() {
    if (_getInt('exportSettings') != null) return;
    final legacyBool = _getBool('exportSettings');
    if (legacyBool != null) {
      prefs?.setInt('exportSettings', legacyBool ? 1 : 0);
    }
  }

  static Future<void> _loadSecureCache() async {
    if (_secureCache.isNotEmpty) return;
    for (var key in {'github-creds', 'gitlab-creds'}) {
      _secureCache[key] = await _secureStorage.read(key: key);
      if (_secureCache[key] == null && prefsInstance != null) {
        final legacy = prefsInstance!.getString(key);
        if (legacy != null && legacy.isNotEmpty) {
          await _secureStorage.write(key: key, value: legacy);
          _secureCache[key] = legacy;
          unawaited(prefsInstance!.remove(key));
        }
      }
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

  bool get useShizuku {
    return _getBool('useShizuku') ?? false;
  }

  set useShizuku(bool useShizuku) {
    prefs?.setBool('useShizuku', useShizuku);
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
  /// granted (if [enforce] is true) or cancelled.
  Future<bool> getInstallPermission({bool enforce = false}) async {
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
      if (!enforce) {
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

  set pinUpdates(bool show) {
    prefs?.setBool('pinUpdates', show);
    notifyListeners();
  }

  bool get buryNonInstalled {
    return _getBool('buryNonInstalled') ?? false;
  }

  set buryNonInstalled(bool show) {
    prefs?.setBool('buryNonInstalled', show);
    notifyListeners();
  }

  bool get groupByCategory {
    return _getBool('groupByCategory') ?? false;
  }

  set groupByCategory(bool show) {
    prefs?.setBool('groupByCategory', show);
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
    if ({'github-creds', 'gitlab-creds'}.contains(settingId)) {
      return _secureCache[settingId];
    }
    final String? str = _getString(settingId);
    return str?.isNotEmpty == true ? str : null;
  }

  void setSettingString(String settingId, String value) {
    if ({'github-creds', 'gitlab-creds'}.contains(settingId)) {
      _secureCache[settingId] = value;
      _secureStorage
          .write(key: settingId, value: value)
          .catchError(
            (e) => LogsProvider().add(
              'Failed to persist credential: $e',
              level: LogLevel.error,
            ),
          );
    } else {
      prefs?.setString(settingId, value);
    }
    notifyListeners();
  }

  /// Returns the health status for a given source's stored credentials.
  /// [sourceName] is matched case-insensitively against the known credential
  /// keys (e.g. "GitHub" -> "github-creds").
  CredentialHealth? getCredentialHealth(String sourceName) {
    final key = '${sourceName.toLowerCase()}-creds';
    if (!{'github-creds', 'gitlab-creds'}.contains(key)) {
      return null;
    }
    final value = getSettingString(key);
    return CredentialHealth(
      sourceName: sourceName,
      isConfigured: value?.isNotEmpty == true,
    );
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
      _categoriesCache = Map<String, int>.from(jsonDecode(raw));
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
        appsProvider.saveApps(changedApps);
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

  bool get showBatteryOptimizationPrompt {
    return _getBool('showBatteryOptimizationPrompt') ?? true;
  }

  set showBatteryOptimizationPrompt(bool show) {
    prefs?.setBool('showBatteryOptimizationPrompt', show);
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

  set removeOnExternalUninstall(bool show) {
    prefs?.setBool('removeOnExternalUninstall', show);
    notifyListeners();
  }

  bool get checkUpdateOnDetailPage {
    return _getBool('checkUpdateOnDetailPage') ?? false;
  }

  set checkUpdateOnDetailPage(bool show) {
    prefs?.setBool('checkUpdateOnDetailPage', show);
    notifyListeners();
  }

  bool get disablePageTransitions {
    return _getBool('disablePageTransitions') ?? false;
  }

  set disablePageTransitions(bool show) {
    prefs?.setBool('disablePageTransitions', show);
    notifyListeners();
  }

  bool get reversePageTransitions {
    return _getBool('reversePageTransitions') ?? false;
  }

  set reversePageTransitions(bool show) {
    prefs?.setBool('reversePageTransitions', show);
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

  DateTime get lastCompletedBGCheckTime {
    final int? temp = _getInt('lastCompletedBGCheckTime');
    return temp != null
        ? DateTime.fromMillisecondsSinceEpoch(temp)
        : DateTime.fromMillisecondsSinceEpoch(0);
  }

  set lastCompletedBGCheckTime(DateTime val) {
    prefs?.setInt('lastCompletedBGCheckTime', val.millisecondsSinceEpoch);
    notifyListeners();
  }

  bool get highlightTouchTargets {
    return _getBool('highlightTouchTargets') ?? false;
  }

  set highlightTouchTargets(bool val) {
    prefs?.setBool('highlightTouchTargets', val);
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

  bool get useFGService {
    return _getBool('useFGService') ?? false;
  }

  set useFGService(bool val) {
    prefs?.setBool('useFGService', val);
    notifyListeners();
  }
}

/// Unified config provider that delegates to SharedPreferences (general settings),
/// FlutterSecureStorage (credentials), and in-memory cache transparently.
class ConfigProvider {
  SharedPreferences? _prefs;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static final Map<String, String?> _cache = {};

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  T? get<T>(String key) {
    return _prefs?.get(key) as T?;
  }

  Future<void> set<T>(String key, T value) async {
    if (value is String) {
      await _prefs?.setString(key, value);
    } else if (value is int) {
      await _prefs?.setInt(key, value);
    } else if (value is double) {
      await _prefs?.setDouble(key, value);
    } else if (value is bool) {
      await _prefs?.setBool(key, value);
    } else if (value is List<String>) {
      await _prefs?.setStringList(key, value);
    }
  }

  Future<void> remove(String key) async {
    await _prefs?.remove(key);
  }

  Future<String?> getCredential(String key) async {
    if (_cache.containsKey(key)) return _cache[key];
    final value = await _secureStorage.read(key: key);
    _cache[key] = value;
    return value;
  }

  Future<void> setCredential(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
    _cache[key] = value;
  }

  Future<void> removeCredential(String key) async {
    await _secureStorage.delete(key: key);
    _cache.remove(key);
  }
}

class CredentialHealth {
  final String sourceName;
  final bool isConfigured;
  final DateTime? expiresAt;
  final int? remainingRateLimit;
  final bool needsRotation;

  const CredentialHealth({
    required this.sourceName,
    this.isConfigured = false,
    this.expiresAt,
    this.remainingRateLimit,
    this.needsRotation = false,
  });
}
