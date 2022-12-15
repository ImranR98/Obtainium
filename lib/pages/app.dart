import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/custom_errors.dart';
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
  AppInMemory? prevApp;

  @override
  Widget build(BuildContext context) {
    var appsProvider = context.watch<AppsProvider>();
    var settingsProvider = context.watch<SettingsProvider>();
    getUpdate(String id) {
      appsProvider.checkUpdate(id).catchError((e) {
        showError(e, context);
      });
    }

    var sourceProvider = SourceProvider();
    AppInMemory? app = appsProvider.apps[widget.appId];
    var source = app != null ? sourceProvider.getSource(app.app.url) : null;
    if (!appsProvider.areDownloadsRunning() && prevApp == null && app != null) {
      prevApp = app;
      getUpdate(app.app.id);
    }
    return Scaffold(
      appBar: settingsProvider.showAppWebpage ? AppBar() : null,
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
          child: settingsProvider.showAppWebpage
              ? WebView(
                  backgroundColor: Theme.of(context).colorScheme.background,
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
                        app?.installedInfo != null
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                    Image.memory(
                                      app!.installedInfo!.icon!,
                                      height: 150,
                                      gaplessPlayback: true,
                                    )
                                  ])
                            : Container(),
                        const SizedBox(
                          height: 25,
                        ),
                        Text(
                          app?.installedInfo?.name ?? app?.app.name ?? 'App',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displayLarge,
                        ),
                        Text(
                          tr('byX', args: [app?.app.author ?? tr('unknown')]),
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
                          tr('latestVersionX',
                              args: [app?.app.latestVersion ?? tr('unknown')]),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        Text(
                          '${tr('installedVersionX', args: [
                                app?.app.installedVersion ?? tr('none')
                              ])}${app?.app.trackOnly == true ? ' ${tr('estimateInBrackets')}\n\n${tr('xIsTrackOnly', args: [
                                  tr('app')
                                ])}' : ''}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(
                          height: 32,
                        ),
                        Text(
                          tr('lastUpdateCheckX', args: [
                            app?.app.lastUpdateCheck == null
                                ? tr('never')
                                : '\n${app?.app.lastUpdateCheck?.toLocal()}'
                          ]),
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
              getUpdate(app.app.id);
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
                        if (app?.app.installedVersion != null &&
                            app?.app.trackOnly == false &&
                            app?.app.installedVersion != app?.app.latestVersion)
                          IconButton(
                              onPressed: app?.downloadProgress != null
                                  ? null
                                  : () {
                                      showDialog(
                                          context: context,
                                          builder: (BuildContext ctx) {
                                            return AlertDialog(
                                              title: Text(tr(
                                                  'alreadyUpToDateQuestion')),
                                              content: Text(
                                                  tr('onlyWorksWithNonEVDApps'),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontStyle:
                                                          FontStyle.italic)),
                                              actions: [
                                                TextButton(
                                                    onPressed: () {
                                                      Navigator.of(context)
                                                          .pop();
                                                    },
                                                    child: Text(tr('no'))),
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
                                                    child: Text(
                                                        tr('yesMarkUpdated')))
                                              ],
                                            );
                                          });
                                    },
                              tooltip: 'Mark as Updated',
                              icon: const Icon(Icons.done)),
                        if (source != null &&
                            source.additionalSourceAppSpecificFormItems
                                .isNotEmpty)
                          IconButton(
                              onPressed: app?.downloadProgress != null
                                  ? null
                                  : () {
                                      showDialog<List<String>>(
                                          context: context,
                                          builder: (BuildContext ctx) {
                                            return GeneratedFormModal(
                                                title: 'Additional Options',
                                                items: source
                                                    .additionalSourceAppSpecificFormItems,
                                                defaultValues: app != null
                                                    ? app.app.additionalData
                                                    : source
                                                        .additionalSourceAppSpecificDefaults);
                                          }).then((values) {
                                        if (app != null && values != null) {
                                          var changedApp = app.app;
                                          changedApp.additionalData = values;
                                          appsProvider.saveApps(
                                              [changedApp]).then((value) {
                                            getUpdate(changedApp.id);
                                          });
                                        }
                                      });
                                    },
                              tooltip: 'Additional Options',
                              icon: const Icon(Icons.settings)),
                        const SizedBox(width: 16.0),
                        Expanded(
                            child: ElevatedButton(
                                onPressed: (app?.app.installedVersion == null ||
                                            app?.app.installedVersion !=
                                                app?.app.latestVersion) &&
                                        !appsProvider.areDownloadsRunning()
                                    ? () {
                                        HapticFeedback.heavyImpact();
                                        () async {
                                          if (app?.app.trackOnly != true) {
                                            await settingsProvider
                                                .getInstallPermission();
                                          }
                                        }()
                                            .then((value) {
                                          appsProvider
                                              .downloadAndInstallLatestApps(
                                                  [app!.app.id],
                                                  context).then((res) {
                                            if (res.isNotEmpty && mounted) {
                                              Navigator.of(context).pop();
                                            }
                                          });
                                        }).catchError((e) {
                                          showError(e, context);
                                        });
                                      }
                                    : null,
                                child: Text(app?.app.installedVersion == null
                                    ? app?.app.trackOnly == false
                                        ? 'Install'
                                        : 'Mark Installed'
                                    : app?.app.trackOnly == false
                                        ? 'Update'
                                        : 'Mark Updated'))),
                        const SizedBox(width: 16.0),
                        ElevatedButton(
                          onPressed: app?.downloadProgress != null
                              ? null
                              : () {
                                  showDialog(
                                      context: context,
                                      builder: (BuildContext ctx) {
                                        return AlertDialog(
                                          title: Text(tr('removeAppQuestion')),
                                          content: Text(tr(
                                              'xWillBeRemovedButRemainInstalled',
                                              args: [
                                                app?.installedInfo?.name ??
                                                    app?.app.name ??
                                                    tr('app')
                                              ])),
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
                                                child: Text(tr('remove'))),
                                            TextButton(
                                                onPressed: () {
                                                  Navigator.of(context).pop();
                                                },
                                                child: Text(tr('cancel')))
                                          ],
                                        );
                                      });
                                },
                          style: TextButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.error,
                              surfaceTintColor:
                                  Theme.of(context).colorScheme.error),
                          child: Text(tr('remove')),
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
