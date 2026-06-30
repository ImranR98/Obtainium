// Defines App sources and provides functions used to interact with them
// AppSource is an abstract class with a concrete implementation for each source

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:html/dom.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/apkcombo.dart';
import 'package:obtainium/app_sources/apkmirror.dart';
import 'package:obtainium/app_sources/apkpure.dart';
import 'package:obtainium/app_sources/aptoide.dart';
import 'package:obtainium/app_sources/apk4free.dart';
import 'package:obtainium/app_sources/codeberg.dart';
import 'package:obtainium/app_sources/coolapk.dart';
import 'package:obtainium/app_sources/direct_apk_link.dart';
import 'package:obtainium/app_sources/farsroid.dart';
import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/app_sources/fdroidrepo.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/app_sources/gitlab.dart';
import 'package:obtainium/app_sources/huaweiappgallery.dart';
import 'package:obtainium/app_sources/itchio.dart';
import 'package:obtainium/app_sources/izzyondroid.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/app_sources/jenkins.dart';
import 'package:obtainium/app_sources/liteapks.dart';
import 'package:obtainium/app_sources/neutroncode.dart';
import 'package:obtainium/app_sources/rockmods.dart';
import 'package:obtainium/app_sources/rustore.dart';
import 'package:obtainium/app_sources/sourceforge.dart';
import 'package:obtainium/app_sources/sourcehut.dart';
import 'package:obtainium/app_sources/telegramapp.dart';
import 'package:obtainium/app_sources/tencent.dart';
import 'package:obtainium/app_sources/uptodown.dart';
import 'package:obtainium/app_sources/vivoappstore.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/mass_app_sources/githubstars.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';

class AppNames {
  late String author;
  late String name;

  AppNames(this.author, this.name);
}

class APKDetails {
  String version;
  List<MapEntry<String, String>> apkUrls;
  final AppNames names;
  final DateTime? releaseDate;
  String? changeLog;
  final List<MapEntry<String, String>> allAssetUrls;

  APKDetails(
    this.version,
    this.apkUrls,
    this.names, {
    this.releaseDate,
    this.changeLog,
    this.allAssetUrls = const [],
  });
}

List<List<String>> stringMapListTo2DList(
  List<MapEntry<String, String>> mapList,
) => mapList.map((e) => [e.key, e.value]).toList();

List<MapEntry<String, String>> assumed2DlistToStringMapList(
  List<dynamic> arr,
) => arr.map((e) => MapEntry(e[0] as String, e[1] as String)).toList();

// Bumped only for the one-time legacy migrations below. Apps whose stored JSON
// already carries this version skip those legacy URL/source conversions. Their
// default settings are still always reconciled afterwards, so this stays safe
// even when newer builds add settings without bumping this number.
const int currentAppJSONCompatVersion = 1;
const _maxRedirects = 10;
const _connectionTimeoutSeconds = 30;

