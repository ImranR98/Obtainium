import 'dart:async' show unawaited;
import 'dart:io' show File;
import 'dart:ui' show PlatformDispatcher, PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/app_distribution.dart';
import 'package:obtainium/app_ui_scaling.dart';
import 'package:obtainium/pages/home.dart';
import 'package:obtainium/custom_errors.dart' show setAppLocale;
import 'package:obtainium/theme/app_dialog_theme.dart';
import 'package:obtainium/theme/app_segmented_button_theme.dart';
import 'package:obtainium/theme/app_text_button_theme.dart';
import 'package:obtainium/theme/app_theme_accent.dart';
import 'package:obtainium/theme/app_switch_theme.dart';
import 'package:obtainium/theme.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';
import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/easy_localization_controller.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

List<MapEntry<Locale, String>> supportedLocales = const [
  MapEntry(Locale('en'), 'English'),
  MapEntry(
    Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
      countryCode: 'TW',
    ),
    '臺灣話',
  ),
  MapEntry(Locale('zh'), '简体中文'),
  MapEntry(Locale('it'), 'Italiano'),
  MapEntry(Locale('ja'), '日本語'),
  MapEntry(Locale('hu'), 'Magyar'),
  MapEntry(Locale('de'), 'Deutsch'),
  MapEntry(Locale('fa'), 'فارسی'),
  MapEntry(Locale('fr'), 'Français'),
  MapEntry(Locale('es'), 'Español'),
  MapEntry(Locale('pl'), 'Polski'),
  MapEntry(Locale('ru'), 'Русский'),
  MapEntry(Locale('bs'), 'Bosanski'),
  MapEntry(Locale('pt', 'BR'), 'Brasileiro'),
  MapEntry(Locale('pt'), 'Português'),
  MapEntry(Locale('cs'), 'Česky'),
  MapEntry(Locale('sv'), 'Svenska'),
  MapEntry(Locale('nl'), 'Nederlands'),
  MapEntry(Locale('vi'), 'Tiếng Việt'),
  MapEntry(Locale('tr'), 'Türkçe'),
  MapEntry(Locale('uk'), 'Українська'),
  MapEntry(Locale('da'), 'Dansk'),
  MapEntry(
    Locale('en', 'EO'),
    'Esperanto',
  ), // https://github.com/aissat/easy_localization/issues/220#issuecomment-846035493
  MapEntry(Locale('in'), 'Bahasa Indonesia'),
  MapEntry(Locale('ko'), '한국어'),
  MapEntry(Locale('ca'), 'Català'),
  MapEntry(Locale('ar'), 'العربية'),
  MapEntry(Locale('ml'), 'മലയാളം'),
  MapEntry(Locale('gl'), 'Galego'),
];
const fallbackLocale = Locale('en');
const localeDir = 'assets/translations';

final globalNavigatorKey = GlobalKey<NavigatorState>();
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
// Lets code outside the shell's subtree (e.g. a pushed folder/app route) reach
// the shell to switch tabs — findAncestorStateOfType can't, since those routes
// are siblings of HomePage under the root navigator, not descendants.
final homePageKey = GlobalKey<HomePageState>();

