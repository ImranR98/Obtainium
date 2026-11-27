import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/components/app_detail_widgets.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Material(child: child)),
);

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

  testWidgets('the header card opens the app from anywhere in the card', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      _wrap(
        AppHeaderCard(
          icon: const SizedBox(width: 56, height: 56),
          name: 'Obtainium',
          author: 'ImranR98',
          onOpen: () => opened++,
        ),
      ),
    );

    expect(find.text('Open'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await tester.tap(find.text('Obtainium'));
    await tester.pump();
    expect(opened, 1);

    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(opened, 2);
  });

  testWidgets('the header card is inert when the app is not installed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AppHeaderCard(
          icon: SizedBox(width: 56, height: 56),
          name: 'Obtainium',
          author: 'ImranR98',
        ),
      ),
    );

    expect(find.text('Open'), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });
}
