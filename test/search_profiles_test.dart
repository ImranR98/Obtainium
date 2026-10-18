import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/app_sources/gitlab.dart';
import 'package:obtainium/app_sources/samsunggalaxystore.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/installers/installer.dart';
import 'package:obtainium/pages/add_app.dart';
import 'package:obtainium/pages/import_export.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _appUrl =
    'https://apps.galaxyappstore.com/detail/com.samsung.android.app.sreminder';
const _queryOnly = 'synthetic-search-filter';

class _UnusedAppsProvider extends ChangeNotifier implements AppsProvider {
  @override
  Map<String, AppInMemory> apps = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SearchGitLab extends GitLab {
  _SearchGitLab() {
    includeAdditionalOptsInMainSearch = true;
  }

  Map<String, dynamic>? query;

  @override
  String get sourceIdentifier => 'GitLab';

  @override
  List<GeneratedFormItem> get searchQuerySettingFormItems => [
    GeneratedFormTextField(
      'searchFilter',
      label: 'Search filter',
      required: false,
    ),
  ];

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    this.query = Map.from(querySettings);
    return {
      '${querySettings['url']}/example/app': ['Example App', 'Example'],
    };
  }
}

class _SearchSamsung extends SamsungGalaxyStore {
  final queries = <Map<String, dynamic>>[];

  @override
  String get sourceIdentifier => 'SamsungGalaxyStore';

  @override
  List<SourceSearchProfile> get searchProfiles =>
      super.searchProfiles.map((profile) {
        return SourceSearchProfile(
          id: profile.id,
          name: profile.name,
          querySettings: {...profile.querySettings, 'queryOnly': _queryOnly},
          appSettings: profile.appSettings,
        );
      }).toList();

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    queries.add(Map.from(querySettings));
    return {
      _appUrl: ['Samsung App', 'Example Seller'],
    };
  }
}

class _SearchProvider implements SourceProvider {
  _SearchProvider(this.sources);

  @override
  final List<AppSource> sources;

  @override
  AppSource getSource(String url, {String? overrideSource}) =>
      SourceProvider().getSource(url, overrideSource: overrideSource);

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

  Future<SettingsProvider> settings({bool isTV = false}) async {
    SharedPreferences.setMockInitialValues({
      'shizukuPretendToBeGooglePlay': true,
      'tactileFeedbackEnabled': false,
    });
    return SettingsProvider()
      ..prefs = await SharedPreferences.getInstance()
      ..isTV = isTV;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    SettingsProvider settings, {
    SourceProvider? sourceProvider,
    String? initialUrl,
  }) async {
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
          Provider<SourceProvider>.value(
            value: sourceProvider ?? SourceProvider(),
          ),
        ],
        child: MaterialApp(home: AddAppPage(initialUrl: initialUrl)),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('new search preferences exclude every available profile', () async {
    final prefs = await settings();
    final profiles = SourceProvider().sources
        .where((source) => source.canSearch)
        .expand((source) => source.searchProfiles)
        .toList();
    expect(
      prefs.searchDeselected,
      unorderedEquals(profiles.map((profile) => profile.id)),
    );
    expect(
      prefs.searchDeselected,
      containsAll(['SamsungGalaxyStore/global', 'SamsungGalaxyStore/china']),
    );
    prefs.searchDeselected = ['SamsungGalaxyStore/china'];
    expect(prefs.searchDeselected, ['SamsungGalaxyStore/china']);
    expect(prefs.prefs!.getStringList('searchDeselected'), [
      'SamsungGalaxyStore/china',
    ]);
  });

