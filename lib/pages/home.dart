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

class NavigationPageItem {
  late String title;
  late IconData icon;
  late Widget widget;

  NavigationPageItem(this.title, this.icon, this.widget);
}

class _HomePageState extends State<HomePage> {
  List<int> selectedIndexHistory = [];

  List<NavigationPageItem> pages = [
    NavigationPageItem('Apps', Icons.apps, const AppsPage()),
    NavigationPageItem('Add App', Icons.add, const AddAppPage()),
    NavigationPageItem(
        'Import/Export', Icons.import_export, const ImportExportPage()),
    NavigationPageItem('Settings', Icons.settings, const SettingsPage())
  ];

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: pages
              .elementAt(
                  selectedIndexHistory.isEmpty ? 0 : selectedIndexHistory.last)
              .widget,
          bottomNavigationBar: NavigationBar(
            destinations: pages
                .map((e) =>
                    NavigationDestination(icon: Icon(e.icon), label: e.title))
                .toList(),
            onDestinationSelected: (int index) {
              HapticFeedback.selectionClick();
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
