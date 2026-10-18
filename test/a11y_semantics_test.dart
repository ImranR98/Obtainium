import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:provider/provider.dart';

void main() {
  Widget wrap(Widget child) {
    return ChangeNotifierProvider<SettingsProvider>(
      create: (_) => SettingsProvider(),
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('app icon exposes a single labelled tap action', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;

    await tester.pumpWidget(
      wrap(
        AppIconAction(
          semanticLabel: 'Open Foo',
          onTap: () => taps++,
          child: const SizedBox(width: 56, height: 56),
        ),
      ),
    );

    final data = tester
        .getSemantics(find.byType(AppIconAction))
        .getSemanticsData();
    expect(data.label, 'Open Foo');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(find.bySemanticsLabel('Open Foo'), findsOneWidget);

    await tester.tap(find.byType(InkWell));
    expect(taps, 1);

    handle.dispose();
  });

  testWidgets('toggle tile labels its switch and toggles it', (tester) async {
    final handle = tester.ensureSemantics();
    var value = false;

    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) => ToggleTile(
            label: 'Flag',
            value: value,
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      ),
    );

    final data = tester.getSemantics(find.byType(Switch)).getSemanticsData();
    expect(data.label, 'Flag');

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(value, isTrue);

    handle.dispose();
  });
}
