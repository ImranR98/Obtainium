import 'package:flutter/widgets.dart';

const double maxSystemTextScaleFactor = 1.2;
const double _textScaleReferenceSize = 14.0;

/// Applies the system text-scale cap before the user's in-app UI multiplier.
///
/// The default multiplier preserves Flutter's non-linear system scaler. A
/// custom multiplier uses a linear approximation and remains inside the
/// app-supported range.
TextScaler cappedAppTextScaler({
  required TextScaler systemTextScaler,
  required double userScale,
  required double minimumEffectiveScale,
  required double maximumEffectiveScale,
}) {
  final TextScaler cappedSystemScaler = systemTextScaler.clamp(
    maxScaleFactor: maxSystemTextScaleFactor,
  );
  if (userScale == 1.0) {
    return cappedSystemScaler;
  }

  final double systemScaleFactor =
      cappedSystemScaler.scale(_textScaleReferenceSize) /
      _textScaleReferenceSize;
  final double effectiveScaleFactor = (systemScaleFactor * userScale)
      .clamp(minimumEffectiveScale, maximumEffectiveScale)
      .toDouble();
  return TextScaler.linear(effectiveScaleFactor);
}
