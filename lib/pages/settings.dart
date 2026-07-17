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
import 'package:obtainium/main.dart';
import 'package:obtainium/pages/import_export.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/external_install_bridge.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/theme.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
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
    final logs = context.read<LogsProvider>();
    await logs.add(
      'Manual BG update check triggered from settings',
      level: LogLevel.info,
    );
    try {
      final taskId = 'manual_${DateTime.now().millisecondsSinceEpoch}';
      await bgUpdateCheck(taskId, null, forceAll: true);
      await logs.add(
        'Manual BG update check completed successfully',
        level: LogLevel.info,
      );
    } catch (e, stack) {
      unawaited(
        logs.add(
          'Manual BG update check crashed: $e\n$stack',
          level: LogLevel.error,
        ),
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
      unawaited(
        context.read<LogsProvider>().add(
          'Failed to get Android SDK info: $e',
          level: LogLevel.error,
        ),
      );
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
    } else {
      settingsProvider.installerMode = mode;
    }
  }

  Widget _caption(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall),
  );

  Widget _fieldTile(BuildContext context, Widget field) => ConnectedCard(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: field,
  );

  Widget _buildFooter(BuildContext context) => SliverToBoxAdapter(
    child: Column(
      children: [
        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              onPressed: () {
                unawaited(
                  launchUrlString(
                    context.read<SettingsProvider>().sourceUrl,
                    mode: LaunchMode.externalApplication,
                  ),
                );
              },
              icon: const Icon(Icons.code),
              tooltip: tr('appSource'),
            ),
            IconButton(
              onPressed: () {
                unawaited(
                  launchUrlString(
                    'https://wiki.obtainium.imranr.dev/',
                    mode: LaunchMode.externalApplication,
                  ),
                );
              },
              icon: const Icon(Icons.help_outline_rounded),
              tooltip: tr('wiki'),
            ),
            IconButton(
              onPressed: () {
                context.read<LogsProvider>().get().then((logs) {
                  if (!context.mounted) return;
                  if (logs.isEmpty) {
                    showMessage(ObtainiumError(tr('noLogs')), context);
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const LogsPage()),
                    );
                  }
                });
              },
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: tr('appLogs'),
            ),
          ],
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settingsProvider = context.watch<SettingsProvider>();
    final sourceProvider = context.read<SourceProvider>();
    final sdk = androidSdkInt ?? 0;

    final colorPicker = CardTile(
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
            final Color colorBeforeDialog = settingsProvider.themeColor;
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

    final themeModeControl = CardTile(
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

    final localeDropdown = DropdownMenu<Locale?>(
      expandedInsets: EdgeInsets.zero,
      label: Text(tr('language')),
      initialSelection: settingsProvider.forcedLocale,
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

    final colourSchemeDropdown = DropdownMenu<ColourSchemeMode>(
      expandedInsets: EdgeInsets.zero,
      label: Text(tr('colourScheme')),
      initialSelection: settingsProvider.colourSchemeMode,
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
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 20,
                      children: [
                        Section(
                          title: tr('obtainiumExport'),
                          children: const [ExportSection()],
                        ),
                        _buildUpdatesSection(context, showBgSection, sdk),
                        if (sourceSpecificForm != null)
                          Section(
                            title: tr('sourceSpecific'),
                            children: [sourceSpecificForm],
                          ),
                        _buildAppearanceSection(
                          context,
                          colorPicker,
                          themeModeControl,
                          sortDropdown,
                          orderControl,
                          localeDropdown,
                          colourSchemeDropdown,
                        ),
                        Section(
                          title: tr('categories'),
                          children: const [
                            CardTile(
                              padding: EdgeInsets.all(12),
                              child: CategoryManager(),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildUpdatesSection(
    BuildContext context,
    bool showBgSection,
    int sdk,
  ) {
    final settingsProvider = context.read<SettingsProvider>();
    return Section(
      title: tr('updates'),
      children: [
        const CardTile(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: _UpdateIntervalSliderTile(),
        ),
        if (showBgSection) ...[
          ToggleTile(
            label: tr('enableBackgroundUpdates'),
            value: settingsProvider.enableBackgroundUpdates,
            onChanged: (value) =>
                settingsProvider.enableBackgroundUpdates = value,
            helpWidgets: [
              Text(tr('backgroundUpdateReqsExplanation')),
              const SizedBox(height: 8),
              Text(tr('backgroundUpdateLimitsExplanation')),
            ],
          ),
          if (settingsProvider.enableBackgroundUpdates)
            ToggleTile(
              label: tr('bgUpdatesOnWiFiOnly'),
              value: settingsProvider.bgUpdatesOnWiFiOnly,
              onChanged: (value) =>
                  settingsProvider.bgUpdatesOnWiFiOnly = value,
            ),
          if (settingsProvider.enableBackgroundUpdates)
            ToggleTile(
              label: tr('bgUpdatesWhileChargingOnly'),
              value: settingsProvider.bgUpdatesWhileChargingOnly,
              onChanged: (value) =>
                  settingsProvider.bgUpdatesWhileChargingOnly = value,
            ),
          if (settingsProvider.enableBackgroundUpdates)
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
        ToggleTile(
          label: tr('checkOnStart'),
          value: settingsProvider.checkOnStart,
          onChanged: (value) => settingsProvider.checkOnStart = value,
        ),
        ToggleTile(
          label: tr('checkUpdateOnDetailPage'),
          value: settingsProvider.checkUpdateOnDetailPage,
          onChanged: (value) =>
              settingsProvider.checkUpdateOnDetailPage = value,
        ),
        ToggleTile(
          label: tr('onlyCheckInstalledOrTrackOnlyApps'),
          value: settingsProvider.onlyCheckInstalledOrTrackOnlyApps,
          onChanged: (value) =>
              settingsProvider.onlyCheckInstalledOrTrackOnlyApps = value,
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
        if (settingsProvider.installerMode == InstallerMode.shizuku.name)
          ToggleTile(
            label: tr('shizukuPretendToBeGooglePlay'),
            value: settingsProvider.shizukuPretendToBeGooglePlay,
            onChanged: (value) =>
                settingsProvider.shizukuPretendToBeGooglePlay = value,
          ),
        if (settingsProvider.installerMode == InstallerMode.external.name)
          const CardTile(child: _ExternalInstallerTile()),
      ],
    );
  }

  Widget _buildAppearanceSection(
    BuildContext context,
    Widget colorPicker,
    Widget themeModeControl,
    Widget sortDropdown,
    Widget orderControl,
    Widget localeDropdown,
    Widget colourSchemeDropdown,
  ) {
    final settingsProvider = context.read<SettingsProvider>();
    final sdk = androidSdkInt ?? 0;
    return Section(
      title: tr('appearance'),
      children: [
        themeModeControl,
        if (settingsProvider.theme == ThemeSettings.system &&
            (androidSdkInt ?? 30) < 29)
          _caption(context, tr('followSystemThemeExplanation')),
        if (settingsProvider.theme != ThemeSettings.light)
          ToggleTile(
            label: tr('useBlackTheme'),
            value: settingsProvider.useBlackTheme,
            onChanged: (value) => settingsProvider.useBlackTheme = value,
          ),
        _fieldTile(context, colourSchemeDropdown),
        if (settingsProvider.colourSchemeMode != ColourSchemeMode.materialYou)
          colorPicker,
        _fieldTile(context, sortDropdown),
        orderControl,
        _fieldTile(context, localeDropdown),
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
              DropdownMenuEntry(
                value: GroupByMode.none.name,
                label: tr('none'),
              ),
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
              DropdownMenuEntry(
                value: ActionBannerMode.none,
                label: tr('none'),
              ),
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
      ],
    );
  }
}

extension on Color {
  ColorSwatch<Object> toSwatch() => ColorTools.createPrimarySwatch(this);
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

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  static const List<int> _dayOptions = [7, 5, 4, 3, 2, 1];

  final ScrollController _scrollController = ScrollController();
  List<Log> _logs = [];
  int _days = _dayOptions.first;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs(_days);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs(int days) async {
    setState(() => _loading = true);
    final value = await context.read<LogsProvider>().get(
      after: DateTime.now().subtract(Duration(days: days)),
    );
    if (!mounted) return;
    setState(() {
      _days = days;
      _logs = value;
      _loading = false;
    });
  }

  String _joinLogs() => _logs.map((e) => e.toString()).join('\n\n');

  void _scrollTo(double offset) {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      offset,
      duration: ExpressiveMotion.medium,
      curve: ExpressiveMotion.emphasized,
    );
  }

  void _scrollToTop() => _scrollTo(0);

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollTo(_scrollController.position.maxScrollExtent);
  }

  Future<void> _clearLogs() async {
    final logsProvider = context.read<LogsProvider>();
    final cont =
        (await showDialog<Map<String, dynamic>?>(
          context: context,
          builder: (BuildContext ctx) {
            return GeneratedFormModal(
              title: tr('appLogs'),
              items: const [],
              initValid: true,
              message: tr('removeFromObtainium'),
            );
          },
        )) !=
        null;
    if (!cont) return;
    await logsProvider.clear();
    if (!mounted) return;
    await _loadLogs(_days);
  }

  void _shareLogs() {
    unawaited(
      SharePlus.instance.share(
        ShareParams(text: _joinLogs(), subject: tr('appLogs')),
      ),
    );
  }

  Color _levelColor(BuildContext context, LogLevel level) {
    final cs = Theme.of(context).colorScheme;
    return switch (level) {
      LogLevel.error => cs.error,
      LogLevel.warning => cs.tertiary,
      LogLevel.debug => cs.onSurfaceVariant,
      LogLevel.info => cs.onSurface,
    };
  }

  Widget _logTile(Log log) {
    final color = _levelColor(context, log.level);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${log.timestamp.toString()} · ${log.level.name}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color.withValues(alpha: 0.8),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            log.message,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _toolbarDivider(ColorScheme cs) => Container(
    width: 1,
    height: 24,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: cs.outlineVariant,
  );

  /// A single M3 Expressive floating toolbar that consolidates navigation
  /// (jump to top/bottom) and actions (filter, share, clear) into one pill,
  /// rather than scattering them across the app bar and multiple FABs.
  Widget _buildFloatingToolbar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasLogs = _logs.isNotEmpty;
    return Material(
      elevation: 3,
      color: cs.surfaceContainer,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: hasLogs ? _scrollToTop : null,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            IconButton(
              onPressed: hasLogs ? _scrollToBottom : null,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            _toolbarDivider(cs),
            PopupMenuButton<int>(
              icon: const Icon(Icons.filter_list_rounded),
              tooltip: tr('filter'),
              initialValue: _days,
              onSelected: _loadLogs,
              itemBuilder: (context) => _dayOptions
                  .map(
                    (e) => CheckedPopupMenuItem<int>(
                      value: e,
                      checked: e == _days,
                      child: Text(plural('day', e)),
                    ),
                  )
                  .toList(),
            ),
            IconButton(
              onPressed: hasLogs ? _shareLogs : null,
              icon: const Icon(Icons.share_rounded),
              tooltip: tr('share'),
            ),
            IconButton(
              onPressed: hasLogs ? _clearLogs : null,
              color: cs.error,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: tr('remove'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          SelectionArea(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
                  pinned: true,
                  automaticallyImplyLeading: false,
                  title: Text(tr('appLogs')),
                ),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_logs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.bug_report_outlined,
                      message: tr('noLogs'),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: _logs.length,
                    itemBuilder: (context, index) => _logTile(_logs[index]),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          ),
          // Docked in a Stack rather than the Scaffold's floatingActionButton
          // slot so it doesn't play the FAB scale/rotate entrance animation.
          if (!_loading)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _buildFloatingToolbar(context),
                  ),
                ),
              ),
            ),
        ],
      ),
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

  InstallerTarget? _current(
    List<InstallerTarget> targets,
    SettingsProvider settingsProvider,
  ) {
    final pkg = settingsProvider.externalInstallerPackage;
    if (pkg == null) return null;
    final activity = settingsProvider.externalInstallerComponent;
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
    final settingsProvider = context.watch<SettingsProvider>();
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
            title: Text('…'),
          );
        }
        final targets = snapshot.data ?? const <InstallerTarget>[];
        final current = _current(targets, settingsProvider);
        final intentCount = targets
            .where((t) => t.package == current?.package)
            .map((t) => t.activity)
            .toSet()
            .length;
        final subtitle = current != null
            ? intentCount > 1
                  ? '${current.label} · ${current.activity.split('.').last}'
                  : current.label
            : settingsProvider.externalInstallerPackage ??
                  tr('externalInstallerUnset');
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
