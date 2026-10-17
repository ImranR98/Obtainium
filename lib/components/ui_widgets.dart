import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/theme.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/utils/color_utils.dart';
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
          // On TV, focus the safe option unless the caller asked for the
          // confirm button: an unfocused dialog would let remote input fall
          // through to the page behind it.
          autofocus: !autofocusConfirm && context.read<SettingsProvider>().isTV,
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
              unawaited(copyToClipboard(context, e.toString()));
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
/// Material's [DropdownMenu] can only be driven with arrow keys and Enter on
/// its internal node (`LogicalKeyboardKey.select`, which a D-pad's OK button
/// produces, is not handled), and on Android its field is not focusable at
/// all. On TV this wrapper owns focus, draws a focus ring, and opens a
/// dialog picker on select; the entries are ordinary focusable list tiles.
/// On touch devices it renders the plain [DropdownMenu].
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
  final TextEditingController _displayController = TextEditingController();
  T? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection;
    _displayController.text = _labelFor(_selected);
  }

  @override
  void didUpdateWidget(covariant TvDropdownMenu<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSelection != widget.initialSelection) {
      _selected = widget.initialSelection;
      _displayController.text = _labelFor(_selected);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _displayController.dispose();
    super.dispose();
  }

  String _labelFor(T? value) {
    if (value == null) return '';
    for (final entry in widget.dropdownMenuEntries) {
      if (entry.value == value) return entry.label;
    }
    return '';
  }

  Future<void> _showOptions() async {
    context.read<SettingsProvider>().selectionClick();
    final selected = await showDialog<T>(
      context: context,
      builder: (ctx) => _TvDropdownOptionsDialog<T>(
        entries: widget.dropdownMenuEntries,
        selected: _selected,
        title: widget.label,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selected = selected;
      _displayController.text = _labelFor(selected);
    });
    widget.onSelected?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    final isTV = context.select<SettingsProvider, bool>((p) => p.isTV);
    final dropdown = DropdownMenu<T>(
      menuController: _menuController,
      controller: isTV ? _displayController : null,
      initialSelection: isTV ? _selected : widget.initialSelection,
      dropdownMenuEntries: widget.dropdownMenuEntries,
      onSelected: (value) {
        if (isTV) {
          // Only reachable through the Material menu's own controls, which
          // the TV flow above does not use; keep the display in sync anyway.
          setState(() {
            _selected = value ?? _selected;
            _displayController.text = _labelFor(_selected);
          });
        }
        widget.onSelected?.call(value);
      },
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
          _showOptions();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      // Focus must never enter the DropdownMenu subtree on TV: its closed
      // menu consumes arrow keys without navigating, which would trap the
      // D-pad on the row.
      child: ExcludeFocus(
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
      ),
    );
  }
}

class _TvDropdownOptionsDialog<T> extends StatelessWidget {
  final List<DropdownMenuEntry<T>> entries;
  final T? selected;
  final Widget? title;

