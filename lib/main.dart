import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:obtainium/pages/home.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/native_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_system_colors/dynamic_system_colors.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:background_fetch/background_fetch.dart';
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
  MapEntry(Locale('pt'), 'Português'),
  MapEntry(Locale('pt', 'BR'), 'Brasileiro'),
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
var fdroid = false;

final globalNavigatorKey = GlobalKey<NavigatorState>();

Future<void> loadTranslations() async {
  // See easy_localization/issues/210
  await EasyLocalizationController.initEasyLocation();
  var s = SettingsProvider();
  await s.initializeSettings();
  var forceLocale = s.forcedLocale;
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

@pragma('vm:entry-point')
void backgroundFetchHeadlessTask(HeadlessTask task) async {
  String taskId = task.taskId;
  bool isTimeout = task.timeout;
  if (isTimeout) {
    print('BG update task timed out.');
    BackgroundFetch.finish(taskId);
    return;
  }
  await bgUpdateCheck(taskId, null);
  BackgroundFetch.finish(taskId);
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  static const String incrementCountCommand = 'incrementCount';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('onStart(starter: ${starter.name})');
    bgUpdateCheck('bg_check', null);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    bgUpdateCheck('bg_check', null);
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print('Foreground service onDestroy(isTimeout: $isTimeout)');
  }

  @override
  void onReceiveData(Object data) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    ByteData data = await PlatformAssetBundle().load(
      'assets/ca/lets-encrypt-r3.pem',
    );
    SecurityContext.defaultContext.setTrustedCertificatesBytes(
      data.buffer.asUint8List(),
    );
  } catch (e) {
    // Already added, do nothing (see #375)
  }
  await initializeDateFormatting();
  await EasyLocalization.ensureInitialized();
  if ((await DeviceInfoPlugin().androidInfo).version.sdkInt >= 29) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        statusBarColor: Colors.transparent,
        systemStatusBarContrastEnforced: false,
      ),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  final np = NotificationsProvider();
  await np.initialize();
  FlutterForegroundTask.initCommunicationPort();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AppsProvider()),
        ChangeNotifierProvider(create: (context) => SettingsProvider()),
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
  BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);
}

/// Builds the app-wide Material 3 Expressive [ThemeData] for a given
/// [colorScheme]. Expressive character lives here (large rounded shapes,
/// emphasized motion, updated M3 component looks) so it propagates to every
/// screen without per-widget styling.
ThemeData buildObtainiumTheme(ColorScheme colorScheme, String fontFamily) {
  // Expressive shape tokens: large, generously rounded corners.
  final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(24),
  );
  const buttonShape = StadiumBorder();
  final dialogShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(28),
  );
  final fieldShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );

  // Fully rounded, comfortably-tall buttons (very M3 Expressive).
  final pillButtonStyle = ButtonStyle(
    shape: const WidgetStatePropertyAll(buttonShape),
    minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: fontFamily,
    // Emphasized, springy page transitions for forward navigation.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    cardTheme: CardThemeData(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: cardShape,
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(shape: dialogShape),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    appBarTheme: const AppBarThemeData(centerTitle: false),
    expansionTileTheme: ExpansionTileThemeData(
      shape: cardShape,
      collapsedShape: cardShape,
    ),
    listTileTheme: ListTileThemeData(shape: fieldShape),
    chipTheme: const ChipThemeData(shape: StadiumBorder()),
    searchBarTheme: const SearchBarThemeData(
      elevation: WidgetStatePropertyAll(0),
    ),
    filledButtonTheme: FilledButtonThemeData(style: pillButtonStyle),
    elevatedButtonTheme: ElevatedButtonThemeData(style: pillButtonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: pillButtonStyle),
    textButtonTheme: TextButtonThemeData(
      style: const ButtonStyle(shape: WidgetStatePropertyAll(buttonShape)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
      ),
      menuStyle: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ),
    sliderTheme: SliderThemeData(
      // Opt into the updated (2024) Material 3 slider appearance.
      // ignore: deprecated_member_use
      year2023: false,
      activeTrackColor: colorScheme.primary,
      inactiveTrackColor: colorScheme.surfaceContainerHighest,
      thumbColor: colorScheme.primary,
      overlayColor: colorScheme.primary.withValues(alpha: 0.12),
    ),
    // Opt into the updated (2024) Material 3 Expressive progress indicators
    // (wavy active track / gapped circular) across the whole app.
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      // ignore: deprecated_member_use
      year2023: false,
    ),
  );
}

class Obtainium extends StatefulWidget {
  const Obtainium({super.key});

  @override
  State<Obtainium> createState() => _ObtainiumState();
}

class _ObtainiumState extends State<Obtainium> {
  var _lastUpdateInterval = -1;
  var _lastUseFGService = false;
  var _firstRunHandled = false;

  void _manageServices(SettingsProvider settings) {
    var interval = settings.updateInterval;
    var useFG = settings.useFGService;
    if (interval == _lastUpdateInterval && useFG == _lastUseFGService) return;
    _lastUpdateInterval = interval;
    _lastUseFGService = useFG;
    if (interval == 0) {
      stopForegroundService();
      BackgroundFetch.stop();
    } else if (useFG) {
      BackgroundFetch.stop();
      startForegroundService(false);
    } else {
      stopForegroundService();
      BackgroundFetch.start();
    }
  }

