// Defines App sources and provides functions used to interact with them
// AppSource is an abstract class with a concrete implementation for each source

import 'dart:convert';

import 'package:html/dom.dart';
import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/app_sources/gitlab.dart';
import 'package:obtainium/app_sources/izzyondroid.dart';
import 'package:obtainium/app_sources/mullvad.dart';
import 'package:obtainium/app_sources/signal.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/mass_app_sources/githubstars.dart';

class AppNames {
  late String author;
  late String name;

  AppNames(this.author, this.name);
}

class APKDetails {
  late String version;
  late List<String> apkUrls;

  APKDetails(this.version, this.apkUrls);
}

class App {
  late String id;
  late String url;
  late String author;
  late String name;
  String? installedVersion;
  late String latestVersion;
  List<String> apkUrls = [];
  late int preferredApkIndex;
  late List<String> additionalData;
  App(
      this.id,
      this.url,
      this.author,
      this.name,
      this.installedVersion,
      this.latestVersion,
      this.apkUrls,
      this.preferredApkIndex,
      this.additionalData);

  @override
  String toString() {
    return 'ID: $id URL: $url INSTALLED: $installedVersion LATEST: $latestVersion APK: $apkUrls';
  }

  factory App.fromJson(Map<String, dynamic> json) => App(
      json['id'] as String,
      json['url'] as String,
      json['author'] as String,
      json['name'] as String,
      json['installedVersion'] == null
          ? null
          : json['installedVersion'] as String,
      json['latestVersion'] as String,
      json['apkUrls'] == null
          ? []
          : List<String>.from(jsonDecode(json['apkUrls'])),
      json['preferredApkIndex'] == null ? 0 : json['preferredApkIndex'] as int,
      json['additionalData'] == null
          ? []
          : List<String>.from(jsonDecode(json['additionalData'])));

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'author': author,
        'name': name,
        'installedVersion': installedVersion,
        'latestVersion': latestVersion,
        'apkUrls': jsonEncode(apkUrls),
        'preferredApkIndex': preferredApkIndex,
        'additionalData': jsonEncode(additionalData)
      };
}

escapeRegEx(String s) {
  return s.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (x) {
    return "\\${x[0]}";
  });
}

makeUrlHttps(String url) {
  if (url.toLowerCase().indexOf('http://') != 0 &&
      url.toLowerCase().indexOf('https://') != 0) {
    url = 'https://$url';
  }
  if (url.toLowerCase().indexOf('https://www.') == 0) {
    url = 'https://${url.substring(12)}';
  }
  return url;
}

const String couldNotFindReleases = 'Unable to fetch release info';
const String couldNotFindLatestVersion =
    'Could not determine latest release version';
const String notValidURL = 'Not a valid URL';
const String noAPKFound = 'No APK found';

List<String> getLinksFromParsedHTML(
        Document dom, RegExp hrefPattern, String prependToLinks) =>
    dom
        .querySelectorAll('a')
        .where((element) {
          if (element.attributes['href'] == null) return false;
          return hrefPattern.hasMatch(element.attributes['href']!);
        })
        .map((e) => '$prependToLinks${e.attributes['href']!}')
        .toList();

abstract class AppSource {
  late String host;
  String standardizeURL(String url);
  Future<APKDetails> getLatestAPKDetails(
      String standardUrl, List<String>? additionalData);
  AppNames getAppNames(String standardUrl);
  late List<List<GeneratedFormItem>> additionalDataFormItems;
  late List<String>
      additionalDataDefaults; // TODO: Make these integrate into generated form
}

abstract class MassAppSource {
  late String name;
  late List<String> requiredArgs;
  Future<List<String>> getUrls(List<String> args);
}

class SourceProvider {
  // Add more source classes here so they are available via the service
  List<AppSource> sources = [
    GitHub(),
    GitLab(),
    FDroid(),
    IzzyOnDroid(),
    Mullvad(),
    Signal()
  ];

  // Add more mass source classes here so they are available via the service
  List<MassAppSource> massSources = [GitHubStars()];

  AppSource getSource(String url) {
    url = makeUrlHttps(url);
    AppSource? source;
    for (var s in sources) {
      if (url.toLowerCase().contains('://${s.host}')) {
        source = s;
        break;
      }
    }
    if (source == null) {
      throw 'URL does not match a known source';
    }
    return source;
  }

  Future<App> getApp(
      AppSource source, String url, List<String> additionalData) async {
    String standardUrl = source.standardizeURL(makeUrlHttps(url));
    AppNames names = source.getAppNames(standardUrl);
    APKDetails apk =
        await source.getLatestAPKDetails(standardUrl, additionalData);
    return App(
        '${names.author.toLowerCase()}_${names.name.toLowerCase()}_${source.host}',
        standardUrl,
        names.author[0].toUpperCase() + names.author.substring(1),
        names.name[0].toUpperCase() + names.name.substring(1),
        null,
        apk.version,
        apk.apkUrls,
        apk.apkUrls.length - 1,
        additionalData);
  }

  /// Returns a length 2 list, where the first element is a list of Apps and
  /// the second is a Map<String, dynamic> of URLs and errors
  Future<List<dynamic>> getApps(List<String> urls) async {
    List<App> apps = [];
    Map<String, dynamic> errors = {};
    for (var url in urls) {
      try {
        apps.add(await getApp(getSource(url), url,
            [])); // TODO: additionalData should have defaults;
      } catch (e) {
        errors.addAll(<String, dynamic>{url: e});
      }
    }
    return [apps, errors];
  }

  List<String> getSourceHosts() => sources.map((e) => e.host).toList();
}
