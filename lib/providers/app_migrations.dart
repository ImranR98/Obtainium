// Legacy JSON compatibility transformations applied when loading App data
// from disk. These convert old formats, remap keys, and apply schema migrations
// so stored JSON stays backward-compatible with the current App model.

import 'dart:convert';

import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/app_sources/fdroidrepo.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/providers/source_provider.dart';

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
