// Material 3 Expressive animation duration tokens.

import 'package:flutter/material.dart';

/// Material 3 Expressive motion tokens used across the app. Centralizing the
/// emphasized easing curve and durations keeps animation timing consistent and
/// tunable.
abstract final class ExpressiveMotion {
  /// Emphasized easing for expand/collapse and other container motion.
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  static const Duration short = Durations.short4;
  static const Duration medium = Durations.medium2;
}
