import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/pages/home.dart';
import 'package:obtainium/theme.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_system_colors/dynamic_system_colors.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:background_fetch/background_fetch.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
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
  MapEntry(Locale('en', 'EO'), 'Esperanto'),
  MapEntry(Locale('id'), 'Bahasa Indonesia'),
  MapEntry(Locale('ko'), '한국어'),
  MapEntry(Locale('ca'), 'Català'),
  MapEntry(Locale('ar'), 'العربية'),
  MapEntry(Locale('ml'), 'മലയാളം'),
  MapEntry(Locale('gl'), 'Galego'),
];
const fallbackLocale = Locale('en');
const localeDir = 'assets/translations';
bool isFdroidBuild = false;

/// Global navigator key, used to navigate from outside the widget tree
/// (e.g. tapping a notification).
final appNavigatorKey = GlobalKey<NavigatorState>();

const minBackgroundFetchInterval = 15;

@pragma('vm:entry-point')
void backgroundFetchHeadlessTask(HeadlessEvent event) async {
  final String taskId = event.taskId;
  final bool isTimeout = event.timeout;
  try {
    if (isTimeout) {
      unawaited(
        LogsProvider().add('BG update task timed out.', level: LogLevel.error),
      );
      return;
    }
    await bgUpdateCheck(taskId, null);
  } catch (e, stack) {
    unawaited(
      LogsProvider().add(
        'BG headless task crashed: $e\n$stack',
        level: LogLevel.error,
      ),
    );
  } finally {
    unawaited(BackgroundFetch.finish(taskId));
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BackgroundUpdateTaskHandler());
}

class BackgroundUpdateTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      unawaited(LogsProvider().add('onStart(starter: ${starter.name})'));
      await bgUpdateCheck('bg_check', null);
    } catch (e, stack) {
      unawaited(
        LogsProvider().add(
          'BG foreground service onStart crashed: $e\n$stack',
          level: LogLevel.error,
        ),
      );
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    bgUpdateCheck('bg_check', null).catchError((e, stack) {
      LogsProvider().add(
        'BG foreground service onRepeatEvent crashed: $e\n$stack',
        level: LogLevel.error,
      );
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    unawaited(
      LogsProvider().add('Foreground service onDestroy(isTimeout: $isTimeout)'),
    );
  }

  @override
  void onReceiveData(Object data) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  PlatformDispatcher.instance.onError = (error, stack) {
    LogsProvider().add(
      'Uncaught platform error: $error\n$stack',
      level: LogLevel.error,
    );
    return true;
  };

  ErrorWidget.builder = (details) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64),
                const SizedBox(height: 16),
                const Text('An unexpected error occurred.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => SystemNavigator.pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  final logs = LogsProvider();
  final logger = AppLogger(logs: logs);
  final settingsProvider = SettingsProvider();
  final sourceProvider = SourceProvider();
  final appsProvider = AppsProvider(
    settingsProvider: settingsProvider,
    logsProvider: logs,
    logger: logger,
  );
  final np = NotificationsProvider();
  await np.initialize();

  try {
    final ByteData data = await PlatformAssetBundle().load(
      'assets/ca/lets-encrypt-r3.pem',
    );
    SecurityContext.defaultContext.setTrustedCertificatesBytes(
      data.buffer.asUint8List(),
    );
  } catch (e) {
    logger.error('Failed to load custom CA certificate', e);
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
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }
  FlutterForegroundTask.initCommunicationPort();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appsProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        Provider.value(value: np),
        Provider.value(value: logs),
        Provider<Logger>.value(value: logger),
        Provider<SourceProvider>.value(value: sourceProvider),
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
  unawaited(BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask));
}

class Obtainium extends StatefulWidget {
  const Obtainium({super.key});

  @override
  State<Obtainium> createState() => _ObtainiumState();
}

class _ObtainiumState extends State<Obtainium> {
  static const _foregroundServiceId = 666;
  static const _fgTaskRepeatMs = 900000;
  var _lastUpdateInterval = -1;
  var _lastUseFGService = false;
  var _firstRunHandled = false;
  var _launchByNotifChecked = false;
  var _listenerRegistered = false;
  void Function()? _settingsListener;

