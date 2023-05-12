import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
import 'package:markdown/markdown.dart' as md;

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
  Set<String> selectedAppIds = {};
  DateTime? refreshingSince;

  clearSelected() {
    if (selectedAppIds.isNotEmpty) {
      setState(() {
        selectedAppIds.clear();
      });
      return true;
    }
    return false;
  }

  selectThese(List<App> apps) {
    if (selectedAppIds.isEmpty) {
      setState(() {
        for (var a in apps) {
          selectedAppIds.add(a.id);
        }
      });
    }
  }

  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  Widget build(BuildContext context) {
    var appsProvider = context.watch<AppsProvider>();
    var settingsProvider = context.watch<SettingsProvider>();
    var sourceProvider = SourceProvider();
    var listedApps = appsProvider.getAppValues().toList();
    var currentFilterIsUpdatesOnly =
        filter.isIdenticalTo(updatesOnlyFilter, settingsProvider);

    refresh() {
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
    }

    if (!appsProvider.loadingApps &&
        appsProvider.apps.isNotEmpty &&
        settingsProvider.checkJustStarted() &&
        settingsProvider.checkOnStart) {
      _refreshIndicatorKey.currentState?.show();
    }

    selectedAppIds = selectedAppIds
        .where((element) => listedApps.map((e) => e.app.id).contains(element))
        .toSet();

    toggleAppSelected(App app) {
      setState(() {
        if (selectedAppIds.map((e) => e).contains(app.id)) {
          selectedAppIds.removeWhere((a) => a == app.id);
        } else {
          selectedAppIds.add(app.id);
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
          if (!app.name.toLowerCase().contains(t.toLowerCase())) {
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
      if (filter.sourceFilter.isNotEmpty &&
          sourceProvider
                  .getSource(app.app.url,
                      overrideSource: app.app.overrideSource)
                  .runtimeType
                  .toString() !=
              filter.sourceFilter) {
        return false;
      }
      return true;
    }).toList();

    listedApps.sort((a, b) {
      int result = 0;
      if (settingsProvider.sortColumn == SortColumnSettings.authorName) {
        result = ((a.app.author + a.name).toLowerCase())
            .compareTo((b.app.author + b.name).toLowerCase());
      } else if (settingsProvider.sortColumn == SortColumnSettings.nameAuthor) {
        result = ((a.name + a.app.author).toLowerCase())
            .compareTo((b.name + b.app.author).toLowerCase());
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
        .where((element) => selectedAppIds.isEmpty
            ? listedApps.where((a) => a.app.id == element).isNotEmpty
            : selectedAppIds.map((e) => e).contains(element))
        .toList();
    var newInstallIdsAllOrSelected = appsProvider
        .findExistingUpdates(nonInstalledOnly: true)
        .where((element) => selectedAppIds.isEmpty
            ? listedApps.where((a) => a.app.id == element).isNotEmpty
            : selectedAppIds.map((e) => e).contains(element))
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

    if (settingsProvider.buryNonInstalled) {
      var temp = [];
      listedApps = listedApps.where((sa) {
        if (sa.app.installedVersion == null) {
          temp.add(sa);
          return false;
        }
        return true;
      }).toList();
      listedApps = [...listedApps, ...temp];
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

    List<String?> getListedCategories() {
      var temp = listedApps
          .map((e) => e.app.categories.isNotEmpty ? e.app.categories : [null]);
      return temp.isNotEmpty
          ? {
              ...temp.reduce((v, e) => [...v, ...e])
            }.toList()
          : [];
    }

    var listedCategories = getListedCategories();
    listedCategories.sort((a, b) {
      return a != null && b != null
          ? a.toLowerCase().compareTo(b.toLowerCase())
          : a == null
              ? 1
              : -1;
    });

    Set<App> selectedApps = listedApps
        .map((e) => e.app)
        .where((a) => selectedAppIds.contains(a.id))
        .toSet();

    showChangeLogDialog(
        String? changesUrl, AppSource appSource, String changeLog, int index) {
      showDialog(
          context: context,
          builder: (BuildContext context) {
            return GeneratedFormModal(
              title: tr('changes'),
              items: const [],
              message: listedApps[index].app.latestVersion,
              additionalWidgets: [
                changesUrl != null
                    ? GestureDetector(
                        child: Text(
                          changesUrl,
                          style: const TextStyle(
                              decoration: TextDecoration.underline,
                              fontStyle: FontStyle.italic),
                        ),
                        onTap: () {
                          launchUrlString(changesUrl,
                              mode: LaunchMode.externalApplication);
                        },
                      )
                    : const SizedBox.shrink(),
                changesUrl != null
                    ? const SizedBox(
                        height: 16,
                      )
                    : const SizedBox.shrink(),
                appSource.changeLogIfAnyIsMarkDown
                    ? SizedBox(
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height - 350,
                        child: Markdown(
                          data: changeLog,
                          onTapLink: (text, href, title) {
                            if (href != null) {
                              launchUrlString(
                                  href.startsWith('http://') ||
                                          href.startsWith('https://')
                                      ? href
                                      : '${Uri.parse(listedApps[index].app.url).origin}/$href',
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                          extensionSet: md.ExtensionSet(
                            md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                            [
                              md.EmojiSyntax(),
                              ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes
                            ],
                          ),
                        ))
                    : Text(changeLog),
              ],
              singleNullReturnButton: tr('ok'),
            );
          });
    }

    getLoadingWidgets() {
      return [
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
              value: appsProvider
                      .getAppValues()
                      .where((element) => !(element.app.lastUpdateCheck
                              ?.isBefore(refreshingSince!) ??
                          true))
                      .length /
                  (appsProvider.apps.isNotEmpty ? appsProvider.apps.length : 1),
            ),
          )
      ];
    }

    getChangeLogFn(int appIndex) {
      AppSource appSource = SourceProvider().getSource(
          listedApps[appIndex].app.url,
          overrideSource: listedApps[appIndex].app.overrideSource);
      String? changesUrl =
          appSource.changeLogPageFromStandardUrl(listedApps[appIndex].app.url);
      String? changeLog = listedApps[appIndex].app.changeLog;
      return (changeLog == null && changesUrl == null)
          ? null
          : () {
              if (changeLog != null) {
                showChangeLogDialog(changesUrl, appSource, changeLog, appIndex);
              } else {
                launchUrlString(changesUrl!,
                    mode: LaunchMode.externalApplication);
              }
            };
    }

    getUpdateButton(int appIndex) {
      return IconButton(
          visualDensity: VisualDensity.compact,
          color: Theme.of(context).colorScheme.primary,
          tooltip:
              listedApps[appIndex].app.additionalSettings['trackOnly'] == true
                  ? tr('markUpdated')
                  : tr('update'),
          onPressed: appsProvider.areDownloadsRunning()
              ? null
              : () {
                  appsProvider.downloadAndInstallLatestApps(
                      [listedApps[appIndex].app.id],
                      globalNavigatorKey.currentContext).catchError((e) {
                    showError(e, context);
                  });
                },
          icon: Icon(
              listedApps[appIndex].app.additionalSettings['trackOnly'] == true
                  ? Icons.check_circle_outline
                  : Icons.install_mobile));
    }

    getAppIcon(int appIndex) {
      return listedApps[appIndex].installedInfo != null
          ? Image.memory(
              listedApps[appIndex].installedInfo!.icon!,
              gaplessPlayback: true,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                  Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.rotationZ(0.31),
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Image(
                          image: const AssetImage(
                              'assets/graphics/icon_small.png'),
                          color: Colors.white.withOpacity(0.3),
                          colorBlendMode: BlendMode.modulate,
                          gaplessPlayback: true,
                        ),
                      )),
                ]);
    }

    getVersionText(int appIndex) {
      return '${listedApps[appIndex].app.installedVersion ?? tr('notInstalled')}${listedApps[appIndex].app.additionalSettings['trackOnly'] == true ? ' ${tr('estimateInBrackets')}' : ''}';
    }

    getChangesButtonString(int appIndex, bool hasChangeLogFn) {
      return listedApps[appIndex].app.releaseDate == null
          ? hasChangeLogFn
              ? tr('changes')
              : ''
          : DateFormat('yyyy-MM-dd')
              .format(listedApps[appIndex].app.releaseDate!);
    }

    getSingleAppHorizTile(int index) {
      var showChangesFn = getChangeLogFn(index);
      var hasUpdate = listedApps[index].app.installedVersion != null &&
          listedApps[index].app.installedVersion !=
              listedApps[index].app.latestVersion;
      Widget trailingRow = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          hasUpdate ? getUpdateButton(index) : const SizedBox.shrink(),
          hasUpdate
              ? const SizedBox(
                  width: 10,
                )
              : const SizedBox.shrink(),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width / 4),
                    child: Text(
                      getVersionText(index),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    )),
              ]),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                      onTap: showChangesFn,
                      child: Text(
                        getChangesButtonString(index, showChangesFn != null),
                        style: TextStyle(
                            fontStyle: FontStyle.italic,
                            decoration: showChangesFn != null
                                ? TextDecoration.underline
                                : TextDecoration.none),
                      ))
                ],
              ),
            ],
          )
        ],
      );

      var transparent =
          Theme.of(context).colorScheme.background.withAlpha(0).value;
      List<double> stops = [
        ...listedApps[index]
            .app
            .categories
            .asMap()
            .entries
            .map((e) =>
                ((e.key / (listedApps[index].app.categories.length - 1))))
            .toList(),
        1
      ];
      if (stops.length == 2) {
        stops[0] = 1;
      }
      return Container(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  stops: stops,
                  begin: const Alignment(-1, 0),
                  end: const Alignment(-0.97, 0),
                  colors: [
                ...listedApps[index]
                    .app
                    .categories
                    .map((e) =>
                        Color(settingsProvider.categories[e] ?? transparent)
                            .withAlpha(255))
                    .toList(),
                Color(transparent)
              ])),
          child: ListTile(
            tileColor: listedApps[index].app.pinned
                ? Colors.grey.withOpacity(0.1)
                : Colors.transparent,
            selectedTileColor: Theme.of(context)
                .colorScheme
                .primary
                .withOpacity(listedApps[index].app.pinned ? 0.2 : 0.1),
            selected:
                selectedAppIds.map((e) => e).contains(listedApps[index].app.id),
            onLongPress: () {
              toggleAppSelected(listedApps[index].app);
            },
            leading: getAppIcon(index),
            title: Text(
              maxLines: 1,
              listedApps[index].name,
              style: TextStyle(
                overflow: TextOverflow.ellipsis,
                fontWeight: listedApps[index].app.pinned
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            subtitle: Text(tr('byX', args: [listedApps[index].app.author]),
                maxLines: 1,
                style: TextStyle(
                    overflow: TextOverflow.ellipsis,
                    fontWeight: listedApps[index].app.pinned
                        ? FontWeight.bold
                        : FontWeight.normal)),
            trailing: listedApps[index].downloadProgress != null
                ? SizedBox(
                    width: 110,
                    child: Text(tr('percentProgress', args: [
                      listedApps[index].downloadProgress! >= 0
                          ? listedApps[index]
                              .downloadProgress!
                              .toInt()
                              .toString()
                          : tr('pleaseWait')
                    ])))
                : trailingRow,
            onTap: () {
              if (selectedAppIds.isNotEmpty) {
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
    }

    getCategoryCollapsibleTile(int index) {
      var tiles = listedApps
          .asMap()
          .entries
          .where((e) =>
              e.value.app.categories.contains(listedCategories[index]) ||
              e.value.app.categories.isEmpty && listedCategories[index] == null)
          .map((e) => getSingleAppHorizTile(e.key))
          .toList();

      capFirstChar(String str) => str[0].toUpperCase() + str.substring(1);
      return ExpansionTile(
          initiallyExpanded: true,
          title: Text(
            capFirstChar(listedCategories[index] ?? tr('noCategory')),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          trailing: Text(tiles.length.toString()),
          children: tiles);
    }

    getSelectAllButton() {
      return selectedAppIds.isEmpty
          ? TextButton.icon(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onPressed: () {
                selectThese(listedApps.map((e) => e.app).toList());
              },
              icon: Icon(
                Icons.select_all_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              label: Text(listedApps.length.toString()))
          : TextButton.icon(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onPressed: () {
                selectedAppIds.isEmpty
                    ? selectThese(listedApps.map((e) => e.app).toList())
                    : clearSelected();
              },
              icon: Icon(
                selectedAppIds.isEmpty
                    ? Icons.select_all_outlined
                    : Icons.deselect_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              label: Text(selectedAppIds.length.toString()));
    }

    getMassObtainFunction() {
      return appsProvider.areDownloadsRunning() ||
              (existingUpdateIdsAllOrSelected.isEmpty &&
                  newInstallIdsAllOrSelected.isEmpty &&
                  trackOnlyUpdateIdsAllOrSelected.isEmpty)
          ? null
          : () {
              HapticFeedback.heavyImpact();
              List<GeneratedFormItem> formItems = [];
              if (existingUpdateIdsAllOrSelected.isNotEmpty) {
                formItems.add(GeneratedFormSwitch('updates',
                    label: tr('updateX', args: [
                      plural('apps', existingUpdateIdsAllOrSelected.length)
                    ]),
                    defaultValue: true));
              }
              if (newInstallIdsAllOrSelected.isNotEmpty) {
                formItems.add(GeneratedFormSwitch('installs',
                    label: tr('installX', args: [
                      plural('apps', newInstallIdsAllOrSelected.length)
                    ]),
                    defaultValue: existingUpdateIdsAllOrSelected.isNotEmpty));
              }
              if (trackOnlyUpdateIdsAllOrSelected.isNotEmpty) {
                formItems.add(GeneratedFormSwitch('trackonlies',
                    label: tr('markXTrackOnlyAsUpdated', args: [
                      plural('apps', trackOnlyUpdateIdsAllOrSelected.length)
                    ]),
                    defaultValue: existingUpdateIdsAllOrSelected.isNotEmpty ||
                        newInstallIdsAllOrSelected.isNotEmpty));
              }
              showDialog<Map<String, dynamic>?>(
                  context: context,
                  builder: (BuildContext ctx) {
                    var totalApps = existingUpdateIdsAllOrSelected.length +
                        newInstallIdsAllOrSelected.length +
                        trackOnlyUpdateIdsAllOrSelected.length;
                    return GeneratedFormModal(
                      title: tr('changeX', args: [plural('apps', totalApps)]),
                      items: formItems.map((e) => [e]).toList(),
                      initValid: true,
                    );
                  }).then((values) async {
                if (values != null) {
                  if (values.isEmpty) {
                    values = getDefaultValuesFromFormItems([formItems]);
                  }
                  bool shouldInstallUpdates = values['updates'] == true;
                  bool shouldInstallNew = values['installs'] == true;
                  bool shouldMarkTrackOnlies = values['trackonlies'] == true;
                  List<String> toInstall = [];
                  if (shouldInstallUpdates) {
                    toInstall.addAll(existingUpdateIdsAllOrSelected);
                  }
                  if (shouldInstallNew) {
                    toInstall.addAll(newInstallIdsAllOrSelected);
                  }
                  if (shouldMarkTrackOnlies) {
                    toInstall.addAll(trackOnlyUpdateIdsAllOrSelected);
                  }
                  appsProvider
                      .downloadAndInstallLatestApps(
                          toInstall, globalNavigatorKey.currentContext,
                          settingsProvider: settingsProvider)
                      .catchError((e) {
                    showError(e, context);
                  });
                }
              });
            };
    }

    launchCategorizeDialog() {
      return () async {
        try {
          Set<String>? preselected;
          var showPrompt = false;
          for (var element in selectedApps) {
            var currentCats = element.categories.toSet();
            if (preselected == null) {
              preselected = currentCats;
            } else {
              if (!settingsProvider.setEqual(currentCats, preselected)) {
                showPrompt = true;
                break;
              }
            }
          }
          var cont = true;
          if (showPrompt) {
            cont = await showDialog<Map<String, dynamic>?>(
                    context: context,
                    builder: (BuildContext ctx) {
                      return GeneratedFormModal(
                        title: tr('categorize'),
                        items: const [],
                        initValid: true,
                        message: tr('selectedCategorizeWarning'),
                      );
                    }) !=
                null;
          }
          if (cont) {
            // ignore: use_build_context_synchronously
            await showDialog<Map<String, dynamic>?>(
                context: context,
                builder: (BuildContext ctx) {
                  return GeneratedFormModal(
                    title: tr('categorize'),
                    items: const [],
                    initValid: true,
                    singleNullReturnButton: tr('continue'),
                    additionalWidgets: [
                      CategoryEditorSelector(
                        preselected: !showPrompt ? preselected ?? {} : {},
                        showLabelWhenNotEmpty: false,
                        onSelected: (categories) {
                          appsProvider.saveApps(selectedApps.map((e) {
                            e.categories = categories;
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
      };
    }

    showMassMarkDialog() {
      return showDialog(
          context: context,
          builder: (BuildContext ctx) {
            return AlertDialog(
              title: Text(tr('markXSelectedAppsAsUpdated',
                  args: [selectedAppIds.length.toString()])),
              content: Text(
                tr('onlyWorksWithNonVersionDetectApps'),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
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
                        if (a.installedVersion != null &&
                            !appsProvider.isVersionDetectionPossible(
                                appsProvider.apps[a.id])) {
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
        Navigator.of(context).pop();
      });
    }

    pinSelectedApps() {
      var pinStatus = selectedApps.where((element) => element.pinned).isEmpty;
      appsProvider.saveApps(selectedApps.map((e) {
        e.pinned = pinStatus;
        return e;
      }).toList());
      Navigator.of(context).pop();
    }

    resetSelectedAppsInstallStatuses() async {
      try {
        var values = await showDialog(
            context: context,
            builder: (BuildContext ctx) {
              return GeneratedFormModal(
                title: tr('resetInstallStatusForSelectedAppsQuestion'),
                items: const [],
                initValid: true,
                message: tr('installStatusOfXWillBeResetExplanation',
                    args: [plural('app', selectedAppIds.length)]),
              );
            });
        if (values != null) {
          appsProvider.saveApps(selectedApps.map((e) {
            e.installedVersion = null;
            return e;
          }).toList());
        }
      } finally {
        Navigator.of(context).pop();
      }
    }

    showMoreOptionsDialog() {
      return showDialog(
          context: context,
          builder: (BuildContext ctx) {
            return AlertDialog(
              scrollable: true,
              content: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                          onPressed: appsProvider.areDownloadsRunning()
                              ? null
                              : showMassMarkDialog,
                          tooltip: tr('markSelectedAppsUpdated'),
                          icon: const Icon(Icons.done)),
                      IconButton(
                        onPressed: pinSelectedApps,
                        tooltip: selectedApps
                                .where((element) => element.pinned)
                                .isEmpty
                            ? tr('pinToTop')
                            : tr('unpinFromTop'),
                        icon: Icon(selectedApps
                                .where((element) => element.pinned)
                                .isEmpty
                            ? Icons.bookmark_outline_rounded
                            : Icons.bookmark_remove_outlined),
                      ),
                      IconButton(
                        onPressed: () {
                          String urls = '';
                          for (var a in selectedApps) {
                            urls += '${a.url}\n';
                          }
                          urls = urls.substring(0, urls.length - 1);
                          Share.share(urls,
                              subject: tr('selectedAppURLsFromObtainium'));
                          Navigator.of(context).pop();
                        },
                        tooltip: tr('shareSelectedAppURLs'),
                        icon: const Icon(Icons.share),
                      ),
                      IconButton(
                        onPressed: resetSelectedAppsInstallStatuses,
                        tooltip: tr('resetInstallStatus'),
                        icon: const Icon(Icons.restore_page_outlined),
                      ),
                    ]),
              ),
            );
          });
    }

    getMainBottomButtonsRow() {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: selectedAppIds.isEmpty
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
              onPressed: getMassObtainFunction(),
              tooltip: selectedAppIds.isEmpty
                  ? tr('installUpdateApps')
                  : tr('installUpdateSelectedApps'),
              icon: const Icon(
                Icons.file_download_outlined,
              )),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: selectedAppIds.isEmpty ? null : launchCategorizeDialog(),
            tooltip: tr('categorize'),
            icon: const Icon(Icons.category_outlined),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: selectedAppIds.isEmpty ? null : showMoreOptionsDialog,
            tooltip: tr('more'),
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      );
    }

    showFilterDialog() async {
      var values = await showDialog<Map<String, dynamic>?>(
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
                ],
                [
                  GeneratedFormDropdown(
                      'sourceFilter',
                      label: tr('appSource'),
                      defaultValue: filter.sourceFilter,
                      [
                        MapEntry('', tr('none')),
                        ...sourceProvider.sources
                            .map((e) =>
                                MapEntry(e.runtimeType.toString(), e.name))
                            .toList()
                      ])
                ]
              ],
              additionalWidgets: [
                const SizedBox(
                  height: 16,
                ),
                CategoryEditorSelector(
                  preselected: filter.categoryFilter,
                  onSelected: (categories) {
                    filter.categoryFilter = categories.toSet();
                  },
                )
              ],
            );
          });
      if (values != null) {
        setState(() {
          filter.setFormValuesFromMap(values);
        });
      }
    }

    getFilterButtonsRow() {
      return Row(
        children: [
          getSelectAllButton(),
          const VerticalDivider(),
          Expanded(
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: getMainBottomButtonsRow())),
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
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              label: Text(
                filter.isIdenticalTo(neutralFilter, settingsProvider)
                    ? tr('filter')
                    : tr('filterActive'),
                style: TextStyle(
                    fontWeight:
                        filter.isIdenticalTo(neutralFilter, settingsProvider)
                            ? FontWeight.normal
                            : FontWeight.bold),
              ),
              onPressed: showFilterDialog,
              icon: const Icon(Icons.filter_list_rounded))
        ],
      );
    }

    getDisplayedList() {
      return settingsProvider.groupByCategory &&
              !(listedCategories.isEmpty ||
                  (listedCategories.length == 1 && listedCategories[0] == null))
          ? SliverList(
              delegate:
                  SliverChildBuilderDelegate((BuildContext context, int index) {
              return getCategoryCollapsibleTile(index);
            }, childCount: listedCategories.length))
          : SliverList(
              delegate:
                  SliverChildBuilderDelegate((BuildContext context, int index) {
              return getSingleAppHorizTile(index);
            }, childCount: listedApps.length));
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
          key: _refreshIndicatorKey,
          onRefresh: refresh,
          child: CustomScrollView(slivers: <Widget>[
            CustomAppBar(title: tr('appsString')),
            ...getLoadingWidgets(),
            getDisplayedList()
          ])),
      persistentFooterButtons: appsProvider.apps.isEmpty
          ? null
          : [
              getFilterButtonsRow(),
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
  late String sourceFilter;

  AppsFilter(
      {this.nameFilter = '',
      this.authorFilter = '',
      this.includeUptodate = true,
      this.includeNonInstalled = true,
      this.categoryFilter = const {},
      this.sourceFilter = ''});

  Map<String, dynamic> toFormValuesMap() {
    return {
      'appName': nameFilter,
      'author': authorFilter,
      'upToDateApps': includeUptodate,
      'nonInstalledApps': includeNonInstalled,
      'sourceFilter': sourceFilter
    };
  }

  setFormValuesFromMap(Map<String, dynamic> values) {
    nameFilter = values['appName']!;
    authorFilter = values['author']!;
    includeUptodate = values['upToDateApps'];
    includeNonInstalled = values['nonInstalledApps'];
    sourceFilter = values['sourceFilter'];
  }

  bool isIdenticalTo(AppsFilter other, SettingsProvider settingsProvider) =>
      authorFilter.trim() == other.authorFilter.trim() &&
      nameFilter.trim() == other.nameFilter.trim() &&
      includeUptodate == other.includeUptodate &&
      includeNonInstalled == other.includeNonInstalled &&
      settingsProvider.setEqual(categoryFilter, other.categoryFilter) &&
      sourceFilter.trim() == other.sourceFilter.trim();
}
