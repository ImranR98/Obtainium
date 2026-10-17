// Core app data models shared by providers, sources, and UI.

import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/models/typed_settings.dart';

// ------------------------------------------------------------------------
// AppNames
// ------------------------------------------------------------------------

class AppNames {
  final String author;
  final String name;

  const AppNames(this.author, this.name);

  AppNames copyWith({String? author, String? name}) {
    return AppNames(author ?? this.author, name ?? this.name);
  }
}

// ------------------------------------------------------------------------
// APKDetails
// ------------------------------------------------------------------------

class APKDetails {
  final String version;
  final List<MapEntry<String, String>> apkUrls;
  final AppNames names;
  final DateTime? releaseDate;
  final String? changeLog;
  final String? releaseUrl;
  final List<MapEntry<String, String>> allAssetUrls;

  /// Package name when the source can infer it (e.g. APKMirror's feed icon),
  /// so callers can resolve an app ID without a second request.
  final String? appId;

  /// Download size in bytes when the source can resolve it (e.g. APKMirror's
  /// release page) and the app has no direct APK URL to probe.
  final int? apkSizeBytes;

  final bool? isArchived;
  final int? newerReleasesFilteredOut;

  const APKDetails(
    this.version,
    this.apkUrls,
    this.names, {
    this.releaseDate,
    this.changeLog,
    this.releaseUrl,
    this.allAssetUrls = const [],
    this.appId,
    this.apkSizeBytes,
    this.isArchived,
    this.newerReleasesFilteredOut,
  });

  APKDetails copyWith({
    String? version,
    List<MapEntry<String, String>>? apkUrls,
    AppNames? names,
    Object? releaseDate = _sentinel,
    Object? changeLog = _sentinel,
    Object? releaseUrl = _sentinel,
    List<MapEntry<String, String>>? allAssetUrls,
    Object? appId = _sentinel,
    Object? apkSizeBytes = _sentinel,
    Object? isArchived = _sentinel,
    Object? newerReleasesFilteredOut = _sentinel,
  }) {
    return APKDetails(
      version ?? this.version,
      apkUrls ?? this.apkUrls,
      names ?? this.names,
      releaseDate: releaseDate == _sentinel
          ? this.releaseDate
          : releaseDate as DateTime?,
      changeLog: changeLog == _sentinel ? this.changeLog : changeLog as String?,
      releaseUrl: releaseUrl == _sentinel
          ? this.releaseUrl
          : releaseUrl as String?,
      allAssetUrls: allAssetUrls ?? this.allAssetUrls,
      appId: appId == _sentinel ? this.appId : appId as String?,
      apkSizeBytes: apkSizeBytes == _sentinel
          ? this.apkSizeBytes
          : apkSizeBytes as int?,
      isArchived: isArchived == _sentinel
          ? this.isArchived
          : isArchived as bool?,
      newerReleasesFilteredOut: newerReleasesFilteredOut == _sentinel
          ? this.newerReleasesFilteredOut
          : newerReleasesFilteredOut as int?,
    );
  }
}

/// Converts a list of [MapEntry] pairs into a 2D list of strings for JSON encoding.
List<List<String>> stringMapListTo2DList(
  List<MapEntry<String, String>> mapList,
) => mapList.map((e) => [e.key, e.value]).toList();

/// Converts a 2D list (decoded from JSON) back into a list of [MapEntry] pairs.
List<MapEntry<String, String>> assumed2DlistToStringMapList(
  List<dynamic> arr,
) => arr.map((e) => MapEntry(e[0] as String, e[1] as String)).toList();

// ------------------------------------------------------------------------
// App
// ------------------------------------------------------------------------

class App {
  final String id;
  final String url;
  final String author;
  final String name;
  final String? installedVersion;
  final String latestVersion;
  final List<MapEntry<String, String>> apkUrls;
  final List<MapEntry<String, String>> otherAssetUrls;
  final int preferredApkIndex;
  final Map<String, dynamic> additionalSettings;
  final DateTime? lastUpdateCheck;
  final bool pinned;
  final bool disabled;
  final List<String> categories;
  final DateTime? releaseDate;
  final String? changeLog;
  final String? releaseUrl;
  final String? overrideSource;
  final bool allowIdChange;
  final String? pendingRepoRenameUrl;
  final int? apkSizeBytes;
  final DateTime? latestVersionChangedAt;
  final int consecutiveFailedChecks;
  final bool? isArchived;
  final int? newerReleasesFilteredOut;
  final bool brokenCheckEnabled;
  final String? brokenCheckDismissedVersion;

