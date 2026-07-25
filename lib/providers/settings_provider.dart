// Exposes functions used to save/load app settings

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/locale_resolution.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/folders/app_folder.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/theme/app_theme_accent.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_storage/shared_storage.dart' as saf;

String obtainiumTempId = 'bikram-agarwal_ObtainX_${GitHub().hosts[0]}';
String obtainiumId = 'dev.bikram.obtainx';
String obtainiumUrl = 'https://github.com/bikram-agarwal/ObtainX';
Color obtainiumThemeColor = const Color(0xFF6438B5);

// Cached mirror of [SettingsProvider.tactileFeedbackEnabled]. Haptic feedback fires
// from deep widget trees and providers alike, so the guarded helpers below read this
// cached flag instead of requiring a SettingsProvider instance at every call site.
// Kept in sync by SettingsProvider.initializeSettings and the setter.
bool _tactileFeedbackEnabled = true;

void hapticSelection() {
  if (_tactileFeedbackEnabled) HapticFeedback.selectionClick();
}

void hapticLightImpact() {
  if (_tactileFeedbackEnabled) HapticFeedback.lightImpact();
}

void hapticMediumImpact() {
  if (_tactileFeedbackEnabled) HapticFeedback.mediumImpact();
}

void hapticHeavyImpact() {
  if (_tactileFeedbackEnabled) HapticFeedback.heavyImpact();
}

void hapticVibrate() {
  if (_tactileFeedbackEnabled) HapticFeedback.vibrate();
}

enum ThemeSettings { system, light, dark }

enum SortColumnSettings {
  added,
  nameAuthor,
  authorName,
  releaseDate,
  lastUpdateCheck,
}

enum SortOrderSettings { ascending, descending }

enum AppsListGroupBy { none, category, source, appType }

enum SwipeAction { update, pin, appOptions, delete, open, appInfo, edit, none }

// Installer selection, converged with upstream Obtainium: same pref key
// (`installMethod`) and same values (these names). ObtainX drives it through the
// string [installerMode] getter/setter; the enum defines the shared vocabulary.
// [AppsListGroupBy] is ObtainX's grouping model — it too persists under
// upstream's `groupBy` key (its none/category/source names match upstream), with
// `appType` as an ObtainX-only extra that Obtainium safely ignores.
enum InstallerMode { system, shizuku, external }

enum ColourSchemeMode { standard, vibrant, expressive, materialYou }

/// Order for settings dropdowns: alphabetical by localized action label,
/// with [SwipeAction.none] ("None") always last.
List<SwipeAction> swipeActionsSortedByLocalizedLabel() {
  final List<SwipeAction> actions = List<SwipeAction>.from(SwipeAction.values);
  actions.sort((SwipeAction first, SwipeAction second) {
    if (first == SwipeAction.none) return 1;
    if (second == SwipeAction.none) return -1;
    final String labelFirst = tr('swipeAction_${first.name}').toLowerCase();
    final String labelSecond = tr('swipeAction_${second.name}').toLowerCase();
    return labelFirst.compareTo(labelSecond);
  });
  return actions;
}

class SettingsProvider with ChangeNotifier {
  SharedPreferences? prefs;
  String? defaultAppDir;
  // One-time-init guard. [initializeSettings] runs schema migrations plus two
  // native round-trips (DeviceInfoPlugin.androidInfo, getAppStorageDir) that
  // never change for the process lifetime, yet it is called more than once on
  // the same instance during cold start (from main() and again from the
  // AppsProvider constructor). Re-running that work needlessly delayed the
  // first frame; subsequent calls now just refresh the (cached) prefs handle
  // and notify, skipping the expensive one-time work.
  bool _settingsInitialized = false;
  bool justStarted = true;
  bool isTV = false;
  Brightness _platformBrightness =
      PlatformDispatcher.instance.platformBrightness;

  static const Duration _storageAccessWarningCooldown = Duration(minutes: 5);
  DateTime? _lastExportDirAccessWarningAt;
  DateTime? _lastApkSaveDirAccessWarningAt;

  // Mirrors last [setCategories] write; [getString] can lag [setString] briefly.
  Map<String, int>? _categoriesMemory;

  // Mirrors last [appFolders] write; avoids re-parsing JSON on every access.
  List<AppFolder>? _appFoldersMemory;

  // Per-folder view settings cache; avoids re-decoding 'folderView_<id>' JSON
  // on every getter call. Null value means the key exists but has no override.
  final Map<String, Map<String, dynamic>?> _folderViewCache = {};

  // Decoded 'savedCustomSeedHexList' cache, keyed by the raw stored string so it
  // self-invalidates whenever the pref changes (no matter which write path) and
  // avoids re-running jsonDecode on every theme-picker rebuild.
  String? _savedSeedHexesRaw;
  List<String>? _savedSeedHexesDecoded;

  String sourceUrl = 'https://github.com/bikram-agarwal/ObtainX';

  // Not done in constructor as we want to be able to await it
  Future<void> initializeSettings() async {
    prefs = await SharedPreferences.getInstance();
    _platformBrightness = PlatformDispatcher.instance.platformBrightness;
    if (_settingsInitialized) {
      // Already fully initialized on this instance — the migrations and native
      // lookups below are one-time work. Just notify so late listeners rebuild.
      notifyListeners();
      return;
    }
    _categoriesMemory = null;
    _appFoldersMemory = null;
    _folderViewCache.clear();
    _removeUnusedUpstreamSettings();
    _migrateProgressiveBlurDefaultForExistingUsers();
    defaultAppDir = (await getAppStorageDir()).path;
    _migrateInstallMethodSetting();
    _migrateExternalInstallerTarget();
    _migrateSwipeActionPrefs();
    _syncSwipeActionNameStringsIfMissing();
    _migrateThemeAccentPrefs();
    _migrateGroupBySetting();
    final info = await DeviceInfoPlugin().androidInfo;
    isTV =
        info.systemFeatures.contains('android.hardware.type.television') ||
        info.systemFeatures.contains('android.software.leanback');
    _tactileFeedbackEnabled = prefs?.getBool('tactileFeedbackEnabled') ?? true;
    _settingsInitialized = true;
    notifyListeners();
  }

  void _removeUnusedUpstreamSettings() {
    if (prefs == null) return;
    prefs!.remove('disableSwipeActions');
    prefs!.remove('showActionBannerForUpdateOnly');
  }

  bool get tactileFeedbackEnabled =>
      prefs?.getBool('tactileFeedbackEnabled') ?? true;

  set tactileFeedbackEnabled(bool val) {
    prefs?.setBool('tactileFeedbackEnabled', val);
    _tactileFeedbackEnabled = val;
    notifyListeners();
  }

  bool get includePrereleasesByDefault =>
      prefs?.getBool('includePrereleasesByDefault') ?? false;

  set includePrereleasesByDefault(bool val) {
    prefs?.setBool('includePrereleasesByDefault', val);
    notifyListeners();
  }

  bool get showAppDowngradeError =>
      prefs?.getBool('showAppDowngradeError') ?? true;

  set showAppDowngradeError(bool val) {
    prefs?.setBool('showAppDowngradeError', val);
    notifyListeners();
  }

  void _migrateProgressiveBlurDefaultForExistingUsers() {
    if (prefs == null) return;
    if (prefs!.containsKey('progressiveBlurDefaultMigrated')) return;
    // No longer force-enable blur for existing installs. The default is off
    // (see progressiveBlurEnabled getter). Users who want blur can enable it
    // explicitly in Settings. The migration guard is still written so this
    // block never runs twice.
    prefs!.setBool('progressiveBlurDefaultMigrated', true);
  }

