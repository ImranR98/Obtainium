import 'package:flutter/material.dart';

/// Expressive empty-state scaffold: a code-drawn illustration, a title, an
/// optional supporting line, and an optional call-to-action.
///
/// All artwork is painted from the active [ColorScheme] (see the illustrations
/// below) — there are no image assets, so dark mode and dynamic color are
/// correct by construction. This mirrors the approach used by the sibling
/// Remember / FilePipe apps' `ThemeColored…Illustration` empty states.
///
/// The widget sizes to its content and centres horizontally; callers decide how
/// to position it in the viewport (the apps list, for example, wraps it in a
/// sliver that lands it at the optical centre).
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.illustration,
    required this.title,
    this.subtitle,
    this.action,
  });

  final Widget illustration;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? subtitle = this.subtitle;
    final Widget? action = this.action;

    final Widget column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        illustration,
        const SizedBox(height: 24),
        Text(
          title,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (action != null) ...[const SizedBox(height: 24), action],
      ],
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Semantics(
          container: true,
          child: _EmptyStateEntrance(child: column),
        ),
      ),
    );
  }
}

/// A gentle fade + scale-up as the empty state appears, using the app's
/// established emphasized curve. Honours the platform "remove animations"
/// accessibility setting, in which case the child is shown immediately.
class _EmptyStateEntrance extends StatelessWidget {
  const _EmptyStateEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubicEmphasized,
      child: child,
      builder: (context, t, child) {
        final double clamped = t.clamp(0.0, 1.0);
        return Opacity(
          opacity: clamped,
          child: Transform.scale(scale: 0.85 + 0.15 * clamped, child: child),
        );
      },
    );
  }
}

/// Empty apps library: a rounded "app tile" carrying a download glyph, with two
/// soft expressive backdrops and a small sparkle. Reads as "get / track apps".
class AppLibraryEmptyIllustration extends StatelessWidget {
  const AppLibraryEmptyIllustration({super.key, this.size = 160});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _LibraryEmptyPainter(Theme.of(context).colorScheme),
      ),
    );
  }
}

/// Empty filter / search result: a small list card behind a magnifier, echoing
/// the "nothing matched" empty state from the sibling apps.
class AppFilterEmptyIllustration extends StatelessWidget {
  const AppFilterEmptyIllustration({super.key, this.size = 148});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _FilterEmptyPainter(Theme.of(context).colorScheme),
      ),
    );
  }
}

/// Empty on-demand-only list: the same tile stack as the library, but the
/// front tile carries an archive glyph (and no "add" badge) — the on-demand
/// list is a stash you check on your own schedule, not a place you add to here.
class AppArchiveEmptyIllustration extends StatelessWidget {
  const AppArchiveEmptyIllustration({super.key, this.size = 160});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ArchiveEmptyPainter(Theme.of(context).colorScheme),
      ),
    );
  }
}

// ── Painters ─────────────────────────────────────────────────────────────────
//
// Both paint against a fixed 220×220 artboard and scale to the canvas, so the
// coordinates below read as absolute design units. Every colour comes from the
// [ColorScheme]; nothing is hard-coded.

const double _artboard = 220;

/// Draws a 4-pointed sparkle (concave-sided diamond) centred at [c] with arm
/// length [r].
void _drawSparkle(Canvas canvas, Offset c, double r, Paint paint) {
  final double waist = r * 0.32;
  final Path path = Path()
    ..moveTo(c.dx, c.dy - r)
    ..quadraticBezierTo(c.dx + waist, c.dy - waist, c.dx + r, c.dy)
    ..quadraticBezierTo(c.dx + waist, c.dy + waist, c.dx, c.dy + r)
    ..quadraticBezierTo(c.dx - waist, c.dy + waist, c.dx - r, c.dy)
    ..quadraticBezierTo(c.dx - waist, c.dy - waist, c.dx, c.dy - r)
    ..close();
  canvas.drawPath(path, paint);
}

