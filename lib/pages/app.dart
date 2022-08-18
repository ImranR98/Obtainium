import 'package:flutter/material.dart';
import 'package:obtainium/services/apps_provider.dart';
import 'package:obtainium/services/source_service.dart';
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
    App? app = appsProvider.apps[widget.appId];
    if (app?.installedVersion != null) {
      appsProvider.getUpdate(app!.id);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('${app?.author}/${app?.name}'),
      ),
      body: WebView(
        initialUrl: app?.url,
      ),
      bottomSheet: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: (app?.installedVersion == null ||
                                appsProvider.checkAppObjectForUpdate(app!)) &&
                            app?.currentDownloadId == null
                        ? () {
                            appsProvider.backgroundDownloadAndInstallApp(app!);
                          }
                        : null,
                    child: Text(
                        app?.installedVersion == null ? 'Install' : 'Update'))),
            const SizedBox(width: 16.0),
            OutlinedButton(
              onPressed: app?.currentDownloadId != null
                  ? null
                  : () {
                      showDialog(
                          context: context,
                          builder: (BuildContext ctx) {
                            return AlertDialog(
                              title: const Text('Remove App?'),
                              content: Text(
                                  'This will remove \'${app?.name}\' from Obtainium.${app?.installedVersion != null ? '\n\nNote that while Obtainium will no longer track its updates, the App will remain installed.' : ''}'),
                              actions: [
                                TextButton(
                                    onPressed: () {
                                      appsProvider.removeApp(app!.id).then((_) {
                                        int count = 0;
                                        Navigator.of(context)
                                            .popUntil((_) => count++ >= 2);
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
                  foregroundColor: Theme.of(context).errorColor),
              child: const Text('Remove'),
            )
            // TODO: Add progress bar when app?.currentDownloadId != null
          ])),
    );
  }
}