  void _migrateThemeAccentPrefs() {
    if (prefs == null) return;
    if (prefs!.containsKey('appAccentColorSource')) return;
    final bool oldMaterialYou = prefs!.getBool('useMaterialYou') ?? true;
    if (oldMaterialYou) {
      prefs!.setString(
        'appAccentColorSource',
        AppAccentColorSource.materialYou.name,
      );
    } else {
      prefs!.setString(
        'appAccentColorSource',
        AppAccentColorSource.custom.name,
      );
      final int? colorCode = prefs!.getInt('themeColor');
      final Color fromLegacy = (colorCode != null)
          ? Color(colorCode)
          : obtainiumThemeColor;
      final String hex = colorToCanonicalHex(fromLegacy);
      prefs!.setString('activeCustomSeedHex', hex);
      prefs!.setString('savedCustomSeedHexList', jsonEncode([hex]));
    }
    prefs!.setString(
      'appThemePaletteStyle',
      AppThemePaletteStyle.tonalSpot.name,
    );
  }

  /// Converges grouping onto upstream Obtainium's representation: pref key
  /// `groupBy`, value = [AppsListGroupBy] name. ObtainX's `none`/`category`/
  /// `source` names match upstream Obtainium's groupBy names, so Obtainium reads
  /// them directly; ObtainX's extra `appType` value is one Obtainium simply
  /// ignores (its getter falls back to `none`). Migrates from ObtainX's older
  /// int `appsListGroupBy` key — which is authoritative because it alone can
  /// encode `appType` — and the even-older `groupByCategory` bool.
  void _migrateGroupBySetting() {
    if (prefs == null) return;
    if (prefs!.containsKey('appsListGroupBy')) {
      final int? idx = prefs!.getInt('appsListGroupBy');
      final AppsListGroupBy mode =
          (idx != null && idx >= 0 && idx < AppsListGroupBy.values.length)
          ? AppsListGroupBy.values[idx]
          : AppsListGroupBy.none;
      prefs!.setString('groupBy', mode.name);
      prefs!.remove('appsListGroupBy');
      prefs!.remove('groupByCategory');
      return;
    }
    final String? existing = prefs!.getString('groupBy');
    final bool validExisting =
        existing != null &&
        AppsListGroupBy.values.any((AppsListGroupBy m) => m.name == existing);
    if (!validExisting) {
      final AppsListGroupBy mode = (prefs!.getBool('groupByCategory') == true)
          ? AppsListGroupBy.category
          : AppsListGroupBy.none;
      prefs!.setString('groupBy', mode.name);
    }
    prefs!.remove('groupByCategory');
  }

  static const String _rightSwipeNameKey = 'rightSwipeActionName';
  static const String _leftSwipeNameKey = 'leftSwipeActionName';

  /// v1: [SwipeAction.none] was index 6 on the 7-value enum. v2 remaps that to index 7.
  /// v3 clears stored swipe name prefs once so they are rebuilt from ints (fixes stale
  /// [rightSwipeActionName] / [leftSwipeActionName] from older ObtainX builds).
  void _migrateSwipeActionPrefs() {
    if (prefs == null) return;
    int schemaVersion = prefs!.getInt('swipeActionEnumVersion') ?? 0;

    if (schemaVersion < 2) {
      for (final String prefKey in ['rightSwipeAction', 'leftSwipeAction']) {
        if (prefs!.containsKey(prefKey) && prefs!.getInt(prefKey) == 6) {
          prefs!.setInt(prefKey, SwipeAction.none.index);
        }
      }
      prefs!.setInt('swipeActionEnumVersion', 2);
      schemaVersion = 2;
    }

    if (schemaVersion < 3) {
      prefs!.remove(_rightSwipeNameKey);
      prefs!.remove(_leftSwipeNameKey);
      prefs!.setInt('swipeActionEnumVersion', 3);
      schemaVersion = 3;
    }

    if (schemaVersion < 4) {
      if (prefs!.getString(_leftSwipeNameKey) == 'pin' ||
          (!prefs!.containsKey(_leftSwipeNameKey) &&
              prefs!.getInt('leftSwipeAction') == SwipeAction.pin.index)) {
        prefs!.remove(_leftSwipeNameKey);
        prefs!.remove('leftSwipeAction');
      }
      prefs!.setInt('swipeActionEnumVersion', 4);
    }
  }

  /// Prefer stable enum [SwipeAction.name] in prefs so reordering does not break gestures.
  void _syncSwipeActionNameStringsIfMissing() {
    if (prefs == null) return;
    void syncOne(String intKey, String nameKey, int defaultIndex) {
      if (prefs!.containsKey(nameKey)) return;
      final int raw = prefs!.getInt(intKey) ?? defaultIndex;
      final SwipeAction action =
          SwipeAction.values[raw.clamp(0, SwipeAction.values.length - 1)];
      prefs!.setString(nameKey, action.name);
    }

    syncOne('rightSwipeAction', _rightSwipeNameKey, SwipeAction.update.index);
    syncOne('leftSwipeAction', _leftSwipeNameKey, SwipeAction.delete.index);
  }

  SwipeAction _swipeActionFromPrefs(
    String intKey,
    String nameKey,
    int defaultIndex,
  ) {
    final String? storedName = prefs?.getString(nameKey);
    if (storedName != null && storedName.isNotEmpty) {
      for (final SwipeAction candidate in SwipeAction.values) {
        if (candidate.name == storedName) return candidate;
      }
    }
    final int index = prefs?.getInt(intKey) ?? defaultIndex;
    return SwipeAction.values[index.clamp(0, SwipeAction.values.length - 1)];
  }

  /// Converges the installer setting onto upstream Obtainium's representation:
  /// key `installMethod`, values [InstallerMode] names (system/shizuku/external).
  /// Migrates from ObtainX's older `installerMode` key (stock/shizuku/legacy) and
  /// the even-older `useShizuku` bool. Runs once; skips if `installMethod` is set.
  void _migrateInstallMethodSetting() {
    if (prefs == null) return;
    final Object? existing = prefs!.get('installMethod');
    if (existing is int) {
      final String converged =
          (existing >= 0 && existing < InstallerMode.values.length)
          ? InstallerMode.values[existing].name
          : InstallerMode.system.name;
      prefs!.setString('installMethod', converged);
    }
    if (prefs!.containsKey('installMethod')) return;
    final Object? legacyMode = prefs!.get('installerMode');
    if (legacyMode != null) {
      final String legacyStr = legacyMode.toString();
      final String converged = switch (legacyStr) {
        'shizuku' || '1' => InstallerMode.shizuku.name,
        'legacy' || '2' => InstallerMode.external.name,
        'stock' || '0' => InstallerMode.system.name,
        _ =>
          int.tryParse(legacyStr) != null
              ? (int.parse(legacyStr) >= 0 &&
                        int.parse(legacyStr) < InstallerMode.values.length
                    ? InstallerMode.values[int.parse(legacyStr)].name
                    : InstallerMode.system.name)
              : InstallerMode.system.name,
      };
      prefs!.setString('installMethod', converged);
      prefs!.remove('installerMode');
      prefs!.remove('useShizuku');
      return;
    }
    final Object? useShizukuVal = prefs!.get('useShizuku');
    if (useShizukuVal == true ||
        useShizukuVal == 1 ||
        useShizukuVal.toString().toLowerCase() == 'true') {
      prefs!.setString('installMethod', InstallerMode.shizuku.name);
    }
    prefs!.remove('useShizuku');
  }

