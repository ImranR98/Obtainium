import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/theme.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

Future<void> copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(tr('copiedToClipboard'))));
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  Widget? content,
  String? confirmText,
  String? cancelText,
  bool autofocusConfirm = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelText ?? tr('no')),
        ),
        FilledButton(
          autofocus: autofocusConfirm,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmText ?? tr('yes')),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

void showMessage(dynamic e, BuildContext context, {bool isError = false}) {
  context.read<LogsProvider>().add(
    e.toString(),
    level: isError ? LogLevel.error : LogLevel.info,
  );
  if (e is String || (e is ObtainiumError && !e.unexpected)) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(e.toString())));
  } else {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          scrollable: true,
          title: Text(
            e is MultiAppMultiError
                ? tr(isError ? 'someErrors' : 'updates')
                : tr(isError ? 'unexpectedError' : 'unknown'),
          ),
          content: GestureDetector(
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: e.toString()));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(tr('copiedToClipboard'))));
            },
            child: Text(e.toString()),
          ),
          actions: [
            FilledButton.tonal(
              autofocus: context.read<SettingsProvider>().isTV,
              onPressed: () {
                Navigator.of(context).pop(null);
              },
              child: Text(tr('ok')),
            ),
          ],
        );
      },
    );
  }
}

void showError(dynamic e, BuildContext context) {
  showMessage(e, context, isError: true);
}

class AppIcon extends StatelessWidget {
  final Uint8List? bytes;
  final double size;
  final double radius;

  final double glyphSize;

  final bool dimmed;

  const AppIcon({
    super.key,
    required this.bytes,
    required this.size,
    this.radius = 12,
    this.glyphSize = 24,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheDim = (size * devicePixelRatio).round();
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: bytes != null
            ? Image.memory(
                bytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                excludeFromSemantics: true,
                cacheWidth: cacheDim,
                cacheHeight: cacheDim,
                opacity: dimmed ? const AlwaysStoppedAnimation(0.6) : null,
              )
            : ColoredBox(
                color: colorScheme.surfaceContainerHighest,
                child: Center(
                  child: Image(
                    image: const AssetImage('assets/graphics/icon_small.png'),
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.4),
                    colorBlendMode: BlendMode.modulate,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    width: glyphSize,
                    height: glyphSize,
                  ),
                ),
              ),
      ),
    );
  }
}

class HighlightableButton extends StatelessWidget {
  final bool highlight;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final Widget? icon;
  final Widget label;

  const HighlightableButton({
    super.key,
    required this.highlight,
    required this.onPressed,
    this.onLongPress,
    this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (highlight) {
      if (icon != null) {
        return FilledButton.icon(
          onPressed: onPressed,
          onLongPress: onLongPress,
          icon: icon!,
          label: label,
        );
      }
      return FilledButton(
        onPressed: onPressed,
        onLongPress: onLongPress,
        child: label,
      );
    }
    if (icon != null) {
      return TextButton.icon(
        onPressed: onPressed,
        onLongPress: onLongPress,
        icon: icon!,
        label: label,
      );
    }
    return TextButton(
      onPressed: onPressed,
      onLongPress: onLongPress,
      child: label,
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String? message;

  const EmptyState({super.key, required this.icon, this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: colorScheme.onSurfaceVariant,
              semanticLabel: message,
            ),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message!,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact "X" button used to cancel an in-progress download.
class DownloadCancelButton extends StatelessWidget {
  final VoidCallback onPressed;

  const DownloadCancelButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.close),
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      tooltip: tr('cancel'),
      onPressed: () {
        context.read<SettingsProvider>().lightImpact();
        onPressed();
      },
    );
  }
}

class ConnectedCard extends StatelessWidget {
  final Widget child;
  final bool isFirst;
  final bool isLast;
  final Color? color;
  final EdgeInsetsGeometry? padding;

  const ConnectedCard({
    super.key,
    required this.child,
    this.isFirst = true,
    this.isLast = true,
    this.color,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return CardTile(
      color: color,
      padding: padding ?? EdgeInsets.zero,
      borderRadius: positionalTileRadius(isFirst: isFirst, isLast: isLast),
      child: child,
    );
  }
}

class LinkText extends StatelessWidget {
  final String text;
  final String url;
  final TextStyle? style;

  const LinkText({
    super.key,
    required this.text,
    required this.url,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => unawaited(
          launchUrlString(url, mode: LaunchMode.externalApplication),
        ),
        child: Text(
          text,
          style: (style ?? const TextStyle()).copyWith(
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}

class ActionListTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool autoPop;
  final BorderRadius? borderRadius;

  const ActionListTile({
    super.key,
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
    this.autoPop = false,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: trailing,
      enabled: onTap != null,
      shape: borderRadius != null
          ? RoundedRectangleBorder(borderRadius: borderRadius!)
          : null,
      onTap: onTap == null
          ? null
          : () {
              if (autoPop) Navigator.of(context).pop();
              onTap?.call();
            },
    );
  }
}

class CustomAppBar extends StatelessWidget {
  const CustomAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      title: Text(title),
      actions: actions,
    );
  }
}

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

bool _isTile(Widget w) =>
    w is CardTile || w is ToggleTile || w is ConnectedCard;

Widget _wrapChildWithRadius(Widget w, BorderRadius radius) {
  if (w is CardTile) {
    return CardTile(
      key: w.key,
      padding: w.padding,
      borderRadius: radius,
      color: w.color,
      child: w.child,
    );
  }
  if (w is ToggleTile) {
    final r = radius;
    final isFirst = r.topLeft.x == connectedTileBigRadius;
    final isLast = r.bottomLeft.x == connectedTileBigRadius;
    return ConnectedCard(
      isFirst: isFirst,
      isLast: isLast,
      child: w,
    );
  }
  if (w is ConnectedCard) {
    final r = radius;
    final isFirst = r.topLeft.x == connectedTileBigRadius;
    final isLast = r.bottomLeft.x == connectedTileBigRadius;
    return ConnectedCard(
      isFirst: isFirst,
      isLast: isLast,
      color: w.color,
      padding: w.padding,
      child: w.child,
    );
  }
  return w;
}

List<Widget> shapeCardTiles(List<Widget> children) {
  final result = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    final w = children[i];
    if (!_isTile(w)) {
      result.add(w);
      continue;
    }
    final prevIsTile = i > 0 && _isTile(children[i - 1]);
    final nextIsTile =
        i < children.length - 1 && _isTile(children[i + 1]);
    result.add(
      _wrapChildWithRadius(
        w,
        positionalTileRadius(isFirst: !prevIsTile, isLast: !nextIsTile),
      ),
    );
  }
  return result;
}

class CardTile extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final Color? color;

  const CardTile({
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

class ToggleTile extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? subtitle;
  final List<Widget> helpWidgets;
  final bool noPadding;

  const ToggleTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.helpWidgets = const [],
    this.noPadding = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: noPadding
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 20),
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
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;

  const SectionHeader({super.key, required this.title});

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

class Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const Section({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 3,
      children: [
        SectionHeader(title: title),
        ...shapeCardTiles(children),
      ],
    );
  }
}
