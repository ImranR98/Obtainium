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
    this.boxShadow = const [],
    this.clipContent = false,
    this.onTap,
    this.tooltip,
  });

  final Widget child;
  final Color backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow> boxShadow;

  /// Clip children to the rounded shape. Only needed when a child paints to the
  /// edge (e.g. a full-bleed header stripe) and would otherwise poke past the
  /// corners. Left off by default: the painted fill below already defines a
  /// smooth corner, and a saveLayer per surface is wasteful for the common case
  /// (chips, plain cards) — which is also where clipping hurt, see [build].
  final bool clipContent;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(borderRadius);
    Widget interactive = Material(
      type: MaterialType.transparency,
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: radius),
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (clipContent) {
      // Deliberately antiAliasWithSaveLayer, NOT Clip.antiAlias: the latter
      // clips with MSAA coverage that visibly stair-steps on curved corners at
      // low DPR under Impeller (the jagged-corner bug). saveLayer compositing
      // keeps the clipped corner analytically anti-aliased.
      interactive = ClipRRect(
        borderRadius: radius,
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: interactive,
      );
    }
    // Fill + border are PAINTED with analytic anti-aliasing so the visible
    // corner is smooth. (Producing the corner via a plain ClipRRect instead —
    // as an earlier revision did — is exactly what made corners look jagged.)
    // The fill is painted BEHIND the child and the border ON TOP of it
    // (foregroundPainter), so a full-bleed child such as a header stripe does
    // not paint over the border — the border still frames the whole surface.
    final bool hasBorder =
        borderColor != null &&
        borderColor != Colors.transparent &&
        borderWidth > 0;
    Widget current = CustomPaint(
      painter: _SmoothRoundedFillPainter(
        backgroundColor: backgroundColor,
        borderRadius: borderRadius,
      ),
      foregroundPainter: hasBorder
          ? _SmoothRoundedBorderPainter(
              borderColor: borderColor!,
              borderWidth: borderWidth,
              borderRadius: borderRadius,
            )
          : null,
      child: interactive,
    );
    if (boxShadow.isNotEmpty) {
      current = DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: boxShadow),
        child: current,
      );
    }
    if (tooltip != null && tooltip!.isNotEmpty) {
      current = Tooltip(message: tooltip!, child: current);
    }
    return current;
  }
}

class _SmoothRoundedFillPainter extends CustomPainter {
  const _SmoothRoundedFillPainter({
    required this.backgroundColor,
    required this.borderRadius,
  });

  final Color backgroundColor;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final double effectiveRadius = math.min(
      borderRadius,
      size.shortestSide / 2,
    );
    final RRect background = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(effectiveRadius),
    );
    final Paint fillPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = backgroundColor;
    canvas.drawRRect(background, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _SmoothRoundedFillPainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.borderRadius != borderRadius;
  }
}

class _SmoothRoundedBorderPainter extends CustomPainter {
  const _SmoothRoundedBorderPainter({
    required this.borderColor,
    required this.borderWidth,
    required this.borderRadius,
  });

  final Color borderColor;
  final double borderWidth;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final double effectiveRadius = math.min(
      borderRadius,
      size.shortestSide / 2,
    );
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
      ..color = borderColor;
    canvas.drawRRect(border, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SmoothRoundedBorderPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.borderRadius != borderRadius;
  }
}