// App JSON schema has changed multiple times over the many versions of Obtainium
// This function takes an App JSON and modifies it if needed to conform to the latest (current) version
Map<String, dynamic> appJSONCompatibilityModifiers(Map<String, dynamic> json) {
  final isCurrentCompat = json['compatVersion'] == currentAppJSONCompatVersion;
  var source = SourceProvider().getSource(
    json['url'],
    overrideSource: json['overrideSource'],
  );
  // Read-only: only used here to read defaults/keys/types, never mutated, so a
  // shared memoized list is safe and avoids re-cloning the form tree per app.
  var formItems = source.flatCombinedFormItemsReadOnly;
  Map<String, dynamic> additionalSettings = getDefaultValuesFromFormItems([
    formItems,
  ]);
  Map<String, dynamic> originalAdditionalSettings = {};
  if (json['additionalSettings'] != null) {
    originalAdditionalSettings = Map<String, dynamic>.from(
      jsonDecode(json['additionalSettings']),
    );
    additionalSettings.addEntries(originalAdditionalSettings.entries);
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
  // Convert dropdown style version detection options back into bool style
  if (additionalSettings['versionDetection'] == 'standardVersionDetection') {
    additionalSettings['versionDetection'] = true;
  } else if (additionalSettings['versionDetection'] == 'noVersionDetection') {
    additionalSettings['versionDetection'] = false;
  } else if (additionalSettings['versionDetection'] == 'releaseDateAsVersion') {
    additionalSettings['versionDetection'] = false;
    additionalSettings['releaseDateAsVersion'] = true;
  }
  // Convert bool style pseudo version method to dropdown style
  if (originalAdditionalSettings['supportFixedAPKURL'] == true) {
    additionalSettings['defaultPseudoVersioningMethod'] = 'partialAPKHash';
  } else if (originalAdditionalSettings['supportFixedAPKURL'] == false) {
    additionalSettings['defaultPseudoVersioningMethod'] = 'APKLinkHash';
  }
  // Ensure additionalSettings are correctly typed
  for (var item in formItems) {
    if (additionalSettings[item.key] != null) {
      additionalSettings[item.key] = item.ensureType(
        additionalSettings[item.key],
      );
    }
  }
  int preferredApkIndex = json['preferredApkIndex'] == null
      ? 0
      : json['preferredApkIndex'] as int;
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
    }
    json['apkUrls'] = jsonEncode(stringMapListTo2DList(apkUrls));
  }
  // Arch based APK filter option should be disabled if it previously did not exist
  if (additionalSettings['autoApkFilterByArch'] == null) {
    additionalSettings['autoApkFilterByArch'] = false;
  }
  // GitHub "don't sort" option to new dropdown format
  if (additionalSettings['dontSortReleasesList'] == true) {
    additionalSettings['sortMethodChoice'] = 'none';
  }
  if (!isCurrentCompat && source.runtimeType == HTML().runtimeType) {
    // HTML key rename
    if (originalAdditionalSettings['sortByFileNamesNotLinks'] != null) {
      additionalSettings['sortByLastLinkSegment'] =
          originalAdditionalSettings['sortByFileNamesNotLinks'];
    }
    // HTML single 'intermediate link' should be converted to multi-support version
    if (originalAdditionalSettings['intermediateLinkRegex'] != null &&
        additionalSettings['intermediateLinkRegex']?.isNotEmpty != true) {
      additionalSettings['intermediateLink'] = [
        {
          'customLinkFilterRegex':
              originalAdditionalSettings['intermediateLinkRegex'],
          'filterByLinkText':
              originalAdditionalSettings['intermediateLinkByText'],
        },
      ];
    }
    if ((additionalSettings['intermediateLink']?.length ?? 0) > 0) {
      additionalSettings['intermediateLink'] =
          additionalSettings['intermediateLink'].where((e) {
            return e['customLinkFilterRegex']?.isNotEmpty == true;
          }).toList();
    }
    // Steam source apps should be converted to HTML (#1244)
    var legacySteamSourceApps = ['steam', 'steam-chat-app'];
    if (legacySteamSourceApps.contains(additionalSettings['app'] ?? '')) {
      json['url'] = '${json['url']}/mobile';
      var replacementAdditionalSettings = getDefaultValuesFromFormItems(
        HTML().combinedAppSpecificSettingFormItems,
      );
      for (var s in replacementAdditionalSettings.keys) {
        if (additionalSettings.containsKey(s)) {
          replacementAdditionalSettings[s] = additionalSettings[s];
        }
      }
      replacementAdditionalSettings['customLinkFilterRegex'] =
          '/${additionalSettings['app']}-(([0-9]+\\.?){1,})\\.apk';
      replacementAdditionalSettings['versionExtractionRegEx'] =
          replacementAdditionalSettings['customLinkFilterRegex'];
      replacementAdditionalSettings['matchGroupToUse'] = '\$1';
      additionalSettings = replacementAdditionalSettings;
    }
    // Signal apps from before it was removed should be converted to HTML (#1928)
    if (json['url'] == 'https://signal.org' &&
        json['id'] == 'org.thoughtcrime.securesms' &&
        json['author'] == 'Signal' &&
        json['name'] == 'Signal' &&
        json['overrideSource'] == null &&
        additionalSettings['trackOnly'] == false &&
        additionalSettings['versionExtractionRegEx'] == '' &&
        json['lastUpdateCheck'] != null) {
      json['url'] = 'https://updates.signal.org/android/latest.json';
      var replacementAdditionalSettings = getDefaultValuesFromFormItems(
        HTML().combinedAppSpecificSettingFormItems,
      );
      replacementAdditionalSettings['versionExtractionRegEx'] =
          '\\d+.\\d+.\\d+';
      additionalSettings = replacementAdditionalSettings;
    }
    // WhatsApp from before it was removed should be converted to HTML (#1943)
    if (json['url'] == 'https://whatsapp.com' &&
        json['id'] == 'com.whatsapp' &&
        json['author'] == 'Meta' &&
        json['name'] == 'WhatsApp' &&
        json['overrideSource'] == null &&
        additionalSettings['trackOnly'] == false &&
        additionalSettings['versionExtractionRegEx'] == '' &&
        json['lastUpdateCheck'] != null) {
      json['url'] = 'https://whatsapp.com/android';
      var replacementAdditionalSettings = getDefaultValuesFromFormItems(
        HTML().combinedAppSpecificSettingFormItems,
      );
      replacementAdditionalSettings['refreshBeforeDownload'] = true;
      additionalSettings = replacementAdditionalSettings;
    }
    // VLC from before it was removed should be converted to HTML (#1943)
    if (json['url'] == 'https://videolan.org' &&
        json['id'] == 'org.videolan.vlc' &&
        json['author'] == 'VideoLAN' &&
        json['name'] == 'VLC' &&
        json['overrideSource'] == null &&
        additionalSettings['trackOnly'] == false &&
        additionalSettings['versionExtractionRegEx'] == '' &&
        json['lastUpdateCheck'] != null) {
      json['url'] = 'https://www.videolan.org/vlc/download-android.html';
      var replacementAdditionalSettings = getDefaultValuesFromFormItems(
        HTML().combinedAppSpecificSettingFormItems,
      );
      replacementAdditionalSettings['refreshBeforeDownload'] = true;
      replacementAdditionalSettings['intermediateLink'] =
          <Map<String, dynamic>>[
            {
              'customLinkFilterRegex': 'APK',
              'filterByLinkText': true,
              'skipSort': false,
              'reverseSort': false,
              'sortByLastLinkSegment': false,
            },
            {
              'customLinkFilterRegex': 'arm64-v8a\\.apk\$',
              'filterByLinkText': false,
              'skipSort': false,
              'reverseSort': false,
              'sortByLastLinkSegment': false,
            },
          ];
      replacementAdditionalSettings['versionExtractionRegEx'] =
          '/vlc-android/([^/]+)/';
      replacementAdditionalSettings['matchGroupToUse'] = "1";
      additionalSettings = replacementAdditionalSettings;
    }
  }
  json['additionalSettings'] = jsonEncode(additionalSettings);
  if (!isCurrentCompat) {
    // F-Droid no longer needs cloudflare exception since override can be used - migrate apps appropriately
    // This allows us to reverse the changes made for issue #418 (support cloudflare.f-droid)
    // While not causing problems for existing apps from that source that were added in a previous version
    var overrideSourceWasUndefined = !json.keys.contains('overrideSource');
    if ((json['url'] as String).startsWith('https://cloudflare.f-droid.org')) {
      json['overrideSource'] = FDroid().runtimeType.toString();
    } else if (overrideSourceWasUndefined) {
      // Similar to above, but for third-party F-Droid repos
      RegExpMatch? match = RegExp(
        '^https?://.+/fdroid/([^/]+(/|\\?)|[^/]+\$)',
      ).firstMatch(json['url'] as String);
      if (match != null) {
        json['overrideSource'] = FDroidRepo().runtimeType.toString();
      }
    }
  }
  json['compatVersion'] = currentAppJSONCompatVersion;
  return json;
}

