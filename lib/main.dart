import 'package:flutter/material.dart';
import 'package:obtainium/pages/apps.dart';
import 'package:obtainium/services/apps_provider.dart';
import 'package:provider/provider.dart';
import 'package:toast/toast.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MultiProvider(
    providers: [ChangeNotifierProvider(create: (context) => AppsProvider())],
    child: const MyApp(),
  ));
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
        // home: const MyHomePage(title: 'Obtainium'),
        home: const AppsPage());
  }
}

// class MyHomePage extends StatefulWidget {
//   const MyHomePage({super.key, required this.title});

//   final String title;

//   @override
//   State<MyHomePage> createState() => _MyHomePageState();
// }

// class _MyHomePageState extends State<MyHomePage> {
//   int ind = 0;
//   List<String> urls = [
//     'https://github.com/Ashinch/ReadYou/releases/download', // Should work
//     'http://github.com/syncthing/syncthing-android/releases/tag/1.20.4', // Should work
//     'https://github.com/videolan/vlc' // Should not
//   ];

//   @override
//   Widget build(BuildContext context) {
//     ToastContext().init(context);
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(widget.title),
//       ),
//       body: Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: <Widget>[
//             Text(
//               urls[ind],
//               style: Theme.of(context).textTheme.headline4,
//             ),
//           ],
//         ),
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: () {
//           context.read<AppsProvider>().installApp(urls[ind]).then((_) {
//             setState(() {
//               ind = ind == (urls.length - 1) ? 0 : ind + 1;
//             });
//           }).catchError((err) {
//             if (err is! String) {
//               err = "Unknown Error";
//             }
//             Toast.show(err);
//           });
//         },
//         tooltip: 'Increment',
//         child: const Icon(Icons.add),
//       ),
//     );
//   }

//   @override
//   void dispose() {
//     super.dispose();
//   }
// }
