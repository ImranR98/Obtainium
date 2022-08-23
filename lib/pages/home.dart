import 'package:flutter/material.dart';
import 'package:obtainium/pages/add_app.dart';
import 'package:obtainium/pages/apps.dart';
import 'package:obtainium/pages/settings.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedIndex = 1;
  List<Widget> pages = [
    const SettingsPage(),
    const AppsPage(),
    const AddAppPage()
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Obtainium')),
      body: pages.elementAt(selectedIndex),
      bottomNavigationBar: NavigationBar(
        destinations: const [
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          NavigationDestination(icon: Icon(Icons.apps), label: 'Apps'),
          NavigationDestination(icon: Icon(Icons.add), label: 'Add App'),
        ],
        onDestinationSelected: (int index) {
          setState(() {
            selectedIndex = index;
          });
        },
        selectedIndex: selectedIndex,
      ),
    );
  }
}
