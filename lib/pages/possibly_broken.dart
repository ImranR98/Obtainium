import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/components/app_list_tile.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/theme.dart';
import 'package:obtainium/utils/broken_check.dart';
import 'package:obtainium/utils/nav_helper.dart';
import 'package:provider/provider.dart';

enum _IgnoreAction { currentVersion, permanently }

class PossiblyBrokenPage extends StatelessWidget {
  const PossiblyBrokenPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final appsProvider = context.watch<AppsProvider>();
    final apps = appsProvider.apps.values.map((e) => e.app).toList();
    final flagged =
        apps.where((a) => isAppPossiblyBroken(a, settingsProvider)).toList()
          ..sort(_byName);
    final ignored = apps.where(isBrokenCheckIgnored).toList()..sort(_byName);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          CustomAppBar(title: tr('possiblyBroken')),
          SliverPadding(
            padding: AppPaddings.page,
            sliver: SliverToBoxAdapter(
              child: TvInitialFocus(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacings.sectionGap,
                  children: [
                    _buildDetectionSettings(settingsProvider),
                    if (flagged.isEmpty && ignored.isEmpty)
                      _buildEmptyState(context)
                    else ...[
                      if (flagged.isNotEmpty)
                        _buildAppSection(
                          context,
                          appsProvider,
                          settingsProvider,
                          title: tr('possiblyBrokenDetectedApps'),
                          apps: flagged,
                          ignoredSection: false,
                        ),
                      if (ignored.isNotEmpty)
                        _buildAppSection(
                          context,
                          appsProvider,
                          settingsProvider,
                          title: tr('possiblyBrokenIgnoredApps'),
                          apps: ignored,
                          ignoredSection: true,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.bottom),
          ),
        ],
      ),
    );
  }

  static int _byName(App a, App b) =>
      a.finalName.toLowerCase().compareTo(b.finalName.toLowerCase());

  Widget _buildDetectionSettings(SettingsProvider settingsProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 3,
      children: shapeCardTiles([
        _sliderTile(
          label: tr('possiblyBrokenStaleReleaseCheck'),
          options: brokenCheckDayOptions,
          value: settingsProvider.brokenCheckStaleReleaseDays,
          labelBuilder: brokenCheckDaysLabel,
          onChanged: (value) =>
              settingsProvider.brokenCheckStaleReleaseDays = value,
        ),
        _sliderTile(
          label: tr('possiblyBrokenStaleVersionCheck'),
          options: brokenCheckDayOptions,
          value: settingsProvider.brokenCheckStaleVersionDays,
          labelBuilder: brokenCheckDaysLabel,
          onChanged: (value) =>
              settingsProvider.brokenCheckStaleVersionDays = value,
        ),
        _sliderTile(
          label: tr('possiblyBrokenFailedChecksCheck'),
          options: brokenCheckFailedChecksOptions,
          value: settingsProvider.brokenCheckFailedChecksCount,
          labelBuilder: brokenCheckFailedChecksLabel,
          onChanged: (value) =>
              settingsProvider.brokenCheckFailedChecksCount = value,
        ),
        ToggleTile(
          label: tr('possiblyBrokenArchivedCheck'),
          value: settingsProvider.brokenCheckArchivedEnabled,
          onChanged: (value) =>
              settingsProvider.brokenCheckArchivedEnabled = value,
        ),
        _sliderTile(
          label: tr('possiblyBrokenFilteredReleasesCheck'),
          options: brokenCheckFilteredReleasesOptions,
          value: settingsProvider.brokenCheckFilteredReleasesCount,
          labelBuilder: brokenCheckFilteredReleasesLabel,
          onChanged: (value) =>
              settingsProvider.brokenCheckFilteredReleasesCount = value,
        ),
        ToggleTile(
          label: tr('showBrokenCheckIndicator'),
          value: settingsProvider.showBrokenCheckIndicator,
          onChanged: (value) =>
              settingsProvider.showBrokenCheckIndicator = value,
        ),
      ]),
    );
  }

  Widget _sliderTile({
    required String label,
    required List<int> options,
    required int value,
    required String Function(int) labelBuilder,
    required ValueChanged<int> onChanged,
  }) {
    return CardTile(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: NumericOptionSliderTile(
        label: label,
        options: options,
        value: value,
        labelBuilder: labelBuilder,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return CardTile(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          tr('possiblyBrokenNoApps'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _buildAppSection(
    BuildContext context,
    AppsProvider appsProvider,
    SettingsProvider settingsProvider, {
    required String title,
    required List<App> apps,
    required bool ignoredSection,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 3,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(title, style: Theme.of(context).textTheme.labelMedium),
        ),
        ...shapeCardTiles(
          apps
              .map(
                (app) => ignoredSection
                    ? _buildIgnoredTile(context, appsProvider, app)
                    : _buildFlaggedTile(
                        context,
                        appsProvider,
                        settingsProvider,
                        app,
                      ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildFlaggedTile(
    BuildContext context,
    AppsProvider appsProvider,
    SettingsProvider settingsProvider,
    App app,
  ) {
    final config = resolveBrokenCheckConfig(
      app.additionalSettings,
      settingsProvider,
    );
    final reasons = evaluateBrokenCheckReasons(app, config);
    return CardTile(
      child: ListTile(
        leading: AppIconWidget(
          appId: app.id,
          installed: app.installedVersion != null,
          appsProvider: appsProvider,
        ),
        title: Text(
          app.finalName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          reasons.map((r) => brokenCheckReasonLabel(r, app, config)).join('\n'),
        ),
        isThreeLine: reasons.length > 1,
        trailing: PopupMenuButton<_IgnoreAction>(
          tooltip: tr('more'),
          onSelected: (action) => _ignoreApp(
            appsProvider,
            app,
            action == _IgnoreAction.permanently,
          ),
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: _IgnoreAction.currentVersion,
              child: Text(tr('ignoreForThisVersion')),
            ),
            PopupMenuItem(
              value: _IgnoreAction.permanently,
              child: Text(tr('ignorePermanently')),
            ),
          ],
        ),
        onTap: () => NavHelper.pushAppPage(context, app.id),
      ),
    );
  }

  Widget _buildIgnoredTile(
    BuildContext context,
    AppsProvider appsProvider,
    App app,
  ) {
    return CardTile(
      child: ListTile(
        leading: AppIconWidget(
          appId: app.id,
          installed: app.installedVersion != null,
          appsProvider: appsProvider,
        ),
        title: Text(
          app.finalName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          app.brokenCheckEnabled
              ? tr('possiblyBrokenIgnoredForVersion')
              : tr('possiblyBrokenIgnoredPermanently'),
        ),
        trailing: IconButton(
          tooltip: tr('restore'),
          icon: const Icon(Icons.settings_backup_restore),
          onPressed: () => appsProvider.saveApps([
            app.copyWith(
              brokenCheckEnabled: true,
              brokenCheckDismissedVersion: null,
            ),
          ]),
        ),
        onTap: () => NavHelper.pushAppPage(context, app.id),
      ),
    );
  }

  Future<void> _ignoreApp(
    AppsProvider appsProvider,
    App app,
    bool permanently,
  ) {
    return appsProvider.saveApps([
      permanently
          ? app.copyWith(
              brokenCheckEnabled: false,
              brokenCheckDismissedVersion: null,
            )
          : app.copyWith(brokenCheckDismissedVersion: app.latestVersion),
    ]);
  }
}
