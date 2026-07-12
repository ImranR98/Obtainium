import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/theme.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:provider/provider.dart';

class _TileClipper extends CustomClipper<Path> {
  final ShapeBorder shape;
  const _TileClipper(this.shape);

  @override
  Path getClip(Size size) => shape.getOuterPath(Offset.zero & size);

  @override
  bool shouldReclip(_TileClipper oldClipper) => oldClipper.shape != shape;
}

Future<void> showHelpDialog(
  BuildContext context, {
  required String title,
  required List<Widget> content,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: content,
      ),
      actions: [
        TextButton(
          autofocus: context.read<SettingsProvider>().isTV,
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(tr('ok')),
        ),
      ],
    ),
  );
}

ValueChanged<bool> hapticSwitchOnChanged(
  BuildContext context,
  ValueChanged<bool> onChanged,
) => (v) {
  context.read<SettingsProvider>().selectionClick();
  onChanged(v);
};

bool _isKnownTileType(Widget w) => w is SettingsTile || w is SettingsToggleRow;

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
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
    this.borderRadius,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius =
        borderRadius ?? BorderRadius.circular(connectedTileBigRadius);
    final shape = RoundedSuperellipseBorder(borderRadius: effectiveRadius);
    return ClipPath(
      clipper: _TileClipper(shape),
      child: Material(
        color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(padding: padding, child: child),
      ),
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
    final tileShape = borderRadius != null
        ? RoundedSuperellipseBorder(borderRadius: borderRadius!)
        : null;
    return SettingsTile(
      padding: EdgeInsets.zero,
      borderRadius: borderRadius,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
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
                onPressed: () =>
                    showHelpDialog(context, title: label, content: helpWidgets),
              ),
            Switch(
              value: value,
              onChanged: onChanged == null
                  ? null
                  : hapticSwitchOnChanged(context, onChanged!),
            ),
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
