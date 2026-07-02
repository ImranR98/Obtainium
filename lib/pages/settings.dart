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
import 'package:obtainium/components/settings_widgets.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/pages/import_export.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/external_install_bridge.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
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
  final SourceProvider sourceProvider = SourceProvider();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sp = context.read<SettingsProvider>();
      if (sp.prefs == null) sp.initializeSettings();
    });
    initAndroidSdk();
  }

  Future<void> initAndroidSdk() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      androidSdkInt = info.version.sdkInt;
      if (mounted) setState(() {});
    } catch (e) {
      unawaited(
        LogsProvider().add(
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
        tr('selectX', args: [tr('colour').toLowerCase()]),
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
  ) {
    if (mode == InstallerMode.shizuku.name) {
      ShizukuApkInstaller()
          .checkPermission()
          .then((resCode) {
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

  Widget _fieldTile(BuildContext context, Widget field) => SettingsTile(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    padding: EdgeInsets.zero,
    child: DropdownMenuTheme(
      data: DropdownMenuThemeData(
        inputDecorationTheme: const InputDecorationThemeData(
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        menuStyle: MenuStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      child: field,
    ),
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
                    'https://wiki.obtainium.page/',
                    mode: LaunchMode.externalApplication,
                  ),
                );
              },
              icon: const Icon(Icons.help_outline_rounded),
              tooltip: tr('wiki'),
            ),
            IconButton(
              onPressed: () {
                unawaited(
                  launchUrlString(
                    'https://apps.obtainium.page/',
                    mode: LaunchMode.externalApplication,
                  ),
                );
              },
              icon: const Icon(Icons.apps_rounded),
              tooltip: tr('crowdsourcedConfigsLabel'),
            ),
            IconButton(
              onPressed: () {
                context.read<LogsProvider>().get().then((logs) {
                  if (!context.mounted) return;
                  if (logs.isEmpty) {
                    showMessage(ObtainiumError(tr('noLogs')), context);
                  } else {
                    showDialog(
                      context: context,
                      builder: (BuildContext ctx) {
                        return const LogsDialog();
                      },
                    );
                  }
                });
              },
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: tr('appLogs'),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settingsProvider = context.watch<SettingsProvider>();
    final sdk = androidSdkInt ?? 0;

    final colorPicker = SettingsTile(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('selectX', args: [tr('colour').toLowerCase()])),
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

    final themeModeControl = SettingsTile(
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

    final orderControl = SettingsTile(
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: settingsProvider.prefs == null
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 20,
                      children: [
                        SettingsGroup(
                          title: tr('obtainiumExport'),
                          children: const [ExportSection()],
                        ),
                        _buildUpdatesSection(context, showBgSection, sdk),
                        if (sourceSpecificForm != null)
                          SettingsGroup(
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
                        SettingsGroup(
                          title: tr('categories'),
                          children: const [
                            SettingsTile(
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
    return SettingsGroup(
      title: tr('updates'),
      children: [
        const SettingsTile(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: _UpdateIntervalSliderTile(),
        ),
        if (showBgSection) ...[
          SettingsToggleRow(
            label: tr('foregroundServiceExplanation'),
            value: settingsProvider.useFGService,
            onChanged: (value) => settingsProvider.useFGService = value,
          ),
          SettingsToggleRow(
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
            SettingsToggleRow(
              label: tr('bgUpdatesOnWiFiOnly'),
              value: settingsProvider.bgUpdatesOnWiFiOnly,
              onChanged: (value) =>
                  settingsProvider.bgUpdatesOnWiFiOnly = value,
            ),
          if (settingsProvider.enableBackgroundUpdates)
            SettingsToggleRow(
              label: tr('bgUpdatesWhileChargingOnly'),
              value: settingsProvider.bgUpdatesWhileChargingOnly,
              onChanged: (value) =>
                  settingsProvider.bgUpdatesWhileChargingOnly = value,
            ),
        ],
        SettingsToggleRow(
          label: tr('checkOnStart'),
          value: settingsProvider.checkOnStart,
          onChanged: (value) => settingsProvider.checkOnStart = value,
        ),
        SettingsToggleRow(
          label: tr('checkUpdateOnDetailPage'),
          value: settingsProvider.checkUpdateOnDetailPage,
          onChanged: (value) =>
              settingsProvider.checkUpdateOnDetailPage = value,
        ),
        SettingsToggleRow(
          label: tr('onlyCheckInstalledOrTrackOnlyApps'),
          value: settingsProvider.onlyCheckInstalledOrTrackOnlyApps,
          onChanged: (value) =>
              settingsProvider.onlyCheckInstalledOrTrackOnlyApps = value,
        ),
        SettingsToggleRow(
          label: tr('removeOnExternalUninstall'),
          value: settingsProvider.removeOnExternalUninstall,
          onChanged: (value) =>
              settingsProvider.removeOnExternalUninstall = value,
        ),
        SettingsToggleRow(
          label: tr('includePrereleasesByDefault'),
          value: settingsProvider.includePrereleasesByDefault,
          onChanged: (value) =>
              settingsProvider.includePrereleasesByDefault = value,
        ),
        SettingsToggleRow(
          label: tr('tactileFeedbackEnabled'),
          value: settingsProvider.tactileFeedbackEnabled,
          onChanged: (value) => settingsProvider.tactileFeedbackEnabled = value,
        ),
        SettingsToggleRow(
          label: tr('showBatteryOptimizationPrompt'),
          value: settingsProvider.showBatteryOptimizationPrompt,
          onChanged: (value) =>
              settingsProvider.showBatteryOptimizationPrompt = value,
        ),
        SettingsToggleRow(
          label: tr('showAppDowngradeError'),
          value: settingsProvider.showAppDowngradeError,
          onChanged: (value) => settingsProvider.showAppDowngradeError = value,
        ),
        SettingsToggleRow(
          label: tr('parallelDownloads'),
          value: settingsProvider.parallelDownloads,
          onChanged: (value) => settingsProvider.parallelDownloads = value,
        ),
        SettingsToggleRow(
          label: tr('beforeNewInstallsShareToAppVerifier'),
          value: settingsProvider.beforeNewInstallsShareToAppVerifier,
          onChanged: (value) =>
              settingsProvider.beforeNewInstallsShareToAppVerifier = value,
          subtitle: LinkText(
            text: tr('about'),
            url: 'https://github.com/soupslurpr/AppVerifier',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        SettingsTile(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(tr('installMethod')),
              ),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: InstallerMode.system.name,
                      label: Text(tr('installMethodSystem')),
                    ),
                    ButtonSegment(
                      value: InstallerMode.shizuku.name,
                      label: Text(tr('installMethodShizuku')),
                    ),
                    ButtonSegment(
                      value: InstallerMode.external.name,
                      label: Text(tr('installMethodExternal')),
                    ),
                  ],
                  selected: {settingsProvider.installerMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => handleInstallerModeChange(
                    settingsProvider,
                    selection.first,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (settingsProvider.installerMode == InstallerMode.shizuku.name)
          SettingsToggleRow(
            label: tr('shizukuPretendToBeGooglePlay'),
            value: settingsProvider.shizukuPretendToBeGooglePlay,
            onChanged: (value) =>
                settingsProvider.shizukuPretendToBeGooglePlay = value,
          ),
        if (settingsProvider.installerMode == InstallerMode.external.name)
          const SettingsTile(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: _ExternalInstallerTile(),
          ),
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
    return SettingsGroup(
      title: tr('appearance'),
      children: [
        themeModeControl,
        if (settingsProvider.theme == ThemeSettings.system &&
            (androidSdkInt ?? 30) < 29)
          _caption(context, tr('followSystemThemeExplanation')),
        if (settingsProvider.theme != ThemeSettings.light)
          SettingsToggleRow(
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
          SettingsToggleRow(
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
        SettingsToggleRow(
          label: tr('showWebInAppView'),
          value: settingsProvider.showAppWebpage,
          onChanged: (value) => settingsProvider.showAppWebpage = value,
        ),
        SettingsToggleRow(
          label: tr('pinUpdates'),
          value: settingsProvider.pinUpdates,
          onChanged: (value) => settingsProvider.pinUpdates = value,
        ),
        SettingsToggleRow(
          label: tr('moveNonInstalledAppsToBottom'),
          value: settingsProvider.buryNonInstalled,
          onChanged: (value) => settingsProvider.buryNonInstalled = value,
        ),
        SettingsToggleRow(
          label: tr('groupByCategory'),
          value: settingsProvider.groupByCategory,
          onChanged: (value) => settingsProvider.groupByCategory = value,
        ),
        SettingsToggleRow(
          label: tr('dontShowTrackOnlyWarnings'),
          value: settingsProvider.hideTrackOnlyWarning,
          onChanged: (value) => settingsProvider.hideTrackOnlyWarning = value,
        ),
        SettingsToggleRow(
          label: tr('dontShowAPKOriginWarnings'),
          value: settingsProvider.hideAPKOriginWarning,
          onChanged: (value) => settingsProvider.hideAPKOriginWarning = value,
        ),
        SettingsToggleRow(
          label: tr('disablePageTransitions'),
          value: settingsProvider.disablePageTransitions,
          onChanged: (value) => settingsProvider.disablePageTransitions = value,
        ),
        SettingsToggleRow(
          label: tr('reversePageTransitions'),
          value: settingsProvider.reversePageTransitions,
          onChanged: settingsProvider.disablePageTransitions
              ? null
              : (value) => settingsProvider.reversePageTransitions = value,
        ),
        SettingsToggleRow(
          label: tr('highlightTouchTargets'),
          value: settingsProvider.highlightTouchTargets,
          onChanged: (value) => settingsProvider.highlightTouchTargets = value,
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

class LogsDialog extends StatefulWidget {
  const LogsDialog({super.key});

  @override
  State<LogsDialog> createState() => _LogsDialogState();
}

class _LogsDialogState extends State<LogsDialog> {
  String? logString;
  List<int> days = [7, 5, 4, 3, 2, 1];

  @override
  void initState() {
    super.initState();
    filterLogs(days.first);
  }

  void filterLogs(int days) {
    context
        .read<LogsProvider>()
        .get(after: DateTime.now().subtract(Duration(days: days)))
        .then((value) {
          if (!mounted) return;
          setState(() {
            final String l = value.map((e) => e.toString()).join('\n\n');
            logString = l.isNotEmpty ? l : tr('noLogs');
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(tr('appLogs')),
      content: Column(
        children: [
          DropdownMenu(
            initialSelection: days.first,
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: days
                .map(
                  (e) => DropdownMenuEntry(value: e, label: plural('day', e)),
                )
                .toList(),
            onSelected: (d) {
              filterLogs(d ?? 7);
            },
          ),
          const SizedBox(height: 32),
          Text(logString ?? ''),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () async {
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
            if (cont) {
              unawaited(logsProvider.clear());
              if (context.mounted) Navigator.of(context).pop();
            }
          },
          child: Text(tr('remove')),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(tr('close')),
        ),
        FilledButton.tonal(
          onPressed: () {
            unawaited(
              SharePlus.instance.share(
                ShareParams(text: logString ?? '', subject: tr('appLogs')),
              ),
            );
            Navigator.of(context).pop();
          },
          child: Text(tr('share')),
        ),
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

  InstallerTarget? _current(
    List<InstallerTarget> targets,
    SettingsProvider settingsProvider,
  ) {
    final pkg = settingsProvider.externalInstallerPackage;
    if (pkg == null) return null;
    for (final target in targets) {
      if (target.package == pkg) return target;
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
    final picked = await showDialog<InstallerTarget>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('chooseExternalInstaller')),
        children: [
          for (final target in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(target),
              child: Row(
                children: [
                  _targetIcon(target, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(target.label),
                        Text(
                          target.package,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    settingsProvider.externalInstallerPackage = picked.package;
    settingsProvider.externalInstallerComponent = picked.activity;
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
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('…'),
          );
        }
        final targets = snapshot.data ?? const <InstallerTarget>[];
        final current = _current(targets, settingsProvider);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: _targetIcon(current),
          title: Text(tr('chooseExternalInstaller')),
          subtitle: Text(
            current?.label ??
                settingsProvider.externalInstallerPackage ??
                tr('externalInstallerUnset'),
          ),
          trailing: const Icon(Icons.arrow_drop_down),
          onTap: () => _choose(targets, settingsProvider),
        );
      },
    );
  }
}
