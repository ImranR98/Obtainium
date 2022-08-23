import 'package:flutter/material.dart';
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
    appsProvider.getUpdates();

    return Center(
      child: appsProvider.loadingApps
          ? const CircularProgressIndicator()
          : appsProvider.apps.isEmpty
              ? Text(
                  'No Apps',
                  style: Theme.of(context).textTheme.headline4,
                )
              : RefreshIndicator(
                  onRefresh: appsProvider.getUpdates,
                  child: ListView(
                    children: appsProvider.apps.values
                        .map(
                          (e) => ListTile(
                            title: Text('${e.app.author}/${e.app.name}'),
                            subtitle:
                                Text(e.app.installedVersion ?? 'Not Installed'),
                            trailing: e.downloadProgress != null
                                ? Text(
                                    'Downloading - ${e.downloadProgress!.toInt()}%')
                                : (e.app.installedVersion != null &&
                                        e.app.installedVersion !=
                                            e.app.latestVersion
                                    ? const Text('Update Available')
                                    : null),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        AppPage(appId: e.app.id)),
                              );
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
    );
  }
}
