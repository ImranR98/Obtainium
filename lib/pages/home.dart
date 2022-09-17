import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/pages/add_app.dart';
import 'package:obtainium/pages/apps.dart';
import 'package:obtainium/pages/import_export.dart';
import 'package:obtainium/pages/settings.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<int> selectedIndexHistory = [];
  List<Widget> pages = [
    const AppsPage(),
    const AddAppPage(),
    const ImportExportPage(),
    const SettingsPage()
  ];

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        child: Scaffold(
          appBar: AppBar(title: const Text('Obtainium')),
          body: pages.elementAt(
              selectedIndexHistory.isEmpty ? 0 : selectedIndexHistory.last),
          bottomNavigationBar: NavigationBar(
            destinations: const [
              NavigationDestination(icon: Icon(Icons.apps), label: 'Apps'),
              NavigationDestination(icon: Icon(Icons.add), label: 'Add App'),
              NavigationDestination(
                  icon: Icon(Icons.import_export), label: 'Import/Export'),
              NavigationDestination(
                  icon: Icon(Icons.settings), label: 'Settings'),
            ],
            onDestinationSelected: (int index) {
              HapticFeedback.lightImpact();
              setState(() {
                if (index == 0) {
                  selectedIndexHistory.clear();
                } else if (selectedIndexHistory.isEmpty ||
                    (selectedIndexHistory.isNotEmpty &&
                        selectedIndexHistory.last != index)) {
                  int existingInd = selectedIndexHistory.indexOf(index);
                  if (existingInd >= 0) {
                    selectedIndexHistory.removeAt(existingInd);
                  }
                  selectedIndexHistory.add(index);
                }
                print(selectedIndexHistory);
              });
            },
            selectedIndex:
                selectedIndexHistory.isEmpty ? 0 : selectedIndexHistory.last,
          ),
        ),
        onWillPop: () async {
          if (selectedIndexHistory.isNotEmpty) {
            setState(() {
              selectedIndexHistory.removeLast();
            });
            return false;
          }
          return true;
        });
  }
}
