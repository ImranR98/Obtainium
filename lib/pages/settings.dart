import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:equations/equations.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:shizuku_apk_installer/shizuku_apk_installer.dart';
import 'package:obtainium/components/category_editor.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/installers/root_installer.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/pages/import_export.dart';
import 'package:obtainium/pages/logs.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/external_install_bridge.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/theme.dart';
import 'package:obtainium/utils/locale_utils.dart';
import 'package:obtainium/utils/native_features.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int? androidSdkInt;
  int _installerCheckSeq = 0;
  bool _isRunningBgCheck = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sp = context.read<SettingsProvider>();
      if (sp.prefs == null) sp.initializeSettings();
      initAndroidSdk();
    });
  }

  Future<void> _triggerManualBgCheck() async {
    if (_isRunningBgCheck) return;
    setState(() => _isRunningBgCheck = true);
    AppLogger.info('Manual BG update check triggered from settings');
    try {
      final taskId = 'manual_${DateTime.now().millisecondsSinceEpoch}';
      await bgUpdateCheck(taskId, null, forceAll: true);
      AppLogger.info('Manual BG update check completed successfully');
    } catch (e, stack) {
      AppLogger.error(
        e,
        stackTrace: stack,
        message: 'Manual BG update check crashed',
      );
    }
    if (!mounted) return;
    setState(() => _isRunningBgCheck = false);
  }

  Future<void> initAndroidSdk() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      androidSdkInt = info.version.sdkInt;
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      AppLogger.error(e, message: 'Failed to get Android SDK info');
    }
  }

  Future<bool> showColorPickerDialog(
    SettingsProvider settingsProvider,
    ColorSwatch<Object> obtainiumSwatch,
  ) async {
    final Map<ColorSwatch<Object>, String> colorsNameMap =
        <ColorSwatch<Object>, String>{obtainiumSwatch: 'Obtainium'};
    return ColorPicker(
      color: settingsProvider.themeColor,
      onColorChanged: (Color color) {
        settingsProvider.themeColor = color;
        setState(() {});
      },
      actionButtons: const ColorPickerActionButtons(
        okButton: true,
        closeButton: true,
        dialogActionButtons: false,
      ),
      pickersEnabled: const <ColorPickerType, bool>{
        ColorPickerType.both: false,
        ColorPickerType.primary: false,
        ColorPickerType.accent: false,
        ColorPickerType.bw: false,
        ColorPickerType.custom: true,
        ColorPickerType.wheel: true,
      },
      pickerTypeLabels: <ColorPickerType, String>{
        ColorPickerType.custom: tr('standard'),
        ColorPickerType.wheel: tr('custom'),
      },
      title: Text(
        tr('selectX', args: [lowerCaseUnlessLang(tr('colour'), 'de')]),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      wheelDiameter: 192,
      wheelSquareBorderRadius: 32,
      width: 48,
      height: 48,
      borderRadius: 24,
      spacing: 8,
      runSpacing: 8,
      enableShadesSelection: false,
      customColorSwatchesAndNames: colorsNameMap,
      showMaterialName: true,
      showColorName: true,
      materialNameTextStyle: Theme.of(context).textTheme.bodySmall,
      colorNameTextStyle: Theme.of(context).textTheme.bodySmall,
      copyPasteBehavior: const ColorPickerCopyPasteBehavior(
        longPressMenu: true,
      ),
    ).showPickerDialog(
      context,
      transitionBuilder:
          (
            BuildContext context,
            Animation<double> a1,
            Animation<double> a2,
            Widget widget,
          ) {
            final double curvedValue = Curves.easeInOutCubicEmphasized
                .transform(a1.value);
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(curvedValue, curvedValue, 1),
              child: Opacity(opacity: a1.value, child: widget),
            );
          },
      transitionDuration: const Duration(milliseconds: 250),
    );
  }

  void handleColorPickerCancel(Color previousColor, SettingsProvider sp) {
    sp.themeColor = previousColor;
    setState(() {});
  }

  void handleInstallerModeChange(
    SettingsProvider settingsProvider,
    String mode,
    int currentSeq,
  ) {
    if (_installerCheckSeq != currentSeq) return;
    settingsProvider.selectionClick();
    if (mode == InstallerMode.shizuku.name) {
      _installerCheckSeq++;
      final seq = _installerCheckSeq;
      ShizukuApkInstaller()
          .checkPermission()
          .then((resCode) {
            if (_installerCheckSeq != seq) return;
            settingsProvider.installerMode =
                (resCode?.startsWith('granted') ?? false)
                ? InstallerMode.shizuku.name
                : InstallerMode.system.name;
            if (!context.mounted) return;
            final errorText = switch (resCode) {
              'services_not_found' => tr('shizukuBinderNotFound'),
              'old_shizuku' => tr('shizukuOld'),
              'old_android_with_adb' => tr('shizukuOldAndroidWithADB'),
              'denied' => tr('cancelled'),
              null => tr('unexpectedError'),
              _ => null,
            };
            if (errorText != null) {
              if (!mounted) return;
              showError(ObtainiumError(errorText), context);
            }
          })
          .catchError((e) {
            if (_installerCheckSeq != seq) return;
            settingsProvider.installerMode = InstallerMode.system.name;
            if (!mounted) return;
            showError(e, context);
          });
    } else if (mode == InstallerMode.root.name) {
      _installerCheckSeq++;
      final seq = _installerCheckSeq;
      RootInstaller(settingsProvider)
          .checkPermission()
          .then((rootGranted) {
            if (_installerCheckSeq != seq) return;
            settingsProvider.installerMode = rootGranted
                ? InstallerMode.root.name
                : InstallerMode.system.name;
            if (!mounted) return;
            if (!rootGranted) {
              showError(ObtainiumError(tr('rootNotGranted')), context);
            }
          })
          .catchError((e) {
            if (_installerCheckSeq != seq) return;
            settingsProvider.installerMode = InstallerMode.system.name;
            if (!mounted) return;
            showError(e, context);
          });
    } else {
      settingsProvider.installerMode = mode;
    }
  }

  Widget _caption(BuildContext context, String text) => CardTile(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall),
  );

  Widget _fieldTile(BuildContext context, Widget field) => ConnectedCard(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: field,
  );

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settingsProvider = context.watch<SettingsProvider>();
    final sourceProvider = context.read<SourceProvider>();
    final sdk = androidSdkInt ?? 0;

    final colorPicker = _ThemeColorPickerTile(
      showColorPickerDialog: showColorPickerDialog,
      handleColorPickerCancel: handleColorPickerCancel,
    );

    final sortDropdown = DropdownMenu<SortColumnSettings>(
      expandedInsets: EdgeInsets.zero,
      label: Text(tr('appSortBy')),
      initialSelection: settingsProvider.sortColumn,
      dropdownMenuEntries: [
        DropdownMenuEntry(
          value: SortColumnSettings.authorName,
          label: tr('authorName'),
        ),
        DropdownMenuEntry(
          value: SortColumnSettings.nameAuthor,
          label: tr('nameAuthor'),
        ),
        DropdownMenuEntry(
          value: SortColumnSettings.added,
          label: tr('asAdded'),
        ),
        DropdownMenuEntry(
          value: SortColumnSettings.releaseDate,
          label: tr('releaseDate'),
        ),
      ],
      onSelected: (value) {
        if (value != null) {
          settingsProvider.sortColumn = value;
        }
      },
    );

    final orderControl = CardTile(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(tr('appSortOrder'))),
          const SizedBox(width: 12),
          SegmentedButton<SortOrderSettings>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: SortOrderSettings.ascending,
                icon: const Icon(Icons.arrow_upward_rounded),
                tooltip: tr('ascending'),
              ),
              ButtonSegment(
                value: SortOrderSettings.descending,
                icon: const Icon(Icons.arrow_downward_rounded),
                tooltip: tr('descending'),
              ),
            ],
            selected: {settingsProvider.sortOrder},
            onSelectionChanged: (selection) {
              settingsProvider.selectionClick();
              settingsProvider.sortOrder = selection.first;
            },
          ),
        ],
      ),
    );

    final allSourceConfigItems = sourceProvider.sources
        .expand((e) => e.sourceConfigSettingFormItems)
        .map((e) => e.clone())
        .toList();
    for (var item in allSourceConfigItems) {
      if (item is GeneratedFormSwitch) {
        item.value = settingsProvider.getSettingBool(item.key);
      } else {
        item.value = settingsProvider.getSettingString(item.key);
      }
    }
    final Widget? sourceSpecificForm = allSourceConfigItems.isEmpty
        ? null
        : GeneratedForm(
            tileMode: true,
            items: allSourceConfigItems.map((e) => [e]).toList(),
            onValueChanges: (values, valid, isBuilding) {
              if (valid && !isBuilding) {
                values.forEach((key, value) {
                  final formItem = allSourceConfigItems
                      .where((i) => i.key == key)
                      .firstOrNull;
                  if (formItem is GeneratedFormSwitch) {
                    settingsProvider.setSettingBool(key, value == true);
                  } else {
                    settingsProvider.setSettingString(key, value ?? '');
                  }
                });
              }
            },
          );

    final bool showBgSection =
        settingsProvider.updateInterval > 0 &&
        (sdk >= 30 || settingsProvider.useShizuku);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: CustomScrollView(
        slivers: <Widget>[
          CustomAppBar(title: tr('settings')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverToBoxAdapter(
              child: settingsProvider.prefs == null
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Builder(
                      builder: (ctx) {
                        final rows = <Widget>[
                          _settingsRow(
                            context,
                            icon: Icons.import_export,
                            title: tr('importExport'),
                            onTap: () => _pushPage(
                              context,
                              title: tr('importExport'),
                              childBuilder: (_) => const Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ExportSection(),
                                  SizedBox(height: 14),
                                  ImportSection(),
                                ],
                              ),
                            ),
                          ),
                          _settingsRow(
                            context,
                            icon: Icons.update_outlined,
                            title: tr('updates'),
                            onTap: () => _pushPage(
                              context,
                              title: tr('updates'),
                              childBuilder: (ctx) =>
                                  _buildUpdatesSection(ctx, showBgSection, sdk),
                            ),
                          ),
                          if (sourceSpecificForm != null)
                            _settingsRow(
                              context,
                              icon: Icons.tune_outlined,
                              title: tr('sourceSpecific'),
                              onTap: () => _pushPage(
                                context,
                                title: tr('sourceSpecific'),
                                childBuilder: (_) => sourceSpecificForm,
                              ),
                            ),
                          _settingsRow(
                            context,
                            icon: Icons.palette_outlined,
                            title: tr('appearance'),
                            onTap: () => _pushPage(
                              context,
                              title: tr('appearance'),
                              childBuilder: (ctx) => _buildAppearanceSection(
                                ctx,
                                colorPicker,
                                sortDropdown,
                                orderControl,
                              ),
                            ),
                          ),
                          CardTile(
                            child: ListTile(
                              leading: Icon(
                                Icons.code,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              title: Text(tr('appSource')),
                              trailing: Icon(
                                Icons.open_in_new,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                size: 20,
                              ),
                              onTap: () => launchUrlString(
                                context.read<SettingsProvider>().sourceUrl,
                                mode: LaunchMode.externalApplication,
                              ),
                              shape: RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          CardTile(
                            child: ListTile(
                              leading: Icon(
                                Icons.help_outline_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              title: Text(tr('wiki')),
                              trailing: Icon(
                                Icons.open_in_new,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                size: 20,
                              ),
                              onTap: () => launchUrlString(
                                'https://wiki.obtainium.imranr.dev/',
                                mode: LaunchMode.externalApplication,
                              ),
                              shape: RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          CardTile(
                            child: ListTile(
                              leading: Icon(
                                Icons.bug_report_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              title: Text(tr('appLogs')),
                              trailing: Icon(
                                Icons.chevron_right,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              onTap: () {
                                AppLogger.getLogs().then((logs) {
                                  if (!context.mounted) return;
                                  if (logs.isEmpty) {
                                    showMessage(
                                      ObtainiumError(tr('noLogs')),
                                      context,
                                    );
                                  } else {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => const LogsPage(),
                                      ),
                                    );
                                  }
                                });
                              },
                              shape: RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ];
                        final settingTiles = rows.sublist(0, rows.length - 3);
                        final footerTiles = rows.sublist(rows.length - 3);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 20,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: 3,
                              children: shapeCardTiles(settingTiles),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: 3,
                              children: shapeCardTiles(footerTiles),
                            ),
                          ],
                        );
                      },
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

  Widget _settingsRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return CardTile(
      child: ListTile(
        leading: Icon(icon, color: cs.primary),
        title: Text(title),
        trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        onTap: () {
          context.read<SettingsProvider>().selectionClick();
          onTap();
        },
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _pushPage(
    BuildContext context, {
    required String title,
    required Widget Function(BuildContext) childBuilder,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Consumer<SettingsProvider>(
          builder: (ctx, sp, _) => Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: CustomScrollView(
              slivers: [
                CustomAppBar(title: title),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  sliver: SliverToBoxAdapter(child: childBuilder(ctx)),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(height: MediaQuery.of(ctx).padding.bottom),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUpdatesSection(
    BuildContext context,
    bool showBgSection,
    int sdk,
  ) {
    final settingsProvider = context.read<SettingsProvider>();
    final children = <Widget>[
      const CardTile(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: _UpdateIntervalSliderTile(),
      ),
      if (showBgSection) ...[
        ToggleTile(
          label: tr('enableBackgroundSilentInstalls'),
          value: settingsProvider.enableBackgroundUpdates,
          onChanged: (value) =>
              settingsProvider.enableBackgroundUpdates = value,
          helpWidgets: [
            Text(tr('backgroundUpdateReqsExplanation')),
            const SizedBox(height: 8),
            Text(tr('backgroundUpdateLimitsExplanation')),
          ],
        ),
        if (settingsProvider.updateInterval != 0) ...[
          ToggleTile(
            label: tr('bgUpdatesOnWiFiOnly'),
            value: settingsProvider.bgUpdatesOnWiFiOnly,
            onChanged: (value) => settingsProvider.bgUpdatesOnWiFiOnly = value,
          ),
          ToggleTile(
            label: tr('bgUpdatesWhileChargingOnly'),
            value: settingsProvider.bgUpdatesWhileChargingOnly,
            onChanged: (value) =>
                settingsProvider.bgUpdatesWhileChargingOnly = value,
          ),
          CardTile(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: _isRunningBgCheck ? null : _triggerManualBgCheck,
                child: _isRunningBgCheck
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(tr('runBgCheckNow')),
              ),
            ),
          ),
        ],
      ],
      ToggleTile(
        label: tr('enableCertificatePinning'),
        value: settingsProvider.enableCertificatePinning,
        onChanged: (value) => settingsProvider.enableCertificatePinning = value,
      ),
      ToggleTile(
        label: tr('checkOnStart'),
        value: settingsProvider.checkOnStart,
        onChanged: (value) => settingsProvider.checkOnStart = value,
      ),
      ToggleTile(
        label: tr('checkUpdateOnDetailPage'),
        value: settingsProvider.checkUpdateOnDetailPage,
        onChanged: (value) => settingsProvider.checkUpdateOnDetailPage = value,
      ),
      ToggleTile(
        label: tr('onlyCheckInstalledOrTrackOnlyApps'),
        value: settingsProvider.onlyCheckInstalledOrTrackOnlyApps,
        onChanged: (value) =>
            settingsProvider.onlyCheckInstalledOrTrackOnlyApps = value,
      ),
      ConnectedCard(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: GeneratedForm(
          tileMode: true,
          items: [
            [
              GeneratedFormTextField(
                'globalApkFilterRegEx',
                label: tr('globalApkFilterRegEx'),
                required: false,
                additionalValidators: [regExValidator],
              )..value = settingsProvider.globalApkFilterRegEx,
            ],
          ],
          onValueChanges: (values, valid, isBuilding) {
            if (valid && !isBuilding) {
              settingsProvider.globalApkFilterRegEx =
                  values['globalApkFilterRegEx'];
            }
          },
        ),
      ),
      ToggleTile(
        label: tr('removeOnExternalUninstall'),
        value: settingsProvider.removeOnExternalUninstall,
        onChanged: (value) =>
            settingsProvider.removeOnExternalUninstall = value,
      ),
      ToggleTile(
        label: tr('includePrereleasesByDefault'),
        value: settingsProvider.includePrereleasesByDefault,
        onChanged: (value) =>
            settingsProvider.includePrereleasesByDefault = value,
      ),
      ToggleTile(
        label: tr('showAppDowngradeError'),
        value: settingsProvider.showAppDowngradeError,
        onChanged: (value) => settingsProvider.showAppDowngradeError = value,
      ),
      ToggleTile(
        label: tr('hideDowngrades'),
        value: settingsProvider.hideDowngrades,
        onChanged: (value) => settingsProvider.hideDowngrades = value,
      ),
      ToggleTile(
        label: tr('skipBulkUpdateConfirmation'),
        value: settingsProvider.skipBulkUpdateConfirmation,
        onChanged: (value) =>
            settingsProvider.skipBulkUpdateConfirmation = value,
      ),
      const CardTile(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: _MinimumUpdateAgeSliderTile(),
      ),
      ToggleTile(
        label: tr('parallelDownloads'),
        value: settingsProvider.parallelDownloads,
        onChanged: (value) => settingsProvider.parallelDownloads = value,
      ),
      ToggleTile(
        label: tr('beforeNewInstallsShareToAppVerifier'),
        value: settingsProvider.beforeNewInstallsShareToAppVerifier,
        onChanged: (value) =>
            settingsProvider.beforeNewInstallsShareToAppVerifier = value,
        subtitle: LinkText(
          text: tr('about'),
          url: 'https://github.com/privacyguides/verified-apps-android',
          style: const TextStyle(fontSize: 12),
        ),
      ),
      _fieldTile(
        context,
        DropdownMenu<String>(
          expandedInsets: EdgeInsets.zero,
          label: Text(tr('installMethod')),
          initialSelection: settingsProvider.installerMode,
          dropdownMenuEntries: [
            DropdownMenuEntry(
              value: InstallerMode.system.name,
              label: tr('installMethodSystem'),
            ),
            DropdownMenuEntry(
              value: InstallerMode.shizuku.name,
              label: tr('installMethodShizuku'),
            ),
            DropdownMenuEntry(
              value: InstallerMode.external.name,
              label: tr('installMethodExternal'),
            ),
            DropdownMenuEntry(
              value: InstallerMode.root.name,
              label: tr('installMethodRoot'),
            ),
          ],
          onSelected: (value) {
            if (value != null) {
              handleInstallerModeChange(
                settingsProvider,
                value,
                _installerCheckSeq,
              );
            }
          },
        ),
      ),
      if (settingsProvider.installerMode == InstallerMode.shizuku.name ||
          settingsProvider.installerMode == InstallerMode.root.name)
        ToggleTile(
          label: tr('shizukuPretendToBeGooglePlay'),
          value: settingsProvider.shizukuPretendToBeGooglePlay,
          onChanged: (value) =>
              settingsProvider.shizukuPretendToBeGooglePlay = value,
        ),
      if (settingsProvider.installerMode == InstallerMode.external.name)
        const CardTile(child: _ExternalInstallerTile()),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 3,
      children: shapeCardTiles(children),
    );
  }

  Widget _buildAppearanceSection(
    BuildContext context,
    Widget colorPicker,
    Widget sortDropdown,
    Widget orderControl,
  ) {
    final settingsProvider = context.read<SettingsProvider>();
    final sdk = androidSdkInt ?? 0;
    final children = <Widget>[
      // Theme segmented button wrapped in CardTile so shapeCardTiles finds it.
      CardTile(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text(tr('theme'))),
            const SizedBox(width: 12),
            SegmentedButton<ThemeSettings>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: ThemeSettings.system,
                  icon: const Icon(Icons.brightness_auto_outlined),
                  tooltip: tr('followSystem'),
                ),
                ButtonSegment(
                  value: ThemeSettings.light,
                  icon: const Icon(Icons.light_mode_outlined),
                  tooltip: tr('light'),
                ),
                ButtonSegment(
                  value: ThemeSettings.dark,
                  icon: const Icon(Icons.dark_mode_outlined),
                  tooltip: tr('dark'),
                ),
              ],
              selected: {settingsProvider.theme},
              onSelectionChanged: (selection) {
                settingsProvider.selectionClick();
                settingsProvider.theme = selection.first;
              },
            ),
          ],
        ),
      ),
      if (settingsProvider.theme == ThemeSettings.system &&
          (androidSdkInt ?? 30) < 29)
        _caption(context, tr('followSystemThemeExplanation')),
      if (settingsProvider.theme != ThemeSettings.light)
        ToggleTile(
          label: tr('useBlackTheme'),
          value: settingsProvider.useBlackTheme,
          onChanged: (value) => settingsProvider.useBlackTheme = value,
        ),
      _fieldTile(context, const _ColourSchemeDropdown()),
      if (settingsProvider.colourSchemeMode != ColourSchemeMode.materialYou)
        // Colour picker as CardTile so shapeCardTiles finds it.
        CardTile(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(connectedTileBigRadius),
            ),
            title: Text(
              tr('selectX', args: [lowerCaseUnlessLang(tr('colour'), 'de')]),
            ),
            subtitle: Text(
              '${ColorTools.nameThatColor(settingsProvider.themeColor)} '
              '(${ColorTools.materialNameAndCode(settingsProvider.themeColor)})',
            ),
            trailing: ColorIndicator(
              width: 40,
              height: 40,
              borderRadius: 20,
              color: settingsProvider.themeColor,
              onSelectFocus: false,
              onSelect: () async {
                final colorBeforeDialog = settingsProvider.themeColor;
                if (!(await showColorPickerDialog(
                  settingsProvider,
                  obtainiumThemeColor.toSwatch(),
                ))) {
                  handleColorPickerCancel(colorBeforeDialog, settingsProvider);
                }
              },
            ),
          ),
        ),
      _fieldTile(context, sortDropdown),
      orderControl,
      _fieldTile(context, const _LocaleDropdown()),
      if (sdk >= 29)
        ToggleTile(
          label: tr('useSystemFont'),
          value: settingsProvider.useSystemFont,
          onChanged: (useSystemFont) {
            if (useSystemFont) {
              NativeFeatures.loadSystemFont()
                  .then((_) {
                    settingsProvider.useSystemFont = true;
                  })
                  .catchError((e) {
                    if (!context.mounted) return;
                    showError(
                      ObtainiumError('${tr('unexpectedError')}: $e'),
                      context,
                    );
                  });
            } else {
              settingsProvider.useSystemFont = false;
            }
          },
        ),
      ToggleTile(
        label: tr('showWebInAppView'),
        value: settingsProvider.showAppWebpage,
        onChanged: (value) => settingsProvider.showAppWebpage = value,
      ),
      ToggleTile(
        label: tr('pinUpdates'),
        value: settingsProvider.pinUpdates,
        onChanged: (value) => settingsProvider.pinUpdates = value,
      ),
      ToggleTile(
        label: tr('moveNonInstalledAppsToBottom'),
        value: settingsProvider.buryNonInstalled,
        onChanged: (value) => settingsProvider.buryNonInstalled = value,
      ),
      _fieldTile(
        context,
        DropdownMenu<String>(
          expandedInsets: EdgeInsets.zero,
          label: Text(tr('groupBy')),
          initialSelection: settingsProvider.groupBy,
          dropdownMenuEntries: [
            DropdownMenuEntry(value: GroupByMode.none.name, label: tr('none')),
            DropdownMenuEntry(
              value: GroupByMode.category.name,
              label: tr('category'),
            ),
            DropdownMenuEntry(
              value: GroupByMode.source.name,
              label: tr('source'),
            ),
          ],
          onSelected: (value) {
            if (value != null) {
              settingsProvider.groupBy = value;
            }
          },
        ),
      ),
      ToggleTile(
        label: tr('dontShowTrackOnlyWarnings'),
        value: settingsProvider.hideTrackOnlyWarning,
        onChanged: (value) => settingsProvider.hideTrackOnlyWarning = value,
      ),
      ToggleTile(
        label: tr('collapseGroupsOnStartup'),
        value: settingsProvider.collapseGroupsOnStartup,
        onChanged: (value) => settingsProvider.collapseGroupsOnStartup = value,
      ),
      ToggleTile(
        label: tr('dontShowAPKOriginWarnings'),
        value: settingsProvider.hideAPKOriginWarning,
        onChanged: (value) => settingsProvider.hideAPKOriginWarning = value,
      ),
      ToggleTile(
        label: tr('highlightTouchTargets'),
        value: settingsProvider.highlightTouchTargets,
        onChanged: (value) => settingsProvider.highlightTouchTargets = value,
      ),
      ToggleTile(
        label: tr('disableSwipeActions'),
        value: settingsProvider.disableSwipeActions,
        onChanged: (value) => settingsProvider.disableSwipeActions = value,
      ),
      ToggleTile(
        label: tr('alwaysUsePhoneLayout'),
        value: settingsProvider.alwaysUsePhoneLayout,
        onChanged: (value) => settingsProvider.alwaysUsePhoneLayout = value,
      ),
      _fieldTile(
        context,
        DropdownMenu<ActionBannerMode>(
          expandedInsets: EdgeInsets.zero,
          label: Text(tr('actionBanner')),
          initialSelection: settingsProvider.actionBannerMode,
          dropdownMenuEntries: [
            DropdownMenuEntry(value: ActionBannerMode.all, label: tr('all')),
            DropdownMenuEntry(
              value: ActionBannerMode.updatesOnly,
              label: tr('updates'),
            ),
            DropdownMenuEntry(value: ActionBannerMode.none, label: tr('none')),
          ],
          onSelected: (value) {
            if (value != null) {
              settingsProvider.actionBannerMode = value;
            }
          },
        ),
      ),
      ToggleTile(
        label: tr('tactileFeedbackEnabled'),
        value: settingsProvider.tactileFeedbackEnabled,
        onChanged: (value) => settingsProvider.tactileFeedbackEnabled = value,
      ),
      const CardTile(padding: EdgeInsets.all(12), child: CategoryManager()),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 3,
      children: shapeCardTiles(children),
    );
  }
}

extension on Color {
  ColorSwatch<Object> toSwatch() => ColorTools.createPrimarySwatch(this);
}

/// Slider tile for the minimum-age-for-updates setting. Kept as its own
/// [StatefulWidget] so that dragging the slider only rebuilds this tile
/// rather than the entire settings page; the chosen value is only committed
/// to the [SettingsProvider] when the drag ends.
class _MinimumUpdateAgeSliderTile extends StatefulWidget {
  const _MinimumUpdateAgeSliderTile();

  @override
  State<_MinimumUpdateAgeSliderTile> createState() =>
      _MinimumUpdateAgeSliderTileState();
}

class _MinimumUpdateAgeSliderTileState
    extends State<_MinimumUpdateAgeSliderTile> {
  double sliderVal = 0;
  bool showLabel = true;

  int get _days =>
      minimumUpdateAgeOptions[sliderVal.round().clamp(
        0,
        minimumUpdateAgeOptions.length - 1,
      )];

  String get _label => _days == 0 ? tr('none') : plural('day', _days);

  @override
  void initState() {
    super.initState();
    _syncFromSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFromSettings();
  }

  void _syncFromSettings() {
    final days = context.read<SettingsProvider>().minimumUpdateAgeDays;
    final index = minimumUpdateAgeOptions.indexOf(days);
    sliderVal = (index >= 0 ? index : 0).toDouble();
  }

  void _commit() {
    context.read<SettingsProvider>().minimumUpdateAgeDays = _days;
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.read<SettingsProvider>();
    final rawSlider = Slider(
      value: sliderVal,
      max: (minimumUpdateAgeOptions.length - 1).toDouble(),
      divisions: minimumUpdateAgeOptions.length - 1,
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

    final Widget ageSlider = settingsProvider.isTV
        ? Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: sliderVal <= 0
                    ? null
                    : () {
                        final newVal = (sliderVal - 1).clamp(
                          0.0,
                          (minimumUpdateAgeOptions.length - 1).toDouble(),
                        );
                        setState(() {
                          sliderVal = newVal;
                        });
                        _commit();
                      },
              ),
              Expanded(child: Text(_label, textAlign: TextAlign.center)),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed:
                    sliderVal >= (minimumUpdateAgeOptions.length - 1).toDouble()
                    ? null
                    : () {
                        final newVal = (sliderVal + 1).clamp(
                          0.0,
                          (minimumUpdateAgeOptions.length - 1).toDouble(),
                        );
                        setState(() {
                          sliderVal = newVal;
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
            ? Text("${tr('minimumUpdateAgeDays')}: $_label")
            : const SizedBox(height: 20),
        ageSlider,
      ],
    );
  }
}

/// The background-update-interval slider tile. Kept as its own [StatefulWidget]
/// so that dragging the slider only rebuilds this tile rather than the entire
/// (large) settings page; the chosen value is only committed to the
/// [SettingsProvider] when the drag ends.
class _UpdateIntervalSliderTile extends StatefulWidget {
  const _UpdateIntervalSliderTile();

  @override
  State<_UpdateIntervalSliderTile> createState() =>
      _UpdateIntervalSliderTileState();
}

class _UpdateIntervalSliderTileState extends State<_UpdateIntervalSliderTile> {
  final List<int> updateIntervalNodes = [
    15,
    30,
    60,
    120,
    180,
    360,
    720,
    1440,
    4320,
    10080,
    20160,
    43200,
  ];
  int updateInterval = 0;
  late SplineInterpolation updateIntervalInterpolator;
  String updateIntervalLabel = tr('neverManualOnly');
  bool showIntervalLabel = true;
  late double sliderVal;

  @override
  void initState() {
    super.initState();
    initUpdateIntervalInterpolator();
    sliderVal = context.read<SettingsProvider>().updateIntervalSliderVal;
    processIntervalSliderValue(sliderVal);
  }

  void initUpdateIntervalInterpolator() {
    final List<InterpolationNode> nodes = [];
    for (final (index, element) in updateIntervalNodes.indexed) {
      nodes.add(
        InterpolationNode(x: index.toDouble() + 1, y: element.toDouble()),
      );
    }
    updateIntervalInterpolator = SplineInterpolation(nodes: nodes);
  }

  void processIntervalSliderValue(double val) {
    if (val < 0.5) {
      updateInterval = 0;
      updateIntervalLabel = tr('neverManualOnly');
      return;
    }
    int valInterpolated = 0;
    if (val < 1) {
      valInterpolated = 15;
    } else {
      valInterpolated = updateIntervalInterpolator.compute(val).round();
    }
    if (valInterpolated < 60) {
      updateInterval = valInterpolated;
      updateIntervalLabel = plural('minute', valInterpolated);
    } else if (valInterpolated < 8 * 60) {
      final int valRounded = (valInterpolated / 15).floor() * 15;
      updateInterval = valRounded;
      updateIntervalLabel = plural('hour', valRounded ~/ 60);
      final int mins = valRounded % 60;
      if (mins != 0) updateIntervalLabel += " ${plural('minute', mins)}";
    } else if (valInterpolated < 24 * 60) {
      final int valRounded = (valInterpolated / 30).floor() * 30;
      updateInterval = valRounded;
      updateIntervalLabel = plural('hour', valRounded ~/ 60);
    } else if (valInterpolated < 7 * 24 * 60) {
      final int valRounded = (valInterpolated / (12 * 60)).floor() * 12 * 60;
      updateInterval = valRounded;
      updateIntervalLabel = plural('day', valRounded ~/ (24 * 60));
    } else {
      final int valRounded = (valInterpolated / (24 * 60)).floor() * 24 * 60;
      updateInterval = valRounded;
      updateIntervalLabel = plural('day', valRounded ~/ (24 * 60));
    }
  }

  void _commit(double value) {
    final settingsProvider = context.read<SettingsProvider>();
    settingsProvider.updateIntervalSliderVal = value;
    settingsProvider.updateInterval = updateInterval;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    processIntervalSliderValue(sliderVal);
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.read<SettingsProvider>();
    final rawSlider = Slider(
      value: sliderVal,
      max: updateIntervalNodes.length.toDouble(),
      divisions: updateIntervalNodes.length * 20,
      label: updateIntervalLabel,
      onChanged: (double value) {
        setState(() {
          sliderVal = value;
          processIntervalSliderValue(value);
        });
      },
      onChangeStart: (double value) {
        setState(() {
          showIntervalLabel = false;
        });
      },
      onChangeEnd: (double value) {
        setState(() {
          showIntervalLabel = true;
        });
        _commit(value);
      },
    );

    final Widget intervalSlider = settingsProvider.isTV
        ? Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: sliderVal <= 0
                    ? null
                    : () {
                        final newVal = (sliderVal - 1).clamp(
                          0.0,
                          updateIntervalNodes.length.toDouble(),
                        );
                        setState(() {
                          sliderVal = newVal;
                          processIntervalSliderValue(newVal);
                        });
                        _commit(newVal);
                      },
              ),
              Expanded(
                child: Text(updateIntervalLabel, textAlign: TextAlign.center),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: sliderVal >= updateIntervalNodes.length.toDouble()
                    ? null
                    : () {
                        final newVal = (sliderVal + 1).clamp(
                          0.0,
                          updateIntervalNodes.length.toDouble(),
                        );
                        setState(() {
                          sliderVal = newVal;
                          processIntervalSliderValue(newVal);
                        });
                        _commit(newVal);
                      },
              ),
            ],
          )
        : rawSlider;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        showIntervalLabel
            ? Text("${tr('bgUpdateCheckInterval')}: $updateIntervalLabel")
            : const SizedBox(height: 20),
        intervalSlider,
      ],
    );
  }
}

