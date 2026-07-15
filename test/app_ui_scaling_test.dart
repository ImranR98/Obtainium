import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/app_ui_scaling.dart';

void main() {
  const double minimumScale = 0.75;
  const double maximumScale = 1.25;

  TextScaler buildScaler({
    required double systemScale,
    required double userScale,
  }) {
    return cappedAppTextScaler(
      systemTextScaler: TextScaler.linear(systemScale),
      userScale: userScale,
      minimumEffectiveScale: minimumScale,
      maximumEffectiveScale: maximumScale,
    );
  }

  test('default UI scale caps oversized system text scaling', () {
    final TextScaler scaler = buildScaler(systemScale: 3.0, userScale: 1.0);

    expect(scaler.scale(10), 12);
    expect(scaler.scale(20), 24);
  });

  test('default UI scale preserves system scaling below the cap', () {
    final TextScaler scaler = buildScaler(systemScale: 1.1, userScale: 1.0);

    expect(scaler.scale(20), 22);
  });

  test('custom UI scale cannot exceed the app-supported maximum', () {
    final TextScaler scaler = buildScaler(systemScale: 3.0, userScale: 1.25);

    expect(scaler.scale(20), 25);
  });

  test('custom UI scale cannot fall below the app-supported minimum', () {
    final TextScaler scaler = buildScaler(systemScale: 0.5, userScale: 0.75);

    expect(scaler.scale(20), 15);
  });
}
