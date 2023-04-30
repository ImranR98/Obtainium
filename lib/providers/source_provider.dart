// Defines App sources and provides functions used to interact with them
// AppSource is an abstract class with a concrete implementation for each source

import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:html/dom.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/apkmirror.dart';
import 'package:obtainium/app_sources/codeberg.dart';
import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/app_sources/fdroidrepo.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/app_sources/gitlab.dart';
import 'package:obtainium/app_sources/izzyondroid.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/app_sources/mullvad.dart';
import 'package:obtainium/app_sources/neutroncode.dart';
import 'package:obtainium/app_sources/signal.dart';
import 'package:obtainium/app_sources/sourceforge.dart';
import 'package:obtainium/app_sources/steammobile.dart';
import 'package:obtainium/app_sources/telegramapp.dart';
import 'package:obtainium/app_sources/vlc.dart';
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
  late List<MapEntry<String, String>> apkUrls;
  late AppNames names;
  late DateTime? releaseDate;
  late String? changeLog;

  APKDetails(this.version, this.apkUrls, this.names,
      {this.releaseDate, this.changeLog});
}

stringMapListTo2DList(List<MapEntry<String, String>> mapList) =>
    mapList.map((e) => [e.key, e.value]).toList();

assumed2DlistToStringMapList(List<dynamic> arr) =>
    arr.map((e) => MapEntry(e[0] as String, e[1] as String)).toList();

// App JSON schema has changed multiple times over the many versions of Obtainium
// This function takes an App JSON and modifies it if needed to conform to the latest (current) version
appJSONCompatibilityModifiers(Map<String, dynamic> json) {
  var source = SourceProvider()
      .getSource(json['url'], overrideSource: json['overrideSource']);
  var formItems = source.combinedAppSpecificSettingFormItems
      .reduce((value, element) => [...value, ...element]);
  Map<String, dynamic> additionalSettings =
      getDefaultValuesFromFormItems([formItems]);
  if (json['additionalSettings'] != null) {
    additionalSettings.addEntries(
        Map<String, dynamic>.from(jsonDecode(json['additionalSettings']))
            .entries);
  }
  // If needed, migrate old-style additionalData to newer-style additionalSettings (V1)
  if (json['additionalData'] != null) {
    List<String> temp = List<String>.from(jsonDecode(json['additionalData']));
    temp.asMap().forEach((i, value) {
      if (i < formItems.length) {
        if (formItems[i] is GeneratedFormSwitch) {
          additionalSettings[formItems[i].key] = value == 'true';
        } else {
          additionalSettings[formItems[i].key] = value;
        }
      }
    });
    additionalSettings['trackOnly'] =
        json['trackOnly'] == 'true' || json['trackOnly'] == true;
    additionalSettings['noVersionDetection'] =
        json['noVersionDetection'] == 'true' || json['trackOnly'] == true;
  }
  // Convert bool style version detection options to dropdown style
  if (additionalSettings['noVersionDetection'] == true) {
    additionalSettings['versionDetection'] = 'noVersionDetection';
    if (additionalSettings['releaseDateAsVersion'] == true) {
      additionalSettings['versionDetection'] = 'releaseDateAsVersion';
      additionalSettings.remove('releaseDateAsVersion');
    }
    if (additionalSettings['noVersionDetection'] != null) {
      additionalSettings.remove('noVersionDetection');
    }
    if (additionalSettings['releaseDateAsVersion'] != null) {
      additionalSettings.remove('releaseDateAsVersion');
    }
  }
  // Ensure additionalSettings are correctly typed
  for (var item in formItems) {
    if (additionalSettings[item.key] != null) {
      additionalSettings[item.key] =
          item.ensureType(additionalSettings[item.key]);
    }
  }
  int preferredApkIndex =
      json['preferredApkIndex'] == null ? 0 : json['preferredApkIndex'] as int;
  if (preferredApkIndex < 0) {
    preferredApkIndex = 0;
  }
  json['preferredApkIndex'] = preferredApkIndex;
  // apkUrls can either be old list or new named list apkUrls
  List<MapEntry<String, String>> apkUrls = [];
  if (json['apkUrls'] != null) {
    var apkUrlJson = jsonDecode(json['apkUrls']);
    try {
      apkUrls = getApkUrlsFromUrls(List<String>.from(apkUrlJson));
    } catch (e) {
      apkUrls = assumed2DlistToStringMapList(List<dynamic>.from(apkUrlJson));
      apkUrls = List<dynamic>.from(apkUrlJson)
          .map((e) => MapEntry(e[0] as String, e[1] as String))
          .toList();
    }
    json['apkUrls'] = jsonEncode(stringMapListTo2DList(apkUrls));
  }
  // Arch based APK filter option should be disabled if it previously did not exist
  if (additionalSettings['autoApkFilterByArch'] == null) {
    additionalSettings['autoApkFilterByArch'] = false;
  }
  json['additionalSettings'] = jsonEncode(additionalSettings);
  // F-Droid no longer needs cloudflare exception since override can be used - migrate apps appropriately
  // This allows us to reverse the changes made for issue #418 (support cloudflare.f-droid)
  // While not causing problems for existing apps from that source that were added in a previous version
  var overrideSourceWasUndefined = !json.keys.contains('overrideSource');
  if ((json['url'] as String).startsWith('https://cloudflare.f-droid.org')) {
    json['overrideSource'] = FDroid().runtimeType.toString();
  } else if (overrideSourceWasUndefined) {
    // Similar to above, but for third-party F-Droid repos
    RegExpMatch? match = RegExp('^https?://.+/fdroid/([^/]+(/|\\?)|[^/]+\$)')
        .firstMatch(json['url'] as String);
    if (match != null) {
      json['overrideSource'] = FDroidRepo().runtimeType.toString();
    }
  }
  return json;
}