class _ExternalInstallerTile extends StatefulWidget {
  const _ExternalInstallerTile();

  @override
  State<_ExternalInstallerTile> createState() => _ExternalInstallerTileState();
}

class _ExternalInstallerTileState extends State<_ExternalInstallerTile> {
  Future<List<InstallerTarget>>? _targetsFuture;

  @override
  void initState() {
    super.initState();
    _targetsFuture = ExternalInstallerBridge.instance.listTargets();
  }

  InstallerTarget? _findCurrent(
    List<InstallerTarget> targets,
    String? pkg,
    String? activity,
  ) {
    if (pkg == null) return null;
    for (final target in targets) {
      if (target.package == pkg && target.activity == activity) return target;
    }
    return null;
  }

  Widget _targetIcon(InstallerTarget? target, {double size = 40}) {
    final icon = target?.icon;
    if (icon != null && icon.isNotEmpty) {
      return Image.memory(icon, width: size, height: size);
    }
    return Icon(Icons.extension_outlined, size: size);
  }

  Future<void> _choose(
    List<InstallerTarget> targets,
    SettingsProvider settingsProvider,
  ) async {
    if (targets.isEmpty) return;
    final grouped = <String, List<InstallerTarget>>{};
    for (final t in targets) {
      grouped.putIfAbsent(t.package, () => []).add(t);
    }
    // Deduplicate intents with identical activity names
    for (final entry in grouped.entries) {
      final seen = <String>{};
      entry.value.removeWhere((t) => !seen.add(t.activity));
    }
    grouped.removeWhere((_, v) => v.isEmpty);
    int expandedIndex = -1;
    final entries = grouped.entries.toList();
    final picked = await showDialog<InstallerTarget>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(tr('chooseExternalInstaller')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              for (var i = 0; i < entries.length; i++)
                ConnectedCard(
                  isFirst: true,
                  isLast: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        onTap: () {
                          final entry = entries[i];
                          if (entry.value.length == 1) {
                            Navigator.of(ctx).pop(entry.value.first);
                          } else {
                            setDialogState(() {
                              expandedIndex = expandedIndex == i ? -1 : i;
                            });
                          }
                        },
                        shape: RoundedSuperellipseBorder(
                          borderRadius: BorderRadius.circular(
                            connectedTileBigRadius,
                          ),
                        ),
                        leading: _targetIcon(entries[i].value.first, size: 36),
                        title: Text(
                          entries[i].value.first.label,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        trailing: entries[i].value.length > 1
                            ? AnimatedRotation(
                                turns: expandedIndex == i ? 0.5 : 0,
                                duration: ExpressiveMotion.short,
                                child: const Icon(Icons.expand_more),
                              )
                            : null,
                      ),
                      if (expandedIndex == i)
                        ...entries[i].value.map(
                          (target) => ListTile(
                            onTap: () => Navigator.of(ctx).pop(target),
                            shape: RoundedSuperellipseBorder(
                              borderRadius: BorderRadius.circular(
                                connectedTileBigRadius,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 2,
                            ),
                            minTileHeight: 36,
                            visualDensity: VisualDensity.compact,
                            title: Text(
                              _shortActivityName(target, entries[i].value),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    settingsProvider.externalInstallerPackage = picked.package;
    settingsProvider.externalInstallerComponent = picked.activity;
    if (mounted) setState(() {});
  }

  String _shortActivityName(
    InstallerTarget target,
    List<InstallerTarget> siblings,
  ) {
    final short = target.activity.split('.').last;
    final duplicates = siblings.where(
      (s) => s.activity.split('.').last == short && s != target,
    );
    if (duplicates.isNotEmpty) {
      return target.activity;
    }
    return short;
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.read<SettingsProvider>();
    final extPkg = context.select<SettingsProvider, String?>(
      (p) => p.externalInstallerPackage,
    );
    final extComp = context.select<SettingsProvider, String?>(
      (p) => p.externalInstallerComponent,
    );
    return FutureBuilder<List<InstallerTarget>>(
      future: _targetsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 8),
            leading: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(),
            ),
          );
        }
        final targets = snapshot.data ?? const <InstallerTarget>[];
        final current = _findCurrent(targets, extPkg, extComp);
        final intentCount = targets
            .where((t) => t.package == current?.package)
            .map((t) => t.activity)
            .toSet()
            .length;
        final subtitle = current != null
            ? intentCount > 1
                  ? '${current.label} · ${current.activity.split('.').last}'
                  : current.label
            : extPkg ?? tr('externalInstallerUnset');
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(connectedTileBigRadius),
          ),
          leading: _targetIcon(current),
          title: Text(tr('chooseExternalInstaller')),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.arrow_drop_down),
          onTap: () => _choose(targets, settingsProvider),
        );
      },
    );
  }
}

