import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:provider/provider.dart';

void main() {
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