  void _migrateExternalInstallerTarget() {
    if (prefs?.containsKey('externalInstallerPackage') != true) {
      final String? legacyPackage = prefs?.getString('legacyInstallerPackage');
      if (legacyPackage != null && legacyPackage.isNotEmpty) {
        prefs?.setString('externalInstallerPackage', legacyPackage);
      }
    }
    if (prefs?.containsKey('externalInstallerComponent') != true) {
      final String? legacyActivity = prefs?.getString(
        'legacyInstallerActivity',
      );
      if (legacyActivity != null && legacyActivity.isNotEmpty) {
        prefs?.setString('externalInstallerComponent', legacyActivity);
      }
    }
    prefs?.remove('legacyInstallerPackage');
    prefs?.remove('legacyInstallerActivity');
  }

  // ── App UI scale ────────────────────────────────────────────────────────
  // User-tunable multiplier applied to the effective text scale used by the
  // top-level MediaQuery override in main.dart. The system scaler is capped at
  // 1.2 and the final custom scale stays inside this 0.75-1.25 range.
  static const double appUiScaleMin = 0.75;
  static const double appUiScaleMax = 1.25;
  static const double appUiScaleDefault = 1.0;
  static const double cardCornerScaleMin = 0.5;
  static const double cardCornerScaleMax = 1.5;
  static const double cardCornerScaleDefault = 1.0;
  static const double baseCardRadius = 14.0;
  static const double baseCollapsedHeaderRadius = 28.0;
  static const double collapsedHeaderHeight = 56.0;
  static const double collapsedHeaderGap = 6.0;

  double get appUiScale {
    final double raw = prefs?.getDouble('appUiScale') ?? appUiScaleDefault;
    if (raw.isNaN || raw <= 0) return appUiScaleDefault;
    return raw.clamp(appUiScaleMin, appUiScaleMax);
  }

  set appUiScale(double scale) {
    final double clamped = scale.clamp(appUiScaleMin, appUiScaleMax);
    prefs?.setDouble('appUiScale', clamped);
    notifyListeners();
  }

  double get cardCornerScale {
    final double raw =
        prefs?.getDouble('cardCornerScale') ?? cardCornerScaleDefault;
    if (raw.isNaN || raw <= 0) return cardCornerScaleDefault;
    return raw.clamp(cardCornerScaleMin, cardCornerScaleMax);
  }

  set cardCornerScale(double scale) {
    final double stepped = (scale * 10).round() / 10;
    final double clamped = stepped.clamp(
      cardCornerScaleMin,
      cardCornerScaleMax,
    );
    prefs?.setDouble('cardCornerScale', clamped);
    notifyListeners();
  }

  static double cardCornerRadiusForScale(double baseRadius, double scale) {
    return (baseRadius * scale).clamp(4.0, 40.0);
  }

  double cardCornerRadiusFor(double baseRadius) {
    return cardCornerRadiusForScale(baseRadius, cardCornerScale);
  }

  // Installer selection, stored the same way upstream Obtainium stores it: pref
  // key `installMethod`, values are [InstallerMode] names — 'system' (default
  // Android installer), 'shizuku', or 'external' (third-party, user-chosen app).
  // Sharing the key/values with upstream is what lets backups move cleanly
  // between ObtainX and Obtainium without any translation.
  String get installerMode {
    final Object? stored = prefs?.get('installMethod');
    if (stored is String) {
      if (InstallerMode.values.any(
        (InstallerMode modeOption) => modeOption.name == stored,
      )) {
        return stored;
      }
    } else if (stored is int) {
      if (stored >= 0 && stored < InstallerMode.values.length) {
        return InstallerMode.values[stored].name;
      }
    }
    return InstallerMode.system.name;
  }

  set installerMode(String mode) {
    final String resolved =
        InstallerMode.values.any(
          (InstallerMode modeOption) => modeOption.name == mode,
        )
        ? mode
        : InstallerMode.system.name;
    prefs?.setString('installMethod', resolved);
    notifyListeners();
  }

  bool get useShizuku {
    return installerMode == InstallerMode.shizuku.name;
  }

  set useShizuku(bool useShizuku) {
    installerMode = useShizuku
        ? InstallerMode.shizuku.name
        : InstallerMode.system.name;
  }

  ThemeSettings get theme {
    return ThemeSettings.values[prefs?.getInt('theme') ??
        ThemeSettings.system.index];
  }

  set theme(ThemeSettings t) {
    if (theme == t) return;
    prefs?.setInt('theme', t.index);
    notifyListeners();
  }

  Color get themeColor {
    final Color? fromHex = colorFromNormalizedHex(
      normalizeCustomSeedHexOrNull(activeCustomSeedHex),
    );
    if (fromHex != null) return fromHex;
    final int? colorCode = prefs?.getInt('themeColor');
    return (colorCode != null) ? Color(colorCode) : obtainiumThemeColor;
  }

  set themeColor(Color themeColor) {
    prefs?.setInt('themeColor', themeColor.toARGB32());
    final String hex = colorToCanonicalHex(themeColor);
    prefs?.setString('activeCustomSeedHex', hex);
    prefs?.setString('appAccentColorSource', AppAccentColorSource.custom.name);
    prefs?.setBool('useMaterialYou', false);
    _ensureHexInSavedList(hex);
    notifyListeners();
  }

  AppAccentColorSource get appAccentColorSource {
    final AppAccentColorSource? parsed = AppAccentColorSourceX.tryParse(
      prefs?.getString('appAccentColorSource'),
    );
    if (parsed != null) return parsed;
    return (prefs?.getBool('useMaterialYou') ?? true)
        ? AppAccentColorSource.materialYou
        : AppAccentColorSource.custom;
  }

  set appAccentColorSource(AppAccentColorSource source) {
    prefs?.setString('appAccentColorSource', source.name);
    prefs?.setBool(
      'useMaterialYou',
      source == AppAccentColorSource.materialYou,
    );
    notifyListeners();
  }

  AppThemePaletteStyle get appThemePaletteStyle {
    return AppThemePaletteStyleX.tryParse(
          prefs?.getString('appThemePaletteStyle'),
        ) ??
        AppThemePaletteStyle.tonalSpot;
  }

  set appThemePaletteStyle(AppThemePaletteStyle style) {
    prefs?.setString('appThemePaletteStyle', style.name);
    notifyListeners();
  }

  String get activeCustomSeedHex {
    final String? stored = prefs?.getString('activeCustomSeedHex');
    final String? normalized = stored != null
        ? normalizeCustomSeedHexOrNull(stored)
        : null;
    if (normalized != null) return normalized;
    final int? colorCode = prefs?.getInt('themeColor');
    return colorToCanonicalHex(
      (colorCode != null) ? Color(colorCode) : obtainiumThemeColor,
    );
  }

  set activeCustomSeedHex(String value) {
    final String? normalized = normalizeCustomSeedHexOrNull(value);
    if (normalized == null) return;
    _setActiveCustomSeedHexNormalized(normalized);
    notifyListeners();
  }

  void _setActiveCustomSeedHexNormalized(String normalized) {
    prefs?.setString('activeCustomSeedHex', normalized);
    final Color? c = colorFromNormalizedHex(normalized);
    if (c != null) prefs?.setInt('themeColor', c.toARGB32());
  }

