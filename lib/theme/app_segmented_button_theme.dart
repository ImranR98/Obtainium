import 'package:flutter/material.dart';

class AppSegmentedButton<T> extends StatelessWidget {
  const AppSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.multiSelectionEnabled = false,
    this.emptySelectionAllowed = false,
    this.style,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final bool multiSelectionEnabled;
  final bool emptySelectionAllowed;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Set<WidgetState> baseStates = <WidgetState>{};
    final EdgeInsetsGeometry segmentPadding =
        style?.padding?.resolve(baseStates) ??
        const EdgeInsets.symmetric(vertical: 8, horizontal: 10);
    final Color selectedFill = Color.lerp(
      scheme.primaryContainer,
      scheme.primary,
      0.18,
    )!;
    final Color containerFill = Color.alphaBlend(
      scheme.onSurface.withValues(
        alpha: scheme.brightness == Brightness.dark ? 0.06 : 0.045,
      ),
      scheme.surfaceContainerHighest,
    );
    final Color dividerFill = Color.alphaBlend(
      scheme.onSurface.withValues(
        alpha: scheme.brightness == Brightness.dark ? 0.18 : 0.12,
      ),
      containerFill,
    );
    final bool enabled = onSelectionChanged != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool expandSegments = constraints.hasBoundedWidth;
        return Material(
          color: containerFill,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: expandSegments
                  ? MainAxisSize.max
                  : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int index = 0; index < segments.length; index++) ...[
                  if (index > 0) Container(width: 2, color: dividerFill),
                  if (expandSegments)
                    Expanded(
                      child: _buildSegment(
                        index,
                        segmentPadding,
                        selectedFill,
                        enabled,
                      ),
                    )
                  else
                    _buildSegment(index, segmentPadding, selectedFill, enabled),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSegment(
    int index,
    EdgeInsetsGeometry segmentPadding,
    Color selectedFill,
    bool enabled,
  ) {
    return _AppSegment<T>(
      segment: segments[index],
      selected: selected.contains(segments[index].value),
      enabled: enabled && segments[index].enabled,
      padding: segmentPadding,
      selectedFill: selectedFill,
      onSelected: _onSegmentPressed,
    );
  }

  void _onSegmentPressed(T value) {
    if (onSelectionChanged == null) {
      return;
    }

    final Set<T> nextSelection = Set<T>.from(selected);
    if (multiSelectionEnabled) {
      if (nextSelection.contains(value)) {
        if (emptySelectionAllowed || nextSelection.length > 1) {
          nextSelection.remove(value);
        }
      } else {
        nextSelection.add(value);
      }
    } else if (nextSelection.contains(value)) {
      if (emptySelectionAllowed) {
        nextSelection.clear();
      }
    } else {
      nextSelection
        ..clear()
        ..add(value);
    }

    onSelectionChanged!(nextSelection);
  }
}

class _AppSegment<T> extends StatelessWidget {
  const _AppSegment({
    required this.segment,
    required this.selected,
    required this.enabled,
    required this.padding,
    required this.selectedFill,
    required this.onSelected,
  });

  final ButtonSegment<T> segment;
  final bool selected;
  final bool enabled;
  final EdgeInsetsGeometry padding;
  final Color selectedFill;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color foregroundColor = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
    final Color iconColor = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final Color resolvedForegroundColor = enabled
        ? foregroundColor
        : foregroundColor.withValues(alpha: 0.38);
    final Color resolvedIconColor = enabled
        ? iconColor
        : iconColor.withValues(alpha: 0.38);

    Widget current = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: enabled ? () => onSelected(segment.value) : null,
        child: Ink(
          color: selected ? selectedFill : Colors.transparent,
          child: Padding(
            padding: padding,
            child: IconTheme.merge(
              data: IconThemeData(size: 18, color: resolvedIconColor),
              child: DefaultTextStyle.merge(
                style: theme.textTheme.labelLarge?.copyWith(
                  color: resolvedForegroundColor,
                  fontWeight: FontWeight.w600,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (segment.icon != null) ...[
                      segment.icon!,
                      if (segment.label != null) const SizedBox(width: 8),
                    ],
                    if (segment.label != null) Flexible(child: segment.label!),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (segment.tooltip != null) {
      current = Tooltip(message: segment.tooltip!, child: current);
    }
    return current;
  }
}

class AppSegmentedButtonLabel extends StatelessWidget {
  const AppSegmentedButtonLabel(this.text, {super.key, this.fontSize});

  final String text;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: fontSize == null ? null : TextStyle(fontSize: fontSize),
    );
  }
}

SegmentedButtonThemeData appSegmentedButtonTheme(ColorScheme colorScheme) {
  final Color selectedFill = Color.lerp(
    colorScheme.primaryContainer,
    colorScheme.primary,
    0.18,
  )!;

  return SegmentedButtonThemeData(
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return null;
        }
        if (states.contains(WidgetState.selected)) {
          return selectedFill;
        }
        return null;
      }),
      foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return null;
        }
        if (states.contains(WidgetState.selected)) {
          return colorScheme.onPrimaryContainer;
        }
        return colorScheme.onSurface;
      }),
      iconColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return null;
        }
        if (states.contains(WidgetState.selected)) {
          return colorScheme.onPrimaryContainer;
        }
        return colorScheme.onSurfaceVariant;
      }),
      side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return null;
        }
        return BorderSide.none;
      }),
    ),
  );
}