class _LibraryEmptyPainter extends CustomPainter {
  _LibraryEmptyPainter(this.scheme);

  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / _artboard;
    double u(double v) => v * s;
    Offset p(double x, double y) => Offset(x * s, y * s);
    RRect box(double x, double y, double w, double h, double r) =>
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * s, y * s, w * s, h * s),
          Radius.circular(r * s),
        );

    final Paint fill = Paint()..style = PaintingStyle.fill;

    // Soft expressive backdrops framing the tile stack.
    fill.color = scheme.tertiaryContainer.withValues(alpha: 0.38);
    canvas.drawRRect(box(20, 40, 78, 78, 28), fill);
    fill.color = scheme.primaryContainer.withValues(alpha: 0.42);
    canvas.drawRRect(box(138, 118, 66, 66, 24), fill);

    // Back tile — offset up/right to give the stack depth.
    fill.color = scheme.scrim.withValues(alpha: 0.08);
    canvas.drawRRect(box(96, 56, 90, 90, 26), fill);
    fill.color = scheme.secondaryContainer;
    canvas.drawRRect(box(92, 52, 90, 90, 26), fill);

    // Front tile — the "app" the download glyph sits on.
    fill.color = scheme.scrim.withValues(alpha: 0.14);
    canvas.drawRRect(box(50, 84, 104, 104, 30), fill);
    fill.color = scheme.primaryContainer;
    canvas.drawRRect(box(46, 80, 104, 104, 30), fill);

    // Download glyph (shaft + chevron head + tray), centred on the front tile.
    final Paint glyph = Paint()
      ..color = scheme.onPrimaryContainer
      ..style = PaintingStyle.stroke
      ..strokeWidth = u(9)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(p(98, 104), p(98, 146), glyph);
    canvas.drawPath(
      Path()
        ..moveTo(u(82), u(130))
        ..lineTo(u(98), u(150))
        ..lineTo(u(114), u(130)),
      glyph,
    );
    canvas.drawLine(p(78, 162), p(118, 162), glyph);

    // "+" badge nested in the front tile's top-right corner — reads as "add".
    final Offset badge = p(150, 88);
    fill.color = scheme.scrim.withValues(alpha: 0.16);
    canvas.drawCircle(badge.translate(u(1.5), u(2.5)), u(19), fill);
    fill.color = scheme.primary;
    canvas.drawCircle(badge, u(19), fill);
    final Paint plus = Paint()
      ..color = scheme.onPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = u(5)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(p(141, 88), p(159, 88), plus);
    canvas.drawLine(p(150, 79), p(150, 97), plus);

    // Sparkles for a little life.
    _drawSparkle(canvas, p(182, 70), u(8), fill..color = scheme.tertiary);
    _drawSparkle(
      canvas,
      p(60, 66),
      u(5),
      fill..color = scheme.tertiary.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_LibraryEmptyPainter oldDelegate) =>
      oldDelegate.scheme != scheme;
}

class _ArchiveEmptyPainter extends CustomPainter {
  _ArchiveEmptyPainter(this.scheme);

  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / _artboard;
    double u(double v) => v * s;
    Offset p(double x, double y) => Offset(x * s, y * s);
    RRect box(double x, double y, double w, double h, double r) =>
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * s, y * s, w * s, h * s),
          Radius.circular(r * s),
        );

    final Paint fill = Paint()..style = PaintingStyle.fill;

    // Same borderless tile stack as the library illustration.
    fill.color = scheme.tertiaryContainer.withValues(alpha: 0.38);
    canvas.drawRRect(box(20, 40, 78, 78, 28), fill);
    fill.color = scheme.primaryContainer.withValues(alpha: 0.42);
    canvas.drawRRect(box(138, 118, 66, 66, 24), fill);

    fill.color = scheme.scrim.withValues(alpha: 0.08);
    canvas.drawRRect(box(96, 56, 90, 90, 26), fill);
    fill.color = scheme.secondaryContainer;
    canvas.drawRRect(box(92, 52, 90, 90, 26), fill);

    fill.color = scheme.scrim.withValues(alpha: 0.14);
    canvas.drawRRect(box(50, 84, 104, 104, 30), fill);
    fill.color = scheme.primaryContainer;
    canvas.drawRRect(box(46, 80, 104, 104, 30), fill);

    // Archive glyph: lid bar + box body + a carved handle slot.
    fill.color = scheme.onPrimaryContainer;
    canvas.drawRRect(box(68, 104, 60, 16, 6), fill); // lid
    canvas.drawRRect(box(74, 122, 48, 42, 8), fill); // body
    final Paint slot = Paint()
      ..color = scheme.primaryContainer
      ..style = PaintingStyle.stroke
      ..strokeWidth = u(7)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(p(86, 141), p(110, 141), slot);

    // Sparkles for a little life.
    _drawSparkle(canvas, p(182, 70), u(8), fill..color = scheme.tertiary);
    _drawSparkle(
      canvas,
      p(60, 66),
      u(5),
      fill..color = scheme.tertiary.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_ArchiveEmptyPainter oldDelegate) =>
      oldDelegate.scheme != scheme;
}

