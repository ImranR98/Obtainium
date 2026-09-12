import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/theme.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/core/logging/app_logger.dart';
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

Future<bool> showContinueCancelDialog(
  BuildContext context, {
  required String title,
  String? message,
}) async {
  final result = await showDialog<Map<String, dynamic>?>(
    context: context,
    builder: (ctx) => GeneratedFormModal(
      title: title,
      items: const [],
      initValid: true,
      message: message ?? '',
    ),
  );
  return result != null;
}

void showMessage(dynamic e, BuildContext context, {bool isError = false}) {
  if (isError) context.read<SettingsProvider>().heavyImpact();
  if (isError) {
    AppLogger.error(e, message: e.toString());
  } else {
    AppLogger.info(e.toString());
  }
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

/// Dropdown menu that is operable with a TV remote.
///
/// Material's [DropdownMenu] makes its field non-focusable on Android
/// (`requestFocusOnTap` defaults to false), which leaves remote users unable to
/// reach or open it. On TV this wrapper owns focus, opens the menu with the
/// select button, and draws a focus ring; the menu items are then navigable
/// with the D-pad as usual. On touch devices it renders the plain
/// [DropdownMenu].
class TvDropdownMenu<T> extends StatefulWidget {
  const TvDropdownMenu({
    super.key,
    required this.initialSelection,
    required this.dropdownMenuEntries,
    this.onSelected,
    this.label,
    this.expandedInsets,
    this.width,
    this.leadingIcon,
    this.menuHeight,
    this.enabled = true,
  });

  final T? initialSelection;
  final List<DropdownMenuEntry<T>> dropdownMenuEntries;
  final ValueChanged<T?>? onSelected;
  final Widget? label;
  final EdgeInsetsGeometry? expandedInsets;
  final double? width;
  final Widget? leadingIcon;
  final double? menuHeight;
  final bool enabled;

  @override
  State<TvDropdownMenu<T>> createState() => _TvDropdownMenuState<T>();
}

class _TvDropdownMenuState<T> extends State<TvDropdownMenu<T>> {
  final MenuController _menuController = MenuController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _openMenu() {
    context.read<SettingsProvider>().selectionClick();
    _menuController.open();
  }

  @override
  Widget build(BuildContext context) {
    final isTV = context.select<SettingsProvider, bool>((p) => p.isTV);
    final dropdown = DropdownMenu<T>(
      menuController: _menuController,
      initialSelection: widget.initialSelection,
      dropdownMenuEntries: widget.dropdownMenuEntries,
      onSelected: widget.onSelected,
      label: widget.label,
      expandedInsets: widget.expandedInsets,
      width: widget.width,
      leadingIcon: widget.leadingIcon,
      menuHeight: widget.menuHeight,
      enabled: widget.enabled,
      // Focus is owned by this wrapper on TV. On other platforms keep the
      // widget's own default (keyboard-focusable on desktop).
      requestFocusOnTap: isTV ? false : null,
    );
    if (!isTV || !widget.enabled) return dropdown;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          _openMenu();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: _focusNode,
        builder: (context, child) => DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: _focusNode.hasFocus
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  )
                : null,
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        ),
        child: dropdown,
      ),
    );
  }
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
            ExcludeSemantics(
              child: Icon(
                icon,
                size: 56,
                color: colorScheme.onSurfaceVariant,
                // The message is rendered below (announced once by the Text).
                semanticLabel: message,
              ),
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

/// Draws a high-contrast ring around whatever is focused inside [child].
///
/// Material's default focus treatment is a barely-visible overlay intended for
/// mouse/keyboard desktop use. On a TV the focus position is the only cursor,
/// so tiles/rows wrapped in this widget get a bright border whenever focus is
/// anywhere in their subtree. Does nothing on non-TV devices.
class TvFocusRing extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final double width;
  final Color? color;

  const TvFocusRing({
    super.key,
    required this.child,
    this.borderRadius = connectedTileBigRadius,
    this.width = 3,
    this.color,
  });

  @override
  State<TvFocusRing> createState() => _TvFocusRingState();
}

class _TvFocusRingState extends State<TvFocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isTV = context.select<SettingsProvider, bool>((p) => p.isTV);
    if (!isTV) return widget.child;
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) {
        if (focused != _focused) setState(() => _focused = focused);
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: _focused
              ? Border.all(color: color, width: widget.width)
              : null,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        child: widget.child,
      ),
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
      child: TvFocusRing(
        borderRadius: 4,
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
    return TvFocusRing(
      borderRadius: borderRadius?.topLeft.x ?? connectedTileBigRadius,
      child: ListTile(
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
      ),
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
      // Root pages have nothing to pop so no leading is shown; pushed pages
      // (Settings, Add app) get the standard back button.
      automaticallyImplyLeading: true,
      title: Text(title),
      actions: actions,
    );
  }
}

class _TileClipper extends CustomClipper<Path> {
  final RoundedSuperellipseBorder shape;
  const _TileClipper(this.shape);

  @override
  Path getClip(Size size) => shape.getOuterPath(Offset.zero & size);

  @override
  bool shouldReclip(_TileClipper oldClipper) =>
      oldClipper.shape.borderRadius != shape.borderRadius;
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
      key: w.key,
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
      key: w.key,
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
    final nextIsTile = i < children.length - 1 && _isTile(children[i + 1]);
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
    return TvFocusRing(
      child: ListTile(
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
