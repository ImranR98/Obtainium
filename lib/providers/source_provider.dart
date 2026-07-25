// Defines App sources and provides functions used to interact with them.
//
// AppSource is an abstract class with a concrete implementation for each source.
// Legacy JSON migration logic lives at the bottom of this file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
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
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/app_sources/githubstars.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';

class AppNames {
  String author;
  String name;

  AppNames(this.author, this.name);
}

// GitHub build attestation status values (stored in App.latestAttestationStatus).
const String githubAttestationStatusVerified = 'verified';
const String githubAttestationStatusUnsupported = 'unsupported';
const String githubAttestationStatusError = 'error';

const Set<String> validGitHubAttestationStatuses = {
  githubAttestationStatusVerified,
  githubAttestationStatusUnsupported,
  githubAttestationStatusError,
};

// Reproducible-build status values (stored in App.latestReproducibleStatus).
const String reproducibleBuildStatusVerified = 'verified';
const String reproducibleBuildStatusNotReproducible = 'not_reproducible';
const String reproducibleBuildStatusNoData = 'no_data';
const String reproducibleBuildStatusError = 'error';

const Set<String> validReproducibleBuildStatuses = {
  reproducibleBuildStatusVerified,
  reproducibleBuildStatusNotReproducible,
  reproducibleBuildStatusNoData,
  reproducibleBuildStatusError,
};

// Malware-scan (VirusTotal) status values (stored in App.latestMalwareScanStatus).
const String malwareScanStatusClean = 'clean';
const String malwareScanStatusFlagged = 'flagged';
const String malwareScanStatusError = 'error';

const Set<String> validMalwareScanStatuses = {
  malwareScanStatusClean,
  malwareScanStatusFlagged,
  malwareScanStatusError,
};

/// Coerces a stored JSON value into a valid malware-scan status, or null.
String? malwareScanStatusFromJsonValue(Object? value) {
  if (value is String && validMalwareScanStatuses.contains(value)) {
    return value;
  }
  return null;
}

/// Coerces a stored JSON value (string, or legacy bool) into a valid
/// attestation status, or null.
String? githubAttestationStatusFromJsonValue(Object? value) {
  if (value is String && validGitHubAttestationStatuses.contains(value)) {
    return value;
  }
  if (value is bool) {
    return value
        ? githubAttestationStatusVerified
        : githubAttestationStatusUnsupported;
  }
  return null;
}

/// Coerces a stored JSON value (string, or legacy bool) into a valid
/// reproducible-build status, or null.
String? reproducibleBuildStatusFromJsonValue(Object? value) {
  if (value is String && validReproducibleBuildStatuses.contains(value)) {
    return value;
  }
  if (value is bool) {
    return value
        ? reproducibleBuildStatusVerified
        : reproducibleBuildStatusNotReproducible;
  }
  return null;
}

/// Maps a tri-state reproducible bool (true/false/null) to a status string.
String reproducibleBuildStatusFromBool(bool? value) {
  if (value == true) {
    return reproducibleBuildStatusVerified;
  }
  if (value == false) {
    return reproducibleBuildStatusNotReproducible;
  }
  return reproducibleBuildStatusNoData;
}

/// Maps a reproducible-build status string back to a tri-state bool.
bool? reproducibleBuildBoolFromStatus(String? status) {
  if (status == reproducibleBuildStatusVerified) {
    return true;
  }
  if (status == reproducibleBuildStatusNotReproducible) {
    return false;
  }
  return null;
}

/// Whether [value] looks like an Android application id (e.g. `org.example.app`)
/// rather than a human-readable app name. Used to decide when a source's
/// readable name should replace a stale package-id-looking stored name.
bool looksLikeAndroidPackageId(String value) {
  return RegExp(
    r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$',
  ).hasMatch(value.trim());
}

// Version-string-source values (stored in additionalSettings['versionStringSource']).
const String versionStringSourceDefault = 'default';
const String versionStringSourceReleaseTitle = 'releaseTitle';
const String versionStringSourceAssetName = 'assetName';
const String versionStringSourceReleaseDate = 'releaseDate';
const String versionStringSourceReleaseCommitSha = 'releaseCommitSha';

const Set<String> validVersionStringSources = {
  versionStringSourceDefault,
  versionStringSourceReleaseTitle,
  versionStringSourceAssetName,
  versionStringSourceReleaseDate,
  versionStringSourceReleaseCommitSha,
};

/// Resolves the effective version-string source from [additionalSettings],
/// preferring an explicitly configured value and otherwise falling back to the
/// legacy per-method boolean flags.
String getVersionStringSource(
  Map<String, dynamic> additionalSettings, {
  bool preferConfiguredSource = true,
}) {
  final dynamic configuredSource = additionalSettings['versionStringSource'];
  if (configuredSource is String &&
      preferConfiguredSource &&
      validVersionStringSources.contains(configuredSource)) {
    return configuredSource;
  }
  if (additionalSettings['releaseDateAsVersion'] == true) {
    return versionStringSourceReleaseDate;
  }
  if (additionalSettings['releaseTitleAsVersion'] == true) {
    return versionStringSourceReleaseTitle;
  }
  if (additionalSettings['extractVersionFromAssetName'] == true) {
    return versionStringSourceAssetName;
  }
  if (additionalSettings['releaseCommitShaAsVersion'] == true) {
    return versionStringSourceReleaseCommitSha;
  }
  if (configuredSource is String &&
      validVersionStringSources.contains(configuredSource)) {
    return configuredSource;
  }
  return versionStringSourceDefault;
}

/// Normalises [additionalSettings] so that the string version-source key and
/// the legacy per-method boolean flags agree with each other.
void syncVersionStringSourceSettings(
  Map<String, dynamic> additionalSettings, {
  bool preferConfiguredSource = true,
}) {
  final String versionStringSource = getVersionStringSource(
    additionalSettings,
    preferConfiguredSource: preferConfiguredSource,
  );
  additionalSettings['versionStringSource'] = versionStringSource;
  additionalSettings['releaseDateAsVersion'] =
      versionStringSource == versionStringSourceReleaseDate;
  additionalSettings['releaseTitleAsVersion'] =
      versionStringSource == versionStringSourceReleaseTitle;
  additionalSettings['extractVersionFromAssetName'] =
      versionStringSource == versionStringSourceAssetName;
  additionalSettings['releaseCommitShaAsVersion'] =
      versionStringSource == versionStringSourceReleaseCommitSha;
}

const int _maxRawAssistStoredLines = 40;
const int _maxRawAssistStoredChars = 8000;

/// Newline-separated snapshot for RegEx assist dialogs (null if empty).
String? encodeRawAssistLines(Iterable<String> lines) {
  final List<String> out = <String>[];
  int chars = 0;
  for (final String line in lines) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (out.length >= _maxRawAssistStoredLines) {
      break;
    }
    if (chars + trimmed.length + 1 > _maxRawAssistStoredChars) {
      break;
    }
    if (!out.contains(trimmed)) {
      out.add(trimmed);
      chars += trimmed.length + 1;
    }
  }
  if (out.isEmpty) {
    return null;
  }
  return out.join('\n');
}

class APKDetails {
  String version;

  /// Source version code associated with the preferred APK, when available.
  final int? versionCode;
  List<MapEntry<String, String>> apkUrls;
  final AppNames names;
  final DateTime? releaseDate;
  String? changeLog;
  final List<MapEntry<String, String>> allAssetUrls;

  /// Optional absolute URL to a raster app icon from the source (for non-installed apps).
  String? iconUrl;

  /// Release names/titles seen before title filtering (RegEx assist).
  List<String> rawReleaseTitleCandidates;

  /// Size of the preferred APK in bytes, if known at update-check time (e.g. GitHub releases).
  int? apkSizeBytes;
  bool? isReproducible;
  String? reproducibleStatus;
  String? attestationStatus;

