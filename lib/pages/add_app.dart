import 'package:flutter/material.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/services/apps_provider.dart';
import 'package:obtainium/services/source_service.dart';
import 'package:provider/provider.dart';

class AddAppPage extends StatefulWidget {
  const AddAppPage({super.key});

  @override
  State<AddAppPage> createState() => _AddAppPageState();
}

class _AddAppPageState extends State<AddAppPage> {
  final _formKey = GlobalKey<FormState>();
  final urlInputController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Obtainium - Add App'),
      ),
      body: Center(
          child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextFormField(
              controller: urlInputController,
              validator: (value) {
                if (value == null ||
                    value.isEmpty ||
                    Uri.tryParse(value) == null) {
                  return 'Please enter a supported source URL';
                }
                return null;
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    SourceService()
                        .getApp(urlInputController.value.text)
                        .then((app) {
                      var appsProvider = context.read<AppsProvider>();
                      appsProvider.saveApp(app).then((_) {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => AppPage(appId: app.id)));
                      });
                    }).catchError((e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    });
                  }
                },
                child: const Text('Add'),
              ),
            ),
          ],
        ),
      )),
    );
  }
}
