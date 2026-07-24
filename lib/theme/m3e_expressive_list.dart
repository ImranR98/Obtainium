import 'package:flutter/material.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/theme/app_theme_accent.dart';
import 'package:provider/provider.dart';

/// Material 3 expressive grouped-list radii and gaps (matches apps tab list).
const double kM3eOuterRadius = SettingsProvider.baseCardRadius;
const double kM3eInnerRadius = 4.0;
const double kM3eItemGap = 3.0;

/// Outer radius for elevated grouped surfaces such as apps-list groups.
const double kM3eGroupCardRadius = 20.0;

/// Gap between expansion group header and first row in apps list body.
const double kM3eHeaderToFirstCardGap = 3.0;

const Duration kM3eGroupHeaderTransitionDuration = Duration(milliseconds: 300);
const Curve kM3eGroupTransitionCurve = Curves.easeInOutCubicEmphasized;
const Duration kM3eGroupExpandDuration = Duration(milliseconds: 360);
const Duration kM3eGroupCollapseDuration = Duration(milliseconds: 250);

/// Shared horizontal gutter for full-width fields, segmented controls, and
/// sliders inside [M3eExpressiveSettingsCard] on the settings page.
const double kM3eSettingsCardHorizontalInset = 16;

/// Trailing gutter for [ListTile] rows and field rows with a trailing action
/// (switch, save, validate). Tighter than [kM3eSettingsCardHorizontalInset]
/// so those controls line up with the right edge of full-width fields.
const double kM3eSettingsCardTrailingInset = 8;

const EdgeInsets kM3eSettingsListTileContentPadding = EdgeInsets.only(
  left: kM3eSettingsCardHorizontalInset,
  right: kM3eSettingsCardTrailingInset,
);

enum M3eListGroupPosition { first, middle, last, only }

/// Corner radii for one row in a vertical stack. Use [flatListBody]: true for
/// rows inside a settings/import-style card or ungrouped apps list runs.
BorderRadius m3eListGroupItemRadius(
  M3eListGroupPosition position, {
  required bool flatListBody,
  double outerRadius = kM3eOuterRadius,
  double innerRadius = kM3eInnerRadius,
}) {
  if (flatListBody) {
    return switch (position) {
      M3eListGroupPosition.first => BorderRadius.only(
        topLeft: Radius.circular(outerRadius),
        topRight: Radius.circular(outerRadius),
        bottomLeft: Radius.circular(innerRadius),
        bottomRight: Radius.circular(innerRadius),
      ),
      M3eListGroupPosition.middle => BorderRadius.circular(innerRadius),
      M3eListGroupPosition.last => BorderRadius.only(
        topLeft: Radius.circular(innerRadius),
        topRight: Radius.circular(innerRadius),
        bottomLeft: Radius.circular(outerRadius),
        bottomRight: Radius.circular(outerRadius),
      ),
      M3eListGroupPosition.only => BorderRadius.only(
        topLeft: Radius.circular(outerRadius),
        topRight: Radius.circular(outerRadius),
        bottomLeft: Radius.circular(outerRadius),
        bottomRight: Radius.circular(outerRadius),
      ),
    };
  }
  return switch (position) {
    M3eListGroupPosition.first => BorderRadius.circular(innerRadius),
    M3eListGroupPosition.middle => BorderRadius.circular(innerRadius),
    M3eListGroupPosition.last => BorderRadius.only(
      topLeft: Radius.circular(innerRadius),
      topRight: Radius.circular(innerRadius),
      bottomLeft: Radius.circular(outerRadius),
      bottomRight: Radius.circular(outerRadius),
    ),
    M3eListGroupPosition.only => BorderRadius.only(
      topLeft: Radius.circular(innerRadius),
      topRight: Radius.circular(innerRadius),
      bottomLeft: Radius.circular(outerRadius),
      bottomRight: Radius.circular(outerRadius),
    ),
  };
}

M3eListGroupPosition m3eFlatStackSlotPosition(int index, int itemCount) {
  if (itemCount <= 1) return M3eListGroupPosition.only;
  if (index == 0) return M3eListGroupPosition.first;
  if (index == itemCount - 1) return M3eListGroupPosition.last;
  return M3eListGroupPosition.middle;
}

Color m3eCollapsedGroupHeaderFill(ColorScheme scheme) {
  if (scheme.usesPureBlackBackgrounds) return Colors.black;
  return Color.lerp(scheme.secondaryContainer, scheme.primaryContainer, 0.30)!;
}

Color m3eGroupedListRowFill(ColorScheme scheme) {
  if (scheme.usesPureBlackBackgrounds) return Colors.black;
  return Color.lerp(scheme.surfaceContainer, scheme.primary, 0.08)!;
}

Color m3eGroupedListBackdropFill(ColorScheme scheme) => scheme.surface;

