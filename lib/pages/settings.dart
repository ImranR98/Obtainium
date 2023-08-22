import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
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
  @override
  Widget build(BuildContext context) {
    SettingsProvider settingsProvider = context.watch<SettingsProvider>();
    SourceProvider sourceProvider = SourceProvider();
    if (settingsProvider.prefs == null) {
      settingsProvider.initializeSettings();
    }

    var themeDropdown = DropdownButtonFormField(
        decoration: InputDecoration(labelText: tr('theme')),
        value: settingsProvider.theme,
        items: [
          DropdownMenuItem(
            value: ThemeSettings.dark,
            child: Text(tr('dark')),
          ),
          DropdownMenuItem(
            value: ThemeSettings.light,
            child: Text(tr('light')),
          ),
          DropdownMenuItem(
            value: ThemeSettings.system,
            child: Text(tr('followSystem')),
          )
        ],
        onChanged: (value) {
          if (value != null) {
            settingsProvider.theme = value;
          }
        });

    var colourDropdown = DropdownButtonFormField(
        decoration: InputDecoration(labelText: tr('colour')),
        value: settingsProvider.colour,
        items: [
          DropdownMenuItem(
            value: ColourSettings.basic,
            child: Text(tr('obtainium')),
          ),
          DropdownMenuItem(
            value: ColourSettings.materialYou,
            child: Text(tr('materialYou')),
          )
        ],
        onChanged: (value) {
          if (value != null) {
            settingsProvider.colour = value;
          }
        });

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
          )
        ],
        onChanged: (value) {
          if (value != null) {
            settingsProvider.sortColumn = value;
          }
        });

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
        });

    var localeDropdown = DropdownButtonFormField(
        decoration: InputDecoration(labelText: tr('language')),
        value: settingsProvider.forcedLocale,
        items: [
          DropdownMenuItem(
            value: null,
            child: Text(tr('followSystem')),
          ),
          ...supportedLocales.map((e) => DropdownMenuItem(
                value: e.key.toLanguageTag(),
                child: Text(e.value),
              ))
        ],
        onChanged: (value) {
          settingsProvider.forcedLocale = value;
          if (value != null) {
            context.setLocale(Locale(value));
          } else {
            settingsProvider.resetLocaleSafe(context);
          }
        });

    var intervalDropdown = DropdownButtonFormField(
        decoration: InputDecoration(labelText: tr('bgUpdateCheckInterval')),
        value: settingsProvider.updateInterval,
        items: updateIntervals.map((e) {
          int displayNum = (e < 60
                  ? e
                  : e < 1440
                      ? e / 60
                      : e / 1440)
              .round();
          String display = e == 0
              ? tr('neverManualOnly')
              : (e < 60
                  ? plural('minute', displayNum)
                  : e < 1440
                      ? plural('hour', displayNum)
                      : plural('day', displayNum));
          return DropdownMenuItem(value: e, child: Text(display));
        }).toList(),
        onChanged: (value) {
          if (value != null) {
            settingsProvider.updateInterval = value;
          }
        });

    var sourceSpecificFields = sourceProvider.sources.map((e) {
      if (e.sourceConfigSettingFormItems.isNotEmpty) {
        return GeneratedForm(
            items: e.sourceConfigSettingFormItems.map((e) {
              e.defaultValue = settingsProvider.getSettingString(e.key);
              return [e];
            }).toList(),
            onValueChanges: (values, valid, isBuilding) {
              if (valid && !isBuilding) {
                values.forEach((key, value) {
                  settingsProvider.setSettingString(key, value);
                });
              }
            });
      } else {
        return Container();
      }
    });

    const height8 = SizedBox(
      height: 8,
    );

    const height16 = SizedBox(
      height: 16,
    );

    const height32 = SizedBox(
      height: 32,
    );

    return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: CustomScrollView(slivers: <Widget>[
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
                                  color: Theme.of(context).colorScheme.primary),
                            ),
                            intervalDropdown,
                            FutureBuilder(
                                builder: (ctx, val) {
                                  return (val.data?.version.sdkInt ?? 0) >= 30
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            height16,
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Flexible(
                                                    child: Text(tr(
                                                        'enableBackgroundUpdates'))),
                                                Switch(
                                                    value: settingsProvider
                                                        .enableBackgroundUpdates,
                                                    onChanged: (value) {
                                                      settingsProvider
                                                              .enableBackgroundUpdates =
                                                          value;
                                                    })
                                              ],
                                            ),
                                            height8,
                                            Text(tr('backgroundUpdateReqsExplanation'),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall),
                                            Text(tr('backgroundUpdateLimitsExplanation'),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall),
                                            height8
                                          ],
                                        )
                                      : const SizedBox.shrink();
                                },
                                future: DeviceInfoPlugin().androidInfo),
                            height16,
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(child: Text(tr('checkOnStart'))),
                                Switch(
                                    value: settingsProvider.checkOnStart,
                                    onChanged: (value) {
                                      settingsProvider.checkOnStart = value;
                                    })
                              ],
                            ),
                            height16,
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                    child: Text(tr('checkUpdateOnDetailPage'))),
                                Switch(
                                    value: settingsProvider
                                        .checkUpdateOnDetailPage,
                                    onChanged: (value) {
                                      settingsProvider.checkUpdateOnDetailPage =
                                          value;
                                    })
                              ],
                            ),
                            height32,
                            Text(
                              tr('sourceSpecific'),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary),
                            ),
                            ...sourceSpecificFields,
                            height32,
                            Text(
                              tr('appearance'),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary),
                            ),
                            themeDropdown,
                            height16,
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(child: Text(tr('useBlackTheme'))),
                                Switch(
                                    value: settingsProvider.useBlackTheme,
                                    onChanged: (value) {
                                      settingsProvider.useBlackTheme = value;
                                    })
                              ],
                            ),
                            colourDropdown,
                            height16,
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: sortDropdown),
                                const SizedBox(
                                  width: 16,
                                ),
                                Expanded(child: orderDropdown),
                              ],
                            ),
                            height16,
                            localeDropdown,
                            height16,
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(child: Text(tr('showWebInAppView'))),
                                Switch(
                                    value: settingsProvider.showAppWebpage,
                                    onChanged: (value) {
                                      settingsProvider.showAppWebpage = value;
                                    })
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
                                    })
                              ],
                            ),
                            height16,
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                    child: Text(
                                        tr('moveNonInstalledAppsToBottom'))),
                                Switch(
                                    value: settingsProvider.buryNonInstalled,
                                    onChanged: (value) {
                                      settingsProvider.buryNonInstalled = value;
                                    })
                              ],
                            ),
                            height16,
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                    child:
                                        Text(tr('removeOnExternalUninstall'))),
                                Switch(
                                    value: settingsProvider
                                        .removeOnExternalUninstall,
                                    onChanged: (value) {
                                      settingsProvider
                                          .removeOnExternalUninstall = value;
                                    })
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
                                    })
                              ],
                            ),
                            height16,
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                    child:
                                        Text(tr('dontShowTrackOnlyWarnings'))),
                                Switch(
                                    value:
                                        settingsProvider.hideTrackOnlyWarning,
                                    onChanged: (value) {
                                      settingsProvider.hideTrackOnlyWarning =
                                          value;
                                    })
                              ],
                            ),
                            height16,
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                    child:
                                        Text(tr('dontShowAPKOriginWarnings'))),
                                Switch(
                                    value:
                                        settingsProvider.hideAPKOriginWarning,
                                    onChanged: (value) {
                                      settingsProvider.hideAPKOriginWarning =
                                          value;
                                    })
                              ],
                            ),
                            height16,
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                    child: Text(tr('disablePageTransitions'))),
                                Switch(
                                    value:
                                        settingsProvider.disablePageTransitions,
                                    onChanged: (value) {
                                      settingsProvider.disablePageTransitions =
                                          value;
                                    })
                              ],
                            ),
                            height16,
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                    child: Text(tr('reversePageTransitions'))),
                                Switch(
                                    value:
                                        settingsProvider.reversePageTransitions,
                                    onChanged: settingsProvider
                                            .disablePageTransitions
                                        ? null
                                        : (value) {
                                            settingsProvider
                                                .reversePageTransitions = value;
                                          })
                              ],
                            ),
                            height32,
                            Text(
                              tr('categories'),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary),
                            ),
                            height16,
                            const CategoryEditorSelector(
                              showLabelWhenNotEmpty: false,
                            )
                          ],
                        ))),
          SliverToBoxAdapter(
            child: Column(
              children: [
                const Divider(
                  height: 32,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        launchUrlString(settingsProvider.sourceUrl,
                            mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.code),
                      label: Text(
                        tr('appSource'),
                      ),
                    ),
                    TextButton.icon(
                        onPressed: () {
                          context.read<LogsProvider>().get().then((logs) {
                            if (logs.isEmpty) {
                              showError(ObtainiumError(tr('noLogs')), context);
                            } else {
                              showDialog(
                                  context: context,
                                  builder: (BuildContext ctx) {
                                    return const LogsDialog();
                                  });
                            }
                          });
                        },
                        icon: const Icon(Icons.bug_report_outlined),
                        label: Text(tr('appLogs'))),
                  ],
                ),
                height16,
              ],
            ),
          )
        ]));
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
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(plural('day', e)),
                      ))
                  .toList(),
              onChanged: (d) {
                filterLogs(d ?? 7);
              }),
          const SizedBox(
            height: 32,
          ),
          Text(logString ?? '')
        ],
      ),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text(tr('close'))),
        TextButton(
            onPressed: () {
              Share.share(logString ?? '', subject: tr('appLogs'));
              Navigator.of(context).pop();
            },
            child: Text(tr('share')))
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
  const CategoryEditorSelector(
      {super.key,
      this.onSelected,
      this.singleSelect = false,
      this.preselected = const {},
      this.alignment = WrapAlignment.start,
      this.showLabelWhenNotEmpty = true});

  @override
  State<CategoryEditorSelector> createState() => _CategoryEditorSelectorState();
}