  List<String> get savedCustomSeedHexes {
    final String? raw = prefs?.getString('savedCustomSeedHexList');
    if (raw == null || raw.isEmpty) {
      return [activeCustomSeedHex];
    }
    // Re-decode only when the raw pref string actually changes. The
    // activeCustomSeedHex fallback stays outside the cache since it can change
    // independently of this list.
    List<String>? out = raw == _savedSeedHexesRaw
        ? _savedSeedHexesDecoded
        : null;
    if (out == null) {
      try {
        final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
        out = decoded
            .map((dynamic e) => normalizeCustomSeedHexOrNull(e.toString()))
            .whereType<String>()
            .toList();
      } catch (_) {
        return [activeCustomSeedHex];
      }
      _savedSeedHexesRaw = raw;
      _savedSeedHexesDecoded = out;
    }
    return out.isNotEmpty ? out : [activeCustomSeedHex];
  }

  void _persistSavedCustomSeedHexes(List<String> list) {
    prefs?.setString('savedCustomSeedHexList', jsonEncode(list));
  }

  void _ensureHexInSavedList(String normalizedHex) {
    final List<String> list = savedCustomSeedHexes.toList();
    if (!list.contains(normalizedHex)) {
      list.add(normalizedHex);
      _persistSavedCustomSeedHexes(list);
    }
  }

  void addCustomSeedHex(String raw) {
    final String? normalized = normalizeCustomSeedHexOrNull(raw);
    if (normalized == null) return;
    final List<String> list = savedCustomSeedHexes.toList();
    if (!list.contains(normalized)) list.add(normalized);
    _persistSavedCustomSeedHexes(list);
    previewCustomSeedHex(normalized);
  }

  void removeCustomSeedHex(String raw) {
    final String? normalized = normalizeCustomSeedHexOrNull(raw);
    if (normalized == null) return;
    final List<String> list = savedCustomSeedHexes
        .where((String h) => h != normalized)
        .toList();
    _persistSavedCustomSeedHexes(list);
    if (activeCustomSeedHex == normalized) {
      final String nextHex = list.isNotEmpty
          ? list.first
          : colorToCanonicalHex(obtainiumThemeColor);
      prefs?.setString('activeCustomSeedHex', nextHex);
      final Color? c = colorFromNormalizedHex(nextHex);
      if (c != null) prefs?.setInt('themeColor', c.toARGB32());
    }
    notifyListeners();
  }

  void selectSavedCustomSeedHex(String raw) {
    previewCustomSeedHex(raw);
  }

  void previewCustomSeedHex(String raw) {
    final String? normalized = normalizeCustomSeedHexOrNull(raw);
    if (normalized == null) return;
    _setActiveCustomSeedHexNormalized(normalized);
    prefs?.setString('appAccentColorSource', AppAccentColorSource.custom.name);
    prefs?.setBool('useMaterialYou', false);
    notifyListeners();
  }

  // New installs default this off because it can be expensive, but
  // [_migrateProgressiveBlurDefaultForExistingUsers] preserves the old
  // implicit enabled default for users upgrading without an explicit pref.
  bool get progressiveBlurEnabled {
    if (reduceVisualEffects) return false;
    return prefs?.getBool('progressiveBlurEnabled') ?? true;
  }

  set progressiveBlurEnabled(bool value) {
    prefs?.setBool('progressiveBlurEnabled', value);
    notifyListeners();
  }

  // Master "low-fidelity mode" toggle. When on:
  //   - Forces [progressiveBlurEnabled] off regardless of its own setting,
  //     so all BackdropFilter passes are skipped.
  //   - Skips the [OpenContainer] container-transform morph for the apps
  //     list -> AppPage navigation; uses a plain page-route push instead.
  // Intended for users who report frame-rate drops on older devices, as a
  // single-switch escape hatch. Default false to preserve the visual look
  // for everyone whose hardware can handle it.
  bool get reduceVisualEffects {
    return prefs?.getBool('reduceVisualEffects') ?? false;
  }

  set reduceVisualEffects(bool value) {
    prefs?.setBool('reduceVisualEffects', value);
    if (value) {
      prefs?.remove('progressiveBlurEnabled');
    }
    notifyListeners();
  }

  bool get useGradientBackground {
    if (reduceVisualEffects || blackThemeActive) return false;
    return prefs?.getBool('useGradientBackground') ?? true;
  }

  set useGradientBackground(bool value) {
    prefs?.setBool('useGradientBackground', value);
    notifyListeners();
  }

  double get shadingIntensity {
    if (blackThemeActive) return 1.0;
    return (prefs?.getDouble('shadingIntensity') ?? 1.0).clamp(0.0, 2.0);
  }

  set shadingIntensity(double value) {
    final double steppedValue = ((value * 10).round() / 10).clamp(0.0, 2.0);
    prefs?.setDouble('shadingIntensity', steppedValue);
    notifyListeners();
  }

  bool get useMaterialYou {
    return appAccentColorSource == AppAccentColorSource.materialYou;
  }

  set useMaterialYou(bool useMaterialYou) {
    prefs?.setBool('useMaterialYou', useMaterialYou);
    if (useMaterialYou) {
      prefs?.setString(
        'appAccentColorSource',
        AppAccentColorSource.materialYou.name,
      );
    } else {
      prefs?.setString(
        'appAccentColorSource',
        AppAccentColorSource.custom.name,
      );
    }
    notifyListeners();
  }

  bool get useBlackTheme {
    return prefs?.getBool('useBlackTheme') ?? false;
  }

  set useBlackTheme(bool useBlackTheme) {
    if (this.useBlackTheme == useBlackTheme) return;
    prefs?.setBool('useBlackTheme', useBlackTheme);
    notifyListeners();
  }

  String? get customFontPath {
    return prefs?.getString('customFontPath');
  }

  set customFontPath(String? value) {
    if (value == null) {
      prefs?.remove('customFontPath');
    } else {
      prefs?.setString('customFontPath', value);
    }
    notifyListeners();
  }

  String? get customFontName {
    return prefs?.getString('customFontName');
  }

  set customFontName(String? value) {
    if (value == null) {
      prefs?.remove('customFontName');
    } else {
      prefs?.setString('customFontName', value);
    }
    notifyListeners();
  }

  bool _blackThemeAppliesTo(Brightness platformBrightness) {
    if (!useBlackTheme || theme == ThemeSettings.light) return false;
    return theme == ThemeSettings.dark || platformBrightness == Brightness.dark;
  }

  // Pure black only applies while the app is effectively using a dark theme.
  // In System mode, the platform brightness determines that effective theme.
  bool get blackThemeActive {
    return _blackThemeAppliesTo(_platformBrightness);
  }

  void updatePlatformBrightness(Brightness platformBrightness) {
    final bool brightnessChanged = _platformBrightness != platformBrightness;
    _platformBrightness = platformBrightness;
    if (brightnessChanged) {
      notifyListeners();
    }
  }

  bool get matchAppPageToIconColors {
    return prefs?.getBool('matchAppPageToIconColors') ?? true;
  }

  set matchAppPageToIconColors(bool matchAppPageToIconColors) {
    prefs?.setBool('matchAppPageToIconColors', matchAppPageToIconColors);
    notifyListeners();
  }

  bool get showAppTypeBadge {
    return prefs?.getBool('showAppTypeBadge') ?? true;
  }

