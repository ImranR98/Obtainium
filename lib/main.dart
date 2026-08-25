import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/utils/native_features.dart';
import 'package:obtainium/pages/home.dart';
import 'package:obtainium/theme.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_system_colors/dynamic_system_colors.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';

List<MapEntry<Locale, String>> supportedLocales = const [
  MapEntry(Locale('en'), 'English'),
  MapEntry(Locale('zh', 'Hant_TW'), '臺灣話'),
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
  MapEntry(Locale('en', 'EO'), 'Esperanto'),
  MapEntry(Locale('id'), 'Bahasa Indonesia'),
  MapEntry(Locale('ko'), '한국어'),
  MapEntry(Locale('ca'), 'Català'),
  MapEntry(Locale('ar'), 'العربية'),
  MapEntry(Locale('ml'), 'മലയാളം'),
  MapEntry(Locale('gl'), 'Galego'),
];
const fallbackLocale = Locale('en');
final Set<Locale> supportedLocaleSet = supportedLocales
    .map((e) => e.key)
    .toSet();
const localeDir = 'assets/translations';
bool isFdroidBuild = false;

const String _unexpectedErrorText = 'An unexpected error occurred.';
const String _closeText = 'Close';

/// Global navigator key, used to navigate from outside the widget tree
/// (e.g. tapping a notification).
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Unique task name used by WorkManager for periodic background update checks.
const _workManagerTaskName = 'obtainiumBgUpdateCheck';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppLogger.init();
    try {
      AppLogger.info('WorkManager callback invoked (task: $taskName)');
      final taskId = 'wm_${DateTime.now().millisecondsSinceEpoch}';
      await bgUpdateCheck(taskId, inputData);
      AppLogger.info('WorkManager callback completed successfully');
      return true;
    } catch (e, stack) {
      AppLogger.error(
        e,
        stackTrace: stack,
        message: 'WorkManager callback crashed',
      );
      return false;
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.init();

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error(
      error,
      stackTrace: stack,
      message: 'Uncaught platform error',
    );
    return true;
  };

  // Exceptions thrown in UI handlers are reported to FlutterError.onError
  // rather than PlatformDispatcher.onError, so hook both into the log store.
  final prevFlutterErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    prevFlutterErrorHandler?.call(details);
    AppLogger.error(
      details.exception,
      stackTrace: details.stack,
      message: 'Uncaught framework error',
    );
  };

  final settingsProvider = SettingsProvider();
  final sourceProvider = SourceProvider();
  final appsProvider = AppsProvider(settingsProvider: settingsProvider);
  final np = NotificationsProvider();
  await np.initialize();

  await initializeDateFormatting();
  await EasyLocalization.ensureInitialized();

  ErrorWidget.builder = (details) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 64),
                SizedBox(height: 16),
                Text(_unexpectedErrorText),
                SizedBox(height: 16),
                FilledButton(
                  onPressed: SystemNavigator.pop,
                  child: Text(_closeText),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

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

  await Workmanager().initialize(callbackDispatcher);
  AppLogger.info('WorkManager initialised');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appsProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        Provider.value(value: np),
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
}

class Obtainium extends StatefulWidget {
  const Obtainium({super.key});

  @override
  State<Obtainium> createState() => _ObtainiumState();
}

class _ObtainiumState extends State<Obtainium> {
  var _firstRunHandled = false;
  var _launchByNotifChecked = false;
  Locale? _lastLocale;

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

  void _handleFirstRun(
    SettingsProvider settings,
    AppsProvider apps,
    BuildContext context,
  ) {
    if (_firstRunHandled) return;
    _firstRunHandled = true;
    final isFirstRun = settings.checkAndFlipFirstRun();
    if (isFirstRun) {
      AppLogger.info('This is the first ever run of Obtainium.');
      if (!settings.isTV) {
        unawaited(Permission.notification.request());
      }
      if (!isFdroidBuild) {
        getInstalledInfo(obtainiumId)
            .then((value) {
              if (value?.versionName != null) {
                unawaited(
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
                  ], onlyIfExists: false),
                );
              }
            })
            .catchError((err, stack) {
              AppLogger.error(
                err,
                stackTrace: stack,
                message: 'Failed to add Obtainium on first run',
              );
            });
      }
    }
    final currentLang = context.locale.languageCode;
    final deviceLang = context.deviceLocale.languageCode;
    if (!supportedLocaleSet.contains(context.locale) ||
        (settings.forcedLocale == null && deviceLang != currentLang)) {
      settings.resetLocaleSafe(context);
    } else if (settings.forcedLocale != null) {
      context.setLocale(settings.forcedLocale!);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final settingsProvider = context.read<SettingsProvider>();
      await settingsProvider.initializeSettings();
      if (!mounted) return;
      final appsProvider = context.read<AppsProvider>();
      final notifs = context.read<NotificationsProvider>();

      unawaited(_scheduleWorkManager());
      _handleFirstRun(settingsProvider, appsProvider, context);

      if (!_launchByNotifChecked) {
        _launchByNotifChecked = true;
        unawaited(notifs.checkLaunchByNotif());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.select<SettingsProvider, Color>(
      (p) => p.themeColor,
    );
    final colourSchemeMode = context.select<SettingsProvider, ColourSchemeMode>(
      (p) => p.colourSchemeMode,
    );
    final useBlackTheme = context.select<SettingsProvider, bool>(
      (p) => p.useBlackTheme,
    );
    final themeSetting = context.select<SettingsProvider, ThemeSettings>(
      (p) => p.theme,
    );
    final useSystemFont = context.select<SettingsProvider, bool>(
      (p) => p.useSystemFont,
    );

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme lightColorScheme;
        ColorScheme darkColorScheme;
        final schemeMode = colourSchemeMode;
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
            seedColor: themeColor,
            dynamicSchemeVariant: variant,
          );
          darkColorScheme = ColorScheme.fromSeed(
            seedColor: themeColor,
            brightness: Brightness.dark,
            dynamicSchemeVariant: variant,
          );
        }

        if (useBlackTheme) {
          darkColorScheme = darkColorScheme.harmonized().copyWith(
            surface: Colors.black,
          );
        }

        if (useSystemFont) {
          unawaited(NativeFeatures.loadSystemFont());
        }

        return MaterialApp(
          title: 'Obtainium',
          navigatorKey: appNavigatorKey,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          debugShowCheckedModeBanner: false,
          theme: buildObtainiumTheme(
            themeSetting == ThemeSettings.dark
                ? darkColorScheme
                : lightColorScheme,
            useSystemFont ? 'SystemFont' : 'Montserrat',
          ),
          darkTheme: buildObtainiumTheme(
            themeSetting == ThemeSettings.light
                ? lightColorScheme
                : darkColorScheme,
            useSystemFont ? 'SystemFont' : 'Montserrat',
          ),
          home: const HomePage(),
          builder: (context, child) {
            if (context.locale != _lastLocale) {
              _lastLocale = context.locale;
              setAppLocale(context.locale);
            }
            return Shortcuts(
              shortcuts: <LogicalKeySet, Intent>{
                LogicalKeySet(LogicalKeyboardKey.select):
                    const ActivateIntent(),
              },
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}
