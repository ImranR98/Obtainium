import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:provider/provider.dart';

class AppsPage extends StatefulWidget {
  const AppsPage({super.key});

  @override
  State<AppsPage> createState() => AppsPageState();
}

class AppsPageState extends State<AppsPage> {
  AppsFilter? filter;
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
    var existingUpdateAppIds = appsProvider.getExistingUpdates();
    var sortedApps = appsProvider.apps.values.toList();

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
            filter!.onlyNonLatest) {
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

    if (settingsProvider.sortOrder == SortOrderSettings.ascending) {
      sortedApps = sortedApps.reversed.toList();
    }

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
                                  : 'No Search Results',
                              style: Theme.of(context).textTheme.headlineMedium,
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
                title: Text(sortedApps[index].app.name),
                subtitle: Text('By ${sortedApps[index].app.author}'),
                trailing: sortedApps[index].downloadProgress != null
                    ? Text(
                        'Downloading - ${sortedApps[index].downloadProgress?.toInt()}%')
                    : (sortedApps[index].app.installedVersion != null &&
                            sortedApps[index].app.installedVersion !=
                                sortedApps[index].app.latestVersion
                        ? const Text('Update Available')
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
            TextButton.icon(
                onPressed: () {
                  selectedIds.isEmpty
                      ? selectThese(sortedApps.map((e) => e.app.id).toList())
                      : clearSelected();
                },
                icon: Icon(selectedIds.isEmpty
                    ? Icons.select_all_outlined
                    : Icons.deselect_outlined),
                label: Text(selectedIds.isEmpty
                    ? 'Select All'
                    : 'Deselect ${selectedIds.length.toString()}')),
            const VerticalDivider(),
            const Spacer(),
            selectedIds.isEmpty
                ? const SizedBox()
                : IconButton(
                    onPressed: () {
                      // TODO: Delete selected Apps after confirming
                    },
                    icon: const Icon(Icons.install_mobile_outlined)),
            selectedIds.isEmpty
                ? const SizedBox()
                : IconButton(
                    onPressed: () {
                      // TODO: Install selected Apps if they are not up to date after confirming (replace existing button)
                    },
                    icon: const Icon(Icons.delete_outline_rounded)),
            existingUpdateAppIds.isEmpty || filter != null
                ? const SizedBox()
                : IconButton(
                    onPressed: appsProvider.areDownloadsRunning()
                        ? null
                        : () {
                            HapticFeedback.heavyImpact();
                            settingsProvider.getInstallPermission().then((_) {
                              appsProvider.downloadAndInstallLatestApp(
                                  existingUpdateAppIds, context);
                            });
                          },
                    icon: const Icon(Icons.install_mobile_outlined),
                  ),
            appsProvider.apps.isEmpty
                ? const SizedBox()
                : IconButton(
                    onPressed: () {
                      showDialog<List<String>?>(
                          context: context,
                          builder: (BuildContext ctx) {
                            return GeneratedFormModal(
                                title: 'Filter Apps',
                                items: [
                                  [
                                    GeneratedFormItem(
                                        label: "App Name", required: false),
                                    GeneratedFormItem(
                                        label: "Author", required: false)
                                  ],
                                  [
                                    GeneratedFormItem(
                                        label: "Ignore Up-to-Date Apps",
                                        type: FormItemType.bool)
                                  ]
                                ],
                                defaultValues: filter == null
                                    ? []
                                    : [
                                        filter!.nameFilter,
                                        filter!.authorFilter,
                                        filter!.onlyNonLatest ? 'true' : ''
                                      ]);
                          }).then((values) {
                        if (values != null &&
                            values
                                .where((element) => element.isNotEmpty)
                                .isNotEmpty) {
                          setState(() {
                            filter = AppsFilter(
                                nameFilter: values[0],
                                authorFilter: values[1],
                                onlyNonLatest: values[2] == "true");
                          });
                        } else {
                          setState(() {
                            filter = null;
                          });
                        }
                      });
                    },
                    icon: Icon(
                        filter == null ? Icons.search : Icons.manage_search))
          ],
        ),
      ],
    );
  }
}

class AppsFilter {
  late String nameFilter;
  late String authorFilter;
  late bool onlyNonLatest;

  AppsFilter(
      {this.nameFilter = "",
      this.authorFilter = "",
      this.onlyNonLatest = false});
}
