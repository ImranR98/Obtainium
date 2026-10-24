import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/components/app_detail_widgets.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:provider/provider.dart';

void main() {
  setUpAll(() {
    Localization.load(
      const Locale('en'),
      translations: Translations(
        jsonDecode(File('assets/translations/en.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
    );
  });

  testWidgets('opens the source URL in an external browser', (tester) async {
    const url = 'https://github.com/example/app';
    const app = App(
      id: 'com.example.app',
      url: url,
      author: 'Example',
      name: 'Example',
      latestVersion: '1.0.0',
      preferredApkIndex: 0,
      additionalSettings: {},
    );

    final calls = <MethodCall>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: AppInfoDialog(
              app: AppInMemory(app, null, null, null),
              appsProvider: AppsProvider(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(url));
    await tester.pump();
    await tester.tap(find.text('Open in browser'));
    await tester.pump();

    expect(calls, hasLength(2));
    for (final call in calls) {
      expect(call.method, 'launch');
      expect(call.arguments['url'], url);
      expect(call.arguments['useWebView'], false);
      expect(call.arguments['useSafariVC'], false);
    }
  });
}
