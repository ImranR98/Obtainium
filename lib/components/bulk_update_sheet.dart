import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/app_bottom_sheet.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/theme/m3e_expressive_list.dart';
import 'package:provider/provider.dart';

Future<Set<String>?> showBulkUpdatePickerSheet({
  required BuildContext context,
  required Map<String, AppInMemory> apps,
  required List<String> existingUpdateIds,
  required List<String> newInstallIds,
  required List<String> trackOnlyUpdateIds,
}) {
  final int totalApps =
      existingUpdateIds.length +
      newInstallIds.length +
      trackOnlyUpdateIds.length;
  return showAppModalSheet<Set<String>>(
    context: context,
    builder: (BuildContext sheetContext) {
      return BulkUpdateSheet(
        existingUpdateIds: existingUpdateIds,
        newInstallIds: newInstallIds,
        trackOnlyUpdateIds: trackOnlyUpdateIds,
        totalApps: totalApps,
        apps: apps,
      );
    },
  );
}

enum _BulkUpdateSectionId { updates, installs, trackOnly }

class _BulkUpdateSection {
  const _BulkUpdateSection({
    required this.id,
    required this.label,
    required this.appIds,
  });

  final _BulkUpdateSectionId id;
  final String label;
  final List<String> appIds;
}

class BulkUpdateSheet extends StatefulWidget {
  const BulkUpdateSheet({
    super.key,
    required this.existingUpdateIds,
    required this.newInstallIds,
    required this.trackOnlyUpdateIds,
    required this.totalApps,
    required this.apps,
  });

  final List<String> existingUpdateIds;
  final List<String> newInstallIds;
  final List<String> trackOnlyUpdateIds;
  final int totalApps;
  final Map<String, AppInMemory> apps;

  @override
  State<BulkUpdateSheet> createState() => _BulkUpdateSheetState();
}

class _BulkUpdateSheetState extends State<BulkUpdateSheet> {
  static const int _expandedByDefaultLimit = 3;

  late Set<String> selectedIds;
  late Set<_BulkUpdateSectionId> expandedSectionIds;

  @override
  void initState() {
    super.initState();
    selectedIds = {...widget.existingUpdateIds, ...widget.trackOnlyUpdateIds};
    if (widget.existingUpdateIds.isEmpty) {
      selectedIds.addAll(widget.newInstallIds);
    }
    expandedSectionIds = {
      if (visibleAppCount(widget.existingUpdateIds) <= _expandedByDefaultLimit)
        _BulkUpdateSectionId.updates,
      if (visibleAppCount(widget.newInstallIds) <= _expandedByDefaultLimit)
        _BulkUpdateSectionId.installs,
      if (visibleAppCount(widget.trackOnlyUpdateIds) <= _expandedByDefaultLimit)
        _BulkUpdateSectionId.trackOnly,
    };
  }

  List<_BulkUpdateSection> get sections => [
    _BulkUpdateSection(
      id: _BulkUpdateSectionId.updates,
      label: tr('updates'),
      appIds: widget.existingUpdateIds,
    ),
    _BulkUpdateSection(
      id: _BulkUpdateSectionId.installs,
      label: tr('nonInstalledApps'),
      appIds: widget.newInstallIds,
    ),
    _BulkUpdateSection(
      id: _BulkUpdateSectionId.trackOnly,
      label: tr('trackOnly'),
      appIds: widget.trackOnlyUpdateIds,
    ),
  ];

  int visibleAppCount(List<String> appIds) {
    return appIds.where(widget.apps.containsKey).length;
  }

  void setAppSelected(String appId, bool selected) {
    hapticSelection();
    setState(() {
      if (selected) {
        selectedIds.add(appId);
      } else {
        selectedIds.remove(appId);
      }
    });
  }

  void toggleGroup(List<String> groupIds) {
    hapticSelection();
    setState(() {
      final bool allInGroupSelected = groupIds.every(selectedIds.contains);
      if (allInGroupSelected) {
        selectedIds.removeAll(groupIds);
      } else {
        selectedIds.addAll(groupIds);
      }
    });
  }

