class App {
  late String id;
  late String url;
  String? installedVersion;
  late String latestVersion;
  String? readmeHTML;
  String? base64Icon;
  App(this.id, this.url, this.installedVersion, this.latestVersion,
      this.readmeHTML, this.base64Icon);
}
