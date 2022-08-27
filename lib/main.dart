import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/pages/home.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'package:dynamic_color/dynamic_color.dart';

const String currentReleaseTag =
    'v0.1.5-beta'; // KEEP THIS IN SYNC WITH GITHUB RELEASES

@pragma('vm:entry-point')
void bgTaskCallback() {
  // Background update checking process
  Workmanager().executeTask((task, taskName) async {
    var appsProvider = AppsProvider(bg: true);
    var notificationsProvider = NotificationsProvider();
    await notificationsProvider.notify(checkingUpdatesNotification);
    try {
      await notificationsProvider
          .cancel(ErrorCheckingUpdatesNotification('').id);
      await appsProvider.loadApps();
      List<App> updates = await appsProvider.checkUpdates();
      if (updates.isNotEmpty) {
        notificationsProvider.notify(UpdateNotification(updates),
            cancelExisting: true);
      }
      return Future.value(true);
    } catch (e) {
      notificationsProvider.notify(
          ErrorCheckingUpdatesNotification(e.toString()),
          cancelExisting: true);
      return Future.value(false);
    } finally {
      await notificationsProvider.cancel(checkingUpdatesNotification.id);
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
      settingsProvider.initializeSettings().then((value) {
        // Delete past downloads and check for updates every time the app is launched
        // Only runs once as the settings are only initialized once (so not on every build)
        appsProvider.deleteSavedAPKs();
        appsProvider.checkUpdates();
      });
    } else {
      // Register the background update task according to the user's setting
      Workmanager().registerPeriodicTask('bg-update-check', 'bg-update-check',
          frequency: Duration(minutes: settingsProvider.updateInterval),
          initialDelay: Duration(minutes: settingsProvider.updateInterval),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingWorkPolicy.replace);
      bool isFirstRun = settingsProvider.checkAndFlipFirstRun();
      if (isFirstRun) {
        // If this is the first run, ask for notification permissions and add Obtainium to the Apps list
        Permission.notification.request();
        appsProvider.saveApp(App(
            'imranr98_obtainium_github',
            'https://github.com/ImranR98/Obtainium',
            'ImranR98',
            'Obtainium',
            currentReleaseTag,
            currentReleaseTag, []));
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
