// Defines App sources and provides functions used to interact with them
// AppSource is an abstract class with a concrete implementation for each source

import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/dom.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/apkmirror.dart';
import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/app_sources/fdroidrepo.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/app_sources/gitlab.dart';
import 'package:obtainium/app_sources/izzyondroid.dart';
import 'package:obtainium/app_sources/mullvad.dart';
import 'package:obtainium/app_sources/signal.dart';
import 'package:obtainium/app_sources/sourceforge.dart';
import 'package:obtainium/app_sources/steammobile.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/mass_app_sources/githubstars.dart';

class AppNames {
  late String author;
  late String name;

  AppNames(this.author, this.name);
}

class APKDetails {
  late String version;
  late List<String> apkUrls;
  late AppNames names;

  APKDetails(this.version, this.apkUrls, this.names);
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
  late Map<String, String> additionalSettings;
  late DateTime? lastUpdateCheck;
  bool pinned = false;
  App(
      this.id,
      this.url,
      this.author,
      this.name,
      this.installedVersion,
      this.latestVersion,
      this.apkUrls,
      this.preferredApkIndex,
      this.additionalSettings,
      this.lastUpdateCheck,
      this.pinned);

  @override
  String toString() {
    return 'ID: $id URL: $url INSTALLED: $installedVersion LATEST: $latestVersion APK: $apkUrls PREFERREDAPK: $preferredApkIndex ADDITIONALSETTINGS: ${additionalSettings.toString()} LASTCHECK: ${lastUpdateCheck.toString()} PINNED $pinned';
  }

  factory App.fromJson(Map<String, dynamic> json) {
    var source = SourceProvider().getSource(json['url']);
    var formItems = source.combinedAppSpecificSettingFormItems
        .reduce((value, element) => [...value, ...element]);
    Map<String, String> additionalSettings =
        getDefaultValuesFromFormItems([formItems]);
    if (json['additionalSettings'] != null) {
      additionalSettings.addEntries(
          Map<String, String>.from(jsonDecode(json['additionalSettings']))
              .entries);
    }
    // If needed, migrate old-style additionalData to new-style additionalSettings
    if (json['additionalData'] != null) {
      List<String> temp = List<String>.from(jsonDecode(json['additionalData']));
      temp.asMap().forEach((i, value) {
        if (i < formItems.length) {
          additionalSettings[formItems[i].key] = value;
        }
      });
      additionalSettings['trackOnly'] = (json['trackOnly'] ?? false).toString();
      additionalSettings['noVersionDetection'] =
          (json['noVersionDetection'] ?? false).toString();
    }
    return App(
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
        json['preferredApkIndex'] == null
            ? 0
            : json['preferredApkIndex'] as int,
        additionalSettings,
        json['lastUpdateCheck'] == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(json['lastUpdateCheck']),
        json['pinned'] ?? false);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'author': author,
        'name': name,
        'installedVersion': installedVersion,
        'latestVersion': latestVersion,
        'apkUrls': jsonEncode(apkUrls),
        'preferredApkIndex': preferredApkIndex,
        'additionalSettings': jsonEncode(additionalSettings),
        'lastUpdateCheck': lastUpdateCheck?.microsecondsSinceEpoch,
        'pinned': pinned
      };
}

