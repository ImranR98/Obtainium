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
import 'package:obtainium/app_sources/sourceforge.dart';
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
  late DateTime? lastUpdateCheck;
  App(
      this.id,
      this.url,
      this.author,
      this.name,
      this.installedVersion,
      this.latestVersion,
      this.apkUrls,
      this.preferredApkIndex,
      this.additionalData,
      this.lastUpdateCheck);

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
          ? SourceProvider().getSource(json['url']).additionalDataDefaults
          : List<String>.from(jsonDecode(json['additionalData'])),
      json['lastUpdateCheck'] == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(json['lastUpdateCheck']));

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'author': author,
        'name': name,
        'installedVersion': installedVersion,
        'latestVersion': latestVersion,
        'apkUrls': jsonEncode(apkUrls),
        'preferredApkIndex': preferredApkIndex,
        'additionalData': jsonEncode(additionalData),
        'lastUpdateCheck': lastUpdateCheck?.microsecondsSinceEpoch
      };
}

escapeRegEx(String s) {
  return s.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (x) {
    return '\\${x[0]}';
  });
}

preStandardizeUrl(String url) {
  if (url.toLowerCase().indexOf('http://') != 0 &&
      url.toLowerCase().indexOf('https://') != 0) {
    url = 'https://$url';
  }
  if (url.toLowerCase().indexOf('https://www.') == 0) {
    url = 'https://${url.substring(12)}';
  }
  return url;
}

const String couldNotFindReleases = 'Could not find a suitable release';
const String couldNotFindLatestVersion =
    'Could not determine latest release version';
String notValidURL(String sourceName) {
  return 'Not a valid $sourceName App URL';
}

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
      String standardUrl, List<String> additionalData);
  AppNames getAppNames(String standardUrl);
  late List<List<GeneratedFormItem>> additionalDataFormItems;
  late List<String> additionalDataDefaults;
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
    Signal(),
    SourceForge()
  ];

  // Add more mass source classes here so they are available via the service
  List<MassAppSource> massSources = [GitHubStars()];

  AppSource getSource(String url) {
    url = preStandardizeUrl(url);
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

  bool doesSourceHaveRequiredAdditionalData(AppSource source) {
    for (var row in source.additionalDataFormItems) {
      for (var element in row) {
        if (element.required) {
          return true;
        }
      }
    }
    return false;
  }

  Future<App> getApp(AppSource source, String url, List<String> additionalData,
      {String customName = ''}) async {
    String standardUrl = source.standardizeURL(preStandardizeUrl(url));
    AppNames names = source.getAppNames(standardUrl);
    APKDetails apk =
        await source.getLatestAPKDetails(standardUrl, additionalData);
    return App(
        '${names.author.toLowerCase()}_${names.name.toLowerCase()}_${source.host}',
        standardUrl,
        names.author[0].toUpperCase() + names.author.substring(1),
        customName.trim().isNotEmpty
            ? customName
            : names.name[0].toUpperCase() + names.name.substring(1),
        null,
        apk.version,
        apk.apkUrls,
        apk.apkUrls.length - 1,
        additionalData,
        DateTime.now());
  }

  /// Returns a length 2 list, where the first element is a list of Apps and
  /// the second is a Map<String, dynamic> of URLs and errors
  Future<List<dynamic>> getApps(List<String> urls,
      {List<String> ignoreUrls = const []}) async {
    List<App> apps = [];
    Map<String, dynamic> errors = {};
    for (var url in urls.where((element) => !ignoreUrls.contains(element))) {
      try {
        var source = getSource(url);
        apps.add(await getApp(source, url, source.additionalDataDefaults));
      } catch (e) {
        errors.addAll(<String, dynamic>{url: e});
      }
    }
    return [apps, errors];
  }

  List<String> getSourceHosts() => sources.map((e) => e.host).toList();
}
