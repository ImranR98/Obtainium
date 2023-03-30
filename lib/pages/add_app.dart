import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/pages/import_export.dart';
import 'package:obtainium/pages/settings.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AddAppPage extends StatefulWidget {
  const AddAppPage({super.key});

  @override
  State<AddAppPage> createState() => _AddAppPageState();
}

class _AddAppPageState extends State<AddAppPage> {
  bool gettingAppInfo = false;
  bool searching = false;

  String userInput = '';
  String searchQuery = '';
  AppSource? pickedSource;
  Map<String, dynamic> additionalSettings = {};
  bool additionalSettingsValid = true;
  List<String> pickedCategories = [];
  int searchnum = 0;
  SourceProvider sourceProvider = SourceProvider();

  @override
  Widget build(BuildContext context) {
    AppsProvider appsProvider = context.read<AppsProvider>();

    bool doingSomething = gettingAppInfo || searching;

    changeUserInput(String input, bool valid, bool isBuilding,
        {bool isSearch = false}) {
      userInput = input;
      if (!isBuilding) {
        setState(() {
          if (isSearch) {
            searchnum++;
          }
          var source = valid ? sourceProvider.getSource(userInput) : null;
          if (pickedSource.runtimeType != source.runtimeType) {
            pickedSource = source;
            additionalSettings = source != null
                ? getDefaultValuesFromFormItems(
                    source.combinedAppSpecificSettingFormItems)
                : {};
            additionalSettingsValid = source != null
                ? !sourceProvider.ifRequiredAppSpecificSettingsExist(source)
                : true;
          }
        });
      }
    }

    getTrackOnlyConfirmationIfNeeded(bool userPickedTrackOnly) async {
      return (!((userPickedTrackOnly || pickedSource!.enforceTrackOnly) &&
          // ignore: use_build_context_synchronously
          await showDialog(
                  context: context,
                  builder: (BuildContext ctx) {
                    return GeneratedFormModal(
                      title: tr('xIsTrackOnly', args: [
                        pickedSource!.enforceTrackOnly
                            ? tr('source')
                            : tr('app')
                      ]),
                      items: const [],
                      message:
                          '${pickedSource!.enforceTrackOnly ? tr('appsFromSourceAreTrackOnly') : tr('youPickedTrackOnly')}\n\n${tr('trackOnlyAppDescription')}',
                    );
                  }) ==
              null));
    }

    getReleaseDateAsVersionConfirmationIfNeeded(
        bool userPickedTrackOnly) async {
      return (!(additionalSettings['versionDetection'] ==
              'releaseDateAsVersion' &&
          // ignore: use_build_context_synchronously
          await showDialog(
                  context: context,
                  builder: (BuildContext ctx) {
                    return GeneratedFormModal(
                      title: tr('releaseDateAsVersion'),
                      items: const [],
                      message: tr('releaseDateAsVersionExplanation'),
                    );
                  }) ==
              null));
    }

    addApp({bool resetUserInputAfter = false}) async {
      setState(() {
        gettingAppInfo = true;
      });
      try {
        var settingsProvider = context.read<SettingsProvider>();
        var userPickedTrackOnly = additionalSettings['trackOnly'] == true;
        App? app;
        if ((await getTrackOnlyConfirmationIfNeeded(userPickedTrackOnly)) &&
            (await getReleaseDateAsVersionConfirmationIfNeeded(
                userPickedTrackOnly))) {
          var trackOnly = pickedSource!.enforceTrackOnly || userPickedTrackOnly;
          app = await sourceProvider.getApp(
              pickedSource!, userInput, additionalSettings,
              trackOnlyOverride: trackOnly);
          if (!trackOnly) {
            await settingsProvider.getInstallPermission();
          }
          // Only download the APK here if you need to for the package ID
          if (sourceProvider.isTempId(app) &&
              app.additionalSettings['trackOnly'] != true) {
            // ignore: use_build_context_synchronously
            var apkUrl = await appsProvider.confirmApkUrl(app, context);
            if (apkUrl == null) {
              throw ObtainiumError(tr('cancelled'));
            }
            app.preferredApkIndex = app.apkUrls.indexOf(apkUrl);
            // ignore: use_build_context_synchronously
            var downloadedApk = await appsProvider.downloadApp(
                app, globalNavigatorKey.currentContext);
            app.id = downloadedApk.appId;
          }
          if (appsProvider.apps.containsKey(app.id)) {
            throw ObtainiumError(tr('appAlreadyAdded'));
          }
          if (app.additionalSettings['trackOnly'] == true) {
            app.installedVersion = app.latestVersion;
          }
          app.categories = pickedCategories;
          await appsProvider.saveApps([app], onlyIfExists: false);
        }
        if (app != null) {
          Navigator.push(globalNavigatorKey.currentContext ?? context,
              MaterialPageRoute(builder: (context) => AppPage(appId: app!.id)));
        }
      } catch (e) {
        showError(e, context);
      } finally {
        setState(() {
          gettingAppInfo = false;
          if (resetUserInputAfter) {
            changeUserInput('', false, true);
          }
        });
      }
    }

    Widget getUrlInputRow() => Row(
          children: [
            Expanded(
                child: GeneratedForm(
                    key: Key(searchnum.toString()),
                    items: [
                      [
                        GeneratedFormTextField('appSourceURL',
                            label: tr('appSourceURL'),
                            defaultValue: userInput,
                            additionalValidators: [
                              (value) {
                                try {
                                  sourceProvider
                                      .getSource(value ?? '')
                                      .standardizeURL(
                                          preStandardizeUrl(value ?? ''));
                                } catch (e) {
                                  return e is String
                                      ? e
                                      : e is ObtainiumError
                                          ? e.toString()
                                          : tr('error');
                                }
                                return null;
                              }
                            ])
                      ]
                    ],
                    onValueChanges: (values, valid, isBuilding) {
                      changeUserInput(
                          values['appSourceURL']!, valid, isBuilding);
                    })),
            const SizedBox(
              width: 16,
            ),
            gettingAppInfo
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: doingSomething ||
                            pickedSource == null ||
                            (pickedSource!.combinedAppSpecificSettingFormItems
                                    .isNotEmpty &&
                                !additionalSettingsValid)
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            addApp();
                          },
                    child: Text(tr('add')))
          ],
        );

    runSearch() async {
      setState(() {
        searching = true;
      });
      try {
        var results = await Future.wait(sourceProvider.sources
            .where((e) => e.canSearch)
            .map((e) => e.search(searchQuery)));

        // .then((results) async {
        // Interleave results instead of simple reduce
        Map<String, String> res = {};
        var si = 0;
        var done = false;
        while (!done) {
          done = true;
          for (var r in results) {
            if (r.length > si) {
              done = false;
              res.addEntries([r.entries.elementAt(si)]);
            }
          }
          si++;
        }
        List<String>? selectedUrls = res.isEmpty
            ? []
            // ignore: use_build_context_synchronously
            : await showDialog<List<String>?>(
                context: context,
                builder: (BuildContext ctx) {
                  return UrlSelectionModal(
                    urlsWithDescriptions: res,
                    selectedByDefault: false,
                    onlyOneSelectionAllowed: true,
                  );
                });
        if (selectedUrls != null && selectedUrls.isNotEmpty) {
          changeUserInput(selectedUrls[0], true, false, isSearch: true);
        }
      } catch (e) {
        showError(e, context);
      } finally {
        setState(() {
          searching = false;
        });
      }
    }

    bool shouldShowSearchBar() =>
        sourceProvider.sources.where((e) => e.canSearch).isNotEmpty &&
        pickedSource == null &&
        userInput.isEmpty;

    Widget getSearchBarRow() => Row(
          children: [
            Expanded(
              child: GeneratedForm(
                  items: [
                    [
                      GeneratedFormTextField('searchSomeSources',
                          label: tr('searchSomeSourcesLabel'), required: false),
                    ]
                  ],
                  onValueChanges: (values, valid, isBuilding) {
                    if (values.isNotEmpty && valid && !isBuilding) {
                      setState(() {
                        searchQuery = values['searchSomeSources']!.trim();
                      });
                    }
                  }),
            ),
            const SizedBox(
              width: 16,
            ),
            ElevatedButton(
                onPressed: searchQuery.isEmpty || doingSomething
                    ? null
                    : () {
                        runSearch();
                      },
                child: Text(tr('search')))
          ],
        );

    Widget getAdditionalOptsCol() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(
              height: 64,
            ),
            Text(
                tr('additionalOptsFor',
                    args: [pickedSource?.name ?? tr('source')]),
                style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            const SizedBox(
              height: 16,
            ),
            GeneratedForm(
                key: Key(pickedSource.runtimeType.toString()),
                items: pickedSource!.combinedAppSpecificSettingFormItems,
                onValueChanges: (values, valid, isBuilding) {
                  if (!isBuilding) {
                    setState(() {
                      additionalSettings = values;
                      additionalSettingsValid = valid;
                    });
                  }
                }),
            Column(
              children: [
                const SizedBox(
                  height: 16,
                ),
                CategoryEditorSelector(
                    alignment: WrapAlignment.start,
                    onSelected: (categories) {
                      pickedCategories = categories;
                    }),
              ],
            ),
          ],
        );

    Widget getSourcesListWidget() => Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              const SizedBox(
                height: 48,
              ),
              Text(
                tr('supportedSourcesBelow'),
              ),
              const SizedBox(
                height: 8,
              ),
              ...sourceProvider.sources
                  .map((e) => GestureDetector(
                      onTap: e.host != null
                          ? () {
                              launchUrlString('https://${e.host}',
                                  mode: LaunchMode.externalApplication);
                            }
                          : null,
                      child: Text(
                        '${e.name}${e.enforceTrackOnly ? ' ${tr('trackOnlyInBrackets')}' : ''}${e.canSearch ? ' ${tr('searchableInBrackets')}' : ''}',
                        style: TextStyle(
                            decoration: e.host != null
                                ? TextDecoration.underline
                                : TextDecoration.none,
                            fontStyle: FontStyle.italic),
                      )))
                  .toList()
            ]));

    return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: CustomScrollView(slivers: <Widget>[
          CustomAppBar(title: tr('addApp')),
          SliverFillRemaining(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      getUrlInputRow(),
                      if (shouldShowSearchBar())
                        const SizedBox(
                          height: 16,
                        ),
                      if (shouldShowSearchBar()) getSearchBarRow(),
                      if (pickedSource != null)
                        getAdditionalOptsCol()
                      else
                        getSourcesListWidget(),
                      const SizedBox(
                        height: 8,
                      ),
                    ])),
          )
        ]));
  }
}
