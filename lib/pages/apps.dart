import 'package:flutter/material.dart';
import 'package:obtainium/pages/add_app.dart';
import 'package:obtainium/pages/app.dart';
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
    var appsProvider = context.watch<AppsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Obtainium'),
      ),
      body: Center(
        child: appsProvider.loadingApps
            ? const CircularProgressIndicator()
            : appsProvider.apps.isEmpty
                ? Text(
                    'No Apps',
                    style: Theme.of(context).textTheme.headline4,
                  )
                : ListView(
                    children: appsProvider.apps.values
                        .map(
                          (e) => ListTile(
                            title: Text(e.name),
                            subtitle: Text(e.author),
                            trailing:
                                Text(e.installedVersion ?? 'Not Installed'),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => AppPage(appId: e.id)),
                              );
                            },
                          ),
                        )
                        .toList(),
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