void installDiagnosticErrorLogging() {
  final logs = LogsProvider(runDefaultClear: false);
  final previousFlutterError = FlutterError.onError;
  final previousPlatformError = PlatformDispatcher.instance.onError;
  unawaited(_recordNativeCrashLogIfPresent(logs));

  FlutterError.onError = (FlutterErrorDetails details) {
    unawaited(
      logs.add(
        _diagnosticErrorMessage(
          'Flutter framework error',
          details.exception,
          details.stack,
          context: details.context?.toDescription(),
          library: details.library,
        ),
        level: LogLevel.error,
      ),
    );
    if (previousFlutterError != null) {
      previousFlutterError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
    unawaited(
      logs.add(
        _diagnosticErrorMessage('Uncaught Dart error', error, stackTrace),
        level: LogLevel.error,
      ),
    );
    return previousPlatformError?.call(error, stackTrace) ?? false;
  };
}

Future<void> _recordNativeCrashLogIfPresent(LogsProvider logs) async {
  final nativeCrashLog = await NativeFeatures.consumeNativeCrashLog();
  if (nativeCrashLog == null) return;
  await logs.add(
    'Native crash from previous run:\n$nativeCrashLog',
    level: LogLevel.error,
  );
}

String _diagnosticErrorMessage(
  String label,
  Object error,
  StackTrace? stackTrace, {
  String? context,
  String? library,
}) {
  final buffer = StringBuffer(label)..writeln(': $error');
  if (library != null && library.isNotEmpty) {
    buffer.writeln('Library: $library');
  }
  if (context != null && context.isNotEmpty) {
    buffer.writeln('Context: $context');
  }
  if (stackTrace != null) {
    buffer.writeln(stackTrace);
  }
  return buffer.toString().trimRight();
}

Future<void> loadTranslations() async {
  // See easy_localization/issues/210
  await EasyLocalizationController.initEasyLocation();
  final s = SettingsProvider();
  await s.initializeSettings();
  final forceLocale = s.forcedLocale;
  final controller = EasyLocalizationController(
    saveLocale: true,
    forceLocale: forceLocale,
    fallbackLocale: fallbackLocale,
    supportedLocales: supportedLocales.map((e) => e.key).toList(),
    assetLoader: const RootBundleAssetLoader(),
    useOnlyLangCode: false,
    useFallbackTranslations: true,
    path: localeDir,
    onLoadError: (FlutterError e) {
      throw e;
    },
  );
  await controller.loadTranslations();
  Localization.load(
    controller.locale,
    translations: controller.translations,
    fallbackTranslations: controller.fallbackTranslations,
  );
}

/// Unique task name used by WorkManager for periodic background update checks.
const _workManagerTaskName = 'obtainiumBgUpdateCheck';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    final logs = LogsProvider();
    try {
      final taskId = 'wm_${DateTime.now().millisecondsSinceEpoch}';
      await bgUpdateCheck(taskId, inputData);
      return true;
    } catch (e, stack) {
      unawaited(
        logs.add(
          'WorkManager callback crashed: $e\n$stack',
          level: LogLevel.error,
        ),
      );
      return false;
    }
  });
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  static const String incrementCountCommand = 'incrementCount';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('onStart(starter: ${starter.name})');
    unawaited(bgUpdateCheck('bg_check', null));
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    bgUpdateCheck('bg_check', null);
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('Foreground service onDestroy(isTimeout: $isTimeout)');
  }

  @override
  void onReceiveData(Object data) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installDiagnosticErrorLogging();
  final SettingsProvider settingsProvider = SettingsProvider();
  final np = NotificationsProvider();
  // These startup round-trips are independent of one another, so run them
  // concurrently instead of serially to shorten time-to-first-frame. Settings
  // must complete before runApp (the theme reads it); EasyLocalization,
  // notifications and WorkManager are awaited here too but overlap. The
  // device-info lookup (only used to choose the system-UI mode below) runs
  // alongside rather than blocking ahead of them.
  final androidInfoFuture = DeviceInfoPlugin().androidInfo;
  await Future.wait([
    EasyLocalization.ensureInitialized(),
    settingsProvider.initializeSettings(),
    np.initialize(),
    Workmanager().initialize(callbackDispatcher),
  ]);
  if ((await androidInfoFuture).version.sdkInt >= 29) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(systemNavigationBarColor: Colors.transparent),
    );
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }
  // The system font (when enabled) is loaded lazily after the first frame in
  // [_ObtainiumState.build] rather than blocking here: reading the font file
  // from disk on the startup path delayed first paint, and FontLoader.load()
  // triggers a repaint of the affected text automatically once it completes.
  FlutterForegroundTask.initCommunicationPort();
  // Construct AppsProvider eagerly (before runApp) so its async init — which
  // ends in the initial loadApps() — starts overlapping the first-frame render
  // instead of running lazily on the first build (which happens after the first
  // frame and left the home list stuck behind a spinner). Settings are already
  // initialized above, so the ctor's initializeSettings() call hits its fast
  // path (no duplicate migrations / native lookups).
  final appsProvider = AppsProvider(settingsProvider: settingsProvider);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appsProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        Provider(create: (context) => np),
        Provider(create: (context) => LogsProvider()),
      ],
      child: EasyLocalization(
        supportedLocales: supportedLocales.map((e) => e.key).toList(),
        path: localeDir,
        fallbackLocale: fallbackLocale,
        useOnlyLangCode: false,
        useFallbackTranslations: true,
        child: const Obtainium(),
      ),
    ),
  );
}

