import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/pages/settings.dart';
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
  AppsFilter filter = AppsFilter();
  final AppsFilter neutralFilter = AppsFilter();
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
    var listedApps = appsProvider.apps.values.toList();
    var currentFilterIsUpdatesOnly =
        filter.isIdenticalTo(updatesOnlyFilter, settingsProvider);

    selectedApps = selectedApps
        .where((element) => listedApps.map((e) => e.app).contains(element))
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

    listedApps = listedApps.where((app) {
      if (app.app.installedVersion == app.app.latestVersion &&
          !(filter.includeUptodate)) {
        return false;
      }
      if (app.app.installedVersion == null && !(filter.includeNonInstalled)) {
        return false;
      }
      if (filter.nameFilter.isNotEmpty || filter.authorFilter.isNotEmpty) {
        List<String> nameTokens = filter.nameFilter
            .split(' ')
            .where((element) => element.trim().isNotEmpty)
            .toList();
        List<String> authorTokens = filter.authorFilter
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
      if (filter.categoryFilter.isNotEmpty &&
          filter.categoryFilter
              .intersection(app.app.categories.toSet())
              .isEmpty) {
        return false;
      }
      return true;
    }).toList();

    listedApps.sort((a, b) {
      var nameA = a.installedInfo?.name ?? a.app.name;
      var nameB = b.installedInfo?.name ?? b.app.name;
      int result = 0;
      if (settingsProvider.sortColumn == SortColumnSettings.authorName) {
        result = (a.app.author + nameA).compareTo(b.app.author + nameB);
      } else if (settingsProvider.sortColumn == SortColumnSettings.nameAuthor) {
        result = (nameA + a.app.author).compareTo(nameB + b.app.author);
      } else if (settingsProvider.sortColumn ==
          SortColumnSettings.releaseDate) {
        result = (a.app.releaseDate)?.compareTo(
                b.app.releaseDate ?? DateTime.fromMicrosecondsSinceEpoch(0)) ??
            0;
      }
      return result;
    });

    if (settingsProvider.sortOrder == SortOrderSettings.descending) {
      listedApps = listedApps.reversed.toList();
    }

    var existingUpdates = appsProvider.findExistingUpdates(installedOnly: true);

    var existingUpdateIdsAllOrSelected = existingUpdates
        .where((element) => selectedApps.isEmpty
            ? listedApps.where((a) => a.app.id == element).isNotEmpty
            : selectedApps.map((e) => e.id).contains(element))
        .toList();
    var newInstallIdsAllOrSelected = appsProvider
        .findExistingUpdates(nonInstalledOnly: true)
        .where((element) => selectedApps.isEmpty
            ? listedApps.where((a) => a.app.id == element).isNotEmpty
            : selectedApps.map((e) => e.id).contains(element))
        .toList();

    List<String> trackOnlyUpdateIdsAllOrSelected = [];
    existingUpdateIdsAllOrSelected = existingUpdateIdsAllOrSelected.where((id) {
      if (appsProvider.apps[id]!.app.additionalSettings['trackOnly'] == true) {
        trackOnlyUpdateIdsAllOrSelected.add(id);
        return false;
      }
      return true;
    }).toList();
    newInstallIdsAllOrSelected = newInstallIdsAllOrSelected.where((id) {
      if (appsProvider.apps[id]!.app.additionalSettings['trackOnly'] == true) {
        trackOnlyUpdateIdsAllOrSelected.add(id);
        return false;
      }
      return true;
    }).toList();

    if (settingsProvider.pinUpdates) {
      var temp = [];
      listedApps = listedApps.where((sa) {
        if (existingUpdates.contains(sa.app.id)) {
          temp.add(sa);
          return false;
        }
        return true;
      }).toList();
      listedApps = [...temp, ...listedApps];
    }

    var tempPinned = [];
    var tempNotPinned = [];
    for (var a in listedApps) {
      if (a.app.pinned) {
        tempPinned.add(a);
      } else {
        tempNotPinned.add(a);
      }
    }
    listedApps = [...tempPinned, ...tempNotPinned];

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
            if (appsProvider.loadingApps || listedApps.isEmpty)
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
                  .getSource(listedApps[index].app.url)
                  .changeLogPageFromStandardUrl(listedApps[index].app.url);
              var transparent = const Color.fromARGB(0, 0, 0, 0).value;
              var hasUpdate = listedApps[index].app.installedVersion != null &&
                  listedApps[index].app.installedVersion !=
                      listedApps[index].app.latestVersion;
              var updateButton = IconButton(
                  visualDensity: VisualDensity.compact,
                  color: Theme.of(context).colorScheme.primary,
                  tooltip:
                      listedApps[index].app.additionalSettings['trackOnly'] ==
                              true
                          ? tr('markUpdated')
                          : tr('update'),
                  onPressed: appsProvider.areDownloadsRunning()
                      ? null
                      : () {
                          appsProvider.downloadAndInstallLatestApps([
                            listedApps[index].app.id
                          ], globalNavigatorKey.currentContext).catchError((e) {
                            showError(e, context);
                          });
                        },
                  icon: Icon(
                      listedApps[index].app.additionalSettings['trackOnly'] ==
                              true
                          ? Icons.check_circle_outline
                          : Icons.install_mobile));
              return Container(
                  decoration: BoxDecoration(
                      border: Border.symmetric(
                          vertical: BorderSide(
                              width: 4,
                              color: Color(
                                  listedApps[index].app.categories.isNotEmpty
                                      ? settingsProvider.categories[
                                              listedApps[index]
                                                  .app
                                                  .categories
                                                  .first] ??
                                          transparent
                                      : transparent)))),
                  child: ListTile(
                    tileColor: listedApps[index].app.pinned
                        ? Colors.grey.withOpacity(0.1)
                        : Colors.transparent,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withOpacity(listedApps[index].app.pinned ? 0.2 : 0.1),
                    selected: selectedApps.contains(listedApps[index].app),
                    onLongPress: () {
                      toggleAppSelected(listedApps[index].app);
                    },
                    leading: listedApps[index].installedInfo != null
                        ? Image.memory(
                            listedApps[index].installedInfo!.icon!,
                            gaplessPlayback: true,
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                                Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.rotationZ(0.31),
                                  child: Image(
                                    image: const AssetImage(
                                        'assets/graphics/icon.png'),
                                    color: Colors.white.withOpacity(0.1),
                                    colorBlendMode: BlendMode.modulate,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              ]),
                    title: Text(
                      maxLines: 1,
                      listedApps[index].installedInfo?.name ??
                          listedApps[index].app.name,
                      style: TextStyle(
                        overflow: TextOverflow.ellipsis,
                        fontWeight: listedApps[index].app.pinned
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                        tr('byX', args: [listedApps[index].app.author]),
                        maxLines: 1,
                        style: TextStyle(
                            overflow: TextOverflow.ellipsis,
                            fontWeight: listedApps[index].app.pinned
                                ? FontWeight.bold
                                : FontWeight.normal)),
                    trailing: listedApps[index].downloadProgress != null
                        ? Text(tr('percentProgress', args: [
                            listedApps[index]
                                    .downloadProgress
                                    ?.toInt()
                                    .toString() ??
                                '100'
                          ]))
                        : (Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              hasUpdate
                                  ? updateButton
                                  : const SizedBox.shrink(),
                              hasUpdate
                                  ? const SizedBox(
                                      width: 10,
                                    )
                                  : const SizedBox.shrink(),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                            constraints: const BoxConstraints(
                                                maxWidth: 150),
                                            child: Text(
                                              '${listedApps[index].app.installedVersion ?? tr('notInstalled')}${listedApps[index].app.additionalSettings['trackOnly'] == true ? ' ${tr('estimateInBrackets')}' : ''}',
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.end,
                                            )),
                                      ]),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      GestureDetector(
                                          onTap: changesUrl == null
                                              ? null
                                              : () {
                                                  launchUrlString(changesUrl,
                                                      mode: LaunchMode
                                                          .externalApplication);
                                                },
                                          child: Text(
                                            listedApps[index].app.releaseDate ==
                                                    null
                                                ? tr('changes')
                                                : DateFormat('yyyy-MM-dd')
                                                    .format(listedApps[index]
                                                        .app
                                                        .releaseDate!),
                                            style: const TextStyle(
                                                fontStyle: FontStyle.italic,
                                                decoration:
                                                    TextDecoration.underline),
                                          ))
                                    ],
                                  ),
                                ],
                              )
                            ],
                          )),
                    onTap: () {
                      if (selectedApps.isNotEmpty) {
                        toggleAppSelected(listedApps[index].app);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  AppPage(appId: listedApps[index].app.id)),
                        );
                      }
                    },
                  ));
            }, childCount: listedApps.length))
          ])),
      persistentFooterButtons: appsProvider.apps.isEmpty
          ? null
          : [
              Row(
                children: [
                  selectedApps.isEmpty
                      ? TextButton.icon(
                          style: const ButtonStyle(
                              visualDensity: VisualDensity.compact),
                          onPressed: () {
                            selectThese(listedApps.map((e) => e.app).toList());
                          },
                          icon: Icon(
                            Icons.select_all_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          label: Text(listedApps.length.toString()))
                      : TextButton.icon(
                          style: const ButtonStyle(
                              visualDensity: VisualDensity.compact),
                          onPressed: () {
                            selectedApps.isEmpty
                                ? selectThese(
                                    listedApps.map((e) => e.app).toList())
                                : clearSelected();
                          },
                          icon: Icon(
                            selectedApps.isEmpty
                                ? Icons.select_all_outlined
                                : Icons.deselect_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          label: Text(selectedApps.length.toString())),
                  const VerticalDivider(),
                  Expanded(
                      child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: selectedApps.isEmpty
                                    ? null
                                    : () {
                                        appsProvider.removeAppsWithModal(
                                            context, selectedApps.toList());
                                      },
                                tooltip: tr('removeSelectedApps'),
                                icon: const Icon(Icons.delete_outline_outlined),
                              ),
                              IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: appsProvider
                                              .areDownloadsRunning() ||
                                          (existingUpdateIdsAllOrSelected
                                                  .isEmpty &&
                                              newInstallIdsAllOrSelected
                                                  .isEmpty &&
                                              trackOnlyUpdateIdsAllOrSelected
                                                  .isEmpty)
                                      ? null
                                      : () {
                                          HapticFeedback.heavyImpact();
                                          List<GeneratedFormItem> formItems =
                                              [];
                                          if (existingUpdateIdsAllOrSelected
                                              .isNotEmpty) {
                                            formItems.add(GeneratedFormSwitch(
                                                'updates',
                                                label: tr('updateX', args: [
                                                  plural(
                                                      'apps',
                                                      existingUpdateIdsAllOrSelected
                                                          .length)
                                                ]),
                                                defaultValue: true));
                                          }
                                          if (newInstallIdsAllOrSelected
                                              .isNotEmpty) {
                                            formItems.add(GeneratedFormSwitch(
                                                'installs',
                                                label: tr('installX', args: [
                                                  plural(
                                                      'apps',
                                                      newInstallIdsAllOrSelected
                                                          .length)
                                                ]),
                                                defaultValue:
                                                    existingUpdateIdsAllOrSelected
                                                        .isNotEmpty));
                                          }
                                          if (trackOnlyUpdateIdsAllOrSelected
                                              .isNotEmpty) {
                                            formItems.add(GeneratedFormSwitch(
                                                'trackonlies',
                                                label: tr(
                                                    'markXTrackOnlyAsUpdated',
                                                    args: [
                                                      plural(
                                                          'apps',
                                                          trackOnlyUpdateIdsAllOrSelected
                                                              .length)
                                                    ]),
                                                defaultValue:
                                                    existingUpdateIdsAllOrSelected
                                                            .isNotEmpty ||
                                                        newInstallIdsAllOrSelected
                                                            .isNotEmpty));
                                          }
                                          showDialog<Map<String, dynamic>?>(
                                              context: context,
                                              builder: (BuildContext ctx) {
                                                var totalApps = existingUpdateIdsAllOrSelected
                                                        .length +
                                                    newInstallIdsAllOrSelected
                                                        .length +
                                                    trackOnlyUpdateIdsAllOrSelected
                                                        .length;
                                                return GeneratedFormModal(
                                                  title: tr('changeX', args: [
                                                    plural('apps', totalApps)
                                                  ]),
                                                  items: formItems
                                                      .map((e) => [e])
                                                      .toList(),
                                                  initValid: true,
                                                );
                                              }).then((values) {
                                            if (values != null) {
                                              if (values.isEmpty) {
                                                values =
                                                    getDefaultValuesFromFormItems(
                                                        [formItems]);
                                              }
                                              bool shouldInstallUpdates =
                                                  values['updates'] == true;
                                              bool shouldInstallNew =
                                                  values['installs'] == true;
                                              bool shouldMarkTrackOnlies =
                                                  values['trackonlies'] == true;
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
                                                  toInstall.addAll(
                                                      existingUpdateIdsAllOrSelected);
                                                }
                                                if (shouldInstallNew) {
                                                  toInstall.addAll(
                                                      newInstallIdsAllOrSelected);
                                                }
                                                if (shouldMarkTrackOnlies) {
                                                  toInstall.addAll(
                                                      trackOnlyUpdateIdsAllOrSelected);
                                                }
                                                appsProvider
                                                    .downloadAndInstallLatestApps(
                                                        toInstall,
                                                        globalNavigatorKey
                                                            .currentContext)
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
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: selectedApps.isEmpty
                                    ? null
                                    : () async {
                                        try {
                                          Set<String>? preselected;
                                          var showPrompt = false;
                                          for (var element in selectedApps) {
                                            var currentCats =
                                                element.categories.toSet();
                                            if (preselected == null) {
                                              preselected = currentCats;
                                            } else {
                                              if (!settingsProvider.setEqual(
                                                  currentCats, preselected)) {
                                                showPrompt = true;
                                                break;
                                              }
                                            }
                                          }
                                          var cont = true;
                                          if (showPrompt) {
                                            cont = await showDialog<
                                                        Map<String, dynamic>?>(
                                                    context: context,
                                                    builder:
                                                        (BuildContext ctx) {
                                                      return GeneratedFormModal(
                                                        title: tr('categorize'),
                                                        items: const [],
                                                        initValid: true,
                                                        message: tr(
                                                            'selectedCategorizeWarning'),
                                                      );
                                                    }) !=
                                                null;
                                          }
                                          if (cont) {
                                            // ignore: use_build_context_synchronously
                                            await showDialog<
                                                    Map<String, dynamic>?>(
                                                context: context,
                                                builder: (BuildContext ctx) {
                                                  return GeneratedFormModal(
                                                    title: tr('categorize'),
                                                    items: const [],
                                                    initValid: true,
                                                    singleNullReturnButton:
                                                        tr('continue'),
                                                    additionalWidgets: [
                                                      CategoryEditorSelector(
                                                        preselected: !showPrompt
                                                            ? preselected ?? {}
                                                            : {},
                                                        showLabelWhenNotEmpty:
                                                            false,
                                                        onSelected:
                                                            (categories) {
                                                          appsProvider.saveApps(
                                                              selectedApps
                                                                  .map((e) {
                                                            e.categories =
                                                                categories;
                                                            return e;
                                                          }).toList());
                                                        },
                                                      )
                                                    ],
                                                  );
                                                });
                                          }
                                        } catch (err) {
                                          showError(err, context);
                                        }
                                      },
                                tooltip: tr('categorize'),
                                icon: const Icon(Icons.category_outlined),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: selectedApps.isEmpty
                                    ? null
                                    : () {
                                        showDialog(
                                            context: context,
                                            builder: (BuildContext ctx) {
                                              return AlertDialog(
                                                scrollable: true,
                                                content: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 6),
                                                  child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceAround,
                                                      children: [
                                                        IconButton(
                                                            onPressed: appsProvider
                                                                    .areDownloadsRunning()
                                                                ? null
                                                                : () {
                                                                    showDialog(
                                                                        context:
                                                                            context,
                                                                        builder:
                                                                            (BuildContext
                                                                                ctx) {
                                                                          return AlertDialog(
                                                                            title:
                                                                                Text(tr('markXSelectedAppsAsUpdated', args: [
                                                                              selectedApps.length.toString()
                                                                            ])),
                                                                            content:
                                                                                Text(
                                                                              tr('onlyWorksWithNonVersionDetectApps'),
                                                                              style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
                                                                            ),
                                                                            actions: [
                                                                              TextButton(
                                                                                  onPressed: () {
                                                                                    Navigator.of(context).pop();
                                                                                  },
                                                                                  child: Text(tr('no'))),
                                                                              TextButton(
                                                                                  onPressed: () {
                                                                                    HapticFeedback.selectionClick();
                                                                                    appsProvider.saveApps(selectedApps.map((a) {
                                                                                      if (a.installedVersion != null && a.additionalSettings['versionDetection'] != 'standardVersionDetection') {
                                                                                        a.installedVersion = a.latestVersion;
                                                                                      }
                                                                                      return a;
                                                                                    }).toList());

                                                                                    Navigator.of(context).pop();
                                                                                  },
                                                                                  child: Text(tr('yes')))
                                                                            ],
                                                                          );
                                                                        }).whenComplete(() {
                                                                      Navigator.of(
                                                                              context)
                                                                          .pop();
                                                                    });
                                                                  },
                                                            tooltip: tr(
                                                                'markSelectedAppsUpdated'),
                                                            icon: const Icon(
                                                                Icons.done)),
                                                        IconButton(
                                                          onPressed: () {
                                                            var pinStatus = selectedApps
                                                                .where((element) =>
                                                                    element
                                                                        .pinned)
                                                                .isEmpty;
                                                            appsProvider
                                                                .saveApps(
                                                                    selectedApps
                                                                        .map(
                                                                            (e) {
                                                              e.pinned =
                                                                  pinStatus;
                                                              return e;
                                                            }).toList());
                                                            Navigator.of(
                                                                    context)
                                                                .pop();
                                                          },
                                                          tooltip: selectedApps
                                                                  .where((element) =>
                                                                      element
                                                                          .pinned)
                                                                  .isEmpty
                                                              ? tr('pinToTop')
                                                              : tr(
                                                                  'unpinFromTop'),
                                                          icon: Icon(selectedApps
                                                                  .where((element) =>
                                                                      element
                                                                          .pinned)
                                                                  .isEmpty
                                                              ? Icons
                                                                  .bookmark_outline_rounded
                                                              : Icons
                                                                  .bookmark_remove_outlined),
                                                        ),
                                                        IconButton(
                                                          onPressed: () {
                                                            String urls = '';
                                                            for (var a
                                                                in selectedApps) {
                                                              urls +=
                                                                  '${a.url}\n';
                                                            }
                                                            urls =
                                                                urls.substring(
                                                                    0,
                                                                    urls.length -
                                                                        1);
                                                            Share.share(urls,
                                                                subject: tr(
                                                                    'selectedAppURLsFromObtainium'));
                                                            Navigator.of(
                                                                    context)
                                                                .pop();
                                                          },
                                                          tooltip: tr(
                                                              'shareSelectedAppURLs'),
                                                          icon: const Icon(
                                                              Icons.share),
                                                        ),
                                                        IconButton(
                                                          onPressed: () {
                                                            showDialog(
                                                                context:
                                                                    context,
                                                                builder:
                                                                    (BuildContext
                                                                        ctx) {
                                                                  return GeneratedFormModal(
                                                                    title: tr(
                                                                        'resetInstallStatusForSelectedAppsQuestion'),
                                                                    items: const [],
                                                                    initValid:
                                                                        true,
                                                                    message: tr(
                                                                        'installStatusOfXWillBeResetExplanation',
                                                                        args: [
                                                                          plural(
                                                                              'app',
                                                                              selectedApps.length)
                                                                        ]),
                                                                  );
                                                                }).then((values) {
                                                              if (values !=
                                                                  null) {
                                                                appsProvider.saveApps(
                                                                    selectedApps
                                                                        .map(
                                                                            (e) {
                                                                  e.installedVersion =
                                                                      null;
                                                                  return e;
                                                                }).toList());
                                                              }
                                                            }).whenComplete(() {
                                                              Navigator.of(
                                                                      context)
                                                                  .pop();
                                                            });
                                                          },
                                                          tooltip: tr(
                                                              'resetInstallStatus'),
                                                          icon: const Icon(Icons
                                                              .restore_page_outlined),
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
                          ))),
                  const VerticalDivider(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() {
                        if (currentFilterIsUpdatesOnly) {
                          filter = AppsFilter();
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
                  TextButton.icon(
                      style: const ButtonStyle(
                          visualDensity: VisualDensity.compact),
                      label: Text(
                        filter.isIdenticalTo(neutralFilter, settingsProvider)
                            ? tr('filter')
                            : tr('filterActive'),
                        style: TextStyle(
                            fontWeight: filter.isIdenticalTo(
                                    neutralFilter, settingsProvider)
                                ? FontWeight.normal
                                : FontWeight.bold),
                      ),
                      onPressed: () {
                        showDialog<Map<String, dynamic>?>(
                            context: context,
                            builder: (BuildContext ctx) {
                              var vals = filter.toFormValuesMap();
                              return GeneratedFormModal(
                                initValid: true,
                                title: tr('filterApps'),
                                items: [
                                  [
                                    GeneratedFormTextField('appName',
                                        label: tr('appName'),
                                        required: false,
                                        defaultValue: vals['appName']),
                                    GeneratedFormTextField('author',
                                        label: tr('author'),
                                        required: false,
                                        defaultValue: vals['author'])
                                  ],
                                  [
                                    GeneratedFormSwitch('upToDateApps',
                                        label: tr('upToDateApps'),
                                        defaultValue: vals['upToDateApps'])
                                  ],
                                  [
                                    GeneratedFormSwitch('nonInstalledApps',
                                        label: tr('nonInstalledApps'),
                                        defaultValue: vals['nonInstalledApps'])
                                  ]
                                ],
                                additionalWidgets: [
                                  const SizedBox(
                                    height: 16,
                                  ),
                                  CategoryEditorSelector(
                                    preselected: filter.categoryFilter,
                                    onSelected: (categories) {
                                      filter.categoryFilter =
                                          categories.toSet();
                                    },
                                  )
                                ],
                              );
                            }).then((values) {
                          if (values != null) {
                            setState(() {
                              filter.setFormValuesFromMap(values);
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
  late Set<String> categoryFilter;

  AppsFilter(
      {this.nameFilter = '',
      this.authorFilter = '',
      this.includeUptodate = true,
      this.includeNonInstalled = true,
      this.categoryFilter = const {}});

  Map<String, dynamic> toFormValuesMap() {
    return {
      'appName': nameFilter,
      'author': authorFilter,
      'upToDateApps': includeUptodate,
      'nonInstalledApps': includeNonInstalled
    };
  }

  setFormValuesFromMap(Map<String, dynamic> values) {
    nameFilter = values['appName']!;
    authorFilter = values['author']!;
    includeUptodate = values['upToDateApps'];
    includeNonInstalled = values['nonInstalledApps'];
  }

  bool isIdenticalTo(AppsFilter other, SettingsProvider settingsProvider) =>
      authorFilter.trim() == other.authorFilter.trim() &&
      nameFilter.trim() == other.nameFilter.trim() &&
      includeUptodate == other.includeUptodate &&
      includeNonInstalled == other.includeNonInstalled &&
      settingsProvider.setEqual(categoryFilter, other.categoryFilter);
}
