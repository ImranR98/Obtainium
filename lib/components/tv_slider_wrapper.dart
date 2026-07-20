import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:provider/provider.dart';

class TVSliderWrapper extends StatefulWidget {
  const TVSliderWrapper({
    super.key,
    required this.child,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    this.onChangeEnd,
    this.enabled = true,
  });

  final Widget child;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final bool enabled;

  @override
  State<TVSliderWrapper> createState() => _TVSliderWrapperState();
}

class _TVSliderWrapperState extends State<TVSliderWrapper> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _adjustValue(double delta) {
    if (!widget.enabled) return;
    final int divs = widget.divisions ?? 20;
    final double step = (widget.max - widget.min) / divs;
    final double newValue = (widget.value + delta * step).clamp(
      widget.min,
      widget.max,
    );
    widget.onChanged(newValue);
    if (widget.onChangeEnd != null) {
      widget.onChangeEnd!(newValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTV = context.read<SettingsProvider>().isTV;
    if (!isTV) {
      return widget.child;
    }

    return Focus(
      focusNode: _focusNode,
      canRequestFocus: widget.enabled,
      skipTraversal: !widget.enabled,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _adjustValue(-1.0);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _adjustValue(1.0);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: _focusNode,
        builder: (context, _) {
          final hasFocus = _focusNode.hasFocus;
          final scheme = Theme.of(context).colorScheme;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: hasFocus
                ? BoxDecoration(
                    border: Border.all(color: scheme.primary, width: 2),
                    borderRadius: BorderRadius.circular(12),
                    color: scheme.primary.withValues(alpha: 0.08),
                  )
                : null,
            child: ExcludeFocus(excluding: true, child: widget.child),
          );
        },
      ),
    );
  }
}
