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
import 'package:obtainium/components/settings_widgets.dart';

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
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
  });

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
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
  const CustomAppBar({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    // M3 Expressive large app bar (pinned, does not collapse on scroll).
    return SliverAppBar.large(
      pinned: true,
      automaticallyImplyLeading: true,
      title: Text(title),
    );
  }
}