  const App({
    required this.id,
    required this.url,
    required this.author,
    required this.name,
    this.installedVersion,
    required this.latestVersion,
    this.apkUrls = const [],
    this.otherAssetUrls = const [],
    required this.preferredApkIndex,
    required this.additionalSettings,
    this.lastUpdateCheck,
    this.pinned = false,
    this.disabled = false,
    this.categories = const [],
    this.releaseDate,
    this.changeLog,
    this.releaseUrl,
    this.overrideSource,
    this.allowIdChange = false,
    this.pendingRepoRenameUrl,
    this.apkSizeBytes,
    this.latestVersionChangedAt,
    this.consecutiveFailedChecks = 0,
    this.isArchived,
    this.newerReleasesFilteredOut,
    this.brokenCheckEnabled = true,
    this.brokenCheckDismissedVersion,
  });

  @override
  String toString() {
    return 'ID: $id URL: $url INSTALLED: $installedVersion LATEST: $latestVersion APK: $apkUrls PREFERREDAPK: $preferredApkIndex ADDITIONALSETTINGS: ${additionalSettings.toString()} LASTCHECK: ${lastUpdateCheck.toString()} PINNED $pinned';
  }

  bool get hasPendingRepoRename =>
      pendingRepoRenameUrl != null && pendingRepoRenameUrl!.isNotEmpty;

  String? get overrideName {
    final n = settings.getStringOrNull('appName');
    return n != null && n.trim().isNotEmpty ? n : null;
  }

  String get finalName {
    return overrideName ?? name;
  }

  String? get overrideAuthor {
    final a = settings.getStringOrNull('appAuthor');
    return a != null && a.trim().isNotEmpty ? a : null;
  }

  String get finalAuthor {
    return overrideAuthor ?? author;
  }

  /// Type-safe accessor for [additionalSettings].
  TypedSettings get settings => TypedSettings(additionalSettings);

  App copyWith({
    String? id,
    String? url,
    String? author,
    String? name,
    Object? installedVersion = _sentinel,
    String? latestVersion,
    List<MapEntry<String, String>>? apkUrls,
    List<MapEntry<String, String>>? otherAssetUrls,
    int? preferredApkIndex,
    Map<String, dynamic>? additionalSettings,
    Object? lastUpdateCheck = _sentinel,
    bool? pinned,
    bool? disabled,
    List<String>? categories,
    Object? releaseDate = _sentinel,
    Object? changeLog = _sentinel,
    Object? releaseUrl = _sentinel,
    Object? overrideSource = _sentinel,
    bool? allowIdChange,
    Object? pendingRepoRenameUrl = _sentinel,
    Object? apkSizeBytes = _sentinel,
    Object? latestVersionChangedAt = _sentinel,
    int? consecutiveFailedChecks,
    Object? isArchived = _sentinel,
    Object? newerReleasesFilteredOut = _sentinel,
    bool? brokenCheckEnabled,
    Object? brokenCheckDismissedVersion = _sentinel,
  }) {
    return App(
      id: id ?? this.id,
      url: url ?? this.url,
      author: author ?? this.author,
      name: name ?? this.name,
      installedVersion: installedVersion == _sentinel
          ? this.installedVersion
          : installedVersion as String?,
      latestVersion: latestVersion ?? this.latestVersion,
      apkUrls: apkUrls ?? List<MapEntry<String, String>>.from(this.apkUrls),
      otherAssetUrls:
          otherAssetUrls ??
          List<MapEntry<String, String>>.from(this.otherAssetUrls),
      preferredApkIndex: preferredApkIndex ?? this.preferredApkIndex,
      additionalSettings:
          additionalSettings ??
          Map<String, dynamic>.from(this.additionalSettings),
      lastUpdateCheck: lastUpdateCheck == _sentinel
          ? this.lastUpdateCheck
          : lastUpdateCheck as DateTime?,
      pinned: pinned ?? this.pinned,
      disabled: disabled ?? this.disabled,
      categories: categories ?? List<String>.from(this.categories),
      releaseDate: releaseDate == _sentinel
          ? this.releaseDate
          : releaseDate as DateTime?,
      changeLog: changeLog == _sentinel ? this.changeLog : changeLog as String?,
      releaseUrl: releaseUrl == _sentinel
          ? this.releaseUrl
          : releaseUrl as String?,
      overrideSource: overrideSource == _sentinel
          ? this.overrideSource
          : overrideSource as String?,
      allowIdChange: allowIdChange ?? this.allowIdChange,
      pendingRepoRenameUrl: pendingRepoRenameUrl == _sentinel
          ? this.pendingRepoRenameUrl
          : pendingRepoRenameUrl as String?,
      apkSizeBytes: apkSizeBytes == _sentinel
          ? this.apkSizeBytes
          : apkSizeBytes as int?,
      latestVersionChangedAt: latestVersionChangedAt == _sentinel
          ? this.latestVersionChangedAt
          : latestVersionChangedAt as DateTime?,
      consecutiveFailedChecks:
          consecutiveFailedChecks ?? this.consecutiveFailedChecks,
      isArchived: isArchived == _sentinel
          ? this.isArchived
          : isArchived as bool?,
      newerReleasesFilteredOut: newerReleasesFilteredOut == _sentinel
          ? this.newerReleasesFilteredOut
          : newerReleasesFilteredOut as int?,
      brokenCheckEnabled: brokenCheckEnabled ?? this.brokenCheckEnabled,
      brokenCheckDismissedVersion: brokenCheckDismissedVersion == _sentinel
          ? this.brokenCheckDismissedVersion
          : brokenCheckDismissedVersion as String?,
    );
  }

