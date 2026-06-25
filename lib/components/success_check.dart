import 'package:flutter/material.dart';

/// A spring‑animated success checkmark.  When built, it scales in with a
/// gentle bounce, holds for [displayDuration], then fades out.
///
/// The caller controls *when* it appears (usually via a `show` boolean that
/// briefly becomes true after a successful action).
class AnimatedSuccessCheck extends StatefulWidget {
  final Duration displayDuration;
  final VoidCallback? onDone;

  const AnimatedSuccessCheck({
    super.key,
    this.displayDuration = const Duration(seconds: 2),
    this.onDone,
  });

  @override
  State<AnimatedSuccessCheck> createState() => _AnimatedSuccessCheckState();
}

class _AnimatedSuccessCheckState extends State<AnimatedSuccessCheck>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const ElasticOutCurve(0.8),
      ),
    );
    _fade = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 1, curve: Curves.easeOut),
      ),
    );

    // Start the check‑in animation immediately; hide after the requested hold.
    _controller.forward().then((_) {
      Future.delayed(widget.displayDuration, () {
        if (mounted) _controller.reverse().then((_) => widget.onDone?.call());
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_rounded,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            size: 40,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
