import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/components/settings_widgets.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/pages/import_export.dart';
import 'package:obtainium/components/category_editor.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/notifications_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AddAppPage extends StatefulWidget {
  const AddAppPage({super.key, this.initialUrl});

  /// When provided (e.g. from a deep link), the URL is applied automatically
  /// after the first frame.
  final String? initialUrl;

  @override
  State<AddAppPage> createState() => AddAppPageState();
}

class AddAppPageState extends State<AddAppPage> {
  bool gettingAppInfo = false;
  bool searching = false;

  String userInput = '';
  String searchQuery = '';
  String? pickedSourceOverride;
  String? previousPickedSourceOverride;
  AppSource? pickedSource;
  Map<String, dynamic> additionalSettings = {};
  bool additionalSettingsValid = true;
  bool inferAppIdIfOptional = true;
  List<String> pickedCategories = [];
  int urlInputKey = 0;
  SourceProvider sourceProvider = SourceProvider();

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) linkFn(widget.initialUrl!);
      });
    }
  }

  Future<String?>? _sourceNoteFuture;
  String? _sourceNoteSourceKey;

  void linkFn(String input) {
    try {
      if (input.isEmpty) {
        throw UnsupportedURLError();
      }
      sourceProvider.getSource(input);
      changeUserInput(input, true, false, updateUrlInput: true);
    } catch (e) {
      showError(e, context);
    }
  }

  void changeUserInput(
    String input,
    bool valid,
    bool isBuilding, {
    bool updateUrlInput = false,
    String? overrideSource,
  }) {
    userInput = input;
    if (!isBuilding) {
      setState(() {
        if (overrideSource != null) {
          pickedSourceOverride = overrideSource;
        }
        bool overrideChanged =
            pickedSourceOverride != previousPickedSourceOverride;
        previousPickedSourceOverride = pickedSourceOverride;
        if (updateUrlInput) {
          urlInputKey++;
        }
        var prevHost = pickedSource?.hosts.isNotEmpty == true
            ? pickedSource?.hosts[0]
            : null;
        var source = valid
            ? sourceProvider.getSource(
                userInput,
                overrideSource: pickedSourceOverride,
              )
            : null;
        if (pickedSource?.sourceIdentifier != source?.sourceIdentifier ||
            overrideChanged ||
            (prevHost != null && prevHost != source?.hosts[0])) {
          pickedSource = source;
          pickedSource?.runOnAddAppInputChange(userInput);
          additionalSettings = source != null
              ? getDefaultValuesFromFormItems(
                  source.combinedAppSpecificSettingFormItems,
                )
              : {};
          additionalSettingsValid = source != null
              ? !sourceProvider.ifRequiredAppSpecificSettingsExist(source)
              : true;
          inferAppIdIfOptional = true;
        }
      });
    }
  }

  Future<bool> _getTrackOnlyConfirmationIfNeeded(
    bool userPickedTrackOnly,
    BuildContext context,
    SettingsProvider settingsProvider, {
    bool ignoreHideSetting = false,
  }) async {
    var useTrackOnly = userPickedTrackOnly || pickedSource!.enforceTrackOnly;
    if (useTrackOnly &&
        (!settingsProvider.hideTrackOnlyWarning || ignoreHideSetting)) {
      if (!context.mounted) return false;
      var values = await showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return GeneratedFormModal(
            initValid: true,
            title: tr(
              'xIsTrackOnly',
              args: [pickedSource!.enforceTrackOnly ? tr('source') : tr('app')],
            ),
            items: [
              [GeneratedFormSwitch('hide', label: tr('dontShowAgain'))],
            ],
            message:
                '${pickedSource!.enforceTrackOnly ? tr('appsFromSourceAreTrackOnly') : tr('youPickedTrackOnly')}\n\n${tr('trackOnlyAppDescription')}',
          );
        },
      );
      if (values != null) {
        settingsProvider.hideTrackOnlyWarning = values['hide'] == true;
      }
      return useTrackOnly && values != null;
    } else {
      return true;
    }
  }

  Future<bool> _getReleaseDateAsVersionConfirmationIfNeeded(
    BuildContext context,
  ) async {
    if (additionalSettings['releaseDateAsVersion'] != true) return true;
    if (!context.mounted) return false;
    return await showDialog(
          context: context,
          builder: (BuildContext ctx) {
            return GeneratedFormModal(
              title: tr('releaseDateAsVersion'),
              items: const [],
              message: tr('releaseDateAsVersionExplanation'),
            );
          },
        ) !=
        null;
  }

  Future<void> _addApp(
    BuildContext context,
    AppsProvider appsProvider,
    SettingsProvider settingsProvider,
    NotificationsProvider notificationsProvider, {
    bool resetUserInputAfter = false,
  }) async {
    setState(() {
      gettingAppInfo = true;
    });
    try {
      var userPickedTrackOnly = additionalSettings['trackOnly'] == true;
      App? app;
      var confirmed = await _getTrackOnlyConfirmationIfNeeded(
        userPickedTrackOnly,
        context,
        settingsProvider,
      );
      if (!context.mounted) return;
      if (confirmed) {
        confirmed = await _getReleaseDateAsVersionConfirmationIfNeeded(
          context,
        );
      }
      if (confirmed) {
        var trackOnly = pickedSource!.enforceTrackOnly || userPickedTrackOnly;
        app = await sourceProvider.getApp(
          pickedSource!,
          userInput.trim(),
          additionalSettings,
          trackOnlyOverride: trackOnly,
          sourceIsOverriden: pickedSourceOverride != null,
          inferAppIdIfOptional: inferAppIdIfOptional,
        );
        // Only download the APK here if you need to for the package ID
        if (isTempId(app) && app.additionalSettings['trackOnly'] != true) {
          if (!context.mounted) return;
          var apkUrl = await appsProvider.confirmAppFileUrl(
            app,
            context,
            false,
          );
          if (apkUrl == null) {
            throw ObtainiumError(tr('cancelled'));
          }
          app.preferredApkIndex = app.apkUrls
              .map((e) => e.value)
              .toList()
              .indexOf(apkUrl.value);
          if (!context.mounted) return;
          var downloadedArtifact = await appsProvider.downloadApp(
            app,
            globalNavigatorKey.currentContext,
            notificationsProvider: notificationsProvider,
          );
          DownloadedApk? downloadedFile;
          DownloadedDir? downloadedDir;
          if (downloadedArtifact is DownloadedApk) {
            downloadedFile = downloadedArtifact;
          } else if (downloadedArtifact is DownloadedDir) {
            downloadedDir = downloadedArtifact;
          }
          if (downloadedFile == null && downloadedDir == null) {
            throw ObtainiumError(tr('downloadFailed'));
          }
          app.id = downloadedFile?.appId ?? downloadedDir!.appId;
        }
        if (appsProvider.apps.containsKey(app.id)) {
          throw ObtainiumError(tr('appAlreadyAdded'));
        }
        if (app.additionalSettings['trackOnly'] == true ||
            app.additionalSettings['versionDetection'] != true) {
          app.installedVersion = app.latestVersion;
        }
        app.categories = pickedCategories;
        await appsProvider.saveApps([app], onlyIfExists: false);
      }
      if (app != null) {
        var route = MaterialPageRoute<void>(
          builder: (context) => AppPage(appId: app!.id),
        );
        var nav = Navigator.of(globalNavigatorKey.currentContext ?? context);
        // Replace this (pushed) add screen with the new app's detail so that
        // backing out returns to the apps list — unless we're staying to add
        // more.
        if (resetUserInputAfter) {
          nav.push(route);
        } else {
          nav.pushReplacement(route);
        }
      }
    } catch (e) {
      if (context.mounted) showError(e, context);
    } finally {
      if (mounted) {
        setState(() {
          gettingAppInfo = false;
          if (resetUserInputAfter) {
            changeUserInput('', false, true);
          }
        });
      }
    }
  }

  Future<void> _runSearch(
    BuildContext context,
    SettingsProvider settingsProvider,
    AppsProvider appsProvider,
  ) async {
    setState(() {
      searching = true;
    });
    var sourceStrings = <String, List<String>>{};
    sourceProvider.sources.where((e) => e.canSearch).forEach((s) {
      sourceStrings[s.name] = [s.name];
    });
    try {
      var searchSources =
          await showDialog<List<String>?>(
            context: context,
            builder: (BuildContext ctx) {
              return SelectionModal(
                title: tr('selectX', args: [plural('source', 2).toLowerCase()]),
                entries: sourceStrings,
                selectedByDefault: true,
                onlyOneSelectionAllowed: false,
                titlesAreLinks: false,
                deselectThese: settingsProvider.searchDeselected,
              );
            },
          ) ??
          [];
      if (searchSources.isNotEmpty) {
        settingsProvider.searchDeselected = sourceStrings.keys
            .where((s) => !searchSources.contains(s))
            .toList();
        List<MapEntry<String, Map<String, List<String>>>?>
        results = (await Future.wait(
          sourceProvider.sources
              .where((e) => searchSources.contains(e.name))
              .map((e) async {
                try {
                  Map<String, dynamic>? querySettings = {};
                  if (e.includeAdditionalOptsInMainSearch) {
                    querySettings = await showDialog<Map<String, dynamic>?>(
                      context: context,
                      builder: (BuildContext ctx) {
                        return GeneratedFormModal(
                          title: tr('searchX', args: [e.name]),
                          items: [
                            ...e.searchQuerySettingFormItems.map((e) => [e]),
                            [
                              GeneratedFormTextField(
                                'url',
                                label: e.hosts.isNotEmpty
                                    ? tr('overrideSource')
                                    : plural('url', 1).substring(2),
                                autoCompleteOptions: [
                                  ...(e.hosts.isNotEmpty ? [e.hosts[0]] : []),
                                  ...appsProvider.apps.values
                                      .where(
                                        (a) =>
                                            sourceProvider
                                                .getSource(
                                                  a.app.url,
                                                  overrideSource:
                                                      a.app.overrideSource,
                                                )
                                                .runtimeType ==
                                            e.runtimeType,
                                      )
                                      .map((a) {
                                        var uri = Uri.parse(a.app.url);
                                        return '${uri.origin}${uri.path}';
                                      }),
                                ],
                                defaultValue: e.hosts.isNotEmpty
                                    ? e.hosts[0]
                                    : '',
                                required: true,
                              ),
                            ],
                          ],
                        );
                      },
                    );
                    if (querySettings == null) {
                      return null;
                    }
                  }
                  return MapEntry(
                    e.name,
                    await e.search(searchQuery, querySettings: querySettings),
                  );
                } catch (err) {
                  // Surface the failing source's error but don't abort the
                  // entire multi-source search - other sources should still
                  // return their results.
                  if (err is ObtainiumError) {
                    err.unexpected = true;
                  }
                  if (context.mounted) showError(err, context);
                  return null;
                }
              }),
        )).where((a) => a != null).toList();

        if (!mounted) return;

        // Interleave results instead of simple reduce
        Map<String, MapEntry<String, List<String>>> res = {};
        var si = 0;
        var done = false;
        while (!done) {
          done = true;
          for (var r in results) {
            var sourceName = r!.key;
            if (r.value.length > si) {
              done = false;
              var singleRes = r.value.entries.elementAt(si);
              res[singleRes.key] = MapEntry(sourceName, singleRes.value);
            }
          }
          si++;
        }
        if (res.isEmpty) {
          throw ObtainiumError(tr('noResults'));
        }
        if (!context.mounted) return;
        List<String>? selectedUrls = res.isEmpty
            ? []
            : await showDialog<List<String>?>(
                context: context,
                builder: (BuildContext ctx) {
                  return SelectionModal(
                    entries: res.map((k, v) => MapEntry(k, v.value)),
                    selectedByDefault: false,
                    onlyOneSelectionAllowed: true,
                  );
                },
              );
        if (selectedUrls != null && selectedUrls.isNotEmpty) {
          var sourceName = res[selectedUrls[0]]?.key;
          changeUserInput(
            selectedUrls[0],
            true,
            false,
            updateUrlInput: true,
            overrideSource: sourceName,
          );
        }
      }
    } catch (e) {
      if (context.mounted) showError(e, context);
    } finally {
      if (mounted) {
        setState(() {
          searching = false;
        });
      }
    }
  }

  Widget _getUrlInputRow(
    BuildContext context,
    SettingsProvider settingsProvider,
    AppsProvider appsProvider,
    NotificationsProvider notificationsProvider,
    bool doingSomething,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: GeneratedForm(
          key: Key(urlInputKey.toString()),
          items: [
            [
              GeneratedFormTextField(
                'appSourceURL',
                label: tr('appSourceURL'),
                defaultValue: userInput,
                additionalValidators: [
                  (value) {
                    try {
                      sourceProvider
                          .getSource(
                            value ?? '',
                            overrideSource: pickedSourceOverride,
                          )
                          .standardizeUrl(value ?? '');
                    } catch (e) {
                      return e is String
                          ? e
                          : e is ObtainiumError
                          ? e.toString()
                          : tr('error');
                    }
                    return null;
                  },
                ],
              ),
            ],
          ],
          onValueChanges: (values, valid, isBuilding) {
            changeUserInput(values['appSourceURL']!, valid, isBuilding);
          },
        ),
      ),
      const SizedBox(width: 16),
      SizedBox(
        height: 56,
        child: gettingAppInfo
            ? const Center(child: CircularProgressIndicator())
            : FilledButton(
                onPressed:
                    doingSomething ||
                        pickedSource == null ||
                        (pickedSource!
                                .combinedAppSpecificSettingFormItems
                                .isNotEmpty &&
                            !additionalSettingsValid)
                    ? null
                    : () {
                        settingsProvider.selectionClick();
                        _addApp(
                          context,
                          appsProvider,
                          settingsProvider,
                          notificationsProvider,
                        );
                      },
                child: Text(tr('add')),
              ),
      ),
    ],
  );

  Widget _getHTMLSourceOverrideDropdown() => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: GeneratedForm(
              items: [
                [
                  GeneratedFormDropdown(
                    'overrideSource',
                    defaultValue: pickedSourceOverride ?? '',
                    [
                      MapEntry('', tr('none')),
                      ...sourceProvider.sources
                          .where(
                            (s) =>
                                s.allowOverride ||
                                (pickedSource != null &&
                                    pickedSource.runtimeType == s.runtimeType),
                          )
                          .map(
                            (s) => MapEntry(s.name, s.name),
                          ),
                    ],
                    label: tr('overrideSource'),
                  ),
                ],
              ],
              onValueChanges: (values, valid, isBuilding) {
                fn() {
                  pickedSourceOverride =
                      (values['overrideSource'] == null ||
                          values['overrideSource'] == '')
                      ? null
                      : values['overrideSource'];
                }

                if (!isBuilding) {
                  setState(() {
                    fn();
                  });
                } else {
                  fn();
                }
                changeUserInput(userInput, valid, isBuilding);
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
    ],
  );

  bool _shouldShowSearchBar() =>
      sourceProvider.sources.where((e) => e.canSearch).isNotEmpty &&
      pickedSource == null &&
      userInput.isEmpty;

  Widget _getSearchBarRow(
    BuildContext context,
    SettingsProvider settingsProvider,
    AppsProvider appsProvider,
    bool doingSomething,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: GeneratedForm(
          items: [
            [
              GeneratedFormTextField(
                'searchSomeSources',
                label: tr('searchSomeSourcesLabel'),
                required: false,
              ),
            ],
          ],
          onValueChanges: (values, valid, isBuilding) {
            if (values.isNotEmpty && valid && !isBuilding) {
              setState(() {
                searchQuery = values['searchSomeSources']!.trim();
              });
            }
          },
        ),
      ),
      const SizedBox(width: 16),
      SizedBox(
        height: 56,
        child: searching
            ? const Center(child: CircularProgressIndicator())
            : FilledButton(
                onPressed: searchQuery.isEmpty || doingSomething
                    ? null
                    : () {
                        _runSearch(context, settingsProvider, appsProvider);
                      },
                child: Text(tr('search')),
              ),
      ),
    ],
  );

  Widget _getAdditionalOptsCol(
    BuildContext context,
    SettingsProvider settingsProvider,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      Text(
        tr('additionalOptsFor', args: [pickedSource?.name ?? tr('source')]),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 16),
      () {
        var formItems = pickedSource!.combinedAppSpecificSettingFormItems;
        if (settingsProvider.includePrereleasesByDefault ||
            settingsProvider.shizukuPretendToBeGooglePlay) {
          for (var row in formItems) {
            for (var item in row) {
              if (item.key == 'includePrereleases' &&
                  settingsProvider.includePrereleasesByDefault) {
                item.defaultValue = true;
              }
              if (item.key == 'shizukuPretendToBeGooglePlay' &&
                  settingsProvider.shizukuPretendToBeGooglePlay) {
                item.defaultValue = true;
              }
            }
          }
        }
        return GeneratedForm(
          tileMode: true,
          key: Key(
            '${pickedSource!.name}-${pickedSource!.hostChanged.toString()}-${pickedSource!.hostIdenticalDespiteAnyChange.toString()}',
          ),
          items: [
            ...formItems,
            ...(pickedSourceOverride != null
                ? pickedSource!.sourceConfigSettingFormItems.map((e) => [e])
                : []),
          ],
          onValueChanges: (values, valid, isBuilding) {
            if (!isBuilding) {
              setState(() {
                additionalSettings = values;
                additionalSettingsValid = valid;
              });
            }
          },
        );
      }(),
      const SizedBox(height: 12),
      SettingsTile(
        padding: const EdgeInsets.all(12),
        child: CategorySelector(
          selected: pickedCategories.toSet(),
          alignment: WrapAlignment.start,
          onChanged: (categories) {
            pickedCategories = categories.toList();
          },
        ),
      ),
      if (pickedSource != null && pickedSource!.appIdInferIsOptional) ...[
        const SizedBox(height: 12),
        GeneratedForm(
          tileMode: true,
          key: const Key('inferAppIdIfOptional'),
          items: [
            [
              GeneratedFormSwitch(
                'inferAppIdIfOptional',
                label: tr('tryInferAppIdFromCode'),
                defaultValue: inferAppIdIfOptional,
              ),
            ],
          ],
          onValueChanges: (values, valid, isBuilding) {
            if (!isBuilding) {
              setState(() {
                inferAppIdIfOptional = values['inferAppIdIfOptional'];
              });
            }
          },
        ),
      ],
      if (pickedSource != null && pickedSource!.enforceTrackOnly) ...[
        const SizedBox(height: 12),
        GeneratedForm(
          tileMode: true,
          key: Key(
            '${pickedSource!.name}-${pickedSource!.hostChanged.toString()}-${pickedSource!.hostIdenticalDespiteAnyChange.toString()}-appId',
          ),
          items: [
            [
              GeneratedFormTextField(
                'appId',
                label: '${tr('appId')} - ${tr('custom')}',
                required: false,
                additionalValidators: [
                  (value) {
                    if (value == null || value.isEmpty) {
                      return null;
                    }
                    final isValid = RegExp(
                      r'^([A-Za-z]{1}[A-Za-z\d_]*\.)+[A-Za-z][A-Za-z\d_]*$',
                    ).hasMatch(value);
                    if (!isValid) {
                      return tr('invalidInput');
                    }
                    return null;
                  },
                ],
              ),
            ],
          ],
          onValueChanges: (values, valid, isBuilding) {
            if (!isBuilding) {
              setState(() {
                additionalSettings['appId'] = values['appId'];
              });
            }
          },
        ),
      ],
    ],
  );

  Widget _getSourcesListWidget(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Wrap(
      direction: Axis.horizontal,
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      children: [
        ActionChip(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) {
                return GeneratedFormModal(
                  singleNullReturnButton: tr('ok'),
                  title: tr('supportedSources'),
                  items: const [],
                  additionalWidgets: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: sourceProvider.sources.map((e) {
                        return ActionChip(
                          label: Text(
                            '${e.name}${e.enforceTrackOnly ? ' ${tr('trackOnlyInBrackets')}' : ''}${e.canSearch ? ' ${tr('searchableInBrackets')}' : ''}',
                          ),
                          onPressed: e.hosts.isNotEmpty
                              ? () {
                                  launchUrlString(
                                    'https://${e.hosts[0]}',
                                    mode: LaunchMode.externalApplication,
                                  ).ignore();
                                }
                              : null,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${tr('note')}:',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(tr('selfHostedNote', args: [tr('overrideSource')])),
                  ],
                );
              },
            );
          },
          avatar: const Icon(Icons.dynamic_feed_outlined, size: 18),
          label: Text(tr('supportedSources')),
        ),
        ActionChip(
          avatar: const Icon(Icons.public, size: 18),
          label: Text(tr('crowdsourcedConfigsShort')),
          onPressed: () {
            launchUrlString(
              'https://apps.obtainium.page/',
              mode: LaunchMode.externalApplication,
            ).ignore();
          },
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    AppsProvider appsProvider = context.read<AppsProvider>();
    SettingsProvider settingsProvider = context.watch<SettingsProvider>();
    NotificationsProvider notificationsProvider = context
        .read<NotificationsProvider>();

    bool doingSomething = gettingAppInfo || searching;

    if (pickedSource != null) {
      final sourceKey = pickedSource!.name;
      if (_sourceNoteSourceKey != sourceKey) {
        _sourceNoteSourceKey = sourceKey;
        _sourceNoteFuture = pickedSource?.getSourceNote();
      }
    } else {
      _sourceNoteFuture = null;
      _sourceNoteSourceKey = null;
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      bottomNavigationBar: pickedSource == null
          ? _getSourcesListWidget(context)
          : null,
      body: CustomScrollView(
        slivers: <Widget>[
          CustomAppBar(title: tr('addApp')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _getUrlInputRow(
                    context,
                    settingsProvider,
                    appsProvider,
                    notificationsProvider,
                    doingSomething,
                  ),
                  const SizedBox(height: 16),
                  if (pickedSource != null) _getHTMLSourceOverrideDropdown(),
                  if (_shouldShowSearchBar())
                    _getSearchBarRow(
                      context,
                      settingsProvider,
                      appsProvider,
                      doingSomething,
                    ),
                  if (pickedSource == null && userInput.isEmpty) ...[
                    if (_shouldShowSearchBar()) const SizedBox(height: 16),
                    const ImportSection(),
                  ],
                  if (pickedSource != null)
                    FutureBuilder(
                      future: _sourceNoteFuture,
                      builder: (ctx, val) {
                        if (val.data != null && val.data!.isNotEmpty) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                            child: Material(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerLow,
                              shape: RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pickedSource!.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        val.data!,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  if (pickedSource != null)
                    _getAdditionalOptsCol(context, settingsProvider),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
