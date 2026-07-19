import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';

// Re-export the size enum so callers can pick a thickness (s = 4px track,
// m = 8px) without importing the underlying package directly.
export 'package:progress_indicator_m3e/progress_indicator_m3e.dart'
    show LinearProgressM3ESize;

/// A linear progress bar with a wavy pattern. Wraps
/// [LinearProgressIndicatorM3E] and adds phase animation
/// and smooth value transitions.
class LinearRipplingWavyProgressIndicator extends StatefulWidget {
  /// Shared default for [dragDuration]; also used when dismissing refresh UI.
  static const defaultDragDuration = Duration(milliseconds: 500);

  final double? value;

  /// Track thickness. Defaults to the small M3E size (4px track) app-wide;
  /// the package's medium (8px) reads as too thick for our lists.
  final LinearProgressM3ESize size;
  final Color? activeColor;
  final Color? trackColor;
  final double inset;

  /// Wave animation speed in cycles per second.
  final double waveSpeed;

  /// Progress below this value renders flat instead of wavy.
  final double flatBelow;

  /// Smooth transition duration when [value] increases.
  final Duration dragDuration;

  const LinearRipplingWavyProgressIndicator({
    super.key,
    this.value,
    this.size = LinearProgressM3ESize.s,
    this.activeColor,
    this.trackColor,
    this.inset = 10.0,
    this.waveSpeed = 1.0,
    this.flatBelow = 0.01,
    this.dragDuration = defaultDragDuration,
  });

  @override
  State<LinearRipplingWavyProgressIndicator> createState() =>
      _LinearRipplingWavyProgressState();
}

class _LinearRipplingWavyProgressState
    extends State<LinearRipplingWavyProgressIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _phaseController;
  late final AnimationController _valueController;
  late final Listenable _mergedListeners;

  Duration _getDuration(double cyclesPerSecond) {
    return Duration(
      milliseconds: (1000 / cyclesPerSecond.clamp(0.001, double.infinity))
          .round(),
    );
  }

  @override
  void initState() {
    super.initState();
    _phaseController = AnimationController(
      vsync: this,
      duration: _getDuration(widget.waveSpeed),
      lowerBound: 1e-10,
      upperBound: 2 * math.pi,
    );
    _valueController = AnimationController(
      vsync: this,
      duration: widget.dragDuration,
      value: widget.value,
    );
    _mergedListeners = Listenable.merge([_phaseController, _valueController]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updatePhaseAnimating();
  }

  @override
  void didUpdateWidget(
    covariant LinearRipplingWavyProgressIndicator oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.waveSpeed != widget.waveSpeed) {
      _phaseController.duration = _getDuration(widget.waveSpeed);
    }
    if (oldWidget.dragDuration != widget.dragDuration) {
      _valueController.duration = widget.dragDuration;
    }

    // Only animate when the value increases else snap
    if (oldWidget.value != widget.value) {
      if (widget.value == null ||
          widget.value! <= _valueController.value ||
          MediaQuery.disableAnimationsOf(context)) {
        _valueController.value = widget.value ?? _valueController.lowerBound;
      } else {
        _valueController.animateTo(
          widget.value!,
          duration: widget.dragDuration,
          curve: Curves.easeOutCubic,
        );
      }
    }
    _updatePhaseAnimating();
  }

  bool get _shouldShowWavyShape {
    if (MediaQuery.disableAnimationsOf(context)) return false;
    if (widget.value == null) return true;
    return widget.value! >= widget.flatBelow;
  }

  void _updatePhaseAnimating() {
    if (_shouldShowWavyShape) {
      if (!_phaseController.isAnimating) _phaseController.repeat();
    } else {
      if (_phaseController.isAnimating) _phaseController.stop();
    }
  }

  @override
  void dispose() {
    _phaseController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _mergedListeners,
      builder: (context, child) {
        final displayedValue = widget.value == null
            ? null
            : _valueController.value;
        return LinearProgressIndicatorM3E(
          value: displayedValue,
          shape: _shouldShowWavyShape
              ? ProgressM3EShape.wavy
              : ProgressM3EShape.flat,
          size: widget.size,
          activeColor: widget.activeColor,
          trackColor: widget.trackColor,
          phase: _phaseController.value,
          inset: widget.inset,
        );
      },
    );
  }
}
