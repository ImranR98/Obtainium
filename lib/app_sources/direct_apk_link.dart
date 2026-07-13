import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

/// Tracks an APK at a direct URL (e.g. `https://example.com/app.apk`).
/// Delegates version detection and downloading to [HTML] with pseudo-versioning
/// (partial APK hash or ETag).
class DirectAPKLink extends AppSource {
  final HTML html = HTML();

  DirectAPKLink() {
    name = tr('directAPKLink');
    versionDetectionDisallowed = true;
    excludeCommonSettingKeys = [
      'versionExtractionRegEx',
      'matchGroupToUse',
      'versionDetection',
      'useVersionCodeAsOSVersion',
      'apkFilterRegEx',
      'autoApkFilterByArch',
    ];
  }

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
    ...html.additionalSourceAppSpecificSettingFormItems.where(
      (element) =>
          element.where((element) => element.key == 'requestHeader').isNotEmpty,
    ),
    [
      GeneratedFormDropdown(
        'defaultPseudoVersioningMethod',
        [
          MapEntry('partialAPKHash', tr('partialAPKHash')),
          const MapEntry('ETag', 'ETag'),
        ],
        label: tr('defaultPseudoVersioningMethod'),
        value: 'partialAPKHash',
      ),
    ],
  ];

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    if (!forSelection) {
      return Uri.tryParse(url)?.toString() ?? url;
    }
    final RegExp standardUrlRegExA = RegExp('.+\\.apk\$', caseSensitive: false);
    final match = standardUrlRegExA.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) {
    return html.getRequestHeaders(
      additionalSettings,
      url,
      forAPKDownload: forAPKDownload,
    );
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final additionalSettingsNew = getDefaultValuesFromFormItems(
        html.combinedAppSpecificSettingFormItems,
      );
      for (var s in additionalSettings.keys) {
        if (additionalSettingsNew.containsKey(s)) {
          additionalSettingsNew[s] = additionalSettings[s];
        }
      }
      additionalSettingsNew['directAPKLink'] = true;
      additionalSettingsNew['versionDetection'] = false;
      return html.getLatestAPKDetails(standardUrl, additionalSettingsNew);
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
