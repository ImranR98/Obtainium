import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppSmoothRoundedSurface extends StatelessWidget {
  const AppSmoothRoundedSurface({
    super.key,
    required this.child,
    required this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1,
    this.borderRadius = 8,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.tooltip,
  });

  final Widget child;
  final Color backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(borderRadius);
    Widget current = CustomPaint(
      painter: _SmoothRoundedSurfacePainter(
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        borderWidth: borderWidth,
        borderRadius: borderRadius,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    current = ClipRRect(
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: current,
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      current = Tooltip(message: tooltip!, child: current);
    }
    return current;
  }
}

class _SmoothRoundedSurfacePainter extends CustomPainter {
  const _SmoothRoundedSurfacePainter({
    required this.backgroundColor,
    required this.borderColor,
    required this.borderWidth,
    required this.borderRadius,
  });

  final Color backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final double effectiveRadius = math.min(
      borderRadius,
      size.shortestSide / 2,
    );
    final Radius radius = Radius.circular(effectiveRadius);
    final RRect background = RRect.fromRectAndRadius(
      Offset.zero & size,
      radius,
    );
    final Paint fillPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = backgroundColor;
    canvas.drawRRect(background, fillPaint);

    final Color? strokeColor = borderColor;
    if (strokeColor == null || borderWidth <= 0) {
      return;
    }
    final double inset = borderWidth / 2;
    final RRect border = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset,
        inset,
        size.width - borderWidth,
        size.height - borderWidth,
      ),
      Radius.circular(math.max(0, effectiveRadius - inset)),
    );
    final Paint borderPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..color = strokeColor;
    canvas.drawRRect(border, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SmoothRoundedSurfacePainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.borderRadius != borderRadius;
  }
}
