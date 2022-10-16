import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
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
  Set<String> selectedIds = {};

  clearSelected() {
    if (selectedIds.isNotEmpty) {
      setState(() {
        selectedIds.clear();
      });
      return true;
    }
    return false;
  }

  selectThese(List<String> appIds) {
    if (selectedIds.isEmpty) {
      setState(() {
        for (var a in appIds) {
          selectedIds.add(a);
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

    selectedIds = selectedIds
        .where((element) => sortedApps.map((e) => e.app.id).contains(element))
        .toSet();

    toggleAppSelected(String appId) {
      setState(() {
        if (selectedIds.contains(appId)) {
          selectedIds.remove(appId);
        } else {
          selectedIds.add(appId);
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
          if (!app.app.name.toLowerCase().contains(t.toLowerCase())) {
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
      int result = 0;
      if (settingsProvider.sortColumn == SortColumnSettings.authorName) {
        result =
            (a.app.author + a.app.name).compareTo(b.app.author + b.app.name);
      } else if (settingsProvider.sortColumn == SortColumnSettings.nameAuthor) {
        result =
            (a.app.name + a.app.author).compareTo(b.app.name + b.app.author);
      }
      return result;
    });

    if (settingsProvider.sortOrder == SortOrderSettings.descending) {
      sortedApps = sortedApps.reversed.toList();
    }

    var existingUpdateIdsAllOrSelected = appsProvider
        .getExistingUpdates(installedOnly: true)
        .where((element) => selectedIds.isEmpty
            ? sortedApps.where((a) => a.app.id == element).isNotEmpty
            : selectedIds.contains(element))
        .toList();
    var newInstallIdsAllOrSelected = appsProvider
        .getExistingUpdates(nonInstalledOnly: true)
        .where((element) => selectedIds.isEmpty
            ? sortedApps.where((a) => a.app.id == element).isNotEmpty
            : selectedIds.contains(element))
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
          onRefresh: () {
            HapticFeedback.lightImpact();
            return appsProvider.checkUpdates().catchError((e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(e.toString())),
              );
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
            SliverList(
                delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) {
              return ListTile(
                selectedTileColor:
                    Theme.of(context).colorScheme.primary.withOpacity(0.1),
                selected: selectedIds.contains(sortedApps[index].app.id),
                onLongPress: () {
                  toggleAppSelected(sortedApps[index].app.id);
                },
                leading: sortedApps[index].icon != null
                    ? Image.memory(sortedApps[index].icon!)
                    : null,
                title: Text(sortedApps[index].app.name),
                subtitle: Text('By ${sortedApps[index].app.author}'),
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
                              const Text('Update Available'),
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
                        : Text(sortedApps[index].app.installedVersion ??
                            'Not Installed')),
                onTap: () {
                  if (selectedIds.isNotEmpty) {
                    toggleAppSelected(sortedApps[index].app.id);
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
                  selectedIds.isEmpty
                      ? selectThese(sortedApps.map((e) => e.app.id).toList())
                      : clearSelected();
                },
                icon: Icon(
                  selectedIds.isEmpty
                      ? Icons.select_all_outlined
                      : Icons.deselect_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                tooltip: selectedIds.isEmpty
                    ? 'Select All'
                    : 'Deselect ${selectedIds.length.toString()}'),
            const VerticalDivider(),
            Expanded(
                child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                selectedIds.isEmpty
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
                                      '${selectedIds.length} App${selectedIds.length == 1 ? '' : 's'} will be removed from Obtainium but remain installed. You still need to uninstall ${selectedIds.length == 1 ? 'it' : 'them'} manually.',
                                );
                              }).then((values) {
                            if (values != null) {
                              appsProvider.removeApps(selectedIds.toList());
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
                                newInstallIdsAllOrSelected.isEmpty)
                        ? null
                        : () {
                            HapticFeedback.heavyImpact();
                            List<List<GeneratedFormItem>> formInputs = [];
                            if (existingUpdateIdsAllOrSelected.isNotEmpty &&
                                newInstallIdsAllOrSelected.isNotEmpty) {
                              formInputs.add([
                                GeneratedFormItem(
                                    label:
                                        'Update ${existingUpdateIdsAllOrSelected.length} App${existingUpdateIdsAllOrSelected.length == 1 ? '' : 's'}',
                                    type: FormItemType.bool)
                              ]);
                              formInputs.add([
                                GeneratedFormItem(
                                    label:
                                        'Install ${newInstallIdsAllOrSelected.length} new App${newInstallIdsAllOrSelected.length == 1 ? '' : 's'}',
                                    type: FormItemType.bool)
                              ]);
                            }
                            showDialog<List<String>?>(
                                context: context,
                                builder: (BuildContext ctx) {
                                  return GeneratedFormModal(
                                    title:
                                        'Install${selectedIds.isEmpty ? ' ' : ' Selected '}Apps?',
                                    message:
                                        '${existingUpdateIdsAllOrSelected.length} update${existingUpdateIdsAllOrSelected.length == 1 ? '' : 's'} and ${newInstallIdsAllOrSelected.length} new install${newInstallIdsAllOrSelected.length == 1 ? '' : 's'}.',
                                    items: formInputs,
                                    defaultValues: const ['true', 'true'],
                                    initValid: true,
                                  );
                                }).then((values) {
                              if (values != null) {
                                bool shouldInstallUpdates =
                                    values.length < 2 || values[0] == 'true';
                                bool shouldInstallNew =
                                    values.length < 2 || values[1] == 'true';
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
                                  appsProvider
                                      .downloadAndInstallLatestApps(
                                          toInstall, context)
                                      .catchError((e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
                                    );
                                  });
                                });
                              }
                            });
                          },
                    tooltip:
                        'Install/Update${selectedIds.isEmpty ? ' ' : ' Selected '}Apps',
                    icon: const Icon(
                      Icons.file_download_outlined,
                    )),
                selectedIds.isEmpty
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
                                            MainAxisAlignment.spaceBetween,
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
                                                                      'Mark ${selectedIds.length} Selected Apps as Not Installed?'),
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
                                                                              .saveApps(selectedIds.map((e) {
                                                                            var a =
                                                                                appsProvider.apps[e]!.app;
                                                                            a.installedVersion =
                                                                                null;
                                                                            return a;
                                                                          }).toList());

                                                                          Navigator.of(context)
                                                                              .pop();
                                                                        },
                                                                        child: const Text(
                                                                            'Yes'))
                                                                  ],
                                                                );
                                                              });
                                                        },
                                              tooltip:
                                                  'Mark Selected Apps as Not Installed',
                                              icon: const Icon(
                                                  Icons.no_cell_outlined)),
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
                                                                      'Mark ${selectedIds.length} Selected Apps as Installed/Updated?'),
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
                                                                              .saveApps(selectedIds.map((e) {
                                                                            var a =
                                                                                appsProvider.apps[e]!.app;
                                                                            a.installedVersion =
                                                                                a.latestVersion;
                                                                            return a;
                                                                          }).toList());

                                                                          Navigator.of(context)
                                                                              .pop();
                                                                        },
                                                                        child: const Text(
                                                                            'Yes'))
                                                                  ],
                                                                );
                                                              });
                                                        },
                                              tooltip:
                                                  'Mark Selected Apps as Installed/Updated',
                                              icon: const Icon(Icons.done)),
                                          IconButton(
                                            onPressed: () {
                                              String urls = '';
                                              for (var id in selectedIds) {
                                                urls +=
                                                    '${appsProvider.apps[id]!.app.url}\n';
                                              }
                                              urls = urls.substring(
                                                  0, urls.length - 1);
                                              Share.share(urls,
                                                  subject:
                                                      '${selectedIds.length} Selected App URLs from Obtainium');
                                            },
                                            tooltip: 'Share Selected App URLs',
                                            icon: const Icon(Icons.share),
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
