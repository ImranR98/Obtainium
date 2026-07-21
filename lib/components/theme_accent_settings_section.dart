import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/components/tv_slider_wrapper.dart';
import 'package:obtainium/theme/app_dialog_theme.dart';
import 'package:obtainium/theme/app_theme_accent.dart';
import 'package:obtainium/theme/m3e_expressive_list.dart';
import 'package:provider/provider.dart';

const double _kAccentSwatchSize = 52;
const double _kAccentInnerSize = 44;

/// One M3E card row each (swatches with label, palette).
List<Widget> buildThemeAccentSettingsCardItems(
  Future<AndroidDeviceInfo> androidInfoFuture,
) {
  return <Widget>[
    const _ThemeAccentSwatchesItem(),
    _ThemeAccentPaletteItem(androidInfoFuture: androidInfoFuture),
  ];
}

class _ThemeAccentSwatchesItem extends StatefulWidget {
  const _ThemeAccentSwatchesItem();

  @override
  State<_ThemeAccentSwatchesItem> createState() =>
      _ThemeAccentSwatchesItemState();
}

class _ThemeAccentSwatchesItemState extends State<_ThemeAccentSwatchesItem> {
  bool _customColorPickerExpanded = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    // Narrow subscription — only rebuilds the swatches grid when a
    // custom-seed hex is added/removed/selected or the accent source
    // changes.
    context.select<SettingsProvider, int>(
      (s) => Object.hash(
        s.appAccentColorSource,
        s.activeCustomSeedHex,
        Object.hashAll(s.savedCustomSeedHexes),
      ),
    );
    final SettingsProvider settings = context.read<SettingsProvider>();

