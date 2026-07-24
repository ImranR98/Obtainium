import 'dart:async';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/layout_breakpoints.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/pages/add_app.dart';
import 'package:obtainium/pages/apps.dart';
import 'package:obtainium/pages/import_export.dart';
import 'package:obtainium/pages/settings.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/services/shared_url_receiver.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class NavigationPageItem {
  late String title;
  late IconData icon;
  late Widget widget;

  NavigationPageItem(this.title, this.icon, this.widget);
}

class _DirectionalIndexedStack extends StatefulWidget {
  const _DirectionalIndexedStack({
    super.key,
    required this.index,
    required this.axis,
    required this.children,
  });

  final int index;
  final Axis axis;
  final List<Widget> children;

  @override
  State<_DirectionalIndexedStack> createState() =>
      _DirectionalIndexedStackState();
}

class _DirectionalIndexedStackState extends State<_DirectionalIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  int _currentIndex = 0;
  int? _previousIndex;
  int _direction = 1;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      value: 1.0,
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubicEmphasized,
    );
    _controller.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      setState(() {
        _previousIndex = null;
      });
    });
  }

  @override
  void didUpdateWidget(covariant _DirectionalIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == _currentIndex) {
      if (_previousIndex != null) {
        _controller.stop();
        _controller.value = 1.0;
        setState(() {
          _previousIndex = null;
        });
      }
      return;
    }
    _direction = widget.index > _currentIndex ? 1 : -1;
    _previousIndex = _currentIndex;
    _currentIndex = widget.index;
    _controller.forward(from: 0);
  }

  /// Ends a slide that never finished (e.g. interrupted by a shell rebuild).
  void completeTransitionIfStuck() {
    if (_previousIndex == null) return;
    _controller.stop();
    _controller.value = 1.0;
    if (!mounted) return;
    setState(() {
      _previousIndex = null;
    });
  }

  bool _pageIgnoresPointer(int index) {
    if (_previousIndex == null) {
      return index != _currentIndex;
    }
    if (index != _currentIndex && index != _previousIndex) {
      return true;
    }
    final double progress = _animation.value;
    if (index == _previousIndex) {
      return progress >= 0.5;
    }
    if (index == _currentIndex) {
      return progress < 0.5;
    }
    return true;
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  Offset _offsetFor(int index, double progress) {
    if (index == _currentIndex) {
      final double incomingOffset = _direction * (1.0 - progress);
      return widget.axis == Axis.horizontal
          ? Offset(incomingOffset, 0)
          : Offset(0, incomingOffset);
    }
    if (index == _previousIndex) {
      final double outgoingOffset = -_direction * progress;
      return widget.axis == Axis.horizontal
          ? Offset(outgoingOffset, 0)
          : Offset(0, outgoingOffset);
    }
    return Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              for (int index = 0; index < widget.children.length; index++)
                Positioned.fill(
                  child: Offstage(
                    offstage: index != _currentIndex && index != _previousIndex,
                    child: TickerMode(
                      enabled:
                          index == _currentIndex || index == _previousIndex,
                      child: IgnorePointer(
                        ignoring: _pageIgnoresPointer(index),
                        child: FractionalTranslation(
                          translation: _offsetFor(index, _animation.value),
                          child: widget.children[index],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class HomePageState extends State<HomePage> {
  List<int> selectedIndexHistory = [];
  int pageSwitchRequestId = 0;
  int prevAppCount = -1;
  bool prevIsLoading = true;
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  final SharedUrlReceiver _sharedUrlReceiver = SharedUrlReceiver();
  bool isLinkActivity = false;

  /// Bumps when [AppsPageState] FAB chrome (badge, mass obtain, selection)
  /// changes so the bottom nav FAB row can rebuild without [setState] on
  /// [HomePageState] (avoids relayout during pointer routing / tooltips).
  final ValueNotifier<int> appsTabFabChromeTick = ValueNotifier<int>(0);
  int? _lastHomeAppsFabProviderSyncKey;
  bool _homeFabNullStateRetryScheduled = false;

  final GlobalKey<_DirectionalIndexedStackState> _pageStackKey =
      GlobalKey<_DirectionalIndexedStackState>();

  void _onAppsPageFabStateChanged() {
    if (!mounted) return;
    final int activeIndex = selectedIndexHistory.isEmpty
        ? 0
        : selectedIndexHistory.last;
    if (activeIndex != 0) return;
    setState(() {});
  }

  late final List<NavigationPageItem> pages = [
    NavigationPageItem(
      tr('appsString'),
      Icons.apps,
      AppsPage(
        key: GlobalKey<AppsPageState>(),
        homeFabChromeTick: appsTabFabChromeTick,
        onStateChanged: _onAppsPageFabStateChanged,
      ),
    ),
    NavigationPageItem(
      tr('addApp'),
      Icons.add,
      AddAppPage(
        key: GlobalKey<AddAppPageState>(),
        homeFabChromeTick: appsTabFabChromeTick,
        onStateChanged: _onAppsPageFabStateChanged,
      ),
    ),
    NavigationPageItem(
      tr('importExport'),
      Icons.backup_outlined,
      const ImportExportPage(),
    ),
    NavigationPageItem(
      tr('settings'),
      Icons.settings,
      SettingsPage(key: GlobalKey<SettingsPageState>()),
    ),
  ];

  @override
  void initState() {
    super.initState();
    initDeepLinks();
  }

  /// Waits for [key.currentState] to become non-null by checking once per
  /// frame instead of busy-looping with microsecond delays.
  Future<T> _waitForState<T extends State>(GlobalKey<T> key) {
    if (key.currentState != null) return Future.value(key.currentState!);
    final completer = Completer<T>();
    void check(Duration _) {
      if (key.currentState != null) {
        completer.complete(key.currentState!);
      } else {
        WidgetsBinding.instance.addPostFrameCallback(check);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(check);
    return completer.future;
  }

  Future<void> switchToAppsTabAndOpenApp(String appId) async {
    await switchToPage(0);
    final state = await _waitForState(
      pages[0].widget.key as GlobalKey<AppsPageState>,
    );
    state.openAppById(appId);
  }

  Future<void> initDeepLinks() async {
    _appLinks = AppLinks();
    final AppsProvider appsProvider = context.read<AppsProvider>();
    final NavigatorState navigator = Navigator.of(context);

    Future<void> goToAddApp(String data) async {
      unawaited(switchToPage(1));
      final state = await _waitForState(
        pages[1].widget.key as GlobalKey<AddAppPageState>,
      );
      state.linkFn(data);
    }

    Future<void> goToExistingApp(String appId) async {
      // Go to Apps page
      unawaited(switchToPage(0));
      final state = await _waitForState(
        pages[0].widget.key as GlobalKey<AppsPageState>,
      );
      // Navigate to the app
      state.openAppById(appId);
    }

    Future<void> handleAddUrl(String data) async {
      // Ensure apps are loaded
      while (appsProvider.loadingApps) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // See if we already have this app
      final String standardizedUrl = SourceProvider()
          .getSource(data)
          .standardizeUrl(data);

      final AppInMemory? existingApp = appsProvider.apps.values
          .where((AppInMemory a) => a.app.url == standardizedUrl)
          .firstOrNull;

      if (existingApp != null) {
        await goToExistingApp(existingApp.app.id);
      } else {
        await goToAddApp(data);
      }
    }

    Future<void> handleSharedText(String sharedText) async {
      isLinkActivity = true;
      final String? sharedUrl = SharedUrlReceiver.extractFirstUrl(sharedText);
      if (sharedUrl == null) {
        showError(UnsupportedURLError());
        return;
      }
      try {
        await handleAddUrl(sharedUrl);
      } catch (e) {
        showError(e);
      }
    }

    Future<void> interpretLink(Uri uri) async {
      isLinkActivity = true;
      final action = uri.host;
      final data = uri.path.length > 1 ? uri.path.substring(1) : '';
      try {
        if (action == 'add') {
          await handleAddUrl(data);
        } else if (action == 'app' || action == 'apps') {
          final dataStr = Uri.decodeComponent(data);
          if (!navigator.mounted) return;
          if (await showDialog(
                context: navigator.context,
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
            final result = await appsProvider.import(
              action == 'app'
                  ? '{ "apps": [$dataStr] }'
                  : '{ "apps": $dataStr }',
            );
            showMessage(
              tr(
                'importedX',
                args: [plural('apps', result.key.length).toLowerCase()],
              ),
            );
          }
        } else {
          throw ObtainiumError(tr('unknown'));
        }
      } catch (e) {
        showError(e);
      }
    }

    // Check initial link if app was in cold state (terminated)
    final appLink = await _appLinks.getInitialLink();
    var initLinked = false;
    if (appLink != null) {
      await interpretLink(appLink);
      initLinked = true;
    }
    _sharedUrlReceiver.listen(handleSharedText);
    final String? initialSharedText = await _sharedUrlReceiver
        .getInitialSharedText();
    if (initialSharedText != null) {
      await handleSharedText(initialSharedText);
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

  Widget _floatingHomeNavigationBar({
    required List<NavigationPageItem> pages,
    required int selectedIndex,
    required int updateCount,
    required bool blurBottomNav,
    required ColorScheme scheme,
    required BuildContext context,
  }) {
    context.select<AppsProvider, int>(
      (AppsProvider provider) => Object.hash(
        provider.loadingApps,
        provider.appsListRevision,
        provider.apps.length,
        provider.pendingUpdateCount,
        provider.areDownloadsRunning(),
      ),
    );
    return ValueListenableBuilder<int>(
      valueListenable: appsTabFabChromeTick,
      builder: (BuildContext context, int _, Widget? child) {
        return _floatingHomeNavigationBarContent(
          pages: pages,
          selectedIndex: selectedIndex,
          blurBottomNav: blurBottomNav,
          scheme: scheme,
          context: context,
        );
      },
    );
  }

  Widget _floatingHomeNavigationBarContent({
    required List<NavigationPageItem> pages,
    required int selectedIndex,
    required bool blurBottomNav,
    required ColorScheme scheme,
    required BuildContext context,
  }) {
    final bool keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final double bottomInset = MediaQuery.of(context).padding.bottom;

    bool isAddAppSubFlowActive = false;
    if (selectedIndex == 1) {
      final key = pages[1].widget.key;
      if (key is GlobalKey<AddAppPageState>) {
        if (key.currentState != null) {
          isAddAppSubFlowActive = key.currentState!.isSubFlowActive;
        }
      }
    }

    // Check AppsPageState for side FABs when on the Apps tab (selectedIndex == 0)
    Widget? leadingFab;
    Widget? trailingFab;

    if (selectedIndex == 0) {
      final key = pages[0].widget.key;
      if (key is GlobalKey<AppsPageState>) {
        if (key.currentState != null) {
          final state = key.currentState!;

          // 1. Left side FAB: Update-all FAB (when operations available) with bottom-left badge
          if (state.hasMassObtainOperations) {
            final Widget fabButton = FloatingActionButton.small(
              heroTag: 'home_update_all_fab',
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              onPressed: () {
                hapticSelection();
                state.runMassObtain();
              },
              tooltip: null,
              child: const Icon(Icons.file_download_outlined, size: 20),
            );

            leadingFab = Stack(
              clipBehavior: Clip.none,
              children: [
                fabButton,
                if (state.pageUpdateCount > 0)
                  Positioned(
                    left: -4,
                    bottom: -4,
                    child: Badge(
                      label: Text(state.pageUpdateCount.toString()),
                      backgroundColor: scheme.error,
                      textColor: scheme.onError,
                    ),
                  ),
              ],
            );
          }

          // 2. Right side FAB: View Options FAB or Selection Actions FAB
          if (state.isSelectionActive) {
            trailingFab = FloatingActionButton.small(
              heroTag: 'home_actions_fab',
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              onPressed: () {
                hapticSelection();
                state.openSelectionActionsSheet();
              },
              tooltip: null,
              child: const Icon(Icons.checklist, size: 20),
            );
          } else {
            trailingFab = FloatingActionButton.small(
              heroTag: 'home_view_options_fab',
              backgroundColor: scheme.surfaceContainerHighest,
              foregroundColor: scheme.onSurfaceVariant,
              onPressed: () {
                hapticSelection();
                state.openViewOptionsSheet();
              },
              tooltip: null,
              child: const Icon(Icons.tune, size: 20),
            );
          }
        } else if (!_homeFabNullStateRetryScheduled) {
          _homeFabNullStateRetryScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _homeFabNullStateRetryScheduled = false;
            if (mounted) {
              appsTabFabChromeTick.value = appsTabFabChromeTick.value + 1;
            }
          });
        }
      }
    }

    final Widget pillRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(pages.length, (int index) {
        final bool isSelected = selectedIndex == index;
        final page = pages[index];

        final Widget iconWidget = Icon(
          page.icon,
          size: 21,
          color: isSelected
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            hapticSelection();
            unawaited(switchToPage(index));
          },
          child: AnimatedContainer(
            // M3 expressive (emphasized) motion, matched to the page transition
            // above so the selection indicator settles in sync with the page.
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubicEmphasized,
            margin: const EdgeInsets.symmetric(horizontal: 2.0),
            padding: EdgeInsets.symmetric(
              horizontal: isSelected ? 15.0 : 11.0,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              color: isSelected ? scheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                iconWidget,
                ClipRect(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutCubicEmphasized,
                    child: isSelected
                        ? Padding(
                            padding: const EdgeInsets.only(left: 7.0),
                            child: Text(
                              page.title,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );

    final Widget pillContent = Padding(
      padding: const EdgeInsets.all(5.0),
      child: pillRow,
    );

    final Widget pillShape = Material(
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(30),
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(30),
            ),
            child: pillContent,
          ),
        ),
      ),
    );

    final Widget compositeRow = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 48,
          child: leadingFab != null
              ? Align(alignment: Alignment.centerRight, child: leadingFab)
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: 8),
        pillShape,
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          child: trailingFab != null
              ? Align(alignment: Alignment.centerLeft, child: trailingFab)
              : const SizedBox.shrink(),
        ),
      ],
    );

    return AnimatedSlide(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubicEmphasized,
      offset: (keyboardOpen || isAddAppSubFlowActive)
          ? const Offset(0, 1.5)
          : Offset.zero,
      child: Padding(
        padding: EdgeInsets.only(
          left: 12.0,
          right: 12.0,
          bottom: 10.0 + bottomInset,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FittedBox(fit: BoxFit.scaleDown, child: compositeRow),
        ),
      ),
    );
  }

  Future<void> switchToPage(int index) async {
    final int activeIndex = selectedIndexHistory.isEmpty
        ? 0
        : selectedIndexHistory.last;
    if (activeIndex == index) {
      _pageStackKey.currentState?.completeTransitionIfStuck();
      return;
    }

    if (!await _confirmActivePageCanNavigateAway(activeIndex)) {
      return;
    }
    if (!mounted) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();

    pageSwitchRequestId += 1;
    final int currentRequestId = pageSwitchRequestId;

    if (index == 0) {
      if (!mounted || currentRequestId != pageSwitchRequestId) {
        return;
      }
      setState(() {
        selectedIndexHistory.clear();
      });
    } else if (selectedIndexHistory.isEmpty ||
        (selectedIndexHistory.isNotEmpty &&
            selectedIndexHistory.last != index)) {
      if (!mounted || currentRequestId != pageSwitchRequestId) {
        return;
      }
      setState(() {
        final int existingIndex = selectedIndexHistory.indexOf(index);
        if (existingIndex >= 0) {
          selectedIndexHistory.removeAt(existingIndex);
        }
        selectedIndexHistory.add(index);
      });
    }
  }

  Future<bool> _confirmActivePageCanNavigateAway(int activeIndex) async {
    final currentKey = pages[activeIndex].widget.key;
    if (currentKey is GlobalKey<AddAppPageState>) {
      return currentKey.currentState?.confirmCancelBulkScanForNavigation() ??
          true;
    }
    if (currentKey is GlobalKey<SettingsPageState>) {
      return currentKey.currentState?.confirmDiscardUnsavedChanges() ?? true;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Only the app-count, loading flag, and update count are needed here;
    // using select() avoids rebuilding the home scaffold on every
    // download-progress notification.
    final (int appsCount, bool isLoading, int updateCount) = context
        .select<AppsProvider, (int, bool, int)>(
          (p) => (p.apps.length, p.loadingApps, p.pendingUpdateCount),
        );
    // Only shell layout settings are watched here; page switching is handled
    // locally by the mounted tab stack.
    context.select<SettingsProvider, int>(
      (s) => Object.hash(s.progressiveBlurEnabled, s.alwaysUsePhoneLayout),
    );
    final SettingsProvider settingsProvider = context.read<SettingsProvider>();

    final AddAppPageState? addPageState =
        (pages[1].widget.key as GlobalKey<AddAppPageState>).currentState;
    if (!prevIsLoading &&
        prevAppCount >= 0 &&
        appsCount > prevAppCount &&
        selectedIndexHistory.isNotEmpty &&
        selectedIndexHistory.last == 1 &&
        !isLinkActivity &&
        !(addPageState?.isBulkAdding ?? false)) {
      switchToPage(0);
    }
    prevAppCount = appsCount;
    prevIsLoading = isLoading;

    final int homeAppsFabProviderSyncKey = Object.hash(
      appsCount,
      isLoading,
      updateCount,
    );
    if (_lastHomeAppsFabProviderSyncKey != null &&
        homeAppsFabProviderSyncKey != _lastHomeAppsFabProviderSyncKey) {
      appsTabFabChromeTick.value = appsTabFabChromeTick.value + 1;
    }
    _lastHomeAppsFabProviderSyncKey = homeAppsFabProviderSyncKey;

    return PopScope(
      canPop:
          isLinkActivity &&
          selectedIndexHistory.length == 1 &&
          selectedIndexHistory.last == 1,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        final int activeIndex = selectedIndexHistory.isEmpty
            ? 0
            : selectedIndexHistory.last;
        final currentKey = pages[activeIndex].widget.key;
        if (currentKey is GlobalKey<AddAppPageState>) {
          final AddAppPageState? addAppPageState = currentKey.currentState;
          if (addAppPageState != null) {
            // The nested Add App PopScope owns back navigation while its
            // launcher is showing an inline flow. Handling the same event here
            // would open a second discard dialog and then switch tabs.
            if (addAppPageState.hasInlineLauncherFlow) return;
            if (!await addAppPageState.confirmCancelBulkScanForNavigation()) {
              return;
            }
            if (!mounted || !addAppPageState.mounted) {
              return;
            }
            if (addAppPageState.handleBack()) return;
          }
        }
        if (currentKey is GlobalKey<SettingsPageState>) {
          final SettingsPageState? settingsPageState = currentKey.currentState;
          if (settingsPageState != null) {
            if (!await settingsPageState.confirmDiscardUnsavedChanges()) {
              return;
            }
          }
        }
        if (currentKey is GlobalKey<AppsPageState>) {
          if (currentKey.currentState?.handleBack() == true) return;
        }
        if (selectedIndexHistory.isNotEmpty) {
          setState(() {
            selectedIndexHistory.removeLast();
          });
          return;
        }
        final AppsPageState? appsPageState =
            (pages[0].widget.key as GlobalKey<AppsPageState>).currentState;
        if (appsPageState == null || !appsPageState.handleBack()) {
          // Root route: Navigator.pop would remove [HomePage] and leave an empty
          // [MaterialApp] (black screen). Minimize/finish the activity instead.
          unawaited(SystemNavigator.pop());
        }
      },
      child: Builder(
        builder: (BuildContext context) {
          final ColorScheme scheme = Theme.of(context).colorScheme;
          final bool blurBottomNav = settingsProvider.progressiveBlurEnabled;
          final double screenWidth = MediaQuery.sizeOf(context).width;
          final Orientation orientation = MediaQuery.orientationOf(context);
          final Axis pageTransitionAxis = orientation == Orientation.landscape
              ? Axis.vertical
              : Axis.horizontal;
          final bool isLargeScreen =
              screenWidth >= kLargeScreenWidthBreakpoint &&
              !settingsProvider.alwaysUsePhoneLayout;

          // Shared icon builder (adds the update-count badge to the first tab),
          // and build only the destination list the current layout actually
          // uses instead of both every frame.
          Widget navIcon(MapEntry<int, NavigationPageItem> entry) =>
              entry.key == 0 && updateCount > 0
              ? Badge(
                  label: Text(updateCount.toString()),
                  child: Icon(entry.value.icon),
                )
              : Icon(entry.value.icon);

          // NavigationRailDestination.selectedIcon defaults to [icon] when
          // omitted, so the previous explicit duplicate isn't needed.
          final List<NavigationRailDestination> homeNavRailDestinations =
              isLargeScreen
              ? pages
                    .asMap()
                    .entries
                    .map(
                      (entry) => NavigationRailDestination(
                        icon: navIcon(entry),
                        label: Text(entry.value.title),
                      ),
                    )
                    .toList()
              : const <NavigationRailDestination>[];

          final int homeNavSelectedIndex = selectedIndexHistory.isEmpty
              ? 0
              : selectedIndexHistory.last;

          return Scaffold(
            // Don't resize the shell for the keyboard. A resize relays-out and
            // lifts the bottom nav bar every frame of the keyboard animation,
            // and the nav bar's progressive blur (a BackdropFilter) re-rasterizes
            // on each of those frames — that is the staggered nav-bar slide and
            // the keyboard-slide stutter. With this off the nav bar stays put and
            // the keyboard simply overlays it, so the blur is never re-rastered.
            // Note this also stops the shell consuming the bottom inset, so it
            // reaches the nested Apps/Add-App Scaffolds — they are deliberately
            // resizeToAvoidBottomInset:false too, because extendBody draws their
            // bodies behind this blurred nav bar and a per-frame body relayout
            // would re-raster the blur and bring the stutter back. Trade-off:
            // the keyboard overlays bottom content rather than pushing it up
            // (the search/URL fields are top-anchored, so they stay visible).
            resizeToAvoidBottomInset: false,
            backgroundColor: scheme.surface,
            extendBody: !isLargeScreen,
            body: isLargeScreen
                ? Builder(
                    builder: (BuildContext context) {
                      return Row(
                        children: [
                          MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              padding: MediaQuery.of(context).padding.copyWith(
                                left: MediaQuery.of(context).padding.left > 0
                                    ? 24.0
                                    : 0.0,
                                right: MediaQuery.of(context).padding.right > 0
                                    ? 24.0
                                    : 0.0,
                              ),
                            ),
                            child: NavigationRail(
                              selectedIndex: homeNavSelectedIndex,
                              onDestinationSelected: (int index) async {
                                hapticSelection();
                                unawaited(switchToPage(index));
                              },
                              labelType: NavigationRailLabelType.all,
                              destinations: homeNavRailDestinations,
                              backgroundColor: scheme.surface,
                            ),
                          ),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: scheme.outlineVariant.withAlpha(50),
                          ),
                          Expanded(
                            child: MediaQuery.removePadding(
                              context: context,
                              removeLeft: true,
                              removeRight: true,
                              child: _DirectionalIndexedStack(
                                key: _pageStackKey,
                                index: homeNavSelectedIndex,
                                axis: pageTransitionAxis,
                                children: pages.map((p) => p.widget).toList(),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      // Keep all four pages mounted while sliding only the
                      // active page pair during tab changes.
                      _DirectionalIndexedStack(
                        key: _pageStackKey,
                        index: homeNavSelectedIndex,
                        axis: pageTransitionAxis,
                        children: pages.map((p) => p.widget).toList(),
                      ),
                      _floatingHomeNavigationBar(
                        pages: pages,
                        selectedIndex: homeNavSelectedIndex,
                        updateCount: updateCount,
                        blurBottomNav: blurBottomNav,
                        scheme: scheme,
                        context: context,
                      ),
                    ],
                  ),
            bottomNavigationBar: null,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    appsTabFabChromeTick.dispose();
    _linkSubscription?.cancel();
    _sharedUrlReceiver.dispose();
    super.dispose();
  }
}
