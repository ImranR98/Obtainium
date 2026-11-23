import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/theme.dart';
import 'package:provider/provider.dart';

void main() {
  Widget wrap(Widget child, {required bool isTV}) {
    final settings = SettingsProvider()..isTV = isTV;
    return ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('TV focus ring follows the supplied superellipse shape', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    const radius = BorderRadius.all(Radius.circular(AppRadii.small));

    await tester.pumpWidget(
      wrap(
        TvFocusRing(
          shape: const RoundedSuperellipseBorder(borderRadius: radius),
          child: Focus(
            focusNode: focusNode,
            child: const SizedBox(width: 160, height: 48),
          ),
        ),
        isTV: true,
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byType(TvFocusRing),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as ShapeDecoration;
    final shape = decoration.shape;
    expect(shape, isA<RoundedSuperellipseBorder>());
    expect((shape as RoundedSuperellipseBorder).borderRadius, radius);
    expect(shape.side.width, 3);
  });

  testWidgets('TV focus ring keeps the circular default shape', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      wrap(
        TvFocusRing(
          borderRadius: AppRadii.small,
          child: Focus(
            focusNode: focusNode,
            child: const SizedBox(width: 160, height: 48),
          ),
        ),
        isTV: true,
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byType(TvFocusRing),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as ShapeDecoration;
    final shape = decoration.shape;
    expect(shape, isA<RoundedRectangleBorder>());
    expect(
      (shape as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(AppRadii.small),
    );
  });

  testWidgets('TV focus ring is not drawn off TV', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      wrap(
        TvFocusRing(
          child: Focus(
            focusNode: focusNode,
            child: const SizedBox(width: 160, height: 48),
          ),
        ),
        isTV: false,
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    expect(find.byType(DecoratedBox), findsNothing);
  });
}
