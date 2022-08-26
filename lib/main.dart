import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/pages/home.dart';
import 'package:obtainium/services/apps_provider.dart';
import 'package:obtainium/services/settings_provider.dart';
import 'package:obtainium/services/source_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'package:dynamic_color/dynamic_color.dart';

const String CURRENT_RELEASE_TAG =
    'v0.1.3-beta'; // KEEP THIS IN SYNC WITH GITHUB RELEASES

@pragma('vm:entry-point')
void bgTaskCallback() {
  Workmanager().executeTask((task, taskName) async {
    var appsProvider = AppsProvider(bg: true);
    await appsProvider.notify(
        4,
        'Checking for Updates',
        '',
        'BG_UPDATE_CHECK',
        'Checking for Updates',
        'Transient notification that appears when checking for updates',
        important: false);
    try {
      await appsProvider.loadApps();
      List<App> updates = await appsProvider.checkUpdates();
      if (updates.isNotEmpty) {
        String message = updates.length == 1
            ? '${updates[0].name} has an update.'
            : '${(updates.length == 2 ? '${updates[0].name} and ${updates[1].name}' : '${updates[0].name} and ${updates.length - 1} more apps')} have updates.';
        await appsProvider.downloaderNotifications.cancel(2);
        await appsProvider.notify(
            2,
            'Updates Available',
            message,
            'UPDATES_AVAILABLE',
            'Updates Available',
            'Notifies the user that updates are available for one or more Apps tracked by Obtainium');
      }
      return Future.value(true);
    } catch (e) {
      await appsProvider.downloaderNotifications.cancel(5);
      await appsProvider.notify(
          5,
          'Error Checking for Updates',
          e.toString(),
          'BG_UPDATE_CHECK_ERROR',
          'Error Checking for Updates',
          'A notification that shows when background update checking fails',
          important: false);
      return Future.value(false);
    } finally {
      await appsProvider.downloaderNotifications.cancel(4);
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(systemNavigationBarColor: Colors.transparent),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  Workmanager().initialize(
    bgTaskCallback,
  );
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (context) => AppsProvider()),
      ChangeNotifierProvider(create: (context) => SettingsProvider())
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
      Workmanager().registerPeriodicTask('bg-update-check', 'bg-update-check',
          frequency: Duration(minutes: settingsProvider.updateInterval),
          initialDelay: Duration(minutes: settingsProvider.updateInterval),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingWorkPolicy.replace);
      bool isFirstRun = settingsProvider.checkAndFlipFirstRun();
      if (isFirstRun) {
        Permission.notification.request();
        appsProvider.saveApp(App(
            'imranr98_obtainium_github',
            'https://github.com/ImranR98/Obtainium',
            'ImranR98',
            'Obtainium',
            CURRENT_RELEASE_TAG,
            CURRENT_RELEASE_TAG,
            ''));
      }
      appsProvider.deleteSavedAPKs();
      appsProvider.checkUpdates();
    }

    return DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
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
                  : darkColorScheme),
          home: const HomePage());
    });
  }
}
