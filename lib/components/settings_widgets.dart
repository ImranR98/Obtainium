import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/ui_shapes.dart';

bool _isSettingsTile(Widget w) => w is SettingsTile || w is SettingsToggleRow;

Widget _withTileRadius(Widget w, BorderRadius radius) {
  if (w is SettingsTile) {
    return SettingsTile(
      key: w.key,
      padding: w.padding,
      borderRadius: radius,
      color: w.color,
      child: w.child,
    );
  }
  if (w is SettingsToggleRow) {
    return SettingsToggleRow(
      key: w.key,
      label: w.label,
      value: w.value,
      onChanged: w.onChanged,
      subtitle: w.subtitle,
      borderRadius: radius,
      helpWidgets: w.helpWidgets,
    );
  }
  return w;
}

/// Shapes consecutive runs of settings tiles so each run reads as a single
/// connected block: large outer corners on the first/last tile of a run and
/// small corners on the inner edges. Non-tile children (captions, dropdowns,
/// spacers) pass through untouched and break a run.
List<Widget> shapeSettingsTiles(List<Widget> children) {
  final result = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    final w = children[i];
    if (!_isSettingsTile(w)) {
      result.add(w);
      continue;
    }
    final prevIsTile = i > 0 && _isSettingsTile(children[i - 1]);
    final nextIsTile =
        i < children.length - 1 && _isSettingsTile(children[i + 1]);
    result.add(
      _withTileRadius(
        w,
        positionalTileRadius(isFirst: !prevIsTile, isLast: !nextIsTile),
      ),
    );
  }
  return result;
}

/// A single rounded, tonal surface that visually separates one settings
/// control from its neighbours — the Material 3 Expressive "split list" look.
class SettingsTile extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final Color? color;

  const SettingsTile({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
    this.borderRadius,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedSuperellipseBorder(
        borderRadius:
            borderRadius ?? BorderRadius.circular(connectedTileBigRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

class SettingsToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? subtitle;
  final BorderRadius? borderRadius;
  final List<Widget> helpWidgets;

  const SettingsToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.borderRadius,
    this.helpWidgets = const [],
  });

  @override
  Widget build(BuildContext context) {
    final Widget tileChild = helpWidgets.isEmpty
        ? SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(label),
            subtitle: subtitle,
            value: value,
            onChanged: onChanged,
          )
        : ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(label),
            subtitle: subtitle,
            onTap: onChanged == null ? null : () => onChanged!(!value),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.help_outline),
                  tooltip: tr('about'),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(label),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: helpWidgets,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text(tr('ok')),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
          );
    return SettingsTile(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      borderRadius: borderRadius,
      child: tileChild,
    );
  }
}

class SettingsSectionHeader extends StatelessWidget {
  final String title;

  const SettingsSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// A M3 Expressive settings section: a labelled header followed by its
/// controls laid out as connected, rounded tiles with small gaps.
class SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SettingsGroup({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 3,
      children: [
        SettingsSectionHeader(title: title),
        ...shapeSettingsTiles(children),
      ],
    );
  }
}
