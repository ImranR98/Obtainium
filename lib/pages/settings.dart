import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:equations/equations.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
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
  final Map<ColorSwatch<Object>, String> colorsNameMap =
      <ColorSwatch<Object>, String>{
        ColorTools.createPrimarySwatch(obtainiumThemeColor): 'Obtainium',
      };

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

    var followSystemThemeExplanation = FutureBuilder(
      builder: (ctx, val) {
        return ((val.data?.version.sdkInt ?? 30) < 29)
            ? Text(
                tr('followSystemThemeExplanation'),
                style: Theme.of(context).textTheme.labelSmall,
              )
            : const SizedBox.shrink();
      },
      future: DeviceInfoPlugin().androidInfo,
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
              final double curvedValue = Curves.easeInCubic.transform(a1.value);
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(curvedValue, curvedValue, 1),
                child: Opacity(opacity: curvedValue, child: widget),
              );
            },
        transitionDuration: const Duration(milliseconds: 250),
      );
    }

    var colorPicker = ListTile(
      dense: true,
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
    );

    var useMaterialThemeSwitch = FutureBuilder(
      builder: (ctx, val) {
        return ((val.data?.version.sdkInt ?? 0) >= 31)
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: Text(tr('useMaterialYou'))),
                  Switch(
                    value: settingsProvider.useMaterialYou,
                    onChanged: (value) {
                      settingsProvider.useMaterialYou = value;
                    },
                  ),
                ],
              )
            : const SizedBox.shrink();
      },
      future: DeviceInfoPlugin().androidInfo,
    );

    var sortDropdown = DropdownButtonFormField(
      isExpanded: true,
      decoration: InputDecoration(labelText: tr('appSortBy')),
      value: settingsProvider.sortColumn,
      items: [
        DropdownMenuItem(
          value: SortColumnSettings.authorName,
          child: Text(tr('authorName')),
        ),
        DropdownMenuItem(
          value: SortColumnSettings.nameAuthor,
          child: Text(tr('nameAuthor')),
        ),
        DropdownMenuItem(
          value: SortColumnSettings.added,
          child: Text(tr('asAdded')),
        ),
        DropdownMenuItem(
          value: SortColumnSettings.releaseDate,
          child: Text(tr('releaseDate')),
        ),
      ],
      onChanged: (value) {
        if (value != null) {
          settingsProvider.sortColumn = value;
        }
      },
    );

    var orderDropdown = DropdownButtonFormField(
      isExpanded: true,
      decoration: InputDecoration(labelText: tr('appSortOrder')),
      value: settingsProvider.sortOrder,
      items: [
        DropdownMenuItem(
          value: SortOrderSettings.ascending,
          child: Text(tr('ascending')),
        ),
        DropdownMenuItem(
          value: SortOrderSettings.descending,
          child: Text(tr('descending')),
        ),
      ],
      onChanged: (value) {
        if (value != null) {
          settingsProvider.sortOrder = value;
        }
      },
    );

    var localeDropdown = DropdownButtonFormField(
      decoration: InputDecoration(labelText: tr('language')),
      value: settingsProvider.forcedLocale,
      items: [
        DropdownMenuItem(value: null, child: Text(tr('followSystem'))),
        ...supportedLocales.map(
          (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
        ),
      ],
      onChanged: (value) {
        settingsProvider.forcedLocale = value;
        if (value != null) {
          context.setLocale(value);
        } else {
          settingsProvider.resetLocaleSafe(context);
        }
      },
    );

    var intervalSlider = Slider(
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

    var sourceSpecificFields = sourceProvider.sources.map((e) {
      if (e.sourceConfigSettingFormItems.isNotEmpty) {
        return GeneratedForm(
          items: e.sourceConfigSettingFormItems.map((e) {
            if (e is GeneratedFormSwitch) {
              e.defaultValue = settingsProvider.getSettingBool(e.key);
            } else {
              e.defaultValue = settingsProvider.getSettingString(e.key);
            }
            return [e];
          }).toList(),
          onValueChanges: (values, valid, isBuilding) {
            if (valid && !isBuilding) {
              values.forEach((key, value) {
                var formItem = e.sourceConfigSettingFormItems
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
      } else {
        return Container();
      }
    });

    const height8 = SizedBox(height: 8);

    const height16 = SizedBox(height: 16);

    const height32 = SizedBox(height: 32);

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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('updates'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        //intervalDropdown,
                        height16,
                        if (showIntervalLabel)
                          SizedBox(
                            child: Text(
                              "${tr('bgUpdateCheckInterval')}: $updateIntervalLabel",
                            ),
                          )
                        else
                          const SizedBox(height: 16),
                        intervalSlider,
                        FutureBuilder(
                          builder: (ctx, val) {
                            return (settingsProvider.updateInterval > 0) &&
                                    (((val.data?.version.sdkInt ?? 0) >= 30) ||
                                        settingsProvider.useShizuku)
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              tr(
                                                'foregroundServiceExplanation',
                                              ),
                                            ),
                                          ),
                                          Switch(
                                            value:
                                                settingsProvider.useFGService,
                                            onChanged: (value) {
                                              settingsProvider.useFGService =
                                                  value;
                                            },
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              tr('enableBackgroundUpdates'),
                                            ),
                                          ),
                                          Switch(
                                            value: settingsProvider
                                                .enableBackgroundUpdates,
                                            onChanged: (value) {
                                              settingsProvider
                                                      .enableBackgroundUpdates =
                                                  value;
                                            },
                                          ),
                                        ],
                                      ),
                                      height8,
                                      Text(
                                        tr('backgroundUpdateReqsExplanation'),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                      Text(
                                        tr('backgroundUpdateLimitsExplanation'),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                      height8,
                                      if (settingsProvider
                                          .enableBackgroundUpdates)
                                        Column(
                                          children: [
                                            height16,
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    tr('bgUpdatesOnWiFiOnly'),
                                                  ),
                                                ),
                                                Switch(
                                                  value: settingsProvider
                                                      .bgUpdatesOnWiFiOnly,
                                                  onChanged: (value) {
                                                    settingsProvider
                                                            .bgUpdatesOnWiFiOnly =
                                                        value;
                                                  },
                                                ),
                                              ],
                                            ),
                                            height16,
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    tr(
                                                      'bgUpdatesWhileChargingOnly',
                                                    ),
                                                  ),
                                                ),
                                                Switch(
                                                  value: settingsProvider
                                                      .bgUpdatesWhileChargingOnly,
                                                  onChanged: (value) {
                                                    settingsProvider
                                                            .bgUpdatesWhileChargingOnly =
                                                        value;
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                    ],
                                  )
                                : const SizedBox.shrink();
                          },
                          future: DeviceInfoPlugin().androidInfo,
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: Text(tr('checkOnStart'))),
                            Switch(
                              value: settingsProvider.checkOnStart,
                              onChanged: (value) {
                                settingsProvider.checkOnStart = value;
                              },
                            ),
                          ],
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(tr('checkUpdateOnDetailPage')),
                            ),
                            Switch(
                              value: settingsProvider.checkUpdateOnDetailPage,
                              onChanged: (value) {
                                settingsProvider.checkUpdateOnDetailPage =
                                    value;
                              },
                            ),
                          ],
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                tr('onlyCheckInstalledOrTrackOnlyApps'),
                              ),
                            ),
                            Switch(
                              value: settingsProvider
                                  .onlyCheckInstalledOrTrackOnlyApps,
                              onChanged: (value) {
                                settingsProvider
                                        .onlyCheckInstalledOrTrackOnlyApps =
                                    value;
                              },
                            ),
                          ],
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(tr('removeOnExternalUninstall')),
                            ),
                            Switch(
                              value: settingsProvider.removeOnExternalUninstall,
                              onChanged: (value) {
                                settingsProvider.removeOnExternalUninstall =
                                    value;
                              },
                            ),
                          ],
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: Text(tr('parallelDownloads'))),
                            Switch(
                              value: settingsProvider.parallelDownloads,
                              onChanged: (value) {
                                settingsProvider.parallelDownloads = value;
                              },
                            ),
                          ],
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    tr('beforeNewInstallsShareToAppVerifier'),
                                  ),
                                  GestureDetector(
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
                                ],
                              ),
                            ),
                            Switch(
                              value: settingsProvider
                                  .beforeNewInstallsShareToAppVerifier,
                              onChanged: (value) {
                                settingsProvider
                                        .beforeNewInstallsShareToAppVerifier =
                                    value;
                              },
                            ),
                          ],
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: Text(tr('useShizuku'))),
                            Switch(
                              value: settingsProvider.useShizuku,
                              onChanged: (useShizuku) {
                                if (useShizuku) {
                                  ShizukuApkInstaller.checkPermission().then((
                                    resCode,
                                  ) {
                                    settingsProvider.useShizuku = resCode!
                                        .startsWith('granted');
                                    switch (resCode) {
                                      case 'binder_not_found':
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
                          ],
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(tr('shizukuPretendToBeGooglePlay')),
                            ),
                            Switch(
                              value:
                                  settingsProvider.shizukuPretendToBeGooglePlay,
                              onChanged: (value) {
                                settingsProvider.shizukuPretendToBeGooglePlay =
                                    value;
                              },
                            ),
                          ],
                        ),
                        height32,
                        Text(
                          tr('sourceSpecific'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        ...sourceSpecificFields,
                        height32,
                        Text(
                          tr('appearance'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        DropdownButtonFormField(
                          decoration: InputDecoration(labelText: tr('theme')),
                          value: settingsProvider.theme,
                          items: [
                            DropdownMenuItem(
                              value: ThemeSettings.system,
                              child: Text(tr('followSystem')),
                            ),
                            DropdownMenuItem(
                              value: ThemeSettings.light,
                              child: Text(tr('light')),
                            ),
                            DropdownMenuItem(
                              value: ThemeSettings.dark,
                              child: Text(tr('dark')),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              settingsProvider.theme = value;
                            }
                          },
                        ),
                        height8,
                        if (settingsProvider.theme == ThemeSettings.system)
                          followSystemThemeExplanation,
                        height16,
                        if (settingsProvider.theme != ThemeSettings.light)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(child: Text(tr('useBlackTheme'))),
                              Switch(
                                value: settingsProvider.useBlackTheme,
                                onChanged: (value) {
                                  settingsProvider.useBlackTheme = value;
                                },
                              ),
                            ],
                          ),
                        height8,
                        useMaterialThemeSwitch,
                        if (!settingsProvider.useMaterialYou) colorPicker,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: sortDropdown),
                            const SizedBox(width: 16),
                            Expanded(child: orderDropdown),
                          ],
                        ),
                        height16,
                        localeDropdown,
                        FutureBuilder(
                          builder: (ctx, val) {
                            return (val.data?.version.sdkInt ?? 0) >= 34
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      height16,
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Flexible(
                                            child: Text(tr('useSystemFont')),
                                          ),
                                          Switch(
                                            value:
                                                settingsProvider.useSystemFont,
                                            onChanged: (useSystemFont) {
                                              if (useSystemFont) {
                                                NativeFeatures.loadSystemFont()
                                                    .then((val) {
                                                      settingsProvider
                                                              .useSystemFont =
                                                          true;
                                                    });
                                              } else {
                                                settingsProvider.useSystemFont =
                                                    false;
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  )
                                : const SizedBox.shrink();
                          },
                          future: DeviceInfoPlugin().androidInfo,
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: Text(tr('showWebInAppView'))),
                            Switch(
                              value: settingsProvider.showAppWebpage,
                              onChanged: (value) {
                                settingsProvider.showAppWebpage = value;
                              },
                            ),
                          ],
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: Text(tr('pinUpdates'))),
                            Switch(
                              value: settingsProvider.pinUpdates,
                              onChanged: (value) {
                                settingsProvider.pinUpdates = value;
                              },
                            ),
                          ],
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(tr('moveNonInstalledAppsToBottom')),
                            ),
                            Switch(
                              value: settingsProvider.buryNonInstalled,
                              onChanged: (value) {
                                settingsProvider.buryNonInstalled = value;
                              },
                            ),
                          ],
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: Text(tr('groupByCategory'))),
                            Switch(
                              value: settingsProvider.groupByCategory,
                              onChanged: (value) {
                                settingsProvider.groupByCategory = value;
                              },
                            ),
                          ],
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(tr('dontShowTrackOnlyWarnings')),
                            ),
                            Switch(
                              value: settingsProvider.hideTrackOnlyWarning,
                              onChanged: (value) {
                                settingsProvider.hideTrackOnlyWarning = value;
                              },
                            ),
                          ],
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(tr('dontShowAPKOriginWarnings')),
                            ),
                            Switch(
                              value: settingsProvider.hideAPKOriginWarning,
                              onChanged: (value) {
                                settingsProvider.hideAPKOriginWarning = value;
                              },
                            ),
                          ],
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: Text(tr('disablePageTransitions'))),
                            Switch(
                              value: settingsProvider.disablePageTransitions,
                              onChanged: (value) {
                                settingsProvider.disablePageTransitions = value;
                              },
                            ),
                          ],
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: Text(tr('reversePageTransitions'))),
                            Switch(
                              value: settingsProvider.reversePageTransitions,
                              onChanged: settingsProvider.disablePageTransitions
                                  ? null
                                  : (value) {
                                      settingsProvider.reversePageTransitions =
                                          value;
                                    },
                            ),
                          ],
                        ),
                        height16,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: Text(tr('highlightTouchTargets'))),
                            Switch(
                              value: settingsProvider.highlightTouchTargets,
                              onChanged: (value) {
                                settingsProvider.highlightTouchTargets = value;
                              },
                            ),
                          ],
                        ),
                        height32,
                        Text(
                          tr('categories'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        height16,
                        const CategoryEditorSelector(
                          showLabelWhenNotEmpty: false,
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
                          'https://wiki.obtainium.imranr.dev/',
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      icon: const Icon(Icons.help_outline_rounded),
                      tooltip: tr('wiki'),
                    ),
                    IconButton(
                      onPressed: () {
                        launchUrlString(
                          'https://apps.obtainium.imranr.dev/',
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
            value: days.first,
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
        TextButton(
          onPressed: () {
            Share.share(logString ?? '', subject: tr('appLogs'));
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