  /// Parses [json] in the current schema. Callers loading persisted app data
  /// should use `appFromStoredJson` (see `app_json_migration.dart`), which
  /// applies the legacy-schema migrations first.
  factory App.fromJson(Map<String, dynamic> json) {
    try {
      return App(
        id: json['id'] as String,
        url: json['url'] as String,
        author: json['author'] as String,
        name: json['name'] as String,
        installedVersion: json['installedVersion'] == null
            ? null
            : json['installedVersion'] as String,
        latestVersion: (json['latestVersion'] ?? tr('unknown')) as String,
        apkUrls: assumed2DlistToStringMapList(
          jsonDecode((json['apkUrls'] ?? '[["placeholder", "placeholder"]]')),
        ),
        preferredApkIndex: (json['preferredApkIndex'] ?? -1) as int,
        additionalSettings:
            jsonDecode(json['additionalSettings']) as Map<String, dynamic>,
        lastUpdateCheck: json['lastUpdateCheck'] == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(json['lastUpdateCheck']),
        pinned: json['pinned'] ?? false,
        disabled: json['disabled'] ?? false,
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
        changeLog: json['changeLog'] == null
            ? null
            : json['changeLog'] as String,
        releaseUrl: json['releaseUrl'] as String?,
        overrideSource: json['overrideSource'],
        allowIdChange: json['allowIdChange'] ?? false,
        otherAssetUrls: assumed2DlistToStringMapList(
          jsonDecode((json['otherAssetUrls'] ?? '[]')),
        ),
        pendingRepoRenameUrl: json['pendingRepoRenameUrl'] as String?,
        apkSizeBytes: json['apkSizeBytes'] as int?,
        latestVersionChangedAt: json['latestVersionChangedAt'] == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(
                json['latestVersionChangedAt'],
              ),
        consecutiveFailedChecks: json['consecutiveFailedChecks'] ?? 0,
        isArchived: json['isArchived'] as bool?,
        newerReleasesFilteredOut: json['newerReleasesFilteredOut'] as int?,
        brokenCheckEnabled: json['brokenCheckEnabled'] ?? true,
        brokenCheckDismissedVersion:
            json['brokenCheckDismissedVersion'] as String?,
      );
    } on TypeError catch (e) {
      AppLogger.error(
        e,
        stackTrace: e.stackTrace,
        message: 'Type mismatch in App.fromJson',
      );
      rethrow;
    }
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
    'disabled': disabled,
    'categories': categories,
    'releaseDate': releaseDate?.microsecondsSinceEpoch,
    'changeLog': changeLog,
    'releaseUrl': releaseUrl,
    'overrideSource': overrideSource,
    'allowIdChange': allowIdChange,
    'pendingRepoRenameUrl': pendingRepoRenameUrl,
    'apkSizeBytes': apkSizeBytes,
    'latestVersionChangedAt': latestVersionChangedAt?.microsecondsSinceEpoch,
    'consecutiveFailedChecks': consecutiveFailedChecks,
    'isArchived': isArchived,
    'newerReleasesFilteredOut': newerReleasesFilteredOut,
    'brokenCheckEnabled': brokenCheckEnabled,
    'brokenCheckDismissedVersion': brokenCheckDismissedVersion,
  };
}

/// Sentinel value used by [App.copyWith] to distinguish "not provided" from
/// an explicitly supplied `null` for nullable fields. Since [Object] uses
/// identity-based equality, a `const` sentinel guarantees it never collides
/// with any real value the caller could pass.
const _sentinel = Object();

/// Returns true if the app's ID is a temporary placeholder rather than a real
/// package name. Matches [generateTempID]'s sha256-hex prefix and legacy numeric
/// IDs; real package names contain a dot and never match.
bool isTempId(App app) {
  return RegExp(r'^[0-9]+$').hasMatch(app.id) ||
      RegExp(r'^[0-9a-f]{12}$').hasMatch(app.id);
}

/// Returns true when the app uses pseudo-versioning (track-only or disabled version detection).
bool isVersionPseudo(App app) =>
    app.settings.getBool('trackOnly') ||
    (app.installedVersion != null && !app.settings.getBool('versionDetection'));
