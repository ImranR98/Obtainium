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
    if (app == null) {
      Navigator.pop(context);
    }
    return Scaffold(
        appBar: AppBar(
          title: Text('App - ${app?.name} - ${app?.author}'),
        ),
        body: WebView(
          initialUrl: app?.url,
        ));
  }
}
