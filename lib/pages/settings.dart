import 'package:flutter/material.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
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
    return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: CustomScrollView(slivers: <Widget>[
          const CustomAppBar(title: 'Settings'),
          SliverToBoxAdapter(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: settingsProvider.prefs == null
                      ? const SizedBox()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Appearance',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary),
                            ),
                            DropdownButtonFormField(
                                decoration:
                                    const InputDecoration(labelText: 'Theme'),
                                value: settingsProvider.theme,
                                items: const [
                                  DropdownMenuItem(
                                    value: ThemeSettings.dark,
                                    child: Text('Dark'),
                                  ),
                                  DropdownMenuItem(
                                    value: ThemeSettings.light,
                                    child: Text('Light'),
                                  ),
                                  DropdownMenuItem(
                                    value: ThemeSettings.system,
                                    child: Text('Follow System'),
                                  )
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    settingsProvider.theme = value;
                                  }
                                }),
                            const SizedBox(
                              height: 16,
                            ),
                            DropdownButtonFormField(
                                decoration:
                                    const InputDecoration(labelText: 'Colour'),
                                value: settingsProvider.colour,
                                items: const [
                                  DropdownMenuItem(
                                    value: ColourSettings.basic,
                                    child: Text('Obtainium'),
                                  ),
                                  DropdownMenuItem(
                                    value: ColourSettings.materialYou,
                                    child: Text('Material You'),
                                  )
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    settingsProvider.colour = value;
                                  }
                                }),
                            const SizedBox(
                              height: 16,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                    child: DropdownButtonFormField(
                                        decoration: const InputDecoration(
                                            labelText: 'App Sort By'),
                                        value: settingsProvider.sortColumn,
                                        items: const [
                                          DropdownMenuItem(
                                            value:
                                                SortColumnSettings.authorName,
                                            child: Text('Author/Name'),
                                          ),
                                          DropdownMenuItem(
                                            value:
                                                SortColumnSettings.nameAuthor,
                                            child: Text('Name/Author'),
                                          ),
                                          DropdownMenuItem(
                                            value: SortColumnSettings.added,
                                            child: Text('As Added'),
                                          )
                                        ],
                                        onChanged: (value) {
                                          if (value != null) {
                                            settingsProvider.sortColumn = value;
                                          }
                                        })),
                                const SizedBox(
                                  width: 16,
                                ),
                                Expanded(
                                    child: DropdownButtonFormField(
                                        decoration: const InputDecoration(
                                            labelText: 'App Sort Order'),
                                        value: settingsProvider.sortOrder,
                                        items: const [
                                          DropdownMenuItem(
                                            value: SortOrderSettings.ascending,
                                            child: Text('Ascending'),
                                          ),
                                          DropdownMenuItem(
                                            value: SortOrderSettings.descending,
                                            child: Text('Descending'),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value != null) {
                                            settingsProvider.sortOrder = value;
                                          }
                                        })),
                              ],
                            ),
                            const SizedBox(
                              height: 16,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Show Source Webpage in App View'),
                                Switch(
                                    value: settingsProvider.showAppWebpage,
                                    onChanged: (value) {
                                      settingsProvider.showAppWebpage = value;
                                    })
                              ],
                            ),
                            const SizedBox(
                              height: 16,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Pin Updates to Top of Apps View'),
                                Switch(
                                    value: settingsProvider.pinUpdates,
                                    onChanged: (value) {
                                      settingsProvider.pinUpdates = value;
                                    })
                              ],
                            ),
                            const Divider(
                              height: 16,
                            ),
                            const SizedBox(
                              height: 16,
                            ),
                            Text(
                              'Updates',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary),
                            ),
                            DropdownButtonFormField(
                                decoration: const InputDecoration(
                                    labelText:
                                        'Background Update Checking Interval'),
                                value: settingsProvider.updateInterval,
                                items: updateIntervals.map((e) {
                                  int displayNum = (e < 60
                                          ? e
                                          : e < 1440
                                              ? e / 60
                                              : e / 1440)
                                      .round();
                                  var displayUnit = (e < 60
                                      ? 'Minute'
                                      : e < 1440
                                          ? 'Hour'
                                          : 'Day');

                                  String display = e == 0
                                      ? 'Never - Manual Only'
                                      : '$displayNum $displayUnit${displayNum == 1 ? '' : 's'}';
                                  return DropdownMenuItem(
                                      value: e, child: Text(display));
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    settingsProvider.updateInterval = value;
                                  }
                                }),
                            const Divider(
                              height: 48,
                            ),
                            Text(
                              'Source-Specific',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary),
                            ),
                            ...sourceProvider.sources.map((e) {
                              if (e.moreSourceSettingsFormItems.isNotEmpty) {
                                return GeneratedForm(
                                    items: e.moreSourceSettingsFormItems
                                        .map((e) => [e])
                                        .toList(),
                                    onValueChanges: (values, valid) {
                                      if (valid) {
                                        for (var i = 0;
                                            i < values.length;
                                            i++) {
                                          settingsProvider.setSettingString(
                                              e.moreSourceSettingsFormItems[i]
                                                  .id,
                                              values[i]);
                                        }
                                      }
                                    },
                                    defaultValues:
                                        e.moreSourceSettingsFormItems.map((e) {
                                      return settingsProvider
                                              .getSettingString(e.id) ??
                                          '';
                                    }).toList());
                              } else {
                                return Container();
                              }
                            }),
                          ],
                        ))),
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(
                  height: 16,
                ),
                TextButton.icon(
                  style: ButtonStyle(
                    foregroundColor: MaterialStateProperty.resolveWith<Color>(
                        (Set<MaterialState> states) {
                      return Colors.grey;
                    }),
                  ),
                  onPressed: () {
                    launchUrlString(settingsProvider.sourceUrl,
                        mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.code),
                  label: Text(
                    'Source',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(
                  height: 16,
                ),
              ],
            ),
          )
        ]));
  }
}