class App {
  String id;
  String url;
  final String author;
  String name;
  String? installedVersion;
  String latestVersion;
  List<MapEntry<String, String>> apkUrls = [];
  List<MapEntry<String, String>> otherAssetUrls = [];
  int preferredApkIndex;
  Map<String, dynamic> additionalSettings;
  final DateTime? lastUpdateCheck;
  bool pinned = false;
  List<String> categories;
  final DateTime? releaseDate;
  String? changeLog;
  final String? overrideSource;
  bool allowIdChange = false;
  String? pendingRepoRenameUrl;
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
    this.pinned, {
    this.categories = const [],
    this.releaseDate,
    this.changeLog,
    this.overrideSource,
    this.allowIdChange = false,
    this.otherAssetUrls = const [],
    this.pendingRepoRenameUrl,
  });

  @override
  String toString() {
    return 'ID: $id URL: $url INSTALLED: $installedVersion LATEST: $latestVersion APK: $apkUrls PREFERREDAPK: $preferredApkIndex ADDITIONALSETTINGS: ${additionalSettings.toString()} LASTCHECK: ${lastUpdateCheck.toString()} PINNED $pinned';
  }

  bool get hasPendingRepoRename =>
      pendingRepoRenameUrl != null && pendingRepoRenameUrl!.isNotEmpty;

  String? get overrideName =>
      additionalSettings['appName']?.toString().trim().isNotEmpty == true
      ? additionalSettings['appName']
      : null;

  String get finalName {
    return overrideName ?? name;
  }

  String? get overrideAuthor =>
      additionalSettings['appAuthor']?.toString().trim().isNotEmpty == true
      ? additionalSettings['appAuthor']
      : null;

  String get finalAuthor {
    return overrideAuthor ?? author;
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
    overrideSource: overrideSource,
    allowIdChange: allowIdChange,
    otherAssetUrls: otherAssetUrls,
    pendingRepoRenameUrl: pendingRepoRenameUrl,
  );

  factory App.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> originalJSON = Map.from(json);
    try {
      json = appJSONCompatibilityModifiers(json);
    } catch (e) {
      LogsProvider().add(
        'Error running JSON compat modifiers: ${e.toString()}: ${originalJSON.toString()}',
      );
      json = originalJSON;
      json['compatVersion'] = currentAppJSONCompatVersion;
    }
    return App(
      json['id'] as String,
      json['url'] as String,
      json['author'] as String,
      json['name'] as String,
      json['installedVersion'] == null
          ? null
          : json['installedVersion'] as String,
      (json['latestVersion'] ?? tr('unknown')) as String,
      assumed2DlistToStringMapList(
        jsonDecode((json['apkUrls'] ?? '[["placeholder", "placeholder"]]')),
      ),
      (json['preferredApkIndex'] ?? -1) as int,
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
      changeLog: json['changeLog'] == null ? null : json['changeLog'] as String,
      overrideSource: json['overrideSource'],
      allowIdChange: json['allowIdChange'] ?? false,
      otherAssetUrls: assumed2DlistToStringMapList(
        jsonDecode((json['otherAssetUrls'] ?? '[]')),
      ),
      pendingRepoRenameUrl: json['pendingRepoRenameUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'author': author,
    'name': name,
    'installedVersion': installedVersion,
    'latestVersion': latestVersion,
    'apkUrls': jsonEncode(stringMapListTo2DList(apkUrls)),
    'otherAssetUrls': jsonEncode(stringMapListTo2DList(otherAssetUrls)),
    'preferredApkIndex': preferredApkIndex,
    'additionalSettings': jsonEncode(additionalSettings),
    'lastUpdateCheck': lastUpdateCheck?.microsecondsSinceEpoch,
    'pinned': pinned,
    'categories': categories,
    'releaseDate': releaseDate?.microsecondsSinceEpoch,
    'changeLog': changeLog,
    'overrideSource': overrideSource,
    'allowIdChange': allowIdChange,
    'pendingRepoRenameUrl': pendingRepoRenameUrl,
    'compatVersion': currentAppJSONCompatVersion,
  };
}

// Ensure the input is starts with HTTPS and has no WWW
String preStandardizeUrl(String url) {
  var firstDotIndex = url.indexOf('.');
  if (!(firstDotIndex >= 0 && firstDotIndex != url.length - 1)) {
    throw UnsupportedURLError();
  }
  if (url.toLowerCase().indexOf('http://') != 0 &&
      url.toLowerCase().indexOf('https://') != 0) {
    url = 'https://$url';
  }
  var uri = Uri.tryParse(url);
  var trailingSlash =
      ((uri?.path.endsWith('/') ?? false) ||
          ((uri?.path.isEmpty ?? false) && url.endsWith('/'))) &&
      (uri?.queryParameters.isEmpty ?? false);

  // Only normalize duplicate slashes in the scheme/host/path portion; leave the
  // query string and fragment untouched so any slashes they contain (e.g. a URL
  // passed as a query parameter) aren't mangled.
  var splitIndex = url.length;
  var queryStart = url.indexOf('?');
  if (queryStart >= 0 && queryStart < splitIndex) {
    splitIndex = queryStart;
  }
  var fragmentStart = url.indexOf('#');
  if (fragmentStart >= 0 && fragmentStart < splitIndex) {
    splitIndex = fragmentStart;
  }
  var mainPart = url.substring(0, splitIndex);
  var rest = url.substring(splitIndex);
  mainPart = mainPart
      .split('/')
      .where((e) => e.isNotEmpty)
      .join('/')
      .replaceFirst(':/', '://');
  url = mainPart + (trailingSlash ? '/' : '') + rest;
  return url;
}