  APKDetails(
    this.version,
    this.apkUrls,
    this.names, {
    this.versionCode,
    this.releaseDate,
    this.changeLog,
    this.allAssetUrls = const [],
    this.iconUrl,
    this.rawReleaseTitleCandidates = const [],
    this.apkSizeBytes,
    this.isReproducible,
    this.reproducibleStatus,
    this.attestationStatus,
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

/// Delegates to [HttpService.ensureAbsoluteUrl].
String ensureAbsoluteUrl(String ambiguousUrl, Uri referenceAbsoluteUrl) =>
    HttpService().ensureAbsoluteUrl(ambiguousUrl, referenceAbsoluteUrl);

/// Tolerant parser for stored date fields (lastUpdateCheck / releaseDate).
/// Accepts an int (microsecondsSinceEpoch), an ISO-8601 string, or a numeric
/// string. Returns null for null/unparseable. A raw
/// `DateTime.fromMicrosecondsSinceEpoch(json[...])` throws a TypeError on a
/// String value, which aborts the whole import — this restores fork main's
/// tolerance for string-encoded dates in legacy/third-party backups.
DateTime? dateTimeFromJsonValue(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return DateTime.fromMicrosecondsSinceEpoch(value);
  }
  if (value is String) {
    final DateTime? isoDateTime = DateTime.tryParse(value);
    if (isoDateTime != null) {
      return isoDateTime;
    }
    final int? microsecondsSinceEpoch = int.tryParse(value);
    if (microsecondsSinceEpoch != null) {
      return DateTime.fromMicrosecondsSinceEpoch(microsecondsSinceEpoch);
    }
  }
  return null;
}

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
  final List<String> categories;
  final DateTime? releaseDate;
  final String? changeLog;
  final String? overrideSource;
  final bool allowIdChange;
  final String? pendingRepoRenameUrl;

  /// Absolute URL to a raster app icon from the source (for non-installed apps).
  final String? iconUrl;

  /// Size of the preferred APK in bytes, if known at update-check time.
  final int? apkSizeBytes;

  /// Version string from the source before extraction / release-date/title
  /// replacement. Used for helpers and RegEx assist; omitted from JSON when null.
  final String? rawLatestVersionFromSource;

  /// APK row keys (e.g. filenames) before [filterApks], newline-separated. RegEx assist.
  final String? rawApkNamesFromSource;

  /// Release title candidates before title filter, newline-separated. RegEx assist.
  final String? rawReleaseTitlesFromSource;

  final bool? latestIsReproducible;
  final String? latestReproducibleStatus;

  /// Version code whose exact APK verification produced the stored status.
  final int? latestReproducibleVersionCode;
  final String? latestAttestationStatus;
  final String? latestMalwareScanStatus;
  final String? latestMalwareScanDetail;
  final String? latestMalwareScanReportUrl;

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
    this.categories = const [],
    this.releaseDate,
    this.changeLog,
    this.overrideSource,
    this.allowIdChange = false,
    this.pendingRepoRenameUrl,
    this.iconUrl,
    this.apkSizeBytes,
    this.rawLatestVersionFromSource,
    this.rawApkNamesFromSource,
    this.rawReleaseTitlesFromSource,
    this.latestIsReproducible,
    this.latestReproducibleStatus,
    this.latestReproducibleVersionCode,
    this.latestAttestationStatus,
    this.latestMalwareScanStatus,
    this.latestMalwareScanDetail,
    this.latestMalwareScanReportUrl,
  });

  @override
  String toString() {
    return 'ID: $id URL: $url INSTALLED: $installedVersion LATEST: $latestVersion APK: $apkUrls PREFERREDAPK: $preferredApkIndex ADDITIONALSETTINGS: ${additionalSettings.toString()} LASTCHECK: ${lastUpdateCheck.toString()} PINNED $pinned';
  }

  bool get hasPendingRepoRename =>
      pendingRepoRenameUrl != null && pendingRepoRenameUrl!.isNotEmpty;

  String? get overrideName {
    final override = settings.getStringOrNull('appName')?.trim();
    if (override == null || override.isEmpty) {
      return null;
    }
    final String sourceName = name.trim();
    // Ignore an override that merely restates the package id (either the exact
    // app id, or anything shaped like a package id) when the source already
    // provides a readable name.
    if (override == id && sourceName.isNotEmpty && sourceName != id) {
      return null;
    }
    if (looksLikeAndroidPackageId(override) &&
        sourceName.isNotEmpty &&
        sourceName != override) {
      return null;
    }
    return override;
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
    List<String>? categories,
    Object? releaseDate = _sentinel,
    Object? changeLog = _sentinel,
    Object? overrideSource = _sentinel,
    bool? allowIdChange,
    Object? pendingRepoRenameUrl = _sentinel,
    Object? iconUrl = _sentinel,
    Object? apkSizeBytes = _sentinel,
    Object? rawLatestVersionFromSource = _sentinel,
    Object? rawApkNamesFromSource = _sentinel,
    Object? rawReleaseTitlesFromSource = _sentinel,
    Object? latestIsReproducible = _sentinel,
    Object? latestReproducibleStatus = _sentinel,
    Object? latestReproducibleVersionCode = _sentinel,
    Object? latestAttestationStatus = _sentinel,
    Object? latestMalwareScanStatus = _sentinel,
    Object? latestMalwareScanDetail = _sentinel,
    Object? latestMalwareScanReportUrl = _sentinel,
  }) {
    return App(
      id: id ?? this.id,
      url: url ?? this.url,
      author: author ?? this.author,
      name: name ?? this.name,
      installedVersion: installedVersion == _sentinel
          ? this.installedVersion
          : installedVersion?.toString(),
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
      categories: categories ?? List<String>.from(this.categories),
      releaseDate: releaseDate == _sentinel
          ? this.releaseDate
          : releaseDate as DateTime?,
      changeLog: changeLog == _sentinel
          ? this.changeLog
          : changeLog?.toString(),
      overrideSource: overrideSource == _sentinel
          ? this.overrideSource
          : overrideSource?.toString(),
      allowIdChange: allowIdChange ?? this.allowIdChange,
      pendingRepoRenameUrl: pendingRepoRenameUrl == _sentinel
          ? this.pendingRepoRenameUrl
          : pendingRepoRenameUrl?.toString(),
      iconUrl: iconUrl == _sentinel ? this.iconUrl : iconUrl?.toString(),
      apkSizeBytes: apkSizeBytes == _sentinel
          ? this.apkSizeBytes
          : apkSizeBytes as int?,
      rawLatestVersionFromSource: rawLatestVersionFromSource == _sentinel
          ? this.rawLatestVersionFromSource
          : rawLatestVersionFromSource?.toString(),
      rawApkNamesFromSource: rawApkNamesFromSource == _sentinel
          ? this.rawApkNamesFromSource
          : rawApkNamesFromSource?.toString(),
      rawReleaseTitlesFromSource: rawReleaseTitlesFromSource == _sentinel
          ? this.rawReleaseTitlesFromSource
          : rawReleaseTitlesFromSource?.toString(),
      latestIsReproducible: latestIsReproducible == _sentinel
          ? this.latestIsReproducible
          : latestIsReproducible as bool?,
      latestReproducibleStatus: latestReproducibleStatus == _sentinel
          ? this.latestReproducibleStatus
          : latestReproducibleStatus?.toString(),
      latestReproducibleVersionCode: latestReproducibleVersionCode == _sentinel
          ? this.latestReproducibleVersionCode
          : latestReproducibleVersionCode as int?,
      latestAttestationStatus: latestAttestationStatus == _sentinel
          ? this.latestAttestationStatus
          : latestAttestationStatus?.toString(),
      latestMalwareScanStatus: latestMalwareScanStatus == _sentinel
          ? this.latestMalwareScanStatus
          : latestMalwareScanStatus?.toString(),
      latestMalwareScanDetail: latestMalwareScanDetail == _sentinel
          ? this.latestMalwareScanDetail
          : latestMalwareScanDetail?.toString(),
      latestMalwareScanReportUrl: latestMalwareScanReportUrl == _sentinel
          ? this.latestMalwareScanReportUrl
          : latestMalwareScanReportUrl?.toString(),
    );
  }

  /// Returns a deep copy of this app. Since [App] is immutable and [copyWith]
  /// already clones its mutable collections, a zero-argument [copyWith] is a
  /// faithful deep copy.
  App deepCopy() => copyWith();

  factory App.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> originalJson = Map.from(json);
    try {
      json = appJSONCompatibilityModifiers(Map.from(json));
    } catch (e) {
      // Fall back to the unmigrated JSON so the app still loads rather than
      // being lost (e.g. when its saved URL no longer matches any source).
      json = originalJson;
      unawaited(
        LogsProvider().add(
          'Error running JSON compat modifiers (using original JSON): ${e.toString()}',
          level: LogLevel.warning,
        ),
      );
    }
    try {
      return App(
        id: json['id']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        author: json['author']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        installedVersion: json['installedVersion']?.toString(),
        latestVersion: json['latestVersion']?.toString() ?? tr('unknown'),
        apkUrls: assumed2DlistToStringMapList(
          jsonDecode((json['apkUrls'] ?? '[["placeholder", "placeholder"]]')),
        ),
        preferredApkIndex: (json['preferredApkIndex'] ?? -1) as int,
        additionalSettings:
            jsonDecode(json['additionalSettings']) as Map<String, dynamic>,
        lastUpdateCheck: dateTimeFromJsonValue(json['lastUpdateCheck']),
        pinned: json['pinned'] ?? false,
        categories: json['categories'] != null
            ? (json['categories'] as List<dynamic>)
                  .map((e) => e.toString())
                  .toList()
            : json['category'] != null
            ? [json['category'].toString()]
            : [],
        releaseDate: dateTimeFromJsonValue(json['releaseDate']),
        changeLog: json['changeLog']?.toString(),
        overrideSource: json['overrideSource']?.toString(),
        allowIdChange: json['allowIdChange'] ?? false,
        otherAssetUrls: assumed2DlistToStringMapList(
          jsonDecode((json['otherAssetUrls'] ?? '[]')),
        ),
        pendingRepoRenameUrl: json['pendingRepoRenameUrl']?.toString(),
        iconUrl: json['iconUrl']?.toString(),
        apkSizeBytes: json['apkSizeBytes'] as int?,
        rawLatestVersionFromSource: json['rawLatestVersionFromSource']
            ?.toString(),
        rawApkNamesFromSource: json['rawApkNamesFromSource']?.toString(),
        rawReleaseTitlesFromSource: json['rawReleaseTitlesFromSource']
            ?.toString(),
        latestIsReproducible: json['latestIsReproducible'] as bool?,
        latestReproducibleStatus: reproducibleBuildStatusFromJsonValue(
          json['latestReproducibleStatus'] ?? json['latestIsReproducible'],
        ),
        latestReproducibleVersionCode:
            json['latestReproducibleVersionCode'] is num
            ? (json['latestReproducibleVersionCode'] as num).toInt()
            : int.tryParse(
                json['latestReproducibleVersionCode']?.toString() ?? '',
              ),
        latestAttestationStatus: githubAttestationStatusFromJsonValue(
          json['latestAttestationStatus'] ?? json['latestIsAttested'],
        ),
        latestMalwareScanStatus: malwareScanStatusFromJsonValue(
          json['latestMalwareScanStatus'],
        ),
        latestMalwareScanDetail: json['latestMalwareScanDetail']?.toString(),
        latestMalwareScanReportUrl: json['latestMalwareScanReportUrl']
            ?.toString(),
      );
    } on TypeError catch (e) {
      unawaited(
        LogsProvider().add(
          'Type mismatch in App.fromJson: ${e.toString()}',
          level: LogLevel.error,
        ),
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
    'categories': categories,
    'releaseDate': releaseDate?.microsecondsSinceEpoch,
    'changeLog': changeLog,
    'overrideSource': overrideSource,
    'allowIdChange': allowIdChange,
    'pendingRepoRenameUrl': pendingRepoRenameUrl,
    if (iconUrl != null) 'iconUrl': iconUrl,
    if (apkSizeBytes != null) 'apkSizeBytes': apkSizeBytes,
    if (rawLatestVersionFromSource != null)
      'rawLatestVersionFromSource': rawLatestVersionFromSource,
    if (rawApkNamesFromSource != null)
      'rawApkNamesFromSource': rawApkNamesFromSource,
    if (rawReleaseTitlesFromSource != null)
      'rawReleaseTitlesFromSource': rawReleaseTitlesFromSource,
    if (latestIsReproducible != null)
      'latestIsReproducible': latestIsReproducible,
    if (latestReproducibleStatus != null)
      'latestReproducibleStatus': latestReproducibleStatus,
    if (latestReproducibleVersionCode != null)
      'latestReproducibleVersionCode': latestReproducibleVersionCode,
    if (latestAttestationStatus != null)
      'latestAttestationStatus': latestAttestationStatus,
    if (latestMalwareScanStatus != null)
      'latestMalwareScanStatus': latestMalwareScanStatus,
    if (latestMalwareScanDetail != null)
      'latestMalwareScanDetail': latestMalwareScanDetail,
    if (latestMalwareScanReportUrl != null)
      'latestMalwareScanReportUrl': latestMalwareScanReportUrl,
  };
}

