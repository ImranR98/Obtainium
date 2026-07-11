import 'dart:async';
import 'dart:convert';

import 'package:animations/animations.dart';
import 'package:app_links/app_links.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class NavigationPageItem {
  late String title;
  late IconData icon;
  late IconData? selectedIcon;
  late Widget widget;

  NavigationPageItem(this.title, this.icon, this.widget, {this.selectedIcon});
}

class _HomePageState extends State<HomePage> {
  late final SourceProvider sourceProvider;
  late final SettingsProvider settingsProvider;
  late final AppsProvider appsProvider;

  List<int> selectedIndexHistory = [];
  bool isReversing = false;
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

  int get currentIndex =>
      selectedIndexHistory.isEmpty ? 0 : selectedIndexHistory.last;

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

  void setIsReversing(int targetIndex) {
    final bool reversing =
        selectedIndexHistory.isNotEmpty &&
        selectedIndexHistory.last > targetIndex;
    isReversing = reversing;
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

  Future<void> switchToPage(int index) async {
    setIsReversing(index);
    if (index == 0) {
      selectedIndexHistory.clear();
    } else {
      if (selectedIndexHistory.isEmpty || selectedIndexHistory.last != index) {
        final int existingInd = selectedIndexHistory.indexOf(index);
        if (existingInd >= 0) {
          selectedIndexHistory.removeAt(existingInd);
        }
        selectedIndexHistory.add(index);
      }
      if (appsSelecting) {
        appsSelecting = false;
        appsPageKey.currentState?.clearSelected();
      }
    }
    if (mounted) setState(() {});
  }

  void handlePop(bool useTwoPane) {
    if (useTwoPane && selectedAppId != null) {
      clearSelectedApp();
    } else {
      setIsReversing(0);
      if (selectedIndexHistory.isNotEmpty) {
        selectedIndexHistory.removeLast();
      }
      setState(() {});
    }
  }

  void pushAddApp({String? initialUrl}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddAppPage(initialUrl: initialUrl)),
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
      await switchToPage(0);
      if (context.mounted) pushAddApp(initialUrl: data);
    }

    Future<void> goToExistingApp(String appId) async {
      await switchToPage(0);
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
            standardizedUrl = sourceProvider
                .getSource(data)
                .standardizeUrl(data);
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

    final pages = <NavigationPageItem>[
      NavigationPageItem(
        tr('appsString'),
        Icons.apps_outlined,
        const SizedBox.shrink(),
        selectedIcon: Icons.apps,
      ),
      NavigationPageItem(
        tr('settings'),
        Icons.settings_outlined,
        const SettingsPage(),
        selectedIcon: Icons.settings,
      ),
    ];

    final layoutWidth = MediaQuery.sizeOf(context).width;
    final useLargeScreen = isTV || layoutWidth >= 840;
    final useRail = useLargeScreen && !settingsProvider.alwaysUsePhoneLayout;
    final updateCount = context.select<AppsProvider, int>(
      (p) => p.findAppIdsWithPendingUpdates(installedOnly: true).length,
    );

    Widget destIcon(NavigationPageItem e, {bool selected = false}) {
      final icon = Icon(selected ? (e.selectedIcon ?? e.icon) : e.icon);
      if (e.title == tr('appsString') && updateCount > 0) {
        return Semantics(
          label: '$updateCount ${tr('updates')}',
          child: Badge(label: Text('$updateCount'), child: icon),
        );
      }
      return icon;
    }

    final currentIndex = this.currentIndex;

    final twoPane = useLargeScreen && !settingsProvider.alwaysUsePhoneLayout;
    final useTwoPane = twoPane && currentIndex == 0;

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

    final Widget content;
    if (useTwoPane) {
      content = Row(
        children: [
          Expanded(
            flex: 2,
            child: AppsPage(
              key: appsPageKey,
              onAppSelected: selectApp,
              selectedAppId: selectedAppId,
              onSelectionChanged: setAppsSelecting,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(flex: 3, child: detailPane),
        ],
      );
    } else {
      content = PageTransitionSwitcher(
        duration: Duration(
          milliseconds: settingsProvider.disablePageTransitions ? 0 : 300,
        ),
        reverse: settingsProvider.reversePageTransitions
            ? !isReversing
            : isReversing,
        transitionBuilder: (child, animation, secondaryAnimation) {
          return SharedAxisTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            transitionType: SharedAxisTransitionType.horizontal,
            child: child,
          );
        },
        child: currentIndex == 0
            ? AppsPage(key: appsPageKey, onSelectionChanged: setAppsSelecting)
            : pages.elementAt(currentIndex).widget,
      );
    }

    void onAddPressed() {
      settingsProvider.selectionClick();
      pushAddApp();
    }

    // Compact FAB for the rail trailing (an extended FAB would overflow it);
    // an expressive extended FAB for the bottom layout's primary action.
    final createFab = FloatingActionButton(
      onPressed: onAddPressed,
      tooltip: tr('addApp'),
      child: const Icon(Icons.add),
    );
    final actionsFab = FloatingActionButton(
      onPressed: () {
        settingsProvider.selectionClick();
        appsPageKey.currentState?.showSelectedAppActions();
      },
      tooltip: plural('action', 2),
      child: const Icon(Icons.more_vert),
    );
    final createFabExtended = FloatingActionButton.extended(
      onPressed: onAddPressed,
      tooltip: tr('addApp'),
      icon: const Icon(Icons.add),
      label: Text(tr('add')),
    );

    return PopScope(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          handlePop(useTwoPane);
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: useRail
            ? Row(
                children: [
                  FocusTraversalGroup(
                    child: NavigationRail(
                      groupAlignment: isTV ? -1.0 : 0.0,
                      destinations: pages
                          .map(
                            (e) => NavigationRailDestination(
                              icon: destIcon(e),
                              selectedIcon: destIcon(e, selected: true),
                              label: Text(e.title),
                            ),
                          )
                          .toList(),
                      selectedIndex: currentIndex,
                      onDestinationSelected: switchToPage,
                      labelType: NavigationRailLabelType.all,
                      trailing: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: currentIndex != 0
                            ? const SizedBox(width: 56, height: 56)
                            : appsSelecting
                            ? actionsFab
                            : createFab,
                      ),
                    ),
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  Expanded(
                    child: useTwoPane
                        ? content
                        : Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: content,
                            ),
                          ),
                  ),
                ],
              )
            : content,
        floatingActionButton: useRail || currentIndex != 0 || appsSelecting
            ? null
            : createFabExtended,
        bottomNavigationBar: useRail
            ? null
            : FocusTraversalGroup(
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      switchToPage((currentIndex + 1) % pages.length);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      switchToPage(
                        (currentIndex - 1 + pages.length) % pages.length,
                      );
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: NavigationBar(
                    destinations: pages
                        .map(
                          (e) => NavigationDestination(
                            icon: destIcon(e),
                            selectedIcon: destIcon(e, selected: true),
                            label: e.title,
                          ),
                        )
                        .toList(),
                    onDestinationSelected: (int index) async {
                      settingsProvider.selectionClick();
                      unawaited(switchToPage(index));
                    },
                    selectedIndex: currentIndex,
                  ),
                ),
              ),
      ),
    );
  }
}