class _ThemeColorPickerTile extends StatelessWidget {
  final Future<bool> Function(SettingsProvider, ColorSwatch<Object>)
  showColorPickerDialog;
  final void Function(Color, SettingsProvider) handleColorPickerCancel;

  const _ThemeColorPickerTile({
    required this.showColorPickerDialog,
    required this.handleColorPickerCancel,
  });

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.read<SettingsProvider>();
    final themeColor = context.select<SettingsProvider, Color>(
      (p) => p.themeColor,
    );
    return CardTile(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(connectedTileBigRadius),
        ),
        title: Text(
          tr('selectX', args: [lowerCaseUnlessLang(tr('colour'), 'de')]),
        ),
        subtitle: Text(
          '${ColorTools.nameThatColor(themeColor)} '
          '(${ColorTools.materialNameAndCode(themeColor)})',
        ),
        trailing: ColorIndicator(
          width: 40,
          height: 40,
          borderRadius: 20,
          color: themeColor,
          onSelectFocus: false,
          onSelect: () async {
            final Color colorBeforeDialog = themeColor;
            if (!(await showColorPickerDialog(
              settingsProvider,
              obtainiumThemeColor.toSwatch(),
            ))) {
              handleColorPickerCancel(colorBeforeDialog, settingsProvider);
            }
          },
        ),
      ),
    );
  }
}

