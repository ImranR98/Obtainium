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
  static const double _trackWidth = 52;
  static const double _trackHeight = 32;
  static const double _handleOff = 16;
  static const double _handleOn = 24;
  static const double _handlePressed = 28;
  static const double _stateLayerSize = 40;
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

  double get _handleSize {
    final base = widget.value ? _handleOn : _handleOff;
    return _pressed ? _handlePressed : base;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTV = context.read<SettingsProvider>().isTV;

    return Semantics(
      container: true,
      label: '', // caller sets label via wrapping Semantics
      toggled: widget.value,
      enabled: widget.onChanged != null,
      excludeSemantics: true,
      onTap: widget.onChanged == null ? null : () => widget.onChanged!(!widget.value),
      child: GestureDetector(
        onTap: widget.onChanged == null
            ? null
            : () {
                context.read<SettingsProvider>().selectionClick();
                widget.onChanged!(!widget.value);
              },
        onSecondaryTapDown: (_) => setState(() => _pressed = true),
        onSecondaryTapUp: (_) => setState(() => _pressed = false),
        onSecondaryTapCancel: () => setState(() => _pressed = false),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: SizedBox(
            width: _targetSize,
            height: _targetSize,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                final handleSize = _handleSize;
                // Handle center X: 16 (off) → 36 (on) within 52dp track
                final handleCenterX = 16 + t * (36 - 16);

                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Track
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: _trackWidth,
                          height: _trackHeight,
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              cs.surfaceContainerHighest,
                              cs.primary,
                              t,
                            ),
                            borderRadius: BorderRadius.circular(_trackHeight / 2),
                            border: t < 0.5
                                ? Border.all(color: cs.outline, width: 2)
                                : null,
                          ),
                        ),
                      ),
                    ),
                    // State layer (hover/press/focus)
                    if (_hovered || _pressed || isTV)
                      Positioned(
                        left: handleCenterX - _stateLayerSize / 2,
                        top: _trackHeight / 2 - _stateLayerSize / 2,
                        child: Container(
                          width: _stateLayerSize,
                          height: _stateLayerSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cs.primary.withValues(
                              alpha: _pressed ? 0.12 : 0.08,
                            ),
                          ),
                        ),
                      ),
                    // Handle
                    Positioned(
                      left: handleCenterX - handleSize / 2,
                      top: _trackHeight / 2 - handleSize / 2,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        curve: Curves.easeOut,
                        width: handleSize,
                        height: handleSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: t > 0.5 ? cs.onPrimary : cs.outline,
                        ),
                        child: t > 0.5
                            ? Icon(
                                Icons.check,
                                size: 16,
                                color: cs.primary,
                              )
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  }
