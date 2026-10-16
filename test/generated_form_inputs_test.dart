import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// Samples every generated-form input type (switch, text field, dropdown,
/// slider) and confirms each writes through to the form's value map. Controls
/// of the same type share their plumbing, so one representative each is enough.
void main() {
  Future<Map<String, dynamic> Function()> pumpForm(
    WidgetTester tester,
    List<List<GeneratedFormItem>> items,
  ) async {
    Map<String, dynamic> values = {};
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: GeneratedForm(
              items: items,
              onValueChanges: (v, _, _) => values = v,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return () => values;
  }

  testWidgets('switch writes through', (tester) async {
    final values = await pumpForm(tester, [
      [GeneratedFormSwitch('flag', label: 'Flag', value: false)],
    ]);
    expect(values()['flag'], isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(values()['flag'], isTrue);
  });

  testWidgets('text field writes through', (tester) async {
    final values = await pumpForm(tester, [
      [GeneratedFormTextField('text', label: 'Text', value: '')],
    ]);
    await tester.enterText(find.byType(TextFormField), 'typed-value');
    await tester.pump();
    expect(values()['text'], 'typed-value');
  });

  testWidgets('dropdown writes through', (tester) async {
    final values = await pumpForm(tester, [
      [
        GeneratedFormDropdown(
          'choice',
          [const MapEntry('a', 'Option A'), const MapEntry('b', 'Option B')],
          label: 'Pick',
          value: 'a',
        ),
      ],
    ]);
    expect(values()['choice'], 'a');
    await tester.tap(
      find.byWidgetPredicate((w) => w is DropdownButtonFormField),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Option B').last);
    await tester.pumpAndSettle();
    expect(values()['choice'], 'b');
  });

  testWidgets('slider writes through', (tester) async {
    final values = await pumpForm(tester, [
      [
        GeneratedFormSlider(
          'days',
          [
            const MapEntry('', 'Use global default'),
            const MapEntry('optA', 'Option A'),
            const MapEntry('optB', 'Option B'),
            const MapEntry('optC', 'Option C'),
          ],
          label: 'Days',
          value: '',
        ),
      ],
    ]);
    expect(values()['days'], '');
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pump();
    expect(values()['days'], isNotEmpty);
  });
}
