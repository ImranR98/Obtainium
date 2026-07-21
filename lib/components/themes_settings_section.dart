import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:obtainium/components/theme_accent_settings_section.dart'
    show buildThemeAccentSettingsCardItems;
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/components/tv_slider_wrapper.dart';
import 'package:obtainium/theme/app_segmented_button_theme.dart';
import 'package:obtainium/theme/m3e_expressive_list.dart';
import 'package:obtainium/widgets/help_hint_icon.dart';
import 'package:provider/provider.dart';

void _showBlackThemeSurfaceSettingDisabledSnackbar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(tr('settingsGradientDisabledInBlackTheme')),
      duration: const Duration(seconds: 4),
    ),
  );
}

/// One M3E row each (for [settingsCard] item list).
List<Widget> buildThemesSettingsCardItems(
  BuildContext context,
  Future<AndroidDeviceInfo> androidInfoFuture,
) {
  // Narrow watch: this section only reflects theme-related settings.
  // Without this, every settings notify rebuilt the whole themes card.
  context.select<SettingsProvider, int>(
    (s) => Object.hash(
      s.useBlackTheme,
      s.blackThemeActive,
      s.theme,
      s.useGradientBackground,
      s.shadingIntensity,
      s.progressiveBlurEnabled,
      s.matchAppPageToIconColors,
      s.reduceVisualEffects,
    ),
  );
  final SettingsProvider settings = context.read<SettingsProvider>();

  return [
    Padding(
      padding: const EdgeInsets.fromLTRB(
        kM3eSettingsCardHorizontalInset,
        8,
        kM3eSettingsCardHorizontalInset,
        8,
      ),
      child: SizedBox(
        width: double.infinity,
        child: AppSegmentedButton<ThemeSettings>(
          segments: [
            ButtonSegment<ThemeSettings>(
              value: ThemeSettings.system,
              label: AppSegmentedButtonLabel(
                tr('followSystem'),
                fontSize: 11.5,
              ),
              icon: const Icon(Icons.brightness_auto_outlined, size: 18),
            ),
            ButtonSegment<ThemeSettings>(
              value: ThemeSettings.light,
              label: AppSegmentedButtonLabel(tr('light'), fontSize: 11.5),
              icon: const Icon(Icons.light_mode_outlined, size: 18),
            ),
            ButtonSegment<ThemeSettings>(
              value: ThemeSettings.dark,
              label: AppSegmentedButtonLabel(tr('dark'), fontSize: 11.5),
              icon: const Icon(Icons.dark_mode_outlined, size: 18),
            ),
          ],
          selected: <ThemeSettings>{settings.theme},
          onSelectionChanged: (Set<ThemeSettings> selected) {
            if (selected.isEmpty) return;
            settings.theme = selected.first;
          },
          style: const ButtonStyle(
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            ),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
            side: WidgetStatePropertyAll(BorderSide.none),
          ),
        ),
      ),
    ),
    if (settings.theme != ThemeSettings.light)
      SwitchListTile(
        title: Text(tr('useBlackTheme')),
        value: settings.useBlackTheme,
        onChanged: (bool value) {
          settings.useBlackTheme = value;
        },
      ),
    ...buildThemeAccentSettingsCardItems(androidInfoFuture),
    _ShadingIntensityTile(settings: settings),
    ListTile(
      title: Text(tr('settingsGradientBackground')),
      trailing: IgnorePointer(
        ignoring: settings.blackThemeActive,
        child: Switch(
          value: settings.useGradientBackground,
          onChanged: settings.blackThemeActive
              ? null
              : (bool value) {
                  settings.useGradientBackground = value;
                },
        ),
      ),
      onTap: () {
        if (settings.blackThemeActive) {
          _showBlackThemeSurfaceSettingDisabledSnackbar(context);
          return;
        }
        settings.useGradientBackground = !settings.useGradientBackground;
      },
    ),
    ListTile(
      title: Text(tr('settingsProgressiveBlur')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HelpHintIcon(
            message: tr('settingsProgressiveBlurSubtitle'),
            padding: EdgeInsets.zero,
          ),
          Switch(
            value: settings.progressiveBlurEnabled,
            onChanged: settings.reduceVisualEffects
                ? null
                : (bool value) {
                    settings.progressiveBlurEnabled = value;
                  },
          ),
        ],
      ),
      // Hard-disabled when the master "reduce visual effects" switch is
      // on - no point letting users toggle a control that won't take
      // effect.
      onTap: settings.reduceVisualEffects
          ? null
          : () {
              settings.progressiveBlurEnabled =
                  !settings.progressiveBlurEnabled;
            },
    ),
    SwitchListTile(
      title: Text(tr('matchAppPageToIconColors')),
      value: settings.matchAppPageToIconColors,
      onChanged: (bool value) {
        settings.matchAppPageToIconColors = value;
      },
    ),
    // Master "low-fidelity mode" toggle. Forces blur off and skips the
    // OpenContainer container-transform morph for apps-list -> AppPage
    // navigation. Single-switch escape hatch for users on weaker
    // hardware who report frame-rate drops.
    ListTile(
      title: Text(tr('settingsReduceVisualEffects')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HelpHintIcon(
            message: tr('settingsReduceVisualEffectsSubtitle'),
            padding: EdgeInsets.zero,
          ),
          Switch(
            value: settings.reduceVisualEffects,
            onChanged: (bool value) {
              settings.reduceVisualEffects = value;
            },
          ),
        ],
      ),
      onTap: () {
        settings.reduceVisualEffects = !settings.reduceVisualEffects;
      },
    ),
  ];
}