List<String> getLinksFromParsedHTML(
  Document dom,
  RegExp hrefPattern,
  String prependToLinks,
) => dom
    .querySelectorAll('a')
    .where((element) {
      if (element.attributes['href'] == null) return false;
      return hrefPattern.hasMatch(element.attributes['href']!);
    })
    .map((e) => '$prependToLinks${e.attributes['href']!}')
    .toList();

Map<String, dynamic> getDefaultValuesFromFormItems(
  List<List<GeneratedFormItem>> items,
) {
  return Map.fromEntries(
    items
        .map((row) => row.map((el) => MapEntry(el.key, el.defaultValue ?? '')))
        .reduce((value, element) => [...value, ...element]),
  );
}

List<MapEntry<String, String>> getApkUrlsFromUrls(List<String> urls) =>
    urls.map((e) {
      var segments = e.split('/').where((el) => el.trim().isNotEmpty);
      var apkSegs = segments.where((s) => s.toLowerCase().endsWith('.apk'));
      return MapEntry(apkSegs.isNotEmpty ? apkSegs.last : segments.last, e);
    }).toList();

Future<List<MapEntry<String, String>>> filterApksByArch(
  List<MapEntry<String, String>> apkUrls,
) async {
  if (apkUrls.length > 1) {
    var abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
    for (var abi in abis) {
      var urls2 = apkUrls
          .where(
            (element) =>
                RegExp('.*$abi.*', caseSensitive: false).hasMatch(element.key),
          )
          .toList();
      if (urls2.isNotEmpty && urls2.length < apkUrls.length) {
        apkUrls = urls2;
        break;
      }
    }
  }
  return apkUrls;
}

String getSourceRegex(List<String> hosts) {
  return '(${hosts.join('|').replaceAll('.', '\\.')})';
}

HttpClient createHttpClient(bool insecure) {
  final client = HttpClient();
  client.connectionTimeout = Duration(seconds: _connectionTimeoutSeconds);
  if (insecure) {
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
  }
  return client;
}

Future<MapEntry<Uri, MapEntry<HttpClient, HttpClientResponse>>>
sourceRequestStreamResponse(
  String method,
  String url,
  Map<String, String>? requestHeaders,
  Map<String, dynamic> additionalSettings, {
  bool followRedirects = true,
  Object? postBody,
}) async {
  var currentUrl = Uri.parse(url);
  var redirectCount = 0;
  List<Cookie> cookies = [];
  HttpClient? httpClient;
  while (redirectCount < _maxRedirects) {
    httpClient = createHttpClient(additionalSettings['allowInsecure'] == true);
    var request = await httpClient.openUrl(method, currentUrl);
    if (requestHeaders != null) {
      requestHeaders.forEach((key, value) {
        request.headers.set(key, value);
      });
    }
    request.cookies.addAll(cookies);
    request.followRedirects = false;
    if (postBody != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(postBody));
    }
    final response = await request.close();

    if (followRedirects &&
        (response.statusCode >= 300 && response.statusCode <= 399)) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location != null) {
        currentUrl = Uri.parse(ensureAbsoluteUrl(location, currentUrl));
        redirectCount++;
        cookies = response.cookies;
        httpClient.close();
        httpClient = null;
        continue;
      }
    }

    return MapEntry(currentUrl, MapEntry(httpClient, response));
  }
  httpClient?.close();
  throw ObtainiumError(tr('tooManyRedirects'));
}

Future<Response> httpClientResponseStreamToFinalResponse(
  HttpClient httpClient,
  String method,
  String url,
  HttpClientResponse response,
) async {
  try {
    final bytes = (await response.fold<BytesBuilder>(
      BytesBuilder(),
      (b, d) => b..add(d),
    )).toBytes();

    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });

    return http.Response.bytes(
      bytes,
      response.statusCode,
      headers: headers,
      request: http.Request(method, Uri.parse(url)),
    );
  } finally {
    httpClient.close();
  }
}

/// Lightweight HTTP helper mixin for classes that need request/response
/// utilities without [AppSource]'s config-aware source-request wrapping.
/// [AppSource] itself uses this mixin for [getRequestHeaders].
mixin HttpClientMixin {
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    return null;
  }
}

abstract class AppSource with HttpClientMixin {
  List<String> hosts = [];
  bool hostChanged = false;
  bool hostIdenticalDespiteAnyChange = false;
  late String name;
  bool enforceTrackOnly = false;
  bool changeLogIfAnyIsMarkDown = true;
  bool appIdInferIsOptional = false;
  bool allowSubDomains = false;
  bool naiveStandardVersionDetection = false;
  bool allowOverride = true;
  bool neverAutoSelect = false;
  bool showReleaseDateAsVersionToggle = false;
  bool versionDetectionDisallowed = false;
  List<String> excludeCommonSettingKeys = [];
  bool urlsAlwaysHaveExtension = false;
  bool allowIncludeZips = false;
  bool allowIncludeTarballs = false;

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

  App endOfGetAppChanges(App app) {
    return app;
  }