BorderSide m3ePureBlackOutlineSide(ColorScheme scheme, {double alpha = 0.18}) {
  if (!scheme.usesPureBlackBackgrounds) {
    return BorderSide.none;
  }
  return BorderSide(color: scheme.onSurface.withValues(alpha: alpha));
}

/// The shared Material 3 Expressive header used by collapsible app groups.
class M3eCollapsibleGroupHeader extends StatelessWidget {
  const M3eCollapsibleGroupHeader({
    super.key,
    required this.title,
    required this.count,
    this.countText,
    required this.isExpanded,
    required this.onTap,
    required this.collapsedRadius,
    required this.colorScheme,
    this.trailingAction,
  });

  final String title;
  final int count;
  final String? countText;
  final bool isExpanded;
  final VoidCallback onTap;
  final double collapsedRadius;
  final ColorScheme colorScheme;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ShapeBorder shape = isExpanded
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(collapsedRadius),
              topRight: Radius.circular(collapsedRadius),
              bottomLeft: const Radius.circular(kM3eInnerRadius),
              bottomRight: const Radius.circular(kM3eInnerRadius),
            ),
            side: m3ePureBlackOutlineSide(colorScheme, alpha: 0.22),
          )
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(collapsedRadius)),
            side: m3ePureBlackOutlineSide(colorScheme, alpha: 0.22),
          );
    final Widget countLabel = Text(
      countText ?? count.toString(),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    );

    return Material(
      elevation: 3,
      shadowColor: colorScheme.shadow.withAlpha(100),
      surfaceTintColor: colorScheme.surfaceTint,
      shape: shape,
      color: colorScheme.usesPureBlackBackgrounds
          ? Color.alphaBlend(
              colorScheme.onSurface.withValues(alpha: 0.14),
              Colors.black,
            )
          : m3eCollapsedGroupHeaderFill(colorScheme),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: SettingsProvider.collapsedHeaderHeight,
          child: Center(
            child: ListTile(
              dense: true,
              onTap: null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: AnimatedContainer(
                duration: kM3eGroupHeaderTransitionDuration,
                curve: kM3eGroupTransitionCurve,
                width: isExpanded ? 20 : 32,
                height: isExpanded ? 20 : 32,
                decoration: BoxDecoration(
                  color: isExpanded
                      ? Colors.transparent
                      : colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0,
                  duration: kM3eGroupHeaderTransitionDuration,
                  curve: kM3eGroupTransitionCurve,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: isExpanded
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    size: isExpanded ? 18 : 20,
                  ),
                ),
              ),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: trailingAction == null
                  ? countLabel
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        countLabel,
                        const SizedBox(width: 8),
                        trailingAction!,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tighter [DropdownMenu] anchor field (language, backup scope, etc.).
ThemeData m3eCompactDropdownTheme(ThemeData base) {
  return base.copyWith(
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
  );
}

Widget m3eCompactDropdownScope({
  required BuildContext context,
  required Widget child,
}) {
  return Theme(data: m3eCompactDropdownTheme(Theme.of(context)), child: child);
}

/// Central Material 3 expressive row stack for settings-style grouped lists.
class M3eExpressiveSettingsCard extends StatelessWidget {
  const M3eExpressiveSettingsCard({
    super.key,
    required this.items,
    this.colorScheme,
    this.itemGap = kM3eItemGap,
  });

  final List<Widget> items;
  final ColorScheme? colorScheme;
  final double itemGap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme effectiveColorScheme = colorScheme ?? theme.colorScheme;
    final double cardCornerScale = context.select<SettingsProvider, double>(
      (s) => s.cardCornerScale,
    );
    final double itemOuterRadius = SettingsProvider.cardCornerRadiusForScale(
      kM3eOuterRadius,
      cardCornerScale,
    );
    final double itemInnerRadius = SettingsProvider.cardCornerRadiusForScale(
      kM3eInnerRadius,
      cardCornerScale,
    );
    final BorderSide blackThemeOutlineSide = m3ePureBlackOutlineSide(
      effectiveColorScheme,
      alpha: 0.22,
    );
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int itemIndex = 0; itemIndex < items.length; itemIndex++) ...[
            if (itemIndex > 0) SizedBox(height: itemGap),
            Material(
              color: m3eGroupedListRowFill(effectiveColorScheme),
              shape: RoundedRectangleBorder(
                borderRadius: m3eListGroupItemRadius(
                  m3eFlatStackSlotPosition(itemIndex, items.length),
                  flatListBody: true,
                  outerRadius: itemOuterRadius,
                  innerRadius: itemInnerRadius,
                ),
                side: blackThemeOutlineSide,
              ),
              clipBehavior: Clip.antiAlias,
              child: items[itemIndex],
            ),
          ],
        ],
      ),
    );
  }
}
