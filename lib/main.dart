import 'dart:async' show unawaited;
import 'dart:ui' show PlatformDispatcher, PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/app_distribution.dart';
import 'package:obtainium/pages/home.dart';
import 'package:obtainium/theme/app_dialog_theme.dart';
import 'package:obtainium/theme/app_segmented_button_theme.dart';
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
import 'package:workmanager/workmanager.dart';
import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/easy_localization_controller.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

List<MapEntry<Locale, String>> supportedLocales = const [
  MapEntry(Locale('en'), 'English'),
  MapEntry(Locale('zh'), '简体中文'),
  MapEntry(Locale('zh', 'Hant_TW'), '臺灣話'),
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
  await settingsProvider.initializeSettings();
  if (settingsProvider.useSystemFont) {
    await NativeFeatures.loadSystemFont();
  }
  final np = NotificationsProvider();
  await np.initialize();
  FlutterForegroundTask.initCommunicationPort();
  await Workmanager().initialize(callbackDispatcher);
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

class _ObtainiumState extends State<Obtainium> {
  var existingUpdateInterval = -1;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      requestNonOptionalPermissions();
    });
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
        s.useSystemFont,
        s.theme,
        s.appUiScale,
      ),
    );
    final SettingsProvider settingsProvider = context.read<SettingsProvider>();
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
                        'versionDetection': true,
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
      if (!supportedLocales.map((e) => e.key).contains(context.locale) ||
          (settingsProvider.forcedLocale == null &&
              context.deviceLocale != context.locale)) {
        settingsProvider.resetLocaleSafe(context);
      } else if (settingsProvider.forcedLocale != null) {
        // #3052: re-apply a configured forced locale explicitly so it survives
        // easy_localization's internal resolution, which can otherwise revert a
        // country-specific locale (e.g. pt_BR) to a language-only match (pt_PT).
        context.setLocale(settingsProvider.forcedLocale!);
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

          NavigationBarThemeData navigationBarThemeFor(ColorScheme scheme) {
            // Use labelMedium as base so nav labels keep M3 size (bare color-only TextStyle inherits body scale and can wrap).
            final TextStyle navLabelBase = Theme.of(
              context,
            ).textTheme.labelMedium!;
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
            // App-wide UI scale. The user controls scaling via the
            // [SettingsProvider.appUiScale] slider in the Settings page.
            // When the slider is at the default 1.0 we return the child
            // unwrapped, so the OS-reported MediaQuery (including any
            // non-linear textScaler curve) flows through untouched. When
            // the slider is off-default we multiply the OS scaler by the
            // user's factor and replace it with a linear approximation.
            builder: (BuildContext context, Widget? child) {
              final double userScale = settingsProvider.appUiScale;
              if (userScale == 1.0) {
                return child ?? const SizedBox.shrink();
              }
              final MediaQueryData mq = MediaQuery.of(context);
              const double referenceSize = 14.0;
              final double systemFactor =
                  mq.textScaler.scale(referenceSize) / referenceSize;
              return MediaQuery(
                data: mq.copyWith(
                  textScaler: TextScaler.linear(systemFactor * userScale),
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
            theme:
                buildObtainiumTheme(
                  themeColorScheme,
                  settingsProvider.useSystemFont ? 'SystemFont' : 'Montserrat',
                ).copyWith(
                  scaffoldBackgroundColor: themeColorScheme.surface,
                  canvasColor: themeColorScheme.surface,
                  cardColor: themeColorScheme.surfaceContainer,
                  focusColor: themeColorScheme.primary.withValues(alpha: 0.12),
                  navigationBarTheme: navigationBarThemeFor(themeColorScheme),
                  segmentedButtonTheme: appSegmentedButtonTheme(
                    themeColorScheme,
                  ),
                  switchTheme: appSwitchTheme(themeColorScheme),
                  tooltipTheme: tooltipThemeFor(themeColorScheme),
                ),
            darkTheme:
                buildObtainiumTheme(
                  darkThemeColorScheme,
                  settingsProvider.useSystemFont ? 'SystemFont' : 'Montserrat',
                ).copyWith(
                  scaffoldBackgroundColor: darkThemeColorScheme.surface,
                  canvasColor: darkThemeColorScheme.surface,
                  cardColor: darkThemeColorScheme.surfaceContainer,
                  focusColor: darkThemeColorScheme.primary.withValues(
                    alpha: 0.24,
                  ),
                  navigationBarTheme: navigationBarThemeFor(
                    darkThemeColorScheme,
                  ),
                  segmentedButtonTheme: appSegmentedButtonTheme(
                    darkThemeColorScheme,
                  ),
                  switchTheme: appSwitchTheme(darkThemeColorScheme),
                  tooltipTheme: tooltipThemeFor(darkThemeColorScheme),
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