/// Sentinel value used by [App.copyWith] to distinguish "not provided" from
/// an explicitly supplied `null` for nullable fields. Since [Object] uses
/// identity-based equality, a `const` sentinel guarantees it never collides
/// with any real value the caller could pass.
const _sentinel = Object();

/// Ensures the URL is well-formed and starts with HTTPS.
String preStandardizeUrl(String url) {
  final firstDotIndex = url.indexOf('.');
  if (!(firstDotIndex >= 0 && firstDotIndex != url.length - 1) &&
      !url.contains('[')) {
    throw UnsupportedURLError();
  }
  if (!url.toLowerCase().startsWith('http://') &&
      !url.toLowerCase().startsWith('https://')) {
    url = 'https://$url';
  }
  final uri = Uri.tryParse(url);
  final trailingSlash =
      ((uri?.path.endsWith('/') ?? false) ||
          ((uri?.path.isEmpty ?? false) && url.endsWith('/'))) &&
      (uri?.queryParameters.isEmpty ?? false);

  // Only normalize duplicate slashes in the scheme/host/path portion; leave the
  // query string and fragment untouched so any slashes they contain (e.g. a URL
  // passed as a query parameter) aren't mangled.
  var splitIndex = url.length;
  final queryStart = url.indexOf('?');
  if (queryStart >= 0 && queryStart < splitIndex) {
    splitIndex = queryStart;
  }
  final fragmentStart = url.indexOf('#');
  if (fragmentStart >= 0 && fragmentStart < splitIndex) {
    splitIndex = fragmentStart;
  }
  var mainPart = url.substring(0, splitIndex);
  final rest = url.substring(splitIndex);
  mainPart = mainPart
      .split('/')
      .where((e) => e.isNotEmpty)
      .join('/')
      .replaceFirst(':/', '://');
  url = mainPart + (trailingSlash ? '/' : '') + rest;
  return url;
}

/// Delegates to [ApkFilterService.getApkUrlsFromUrls].
List<MapEntry<String, String>> getApkUrlsFromUrls(List<String> urls) =>
    ApkFilterService().getApkUrlsFromUrls(urls);

/// Delegates to [ApkFilterService.filterApksByArch].
Future<List<MapEntry<String, String>>> filterApksByArch(
  List<MapEntry<String, String>> apkUrls,
) async {
  final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
  return ApkFilterService().filterApksByArch(apkUrls, abis);
}

/// Builds a regex alternation pattern from a list of hostname strings, escaping dots.
String getSourceRegex(List<String> hosts) {
  return '(${hosts.join('|').replaceAll('.', '\\.')})';
}

/// Delegates to [HttpService.createHttpClient].
HttpClient createHttpClient(bool insecure) =>
    HttpService().createHttpClient(insecure);

/// Delegates to [HttpService.sourceRequestStreamResponse].
Future<MapEntry<Uri, MapEntry<HttpClient, HttpClientResponse>>>
sourceRequestStreamResponse(
  String method,
  String url,
  Map<String, String>? requestHeaders,
  Map<String, dynamic> additionalSettings, {
  bool followRedirects = true,
  Object? postBody,
}) => HttpService().sourceRequestStreamResponse(
  method,
  url,
  requestHeaders,
  additionalSettings,
  followRedirects: followRedirects,
  postBody: postBody,
);

/// Delegates to [HttpService.httpClientResponseStreamToFinalResponse].
Future<http.Response> httpClientResponseStreamToFinalResponse(
  HttpClient httpClient,
  String method,
  String url,
  HttpClientResponse response,
) => HttpService().httpClientResponseStreamToFinalResponse(
  httpClient,
  method,
  url,
  response,
);

