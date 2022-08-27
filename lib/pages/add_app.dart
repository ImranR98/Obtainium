import 'package:flutter/material.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';

class AddAppPage extends StatefulWidget {
  const AddAppPage({super.key});

  @override
  State<AddAppPage> createState() => _AddAppPageState();
}

class _AddAppPageState extends State<AddAppPage> {
  final _formKey = GlobalKey<FormState>();
  final urlInputController = TextEditingController();
  bool gettingAppInfo = false;

  @override
  Widget build(BuildContext context) {
    return Center(
        child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextFormField(
                decoration: const InputDecoration(
                    hintText: 'https://github.com/Author/Project',
                    helperText: 'Enter the App source URL'),
                controller: urlInputController,
                validator: (value) {
                  if (value == null ||
                      value.isEmpty ||
                      Uri.tryParse(value) == null) {
                    return 'Please enter a supported source URL';
                  }
                  return null;
                },
              )),
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
            child: ElevatedButton(
              onPressed: gettingAppInfo
                  ? null
                  : () {
                      if (_formKey.currentState!.validate()) {
                        setState(() {
                          gettingAppInfo = true;
                        });
                        sourceProvider()
                            .getApp(urlInputController.value.text)
                            .then((app) {
                          var appsProvider = context.read<AppsProvider>();
                          var settingsProvider =
                              context.read<SettingsProvider>();
                          if (appsProvider.apps.containsKey(app.id)) {
                            throw 'App already added';
                          }
                          settingsProvider.getInstallPermission().then((_) {
                            appsProvider.saveApp(app).then((_) {
                              urlInputController.clear();
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          AppPage(appId: app.id)));
                            });
                          });
                        }).catchError((e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString())),
                          );
                        }).whenComplete(() {
                          setState(() {
                            gettingAppInfo = false;
                          });
                        });
                      }
                    },
              child: const Text('Add'),
            ),
          ),
          const Spacer(),
          if (gettingAppInfo) const LinearProgressIndicator(),
        ],
      ),
    ));
  }
}
