import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AppsPage extends StatefulWidget {
  const AppsPage({super.key});

  @override
  State<AppsPage> createState() => AppsPageState();
}

class AppsPageState extends State<AppsPage> {
  AppsFilter? filter;
  var updatesOnlyFilter =
      AppsFilter(includeUptodate: false, includeNonInstalled: false);
  Set<App> selectedApps = {};
  DateTime? refreshingSince;

  clearSelected() {
    if (selectedApps.isNotEmpty) {
      setState(() {
        selectedApps.clear();
      });
      return true;
    }
    return false;
  }

  selectThese(List<App> apps) {
    if (selectedApps.isEmpty) {
      setState(() {
        for (var a in apps) {
          selectedApps.add(a);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    var appsProvider = context.watch<AppsProvider>();
    var settingsProvider = context.watch<SettingsProvider>();
    var sortedApps = appsProvider.apps.values.toList();
    var currentFilterIsUpdatesOnly =
        filter?.isIdenticalTo(updatesOnlyFilter) ?? false;

    selectedApps = selectedApps
        .where((element) => sortedApps.map((e) => e.app).contains(element))
        .toSet();

    toggleAppSelected(App app) {
      setState(() {
        if (selectedApps.contains(app)) {
          selectedApps.remove(app);
        } else {
          selectedApps.add(app);
        }
      });
    }

    if (filter != null) {
      sortedApps = sortedApps.where((app) {
        if (app.app.installedVersion == app.app.latestVersion &&
            !(filter!.includeUptodate)) {
          return false;
        }
        if (app.app.installedVersion == null &&
            !(filter!.includeNonInstalled)) {
          return false;
        }
        if (filter!.nameFilter.isNotEmpty || filter!.authorFilter.isNotEmpty) {
          List<String> nameTokens = filter!.nameFilter
              .split(' ')
              .where((element) => element.trim().isNotEmpty)
              .toList();
          List<String> authorTokens = filter!.authorFilter
              .split(' ')
              .where((element) => element.trim().isNotEmpty)
              .toList();

          for (var t in nameTokens) {
            var name = app.installedInfo?.name ?? app.app.name;
            if (!name.toLowerCase().contains(t.toLowerCase())) {
              return false;
            }
          }
          for (var t in authorTokens) {
            if (!app.app.author.toLowerCase().contains(t.toLowerCase())) {
              return false;
            }
          }
        }
        if (filter!.categoryFilter.isNotEmpty &&
            filter!.categoryFilter != app.app.category) {
          return false;
        }
        return true;
      }).toList();
    }

    sortedApps.sort((a, b) {
      var nameA = a.installedInfo?.name ?? a.app.name;
      var nameB = b.installedInfo?.name ?? b.app.name;
      int result = 0;
      if (settingsProvider.sortColumn == SortColumnSettings.authorName) {
        result = (a.app.author + nameA).compareTo(b.app.author + nameB);
      } else if (settingsProvider.sortColumn == SortColumnSettings.nameAuthor) {
        result = (nameA + a.app.author).compareTo(nameB + b.app.author);
      }
      return result;
    });

    if (settingsProvider.sortOrder == SortOrderSettings.descending) {
      sortedApps = sortedApps.reversed.toList();
    }

    var existingUpdates = appsProvider.findExistingUpdates(installedOnly: true);

    var existingUpdateIdsAllOrSelected = existingUpdates
        .where((element) => selectedApps.isEmpty
            ? sortedApps.where((a) => a.app.id == element).isNotEmpty
            : selectedApps.map((e) => e.id).contains(element))
        .toList();
    var newInstallIdsAllOrSelected = appsProvider
        .findExistingUpdates(nonInstalledOnly: true)
        .where((element) => selectedApps.isEmpty
            ? sortedApps.where((a) => a.app.id == element).isNotEmpty
            : selectedApps.map((e) => e.id).contains(element))
        .toList();

    List<String> trackOnlyUpdateIdsAllOrSelected = [];
    existingUpdateIdsAllOrSelected = existingUpdateIdsAllOrSelected.where((id) {
      if (appsProvider.apps[id]!.app.additionalSettings['trackOnly'] ==
          'true') {
        trackOnlyUpdateIdsAllOrSelected.add(id);
        return false;
      }
      return true;
    }).toList();
    newInstallIdsAllOrSelected = newInstallIdsAllOrSelected.where((id) {
      if (appsProvider.apps[id]!.app.additionalSettings['trackOnly'] ==
          'true') {
        trackOnlyUpdateIdsAllOrSelected.add(id);
        return false;
      }
      return true;
    }).toList();

    if (settingsProvider.pinUpdates) {
      var temp = [];
      sortedApps = sortedApps.where((sa) {
        if (existingUpdates.contains(sa.app.id)) {
          temp.add(sa);
          return false;
        }
        return true;
      }).toList();
      sortedApps = [...temp, ...sortedApps];
    }

    var tempPinned = [];
    var tempNotPinned = [];
    for (var a in sortedApps) {
      if (a.app.pinned) {
        tempPinned.add(a);
      } else {
        tempNotPinned.add(a);
      }
    }
    sortedApps = [...tempPinned, ...tempNotPinned];

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
          onRefresh: () {
            HapticFeedback.lightImpact();
            setState(() {
              refreshingSince = DateTime.now();
            });
            return appsProvider.checkUpdates().catchError((e) {
              showError(e, context);
            }).whenComplete(() {
              setState(() {
                refreshingSince = null;
              });
            });
          },
          child: CustomScrollView(slivers: <Widget>[
            CustomAppBar(title: tr('appsString')),
            if (appsProvider.loadingApps || sortedApps.isEmpty)
              SliverFillRemaining(
                  child: Center(
                      child: appsProvider.loadingApps
                          ? const CircularProgressIndicator()
                          : Text(
                              appsProvider.apps.isEmpty
                                  ? tr('noApps')
                                  : tr('noAppsForFilter'),
                              style: Theme.of(context).textTheme.headlineMedium,
                              textAlign: TextAlign.center,
                            ))),
            if (refreshingSince != null)
              SliverToBoxAdapter(
                child: LinearProgressIndicator(
                  value: appsProvider.apps.values
                          .where((element) => !(element.app.lastUpdateCheck
                                  ?.isBefore(refreshingSince!) ??
                              true))
                          .length /
                      appsProvider.apps.length,
                ),
              ),
            SliverList(
                delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) {
              String? changesUrl = SourceProvider()
                  .getSource(sortedApps[index].app.url)
                  .changeLogPageFromStandardUrl(sortedApps[index].app.url);
              return Container(
                  decoration: BoxDecoration(
                      border: Border.symmetric(
                          vertical: BorderSide(
                              width: 3,
                              color: Color(settingsProvider.categories[
                                      sortedApps[index].app.category] ??
                                  const Color.fromARGB(0, 0, 0, 0).value)))),
                  child: ListTile(
                    tileColor: sortedApps[index].app.pinned
                        ? Colors.grey.withOpacity(0.1)
                        : Colors.transparent,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withOpacity(sortedApps[index].app.pinned ? 0.2 : 0.1),
                    selected: selectedApps.contains(sortedApps[index].app),
                    onLongPress: () {
                      toggleAppSelected(sortedApps[index].app);
                    },
                    leading: sortedApps[index].installedInfo != null
                        ? Image.memory(
                            sortedApps[index].installedInfo!.icon!,
                            gaplessPlayback: true,
                          )
                        : null,
                    title: Text(
                      sortedApps[index].installedInfo?.name ??
                          sortedApps[index].app.name,
                      style: TextStyle(
                        fontWeight: sortedApps[index].app.pinned
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                        tr('byX', args: [sortedApps[index].app.author]),
                        style: TextStyle(
                            fontWeight: sortedApps[index].app.pinned
                                ? FontWeight.bold
                                : FontWeight.normal)),
                    trailing: SingleChildScrollView(
                        reverse: true,
                        child: sortedApps[index].downloadProgress != null
                            ? Text(tr('percentProgress', args: [
                                sortedApps[index]
                                        .downloadProgress
                                        ?.toInt()
                                        .toString() ??
                                    '100'
                              ]))
                            : (Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  SizedBox(
                                      width: 100,
                                      child: Text(
                                        '${sortedApps[index].app.installedVersion ?? tr('notInstalled')}${sortedApps[index].app.additionalSettings['trackOnly'] == 'true' ? ' ${tr('estimateInBrackets')}' : ''}',
                                        overflow: TextOverflow.fade,
                                        textAlign: TextAlign.end,
                                      )),
                                  sortedApps[index].app.installedVersion !=
                                              null &&
                                          sortedApps[index]
                                                  .app
                                                  .installedVersion !=
                                              sortedApps[index]
                                                  .app
                                                  .latestVersion
                                      ? GestureDetector(
                                          onTap: changesUrl == null
                                              ? null
                                              : () {
                                                  launchUrlString(changesUrl,
                                                      mode: LaunchMode
                                                          .externalApplication);
                                                },
                                          child: appsProvider
                                                  .areDownloadsRunning()
                                              ? Text(tr('pleaseWait'))
                                              : Text(
                                                  '${tr('updateAvailable')}${sortedApps[index].app.additionalSettings['trackOnly'] == 'true' ? ' ${tr('estimateInBracketsShort')}' : ''}',
                                                  style: TextStyle(
                                                      fontStyle:
                                                          FontStyle.italic,
                                                      decoration: changesUrl ==
                                                              null
                                                          ? TextDecoration.none
                                                          : TextDecoration
                                                              .underline),
                                                ))
                                      : const SizedBox(),
                                ],
                              ))),
                    onTap: () {
                      if (selectedApps.isNotEmpty) {
                        toggleAppSelected(sortedApps[index].app);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  AppPage(appId: sortedApps[index].app.id)),
                        );
                      }
                    },
                  ));
            }, childCount: sortedApps.length))
          ])),
      persistentFooterButtons: [
        Row(
          children: [
            IconButton(
                onPressed: () {
                  selectedApps.isEmpty
                      ? selectThese(sortedApps.map((e) => e.app).toList())
                      : clearSelected();
                },
                icon: Icon(
                  selectedApps.isEmpty
                      ? Icons.select_all_outlined
                      : Icons.deselect_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                tooltip: selectedApps.isEmpty
                    ? tr('selectAll')
                    : tr('deselectN', args: [selectedApps.length.toString()])),
            const VerticalDivider(),
            Expanded(
                child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                selectedApps.isEmpty
                    ? const SizedBox()
                    : IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          showDialog<Map<String, String>?>(
                              context: context,
                              builder: (BuildContext ctx) {
                                return GeneratedFormModal(
                                  title: tr('removeSelectedAppsQuestion'),
                                  items: const [],
                                  initValid: true,
                                  message: tr(
                                      'xWillBeRemovedButRemainInstalled',
                                      args: [
                                        plural('apps', selectedApps.length)
                                      ]),
                                );
                              }).then((values) {
                            if (values != null) {
                              appsProvider.removeApps(
                                  selectedApps.map((e) => e.id).toList());
                            }
                          });
                        },
                        tooltip: tr('removeSelectedApps'),
                        icon: const Icon(Icons.delete_outline_outlined),
                      ),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: appsProvider.areDownloadsRunning() ||
                            (existingUpdateIdsAllOrSelected.isEmpty &&
                                newInstallIdsAllOrSelected.isEmpty &&
                                trackOnlyUpdateIdsAllOrSelected.isEmpty)
                        ? null
                        : () {
                            HapticFeedback.heavyImpact();
                            List<GeneratedFormItem> formItems = [];
                            if (existingUpdateIdsAllOrSelected.isNotEmpty) {
                              formItems.add(GeneratedFormItem('updates',
                                  label: tr('updateX', args: [
                                    plural('apps',
                                        existingUpdateIdsAllOrSelected.length)
                                  ]),
                                  type: FormItemType.bool,
                                  defaultValue: 'true'));
                            }
                            if (newInstallIdsAllOrSelected.isNotEmpty) {
                              formItems.add(GeneratedFormItem('installs',
                                  label: tr('installX', args: [
                                    plural('apps',
                                        newInstallIdsAllOrSelected.length)
                                  ]),
                                  type: FormItemType.bool,
                                  defaultValue:
                                      existingUpdateIdsAllOrSelected.isNotEmpty
                                          ? 'true'
                                          : ''));
                            }
                            if (trackOnlyUpdateIdsAllOrSelected.isNotEmpty) {
                              formItems.add(GeneratedFormItem('trackonlies',
                                  label: tr('markXTrackOnlyAsUpdated', args: [
                                    plural('apps',
                                        trackOnlyUpdateIdsAllOrSelected.length)
                                  ]),
                                  type: FormItemType.bool,
                                  defaultValue: existingUpdateIdsAllOrSelected
                                              .isNotEmpty ||
                                          newInstallIdsAllOrSelected.isNotEmpty
                                      ? 'true'
                                      : ''));
                            }
                            showDialog<Map<String, String>?>(
                                context: context,
                                builder: (BuildContext ctx) {
                                  var totalApps = existingUpdateIdsAllOrSelected
                                          .length +
                                      newInstallIdsAllOrSelected.length +
                                      trackOnlyUpdateIdsAllOrSelected.length;
                                  return GeneratedFormModal(
                                    title: tr('changeX',
                                        args: [plural('apps', totalApps)]),
                                    items: formItems.map((e) => [e]).toList(),
                                    initValid: true,
                                  );
                                }).then((values) {
                              if (values != null) {
                                if (values.isEmpty) {
                                  values = getDefaultValuesFromFormItems(
                                      [formItems]);
                                }
                                bool shouldInstallUpdates =
                                    values['updates'] == 'true';
                                bool shouldInstallNew =
                                    values['installs'] == 'true';
                                bool shouldMarkTrackOnlies =
                                    values['trackonlies'] == 'true';
                                (() async {
                                  if (shouldInstallNew ||
                                      shouldInstallUpdates) {
                                    await settingsProvider
                                        .getInstallPermission();
                                  }
                                })()
                                    .then((_) {
                                  List<String> toInstall = [];
                                  if (shouldInstallUpdates) {
                                    toInstall
                                        .addAll(existingUpdateIdsAllOrSelected);
                                  }
                                  if (shouldInstallNew) {
                                    toInstall
                                        .addAll(newInstallIdsAllOrSelected);
                                  }
                                  if (shouldMarkTrackOnlies) {
                                    toInstall.addAll(
                                        trackOnlyUpdateIdsAllOrSelected);
                                  }
                                  appsProvider
                                      .downloadAndInstallLatestApps(toInstall,
                                          globalNavigatorKey.currentContext)
                                      .catchError((e) {
                                    showError(e, context);
                                  });
                                });
                              }
                            });
                          },
                    tooltip: selectedApps.isEmpty
                        ? tr('installUpdateApps')
                        : tr('installUpdateSelectedApps'),
                    icon: const Icon(
                      Icons.file_download_outlined,
                    )),
                selectedApps.isEmpty
                    ? const SizedBox()
                    : IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          showDialog(
                              context: context,
                              builder: (BuildContext ctx) {
                                return AlertDialog(
                                  scrollable: true,
                                  content: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceAround,
                                        children: [
                                          IconButton(
                                              onPressed:
                                                  appsProvider
                                                          .areDownloadsRunning()
                                                      ? null
                                                      : () {
                                                          showDialog(
                                                              context: context,
                                                              builder:
                                                                  (BuildContext
                                                                      ctx) {
                                                                return AlertDialog(
                                                                  title: Text(tr(
                                                                      'markXSelectedAppsAsUpdated',
                                                                      args: [
                                                                        selectedApps
                                                                            .length
                                                                            .toString()
                                                                      ])),
                                                                  content: Text(
                                                                    tr('onlyWorksWithNonEVDApps'),
                                                                    style: const TextStyle(
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .bold,
                                                                        fontStyle:
                                                                            FontStyle.italic),
                                                                  ),
                                                                  actions: [
                                                                    TextButton(
                                                                        onPressed:
                                                                            () {
                                                                          Navigator.of(context)
                                                                              .pop();
                                                                        },
                                                                        child: Text(
                                                                            tr('no'))),
                                                                    TextButton(
                                                                        onPressed:
                                                                            () {
                                                                          HapticFeedback
                                                                              .selectionClick();
                                                                          appsProvider
                                                                              .saveApps(selectedApps.map((a) {
                                                                            if (a.installedVersion !=
                                                                                null) {
                                                                              a.installedVersion = a.latestVersion;
                                                                            }
                                                                            return a;
                                                                          }).toList());

                                                                          Navigator.of(context)
                                                                              .pop();
                                                                        },
                                                                        child: Text(
                                                                            tr('yes')))
                                                                  ],
                                                                );
                                                              }).whenComplete(() {
                                                            Navigator.of(
                                                                    context)
                                                                .pop();
                                                          });
                                                        },
                                              tooltip:
                                                  tr('markSelectedAppsUpdated'),
                                              icon: const Icon(Icons.done)),
                                          IconButton(
                                            onPressed: () {
                                              var pinStatus = selectedApps
                                                  .where((element) =>
                                                      element.pinned)
                                                  .isEmpty;
                                              appsProvider.saveApps(
                                                  selectedApps.map((e) {
                                                e.pinned = pinStatus;
                                                return e;
                                              }).toList());
                                              Navigator.of(context).pop();
                                            },
                                            tooltip: selectedApps
                                                    .where((element) =>
                                                        element.pinned)
                                                    .isEmpty
                                                ? tr('pinToTop')
                                                : tr('unpinFromTop'),
                                            icon: Icon(selectedApps
                                                    .where((element) =>
                                                        element.pinned)
                                                    .isEmpty
                                                ? Icons.bookmark_outline_rounded
                                                : Icons
                                                    .bookmark_remove_outlined),
                                          ),
                                          IconButton(
                                            onPressed: () {
                                              String urls = '';
                                              for (var a in selectedApps) {
                                                urls += '${a.url}\n';
                                              }
                                              urls = urls.substring(
                                                  0, urls.length - 1);
                                              Share.share(urls,
                                                  subject: tr(
                                                      'selectedAppURLsFromObtainium'));
                                              Navigator.of(context).pop();
                                            },
                                            tooltip: tr('shareSelectedAppURLs'),
                                            icon: const Icon(Icons.share),
                                          ),
                                          IconButton(
                                            onPressed: () {
                                              showDialog(
                                                  context: context,
                                                  builder: (BuildContext ctx) {
                                                    return GeneratedFormModal(
                                                      title: tr(
                                                          'resetInstallStatusForSelectedAppsQuestion'),
                                                      items: const [],
                                                      initValid: true,
                                                      message: tr(
                                                          'installStatusOfXWillBeResetExplanation',
                                                          args: [
                                                            plural(
                                                                'app',
                                                                selectedApps
                                                                    .length)
                                                          ]),
                                                    );
                                                  }).then((values) {
                                                if (values != null) {
                                                  appsProvider.saveApps(
                                                      selectedApps.map((e) {
                                                    e.installedVersion = null;
                                                    return e;
                                                  }).toList());
                                                }
                                              }).whenComplete(() {
                                                Navigator.of(context).pop();
                                              });
                                            },
                                            tooltip: tr('resetInstallStatus'),
                                            icon: const Icon(
                                                Icons.restore_page_outlined),
                                          ),
                                        ]),
                                  ),
                                );
                              });
                        },
                        tooltip: tr('more'),
                        icon: const Icon(Icons.more_horiz),
                      ),
              ],
            )),
            const VerticalDivider(),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() {
                  if (currentFilterIsUpdatesOnly) {
                    filter = null;
                  } else {
                    filter = updatesOnlyFilter;
                  }
                });
              },
              tooltip: currentFilterIsUpdatesOnly
                  ? tr('removeOutdatedFilter')
                  : tr('showOutdatedOnly'),
              icon: Icon(
                currentFilterIsUpdatesOnly
                    ? Icons.update_disabled_rounded
                    : Icons.update_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            appsProvider.apps.isEmpty
                ? const SizedBox()
                : TextButton.icon(
                    label: Text(
                      filter == null ? tr('filter') : tr('filterActive'),
                      style: TextStyle(
                          fontWeight: filter == null
                              ? FontWeight.normal
                              : FontWeight.bold),
                    ),
                    onPressed: () {
                      showDialog<Map<String, String>?>(
                          context: context,
                          builder: (BuildContext ctx) {
                            var vals = filter == null
                                ? AppsFilter().toValuesMap()
                                : filter!.toValuesMap();
                            return GeneratedFormModal(
                                title: tr('filterApps'),
                                items: [
                                  [
                                    GeneratedFormItem('appName',
                                        label: tr('appName'),
                                        required: false,
                                        defaultValue: vals['appName']),
                                    GeneratedFormItem('author',
                                        label: tr('author'),
                                        required: false,
                                        defaultValue: vals['author'])
                                  ],
                                  [
                                    GeneratedFormItem('upToDateApps',
                                        label: tr('upToDateApps'),
                                        type: FormItemType.bool,
                                        defaultValue: vals['upToDateApps'])
                                  ],
                                  [
                                    GeneratedFormItem('nonInstalledApps',
                                        label: tr('nonInstalledApps'),
                                        type: FormItemType.bool,
                                        defaultValue: vals['nonInstalledApps'])
                                  ],
                                  [
                                    settingsProvider.getCategoryFormItem(
                                        initCategory: vals['category'] ?? '')
                                  ]
                                ]);
                          }).then((values) {
                        if (values != null) {
                          setState(() {
                            filter = AppsFilter.fromValuesMap(values);
                            if (AppsFilter().isIdenticalTo(filter!)) {
                              filter = null;
                            }
                          });
                        }
                      });
                    },
                    icon: const Icon(Icons.filter_list_rounded))
          ],
        ),
      ],
    );
  }
}