abstract class AppSource {
  List<String> hosts = [];
  bool hostChanged = false;
  bool hostIdenticalDespiteAnyChange = false;
  late String name;
  bool enforceTrackOnly = false;
  bool changeLogIfAnyIsMarkDown = true;
  bool changeLogPageIsStandardUrl = false;
  bool appIdInferIsOptional = false;
  bool inferAppIdFromUrlPath = false;
  bool allowSubDomains = false;
  bool naiveStandardVersionDetection = false;
  bool allowOverride = true;
  bool neverAutoSelect = false;
  bool showReleaseDateAsVersionToggle = false;
  bool showReleaseTitleAsVersionToggle = false;
  bool showExtractVersionFromAssetNameToggle = false;
  bool showReleaseCommitShaAsVersionToggle = false;
  bool versionDetectionDisallowed = false;
  bool suppressStandardVersionExtraction = false;
  List<String> excludeCommonSettingKeys = [];
  bool urlsAlwaysHaveExtension = false;
  bool allowIncludeZips = false;
  bool allowIncludeTarballs = false;
  bool regionalStore = false;
  String get sourceIdentifier => runtimeType.toString();

  /// Transient per-check context: the app as it was known before this update
  /// check, set by [SourceProvider.getApp] right before [getLatestAPKDetails].
  /// Lets a source skip an expensive *secondary* verification network round-trip
  /// (e.g. F-Droid reproducible-build metadata) when the raw upstream version is
  /// unchanged since the last check, reusing the cached result instead. Not
  /// persisted; safe to read because each check gets its own source instance.
  App? previouslyCheckedApp;

  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    return null;
  }

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

  App postProcessApp(App app) {
    return app;
  }

  Future<Map<String, dynamic>> buildMergedSettings(
    Map<String, dynamic> additionalSettings,
    SettingsProvider settingsProvider,
  ) async {
    return {
      ...additionalSettings,
      ...(await getSourceConfigValues(additionalSettings, settingsProvider)),
    };
  }

  Future<http.Response> sourceRequest(
    String url,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    final sp = SettingsProvider();
    await sp.initializeSettings();
    final additionalSettingsPlusSourceConfig = await buildMergedSettings(
      additionalSettings,
      sp,
    );
    url = await generalReqPrefetchModifier(
      url,
      additionalSettingsPlusSourceConfig,
    );
    final method = postBody == null ? 'GET' : 'POST';
    final requestHeaders = await getRequestHeaders(
      additionalSettingsPlusSourceConfig,
      url,
    );
    final streamedResponseUrlWithResponseAndClient =
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

  void runOnAddAppInputChange(String inputUrl) {}

  /// Delegates to [ApkFilterService.apkContainerExtensions].
  static List<String> get apkContainerExtensions =>
      ApkFilterService.apkContainerExtensions;

  /// Delegates to [ApkFilterService.archiveExtensions].
  static List<String> get archiveExtensions =>
      ApkFilterService.archiveExtensions;

  /// Delegates to [ApkFilterService.tarballExtensions].
  static List<String> get tarballExtensions =>
      ApkFilterService.tarballExtensions;

  /// Delegates to [ApkFilterService.isApkOrContainerFile].
  static bool isApkOrContainerFile(
    String name, {
    bool includeArchives = false,
    bool includeTarballs = false,
  }) => ApkFilterService.isApkOrContainerFile(
    name,
    includeArchives: includeArchives,
    includeTarballs: includeTarballs,
  );

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
    if (match == null) throw InvalidURLError(name)..url = url;
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
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [];

  static List<GeneratedFormItem> get fallbackToOlderReleasesFormItem => [
    GeneratedFormSwitch(
      'fallbackToOlderReleases',
      label: tr('fallbackToOlderReleases'),
      value: true,
    ),
  ];

  /// Some additional data may be needed for Apps regardless of Source.
  ///
  /// ORDER + SECTION HEADERS ARE DELIBERATE. The [GeneratedFormSectionHeader]
  /// rows split the Additional-Options page into separate section cards (the
  /// renderer groups every header + its following rows into one card when
  /// `wrapFormSectionsInCards` is set). Do NOT flatten this back into one list
  /// or drop the headers — that collapses the page into a single giant card
  /// (matches the fork's `main`). Name / author / notes are intentionally NOT
  /// here: they are edited via the app detail page's "Edit app info" dialog, not
  /// this form.
  List<List<GeneratedFormItem>> get _commonAppSettingFormItems => [
    [
      GeneratedFormSectionHeader(
        '__formSectionTracking',
        label: tr('additionalOptionsSectionTracking'),
      ),
    ],
    [
      GeneratedFormSwitch(
        'trackOnly',
        label: tr('trackOnly'),
        labelTooltip: tr('trackOnlyAppDescription'),
      ),
    ],
    [
      GeneratedFormSwitch(
        'onDemandOnly',
        label: tr('onDemandOnly'),
        value: false,
        labelTooltip: tr('onDemandOnlyDescription'),
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
    [
      GeneratedFormSectionHeader(
        '__formSectionVersion',
        label: tr('additionalOptionsSectionVersion'),
      ),
    ],
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
      // Version detection is a THREE-STATE dropdown, not a bool switch. Every
      // reader (isVersionPseudo, app.dart's isVersionDetectionStandard,
      // apps_provider_updates/lifecycle, additional_options_page) keys off the
      // string values 'auto'/'standard'/'pseudo'/'versionCode'. A bool switch
      // here silently corrupts the value (GeneratedFormSwitch.ensureType coerces
      // it to a bool on every deserialize) and breaks install/update detection —
      // do NOT revert to a switch. 'versionCode' subsumes the old separate
      // useVersionCodeAsOSVersion switch (kept in sync as a derived bool).
      GeneratedFormDropdown(
        'versionDetection',
        [
          MapEntry('auto', tr('versionDetectionModeAuto')),
          MapEntry('standard', tr('versionDetectionModeStandard')),
          MapEntry('pseudo', tr('versionDetectionModePseudo')),
          MapEntry('versionCode', tr('versionDetectionModeVersionCode')),
        ],
        label: tr('versionDetection'),
        value: 'auto',
      ),
    ],
    [
      GeneratedFormSectionHeader(
        '__formSectionApk',
        label: tr('additionalOptionsSectionApk'),
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
        value: false,
      ),
    ],
    [
      GeneratedFormSwitch(
        'autoApkFilterByArch',
        label: tr('autoApkFilterByArch'),
        value: true,
      ),
    ],
    [
      GeneratedFormSectionHeader(
        '__formSectionAdvanced',
        label: tr('additionalOptionsSectionAdvanced'),
      ),
    ],
    [
      GeneratedFormSwitch(
        'shizukuPretendToBeGooglePlay',
        label: tr('shizukuPretendToBeGooglePlay'),
        value: false,
      ),
    ],
    [
      GeneratedFormSwitch(
        'allowInsecure',
        label: tr('allowInsecure'),
        value: false,
      ),
    ],
    [
      GeneratedFormSwitch(
        'refreshBeforeDownload',
        label: tr('refreshBeforeDownload'),
      ),
    ],
  ];

  /// The choices for the unified "Use as version string" (`versionStringSource`)
  /// dropdown. 'Default' is always offered; each alternate pseudo-version source
  /// is added only when the source opted in via its show*Toggle flag. A single
  /// dropdown here replaces the old scattered per-source boolean switches
  /// (releaseTitleAsVersion / releaseDateAsVersion / …) — parity with fork main.
  List<MapEntry<String, String>> get versionStringSourceOptions {
    final List<MapEntry<String, String>> options = [
      MapEntry(versionStringSourceDefault, tr('versionStringSourceDefault')),
    ];
    if (showReleaseTitleAsVersionToggle) {
      options.add(
        MapEntry(
          versionStringSourceReleaseTitle,
          tr('versionStringSourceReleaseTitle'),
        ),
      );
    }
    if (showExtractVersionFromAssetNameToggle) {
      options.add(
        MapEntry(
          versionStringSourceAssetName,
          tr('versionStringSourceAssetName'),
        ),
      );
    }
    if (showReleaseDateAsVersionToggle) {
      options.add(
        MapEntry(
          versionStringSourceReleaseDate,
          tr('versionStringSourceReleaseDate'),
        ),
      );
    }
    if (showReleaseCommitShaAsVersionToggle) {
      options.add(
        MapEntry(
          versionStringSourceReleaseCommitSha,
          tr('versionStringSourceReleaseCommitSha'),
        ),
      );
    }
    return options;
  }

  /// Combines per-source form items with the common app-setting form items,
  /// interspersing conditional items (zip/tarball options, version toggles) and
  /// filtering out excluded keys. Cloned so that callers cannot mutate the
  /// shared source-owned form items. Rebuilt on every access so that labels
  /// pick up the current locale via tr().
  List<List<GeneratedFormItem>> get combinedAppSpecificSettingFormItems {
    var agnosticItems = cloneFormItems(_commonAppSettingFormItems);

    // Insert the unified versionStringSource dropdown at the top of the Version
    // section (right after its header) when the source offers any alternate
    // version-string source. Mirrors fork main; do NOT revert to per-flag
    // switches (the backend's single source of truth is the versionStringSource
    // string, kept in sync with the legacy booleans by syncVersionStringSourceSettings).
    final List<MapEntry<String, String>> versionSourceOptions =
        versionStringSourceOptions;
    if (versionSourceOptions.length > 1 &&
        !agnosticItems.any(
          (row) => row.any((item) => item.key == 'versionStringSource'),
        )) {
      final int versionSectionHeaderIndex = agnosticItems.indexWhere(
        (row) => row.length == 1 && row.first.key == '__formSectionVersion',
      );
      agnosticItems.insert(
        versionSectionHeaderIndex >= 0 ? versionSectionHeaderIndex + 1 : 0,
        [
          GeneratedFormDropdown(
            'versionStringSource',
            versionSourceOptions,
            label: tr('versionStringSource'),
            value: versionStringSourceDefault,
          ),
        ],
      );
    }

    agnosticItems = agnosticItems
        .map(
          (e) => e
              .where((ee) => !excludeCommonSettingKeys.contains(ee.key))
              .toList(),
        )
        .where((e) => e.isNotEmpty)
        .toList();

    final moreConditionalItems = <List<GeneratedFormItem>>[];
    if (allowIncludeZips) {
      moreConditionalItems.addAll([
        [
          GeneratedFormSwitch(
            'includeZips',
            label: tr('includeZips'),
            value: false,
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
            value: false,
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
      for (final item in agnosticItems.expand((row) => row)) {
        // versionDetection is now a dropdown; guard the cast so this can't crash
        // (mirrors fork main, which only disables switch-typed items here).
        if ((item.key == 'versionDetection' ||
                item.key == 'useVersionCodeAsOSVersion') &&
            item is GeneratedFormSwitch) {
          item.disabled = true;
          item.value = false;
        }
      }
    }

    final combined = [
      // Clone so callers (e.g. the add-app form pre-filling default values)
      // can't mutate the source-owned items. Sources are now cached/shared, so
      // an in-place edit here would otherwise leak across apps.
      ...cloneFormItems(additionalSourceAppSpecificSettingFormItems),
      ...agnosticItems,
      ...moreConditionalItems,
    ];

    final List<List<GeneratedFormItem>> pruned = [];
    List<GeneratedFormItem>? pendingHeaderRow;

    for (final row in combined) {
      final bool isHeader =
          row.length == 1 && row.first is GeneratedFormSectionHeader;
      if (isHeader) {
        pendingHeaderRow = row;
      } else {
        if (pendingHeaderRow != null) {
          pruned.add(pendingHeaderRow);
          pendingHeaderRow = null;
        }
        pruned.add(row);
      }
    }

    return pruned;
  }

  bool get hasAppSpecificSettings =>
      combinedAppSpecificSettingFormItems.isNotEmpty;

  /// Flattened, read-only view of [combinedAppSpecificSettingFormItems],
  /// used by callers that only need to enumerate keys without cloning.
  List<GeneratedFormItem> get flatCombinedFormItemsReadOnly =>
      combinedAppSpecificSettingFormItems.expand((row) => row).toList();

  /// Source-level additional settings (not specific to Apps) backed by [SettingsProvider].
  /// If the source has been overridden, per-app additional settings take precedence.
  List<GeneratedFormItem> get sourceConfigSettingFormItems => [];
  Future<Map<String, String>> getSourceConfigValues(
    Map<String, dynamic> additionalSettings,
    SettingsProvider settingsProvider,
  ) async {
    final Map<String, String> results = {};
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
    return changeLogPageIsStandardUrl ? standardUrl : null;
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
  List<GeneratedFormItem> get searchQuerySettingFormItems => [];
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) {
    throw NotImplementedError();
  }

  static String stripLastPathSegment(String url) {
    final uri = Uri.parse(url);
    return uri
        .replace(
          pathSegments: uri.pathSegments.sublist(
            0,
            uri.pathSegments.length - 1,
          ),
        )
        .toString();
  }

  static Future<String?> tryInferAppIdFromLastPathSegment(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    return Uri.parse(
      standardUrl,
    ).pathSegments.where((s) => s.isNotEmpty).lastOrNull;
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

/// Delegates to [HttpService.getHttpError].
ObtainiumError getObtainiumHttpError(http.Response res) =>
    HttpService().getHttpError(res);

abstract class MassAppUrlSource {
  String get name;
  List<String> get requiredArgs;
  Future<Map<String, List<String>>> getUrlsWithDescriptions(List<String> args);
}

/// Delegates to [VersionService.regExValidator].
String? regExValidator(String? value) => VersionService().regExValidator(value);

/// Returns true if the app's ID is a temporary placeholder rather than a real
/// package name. Matches [generateTempID]'s sha256-hex prefix and legacy numeric
/// IDs; real package names contain a dot and never match.
bool isTempId(App app) {
  return RegExp(r'^[0-9]+$').hasMatch(app.id) ||
      RegExp(r'^[0-9a-f]{12}$').hasMatch(app.id);
}

/// Delegates to [VersionService.replaceMatchGroupsInString].
String? replaceMatchGroupsInString(
  RegExpMatch match,
  String matchGroupString,
) => VersionService().replaceMatchGroupsInString(match, matchGroupString);

/// Delegates to [VersionService.extractVersion].
String? extractVersion(
  String? versionExtractionRegEx,
  String? matchGroupString,
  String stringToCheck,
) => VersionService().extractVersion(
  versionExtractionRegEx,
  matchGroupString,
  stringToCheck,
);

/// Delegates to [ApkFilterService.filterApks].
List<MapEntry<String, String>> filterApks(
  List<MapEntry<String, String>> apkUrls,
  String? apkFilterRegEx,
  bool? invert,
) => ApkFilterService().filterApks(apkUrls, apkFilterRegEx, invert);

/// Returns true when the app uses pseudo-versioning (track-only or disabled version detection).
bool isVersionPseudo(App app) =>
    app.settings.getBool('trackOnly') ||
    (app.installedVersion != null &&
        // versionDetection is a string enum, NOT a bool — getBool() would return
        // false for 'auto'/'standard'/'versionCode' and mark every app pseudo.
        (app.additionalSettings['versionDetection'] == 'pseudo' ||
            app.additionalSettings['versionDetection'] == false));

class SourceProvider {
  static final SourceProvider _instance = SourceProvider._();
  factory SourceProvider() => _instance;
  SourceProvider._();

  static final Map<String, RegExp> _sourceRegexCache = {};
  static final Map<String, int> _sourceMatchIndexCache = {};

  // Single source of truth for source construction. Matching uses cached,
  // never-mutated templates and [getSource] constructs only the matched source.
  //
  // ORDER IS DELIBERATE — host-based sources are listed alphabetically by their
  // display name (the [name] field, comparing case-insensitively and ignoring
  // punctuation, so "Farsroid" precedes "F-Droid official"). This order is what
  // the source-picker lists render (filter-by-source sheet, "Supported sources"
  // dialog, override-source dropdown), so it must stay alphabetical — do NOT
  // revert to upstream's arbitrary definition order. The two hostless catch-alls
  // stay pinned at the end: source matching walks this list in order and these
  // match by URL *shape* rather than host, so they must be tried only after
  // every host-based source — DirectAPKLink (only .apk URLs) before HTML (the
  // universal fallback), so HTML is ALWAYS last.
  static final List<AppSource Function()> _sourceFactories = [
    () => Apk4Free(),
    () => APKCombo(),
    () => APKMirror(),
    () => APKPure(),
    () => Aptoide(),
    () => CoolApk(),
    () => Farsroid(),
    () => FDroid(), // "F-Droid official"
    () => FDroidRepo(), // "F-Droid third-party repo"
    () => Codeberg(), // "Forgejo (Codeberg)"
    () => GitHub(),
    () => GitLab(),
    () => HuaweiAppGallery(), // "Huawei AppGallery"
    () => ItchIO(), // "itch.io"
    () => IzzyOnDroid(),
    () => Jenkins(),
    () => LiteAPKs(),
    () => NeutronCode(),
    () => RockMods(),
    () => RuStore(),
    () => SourceForge(),
    () => SourceHut(),
    () => TelegramApp(), // "Telegram <app>"
    () => Tencent(), // "Tencent App Store"
    () => Uptodown(),
    () => VivoAppStore(), // "vivo App Store (CN)"
    () => DirectAPKLink(), // "Direct APK link"
    () => HTML(), // Must be the last entry - HTML is the catch-all fallback.
  ];

  static List<AppSource>? _sourceTemplatesCache;
  static List<AppSource> get _sourceTemplates => _sourceTemplatesCache ??=
      _sourceFactories.map((factory) => factory()).toList();

  /// Fresh source instances for callers that may mutate the returned objects.
  List<AppSource> get sources =>
      _sourceFactories.map((factory) => factory()).toList();

  /// Add mass URL source classes here so they are available via the service.
  List<MassAppUrlSource> massUrlSources = [GitHubStars()];

  /// Read-only view of the cached source set for callers that only read source
  /// properties (name, hosts, form items) and never mutate them — e.g. the
  /// settings source-specific section and the filter-by-source sheet. Callers
  /// MUST NOT mutate the returned instances; use [sources] for a fresh copy.
  List<AppSource> get sourceTemplates => _sourceTemplates;

  /// Read-only source resolution mirroring [getSource]; use on hot paths that
  /// only need the source's type or its (type-level) flags/form items — e.g.
  /// JSON compatibility migration and version-detection checks. Callers MUST
  /// NOT mutate the returned instance.
  AppSource getSourceTemplate(String url, {String? overrideSource}) {
    if (overrideSource != null) {
      // Override resolution rewrites the source host for this app. Construct
      // only that matched adapter so the shared template remains immutable.
      return getSource(url, overrideSource: overrideSource);
    }
    return _sourceTemplates[_matchSourceIndexForStandardizedUrl(
      preStandardizeUrl(url),
    )];
  }

  // `naiveStandardVersionDetection` depends only on the resolved source (a
  // function of host + overrideSource), so cache it per host to avoid a
  // getSource() per app on the install-status reconcile hot path.
  static final Map<String, bool> _naiveStandardVersionDetectionCache = {};
  bool naiveStandardVersionDetectionForUrl(
    String url, {
    String? overrideSource,
  }) {
    final String host = Uri.tryParse(url)?.host ?? url;
    final String key = '${overrideSource ?? ''} $host';
    return _naiveStandardVersionDetectionCache[key] ??= getSourceTemplate(
      url,
      overrideSource: overrideSource,
    ).naiveStandardVersionDetection;
  }

  AppSource getSource(String url, {String? overrideSource}) {
    url = preStandardizeUrl(url);
    final int sourceIndex = _matchSourceIndexForStandardizedUrl(
      url,
      overrideSource: overrideSource,
    );
    final AppSource res = _sourceFactories[sourceIndex]();
    if (overrideSource != null) {
      final originalHosts = res.hosts;
      final newHost = Uri.parse(url).host;
      res.hosts = [newHost];
      res.hostChanged = true;
      if (originalHosts.contains(newHost)) {
        res.hostIdenticalDespiteAnyChange = true;
      }
    }
    return res;
  }

  int _matchSourceIndexForStandardizedUrl(
    String url, {
    String? overrideSource,
  }) {
    final String matchCacheKey = '${overrideSource ?? ''}\n$url';
    final int? cachedSourceIndex = _sourceMatchIndexCache[matchCacheKey];
    if (cachedSourceIndex != null) {
      return cachedSourceIndex;
    }
    final List<AppSource> templates = _sourceTemplates;
    if (overrideSource != null) {
      final int sourceIndex = templates.indexWhere(
        (source) => source.sourceIdentifier == overrideSource,
      );
      if (sourceIndex < 0) {
        throw UnsupportedURLError()..url = url;
      }
      _sourceMatchIndexCache[matchCacheKey] = sourceIndex;
      return sourceIndex;
    }
    for (int sourceIndex = 0; sourceIndex < templates.length; sourceIndex++) {
      final AppSource source = templates[sourceIndex];
      if (source.hosts.isEmpty) continue;
      try {
        final String cacheKey =
            '${source.allowSubDomains}:${source.hosts.join(',')}';
        final RegExp regex = _sourceRegexCache[cacheKey] ??= RegExp(
          '^${source.allowSubDomains ? '([^\\.]+\\.)*' : '(www\\.)?'}(${getSourceRegex(source.hosts)})\$',
        );
        if (regex.hasMatch(Uri.parse(url).host)) {
          _sourceMatchIndexCache[matchCacheKey] = sourceIndex;
          return sourceIndex;
        }
      } catch (_) {
        // Ignore and try the next source.
      }
    }
    for (int sourceIndex = 0; sourceIndex < templates.length; sourceIndex++) {
      final AppSource source = templates[sourceIndex];
      if (source.hosts.isNotEmpty || source.neverAutoSelect) continue;
      try {
        source.sourceSpecificStandardizeURL(url, forSelection: true);
        _sourceMatchIndexCache[matchCacheKey] = sourceIndex;
        return sourceIndex;
      } catch (_) {
        // Ignore and try the next source.
      }
    }
    throw UnsupportedURLError()..url = url;
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
  ) => sha256
      .convert(utf8.encode(standardUrl + additionalSettings.toString()))
      .toString()
      .substring(0, 12);

  Future<String> _resolveAppId(
    AppSource source,
    App? currentApp,
    Map<String, dynamic> additionalSettings,
    bool trackOnly,
    String standardUrl,
    bool inferAppIdIfOptional,
  ) async {
    if (currentApp?.id != null) return currentApp!.id;
    final explicitId = additionalSettings['appId'] as String?;
    if (explicitId != null) return explicitId;
    if (!trackOnly &&
        (!source.appIdInferIsOptional ||
            (source.appIdInferIsOptional && inferAppIdIfOptional))) {
      final inferred = await source.tryInferringAppId(
        standardUrl,
        additionalSettings: additionalSettings,
      );
      if (inferred != null) return inferred;
    }
    return generateTempID(standardUrl, additionalSettings);
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
    additionalSettings = Map<String, dynamic>.from(additionalSettings);
    if (trackOnlyOverride || source.enforceTrackOnly) {
      additionalSettings['trackOnly'] = true;
    }
    final trackOnly = additionalSettings['trackOnly'] == true;
    // Populate the derived per-source version-string booleans (releaseTitle/
    // assetName/releaseDate/commitSha) from the unified versionStringSource
    // dropdown BEFORE the source reads them — otherwise a freshly-added app's
    // selection is silently ignored on its first check (it only self-heals
    // after save + reload). Parity with fork main.
    syncVersionStringSourceSettings(additionalSettings);
    final String standardUrl;
    try {
      standardUrl = source.standardizeUrl(url);
    } on ObtainiumError catch (e) {
      throw e..withUrlContext(url);
    }
    // Hand the source the previously-known app so it can skip redundant
    // secondary verification round-trips when the upstream release is unchanged.
    source.previouslyCheckedApp = currentApp;
    final APKDetails apk;
    try {
      apk = await source.getLatestAPKDetails(standardUrl, additionalSettings);
    } on ObtainiumError catch (e) {
      throw e..withUrlContext(standardUrl);
    }

    // Capture raw snapshots before version extraction / release-date/title
    // replacement and APK filtering mutate them (used by the RegEx assist).
    final String rawLatestVersionFromSource = apk.version;
    final String? rawApkNamesFromSource = encodeRawAssistLines(
      apk.apkUrls.map((MapEntry<String, String> entry) => entry.key),
    );
    final String? rawReleaseTitlesFromSource = encodeRawAssistLines(
      apk.rawReleaseTitleCandidates,
    );

    if (!source.suppressStandardVersionExtraction) {
      final String? extractedVersion = extractVersion(
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
      // ISO-8601 (parity with fork main): a readable, stable string. Upstream's
      // microsecondsSinceEpoch renders as an opaque integer and, on upgrade,
      // recomputes to a different value → a one-time spurious "update".
      apk.version = apk.releaseDate!.toUtc().toIso8601String();
    }
    apk.apkUrls = filterApks(
      apk.apkUrls,
      additionalSettings['apkFilterRegEx'],
      additionalSettings['invertAPKFilter'],
    );
    if (apk.apkUrls.isEmpty && !trackOnly) {
      throw NoAPKError()..url = standardUrl;
    }
    if (additionalSettings['autoApkFilterByArch'] == true) {
      apk.apkUrls = await filterApksByArch(apk.apkUrls);
      if (apk.apkUrls.isEmpty && !trackOnly) {
        throw NoAPKError()..url = standardUrl;
      }
    }
    final int preferredApkIndex;
    if (apk.apkUrls.isEmpty) {
      preferredApkIndex = 0;
    } else if (currentApp == null) {
      preferredApkIndex = apk.apkUrls.length - 1;
    } else {
      preferredApkIndex = currentApp.preferredApkIndex.clamp(
        0,
        apk.apkUrls.length - 1,
      );
    }
    final String sourceName = apk.names.name.trim();
    // Replace the stored name with the source's readable name when the stored
    // name is missing, is exactly the app id, or merely looks like a package id
    // (e.g. 'org.example.app') while the source offers a real display name.
    var name = currentApp != null ? currentApp.name.trim() : '';
    if (name.isEmpty ||
        name == currentApp?.id ||
        (looksLikeAndroidPackageId(name) &&
            sourceName.isNotEmpty &&
            sourceName != name)) {
      name = sourceName.isNotEmpty ? sourceName : name;
    }
    // Reuse the previous check's verification/size/icon when the resolved
    // version is unchanged, so a skipped secondary round-trip doesn't clear them.
    final bool sameVersionAsPrevious =
        currentApp != null && currentApp.latestVersion == apk.version;
    final String? resolvedReproducibleStatus =
        apk.reproducibleStatus ??
        (apk.isReproducible != null
            ? reproducibleBuildStatusFromBool(apk.isReproducible)
            : sameVersionAsPrevious
            ? currentApp.latestReproducibleStatus
            : null);
    final App finalApp = App(
      id: await _resolveAppId(
        source,
        currentApp,
        additionalSettings,
        trackOnly,
        standardUrl,
        inferAppIdIfOptional,
      ),
      url: standardUrl,
      author: apk.names.author,
      name: name,
      installedVersion: currentApp?.installedVersion,
      latestVersion: apk.version,
      apkUrls: apk.apkUrls,
      preferredApkIndex: preferredApkIndex,
      additionalSettings: additionalSettings,
      lastUpdateCheck: DateTime.now(),
      pinned: currentApp?.pinned ?? false,
      categories: currentApp?.categories ?? const [],
      releaseDate: apk.releaseDate,
      changeLog: apk.changeLog,
      overrideSource: sourceIsOverriden
          ? source.sourceIdentifier
          : currentApp?.overrideSource,
      allowIdChange:
          currentApp?.allowIdChange ??
          trackOnly || (source.appIdInferIsOptional && inferAppIdIfOptional),
      otherAssetUrls: apk.allAssetUrls
          .where((a) => apk.apkUrls.indexWhere((p) => a.key == p.key) < 0)
          .toList(),
      iconUrl: apk.iconUrl ?? currentApp?.iconUrl,
      apkSizeBytes:
          apk.apkSizeBytes ??
          (sameVersionAsPrevious ? currentApp.apkSizeBytes : null),
      rawLatestVersionFromSource: rawLatestVersionFromSource,
      rawApkNamesFromSource: rawApkNamesFromSource,
      rawReleaseTitlesFromSource: rawReleaseTitlesFromSource,
      latestIsReproducible: reproducibleBuildBoolFromStatus(
        resolvedReproducibleStatus,
      ),
      latestReproducibleStatus: resolvedReproducibleStatus,
      latestReproducibleVersionCode: apk.versionCode,
      latestAttestationStatus:
          apk.attestationStatus ??
          (sameVersionAsPrevious ? currentApp.latestAttestationStatus : null),
    );
    return source.postProcessApp(finalApp);
  }

  // Returns errors in [results, errors] instead of throwing them
  Future<List<dynamic>> getAppsByURLNaive(
    List<String> urls, {
    Set<String> alreadyAddedUrls = const {},
    AppSource? sourceOverride,
  }) async {
    final List<App> apps = [];
    final Map<String, dynamic> errors = {};
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
            final source = sourceOverride ?? getSource(url);
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

/// Type-safe wrapper around [App.additionalSettings] that eliminates
/// manual casts and null checks when reading per-source configuration values.
///
/// Usage:
/// ```dart
/// if (app.settings.getBool('trackOnly')) { ... }
/// String? regex = app.settings.getStringOrNull('apkFilterRegEx');
/// ```
class TypedSettings {
  final Map<String, dynamic> _raw;

  const TypedSettings(Map<String, dynamic> raw) : _raw = raw;

  bool getBool(String key, {bool defaultValue = false}) {
    final val = _raw[key];
    if (val == null) return defaultValue;
    if (val is bool) return val;
    if (val is String) return val == 'true';
    return defaultValue;
  }

  int? getIntOrNull(String key) {
    final val = _raw[key];
    if (val is int) return val;
    if (val is String) return int.tryParse(val);
    return null;
  }

  String? getStringOrNull(String key) {
    final val = _raw[key];
    if (val == null) return null;
    if (val is String) return val.isNotEmpty ? val : null;
    return val.toString();
  }

  String getString(String key, {String defaultValue = ''}) =>
      getStringOrNull(key) ?? defaultValue;

  @override
  String toString() => _raw.toString();
}

class HttpService {
  static const int maxRedirects = 10;

  HttpClient createHttpClient(bool insecure) {
    final client = HttpClient();
    if (insecure) {
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
    }
    return client;
  }

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
    while (redirectCount < maxRedirects) {
      httpClient = createHttpClient(
        additionalSettings['allowInsecure'] == true,
      );
      final request = await httpClient.openUrl(method, currentUrl);
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

  ObtainiumError getHttpError(http.Response res) {
    if (res.statusCode == 404) return NoReleasesError();

    final reasonLower = res.reasonPhrase?.toLowerCase() ?? '';
    final bodySample = res.body.length > 1000
        ? res.body.substring(0, 1000).toLowerCase()
        : res.body.toLowerCase();
    final isRateLimit =
        res.statusCode == 429 ||
        res.statusCode == 403 ||
        reasonLower.contains('rate limit') ||
        reasonLower.contains('too many requests') ||
        bodySample.contains('rate limit') ||
        bodySample.contains('too many requests');

    if (isRateLimit) {
      final retryAfter = res.headers['retry-after'];
      final secs = retryAfter != null ? int.tryParse(retryAfter) : null;
      if (secs != null) return RateLimitError((secs / 60).ceil());

      final resetHeader = res.headers['x-ratelimit-reset'];
      if (resetHeader != null) {
        final parsed = int.tryParse(resetHeader);
        if (parsed != null) {
          final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final remainingMinutes = ((parsed - nowSeconds) / 60).ceil().clamp(
            1,
            9999,
          );
          return RateLimitError(remainingMinutes);
        }
      }
      return RateLimitError(30); // Default to a conservative 30 minutes
    }
    return ObtainiumError(
      (res.reasonPhrase != null && res.reasonPhrase!.isNotEmpty)
          ? res.reasonPhrase!
          : tr('errorWithHttpStatusCode', args: [res.statusCode.toString()]),
      code: 'HTTP_ERROR',
    );
  }
}

class VersionService {
  static const defaultMatchGroup = '0';

  static final List<String> standardVersionRegExStrings =
      _generateStandardVersionRegExStrings();

  static final List<MapEntry<String, RegExp>> strictStandardVersionRegExes =
      standardVersionRegExStrings
          .map((p) => MapEntry(p, RegExp('^$p\$')))
          .toList();

  static final List<MapEntry<String, RegExp>> looseStandardVersionRegExes =
      standardVersionRegExStrings.map((p) => MapEntry(p, RegExp(p))).toList();

  static List<String> _generateStandardVersionRegExStrings() {
    final basics = [
      '[0-9]+',
      '[0-9]+\\.[0-9]+',
      '[0-9]+\\.[0-9]+\\.[0-9]+',
      '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+',
    ];
    final preSuffixes = ['-', '\\+'];
    final suffixes = [
      'alpha',
      'beta',
      'rc',
      'pre',
      'dev',
      'snapshot',
      'nightly',
      'ose',
      '[0-9]+',
    ];
    final finals = ['\\+[0-9]+', '[0-9]+'];
    final List<String> results = [];
    for (var b in basics) {
      results.add(b);
      for (var p in preSuffixes) {
        for (var s in suffixes) {
          results.add('$b$s');
          results.add('$b$p$s');
          for (var f in finals) {
            results.add('$b$s$f');
            results.add('$b$p$s$f');
          }
        }
      }
    }
    return results.toSet().toList();
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

  /// Replaces `$N` references in a string with the corresponding regex match groups.
  String? replaceMatchGroupsInString(
    RegExpMatch match,
    String matchGroupString,
  ) {
    if (RegExp('^\\d+\$').hasMatch(matchGroupString)) {
      matchGroupString = '\$$matchGroupString';
    }
    final numberRegex = RegExp(r'\$\d+');
    final numbers = numberRegex.allMatches(matchGroupString);
    if (numbers.isEmpty) {
      return null;
    }
    var outputString = matchGroupString;
    for (final numberMatch in numbers) {
      final number = numberMatch.group(0)!;
      final int matchGroupIndex = int.parse(number.substring(1));
      // Guard against a replacement referencing a capture group that doesn't
      // exist — return null (→ caller raises NoVersionError) instead of letting
      // match.group() throw a RangeError (parity with fork main).
      if (matchGroupIndex > match.groupCount) {
        return null;
      }
      final matchGroup = match.group(matchGroupIndex) ?? '';
      final isEscaped = outputString.contains('\\$number');
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
      final match = RegExp(versionExtractionRegEx!).allMatches(version);
      if (match.isEmpty) {
        throw NoVersionError();
      }
      matchGroupString = matchGroupString?.trim() ?? '';
      if (matchGroupString.isEmpty) {
        matchGroupString = defaultMatchGroup;
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

  static final Map<String, Set<String>> _strictFormatCache = {};
  static final Map<String, Set<String>> _looseFormatCache = {};
  static const int _maxFormatCacheSize = 4096;

  Set<String> findStandardFormatsForVersion(String version, bool strict) {
    final cache = strict ? _strictFormatCache : _looseFormatCache;
    final cached = cache[version];
    if (cached != null) return cached;

    final Set<String> results = {};
    final patterns = strict
        ? strictStandardVersionRegExes
        : looseStandardVersionRegExes;
    for (var entry in patterns) {
      if (entry.value.hasMatch(version)) {
        results.add(entry.key);
      }
    }
    if (cache.length >= _maxFormatCacheSize) cache.clear();
    cache[version] = results;
    return results;
  }

  bool doStringsMatchUnderRegEx(String pattern, String value1, String value2) {
    final r = RegExp(pattern);
    final m1 = r.firstMatch(value1);
    final m2 = r.firstMatch(value2);
    return m1 != null && m2 != null
        ? value1.substring(m1.start, m1.end) ==
              value2.substring(m2.start, m2.end)
        : false;
  }
}

class ApkFilterService {
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

  List<MapEntry<String, String>> getApkUrlsFromUrls(List<String> urls) =>
      urls.map((e) {
        final segments = e.split('/').where((el) => el.trim().isNotEmpty);
        final apkSegs = segments.where((s) => isApkOrContainerFile(s));
        return MapEntry(apkSegs.isNotEmpty ? apkSegs.last : segments.last, e);
      }).toList();

  List<MapEntry<String, String>> filterApks(
    List<MapEntry<String, String>> apkUrls,
    String? apkFilterRegEx,
    bool? invert,
  ) {
    if (apkFilterRegEx?.isNotEmpty == true) {
      final reg = RegExp(apkFilterRegEx!);
      apkUrls = apkUrls.where((element) {
        final hasMatch = reg.hasMatch(element.key);
        return invert == true ? !hasMatch : hasMatch;
      }).toList();
    }
    return apkUrls;
  }

  Future<List<MapEntry<String, String>>> filterApksByArch(
    List<MapEntry<String, String>> apkUrls,
    List<String> abis, {
    bool preferSplits = true,
  }) async {
    if (apkUrls.length > 1) {
      for (var abi in abis) {
        final urls2 = apkUrls
            .where(
              (element) => RegExp(
                '.*$abi.*',
                caseSensitive: false,
              ).hasMatch(element.key),
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
}

Map<String, dynamic> _migrateAppToHTML(
  Map<String, dynamic> json,
  Map<String, dynamic> additionalSettings, {
  required String newUrl,
  Map<String, dynamic>? overrides,
}) {
  json['url'] = newUrl;
  final replacement = getDefaultValuesFromFormItems(
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
  final List<String> temp = List<String>.from(decoded);
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
      json['noVersionDetection'] == 'true' ||
      json['noVersionDetection'] == true ||
      // Ancient additionalData-format apps: track-only implies no version
      // detection (parity with fork main).
      json['trackOnly'] == true;
}

/// Converts legacy booleans `noVersionDetection` / `releaseDateAsVersion`
/// to the current `versionDetection` string dropdown and back.
void _migrateVersionDetectionFormat(Map<String, dynamic> additionalSettings) {
  // Legacy bool-style flags → intermediate dropdown keys.
  if (additionalSettings['noVersionDetection'] == true) {
    additionalSettings['versionDetection'] = 'noVersionDetection';
    if (additionalSettings['releaseDateAsVersion'] == true) {
      additionalSettings['versionDetection'] = 'releaseDateAsVersion';
    }
    additionalSettings.remove('noVersionDetection');
    additionalSettings.remove('releaseDateAsVersion');
  }
  // Old dropdown/boolean values → the three-state string enum that every reader
  // now expects ('auto'/'standard'/'pseudo'/'versionCode'). This MUST land on a
  // string, never a bool — a bool value makes every installed app read as
  // pseudo-versioned (see isVersionPseudo) and breaks update detection.
  if (additionalSettings['versionDetection'] == 'standardVersionDetection') {
    additionalSettings['versionDetection'] = 'auto';
  } else if (additionalSettings['versionDetection'] == 'noVersionDetection') {
    additionalSettings['versionDetection'] = 'pseudo';
  } else if (additionalSettings['versionDetection'] == 'releaseDateAsVersion') {
    additionalSettings['versionDetection'] = 'pseudo';
    additionalSettings['releaseDateAsVersion'] = true;
  } else if (additionalSettings['versionDetection'] == true) {
    additionalSettings['versionDetection'] = 'auto';
  } else if (additionalSettings['versionDetection'] == false) {
    additionalSettings['versionDetection'] = 'pseudo';
  }
  // 'versionCode' is a dropdown option; keep the derived useVersionCodeAsOSVersion
  // bool in sync (mirrors fork main).
  if (additionalSettings['versionDetection'] == 'versionCode' ||
      additionalSettings['useVersionCodeAsOSVersion'] == true) {
    additionalSettings['versionDetection'] = 'versionCode';
    additionalSettings['useVersionCodeAsOSVersion'] = true;
  } else {
    additionalSettings['useVersionCodeAsOSVersion'] = false;
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
  final apkUrlJson = jsonDecode(json['apkUrls']);
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

  final legacySteamSourceApps = ['steam', 'steam-chat-app'];
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
  final overrideSourceWasUndefined = !json.keys.contains('overrideSource');
  if ((json['url'] as String).startsWith('https://cloudflare.f-droid.org')) {
    json['overrideSource'] = FDroid().sourceIdentifier;
  } else if (overrideSourceWasUndefined) {
    final RegExpMatch? match = RegExp(
      '^https?://.+/fdroid/([^/]+(/|\\?)|[^/]+\$)',
    ).firstMatch(json['url'] as String);
    if (match != null) {
      json['overrideSource'] = FDroidRepo().sourceIdentifier;
    }
  }
}

/// Applies any legacy JSON transformations so the stored [json] matches the
/// current schema. All transformations are idempotent, so they run on every
/// load.
Map<String, dynamic> appJSONCompatibilityModifiers(Map<String, dynamic> json) {
  final source = SourceProvider().getSource(
    json['url'],
    overrideSource: json['overrideSource'],
  );
  final formItems = source.flatCombinedFormItemsReadOnly;
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
  // Populate the versionStringSource string from any legacy per-method boolean
  // flags so the unified dropdown pre-fills correctly (parity with fork main,
  // which syncs here during deserialization). Prefer an already-configured
  // string value when the app has one.
  syncVersionStringSourceSettings(
    additionalSettings,
    preferConfiguredSource: originalAdditionalSettings.containsKey(
      'versionStringSource',
    ),
  );
  _migratePseudoVersioningMethod(
    originalAdditionalSettings,
    additionalSettings,
  );
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

  if (source is HTML) {
    additionalSettings = _migrateHtmlSpecificMigrations(
      json,
      originalAdditionalSettings,
      additionalSettings,
    );
  }

  json['additionalSettings'] = jsonEncode(additionalSettings);
  _migrateFdroidOverrides(json);
  return json;
}
