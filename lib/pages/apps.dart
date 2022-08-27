import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
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
    var existingUpdateAppIds = appsProvider.getExistingUpdates();

    return Scaffold(
        floatingActionButton: existingUpdateAppIds.isEmpty
            ? null
            : ElevatedButton.icon(
                onPressed: appsProvider.areDownloadsRunning()
                    ? null
                    : () {
                        HapticFeedback.heavyImpact();
                        context
                            .read<SettingsProvider>()
                            .getInstallPermission()
                            .then((_) {
                          appsProvider.downloadAndInstallLatestApp(
                              existingUpdateAppIds, context);
                        });
                      },
                icon: const Icon(Icons.update),
                label: const Text('Update All')),
        body: Center(
          child: appsProvider.loadingApps
              ? const CircularProgressIndicator()
              : appsProvider.apps.isEmpty
                  ? Text(
                      'No Apps',
                      style: Theme.of(context).textTheme.headline4,
                    )
                  : RefreshIndicator(
                      onRefresh: () {
                        HapticFeedback.lightImpact();
                        return appsProvider.checkUpdates();
                      },
                      child: ListView(
                        children: appsProvider.apps.values
                            .map(
                              (e) => ListTile(
                                title: Text('${e.app.author}/${e.app.name}'),
                                subtitle: Text(
                                    e.app.installedVersion ?? 'Not Installed'),
                                trailing: e.downloadProgress != null
                                    ? Text(
                                        'Downloading - ${e.downloadProgress?.toInt()}%')
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
        ));
  }
}
