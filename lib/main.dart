import 'package:flutter/material.dart';
import 'package:obtainium/pages/apps.dart';
import 'package:obtainium/services/apps_provider.dart';
import 'package:provider/provider.dart';
import 'package:toast/toast.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