  set showAppTypeBadge(bool value) {
    prefs?.setBool('showAppTypeBadge', value);
    notifyListeners();
  }

  bool get showTrackedStoreBadge {
    return prefs?.getBool('showTrackedStoreBadge') ?? true;
  }

  set showTrackedStoreBadge(bool value) {
    prefs?.setBool('showTrackedStoreBadge', value);
    notifyListeners();
  }

  bool get showCategoriesBadge {
    return prefs?.getBool('showCategoriesBadge') ?? false;
  }

  set showCategoriesBadge(bool value) {
    prefs?.setBool('showCategoriesBadge', value);
    notifyListeners();
  }

  int get updateInterval {
    return prefs?.getInt('updateInterval') ?? 360;
  }

  set updateInterval(int min) {
    prefs?.setInt('updateInterval', min);
    notifyListeners();
  }

  double get updateIntervalSliderVal {
    return prefs?.getDouble('updateIntervalSliderVal') ?? 6.0;
  }

  set updateIntervalSliderVal(double val) {
    prefs?.setDouble('updateIntervalSliderVal', val);
    notifyListeners();
  }

  bool get checkOnStart {
    return prefs?.getBool('checkOnStart') ?? false;
  }

  set checkOnStart(bool checkOnStart) {
    prefs?.setBool('checkOnStart', checkOnStart);
    notifyListeners();
  }

  SortColumnSettings get sortColumn {
    final stored = prefs?.getInt('sortColumn');
    if (stored == null) return SortColumnSettings.nameAuthor;
    if (stored < 0 || stored >= SortColumnSettings.values.length) {
      return SortColumnSettings.nameAuthor;
    }
    return SortColumnSettings.values[stored];
  }

  set sortColumn(SortColumnSettings sortColumnSetting) {
    prefs?.setInt('sortColumn', sortColumnSetting.index);
    notifyListeners();
  }

  SortOrderSettings get sortOrder {
    return SortOrderSettings.values[prefs?.getInt('sortOrder') ??
        SortOrderSettings.ascending.index];
  }

  set sortOrder(SortOrderSettings s) {
    prefs?.setInt('sortOrder', s.index);
    notifyListeners();
  }