  Future<Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    var sp = SettingsProvider();
    await sp.initializeSettings();
    var additionalSettingsPlusSourceConfig = {
      ...additionalSettings,
      ...(await getSourceConfigValues(additionalSettings, sp)),
    };
    url = await generalReqPrefetchModifier(
      url,
      additionalSettingsPlusSourceConfig,
    );
    var method = postBody == null ? 'GET' : 'POST';
    var requestHeaders = await getRequestHeaders(
      additionalSettingsPlusSourceConfig,
      url,
    );
    var streamedResponseUrlWithResponseAndClient =
        await sourceRequestStreamResponse(
          method,
          url,
          requestHeaders,
          additionalSettingsPlusSourceConfig,
          followRedirects: followRedirects,
          postBody: postBody,
        );
    return await httpClientResponseStreamToFinalResponse(
      streamedResponseUrlWithResponseAndClient.value.key,
      method,
      streamedResponseUrlWithResponseAndClient.key.toString(),
      streamedResponseUrlWithResponseAndClient.value.value,
    );
  }

  void runOnAddAppInputChange(String inputUrl) {
    //
  }

  /// File extensions Obtainium recognizes as installable Android package
  /// containers. Centralized here so every source agrees on what counts as an
  /// "APK"; previously each source defined this inconsistently (some only
  /// accepted `.apk` and silently missed `.xapk`/`.apkm`/`.apks` releases).
  static const List<String> apkContainerExtensions = [
    '.apk',
    '.xapk',
    '.apkm',
    '.apks',
  ];

  static const List<String> archiveExtensions = ['.zip'];

  static const List<String> tarballExtensions = [
    '.tar.gz',
    '.tgz',
    '.tar.bz2',
    '.tar.xz',
  ];

  /// Whether [name] (a filename or URL) refers to an APK-type container that
  /// Obtainium can install. Optionally also accept generic zip archives and
  /// tarballs (some sources bundle split APKs that way).
  static bool isApkOrContainerFile(
    String name, {
    bool includeArchives = false,
    bool includeTarballs = false,
  }) {
    final lower = name.toLowerCase();
    bool endsWithAny(List<String> exts) => exts.any(lower.endsWith);
    return endsWithAny(apkContainerExtensions) ||
        (includeArchives && endsWithAny(archiveExtensions)) ||
        (includeTarballs && endsWithAny(tarballExtensions));
  }

  /// A convenience for the common standardize-by-regex pattern: build a regex
  /// from the source's [hosts] plus the given subdomain prefix and path, match
  /// against [url], and return the match or throw [InvalidURLError].  Many
  /// sources (16+) repeat this block verbatim; subclasses can call this
  /// helper instead.
  String standardizeUrlWithRegex(
    String url, {
    required String subdomainPrefix,
    required String pathPattern,
  }) {
    final re = RegExp(
      '^https?://$subdomainPrefix${getSourceRegex(hosts)}$pathPattern',
      caseSensitive: false,
    );
    final match = re.firstMatch(url);
    if (match == null) throw InvalidURLError(name);
    return match.group(0)!;
  }

  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    throw NotImplementedError();
  }

  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) {
    throw NotImplementedError();
  }

  // Different Sources may need different kinds of additional data for Apps
  List<List<GeneratedFormItem>> additionalSourceAppSpecificSettingFormItems =
      [];

  // Some additional data may be needed for Apps regardless of Source
  List<List<GeneratedFormItem>>
  additionalAppSpecificSourceAgnosticSettingFormItemsNeverUseDirectly = [
    [GeneratedFormSwitch('trackOnly', label: tr('trackOnly'))],
    [
      GeneratedFormTextField(
        'versionExtractionRegEx',
        label: tr('trimVersionString'),
        required: false,
        additionalValidators: [(value) => regExValidator(value)],
      ),
    ],
    [
      GeneratedFormTextField(
        'matchGroupToUse',
        label: tr('matchGroupToUseForX', args: [tr('trimVersionString')]),
        required: false,
        hint: '\$0',
      ),
    ],
    [
      GeneratedFormSwitch(
        'versionDetection',
        label: tr('versionDetectionExplanation'),
        defaultValue: true,
      ),
    ],
    [
      GeneratedFormSwitch(
        'useVersionCodeAsOSVersion',
        label: tr('useVersionCodeAsOSVersion'),
        defaultValue: false,
      ),
    ],
    [
      GeneratedFormTextField(
        'apkFilterRegEx',
        label: tr('filterAPKsByRegEx'),
        required: false,
        additionalValidators: [
          (value) {
            return regExValidator(value);
          },
        ],
      ),
    ],
    [
      GeneratedFormSwitch(
        'invertAPKFilter',
        label: '${tr('invertRegEx')} (${tr('filterAPKsByRegEx')})',
        defaultValue: false,
      ),
    ],
    [
      GeneratedFormSwitch(
        'autoApkFilterByArch',
        label: tr('autoApkFilterByArch'),
        defaultValue: true,
      ),
    ],
    [GeneratedFormTextField('appName', label: tr('appName'), required: false)],
    [GeneratedFormTextField('appAuthor', label: tr('author'), required: false)],
    [
      GeneratedFormSwitch(
        'shizukuPretendToBeGooglePlay',
        label: tr('shizukuPretendToBeGooglePlay'),
        defaultValue: false,
      ),
    ],
    [
      GeneratedFormSwitch(
        'allowInsecure',
        label: tr('allowInsecure'),
        defaultValue: false,
      ),
    ],
    [
      GeneratedFormSwitch(
        'exemptFromBackgroundUpdates',
        label: tr('exemptFromBackgroundUpdates'),
      ),
    ],
    [
      GeneratedFormSwitch(
        'skipUpdateNotifications',
        label: tr('skipUpdateNotifications'),
      ),
    ],
    [GeneratedFormTextField('about', label: tr('about'), required: false)],
    [
      GeneratedFormSwitch(
        'refreshBeforeDownload',
        label: tr('refreshBeforeDownload'),
      ),
    ],
  ];

  // Previous 2 variables combined into one at runtime for convenient usage + additional processing
  List<List<GeneratedFormItem>> get combinedAppSpecificSettingFormItems {
    var agnosticItems = cloneFormItems(
      additionalAppSpecificSourceAgnosticSettingFormItemsNeverUseDirectly,
    );

    final versionDetectionIdx = agnosticItems.indexWhere(
      (row) => row.any((item) => item.key == 'versionDetection'),
    );
    if (showReleaseDateAsVersionToggle &&
        versionDetectionIdx >= 0 &&
        !agnosticItems.any(
          (row) => row.any((item) => item.key == 'releaseDateAsVersion'),
        )) {
      agnosticItems.insert(versionDetectionIdx + 1, [
        GeneratedFormSwitch(
          'releaseDateAsVersion',
          label: '${tr('releaseDateAsVersion')} (${tr('pseudoVersion')})',
          defaultValue: false,
        ),
      ]);
    }

    agnosticItems = agnosticItems
        .map(
          (e) => e
              .where((ee) => !excludeCommonSettingKeys.contains(ee.key))
              .toList(),
        )
        .where((e) => e.isNotEmpty)
        .toList();

    var moreConditionalItems = <List<GeneratedFormItem>>[];
    if (allowIncludeZips) {
      moreConditionalItems.addAll([
        [
          GeneratedFormSwitch(
            'includeZips',
            label: tr('includeZips'),
            defaultValue: false,
          ),
        ],
        [
          GeneratedFormTextField(
            'zippedApkFilterRegEx',
            label: tr('zippedApkFilterRegEx'),
            required: false,
            additionalValidators: [
              (value) {
                return regExValidator(value);
              },
            ],
          ),
        ],
      ]);
    }

    if (allowIncludeTarballs) {
      moreConditionalItems.addAll([
        [
          GeneratedFormSwitch(
            'includeTarballs',
            label: tr('includeTarballs'),
            defaultValue: false,
          ),
        ],
        [
          GeneratedFormTextField(
            'tarballedApkFilterRegEx',
            label: tr('tarballedApkFilterRegEx'),
            required: false,
            additionalValidators: [
              (value) {
                return regExValidator(value);
              },
            ],
          ),
        ],
      ]);
    }

    if (versionDetectionDisallowed) {
      for (var item in agnosticItems.expand((row) => row)) {
        if (item.key == 'versionDetection' ||
            item.key == 'useVersionCodeAsOSVersion') {
          (item as GeneratedFormSwitch).disabled = true;
          item.defaultValue = false;
        }
      }
    }

    return [
      // Clone so callers (e.g. the add-app form pre-filling default values)
      // can't mutate the source-owned items. Sources are now cached/shared, so
      // an in-place edit here would otherwise leak across apps.
      ...cloneFormItems(additionalSourceAppSpecificSettingFormItems),
      ...agnosticItems,
      ...moreConditionalItems,
    ];
  }

  // Cheap, cached emptiness check for [combinedAppSpecificSettingFormItems],
  // used in hot build paths (e.g. the app detail page) to avoid cloning the
  // entire form-item tree just to test isNotEmpty. Emptiness is invariant for a
  // given source instance, so caching the boolean is safe.
  bool? _hasAppSpecificSettingsCache;
  bool get hasAppSpecificSettings => _hasAppSpecificSettingsCache ??=
      combinedAppSpecificSettingFormItems.isNotEmpty;

  // Flattened, read-only view of [combinedAppSpecificSettingFormItems],
  // memoized so read-only callers (notably the per-app JSON migration at load,
  // which runs for every stored app) don't re-clone the whole form-item tree
  // each time. Callers MUST treat these as read-only - the list is shared.
  List<GeneratedFormItem>? _flatCombinedFormItemsCache;
  List<GeneratedFormItem> get flatCombinedFormItemsReadOnly =>
      _flatCombinedFormItemsCache ??= combinedAppSpecificSettingFormItems
          .expand((row) => row)
          .toList();

  // Some Sources may have additional settings at the Source level (not specific to Apps) - these use SettingsProvider
  // If the source has been overridden, we expect the user to define one-time values as additional settings - don't use the stored values
  List<GeneratedFormItem> sourceConfigSettingFormItems = [];
  Future<Map<String, String>> getSourceConfigValues(
    Map<String, dynamic> additionalSettings,
    SettingsProvider settingsProvider,
  ) async {
    Map<String, String> results = {};
    for (var e in sourceConfigSettingFormItems) {
      var val = hostChanged && !hostIdenticalDespiteAnyChange
          ? additionalSettings[e.key]
          : additionalSettings[e.key] ??
                (e.runtimeType == GeneratedFormSwitch
                    ? settingsProvider.getSettingBool(e.key).toString()
                    : settingsProvider.getSettingString(e.key));
      if (val != null) {
        if (e.runtimeType == GeneratedFormSwitch) {
          val = val.toString();
        }
        results[e.key] = val;
      }
    }
    return results;
  }

  String? changeLogPageFromStandardUrl(String standardUrl) {
    return null;
  }

  Future<String?> getSourceNote() async {
    return null;
  }

  Future<String> assetUrlPrefetchModifier(
    String assetUrl,
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    return assetUrl;
  }

  Future<String> generalReqPrefetchModifier(
    String reqUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    return reqUrl;
  }

  bool canSearch = false;
  bool includeAdditionalOptsInMainSearch = false;
  List<GeneratedFormItem> searchQuerySettingFormItems = [];
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) {
    throw NotImplementedError();
  }

  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    return null;
  }
}

