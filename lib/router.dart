import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:obtainium/router.dart';
import 'package:obtainium/pages/home.dart';
import 'package:obtainium/pages/apps.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/pages/add_app.dart';
import 'package:obtainium/pages/settings.dart';
import 'package:obtainium/pages/import_export.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: appNavigatorKey,
  initialLocation: '/apps',
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          ObtainiumErrorBoundary(child: HomePage(child: child)),
      routes: [
        GoRoute(
          path: '/apps',
          builder: (context, state) =>
              const ObtainiumErrorBoundary(child: AppsPage()),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) =>
              const ObtainiumErrorBoundary(child: SettingsPage()),
        ),
      ],
    ),
    GoRoute(
      path: '/app/:appId',
      builder: (context, state) => ObtainiumErrorBoundary(
        child: AppPage(
          appId: state.pathParameters['appId']!,
        ),
      ),
    ),
    GoRoute(
      path: '/add-app',
      builder: (context, state) => ObtainiumErrorBoundary(
        child: AddAppPage(
          initialUrl: state.uri.queryParameters['url'],
        ),
      ),
    ),
    GoRoute(
      path: '/import-export',
      builder: (context, state) =>
          const ObtainiumErrorBoundary(child: ImportFromURLListPage()),
    ),
  ],
);

class ObtainiumErrorBoundary extends StatelessWidget {
  final Widget child;

  const ObtainiumErrorBoundary({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
