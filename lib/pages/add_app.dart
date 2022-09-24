import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/pages/app.dart';
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

  String userInput = "";
  AppSource? pickedSource;
  List<String> additionalData = [];
  bool validAdditionalData = true;

  @override
  Widget build(BuildContext context) {
    SourceProvider sourceProvider = SourceProvider();
    return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: CustomScrollView(slivers: <Widget>[
          const CustomAppBar(title: 'Add App'),
          SliverFillRemaining(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: GeneratedForm(
                                  items: [
                                    [
                                      GeneratedFormItem(
                                          label: "App Source Url",
                                          additionalValidators: [
                                            (value) {
                                              try {
                                                sourceProvider
                                                    .getSource(value ?? "")
                                                    .standardizeURL(
                                                        makeUrlHttps(
                                                            value ?? ""));
                                              } catch (e) {
                                                return e is String
                                                    ? e
                                                    : "Error";
                                              }
                                              return null;
                                            }
                                          ])
                                    ]
                                  ],
                                  onValueChanges: (values, valid) {
                                    setState(() {
                                      userInput = values[0];
                                      var source = valid
                                          ? sourceProvider.getSource(userInput)
                                          : null;
                                      if (pickedSource != source) {
                                        pickedSource = source;
                                        additionalData = source != null
                                            ? source.additionalDataDefaults
                                            : [];
                                        validAdditionalData = source != null
                                            ? sourceProvider
                                                .doesSourceHaveRequiredAdditionalData(
                                                    source)
                                            : true;
                                      }
                                    });
                                  },
                                  defaultValues: const [])),
                          const SizedBox(
                            width: 16,
                          ),
                          ElevatedButton(
                              onPressed: gettingAppInfo ||
                                      pickedSource == null ||
                                      (pickedSource!.additionalDataFormItems
                                              .isNotEmpty &&
                                          !validAdditionalData)
                                  ? null
                                  : () {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        gettingAppInfo = true;
                                      });
                                      sourceProvider
                                          .getApp(pickedSource!, userInput,
                                              additionalData)
                                          .then((app) {
                                        var appsProvider =
                                            context.read<AppsProvider>();
                                        var settingsProvider =
                                            context.read<SettingsProvider>();
                                        if (appsProvider.apps
                                            .containsKey(app.id)) {
                                          throw 'App already added';
                                        }
                                        settingsProvider
                                            .getInstallPermission()
                                            .then((_) {
                                          appsProvider.saveApp(app).then((_) {
                                            Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                    builder: (context) =>
                                                        AppPage(
                                                            appId: app.id)));
                                          });
                                        });
                                      }).catchError((e) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(content: Text(e.toString())),
                                        );
                                      }).whenComplete(() {
                                        setState(() {
                                          gettingAppInfo = false;
                                        });
                                      });
                                    },
                              child: const Text('Add'))
                        ],
                      ),
                      if (pickedSource != null &&
                          (pickedSource!.additionalDataFormItems.isNotEmpty))
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Divider(
                              height: 64,
                            ),
                            Text(
                                'Additional Options for ${pickedSource?.runtimeType}',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary)),
                            const SizedBox(
                              height: 16,
                            ),
                            GeneratedForm(
                                items: pickedSource!.additionalDataFormItems,
                                onValueChanges: (values, valid) {
                                  setState(() {
                                    additionalData = values;
                                    validAdditionalData = valid;
                                  });
                                },
                                defaultValues:
                                    pickedSource!.additionalDataDefaults)
                          ],
                        )
                      else
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                              // const SizedBox(
                              //   height: 48,
                              // ),
                              const Text(
                                'Supported Sources:',
                              ),
                              const SizedBox(
                                height: 8,
                              ),
                              ...sourceProvider
                                  .getSourceHosts()
                                  .map((e) => GestureDetector(
                                      onTap: () {
                                        launchUrlString('https://$e',
                                            mode:
                                                LaunchMode.externalApplication);
                                      },
                                      child: Text(
                                        e,
                                        style: const TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            fontStyle: FontStyle.italic),
                                      )))
                                  .toList()
                            ])),
                    ])),
          )
        ]));
  }
}
