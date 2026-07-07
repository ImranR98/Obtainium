import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/theme.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:provider/provider.dart';

bool _isKnownTileType(Widget w) =>
    w is SettingsTile || w is SettingsToggleRow;

Widget _wrapChildWithRadius(Widget w, BorderRadius radius) {
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

List<Widget> shapeSettingsTiles(List<Widget> children) {
  final result = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    final w = children[i];
    if (!_isKnownTileType(w)) {
      result.add(w);
      continue;
    }
    final prevIsTile = i > 0 && _isKnownTileType(children[i - 1]);
    final nextIsTile =
        i < children.length - 1 && _isKnownTileType(children[i + 1]);
    result.add(
      _wrapChildWithRadius(
        w,
        positionalTileRadius(isFirst: !prevIsTile, isLast: !nextIsTile),
      ),
    );
  }
  return result;
}

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
    final effectiveRadius =
        borderRadius ?? BorderRadius.circular(connectedTileBigRadius);
    return Material(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: effectiveRadius,
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
    final ValueChanged<bool>? hapticOnChanged = onChanged == null
        ? null
        : (v) {
            context.read<SettingsProvider>().selectionClick();
            onChanged!(v);
          };
    final tileShape = borderRadius != null
        ? RoundedRectangleBorder(borderRadius: borderRadius!)
        : null;
    return SettingsTile(
      padding: EdgeInsets.zero,
      borderRadius: borderRadius,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        shape: tileShape,
        title: Text(label),
        subtitle: subtitle,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (helpWidgets.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.help_outline),
                tooltip: tr('about'),
                onPressed: () => showHelpDialog(
                  context,
                  title: label,
                  content: helpWidgets,
                ),
              ),
            Switch(value: value, onChanged: hapticOnChanged),
          ],
        ),
      ),
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
