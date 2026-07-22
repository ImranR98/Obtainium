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
  await EasyLocalization.ensureInitialized();
  if ((await DeviceInfoPlugin().androidInfo).version.sdkInt >= 29) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(systemNavigationBarColor: Colors.transparent),
    );
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }
  final SettingsProvider settingsProvider = SettingsProvider();
  final np = NotificationsProvider();
  // These three native initializations are independent of one another, so run
  // their platform-channel round-trips concurrently instead of serially to
  // shorten time-to-first-frame. Only settings must complete before runApp
  // (the theme reads it); np/WorkManager are awaited here too but overlap.
  await Future.wait([
    settingsProvider.initializeSettings(),
    np.initialize(),
    Workmanager().initialize(callbackDispatcher),
  ]);
  // The system font (when enabled) is loaded lazily after the first frame in
  // [_ObtainiumState.build] rather than blocking here: reading the font file
  // from disk on the startup path delayed first paint, and FontLoader.load()
  // triggers a repaint of the affected text automatically once it completes.
  FlutterForegroundTask.initCommunicationPort();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => AppsProvider(settingsProvider: settingsProvider),
        ),
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
    return (light: lightColorScheme, dark: darkColorScheme);
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

          // Material 3 styled tooltips used app-wide. The default Flutter
          // tooltip is a small dark rounded-rectangle with white text - a
          // Material 2 holdover. Theming it lifts every Tooltip in the app
          // (action button hover hints, settings help icons, IconButton
          // tooltips on toolbars) to a consistent, M3-themed look without
          // any per-call-site changes.
          //
          // Uses `inverseSurface` / `onInverseSurface` per the M3 spec for
          // plain tooltips: a high-contrast block of colour against the
          // surrounding app surface, so it reads clearly without competing
          // with surrounding content. Auto-flips with light/dark mode
          // because [inverseSurface] is dark in light themes and light in
          // dark themes.
          //
          // [triggerMode] / [waitDuration] / [showDuration] are deliberately
          // NOT theme-set: per-Tooltip overrides drive the interaction
          // semantics (long-press for action buttons, tap for help icons),
          // and we want each call site to keep its current behaviour.
          TooltipThemeData tooltipThemeFor(ColorScheme scheme) {
            return TooltipThemeData(
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

          NavigationBarThemeData navigationBarThemeFor(
            ColorScheme scheme,
            TextTheme appTextTheme,
          ) {
            // Use the app theme's labelMedium so nav labels keep both the M3
            // sizing and the app's active font family.
            final TextStyle navLabelBase = appTextTheme.labelMedium!;
            return NavigationBarThemeData(
              backgroundColor: scheme.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              shadowColor: Colors.transparent,
              indicatorColor: scheme.primary.withValues(alpha: 0.14),
              iconTheme: WidgetStateProperty.resolveWith((
                Set<WidgetState> states,
              ) {
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
          final ThemeData lightBaseTheme = buildObtainiumTheme(
            themeColorScheme,
            appFontFamily,
          );
          final ThemeData darkBaseTheme = buildObtainiumTheme(
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
            // Best-of-both M3E theme: upstream's shape/motion tokens
            // (RoundedSuperellipse cards/dialogs/fields, stadium buttons/chips,
            // FadeForwards page transitions) via [buildObtainiumTheme], layered
            // with the fork's boosted colour science (the passed schemes) plus
            // the fork's vivid surface choices and custom nav/switch/segmented/
            // tooltip themes via copyWith.
            theme: lightBaseTheme.copyWith(
              scaffoldBackgroundColor: themeColorScheme.surface,
              canvasColor: themeColorScheme.surface,
              cardColor: themeColorScheme.surfaceContainer,
              focusColor: themeColorScheme.primary.withValues(alpha: 0.12),
              navigationBarTheme: navigationBarThemeFor(
                themeColorScheme,
                lightBaseTheme.textTheme,
              ),
              segmentedButtonTheme: appSegmentedButtonTheme(themeColorScheme),
              switchTheme: appSwitchTheme(themeColorScheme),
              tooltipTheme: tooltipThemeFor(themeColorScheme),
              // Fork: tighten dialog action padding + text-button tap target
              // (the "dead space under the dialog action row" fix), while
              // keeping buildObtainiumTheme's M3E shapes.
              dialogTheme: appDialogTheme().copyWith(
                shape: lightBaseTheme.dialogTheme.shape,
              ),
              textButtonTheme: TextButtonThemeData(
                style: appTextButtonTheme().style!.merge(
                  lightBaseTheme.textButtonTheme.style,
                ),
              ),
            ),
            darkTheme: darkBaseTheme.copyWith(
              scaffoldBackgroundColor: darkThemeColorScheme.surface,
              canvasColor: darkThemeColorScheme.surface,
              cardColor: darkThemeColorScheme.surfaceContainer,
              focusColor: darkThemeColorScheme.primary.withValues(alpha: 0.24),
              navigationBarTheme: navigationBarThemeFor(
                darkThemeColorScheme,
                darkBaseTheme.textTheme,
              ),
              segmentedButtonTheme: appSegmentedButtonTheme(
                darkThemeColorScheme,
              ),
              switchTheme: appSwitchTheme(darkThemeColorScheme),
              tooltipTheme: tooltipThemeFor(darkThemeColorScheme),
              // Fork: see light theme above.
              dialogTheme: appDialogTheme().copyWith(
                shape: darkBaseTheme.dialogTheme.shape,
              ),
              textButtonTheme: TextButtonThemeData(
                style: appTextButtonTheme().style!.merge(
                  darkBaseTheme.textButtonTheme.style,
                ),
              ),
            ),
            home: Shortcuts(
              shortcuts: <LogicalKeySet, Intent>{
                LogicalKeySet(LogicalKeyboardKey.select):
                    const ActivateIntent(),
              },
              child: const HomePage(),
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
