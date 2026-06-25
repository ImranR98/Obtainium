import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class DirectAPKLink extends AppSource {
  HTML html = HTML();

  DirectAPKLink() {
    name = tr('directAPKLink');
    additionalSourceAppSpecificSettingFormItems = [
      ...html.additionalSourceAppSpecificSettingFormItems.where(
        (element) => element
            .where((element) => element.key == 'requestHeader')
            .isNotEmpty,
      ),
      [
        GeneratedFormDropdown(
          'defaultPseudoVersioningMethod',
          [
            MapEntry('partialAPKHash', tr('partialAPKHash')),
            MapEntry('ETag', 'ETag'),
          ],
          label: tr('defaultPseudoVersioningMethod'),
          defaultValue: 'partialAPKHash',
        ),
      ],
    ];
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
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    if (!forSelection) {
      return url;
    }
    RegExp standardUrlRegExA = RegExp('.+\\.apk\$', caseSensitive: false);
    var match = standardUrlRegExA.firstMatch(url);
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
    var additionalSettingsNew = getDefaultValuesFromFormItems(
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
  }
}
