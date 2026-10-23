import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('conflicting exclusive values normalize on load and rebuild', (
    tester,
  ) async {
    Map<String, dynamic> values = {};
    var play = true;
    var galaxy = true;
    late StateSetter setOuter;
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setOuter = setState;
                return GeneratedForm(
                  items: [
                    [
                      GeneratedFormSwitch(
                        'play',
                        value: play,
                        mutuallyExclusiveWith: ['galaxy'],
                      ),
                    ],
                    [
                      GeneratedFormSwitch(
                        'galaxy',
                        value: galaxy,
                        mutuallyExclusiveWith: ['play'],
                      ),
                    ],
                  ],
                  onValueChanges: (v, _, _) => values = v,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(values, {'play': false, 'galaxy': true});
    setOuter(() {
      play = false;
      galaxy = false;
    });
    await tester.pump();
    expect(values, {'play': false, 'galaxy': false});
    setOuter(() {
      play = true;
      galaxy = true;
    });
    await tester.pump();
    expect(values, {'play': false, 'galaxy': true});
  });

  testWidgets('GeneratedForm syncs item value changes in place', (
    tester,
  ) async {
    Map<String, dynamic> values = {};
    List<List<GeneratedFormItem>> items = [
      [GeneratedFormTextField('token', value: 'saved')],
    ];
    late StateSetter setOuter;
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setOuter = setState;
                return GeneratedForm(
                  items: items,
                  onValueChanges: (v, _, _) => values = v,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('saved'), findsOneWidget);
    expect(values['token'], 'saved');

    setOuter(() {
      items = [
        [GeneratedFormTextField('token', value: '')],
      ];
    });
    await tester.pump();
    expect(find.text('saved'), findsNothing);
    expect(values['token'], '');
  });
}