// Ensure the input is starts with HTTPS and has no WWW
preStandardizeUrl(String url) {
  if (url.toLowerCase().indexOf('http://') != 0 &&
      url.toLowerCase().indexOf('https://') != 0) {
    url = 'https://$url';
  }
  if (url.toLowerCase().indexOf('https://www.') == 0) {
    url = 'https://${url.substring(12)}';
  }
  url = url
      .split('/')
      .where((e) => e.isNotEmpty)
      .join('/')
      .replaceFirst(':/', '://');
  return url;
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

Map<String, String> getDefaultValuesFromFormItems(
    List<List<GeneratedFormItem>> items) {
  return Map.fromEntries(items
      .map((row) => row.map((el) => MapEntry(el.key, el.defaultValue ?? '')))
      .reduce((value, element) => [...value, ...element]));
}

class AppSource {
  String? host;
  late String name;
  bool enforceTrackOnly = false;

  AppSource() {
    name = runtimeType.toString();
  }

  String standardizeURL(String url) {
    throw NotImplementedError();
  }

  Future<APKDetails> getLatestAPKDetails(
      String standardUrl, Map<String, String> additionalSettings) {
    throw NotImplementedError();
  }

  // Different Sources may need different kinds of additional data for Apps
  List<List<GeneratedFormItem>> additionalSourceAppSpecificSettingFormItems =
      [];

  // Some additional data may be needed for Apps regardless of Source
  final List<List<GeneratedFormItem>>
      additionalAppSpecificSourceAgnosticSettingFormItems = [
    [
      GeneratedFormItem(
        'trackOnly',
        label: tr('trackOnly'),
        type: FormItemType.bool,
      )
    ],
    [
      GeneratedFormItem('noVersionDetection',
          label: 'Do not attempt version detection', // TODO
          type: FormItemType.bool)
    ]
  ];

  // Previous 2 variables combined into one at runtime for convenient usage
  List<List<GeneratedFormItem>> get combinedAppSpecificSettingFormItems {
    return [
      ...additionalSourceAppSpecificSettingFormItems,
      ...additionalAppSpecificSourceAgnosticSettingFormItems
    ];
  }

  // Some Sources may have additional settings at the Source level (not specific to Apps) - these use SettingsProvider
  List<GeneratedFormItem> additionalSourceSpecificSettingFormItems = [];

  String? changeLogPageFromStandardUrl(String standardUrl) {
    return null;
  }

  Future<String> apkUrlPrefetchModifier(String apkUrl) async {
    return apkUrl;
  }

  bool canSearch = false;
  Future<Map<String, String>> search(String query) {
    throw NotImplementedError();
  }

  String? tryInferringAppId(String standardUrl,
      {Map<String, String> additionalSettings = const {}}) {
    return null;
  }
}

ObtainiumError getObtainiumHttpError(Response res) {
  return ObtainiumError(res.reasonPhrase ??
      tr('errorWithHttpStatusCode', args: [res.statusCode.toString()]));
}

abstract class MassAppUrlSource {
  late String name;
  late List<String> requiredArgs;
  Future<Map<String, String>> getUrlsWithDescriptions(List<String> args);
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
    SourceForge(),
    APKMirror(),
    FDroidRepo(),
    SteamMobile()
  ];

  // Add more mass url source classes here so they are available via the service
  List<MassAppUrlSource> massUrlSources = [GitHubStars()];

  AppSource getSource(String url) {
    url = preStandardizeUrl(url);
    AppSource? source;
    for (var s in sources.where((element) => element.host != null)) {
      if (url.contains('://${s.host}')) {
        source = s;
        break;
      }
    }
    if (source == null) {
      for (var s in sources.where((element) => element.host == null)) {
        try {
          s.standardizeURL(url);
          source = s;
          break;
        } catch (e) {
          //
        }
      }
    }
    if (source == null) {
      throw UnsupportedURLError();
    }
    return source;
  }

  bool ifRequiredAppSpecificSettingsExist(AppSource source) {
    for (var row in source.combinedAppSpecificSettingFormItems) {
      for (var element in row) {
        if (element.required && element.opts == null) {
          return true;
        }
      }
    }
    return false;
  }

  String generateTempID(AppNames names, AppSource source) =>
      '${names.author.toLowerCase()}_${names.name.toLowerCase()}_${source.host}';

  bool isTempId(String id) {
    List<String> parts = id.split('_');
    if (parts.length < 3) {
      return false;
    }
    for (int i = 0; i < parts.length - 1; i++) {
      if (RegExp('.*[A-Z].*').hasMatch(parts[i])) {
        // TODO: Look into RegEx for non-Latin characters
        return false;
      }
    }
    return true;
  }

  Future<App> getApp(
      AppSource source, String url, Map<String, String> additionalSettings,
      {App? currentApp,
      bool trackOnlyOverride = false,
      noVersionDetectionOverride = false}) async {
    if (trackOnlyOverride) {
      additionalSettings['trackOnly'] = 'true';
    }
    if (noVersionDetectionOverride) {
      additionalSettings['noVersionDetection'] = 'true';
    }
    var trackOnly = currentApp?.additionalSettings['trackOnly'] == 'true';
    String standardUrl = source.standardizeURL(preStandardizeUrl(url));
    APKDetails apk =
        await source.getLatestAPKDetails(standardUrl, additionalSettings);
    if (apk.apkUrls.isEmpty && !trackOnly) {
      throw NoAPKError();
    }
    String apkVersion = apk.version.replaceAll('/', '-');
    var name = currentApp?.name.trim() ??
        apk.names.name[0].toUpperCase() + apk.names.name.substring(1);
    return App(
        currentApp?.id ??
            source.tryInferringAppId(standardUrl,
                additionalSettings: additionalSettings) ??
            generateTempID(apk.names, source),
        standardUrl,
        apk.names.author[0].toUpperCase() + apk.names.author.substring(1),
        name.trim().isNotEmpty
            ? name
            : apk.names.name[0].toUpperCase() + apk.names.name.substring(1),
        currentApp?.installedVersion,
        apkVersion,
        apk.apkUrls,
        apk.apkUrls.length - 1,
        additionalSettings,
        DateTime.now(),
        currentApp?.pinned ?? false);
  }

  // Returns errors in [results, errors] instead of throwing them
  Future<List<dynamic>> getAppsByURLNaive(List<String> urls,
      {List<String> ignoreUrls = const []}) async {
    List<App> apps = [];
    Map<String, dynamic> errors = {};
    for (var url in urls.where((element) => !ignoreUrls.contains(element))) {
      try {
        var source = getSource(url);
        apps.add(await getApp(
            source,
            url,
            getDefaultValuesFromFormItems(
                source.combinedAppSpecificSettingFormItems)));
      } catch (e) {
        errors.addAll(<String, dynamic>{url: e});
      }
    }
    return [apps, errors];
  }
}
