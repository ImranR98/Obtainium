import 'package:flutter/material.dart';
import 'package:obtainium/pages/add_app.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/pages/logs.dart';
import 'package:obtainium/pages/settings.dart';

class NavHelper {
  NavHelper._();

  static void pushAppPage(
    BuildContext context,
    String appId, {
    bool showOppositeOfPreferredView = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppPage(
          appId: appId,
          showOppositeOfPreferredView: showOppositeOfPreferredView,
        ),
      ),
    );
  }

  static void pushSettingsPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  static void pushAddAppPage(BuildContext context, {String? initialUrl}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddAppPage(initialUrl: initialUrl),
      ),
    );
  }

  static void pushLogsPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LogsPage()),
    );
  }
}
