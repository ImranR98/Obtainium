import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/components/category_editor.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/pages/import_export.dart';
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
  late final AppsProvider appsProvider;
  late final SettingsProvider settingsProvider;
  late final NotificationsProvider notificationsProvider;
  bool _providersInitialized = false;

  bool gettingAppInfo = false;
  bool searching = false;

  String userInput = '';
  String searchQuery = '';
  String? pickedSourceOverride;
  String? _previousPickedSourceOverride;
  AppSource? pickedSource;
  Map<String, dynamic> additionalSettings = {};
  bool additionalSettingsValid = true;
  bool _urlValid = false;
  bool _prevValid = false;
  bool inferAppIdIfOptional = true;
  List<String> pickedCategories = [];
  int urlInputKey = 0;
  late final SourceProvider sourceProvider;

  Future<String?>? _sourceNoteFuture;
  String? _sourceNoteSourceKey;

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) processInitialUrl(widget.initialUrl);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_providersInitialized) {
      appsProvider = context.read<AppsProvider>();
      settingsProvider = context.read<SettingsProvider>();
      notificationsProvider = context.read<NotificationsProvider>();
      sourceProvider = context.read<SourceProvider>();
      _providersInitialized = true;
    }
  }

  void processInitialUrl(String? url) {
    if (url != null && url.isNotEmpty) {
      linkFn(url);
    }
  }

  void linkFn(String input) {
    try {
      if (input.isEmpty) {
        throw UnsupportedURLError();
      }
      sourceProvider.getSource(input);
      changeUserInput(input, true, false, updateUrlInput: true);
    } catch (e) {
      changeUserInput(input, false, false, updateUrlInput: true);
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
    if (!isBuilding) {
      userInput = input;
      if (overrideSource != null) {
        pickedSourceOverride = overrideSource;
      }
      final bool overrideChanged =
          pickedSourceOverride != _previousPickedSourceOverride;
      _previousPickedSourceOverride = pickedSourceOverride;
      if (updateUrlInput) {
        urlInputKey++;
      }
      _urlValid = valid || pickedSourceOverride != null;
      final prevHost = pickedSource?.hosts.isNotEmpty == true
          ? pickedSource?.hosts.first
          : null;
      AppSource? source;
      try {
        source = sourceProvider.getSource(
          userInput,
          overrideSource: pickedSourceOverride,
        );
      } catch (_) {
        source = null;
      }
      if (pickedSource?.sourceIdentifier != source?.sourceIdentifier ||
          overrideChanged ||
          (prevHost != null && prevHost != source?.hosts.firstOrNull)) {
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
      } else if (valid && !updateUrlInput && _prevValid) {
        return;
      }
      _prevValid = valid;
      _updateSourceNote();
      if (mounted) setState(() {});
    }
  }

  void setSourceOverride(String? override) {
    pickedSourceOverride = override;
    changeUserInput(userInput, true, false);
  }

  void _updateSourceNote() {
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
  }

  Future<bool> getTrackOnlyConfirmationIfNeeded(
    bool userPickedTrackOnly,
    BuildContext context, {
    bool ignoreHideSetting = false,
  }) async {
    final s = pickedSource!;
    final useTrackOnly = userPickedTrackOnly || s.enforceTrackOnly;
    if (useTrackOnly &&
        (!settingsProvider.hideTrackOnlyWarning || ignoreHideSetting)) {
      if (!context.mounted) return false;
      final values = await showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return GeneratedFormModal(
            initValid: true,
            title: tr(
              'xIsTrackOnly',
              args: [s.enforceTrackOnly ? tr('source') : tr('app')],
            ),
            items: [
              [GeneratedFormSwitch('hide', label: tr('dontShowAgain'))],
            ],
            message:
                '${s.enforceTrackOnly ? tr('appsFromSourceAreTrackOnly') : tr('youPickedTrackOnly')}\n\n${tr('trackOnlyAppDescription')}',
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

  Future<bool> getReleaseDateAsVersionConfirmationIfNeeded(
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

  Future<void> addApp(BuildContext context) async {
    gettingAppInfo = true;
    setState(() {});
    try {
      final userPickedTrackOnly = additionalSettings['trackOnly'] == true;
      App? app;
      var confirmed = await getTrackOnlyConfirmationIfNeeded(
        userPickedTrackOnly,
        context,
      );
      if (!context.mounted) return;
      if (confirmed) {
        confirmed = await getReleaseDateAsVersionConfirmationIfNeeded(context);
      }
      if (!context.mounted) return;
      if (confirmed) {
        final s = pickedSource!;
        final trackOnly = s.enforceTrackOnly || userPickedTrackOnly;
        app = await sourceProvider.getApp(
          s,
          userInput.trim(),
          additionalSettings,
          trackOnlyOverride: trackOnly,
          sourceIsOverriden: pickedSourceOverride != null,
          inferAppIdIfOptional: inferAppIdIfOptional,
        );
        if (isTempId(app) && !app.settings.getBool('trackOnly')) {
          if (!context.mounted) return;
          final apkUrl = await appsProvider.confirmAppFileUrl(
            app,
            context,
            false,
          );
          if (apkUrl == null) {
            throw ObtainiumError(tr('cancelled'));
          }
          app = app.copyWith(
            preferredApkIndex: app.apkUrls
                .map((e) => e.value)
                .toList()
                .indexOf(apkUrl.value),
          );
          if (!context.mounted) return;
          final downloadedArtifact = await appsProvider.downloadApp(
            app,
            context,
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
          app = app.copyWith(id: downloadedFile?.appId ?? downloadedDir!.appId);
        }
        if (appsProvider.apps.containsKey(app.id)) {
          throw ObtainiumError(tr('appAlreadyAdded'));
        }
        if (app.settings.getBool('trackOnly') ||
            !app.settings.getBool('versionDetection')) {
          app = app.copyWith(installedVersion: app.latestVersion);
        }
        app = app.copyWith(categories: pickedCategories);
        await appsProvider.saveApps([app], onlyIfExists: false);
      }
      if (app != null && context.mounted) {
        final route = MaterialPageRoute<void>(
          builder: (context) => AppPage(appId: app!.id),
        );
        unawaited(Navigator.of(context).pushReplacement(route));
      }
    } catch (e) {
      if (context.mounted) showError(e, context);
    } finally {
      gettingAppInfo = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> runSearch(BuildContext context) async {
    searching = true;
    setState(() {});
    final sourceStrings = <String, List<String>>{};
    sourceProvider.sources.where((e) => e.canSearch).forEach((s) {
      sourceStrings[s.name] = [s.name];
    });
    try {
      final searchSources =
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
        final List<MapEntry<String, Map<String, List<String>>>?>
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
                                                .sourceIdentifier ==
                                            e.sourceIdentifier,
                                      )
                                      .map((a) {
                                        final uri = Uri.parse(a.app.url);
                                        return '${uri.origin}${uri.path}';
                                      }),
                                ],
                                value: e.hosts.isNotEmpty ? e.hosts[0] : '',
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
                    e.sourceIdentifier,
                    await e.search(searchQuery, querySettings: querySettings),
                  );
                } catch (err) {
                  final errorToShow = err is ObtainiumError
                      ? ObtainiumError(
                          err.message,
                          code: err.code,
                          unexpected: true,
                          stack: err.stack,
                          data: err.data,
                        )
                      : err;
                  if (context.mounted) showError(errorToShow, context);
                  return null;
                }
              }),
        )).where((a) => a != null).toList();

        if (!context.mounted) return;

        final Map<String, MapEntry<String, List<String>>> res = {};
        var si = 0;
        var done = false;
        while (!done) {
          done = true;
          for (var r in results) {
            final sourceName = r!.key;
            if (r.value.length > si) {
              done = false;
              final singleRes = r.value.entries.elementAt(si);
              res[singleRes.key] = MapEntry(sourceName, singleRes.value);
            }
          }
          si++;
        }
        if (res.isEmpty) {
          throw ObtainiumError(tr('noResults'));
        }
        if (!context.mounted) return;
        final List<String>? selectedUrls = await showDialog<List<String>?>(
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
          final sourceName = res[selectedUrls[0]]?.key;
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
      searching = false;
      if (mounted) setState(() {});
    }
  }

  bool get shouldShowSearchBar =>
      sourceProvider.sources.where((e) => e.canSearch).isNotEmpty &&
      pickedSource == null &&
      userInput.isEmpty;

  void openSourcesListDialog(BuildContext context) {
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
                          unawaited(
                            launchUrlString(
                              'https://${e.hosts[0]}',
                              mode: LaunchMode.externalApplication,
                            ),
                          );
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
  }

  void openCrowdsourcedConfigs() {
    unawaited(
      launchUrlString(
        'https://apps.obtainium.imranr.dev/',
        mode: LaunchMode.externalApplication,
      ),
    );
  }

  Widget _buildSourceSpecificForm(SettingsProvider settingsProvider) {
    final s = pickedSource!;
    final formItems = s.combinedAppSpecificSettingFormItems;
    for (var row in formItems) {
      for (var item in row) {
        if (additionalSettings[item.key] != null) {
          item.value = additionalSettings[item.key];
        }
      }
    }
    if (settingsProvider.includePrereleasesByDefault ||
        settingsProvider.shizukuPretendToBeGooglePlay) {
      for (var row in formItems) {
        for (var item in row) {
          if (item.key == 'includePrereleases' &&
              settingsProvider.includePrereleasesByDefault) {
            item.value = true;
          }
          if (item.key == 'shizukuPretendToBeGooglePlay' &&
              settingsProvider.shizukuPretendToBeGooglePlay) {
            item.value = true;
          }
        }
      }
    }
    return GeneratedForm(
      tileMode: true,
      key: Key(
        '${s.name}-${s.hostChanged.toString()}-${s.hostIdenticalDespiteAnyChange.toString()}',
      ),
      items: [
        ...formItems,
        ...(pickedSourceOverride != null
            ? s.sourceConfigSettingFormItems.map((e) => [e])
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
  }

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
      _buildSourceSpecificForm(settingsProvider),
      const SizedBox(height: 12),
      CardTile(
        padding: const EdgeInsets.all(12),
        child: CategorySelector(
          selected: pickedCategories.toSet(),
          alignment: WrapAlignment.start,
          onChanged: (categories) {
            pickedCategories = categories.toList();
          },
        ),
      ),
      if (pickedSource?.appIdInferIsOptional == true) ...[
        const SizedBox(height: 12),
        GeneratedForm(
          tileMode: true,
          key: const Key('inferAppIdIfOptional'),
          items: [
            [
              GeneratedFormSwitch(
                'inferAppIdIfOptional',
                label: tr('tryInferAppIdFromCode'),
                value: inferAppIdIfOptional,
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
      if (pickedSource?.enforceTrackOnly == true) ...[
        const SizedBox(height: 12),
        GeneratedForm(
          tileMode: true,
          key: Key(
            '${pickedSource?.name}-${pickedSource?.hostChanged.toString()}-${pickedSource?.hostIdenticalDespiteAnyChange.toString()}-appId',
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
    padding: EdgeInsets.only(
      left: 16,
      right: 16,
      top: MediaQuery.of(context).padding.top,
      bottom: MediaQuery.of(context).padding.bottom,
    ),
    child: Wrap(
      direction: Axis.horizontal,
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      children: [
        ActionChip(
          onPressed: () {
            openSourcesListDialog(context);
          },
          avatar: const Icon(Icons.dynamic_feed_outlined, size: 18),
          label: Text(tr('supportedSources')),
        ),
        ActionChip(
          avatar: const Icon(Icons.public, size: 18),
          label: Text(tr('crowdsourcedConfigsShort')),
          onPressed: () {
            openCrowdsourcedConfigs();
          },
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settingsProvider = context.watch<SettingsProvider>();

    final bool doingSomething = gettingAppInfo || searching;
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
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: GeneratedForm(
                          key: Key('url-$urlInputKey'),
                          tileMode: true,
                          items: [
                            [
                              GeneratedFormTextField(
                                'appSourceURL',
                                label: tr('appSourceURL'),
                                value: userInput,
                                required: false,
                                additionalValidators: [
                                  (value) {
                                    if (value == null ||
                                        value.trim().isEmpty) {
                                      return null;
                                    }
                                    try {
                                      sourceProvider
                                          .getSource(
                                            value,
                                            overrideSource:
                                                pickedSourceOverride,
                                          )
                                          .standardizeUrl(value);
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
                            changeUserInput(
                              values['appSourceURL']!,
                              valid,
                              isBuilding,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      gettingAppInfo
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.add_rounded),
                              visualDensity: VisualDensity.compact,
                              tooltip: tr('add'),
                              onPressed:
                                  doingSomething ||
                                          pickedSource == null ||
                                          !_urlValid ||
                                          userInput.trim().isEmpty ||
                                          (pickedSource!
                                                      .combinedAppSpecificSettingFormItems
                                                      .isNotEmpty &&
                                                  !additionalSettingsValid)
                                      ? null
                                      : () {
                                          settingsProvider.selectionClick();
                                          addApp(context);
                                        },
                            ),
                    ],
                  ),
                  if (pickedSource != null) ...[
                    const SizedBox(height: 13),
                    GeneratedForm(
                      tileMode: true,
                      items: [
                        [
                          GeneratedFormDropdown(
                            'overrideSource',
                            value: pickedSourceOverride ?? '',
                            [
                              MapEntry('', tr('none')),
                              ...sourceProvider.sources
                                  .where(
                                    (s) =>
                                        s.allowOverride ||
                                        (pickedSource!.sourceIdentifier ==
                                            s.sourceIdentifier),
                                  )
                                  .map(
                                    (s) => MapEntry(s.sourceIdentifier, s.name),
                                  ),
                            ],
                            label: tr('overrideSource'),
                          ),
                        ],
                      ],
                      onValueChanges: (values, valid, isBuilding) {
                        final newOverride =
                            (values['overrideSource'] == null ||
                                values['overrideSource'] == '')
                            ? null
                            : values['overrideSource'] as String?;
                        setSourceOverride(newOverride);
                      },
                    ),
                  ],
                  if (shouldShowSearchBar) ...[
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        Expanded(
                          child: GeneratedForm(
                            tileMode: true,
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
                              if (values.isNotEmpty &&
                                  valid &&
                                  !isBuilding) {
                                setState(() {
                                  searchQuery =
                                      values['searchSomeSources']!.trim();
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(
                                    Icons.search_rounded),
                                visualDensity:
                                    VisualDensity.compact,
                                tooltip: tr('search'),
                                onPressed: doingSomething
                                    ? null
                                    : () => runSearch(context),
                              ),
                      ],
                    ),
                  ],
                  if (pickedSource == null && userInput.isEmpty) ...[
                    if (shouldShowSearchBar) const SizedBox(height: 13),
                    const ImportSection(),
                  ],
                  if (pickedSource != null)
                    FutureBuilder(
                      future: _sourceNoteFuture,
                      builder: (ctx, val) {
                        if (val.data != null && val.data!.isNotEmpty) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                            child: ConnectedCard(
                              isFirst: true,
                              isLast: true,
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
