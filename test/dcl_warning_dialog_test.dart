import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/components/dcl_warning_dialog.dart';

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

  Future<void> showWarning(
    WidgetTester tester, {
    required VoidCallback onOpenSettings,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showDialog<void>(
                  context: context,
                  builder: (_) =>
                      DclWarningDialog(onOpenSettings: onOpenSettings),
                ),
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens app settings and dismisses', (tester) async {
    var opened = false;
    await showWarning(tester, onOpenSettings: () => opened = true);

    expect(find.text('Android certificate store unavailable'), findsOneWidget);
    await tester.tap(find.text('Open app settings'));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('OK dismisses without opening settings', (tester) async {
    var opened = false;
    await showWarning(tester, onOpenSettings: () => opened = true);

    await tester.tap(find.text('Okay'));
    await tester.pumpAndSettle();

    expect(opened, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