  bool checkAndFlipFirstRun() {
    final bool result = prefs?.getBool('firstRun') ?? true;
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

  bool get buryNonInstalled {
    return prefs?.getBool('buryNonInstalled') ?? false;
  }

  set buryNonInstalled(bool show) {
    prefs?.setBool('buryNonInstalled', show);
    notifyListeners();
  }

  bool get groupNonInstalledSeparately {
    return prefs?.getBool('groupNonInstalledSeparately') ?? false;
  }

  set groupNonInstalledSeparately(bool show) {
    prefs?.setBool('groupNonInstalledSeparately', show);
    notifyListeners();
  }

  bool get groupTrackOnlySeparately {
    return prefs?.getBool('groupTrackOnlySeparately') ?? false;
  }

  set groupTrackOnlySeparately(bool show) {
    prefs?.setBool('groupTrackOnlySeparately', show);
    notifyListeners();
  }

  bool get groupUpdatesSeparately {
    return prefs?.getBool('groupUpdatesSeparately') ?? false;
  }

  set groupUpdatesSeparately(bool value) {
    prefs?.setBool('groupUpdatesSeparately', value);
    notifyListeners();
  }

  // Grouping is persisted under upstream Obtainium's `groupBy` key as the
  // [AppsListGroupBy] name (see [_migrateGroupBySetting]). The enum is kept in
  // code for type-safe grouping logic/UI; only its persisted form is shared with
  // upstream so backups move between ObtainX and Obtainium without translation.
  AppsListGroupBy get appsListGroupBy {
    final String? stored = prefs?.getString('groupBy');
    if (stored != null) {
      for (final AppsListGroupBy mode in AppsListGroupBy.values) {
        if (mode.name == stored) return mode;
      }
    }
    return AppsListGroupBy.none;
  }

  set appsListGroupBy(AppsListGroupBy mode) {
    prefs?.setString('groupBy', mode.name);
    notifyListeners();
  }

  bool get groupByCategory => appsListGroupBy == AppsListGroupBy.category;

  set groupByCategory(bool show) {
    appsListGroupBy = show ? AppsListGroupBy.category : AppsListGroupBy.none;
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

  bool get hideBatteryOptimizationWarning {
    return prefs?.getBool('hideBatteryOptimizationWarning') ?? false;
  }

  set hideBatteryOptimizationWarning(bool show) {
    prefs?.setBool('hideBatteryOptimizationWarning', show);
    notifyListeners();
  }

  String? getSettingString(String settingId) {
    final String? str = prefs?.getString(settingId);
    return str?.isNotEmpty == true ? str : null;
  }

  void setSettingString(String settingId, String value) {
    prefs?.setString(settingId, value);
    notifyListeners();
  }

  bool? getSettingBool(String settingId) {
    return prefs?.getBool(settingId) ?? false;
  }

  void setSettingBool(String settingId, bool value) {
    prefs?.setBool(settingId, value);
    notifyListeners();
  }

  Map<String, int> get categories {
    if (_categoriesMemory != null) {
      return Map<String, int>.from(_categoriesMemory!);
    }
    // Lazily populate the in-memory cache on first read (mirrors [appFolders]).
    // Previously this decoded the 'categories' JSON on every read until a write
    // happened — and categories is read on every apps-list / settings rebuild.
    final Map<String, int> rawCats = Map<String, int>.from(
      jsonDecode(prefs?.getString('categories') ?? '{}'),
    );
    final List<MapEntry<String, int>> sortedEntries = rawCats.entries.toList()
      ..sort((a, b) {
        final int cmp = a.key.toLowerCase().compareTo(b.key.toLowerCase());
        if (cmp != 0) return cmp;
        return a.key.compareTo(b.key);
      });
    _categoriesMemory = Map<String, int>.fromEntries(sortedEntries);
    return Map<String, int>.from(_categoriesMemory!);
  }

  void setCategories(Map<String, int> cats, {AppsProvider? appsProvider}) {
    final List<MapEntry<String, int>> sortedEntries = cats.entries.toList()
      ..sort((a, b) {
        final int cmp = a.key.toLowerCase().compareTo(b.key.toLowerCase());
        if (cmp != 0) return cmp;
        return a.key.compareTo(b.key);
      });
    final Map<String, int> sortedCats = Map<String, int>.fromEntries(
      sortedEntries,
    );

    if (appsProvider != null) {
      // Detect a rename: one key removed from old map, one key added to new map.
      // Each UI action (rename, delete) fires a separate call, so at most one
      // rename is in flight per call.
      final Map<String, int> oldCats = categories;
      final Set<String> removed = oldCats.keys.toSet().difference(
        sortedCats.keys.toSet(),
      );
      final Set<String> added = sortedCats.keys.toSet().difference(
        oldCats.keys.toSet(),
      );
      final String? renamedFrom = (removed.length == 1 && added.length == 1)
          ? removed.first
          : null;
      final String? renamedTo = (removed.length == 1 && added.length == 1)
          ? added.first
          : null;

      final List<App> changedApps = appsProvider
          .getAppValues()
          .map((a) {
            bool changed = false;
            if (renamedFrom != null && renamedTo != null) {
              final idx = a.app.categories.indexOf(renamedFrom);
              if (idx >= 0) {
                a.app.categories[idx] = renamedTo;
                changed = true;
              }
            }
            final n1 = a.app.categories.length;
            a.app.categories.removeWhere((c) => !sortedCats.keys.contains(c));
            if (a.app.categories.length < n1) changed = true;
            return changed ? a.app : null;
          })
          .where((element) => element != null)
          .map((e) => e as App)
          .toList();
      if (changedApps.isNotEmpty) {
        appsProvider.saveApps(changedApps, updateInstalledInfo: false);
      }
    }
    _categoriesMemory = Map<String, int>.from(sortedCats);
    prefs?.setString('categories', jsonEncode(sortedCats));
    notifyListeners();
  }

  List<AppFolder> get appFolders {
    if (_appFoldersMemory != null) {
      return List<AppFolder>.from(_appFoldersMemory!);
    }
    final raw = prefs?.getString('appFolders') ?? '[]';
    final list = jsonDecode(raw) as List<dynamic>;
    _appFoldersMemory = list
        .map((e) => AppFolder.fromJson(e as Map<String, dynamic>))
        .toList();
    return List<AppFolder>.from(_appFoldersMemory!);
  }

  set appFolders(List<AppFolder> folders) {
    _appFoldersMemory = List<AppFolder>.from(folders);
    prefs?.setString(
      'appFolders',
      jsonEncode(folders.map((f) => f.toJson()).toList()),
    );
    notifyListeners();
  }

  bool get showFolderedAppsOnMainPage =>
      prefs?.getBool('showFolderedAppsOnMainPage') ?? false;

  set showFolderedAppsOnMainPage(bool value) {
    prefs?.setBool('showFolderedAppsOnMainPage', value);
    notifyListeners();
  }

  // ── Per-folder view settings ──────────────────────────────────────────────
  // Stored as JSON maps in SharedPreferences under 'folderView_<id>'.
  // Each getter falls back to the global setting when no override is stored.

  Map<String, dynamic>? _getFolderViewRaw(String folderId) {
    if (_folderViewCache.containsKey(folderId)) {
      return _folderViewCache[folderId];
    }
    final raw = prefs?.getString('folderView_$folderId');
    final result = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
    _folderViewCache[folderId] = result;
    return result;
  }

  void _setFolderViewField(String folderId, String key, dynamic value) {
    final data = Map<String, dynamic>.from(_getFolderViewRaw(folderId) ?? {});
    data[key] = value;
    _folderViewCache[folderId] = data;
    prefs?.setString('folderView_$folderId', jsonEncode(data));
    notifyListeners();
  }

  void clearFolderViewSettings(String folderId) {
    _folderViewCache.remove(folderId);
    prefs?.remove('folderView_$folderId');
    notifyListeners();
  }

  SortColumnSettings folderSortColumn(String id) {
    final idx = _getFolderViewRaw(id)?['sortColumn'] as int?;
    if (idx == null) return sortColumn;
    return SortColumnSettings.values[idx.clamp(
      0,
      SortColumnSettings.values.length - 1,
    )];
  }

  void setFolderSortColumn(String id, SortColumnSettings v) =>
      _setFolderViewField(id, 'sortColumn', v.index);

  SortOrderSettings folderSortOrder(String id) {
    final idx = _getFolderViewRaw(id)?['sortOrder'] as int?;
    if (idx == null) return sortOrder;
    return SortOrderSettings.values[idx.clamp(
      0,
      SortOrderSettings.values.length - 1,
    )];
  }

  void setFolderSortOrder(String id, SortOrderSettings v) =>
      _setFolderViewField(id, 'sortOrder', v.index);

  AppsListGroupBy folderGroupBy(String id) {
    final idx = _getFolderViewRaw(id)?['groupBy'] as int?;
    if (idx == null) return appsListGroupBy;
    return AppsListGroupBy.values[idx.clamp(
      0,
      AppsListGroupBy.values.length - 1,
    )];
  }

  void setFolderGroupBy(String id, AppsListGroupBy v) =>
      _setFolderViewField(id, 'groupBy', v.index);

  bool folderPinUpdates(String id) =>
      (_getFolderViewRaw(id)?['pinUpdates'] as bool?) ?? pinUpdates;

  void setFolderPinUpdates(String id, bool v) =>
      _setFolderViewField(id, 'pinUpdates', v);

  bool folderBuryNonInstalled(String id) =>
      (_getFolderViewRaw(id)?['buryNonInstalled'] as bool?) ?? buryNonInstalled;

  void setFolderBuryNonInstalled(String id, bool v) =>
      _setFolderViewField(id, 'buryNonInstalled', v);

  bool folderGroupNonInstalledSeparately(String id) =>
      (_getFolderViewRaw(id)?['groupNonInstalledSeparately'] as bool?) ??
      groupNonInstalledSeparately;

  void setFolderGroupNonInstalledSeparately(String id, bool v) =>
      _setFolderViewField(id, 'groupNonInstalledSeparately', v);

  bool folderGroupTrackOnlySeparately(String id) =>
      (_getFolderViewRaw(id)?['groupTrackOnlySeparately'] as bool?) ??
      groupTrackOnlySeparately;

  void setFolderGroupTrackOnlySeparately(String id, bool v) =>
      _setFolderViewField(id, 'groupTrackOnlySeparately', v);

  bool folderGroupUpdatesSeparately(String id) =>
      (_getFolderViewRaw(id)?['groupUpdatesSeparately'] as bool?) ??
      groupUpdatesSeparately;

  void setFolderGroupUpdatesSeparately(String id, bool v) =>
      _setFolderViewField(id, 'groupUpdatesSeparately', v);

  Locale? get forcedLocale {
    final Locale? storedLocale = parseStoredLocaleTag(
      prefs?.getString('forcedLocale'),
    );
    if (storedLocale == null) return null;

    final bool isSupported = supportedLocales.any(
      (supportedLocale) => supportedLocale.key == storedLocale,
    );
    return isSupported ? storedLocale : null;
  }

  set forcedLocale(Locale? fl) {
    if (fl == null) {
      prefs?.remove('forcedLocale');
    } else if (supportedLocales.any(
      (supportedLocale) => supportedLocale.key == fl,
    )) {
      prefs?.setString('forcedLocale', fl.toLanguageTag());
    }
    notifyListeners();
  }

  bool setEqual(Set<String> a, Set<String> b) =>
      a.length == b.length && a.union(b).length == a.length;

  Future<void> resetLocaleSafe(BuildContext context) async {
    final Locale bestMatch = resolveBestSupportedLocale(
      deviceLocale: context.deviceLocale,
      supportedLocales: context.supportedLocales,
      fallbackLocale: context.fallbackLocale ?? fallbackLocale,
    );
    if (context.locale == bestMatch) return;

    await context.setLocale(bestMatch);
    if (!context.mounted) return;
    await context.deleteSaveLocale();
  }

  bool get removeOnExternalUninstall {
    return prefs?.getBool('removeOnExternalUninstall') ?? false;
  }

  set removeOnExternalUninstall(bool show) {
    prefs?.setBool('removeOnExternalUninstall', show);
    notifyListeners();
  }

  bool get openAppInfoInAppManager {
    return prefs?.getBool('openAppInfoInAppManager') ?? false;
  }

  set openAppInfoInAppManager(bool value) {
    prefs?.setBool('openAppInfoInAppManager', value);
    notifyListeners();
  }

  bool get enableLetMeDowngrade {
    return prefs?.getBool('enableLetMeDowngrade') ?? true;
  }

  set enableLetMeDowngrade(bool value) {
    prefs?.setBool('enableLetMeDowngrade', value);
    notifyListeners();
  }

  bool get checkUpdateOnDetailPage {
    return prefs?.getBool('checkUpdateOnDetailPage') ?? false;
  }

  set checkUpdateOnDetailPage(bool show) {
    prefs?.setBool('checkUpdateOnDetailPage', show);
    notifyListeners();
  }

  bool get enableBackgroundUpdates {
    return prefs?.getBool('enableBackgroundUpdates') ?? true;
  }

  set enableBackgroundUpdates(bool val) {
    prefs?.setBool('enableBackgroundUpdates', val);
    notifyListeners();
  }

  bool get bgUpdatesOnWiFiOnly {
    return prefs?.getBool('bgUpdatesOnWiFiOnly') ?? false;
  }

  set bgUpdatesOnWiFiOnly(bool val) {
    prefs?.setBool('bgUpdatesOnWiFiOnly', val);
    notifyListeners();
  }

  bool get bgUpdatesWhileChargingOnly {
    return prefs?.getBool('bgUpdatesWhileChargingOnly') ?? false;
  }

  set bgUpdatesWhileChargingOnly(bool val) {
    prefs?.setBool('bgUpdatesWhileChargingOnly', val);
    notifyListeners();
  }

  DateTime get lastCompletedBGCheckTime {
    final int? temp = prefs?.getInt('lastCompletedBGCheckTime');
    return temp != null
        ? DateTime.fromMillisecondsSinceEpoch(temp)
        : DateTime.fromMillisecondsSinceEpoch(0);
  }

  set lastCompletedBGCheckTime(DateTime val) {
    prefs?.setInt('lastCompletedBGCheckTime', val.millisecondsSinceEpoch);
    notifyListeners();
  }

  bool get showDebugOpts {
    return prefs?.getBool('showDebugOpts') ?? false;
  }

  set showDebugOpts(bool val) {
    prefs?.setBool('showDebugOpts', val);
    notifyListeners();
  }

  bool get highlightTouchTargets {
    return prefs?.getBool('highlightTouchTargets') ?? false;
  }

  set highlightTouchTargets(bool val) {
    prefs?.setBool('highlightTouchTargets', val);
    notifyListeners();
  }

  Future<Uri?> getExportDir({
    bool requireAccess = true,
    bool warnIfInaccessible = false,
  }) async {
    final String? uriString = prefs?.getString('exportDir');
    if (uriString == null) {
      return null;
    }
    final Uri uri = Uri.parse(uriString);
    if (!requireAccess) {
      return uri;
    }

    if (!await _canReadAndWriteSafTree(uri)) {
      // Retry once so transient SAF failures do not hide a still-valid grant.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!await _canReadAndWriteSafTree(uri)) {
        if (warnIfInaccessible) {
          _showStorageAccessWarning(isExportDir: true);
        }
        return null;
      }
    }
    return uri;
  }

  /// Lets the user pick a folder for exports. Cancelling the system picker
  /// leaves the previous folder and persisted URI permission unchanged.
  /// Only the replaced export URI is released when the user picks a new tree.
  Future<void> pickExportDir({bool remove = false}) async {
    if (remove) {
      final String? saved = prefs?.getString('exportDir');
      unawaited(prefs?.remove('exportDir'));
      notifyListeners();
      if (saved != null && saved.isNotEmpty) {
        try {
          await saf.releasePersistableUriPermission(Uri.parse(saved));
        } catch (_) {}
      }
      return;
    }

    final String? previousExportDirString = prefs?.getString('exportDir');
    final Uri? newUri = await NativeFeatures.openPersistedDocumentTree(
      initialUri: previousExportDirString == null
          ? null
          : Uri.parse(previousExportDirString),
    );

    if (newUri == null) {
      return;
    }

    final String newUriString = newUri.toString();
    if (previousExportDirString == newUriString) {
      return;
    }

    unawaited(prefs?.setString('exportDir', newUriString));
    notifyListeners();

    if (previousExportDirString != null && previousExportDirString.isNotEmpty) {
      try {
        await saf.releasePersistableUriPermission(
          Uri.parse(previousExportDirString),
        );
      } catch (_) {}
    }
  }

  Future<Uri?> getApkSaveDir({
    bool requireAccess = true,
    bool warnIfInaccessible = false,
  }) async {
    final String? uriString = prefs?.getString('apkSaveDir');
    if (uriString == null) {
      return null;
    }
    final Uri uri = Uri.parse(uriString);
    if (!requireAccess) {
      return uri;
    }

    if (!await _canReadAndWriteSafTree(uri)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!await _canReadAndWriteSafTree(uri)) {
        if (warnIfInaccessible) {
          _showStorageAccessWarning(isExportDir: false);
        }
        return null;
      }
    }
    return uri;
  }

