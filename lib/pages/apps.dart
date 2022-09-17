import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/custom_app_bar.dart';
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
    var settingsProvider = context.watch<SettingsProvider>();
    var existingUpdateAppIds = appsProvider.getExistingUpdates();
    var sortedApps = appsProvider.apps.values.toList();
    sortedApps.sort((a, b) {
      int result = 0;
      if (settingsProvider.sortColumn == SortColumnSettings.authorName) {
        result =
            (a.app.author + a.app.name).compareTo(b.app.author + b.app.name);
      } else if (settingsProvider.sortColumn == SortColumnSettings.nameAuthor) {
        result =
            (a.app.name + a.app.author).compareTo(b.app.name + b.app.author);
      }
      return result;
    });
    if (settingsProvider.sortOrder == SortOrderSettings.ascending) {
      sortedApps = sortedApps.reversed.toList();
    }

    return Scaffold(
        floatingActionButton: existingUpdateAppIds.isEmpty
            ? null
            : ElevatedButton.icon(
                onPressed: appsProvider.areDownloadsRunning()
                    ? null
                    : () {
                        HapticFeedback.heavyImpact();
                        settingsProvider.getInstallPermission().then((_) {
                          appsProvider.downloadAndInstallLatestApp(
                              existingUpdateAppIds, context);
                        });
                      },
                icon: const Icon(Icons.install_mobile_outlined),
                label: const Text('Install All')),
        body: RefreshIndicator(
            onRefresh: () {
              HapticFeedback.lightImpact();
              return appsProvider.checkUpdates();
            },
            child: CustomScrollView(slivers: <Widget>[
              const CustomAppBar(title: 'Apps'),
              if (appsProvider.loadingApps || appsProvider.apps.isEmpty)
                SliverFillRemaining(
                    child: appsProvider.loadingApps
                        ? const CircularProgressIndicator()
                        : Text(
                            'No Apps',
                            style: Theme.of(context).textTheme.headlineMedium,
                          )),
              SliverList(
                  delegate: SliverChildBuilderDelegate(
                      (BuildContext context, int index) {
                return ListTile(
                  title: Text(
                      '${sortedApps[index].app.author}/${sortedApps[index].app.name}'),
                  subtitle: Text(sortedApps[index].app.installedVersion ??
                      'Not Installed'),
                  trailing: sortedApps[index].downloadProgress != null
                      ? Text(
                          'Downloading - ${sortedApps[index].downloadProgress?.toInt()}%')
                      : (sortedApps[index].app.installedVersion != null &&
                              sortedApps[index].app.installedVersion !=
                                  sortedApps[index].app.latestVersion
                          ? const Text('Update Available')
                          : null),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              AppPage(appId: sortedApps[index].app.id)),
                    );
                  },
                );
              }, childCount: sortedApps.length))
            ])));
  }
}