class AppsFilter {
  late String nameFilter;
  late String authorFilter;
  late bool includeUptodate;
  late bool includeNonInstalled;
  late String categoryFilter;

  AppsFilter(
      {this.nameFilter = '',
      this.authorFilter = '',
      this.includeUptodate = true,
      this.includeNonInstalled = true,
      this.categoryFilter = ''});

  Map<String, String> toValuesMap() {
    return {
      'appName': nameFilter,
      'author': authorFilter,
      'upToDateApps': includeUptodate ? 'true' : '',
      'nonInstalledApps': includeNonInstalled ? 'true' : '',
      'category': categoryFilter
    };
  }

  AppsFilter.fromValuesMap(Map<String, String> values) {
    nameFilter = values['appName']!;
    authorFilter = values['author']!;
    includeUptodate = values['upToDateApps'] == 'true';
    includeNonInstalled = values['nonInstalledApps'] == 'true';
    categoryFilter = values['category']!;
  }

  bool isIdenticalTo(AppsFilter other) =>
      authorFilter.trim() == other.authorFilter.trim() &&
      nameFilter.trim() == other.nameFilter.trim() &&
      includeUptodate == other.includeUptodate &&
      includeNonInstalled == other.includeNonInstalled &&
      categoryFilter.trim() == other.categoryFilter.trim();
}