  void _handleFirstRun(
    SettingsProvider settings,
    AppsProvider apps,
    LogsProvider logs,
    BuildContext context,
  ) {
    if (settings.prefs == null) {
      settings.initializeSettings();
      return;
    }
    if (_firstRunHandled) return;
    _firstRunHandled = true;
    var isFirstRun = settings.checkAndFlipFirstRun();
    if (isFirstRun) {
      logs.add('This is the first ever run of Obtainium.');
      if (!fdroid) {
        getInstalledInfo(obtainiumId)
            .then((value) {
              if (value?.versionName != null) {
                apps.saveApps([
                  App(
                    obtainiumId,
                    obtainiumUrl,
                    'ImranR98',
                    'Obtainium',
                    value!.versionName,
                    value.versionName!,
                    [],
                    0,
                    {
                      'versionDetection': true,
                      'apkFilterRegEx': 'fdroid',
                      'invertAPKFilter': true,
                    },
                    null,
                    false,
                  ),
                ], onlyIfExists: false);
              }
            })
            .catchError((err) {
              logs.add('Failed to add Obtainium on first run: $err');
            });
      }
    }
    if (!supportedLocales.map((e) => e.key).contains(context.locale) ||
        (settings.forcedLocale == null &&
            context.deviceLocale != context.locale)) {
      settings.resetLocaleSafe(context);
    }
  }

  @override
  void initState() {
    super.initState();
    initPlatformState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      requestNonOptionalPermissions();
    });
  }

  Future<void> requestNonOptionalPermissions() async {
    final NotificationPermission notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      var settingsProvider = context.read<SettingsProvider>();
      if (settingsProvider.showBatteryOptimizationPrompt) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
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
        notificationIcon: NotificationIcon(
          metaDataName: 'dev.imranr.obtainium.service.NOTIFICATION_ICON',
        ),
        callback: startCallback,
      );
    }
    return null;
  }

  stopForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) {
      return FlutterForegroundTask.stopService();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> initPlatformState() async {
    await BackgroundFetch.configure(
      BackgroundFetchConfig(
        minimumFetchInterval: 15,
        stopOnTerminate: false,
        startOnBoot: true,
        enableHeadless: true,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresStorageNotLow: false,
        requiresDeviceIdle: false,
        requiredNetworkType: NetworkType.ANY,
      ),
      (String taskId) async {
        await bgUpdateCheck(taskId, null);
        BackgroundFetch.finish(taskId);
      },
      (String taskId) async {
        context.read<LogsProvider>().add('BG update task timed out.');
        BackgroundFetch.finish(taskId);
      },
    );
    if (!mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    SettingsProvider settingsProvider = context.watch<SettingsProvider>();
    AppsProvider appsProvider = context.read<AppsProvider>();
    LogsProvider logs = context.read<LogsProvider>();
    NotificationsProvider notifs = context.read<NotificationsProvider>();
    _manageServices(settingsProvider);
    _handleFirstRun(settingsProvider, appsProvider, logs, context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifs.checkLaunchByNotif();
    });

    return WithForegroundTask(
      child: DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          // Decide on a colour/brightness scheme based on OS and user settings
          ColorScheme lightColorScheme;
          ColorScheme darkColorScheme;
          final schemeMode = settingsProvider.colourSchemeMode;
          if (lightDynamic != null &&
              darkDynamic != null &&
              schemeMode == ColourSchemeMode.materialYou) {
            lightColorScheme = lightDynamic.harmonized();
            darkColorScheme = darkDynamic.harmonized();
          } else {
            final variant = switch (schemeMode) {
              ColourSchemeMode.vibrant => DynamicSchemeVariant.vibrant,
              ColourSchemeMode.expressive => DynamicSchemeVariant.expressive,
              _ => DynamicSchemeVariant.tonalSpot,
            };
            lightColorScheme = ColorScheme.fromSeed(
              seedColor: settingsProvider.themeColor,
              dynamicSchemeVariant: variant,
            );
            darkColorScheme = ColorScheme.fromSeed(
              seedColor: settingsProvider.themeColor,
              brightness: Brightness.dark,
              dynamicSchemeVariant: variant,
            );
          }

          // set the background and surface colors to pure black in the amoled theme
          if (settingsProvider.useBlackTheme) {
            darkColorScheme = darkColorScheme
                .copyWith(surface: Colors.black)
                .harmonized();
          }

          if (settingsProvider.useSystemFont) NativeFeatures.loadSystemFont();

          return MaterialApp(
            title: 'Obtainium',
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            navigatorKey: globalNavigatorKey,
            debugShowCheckedModeBanner: false,
            theme: buildObtainiumTheme(
              settingsProvider.theme == ThemeSettings.dark
                  ? darkColorScheme
                  : lightColorScheme,
              settingsProvider.useSystemFont ? 'SystemFont' : 'Montserrat',
            ),
            darkTheme: buildObtainiumTheme(
              settingsProvider.theme == ThemeSettings.light
                  ? lightColorScheme
                  : darkColorScheme,
              settingsProvider.useSystemFont ? 'SystemFont' : 'Montserrat',
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
