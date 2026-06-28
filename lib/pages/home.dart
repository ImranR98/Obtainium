import 'dart:async';

import 'package:animations/animations.dart';
import 'package:app_links/app_links.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/pages/add_app.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/pages/apps.dart';
import 'package:obtainium/pages/settings.dart';
import 'package:obtainium/providers/apps_provider.dart';
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
  List<int> selectedIndexHistory = [];
  bool isReversing = false;
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  final GlobalKey<AppsPageState> appsPageKey = GlobalKey<AppsPageState>();
  String? selectedAppId;

  /// Whether the apps page currently has a multi-selection active. Reported by
  /// [AppsPage] via its onSelectionChanged callback so the shell can morph the
  /// FAB without reaching into the apps page's State during build.
  bool _appsSelecting = false;

  void _selectApp(String appId) {
    setState(() {
      selectedAppId = appId;
    });
  }

  void pushAddApp({String? initialUrl}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddAppPage(initialUrl: initialUrl)),
    );
  }

  @override
  void initState() {
    super.initState();
    initDeepLinks();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      var sp = context.read<SettingsProvider>();
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
      if (!sp.googleVerificationWarningShown && DateTime.now().year == 2026) {
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
    });
  }

  Future<void> initDeepLinks() async {
    _appLinks = AppLinks();

    goToAddApp(String data) async {
      await switchToPage(0);
      if (mounted) pushAddApp(initialUrl: data);
    }

    goToExistingApp(String appId) async {
      await switchToPage(0);
      await _waitUntil(
        () => appsPageKey.currentState != null,
        interval: const Duration(milliseconds: 100),
        maxAttempts: 50,
      );
      appsPageKey.currentState?.openAppById(appId);
    }

    interpretLink(Uri uri) async {
      var action = uri.host;
      var data = uri.path.length > 1 ? uri.path.substring(1) : "";
      try {
        if (action == 'add') {
          // Ensure apps are loaded
          AppsProvider appsProvider = context.read<AppsProvider>();
          await _waitUntil(
            () => !appsProvider.loadingApps,
            interval: const Duration(milliseconds: 10),
            maxAttempts: 500,
          );

          // See if we already have this app
          String standardizedUrl = SourceProvider()
              .getSource(data)
              .standardizeUrl(data);

          AppInMemory? existingApp = appsProvider.apps.values
              .where((AppInMemory a) => a.app.url == standardizedUrl)
              .firstOrNull;

          if (existingApp != null) {
            await goToExistingApp(existingApp.app.id);
          } else {
            await goToAddApp(data);
          }
        } else if (action == 'app' || action == 'apps') {
          var dataStr = Uri.decodeComponent(data);
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
                        title: const Text('Raw JSON'),
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
            // ignore: use_build_context_synchronously
            var appsProvider = context.read<AppsProvider>();
            var result = await appsProvider.import(
              action == 'app'
                  ? '{ "apps": [$dataStr] }'
                  : '{ "apps": $dataStr }',
            );
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
        if (mounted) showError(e, context);
      }
    }

    // Check initial link if app was in cold state (terminated)
    final appLink = await _appLinks.getInitialLink();
    var initLinked = false;
    if (appLink != null) {
      await interpretLink(appLink);
      initLinked = true;
    }
    // Handle link when app is in warm state (front or background)
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) async {
      if (!initLinked) {
        await interpretLink(uri);
      } else {
        initLinked = false;
      }
    });
  }

  void setIsReversing(int targetIndex) {
    bool reversing =
        selectedIndexHistory.isNotEmpty &&
        selectedIndexHistory.last > targetIndex;
    setState(() {
      isReversing = reversing;
    });
  }

  /// Polls [condition] until it returns true, yielding to the event loop
  /// between checks, up to [maxAttempts] times. Returns whether it became true.
  /// Used to coordinate GlobalKey reparenting / app loading without hanging.
  Future<bool> _waitUntil(
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
      // Wait for any existing AppsPage to detach before reusing its GlobalKey.
      await _waitUntil(
        () => appsPageKey.currentState == null,
        interval: Duration.zero,
        maxAttempts: 1000,
      );
      setState(() {
        selectedIndexHistory.clear();
      });
    } else if (selectedIndexHistory.isEmpty ||
        (selectedIndexHistory.isNotEmpty &&
            selectedIndexHistory.last != index)) {
      setState(() {
        int existingInd = selectedIndexHistory.indexOf(index);
        if (existingInd >= 0) {
          selectedIndexHistory.removeAt(existingInd);
        }
        selectedIndexHistory.add(index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    AppsProvider appsProvider = context.watch<AppsProvider>();
    SettingsProvider settingsProvider = context.watch<SettingsProvider>();

    final pages = <NavigationPageItem>[
      NavigationPageItem(
        tr('appsString'),
        Icons.apps_outlined,
        const SizedBox.shrink(), // Built below using appsPageKey.
        selectedIcon: Icons.apps,
      ),
      NavigationPageItem(
        tr('settings'),
        Icons.settings_outlined,
        const SettingsPage(),
        selectedIcon: Icons.settings,
      ),
    ];

    // Adaptive navigation: a rail on wide/landscape/TV layouts, a bottom bar on
    // compact ones. A live badge shows the number of available updates.
    final layoutWidth = MediaQuery.sizeOf(context).width;
    final useRail = settingsProvider.isTV || layoutWidth >= 600;
    final updateCount = appsProvider
        .findExistingUpdates(installedOnly: true)
        .length;

    Widget destIcon(NavigationPageItem e, {bool selected = false}) {
      final icon = Icon(selected ? (e.selectedIcon ?? e.icon) : e.icon);
      if (identical(e, pages[0]) && updateCount > 0) {
        return Semantics(
          label: '$updateCount ${tr('updates')}',
          child: Badge(label: Text('$updateCount'), child: icon),
        );
      }
      return icon;
    }

    final currentIndex = selectedIndexHistory.isEmpty
        ? 0
        : selectedIndexHistory.last;

    // When on Apps and wide enough, split into a two-pane list + detail view.
    final twoPane = settingsProvider.isTV || layoutWidth >= 900;
    final useTwoPane = twoPane && currentIndex == 0;

    final detailPane =
        selectedAppId != null && appsProvider.apps.containsKey(selectedAppId)
        ? AppPage(
            key: ValueKey(selectedAppId),
            appId: selectedAppId!,
            onClose: () => setState(() => selectedAppId = null),
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
              onAppSelected: _selectApp,
              selectedAppId: selectedAppId,
              onSelectionChanged: (has) => setState(() => _appsSelecting = has),
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
            ? AppsPage(
                key: appsPageKey,
                onSelectionChanged: (has) =>
                    setState(() => _appsSelecting = has),
              )
            : pages.elementAt(currentIndex).widget,
      );
    }

    // Shows the "Add" FAB, or hides it entirely while the user is
    // mass‑selecting apps (the apps page will show its own action FAB).
    final isSelecting = _appsSelecting;
    final createFab = FloatingActionButton(
      onPressed: () => pushAddApp(),
      tooltip: tr('addApp'),
      child: const Icon(Icons.add),
    );

    return PopScope(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (useTwoPane && selectedAppId != null) {
            setState(() => selectedAppId = null);
          } else {
            setIsReversing(0);
            setState(() {
              if (selectedIndexHistory.isNotEmpty) {
                selectedIndexHistory.removeLast();
              }
            });
          }
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: useRail
            ? Row(
                children: [
                  FocusTraversalGroup(
                    child: NavigationRail(
                      leading: currentIndex == 0 && !isSelecting
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: createFab,
                            )
                          : null,
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
                    ),
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  // In single-pane (rail) mode on wide screens, cap the content
                  // width so list rows don't stretch edge-to-edge. (Two-pane
                  // already constrains each pane via its flex.)
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
        floatingActionButton: useRail || currentIndex != 0 || isSelecting
            ? null
            : createFab,
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
                      switchToPage(index);
                    },
                    selectedIndex: currentIndex,
                  ),
                ),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }
}
