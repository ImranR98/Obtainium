import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/providers/apps_provider.dart';
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
    AppInMemory? app = appsProvider.apps[widget.appId];
    if (app?.app.installedVersion != null) {
      appsProvider.getUpdate(app!.app.id);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('${app?.app.author}/${app?.app.name}'),
      ),
      body: WebView(
        initialUrl: app?.app.url,
        javascriptMode: JavascriptMode.unrestricted,
      ),
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
                        Expanded(
                            child: ElevatedButton(
                                onPressed: (app?.app.installedVersion == null ||
                                            appsProvider
                                                .checkAppObjectForUpdate(
                                                    app!.app)) &&
                                        app?.downloadProgress == null
                                    ? () {
                                        HapticFeedback.heavyImpact();
                                        appsProvider
                                            .downloadAndInstallLatestApp(
                                                [app!.app.id],
                                                context).then((res) {
                                          if (res) {
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
                                  HapticFeedback.lightImpact();
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
                                                  HapticFeedback.heavyImpact();
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
                                                  HapticFeedback.lightImpact();
                                                  Navigator.of(context).pop();
                                                },
                                                child: const Text('Cancel'))
                                          ],
                                        );
                                      });
                                },
                          style: TextButton.styleFrom(
                              foregroundColor: Theme.of(context).errorColor,
                              surfaceTintColor: Theme.of(context).errorColor),
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
