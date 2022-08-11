import 'package:flutter/material.dart';
import 'package:obtainium/services/apk_service.dart';
import 'package:provider/provider.dart';

void main() async {
  ;
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MultiProvider(
    providers: [
      Provider(
        create: (context) => APKService(),
        dispose: (context, apkInstallService) => apkInstallService.dispose(),
      ),
    ],
    child: const MyApp(),
  ));
}

// Extract a GitHub project name and author account name from a GitHub URL (can be any sub-URL of the project)
Map<String, String>? getAppNamesFromGitHubURL(String url) {
  RegExp regex = RegExp(r"://github.com/[^/]*/[^/]*");
  var match = regex.firstMatch(url.toLowerCase());
  if (match != null) {
    var uri = url.substring(match.start + 14, match.end);
    var slashIndex = uri.indexOf("/");
    var author = uri.substring(0, slashIndex);
    var appName = uri.substring(slashIndex + 1);
    return {"author": author, "appName": appName};
  }
  return null;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Obtainium',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Obtainium'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int ind = 0;
  var urls = [
    "https://github.com/Ashinch/ReadYou/releases/download/0.8.0/ReadYou-0.8.0-eec397e.apk",
    "https://github.com/Ashinch/ReadYou/releases/download/0.8.1/ReadYou-0.8.1-c741f19.apk",
    "https://github.com/Ashinch/ReadYou/releases/download/0.8.3/ReadYou-0.8.3-7a47329.apk"
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              urls[ind] + ind.toString(),
              style: Theme.of(context).textTheme.headline4,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          var names = getAppNamesFromGitHubURL(urls[ind]);
          if (names != null) {
            Provider.of<APKService>(context, listen: false)
                .downloadAndInstallAPK(
                    urls[ind], "${names["author"]!}_${names["appName"]!}");
            setState(() {
              ind = ind == (urls.length - 1) ? 0 : ind + 1;
            });
          }
        },
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
