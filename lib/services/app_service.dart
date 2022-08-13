import 'package:obtainium/services/source_service.dart';

class App {
  late String id;
  late String url;
  String? installedVersion;
  late String latestVersion;
  late String apkUrl;
  App(this.id, this.url, this.installedVersion, this.latestVersion,
      this.apkUrl);
}

class AppService {
  late SourceService sourceService;
  AppService(this.sourceService);

  Future<App> getApp(String url) async {
    AppSource source = sourceService.getSource(url);
    String standardUrl = source.standardizeURL(url);
    AppNames names = source.getAppNames(standardUrl);
    APKDetails apk = await source.getLatestAPKUrl(standardUrl);
    return App("${names.author}_${names.name}", standardUrl, null, apk.version,
        apk.downloadUrl);
  }

  // Load Apps, Save App
}