class _CategoryEditorSelectorState extends State<CategoryEditorSelector> {
  Map<String, MapEntry<int, bool>> storedValues = {};

  @override
  Widget build(BuildContext context) {
    var settingsProvider = context.watch<SettingsProvider>();
    var appsProvider = context.watch<AppsProvider>();
    storedValues = settingsProvider.categories.map((key, value) => MapEntry(
        key,
        MapEntry(value,
            storedValues[key]?.value ?? widget.preselected.contains(key))));
    return GeneratedForm(
        items: [
          [
            GeneratedFormTagInput('categories',
                label: tr('categories'),
                emptyMessage: tr('noCategories'),
                defaultValue: storedValues,
                alignment: widget.alignment,
                deleteConfirmationMessage: MapEntry(
                    tr('deleteCategoriesQuestion'),
                    tr('categoryDeleteWarning')),
                singleSelect: widget.singleSelect,
                showLabelWhenNotEmpty: widget.showLabelWhenNotEmpty)
          ]
        ],
        onValueChanges: ((values, valid, isBuilding) {
          if (!isBuilding) {
            storedValues =
                values['categories'] as Map<String, MapEntry<int, bool>>;
            settingsProvider.setCategories(
                storedValues.map((key, value) => MapEntry(key, value.key)),
                appsProvider: appsProvider);
            if (widget.onSelected != null) {
              widget.onSelected!(storedValues.keys
                  .where((k) => storedValues[k]!.value)
                  .toList());
            }
          }
        }));
  }
}
