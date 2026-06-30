// Defines App sources and provides functions used to interact with them
//
// AppSource is an abstract class with a concrete implementation for each source

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:html/dom.dart';
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
  String author;
  String name;

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

/// Converts a list of [MapEntry] pairs into a 2D list of strings for JSON encoding.
List<List<String>> stringMapListTo2DList(
  List<MapEntry<String, String>> mapList,
) => mapList.map((e) => [e.key, e.value]).toList();

/// Converts a 2D list (decoded from JSON) back into a list of [MapEntry] pairs.
List<MapEntry<String, String>> assumed2DlistToStringMapList(
  List<dynamic> arr,
) => arr.map((e) => MapEntry(e[0] as String, e[1] as String)).toList();

String ensureAbsoluteUrl(String ambiguousUrl, Uri referenceAbsoluteUrl) {
  try {
    ambiguousUrl = ambiguousUrl.trim();
    if (Uri.parse(ambiguousUrl).isAbsolute) {
      return ambiguousUrl;
    }
  } on FormatException {
    // Non-parsable URL, fall through to resolve logic below
  }
  return referenceAbsoluteUrl.resolve(ambiguousUrl).toString();
}

/// Gating version for one-time legacy app-JSON migrations. Apps whose stored
/// JSON carries this version skip the legacy conversions; default-settings
/// reconciliation always runs regardless.
const int currentAppJSONCompatVersion = 1;
const _maxRedirects = 10;
const _connectionTimeoutSeconds = 30;
const _defaultMatchGroup = '0';

Map<String, dynamic> _migrateAppToHTML(
  Map<String, dynamic> json,
  Map<String, dynamic> additionalSettings, {
  required String newUrl,
  Map<String, dynamic>? overrides,
}) {
  json['url'] = newUrl;
  var replacement = getDefaultValuesFromFormItems(
    HTML().combinedAppSpecificSettingFormItems,
  );
  for (var s in replacement.keys) {
    if (additionalSettings.containsKey(s)) {
      replacement[s] = additionalSettings[s];
    }
  }
  if (overrides != null) replacement.addAll(overrides);
  return replacement;
}

/// Migrates old-style `additionalData` array (list of strings) to the
/// newer `additionalSettings` map, keyed by form-item key.
void _migrateAdditionalDataToSettings(
  Map<String, dynamic> json,
  Map<String, dynamic> additionalSettings,
  List<GeneratedFormItem> formItems,
) {
  if (json['additionalData'] == null) return;
  final decoded = jsonDecode(json['additionalData']);
  if (decoded is! List) return;
  List<String> temp = List<String>.from(decoded);
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
      json['noVersionDetection'] == 'true' || json['noVersionDetection'] == true;
}

/// Converts legacy booleans `noVersionDetection` / `releaseDateAsVersion`
/// to the current `versionDetection` string dropdown and back.
void _migrateVersionDetectionFormat(Map<String, dynamic> additionalSettings) {
  if (additionalSettings['noVersionDetection'] == true) {
    additionalSettings['versionDetection'] = 'noVersionDetection';
    if (additionalSettings['releaseDateAsVersion'] == true) {
      additionalSettings['versionDetection'] = 'releaseDateAsVersion';
      additionalSettings.remove('releaseDateAsVersion');
    }
    additionalSettings.remove('noVersionDetection');
    additionalSettings.remove('releaseDateAsVersion');
  }
  if (additionalSettings['versionDetection'] == 'standardVersionDetection') {
    additionalSettings['versionDetection'] = true;
  } else if (additionalSettings['versionDetection'] == 'noVersionDetection') {
    additionalSettings['versionDetection'] = false;
  } else if (additionalSettings['versionDetection'] == 'releaseDateAsVersion') {
    additionalSettings['versionDetection'] = false;
    additionalSettings['releaseDateAsVersion'] = true;
  }
}

