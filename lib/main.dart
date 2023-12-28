import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/pages/home.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:background_fetch/background_fetch.dart';
import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/easy_localization_controller.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';

const String currentVersion = '0.14.41';
const String currentReleaseTag =
    'v$currentVersion-beta'; // KEEP THIS IN SYNC WITH GITHUB RELEASES

const int bgUpdateCheckAlarmId = 666;

List<MapEntry<Locale, String>> supportedLocales = const [
  MapEntry(Locale('en'), 'English'),
  MapEntry(Locale('zh'), '简体中文'),
  MapEntry(Locale('it'), 'Italiano'),
  MapEntry(Locale('ja'), '日本語'),
  MapEntry(Locale('hu'), 'Magyar'),
  MapEntry(Locale('de'), 'Deutsch'),
  MapEntry(Locale('fa'), 'فارسی'),
  MapEntry(Locale('fr'), 'Français'),
  MapEntry(Locale('es'), 'Español'),
  MapEntry(Locale('pl'), 'Polski'),
  MapEntry(Locale('ru'), 'Русский язык'),
  MapEntry(Locale('bs'), 'Bosanski'),
  MapEntry(Locale('pt'), 'Brasileiro'),
  MapEntry(Locale('cs'), 'Česky'),
  MapEntry(Locale('sv'), 'Svenska'),
  MapEntry(Locale('nl'), 'Nederlands'),
  MapEntry(Locale('vi'), 'Tiếng Việt'),
  MapEntry(Locale('tr'), 'Türkçe'),
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
    forceLocale: forceLocale != null ? Locale(forceLocale) : null,
    fallbackLocale: fallbackLocale,
    supportedLocales: supportedLocales.map((e) => e.key).toList(),
    assetLoader: const RootBundleAssetLoader(),
    useOnlyLangCode: true,
    useFallbackTranslations: true,
    path: localeDir,
    onLoadError: (FlutterError e) {
      throw e;
    },
  );
  await controller.loadTranslations();
  Localization.load(controller.locale,
      translations: controller.translations,
      fallbackTranslations: controller.fallbackTranslations);
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    ByteData data =
        await PlatformAssetBundle().load('assets/ca/lets-encrypt-r3.pem');
    SecurityContext.defaultContext
        .setTrustedCertificatesBytes(data.buffer.asUint8List());
  } catch (e) {
    // Already added, do nothing (see #375)
  }
  await EasyLocalization.ensureInitialized();
  if ((await DeviceInfoPlugin().androidInfo).version.sdkInt >= 29) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(systemNavigationBarColor: Colors.transparent),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (context) => AppsProvider()),
      ChangeNotifierProvider(create: (context) => SettingsProvider()),
      Provider(create: (context) => NotificationsProvider()),
      Provider(create: (context) => LogsProvider())
    ],
    child: EasyLocalization(
        supportedLocales: supportedLocales.map((e) => e.key).toList(),
        path: localeDir,
        fallbackLocale: fallbackLocale,
        useOnlyLangCode: true,
        child: const Obtainium()),
  ));
  BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);
}

var defaultThemeColour = Colors.deepPurple;

class Obtainium extends StatefulWidget {
  const Obtainium({super.key});

  @override
  State<Obtainium> createState() => _ObtainiumState();
}

class _ObtainiumState extends State<Obtainium> {
  var existingUpdateInterval = -1;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    await BackgroundFetch.configure(
        BackgroundFetchConfig(
            minimumFetchInterval: 15,
            stopOnTerminate: false,
            enableHeadless: true,
            requiresBatteryNotLow: false,
            requiresCharging: false,
            requiresStorageNotLow: false,
            requiresDeviceIdle: false,
            requiredNetworkType: NetworkType.ANY), (String taskId) async {
      // We don't want periodic tasks in the foreground - ignore
      await bgUpdateCheck(taskId, null);
      BackgroundFetch.finish(taskId);
    }, (String taskId) async {
      context.read<LogsProvider>().add('BG update task timed out.');
      BackgroundFetch.finish(taskId);
    });
    if (!mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    SettingsProvider settingsProvider = context.watch<SettingsProvider>();
    AppsProvider appsProvider = context.read<AppsProvider>();
    LogsProvider logs = context.read<LogsProvider>();

    if (settingsProvider.prefs == null) {
      settingsProvider.initializeSettings();
    } else {
      bool isFirstRun = settingsProvider.checkAndFlipFirstRun();
      if (isFirstRun) {
        logs.add('This is the first ever run of Obtainium.');
        // If this is the first run, ask for notification permissions and add Obtainium to the Apps list
        Permission.notification.request();
        if (!fdroid) {
          appsProvider.saveApps([
            App(
                obtainiumId,
                'https://github.com/ImranR98/Obtainium',
                'ImranR98',
                'Obtainium',
                currentReleaseTag,
                currentReleaseTag,
                [],
                0,
                {'includePrereleases': true},
                null,
                false)
          ], onlyIfExists: false);
        }
      }
      if (!supportedLocales
              .map((e) => e.key.languageCode)
              .contains(context.locale.languageCode) ||
          (settingsProvider.forcedLocale == null &&
              context.deviceLocale.languageCode !=
                  context.locale.languageCode)) {
        settingsProvider.resetLocaleSafe(context);
      }
    }

    return DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
      // Decide on a colour/brightness scheme based on OS and user settings
      ColorScheme lightColorScheme;
      ColorScheme darkColorScheme;
      if (lightDynamic != null &&
          darkDynamic != null &&
          settingsProvider.colour == ColourSettings.materialYou) {
        lightColorScheme = lightDynamic.harmonized();
        darkColorScheme = darkDynamic.harmonized();
      } else {
        lightColorScheme = ColorScheme.fromSeed(seedColor: defaultThemeColour);
        darkColorScheme = ColorScheme.fromSeed(
            seedColor: defaultThemeColour, brightness: Brightness.dark);
      }

      // set the background and surface colors to pure black in the amoled theme
      if (settingsProvider.useBlackTheme) {
        darkColorScheme = darkColorScheme
            .copyWith(background: Colors.black, surface: Colors.black)
            .harmonized();
      }

      return MaterialApp(
          title: 'Obtainium',
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          navigatorKey: globalNavigatorKey,
          theme: ThemeData(
              useMaterial3: true,
              colorScheme: settingsProvider.theme == ThemeSettings.dark
                  ? darkColorScheme
                  : lightColorScheme,
              fontFamily: 'Metropolis'),
          darkTheme: ThemeData(
              useMaterial3: true,
              colorScheme: settingsProvider.theme == ThemeSettings.light
                  ? lightColorScheme
                  : darkColorScheme,
              fontFamily: 'Metropolis'),
          home: Shortcuts(shortcuts: <LogicalKeySet, Intent>{
            LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
          }, child: const HomePage()));
    });
  }
}
