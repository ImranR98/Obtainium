import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'progressiveBlurEnabled': true,
    });
  });

  testWidgets('solid page background retains progressive blur when enabled', (
    WidgetTester tester,
  ) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final SettingsProvider settingsProvider = SettingsProvider()
      ..prefs = preferences;
    const Color surfaceColor = Color(0xFF123456);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settingsProvider,
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: const ColorScheme.dark(surface: surfaceColor),
          ),
          home: const Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                CustomAppBar(title: 'Apps', matchGradientBackground: false),
                SliverToBoxAdapter(child: SizedBox(height: 1000)),
              ],
            ),
          ),
        ),
      ),
    );

    final Finder appBar = find.byType(CustomAppBar);
    final SliverAppBar renderedAppBar = tester.widget<SliverAppBar>(
      find.descendant(of: appBar, matching: find.byType(SliverAppBar)),
    );
    expect(renderedAppBar.backgroundColor, Colors.transparent);
    expect(renderedAppBar.forceMaterialTransparency, isTrue);
    expect(
      find.descendant(
        of: appBar,
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is ColoredBox && widget.color == surfaceColor,
        ),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: appBar,
        matching: find.byType(ScrollLinkedProgressiveBlur),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'gradient page background retains progressive blur when enabled',
    (WidgetTester tester) async {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final SettingsProvider settingsProvider = SettingsProvider()
        ..prefs = preferences;

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settingsProvider,
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: const Scaffold(
              body: CustomScrollView(
                slivers: <Widget>[
                  CustomAppBar(title: 'Apps', matchGradientBackground: true),
                  SliverToBoxAdapter(child: SizedBox(height: 1000)),
                ],
              ),
            ),
          ),
        ),
      );

      final SliverAppBar renderedAppBar = tester.widget<SliverAppBar>(
        find.descendant(
          of: find.byType(CustomAppBar),
          matching: find.byType(SliverAppBar),
        ),
      );
      expect(renderedAppBar.backgroundColor, Colors.transparent);
      expect(renderedAppBar.forceMaterialTransparency, isTrue);
      expect(
        find.descendant(
          of: find.byType(CustomAppBar),
          matching: find.byType(ScrollLinkedProgressiveBlur),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('solid page background becomes opaque when blur is disabled', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'progressiveBlurEnabled': false,
    });
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final SettingsProvider settingsProvider = SettingsProvider()
      ..prefs = preferences;
    const Color surfaceColor = Color(0xFF123456);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settingsProvider,
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: const ColorScheme.dark(surface: surfaceColor),
          ),
          home: const Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                CustomAppBar(title: 'Apps', matchGradientBackground: false),
                SliverToBoxAdapter(child: SizedBox(height: 1000)),
              ],
            ),
          ),
        ),
      ),
    );

    final Finder appBar = find.byType(CustomAppBar);
    final SliverAppBar renderedAppBar = tester.widget<SliverAppBar>(
      find.descendant(of: appBar, matching: find.byType(SliverAppBar)),
    );
    expect(renderedAppBar.backgroundColor, surfaceColor);
    expect(renderedAppBar.forceMaterialTransparency, isFalse);
    expect(
      find.descendant(
        of: appBar,
        matching: find.byType(ScrollLinkedProgressiveBlur),
      ),
      findsNothing,
    );
  });
}
