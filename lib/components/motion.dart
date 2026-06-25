import 'package:flutter/material.dart';

/// Material 3 Expressive motion tokens used across the app: spring-based
/// "spatial" motion for containers and emphasized easing/durations for the
/// rest. Centralizing these keeps motion consistent and tunable.
abstract final class ExpressiveMotion {
  /// Spatial spring with a gentle bounce — for containers and large
  /// expand/collapse / shared-element transitions.
  static final SpringDescription spatialSpring =
      SpringDescription.withDurationAndBounce(
        duration: Durations.long2,
        bounce: 0.18,
      );

  /// Snappier, lower-bounce spring for smaller effects.
  static final SpringDescription effectSpring =
      SpringDescription.withDurationAndBounce(
        duration: Durations.medium2,
        bounce: 0.08,
      );

  // Emphasized easing for non-spring tweens.
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve emphasizedDecelerate = Easing.emphasizedDecelerate;
  static const Curve emphasizedAccelerate = Easing.emphasizedAccelerate;
  static const Curve standard = Easing.standard;

  static const Duration short = Durations.short4; // 200ms
  static const Duration medium = Durations.medium2; // 300ms
  static const Duration long = Durations.long2; // 500ms
}