    Future<void> confirmRemoveHex(String hex) async {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text(tr('settingsCustomSeedRemoveTitle')),
            contentPadding: appDialogContentPadding,
            content: Text(tr('settingsCustomSeedRemoveMessage')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(tr('cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                child: Text(tr('remove')),
              ),
            ],
          );
        },
      );
      if (ok == true) settings.removeCustomSeedHex(hex);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kM3eSettingsCardHorizontalInset,
        8,
        kM3eSettingsCardHorizontalInset,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('settingsThemeColorsHint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: _kAccentSwatchSize,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final AppAccentColorSource source
                    in AppAccentColorSourceX.accentPickerOrder)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _AccentSourceSwatch(
                      source: source,
                      selected: settings.appAccentColorSource == source,
                      onTap: () {
                        settings.appAccentColorSource = source;
                      },
                    ),
                  ),
                for (final String storedHex in settings.savedCustomSeedHexes)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _CustomHexSwatch(
                      hex: storedHex,
                      selected: _customHexSwatchSelected(settings, storedHex),
                      onTap: () => settings.selectSavedCustomSeedHex(storedHex),
                      onLongPress: () => confirmRemoveHex(storedHex),
                    ),
                  ),
                _AddCustomHexSwatch(
                  expanded: _customColorPickerExpanded,
                  onTap: () {
                    setState(() {
                      _customColorPickerExpanded = !_customColorPickerExpanded;
                    });
                  },
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _customColorPickerExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: CustomColorSliderPanel(
                      seedHex: _sliderSeedHexForSettings(settings, scheme),
                      onPreviewColor: settings.previewCustomSeedHex,
                      onSaveColor: settings.addCustomSeedHex,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

bool _customHexSwatchSelected(SettingsProvider settings, String storedHex) {
  if (settings.appAccentColorSource != AppAccentColorSource.custom) {
    return false;
  }
  final String? activeNorm = normalizeCustomSeedHexOrNull(
    settings.activeCustomSeedHex,
  );
  final String? storedNorm = normalizeCustomSeedHexOrNull(storedHex);
  if (activeNorm != null && storedNorm != null) {
    return activeNorm == storedNorm;
  }
  return settings.activeCustomSeedHex.trim() == storedHex.trim();
}

String _sliderSeedHexForSettings(
  SettingsProvider settings,
  ColorScheme scheme,
) {
  if (settings.appAccentColorSource == AppAccentColorSource.custom) {
    final String? active = normalizeCustomSeedHexOrNull(
      settings.activeCustomSeedHex,
    );
    if (active != null) return active;
  }
  final Color? seed = settings.appAccentColorSource.seedOrNull;
  return colorToCanonicalHex(seed ?? scheme.primary);
}

const double _kCustomHexChipWidth = 96;
const Duration _kCustomHexDebounce = Duration(milliseconds: 450);

class CustomColorSliderPanel extends StatefulWidget {
  const CustomColorSliderPanel({
    super.key,
    required this.seedHex,
    required this.onPreviewColor,
    required this.onSaveColor,
    this.title,
    this.showSaveButton = true,
  });

  final String seedHex;
  final ValueChanged<String> onPreviewColor;
  final ValueChanged<String> onSaveColor;
  final String? title;
  final bool showSaveButton;

  @override
  State<CustomColorSliderPanel> createState() => _CustomColorSliderPanelState();
}

class _CustomColorSliderPanelState extends State<CustomColorSliderPanel> {
  late String _selectedHex;
  late final TextEditingController _hexController;
  final FocusNode _hexFocusNode = FocusNode();
  final Object _hexTapRegionGroup = Object();
  Timer? _hexDebounce;
  bool _hexEditing = false;

  @override
  void initState() {
    super.initState();
    _selectedHex = _normalizedOrDefault(widget.seedHex);
    _hexController = TextEditingController();
    _syncHexController();
  }

  @override
  void didUpdateWidget(covariant CustomColorSliderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String nextHex = _normalizedOrDefault(widget.seedHex);
    if (nextHex == _selectedHex) return;
    _hexDebounce?.cancel();
    setState(() {
      _selectedHex = nextHex;
      _syncHexController();
    });
  }

  @override
  void dispose() {
    _hexDebounce?.cancel();
    _hexController.dispose();
    _hexFocusNode.dispose();
    super.dispose();
  }

  String _normalizedOrDefault(String raw) {
    return normalizeCustomSeedHexOrNull(raw) ??
        colorToCanonicalHex(obtainiumThemeColor);
  }

  void _syncHexController() {
    final String text = _selectedHex;
    _hexController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _startHexEditing() {
    _hexDebounce?.cancel();
    _syncHexController();
    setState(() {
      _hexEditing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hexFocusNode.requestFocus();
    });
  }

  String _finishHexEditing() {
    _hexDebounce?.cancel();
    if (!_hexEditing) return _selectedHex;

    final String? normalized = normalizeCustomSeedHexOrNull(
      _hexController.text,
    );
    if (normalized != null) {
      _selectedHex = normalized;
      widget.onPreviewColor(normalized);
    }
    _syncHexController();
    setState(() {
      _hexEditing = false;
    });
    return _selectedHex;
  }

  void _scheduleHexPreview() {
    _hexDebounce?.cancel();
    final String raw = _hexController.text;
    final String clean = raw.startsWith('#') ? raw.substring(1) : raw;
    if (clean.length != 6) return;
    _hexDebounce = Timer(_kCustomHexDebounce, () {
      if (!mounted) return;
      final String? normalized = normalizeCustomSeedHexOrNull(raw);
      if (normalized == null) return;
      setState(() {
        _selectedHex = normalized;
      });
      widget.onPreviewColor(normalized);
    });
  }

  void _handleSliderChanged(String hex) {
    _hexDebounce?.cancel();
    final String normalized = _normalizedOrDefault(hex);
    setState(() {
      _selectedHex = normalized;
      _syncHexController();
    });
  }

  void _rejectHexInput() {
    hapticVibrate();
    SystemSound.play(SystemSoundType.alert);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final SettingsProvider settings = context.watch<SettingsProvider>();
    final double cardRadius = settings.cardCornerRadiusFor(
      SettingsProvider.baseCardRadius,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 18, 18, 22),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title ?? tr('settingsCustomSeedSliderTitle'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _buildHexChip(context),
              if (widget.showSaveButton) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton.filledTonal(
                    tooltip: tr('ok'),
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      fixedSize: const Size.square(36),
                      minimumSize: const Size.square(36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () {
                      final String hex = _finishHexEditing();
                      widget.onSaveColor(hex);
                    },
                    icon: const Icon(Icons.check_rounded),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          _HueColorSlider(
            hex: _selectedHex,
            onChanged: _handleSliderChanged,
            onChangeEnd: (String hex) {
              _handleSliderChanged(hex);
              widget.onPreviewColor(hex);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHexChip(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextStyle textStyle =
        (theme.textTheme.labelLarge ??
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))
            .copyWith(
              color: scheme.onSurfaceVariant,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            );

    final BoxDecoration decoration = BoxDecoration(
      color: Color.alphaBlend(
        scheme.onSurface.withValues(alpha: 0.055),
        scheme.surfaceContainerHigh,
      ),
      borderRadius: BorderRadius.circular(18),
    );

    if (!_hexEditing) {
      return SizedBox(
        width: _kCustomHexChipWidth,
        height: 36,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _startHexEditing,
            child: DecoratedBox(
              decoration: decoration,
              child: Center(
                child: Text(_selectedHex, maxLines: 1, style: textStyle),
              ),
            ),
          ),
        ),
      );
    }

    final double lineHeight = (textStyle.fontSize ?? 14) * 1.25;

    return TapRegion(
      groupId: _hexTapRegionGroup,
      onTapOutside: (_) => _finishHexEditing(),
      child: SizedBox(
        width: _kCustomHexChipWidth,
        height: 36,
        child: DecoratedBox(
          decoration: decoration,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.center,
              child: SizedBox(
                height: lineHeight,
                child: TextField(
                  controller: _hexController,
                  focusNode: _hexFocusNode,
                  inputFormatters: [
                    _HexInputFormatter(onReject: _rejectHexInput),
                  ],
                  maxLines: 1,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.center,
                  textAlignVertical: TextAlignVertical.center,
                  style: textStyle.copyWith(height: 1.0),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => _scheduleHexPreview(),
                  onEditingComplete: _finishHexEditing,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HexInputFormatter extends TextInputFormatter {
  const _HexInputFormatter({required this.onReject});

  final VoidCallback onReject;

  static final RegExp _validHex = RegExp(r'^[0-9a-fA-F]*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String nextText = newValue.text.toUpperCase();
    if (nextText.isNotEmpty && !nextText.startsWith('#')) {
      nextText = '#$nextText';
    }
    final String cleanText = nextText.startsWith('#')
        ? nextText.substring(1)
        : nextText;
    if (cleanText.length > 6 || !_validHex.hasMatch(cleanText)) {
      onReject();
      return oldValue;
    }

    int clampOffset(int offset) {
      final int prefixOffset =
          newValue.text.isNotEmpty && !newValue.text.startsWith('#') ? 1 : 0;
      return (offset + prefixOffset).clamp(0, nextText.length).toInt();
    }

    return TextEditingValue(
      text: nextText,
      selection: TextSelection(
        baseOffset: clampOffset(newValue.selection.baseOffset),
        extentOffset: clampOffset(newValue.selection.extentOffset),
        affinity: newValue.selection.affinity,
        isDirectional: newValue.selection.isDirectional,
      ),
      composing: TextRange.empty,
    );
  }
}

class CustomHueColorSlider extends StatelessWidget {
  const CustomHueColorSlider({
    super.key,
    required this.seedHex,
    required this.onPreviewColor,
    required this.onSaveColor,
    this.gapColor,
    this.showHandleGap = true,
  });

  final String seedHex;
  final ValueChanged<String> onPreviewColor;
  final ValueChanged<String> onSaveColor;
  final Color? gapColor;
  final bool showHandleGap;

  @override
  Widget build(BuildContext context) {
    final String hex =
        normalizeCustomSeedHexOrNull(seedHex) ??
        colorToCanonicalHex(obtainiumThemeColor);
    return _HueColorSlider(
      hex: hex,
      gapColor: gapColor,
      showHandleGap: showHandleGap,
      onChanged: onPreviewColor,
      onChangeEnd: onSaveColor,
    );
  }
}

class _HueColorSlider extends StatefulWidget {
  const _HueColorSlider({
    required this.hex,
    required this.onChanged,
    required this.onChangeEnd,
    this.gapColor,
    this.showHandleGap = true,
  });

  final String hex;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onChangeEnd;
  final Color? gapColor;
  final bool showHandleGap;

  @override
  State<_HueColorSlider> createState() => _HueColorSliderState();
}

class _HueColorSliderState extends State<_HueColorSlider> {
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double hue = _hueFromHexColor(widget.hex);
    final Color thumbColor = _colorFromHue(
      hue,
      saturation: _kHueSliderThumbSaturation,
      value: _kHueSliderThumbValue,
    );
    final bool lightPanel =
        scheme.surfaceContainerHighest.computeLuminance() > 0.5;
    final double gapWidth = widget.showHandleGap
        ? lightPanel
              ? _HueSliderTrackBackground.lightGapWidth
              : _HueSliderTrackBackground.defaultGapWidth
        : 0;
    final double handleWidth = lightPanel
        ? _HueSliderThumbShape.lightWidth
        : _HueSliderThumbShape.width;
    final isTV = context.read<SettingsProvider>().isTV;

    return SizedBox(
      height: _HueSliderThumbShape.height,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: _HueSliderTrackBackground(
                value: (hue / 360).clamp(0, 1).toDouble(),
                gapColor: widget.gapColor ?? scheme.surfaceContainerHighest,
                gapWidth: gapWidth,
                handleWidth: handleWidth,
              ),
            ),
          ),
          TVSliderWrapper(
            value: hue.clamp(0, 360).toDouble(),
            min: 0,
            max: 360,
            divisions: 72,
            onChanged: (double value) =>
                widget.onChanged(_colorHexFromHue(value)),
            onChangeEnd: (double value) =>
                widget.onChangeEnd(_colorHexFromHue(value)),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: _HueSliderTrackBackground.trackHeight,
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                secondaryActiveTrackColor: Colors.transparent,
                disabledActiveTrackColor: Colors.transparent,
                disabledInactiveTrackColor: Colors.transparent,
                thumbColor: thumbColor,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: _HueSliderThumbShape(handleWidth: handleWidth),
                tickMarkShape: SliderTickMarkShape.noTickMark,
              ),
              child: Slider(
                focusNode: isTV ? _sliderFocusNode : null,
                min: 0,
                max: 360,
                value: hue.clamp(0, 360).toDouble(),
                onChanged: (double value) =>
                    widget.onChanged(_colorHexFromHue(value)),
                onChangeEnd: (double value) =>
                    widget.onChangeEnd(_colorHexFromHue(value)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HueSliderTrackBackground extends StatelessWidget {
  const _HueSliderTrackBackground({
    required this.value,
    required this.gapColor,
    required this.gapWidth,
    required this.handleWidth,
  });

  final double value;
  final Color gapColor;
  final double gapWidth;
  final double handleWidth;
  static const double trackHeight = 28;
  static const double trackCorner = 10;
  static const double defaultGapWidth = 14;
  static const double lightGapWidth = 13;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double handleRadius = handleWidth / 2;
        final double usableWidth = (width - handleWidth).clamp(
          0.0,
          double.infinity,
        );
        final double gapCenter = handleRadius + usableWidth * value;

        return Center(
          child: SizedBox(
            height: trackHeight,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(trackCorner),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: _kHueSliderColors),
                    ),
                  ),
                  if (gapWidth > 0)
                    Positioned(
                      left: gapCenter - gapWidth / 2,
                      width: gapWidth,
                      top: 0,
                      bottom: 0,
                      child: ColoredBox(color: gapColor),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

const List<Color> _kHueSliderColors = [
  Color(0xFFE95A50),
  Color(0xFFE8B84E),
  Color(0xFFD5DB4C),
  Color(0xFF58D95C),
  Color(0xFF43CDD0),
  Color(0xFF5569E8),
  Color(0xFFD64BDD),
  Color(0xFFE95A50),
];

const double _kHueSliderGeneratedSaturation = 0.66;
const double _kHueSliderGeneratedValue = 0.90;
const double _kHueSliderThumbSaturation = 0.58;
const double _kHueSliderThumbValue = 0.86;

String _colorHexFromHue(double hue) {
  final double normalizedHue = hue >= 360 ? 0 : hue.clamp(0, 360).toDouble();
  return colorToCanonicalHex(
    HSVColor.fromAHSV(
      1,
      normalizedHue,
      _kHueSliderGeneratedSaturation,
      _kHueSliderGeneratedValue,
    ).toColor(),
  );
}

Color _colorFromHue(
  double hue, {
  required double saturation,
  required double value,
}) {
  final double normalizedHue = hue >= 360 ? 0 : hue.clamp(0, 360).toDouble();
  return HSVColor.fromAHSV(1, normalizedHue, saturation, value).toColor();
}

double _hueFromHexColor(String hex) {
  final Color? color = colorFromNormalizedHex(
    normalizeCustomSeedHexOrNull(hex),
  );
  if (color == null) return 0;
  return HSVColor.fromColor(color).hue;
}

class _HueSliderThumbShape extends SliderComponentShape {
  const _HueSliderThumbShape({required this.handleWidth});

  final double handleWidth;
  static const double width = 5;
  static const double lightWidth = 6;
  static const double height = 42;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size(handleWidth, height);
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
    final Color color = sliderTheme.thumbColor ?? Colors.white;
    final Rect rect = Rect.fromCenter(
      center: center,
      width: handleWidth,
      height: height,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = color,
    );
  }
}

class _ThemeAccentPaletteItem extends StatelessWidget {
  const _ThemeAccentPaletteItem({required this.androidInfoFuture});

  final Future<AndroidDeviceInfo> androidInfoFuture;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    // Narrow watch: this section reflects only the accent source and
    // palette-style selector.
    context.select<SettingsProvider, int>(
      (s) => Object.hash(s.appAccentColorSource, s.appThemePaletteStyle),
    );
    final SettingsProvider settings = context.read<SettingsProvider>();
    final bool paletteEnabled =
        settings.appAccentColorSource != AppAccentColorSource.materialYou;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kM3eSettingsCardHorizontalInset,
        8,
        kM3eSettingsCardHorizontalInset,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('settingsPaletteStyle'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (
                  int paletteIndex = 0;
                  paletteIndex < AppThemePaletteStyleX.all.length;
                  paletteIndex++
                ) ...[
                  if (paletteIndex > 0) const SizedBox(width: 8),
                  FilterChip(
                    label: Text(
                      tr(
                        'themePalette_${AppThemePaletteStyleX.all[paletteIndex].name}',
                      ),
                    ),
                    selected:
                        settings.appThemePaletteStyle ==
                        AppThemePaletteStyleX.all[paletteIndex],
                    onSelected: paletteEnabled
                        ? (bool selected) {
                            if (selected) {
                              settings.appThemePaletteStyle =
                                  AppThemePaletteStyleX.all[paletteIndex];
                            }
                          }
                        : null,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<AndroidDeviceInfo>(
            future: androidInfoFuture,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<AndroidDeviceInfo> snapshot,
                ) {
                  final int sdkInt = snapshot.data?.version.sdkInt ?? 0;
                  if (sdkInt >= 31) return const SizedBox.shrink();
                  if (settings.appAccentColorSource !=
                      AppAccentColorSource.materialYou) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      tr('settingsMaterialYouHint'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
          ),
        ],
      ),
    );
  }
}

class _AccentSourceSwatch extends StatelessWidget {
  const _AccentSourceSwatch({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final AppAccentColorSource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color haloColor = selected
        ? Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.58),
            scheme.surfaceContainerHighest,
          )
        : Color.alphaBlend(
            scheme.onSurface.withValues(alpha: 0.055),
            scheme.surfaceContainerHighest,
          );
    return Semantics(
      button: true,
      selected: selected,
      label: tr('accentSource_${source.name}'),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: _kAccentSwatchSize,
            height: _kAccentSwatchSize,
            decoration: BoxDecoration(shape: BoxShape.circle, color: haloColor),
            alignment: Alignment.center,
            child: _AccentCircleContent(source: source),
          ),
        ),
      ),
    );
  }
}

class _AccentCircleContent extends StatelessWidget {
  const _AccentCircleContent({required this.source});

  final AppAccentColorSource source;

  @override
  Widget build(BuildContext context) {
    const double inner = _kAccentInnerSize;
    switch (source) {
      case AppAccentColorSource.appDefault:
        return const _TripletAccentCircle(
          primary: Color(0xFF1B5EA8),
          secondary: Color(0xFF576270),
          tertiary: Color(0xFF006874),
          size: inner,
        );
      case AppAccentColorSource.materialYou:
        return SizedBox(
          width: inner,
          height: inner,
          child: Icon(
            Icons.palette_outlined,
            size: 28,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      default:
        final Color? seed = source.seedOrNull;
        final Color fill =
            seed ?? Theme.of(context).colorScheme.surfaceContainerHighest;
        return ClipOval(
          child: Container(width: inner, height: inner, color: fill),
        );
    }
  }
}

class _TripletAccentCircle extends StatelessWidget {
  const _TripletAccentCircle({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.size,
  });

  final Color primary;
  final Color secondary;
  final Color tertiary;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            Expanded(child: Container(color: primary)),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: Container(color: secondary)),
                  Expanded(child: Container(color: tertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomHexSwatch extends StatelessWidget {
  const _CustomHexSwatch({
    required this.hex,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color haloColor = selected
        ? Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.58),
            scheme.surfaceContainerHighest,
          )
        : Color.alphaBlend(
            scheme.onSurface.withValues(alpha: 0.055),
            scheme.surfaceContainerHighest,
          );
    final Color fill =
        colorFromNormalizedHex(normalizeCustomSeedHexOrNull(hex) ?? '') ??
        scheme.surfaceContainerHighest;
    return Semantics(
      button: true,
      selected: selected,
      label: hex,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          customBorder: const CircleBorder(),
          child: Container(
            width: _kAccentSwatchSize,
            height: _kAccentSwatchSize,
            decoration: BoxDecoration(shape: BoxShape.circle, color: haloColor),
            alignment: Alignment.center,
            child: ClipOval(
              child: Container(
                width: _kAccentInnerSize,
                height: _kAccentInnerSize,
                color: fill,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddCustomHexSwatch extends StatelessWidget {
  const _AddCustomHexSwatch({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: tr('settingsCustomSeedDialogTitle'),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: _kAccentSwatchSize,
            height: _kAccentSwatchSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.alphaBlend(
                scheme.onSurface.withValues(alpha: 0.055),
                scheme.surfaceContainerHighest,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              expanded ? Icons.keyboard_arrow_down_rounded : Icons.add,
              size: 26,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