  /// Lets the user pick a folder for saved APK copies. Cancelling leaves the
  /// previous folder and persisted URI permission unchanged.
  Future<void> pickApkSaveDir({bool remove = false}) async {
    if (remove) {
      final String? saved = prefs?.getString('apkSaveDir');
      unawaited(prefs?.remove('apkSaveDir'));
      notifyListeners();
      if (saved != null && saved.isNotEmpty) {
        try {
          await saf.releasePersistableUriPermission(Uri.parse(saved));
        } catch (_) {}
      }
      return;
    }

    final String? previousApkSaveDirString = prefs?.getString('apkSaveDir');
    final Uri? newUri = await NativeFeatures.openPersistedDocumentTree(
      initialUri: previousApkSaveDirString == null
          ? null
          : Uri.parse(previousApkSaveDirString),
    );

    if (newUri == null) {
      return;
    }

    final String newUriString = newUri.toString();
    if (previousApkSaveDirString == newUriString) {
      return;
    }

    unawaited(prefs?.setString('apkSaveDir', newUriString));
    notifyListeners();

    if (previousApkSaveDirString != null &&
        previousApkSaveDirString.isNotEmpty) {
      try {
        await saf.releasePersistableUriPermission(
          Uri.parse(previousApkSaveDirString),
        );
      } catch (_) {}
    }
  }

  Future<bool> _canReadAndWriteSafTree(Uri treeUri) async {
    try {
      if (await NativeFeatures.hasPersistedDocumentTreePermission(treeUri)) {
        final bool canReadTree = await saf.canRead(treeUri) ?? false;
        if (!canReadTree) {
          return false;
        }
        final bool canWriteTree = await saf.canWrite(treeUri) ?? false;
        return canWriteTree;
      }

      final bool canReadTree = await saf.canRead(treeUri) ?? false;
      if (!canReadTree) {
        return false;
      }

      final bool canWriteTree = await saf.canWrite(treeUri) ?? false;
      return canWriteTree;
    } catch (e) {
      debugPrint('Error checking SAF tree permissions: $e');
      return false;
    }
  }

  void _showStorageAccessWarning({required bool isExportDir}) {
    final DateTime now = DateTime.now();
    final DateTime? lastWarningAt = isExportDir
        ? _lastExportDirAccessWarningAt
        : _lastApkSaveDirAccessWarningAt;

    if (lastWarningAt != null &&
        now.difference(lastWarningAt) < _storageAccessWarningCooldown) {
      return;
    }

    if (isExportDir) {
      _lastExportDirAccessWarningAt = now;
    } else {
      _lastApkSaveDirAccessWarningAt = now;
    }

    Fluttertoast.showToast(msg: tr('storagePermissionDenied'));
  }

