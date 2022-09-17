import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
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
    AppInMemory? app = appsProvider.apps[widget.appId];
    if (app?.app.installedVersion != null) {
      appsProvider.getUpdate(app!.app.id);
    }
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: CustomScrollView(slivers: <Widget>[
        CustomAppBar(title: '${app?.app.name}'),
        SliverFillRemaining(
          child: settingsProvider.showAppWebpage
              ? WebView(
                  initialUrl: app?.app.url,
                  javascriptMode: JavascriptMode.unrestricted,
                )
              : Column(
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
                  ],
                ),
        ),
      ]),
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
                        if (app?.app.installedVersion == null)
                          IconButton(
                              onPressed: () {
                                showDialog(
                                    context: context,
                                    builder: (BuildContext ctx) {
                                      return AlertDialog(
                                        title: const Text(
                                            'App Already Installed?'),
                                        actions: [
                                          TextButton(
                                              onPressed: () {
                                                Navigator.of(context).pop();
                                              },
                                              child: const Text('No')),
                                          TextButton(
                                              onPressed: () {
                                                HapticFeedback.selectionClick();
                                                var updatedApp = app?.app;
                                                if (updatedApp != null) {
                                                  updatedApp.installedVersion =
                                                      updatedApp.latestVersion;
                                                  appsProvider
                                                      .saveApp(updatedApp);
                                                }
                                                Navigator.of(context).pop();
                                              },
                                              child: const Text(
                                                  'Yes, Mark as Installed'))
                                        ],
                                      );
                                    });
                              },
                              tooltip: 'Mark as Installed',
                              icon: const Icon(Icons.done)),
                        if (app?.app.installedVersion == null)
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
                                          if (res && mounted) {
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
                                                  appsProvider
                                                      .removeApp(app!.app.id)
                                                      .then((_) {
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