  void toggleSectionExpanded(_BulkUpdateSectionId sectionId) {
    hapticSelection();
    setState(() {
      if (expandedSectionIds.contains(sectionId)) {
        expandedSectionIds.remove(sectionId);
      } else {
        expandedSectionIds.add(sectionId);
      }
    });
  }

  Widget buildAppIcon(AppInMemory appInMemory, bool notInstalled) {
    final iconBytes = appInMemory.icon;
    if (iconBytes != null) {
      final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      final int iconCachePx = (40 * devicePixelRatio).round();
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          iconBytes,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: iconCachePx,
          cacheHeight: iconCachePx,
          filterQuality: FilterQuality.low,
          opacity: AlwaysStoppedAnimation(notInstalled ? 0.6 : 1.0),
        ),
      );
    }
    return SizedBox(
      width: 40,
      height: 40,
      child: Center(
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.rotationZ(0.31),
          child: Image(
            image: const AssetImage('assets/graphics/icon_small.png'),
            width: 28,
            height: 28,
            fit: BoxFit.contain,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.3),
            colorBlendMode: BlendMode.modulate,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }

  Widget buildAppRow({
    required String appId,
    required ColorScheme colorScheme,
    required M3eListGroupPosition position,
    required double itemOuterRadius,
    required double itemInnerRadius,
  }) {
    final AppInMemory appInMemory = widget.apps[appId]!;
    final bool isNewInstall = appInMemory.app.installedVersion == null;
    final bool isUpdate =
        appInMemory.app.installedVersion != null &&
        appInMemory.app.installedVersion != appInMemory.app.latestVersion;
    final String versionLabel = isUpdate
        ? '${appInMemory.app.installedVersion} → ${appInMemory.app.latestVersion}'
        : appInMemory.app.latestVersion;
    final bool isSelected = selectedIds.contains(appId);
    final BorderRadius cardBorderRadius = m3eListGroupItemRadius(
      position,
      flatListBody: false,
      outerRadius: itemOuterRadius,
      innerRadius: itemInnerRadius,
    );
    return Material(
      color: m3eGroupedListRowFill(colorScheme),
      elevation: isSelected ? 1 : 0,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: cardBorderRadius,
        side: isSelected
            ? BorderSide(
                color: colorScheme.primary.withValues(alpha: 0.7),
                width: 1.5,
              )
            : m3ePureBlackOutlineSide(colorScheme),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: cardBorderRadius),
        selected: isSelected,
        tileColor: Colors.transparent,
        selectedTileColor: Colors.transparent,
        contentPadding: const EdgeInsets.only(left: 12, right: 8),
        leading: buildAppIcon(appInMemory, isNewInstall),
        title: Text(
          appInMemory.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (appInMemory.author.isNotEmpty)
              Text(
                tr('byX', args: [appInMemory.author]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (versionLabel.isNotEmpty)
              Text(versionLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        trailing: Checkbox(
          value: isSelected,
          onChanged: (bool? selected) {
            if (selected != null) {
              setAppSelected(appId, selected);
            }
          },
        ),
        onTap: () => setAppSelected(appId, !isSelected),
      ),
    );
  }

  Widget buildSection(
    _BulkUpdateSection section,
    ColorScheme colorScheme,
    double groupCardRadius,
    double collapsedHeaderRadius,
    double itemOuterRadius,
    double itemInnerRadius,
  ) {
    final List<String> visibleAppIds = section.appIds
        .where(widget.apps.containsKey)
        .toList();
    if (visibleAppIds.isEmpty) return const SizedBox.shrink();

    final bool isExpanded = expandedSectionIds.contains(section.id);
    final int selectedInGroup = visibleAppIds
        .where(selectedIds.contains)
        .length;
    final bool allInGroupSelected = visibleAppIds.every(selectedIds.contains);
    final bool someInGroupSelected = selectedInGroup > 0 && !allInGroupSelected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        M3eCollapsibleGroupHeader(
          title: section.label,
          count: visibleAppIds.length,
          isExpanded: isExpanded,
          onTap: () => toggleSectionExpanded(section.id),
          collapsedRadius: collapsedHeaderRadius,
          colorScheme: colorScheme,
          trailingAction: Tooltip(
            message: allInGroupSelected
                ? tr('deselectX', args: [visibleAppIds.length.toString()])
                : tr('selectAll'),
            child: Checkbox(
              value: allInGroupSelected
                  ? true
                  : someInGroupSelected
                  ? null
                  : false,
              tristate: true,
              onChanged: (_) => toggleGroup(visibleAppIds),
            ),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: AnimatedSize(
            duration: kM3eGroupExpandDuration,
            reverseDuration: kM3eGroupCollapseDuration,
            curve: kM3eGroupTransitionCurve,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(groupCardRadius),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (
                          int appIndex = 0;
                          appIndex < visibleAppIds.length;
                          appIndex++
                        ) ...[
                          SizedBox(
                            height: appIndex == 0
                                ? kM3eHeaderToFirstCardGap
                                : kM3eItemGap,
                          ),
                          buildAppRow(
                            appId: visibleAppIds[appIndex],
                            colorScheme: colorScheme,
                            position: visibleAppIds.length == 1
                                ? M3eListGroupPosition.only
                                : appIndex == 0
                                ? M3eListGroupPosition.first
                                : appIndex == visibleAppIds.length - 1
                                ? M3eListGroupPosition.last
                                : M3eListGroupPosition.middle,
                            itemOuterRadius: itemOuterRadius,
                            itemInnerRadius: itemInnerRadius,
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isTelevision = context.read<SettingsProvider>().isTV;
    final double cardCornerScale = context.select<SettingsProvider, double>(
      (SettingsProvider settings) => settings.cardCornerScale,
    );
    final double groupCardRadius = SettingsProvider.cardCornerRadiusForScale(
      kM3eGroupCardRadius,
      cardCornerScale,
    );
    final double collapsedHeaderRadius =
        SettingsProvider.cardCornerRadiusForScale(
          SettingsProvider.baseCollapsedHeaderRadius,
          cardCornerScale,
        );
    final double itemOuterRadius = SettingsProvider.cardCornerRadiusForScale(
      kM3eOuterRadius,
      cardCornerScale,
    );
    final double itemInnerRadius = SettingsProvider.cardCornerRadiusForScale(
      kM3eInnerRadius,
      cardCornerScale,
    );
    final List<_BulkUpdateSection> visibleSections = sections
        .where(
          (_BulkUpdateSection section) =>
              section.appIds.any(widget.apps.containsKey),
        )
        .toList();

    return AppSheetScaffold(
      header: Row(
        children: [
          Material(
            color: colorScheme.tertiaryContainer,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox.square(
              dimension: 48,
              child: Icon(
                Icons.system_update_alt_rounded,
                color: colorScheme.onTertiaryContainer,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr(
                'changeX',
                args: [plural('apps', widget.totalApps).toLowerCase()],
              ),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (
              int sectionIndex = 0;
              sectionIndex < visibleSections.length;
              sectionIndex++
            ) ...[
              if (sectionIndex > 0)
                const SizedBox(height: SettingsProvider.collapsedHeaderGap),
              buildSection(
                visibleSections[sectionIndex],
                colorScheme,
                groupCardRadius,
                collapsedHeaderRadius,
                itemOuterRadius,
                itemInnerRadius,
              ),
            ],
          ],
        ),
      ),
      footer: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            autofocus: isTelevision,
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: selectedIds.isEmpty
                ? null
                : () {
                    hapticSelection();
                    Navigator.of(context).pop(selectedIds);
                  },
            child: Text(tr('continue')),
          ),
        ],
      ),
    );
  }
}
