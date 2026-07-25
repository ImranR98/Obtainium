import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/components/app_dropdown_field.dart';

void main() {
  testWidgets(
    'menu width shrinks safely when requested minimum exceeds available width',
    (WidgetTester tester) async {
      final Map<String, double> measuredWidths = <String, double>{};

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(190, 800)),
            child: Builder(
              builder: (BuildContext context) {
                measuredWidths['importExport'] = appDropdownMenuWidth(
                  context,
                  const <String>['Apps'],
                  horizontalPadding: 96,
                  minWidth: 150,
                  maxWidthInset: 120,
                );
                measuredWidths['locale'] = appDropdownMenuWidth(
                  context,
                  const <String>['System'],
                  horizontalPadding: 96,
                  minWidth: 150,
                  maxWidthInset: 48,
                );
                measuredWidths['swipeAction'] = appDropdownMenuWidth(
                  context,
                  const <String>['None'],
                  horizontalPadding: 120,
                  minWidth: 180,
                  maxWidthInset: 80,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(measuredWidths['importExport'], 70);
      expect(measuredWidths['locale'], 142);
      expect(measuredWidths['swipeAction'], 110);
    },
  );

  testWidgets(
    'menu width preserves its requested minimum when space is available',
    (WidgetTester tester) async {
      double? measuredWidth;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Builder(
              builder: (BuildContext context) {
                measuredWidth = appDropdownMenuWidth(
                  context,
                  const <String>['Short'],
                  horizontalPadding: 0,
                  minWidth: 150,
                  maxWidthInset: 48,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(measuredWidth, 150);
    },
  );
}
