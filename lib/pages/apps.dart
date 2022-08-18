import 'package:flutter/material.dart';
import 'package:obtainium/pages/add_app.dart';
import 'package:obtainium/services/apps_provider.dart';
import 'package:provider/provider.dart';

class AppsPage extends StatefulWidget {
  const AppsPage({super.key});

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Obtainium - Apps'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: () {
            var appsProvider = context.watch<AppsProvider>();
            if (appsProvider.loadingApps) {
              return [const Text('Loading Apps...')];
            } else if (appsProvider.apps.isEmpty) {
              return [const Text('No Apps Yet.')];
            } else {
              return appsProvider.apps.values.map((e) => Text(e.id)).toList();
            }
          }(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddAppPage()),
          );
        },
        tooltip: 'Add App',
        child: const Icon(Icons.add),
      ),
    );
  }
}
