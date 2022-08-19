import 'package:flutter/material.dart';
import 'package:obtainium/pages/apps.dart';
import 'package:obtainium/services/apps_provider.dart';
import 'package:obtainium/services/source_service.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';

void backgroundUpdateCheck() {
  Workmanager().executeTask((task, inputData) async {
    var appsProvider = AppsProvider(bg: true);
    await appsProvider.loadApps();
    List<App> updates = await appsProvider.getUpdates();
    if (updates.isNotEmpty) {
      String message = updates.length == 1
          ? '${updates[0].name} has an update.'
          : '${(updates.length == 2 ? '${updates[0].name} and ${updates[1].name}' : '${updates[0].name} and ${updates.length - 1} more apps')} have updates.';
      appsProvider.downloaderNotifications.cancel(2);
      appsProvider.notify(
          2,
          'Updates Available',
          message,
          'UPDATES_AVAILABLE',
          'Updates Available',
          'Notifies the user that updates are available for one or more Apps tracked by Obtainium');
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().initialize(
    backgroundUpdateCheck,
  );
  await Workmanager().cancelByUniqueName('update-apps-task');
  await Workmanager().registerPeriodicTask(
      'update-apps-task', 'backgroundUpdateCheck',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected));
  runApp(MultiProvider(
    providers: [ChangeNotifierProvider(create: (context) => AppsProvider())],
    child: const MyApp(),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Obtainium',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: const AppsPage());
  }
}