class _FilterEmptyPainter extends CustomPainter {
  _FilterEmptyPainter(this.scheme);

  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / _artboard;
    double u(double v) => v * s;
    Offset p(double x, double y) => Offset(x * s, y * s);
    RRect box(double x, double y, double w, double h, double r) =>
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * s, y * s, w * s, h * s),
          Radius.circular(r * s),
        );

    final Paint fill = Paint()..style = PaintingStyle.fill;
    final Paint stroke = Paint()..style = PaintingStyle.stroke;
    final double outlineW = u(1.4);

    // Soft expressive backdrops.
    fill.color = scheme.tertiaryContainer.withValues(alpha: 0.56);
    canvas.drawRRect(box(14, 16, 56, 56, 22), fill);
    fill.color = scheme.primaryContainer.withValues(alpha: 0.56);
    canvas.drawRRect(box(150, 150, 48, 48, 18), fill);

    // List card: shadow, fill, outline.
    fill.color = scheme.scrim.withValues(alpha: 0.11);
    canvas.drawRRect(box(45, 47, 120, 120, 18), fill);
    fill.color = scheme.surfaceContainerHigh;
    canvas.drawRRect(box(40, 42, 120, 120, 18), fill);
    stroke
      ..color = scheme.outline.withValues(alpha: 0.55)
      ..strokeWidth = outlineW;
    canvas.drawRRect(box(40, 42, 120, 120, 18), stroke);

    // Three list rows.
    fill.color = scheme.primaryContainer;
    canvas.drawRRect(box(58, 62, 62, 18, 9), fill);
    fill.color = scheme.tertiaryContainer;
    canvas.drawRRect(box(58, 91, 80, 18, 9), fill);
    fill.color = scheme.secondaryContainer;
    canvas.drawRRect(box(58, 120, 52, 18, 9), fill);

    // Row accent dots.
    fill.color = scheme.onPrimaryContainer.withValues(alpha: 0.72);
    canvas.drawCircle(p(75, 71), u(4), fill);
    fill.color = scheme.onTertiaryContainer.withValues(alpha: 0.68);
    canvas.drawCircle(p(122, 100), u(4), fill);
    fill.color = scheme.onSurfaceVariant.withValues(alpha: 0.54);
    canvas.drawCircle(p(87, 129), u(4), fill);

    // Magnifier: disc for contrast, ring, then handle.
    fill.color = scheme.surface.withValues(alpha: 0.78);
    canvas.drawCircle(p(131, 129), u(33), fill);
    stroke
      ..color = scheme.onSurface.withValues(alpha: 0.86)
      ..strokeWidth = u(4)
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(p(131, 129), u(34), stroke);
    canvas.drawLine(p(154, 153), p(179, 178), stroke);

    // A faint bar across the lens: "nothing here".
    stroke
      ..color = scheme.onSurfaceVariant.withValues(alpha: 0.28)
      ..strokeWidth = outlineW;
    canvas.drawLine(p(116, 129), p(146, 129), stroke);
  }

  @override
  bool shouldRepaint(_FilterEmptyPainter oldDelegate) =>
      oldDelegate.scheme != scheme;
}