  void _manageServices(SettingsProvider settings) {
    final interval = settings.updateInterval;
    final useFG = settings.useFGService;
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
    Logger logger,
    BuildContext context,
  ) {
    if (settings.prefs == null) {
      settings.initializeSettings();
      return;
    }
    if (_firstRunHandled) return;
    _firstRunHandled = true;
    final isFirstRun = settings.checkAndFlipFirstRun();
    if (isFirstRun) {
      logger.info('This is the first ever run of Obtainium.');
      if (!isFdroidBuild) {
        getInstalledInfo(obtainiumId)
            .then((value) {
              if (value?.versionName != null) {
                apps.saveApps([
                  App(
                    id: obtainiumId,
                    url: obtainiumUrl,
                    author: 'ImranR98',
                    name: 'Obtainium',
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
              logger.error('Failed to add Obtainium on first run', err);
            });
      }
    }
    final currentLang = context.locale.languageCode;
    final deviceLang = context.deviceLocale.languageCode;
    if (!supportedLocales.map((e) => e.key).contains(context.locale) ||
        (settings.forcedLocale == null && deviceLang != currentLang)) {
      settings.resetLocaleSafe(context);
    }
  }

  @override
  void initState() {
    super.initState();
    initPlatformState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      requestNonOptionalPermissions();
      final settingsProvider = context.read<SettingsProvider>();
      final appsProvider = context.read<AppsProvider>();
      final logger = context.read<Logger>();
      final notifs = context.read<NotificationsProvider>();
      _manageServices(settingsProvider);
      _handleFirstRun(settingsProvider, appsProvider, logger, context);
      if (!_launchByNotifChecked) {
        _launchByNotifChecked = true;
        notifs.checkLaunchByNotif();
      }
      if (!_listenerRegistered) {
        _listenerRegistered = true;
        _settingsListener = () {
          _manageServices(settingsProvider);
          _handleFirstRun(settingsProvider, appsProvider, logger, context);
        };
        settingsProvider.addListener(_settingsListener!);
      }
    });
  }

  Future<void> requestNonOptionalPermissions() async {
    final settingsProvider = context.read<SettingsProvider>();
    final NotificationPermission notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      if (settingsProvider.showBatteryOptimizationPrompt) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    }
  }

  var _fgServiceInitialized = false;

  void initForegroundService() {
    if (_fgServiceInitialized) return;
    _fgServiceInitialized = true;
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
        eventAction: ForegroundTaskEventAction.repeat(_fgTaskRepeatMs),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
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
        serviceId: _foregroundServiceId,
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

  Future<ServiceRequestResult?> stopForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) {
      return FlutterForegroundTask.stopService();
    }
    return null;
  }

  @override
  void dispose() {
    if (_settingsListener != null) {
      try {
        final settingsProvider = context.read<SettingsProvider>();
        settingsProvider.removeListener(_settingsListener!);
      } catch (e) {
        LogsProvider().add(
          'Failed to remove settings listener: $e',
          level: LogLevel.error,
        );
      }
    }
    LogsProvider.close();
    super.dispose();
  }

  Future<void> initPlatformState() async {
    await BackgroundFetch.configure(
      BackgroundFetchConfig(
        minimumFetchInterval: minBackgroundFetchInterval,
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
        await bgUpdateCheck(
          taskId,
          null,
          logs: context.read<LogsProvider>(),
          notifs: context.read<NotificationsProvider>(),
          settings: context.read<SettingsProvider>(),
        );
        unawaited(BackgroundFetch.finish(taskId));
      },
      (String taskId) async {
        unawaited(
          context.read<LogsProvider>().add('BG update task timed out.'),
        );
        unawaited(BackgroundFetch.finish(taskId));
      },
    );
    if (!context.mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settingsProvider = context.watch<SettingsProvider>();

    return WithForegroundTask(
      child: DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
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

          if (settingsProvider.useBlackTheme) {
            darkColorScheme = darkColorScheme
                .copyWith(surface: Colors.black)
                .harmonized();
          }

          if (settingsProvider.useSystemFont) NativeFeatures.loadSystemFont();

          return MaterialApp(
            title: 'Obtainium',
            navigatorKey: appNavigatorKey,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
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
            home: const HomePage(),
            builder: (context, child) => Shortcuts(
              shortcuts: <LogicalKeySet, Intent>{
                LogicalKeySet(LogicalKeyboardKey.select):
                    const ActivateIntent(),
              },
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }
}