  const _TvDropdownOptionsDialog({
    required this.entries,
    this.selected,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    var initialFocus = entries.indexWhere(
      (e) => e.enabled && e.value == selected,
    );
    if (initialFocus < 0) {
      initialFocus = entries.indexWhere((e) => e.enabled);
    }
    return AlertDialog(
      title: title,
      content: SizedBox(
        width: 480,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < entries.length; i++)
                  ListTile(
                    autofocus: i == initialFocus,
                    enabled: entries[i].enabled,
                    leading: entries[i].leadingIcon,
                    title: Text(entries[i].label),
                    trailing: entries[i].value == selected
                        ? Icon(
                            Icons.check,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: entries[i].enabled
                        ? () => Navigator.of(context).pop(entries[i].value)
                        : null,
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('cancel')),
        ),
      ],
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

/// Gives freshly pushed pages an initial focus ring on TV.
///
/// Pages without an explicit autofocus open unfocused, so the first SELECT
/// does nothing until a direction key is pressed. This focuses the first
/// control below the app bar unless the page already focused something;
/// arrow-up still reaches the bar geometrically.
class TvInitialFocus extends StatefulWidget {
  final Widget child;

  const TvInitialFocus({super.key, required this.child});

  @override
  State<TvInitialFocus> createState() => _TvInitialFocusState();
}

class _TvInitialFocusState extends State<TvInitialFocus> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !context.read<SettingsProvider>().isTV) return;
      final scope = FocusScope.of(context);
      if (scope.hasFocus) return;
      final policy = FocusTraversalGroup.maybeOf(context);
      if (policy == null) return;
      FocusNode? first = policy.findFirstFocus(scope, ignoreCurrentFocus: true);
      // Skip leading app-bar buttons (e.g. Back) so the first content
      // control gets the ring.
      for (var i = 0; i < 4 && first != null; i++) {
        final ctx = first.context;
        final inAppBar =
            ctx?.findAncestorWidgetOfExactType<CustomAppBar>() != null ||
            ctx?.findAncestorWidgetOfExactType<SliverAppBar>() != null ||
            ctx?.findAncestorWidgetOfExactType<AppBar>() != null;
        if (!inAppBar) break;
        if (!first.nextFocus()) return;
        first = FocusManager.instance.primaryFocus;
      }
      first?.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
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

/// A labelled slider over a fixed list of integer options, with the chosen
/// value rendered by [labelBuilder]. Mirrors the update-interval/minimum-age
/// sliders in the settings page and stays its own [StatefulWidget] so dragging
/// only rebuilds this tile; the value is committed when the drag ends.
class NumericOptionSliderTile extends StatefulWidget {
  final String label;
  final List<int> options;
  final int value;
  final ValueChanged<int> onChanged;
  final String Function(int value) labelBuilder;

  const NumericOptionSliderTile({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.labelBuilder,
  });

  @override
  State<NumericOptionSliderTile> createState() =>
      _NumericOptionSliderTileState();
}

class _NumericOptionSliderTileState extends State<NumericOptionSliderTile> {
  late double sliderVal;
  bool showLabel = true;

  int get _selected =>
      widget.options[sliderVal.round().clamp(0, widget.options.length - 1)];

  String get _label => widget.labelBuilder(_selected);

  @override
  void initState() {
    super.initState();
    _syncFromValue();
  }

  @override
  void didUpdateWidget(covariant NumericOptionSliderTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.options.length != widget.options.length) {
      _syncFromValue();
    }
  }

  void _syncFromValue() {
    final index = widget.options.indexOf(widget.value);
    sliderVal = (index >= 0 ? index : 0).toDouble();
  }

  void _commit() => widget.onChanged(_selected);

  @override
  Widget build(BuildContext context) {
    final max = (widget.options.length - 1).toDouble();
    final rawSlider = Slider(
      value: sliderVal,
      max: max,
      divisions: widget.options.length > 1 ? widget.options.length - 1 : null,
      label: _label,
      onChanged: (double value) {
        setState(() {
          sliderVal = value;
        });
      },
      onChangeStart: (double value) {
        setState(() {
          showLabel = false;
        });
      },
      onChangeEnd: (double value) {
        setState(() {
          showLabel = true;
        });
        _commit();
      },
    );

    final Widget slider = context.read<SettingsProvider>().isTV
        ? Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: sliderVal <= 0
                    ? null
                    : () {
                        setState(() {
                          sliderVal = (sliderVal - 1).clamp(0.0, max);
                        });
                        _commit();
                      },
              ),
              Expanded(child: Text(_label, textAlign: TextAlign.center)),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: sliderVal >= max
                    ? null
                    : () {
                        setState(() {
                          sliderVal = (sliderVal + 1).clamp(0.0, max);
                        });
                        _commit();
                      },
              ),
            ],
          )
        : rawSlider;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        showLabel
            ? Text('${widget.label}: $_label')
            : const SizedBox(height: 20),
        slider,
      ],
    );
  }
}