/// Converts legacy `supportFixedAPKURL` bool to `defaultPseudoVersioningMethod`.
void _migratePseudoVersioningMethod(
  Map<String, dynamic> originalAdditionalSettings,
  Map<String, dynamic> additionalSettings,
) {
  if (originalAdditionalSettings['supportFixedAPKURL'] == true) {
    additionalSettings['defaultPseudoVersioningMethod'] = 'partialAPKHash';
  } else if (originalAdditionalSettings['supportFixedAPKURL'] == false) {
    additionalSettings['defaultPseudoVersioningMethod'] = 'APKLinkHash';
  }
}

/// Ensures every known form item's value is coerced to its declared type.
void _coerceAdditionalSettingTypes(
  Map<String, dynamic> additionalSettings,
  List<GeneratedFormItem> formItems,
) {
  for (var item in formItems) {
    if (additionalSettings[item.key] != null) {
      additionalSettings[item.key] = item.ensureType(
        additionalSettings[item.key],
      );
    }
  }
}

/// Normalises `apkUrls` to the current 2D-list JSON format.
void _migrateApkUrlsFormat(Map<String, dynamic> json) {
  if (json['apkUrls'] == null) return;
  var apkUrlJson = jsonDecode(json['apkUrls']);
  List<MapEntry<String, String>> apkUrls;
  try {
    apkUrls = getApkUrlsFromUrls(List<String>.from(apkUrlJson));
  } catch (e) {
    apkUrls = assumed2DlistToStringMapList(List<dynamic>.from(apkUrlJson));
  }
  json['apkUrls'] = jsonEncode(stringMapListTo2DList(apkUrls));
}

/// Applies HTML-source-specific one-time migrations: key renames,
/// intermediate-link format upgrade, and legacy-source → HTML conversions
/// (Steam, Signal, WhatsApp, VLC).
Map<String, dynamic> _migrateHtmlSpecificMigrations(
  Map<String, dynamic> json,
  Map<String, dynamic> originalAdditionalSettings,
  Map<String, dynamic> additionalSettings,
) {
  if (originalAdditionalSettings['sortByFileNamesNotLinks'] != null) {
    additionalSettings['sortByLastLinkSegment'] =
        originalAdditionalSettings['sortByFileNamesNotLinks'];
  }
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

  var legacySteamSourceApps = ['steam', 'steam-chat-app'];
  if (legacySteamSourceApps.contains(additionalSettings['app'] ?? '')) {
    additionalSettings = _migrateAppToHTML(
      json,
      additionalSettings,
      newUrl: '${json['url']}/mobile',
      overrides: {
        'customLinkFilterRegex':
            '/${additionalSettings['app']}-(([0-9]+\\.?){1,})\\.apk',
        'versionExtractionRegEx':
            '/${additionalSettings['app']}-(([0-9]+\\.?){1,})\\.apk',
        'matchGroupToUse': '\$1',
      },
    );
  }
  if (json['url'] == 'https://signal.org' &&
      json['id'] == 'org.thoughtcrime.securesms' &&
      json['author'] == 'Signal' &&
      json['name'] == 'Signal' &&
      json['overrideSource'] == null &&
      additionalSettings['trackOnly'] == false &&
      additionalSettings['versionExtractionRegEx'] == '' &&
      json['lastUpdateCheck'] != null) {
    additionalSettings = _migrateAppToHTML(
      json,
      additionalSettings,
      newUrl: 'https://updates.signal.org/android/latest.json',
      overrides: {'versionExtractionRegEx': r'\d+.\d+.\d+'},
    );
  }
  if (json['url'] == 'https://whatsapp.com' &&
      json['id'] == 'com.whatsapp' &&
      json['author'] == 'Meta' &&
      json['name'] == 'WhatsApp' &&
      json['overrideSource'] == null &&
      additionalSettings['trackOnly'] == false &&
      additionalSettings['versionExtractionRegEx'] == '' &&
      json['lastUpdateCheck'] != null) {
    additionalSettings = _migrateAppToHTML(
      json,
      additionalSettings,
      newUrl: 'https://whatsapp.com/android',
      overrides: {'refreshBeforeDownload': true},
    );
  }
  if (json['url'] == 'https://videolan.org' &&
      json['id'] == 'org.videolan.vlc' &&
      json['author'] == 'VideoLAN' &&
      json['name'] == 'VLC' &&
      json['overrideSource'] == null &&
      additionalSettings['trackOnly'] == false &&
      additionalSettings['versionExtractionRegEx'] == '' &&
      json['lastUpdateCheck'] != null) {
    additionalSettings = _migrateAppToHTML(
      json,
      additionalSettings,
      newUrl: 'https://www.videolan.org/vlc/download-android.html',
      overrides: {
        'refreshBeforeDownload': true,
        'intermediateLink': <Map<String, dynamic>>[
          {
            'customLinkFilterRegex': 'APK',
            'filterByLinkText': true,
            'skipSort': false,
            'reverseSort': false,
            'sortByLastLinkSegment': false,
          },
          {
            'customLinkFilterRegex': r'arm64-v8a\.apk$',
            'filterByLinkText': false,
            'skipSort': false,
            'reverseSort': false,
            'sortByLastLinkSegment': false,
          },
        ],
        'versionExtractionRegEx': '/vlc-android/([^/]+)/',
        'matchGroupToUse': '1',
      },
    );
  }
  return additionalSettings;
}

