import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:obtainium/theme.dart';
import 'package:obtainium/providers/settings_provider.dart';

/// Material 3 Expressive switch.
///
/// Spec: 52×32 track, handle 16 (off) / 24 (on) / 28 (pressed),
/// 40dp state layer, 48dp target.
///
/// Per contributor note: handle uses [ColorScheme.onPrimary] in all
/// enabled+selected states to avoid contrast issues with expressive
/// color schemes where primaryContainer ≈ primary.
class M3ESwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const M3ESwitch({super.key, required this.value, required this.onChanged});

  @override
  State<M3ESwitch> createState() => _M3ESwitchState();
}

class _M3ESwitchState extends State<M3ESwitch>
    with SingleTickerProviderStateMixin {
  static const double _targetSize = 48;

  late final AnimationController _controller;
  bool _pressed = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: ExpressiveMotion.medium,
      value: widget.value ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant M3ESwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.animateTo(
        widget.value ? 1.0 : 0.0,
        curve: ExpressiveMotion.emphasized,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTV = context.read<SettingsProvider>().isTV;
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      label: '',
      toggled: widget.value,
      enabled: widget.onChanged != null,
      excludeSemantics: true,
      onTap: widget.onChanged == null
          ? null
          : () => widget.onChanged!(!widget.value),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            highlightColor: Colors.transparent,
            splashColor: cs.primary.withValues(alpha: 0.12),
            onTap: widget.onChanged == null
                ? null
                : () {
                    context.read<SettingsProvider>().selectionClick();
                    widget.onChanged!(!widget.value);
                  },
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _M3ESwitchPainter(
                  controller: _controller,
                  pressed: _pressed,
                  hovered: _hovered,
                  isTV: isTV,
                  colorScheme: cs,
                ),
                size: const Size(_targetSize, _targetSize),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _M3ESwitchPainter extends CustomPainter {
  final AnimationController controller;
  final bool pressed;
  final bool hovered;
  final bool isTV;
  final ColorScheme colorScheme;

  // Cached paint objects — mutated in place, never re-allocated.
  final _trackPaint = Paint();
  final _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final _stateLayerPaint = Paint();
  final _handlePaint = Paint();
  final _xPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;
  final _checkPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;

  // Cached paths — mutated in place.
  final _xPath = Path();
  final _checkPath = Path();

  _M3ESwitchPainter({
    required this.controller,
    required this.pressed,
    required this.hovered,
    required this.isTV,
    required this.colorScheme,
  }) : super(repaint: controller);

  double get t =>
      ExpressiveMotion.emphasized.transform(controller.value);

  @override
  void paint(Canvas canvas, Size size) {
    final t = this.t;

    const trackW = 52.0;
    const trackH = 32.0;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        (size.width - trackW) / 2,
        (size.height - trackH) / 2,
        trackW,
        trackH,
      ),
      const Radius.circular(trackH / 2),
    );

    // Track
    _trackPaint.color = Color.lerp(
      colorScheme.surfaceContainerHighest,
      colorScheme.primary,
      t,
    )!;
    canvas.drawRRect(trackRect, _trackPaint);

    if (t < 0.5) {
      _borderPaint.color = colorScheme.outline;
      canvas.drawRRect(trackRect.deflate(2), _borderPaint);
    }

    // Handle center: x goes from 16 to 36 within the track
    final handleCenter = Offset(
      (size.width - trackW) / 2 + 16 + t * 20,
      size.height / 2,
    );

    // State layer
    if (hovered || pressed || isTV) {
      _stateLayerPaint.color = colorScheme.primary.withValues(
        alpha: pressed ? 0.12 : 0.08,
      );
      canvas.drawCircle(handleCenter, 20, _stateLayerPaint);
    }

    // Handle
    final handleR = (pressed ? 28.0 : (t > 0.5 ? 24.0 : 16.0)) / 2;
    _handlePaint.color =
        t > 0.5 ? colorScheme.onPrimary : colorScheme.outline;
    canvas.drawCircle(handleCenter, handleR, _handlePaint);

    // Handle icon: X when off, check when on — crossfades with t
    if (t < 1.0) {
      final xOpacity = 1.0 - t;
      if (xOpacity > 0.01) {
        _xPath
          ..reset()
          ..moveTo(handleCenter.dx - 4, handleCenter.dy - 4)
          ..lineTo(handleCenter.dx + 4, handleCenter.dy + 4)
          ..moveTo(handleCenter.dx + 4, handleCenter.dy - 4)
          ..lineTo(handleCenter.dx - 4, handleCenter.dy + 4);
        _xPaint.color = colorScheme.onSurfaceVariant
            .withValues(alpha: xOpacity);
        canvas.drawPath(_xPath, _xPaint);
      }
    }

    if (t > 0.0) {
      final checkOpacity = t;
      if (checkOpacity > 0.01) {
        _checkPath
          ..reset()
          ..moveTo(handleCenter.dx - 5, handleCenter.dy)
          ..lineTo(handleCenter.dx - 1, handleCenter.dy + 4)
          ..lineTo(handleCenter.dx + 5, handleCenter.dy - 4);
        _checkPaint.color = colorScheme.primary
            .withValues(alpha: checkOpacity);
        canvas.drawPath(_checkPath, _checkPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _M3ESwitchPainter old) =>
      old.pressed != pressed ||
      old.hovered != hovered ||
      old.isTV != isTV ||
      old.colorScheme != colorScheme;
}
