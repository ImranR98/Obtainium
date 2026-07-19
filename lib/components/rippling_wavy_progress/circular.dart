import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:obtainium/components/rippling_wavy_progress/linear.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';

/// A circular progress indicator with a wavy arc that ripples
/// along the active portion rather than rotating the ring.
class CircularRipplingWavyProgressIndicator extends StatefulWidget {
  final double? value;
  final CircularProgressM3ESize size;
  final Color? activeColor;
  final Color? trackColor;

  /// Smooth transition duration when [value] increases.
  final Duration dragDuration;

  /// Wave animation speed in cycles per second.
  final double waveSpeed;

  /// Width of the painted stroke.
  final double strokeWidth;

  /// Arc-length gap between the edge of the track and active arcs.
  final double gapWidth;

  /// Radial amplitude of the wave squiggle.
  final double amplitude;

  /// Along‑arc wavelength in logical pixels.
  final double wavelength;

  const CircularRipplingWavyProgressIndicator({
    super.key,
    this.value,
    this.size = CircularProgressM3ESize.m,
    this.activeColor,
    this.trackColor,
    this.dragDuration = LinearRipplingWavyProgressIndicator.defaultDragDuration,
    this.waveSpeed = 1.0,
    // Thinner ring app-wide (was 4.0) to match the slimmer linear track.
    this.strokeWidth = 3.0,
    this.gapWidth = 1.0,
    this.amplitude = 1.0,
    this.wavelength = 15.0,
  });

  @override
  State<CircularRipplingWavyProgressIndicator> createState() =>
      _CircularRipplingWavyProgressState();
}

class _CircularRipplingWavyProgressState
    extends State<CircularRipplingWavyProgressIndicator>
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
    covariant CircularRipplingWavyProgressIndicator oldWidget,
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

  bool get _shouldAnimatePhase {
    if (MediaQuery.disableAnimationsOf(context)) return false;
    if (widget.value == null) return true;
    return widget.value! > 0;
  }

  void _updatePhaseAnimating() {
    if (_shouldAnimatePhase) {
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
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final active = widget.activeColor ?? cs.primary;
        final track =
            widget.trackColor ?? cs.onSurfaceVariant.withValues(alpha: 0.24);
        final value = widget.value == null ? null : _valueController.value;
        return RepaintBoundary(
          child: SizedBox(
            width: widget.size.diameterWavy,
            height: widget.size.diameterWavy,
            child: CustomPaint(
              painter: _CircularRipplingWavyPainter(
                value: value,
                active: active,
                track: track,
                phase: _phaseController.value,
                strokeWidth: widget.strokeWidth,
                amplitude: widget.amplitude,
                wavelength: widget.wavelength,
                gapWidth: widget.gapWidth,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CircularRipplingWavyPainter extends CustomPainter {
  _CircularRipplingWavyPainter({
    this.value,
    required this.active,
    required this.track,
    required this.phase,
    required this.strokeWidth,
    required this.amplitude,
    required this.wavelength,
    required this.gapWidth,
  });

  final double? value;
  final Color active;
  final Color track;
  final double phase;
  final double strokeWidth;
  final double amplitude;
  final double wavelength;
  final double gapWidth;

  bool get _isIndeterminate => value == null;
  bool get _isClosedLoop => value == null || value! >= 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;

    final circumference = 2 * math.pi * radius;
    final steps = (circumference / 2.5).round().clamp(60, 360);

    // Align the wavelength to the circumference so that the wave pattern is complete
    // and doesn't get cut off at the end of the arc.
    final waveCount = (circumference / wavelength).round().clamp(
      1,
      double.infinity,
    );
    final alignedWavelength = circumference / waveCount;

    const startAngle = -math.pi / 2;
    final sweep = _isIndeterminate
        ? 2 * math.pi
        : value!.clamp(0.0, 1.0) * 2 * math.pi;
    final endAngle = startAngle + sweep;

    final gapArcLen = sweep == 0 ? 0.0 : (gapWidth + strokeWidth);
    final gapAngle = gapArcLen / radius;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Draw the track arc with a gap at both ends of the active arc
    if (!_isIndeterminate && value! < 1.0) {
      final minGapAngle = strokeWidth / radius;
      final requiredForGaps = 2 * minGapAngle;
      final availableSpace = 2 * math.pi - sweep;
      if (availableSpace > requiredForGaps) {
        final minTrackAngle = 1 / radius;
        // So that the track isn't cut off prematurely when the value is reaches the end.
        final maxTrackFriendlyGap = (availableSpace - minTrackAngle) / 2;
        final currentGapAngle = math.min(gapAngle, maxTrackFriendlyGap);
        final trackSweep = availableSpace - 2 * currentGapAngle;
        if (trackSweep > 0) {
          canvas.drawArc(
            rect,
            endAngle + currentGapAngle,
            trackSweep,
            false,
            Paint()
              ..color = track
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }

    if (sweep <= 0) return;

    // Draw the wavy active arc

    final wavePaint = Paint()
      ..color = active
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round;

    if (!_isClosedLoop) {
      wavePaint.strokeCap = StrokeCap.round;
    }

    final path = Path();
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final angle = startAngle + sweep * t;
      final arcLen = radius * (angle - startAngle);
      final wave = math.sin(arcLen / alignedWavelength * 2 * math.pi + phase);

      double currentAmplitude = amplitude;

      // Taper the wave amplitude to 0 at the start & end of the arc
      // Only when not a closed loop, otherwise it'd look weird with
      // a dent at the top.
      if (!_isClosedLoop) {
        final taperLen = alignedWavelength / 2;

        if (arcLen < taperLen && arcLen >= 0) {
          final startTaperFactor = math.sin((arcLen / taperLen) * math.pi / 2);
          currentAmplitude *= startTaperFactor;
        }

        final arcToEnd = radius * (endAngle - angle);
        if (arcToEnd < taperLen && arcToEnd >= 0) {
          final endTaperFactor = math.sin((arcToEnd / taperLen) * math.pi / 2);
          currentAmplitude *= endTaperFactor;
        }
      }

      final r = radius + currentAmplitude * wave;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    if (_isClosedLoop) {
      path.close();
    }

    canvas.drawPath(path, wavePaint);
  }

  @override
  bool shouldRepaint(_CircularRipplingWavyPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.active != active ||
        oldDelegate.track != track ||
        oldDelegate.phase != phase ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.wavelength != wavelength ||
        oldDelegate.gapWidth != gapWidth;
  }
}
