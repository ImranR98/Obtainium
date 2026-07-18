import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:obtainium/components/app_smooth_surface.dart';

enum CategoryActionChipState {
  selected,
  partial,
  unselected,
  checked,
  plain,
  muted,
  add,
  remove,
}

class CategoryActionChipGroup extends StatelessWidget {
  const CategoryActionChipGroup({
    super.key,
    required this.children,
    this.alignment = WrapAlignment.start,
    this.crossAxisAlignment = WrapCrossAlignment.start,
  });

  final List<Widget> children;
  final WrapAlignment alignment;
  final WrapCrossAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: alignment,
      crossAxisAlignment: crossAxisAlignment,
      children: children,
    );
  }
}

class CategoryActionChip extends StatelessWidget {
  const CategoryActionChip({
    super.key,
    required this.label,
    required this.color,
    required this.state,
    this.onPressed,
    this.outerPadding = const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
  });

  final String label;
  final Color color;
  final CategoryActionChipState state;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry outerPadding;

  // computeLuminance() gamma-decodes all three channels — non-trivial, and these
  // chips render in groups that rebuild on every keystroke in the bulk category
  // editor. The light/dark decision depends only on the colour, so memoize it
  // (Color overrides ==/hashCode, so it's a stable map key).
  static final Map<Color, bool> _colorIsLightCache = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorIsLight = _colorIsLightCache[color] ??=
        color.computeLuminance() > 0.35;
    final onColor = colorIsLight ? Colors.black87 : Colors.white;
    final mutedContainerColor = Color.alphaBlend(
      color.withValues(alpha: 0.10),
      theme.colorScheme.surfaceContainerHighest,
    );
    final mutedForegroundColor = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: 0.58,
    );

    Widget? avatar;
    late final Color containerColor;
    late final Color foregroundColor;
    late final TextDecoration decoration;
    late final FontWeight fontWeight;
    late final BorderSide borderSide;

    switch (state) {
      case CategoryActionChipState.selected:
        containerColor = color;
        foregroundColor = onColor;
        decoration = TextDecoration.none;
        fontWeight = FontWeight.w600;
        borderSide = BorderSide.none;
        avatar = Icon(
          Icons.radio_button_checked,
          size: 18,
          color: foregroundColor,
        );
      case CategoryActionChipState.partial:
        containerColor = color;
        foregroundColor = onColor;
        decoration = TextDecoration.none;
        fontWeight = FontWeight.w500;
        borderSide = BorderSide.none;
        avatar = _PartialRadioIcon(color: foregroundColor);
      case CategoryActionChipState.unselected:
        containerColor = mutedContainerColor;
        foregroundColor = mutedForegroundColor;
        decoration = TextDecoration.none;
        fontWeight = FontWeight.w500;
        borderSide = BorderSide.none;
        avatar = Icon(
          Icons.radio_button_unchecked,
          size: 18,
          color: foregroundColor,
        );
      case CategoryActionChipState.checked:
        containerColor = color;
        foregroundColor = onColor;
        decoration = TextDecoration.none;
        fontWeight = FontWeight.w600;
        borderSide = BorderSide.none;
        avatar = Icon(Icons.check, size: 18, color: foregroundColor);
      case CategoryActionChipState.plain:
        containerColor = color;
        foregroundColor = onColor.withValues(alpha: 0.78);
        decoration = TextDecoration.none;
        fontWeight = FontWeight.w500;
        borderSide = BorderSide.none;
        avatar = null;
      case CategoryActionChipState.muted:
        containerColor = mutedContainerColor;
        foregroundColor = mutedForegroundColor;
        decoration = TextDecoration.none;
        fontWeight = FontWeight.w500;
        borderSide = BorderSide.none;
        avatar = null;
      case CategoryActionChipState.add:
        containerColor = color;
        foregroundColor = onColor;
        decoration = TextDecoration.none;
        fontWeight = FontWeight.w600;
        borderSide = BorderSide.none;
        avatar = Icon(Icons.add, size: 18, color: foregroundColor);
      case CategoryActionChipState.remove:
        containerColor = theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.3,
        );
        foregroundColor = theme.colorScheme.onSurface.withValues(alpha: 0.55);
        decoration = TextDecoration.lineThrough;
        fontWeight = FontWeight.w500;
        borderSide = BorderSide(color: color.withValues(alpha: 0.55));
        avatar = Icon(Icons.close, size: 18, color: foregroundColor);
    }

    return Padding(
      padding: outerPadding,
      child: AppSmoothRoundedSurface(
        backgroundColor: containerColor,
        borderColor: borderSide.style == BorderStyle.none
            ? null
            : borderSide.color,
        borderWidth: borderSide.width,
        borderRadius: 999,
        padding: EdgeInsetsDirectional.fromSTEB(
          avatar == null ? 12 : 9,
          6,
          12,
          6,
        ),
        onTap: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (avatar != null) ...[avatar, const SizedBox(width: 6)],
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: foregroundColor,
                decoration: decoration,
                fontWeight: fontWeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartialRadioIcon extends StatelessWidget {
  const _PartialRadioIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 18,
      child: CustomPaint(painter: _PartialRadioPainter(color)),
    );
  }
}

class _PartialRadioPainter extends CustomPainter {
  const _PartialRadioPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outlinePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 7, outlinePaint);

    const innerRadius = 4.75;
    final innerBounds = Rect.fromCircle(center: center, radius: innerRadius);
    final halfDot = Path()
      ..moveTo(center.dx, center.dy - innerRadius)
      ..arcTo(innerBounds, -math.pi / 2, -math.pi, false)
      ..lineTo(center.dx, center.dy - innerRadius)
      ..close();

    canvas.drawPath(halfDot, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _PartialRadioPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
