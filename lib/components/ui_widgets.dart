import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/ui_shapes.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Renders an app's icon as a Material 3 Expressive squircle, falling back to
/// the Obtainium glyph on a tonal surface when no icon is available. Centralizes
/// the icon/placeholder rendering shared by the app list and the app detail page.
class AppIcon extends StatelessWidget {
  final Uint8List? bytes;
  final double size;
  final double radius;

  /// Size of the fallback glyph shown when [bytes] is null.
  final double glyphSize;

  /// Dims the icon (e.g. to mark an app as not installed).
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

/// A text-style action that becomes a visible tonal button when the user has
/// enabled the "highlight touch targets" accessibility option, and a subtle
/// text button otherwise. Replaces the app's hand-built `InkWell` + tinted
/// `Container` link pattern with standard Material 3 buttons.
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
    final style = highlight ? FilledButton.styleFrom() : TextButton.styleFrom();
    if (icon != null) {
      return TextButton.icon(
        onPressed: onPressed,
        onLongPress: onLongPress,
        icon: icon!,
        label: label,
        style: style,
      );
    }
    return TextButton(
      onPressed: onPressed,
      onLongPress: onLongPress,
      style: style,
      child: label,
    );
  }
}

/// Copies [text] to the clipboard and shows a brief confirmation snackbar.
Future<void> copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(tr('copiedToClipboard'))));
  }
}

/// Shows a simple confirm/cancel dialog, resolving to true only if the user
/// confirmed.
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

/// Shows an informational "about/help" dialog with a title, scrollable content
/// widgets, and a single dismiss button.
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
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(tr('ok')),
        ),
      ],
    ),
  );
}

/// A centered placeholder for empty / loading / no-results states: a large
/// tonal icon with an optional caption.
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

/// A single rounded, tonal surface used for "connected" card runs (detail
/// sections, category groups, banners). [isFirst]/[isLast] set the squircle
/// corner radii so consecutive cards read as one block. Pass `padding: null`
/// when the child already provides its own insets.
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
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
      shape: positionalTileShape(isFirst: isFirst, isLast: isLast),
      clipBehavior: Clip.antiAlias,
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}

/// Tappable, underlined text that opens [url] in the external browser. Any
/// extra [style] (e.g. bold/italic) is merged with the underline decoration.
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
        onTap: () =>
            launchUrlString(url, mode: LaunchMode.externalApplication).ignore(),
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

  const ActionListTile({
    super.key,
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
    this.autoPop = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: trailing,
      enabled: onTap != null,
      onTap: onTap == null
          ? null
          : () {
              if (autoPop) Navigator.of(context).pop();
              onTap?.call();
            },
    );
  }
}

void showMessage(dynamic e, BuildContext context, {bool isError = false}) {
  Provider.of<LogsProvider>(
    context,
    listen: false,
  ).add(e.toString(), level: isError ? LogLevels.error : LogLevels.info);
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
