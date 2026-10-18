import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/installers/installer.dart';
import 'package:obtainium/pages/add_app.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UnusedAppsProvider extends ChangeNotifier implements AppsProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const samsung =
      'https://galaxystore.samsung.com/detail/com.samsung.android.app.sreminder';
  const github = 'https://github.com/example/app';
  const galaxyFlag = 'shizukuPretendToBeGalaxyStore';
  const playFlag = 'shizukuPretendToBeGooglePlay';
  final translations =
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;

  setUpAll(() {
    Localization.load(
      const Locale('en'),
      translations: Translations(translations),
    );
  });

  Future<SettingsProvider> pumpPage(
    WidgetTester tester,
    String url, {
    bool googlePlayDefault = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      playFlag: googlePlayDefault,
      'tactileFeedbackEnabled': false,
    });
    final settings = SettingsProvider()
      ..prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<AppsProvider>(
            create: (_) => _UnusedAppsProvider(),
          ),
          Provider<NotificationsProvider>(
            create: (_) => NotificationsProvider(),
          ),
          Provider<SourceProvider>.value(value: SourceProvider()),
        ],
        child: MaterialApp(home: AddAppPage(initialUrl: url)),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  Finder switchFor(String key) => find.descendant(
    of: find.widgetWithText(ToggleTile, translations[key] as String),
    matching: find.byType(Switch),
  );

  bool switchValue(WidgetTester tester, String key) =>
      tester.widget<Switch>(switchFor(key)).value;

  String selectedSource(WidgetTester tester, SettingsProvider settings) {
    final state = tester.state<AddAppPageState>(find.byType(AddAppPage));
    final app = SourceProvider().buildPlaceholderApp(
      state.pickedSource!,
      state.userInput,
      state.additionalSettings,
    );
    return installerPackageNameForApp(
      app,
      googlePlayDefault: settings.shizukuPretendToBeGooglePlay,
    );
  }

  testWidgets('new GitHub app retains the global Google Play default', (
    tester,
  ) async {
    final settings = await pumpPage(tester, github);
    expect(switchValue(tester, playFlag), isTrue);
    expect(switchFor(galaxyFlag), findsNothing);
    expect(selectedSource(tester, settings), 'com.android.vending');
  });

  testWidgets('Samsung spoofing defaults off without a global default', (
    tester,
  ) async {
    final settings = await pumpPage(tester, samsung, googlePlayDefault: false);
    expect(switchValue(tester, playFlag), isFalse);
    expect(switchValue(tester, galaxyFlag), isFalse);
    expect(selectedSource(tester, settings), '');
  });

  testWidgets(
    'Samsung opt-in and opt-out preserve the global Google Play rule',
    (tester) async {
      final settings = await pumpPage(tester, samsung);
      expect(switchValue(tester, playFlag), isTrue);
      expect(switchValue(tester, galaxyFlag), isFalse);

      await tester.ensureVisible(switchFor(galaxyFlag));
      await tester.pumpAndSettle();
      await tester.tap(switchFor(galaxyFlag));
      await tester.pumpAndSettle();
      expect(switchValue(tester, playFlag), isFalse);
      expect(switchValue(tester, galaxyFlag), isTrue);
      expect(
        selectedSource(tester, settings),
        'com.sec.android.app.samsungapps',
      );
      expect(settings.shizukuPretendToBeGooglePlay, isTrue);

      await tester.tap(switchFor(galaxyFlag));
      await tester.pumpAndSettle();
      expect(switchValue(tester, playFlag), isTrue);
      expect(switchValue(tester, galaxyFlag), isFalse);
      expect(selectedSource(tester, settings), 'com.android.vending');
      expect(settings.shizukuPretendToBeGooglePlay, isTrue);
    },
  );

  testWidgets('conflicting Samsung values normalize when the form rebuilds', (
    tester,
  ) async {
    final settings = await pumpPage(tester, samsung);
    final state = tester.state<AddAppPageState>(find.byType(AddAppPage));
    state.additionalSettings = {
      ...state.additionalSettings,
      playFlag: true,
      galaxyFlag: true,
    };
    state.changeUserInput(samsung, true, false, updateUrlInput: true);
    await tester.pumpAndSettle();

    expect(switchValue(tester, playFlag), isFalse);
    expect(switchValue(tester, galaxyFlag), isTrue);
    expect(state.additionalSettings[playFlag], isFalse);
    expect(selectedSource(tester, settings), 'com.sec.android.app.samsungapps');
    expect(settings.shizukuPretendToBeGooglePlay, isTrue);

    state.changeUserInput(github, true, false, updateUrlInput: true);
    await tester.pumpAndSettle();
    expect(switchFor(galaxyFlag), findsNothing);
    expect(switchValue(tester, playFlag), isTrue);
    expect(selectedSource(tester, settings), 'com.android.vending');
  });
}
