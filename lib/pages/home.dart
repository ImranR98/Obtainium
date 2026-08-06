import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/pages/add_app.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/pages/apps.dart';
import 'package:obtainium/pages/settings.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final SourceProvider sourceProvider;
  late final SettingsProvider settingsProvider;
  late final AppsProvider appsProvider;

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  final GlobalKey<AppsPageState> appsPageKey = GlobalKey<AppsPageState>();
  String? selectedAppId;
  bool appsSelecting = false;

  @override
  void initState() {
    super.initState();
    sourceProvider = context.read<SourceProvider>();
    settingsProvider = context.read<SettingsProvider>();
    appsProvider = context.read<AppsProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showWelcomeDialogs();
      if (!mounted) return;
      unawaited(initDeepLinks());
    });
  }

  void selectApp(String appId) {
    selectedAppId = appId;
    setState(() {});
  }

  void clearSelectedApp() {
    selectedAppId = null;
    setState(() {});
  }

  void setAppsSelecting(bool has) {
    appsSelecting = has;
    setState(() {});
  }

  Future<bool> waitUntil(
    bool Function() condition, {
    Duration interval = const Duration(milliseconds: 50),
    int maxAttempts = 100,
  }) async {
    var attempts = 0;
    while (!condition()) {
      if (++attempts > maxAttempts) return false;
      await Future.delayed(interval);
    }
    return true;
  }

  void pushAddApp({String? initialUrl}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddAppPage(initialUrl: initialUrl)),
    );
  }

  void pushSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  Future<void> showWelcomeDialogs() async {
    final sp = settingsProvider;
    if (!sp.welcomeShown) {
      await showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: Text(tr('welcome')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 20,
              children: [
                Text(tr('documentationLinksNote')),
                const LinkText(
                  text:
                      'https://github.com/ImranR98/Obtainium/blob/main/README.md',
                  url:
                      'https://github.com/ImranR98/Obtainium/blob/main/README.md',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              FilledButton.tonal(
                autofocus: sp.isTV,
                onPressed: () {
                  sp.welcomeShown = true;
                  Navigator.of(context).pop(null);
                },
                child: Text(tr('ok')),
              ),
            ],
          );
        },
      );
    }
    if (!mounted) return;
    if (!sp.googleVerificationWarningShown) {
      await showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: Text(tr('note')),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 20,
              children: [
                Text(tr('googleVerificationWarningP1')),
                LinkText(
                  text: tr('googleVerificationWarningP2'),
                  url: 'https://keepandroidopen.org/',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(tr('googleVerificationWarningP3')),
              ],
            ),
            actions: [
              FilledButton.tonal(
                autofocus: sp.isTV,
                onPressed: () {
                  sp.googleVerificationWarningShown = true;
                  Navigator.of(context).pop(null);
                },
                child: Text(tr('ok')),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> initDeepLinks() async {
    _appLinks = AppLinks();

    Future<void> goToAddApp(String data) async {
      if (context.mounted) pushAddApp(initialUrl: data);
    }

    Future<void> goToExistingApp(String appId) async {
      await waitUntil(
        () => appsPageKey.currentState != null,
        interval: const Duration(milliseconds: 100),
        maxAttempts: 50,
      );
      appsPageKey.currentState?.openAppById(appId);
    }

    Future<void> interpretLink(Uri uri) async {
      final action = uri.host;
      final data =
          uri.queryParameters['url'] ??
          (uri.path.length > 1
              ? Uri.decodeComponent(uri.path.substring(1))
              : '');
      try {
        if (action == 'add') {
          final AppsProvider ap = appsProvider;
          await waitUntil(
            () => !ap.loadingApps,
            interval: const Duration(milliseconds: 10),
            maxAttempts: 500,
          );

          String? standardizedUrl;
          try {
            standardizedUrl = sourceProvider.getSource(data).standardizeUrl(data);
          } catch (_) {
            standardizedUrl = null;
          }

          final AppInMemory? existingApp = ap.apps.values
              .where(
                (AppInMemory a) =>
                    a.app.url == standardizedUrl || a.app.url == data,
              )
              .firstOrNull;

          if (existingApp != null) {
            await goToExistingApp(existingApp.app.id);
          } else {
            await goToAddApp(data);
          }
        } else if (action == 'app' || action == 'apps') {
          final dataStr = Uri.decodeComponent(data);
          if (!context.mounted) return;
          if (await showDialog(
                context: context,
                builder: (BuildContext ctx) {
                  return GeneratedFormModal(
                    title: tr(
                      'importX',
                      args: [
                        (action == 'app' ? tr('app') : tr('appsString'))
                            .toLowerCase(),
                      ],
                    ),
                    items: const [],
                    additionalWidgets: [
                      ExpansionTile(
                        title: Text(tr('rawJson')),
                        children: [
                          Text(
                            dataStr,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ) !=
              null) {
            if (!context.mounted) return;
            final ap = appsProvider;
            dynamic parsedData;
            try {
              parsedData = jsonDecode(dataStr);
            } catch (e) {
              unawaited(
                LogsProvider().add(
                  'Failed to decode deep-link JSON: $e',
                  level: LogLevel.error,
                ),
              );
              throw ObtainiumError(tr('invalidInput'));
            }
            final importPayload = jsonEncode(<String, dynamic>{
              'apps': action == 'app' ? <dynamic>[parsedData] : parsedData,
            });
            final result = await ap.import(importPayload);
            if (mounted) {
              showMessage(
                tr(
                  'importedX',
                  args: [plural('apps', result.key.length).toLowerCase()],
                ),
                context,
              );
            }
          }
        } else {
          throw ObtainiumError(tr('unknown'));
        }
      } catch (e) {
        if (mounted) {
          showError(e, context);
        }
      }
    }

    final initialLink = await _appLinks.getInitialLink();
    if (initialLink != null) {
      await interpretLink(initialLink);
    }

    var dedupeInitial = initialLink != null;
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) async {
      if (dedupeInitial) {
        dedupeInitial = false;
        if (uri == initialLink) {
          return;
        }
      }
      await interpretLink(uri);
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final isTV = context.select<SettingsProvider, bool>((p) => p.isTV);

    final layoutWidth = MediaQuery.sizeOf(context).width;
    final useLargeScreen = isTV || layoutWidth >= 840;
    final useTwoPane =
        useLargeScreen && !settingsProvider.alwaysUsePhoneLayout;

    final detailPane =
        selectedAppId != null &&
            context.select<AppsProvider, bool>(
              (p) => p.apps.containsKey(selectedAppId),
            )
        ? AppPage(
            key: ValueKey(selectedAppId),
            appId: selectedAppId!,
            onClose: () => clearSelectedApp(),
          )
        : EmptyState(
            icon: Icons.touch_app_outlined,
            message: tr('selectAppForDetails'),
          );

    final appsPage = AppsPage(
      key: appsPageKey,
      onAppSelected: useTwoPane ? selectApp : null,
      selectedAppId: selectedAppId,
      onSelectionChanged: setAppsSelecting,
    );

    void onAddPressed() {
      settingsProvider.selectionClick();
      pushAddApp();
    }

    void onActionsPressed() {
      settingsProvider.selectionClick();
      appsPageKey.currentState?.showSelectedAppActions();
    }

    // Use the same extended (icon + label) FABs on every layout, so the
    // tablet/two-pane UI matches mobile.
    final actionsFab = FloatingActionButton.extended(
      onPressed: onActionsPressed,
      tooltip: plural('action', 2),
      icon: const Icon(Icons.more_vert),
      label: Text(plural('action', 2)),
    );
    final createFabExtended = FloatingActionButton.extended(
      onPressed: onAddPressed,
      tooltip: tr('addApp'),
      icon: const Icon(Icons.add),
      label: Text(tr('add')),
    );

    final loadingApps = context.select<AppsProvider, bool>((p) => p.loadingApps);

    final Widget? fab = appsSelecting
        ? actionsFab
        : (loadingApps ? null : createFabExtended);

    final Widget content;
    if (useTwoPane) {
      // Host the FAB in a nested Scaffold around the first pane so it aligns
      // with the app list instead of floating over the detail pane.
      content = Row(
        children: [
          Expanded(
            flex: 2,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: appsPage,
              floatingActionButton: fab,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(flex: 3, child: detailPane),
        ],
      );
    } else {
      content = appsPage;
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selectedAppId != null) {
          clearSelectedApp();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: useTwoPane
            ? content
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: content,
                ),
              ),
        floatingActionButton: useTwoPane ? null : fab,
      ),
    );
  }
}