/// Migrates F-Droid cloudflare URLs to override-source and auto-detects
/// third-party F-Droid repo URLs.
void _migrateFdroidOverrides(Map<String, dynamic> json) {
  var overrideSourceWasUndefined = !json.keys.contains('overrideSource');
  if ((json['url'] as String).startsWith('https://cloudflare.f-droid.org')) {
    json['overrideSource'] = FDroid().sourceIdentifier;
  } else if (overrideSourceWasUndefined) {
    RegExpMatch? match = RegExp(
      '^https?://.+/fdroid/([^/]+(/|\\?)|[^/]+\$)',
    ).firstMatch(json['url'] as String);
    if (match != null) {
      json['overrideSource'] = FDroidRepo().sourceIdentifier;
    }
  }
}

/// Applies any legacy JSON transformations so the stored [json] matches the
/// current schema. Default-setting reconciliation always runs; one-time
/// migrations (URL rewrites, format conversions) are gated by compatVersion.
Map<String, dynamic> appJSONCompatibilityModifiers(Map<String, dynamic> json) {
  final isCurrentCompat = json['compatVersion'] == currentAppJSONCompatVersion;
  var source = SourceProvider().getSource(
    json['url'],
    overrideSource: json['overrideSource'],
  );
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

  _migrateAdditionalDataToSettings(json, additionalSettings, formItems);
  _migrateVersionDetectionFormat(additionalSettings);
  _migratePseudoVersioningMethod(originalAdditionalSettings, additionalSettings);
  _coerceAdditionalSettingTypes(additionalSettings, formItems);

  int preferredApkIndex = json['preferredApkIndex'] == null
      ? 0
      : json['preferredApkIndex'] as int;
  if (preferredApkIndex < 0) {
    preferredApkIndex = 0;
  }
  json['preferredApkIndex'] = preferredApkIndex;
  _migrateApkUrlsFormat(json);

  if (additionalSettings['autoApkFilterByArch'] == null) {
    additionalSettings['autoApkFilterByArch'] = false;
  }
  if (additionalSettings['dontSortReleasesList'] == true) {
    additionalSettings['sortMethodChoice'] = 'none';
  }

  if (!isCurrentCompat && source is HTML) {
    additionalSettings = _migrateHtmlSpecificMigrations(
      json,
      originalAdditionalSettings,
      additionalSettings,
    );
  }

  json['additionalSettings'] = jsonEncode(additionalSettings);
  if (!isCurrentCompat) {
    _migrateFdroidOverrides(json);
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
    List<MapEntry<String, String>>.from(apkUrls),
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

/// Ensures the URL is well-formed and starts with HTTPS.
String preStandardizeUrl(String url) {
  var firstDotIndex = url.indexOf('.');
  if (!(firstDotIndex >= 0 && firstDotIndex != url.length - 1) &&
      !url.contains('[')) {
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

/// Extracts anchor hrefs from parsed HTML that match [hrefPattern], prepending a base URL.
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

/// Builds a flat map of default values from nested [GeneratedFormItem] rows.
Map<String, dynamic> getDefaultValuesFromFormItems(
  List<List<GeneratedFormItem>> items,
) {
  return Map.fromEntries(
    items
        .map((row) => row.map((el) => MapEntry(el.key, el.defaultValue ?? '')))
        .reduce((value, element) => [...value, ...element]),
  );
}

/// Parses a list of raw URLs into filename→URL [MapEntry] pairs, extracting APK filenames.
List<MapEntry<String, String>> getApkUrlsFromUrls(List<String> urls) =>
    urls.map((e) {
      var segments = e.split('/').where((el) => el.trim().isNotEmpty);
      var apkSegs = segments.where((s) => AppSource.isApkOrContainerFile(s));
      return MapEntry(apkSegs.isNotEmpty ? apkSegs.last : segments.last, e);
    }).toList();

/// Narrows a list of APK URLs to those matching the device's supported ABIs.
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

/// Builds a regex alternation pattern from a list of hostname strings, escaping dots.
String getSourceRegex(List<String> hosts) {
  return '(${hosts.join('|').replaceAll('.', '\\.')})';
}

/// Creates an [HttpClient] with a connection timeout, optionally accepting bad certificates.
HttpClient createHttpClient(bool insecure) {
  final client = HttpClient();
  client.connectionTimeout = Duration(seconds: _connectionTimeoutSeconds);
  if (insecure) {
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
  }
  return client;
}

/// Performs an HTTP request with redirect following, returning the final URL, client, and streamed response.
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
        (response.statusCode >= 301 && response.statusCode <= 308 &&
            response.statusCode != 304)) {
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

Future<http.Response> httpClientResponseStreamToFinalResponse(
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
  bool inferAppIdFromUrlPath = false;
  bool allowSubDomains = false;
  bool naiveStandardVersionDetection = false;
  bool allowOverride = true;
  bool neverAutoSelect = false;
  bool showReleaseDateAsVersionToggle = false;
  bool versionDetectionDisallowed = false;
  bool suppressStandardVersionExtraction = false;
  List<String> excludeCommonSettingKeys = [];
  bool urlsAlwaysHaveExtension = false;
  bool allowIncludeZips = false;
  bool allowIncludeTarballs = false;
  String get sourceIdentifier => runtimeType.toString();

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

  Future<http.Response> sourceRequest(
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

  /// Per-source additional form items (e.g. GitHub's sort method, HTML's version regex).
  List<List<GeneratedFormItem>> additionalSourceAppSpecificSettingFormItems =
      [];

  /// Some additional data may be needed for Apps regardless of Source
  final List<List<GeneratedFormItem>>
  _commonAppSettingFormItems = [
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

  /// Previous 2 variables combined into one at runtime for convenient usage + additional processing
  List<List<GeneratedFormItem>> get combinedAppSpecificSettingFormItems {
    var agnosticItems = cloneFormItems(
      _commonAppSettingFormItems,
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

  /// Cached emptiness check for [combinedAppSpecificSettingFormItems], used to
  /// avoid cloning the form-item tree just to test isNotEmpty.
  bool? _hasAppSpecificSettingsCache;
  bool get hasAppSpecificSettings => _hasAppSpecificSettingsCache ??=
      combinedAppSpecificSettingFormItems.isNotEmpty;

  /// Flattened, read-only view of [combinedAppSpecificSettingFormItems],
  /// memoized for callers that only need to enumerate keys without cloning.
  List<GeneratedFormItem>? _flatCombinedFormItemsCache;
  List<GeneratedFormItem> get flatCombinedFormItemsReadOnly =>
      _flatCombinedFormItemsCache ??= combinedAppSpecificSettingFormItems
          .expand((row) => row)
          .toList();

  /// Source-level additional settings (not specific to Apps) backed by [SettingsProvider].
  /// If the source has been overridden, per-app additional settings take precedence.
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
                (e is GeneratedFormSwitch
                    ? settingsProvider.getSettingBool(e.key).toString()
                    : settingsProvider.getSettingString(e.key));
      if (val != null) {
        if (e is GeneratedFormSwitch) {
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

  static String stripLastPathSegment(String url) {
    final uri = Uri.parse(url);
    return uri
        .replace(pathSegments:
            uri.pathSegments.sublist(0, uri.pathSegments.length - 1))
        .toString();
  }

  static Future<String?> tryInferAppIdFromLastPathSegment(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    return Uri.parse(standardUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull;
  }

  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    if (inferAppIdFromUrlPath) {
      return tryInferAppIdFromLastPathSegment(standardUrl);
    }
    return null;
  }
}

ObtainiumError getObtainiumHttpError(http.Response res) {
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

/// Returns true if the app's ID is a numeric placeholder (temporary ID) rather than a real package name.
bool isTempId(App app) {
  return RegExp('^[0-9]+\$').hasMatch(app.id);
}

/// Replaces `$N` references in a string with the corresponding regex match groups.
String? replaceMatchGroupsInString(RegExpMatch match, String matchGroupString) {
  if (RegExp('^\\d+\$').hasMatch(matchGroupString)) {
    matchGroupString = '\$$matchGroupString';
  }
  final numberRegex = RegExp(r'\$\d+');
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

/// Applies a version extraction regex to a string and returns the captured match group.
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
      matchGroupString = _defaultMatchGroup;
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

/// Filters APK URLs by a regex pattern on their filenames, optionally inverting the match.
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
/// Lowercases [str] only if the current locale is English, preserving case for other languages.
String lowerCaseIfEnglish(String str) => isEnglish() ? str.toLowerCase() : str;

/// Returns true when the app uses pseudo-versioning (track-only or disabled version detection).
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
    HTML(), // Must be the last entry — hostless sources are tried in order and HTML is the catch-all fallback
  ];

  /// Cached, read-only source list built lazily by [_buildSources].
  /// Because sources are immutable after construction, the cache is safe.
  static List<AppSource>? _cachedSources;
  List<AppSource> get sources => _cachedSources ??= _buildSources();

  /// Add mass URL source classes here so they are available via the service.
  List<MassAppUrlSource> massUrlSources = [GitHubStars()];

  AppSource getSource(String url, {String? overrideSource}) {
    url = preStandardizeUrl(url);
    if (overrideSource != null) {
      // The override path mutates the chosen source's host config, so build a
      // throwaway instance here rather than touching the shared cache.
      var srcs = _buildSources().where(
        (e) => e.sourceIdentifier == overrideSource,
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

  Future<String?> _resolveAppId(
    AppSource source,
    App? currentApp,
    Map<String, dynamic> additionalSettings,
    bool trackOnly,
    String standardUrl,
    bool inferAppIdIfOptional,
  ) async {
    return currentApp?.id ??
        (additionalSettings['appId'] as String?) ??
        (!trackOnly &&
                (!source.appIdInferIsOptional ||
                    (source.appIdInferIsOptional && inferAppIdIfOptional))
            ? await source.tryInferringAppId(
                standardUrl,
                additionalSettings: additionalSettings,
              )
            : null) ??
        generateTempID(standardUrl, additionalSettings);
  }

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

    if (!source.suppressStandardVersionExtraction) {
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
      await _resolveAppId(
            source,
            currentApp,
            additionalSettings,
            trackOnly,
            standardUrl,
            inferAppIdIfOptional,
          ) ??
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
          ? source.sourceIdentifier
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