class _ShadingIntensityTile extends StatefulWidget {
  const _ShadingIntensityTile({required this.settings});

  final SettingsProvider settings;

  @override
  State<_ShadingIntensityTile> createState() => _ShadingIntensityTileState();
}

class _ShadingIntensityTileState extends State<_ShadingIntensityTile> {
  late final FocusNode _sliderFocusNode;

  @override
  void initState() {
    super.initState();
    _sliderFocusNode = FocusNode(canRequestFocus: false, skipTraversal: true);
  }

  @override
  void dispose() {
    _sliderFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool enabled = !widget.settings.blackThemeActive;
    final double sliderValue = widget.settings.shadingIntensity;
    final isTV = context.read<SettingsProvider>().isTV;

    return InkWell(
      onTap: enabled
          ? null
          : () {
              _showBlackThemeSurfaceSettingDisabledSnackbar(context);
            },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          kM3eSettingsCardHorizontalInset,
          10,
          kM3eSettingsCardHorizontalInset,
          12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('settingsShadingIntensity'),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  _shadingIntensityLabel(sliderValue),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              tr('settingsShadingIntensitySubtitle'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            TVSliderWrapper(
              enabled: enabled,
              value: sliderValue,
              min: 0,
              max: 2,
              divisions: 20,
              onChanged: (double value) {
                widget.settings.shadingIntensity = value;
              },
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 16,
                  trackShape: const _ShadingGappedTrackShape(),
                  thumbShape: const _ShadingVerticalBarThumbShape(),
                  tickMarkShape: const RoundSliderTickMarkShape(
                    tickMarkRadius: 3,
                  ),
                  activeTickMarkColor: colorScheme.onPrimary,
                  inactiveTickMarkColor: colorScheme.primary,
                  disabledActiveTrackColor: colorScheme.onSurface.withValues(
                    alpha: 0.38,
                  ),
                  disabledInactiveTrackColor: colorScheme.onSurface.withValues(
                    alpha: 0.12,
                  ),
                  disabledThumbColor: colorScheme.onSurface.withValues(
                    alpha: 0.38,
                  ),
                  disabledActiveTickMarkColor: colorScheme.onSurface.withValues(
                    alpha: 0.38,
                  ),
                  disabledInactiveTickMarkColor: colorScheme.onSurface
                      .withValues(alpha: 0.38),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 20,
                  ),
                ),
                child: Slider(
                  focusNode: isTV ? _sliderFocusNode : null,
                  value: sliderValue,
                  min: 0,
                  max: 2,
                  divisions: 20,
                  label: _shadingIntensityLabel(sliderValue),
                  onChanged: enabled
                      ? (double value) {
                          widget.settings.shadingIntensity = value;
                        }
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _shadingIntensityLabel(double value) {
  return '${(value * 100).round()}%';
}

class _ShadingVerticalBarThumbShape extends SliderComponentShape {
  const _ShadingVerticalBarThumbShape();

  static const double _width = 4;
  static const double _height = 28;
  static const double _radius = 2;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(_width, _height);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Rect trackRect = sliderTheme.trackShape!.getPreferredRect(
      parentBox: parentBox,
      offset: Offset.zero,
      sliderTheme: sliderTheme,
      isEnabled: enableAnimation.value > 0,
      isDiscrete: isDiscrete,
    );
    final double trackHeight = trackRect.height;
    final double trackWidth = trackRect.width;
    Offset alignedCenter = center;
    if (trackWidth > trackHeight) {
      final double valueRatio = textDirection == TextDirection.rtl
          ? 1.0 - value
          : value;
      final double alignedX =
          trackRect.left +
          valueRatio * (trackWidth - trackHeight) +
          trackHeight / 2;
      alignedCenter = Offset(alignedX, center.dy);
    }
    final Canvas canvas = context.canvas;
    final Color thumbColor =
        ColorTween(
          begin: sliderTheme.disabledThumbColor,
          end: sliderTheme.thumbColor,
        ).evaluate(enableAnimation) ??
        sliderTheme.thumbColor ??
        Colors.white;
    final Paint paint = Paint()
      ..color = thumbColor
      ..style = PaintingStyle.fill;
    final RRect thumb = RRect.fromRectAndRadius(
      Rect.fromCenter(center: alignedCenter, width: _width, height: _height),
      const Radius.circular(_radius),
    );
    canvas.drawRRect(thumb, paint);
  }
}

class _ShadingGappedTrackShape extends SliderTrackShape
    with BaseSliderTrackShape {
  const _ShadingGappedTrackShape();

  static const int _divisions = 20;
  static const double _gap = 4;
  static const double _radius = 8;
  static const double _tickRadius = 2.75;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final Canvas canvas = context.canvas;
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    double thumbX = thumbCenter.dx;
    final double trackHeight = trackRect.height;
    final double trackWidth = trackRect.width;
    if (trackWidth > trackHeight) {
      final double valueRatio = ((thumbCenter.dx - trackRect.left) / trackWidth)
          .clamp(0.0, 1.0);
      thumbX =
          trackRect.left +
          valueRatio * (trackWidth - trackHeight) +
          trackHeight / 2;
    }

    final Color activeTrackColor =
        ColorTween(
          begin: sliderTheme.disabledActiveTrackColor,
          end: sliderTheme.activeTrackColor,
        ).evaluate(enableAnimation) ??
        sliderTheme.activeTrackColor ??
        Colors.blue;
    final Color inactiveTrackColor =
        ColorTween(
          begin: sliderTheme.disabledInactiveTrackColor,
          end: sliderTheme.inactiveTrackColor,
        ).evaluate(enableAnimation) ??
        sliderTheme.inactiveTrackColor ??
        Colors.grey;
    final Color activeTickMarkColor =
        ColorTween(
          begin: sliderTheme.disabledActiveTickMarkColor,
          end: sliderTheme.activeTickMarkColor,
        ).evaluate(enableAnimation) ??
        activeTrackColor;
    final Color inactiveTickMarkColor =
        ColorTween(
          begin: sliderTheme.disabledInactiveTickMarkColor,
          end: sliderTheme.inactiveTickMarkColor,
        ).evaluate(enableAnimation) ??
        inactiveTrackColor;
    final Paint activePaint = Paint()..color = activeTrackColor;
    final Paint inactivePaint = Paint()..color = inactiveTrackColor;

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(
          trackRect.left,
          trackRect.top,
          thumbX - _gap,
          trackRect.bottom,
        ),
        topLeft: const Radius.circular(_radius),
        bottomLeft: const Radius.circular(_radius),
      ),
      activePaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(
          thumbX + _gap,
          trackRect.top,
          trackRect.right,
          trackRect.bottom,
        ),
        topRight: const Radius.circular(_radius),
        bottomRight: const Radius.circular(_radius),
      ),
      inactivePaint,
    );

    final Paint tickPaint = Paint()..style = PaintingStyle.fill;
    for (int tickIndex = 1; tickIndex < _divisions; tickIndex++) {
      final double tickRatio = tickIndex / _divisions;
      final double tickX =
          trackRect.left +
          tickRatio * (trackWidth - trackHeight) +
          trackHeight / 2;
      final bool isActive = textDirection == TextDirection.rtl
          ? tickX > thumbX
          : tickX < thumbX;
      tickPaint.color = isActive ? activeTickMarkColor : inactiveTickMarkColor;
      canvas.drawCircle(
        Offset(tickX, trackRect.center.dy),
        _tickRadius,
        tickPaint,
      );
    }
  }
}