ObtainiumError getObtainiumHttpError(Response res) {
  return ObtainiumError(
    (res.reasonPhrase != null && res.reasonPhrase!.isNotEmpty)
        ? res.reasonPhrase!
        : tr('errorWithHttpStatusCode', args: [res.statusCode.toString()]),
  );
}

abstract class MassAppUrlSource {
  late String name;
  late List<String> requiredArgs;
  Future<Map<String, List<String>>> getUrlsWithDescriptions(List<String> args);
}

String? regExValidator(String? value) {
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

String? intValidator(String? value, {bool positive = false}) {
  if (value == null) {
    return tr('invalidInput');
  }
  var num = int.tryParse(value);
  if (num == null) {
    return tr('invalidInput');
  }
  if (positive && num <= 0) {
    return tr('invalidInput');
  }
  return null;
}

bool isTempId(App app) {
  return RegExp('^[0-9]+\$').hasMatch(app.id);
}

String? replaceMatchGroupsInString(RegExpMatch match, String matchGroupString) {
  if (RegExp('^\\d+\$').hasMatch(matchGroupString)) {
    matchGroupString = '\$$matchGroupString';
  }
  // Regular expression to match numbers in the input string
  final numberRegex = RegExp(r'\$\d+');
  // Extract all numbers from the input string
  final numbers = numberRegex.allMatches(matchGroupString);
  if (numbers.isEmpty) {
    // If no numbers found, return the original string
    return null;
  }
  // Replace numbers with corresponding match groups
  var outputString = matchGroupString;
  for (final numberMatch in numbers) {
    final number = numberMatch.group(0)!;
    final matchGroup = match.group(int.parse(number.substring(1))) ?? '';
    // Check if the number is preceded by a single backslash
    final isEscaped = outputString.contains('\\$number');
    // Replace the number with the corresponding match group
    if (!isEscaped) {
      outputString = outputString.replaceAll(number, matchGroup);
    } else {
      outputString = outputString.replaceAll('\\$number', number);
    }
  }
  return outputString;
}

String? extractVersion(
  String? versionExtractionRegEx,
  String? matchGroupString,
  String stringToCheck,
) {
  if (versionExtractionRegEx?.isNotEmpty == true) {
    String? version = stringToCheck;
    var match = RegExp(versionExtractionRegEx!).allMatches(version);
    if (match.isEmpty) {
      throw NoVersionError();
    }
    matchGroupString = matchGroupString?.trim() ?? '';
    if (matchGroupString.isEmpty) {
      matchGroupString = "0";
    }
    version = replaceMatchGroupsInString(match.last, matchGroupString);
    if (version?.isNotEmpty != true) {
      throw NoVersionError();
    }
    return version!;
  } else {
    return null;
  }
}

List<MapEntry<String, String>> filterApks(
  List<MapEntry<String, String>> apkUrls,
  String? apkFilterRegEx,
  bool? invert,
) {
  if (apkFilterRegEx?.isNotEmpty == true) {
    var reg = RegExp(apkFilterRegEx!);
    apkUrls = apkUrls.where((element) {
      var hasMatch = reg.hasMatch(element.key);
      return invert == true ? !hasMatch : hasMatch;
    }).toList();
  }
  return apkUrls;
}

/// Whether the current locale is English.  Use sparingly — this exists because
/// easy\_localization doesn't expose a public global locale without a context,
/// and callers (list formatting, source labels) often run outside a widget tree.
/// The comparison `tr('and') == 'and'` relies on the fact that English (and
/// untranslated en-fallback keys) return the key unchanged, while every other
/// locale returns a translated word.
bool isEnglish() => tr('and') == 'and';
String lowerCaseIfEnglish(String str) => isEnglish() ? str.toLowerCase() : str;

bool isVersionPseudo(App app) =>
    app.additionalSettings['trackOnly'] == true ||
    (app.installedVersion != null &&
        app.additionalSettings['versionDetection'] != true);

class SourceProvider {
  static final SourceProvider _instance = SourceProvider._();
  factory SourceProvider() => _instance;
  SourceProvider._();

  // Builds a fresh set of source instances. Adding a source here makes it
  // available via the service. Kept private so callers go through [sources]
  // (cached) or, when per-call mutation is needed, [_buildSources] directly.
  static List<AppSource> _buildSources() => [
    GitHub(),
    GitLab(),
    Codeberg(),
    FDroid(),
    FDroidRepo(),
    IzzyOnDroid(),
    SourceHut(),
    APKPure(),
    Aptoide(),
    Uptodown(),
    ItchIO(),
    HuaweiAppGallery(),
    Tencent(),
    VivoAppStore(),
    RuStore(),
    Apk4Free(),
    Farsroid(),
    CoolApk(),
    LiteAPKs(),
    Jenkins(),
    APKMirror(),
    APKCombo(),
    RockMods(),
    TelegramApp(),
    NeutronCode(),
    DirectAPKLink(),
    HTML(), // This should ALWAYS be the last option as they are tried in order
  ];

  // Each source instance is immutable after construction (fields are only set
  // in the constructor), so we can safely cache one shared, read-only set and
  // reuse it across the many SourceProvider() throwaways created at runtime.
  // The only path that mutates a source (the [overrideSource] branch in
  // [getSource]) builds its own fresh instances so this cache stays pristine.
  static List<AppSource>? _cachedSources;
  List<AppSource> get sources => _cachedSources ??= _buildSources();

  // Add more mass url source classes here so they are available via the service
  List<MassAppUrlSource> massUrlSources = [GitHubStars()];

  AppSource getSource(String url, {String? overrideSource}) {
    url = preStandardizeUrl(url);
    if (overrideSource != null) {
      // The override path mutates the chosen source's host config, so build a
      // throwaway instance here rather than touching the shared cache.
      var srcs = _buildSources().where(
        (e) => e.runtimeType.toString() == overrideSource,
      );
      if (srcs.isEmpty) {
        throw UnsupportedURLError();
      }
      var res = srcs.first;
      var originalHosts = res.hosts;
      var newHost = Uri.parse(url).host;
      res.hosts = [newHost];
      res.hostChanged = true;
      if (originalHosts.contains(newHost)) {
        res.hostIdenticalDespiteAnyChange = true;
      }
      return res;
    }
    // The non-override path is read-only, so reuse the cached source set.
    final allSources = sources;
    AppSource? source;
    for (var s in allSources.where((element) => element.hosts.isNotEmpty)) {
      try {
        if (RegExp(
          '^${s.allowSubDomains ? '([^\\.]+\\.)*' : '(www\\.)?'}(${getSourceRegex(s.hosts)})\$',
        ).hasMatch(Uri.parse(url).host)) {
          source = s;
          break;
        }
      } catch (e) {
        LogsProvider().add(
          'Source host-match error for ${s.runtimeType}: ${e.toString()}',
        );
      }
    }
    if (source == null) {
      for (var s in allSources.where(
        (element) => element.hosts.isEmpty && !element.neverAutoSelect,
      )) {
        try {
          s.sourceSpecificStandardizeURL(url, forSelection: true);
          source = s;
          break;
        } catch (e) {
          LogsProvider().add(
            'Source standardize error for ${s.runtimeType}: ${e.toString()}',
          );
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
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) => (standardUrl + additionalSettings.toString()).hashCode.toString();

  Future<App> getApp(
    AppSource source,
    String url,
    Map<String, dynamic> additionalSettings, {
    App? currentApp,
    bool trackOnlyOverride = false,
    bool sourceIsOverriden = false,
    bool inferAppIdIfOptional = false,
  }) async {
    if (trackOnlyOverride || source.enforceTrackOnly) {
      additionalSettings['trackOnly'] = true;
    }
    var trackOnly = additionalSettings['trackOnly'] == true;
    String standardUrl = source.standardizeUrl(url);
    APKDetails apk = await source.getLatestAPKDetails(
      standardUrl,
      additionalSettings,
    );

    if (source.runtimeType !=
            HTML().runtimeType && // Some sources do it separately
        source.runtimeType != SourceForge().runtimeType) {
      String? extractedVersion = extractVersion(
        additionalSettings['versionExtractionRegEx'] as String?,
        additionalSettings['matchGroupToUse'] as String?,
        apk.version,
      );
      if (extractedVersion != null) {
        apk.version = extractedVersion;
      }
    }

    if (additionalSettings['releaseDateAsVersion'] == true &&
        apk.releaseDate != null) {
      apk.version = apk.releaseDate!.microsecondsSinceEpoch.toString();
    }
    apk.apkUrls = filterApks(
      apk.apkUrls,
      additionalSettings['apkFilterRegEx'],
      additionalSettings['invertAPKFilter'],
    );
    if (apk.apkUrls.isEmpty && !trackOnly) {
      throw NoAPKError();
    }
    if (additionalSettings['autoApkFilterByArch'] == true) {
      apk.apkUrls = await filterApksByArch(apk.apkUrls);
    }
    var name = currentApp != null ? currentApp.name.trim() : '';
    name = name.isNotEmpty ? name : apk.names.name;
    App finalApp = App(
      currentApp?.id ??
          ((additionalSettings['appId'] != null)
              ? additionalSettings['appId']
              : null) ??
          (!trackOnly &&
                  (!source.appIdInferIsOptional ||
                      (source.appIdInferIsOptional && inferAppIdIfOptional))
              ? await source.tryInferringAppId(
                  standardUrl,
                  additionalSettings: additionalSettings,
                )
              : null) ??
          generateTempID(standardUrl, additionalSettings),
      standardUrl,
      apk.names.author,
      name,
      currentApp?.installedVersion,
      apk.version,
      apk.apkUrls,
      apk.apkUrls.length - 1 >= 0 ? apk.apkUrls.length - 1 : 0,
      additionalSettings,
      DateTime.now(),
      currentApp?.pinned ?? false,
      categories: currentApp?.categories ?? const [],
      releaseDate: apk.releaseDate,
      changeLog: apk.changeLog,
      overrideSource: sourceIsOverriden
          ? source.runtimeType.toString()
          : currentApp?.overrideSource,
      allowIdChange:
          currentApp?.allowIdChange ??
          trackOnly ||
              (source.appIdInferIsOptional &&
                  inferAppIdIfOptional), // Optional ID inferring may be incorrect - allow correction on first install
      otherAssetUrls: apk.allAssetUrls
          .where((a) => apk.apkUrls.indexWhere((p) => a.key == p.key) < 0)
          .toList(),
    );
    return source.endOfGetAppChanges(finalApp);
  }

  // Returns errors in [results, errors] instead of throwing them
  Future<List<dynamic>> getAppsByURLNaive(
    List<String> urls, {
    Set<String> alreadyAddedUrls = const {},
    AppSource? sourceOverride,
  }) async {
    List<App> apps = [];
    Map<String, dynamic> errors = {};
    const concurrency = 4;
    for (var i = 0; i < urls.length; i += concurrency) {
      final end = i + concurrency > urls.length ? urls.length : i + concurrency;
      final batch = urls.sublist(i, end);
      final results = await Future.wait(
        batch.map((url) async {
          try {
            if (alreadyAddedUrls.contains(url)) {
              throw ObtainiumError(tr('appAlreadyAdded'));
            }
            var source = sourceOverride ?? getSource(url);
            return await getApp(
              source,
              url,
              sourceIsOverriden: sourceOverride != null,
              getDefaultValuesFromFormItems(
                source.combinedAppSpecificSettingFormItems,
              ),
            );
          } catch (e) {
            return e;
          }
        }),
      );
      for (var j = 0; j < batch.length; j++) {
        final result = results[j];
        if (result is App) {
          apps.add(result);
        } else {
          errors[batch[j]] = result;
        }
      }
    }
    return [apps, errors];
  }
}