class App {
  late String id;
  late String url;
  late String author;
  late String name;
  String? installedVersion;
  late String latestVersion;
  List<MapEntry<String, String>> apkUrls = [];
  late int preferredApkIndex;
  late Map<String, dynamic> additionalSettings;
  late DateTime? lastUpdateCheck;
  bool pinned = false;
  List<String> categories;
  late DateTime? releaseDate;
  late String? changeLog;
  late String? overrideSource;
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
      this.pinned,
      {this.categories = const [],
      this.releaseDate,
      this.changeLog,
      this.overrideSource});

  @override
  String toString() {
    return 'ID: $id URL: $url INSTALLED: $installedVersion LATEST: $latestVersion APK: $apkUrls PREFERREDAPK: $preferredApkIndex ADDITIONALSETTINGS: ${additionalSettings.toString()} LASTCHECK: ${lastUpdateCheck.toString()} PINNED $pinned';
  }

  String? get overrideName =>
      additionalSettings['appName']?.toString().trim().isNotEmpty == true
          ? additionalSettings['appName']
          : null;

  String get finalName {
    return overrideName ?? name;
  }

  App deepCopy() => App(
      id,
      url,
      author,
      name,
      installedVersion,
      latestVersion,
      apkUrls,
      preferredApkIndex,
      Map.from(additionalSettings),
      lastUpdateCheck,
      pinned,
      categories: categories,
      changeLog: changeLog,
      releaseDate: releaseDate,
      overrideSource: overrideSource);

  factory App.fromJson(Map<String, dynamic> json) {
    json = appJSONCompatibilityModifiers(json);
    return App(
        json['id'] as String,
        json['url'] as String,
        json['author'] as String,
        json['name'] as String,
        json['installedVersion'] == null
            ? null
            : json['installedVersion'] as String,
        json['latestVersion'] as String,
        assumed2DlistToStringMapList(jsonDecode(json['apkUrls'])),
        json['preferredApkIndex'] as int,
        jsonDecode(json['additionalSettings']) as Map<String, dynamic>,
        json['lastUpdateCheck'] == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(json['lastUpdateCheck']),
        json['pinned'] ?? false,
        categories: json['categories'] != null
            ? (json['categories'] as List<dynamic>)
                .map((e) => e.toString())
                .toList()
            : json['category'] != null
                ? [json['category'] as String]
                : [],
        releaseDate: json['releaseDate'] == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(json['releaseDate']),
        changeLog:
            json['changeLog'] == null ? null : json['changeLog'] as String,
        overrideSource: json['overrideSource']);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'author': author,
        'name': name,
        'installedVersion': installedVersion,
        'latestVersion': latestVersion,
        'apkUrls': jsonEncode(stringMapListTo2DList(apkUrls)),
        'preferredApkIndex': preferredApkIndex,
        'additionalSettings': jsonEncode(additionalSettings),
        'lastUpdateCheck': lastUpdateCheck?.microsecondsSinceEpoch,
        'pinned': pinned,
        'categories': categories,
        'releaseDate': releaseDate?.microsecondsSinceEpoch,
        'changeLog': changeLog,
        'overrideSource': overrideSource
      };
}