class Obtainium extends StatefulWidget {
  const Obtainium({super.key});

  @override
  State<Obtainium> createState() => _ObtainiumState();
}

class _ObtainiumState extends State<Obtainium> with WidgetsBindingObserver {
  var existingUpdateInterval = -1;

  // Guards the lazy, one-shot attempt to adopt the device's explicit system
  // font family. Kicked off from [build] off the cold-start critical path; the
  // app renders with the OS default font (fontFamily: null) until/unless it
  // applies, at which point we rebuild once to switch to it.
  bool _systemFontLoadStarted = false;

  String? _loadedCustomFontPath;
  bool _customFontLoadFailed = false;

  Future<bool> _loadCustomFont(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final fontLoader = FontLoader('CustomFont');
        final bytes = await file.readAsBytes();
        fontLoader.addFont(Future.value(bytes.buffer.asByteData()));
        await fontLoader.load();
        return true;
      }
    } catch (_) {}
    return false;
  }

  // Cache for the expensive boosted light/dark [ColorScheme]s.
  // [ColorScheme.fromSeed] runs HCT colour-space math and the boost*
  // extensions add several lerp/luminance passes on top. Recomputing both
  // schemes on every MaterialApp rebuild — in particular on a light↔dark↔black
  // flip, which changes none of the seed inputs — blocked the frame the switch
  // landed on and was the dominant cause of the sluggish theme change. We now
  // rebuild the pair only when an input that actually feeds the schemes
  // changes; brightness (`theme`) is deliberately NOT a key, so a pure
  // brightness flip reuses the already-built pair and skips the seed math.
  int? _schemeCacheKey;
  ColorScheme? _cachedLightScheme;
  ColorScheme? _cachedDarkScheme;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      requestNonOptionalPermissions();
    });
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    context.read<SettingsProvider>().updatePlatformBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  Future<void> _scheduleWorkManager() async {
    await Workmanager().registerPeriodicTask(
      _workManagerTaskName,
      _workManagerTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  Future<void> _cancelWorkManager() async {
    await Workmanager().cancelByUniqueName(_workManagerTaskName);
  }

  Future<void> requestNonOptionalPermissions() async {
    final NotificationPermission notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!mounted) return;
    await showBatteryOptimizationWarningIfNeeded();
  }

  Future<void> showBatteryOptimizationWarningIfNeeded() async {
    final SettingsProvider settingsProvider = context.read<SettingsProvider>();
    if (settingsProvider.hideBatteryOptimizationWarning) {
      return;
    }
    final bool isIgnoringBatteryOptimizations =
        await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (!mounted || isIgnoringBatteryOptimizations) {
      return;
    }
    final BuildContext? dialogContext = globalNavigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) return;
    final bool? openSettings = await showDialog<bool>(
      context: dialogContext,
      builder: (BuildContext alertContext) {
        return AlertDialog(
          title: Text(tr('batteryOptimizationWarningTitle')),
          contentPadding: appDialogContentPadding,
          content: Text(tr('batteryOptimizationWarningBody')),
          actions: [
            TextButton(
              onPressed: () {
                settingsProvider.hideBatteryOptimizationWarning = true;
                Navigator.of(alertContext).pop(false);
              },
              child: Text(tr('dontAskAgain')),
            ),
            TextButton(
              onPressed: () => Navigator.of(alertContext).pop(true),
              child: Text(tr('openSettings')),
            ),
          ],
        );
      },
    );
    if (openSettings == true) {
      await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    }
  }

  void initForegroundService() {
    // ignore: invalid_use_of_visible_for_testing_member
    if (!FlutterForegroundTask.isInitialized) {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'bg_update',
          channelName: tr('foregroundService'),
          channelDescription: tr('foregroundService'),
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(900000),
          autoRunOnBoot: true,
          autoRunOnMyPackageReplaced: true,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
    }
  }

  Future<ServiceRequestResult?> startForegroundService(bool restart) async {
    initForegroundService();
    if (await FlutterForegroundTask.isRunningService) {
      if (restart) {
        return FlutterForegroundTask.restartService();
      }
    } else {
      return FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.specialUse],
        serviceId: 666,
        notificationTitle: tr('foregroundService'),
        notificationText: tr('fgServiceNotice'),
        notificationIcon: const NotificationIcon(
          metaDataName: 'dev.imranr.obtainium.service.NOTIFICATION_ICON',
        ),
        callback: startCallback,
      );
    }
    return null;
  }

  Future<dynamic> stopForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) {
      return FlutterForegroundTask.stopService();
    }
  }

  // void onReceiveForegroundServiceData(Object data) {
  //   print('onReceiveTaskData: $data');
  // }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Remove a callback to receive data sent from the TaskHandler.
    // FlutterForegroundTask.removeTaskDataCallback(onReceiveForegroundServiceData);
    super.dispose();
  }

  /// Builds (or reuses) the boosted light + dark [ColorScheme] pair for the
  /// current accent/palette/black/gradient/shading settings and the supplied
  /// dynamic colour schemes. See [_schemeCacheKey] for why this is cached.
  ({ColorScheme light, ColorScheme dark}) _resolveThemeSchemes(
    SettingsProvider settings,
    ColorScheme? lightDynamic,
    ColorScheme? darkDynamic,
  ) {
    final int key = Object.hash(
      settings.appAccentColorSource,
      settings.appThemePaletteStyle,
      settings.activeCustomSeedHex,
      settings.useGradientBackground,
      settings.shadingIntensity,
      settings.useBlackTheme,
      lightDynamic,
      darkDynamic,
    );
    if (key == _schemeCacheKey &&
        _cachedLightScheme != null &&
        _cachedDarkScheme != null) {
      return (light: _cachedLightScheme!, dark: _cachedDarkScheme!);
    }

    // Decide on a colour/brightness scheme based on OS and user settings
    ColorScheme lightColorScheme = colorSchemeForAccentSettings(
      brightness: Brightness.light,
      accentSource: settings.appAccentColorSource,
      paletteStyle: settings.appThemePaletteStyle,
      lightDynamic: lightDynamic,
      darkDynamic: darkDynamic,
      activeCustomSeedHex: settings.activeCustomSeedHex,
    );
    ColorScheme darkColorScheme = colorSchemeForAccentSettings(
      brightness: Brightness.dark,
      accentSource: settings.appAccentColorSource,
      paletteStyle: settings.appThemePaletteStyle,
      lightDynamic: lightDynamic,
      darkDynamic: darkDynamic,
      activeCustomSeedHex: settings.activeCustomSeedHex,
    );

    // Boost surface containers toward primary — ports FilePipe's
    // boostSurfaceContainersTowardPrimary* logic that makes surfaces vivid.
    final bool useGradient = settings.useGradientBackground;
    lightColorScheme = lightColorScheme.boostSurfaceContainersTowardPrimary(
      darkTheme: false,
      useGradient: useGradient,
      shadingIntensity: settings.shadingIntensity,
    );
    darkColorScheme = darkColorScheme.boostSurfaceContainersTowardPrimary(
      darkTheme: true,
      useGradient: useGradient,
      shadingIntensity: settings.shadingIntensity,
    );
    if (settings.appAccentColorSource != AppAccentColorSource.materialYou) {
      lightColorScheme = lightColorScheme.boostContainersForSeedThemes(
        darkTheme: false,
      );
      darkColorScheme = darkColorScheme.boostContainersForSeedThemes(
        darkTheme: true,
      );
    }
    if (settings.useBlackTheme) {
      darkColorScheme = darkColorScheme.withPureBlackBackgrounds();
    }

    _schemeCacheKey = key;
    _cachedLightScheme = lightColorScheme;
    _cachedDarkScheme = darkColorScheme;
    // The scheme pair changed, so any ThemeData memoized against the old schemes
    // is stale; drop it (only the new light/dark pair gets re-cached below).
    _appThemeCache.clear();
    return (light: lightColorScheme, dark: darkColorScheme);
  }

  // Fully-built app ThemeData (base theme + all app-wide sub-themes) memoized
  // per (ColorScheme, fontFamily). buildObtainiumTheme() and the sub-themes are
  // pure functions of those two inputs, so this lets rebuilds (settings/theme
  // toggles) reuse a prebuilt ThemeData — and lets a forced light/dark theme,
  // whose two MaterialApp slots share one scheme, build it only once. The
  // ColorScheme instances handed out by [_resolveThemeSchemes] are themselves
  // cached, so the map lookup hits by identity and stays bounded to the live
  // light/dark pair (see the clear() above).
  String? _appThemeCacheFont;
  final Map<ColorScheme, ThemeData> _appThemeCache = {};

  ThemeData _resolveAppThemeData(ColorScheme scheme, String? fontFamily) {
    if (_appThemeCacheFont != fontFamily) {
      _appThemeCache.clear();
      _appThemeCacheFont = fontFamily;
    }
    return _appThemeCache[scheme] ??= _buildAppThemeData(scheme, fontFamily);
  }

  ThemeData _buildAppThemeData(ColorScheme scheme, String? fontFamily) {
    // Best-of-both M3E theme: upstream's shape/motion tokens (RoundedSuperellipse
    // cards/dialogs/fields, stadium buttons/chips, FadeForwards page transitions)
    // via [buildObtainiumTheme], layered with the fork's boosted colour science
    // (the passed scheme) plus the fork's vivid surface choices and custom
    // nav/switch/segmented/tooltip themes via copyWith.
    final ThemeData base = buildObtainiumTheme(scheme, fontFamily);
    // Focus overlay opacity tracks brightness (subtler in light, stronger in
    // dark) rather than the MaterialApp theme/darkTheme slot, so a forced
    // single-brightness theme produces one identical ThemeData for both slots.
    final double focusAlpha = scheme.brightness == Brightness.dark
        ? 0.24
        : 0.12;
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      cardColor: scheme.surfaceContainer,
      focusColor: scheme.primary.withValues(alpha: focusAlpha),
      navigationBarTheme: _navigationBarThemeFor(scheme, base.textTheme),
      segmentedButtonTheme: appSegmentedButtonTheme(scheme),
      switchTheme: appSwitchTheme(scheme),
      tooltipTheme: _tooltipThemeFor(scheme),
      // Fork: tighten dialog action padding + text-button tap target (the "dead
      // space under the dialog action row" fix), keeping the M3E shapes.
      dialogTheme: appDialogTheme().copyWith(shape: base.dialogTheme.shape),
      textButtonTheme: TextButtonThemeData(
        style: appTextButtonTheme().style!.merge(base.textButtonTheme.style),
      ),
    );
  }

  // Material 3 styled tooltips used app-wide. The default Flutter tooltip is a
  // small dark rounded-rectangle with white text - a Material 2 holdover.
  // Theming it lifts every Tooltip in the app (action button hover hints,
  // settings help icons, IconButton tooltips on toolbars) to a consistent,
  // M3-themed look without any per-call-site changes.
  //
  // Uses `inverseSurface` / `onInverseSurface` per the M3 spec for plain
  // tooltips: a high-contrast block of colour against the surrounding app
  // surface. Auto-flips with light/dark mode because [inverseSurface] is dark in
  // light themes and light in dark themes.
  //
  // Default [triggerMode] is manual so Flutter does not attach a global pointer
  // listener on every [Tooltip] (long-press mode). Rebuilding the tree during
  // pointer routing used to recreate [RawTooltipState] and spam "multiple
  // tickers" framework errors. Call sites that need visible tooltips (e.g.
  // [HelpHintIcon]) set triggerMode explicitly.
  TooltipThemeData _tooltipThemeFor(ColorScheme scheme) {
    return TooltipThemeData(
      triggerMode: TooltipTriggerMode.manual,
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: TextStyle(
        color: scheme.onInverseSurface,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      preferBelow: true,
    );
  }

  NavigationBarThemeData _navigationBarThemeFor(
    ColorScheme scheme,
    TextTheme appTextTheme,
  ) {
    // Use the app theme's labelMedium so nav labels keep both the M3 sizing and
    // the app's active font family.
    final TextStyle navLabelBase = appTextTheme.labelMedium!;
    return NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
      iconTheme: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: scheme.primary);
        }
        return IconThemeData(color: scheme.onSurfaceVariant);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.disabled)) {
          return navLabelBase.copyWith(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.38),
          );
        }
        if (states.contains(WidgetState.selected)) {
          return navLabelBase.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w600,
          );
        }
        return navLabelBase.copyWith(color: scheme.onSurfaceVariant);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Same pattern as on the apps page: subscribe to a hash of the
    // SettingsProvider fields this build actually reads, then grab the
    // instance via [context.read] for non-reactive access. Without this,
    // every notify (categories, swipe actions, sort columns, folders,
    // …) rebuilds the entire MaterialApp tree even though those settings
    // don't affect anything inside this build method.
    context.select<SettingsProvider, int>(
      (s) => Object.hash(
        s.updateInterval,
        s.useFGService,
        s.prefs == null,
        s.forcedLocale,
        s.appAccentColorSource,
        s.appThemePaletteStyle,
        s.activeCustomSeedHex,
        s.useBlackTheme,
        s.useGradientBackground,
        s.shadingIntensity,
        s.theme,
        s.appUiScale,
        s.customFontPath,
        s.customFontName,
      ),
    );
    final SettingsProvider settingsProvider = context.read<SettingsProvider>();

    if (settingsProvider.customFontPath != _loadedCustomFontPath) {
      final String? fontPath = settingsProvider.customFontPath;
      _loadedCustomFontPath = fontPath;
      _customFontLoadFailed = false;
      if (fontPath != null) {
        _loadCustomFont(fontPath).then((success) {
          if (mounted) {
            if (!success) {
              _customFontLoadFailed = true;
            }
            setState(() {});
          }
        });
      }
    }

    // The app renders with the OS system font by default (fontFamily: null),
    // which paints immediately with real weights. Off the startup critical
    // path we then try to adopt the device's exact font family explicitly (see
    // [NativeFeatures.loadSystemFont]); if it applies a multi-weight family we
    // rebuild once so the theme switches null -> 'SystemFont'. On a modern
    // single-variable-font device this is a no-op and we stay on the default.
    if (!_systemFontLoadStarted) {
      _systemFontLoadStarted = true;
      NativeFeatures.loadSystemFont().then((_) {
        if (mounted && NativeFeatures.systemFontApplied) {
          setState(() {});
        }
      });
    }
    final AppsProvider appsProvider = context.read<AppsProvider>();
    final LogsProvider logs = context.read<LogsProvider>();
    final NotificationsProvider notifs = context.read<NotificationsProvider>();
    if (settingsProvider.updateInterval == 0) {
      stopForegroundService();
      unawaited(_cancelWorkManager());
    } else {
      if (settingsProvider.useFGService) {
        unawaited(_cancelWorkManager());
        startForegroundService(false);
      } else {
        stopForegroundService();
        unawaited(_scheduleWorkManager());
      }
    }
    if (settingsProvider.prefs == null) {
      settingsProvider.initializeSettings();
    } else {
      final bool isFirstRun = settingsProvider.checkAndFlipFirstRun();
      if (isFirstRun) {
        logs.add('This is the first ever run of ObtainX.');
        if (!settingsProvider.isTV) {
          unawaited(Permission.notification.request());
        }
        // If this is the first run, add ObtainX to the Apps list
        if (!AppDistribution.fdroid) {
          getInstalledInfo(obtainiumId, includeOwnDebugBuild: true)
              .then((value) {
                if (value?.versionName != null) {
                  appsProvider.saveApps([
                    App(
                      id: obtainiumId,
                      url: obtainiumUrl,
                      author: 'Bikram-Agarwal',
                      name: 'ObtainX',
                      installedVersion: value!.versionName,
                      latestVersion: value.versionName!,
                      apkUrls: [],
                      preferredApkIndex: 0,
                      additionalSettings: {
                        'versionDetection': 'auto',
                        'apkFilterRegEx': 'fdroid',
                        'invertAPKFilter': true,
                      },
                      lastUpdateCheck: null,
                      pinned: false,
                    ),
                  ], onlyIfExists: false);
                }
              })
              .catchError((err) {
                debugPrint(err.toString());
              });
        }
      }
      final forcedLocale = settingsProvider.forcedLocale;
      if (forcedLocale != null) {
        if (context.locale != forcedLocale) {
          unawaited(context.setLocale(forcedLocale));
        }
      } else {
        unawaited(settingsProvider.resetLocaleSafe(context));
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifs.checkLaunchByNotif();
    });

    return WithForegroundTask(
      child: DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          final ({ColorScheme light, ColorScheme dark}) schemes =
              _resolveThemeSchemes(settingsProvider, lightDynamic, darkDynamic);
          final ColorScheme lightColorScheme = schemes.light;
          final ColorScheme darkColorScheme = schemes.dark;

          final ColorScheme themeColorScheme =
              settingsProvider.theme == ThemeSettings.dark
              ? darkColorScheme
              : lightColorScheme;
          final ColorScheme darkThemeColorScheme =
              settingsProvider.theme == ThemeSettings.light
              ? lightColorScheme
              : darkColorScheme;

          // Keep the locale-aware English detection in custom_errors.dart in
          // sync (drives lowerCaseIfEnglish / list2FriendlyString). Without
          // this, isEnglish() is stuck false and English strings never get
          // lowercased — parity with fork main.
          setAppLocale(context.locale);
          // Default to the OS system font (null lets Flutter resolve the
          // platform font with real weights). Once an explicit multi-weight
          // device family is loaded, switch to it so a user-picked OEM font is
          // honoured. Montserrat is no longer bundled.
          final String? appFontFamily =
              (settingsProvider.customFontPath != null &&
                  !_customFontLoadFailed)
              ? 'CustomFont'
              : (NativeFeatures.systemFontApplied ? 'SystemFont' : null);
          // Resolve both MaterialApp theme slots through the memoized builder:
          // a forced light/dark theme (same scheme for both slots) builds its
          // ThemeData once, and rebuilds reuse the prebuilt objects instead of
          // reconstructing buildObtainiumTheme + every sub-theme each frame.
          final ThemeData lightTheme = _resolveAppThemeData(
            themeColorScheme,
            appFontFamily,
          );
          final ThemeData darkTheme = _resolveAppThemeData(
            darkThemeColorScheme,
            appFontFamily,
          );
          return MaterialApp(
            title: 'ObtainX',
            scrollBehavior: const AppScrollBehavior(),
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            navigatorKey: globalNavigatorKey,
            scaffoldMessengerKey: scaffoldMessengerKey,
            debugShowCheckedModeBanner: false,
            themeAnimationDuration: Duration.zero,
            // Cap the system scaler globally before applying the in-app UI
            // scale. The default preserves Flutter's non-linear curve; a
            // custom app scale uses a bounded linear approximation.
            builder: (BuildContext context, Widget? child) {
              final MediaQueryData mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(
                  textScaler: cappedAppTextScaler(
                    systemTextScaler: mq.textScaler,
                    userScale: settingsProvider.appUiScale,
                    minimumEffectiveScale: SettingsProvider.appUiScaleMin,
                    maximumEffectiveScale: SettingsProvider.appUiScaleMax,
                  ),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            // Best-of-both M3E theme, built and memoized by
            // [_resolveAppThemeData]: upstream's shape/motion tokens layered
            // with the fork's boosted colour science and custom
            // nav/switch/segmented/tooltip themes.
            theme: lightTheme,
            darkTheme: darkTheme,
            home: Shortcuts(
              shortcuts: <LogicalKeySet, Intent>{
                LogicalKeySet(LogicalKeyboardKey.select):
                    const ActivateIntent(),
              },
              child: HomePage(key: homePageKey),
            ),
          );
        },
      ),
    );
  }
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
