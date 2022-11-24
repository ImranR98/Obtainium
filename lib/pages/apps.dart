import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/custom_errors.dart';
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
        if (filter!.nameFilter.isEmpty && filter!.authorFilter.isEmpty) {
          return true;
        }
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
      if (appsProvider.apps[id]!.app.trackOnly) {
        trackOnlyUpdateIdsAllOrSelected.add(id);
        return false;
      }
      return true;
    }).toList();
    newInstallIdsAllOrSelected = newInstallIdsAllOrSelected.where((id) {
      if (appsProvider.apps[id]!.app.trackOnly) {
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
            const CustomAppBar(title: 'Apps'),
            if (appsProvider.loadingApps || sortedApps.isEmpty)
              SliverFillRemaining(
                  child: Center(
                      child: appsProvider.loadingApps
                          ? const CircularProgressIndicator()
                          : Text(
                              appsProvider.apps.isEmpty
                                  ? 'No Apps'
                                  : 'No Apps for Filter',
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
              return ListTile(
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
                          : FontWeight.normal),
                ),
                subtitle: Text('By ${sortedApps[index].app.author}',
                    style: TextStyle(
                        fontWeight: sortedApps[index].app.pinned
                            ? FontWeight.bold
                            : FontWeight.normal)),
                trailing: sortedApps[index].downloadProgress != null
                    ? Text(
                        'Downloading - ${sortedApps[index].downloadProgress?.toInt()}%')
                    : (sortedApps[index].app.installedVersion != null &&
                            sortedApps[index].app.installedVersion !=
                                sortedApps[index].app.latestVersion
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(appsProvider.areDownloadsRunning()
                                  ? 'Please Wait...'
                                  : 'Update Available${sortedApps[index].app.trackOnly ? ' (Est.)' : ''}'),
                              SourceProvider()
                                          .getSource(sortedApps[index].app.url)
                                          .changeLogPageFromStandardUrl(
                                              sortedApps[index].app.url) ==
                                      null
                                  ? const SizedBox()
                                  : GestureDetector(
                                      onTap: () {
                                        launchUrlString(
                                            SourceProvider()
                                                .getSource(
                                                    sortedApps[index].app.url)
                                                .changeLogPageFromStandardUrl(
                                                    sortedApps[index].app.url)!,
                                            mode:
                                                LaunchMode.externalApplication);
                                      },
                                      child: const Text(
                                        'See Changes',
                                        style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            decoration:
                                                TextDecoration.underline),
                                      )),
                            ],
                          )
                        : SingleChildScrollView(
                            child: SizedBox(
                                width: 80,
                                child: Text(
                                  '${sortedApps[index].app.installedVersion ?? 'Not Installed'} ${sortedApps[index].app.trackOnly == true ? '(Estimate)' : ''}',
                                  overflow: TextOverflow.fade,
                                  textAlign: TextAlign.end,
                                )))),
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
              );
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
                    ? 'Select All'
                    : 'Deselect ${selectedApps.length.toString()}'),
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
                          showDialog<List<String>?>(
                              context: context,
                              builder: (BuildContext ctx) {
                                return GeneratedFormModal(
                                  title: 'Remove Selected Apps?',
                                  items: const [],
                                  defaultValues: const [],
                                  initValid: true,
                                  message:
                                      '${selectedApps.length} App${selectedApps.length == 1 ? '' : 's'} will be removed from Obtainium but remain installed. You still need to uninstall ${selectedApps.length == 1 ? 'it' : 'them'} manually.',
                                );
                              }).then((values) {
                            if (values != null) {
                              appsProvider.removeApps(
                                  selectedApps.map((e) => e.id).toList());
                            }
                          });
                        },
                        tooltip: 'Remove Selected Apps',
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
                            List<GeneratedFormItem> formInputs = [];
                            List<String> defaultValues = [];
                            if (existingUpdateIdsAllOrSelected.isNotEmpty) {
                              formInputs.add(GeneratedFormItem(
                                  label:
                                      'Update ${existingUpdateIdsAllOrSelected.length} App${existingUpdateIdsAllOrSelected.length == 1 ? '' : 's'}',
                                  type: FormItemType.bool,
                                  key: 'updates'));
                              defaultValues.add('true');
                            }
                            if (newInstallIdsAllOrSelected.isNotEmpty) {
                              formInputs.add(GeneratedFormItem(
                                  label:
                                      'Install ${newInstallIdsAllOrSelected.length} new App${newInstallIdsAllOrSelected.length == 1 ? '' : 's'}',
                                  type: FormItemType.bool,
                                  key: 'installs'));
                              defaultValues
                                  .add(defaultValues.isEmpty ? 'true' : '');
                            }
                            if (trackOnlyUpdateIdsAllOrSelected.isNotEmpty) {
                              formInputs.add(GeneratedFormItem(
                                  label:
                                      'Mark ${trackOnlyUpdateIdsAllOrSelected.length} Track-Only\nApp${trackOnlyUpdateIdsAllOrSelected.length == 1 ? '' : 's'} as Updated',
                                  type: FormItemType.bool,
                                  key: 'trackonlies'));
                              defaultValues
                                  .add(defaultValues.isEmpty ? 'true' : '');
                            }
                            showDialog<List<String>?>(
                                context: context,
                                builder: (BuildContext ctx) {
                                  return GeneratedFormModal(
                                    title:
                                        'Install ${existingUpdateIdsAllOrSelected.length + newInstallIdsAllOrSelected.length + trackOnlyUpdateIdsAllOrSelected.length} Apps?',
                                    items: formInputs.map((e) => [e]).toList(),
                                    defaultValues: defaultValues,
                                    initValid: true,
                                  );
                                }).then((values) {
                              if (values != null) {
                                if (values.isEmpty) {
                                  values = defaultValues;
                                }
                                bool shouldInstallUpdates =
                                    findGeneratedFormValueByKey(
                                            formInputs, values, 'updates') ==
                                        'true';
                                bool shouldInstallNew =
                                    findGeneratedFormValueByKey(
                                            formInputs, values, 'installs') ==
                                        'true';
                                bool shouldMarkTrackOnlies =
                                    findGeneratedFormValueByKey(formInputs,
                                            values, 'trackonlies') ==
                                        'true';
                                settingsProvider
                                    .getInstallPermission()
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
                                      .downloadAndInstallLatestApps(
                                          toInstall, context)
                                      .catchError((e) {
                                    showError(e, context);
                                  });
                                });
                              }
                            });
                          },
                    tooltip:
                        'Install/Update${selectedApps.isEmpty ? ' ' : ' Selected '}Apps',
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
                                                                  title: Text(
                                                                      'Mark ${selectedApps.length} Selected Apps as Updated?'),
                                                                  content:
                                                                      const Text(
                                                                          'Only applies to installed but out of date Apps.'),
                                                                  actions: [
                                                                    TextButton(
                                                                        onPressed:
                                                                            () {
                                                                          Navigator.of(context)
                                                                              .pop();
                                                                        },
                                                                        child: const Text(
                                                                            'No')),
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
                                                                        child: const Text(
                                                                            'Yes'))
                                                                  ],
                                                                );
                                                              }).whenComplete(() {
                                                            Navigator.of(
                                                                    context)
                                                                .pop();
                                                          });
                                                        },
                                              tooltip:
                                                  'Mark Selected Apps as Updated',
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
                                            tooltip:
                                                '${selectedApps.where((element) => element.pinned).isEmpty ? 'Pin to' : 'Unpin from'} top',
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
                                                  subject:
                                                      '${selectedApps.length} Selected App URLs from Obtainium');
                                              Navigator.of(context).pop();
                                            },
                                            tooltip: 'Share Selected App URLs',
                                            icon: const Icon(Icons.share),
                                          ),
                                          IconButton(
                                            onPressed: () {
                                              showDialog(
                                                  context: context,
                                                  builder: (BuildContext ctx) {
                                                    return GeneratedFormModal(
                                                      title:
                                                          'Reset Install Status for Selected Apps?',
                                                      items: const [],
                                                      defaultValues: const [],
                                                      initValid: true,
                                                      message:
                                                          'The install status of ${selectedApps.length} App${selectedApps.length == 1 ? '' : 's'} will be reset.\n\nThis can help when the App version shown in Obtainium is incorrect due to failed updates or other issues.',
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
                                            tooltip: 'Reset Install Status',
                                            icon: const Icon(
                                                Icons.restore_page_outlined),
                                          ),
                                        ]),
                                  ),
                                );
                              });
                        },
                        tooltip: 'More',
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
                  ? 'Remove Out-of-Date App Filter'
                  : 'Show Out-of-Date Apps Only',
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
                      filter == null ? 'Filter' : 'Filter *',
                      style: TextStyle(
                          fontWeight: filter == null
                              ? FontWeight.normal
                              : FontWeight.bold),
                    ),
                    onPressed: () {
                      showDialog<List<String>?>(
                          context: context,
                          builder: (BuildContext ctx) {
                            return GeneratedFormModal(
                                title: 'Filter Apps',
                                items: [
                                  [
                                    GeneratedFormItem(
                                        label: 'App Name', required: false),
                                    GeneratedFormItem(
                                        label: 'Author', required: false)
                                  ],
                                  [
                                    GeneratedFormItem(
                                        label: 'Up to Date Apps',
                                        type: FormItemType.bool)
                                  ],
                                  [
                                    GeneratedFormItem(
                                        label: 'Non-Installed Apps',
                                        type: FormItemType.bool)
                                  ]
                                ],
                                defaultValues: filter == null
                                    ? AppsFilter().toValuesArray()
                                    : filter!.toValuesArray());
                          }).then((values) {
                        if (values != null) {
                          setState(() {
                            filter = AppsFilter.fromValuesArray(values);
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

  AppsFilter(
      {this.nameFilter = '',
      this.authorFilter = '',
      this.includeUptodate = true,
      this.includeNonInstalled = true});

  List<String> toValuesArray() {
    return [
      nameFilter,
      authorFilter,
      includeUptodate ? 'true' : '',
      includeNonInstalled ? 'true' : ''
    ];
  }

  AppsFilter.fromValuesArray(List<String> values) {
    nameFilter = values[0];
    authorFilter = values[1];
    includeUptodate = values[2] == 'true';
    includeNonInstalled = values[3] == 'true';
  }

  bool isIdenticalTo(AppsFilter other) =>
      authorFilter.trim() == other.authorFilter.trim() &&
      nameFilter.trim() == other.nameFilter.trim() &&
      includeUptodate == other.includeUptodate &&
      includeNonInstalled == other.includeNonInstalled;
}
