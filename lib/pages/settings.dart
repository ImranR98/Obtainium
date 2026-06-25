import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:equations/equations.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/components/settings_widgets.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/pages/import_export.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/native_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shizuku_apk_installer/shizuku_apk_installer.dart';
import 'package:url_launcher/url_launcher_string.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<int> updateIntervalNodes = [
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
  late SplineInterpolation updateIntervalInterpolator; // 🤓
  String updateIntervalLabel = tr('neverManualOnly');
  bool showIntervalLabel = true;
  int? androidSdkInt;
  final Map<ColorSwatch<Object>, String> colorsNameMap =
      <ColorSwatch<Object>, String>{
        ColorTools.createPrimarySwatch(obtainiumThemeColor): 'Obtainium',
      };

  @override
  void initState() {
    super.initState();
    DeviceInfoPlugin().androidInfo.then((info) {
      if (mounted) {
        setState(() {
          androidSdkInt = info.version.sdkInt;
        });
      }
    });
  }

  void initUpdateIntervalInterpolator() {
    List<InterpolationNode> nodes = [];
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
      int valRounded = (valInterpolated / 15).floor() * 15;
      updateInterval = valRounded;
      updateIntervalLabel = plural('hour', valRounded ~/ 60);
      int mins = valRounded % 60;
      if (mins != 0) updateIntervalLabel += " ${plural('minute', mins)}";
    } else if (valInterpolated < 24 * 60) {
      int valRounded = (valInterpolated / 30).floor() * 30;
      updateInterval = valRounded;
      updateIntervalLabel = plural('hour', valRounded / 60);
    } else if (valInterpolated < 7 * 24 * 60) {
      int valRounded = (valInterpolated / (12 * 60)).floor() * 12 * 60;
      updateInterval = valRounded;
      updateIntervalLabel = plural('day', valRounded / (24 * 60));
    } else {
      int valRounded = (valInterpolated / (24 * 60)).floor() * 24 * 60;
      updateInterval = valRounded;
      updateIntervalLabel = plural('day', valRounded ~/ (24 * 60));
    }
  }

  @override
  Widget build(BuildContext context) {
    SettingsProvider settingsProvider = context.watch<SettingsProvider>();
    SourceProvider sourceProvider = SourceProvider();
    if (settingsProvider.prefs == null) settingsProvider.initializeSettings();
    initUpdateIntervalInterpolator();
    processIntervalSliderValue(settingsProvider.updateIntervalSliderVal);
    final sdk = androidSdkInt ?? 0;

    Widget caption(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );

    // Wraps a dropdown/field in a distinct-tone tile so it stands out from the
    // surrounding control tiles while still joining the positional-radii run.
    Widget fieldTile(Widget field) => SettingsTile(
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

    Future<bool> colorPickerDialog() async {
      return ColorPicker(
        color: settingsProvider.themeColor,
        onColorChanged: (Color color) =>
            setState(() => settingsProvider.themeColor = color),
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

    var colorPicker = SettingsTile(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('selectX', args: [tr('colour').toLowerCase()])),
        subtitle: Text(
          "${ColorTools.nameThatColor(settingsProvider.themeColor)} "
          "(${ColorTools.materialNameAndCode(settingsProvider.themeColor, colorSwatchNameMap: colorsNameMap)})",
        ),
        trailing: ColorIndicator(
          width: 40,
          height: 40,
          borderRadius: 20,
          color: settingsProvider.themeColor,
          onSelectFocus: false,
          onSelect: () async {
            final Color colorBeforeDialog = settingsProvider.themeColor;
            if (!(await colorPickerDialog())) {
              setState(() {
                settingsProvider.themeColor = colorBeforeDialog;
              });
            }
          },
        ),
      ),
    );

    // Expressive segmented control for theme mode (icon-only with tooltips).
    var themeModeControl = SettingsTile(
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

    var sortDropdown = DropdownMenu<SortColumnSettings>(
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
        DropdownMenuEntry(value: SortColumnSettings.added, label: tr('asAdded')),
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

    var orderControl = SettingsTile(
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

    var localeDropdown = DropdownMenu<Locale?>(
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

    var colourSchemeDropdown = DropdownMenu<ColourSchemeMode>(
      expandedInsets: EdgeInsets.zero,
      label: Text(tr('colourScheme')),
      initialSelection: settingsProvider.colourSchemeMode,
      dropdownMenuEntries: [
        DropdownMenuEntry(
          value: ColourSchemeMode.standard,
          label: tr('standard'),
        ),
        DropdownMenuEntry(value: ColourSchemeMode.vibrant, label: tr('vibrant')),
        DropdownMenuEntry(
          value: ColourSchemeMode.expressive,
          label: tr('expressive'),
        ),
        if (sdk >= 31)
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

    final rawSlider = Slider(
      value: settingsProvider.updateIntervalSliderVal,
      max: updateIntervalNodes.length.toDouble(),
      divisions: updateIntervalNodes.length * 20,
      label: updateIntervalLabel,
      onChanged: (double value) {
        setState(() {
          settingsProvider.updateIntervalSliderVal = value;
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
          settingsProvider.updateInterval = updateInterval;
        });
      },
    );

    final Widget intervalSlider = settingsProvider.isTV
        ? Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: settingsProvider.updateIntervalSliderVal <= 0
                    ? null
                    : () {
                        setState(() {
                          final newVal =
                              (settingsProvider.updateIntervalSliderVal - 1)
                                  .clamp(
                                    0.0,
                                    updateIntervalNodes.length.toDouble(),
                                  );
                          settingsProvider.updateIntervalSliderVal = newVal;
                          processIntervalSliderValue(newVal);
                          settingsProvider.updateInterval = updateInterval;
                        });
                      },
              ),
              Expanded(
                child: Text(updateIntervalLabel, textAlign: TextAlign.center),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed:
                    settingsProvider.updateIntervalSliderVal >=
                        updateIntervalNodes.length.toDouble()
                    ? null
                    : () {
                        setState(() {
                          final newVal =
                              (settingsProvider.updateIntervalSliderVal + 1)
                                  .clamp(
                                    0.0,
                                    updateIntervalNodes.length.toDouble(),
                                  );
                          settingsProvider.updateIntervalSliderVal = newVal;
                          processIntervalSliderValue(newVal);
                          settingsProvider.updateInterval = updateInterval;
                        });
                      },
              ),
            ],
          )
        : rawSlider;

    var intervalSliderTile = SettingsTile(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          showIntervalLabel
              ? Text("${tr('bgUpdateCheckInterval')}: $updateIntervalLabel")
              : const SizedBox(height: 20),
          intervalSlider,
        ],
      ),
    );

    // Merge every source's config items into a single form so they read as one
    // connected block (rather than one disjointed block per source).
    var allSourceConfigItems = sourceProvider.sources
        .expand((e) => e.sourceConfigSettingFormItems)
        .toList();
    for (var item in allSourceConfigItems) {
      if (item is GeneratedFormSwitch) {
        item.defaultValue = settingsProvider.getSettingBool(item.key);
      } else {
        item.defaultValue = settingsProvider.getSettingString(item.key);
      }
    }
    Widget? sourceSpecificForm = allSourceConfigItems.isEmpty
        ? null
        : GeneratedForm(
            tileMode: true,
            items: allSourceConfigItems.map((e) => [e]).toList(),
            onValueChanges: (values, valid, isBuilding) {
              if (valid && !isBuilding) {
                values.forEach((key, value) {
                  var formItem = allSourceConfigItems
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

    bool showBgSection =
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
                  ? const SizedBox()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 20,
                      children: [
                        SettingsTile(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            leading: const Icon(Icons.import_export_outlined),
                            title: Text(tr('importExport')),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ImportExportPage(),
                                ),
                              );
                            },
                          ),
                        ),
                        SettingsGroup(
                          title: tr('updates'),
                          children: [
                            intervalSliderTile,
                            if (showBgSection) ...[
                              SettingsToggleRow(
                                label: tr('foregroundServiceExplanation'),
                                value: settingsProvider.useFGService,
                                onChanged: (value) {
                                  settingsProvider.useFGService = value;
                                },
                              ),
                              SettingsToggleRow(
                                label: tr('enableBackgroundUpdates'),
                                value: settingsProvider.enableBackgroundUpdates,
                                onChanged: (value) {
                                  settingsProvider.enableBackgroundUpdates =
                                      value;
                                },
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
                                  onChanged: (value) {
                                    settingsProvider.bgUpdatesOnWiFiOnly = value;
                                  },
                                ),
                              if (settingsProvider.enableBackgroundUpdates)
                                SettingsToggleRow(
                                  label: tr('bgUpdatesWhileChargingOnly'),
                                  value: settingsProvider
                                      .bgUpdatesWhileChargingOnly,
                                  onChanged: (value) {
                                    settingsProvider.bgUpdatesWhileChargingOnly =
                                        value;
                                  },
                                ),
                            ],
                            SettingsToggleRow(
                              label: tr('checkOnStart'),
                              value: settingsProvider.checkOnStart,
                              onChanged: (value) {
                                settingsProvider.checkOnStart = value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('checkUpdateOnDetailPage'),
                              value: settingsProvider.checkUpdateOnDetailPage,
                              onChanged: (value) {
                                settingsProvider.checkUpdateOnDetailPage = value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('onlyCheckInstalledOrTrackOnlyApps'),
                              value: settingsProvider
                                  .onlyCheckInstalledOrTrackOnlyApps,
                              onChanged: (value) {
                                settingsProvider
                                        .onlyCheckInstalledOrTrackOnlyApps =
                                    value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('removeOnExternalUninstall'),
                              value: settingsProvider.removeOnExternalUninstall,
                              onChanged: (value) {
                                settingsProvider.removeOnExternalUninstall =
                                    value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('includePrereleasesByDefault'),
                              value:
                                  settingsProvider.includePrereleasesByDefault,
                              onChanged: (value) {
                                settingsProvider.includePrereleasesByDefault =
                                    value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('tactileFeedbackEnabled'),
                              value: settingsProvider.tactileFeedbackEnabled,
                              onChanged: (value) {
                                settingsProvider.tactileFeedbackEnabled = value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('showBatteryOptimizationPrompt'),
                              value:
                                  settingsProvider.showBatteryOptimizationPrompt,
                              onChanged: (value) {
                                settingsProvider.showBatteryOptimizationPrompt =
                                    value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('showAppDowngradeError'),
                              value: settingsProvider.showAppDowngradeError,
                              onChanged: (value) {
                                settingsProvider.showAppDowngradeError = value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('parallelDownloads'),
                              value: settingsProvider.parallelDownloads,
                              onChanged: (value) {
                                settingsProvider.parallelDownloads = value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('beforeNewInstallsShareToAppVerifier'),
                              value: settingsProvider
                                  .beforeNewInstallsShareToAppVerifier,
                              onChanged: (value) {
                                settingsProvider
                                        .beforeNewInstallsShareToAppVerifier =
                                    value;
                              },
                              subtitle: InkWell(
                                onTap: () {
                                  launchUrlString(
                                    'https://github.com/soupslurpr/AppVerifier',
                                    mode: LaunchMode.externalApplication,
                                  );
                                },
                                child: Text(
                                  tr('about'),
                                  style: const TextStyle(
                                    decoration: TextDecoration.underline,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            SettingsToggleRow(
                              label: tr('useShizuku'),
                              value: settingsProvider.useShizuku,
                              onChanged: (useShizuku) {
                                if (useShizuku) {
                                  ShizukuApkInstaller().checkPermission().then((
                                    resCode,
                                  ) {
                                    settingsProvider.useShizuku = resCode!
                                        .startsWith('granted');
                                    switch (resCode) {
                                      case 'services_not_found':
                                        showError(
                                          ObtainiumError(
                                            tr('shizukuBinderNotFound'),
                                          ),
                                          context,
                                        );
                                      case 'old_shizuku':
                                        showError(
                                          ObtainiumError(tr('shizukuOld')),
                                          context,
                                        );
                                      case 'old_android_with_adb':
                                        showError(
                                          ObtainiumError(
                                            tr('shizukuOldAndroidWithADB'),
                                          ),
                                          context,
                                        );
                                      case 'denied':
                                        showError(
                                          ObtainiumError(tr('cancelled')),
                                          context,
                                        );
                                    }
                                  });
                                } else {
                                  settingsProvider.useShizuku = false;
                                }
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('shizukuPretendToBeGooglePlay'),
                              value:
                                  settingsProvider.shizukuPretendToBeGooglePlay,
                              onChanged: (value) {
                                settingsProvider.shizukuPretendToBeGooglePlay =
                                    value;
                              },
                            ),
                          ],
                        ),
                        if (sourceSpecificForm != null)
                          SettingsGroup(
                            title: tr('sourceSpecific'),
                            children: [sourceSpecificForm],
                          ),
                        SettingsGroup(
                          title: tr('appearance'),
                          children: [
                            themeModeControl,
                            if (settingsProvider.theme == ThemeSettings.system &&
                                (androidSdkInt ?? 30) < 29)
                              caption(tr('followSystemThemeExplanation')),
                            if (settingsProvider.theme != ThemeSettings.light)
                              SettingsToggleRow(
                                label: tr('useBlackTheme'),
                                value: settingsProvider.useBlackTheme,
                                onChanged: (value) {
                                  settingsProvider.useBlackTheme = value;
                                },
                              ),
                            fieldTile(colourSchemeDropdown),
                            if (settingsProvider.colourSchemeMode !=
                                ColourSchemeMode.materialYou)
                              colorPicker,
                            fieldTile(sortDropdown),
                            orderControl,
                            fieldTile(localeDropdown),
                            if (sdk >= 29)
                              SettingsToggleRow(
                                label: tr('useSystemFont'),
                                value: settingsProvider.useSystemFont,
                                onChanged: (useSystemFont) {
                                  if (useSystemFont) {
                                    NativeFeatures.loadSystemFont().then((val) {
                                      settingsProvider.useSystemFont = true;
                                    });
                                  } else {
                                    settingsProvider.useSystemFont = false;
                                  }
                                },
                              ),
                            SettingsToggleRow(
                              label: tr('showWebInAppView'),
                              value: settingsProvider.showAppWebpage,
                              onChanged: (value) {
                                settingsProvider.showAppWebpage = value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('pinUpdates'),
                              value: settingsProvider.pinUpdates,
                              onChanged: (value) {
                                settingsProvider.pinUpdates = value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('moveNonInstalledAppsToBottom'),
                              value: settingsProvider.buryNonInstalled,
                              onChanged: (value) {
                                settingsProvider.buryNonInstalled = value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('groupByCategory'),
                              value: settingsProvider.groupByCategory,
                              onChanged: (value) {
                                settingsProvider.groupByCategory = value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('dontShowTrackOnlyWarnings'),
                              value: settingsProvider.hideTrackOnlyWarning,
                              onChanged: (value) {
                                settingsProvider.hideTrackOnlyWarning = value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('dontShowAPKOriginWarnings'),
                              value: settingsProvider.hideAPKOriginWarning,
                              onChanged: (value) {
                                settingsProvider.hideAPKOriginWarning = value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('disablePageTransitions'),
                              value: settingsProvider.disablePageTransitions,
                              onChanged: (value) {
                                settingsProvider.disablePageTransitions = value;
                              },
                            ),
                            SettingsToggleRow(
                              label: tr('reversePageTransitions'),
                              value: settingsProvider.reversePageTransitions,
                              onChanged: settingsProvider.disablePageTransitions
                                  ? null
                                  : (value) {
                                      settingsProvider.reversePageTransitions =
                                          value;
                                    },
                            ),
                            SettingsToggleRow(
                              label: tr('highlightTouchTargets'),
                              value: settingsProvider.highlightTouchTargets,
                              onChanged: (value) {
                                settingsProvider.highlightTouchTargets = value;
                              },
                            ),
                          ],
                        ),
                        SettingsGroup(
                          title: tr('categories'),
                          children: const [
                            SettingsTile(
                              padding: EdgeInsets.all(12),
                              child: CategoryEditorSelector(
                                showLabelWhenNotEmpty: false,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      onPressed: () {
                        launchUrlString(
                          settingsProvider.sourceUrl,
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      icon: const Icon(Icons.code),
                      tooltip: tr('appSource'),
                    ),
                    IconButton(
                      onPressed: () {
                        launchUrlString(
                          'https://wiki.obtainium.page/',
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      icon: const Icon(Icons.help_outline_rounded),
                      tooltip: tr('wiki'),
                    ),
                    IconButton(
                      onPressed: () {
                        launchUrlString(
                          'https://apps.obtainium.page/',
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      icon: const Icon(Icons.apps_rounded),
                      tooltip: tr('crowdsourcedConfigsLabel'),
                    ),
                    IconButton(
                      onPressed: () {
                        context.read<LogsProvider>().get().then((logs) {
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
          ),
        ],
      ),
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
  Widget build(BuildContext context) {
    var logsProvider = context.read<LogsProvider>();
    void filterLogs(int days) {
      logsProvider
          .get(after: DateTime.now().subtract(Duration(days: days)))
          .then((value) {
            setState(() {
              String l = value.map((e) => e.toString()).join('\n\n');
              logString = l.isNotEmpty ? l : tr('noLogs');
            });
          });
    }

    if (logString == null) {
      filterLogs(days.first);
    }

    return AlertDialog(
      scrollable: true,
      title: Text(tr('appLogs')),
      content: Column(
        children: [
          DropdownButtonFormField(
            initialValue: days.first,
            items: days
                .map(
                  (e) =>
                      DropdownMenuItem(value: e, child: Text(plural('day', e))),
                )
                .toList(),
            onChanged: (d) {
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
            var cont =
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
              logsProvider.clear();
              Navigator.of(context).pop();
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
            SharePlus.instance.share(
              ShareParams(text: logString ?? '', subject: tr('appLogs')),
            );
            Navigator.of(context).pop();
          },
          child: Text(tr('share')),
        ),
      ],
    );
  }
}

class CategoryEditorSelector extends StatefulWidget {
  final void Function(List<String> categories)? onSelected;
  final bool singleSelect;
  final Set<String> preselected;
  final WrapAlignment alignment;
  final bool showLabelWhenNotEmpty;
  const CategoryEditorSelector({
    super.key,
    this.onSelected,
    this.singleSelect = false,
    this.preselected = const {},
    this.alignment = WrapAlignment.start,
    this.showLabelWhenNotEmpty = true,
  });

  @override
  State<CategoryEditorSelector> createState() => _CategoryEditorSelectorState();
}

class _CategoryEditorSelectorState extends State<CategoryEditorSelector> {
  Map<String, MapEntry<int, bool>> storedValues = {};

  @override
  Widget build(BuildContext context) {
    var settingsProvider = context.watch<SettingsProvider>();
    var appsProvider = context.watch<AppsProvider>();
    storedValues = settingsProvider.categories.map(
      (key, value) => MapEntry(
        key,
        MapEntry(
          value,
          storedValues[key]?.value ?? widget.preselected.contains(key),
        ),
      ),
    );
    return GeneratedForm(
      items: [
        [
          GeneratedFormTagInput(
            'categories',
            label: tr('categories'),
            emptyMessage: tr('noCategories'),
            defaultValue: storedValues,
            alignment: widget.alignment,
            deleteConfirmationMessage: MapEntry(
              tr('deleteCategoriesQuestion'),
              tr('categoryDeleteWarning'),
            ),
            singleSelect: widget.singleSelect,
            showLabelWhenNotEmpty: widget.showLabelWhenNotEmpty,
          ),
        ],
      ],
      onValueChanges: ((values, valid, isBuilding) {
        if (!isBuilding) {
          storedValues =
              values['categories'] as Map<String, MapEntry<int, bool>>;
          settingsProvider.setCategories(
            storedValues.map((key, value) => MapEntry(key, value.key)),
            appsProvider: appsProvider,
          );
          if (widget.onSelected != null) {
            widget.onSelected!(
              storedValues.keys.where((k) => storedValues[k]!.value).toList(),
            );
          }
        }
      }),
    );
  }
}