// Ensure the input is starts with HTTPS and has no WWW
preStandardizeUrl(String url) {
  var firstDotIndex = url.indexOf('.');
  if (!(firstDotIndex >= 0 && firstDotIndex != url.length - 1)) {
    throw UnsupportedURLError();
  }
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

String noAPKFound = tr('noAPKFound');

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

Map<String, dynamic> getDefaultValuesFromFormItems(
    List<List<GeneratedFormItem>> items) {
  return Map.fromEntries(items
      .map((row) => row.map((el) => MapEntry(el.key, el.defaultValue ?? '')))
      .reduce((value, element) => [...value, ...element]));
}

List<MapEntry<String, String>> getApkUrlsFromUrls(List<String> urls) =>
    urls.map((e) {
      var segments = e.split('/').where((el) => el.trim().isNotEmpty);
      var apkSegs = segments.where((s) => s.toLowerCase().endsWith('.apk'));
      return MapEntry(apkSegs.isNotEmpty ? apkSegs.last : segments.last, e);
    }).toList();

abstract class AppSource {
  String? host;
  bool hostChanged = false;
  late String name;
  bool enforceTrackOnly = false;
  bool changeLogIfAnyIsMarkDown = true;

  AppSource() {
    name = runtimeType.toString();
  }

  String standardizeUrl(String url) {
    url = preStandardizeUrl(url);
    if (!hostChanged) {
      url = sourceSpecificStandardizeURL(url);
    }
    return url;
  }

  String sourceSpecificStandardizeURL(String url) {
    throw NotImplementedError();
  }

  Future<APKDetails> getLatestAPKDetails(
      String standardUrl, Map<String, dynamic> additionalSettings) {
    throw NotImplementedError();
  }

  // Different Sources may need different kinds of additional data for Apps
  List<List<GeneratedFormItem>> additionalSourceAppSpecificSettingFormItems =
      [];

  // Some additional data may be needed for Apps regardless of Source
  final List<List<GeneratedFormItem>>
      additionalAppSpecificSourceAgnosticSettingFormItems = [
    [
      GeneratedFormSwitch(
        'trackOnly',
        label: tr('trackOnly'),
      )
    ],
    [
      GeneratedFormDropdown(
          'versionDetection',
          [
            MapEntry(
                'standardVersionDetection', tr('standardVersionDetection')),
            MapEntry('releaseDateAsVersion', tr('releaseDateAsVersion')),
            MapEntry('noVersionDetection', tr('noVersionDetection'))
          ],
          label: tr('versionDetection'),
          defaultValue: 'standardVersionDetection')
    ],
    [
      GeneratedFormTextField('apkFilterRegEx',
          label: tr('filterAPKsByRegEx'),
          required: false,
          additionalValidators: [
            (value) {
              return regExValidator(value);
            }
          ])
    ],
    [
      GeneratedFormSwitch('autoApkFilterByArch',
          label: tr('autoApkFilterByArch'), defaultValue: true)
    ],
    [GeneratedFormTextField('appName', label: tr('appName'), required: false)]
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
      {Map<String, dynamic> additionalSettings = const {}}) {
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

regExValidator(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  try {
    RegExp(value);
  } catch (e) {
    return tr('invalidRegEx');
  }
  return null;
}

class SourceProvider {
  // Add more source classes here so they are available via the service
  List<AppSource> get sources => [
        GitHub(),
        GitLab(),
        Codeberg(),
        FDroid(),
        IzzyOnDroid(),
        FDroidRepo(),
        SourceForge(),
        APKMirror(),
        Mullvad(),
        Signal(),
        VLC(),
        // WhatsApp(), // As of 2023-03-20 this is unusable as the version on the webpage is months out of date
        TelegramApp(),
        SteamMobile(),
        NeutronCode(),
        HTML() // This should ALWAYS be the last option as they are tried in order
      ];

  // Add more mass url source classes here so they are available via the service
  List<MassAppUrlSource> massUrlSources = [GitHubStars()];

  AppSource getSource(String url, {String? overrideSource}) {
    url = preStandardizeUrl(url);
    if (overrideSource != null) {
      var srcs =
          sources.where((e) => e.runtimeType.toString() == overrideSource);
      if (srcs.isEmpty) {
        throw UnsupportedURLError();
      }
      var res = srcs.first;
      res.host = Uri.parse(url).host;
      res.hostChanged = true;
      return srcs.first;
    }
    AppSource? source;
    for (var s in sources.where((element) => element.host != null)) {
      if (RegExp('://${s.host}').hasMatch(url)) {
        source = s;
        break;
      }
    }
    if (source == null) {
      for (var s in sources.where((element) => element.host == null)) {
        try {
          s.sourceSpecificStandardizeURL(url);
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
        if (element is GeneratedFormTextField && element.required) {
          return true;
        }
      }
    }
    return false;
  }

  String generateTempID(
          String standardUrl, Map<String, dynamic> additionalSettings) =>
      (standardUrl + additionalSettings.toString()).hashCode.toString();

  bool isTempId(App app) {
    // return app.id == generateTempID(app.url, app.additionalSettings);
    return RegExp('^[0-9]+\$').hasMatch(app.id);
  }

  Future<App> getApp(
      AppSource source, String url, Map<String, dynamic> additionalSettings,
      {App? currentApp,
      bool trackOnlyOverride = false,
      String? overrideSource}) async {
    if (trackOnlyOverride || source.enforceTrackOnly) {
      additionalSettings['trackOnly'] = true;
    }
    var trackOnly = additionalSettings['trackOnly'] == true;
    String standardUrl = source.standardizeUrl(url);
    APKDetails apk =
        await source.getLatestAPKDetails(standardUrl, additionalSettings);
    if (additionalSettings['versionDetection'] == 'releaseDateAsVersion' &&
        apk.releaseDate != null) {
      apk.version = apk.releaseDate!.microsecondsSinceEpoch.toString();
    }
    if (additionalSettings['apkFilterRegEx'] != null) {
      var reg = RegExp(additionalSettings['apkFilterRegEx']);
      apk.apkUrls =
          apk.apkUrls.where((element) => reg.hasMatch(element.key)).toList();
    }
    if (apk.apkUrls.isEmpty && !trackOnly) {
      throw NoAPKError();
    }
    if (apk.apkUrls.length > 1 &&
        additionalSettings['autoApkFilterByArch'] == true) {
      var abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
      for (var abi in abis) {
        var urls2 = apk.apkUrls
            .where((element) => RegExp('.*$abi.*').hasMatch(element.key))
            .toList();
        if (urls2.isNotEmpty && urls2.length < apk.apkUrls.length) {
          apk.apkUrls = urls2;
          break;
        }
      }
    }
    String apkVersion = apk.version.replaceAll('/', '-');
    var name = currentApp != null ? currentApp.name.trim() : '';
    name = name.isNotEmpty
        ? name
        : apk.names.name[0].toUpperCase() + apk.names.name.substring(1);
    return App(
        currentApp?.id ??
            source.tryInferringAppId(standardUrl,
                additionalSettings: additionalSettings) ??
            generateTempID(standardUrl, additionalSettings),
        standardUrl,
        apk.names.author[0].toUpperCase() + apk.names.author.substring(1),
        name,
        currentApp?.installedVersion,
        apkVersion,
        apk.apkUrls,
        apk.apkUrls.length - 1 >= 0 ? apk.apkUrls.length - 1 : 0,
        additionalSettings,
        DateTime.now(),
        currentApp?.pinned ?? false,
        categories: currentApp?.categories ?? const [],
        releaseDate: apk.releaseDate,
        changeLog: apk.changeLog,
        overrideSource: overrideSource ?? currentApp?.overrideSource);
  }

  // Returns errors in [results, errors] instead of throwing them
  Future<List<dynamic>> getAppsByURLNaive(List<String> urls,
      {List<String> alreadyAddedUrls = const []}) async {
    List<App> apps = [];
    Map<String, dynamic> errors = {};
    for (var url in urls) {
      try {
        if (alreadyAddedUrls.contains(url)) {
          throw ObtainiumError(tr('appAlreadyAdded'));
        }
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
