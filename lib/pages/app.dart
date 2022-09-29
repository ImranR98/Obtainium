import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:provider/provider.dart';

class AppPage extends StatefulWidget {
  const AppPage({super.key, required this.appId});

  final String appId;

  @override
  State<AppPage> createState() => _AppPageState();
}

class _AppPageState extends State<AppPage> {
  @override
  Widget build(BuildContext context) {
    var appsProvider = context.watch<AppsProvider>();
    var settingsProvider = context.watch<SettingsProvider>();
    var sourceProvider = SourceProvider();
    AppInMemory? app = appsProvider.apps[widget.appId];
    var source = app != null ? sourceProvider.getSource(app.app.url) : null;
    if (!appsProvider.areDownloadsRunning() && app != null) {
      appsProvider.getUpdate(app.app.id).catchError((e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      });
    }
    return Scaffold(
      appBar: settingsProvider.showAppWebpage ? AppBar() : null,
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
          child: settingsProvider.showAppWebpage
              ? WebView(
                  initialUrl: app?.app.url,
                  javascriptMode: JavascriptMode.unrestricted,
                )
              : CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                        child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          app?.app.name ?? 'App',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displayLarge,
                        ),
                        Text(
                          'By ${app?.app.author ?? 'Unknown'}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(
                          height: 32,
                        ),
                        GestureDetector(
                            onTap: () {
                              if (app?.app.url != null) {
                                launchUrlString(app?.app.url ?? '',
                                    mode: LaunchMode.externalApplication);
                              }
                            },
                            child: Text(
                              app?.app.url ?? '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  decoration: TextDecoration.underline,
                                  fontStyle: FontStyle.italic,
                                  fontSize: 12),
                            )),
                        const SizedBox(
                          height: 32,
                        ),
                        Text(
                          'Latest Version: ${app?.app.latestVersion ?? 'Unknown'}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        Text(
                          'Installed Version: ${app?.app.installedVersion ?? 'None'}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(
                          height: 32,
                        ),
                        Text(
                          'Last Update Check: ${app?.app.lastUpdateCheck == null ? 'Never' : '\n${app?.app.lastUpdateCheck?.toLocal()}'}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontStyle: FontStyle.italic, fontSize: 12),
                        )
                      ],
                    )),
                  ],
                ),
          onRefresh: () async {
            if (app != null) {
              try {
                await appsProvider.getUpdate(app.app.id);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString())),
                );
              }
            }
          }),
      bottomSheet: Padding(
          padding: EdgeInsets.fromLTRB(
              0, 0, 0, MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (app?.app.installedVersion != app?.app.latestVersion)
                          IconButton(
                              onPressed: app?.downloadProgress != null
                                  ? null
                                  : () {
                                      showDialog(
                                          context: context,
                                          builder: (BuildContext ctx) {
                                            return AlertDialog(
                                              title: Text(
                                                  'App Already ${app?.app.installedVersion == null ? 'Installed' : 'Updated'}?'),
                                              actions: [
                                                TextButton(
                                                    onPressed: () {
                                                      Navigator.of(context)
                                                          .pop();
                                                    },
                                                    child: const Text('No')),
                                                TextButton(
                                                    onPressed: () {
                                                      HapticFeedback
                                                          .selectionClick();
                                                      var updatedApp = app?.app;
                                                      if (updatedApp != null) {
                                                        updatedApp
                                                                .installedVersion =
                                                            updatedApp
                                                                .latestVersion;
                                                        appsProvider.saveApps(
                                                            [updatedApp]);
                                                      }
                                                      Navigator.of(context)
                                                          .pop();
                                                    },
                                                    child: const Text(
                                                        'Yes, Mark as Installed'))
                                              ],
                                            );
                                          });
                                    },
                              tooltip: 'Mark as Installed',
                              icon: const Icon(Icons.done))
                        else
                          IconButton(
                              onPressed: app?.downloadProgress != null
                                  ? null
                                  : () {
                                      showDialog(
                                          context: context,
                                          builder: (BuildContext ctx) {
                                            return AlertDialog(
                                              title: const Text(
                                                  'App Not Installed?'),
                                              actions: [
                                                TextButton(
                                                    onPressed: () {
                                                      Navigator.of(context)
                                                          .pop();
                                                    },
                                                    child: const Text('No')),
                                                TextButton(
                                                    onPressed: () {
                                                      HapticFeedback
                                                          .selectionClick();
                                                      var updatedApp = app?.app;
                                                      if (updatedApp != null) {
                                                        updatedApp
                                                                .installedVersion =
                                                            null;
                                                        appsProvider.saveApps(
                                                            [updatedApp]);
                                                      }
                                                      Navigator.of(context)
                                                          .pop();
                                                    },
                                                    child: const Text(
                                                        'Yes, Mark as Not Installed'))
                                              ],
                                            );
                                          });
                                    },
                              tooltip: 'Mark as Not Installed',
                              icon: const Icon(Icons.no_cell_outlined)),
                        if (source != null &&
                            source.additionalDataFormItems.isNotEmpty)
                          IconButton(
                              onPressed: app?.downloadProgress != null
                                  ? null
                                  : () {
                                      showDialog(
                                          context: context,
                                          builder: (BuildContext ctx) {
                                            return GeneratedFormModal(
                                                title: 'Additional Options',
                                                items: source
                                                    .additionalDataFormItems,
                                                defaultValues: app != null
                                                    ? app.app.additionalData
                                                    : source
                                                        .additionalDataDefaults);
                                          }).then((values) {
                                        if (app != null && values != null) {
                                          var changedApp = app.app;
                                          changedApp.additionalData = values;
                                          appsProvider.saveApps([changedApp]);
                                        }
                                      });
                                    },
                              tooltip: 'Additional Options',
                              icon: const Icon(Icons.settings)),
                        const SizedBox(width: 16.0),
                        Expanded(
                            child: ElevatedButton(
                                onPressed: (app?.app.installedVersion == null ||
                                            appsProvider
                                                .checkAppObjectForUpdate(
                                                    app!.app)) &&
                                        !appsProvider.areDownloadsRunning()
                                    ? () {
                                        HapticFeedback.heavyImpact();
                                        appsProvider
                                            .downloadAndInstallLatestApp(
                                                [app!.app.id],
                                                context).then((res) {
                                          if (res.isNotEmpty && mounted) {
                                            Navigator.of(context).pop();
                                          }
                                        });
                                      }
                                    : null,
                                child: Text(app?.app.installedVersion == null
                                    ? 'Install'
                                    : 'Update'))),
                        const SizedBox(width: 16.0),
                        ElevatedButton(
                          onPressed: app?.downloadProgress != null
                              ? null
                              : () {
                                  showDialog(
                                      context: context,
                                      builder: (BuildContext ctx) {
                                        return AlertDialog(
                                          title: const Text('Remove App?'),
                                          content: Text(
                                              'This will remove \'${app?.app.name}\' from Obtainium.${app?.app.installedVersion != null ? '\n\nNote that while Obtainium will no longer track its updates, the App will remain installed.' : ''}'),
                                          actions: [
                                            TextButton(
                                                onPressed: () {
                                                  HapticFeedback
                                                      .selectionClick();
                                                  appsProvider.removeApps(
                                                      [app!.app.id]).then((_) {
                                                    int count = 0;
                                                    Navigator.of(context)
                                                        .popUntil((_) =>
                                                            count++ >= 2);
                                                  });
                                                },
                                                child: const Text('Remove')),
                                            TextButton(
                                                onPressed: () {
                                                  Navigator.of(context).pop();
                                                },
                                                child: const Text('Cancel'))
                                          ],
                                        );
                                      });
                                },
                          style: TextButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.error,
                              surfaceTintColor:
                                  Theme.of(context).colorScheme.error),
                          child: const Text('Remove'),
                        ),
                      ])),
              if (app?.downloadProgress != null)
                Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                    child: LinearProgressIndicator(
                        value: app!.downloadProgress! / 100))
            ],
          )),
    );
  }
}