  testWidgets(
    'search preserves duplicate URLs and carries only the selected app settings',
    (tester) async {
      final prefs = await settings();
      final source = _SearchSamsung();
      await pumpPage(tester, prefs, sourceProvider: _SearchProvider([source]));
      final state = tester.state<AddAppPageState>(find.byType(AddAppPage));
      state.searchQuery = 'Samsung';
      final search = state.runSearch(state.context);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final global = SamsungGalaxyStore().name;
      final china = tr('samsungGalaxyStoreCN');
      expect(find.text(global), findsOneWidget);
      expect(find.text(china), findsOneWidget);
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .every((box) => box.value == false),
        isTrue,
      );
      await tester.tap(find.text(global));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(china));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.widgetWithText(FilledButton, tr('selectX', args: ['2'])),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        source.queries.map((query) => query['csc']),
        unorderedEquals(['DBT', 'CHC']),
      );
      expect(
        source.queries.every((query) => query['queryOnly'] == _queryOnly),
        isTrue,
      );
      final modal = tester.widget<SelectionModal>(find.byType(SelectionModal));
      expect(modal.entries.length, 2);
      expect(modal.entryUrls.values, everyElement(_appUrl));
      expect(
        modal.entries.values.map((description) => description[1]),
        unorderedEquals([
          '$global · Example Seller',
          '$china · Example Seller',
        ]),
      );
      expect(
        tester
            .widgetList<LinkText>(find.byType(LinkText))
            .map((link) => link.url),
        everyElement(_appUrl),
      );
      expect(find.text('apps.galaxyappstore.com'), findsNWidgets(2));

      await tester.tap(find.text('$china · Example Seller'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.widgetWithText(FilledButton, tr('pick')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await search;

      expect(state.userInput, _appUrl);
      expect(state.pickedSourceOverride, 'SamsungGalaxyStore');
      expect(state.additionalSettings['csc'], 'CHC');
      expect(state.additionalSettings['deviceId'], 'SM-S9480');
      expect(state.additionalSettings.containsKey('queryOnly'), isFalse);
      expect(prefs.searchDeselected, isEmpty);
      final saved = SourceProvider().buildPlaceholderApp(
        state.pickedSource!,
        state.userInput,
        state.additionalSettings,
        sourceIsOverriden: true,
      );
      expect(saved.additionalSettings['csc'], 'CHC');
      expect(saved.additionalSettings.containsKey('queryOnly'), isFalse);
      expect(
        installerPackageNameForApp(saved, googlePlayDefault: true),
        'com.android.vending',
      );
      expect(prefs.shizukuPretendToBeGooglePlay, isTrue);
    },
  );

  testWidgets(
    'existing search settings and custom instance URLs retain their behavior',
    (tester) async {
      final prefs = await settings();
      final source = _SearchGitLab();
      await pumpPage(tester, prefs, sourceProvider: _SearchProvider([source]));
      final state = tester.state<AddAppPageState>(find.byType(AddAppPage));
      state.searchQuery = 'example';
      final search = state.runSearch(state.context);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('GitLab'));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, tr('selectX', args: ['1'])),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final fields = find.descendant(
        of: find.byType(GeneratedFormModal),
        matching: find.byType(TextFormField),
      );
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.first, _queryOnly);
      await tester.enterText(fields.last, 'https://git.example.com');
      await tester.pump();
      final formButton = find.descendant(
        of: find.byType(GeneratedFormModal),
        matching: find.byType(FilledButton),
      );
      await tester.tap(formButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(source.query!['searchFilter'], _queryOnly);
      expect(source.query!['url'], 'https://git.example.com');
      await tester.tap(find.byType(Radio<String>));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, tr('pick')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await search;
      expect(state.userInput, 'https://git.example.com/example/app');
      expect(state.pickedSourceOverride, 'GitLab');
      expect(state.pickedSource!.hosts, ['git.example.com']);
      expect(state.additionalSettings.containsKey('searchFilter'), isFalse);
      expect(state.additionalSettings.containsKey('url'), isFalse);
    },
  );

  testWidgets(
    'changing profiles on the same Samsung URL updates the form and saved settings',
    (tester) async {
      final prefs = await settings();
      await pumpPage(tester, prefs, initialUrl: _appUrl);
      final state = tester.state<AddAppPageState>(find.byType(AddAppPage));
      final profiles = SamsungGalaxyStore().searchProfiles;
      state.changeUserInput(
        _appUrl,
        true,
        false,
        updateUrlInput: true,
        overrideSource: 'SamsungGalaxyStore',
      );
      await tester.pumpAndSettle();
      final galaxySwitch = find.descendant(
        of: find.widgetWithText(
          ToggleTile,
          tr('shizukuPretendToBeGalaxyStore'),
        ),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(galaxySwitch);
      await tester.pumpAndSettle();
      await tester.tap(galaxySwitch);
      await tester.pumpAndSettle();
      for (final profile in [profiles[0], profiles[1], profiles[0]]) {
        state.changeUserInput(
          _appUrl,
          true,
          false,
          updateUrlInput: true,
          overrideSource: 'SamsungGalaxyStore',
          appSettings: profile.appSettings,
        );
        await tester.pumpAndSettle();
        for (final entry in profile.appSettings.entries) {
          expect(state.additionalSettings[entry.key], entry.value);
          expect(
            tester
                .widgetList<TextFormField>(find.byType(TextFormField))
                .map((field) => field.controller?.text),
            contains(entry.value),
          );
        }
        state.changeUserInput(_appUrl, true, false, updateUrlInput: true);
        await tester.pumpAndSettle();
        final saved = SourceProvider().buildPlaceholderApp(
          state.pickedSource!,
          state.userInput,
          state.additionalSettings,
          sourceIsOverriden: true,
        );
        expect(saved.additionalSettings['csc'], profile.appSettings['csc']);
        expect(
          saved.additionalSettings['deviceId'],
          profile.appSettings['deviceId'],
        );
        expect(
          installerPackageNameForApp(saved, googlePlayDefault: true),
          'com.sec.android.app.samsungapps',
        );
        expect(
          saved.additionalSettings['shizukuPretendToBeGalaxyStore'],
          isTrue,
        );
        expect(
          saved.additionalSettings['shizukuPretendToBeGooglePlay'],
          isFalse,
        );
      }
      expect(prefs.shizukuPretendToBeGooglePlay, isTrue);
    },
  );

  for (final isTV in [false, true]) {
    testWidgets(
      'selection IDs preserve the real URL on ${isTV ? 'TV' : 'phone'}',
      (tester) async {
        final prefs = await settings(isTV: isTV);
        List<String>? selected;
        await tester.pumpWidget(
          ChangeNotifierProvider<SettingsProvider>.value(
            value: prefs,
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      selected = await showDialog<List<String>>(
                        context: context,
                        builder: (_) => const SelectionModal(
                          entries: {
                            'global-result': [],
                            'china-result': ['Samsung App', 'China'],
                          },
                          entryUrls: {
                            'global-result': _appUrl,
                            'china-result': _appUrl,
                          },
                          selectedByDefault: false,
                          onlyOneSelectionAllowed: true,
                        ),
                      );
                    },
                    child: const Text('Search'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Search'));
        await tester.pumpAndSettle();
        expect(find.text('apps.galaxyappstore.com'), findsNWidgets(2));
        expect(find.text(_appUrl), findsOneWidget);
        if (!isTV) {
          final links = tester.widgetList<LinkText>(find.byType(LinkText));
          expect(links, hasLength(2));
          expect(links.map((link) => link.url), everyElement(_appUrl));
        }
        await tester.tap(find.text('China'));
        await tester.pumpAndSettle();
        if (!isTV) {
          await tester.tap(find.widgetWithText(FilledButton, tr('pick')));
          await tester.pumpAndSettle();
        }
        expect(selected, ['china-result']);
      },
    );
  }
}
