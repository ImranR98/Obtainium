import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/pages/apps.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAppsProvider extends ChangeNotifier implements AppsProvider {
  _FakeAppsProvider(this.settingsProvider) {
    refreshProgress.addListener(() {
      if (refreshProgress.value == 0.0) checksStarted++;
    });
  }

  int checksStarted = 0;

  @override
  final SettingsProvider settingsProvider;

  @override
  Map<String, AppInMemory> apps = {};

  @override
  bool loadingApps = false;

  @override
  Future<void> waitForAppsToLoad() async {}

  @override
  Completer<List<App>>? updateCheckCompleter;

  @override
  CancellationToken? updateCheckCancellation;

  @override
  final ValueNotifier<double?> refreshProgress = ValueNotifier<double?>(null);

  int cancelCalls = 0;

  @override
  void cancelUpdateCheck() {
    cancelCalls++;
    updateCheckCancellation?.cancel();
  }

  @override
  void notify() => notifyListeners();

  @override
  Iterable<AppInMemory> getAppValues() => apps.values;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNotificationsProvider implements NotificationsProvider {
  @override
  Future<void> cancel(int id) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final translations =
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;

  setUpAll(() {
    Localization.load(
      const Locale('en'),
      translations: Translations(translations),
    );
  });

  Future<_FakeAppsProvider> pumpAppsPage(
    WidgetTester tester, {
    required bool useRefreshButton,
  }) async {
    SharedPreferences.setMockInitialValues({
      'useRefreshButton': useRefreshButton,
      'tactileFeedbackEnabled': false,
      'checkOnStart': false,
    });
    final settings = SettingsProvider()
      ..prefs = await SharedPreferences.getInstance();
    final appsProvider = _FakeAppsProvider(settings);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<AppsProvider>.value(value: appsProvider),
          Provider<NotificationsProvider>.value(
            value: _FakeNotificationsProvider(),
          ),
          Provider<SourceProvider>.value(value: SourceProvider()),
        ],
        child: const MaterialApp(home: AppsPage()),
      ),
    );
    await tester.pump();
    return appsProvider;
  }

  Future<void> pullDown(WidgetTester tester) async {
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  test('the refresh button setting defaults to off and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider()
      ..prefs = await SharedPreferences.getInstance();
    expect(settings.useRefreshButton, isFalse);
    settings.useRefreshButton = true;
    expect(settings.useRefreshButton, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool('useRefreshButton'),
      isTrue,
    );
  });

  testWidgets('phones show no refresh button by default and keep the pull', (
    tester,
  ) async {
    final appsProvider = await pumpAppsPage(tester, useRefreshButton: false);
    expect(find.byTooltip(translations['refresh'] as String), findsNothing);

    await pullDown(tester);
    await tester.pumpAndSettle();
    expect(
      appsProvider.checksStarted,
      1,
      reason: 'pulling the list down starts a check',
    );
  });

  testWidgets('the setting shows a refresh button and turns off the pull', (
    tester,
  ) async {
    final appsProvider = await pumpAppsPage(tester, useRefreshButton: true);
    final refresh = find.byTooltip(translations['refresh'] as String);
    expect(refresh, findsOneWidget);

    await pullDown(tester);
    await tester.pumpAndSettle();
    expect(
      appsProvider.checksStarted,
      0,
      reason: 'pulling the list down does not start a check',
    );

    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(appsProvider.checksStarted, 1, reason: 'the button starts a check');
  });

  testWidgets('the button turns into a cancel button while checking', (
    tester,
  ) async {
    final appsProvider = await pumpAppsPage(tester, useRefreshButton: true);
    final refreshTooltip = translations['refresh'] as String;
    final cancelTooltip = translations['cancel'] as String;

    final token = appsProvider.updateCheckCancellation = CancellationToken();
    appsProvider.refreshProgress.value = 0.25;
    await tester.pump();
    expect(find.byTooltip(refreshTooltip), findsNothing);
    expect(find.byTooltip(cancelTooltip), findsOneWidget);

    await tester.tap(find.byTooltip(cancelTooltip));
    await tester.pump();
    expect(appsProvider.cancelCalls, 1);
    expect(token.isCancelled, isTrue);

    appsProvider.updateCheckCancellation = null;
    appsProvider.refreshProgress.value = null;
    await tester.pump();
    expect(find.byTooltip(refreshTooltip), findsOneWidget);
    expect(find.byTooltip(cancelTooltip), findsNothing);
  });
}
