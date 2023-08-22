import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
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
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/easy_localization_controller.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';

const String currentVersion = '0.13.27';
const String currentReleaseTag =
    'v$currentVersion-beta'; // KEEP THIS IN SYNC WITH GITHUB RELEASES

const int bgUpdateCheckAlarmId = 666;

List<MapEntry<Locale, String>> supportedLocales = const [
  MapEntry(Locale('en'), 'English'),
  MapEntry(Locale('zh'), '汉语'),
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
];
const fallbackLocale = Locale('en');
const localeDir = 'assets/translations';

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

moveStrToEnd(List<String> arr, String str, {String? strB}) {
  String? temp;
  arr.removeWhere((element) {
    bool res = element == str || element == strB;
    if (res) {
      temp = element;
    }
    return res;
  });
  if (temp != null) {
    arr = [...arr, temp!];
  }
  return arr;
}

@pragma('vm:entry-point')
Future<void> bgUpdateCheck(int taskId, Map<String, dynamic>? params) async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await AndroidAlarmManager.initialize();
  await loadTranslations();

  LogsProvider logs = LogsProvider();
  NotificationsProvider notificationsProvider = NotificationsProvider();
  AppsProvider appsProvider = AppsProvider();
  await appsProvider.loadApps();
  var settingsProvider = SettingsProvider();
  await settingsProvider.initializeSettings();

  int maxAttempts = 5;

  params ??= {};
  if (params['toCheck'] == null) {
    settingsProvider.lastBGCheckTime = DateTime.now();
  }
  params['attemptCount'] = (params['attemptCount'] ?? 0) + 1;
  params['toCheck'] =
      params['toCheck'] ?? appsProvider.getAppsSortedByUpdateCheckTime();
  params['toInstall'] = params['toInstall'] ?? (<String>[]);

  List<String> toCheck = <String>[...params['toCheck']];
  List<String> toInstall = <String>[...params['toInstall']];

  logs.add(
      'BG update task $taskId: Started [${toCheck.length},${toInstall.length}]${params['attemptCount'] > 1 ? '. ${params['attemptCount'] - 1} consecutive fail(s)' : ''}.');

  if (toCheck.isNotEmpty) {
    String appId = toCheck.removeAt(0);
    AppInMemory? app = appsProvider.apps[appId];
    if (app?.app.installedVersion != null) {
      try {
        notificationsProvider.notify(checkingUpdatesNotification,
            cancelExisting: true);
        App? newApp = await appsProvider.checkUpdate(appId);
        if (newApp != null) {
          if (!(await appsProvider.canInstallSilently(app!.app))) {
            notificationsProvider.notify(
                UpdateNotification([newApp], id: newApp.id.hashCode - 1));
          } else {
            toInstall.add(appId);
          }
        }
      } catch (e) {
        logs.add(
            'BG update task $taskId: Got error on checking for $appId \'${e.toString()}\'.');
        if (e is RateLimitError ||
            e is ClientException && params['attemptCount'] < maxAttempts) {
          var remainingMinutes = e is RateLimitError ? e.remainingMinutes : 15;
          logs.add(
              'BG update task $taskId: Next task will start in $remainingMinutes minutes (with $appId moved to the end of the line).');
          toCheck = toInstall = []; // So the next task will not start
          params['toCheck'] = moveStrToEnd(params['toCheck'], appId);
          AndroidAlarmManager.oneShot(
              Duration(minutes: remainingMinutes), taskId + 1, bgUpdateCheck,
              params: params);
        } else {
          rethrow;
        }
      } finally {
        notificationsProvider.cancel(checkingUpdatesNotification.id);
      }
    }
  } else if (toInstall.isNotEmpty) {
    toInstall = moveStrToEnd(toInstall, obtainiumId);
    String appId = toInstall.removeAt(0);
    logs.add(
        'BG update task $taskId: Attempting to update $appId in the background.');
    await appsProvider.downloadAndInstallLatestApps([appId], null,
        notificationsProvider: notificationsProvider);
  }

  if (toCheck.isNotEmpty || toInstall.isNotEmpty) {
    logs.add('BG update task $taskId: Ended. Next task will start soon.');
    AndroidAlarmManager.oneShot(
        const Duration(seconds: 0), taskId + 1, bgUpdateCheck,
        params: {'toCheck': toCheck, 'toInstall': toInstall});
  } else {
    logs.add('BG update task $taskId: Ended.');
  }
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
  await AndroidAlarmManager.initialize();
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
      if (!supportedLocales
              .map((e) => e.key.languageCode)
              .contains(context.locale.languageCode) ||
          (settingsProvider.forcedLocale == null &&
              context.deviceLocale.languageCode !=
                  context.locale.languageCode)) {
        settingsProvider.resetLocaleSafe(context);
      }
      // Register the background update task according to the user's setting
      var actualUpdateInterval = settingsProvider.updateInterval;
      if (existingUpdateInterval != actualUpdateInterval) {
        if (actualUpdateInterval == 0) {
          AndroidAlarmManager.cancel(bgUpdateCheckAlarmId);
        } else {
          var settingChanged = existingUpdateInterval != -1;
          var lastCheckWasTooLongAgo = actualUpdateInterval != 0 &&
              settingsProvider.lastBGCheckTime
                  .add(Duration(seconds: actualUpdateInterval + 60))
                  .isBefore(DateTime.now());
          if (settingChanged || lastCheckWasTooLongAgo) {
            logs.add(
                'Update interval was set to ${actualUpdateInterval.toString()} (reason: ${settingChanged ? 'setting changed' : 'last check was too long ago or never'}).');
            AndroidAlarmManager.periodic(
                Duration(minutes: actualUpdateInterval),
                bgUpdateCheckAlarmId,
                bgUpdateCheck,
                rescheduleOnReboot: true,
                wakeup: true);
          }
        }
        existingUpdateInterval = actualUpdateInterval;
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
