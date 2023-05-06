import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

const String currentVersion = '0.13.0';
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

@pragma('vm:entry-point')
Future<void> bgUpdateCheck(int taskId, Map<String, dynamic>? params) async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  await loadTranslations();

  LogsProvider logs = LogsProvider();
  logs.add(tr('startedBgUpdateTask'));
  int? ignoreAfterMicroseconds = params?['ignoreAfterMicroseconds'];
  await AndroidAlarmManager.initialize();
  DateTime? ignoreAfter = ignoreAfterMicroseconds != null
      ? DateTime.fromMicrosecondsSinceEpoch(ignoreAfterMicroseconds)
      : null;
  logs.add(tr('bgUpdateIgnoreAfterIs', args: [ignoreAfter.toString()]));
  var notificationsProvider = NotificationsProvider();
  await notificationsProvider.notify(checkingUpdatesNotification);
  try {
    var appsProvider = AppsProvider();
    await notificationsProvider.cancel(ErrorCheckingUpdatesNotification('').id);
    await appsProvider.loadApps();
    List<String> existingUpdateIds =
        appsProvider.findExistingUpdates(installedOnly: true);
    DateTime nextIgnoreAfter = DateTime.now();
    String? err;
    try {
      logs.add(tr('startedActualBGUpdateCheck'));
      await appsProvider.checkUpdates(
          ignoreAppsCheckedAfter: ignoreAfter, throwErrorsForRetry: true);
    } catch (e) {
      if (e is RateLimitError || e is SocketException) {
        var remainingMinutes = e is RateLimitError ? e.remainingMinutes : 15;
        logs.add(plural('bgUpdateGotErrorRetryInMinutes', remainingMinutes,
            args: [e.toString(), remainingMinutes.toString()]));
        AndroidAlarmManager.oneShot(Duration(minutes: remainingMinutes),
            Random().nextInt(pow(2, 31) as int), bgUpdateCheck, params: {
          'ignoreAfterMicroseconds': nextIgnoreAfter.microsecondsSinceEpoch
        });
      } else {
        err = e.toString();
      }
    }
    List<App> newUpdates = appsProvider
        .findExistingUpdates(installedOnly: true)
        .where((id) => !existingUpdateIds.contains(id))
        .map((e) => appsProvider.apps[e]!.app)
        .toList();

    // TODO: This silent update code doesn't work yet
    // List<String> silentlyUpdated = await appsProvider
    //     .downloadAndInstallLatestApp(
    //         [...newUpdates.map((e) => e.id), ...existingUpdateIds], null);
    // if (silentlyUpdated.isNotEmpty) {
    //   newUpdates = newUpdates
    //       .where((element) => !silentlyUpdated.contains(element.id))
    //       .toList();
    //   notificationsProvider.notify(
    //       SilentUpdateNotification(
    //           silentlyUpdated.map((e) => appsProvider.apps[e]!.app).toList()),
    //       cancelExisting: true);
    // }
    logs.add(
        plural('bgCheckFoundUpdatesWillNotifyIfNeeded', newUpdates.length));
    if (newUpdates.isNotEmpty) {
      notificationsProvider.notify(UpdateNotification(newUpdates));
    }
    if (err != null) {
      throw err;
    }
  } catch (e) {
    notificationsProvider
        .notify(ErrorCheckingUpdatesNotification(e.toString()));
  } finally {
    logs.add(tr('bgUpdateTaskFinished'));
    await notificationsProvider.cancel(checkingUpdatesNotification.id);
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
        logs.add(tr('firstRun'));
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
          settingsProvider.forcedLocale == null &&
              context.deviceLocale.languageCode !=
                  context.locale.languageCode) {
        settingsProvider.resetLocaleSafe(context);
      }
      // Register the background update task according to the user's setting
      if (existingUpdateInterval != settingsProvider.updateInterval) {
        if (existingUpdateInterval != -1) {
          logs.add(tr('settingUpdateCheckIntervalTo',
              args: [settingsProvider.updateInterval.toString()]));
        }
        existingUpdateInterval = settingsProvider.updateInterval;
        if (existingUpdateInterval == 0) {
          AndroidAlarmManager.cancel(bgUpdateCheckAlarmId);
        } else {
          AndroidAlarmManager.periodic(
              Duration(minutes: existingUpdateInterval),
              bgUpdateCheckAlarmId,
              bgUpdateCheck,
              rescheduleOnReboot: true,
              wakeup: true);
        }
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
          home: const HomePage());
    });
  }
}