class LegacyMaterialBridge extends StatelessWidget {
  final Widget child;

  const LegacyMaterialBridge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return MaterialUiCompatibilityBridge(child: child);
  }
}

/// A curated palette shared by the TV colour pickers (categories and the app
/// accent colour).
const List<Color> kPickerPalette = [
  Color(0xFFEF5350),
  Color(0xFFFF7043),
  Color(0xFFFFA726),
  Color(0xFFFFCA28),
  Color(0xFF9CCC65),
  Color(0xFF66BB6A),
  Color(0xFF26A69A),
  Color(0xFF26C6DA),
  Color(0xFF29B6F6),
  Color(0xFF42A5F5),
  Color(0xFF5C6BC0),
  Color(0xFF7E57C2),
  Color(0xFFAB47BC),
  Color(0xFFEC407A),
  Color(0xFF8D6E63),
  Color(0xFF78909C),
];

/// TV-friendly colour picker: a focusable palette (plus random) instead of
/// the gesture-driven wheel, which a remote cannot operate. Returns the
/// confirmed colour, or null when cancelled.
Future<Color?> showTvColourPickerDialog(
  BuildContext context, {
  required Color initialColor,
  required String title,
  ValueChanged<Color>? onColorChanged,
  List<Color> extraColors = const [],
}) {
  return showDialog<Color>(
    context: context,
    builder: (ctx) => _TvColourPickerDialog(
      initialColor: initialColor,
      title: title,
      onColorChanged: onColorChanged,
      extraColors: extraColors,
    ),
  );
}

class _TvColourPickerDialog extends StatefulWidget {
  final Color initialColor;
  final String title;
  final ValueChanged<Color>? onColorChanged;
  final List<Color> extraColors;

  const _TvColourPickerDialog({
    required this.initialColor,
    required this.title,
    this.onColorChanged,
    this.extraColors = const [],
  });

  @override
  State<_TvColourPickerDialog> createState() => _TvColourPickerDialogState();
}

class _TvColourPickerDialogState extends State<_TvColourPickerDialog> {
  late Color _color = widget.initialColor;

  void _pick(Color color) {
    setState(() => _color = color);
    widget.onColorChanged?.call(color);
  }

  @override
  Widget build(BuildContext context) {
    final seen = <int>{};
    final colors = <Color>[
      for (final c in [
        ...kPickerPalette,
        ...widget.extraColors,
        widget.initialColor,
      ])
        if (seen.add(c.toARGB32())) c,
    ];
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Wrap(
          spacing: AppSpacings.elementGap,
          runSpacing: AppSpacings.elementGap,
          children: [
            for (final c in colors)
              _TvColourSwatch(
                color: c,
                selected: c.toARGB32() == _color.toARGB32(),
                autofocus: c.toARGB32() == widget.initialColor.toARGB32(),
                onTap: () => _pick(c),
              ),
            _TvColourSwatch(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              selected: false,
              onTap: () => _pick(generateRandomLightColor()),
              icon: Tooltip(
                message: tr('randomColour'),
                child: const Icon(Icons.casino_outlined, size: 20),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_color),
          child: Text(tr('continue')),
        ),
      ],
    );
  }
}

class _TvColourSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;
  final Widget? icon;

  const _TvColourSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: TvFocusRing(
        borderRadius: 24,
        child: InkWell(
          autofocus: autofocus,
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? cs.onSurface : cs.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: icon == null
                ? (selected
                      ? Icon(
                          Icons.check,
                          size: 20,
                          color:
                              ThemeData.estimateBrightnessForColor(color) ==
                                  Brightness.dark
                              ? Colors.white
                              : Colors.black,
                        )
                      : null)
                : Center(child: icon),
          ),
        ),
      ),
    );
  }
}