  /// When true (and an APK save folder is set), copies of downloaded APKs are
  /// persisted under the SAF tree. Default false so picking a folder alone does
  /// not enable copying until the user turns this on.
  bool get saveDownloadedApkCopies {
    return prefs?.getBool('saveDownloadedApkCopies') ?? false;
  }

  set saveDownloadedApkCopies(bool value) {
    prefs?.setBool('saveDownloadedApkCopies', value);
    notifyListeners();
  }

  bool get autoExportOnChanges {
    return prefs?.getBool('autoExportOnChanges') ?? false;
  }

  set autoExportOnChanges(bool val) {
    prefs?.setBool('autoExportOnChanges', val);
    notifyListeners();
  }

  bool get onlyCheckInstalledOrTrackOnlyApps {
    return prefs?.getBool('onlyCheckInstalledOrTrackOnlyApps') ?? true;
  }

  set onlyCheckInstalledOrTrackOnlyApps(bool val) {
    prefs?.setBool('onlyCheckInstalledOrTrackOnlyApps', val);
    notifyListeners();
  }

  int get exportSettings {
    try {
      return prefs?.getInt('exportSettings') ??
          1; // 0 for no, 1 for yes but no secrets, 2 for everything
    } catch (e) {
      final val = prefs?.getBool('exportSettings') == true ? 1 : 0;
      prefs?.setInt('exportSettings', val);
      return val;
    }
  }

  set exportSettings(int val) {
    prefs?.setInt('exportSettings', val > 2 || val < 0 ? 1 : val);
    notifyListeners();
  }

  bool get parallelDownloads {
    return prefs?.getBool('parallelDownloads') ?? false;
  }

  set parallelDownloads(bool val) {
    prefs?.setBool('parallelDownloads', val);
    notifyListeners();
  }

  List<String> get searchDeselected {
    return prefs?.getStringList('searchDeselected') ??
        SourceProvider().sourceTemplates.map((s) => s.name).toList();
  }

  set searchDeselected(List<String> list) {
    prefs?.setStringList('searchDeselected', list);
    notifyListeners();
  }

  bool get beforeNewInstallsShareToAppVerifier {
    return prefs?.getBool('beforeNewInstallsShareToAppVerifier') ?? false;
  }

  set beforeNewInstallsShareToAppVerifier(bool val) {
    prefs?.setBool('beforeNewInstallsShareToAppVerifier', val);
    notifyListeners();
  }

  bool get enableVirusTotalScanning {
    return prefs?.getBool('enableVirusTotalScanning') ?? false;
  }

  set enableVirusTotalScanning(bool val) {
    prefs?.setBool('enableVirusTotalScanning', val);
    notifyListeners();
  }

  bool get shizukuPretendToBeGooglePlay {
    return prefs?.getBool('shizukuPretendToBeGooglePlay') ?? false;
  }

  set shizukuPretendToBeGooglePlay(bool val) {
    prefs?.setBool('shizukuPretendToBeGooglePlay', val);
    notifyListeners();
  }

  bool get useFGService {
    return prefs?.getBool('useFGService') ?? false;
  }

  set useFGService(bool val) {
    prefs?.setBool('useFGService', val);
    notifyListeners();
  }

  SwipeAction get rightSwipeAction {
    return _swipeActionFromPrefs(
      'rightSwipeAction',
      _rightSwipeNameKey,
      SwipeAction.update.index,
    );
  }

  set rightSwipeAction(SwipeAction action) {
    prefs?.setInt('rightSwipeAction', action.index);
    prefs?.setString(_rightSwipeNameKey, action.name);
    notifyListeners();
  }

  SwipeAction get leftSwipeAction {
    return _swipeActionFromPrefs(
      'leftSwipeAction',
      _leftSwipeNameKey,
      SwipeAction.delete.index,
    );
  }

  set leftSwipeAction(SwipeAction action) {
    prefs?.setInt('leftSwipeAction', action.index);
    prefs?.setString(_leftSwipeNameKey, action.name);
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Settings merged from Obtainium upstream.
  //
  // ObtainX's own settings (everything above) are kept intact; these adopt
  // upstream additions that the merged codebase now references. Grouping and the
  // installer setting have been converged onto upstream's pref keys/values (see
  // [appsListGroupBy] and [installerMode]), so those no longer diverge. Theme
  // accents still differ intentionally — ObtainX's accent system
  // ([appAccentColorSource], app_theme_accent.dart) is a superset of upstream's
  // [colourSchemeMode]/[ColourSchemeMode], so both are kept.
  // ───────────────────────────────────────────────────────────────────────────

  // Instance-method haptics (upstream API). ObtainX also exposes the top-level
  // haptic* helpers for call sites that lack a SettingsProvider instance; both
  // honor [tactileFeedbackEnabled].
  void lightImpact() {
    if (tactileFeedbackEnabled) HapticFeedback.lightImpact();
  }

  void heavyImpact() {
    if (tactileFeedbackEnabled) HapticFeedback.heavyImpact();
  }

  void selectionClick() {
    if (tactileFeedbackEnabled) HapticFeedback.selectionClick();
  }

  bool get alwaysUsePhoneLayout {
    return prefs?.getBool('alwaysUsePhoneLayout') ?? false;
  }

  set alwaysUsePhoneLayout(bool val) {
    prefs?.setBool('alwaysUsePhoneLayout', val);
    notifyListeners();
  }

  bool get welcomeShown {
    return prefs?.getBool('welcomeShown') ?? false;
  }

  set welcomeShown(bool val) {
    prefs?.setBool('welcomeShown', val);
    notifyListeners();
  }

  bool get googleVerificationWarningShown {
    return prefs?.getBool('googleVerificationWarningShown') ?? false;
  }

  set googleVerificationWarningShown(bool val) {
    prefs?.setBool('googleVerificationWarningShown', val);
    notifyListeners();
  }

  String? get externalInstallerPackage {
    final value = prefs?.getString('externalInstallerPackage');
    return (value != null && value.isNotEmpty) ? value : null;
  }

  set externalInstallerPackage(String? val) {
    if (val == null || val.isEmpty) {
      prefs?.remove('externalInstallerPackage');
    } else {
      prefs?.setString('externalInstallerPackage', val);
    }
    notifyListeners();
  }

  String? get externalInstallerComponent {
    final value = prefs?.getString('externalInstallerComponent');
    return (value != null && value.isNotEmpty) ? value : null;
  }

  set externalInstallerComponent(String? val) {
    if (val == null || val.isEmpty) {
      prefs?.remove('externalInstallerComponent');
    } else {
      prefs?.setString('externalInstallerComponent', val);
    }
    notifyListeners();
  }

  ColourSchemeMode get colourSchemeMode {
    final stored = prefs?.getInt('colourSchemeMode');
    if (stored != null &&
        stored >= 0 &&
        stored < ColourSchemeMode.values.length) {
      return ColourSchemeMode.values[stored];
    }
    return (prefs?.getBool('useMaterialYou') ?? false)
        ? ColourSchemeMode.materialYou
        : ColourSchemeMode.standard;
  }

  set colourSchemeMode(ColourSchemeMode mode) {
    prefs?.setInt('colourSchemeMode', mode.index);
    prefs?.setBool('useMaterialYou', mode == ColourSchemeMode.materialYou);
    notifyListeners();
  }
}
