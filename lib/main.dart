import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/pages/home.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:device_info_plus/device_info_plus.dart';

const String currentReleaseTag =
    'v0.4.1-beta'; // KEEP THIS IN SYNC WITH GITHUB RELEASES

const String bgUpdateCheckTaskName = 'bg-update-check';

bgUpdateCheck(int? ignoreAfterMicroseconds) async {
  DateTime? ignoreAfter = ignoreAfterMicroseconds != null
      ? DateTime.fromMicrosecondsSinceEpoch(ignoreAfterMicroseconds)
      : null;
  var notificationsProvider = NotificationsProvider();
  await notificationsProvider.notify(checkingUpdatesNotification);
  try {
    var appsProvider = AppsProvider();
    await notificationsProvider.cancel(ErrorCheckingUpdatesNotification('').id);
    await appsProvider.loadApps();
    // List<String> existingUpdateIds = // TODO: Uncomment this and below when it works
    //     appsProvider.getExistingUpdates(installedOnly: true);
    List<String> existingUpdateIds =
        appsProvider.getExistingUpdates(installedOnly: true);
    // DateTime nextIgnoreAfter = DateTime.now();
    try {
      await appsProvider.checkUpdates(ignoreAfter: ignoreAfter);
    } catch (e) {
      if (e is RateLimitError) {
        // Ignore these (scheduling another task as below does not work)
        // Workmanager().registerOneOffTask(
        //     bgUpdateCheckTaskName, bgUpdateCheckTaskName,
        //     constraints: Constraints(networkType: NetworkType.connected),
        //     initialDelay: Duration(minutes: e.remainingMinutes),
        //     inputData: {'ignoreAfter': nextIgnoreAfter.microsecondsSinceEpoch});
      } else {
        rethrow;
      }
    }
    List<App> newUpdates = appsProvider
        .getExistingUpdates(installedOnly: true)
        .where((id) => !existingUpdateIds.contains(id))
        .map((e) => appsProvider.apps[e]!.app)
        .toList();
    // List<String> silentlyUpdated = await appsProvider
    //     .downloadAndInstallLatestApp(
    //         [...newUpdates.map((e) => e.id), ...existingUpdateIds], null);
    // if (silentlyUpdated.isNotEmpty) {
    //   newUpdates
    //       .where((element) => !silentlyUpdated.contains(element.id))
    //       .toList();
    //   notificationsProvider.notify(
    //       SilentUpdateNotification(
    //           silentlyUpdated.map((e) => appsProvider.apps[e]!.app).toList()),
    //       cancelExisting: true);
    // }
    if (newUpdates.isNotEmpty) {
      notificationsProvider.notify(UpdateNotification(newUpdates),
          cancelExisting: true);
    }
    return Future.value(true);
  } catch (e) {
    notificationsProvider.notify(ErrorCheckingUpdatesNotification(e.toString()),
        cancelExisting: true);
    return Future.error(false);
  } finally {
    await notificationsProvider.cancel(checkingUpdatesNotification.id);
  }
}

@pragma('vm:entry-point')
void bgTaskCallback() {
  // Background process callback
  Workmanager().executeTask((task, inputData) async {
    return await bgUpdateCheck(inputData?['ignoreAfter']);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if ((await DeviceInfoPlugin().androidInfo).version.sdkInt! >= 29) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(systemNavigationBarColor: Colors.transparent),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  Workmanager().initialize(
    bgTaskCallback,
  );
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(
          create: (context) => AppsProvider(
              shouldLoadApps: true,
              shouldCheckUpdatesAfterLoad: false,
              shouldDeleteAPKs: true)),
      ChangeNotifierProvider(create: (context) => SettingsProvider()),
      Provider(create: (context) => NotificationsProvider())
    ],
    child: const MyApp(),
  ));
}

var defaultThemeColour = Colors.deepPurple;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    SettingsProvider settingsProvider = context.watch<SettingsProvider>();
    AppsProvider appsProvider = context.read<AppsProvider>();

    if (settingsProvider.prefs == null) {
      settingsProvider.initializeSettings();
    } else {
      bool isFirstRun = settingsProvider.checkAndFlipFirstRun();
      if (isFirstRun) {
        // If this is the first run, ask for notification permissions and add Obtainium to the Apps list
        Permission.notification.request();
        appsProvider.saveApps([
          App(
              'imranr98_obtainium_${GitHub().host}',
              'https://github.com/ImranR98/Obtainium',
              'ImranR98',
              'Obtainium',
              currentReleaseTag,
              currentReleaseTag,
              [],
              0,
              ['true'],
              null)
        ]);
      }
      // Register the background update task according to the user's setting
      if (settingsProvider.updateInterval == 0) {
        Workmanager().cancelByUniqueName(bgUpdateCheckTaskName);
      } else {
        Workmanager().registerPeriodicTask(
            bgUpdateCheckTaskName, bgUpdateCheckTaskName,
            frequency: Duration(minutes: settingsProvider.updateInterval),
            initialDelay: Duration(minutes: settingsProvider.updateInterval),
            constraints: Constraints(networkType: NetworkType.connected),
            existingWorkPolicy: ExistingWorkPolicy.keep,
            backoffPolicy: BackoffPolicy.linear,
            backoffPolicyDelay:
                const Duration(minutes: minUpdateIntervalMinutes));
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
      return MaterialApp(
          title: 'Obtainium',
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