class _LocaleDropdown extends StatelessWidget {
  const _LocaleDropdown();

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.read<SettingsProvider>();
    final forcedLocale = context.select<SettingsProvider, Locale?>(
      (p) => p.forcedLocale,
    );
    return DropdownMenu<Locale?>(
      expandedInsets: EdgeInsets.zero,
      label: Text(tr('language')),
      initialSelection: forcedLocale,
      dropdownMenuEntries: [
        DropdownMenuEntry<Locale?>(value: null, label: tr('followSystem')),
        ...supportedLocales.map(
          (e) => DropdownMenuEntry<Locale?>(value: e.key, label: e.value),
        ),
      ],
      onSelected: (value) {
        settingsProvider.forcedLocale = value;
        if (value != null) {
          context.setLocale(value);
        } else {
          settingsProvider.resetLocaleSafe(context);
        }
      },
    );
  }
}

class _ColourSchemeDropdown extends StatelessWidget {
  const _ColourSchemeDropdown();

  @override
  Widget build(BuildContext context) {
    final colourSchemeMode = context.select<SettingsProvider, ColourSchemeMode>(
      (p) => p.colourSchemeMode,
    );
    final settingsProvider = context.read<SettingsProvider>();
    return DropdownMenu<ColourSchemeMode>(
      expandedInsets: EdgeInsets.zero,
      label: Text(tr('colourScheme')),
      initialSelection: colourSchemeMode,
      dropdownMenuEntries: [
        DropdownMenuEntry(
          value: ColourSchemeMode.standard,
          label: tr('standard'),
        ),
        DropdownMenuEntry(
          value: ColourSchemeMode.vibrant,
          label: tr('vibrant'),
        ),
        DropdownMenuEntry(
          value: ColourSchemeMode.expressive,
          label: tr('expressive'),
        ),
        DropdownMenuEntry(
          value: ColourSchemeMode.materialYou,
          label: tr('useMaterialYou'),
        ),
      ],
      onSelected: (value) {
        if (value != null) {
          settingsProvider.colourSchemeMode = value;
        }
      },
    );
  }
}
