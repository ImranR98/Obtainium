import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/providers/source_provider.dart';

class Farsroid extends AppSource {
  Farsroid() {
    hosts = ['farsroid.com'];
    name = 'Farsroid';
  }

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
    [GeneratedFormHeader(label: tr('sectionReleaseSelection'))],
    [
      GeneratedFormSwitch(
        'useFirstApkOfVersion',
        label: tr('useFirstApkOfVersion'),
        value: true,
      ),
    ],
    [
      GeneratedFormSwitch(
        'releaseTitleAsVersion',
        label: tr('releaseTitleAsVersion'),
        value: false,
      ),
    ],
  ];

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    return standardizeUrlWithRegex(
      url,
      subdomainPrefix: r'([^\.]+\.)',
      pathPattern: r'/[^/]+',
    );
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final String appName = Uri.parse(standardUrl).pathSegments.last;

      final res = await sourceRequest(standardUrl, additionalSettings);
      ensureHttpSuccess(res);
      final html = parse(res.body);
      final dlinks = html.querySelectorAll('#secure-json [data-j]');
      if (dlinks.isEmpty) {
        throw NoReleasesError();
      }
      final base64 = dlinks.map((n) => n.attributes['data-j'] ?? '').join();
      var version = html.querySelector('h3.version-name')?.text.split(' ').last ?? '';

      if (base64.isEmpty || version.isEmpty) {
        throw NoVersionError();
      }

      List<dynamic>? farsroidJson;
      try {
        farsroidJson = jsonDecode(utf8.decode(base64Decode(base64))) as List<dynamic>?;
      } catch (e) {
        AppLogger.error(e, message: 'Failed to decode Farsroid JSON');
        throw NoAPKError();
      }
      final requestUrl = res.request?.url;
      if (requestUrl == null) throw NoAPKError();
      var apkLinks = farsroidJson?.map(
        (l) => l?['url'] as String? ?? '',
      ).where(
        (l) => l.isNotEmpty,
      ).map(
        (l) => ensureAbsoluteUrl(l, requestUrl),
      ).where(
        (l) => AppSource.isApkOrContainerFile(l),
      ).map(
        (l) => MapEntry(Uri.parse(l).pathSegments.last, l),
      ).toList() ?? <MapEntry<String, String>>[];

      apkLinks = filterApks(
        apkLinks,
        additionalSettings['apkFilterRegEx'],
        additionalSettings['invertAPKFilter'],
      );
      if (apkLinks.isEmpty) {
        throw NoAPKError();
      }
      if (additionalSettings['autoApkFilterByArch'] == true) {
        apkLinks = await filterApksByArch(apkLinks);
      }
      if (additionalSettings['useFirstApkOfVersion'] == true) {
        apkLinks = [apkLinks.firstWhere(
          (l) => l.key.toLowerCase().contains(version.toLowerCase()),
          orElse: () => apkLinks.first,
        )];
      }

      if (additionalSettings['releaseTitleAsVersion'] == true) {
        if (apkLinks.length != 1) {
          throw NoVersionError();
        }
        version = apkLinks.single.key;
      }

      return APKDetails(version, apkLinks, AppNames(name, appName));
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
